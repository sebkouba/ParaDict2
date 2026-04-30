import SwiftUI
import CoreAudio
import AppKit

struct AudioInputView: View {
    @ObservedObject private var deviceManager = AudioDeviceManager.shared
    @AppStorage(SettingsKeys.recordingArchiveEnabled) private var archiveEnabled = SettingsDefaults.recordingArchiveEnabled
    @AppStorage(SettingsKeys.recordingArchiveDirectory) private var archiveDirectory = SettingsDefaults.recordingArchiveDirectory
    @AppStorage(SettingsKeys.recordingArchiveRetentionDays) private var archiveRetentionDays = SettingsDefaults.recordingArchiveRetentionDays
    @State private var orderedDevices: [(id: AudioDeviceID, uid: String, name: String)] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.accentColor)
                        .padding(16)
                        .background(
                            Circle()
                                .fill(Color(NSColor.controlBackgroundColor))
                        )

                    VStack(spacing: 6) {
                        Text("Audio Input")
                            .font(.system(size: 24, weight: .bold))
                        Text("Drag to reorder. First available device is used.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.vertical, 24)

                // Device list
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Priority Order")
                            .font(.headline)
                        Spacer()
                        Button(action: {
                            deviceManager.loadAvailableDevices()
                            updateOrderedDevices()
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Refresh devices")
                    }

                    if orderedDevices.isEmpty {
                        Text("No input devices found")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    } else {
                        List {
                            ForEach(orderedDevices, id: \.uid) { device in
                                DeviceRow(
                                    name: device.name,
                                    isAvailable: deviceManager.isAvailable(uid: device.uid),
                                    isEnabled: deviceManager.isEnabled(uid: device.uid),
                                    onToggle: {
                                        deviceManager.toggleEnabled(uid: device.uid)
                                    }
                                )
                            }
                            .onMove { from, to in
                                // Move in local array first (SwiftUI expects this)
                                orderedDevices.move(fromOffsets: from, toOffset: to)
                                // Then sync order to device manager
                                deviceManager.setDevicePriority(orderedDevices.map { $0.uid })
                            }
                        }
                        .listStyle(.plain)
                        .frame(minHeight: CGFloat(orderedDevices.count * 44 + 8))
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }

                    // Legend
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Connected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            Circle()
                                .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                                .frame(width: 8, height: 8)
                            Text("Disconnected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Unchecked = fallback only")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Store recordings on disk", isOn: $archiveEnabled)
                        .toggleStyle(.switch)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Archive Directory")
                            .font(.headline)

                        HStack(spacing: 8) {
                            Text(archiveDirectory.isEmpty ? "No folder selected" : archiveDirectory)
                                .font(.system(size: 12))
                                .foregroundStyle(archiveDirectory.isEmpty ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button("Choose...") {
                                chooseArchiveDirectory()
                            }
                            .disabled(!archiveEnabled)
                        }
                    }

                    Stepper(value: retentionBinding, in: 1...999) {
                        HStack {
                            Text("Keep recordings")
                            Spacer()
                            Text("\(archiveRetentionDays) days")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!archiveEnabled)

                    Text("Each dictation is saved as a 16 kHz mono WAV with a matching JSON sidecar containing the transcript and metadata.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .onAppear {
            updateOrderedDevices()
        }
        .onReceive(deviceManager.$availableDevices) { _ in
            updateOrderedDevices()
        }
    }

    private func updateOrderedDevices() {
        orderedDevices = deviceManager.getOrderedDevices()
    }

    private var retentionBinding: Binding<Int> {
        Binding(
            get: { max(1, min(archiveRetentionDays, 999)) },
            set: { archiveRetentionDays = max(1, min($0, 999)) }
        )
    }

    private func chooseArchiveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"

        if panel.runModal() == .OK, let url = panel.url {
            archiveDirectory = url.path
        }
    }
}

struct DeviceRow: View {
    let name: String
    let isAvailable: Bool
    let isEnabled: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))

            // Device name
            Text(name)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            // Availability indicator
            Circle()
                .fill(isAvailable ? Color.green : Color.clear)
                .stroke(isAvailable ? Color.clear : Color.secondary.opacity(0.5), lineWidth: 1)
                .frame(width: 8, height: 8)

            // Enable toggle
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

#Preview {
    AudioInputView()
}
