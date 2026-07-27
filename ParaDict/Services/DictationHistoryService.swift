import Foundation
import SQLite3

actor DictationHistoryService {
    static let shared = DictationHistoryService()

    struct Entry: Identifiable, Equatable, Sendable {
        let id: Int64
        let createdAt: Date
        let mode: String
        let targetApp: String?
        let transcription: String
        let enhancedText: String?
        let finalText: String

        var modeDisplayName: String {
            switch mode {
            case DictationMode.local.rawValue:
                return "Local"
            case DictationMode.enhanced.rawValue:
                return "Enhanced"
            case DictationMode.reply.rawValue:
                return "Reply"
            case DictationMode.command.rawValue:
                return "Command"
            default:
                return mode.capitalized
            }
        }
    }

    enum RetentionLimit: Int, CaseIterable, Identifiable, Sendable {
        case all = 0
        case fifty = 50
        case oneHundred = 100
        case fiveHundred = 500
        case oneThousand = 1_000
        case fiveThousand = 5_000

        var id: Int { rawValue }

        var displayName: String {
            rawValue == 0 ? "All dictations" : "Last \(rawValue.formatted())"
        }
    }

    enum HistoryError: LocalizedError {
        case database(message: String)
        case invalidLegacyHistory

        var errorDescription: String? {
            switch self {
            case .database(let message):
                return "History database error: \(message)"
            case .invalidLegacyHistory:
                return "The existing transcription history could not be read."
            }
        }
    }

    private static let legacyImportKey = "legacy_csv_imported_v1"

    private let databaseURL: URL
    private let legacyCSVURL: URL?
    private var database: OpaquePointer?
    private var isPrepared = false

    init(
        databaseURL: URL? = nil,
        legacyCSVURL: URL? = nil,
        importsLegacyCSV: Bool = true
    ) {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let appDirectory = appSupport.appendingPathComponent("ParaDict", isDirectory: true)

        self.databaseURL = databaseURL
            ?? appDirectory.appendingPathComponent("dictation_history.sqlite3")
        self.legacyCSVURL = importsLegacyCSV
            ? (legacyCSVURL
                ?? appDirectory.appendingPathComponent("transcription_history.csv"))
            : nil
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func save(
        transcription: String,
        enhancedText: String?,
        mode: DictationMode,
        targetApp: String?,
        createdAt: Date = Date(),
        retentionLimit: Int
    ) async throws {
        try prepareIfNeeded()

        let sql = """
            INSERT INTO dictation_history (
                created_at,
                mode,
                target_app,
                transcription,
                enhanced_text,
                final_text
            ) VALUES (?, ?, ?, ?, ?, ?)
            """
        let statement = try prepareStatement(sql)
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, createdAt.timeIntervalSince1970)
        bind(mode.rawValue, to: statement, at: 2)
        bind(targetApp, to: statement, at: 3)
        bind(transcription, to: statement, at: 4)
        bind(enhancedText, to: statement, at: 5)
        bind(enhancedText ?? transcription, to: statement, at: 6)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw databaseError()
        }

        try prune(to: retentionLimit)

        await MainActor.run {
            NotificationCenter.default.post(name: .dictationHistoryDidChange, object: nil)
        }
    }

    func fetchEntries(retentionLimit: Int) throws -> [Entry] {
        try prepareIfNeeded()
        try prune(to: retentionLimit)

        let sql = """
            SELECT
                id,
                created_at,
                mode,
                target_app,
                transcription,
                enhanced_text,
                final_text
            FROM dictation_history
            ORDER BY created_at DESC, id DESC
            """
        let statement = try prepareStatement(sql)
        defer { sqlite3_finalize(statement) }

        var entries: [Entry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            entries.append(
                Entry(
                    id: sqlite3_column_int64(statement, 0),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                    mode: requiredText(from: statement, at: 2),
                    targetApp: optionalText(from: statement, at: 3),
                    transcription: requiredText(from: statement, at: 4),
                    enhancedText: optionalText(from: statement, at: 5),
                    finalText: requiredText(from: statement, at: 6)
                )
            )
        }

        guard sqlite3_errcode(database) == SQLITE_OK
                || sqlite3_errcode(database) == SQLITE_DONE else {
            throw databaseError()
        }

        return entries
    }

    func applyRetentionLimit(_ retentionLimit: Int) throws {
        try prepareIfNeeded()
        try prune(to: retentionLimit)
    }

    private func prepareIfNeeded() throws {
        guard !isPrepared else { return }

        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if database == nil {
            var connection: OpaquePointer?
            let result = sqlite3_open_v2(
                databaseURL.path,
                &connection,
                SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
                nil
            )

            guard result == SQLITE_OK, let connection else {
                let message = connection.map { String(cString: sqlite3_errmsg($0)) }
                    ?? "Unable to open \(databaseURL.lastPathComponent)"
                if let connection {
                    sqlite3_close(connection)
                }
                throw HistoryError.database(message: message)
            }

            database = connection
            sqlite3_busy_timeout(connection, 5_000)
        }

        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA foreign_keys = ON")
        try execute(
            """
            CREATE TABLE IF NOT EXISTS dictation_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                created_at REAL NOT NULL,
                mode TEXT NOT NULL,
                target_app TEXT,
                transcription TEXT NOT NULL,
                enhanced_text TEXT,
                final_text TEXT NOT NULL
            )
            """
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS dictation_history_created_at
            ON dictation_history (created_at DESC, id DESC)
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS history_metadata (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            )
            """
        )
        try importLegacyCSVIfNeeded()
        isPrepared = true
    }

    private func importLegacyCSVIfNeeded() throws {
        guard metadataValue(for: Self.legacyImportKey) == nil else { return }
        guard let legacyCSVURL,
              FileManager.default.fileExists(atPath: legacyCSVURL.path) else {
            try setMetadataValue("missing", for: Self.legacyImportKey)
            return
        }

        let data = try Data(contentsOf: legacyCSVURL)
        let rows = Self.parseCSV(data)
        guard let header = rows.first else {
            try setMetadataValue("empty", for: Self.legacyImportKey)
            return
        }

        let columns = Dictionary(
            uniqueKeysWithValues: header.enumerated().map { ($0.element, $0.offset) }
        )
        guard let timestampColumn = columns["timestamp"],
              let eventTypeColumn = columns["event_type"],
              let modeColumn = columns["mode"],
              let targetAppColumn = columns["target_app"],
              let transcriptionColumn = columns["transcription"],
              let llmResponseColumn = columns["llm_response"],
              let finalOutputColumn = columns["final_output"] else {
            throw HistoryError.invalidLegacyHistory
        }

        let insertSQL = """
            INSERT INTO dictation_history (
                created_at,
                mode,
                target_app,
                transcription,
                enhanced_text,
                final_text
            ) VALUES (?, ?, ?, ?, ?, ?)
            """
        let statement = try prepareStatement(insertSQL)
        defer { sqlite3_finalize(statement) }

        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            var importedCount = 0

            for row in rows.dropFirst() {
                let requiredColumn = max(
                    timestampColumn,
                    eventTypeColumn,
                    modeColumn,
                    targetAppColumn,
                    transcriptionColumn,
                    llmResponseColumn,
                    finalOutputColumn
                )
                guard row.indices.contains(requiredColumn) else { continue }

                let eventType = row[eventTypeColumn]
                guard eventType == "local_transcription"
                        || eventType == "enhanced_transcription" else {
                    continue
                }

                let transcription = row[transcriptionColumn]
                let llmResponse = row[llmResponseColumn]
                let finalText = row[finalOutputColumn].isEmpty
                    ? (llmResponse.isEmpty ? transcription : llmResponse)
                    : row[finalOutputColumn]
                guard !finalText.isEmpty else { continue }

                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                sqlite3_bind_double(
                    statement,
                    1,
                    Self.parseLegacyDate(row[timestampColumn]).timeIntervalSince1970
                )
                bind(row[modeColumn], to: statement, at: 2)
                let targetApp = row[targetAppColumn]
                bind(targetApp.isEmpty ? nil : targetApp, to: statement, at: 3)
                bind(transcription, to: statement, at: 4)
                bind(llmResponse.isEmpty ? nil : llmResponse, to: statement, at: 5)
                bind(finalText, to: statement, at: 6)

                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw databaseError()
                }
                importedCount += 1
            }

            try setMetadataValue(String(importedCount), for: Self.legacyImportKey)
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func prune(to requestedLimit: Int) throws {
        let limit = max(0, requestedLimit)
        guard limit > 0 else { return }

        let statement = try prepareStatement(
            """
            DELETE FROM dictation_history
            WHERE id IN (
                SELECT id
                FROM dictation_history
                ORDER BY created_at DESC, id DESC
                LIMIT -1 OFFSET ?
            )
            """
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, Int64(limit))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw databaseError()
        }
    }

    private func metadataValue(for key: String) -> String? {
        guard let statement = try? prepareStatement(
            "SELECT value FROM history_metadata WHERE key = ?"
        ) else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        bind(key, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return requiredText(from: statement, at: 0)
    }

    private func setMetadataValue(_ value: String, for key: String) throws {
        let statement = try prepareStatement(
            """
            INSERT INTO history_metadata (key, value)
            VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """
        )
        defer { sqlite3_finalize(statement) }

        bind(key, to: statement, at: 1)
        bind(value, to: statement, at: 2)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw databaseError()
        }
    }

    private func prepareStatement(_ sql: String) throws -> OpaquePointer {
        guard let database else {
            throw HistoryError.database(message: "Database is not open")
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw databaseError()
        }
        return statement
    }

    private func execute(_ sql: String) throws {
        guard let database else {
            throw HistoryError.database(message: "Database is not open")
        }

        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) }
                ?? databaseError().localizedDescription
            sqlite3_free(errorMessage)
            throw HistoryError.database(message: message)
        }
    }

    private func databaseError() -> HistoryError {
        guard let database else {
            return .database(message: "Database is not open")
        }
        return .database(message: String(cString: sqlite3_errmsg(database)))
    }

    private func bind(_ value: String?, to statement: OpaquePointer, at index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }

        sqlite3_bind_text(
            statement,
            index,
            value,
            -1,
            unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        )
    }

    private func requiredText(from statement: OpaquePointer, at index: Int32) -> String {
        guard let text = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: text)
    }

    private func optionalText(from statement: OpaquePointer, at index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return requiredText(from: statement, at: index)
    }

    private static func parseLegacyDate(_ value: String) -> Date {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        return ISO8601DateFormatter().date(from: value) ?? Date()
    }

    private static func parseCSV(_ data: Data) -> [[String]] {
        let bytes = Array(data)
        var rows: [[String]] = []
        var row: [String] = []
        var field: [UInt8] = []
        var isInsideQuotes = false
        var index = 0

        while index < bytes.count {
            let byte = bytes[index]

            if byte == 34 {
                if isInsideQuotes {
                    if index + 1 < bytes.count, bytes[index + 1] == 34 {
                        field.append(34)
                        index += 1
                    } else {
                        isInsideQuotes = false
                    }
                } else if field.isEmpty {
                    isInsideQuotes = true
                } else {
                    field.append(byte)
                }
            } else if byte == 44, !isInsideQuotes {
                row.append(String(decoding: field, as: UTF8.self))
                field.removeAll(keepingCapacity: true)
            } else if byte == 10, !isInsideQuotes {
                row.append(String(decoding: field, as: UTF8.self))
                field.removeAll(keepingCapacity: true)
                if row.count > 1 || row.first?.isEmpty == false {
                    rows.append(row)
                }
                row.removeAll(keepingCapacity: true)
            } else if byte != 13 || isInsideQuotes {
                field.append(byte)
            }

            index += 1
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(String(decoding: field, as: UTF8.self))
            if row.count > 1 || row.first?.isEmpty == false {
                rows.append(row)
            }
        }

        return rows
    }
}

extension Notification.Name {
    static let dictationHistoryDidChange = Notification.Name("dictationHistoryDidChange")
}
