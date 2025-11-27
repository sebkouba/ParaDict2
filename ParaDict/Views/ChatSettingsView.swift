import SwiftUI

struct Message: Identifiable {
    let id = UUID()
    let role: String
    let content: String
    let timestamp: Date
}

struct ChatSettingsView: View {
    @EnvironmentObject var configManager: ConfigManager
    @State private var messages: [Message] = []
    @State private var inputText: String = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings Chat")
                        .font(.headline)
                    Text("Ask questions or modify settings using natural language")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()

                Button(action: clearChat) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(messages.isEmpty)

                Button(action: openConfigFile) {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("Open Config")
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        // Welcome message
                        if messages.isEmpty {
                            WelcomeMessageView()
                        }

                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        if isLoading {
                            LoadingBubble()
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input area
            HStack(spacing: 12) {
                TextField("Ask about settings or request changes...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .onSubmit {
                        sendMessage()
                    }

                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderedProminent)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    private func openConfigFile() {
        NSWorkspace.shared.open(URL(fileURLWithPath: configManager.configFilePath))
    }

    private func clearChat() {
        messages.removeAll()
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let userMessage = Message(role: "user", content: text, timestamp: Date())
        messages.append(userMessage)
        inputText = ""
        isLoading = true

        Task {
            do {
                let response = try await LLMClient.shared.chat(
                    messages: messages.map { ChatMessage(role: $0.role, content: $0.content) },
                    configContext: configManager.getConfigYAML()
                )

                let assistantMessage = Message(role: "assistant", content: response, timestamp: Date())
                await MainActor.run {
                    messages.append(assistantMessage)
                    isLoading = false
                }

                // Check if the response contains YAML to update config
                await processResponse(response)
            } catch {
                let errorMessage = Message(
                    role: "assistant",
                    content: "Error: \(error.localizedDescription)",
                    timestamp: Date()
                )
                await MainActor.run {
                    messages.append(errorMessage)
                    isLoading = false
                }
            }
        }
    }

    private func processResponse(_ response: String) async {
        // Look for YAML code blocks and offer to apply them
        let pattern = "```yaml\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: response, range: NSRange(response.startIndex..., in: response)),
              let range = Range(match.range(at: 1), in: response) else {
            return
        }

        let yamlContent = String(response[range])

        // Validate and apply the YAML
        do {
            try configManager.updateFromYAML(yamlContent)
            let confirmMessage = Message(
                role: "assistant",
                content: "Config updated successfully! The changes have been applied.",
                timestamp: Date()
            )
            await MainActor.run {
                messages.append(confirmMessage)
            }
        } catch {
            // YAML parsing failed, don't apply
        }
    }
}

struct WelcomeMessageView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to ParaDict Settings")
                .font(.headline)

            Text("You can ask me to help you configure the app. Try:")
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                SuggestionChip(text: "Show my current hotkeys")
                SuggestionChip(text: "Add a new hotkey for summarizing text")
                SuggestionChip(text: "Change the LLM model to llama3")
                SuggestionChip(text: "How do I add custom vocabulary?")
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
}

struct SuggestionChip: View {
    let text: String

    var body: some View {
        Text("• \(text)")
            .font(.subheadline)
            .foregroundColor(.blue)
    }
}

struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == "user" {
                Spacer()
            }

            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(12)
                    .background(message.role == "user" ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                    .foregroundColor(message.role == "user" ? .white : .primary)
                    .cornerRadius(16)

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if message.role == "assistant" {
                Spacer()
            }
        }
    }
}

struct LoadingBubble: View {
    @State private var dotCount = 0

    var body: some View {
        HStack {
            Text("Thinking" + String(repeating: ".", count: dotCount))
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(16)
            Spacer()
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                dotCount = (dotCount + 1) % 4
            }
        }
    }
}

#Preview {
    ChatSettingsView()
        .environmentObject(ConfigManager.shared)
}
