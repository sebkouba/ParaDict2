import Foundation
import os

private let logger = Logger(subsystem: "com.paradict", category: "CorrectionLogger")

/// Logs user corrections (original text, corrected text, and explanation) to a TSV file.
class CorrectionLogger {
    static let shared = CorrectionLogger()

    private var logFilePath: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("ParaDict")
        return appDir.appendingPathComponent("corrections.tsv")
    }

    private init() {
        ensureLogFileExists()
    }

    private func ensureLogFileExists() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("ParaDict")

        if !FileManager.default.fileExists(atPath: appDir.path) {
            do {
                try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
                logger.notice("Created app support directory")
            } catch {
                logger.error("Failed to create app support directory: \(error.localizedDescription)")
            }
        }

        if !FileManager.default.fileExists(atPath: logFilePath.path) {
            let header = "timestamp\toriginal\tcorrection\texplanation\n"
            do {
                try header.write(to: logFilePath, atomically: true, encoding: .utf8)
                logger.notice("Created corrections log file with header")
            } catch {
                logger.error("Failed to create corrections log file: \(error.localizedDescription)")
            }
        }
    }

    /// Log a correction entry
    func logCorrection(original: String, correction: String, explanation: String?) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())

        let fields = [
            timestamp,
            escapeTSVField(original),
            escapeTSVField(correction),
            escapeTSVField(explanation ?? "")
        ]

        let row = fields.joined(separator: "\t") + "\n"

        do {
            let fileHandle = try FileHandle(forWritingTo: logFilePath)
            fileHandle.seekToEndOfFile()
            if let data = row.data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
            logger.notice("Logged correction: original=\(original.prefix(50))..., correction=\(correction.prefix(50))...")
        } catch {
            logger.error("Failed to append to corrections log: \(error.localizedDescription)")
        }
    }

    /// Escape a field for TSV (replace tabs and newlines)
    private func escapeTSVField(_ field: String) -> String {
        return field
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
