import SwiftUI
import KeyboardShortcuts
import AVFoundation
import os

private let logger = Logger(subsystem: "com.paradict", category: "App")

extension KeyboardShortcuts.Name {
    static let localDictation = Self("localDictation")
    static let enhancedDictation = Self("enhancedDictation")
    static let replyDictation = Self("replyDictation")
    // Future shortcuts can be added here (e.g., customDictation1, customDictation2)
}

@main
struct ParaDictApp: App {
    @StateObject private var configManager = ConfigManager.shared
    @StateObject private var dictationManager = DictationManager.shared
    @StateObject private var menuBarManager = MenuBarManager()
    @StateObject private var permissionManager = PermissionManager.shared

    @State private var showMenuBarIcon = true

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

        logger.notice("ParaDict initialization complete")
    }

    var body: some Scene {
        // Main window for settings
        WindowGroup {
            MainContentView()
                .environmentObject(configManager)
                .environmentObject(dictationManager)
                .environmentObject(menuBarManager)
                .frame(minWidth: 600, minHeight: 500)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        // Menu bar extra - following VoiceInk's exact pattern
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarView()
                .environmentObject(configManager)
                .environmentObject(dictationManager)
                .environmentObject(menuBarManager)
        } label: {
            Image(systemName: menuBarIconName)
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarIconName: String {
        switch dictationManager.state {
        case .idle:
            return "waveform"
        case .recording:
            return "waveform.circle.fill"
        case .transcribing:
            return "text.bubble"
        case .enhancing:
            return "sparkles"
        case .error:
            return "exclamationmark.triangle"
        }
    }
}

struct MainContentView: View {
    @EnvironmentObject var configManager: ConfigManager
    @EnvironmentObject var dictationManager: DictationManager
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
        }
        .padding()
    }
}

struct ShortcutsSettingsView: View {
    @EnvironmentObject var configManager: ConfigManager
    // Timer to periodically sync shortcuts (Recorder widget doesn't have a callback)
    @State private var syncTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Keyboard Shortcuts")
                .font(.title2)
                .fontWeight(.bold)

            GroupBox("Local Dictation") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Records and transcribes using Parakeet (no LLM)")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    KeyboardShortcuts.Recorder("Shortcut:", name: .localDictation)
                }
                .padding(.vertical, 8)
            }

            GroupBox("Enhanced Dictation") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Records, transcribes, then processes with LLM")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    KeyboardShortcuts.Recorder("Shortcut:", name: .enhancedDictation)

                    Divider()

                    // Show current prompt file
                    if let enhancedConfig = configManager.config.shortcuts.first(where: { $0.mode == .enhanced }) {
                        HStack {
                            Text("Prompt file:")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text(enhancedConfig.promptFile ?? "none")
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            GroupBox("Reply Dictation") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Copy text, click target field, press shortcut and speak to generate a response")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    KeyboardShortcuts.Recorder("Shortcut:", name: .replyDictation)

                    Divider()

                    // Show current prompt file
                    if let replyConfig = configManager.config.shortcuts.first(where: { $0.mode == .reply }) {
                        HStack {
                            Text("Prompt file:")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text(replyConfig.promptFile ?? "none")
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Text("Configure prompts and LLM settings in the LLM tab.")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
        .onAppear {
            // Start a timer to periodically sync shortcuts to config
            // (KeyboardShortcuts.Recorder doesn't have a change callback)
            syncTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                Task { @MainActor in
                    HotkeyManager.shared.syncShortcutsToConfig()
                }
            }
        }
        .onDisappear {
            syncTimer?.invalidate()
            syncTimer = nil
            // Final sync when leaving the view
            Task { @MainActor in
                HotkeyManager.shared.syncShortcutsToConfig()
            }
        }
    }
}
