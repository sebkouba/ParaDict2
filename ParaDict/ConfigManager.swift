import Foundation
import Combine
import Yams
import KeyboardShortcuts
import Carbon.HIToolbox
import AppKit
import os

struct AppConfig: Codable {
    var app: AppSettings
    var audio: AudioSettings
    var llm: LLMSettings
    var shortcuts: [ShortcutConfig]
    var customVocabulary: [String]

    enum CodingKeys: String, CodingKey {
        case app, audio, llm, shortcuts
        case customVocabulary = "custom_vocabulary"
    }

    static var `default`: AppConfig {
        AppConfig(
            app: AppSettings(),
            audio: AudioSettings(),
            llm: LLMSettings(),
            shortcuts: [
                ShortcutConfig(name: "local", shortcut: "ctrl+cmd+t", mode: .local, promptFile: nil, captureSelection: nil),
                ShortcutConfig(name: "enhanced", shortcut: nil, mode: .enhanced, promptFile: "default", captureSelection: nil),
                ShortcutConfig(name: "reply", shortcut: nil, mode: .reply, promptFile: "reply", captureSelection: true)
            ],
            customVocabulary: ["Parakeet", "Groq"]
        )
    }
}

struct ShortcutConfig: Codable, Identifiable {
    var id: String { name }
    var name: String
    var shortcut: String?
    var mode: DictationMode
    var promptFile: String?
    var captureSelection: Bool?  // If true, capture highlighted text before recording

    enum CodingKeys: String, CodingKey {
        case name, shortcut, mode
        case promptFile = "prompt_file"
        case captureSelection = "capture_selection"
    }

    /// Whether this shortcut should capture selected text
    var shouldCaptureSelection: Bool {
        captureSelection ?? (mode == .reply)  // Default true for reply mode
    }
}

struct AppSettings: Codable {
    var hideDockIcon: Bool = true
    var launchAtLogin: Bool = false
    var muteDuringRecording: Bool = true

    enum CodingKeys: String, CodingKey {
        case hideDockIcon = "hide_dock_icon"
        case launchAtLogin = "launch_at_login"
        case muteDuringRecording = "mute_during_recording"
    }
}

struct AudioSettings: Codable {
    var device: String = "system_default"
}

struct LLMSettings: Codable {
    var provider: String = "groq"
    var model: String = "moonshotai/kimi-k2-instruct-0905"

    enum CodingKeys: String, CodingKey {
        case provider, model
    }
}

enum DictationMode: String, Codable {
    case local      // Parakeet only
    case enhanced   // Parakeet + LLM
    case reply      // Parakeet + LLM with selection context
}

// MARK: - Shortcut String Parsing

/// Parses shortcut strings like "ctrl+cmd+t" to KeyboardShortcuts.Shortcut
struct ShortcutParser {
    /// Parse a string like "ctrl+cmd+t" into a KeyboardShortcuts.Shortcut
    static func parse(_ string: String) -> KeyboardShortcuts.Shortcut? {
        let parts = string.lowercased().split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty else { return nil }

        var modifiers: NSEvent.ModifierFlags = []
        var keyString: String?

        for part in parts {
            switch part {
            case "cmd", "command", "⌘":
                modifiers.insert(.command)
            case "ctrl", "control", "⌃":
                modifiers.insert(.control)
            case "opt", "option", "alt", "⌥":
                modifiers.insert(.option)
            case "shift", "⇧":
                modifiers.insert(.shift)
            default:
                keyString = part
            }
        }

        guard let key = keyString, let keyCode = keyCodeForString(key) else {
            return nil
        }

        let shortcutKey = KeyboardShortcuts.Key(rawValue: Int(keyCode))
        return KeyboardShortcuts.Shortcut(shortcutKey, modifiers: modifiers)
    }

