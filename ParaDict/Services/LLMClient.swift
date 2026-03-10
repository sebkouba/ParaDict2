import Foundation
import Combine
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

// MARK: - Tool Calling Types

struct ToolDefinition: Codable {
    let type: String
    let function: FunctionDefinition

    init(name: String, description: String, parameters: [String: ParameterDefinition], required: [String] = []) {
        self.type = "function"
        self.function = FunctionDefinition(
            name: name,
            description: description,
            parameters: ParametersSchema(
                type: "object",
                properties: parameters,
                required: required
            )
        )
    }
}

struct FunctionDefinition: Codable {
    let name: String
    let description: String
    let parameters: ParametersSchema
}

struct ParametersSchema: Codable {
    let type: String
    let properties: [String: ParameterDefinition]
    let required: [String]
}

struct ParameterDefinition: Codable {
    let type: String
    let description: String
    let `enum`: [String]?

    init(type: String, description: String, enumValues: [String]? = nil) {
        self.type = type
        self.description = description
        self.enum = enumValues
    }
}

struct ToolCall: Codable {
    let id: String
    let type: String
    let function: FunctionCallInfo
}

struct FunctionCallInfo: Codable {
    let name: String
    let arguments: String  // JSON string to be parsed
}

/// Extended response that includes tool_calls
struct ChatCompletionResponseWithTools: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let role: String
            let content: String?
            let toolCalls: [ToolCall]?

            enum CodingKeys: String, CodingKey {
                case role, content
                case toolCalls = "tool_calls"
            }
        }
        let message: Message
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }
    let choices: [Choice]
}

struct ChatCompletionRequestWithTools: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double?
    let maxTokens: Int?
    let tools: [ToolDefinition]?
    let toolChoice: String?

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, tools
        case maxTokens = "max_tokens"
        case toolChoice = "tool_choice"
    }
}

/// Result type for tool-aware chat
enum ChatWithToolsResult {
    case content(String)
    case toolCalls([ToolCall])
}

enum LLMError: LocalizedError {
    case noAPIKey
    case invalidAPIKey
    case requestFailed(String)
    case invalidResponse
    case emptyResponse
    case networkError(Error)
    case rateLimitExceeded
    case serverError(Int)
    case timeout(originalText: String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "API key not configured. Please add your Groq API key in Settings."
        case .invalidAPIKey:
            return "Invalid API key. Please check your Groq API key."
        case .requestFailed(let message):
            return "LLM request failed: \(message)"
        case .invalidResponse:
            return "Invalid response from LLM"
        case .emptyResponse:
            return "Empty response from LLM"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please wait and try again."
        case .serverError(let code):
            return "Server error (HTTP \(code)). Please try again."
        case .timeout:
            return "Enhancement timed out. Using original transcription."
        }
    }
}

@MainActor
class LLMClient: ObservableObject {
    static let shared = LLMClient()

    private let logger = Logger(subsystem: "com.paradict", category: "LLMClient")
    private let baseURL = "https://api.groq.com/openai/v1/chat/completions"

    // API Key storage
    private let apiKeyStorageKey = "GROQAPIKey"

    @Published var isAPIKeyValid: Bool = false
    @Published var isValidating: Bool = false
    @Published var lastValidationError: String?

    private init() {
        // Check if we have a stored API key on init
        if let _ = getStoredAPIKey() {
            isAPIKeyValid = true
        }
    }

    // MARK: - API Key Management

    var isConfigured: Bool {
        getStoredAPIKey() != nil
    }

    func getStoredAPIKey() -> String? {
        // First check UserDefaults
        if let key = UserDefaults.standard.string(forKey: apiKeyStorageKey), !key.isEmpty {
            return key
        }
        // Fall back to environment variable for backwards compatibility
        if let key = ProcessInfo.processInfo.environment["GROQ_API_KEY"], !key.isEmpty {
            return key
        }
        return nil
    }

