import SwiftUI

struct AudioInputView: View {
    @ObservedObject private var deviceManager = AudioDeviceManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 24) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)
                        .padding(20)
                        .background(Circle().fill(Color(NSColor.windowBackgroundColor).opacity(0.9)))

                    VStack(spacing: 8) {
                        Text("Audio Input")
                            .font(.system(size: 28, weight: .bold))
                        Text("Select which microphone to use for dictation")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 40)

                // Input mode selection
                VStack(alignment: .leading, spacing: 16) {
                    Text("Input Device")
                        .font(.headline)

                    // System Default option
                    DeviceOptionCard(
                        title: "System Default",
                        subtitle: "Use the system's default input device",
                        isSelected: deviceManager.selectedDeviceUID == nil,
                        action: {
                            deviceManager.useSystemDefault()
                        }
                    )

                    // Available devices
                    if !deviceManager.availableDevices.isEmpty {
                        Text("Available Devices")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)

                        ForEach(deviceManager.availableDevices, id: \.uid) { device in
                            DeviceOptionCard(
                                title: device.name,
                                subtitle: "UID: \(device.uid.prefix(20))...",
                                isSelected: deviceManager.selectedDeviceUID == device.uid,
                                action: {
                                    deviceManager.selectDevice(uid: device.uid)
                                }
                            )
                        }
                    }

                    // Refresh button
                    Button(action: {
                        deviceManager.loadAvailableDevices()
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh Devices")
                        }
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 8)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(16)
            }
            .padding(24)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct DeviceOptionCard: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.title2)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AudioInputView()
}