    /// Convert a KeyboardShortcuts.Shortcut to a string like "ctrl+cmd+t"
    static func toString(_ shortcut: KeyboardShortcuts.Shortcut) -> String {
        var parts: [String] = []

        if shortcut.modifiers.contains(.control) { parts.append("ctrl") }
        if shortcut.modifiers.contains(.option) { parts.append("opt") }
        if shortcut.modifiers.contains(.shift) { parts.append("shift") }
        if shortcut.modifiers.contains(.command) { parts.append("cmd") }

        if let key = shortcut.key, let keyString = stringForKeyCode(UInt16(key.rawValue)) {
            parts.append(keyString)
        }

        return parts.joined(separator: "+")
    }

    private static func keyCodeForString(_ string: String) -> UInt16? {
        // Common keys
        let keyMap: [String: UInt16] = [
            "a": UInt16(kVK_ANSI_A), "b": UInt16(kVK_ANSI_B), "c": UInt16(kVK_ANSI_C),
            "d": UInt16(kVK_ANSI_D), "e": UInt16(kVK_ANSI_E), "f": UInt16(kVK_ANSI_F),
            "g": UInt16(kVK_ANSI_G), "h": UInt16(kVK_ANSI_H), "i": UInt16(kVK_ANSI_I),
            "j": UInt16(kVK_ANSI_J), "k": UInt16(kVK_ANSI_K), "l": UInt16(kVK_ANSI_L),
            "m": UInt16(kVK_ANSI_M), "n": UInt16(kVK_ANSI_N), "o": UInt16(kVK_ANSI_O),
            "p": UInt16(kVK_ANSI_P), "q": UInt16(kVK_ANSI_Q), "r": UInt16(kVK_ANSI_R),
            "s": UInt16(kVK_ANSI_S), "t": UInt16(kVK_ANSI_T), "u": UInt16(kVK_ANSI_U),
            "v": UInt16(kVK_ANSI_V), "w": UInt16(kVK_ANSI_W), "x": UInt16(kVK_ANSI_X),
            "y": UInt16(kVK_ANSI_Y), "z": UInt16(kVK_ANSI_Z),
            "0": UInt16(kVK_ANSI_0), "1": UInt16(kVK_ANSI_1), "2": UInt16(kVK_ANSI_2),
            "3": UInt16(kVK_ANSI_3), "4": UInt16(kVK_ANSI_4), "5": UInt16(kVK_ANSI_5),
            "6": UInt16(kVK_ANSI_6), "7": UInt16(kVK_ANSI_7), "8": UInt16(kVK_ANSI_8),
            "9": UInt16(kVK_ANSI_9),
            "space": UInt16(kVK_Space), "return": UInt16(kVK_Return), "enter": UInt16(kVK_Return),
            "tab": UInt16(kVK_Tab), "escape": UInt16(kVK_Escape), "esc": UInt16(kVK_Escape),
            "delete": UInt16(kVK_Delete), "backspace": UInt16(kVK_Delete),
            "up": UInt16(kVK_UpArrow), "down": UInt16(kVK_DownArrow),
            "left": UInt16(kVK_LeftArrow), "right": UInt16(kVK_RightArrow),
            "f1": UInt16(kVK_F1), "f2": UInt16(kVK_F2), "f3": UInt16(kVK_F3),
            "f4": UInt16(kVK_F4), "f5": UInt16(kVK_F5), "f6": UInt16(kVK_F6),
            "f7": UInt16(kVK_F7), "f8": UInt16(kVK_F8), "f9": UInt16(kVK_F9),
            "f10": UInt16(kVK_F10), "f11": UInt16(kVK_F11), "f12": UInt16(kVK_F12),
        ]
        return keyMap[string.lowercased()]
    }

