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

/// App delegate to manage NSStatusItem (traditional AppKit menu bar)
/// Using NSStatusItem instead of SwiftUI MenuBarExtra to avoid ghost window issues
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.notice("AppDelegate: applicationDidFinishLaunching")

        // Initialize PromptManager to copy bundled prompts
        _ = PromptManager.shared

        // Request microphone permission early
        let manager = PermissionManager.shared
        if manager.audioPermissionStatus == .notDetermined {
            logger.notice("Audio permission not determined - requesting on startup...")
            manager.requestAudioPermission()
        }

        // Start directory watcher if enabled
        let config = ConfigManager.shared.config.directoryWatcher
        if config.enabled && !config.inputDirectory.isEmpty && !config.outputDirectory.isEmpty {
            logger.notice("Starting directory watcher on launch...")
            DirectoryWatcherService.shared.start(
                inputDir: URL(fileURLWithPath: config.inputDirectory),
                outputDir: URL(fileURLWithPath: config.outputDirectory)
            )
        }

        // Preload ASR models in background to avoid UI blocking on first transcription
        logger.notice("Preloading ASR models...")
        ParakeetTranscriptionService.shared.preloadModels()

        // Setup status bar controller (NSStatusItem with NSMenu)
        statusBarController = StatusBarController()
        statusBarController?.setup(
            configManager: ConfigManager.shared,
            dictationCoordinator: DictationCoordinator.shared,
            menuBarManager: MenuBarManager.shared
        )

        logger.notice("AppDelegate: initialization complete")
    }
}

@main
struct ParaDictApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var configManager = ConfigManager.shared
    @StateObject private var dictationCoordinator = DictationCoordinator.shared
    @StateObject private var menuBarManager = MenuBarManager.shared
    @StateObject private var permissionManager = PermissionManager.shared

    var body: some Scene {
        // Main window for settings
        WindowGroup {
            MainContentView()
                .environmentObject(configManager)
                .environmentObject(dictationCoordinator)
                .environmentObject(menuBarManager)
                .frame(minWidth: 600, minHeight: 500)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
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
