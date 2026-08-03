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
    private var isDuplicateInstance = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        isDuplicateInstance = ApplicationInstanceService.shared.shouldTerminateCurrentInstance()

        if isDuplicateInstance {
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isDuplicateInstance else { return }

        logger.notice("AppDelegate: applicationDidFinishLaunching")

        // Run settings migration from old YAML config (if exists)
        SettingsMigration.migrateIfNeeded()

        // Initialize PromptManager to copy bundled prompts
        _ = PromptManager.shared

        // Request microphone permission early
        let manager = PermissionManager.shared
        if manager.audioPermissionStatus == .notDetermined {
            logger.notice("Audio permission not determined - requesting on startup...")
            manager.requestAudioPermission()
        }

        // Start directory watcher if enabled
        let watcherEnabled = UserDefaults.standard.bool(forKey: SettingsKeys.directoryWatcherEnabled)
        let inputDir = UserDefaults.standard.string(forKey: SettingsKeys.directoryWatcherInput) ?? ""
        let outputDir = UserDefaults.standard.string(forKey: SettingsKeys.directoryWatcherOutput) ?? ""
        if watcherEnabled && !inputDir.isEmpty && !outputDir.isEmpty {
            logger.notice("Starting directory watcher on launch...")
            DirectoryWatcherService.shared.start(
                inputDir: URL(fileURLWithPath: inputDir),
                outputDir: URL(fileURLWithPath: outputDir)
            )
        }

        // Preload ASR models in background to avoid UI blocking on first transcription
        logger.notice("Preloading ASR models...")
        ParakeetTranscriptionService.shared.preloadModels()

        // Setup status bar controller (NSStatusItem with NSMenu)
        statusBarController = StatusBarController()
        statusBarController?.setup(
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

    @StateObject private var dictationCoordinator = DictationCoordinator.shared
    @StateObject private var menuBarManager = MenuBarManager.shared
    @StateObject private var permissionManager = PermissionManager.shared
    @StateObject private var betaExpirationManager = BetaExpirationManager.shared

    var body: some Scene {
        // Main window for settings
        WindowGroup {
            if betaExpirationManager.canUseApp {
                MainContentView()
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

            TranscriptionSettingsView()
                .tabItem {
                    Label("Transcription", systemImage: "waveform")
                }

            DictationHistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

            ShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            LLMSettingsView()
                .tabItem {
                    Label("LLM", systemImage: "sparkles")
                }

            DirectoryWatcherView()
                .tabItem {
                    Label("Watcher", systemImage: "folder.badge.gearshape")
                }

            AdvancedSettingsView()
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
