import SwiftUI

struct AdvancedSettingsView: View {
    @AppStorage(SettingsKeys.enhancementTimeoutBaseMs) private var enhancementTimeoutBaseMs = SettingsDefaults.enhancementTimeoutBaseMs
    @AppStorage(SettingsKeys.enhancementTimeoutPerTokenMs) private var enhancementTimeoutPerTokenMs = SettingsDefaults.enhancementTimeoutPerTokenMs
    @AppStorage(SettingsKeys.obsidianDailyNoteEnabled) private var obsidianDailyNoteEnabled = SettingsDefaults.obsidianDailyNoteEnabled
    @AppStorage(SettingsKeys.obsidianVault) private var obsidianVault: String = ""
    @AppStorage(SettingsKeys.streamingPreviewPlacement) private var previewPlacement: String = SettingsDefaults.streamingPreviewPlacement
    @AppStorage(SettingsKeys.streamingPreviewCharLimit) private var previewCharLimit: Int = SettingsDefaults.streamingPreviewCharLimit

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

                // Live Preview
                VStack(alignment: .leading, spacing: 16) {
                    Label("Live Preview", systemImage: "text.bubble")
                        .font(.headline)

                    Text("Show a streaming transcription preview while recording")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        // Placement picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Placement")
                                .font(.subheadline)

                            Picker("", selection: $previewPlacement) {
                                ForEach(StreamingPreviewPlacement.allCases, id: \.rawValue) { placement in
                                    Text(placement.displayName).tag(placement.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }

                        if previewPlacement != StreamingPreviewPlacement.disabled.rawValue {
                            Divider()

                            // Character limit slider
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Character Limit")
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(previewCharLimit)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .monospacedDigit()
                                }

                                Slider(
                                    value: Binding(
                                        get: { Double(previewCharLimit) },
                                        set: { previewCharLimit = Int($0) }
                                    ),
                                    in: 50...500,
                                    step: 10
                                )

                                Text("Maximum characters shown in the preview overlay")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
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
                                Text("\(enhancementTimeoutBaseMs) ms")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }

                            Slider(
                                value: Binding(
                                    get: { Double(enhancementTimeoutBaseMs) },
                                    set: { enhancementTimeoutBaseMs = Int($0) }
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
                                Text("\(enhancementTimeoutPerTokenMs) ms")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }

                            Slider(
                                value: Binding(
                                    get: { Double(enhancementTimeoutPerTokenMs) },
                                    set: { enhancementTimeoutPerTokenMs = Int($0) }
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
                        let exampleShort = calculateTimeout(forTextLength: 50)
                        let exampleMedium = calculateTimeout(forTextLength: 200)
                        let exampleLong = calculateTimeout(forTextLength: 500)

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
                        Toggle(isOn: $obsidianDailyNoteEnabled) {
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
                                TextField("Leave empty for default vault", text: $obsidianVault)
                                    .textFieldStyle(.roundedBorder)

                                Button("Browse...") {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = false
                                    panel.canChooseDirectories = true
                                    panel.allowsMultipleSelection = false
                                    panel.message = "Select your Obsidian vault folder"
                                    panel.prompt = "Select Vault"

                                    if panel.runModal() == .OK, let url = panel.url {
                                        obsidianVault = url.lastPathComponent
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

    private func calculateTimeout(forTextLength length: Int) -> TimeInterval {
        let estimatedTokens = max(1, length / 4)
        let timeoutMs = enhancementTimeoutBaseMs + (estimatedTokens * enhancementTimeoutPerTokenMs)
        return TimeInterval(timeoutMs) / 1000.0
    }
}

#Preview {
    AdvancedSettingsView()
}
