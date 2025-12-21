import Foundation
import Yams
import KeyboardShortcuts
import os

/// Handles one-time migration from the old YAML config file to UserDefaults.
/// This runs on app launch and migrates any existing config.yaml settings.
struct SettingsMigration {
    private static let logger = Logger(subsystem: "com.paradict", category: "SettingsMigration")

    /// Run migration if needed. Call this on app launch.
    static func migrateIfNeeded() {
        // Check if already migrated
        if UserDefaults.standard.bool(forKey: SettingsKeys.configMigrated) {
            return
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let configURL = appSupport.appendingPathComponent("ParaDict/config.yaml")

        guard FileManager.default.fileExists(atPath: configURL.path) else {
            // No config to migrate - mark as done so we don't check again
            UserDefaults.standard.set(true, forKey: SettingsKeys.configMigrated)
            logger.notice("No config.yaml found, skipping migration")
            return
        }

        do {
            let yamlString = try String(contentsOf: configURL, encoding: .utf8)
            let config = try YAMLDecoder().decode(LegacyAppConfig.self, from: yamlString)

            migrate(config)

            // Backup the old config file
            let backupURL = appSupport.appendingPathComponent("ParaDict/config.yaml.backup")
            try? FileManager.default.moveItem(at: configURL, to: backupURL)

            UserDefaults.standard.set(true, forKey: SettingsKeys.configMigrated)
            logger.notice("Successfully migrated config.yaml to UserDefaults")
        } catch {
            logger.error("Failed to migrate config.yaml: \(error.localizedDescription)")
            // Don't mark as migrated so we can retry on next launch
        }
    }

    private static func migrate(_ config: LegacyAppConfig) {
        let defaults = UserDefaults.standard

        // App settings
        defaults.set(config.app.hideDockIcon, forKey: SettingsKeys.hideDockIcon)
        defaults.set(config.app.muteDuringRecording, forKey: SettingsKeys.muteDuringRecording)

        // Audio
        if config.audio.device != "system_default" {
            defaults.set(config.audio.device, forKey: SettingsKeys.audioDeviceUID)
        }

        // LLM settings
        defaults.set(config.llm.model, forKey: SettingsKeys.llmModel)
        defaults.set(config.llm.enhancementTimeoutBaseMs, forKey: SettingsKeys.enhancementTimeoutBaseMs)
        defaults.set(config.llm.enhancementTimeoutPerTokenMs, forKey: SettingsKeys.enhancementTimeoutPerTokenMs)

        // Directory watcher
        defaults.set(config.directoryWatcher.enabled, forKey: SettingsKeys.directoryWatcherEnabled)
        defaults.set(config.directoryWatcher.inputDirectory, forKey: SettingsKeys.directoryWatcherInput)
        defaults.set(config.directoryWatcher.outputDirectory, forKey: SettingsKeys.directoryWatcherOutput)

        // Obsidian
        if let vault = config.obsidian.vault {
            defaults.set(vault, forKey: SettingsKeys.obsidianVault)
        }
        defaults.set(config.obsidian.dailyNoteKeywordEnabled, forKey: SettingsKeys.obsidianDailyNoteEnabled)

        // Per-mode settings from shortcuts array
        for shortcut in config.shortcuts {
            switch shortcut.mode {
            case .enhanced:
                if let promptFile = shortcut.promptFile {
                    defaults.set(promptFile, forKey: SettingsKeys.enhancedPromptFile)
                }
            case .reply:
                if let promptFile = shortcut.promptFile {
                    defaults.set(promptFile, forKey: SettingsKeys.replyPromptFile)
                }
                if let capture = shortcut.captureSelection {
                    defaults.set(capture, forKey: SettingsKeys.replyCaptureSelection)
                }
            case .command:
                if let promptFile = shortcut.promptFile {
                    defaults.set(promptFile, forKey: SettingsKeys.commandPromptFile)
                }
            case .local:
                break  // No settings to migrate for local mode
            }

            // Migrate keyboard shortcuts to KeyboardShortcuts library
            if let shortcutString = shortcut.shortcut,
               let parsedShortcut = ShortcutParser.parse(shortcutString) {
                switch shortcut.mode {
                case .local:
                    KeyboardShortcuts.setShortcut(parsedShortcut, for: .localDictation)
                case .enhanced:
                    KeyboardShortcuts.setShortcut(parsedShortcut, for: .enhancedDictation)
                case .reply:
                    KeyboardShortcuts.setShortcut(parsedShortcut, for: .replyDictation)
                case .command:
                    KeyboardShortcuts.setShortcut(parsedShortcut, for: .commandDictation)
                }
            }
        }

        // Custom vocabulary
        if !config.customVocabulary.isEmpty,
           let data = try? JSONEncoder().encode(config.customVocabulary),
           let jsonString = String(data: data, encoding: .utf8) {
            defaults.set(jsonString, forKey: SettingsKeys.customVocabulary)
        }

        logger.notice("Migrated settings: hideDockIcon=\(config.app.hideDockIcon), muteDuringRecording=\(config.app.muteDuringRecording), llmModel=\(config.llm.model)")
    }
}

// MARK: - Legacy Config Structures (for migration only)

private struct LegacyAppConfig: Codable {
    var app: LegacyAppSettings
    var audio: LegacyAudioSettings
    var llm: LegacyLLMSettings
    var directoryWatcher: LegacyDirectoryWatcherSettings
    var obsidian: LegacyObsidianSettings
    var shortcuts: [LegacyShortcutConfig]
    var customVocabulary: [String]

