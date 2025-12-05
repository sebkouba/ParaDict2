import SwiftUI
import KeyboardShortcuts
import AVFoundation
import os

private let logger = Logger(subsystem: "com.paradict", category: "App")

extension KeyboardShortcuts.Name {
    static let localDictation = Self("localDictation")
    static let enhancedDictation = Self("enhancedDictation")
    static let replyDictation = Self("replyDictation")
    static let commandDictation = Self("commandDictation")
}

/// Menu bar flash state for visual feedback
enum MenuBarFlashState {
    case normal
    case success
    case error
}

@main
struct ParaDictApp: App {
    @StateObject private var configManager = ConfigManager.shared
    @StateObject private var dictationCoordinator = DictationCoordinator.shared
    @StateObject private var menuBarManager = MenuBarManager()
    @StateObject private var permissionManager = PermissionManager.shared

    @State private var showMenuBarIcon = true
    @State private var menuBarFlashState: MenuBarFlashState = .normal

    init() {
        logger.notice("ParaDict initializing...")

        // Initialize PromptManager to copy bundled prompts
        _ = PromptManager.shared

        // Shortcuts are now managed by ConfigManager - it loads from config.yaml
        // and applies them during its initialization

        // Request microphone permission early (on next run loop to avoid init issues)
        DispatchQueue.main.async {
            let manager = PermissionManager.shared
            if manager.audioPermissionStatus == .notDetermined {
                logger.notice("Audio permission not determined - requesting on startup...")
                manager.requestAudioPermission()
            }
        }

        // Start directory watcher if enabled
        DispatchQueue.main.async {
            let config = ConfigManager.shared.config.directoryWatcher
            if config.enabled && !config.inputDirectory.isEmpty && !config.outputDirectory.isEmpty {
                logger.notice("Starting directory watcher on launch...")
                DirectoryWatcherService.shared.start(
                    inputDir: URL(fileURLWithPath: config.inputDirectory),
                    outputDir: URL(fileURLWithPath: config.outputDirectory)
                )
            }
        }

        // Preload ASR models in background to avoid UI blocking on first transcription
        DispatchQueue.main.async {
            logger.notice("Preloading ASR models...")
            ParakeetTranscriptionService.shared.preloadModels()
        }

        logger.notice("ParaDict initialization complete")
    }

    var body: some Scene {
        // Main window for settings
        WindowGroup {
            MainContentView()
                .environmentObject(configManager)
                .environmentObject(dictationCoordinator)
                .environmentObject(menuBarManager)
                .frame(minWidth: 600, minHeight: 500)
                .onReceive(NotificationCenter.default.publisher(for: .menuBarFlash)) { notification in
                    guard let success = notification.userInfo?["success"] as? Bool else { return }
                    menuBarFlashState = success ? .success : .error

                    // Reset after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        menuBarFlashState = .normal
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        // Menu bar extra - following VoiceInk's exact pattern
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarView()
                .environmentObject(configManager)
                .environmentObject(dictationCoordinator)
                .environmentObject(menuBarManager)
        } label: {
            Image(systemName: menuBarIconName)
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarIconName: String {
        // Flash state takes priority
        switch menuBarFlashState {
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "xmark.circle.fill"
        case .normal:
            break
        }

        // Normal state based on dictation state
        switch dictationCoordinator.state {
        case .idle:
            return "waveform"
        case .recording:
            return "waveform.circle.fill"
        case .transcribing:
            return "text.bubble"
        case .enhancing:
            return "sparkles"
        case .pasting:
            return "doc.on.clipboard"
        case .executingCommand:
            return "terminal"
        case .error:
            return "exclamationmark.triangle"
        }
    }
}

struct MainContentView: View {
    @EnvironmentObject var configManager: ConfigManager
    @EnvironmentObject var dictationCoordinator: DictationCoordinator
    @EnvironmentObject var menuBarManager: MenuBarManager

    var body: some View {
        TabView {
            PermissionsView()
                .tabItem {
                    Label("Permissions", systemImage: "shield.lefthalf.filled")
                }

            AudioInputView()
                .tabItem {
                    Label("Audio", systemImage: "mic")
                }

            ShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            LLMSettingsView()
                .environmentObject(configManager)
                .tabItem {
                    Label("LLM", systemImage: "sparkles")
                }

            ChatSettingsView()
                .environmentObject(configManager)
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right")
                }

            DirectoryWatcherView()
                .environmentObject(configManager)
                .tabItem {
                    Label("Watcher", systemImage: "folder.badge.gearshape")
                }
        }
        .padding()
    }
}
