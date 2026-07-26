import Foundation
import SwiftUI

/// Observable singleton that provides access to all app settings via UserDefaults.
/// Use @AppStorage in views for direct binding, or access this singleton for non-UI code.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private init() {}

    // MARK: - App Settings

    var hideDockIcon: Bool {
        get { UserDefaults.standard.object(forKey: SettingsKeys.hideDockIcon) as? Bool ?? SettingsDefaults.hideDockIcon }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKeys.hideDockIcon) }
    }

    var muteDuringRecording: Bool {
        get { UserDefaults.standard.object(forKey: SettingsKeys.muteDuringRecording) as? Bool ?? SettingsDefaults.muteDuringRecording }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKeys.muteDuringRecording) }
    }

    var pauseMediaDuringDictation: Bool {
        get { UserDefaults.standard.object(forKey: SettingsKeys.pauseMediaDuringDictation) as? Bool ?? SettingsDefaults.pauseMediaDuringDictation }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKeys.pauseMediaDuringDictation) }
    }

    var pauseMicrophoneDuringPlayback: Bool {
        get { UserDefaults.standard.object(forKey: SettingsKeys.pauseMicrophoneDuringPlayback) as? Bool ?? SettingsDefaults.pauseMicrophoneDuringPlayback }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKeys.pauseMicrophoneDuringPlayback) }
    }

    // MARK: - Audio Settings

    var audioDeviceUID: String? {
        get { UserDefaults.standard.string(forKey: SettingsKeys.audioDeviceUID) }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKeys.audioDeviceUID) }
    }

    var recordingArchiveEnabled: Bool {
        get { UserDefaults.standard.object(forKey: SettingsKeys.recordingArchiveEnabled) as? Bool ?? SettingsDefaults.recordingArchiveEnabled }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKeys.recordingArchiveEnabled) }
    }

    var recordingArchiveDirectory: String {
        get { UserDefaults.standard.string(forKey: SettingsKeys.recordingArchiveDirectory) ?? SettingsDefaults.recordingArchiveDirectory }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKeys.recordingArchiveDirectory) }
    }

    var recordingArchiveRetentionDays: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: SettingsKeys.recordingArchiveRetentionDays)
            return value > 0 ? min(value, 999) : SettingsDefaults.recordingArchiveRetentionDays
        }
        set { UserDefaults.standard.set(max(1, min(newValue, 999)), forKey: SettingsKeys.recordingArchiveRetentionDays) }
    }

    // MARK: - LLM Settings

    var llmModel: String {
        get { UserDefaults.standard.string(forKey: SettingsKeys.llmModel) ?? SettingsDefaults.llmModel }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKeys.llmModel) }
    }

    var enhancementTimeoutBaseMs: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: SettingsKeys.enhancementTimeoutBaseMs)
            return value > 0 ? value : SettingsDefaults.enhancementTimeoutBaseMs
        }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKeys.enhancementTimeoutBaseMs) }
    }

    var enhancementTimeoutPerTokenMs: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: SettingsKeys.enhancementTimeoutPerTokenMs)
            return value > 0 ? value : SettingsDefaults.enhancementTimeoutPerTokenMs
        }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKeys.enhancementTimeoutPerTokenMs) }
    }

    // MARK: - Transcription Settings

    var transcriptionProvider: TranscriptionProvider {
        get {
            let rawValue = UserDefaults.standard.string(forKey: SettingsKeys.transcriptionProvider) ?? SettingsDefaults.transcriptionProvider
            return TranscriptionProvider(rawValue: rawValue) ?? .parakeet
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: SettingsKeys.transcriptionProvider) }
    }

    /// Calculate timeout for enhancement based on text length (estimates ~4 characters per token)
    func calculateEnhancementTimeout(forText text: String) -> TimeInterval {
        let estimatedTokens = max(1, text.count / 4)
        let timeoutMs = enhancementTimeoutBaseMs + (estimatedTokens * enhancementTimeoutPerTokenMs)
        return TimeInterval(timeoutMs) / 1000.0
    }

    // MARK: - Directory Watcher Settings

    var directoryWatcherEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: SettingsKeys.directoryWatcherEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKeys.directoryWatcherEnabled) }
    }

    var directoryWatcherInput: String {
        get { UserDefaults.standard.string(forKey: SettingsKeys.directoryWatcherInput) ?? SettingsDefaults.directoryWatcherInput }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKeys.directoryWatcherInput) }
    }

    var directoryWatcherOutput: String {
        get { UserDefaults.standard.string(forKey: SettingsKeys.directoryWatcherOutput) ?? SettingsDefaults.directoryWatcherOutput }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKeys.directoryWatcherOutput) }
    }

    // MARK: - Obsidian Settings

    var obsidianVault: String? {
        get { UserDefaults.standard.string(forKey: SettingsKeys.obsidianVault) }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKeys.obsidianVault) }
    }

    var obsidianDailyNoteEnabled: Bool {
        get { UserDefaults.standard.object(forKey: SettingsKeys.obsidianDailyNoteEnabled) as? Bool ?? SettingsDefaults.obsidianDailyNoteEnabled }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKeys.obsidianDailyNoteEnabled) }
    }

    // MARK: - Per-Mode Prompt Files

    var enhancedPromptFile: String {
        get { UserDefaults.standard.string(forKey: SettingsKeys.enhancedPromptFile) ?? SettingsDefaults.enhancedPromptFile }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKeys.enhancedPromptFile) }
    }

    var replyPromptFile: String {
        get { UserDefaults.standard.string(forKey: SettingsKeys.replyPromptFile) ?? SettingsDefaults.replyPromptFile }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKeys.replyPromptFile) }
    }

    var commandPromptFile: String {
        get { UserDefaults.standard.string(forKey: SettingsKeys.commandPromptFile) ?? SettingsDefaults.commandPromptFile }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKeys.commandPromptFile) }
    }

    /// Get the prompt file for a given dictation mode
    func promptFile(for mode: DictationMode) -> String? {
        switch mode {
        case .local:
            return nil  // Local mode doesn't use prompts
        case .enhanced:
            return enhancedPromptFile
        case .reply:
            return replyPromptFile
        case .command:
            return commandPromptFile
        }
    }

    // MARK: - Per-Mode Selection Capture

    var replyCaptureSelection: Bool {
        get { UserDefaults.standard.object(forKey: SettingsKeys.replyCaptureSelection) as? Bool ?? SettingsDefaults.replyCaptureSelection }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKeys.replyCaptureSelection) }
    }

    /// Check if selection should be captured for a given mode
    func shouldCaptureSelection(for mode: DictationMode) -> Bool {
        switch mode {
        case .reply:
            return replyCaptureSelection
        default:
            return false
        }
    }

    // MARK: - Streaming Preview

    var streamingPreviewEnabled: Bool {
        get { UserDefaults.standard.object(forKey: SettingsKeys.streamingPreviewEnabled) as? Bool ?? SettingsDefaults.streamingPreviewEnabled }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKeys.streamingPreviewEnabled) }
    }

    // MARK: - Custom Vocabulary

    var customVocabulary: [String] {
        get {
            guard let jsonString = UserDefaults.standard.string(forKey: SettingsKeys.customVocabulary),
                  let data = jsonString.data(using: .utf8),
                  let array = try? JSONDecoder().decode([String].self, from: data) else {
                return SettingsDefaults.customVocabulary
            }
            return array
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let jsonString = String(data: data, encoding: .utf8) {
                UserDefaults.standard.set(jsonString, forKey: SettingsKeys.customVocabulary)
            }
        }
    }
}

// MARK: - DictationMode (moved from ConfigManager)

enum DictationMode: String, Codable, CaseIterable {
    case local      // Parakeet only
    case enhanced   // Parakeet + LLM
    case reply      // Parakeet + LLM with selection context
    case command    // Parakeet + LLM with tool calling (voice commands)
}

enum TranscriptionProvider: String, Codable, CaseIterable, Identifiable {
    case parakeet
    case xai
    case elevenLabs

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .parakeet:
            return "Parakeet"
        case .xai:
            return "x.ai"
        case .elevenLabs:
            return "ElevenLabs"
        }
    }
}