    enum CodingKeys: String, CodingKey {
        case app, audio, llm, shortcuts, obsidian
        case directoryWatcher = "directory_watcher"
        case customVocabulary = "custom_vocabulary"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        app = try container.decodeIfPresent(LegacyAppSettings.self, forKey: .app) ?? LegacyAppSettings()
        audio = try container.decodeIfPresent(LegacyAudioSettings.self, forKey: .audio) ?? LegacyAudioSettings()
        llm = try container.decodeIfPresent(LegacyLLMSettings.self, forKey: .llm) ?? LegacyLLMSettings()
        directoryWatcher = try container.decodeIfPresent(LegacyDirectoryWatcherSettings.self, forKey: .directoryWatcher) ?? LegacyDirectoryWatcherSettings()
        obsidian = try container.decodeIfPresent(LegacyObsidianSettings.self, forKey: .obsidian) ?? LegacyObsidianSettings()
        shortcuts = try container.decodeIfPresent([LegacyShortcutConfig].self, forKey: .shortcuts) ?? []
        customVocabulary = try container.decodeIfPresent([String].self, forKey: .customVocabulary) ?? []
    }
}

private struct LegacyShortcutConfig: Codable {
    var name: String
    var shortcut: String?
    var mode: DictationMode
    var promptFile: String?
    var captureSelection: Bool?

    enum CodingKeys: String, CodingKey {
        case name, shortcut, mode
        case promptFile = "prompt_file"
        case captureSelection = "capture_selection"
    }
}

private struct LegacyAppSettings: Codable {
    var hideDockIcon: Bool = true
    var launchAtLogin: Bool = false
    var muteDuringRecording: Bool = true

    enum CodingKeys: String, CodingKey {
        case hideDockIcon = "hide_dock_icon"
        case launchAtLogin = "launch_at_login"
        case muteDuringRecording = "mute_during_recording"
    }
}

private struct LegacyAudioSettings: Codable {
    var device: String = "system_default"
}

private struct LegacyLLMSettings: Codable {
    var provider: String = "groq"
    var model: String = "moonshotai/kimi-k2-instruct-0905"
    var enhancementTimeoutBaseMs: Int = 800
    var enhancementTimeoutPerTokenMs: Int = 10

    enum CodingKeys: String, CodingKey {
        case provider, model
        case enhancementTimeoutBaseMs = "enhancement_timeout_base_ms"
        case enhancementTimeoutPerTokenMs = "enhancement_timeout_per_token_ms"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decodeIfPresent(String.self, forKey: .provider) ?? "groq"
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? "moonshotai/kimi-k2-instruct-0905"
        enhancementTimeoutBaseMs = try container.decodeIfPresent(Int.self, forKey: .enhancementTimeoutBaseMs) ?? 800
        enhancementTimeoutPerTokenMs = try container.decodeIfPresent(Int.self, forKey: .enhancementTimeoutPerTokenMs) ?? 10
    }

    init() {}
}

private struct LegacyDirectoryWatcherSettings: Codable {
    var enabled: Bool = false
    var inputDirectory: String = ""
    var outputDirectory: String = ""

    enum CodingKeys: String, CodingKey {
        case enabled
        case inputDirectory = "input_directory"
        case outputDirectory = "output_directory"
    }
}

private struct LegacyObsidianSettings: Codable {
    var vault: String?
    var dailyNoteKeywordEnabled: Bool = true
}
