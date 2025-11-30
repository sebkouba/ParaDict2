import Foundation
import os

private let logger = Logger(subsystem: "com.paradict", category: "CorrectionLogger")

/// Logs user corrections to a TSV file and immediately appends them to the custom dictionary.
/// Columns: timestamp, original_transcription (Parakeet), llm_output (what was pasted), correction, explanation
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
            let header = "timestamp\toriginal_transcription\tllm_output\tcorrection\texplanation\n"
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
    ///   - correction: User's corrected text
    ///   - explanation: Optional explanation of why correction was needed
    func logCorrection(originalTranscription: String, llmOutput: String, correction: String, explanation: String?) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())

        let fields = [
            timestamp,
            escapeTSVField(originalTranscription),
            escapeTSVField(llmOutput),
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
            logger.notice("Logged correction: transcription=\(originalTranscription.prefix(30))..., llm=\(llmOutput.prefix(30))..., correction=\(correction.prefix(30))...")
        } catch {
            logger.error("Failed to append to corrections log: \(error.localizedDescription)")
        }

        // Immediately append the correction to the custom dictionary
        appendToDictionary(llmOutput: llmOutput, correction: correction)
    }

    /// Append a correction entry to the dictionary.md file
    private func appendToDictionary(llmOutput: String, correction: String) {
        // Only add if there's an actual difference
        guard llmOutput != correction else {
            logger.notice("Correction matches LLM output, skipping dictionary update")
            return
        }

        // Build the correction entry
        let entry = "- \"\(llmOutput)\" → \"\(correction)\"\n"

        // Load current dictionary
        guard var dictionary = DictionaryManager.shared.loadDictionary() else {
            logger.error("Could not load dictionary to append correction")
            return
        }

        // Append to the end of the dictionary
        if !dictionary.hasSuffix("\n") {
            dictionary += "\n"
        }
        dictionary += entry

        // Save the updated dictionary
        DictionaryManager.shared.saveDictionary(dictionary)
        logger.notice("Appended correction to dictionary: \(llmOutput.prefix(20))... → \(correction.prefix(20))...")
    }

    /// Escape a field for TSV (replace tabs and newlines)
    private func escapeTSVField(_ field: String) -> String {
        return field
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
