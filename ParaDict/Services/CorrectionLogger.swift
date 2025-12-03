import Foundation
import os

private let logger = Logger(subsystem: "com.paradict", category: "CorrectionLogger")

/// Logs user corrections to a TSV file and immediately appends them to the custom dictionary.
/// Columns: timestamp, original_transcription (Parakeet), llm_output (what was pasted), dictionary_entry
class CorrectionLogger {
    static let shared = CorrectionLogger()

    private var logFilePath: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let appDir = appSupport.appendingPathComponent("ParaDict")
        return appDir.appendingPathComponent("corrections.tsv")
    }

    private init() {
        ensureLogFileExists()
    }

    private func ensureLogFileExists() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
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
            let header = "timestamp\toriginal_transcription\tllm_output\tdictionary_entry\n"
            do {
                try header.write(to: logFilePath, atomically: true, encoding: .utf8)
                logger.notice("Created corrections log file with header")
            } catch {
                logger.error("Failed to create corrections log file: \(error.localizedDescription)")
            }
        }
    }

    /// Log a correction entry and immediately append it to the custom dictionary
    /// - Parameters:
    ///   - originalTranscription: Raw transcription from Parakeet/FluidAudio
    ///   - llmOutput: What was actually pasted (may be LLM-enhanced, or same as original if local mode)
    ///   - dictionaryEntry: The full XML-formatted dictionary entry to append
    func logCorrection(originalTranscription: String, llmOutput: String, dictionaryEntry: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())

        let fields = [
            timestamp,
            escapeTSVField(originalTranscription),
            escapeTSVField(llmOutput),
            escapeTSVField(dictionaryEntry)
        ]

        let row = fields.joined(separator: "\t") + "\n"

        do {
            let fileHandle = try FileHandle(forWritingTo: logFilePath)
            fileHandle.seekToEndOfFile()
            if let data = row.data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
            logger.notice("Logged correction: transcription=\(originalTranscription.prefix(30))..., entry=\(dictionaryEntry.prefix(50))...")
        } catch {
            logger.error("Failed to append to corrections log: \(error.localizedDescription)")
        }

        // Immediately append the dictionary entry
        appendToDictionary(dictionaryEntry: dictionaryEntry)
    }

    /// Append a dictionary entry to the dictionary.md file
    private func appendToDictionary(dictionaryEntry: String) {
        // Load current dictionary
        guard var dictionary = DictionaryManager.shared.loadDictionary() else {
            logger.error("Could not load dictionary to append entry")
            return
        }

        // Append to the end of the dictionary with newline
        if !dictionary.hasSuffix("\n") {
            dictionary += "\n"
        }
        dictionary += dictionaryEntry + "\n"

        // Save the updated dictionary
        DictionaryManager.shared.saveDictionary(dictionary)
        logger.notice("Appended entry to dictionary: \(dictionaryEntry.prefix(50))...")
    }

    /// Escape a field for TSV (replace tabs and newlines)
    private func escapeTSVField(_ field: String) -> String {
        return field
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
