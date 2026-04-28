import Foundation

/// Central registry of all UserDefaults keys used by the app.
/// This provides type safety and prevents key typos.
enum SettingsKeys {
    // MARK: - App Settings
    static let hideDockIcon = "hideDockIcon"
    static let muteDuringRecording = "muteDuringRecording"
    static let pauseMediaDuringDictation = "pauseMediaDuringDictation"

    // MARK: - Audio
    static let audioDeviceUID = "audioDeviceUID"  // deprecated, kept for migration
    static let audioDevicePriority = "audioDevicePriority"  // [String] UIDs in priority order
    static let audioDevicesEnabled = "audioDevicesEnabled"  // [String] UIDs of enabled devices

    // MARK: - LLM Settings
    static let llmModel = "llmModel"
    static let enhancementTimeoutBaseMs = "enhancementTimeoutBaseMs"
    static let enhancementTimeoutPerTokenMs = "enhancementTimeoutPerTokenMs"

    // MARK: - Transcription Settings
    static let transcriptionProvider = "transcriptionProvider"

    // MARK: - Directory Watcher
    static let directoryWatcherEnabled = "directoryWatcherEnabled"
    static let directoryWatcherInput = "directoryWatcherInput"
    static let directoryWatcherOutput = "directoryWatcherOutput"

    // MARK: - Obsidian Integration
    static let obsidianVault = "obsidianVault"
    static let obsidianDailyNoteEnabled = "obsidianDailyNoteEnabled"

    // MARK: - Per-Mode Prompt Files
    static let enhancedPromptFile = "enhancedPromptFile"
    static let replyPromptFile = "replyPromptFile"
    static let commandPromptFile = "commandPromptFile"

    // MARK: - Per-Mode Selection Capture
    static let replyCaptureSelection = "replyCaptureSelection"

    // MARK: - Custom Vocabulary (stored as JSON string)
    static let customVocabulary = "customVocabulary"

    // MARK: - Streaming Preview
    static let streamingPreviewEnabled = "streamingPreviewEnabled"

    // MARK: - Text Formatting
    static let trailingPunctuationRemoval = "TrailingPunctuationRemoval"
    static let trailingSpace = "TrailingSpace"
    static let trailingLineBreak = "TrailingLineBreak"
    static let trailingEnter = "TrailingEnter"

    // MARK: - Migration Flag
    static let configMigrated = "configMigrated"
}

/// Default values for all settings
enum SettingsDefaults {
    // App
    static let hideDockIcon = true
    static let muteDuringRecording = true
    static let pauseMediaDuringDictation = false

    // Audio
    static let audioDeviceUID: String? = nil  // deprecated
    static let audioDevicePriority: [String] = []  // empty = use discovery order
    static let audioDevicesEnabled: [String] = []  // empty = all enabled by default

    // LLM
    static let llmModel = "moonshotai/kimi-k2-instruct-0905"
    static let enhancementTimeoutBaseMs = 800
    static let enhancementTimeoutPerTokenMs = 10

    // Transcription
    static let transcriptionProvider = TranscriptionProvider.parakeet.rawValue

    // Directory Watcher
    static let directoryWatcherEnabled = false
    static let directoryWatcherInput = ""
    static let directoryWatcherOutput = ""

    // Obsidian
    static let obsidianVault: String? = nil
    static let obsidianDailyNoteEnabled = true

    // Per-mode prompt files
    static let enhancedPromptFile = "default"
    static let replyPromptFile = "reply"
    static let commandPromptFile = "command"

    // Per-mode selection capture
    static let replyCaptureSelection = true

    // Custom vocabulary
    static let customVocabulary: [String] = ["Parakeet", "Groq"]

    // Streaming Preview
    static let streamingPreviewEnabled = false

    // Text Formatting
    static let trailingPunctuationRemoval = false
    static let trailingSpace = false
    static let trailingLineBreak = false
    static let trailingEnter = false
}
