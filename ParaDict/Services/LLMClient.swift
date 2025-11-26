import Foundation
import os

struct ChatMessage: Codable {
    let role: String
    let content: String
}

struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double?
    let maxTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

struct ChatCompletionResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let role: String
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

enum LLMError: LocalizedError {
    case noAPIKey
    case requestFailed(String)
    case invalidResponse
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "API key not found. Set GROQ_API_KEY environment variable."
        case .requestFailed(let message):
            return "LLM request failed: \(message)"
        case .invalidResponse:
            return "Invalid response from LLM"
        case .emptyResponse:
            return "Empty response from LLM"
        }
    }
}

class LLMClient {
    static let shared = LLMClient()

    private let logger = Logger(subsystem: "com.paradict", category: "LLMClient")
    private let baseURL = "https://api.groq.com/openai/v1/chat/completions"

    private init() {}

    func enhance(text: String, systemPrompt: String) async throws -> String {
        let messages = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: text)
        ]
        return try await chat(messages: messages)
    }

    func chat(messages: [ChatMessage], configContext: String? = nil) async throws -> String {
        guard let apiKey = ConfigManager.shared.apiKey else {
            throw LLMError.noAPIKey
        }

        let config = ConfigManager.shared.config.llm
        var allMessages = messages

        // Add config context if provided (for settings chat)
        if let context = configContext {
            let systemMessage = ChatMessage(
                role: "system",
                content: """
                You are a helpful assistant for the ParaDict app. You help users configure the app.

                Current config.yaml contents:
                ```yaml
                \(context)
                ```

                When the user asks to modify settings, output the modified YAML in a code block.
                The user's config file is at: \(ConfigManager.shared.configFilePath)
                """
            )
            allMessages.insert(systemMessage, at: 0)
        }

        let request = ChatCompletionRequest(
            model: config.model,
            messages: allMessages,
            temperature: 0.7,
            maxTokens: 2048
        )

        var urlRequest = URLRequest(url: URL(string: baseURL)!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        logger.notice("Sending request to Groq API with model: \(config.model)")

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("API error: \(httpResponse.statusCode) - \(errorMessage)")
            throw LLMError.requestFailed("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        guard let content = completion.choices.first?.message.content else {
            throw LLMError.emptyResponse
        }

        return content
    }
}
