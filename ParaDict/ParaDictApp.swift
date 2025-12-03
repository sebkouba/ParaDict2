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
        }
        .padding()
    }
}

struct ShortcutsSettingsView: View {
    @EnvironmentObject var configManager: ConfigManager
    // Timer to periodically sync shortcuts (Recorder widget doesn't have a callback)
    @State private var syncTimer: Timer?
    @State private var editingPrompt: String?
    @State private var hoveredPrompt: String?

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
                    if let enhancedConfig = configManager.config.shortcuts.first(where: { $0.mode == .enhanced }),
                       let promptFile = enhancedConfig.promptFile {
                        PromptFileLink(
                            promptName: promptFile,
                            isHovered: hoveredPrompt == promptFile,
                            onHover: { hoveredPrompt = $0 ? promptFile : nil },
                            onTap: { editingPrompt = promptFile }
                        )
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
                    if let replyConfig = configManager.config.shortcuts.first(where: { $0.mode == .reply }),
                       let promptFile = replyConfig.promptFile {
                        PromptFileLink(
                            promptName: promptFile,
                            isHovered: hoveredPrompt == promptFile,
                            onHover: { hoveredPrompt = $0 ? promptFile : nil },
                            onTap: { editingPrompt = promptFile }
                        )
                    }
                }
                .padding(.vertical, 8)
            }

            GroupBox("Command Dictation") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Execute voice commands like 'open Parakeet' to launch projects")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    KeyboardShortcuts.Recorder("Shortcut:", name: .commandDictation)

                    Divider()

                    // Show current prompt file
                    if let commandConfig = configManager.config.shortcuts.first(where: { $0.mode == .command }),
                       let promptFile = commandConfig.promptFile {
                        PromptFileLink(
                            promptName: promptFile,
                            isHovered: hoveredPrompt == promptFile,
                            onHover: { hoveredPrompt = $0 ? promptFile : nil },
                            onTap: { editingPrompt = promptFile }
                        )
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
        .sheet(item: $editingPrompt) { promptName in
            PromptEditorSheet(promptName: promptName, onDismiss: { editingPrompt = nil })
        }
    }
}

// MARK: - Prompt File Link

struct PromptFileLink: View {
    let promptName: String
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text("Prompt file:")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text(promptName)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(isHovered ? .accentColor : .primary)
                    .underline(isHovered)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            onHover(hovering)
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
