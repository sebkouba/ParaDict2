import SwiftUI

struct TranscriptionSettingsView: View {
    @StateObject private var xaiService = XAITranscriptionService.shared
    @StateObject private var elevenLabsService = ElevenLabsTranscriptionService.shared

    @AppStorage(SettingsKeys.transcriptionProvider) private var transcriptionProvider = SettingsDefaults.transcriptionProvider

    @State private var xaiAPIKeyInput = ""
    @State private var elevenLabsAPIKeyInput = ""
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

                    if selectedProvider != .parakeet {
                        Divider()

                        providerStatusSection

                        Divider()

                        providerAPIKeySection
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
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onChange(of: transcriptionProvider) {
            testResult = nil
            showAPIKey = false
        }
    }

    private var selectedProvider: TranscriptionProvider {
        TranscriptionProvider(rawValue: transcriptionProvider) ?? .parakeet
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Provider", systemImage: "switch.2")
                .font(.headline)

            Text("Parakeet stays on-device. x.ai and ElevenLabs send each completed recording to the selected cloud API.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Picker("Transcription Provider", selection: $transcriptionProvider) {
                ForEach(TranscriptionProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider.rawValue)
                }
            }
            .pickerStyle(.segmented)

            if selectedProvider != .parakeet {
                Label(
                    "Live preview still uses local Parakeet when enabled; final pasted text uses \(selectedProvider.displayName).",
                    systemImage: "info.circle"
                )
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if selectedProvider == .elevenLabs {
                Label(
                    "Scribe v2 transcribes synchronously and detects the spoken language automatically.",
                    systemImage: "globe"
                )
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var providerStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(selectedProvider.displayName) Status", systemImage: "network")
                .font(.headline)

            HStack {
                Circle()
                    .fill(selectedProviderAPIKeyIsValid ? Color.green : Color.red)
                    .frame(width: 12, height: 12)

                Text(selectedProviderAPIKeyIsValid ? "Connected to \(selectedProvider.displayName)" : "Not Connected")
                    .fontWeight(.medium)

                Spacer()

                if selectedProviderIsValidating || isTestingConnection {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(!selectedProviderIsConfigured)
                }
            }

            if let result = testResult {
                Text(result)
                    .font(.caption)
                    .foregroundColor(result.contains("successful") || result.contains("verified") ? .green : .orange)
            }
        }
    }

    private var providerAPIKeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(selectedProvider.displayName) API Key", systemImage: "key")
                .font(.headline)

            Text("Stored securely in the macOS Keychain.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack {
                if showAPIKey {
                    TextField(selectedProviderAPIKeyPlaceholder, text: selectedProviderAPIKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                } else {
                    SecureField(selectedProviderAPIKeyPlaceholder, text: selectedProviderAPIKeyInput)
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
                .disabled(selectedProviderAPIKeyInput.wrappedValue.isEmpty || selectedProviderIsValidating)

                if selectedProviderIsConfigured {
                    Button("Clear Key", role: .destructive) {
                        clearAPIKey()
                    }
                }

                Spacer()

                Link("Get API Key", destination: selectedProviderAPIKeyURL)
                    .font(.caption)
            }

            if let error = selectedProviderValidationError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private var selectedProviderAPIKeyInput: Binding<String> {
        switch selectedProvider {
        case .xai:
            return $xaiAPIKeyInput
        case .elevenLabs:
            return $elevenLabsAPIKeyInput
        case .parakeet:
            return .constant("")
        }
    }

    private var selectedProviderAPIKeyIsValid: Bool {
        switch selectedProvider {
        case .xai:
            return xaiService.isAPIKeyValid
        case .elevenLabs:
            return elevenLabsService.isAPIKeyValid
        case .parakeet:
            return true
        }
    }

    private var selectedProviderIsConfigured: Bool {
        switch selectedProvider {
        case .xai:
            return xaiService.isConfigured
        case .elevenLabs:
            return elevenLabsService.isConfigured
        case .parakeet:
            return true
        }
    }

    private var selectedProviderIsValidating: Bool {
        switch selectedProvider {
        case .xai:
            return xaiService.isValidating
        case .elevenLabs:
            return elevenLabsService.isValidating
        case .parakeet:
            return false
        }
    }

    private var selectedProviderValidationError: String? {
        switch selectedProvider {
        case .xai:
            return xaiService.lastValidationError
        case .elevenLabs:
            return elevenLabsService.lastValidationError
        case .parakeet:
            return nil
        }
    }

    private var selectedProviderAPIKeyPlaceholder: String {
        switch selectedProvider {
        case .xai:
            return "xai-..."
        case .elevenLabs:
            return "Paste ElevenLabs API key"
        case .parakeet:
            return ""
        }
    }

    private var selectedProviderAPIKeyURL: URL {
        switch selectedProvider {
        case .xai:
            return URL(string: "https://console.x.ai/team/default/api-keys?campaign=voice-docs-stt")!
        case .elevenLabs:
            return URL(string: "https://elevenlabs.io/app/settings/api-keys")!
        case .parakeet:
            return URL(string: "https://elevenlabs.io/docs/api-reference/authentication")!
        }
    }

    private func saveAPIKey() {
        let provider = selectedProvider
        let key = selectedProviderAPIKeyInput.wrappedValue

        Task {
            let success: Bool
            switch provider {
            case .xai:
                success = await xaiService.saveAPIKey(key)
            case .elevenLabs:
                success = await elevenLabsService.saveAPIKey(key)
            case .parakeet:
                return
            }

            if success {
                testResult = "\(provider.displayName) API key verified successfully!"
                clearAPIKeyInput(for: provider)
            }
        }
    }

    private func clearAPIKey() {
        let provider = selectedProvider

        Task {
            switch provider {
            case .xai:
                await xaiService.clearAPIKey()
            case .elevenLabs:
                await elevenLabsService.clearAPIKey()
            case .parakeet:
                return
            }

            clearAPIKeyInput(for: provider)
            testResult = nil
        }
    }

    private func testConnection() {
        let provider = selectedProvider
        isTestingConnection = true
        testResult = nil

        Task {
            let result: (success: Bool, message: String)
            switch provider {
            case .xai:
                result = await xaiService.testConnection()
            case .elevenLabs:
                result = await elevenLabsService.testConnection()
            case .parakeet:
                isTestingConnection = false
                return
            }

            isTestingConnection = false
            testResult = result.success ? "Connection successful!" : result.message
        }
    }

    private func clearAPIKeyInput(for provider: TranscriptionProvider) {
        switch provider {
        case .xai:
            xaiAPIKeyInput = ""
        case .elevenLabs:
            elevenLabsAPIKeyInput = ""
        case .parakeet:
            break
        }
    }
}

#Preview {
    TranscriptionSettingsView()
        .frame(width: 500, height: 600)
}
