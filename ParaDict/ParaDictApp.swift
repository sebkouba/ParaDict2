import SwiftUI
import KeyboardShortcuts
import os

private let logger = Logger(subsystem: "com.paradict", category: "App")

extension KeyboardShortcuts.Name {
    static let localDictation = Self("localDictation")
    static let enhancedDictation = Self("enhancedDictation")
}

@main
struct ParaDictApp: App {
    @StateObject private var configManager = ConfigManager.shared
    @StateObject private var dictationManager = DictationManager.shared
    @StateObject private var menuBarManager = MenuBarManager()

    @State private var showMenuBarIcon = true

    init() {
        logger.info("ParaDict initializing...")

        // Set up default keyboard shortcuts if not already set
        if KeyboardShortcuts.getShortcut(for: .localDictation) == nil {
            logger.info("Setting default local dictation shortcut: Ctrl+Cmd+T")
            KeyboardShortcuts.setShortcut(.init(.t, modifiers: [.control, .command]), for: .localDictation)
        } else {
            logger.info("Local dictation shortcut already configured")
        }

        logger.info("ParaDict initialization complete")
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
                }
                .padding(.vertical, 8)
            }

            Spacer()
        }
        .padding()
    }
}
