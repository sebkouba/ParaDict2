import SwiftUI

struct DirectoryWatcherView: View {
    @EnvironmentObject var configManager: ConfigManager
    @ObservedObject private var watcherService = DirectoryWatcherService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 24) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)
                        .padding(20)
                        .background(Circle().fill(Color(NSColor.windowBackgroundColor).opacity(0.9)))

                    VStack(spacing: 8) {
                        Text("Directory Watcher")
                            .font(.system(size: 28, weight: .bold))
                        Text("Automatically transcribe audio files dropped into a folder")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
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
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(16)

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
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(16)

                // Supported Formats
                VStack(alignment: .leading, spacing: 12) {
                    Text("Supported Formats")
                        .font(.headline)

                    Text("WAV, MP3, M4A, AAC, FLAC, OGG, WMA")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("Non-WAV files will be automatically converted using ffmpeg")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(16)

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
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(16)
                }

                // Advanced Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Advanced")
                        .font(.headline)

                    Button("Clear Processed Files History") {
                        watcherService.clearProcessedFiles()
                    }
                    .buttonStyle(.bordered)

                    Text("This will allow all files to be reprocessed on next scan")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(16)
            }
            .padding(24)
        }
        .background(Color(NSColor.controlBackgroundColor))
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
            if !watcherService.isRunning {
                watcherService.start(
                    inputDir: URL(fileURLWithPath: config.inputDirectory),
                    outputDir: URL(fileURLWithPath: config.outputDirectory)
                )
            }
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

                Text(activity.timestamp, style: .relative)
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
