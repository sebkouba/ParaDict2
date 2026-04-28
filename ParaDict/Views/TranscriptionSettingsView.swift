import SwiftUI

struct TranscriptionSettingsView: View {
    @StateObject private var xaiService = XAITranscriptionService.shared

    @AppStorage(SettingsKeys.transcriptionProvider) private var transcriptionProvider = SettingsDefaults.transcriptionProvider

    @State private var apiKeyInput = ""
    @State private var showAPIKey = false
    @State private var testResult: String?
    @State private var isTestingConnection = false

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                VStack(spacing: 24) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.accentColor)
                        .padding(20)
                        .background(
                            Circle()
                                .fill(Color(NSColor.controlBackgroundColor))
                        )

                    VStack(spacing: 8) {
                        Text("Transcription")
                            .font(.system(size: 28, weight: .bold))
                        Text("Choose the speech-to-text service used after recording")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.vertical, 40)

                VStack(alignment: .leading, spacing: 24) {
                    providerSection

                    Divider()

                    xaiStatusSection

                    Divider()

                    xaiAPIKeySection
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

    private var selectedProvider: TranscriptionProvider {
        TranscriptionProvider(rawValue: transcriptionProvider) ?? .parakeet
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Provider", systemImage: "switch.2")
                .font(.headline)

            Text("Parakeet runs locally. x.ai sends recorded audio to the x.ai speech-to-text API.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Picker("Transcription Provider", selection: $transcriptionProvider) {
                ForEach(TranscriptionProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider.rawValue)
                }
            }
            .pickerStyle(.segmented)

            if selectedProvider == .xai {
                Label("Live preview still uses local Parakeet when enabled; final pasted text uses x.ai.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var xaiStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("x.ai Status", systemImage: "network")
                .font(.headline)

            HStack {
                Circle()
                    .fill(xaiService.isAPIKeyValid ? Color.green : Color.red)
                    .frame(width: 12, height: 12)

                Text(xaiService.isAPIKeyValid ? "Connected to x.ai" : "Not Connected")
                    .fontWeight(.medium)

                Spacer()

                if xaiService.isValidating || isTestingConnection {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(!xaiService.isConfigured)
                }
            }

            if let result = testResult {
                Text(result)
                    .font(.caption)
                    .foregroundColor(result.contains("successful") || result.contains("verified") ? .green : .orange)
            }
        }
    }

    private var xaiAPIKeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("x.ai API Key", systemImage: "key")
                .font(.headline)

            Text("Enter your x.ai API key to enable cloud transcription.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack {
                if showAPIKey {
                    TextField("xai-...", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                } else {
                    SecureField("xai-...", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                }

                Button {
                    showAPIKey.toggle()
                } label: {
                    Image(systemName: showAPIKey ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
            }

            HStack {
                Button("Save & Verify") {
                    saveAPIKey()
                }
                .disabled(apiKeyInput.isEmpty || xaiService.isValidating)

                if xaiService.isConfigured {
                    Button("Clear Key", role: .destructive) {
                        clearAPIKey()
                    }
                }

                Spacer()

                Link("Get API Key", destination: URL(string: "https://console.x.ai/team/default/api-keys?campaign=voice-docs-stt")!)
                    .font(.caption)
            }

            if let error = xaiService.lastValidationError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private func saveAPIKey() {
        Task {
            let success = await xaiService.saveAPIKey(apiKeyInput)
            if success {
                testResult = "x.ai API key verified successfully!"
                apiKeyInput = ""
            }
        }
    }

    private func clearAPIKey() {
        xaiService.clearAPIKey()
        apiKeyInput = ""
        testResult = nil
    }

    private func testConnection() {
        isTestingConnection = true
        testResult = nil

        Task {
            let result = await xaiService.testConnection()
            isTestingConnection = false
            testResult = result.success ? "Connection successful!" : result.message
        }
    }
}

#Preview {
    TranscriptionSettingsView()
        .frame(width: 500, height: 600)
}
