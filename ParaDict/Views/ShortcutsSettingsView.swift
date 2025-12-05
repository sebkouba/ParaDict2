import SwiftUI
import KeyboardShortcuts

struct ShortcutsSettingsView: View {
    @EnvironmentObject var configManager: ConfigManager
    @State private var syncTimer: Timer?
    @State private var editingPrompt: String?
    @State private var hoveredPrompt: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.accentColor)
                        .padding(20)
                        .background(
                            Circle()
                                .fill(Color(NSColor.controlBackgroundColor))
                        )

                    VStack(spacing: 8) {
                        Text("Keyboard Shortcuts")
                            .font(.system(size: 28, weight: .bold))
                        Text("Configure hotkeys for different dictation modes")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.vertical, 24)

                // Shortcut Cards
                VStack(spacing: 16) {
                    // Local Dictation
                    ShortcutCard(
                        title: "Local Dictation",
                        description: "Records and transcribes using Parakeet (no LLM)",
                        shortcutName: .localDictation,
                        promptFile: nil,
                        hoveredPrompt: $hoveredPrompt,
                        editingPrompt: $editingPrompt
                    )

                    // Enhanced Dictation
                    ShortcutCard(
                        title: "Enhanced Dictation",
                        description: "Records, transcribes, then processes with LLM",
                        shortcutName: .enhancedDictation,
                        promptFile: configManager.config.shortcuts.first(where: { $0.mode == .enhanced })?.promptFile,
                        hoveredPrompt: $hoveredPrompt,
                        editingPrompt: $editingPrompt
                    )

                    // Reply Dictation
                    ShortcutCard(
                        title: "Reply Dictation",
                        description: "Copy text, click target field, press shortcut and speak to generate a response",
                        shortcutName: .replyDictation,
                        promptFile: configManager.config.shortcuts.first(where: { $0.mode == .reply })?.promptFile,
                        hoveredPrompt: $hoveredPrompt,
                        editingPrompt: $editingPrompt
                    )

                    // Command Dictation
                    ShortcutCard(
                        title: "Command Dictation",
                        description: "Execute voice commands like 'open Parakeet' to launch projects",
                        shortcutName: .commandDictation,
                        promptFile: configManager.config.shortcuts.first(where: { $0.mode == .command })?.promptFile,
                        hoveredPrompt: $hoveredPrompt,
                        editingPrompt: $editingPrompt
                    )
                }

                // Footer hint
                Text("Configure prompts and LLM settings in the LLM tab.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            syncTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                Task { @MainActor in
                    HotkeyManager.shared.syncShortcutsToConfig()
                }
            }
        }
        .onDisappear {
            syncTimer?.invalidate()
            syncTimer = nil
            Task { @MainActor in
                HotkeyManager.shared.syncShortcutsToConfig()
            }
        }
        .sheet(item: $editingPrompt) { promptName in
            PromptEditorSheet(promptName: promptName, onDismiss: { editingPrompt = nil })
        }
    }
}

// MARK: - Shortcut Card

struct ShortcutCard: View {
    let title: String
    let description: String
    let shortcutName: KeyboardShortcuts.Name
    let promptFile: String?
    @Binding var hoveredPrompt: String?
    @Binding var editingPrompt: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            Text(title)
                .font(.headline)

            // Description
            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Shortcut recorder
            KeyboardShortcuts.Recorder("Shortcut:", name: shortcutName)

            // Prompt file link (if applicable)
            if let promptFile = promptFile {
                PromptFileLink(
                    promptName: promptFile,
                    isHovered: hoveredPrompt == promptFile,
                    onHover: { hoveredPrompt = $0 ? promptFile : nil },
                    onTap: { editingPrompt = promptFile }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
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
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Prompt file")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(promptName)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.primary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isHovered ? .accentColor : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.accentColor.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                onHover(hovering)
            }
        }
    }
}

#Preview {
    ShortcutsSettingsView()
        .environmentObject(ConfigManager.shared)
        .frame(width: 500, height: 700)
}