    func saveAPIKey(_ key: String) async -> Bool {
        isValidating = true
        lastValidationError = nil

        defer { isValidating = false }

        // Validate the key first
        do {
            let isValid = try await validateAPIKey(key)
            if isValid {
                UserDefaults.standard.set(key, forKey: apiKeyStorageKey)
                isAPIKeyValid = true
                logger.notice("API key saved and validated successfully")
                return true
            } else {
                lastValidationError = "API key validation failed"
                isAPIKeyValid = false
                return false
            }
        } catch {
            lastValidationError = error.localizedDescription
            isAPIKeyValid = false
            logger.error("API key validation error: \(error.localizedDescription)")
            return false
        }
    }

    func clearAPIKey() {
        UserDefaults.standard.removeObject(forKey: apiKeyStorageKey)
        isAPIKeyValid = false
        lastValidationError = nil
        logger.notice("API key cleared")
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        logger.notice("Validating API key...")

        let model = UserDefaults.standard.string(forKey: SettingsKeys.llmModel) ?? SettingsDefaults.llmModel

        let request = ChatCompletionRequest(
            model: model,
            messages: [ChatMessage(role: "user", content: "test")],
            temperature: 0.1,
            maxTokens: 5
        )

        var urlRequest = URLRequest(url: URL(string: baseURL)!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        urlRequest.timeoutInterval = 15
        urlRequest.httpBody = try JSONEncoder().encode(request)

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw LLMError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200...299:
                logger.notice("API key validated successfully (HTTP \(httpResponse.statusCode))")
                return true
            case 401:
                logger.error("API key invalid (HTTP 401)")
                throw LLMError.invalidAPIKey
            case 429:
                // Rate limited but key is valid
                logger.notice("API key valid but rate limited")
                return true
            default:
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                logger.error("API validation failed: HTTP \(httpResponse.statusCode) - \(errorMessage)")
                throw LLMError.requestFailed("HTTP \(httpResponse.statusCode)")
            }
        } catch let error as LLMError {
            throw error
        } catch {
            logger.error("Network error during validation: \(error.localizedDescription)")
            throw LLMError.networkError(error)
        }
    }

    // MARK: - LLM Requests

    func enhance(text: String, systemPrompt: String) async throws -> String {
        // Append custom dictionary to the system prompt if available
        var fullSystemPrompt = systemPrompt
        if let dictionary = DictionaryManager.shared.loadDictionary(), !dictionary.isEmpty {
            fullSystemPrompt += "\n\n---\n\n\(dictionary)"
        }

        let messages = [
            ChatMessage(role: "system", content: fullSystemPrompt),
            ChatMessage(role: "user", content: text)
        ]

        // Calculate timeout based on text length
        let timeout = AppSettings.shared.calculateEnhancementTimeout(forText: text)
        let baseMs = AppSettings.shared.enhancementTimeoutBaseMs
        logger.notice("Enhancement request starting - timeout: \(String(format: "%.2f", timeout))s (base: \(baseMs)ms + \(text.count) chars)")

        let startTime = ContinuousClock.now

        // Race the chat request against a timeout
        return try await withThrowingTaskGroup(of: String.self) { group in
            // Add the actual chat task
            group.addTask {
                try await self.chat(messages: messages)
            }

            // Add the timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw LLMError.timeout(originalText: text)
            }

            // Return whichever completes first
            do {
                let result = try await group.next()!
                group.cancelAll()  // Cancel the other task
                let elapsed = startTime.duration(to: .now)
                let elapsedMs = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
                self.logger.notice("Enhancement completed in \(elapsedMs)ms (budget: \(String(format: "%.0f", timeout * 1000))ms)")
                return result
            } catch let error as LLMError {
                group.cancelAll()
                let elapsed = startTime.duration(to: .now)
                let elapsedMs = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
                self.logger.warning("Enhancement timed out after \(elapsedMs)ms (budget: \(String(format: "%.0f", timeout * 1000))ms)")
                throw error
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    func chat(messages: [ChatMessage]) async throws -> String {
        guard let apiKey = getStoredAPIKey() else {
            throw LLMError.noAPIKey
        }

        let model = UserDefaults.standard.string(forKey: SettingsKeys.llmModel) ?? SettingsDefaults.llmModel

        let request = ChatCompletionRequest(
            model: model,
            messages: messages,
            temperature: 0.7,
            maxTokens: 2048
        )

        return try await makeRequestWithRetry(request: request, apiKey: apiKey)
    }

    private func makeRequestWithRetry(request: ChatCompletionRequest, apiKey: String, retryCount: Int = 0) async throws -> String {
        let maxRetries = 3
        let baseDelay: UInt64 = 1_000_000_000 // 1 second

        do {
            return try await makeRequest(request: request, apiKey: apiKey)
        } catch LLMError.rateLimitExceeded, LLMError.serverError {
            if retryCount < maxRetries {
                let delay = baseDelay * UInt64(1 << retryCount) // Exponential backoff
                logger.notice("Retrying request (attempt \(retryCount + 2)/\(maxRetries + 1)) after \(delay / 1_000_000_000)s delay")
                try await Task.sleep(nanoseconds: delay)
                return try await makeRequestWithRetry(request: request, apiKey: apiKey, retryCount: retryCount + 1)
            }
            throw LLMError.rateLimitExceeded
        }
    }

    private func makeRequest(request: ChatCompletionRequest, apiKey: String) async throws -> String {
        var urlRequest = URLRequest(url: URL(string: baseURL)!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.timeoutInterval = 30
        urlRequest.httpBody = try JSONEncoder().encode(request)

        logger.notice("Sending request to Groq API with model: \(request.model)")

        // Log message details for debugging
        for (index, msg) in request.messages.enumerated() {
            let contentPreview = msg.content.prefix(100)
            logger.notice("  Message[\(index)] role=\(msg.role), content_length=\(msg.content.count), preview: \(contentPreview)...")
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            isAPIKeyValid = false
            throw LLMError.invalidAPIKey
        case 429:
            throw LLMError.rateLimitExceeded
        case 500...599:
            throw LLMError.serverError(httpResponse.statusCode)
        default:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("API error: \(httpResponse.statusCode) - \(errorMessage)")
            throw LLMError.requestFailed("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        guard let content = completion.choices.first?.message.content else {
            throw LLMError.emptyResponse
        }

        let responsePreview = content.prefix(100)
        logger.notice("LLM response (length=\(content.count)): \(responsePreview)...")

        return content
    }

    // MARK: - Tool Calling

    func chatWithTools(
        messages: [ChatMessage],
        tools: [ToolDefinition]
    ) async throws -> ChatWithToolsResult {
        guard let apiKey = getStoredAPIKey() else {
            throw LLMError.noAPIKey
        }

        let model = UserDefaults.standard.string(forKey: SettingsKeys.llmModel) ?? SettingsDefaults.llmModel

        let request = ChatCompletionRequestWithTools(
            model: model,
            messages: messages,
            temperature: 0.6,  // Kimi K2 recommended
            maxTokens: 1024,
            tools: tools,
            toolChoice: "auto"
        )

        var urlRequest = URLRequest(url: URL(string: baseURL)!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.timeoutInterval = 30
        urlRequest.httpBody = try JSONEncoder().encode(request)

        logger.notice("Sending tool-aware request to Groq API")

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            isAPIKeyValid = false
            throw LLMError.invalidAPIKey
        case 429:
            throw LLMError.rateLimitExceeded
        case 500...599:
            throw LLMError.serverError(httpResponse.statusCode)
        default:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("API error: \(httpResponse.statusCode) - \(errorMessage)")
            throw LLMError.requestFailed("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        let completion = try JSONDecoder().decode(ChatCompletionResponseWithTools.self, from: data)

        guard let choice = completion.choices.first else {
            throw LLMError.emptyResponse
        }

        // Check for tool calls first
        if let toolCalls = choice.message.toolCalls, !toolCalls.isEmpty {
            logger.notice("Received \(toolCalls.count) tool call(s)")
            return .toolCalls(toolCalls)
        }

        // Otherwise return content
        if let content = choice.message.content {
            return .content(content)
        }

        throw LLMError.emptyResponse
    }

    // MARK: - Connection Test

    func testConnection() async -> (success: Bool, message: String) {
        guard let apiKey = getStoredAPIKey() else {
            return (false, "No API key configured")
        }

        do {
            let isValid = try await validateAPIKey(apiKey)
            if isValid {
                return (true, "Connected to Groq API successfully")
            } else {
                return (false, "API key validation failed")
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
