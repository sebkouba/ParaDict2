import SwiftUI

struct DirectoryWatcherView: View {
    @EnvironmentObject var configManager: ConfigManager
    @ObservedObject private var watcherService = DirectoryWatcherService.shared
    @State private var markedFilesMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 24) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.accentColor)
                        .padding(20)
                        .background(
                            Circle()
                                .fill(Color(NSColor.controlBackgroundColor))
                        )

                    VStack(spacing: 8) {
                        Text("Directory Watcher")
                            .font(.system(size: 28, weight: .bold))
                        Text("Automatically transcribe audio files dropped into a folder")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.vertical, 40)

                // Enable/Status Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Enable Watcher")
                            .font(.headline)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { configManager.config.directoryWatcher.enabled },
                            set: { newValue in
                                configManager.config.directoryWatcher.enabled = newValue
                                configManager.saveConfig()
                                updateWatcherState()
                            }
                        ))
                        .toggleStyle(.switch)
                    }

                    // Status indicator
                    HStack(spacing: 8) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 10, height: 10)
                        Text(statusText)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    // Processing indicator with cancel button
                    if let filename = watcherService.currentlyProcessing {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Transcribing: \(filename)")
                                        .font(.subheadline)
                                        .foregroundColor(.blue)
                                    if watcherService.pendingFilesCount > 0 {
                                        Text("\(watcherService.pendingFilesCount) more file\(watcherService.pendingFilesCount == 1 ? "" : "s") pending")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Button("Cancel") {
                                    watcherService.cancelProcessing()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }

                    if let error = watcherService.lastError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

                // Directories Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Directories")
                        .font(.headline)

                    // Input Directory
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Input Folder")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        HStack {
                            Text(inputDirectoryDisplay)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundColor(configManager.config.directoryWatcher.inputDirectory.isEmpty ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button("Browse...") {
                                selectInputDirectory()
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(12)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)

                        Text("Audio files in this folder will be transcribed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Output Directory
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Output Folder")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        HStack {
                            Text(outputDirectoryDisplay)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundColor(configManager.config.directoryWatcher.outputDirectory.isEmpty ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button("Browse...") {
                                selectOutputDirectory()
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(12)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)

                        Text("Transcription text files will be saved here")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

                // Supported Formats
                VStack(alignment: .leading, spacing: 12) {
                    Text("Supported Formats")
                        .font(.headline)

                    Text("WAV, MP3, M4A, AAC, FLAC, OGG, WMA")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("Non-WAV files will be automatically converted")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

                // Recent Activity Section
                if !watcherService.recentActivity.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Recent Activity")
                                .font(.headline)
                            Spacer()
                            Button("Clear") {
                                watcherService.clearActivity()
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(.secondary)
                        }

                        ForEach(watcherService.recentActivity) { activity in
                            ActivityRow(activity: activity)
                        }
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                }

                // Advanced Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Advanced")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        Button("Skip Existing Files") {
                            // Pass directory from config since watcher may not be started
                            let inputPath = configManager.config.directoryWatcher.inputDirectory
                            let inputDir = inputPath.isEmpty ? nil : URL(fileURLWithPath: inputPath)
                            let count = watcherService.markAllAsProcessed(inputDir: inputDir)
                            if count > 0 {
                                markedFilesMessage = "Marked \(count) file\(count == 1 ? "" : "s") as processed"
                            } else {
                                markedFilesMessage = "No new files to mark"
                            }
                            // Clear message after delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                markedFilesMessage = nil
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(configManager.config.directoryWatcher.inputDirectory.isEmpty)

                        Text("Mark all current files as already processed (only transcribe new files)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if let message = markedFilesMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Button("Clear Processed Files History") {
                            watcherService.clearProcessedFiles()
                        }
                        .buttonStyle(.bordered)

                        Text("This will allow all files to be reprocessed on next scan")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            updateWatcherState()
        }
    }

    // MARK: - Computed Properties

    private var statusColor: Color {
        if watcherService.isRunning {
            return .green
        } else if configManager.config.directoryWatcher.enabled {
            return .orange
        } else {
            return .gray
        }
    }

    private var statusText: String {
        if watcherService.isRunning {
            return "Watching for new audio files..."
        } else if configManager.config.directoryWatcher.enabled {
            return "Enabled but not running (check configuration)"
        } else {
            return "Stopped"
        }
    }

    private var inputDirectoryDisplay: String {
        let path = configManager.config.directoryWatcher.inputDirectory
        return path.isEmpty ? "Not configured" : path
    }

    private var outputDirectoryDisplay: String {
        let path = configManager.config.directoryWatcher.outputDirectory
        return path.isEmpty ? "Not configured" : path
    }

    // MARK: - Actions

    private func selectInputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select folder to watch for audio files"
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            configManager.config.directoryWatcher.inputDirectory = url.path
            configManager.saveConfig()
            updateWatcherState()
        }
    }

    private func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Select folder for transcription output"
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            configManager.config.directoryWatcher.outputDirectory = url.path
            configManager.saveConfig()
            updateWatcherState()
        }
    }

    private func updateWatcherState() {
        let config = configManager.config.directoryWatcher

        if config.enabled && !config.inputDirectory.isEmpty && !config.outputDirectory.isEmpty {
            // Always restart to pick up any directory changes
            watcherService.restart(
                inputDir: URL(fileURLWithPath: config.inputDirectory),
                outputDir: URL(fileURLWithPath: config.outputDirectory)
            )
        } else {
            if watcherService.isRunning {
                watcherService.stop()
            }
        }
    }
}

// MARK: - Activity Row

struct ActivityRow: View {
    let activity: WatcherActivity

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: activity.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(activity.success ? .green : .red)

            VStack(alignment: .leading, spacing: 2) {
                if activity.success, let output = activity.outputFilename {
                    Text("\(activity.filename) → \(output)")
                        .font(.system(.caption, design: .monospaced))
                } else {
                    Text(activity.filename)
                        .font(.system(.caption, design: .monospaced))
                }

                if let error = activity.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                }

                Text(activity.formattedDuration)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(8)
        .background(Color(NSColor.textBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }
}

#Preview {
    DirectoryWatcherView()
        .environmentObject(ConfigManager.shared)
}
