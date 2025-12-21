import SwiftUI

struct AdvancedSettingsView: View {
    @EnvironmentObject var configManager: ConfigManager

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 24) {
                    Image(systemName: "gearshape.2.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.accentColor)
                        .padding(20)
                        .background(
                            Circle()
                                .fill(Color(NSColor.controlBackgroundColor))
                        )

                    VStack(spacing: 8) {
                        Text("Advanced")
                            .font(.system(size: 28, weight: .bold))
                        Text("Integration settings and advanced features")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.vertical, 40)

                // Enhancement Timeout
                VStack(alignment: .leading, spacing: 16) {
                    Label("Enhancement Timeout", systemImage: "clock.badge.xmark")
                        .font(.headline)

                    Text("When the LLM takes too long, fall back to the original transcription")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        // Base timeout
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Base Timeout")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(configManager.config.llm.enhancementTimeoutBaseMs) ms")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }

                            Slider(
                                value: Binding(
                                    get: { Double(configManager.config.llm.enhancementTimeoutBaseMs) },
                                    set: { newValue in
                                        configManager.config.llm.enhancementTimeoutBaseMs = Int(newValue)
                                        configManager.saveConfig()
                                    }
                                ),
                                in: 200...3000,
                                step: 100
                            )

                            Text("Minimum timeout before falling back to original transcription")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Divider()

                        // Per-token timeout
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Per-Token Timeout")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(configManager.config.llm.enhancementTimeoutPerTokenMs) ms")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }

                            Slider(
                                value: Binding(
                                    get: { Double(configManager.config.llm.enhancementTimeoutPerTokenMs) },
                                    set: { newValue in
                                        configManager.config.llm.enhancementTimeoutPerTokenMs = Int(newValue)
                                        configManager.saveConfig()
                                    }
                                ),
                                in: 0...50,
                                step: 1
                            )

                            Text("Additional time per ~4 characters of transcription (longer dictations get more time)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Divider()

                        // Example calculation
                        let exampleShort = configManager.config.llm.calculateEnhancementTimeout(forText: String(repeating: "x", count: 50))
                        let exampleMedium = configManager.config.llm.calculateEnhancementTimeout(forText: String(repeating: "x", count: 200))
                        let exampleLong = configManager.config.llm.calculateEnhancementTimeout(forText: String(repeating: "x", count: 500))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Example timeouts:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 16) {
                                Text("~10 words: \(String(format: "%.1f", exampleShort))s")
                                Text("~40 words: \(String(format: "%.1f", exampleMedium))s")
                                Text("~100 words: \(String(format: "%.1f", exampleLong))s")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    )
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

                // Obsidian Integration
                VStack(alignment: .leading, spacing: 16) {
                    Label("Obsidian Integration", systemImage: "link")
                        .font(.headline)

                    Text("Say \"daily\" to open your Obsidian daily note")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        // Enable toggle
                        Toggle(isOn: Binding(
                            get: { configManager.config.obsidian.dailyNoteKeywordEnabled },
                            set: { newValue in
                                configManager.config.obsidian.dailyNoteKeywordEnabled = newValue
                                configManager.saveConfig()
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\"Daily\" keyword enabled")
                                    .font(.body)
                                Text("Say \"daily\" or \"daily note\" to open Obsidian")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .padding(.vertical, 4)

                        Divider()

                        // Vault name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Vault Name")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            HStack {
                                TextField("Leave empty for default vault", text: Binding(
                                    get: { configManager.config.obsidian.vault ?? "" },
                                    set: { newValue in
                                        configManager.config.obsidian.vault = newValue.isEmpty ? nil : newValue
                                        configManager.saveConfig()
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)

                                Button("Browse...") {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = false
                                    panel.canChooseDirectories = true
                                    panel.allowsMultipleSelection = false
                                    panel.message = "Select your Obsidian vault folder"
                                    panel.prompt = "Select Vault"

                                    if panel.runModal() == .OK, let url = panel.url {
                                        // Use the folder name as the vault name
                                        configManager.config.obsidian.vault = url.lastPathComponent
                                        configManager.saveConfig()
                                    }
                                }
                            }

                            Text("The name of your Obsidian vault (folder name). If empty, Obsidian will use the currently open or default vault.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    )
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

#Preview {
    AdvancedSettingsView()
        .environmentObject(ConfigManager.shared)
}
