import SwiftUI

struct LLMSettingsView: View {
    @StateObject private var llmClient = LLMClient.shared
    @ObservedObject private var promptManager = PromptManager.shared
    @EnvironmentObject var configManager: ConfigManager

    @State private var apiKeyInput: String = ""
    @State private var showAPIKey: Bool = false
    @State private var testResult: String?
    @State private var isTestingConnection: Bool = false
    @State private var editingPrompt: String?
    @State private var hoveredPrompt: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 24) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.accentColor)
                        .padding(20)
                        .background(
                            Circle()
                                .fill(Color(NSColor.controlBackgroundColor))
                        )

                    VStack(spacing: 8) {
                        Text("LLM Settings")
                            .font(.system(size: 28, weight: .bold))
                        Text("Configure AI enhancement for your dictation")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.vertical, 40)

                // All sections in a card
                VStack(alignment: .leading, spacing: 24) {
                    // Connection Status
                    connectionStatusSection

                    Divider()

                    // API Key Section
                    apiKeySection

                    Divider()

                    // Model Configuration
                    modelSection

                    Divider()

                    // Prompts Section
                    promptsSection
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
        .sheet(item: $editingPrompt) { promptName in
            PromptEditorSheet(promptName: promptName, onDismiss: { editingPrompt = nil })
        }
    }

    // MARK: - Connection Status

    private var connectionStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Status", systemImage: "network")
                .font(.headline)

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
            }
        }
    }

    // MARK: - API Key Section

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("API Key", systemImage: "key")
                .font(.headline)

            Text("Enter your Groq API key to enable LLM enhancement.")
                .font(.subheadline)
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
    }

    // MARK: - Model Section

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Model", systemImage: "cpu")
                .font(.headline)

            Text("Enter the Groq model ID to use for enhancement.")
                .font(.subheadline)
                .foregroundColor(.secondary)

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
    }

    // MARK: - Prompts Section

    private var promptsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Prompts", systemImage: "doc.plaintext")
                .font(.headline)

            HStack {
                Text(promptManager.getPromptsDirectoryPath())
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button("Open Folder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: promptManager.getPromptsDirectoryPath()))
                }
                .font(.caption)
            }

            if promptManager.availablePrompts.isEmpty {
                Text("No prompts found. Add .md files to the prompts folder.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 4) {
                    ForEach(promptManager.availablePrompts, id: \.self) { prompt in
                        PromptRow(
                            promptName: prompt,
                            isHovered: hoveredPrompt == prompt,
                            onHover: { isHovered in
                                hoveredPrompt = isHovered ? prompt : nil
                            },
                            onTap: {
                                editingPrompt = prompt
                            }
                        )
                    }
                }
            }

            Button {
                promptManager.refreshPromptList()
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
            }
            .font(.caption)
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

// MARK: - Prompt Row

struct PromptRow: View {
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

                Text(promptName)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primary)

                Text(".md")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Image(systemName: "pencil")
                    .font(.system(size: 14))
                    .foregroundColor(isHovered ? .accentColor : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovered ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            onHover(hovering)
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - String Identifiable Extension

extension String: @retroactive Identifiable {
    public var id: String { self }
}

// MARK: - Prompt Editor Sheet

struct PromptEditorSheet: View {
    let promptName: String
    let onDismiss: () -> Void

    @State private var content: String = ""
    @State private var saveStatus: SaveStatus = .idle
    @State private var saveTask: Task<Void, Never>?

    enum SaveStatus {
        case idle
        case saving
        case saved
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(promptName + ".md")
                        .font(.headline)
                    Text(PromptManager.shared.getPromptsDirectoryPath())
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                // Save status
                HStack(spacing: 6) {
                    switch saveStatus {
                    case .idle:
                        EmptyView()
                    case .saving:
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Saving...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    case .saved:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Saved")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                .frame(width: 80, alignment: .trailing)

                Button("Done") {
                    // Save immediately if there are pending changes
                    saveTask?.cancel()
                    saveImmediately()
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Editor
            TextEditor(text: $content)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .onChange(of: content) { _, _ in
                    scheduleAutoSave()
                }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            loadContent()
        }
    }

    private func loadContent() {
        if let loaded = PromptManager.shared.loadPrompt(named: promptName) {
            content = loaded
        } else {
            content = "# \(promptName)\n\nEnter your prompt here..."
        }
    }

    private func scheduleAutoSave() {
        // Cancel any pending save
        saveTask?.cancel()

        // Schedule new save after 0.8 second debounce
        saveTask = Task {
            saveStatus = .idle
            try? await Task.sleep(nanoseconds: 800_000_000)

            guard !Task.isCancelled else { return }

            await MainActor.run {
                saveStatus = .saving
            }

            // Small delay to show "Saving..." state
            try? await Task.sleep(nanoseconds: 200_000_000)

            guard !Task.isCancelled else { return }

            do {
                try PromptManager.shared.createPrompt(name: promptName, content: content)
                await MainActor.run {
                    saveStatus = .saved
                }

                // Reset to idle after showing "Saved"
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if saveStatus == .saved {
                        saveStatus = .idle
                    }
                }
            } catch {
                await MainActor.run {
                    saveStatus = .idle
                }
            }
        }
    }

    private func saveImmediately() {
        try? PromptManager.shared.createPrompt(name: promptName, content: content)
    }
}

#Preview {
    LLMSettingsView()
        .environmentObject(ConfigManager.shared)
        .frame(width: 500, height: 600)
}
