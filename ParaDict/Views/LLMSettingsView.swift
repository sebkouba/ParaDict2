import SwiftUI

struct LLMSettingsView: View {
    @StateObject private var llmClient = LLMClient.shared
    @EnvironmentObject var configManager: ConfigManager

    @State private var apiKeyInput: String = ""
    @State private var showAPIKey: Bool = false
    @State private var testResult: String?
    @State private var isTestingConnection: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                Text("LLM Settings")
                    .font(.title2)
                    .fontWeight(.bold)

                // Connection Status
                connectionStatusSection

                // API Key Section
                apiKeySection

                // Model Configuration
                modelSection

                // Prompts Section
                promptsSection

                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Connection Status

    private var connectionStatusSection: some View {
        GroupBox {
            HStack {
                Circle()
                    .fill(llmClient.isAPIKeyValid ? Color.green : Color.red)
                    .frame(width: 12, height: 12)

                Text(llmClient.isAPIKeyValid ? "Connected to Groq" : "Not Connected")
                    .fontWeight(.medium)

                Spacer()

                if llmClient.isValidating || isTestingConnection {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(!llmClient.isConfigured)
                }
            }

            if let result = testResult {
                Text(result)
                    .font(.caption)
                    .foregroundColor(result.contains("success") ? .green : .orange)
                    .padding(.top, 4)
            }
        } label: {
            Label("Status", systemImage: "network")
        }
    }

    // MARK: - API Key Section

    private var apiKeySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Enter your Groq API key to enable LLM enhancement.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    if showAPIKey {
                        TextField("gsk_...", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("gsk_...", text: $apiKeyInput)
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
                    .disabled(apiKeyInput.isEmpty || llmClient.isValidating)

                    if llmClient.isConfigured {
                        Button("Clear Key", role: .destructive) {
                            clearAPIKey()
                        }
                    }

                    Spacer()

                    Link("Get API Key", destination: URL(string: "https://console.groq.com/keys")!)
                        .font(.caption)
                }

                if let error = llmClient.lastValidationError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label("API Key", systemImage: "key")
        }
    }

    // MARK: - Model Section

    private var modelSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Model:")
                    TextField("Model ID", text: Binding(
                        get: { configManager.config.llm.model },
                        set: { newValue in
                            configManager.config.llm.model = newValue
                            configManager.saveConfig()
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                }

                Text("Current: \(configManager.config.llm.model)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                Text("Available Models")
                    .font(.caption)
                    .fontWeight(.medium)

                VStack(alignment: .leading, spacing: 4) {
                    modelButton("moonshotai/kimi-k2-instruct-0905", description: "Kimi K2 - Fast & capable")
                    modelButton("llama-3.3-70b-versatile", description: "Llama 3.3 70B - High quality")
                    modelButton("llama-3.1-8b-instant", description: "Llama 3.1 8B - Very fast")
                    modelButton("mixtral-8x7b-32768", description: "Mixtral 8x7B - Balanced")
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label("Model", systemImage: "cpu")
        }
    }

    private func modelButton(_ model: String, description: String) -> some View {
        Button {
            configManager.config.llm.model = model
            configManager.saveConfig()
        } label: {
            HStack {
                Text(model)
                    .font(.system(.caption, design: .monospaced))
                Spacer()
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if configManager.config.llm.model == model {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    // MARK: - Prompts Section

    private var promptsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Prompt files are stored in:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Text(PromptManager.shared.getPromptsDirectoryPath())
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button("Open Folder") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: PromptManager.shared.getPromptsDirectoryPath()))
                    }
                    .font(.caption)
                }

                Divider()

                Text("Available Prompts")
                    .font(.caption)
                    .fontWeight(.medium)

                if PromptManager.shared.availablePrompts.isEmpty {
                    Text("No prompts found. Add .md files to the prompts folder.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(PromptManager.shared.availablePrompts, id: \.self) { prompt in
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundColor(.secondary)
                            Text(prompt)
                                .font(.system(.caption, design: .monospaced))
                            Text(".md")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Button("Refresh") {
                    PromptManager.shared.refreshPromptList()
                }
                .font(.caption)
            }
            .padding(.vertical, 4)
        } label: {
            Label("Prompts", systemImage: "doc.plaintext")
        }
    }

    // MARK: - Actions

    private func saveAPIKey() {
        Task {
            let success = await llmClient.saveAPIKey(apiKeyInput)
            if success {
                testResult = "API key verified successfully!"
                apiKeyInput = "" // Clear input after successful save
            }
        }
    }

    private func clearAPIKey() {
        llmClient.clearAPIKey()
        apiKeyInput = ""
        testResult = nil
    }

    private func testConnection() {
        isTestingConnection = true
        testResult = nil

        Task {
            let result = await llmClient.testConnection()
            isTestingConnection = false
            testResult = result.success ? "Connection successful!" : result.message
        }
    }
}

#Preview {
    LLMSettingsView()
        .environmentObject(ConfigManager.shared)
        .frame(width: 500, height: 600)
}
