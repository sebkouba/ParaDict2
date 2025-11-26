import Foundation
import Combine
import Yams
import os

struct AppConfig: Codable {
    var app: AppSettings
    var audio: AudioSettings
    var llm: LLMSettings
    var hotkeys: [HotkeyConfig]
    var customVocabulary: [String]

    enum CodingKeys: String, CodingKey {
        case app, audio, llm, hotkeys
        case customVocabulary = "custom_vocabulary"
    }

    static var `default`: AppConfig {
        AppConfig(
            app: AppSettings(),
            audio: AudioSettings(),
            llm: LLMSettings(),
            hotkeys: [
                HotkeyConfig(shortcut: .rightOption, mode: .local, prompt: nil),
                HotkeyConfig(shortcut: .rightCommand, mode: .enhanced, prompt: "Clean up this transcription. Fix grammar, punctuation, and formatting. Output only the cleaned text.")
            ],
            customVocabulary: ["Parakeet", "Groq"]
        )
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
    var model: String = "kimi-k2"
    var apiKeyEnv: String = "GROQ_API_KEY"

    enum CodingKeys: String, CodingKey {
        case provider, model
        case apiKeyEnv = "api_key_env"
    }
}

enum HotkeyShortcut: String, Codable, CaseIterable {
    case rightOption = "right_option"
    case leftOption = "left_option"
    case rightCommand = "right_command"
    case leftCommand = "left_command"
    case rightControl = "right_control"
    case leftControl = "left_control"
    case rightShift = "right_shift"
    case fn = "fn"
    case custom = "custom"

    var keyCode: UInt16? {
        switch self {
        case .rightOption: return 0x3D
        case .leftOption: return 0x3A
        case .leftControl: return 0x3B
        case .rightControl: return 0x3E
        case .fn: return 0x3F
        case .rightCommand: return 0x36
        case .leftCommand: return 0x37
        case .rightShift: return 0x3C
        case .custom: return nil
        }
    }

    var displayName: String {
        switch self {
        case .rightOption: return "Right Option (⌥)"
        case .leftOption: return "Left Option (⌥)"
        case .rightCommand: return "Right Command (⌘)"
        case .leftCommand: return "Left Command (⌘)"
        case .rightControl: return "Right Control (⌃)"
        case .leftControl: return "Left Control (⌃)"
        case .rightShift: return "Right Shift (⇧)"
        case .fn: return "Fn"
        case .custom: return "Custom"
        }
    }
}

enum DictationMode: String, Codable {
    case local      // Parakeet only
    case enhanced   // Parakeet + LLM
}

struct HotkeyConfig: Codable, Identifiable {
    var id: String { shortcut.rawValue }
    var shortcut: HotkeyShortcut
    var mode: DictationMode
    var prompt: String?
}

@MainActor
class ConfigManager: ObservableObject {
    static let shared = ConfigManager()

    @Published var config: AppConfig

    private let logger = Logger(subsystem: "com.paradict", category: "ConfigManager")
    private var configURL: URL
    private var fileWatcher: DispatchSourceFileSystemObject?

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

    func loadConfig() {
        do {
            if FileManager.default.fileExists(atPath: configURL.path) {
                let yamlString = try String(contentsOf: configURL, encoding: .utf8)
                let decoder = YAMLDecoder()
                config = try decoder.decode(AppConfig.self, from: yamlString)
                logger.info("Config loaded successfully")
            } else {
                // Create default config file
                saveConfig()
                logger.info("Created default config file")
            }
        } catch {
            logger.error("Failed to load config: \(error.localizedDescription)")
            config = AppConfig.default
        }
    }

    func saveConfig() {
        do {
            let encoder = YAMLEncoder()
            let yamlString = try encoder.encode(config)
            try yamlString.write(to: configURL, atomically: true, encoding: .utf8)
            logger.info("Config saved successfully")
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
    }

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

    var configFilePath: String {
        configURL.path
    }

    func hotkeyConfig(for shortcut: HotkeyShortcut) -> HotkeyConfig? {
        config.hotkeys.first { $0.shortcut == shortcut }
    }

    var apiKey: String? {
        ProcessInfo.processInfo.environment[config.llm.apiKeyEnv]
    }
}