    private static func stringForKeyCode(_ keyCode: UInt16) -> String? {
        let keyMap: [UInt16: String] = [
            UInt16(kVK_ANSI_A): "a", UInt16(kVK_ANSI_B): "b", UInt16(kVK_ANSI_C): "c",
            UInt16(kVK_ANSI_D): "d", UInt16(kVK_ANSI_E): "e", UInt16(kVK_ANSI_F): "f",
            UInt16(kVK_ANSI_G): "g", UInt16(kVK_ANSI_H): "h", UInt16(kVK_ANSI_I): "i",
            UInt16(kVK_ANSI_J): "j", UInt16(kVK_ANSI_K): "k", UInt16(kVK_ANSI_L): "l",
            UInt16(kVK_ANSI_M): "m", UInt16(kVK_ANSI_N): "n", UInt16(kVK_ANSI_O): "o",
            UInt16(kVK_ANSI_P): "p", UInt16(kVK_ANSI_Q): "q", UInt16(kVK_ANSI_R): "r",
            UInt16(kVK_ANSI_S): "s", UInt16(kVK_ANSI_T): "t", UInt16(kVK_ANSI_U): "u",
            UInt16(kVK_ANSI_V): "v", UInt16(kVK_ANSI_W): "w", UInt16(kVK_ANSI_X): "x",
            UInt16(kVK_ANSI_Y): "y", UInt16(kVK_ANSI_Z): "z",
            UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1", UInt16(kVK_ANSI_2): "2",
            UInt16(kVK_ANSI_3): "3", UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5",
            UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7", UInt16(kVK_ANSI_8): "8",
            UInt16(kVK_ANSI_9): "9",
            UInt16(kVK_Space): "space", UInt16(kVK_Return): "return",
            UInt16(kVK_Tab): "tab", UInt16(kVK_Escape): "escape",
            UInt16(kVK_Delete): "delete",
            UInt16(kVK_UpArrow): "up", UInt16(kVK_DownArrow): "down",
            UInt16(kVK_LeftArrow): "left", UInt16(kVK_RightArrow): "right",
            UInt16(kVK_F1): "f1", UInt16(kVK_F2): "f2", UInt16(kVK_F3): "f3",
            UInt16(kVK_F4): "f4", UInt16(kVK_F5): "f5", UInt16(kVK_F6): "f6",
            UInt16(kVK_F7): "f7", UInt16(kVK_F8): "f8", UInt16(kVK_F9): "f9",
            UInt16(kVK_F10): "f10", UInt16(kVK_F11): "f11", UInt16(kVK_F12): "f12",
        ]
        return keyMap[keyCode]
    }
}

// MARK: - ConfigManager

@MainActor
class ConfigManager: ObservableObject {
    static let shared = ConfigManager()

    @Published var config: AppConfig

    private let logger = Logger(subsystem: "com.paradict", category: "ConfigManager")
    private var configURL: URL
    private var fileWatcher: DispatchSourceFileSystemObject?

    /// Flag to prevent recursive updates when syncing config ↔ subsystems
    private var isApplyingConfig = false

