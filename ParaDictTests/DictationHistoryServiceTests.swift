import Foundation
import XCTest
@testable import ParaDict

final class DictationHistoryServiceTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "DictationHistoryServiceTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testSaveKeepsAllEntriesByDefaultAndReturnsNewestFirst() async throws {
        let service = makeService()

        try await service.save(
            transcription: "First",
            enhancedText: nil,
            mode: .local,
            targetApp: "com.example.first",
            createdAt: Date(timeIntervalSince1970: 100),
            retentionLimit: 0
        )
        try await service.save(
            transcription: "Second raw",
            enhancedText: "Second enhanced",
            mode: .enhanced,
            targetApp: "com.example.second",
            createdAt: Date(timeIntervalSince1970: 200),
            retentionLimit: 0
        )

        let entries = try await service.fetchEntries(retentionLimit: 0)

        XCTAssertEqual(entries.map(\.finalText), ["Second enhanced", "First"])
        XCTAssertEqual(entries[0].transcription, "Second raw")
        XCTAssertEqual(entries[0].enhancedText, "Second enhanced")
        XCTAssertEqual(entries[0].modeDisplayName, "Enhanced")
        XCTAssertEqual(entries[1].targetApp, "com.example.first")
    }

    func testFiniteRetentionDeletesOlderEntries() async throws {
        let service = makeService()

        for index in 1...4 {
            try await service.save(
                transcription: "Entry \(index)",
                enhancedText: nil,
                mode: .local,
                targetApp: nil,
                createdAt: Date(timeIntervalSince1970: Double(index)),
                retentionLimit: 2
            )
        }

        let entries = try await service.fetchEntries(retentionLimit: 2)

        XCTAssertEqual(entries.map(\.finalText), ["Entry 4", "Entry 3"])
    }

    func testImportsExistingCSVWithQuotedCommasAndNewlinesOnce() async throws {
        let csvURL = temporaryDirectory.appendingPathComponent("transcription_history.csv")
        let csv = #"""
        timestamp,event_type,mode,target_app,transcription,llm_prompt,llm_response,final_output
        2026-02-07T18:39:50.560Z,local_transcription,local,md.obsidian,"Hello, world",,,"Hello, world"
        2026-02-07T18:40:00.000Z,enhanced_transcription,enhanced,com.example,"Raw
        text",,"Enhanced ""text""","Enhanced ""text"""

        """#
        try csv.write(to: csvURL, atomically: true, encoding: .utf8)

        let databaseURL = temporaryDirectory.appendingPathComponent("history.sqlite3")
        let service = DictationHistoryService(
            databaseURL: databaseURL,
            legacyCSVURL: csvURL
        )

        let firstFetch = try await service.fetchEntries(retentionLimit: 0)
        let secondFetch = try await service.fetchEntries(retentionLimit: 0)

        XCTAssertEqual(firstFetch.count, 2)
        XCTAssertEqual(secondFetch.count, 2)
        XCTAssertEqual(firstFetch[0].transcription, "Raw\ntext")
        XCTAssertEqual(firstFetch[0].finalText, "Enhanced \"text\"")
        XCTAssertEqual(firstFetch[1].finalText, "Hello, world")
    }

    private func makeService() -> DictationHistoryService {
        DictationHistoryService(
            databaseURL: temporaryDirectory.appendingPathComponent("history.sqlite3"),
            importsLegacyCSV: false
        )
    }
}
