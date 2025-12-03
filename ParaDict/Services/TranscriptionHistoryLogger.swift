import Foundation
import os

private let logger = Logger(subsystem: "com.paradict", category: "TranscriptionHistoryLogger")

/// Logs all transcription events, LLM prompts, and LLM responses to a CSV file
/// for complete history tracking.
class TranscriptionHistoryLogger {
    static let shared = TranscriptionHistoryLogger()

    /// CSV columns: timestamp, event_type, mode, target_app, transcription, llm_prompt, llm_response, final_output
    private let csvHeader = "timestamp,event_type,mode,target_app,transcription,llm_prompt,llm_response,final_output"

    private var logFilePath: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let appDir = appSupport.appendingPathComponent("ParaDict")
        return appDir.appendingPathComponent("transcription_history.csv")
    }

    private init() {
        ensureLogFileExists()
    }

    /// Ensure the log file exists with header
    private func ensureLogFileExists() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let appDir = appSupport.appendingPathComponent("ParaDict")

        // Create directory if needed
        if !FileManager.default.fileExists(atPath: appDir.path) {
            do {
                try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
                logger.notice("Created app support directory")
            } catch {
                logger.error("Failed to create app support directory: \(error.localizedDescription)")
            }
        }

        // Create file with header if it doesn't exist
        if !FileManager.default.fileExists(atPath: logFilePath.path) {
            do {
                try (csvHeader + "\n").write(to: logFilePath, atomically: true, encoding: .utf8)
                logger.notice("Created transcription history log file with header")
            } catch {
                logger.error("Failed to create log file: \(error.localizedDescription)")
            }
        }
    }

    /// Log a local transcription (no LLM)
    func logLocalTranscription(
        transcription: String,
        targetApp: String?
    ) {
        let row = createCSVRow(
            eventType: "local_transcription",
            mode: "local",
            targetApp: targetApp,
            transcription: transcription,
            llmPrompt: nil,
            llmResponse: nil,
            finalOutput: transcription
        )
        appendRow(row)
        logger.notice("Logged local transcription (\(transcription.count) chars)")
    }

    /// Log an enhanced transcription (with LLM)
    func logEnhancedTranscription(
        transcription: String,
        llmPrompt: String,
        llmResponse: String,
        targetApp: String?
    ) {
        let row = createCSVRow(
            eventType: "enhanced_transcription",
            mode: "enhanced",
            targetApp: targetApp,
            transcription: transcription,
            llmPrompt: llmPrompt,
            llmResponse: llmResponse,
            finalOutput: llmResponse
        )
        appendRow(row)
        logger.notice("Logged enhanced transcription (transcription: \(transcription.count) chars, response: \(llmResponse.count) chars)")
    }

    /// Log a failed transcription attempt
    func logFailedTranscription(
        mode: String,
        error: String,
        targetApp: String?
    ) {
        let row = createCSVRow(
            eventType: "failed_transcription",
            mode: mode,
            targetApp: targetApp,
            transcription: nil,
            llmPrompt: nil,
            llmResponse: nil,
            finalOutput: "ERROR: \(error)"
        )
        appendRow(row)
        logger.notice("Logged failed transcription: \(error)")
    }

    /// Create a CSV row with proper escaping
    private func createCSVRow(
        eventType: String,
        mode: String,
        targetApp: String?,
        transcription: String?,
        llmPrompt: String?,
        llmResponse: String?,
        finalOutput: String?
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())

        let fields = [
            timestamp,
            eventType,
            mode,
            targetApp ?? "",
            transcription ?? "",
            llmPrompt ?? "",
            llmResponse ?? "",
            finalOutput ?? ""
        ]

        return fields.map { escapeCSVField($0) }.joined(separator: ",")
    }

    /// Escape a field for CSV (handle commas, quotes, newlines)
    private func escapeCSVField(_ field: String) -> String {
        // If field contains comma, quote, or newline, wrap in quotes and escape internal quotes
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }

    /// Append a row to the log file
    private func appendRow(_ row: String) {
        do {
            let fileHandle = try FileHandle(forWritingTo: logFilePath)
            fileHandle.seekToEndOfFile()
            if let data = (row + "\n").data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
        } catch {
            logger.error("Failed to append to log file: \(error.localizedDescription)")
        }
    }
}
