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

        // Apply initial activation policy
        MenuBarManager.shared.applyActivationPolicy()

        logger.notice("AppDelegate: initialization complete")
    }

    /// Called when user clicks the dock icon or activates the app when no windows are visible.
    /// Return true to let macOS/SwiftUI create a new window automatically.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        logger.notice("applicationShouldHandleReopen: hasVisibleWindows=\(flag)")

        if !flag && !MenuBarManager.shared.isMenuBarOnly {
            // No visible windows and not in menu-bar-only mode
            // Try to show existing window first
            if WindowManager.shared.showMainWindow() != nil {
                return false // We handled it
            }
        }
        // Return true to let macOS create a new window via SwiftUI WindowGroup
        return true
    }

    /// Don't quit when the last window is closed - we're a menu bar app
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

@main
struct ParaDictApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var configManager = ConfigManager.shared
    @StateObject private var dictationCoordinator = DictationCoordinator.shared
    @StateObject private var menuBarManager = MenuBarManager.shared
    @StateObject private var permissionManager = PermissionManager.shared
    @StateObject private var betaExpirationManager = BetaExpirationManager.shared

    var body: some Scene {
        // Main window for settings
        WindowGroup {
            if betaExpirationManager.canUseApp {
                MainContentView()
                    .environmentObject(configManager)
                    .environmentObject(dictationCoordinator)
                    .environmentObject(menuBarManager)
                    .environmentObject(betaExpirationManager)
                    .frame(minWidth: 600, minHeight: 500)
            } else {
                BetaExpiredBlockingView()
                    .environmentObject(betaExpirationManager)
            }
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

            AdvancedSettingsView()
                .environmentObject(configManager)
                .tabItem {
                    Label("Advanced", systemImage: "gearshape.2")
                }

            BetaLicenseView()
                .tabItem {
                    Label("License", systemImage: "key")
                }
        }
        .padding()
        .background(WindowAccessor { window in
            WindowManager.shared.configureWindow(window)
        })
    }
}