    private init() {
        // Set up config file path
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appDir = appSupport.appendingPathComponent("ParaDict", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        self.configURL = appDir.appendingPathComponent("config.yaml")
        self.config = AppConfig.default

        loadConfig()
        setupFileWatcher()
    }

    // MARK: - Load/Save

    func loadConfig() {
        do {
            if FileManager.default.fileExists(atPath: configURL.path) {
                let yamlString = try String(contentsOf: configURL, encoding: .utf8)
                let decoder = YAMLDecoder()
                config = try decoder.decode(AppConfig.self, from: yamlString)
                logger.notice("Config loaded successfully")

                // Migrate: add any missing shortcut modes from defaults
                migrateShortcuts()
            } else {
                // Create default config file
                saveConfig()
                logger.notice("Created default config file")
            }
            applyConfigToSubsystems()
        } catch {
            logger.error("Failed to load config: \(error.localizedDescription)")
            config = AppConfig.default
            applyConfigToSubsystems()
        }
    }

    /// Add any missing shortcut modes from default config (for migration)
    private func migrateShortcuts() {
        let defaultShortcuts = AppConfig.default.shortcuts
        var needsSave = false

        for defaultShortcut in defaultShortcuts {
            // Check if this mode exists in current config
            if !config.shortcuts.contains(where: { $0.mode == defaultShortcut.mode }) {
                // Add the missing shortcut (without a key binding - user will set it)
                var newShortcut = defaultShortcut
                newShortcut.shortcut = nil  // Don't auto-assign a shortcut
                config.shortcuts.append(newShortcut)
                logger.notice("Migrated missing shortcut: \(defaultShortcut.name) (mode: \(defaultShortcut.mode.rawValue))")
                needsSave = true
            }
        }

        if needsSave {
            saveConfig()
        }
    }

    func saveConfig() {
        do {
            let encoder = YAMLEncoder()
            let yamlString = try encoder.encode(config)
            try yamlString.write(to: configURL, atomically: true, encoding: .utf8)
            logger.notice("Config saved successfully")
        } catch {
            logger.error("Failed to save config: \(error.localizedDescription)")
        }
    }

    func getConfigYAML() -> String {
        do {
            let encoder = YAMLEncoder()
            return try encoder.encode(config)
        } catch {
            return "# Error encoding config"
        }
    }

    func updateFromYAML(_ yamlString: String) throws {
        let decoder = YAMLDecoder()
        config = try decoder.decode(AppConfig.self, from: yamlString)
        saveConfig()
        applyConfigToSubsystems()
    }

    // MARK: - Apply Config to Subsystems

    /// Apply config settings to KeyboardShortcuts and AudioDeviceManager
    func applyConfigToSubsystems() {
        guard !isApplyingConfig else { return }
        isApplyingConfig = true
        defer { isApplyingConfig = false }

        logger.notice("Applying config to subsystems...")

        // Notify HotkeyManager to reconfigure shortcuts
        NotificationCenter.default.post(name: .configDidChange, object: nil)

        // Apply audio device
        applyAudioDevice()

        logger.notice("Config applied to subsystems")
    }

    private func applyAudioDevice() {
        let deviceUID = config.audio.device
        let audioManager = AudioDeviceManager.shared

        if deviceUID == "system_default" {
            if audioManager.selectedDeviceUID != nil {
                audioManager.useSystemDefault()
            }
        } else {
            if audioManager.selectedDeviceUID != deviceUID {
                audioManager.selectDevice(uid: deviceUID)
            }
        }
    }

    /// Call this when audio device selection changes in UI
    func syncAudioDeviceFromUI() {
        guard !isApplyingConfig else { return }

        let audioManager = AudioDeviceManager.shared
        let newDevice = audioManager.selectedDeviceUID ?? "system_default"

        if config.audio.device != newDevice {
            config.audio.device = newDevice
            logger.notice("Synced audio device from UI: \(newDevice)")
            saveConfig()
        }
    }

    // MARK: - File Watcher

    private func setupFileWatcher() {
        let fileDescriptor = open(configURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        fileWatcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: .main
        )

        fileWatcher?.setEventHandler { [weak self] in
            self?.loadConfig()
        }

        fileWatcher?.setCancelHandler {
            close(fileDescriptor)
        }

        fileWatcher?.resume()
    }

    // MARK: - Accessors

    var configFilePath: String {
        configURL.path
    }

    /// Get shortcut config by name
    func shortcut(named name: String) -> ShortcutConfig? {
        config.shortcuts.first { $0.name == name }
    }

    /// Get the prompt content for a shortcut (loads from file)
    func promptForShortcut(_ shortcutConfig: ShortcutConfig) -> String? {
        guard let promptFile = shortcutConfig.promptFile else { return nil }
        return PromptManager.shared.loadPrompt(named: promptFile)
    }
}

// MARK: - Notification for config changes

extension Notification.Name {
    static let configDidChange = Notification.Name("configDidChange")
}
