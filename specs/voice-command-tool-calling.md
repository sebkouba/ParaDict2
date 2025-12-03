# Voice Command with Tool Calling Implementation Plan

## Overview

Add a "command" mode to ParaDict that uses Kimi K2's tool calling capabilities to execute voice commands like "open Parakeet" by invoking shell commands or launching apps.

**User says:** "open Parakeet"
**System:** Transcribes → LLM with tools → `open_project("Parakeet")` → Opens VS Code with project

---

## Research Summary

### Kimi K2 Tool Calling (via Groq)

- **Model ID:** `moonshotai/kimi-k2-instruct` (already configured in ParaDict)
- **API:** OpenAI-compatible at `https://api.groq.com/openai/v1/chat/completions`
- **Context:** 131K tokens, 16K output
- **Strengths:** Designed for agentic tool use, can orchestrate 200+ tool calls

### OpenAI Tool Calling Format

**Request with tools:**
```json
{
  "model": "moonshotai/kimi-k2-instruct",
  "messages": [
    {"role": "system", "content": "You are a voice command assistant..."},
    {"role": "user", "content": "open Parakeet"}
  ],
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "open_project",
        "description": "Opens a coding project in VS Code",
        "parameters": {
          "type": "object",
          "properties": {
            "project_name": {
              "type": "string",
              "description": "Name of the project to open"
            }
          },
          "required": ["project_name"]
        }
      }
    }
  ],
  "tool_choice": "auto",
  "temperature": 0.6
}
```

**Response with tool call:**
```json
{
  "choices": [{
    "message": {
      "role": "assistant",
      "content": null,
      "tool_calls": [{
        "id": "call_abc123",
        "type": "function",
        "function": {
          "name": "open_project",
          "arguments": "{\"project_name\": \"Parakeet\"}"
        }
      }]
    },
    "finish_reason": "tool_calls"
  }]
}
```

**Sources:**
- [Kimi K2 on Groq](https://console.groq.com/docs/model/moonshotai/kimi-k2-instruct)
- [Moonshot Platform - Tool Calls](https://platform.moonshot.ai/docs/guide/use-kimi-api-to-complete-tool-calls)
- [OpenAI Structured Outputs](https://cookbook.openai.com/examples/structured_outputs_intro)

---

## Phase 1: Add Command Mode

### 1.1 Update DictationMode Enum

**File:** `ConfigManager.swift:81-85`

```swift
enum DictationMode: String, Codable {
    case local      // Parakeet only
    case enhanced   // Parakeet + LLM
    case reply      // Parakeet + LLM with selection context
    case command    // Parakeet + LLM with tool calling (NEW)
}
```

### 1.2 Add Default Command Shortcut

**File:** `ConfigManager.swift` - `AppConfig.default`

Add to default shortcuts array:
```swift
ShortcutConfig(name: "command", shortcut: nil, mode: .command, promptFile: "command", captureSelection: nil)
```

---

## Phase 2: Tool Calling Models

### 2.1 Add Tool Definition Structs

**File:** `Services/LLMClient.swift` - Add after existing Codable structs

```swift
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
    let `enum`: [String]?  // Optional enum values

    init(type: String, description: String, enumValues: [String]? = nil) {
        self.type = type
        self.description = description
        self.enum = enumValues
    }
}
```

### 2.2 Add Tool Call Response Types

```swift
struct ToolCall: Codable {
    let id: String
    let type: String
    let function: FunctionCallInfo
}

struct FunctionCallInfo: Codable {
    let name: String
    let arguments: String  // JSON string to be parsed
}

// Extended response that includes tool_calls
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
```

### 2.3 Add Tool-Aware Request Type

```swift
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
```

---

## Phase 3: LLMClient Tool Calling Method

### 3.1 Add chatWithTools Method

**File:** `Services/LLMClient.swift`

```swift
/// Result type for tool-aware chat
enum ChatWithToolsResult {
    case content(String)
    case toolCalls([ToolCall])
}

func chatWithTools(
    messages: [ChatMessage],
    tools: [ToolDefinition]
) async throws -> ChatWithToolsResult {
    guard let apiKey = getStoredAPIKey() else {
        throw LLMError.noAPIKey
    }

    let config = ConfigManager.shared.config.llm

    let request = ChatCompletionRequestWithTools(
        model: config.model,
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

    guard httpResponse.statusCode == 200 else {
        // Handle errors (reuse existing error handling)
        throw LLMError.requestFailed("HTTP \(httpResponse.statusCode)")
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
```

---

## Phase 4: Command Executor Service

### 4.1 Create CommandExecutorService

**File:** `Services/CommandExecutorService.swift` (NEW)

```swift
import Foundation
import AppKit
import os

/// Defines available tools and executes tool calls from LLM
@MainActor
class CommandExecutorService: ObservableObject {
    static let shared = CommandExecutorService()

    private let logger = Logger(subsystem: "com.paradict", category: "CommandExecutor")

    private init() {}

    // MARK: - Tool Definitions

    /// Returns all available tool definitions for the command prompt
    func getToolDefinitions() -> [ToolDefinition] {
        return [
            openProjectTool(),
            openAppTool(),
            openURLTool(),
            runShellTool()
        ]
    }

    private func openProjectTool() -> ToolDefinition {
        // Get project names from the command prompt file
        let projectNames = getConfiguredProjectNames()

        return ToolDefinition(
            name: "open_project",
            description: "Opens a coding project in VS Code. Use this when the user says 'open [project name]'.",
            parameters: [
                "project_name": ParameterDefinition(
                    type: "string",
                    description: "The name of the project to open",
                    enumValues: projectNames.isEmpty ? nil : projectNames
                )
            ],
            required: ["project_name"]
        )
    }

    private func openAppTool() -> ToolDefinition {
        return ToolDefinition(
            name: "open_app",
            description: "Opens a macOS application by name",
            parameters: [
                "app_name": ParameterDefinition(
                    type: "string",
                    description: "The name of the application to open (e.g., 'Safari', 'Finder', 'Terminal')"
                )
            ],
            required: ["app_name"]
        )
    }

    private func openURLTool() -> ToolDefinition {
        return ToolDefinition(
            name: "open_url",
            description: "Opens a URL in the default browser",
            parameters: [
                "url": ParameterDefinition(
                    type: "string",
                    description: "The URL to open"
                )
            ],
            required: ["url"]
        )
    }

    private func runShellTool() -> ToolDefinition {
        return ToolDefinition(
            name: "run_shell",
            description: "Runs a shell command. Use sparingly and only for safe operations.",
            parameters: [
                "command": ParameterDefinition(
                    type: "string",
                    description: "The shell command to execute"
                )
            ],
            required: ["command"]
        )
    }

    // MARK: - Tool Execution

    /// Execute a tool call and return the result
    func execute(toolCall: ToolCall) async throws -> String {
        let name = toolCall.function.name
        let argsJSON = toolCall.function.arguments

        logger.notice("Executing tool: \(name) with args: \(argsJSON)")

        guard let argsData = argsJSON.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] else {
            throw CommandError.invalidArguments
        }

        switch name {
        case "open_project":
            guard let projectName = args["project_name"] as? String else {
                throw CommandError.missingParameter("project_name")
            }
            return try await openProject(name: projectName)

        case "open_app":
            guard let appName = args["app_name"] as? String else {
                throw CommandError.missingParameter("app_name")
            }
            return try openApp(name: appName)

        case "open_url":
            guard let urlString = args["url"] as? String else {
                throw CommandError.missingParameter("url")
            }
            return try openURL(urlString: urlString)

        case "run_shell":
            guard let command = args["command"] as? String else {
                throw CommandError.missingParameter("command")
            }
            return try await runShell(command: command)

        default:
            throw CommandError.unknownTool(name)
        }
    }

    // MARK: - Tool Implementations

    private func openProject(name: String) async throws -> String {
        // Load projects from command prompt or a config file
        let projects = getConfiguredProjects()

        guard let projectPath = projects[name.lowercased()] else {
            throw CommandError.projectNotFound(name)
        }

        // Expand ~ to home directory
        let expandedPath = (projectPath as NSString).expandingTildeInPath

        // Check if VS Code is already open with this project
        // Open with VS Code using 'code' command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["code", expandedPath]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            logger.notice("Opened project: \(name) at \(expandedPath)")
            return "Opened \(name) in VS Code"
        } else {
            throw CommandError.executionFailed("Failed to open VS Code")
        }
    }

    private func openApp(name: String) throws -> String {
        let workspace = NSWorkspace.shared

        // Try to find and launch the app
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier(for: name)) {
            let config = NSWorkspace.OpenConfiguration()
            workspace.openApplication(at: appURL, configuration: config)
            return "Opened \(name)"
        }

        // Fallback: try opening by name
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", name]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            return "Opened \(name)"
        } else {
            throw CommandError.appNotFound(name)
        }
    }

    private func openURL(urlString: String) throws -> String {
        guard let url = URL(string: urlString) else {
            throw CommandError.invalidURL(urlString)
        }

        NSWorkspace.shared.open(url)
        return "Opened \(urlString)"
    }

    private func runShell(command: String) async throws -> String {
        // Security check: reject dangerous commands
        let dangerousPatterns = ["rm -rf", "sudo", "mkfs", "dd if=", "> /dev/"]
        for pattern in dangerousPatterns {
            if command.contains(pattern) {
                throw CommandError.dangerousCommand(command)
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus == 0 {
            return output.isEmpty ? "Command executed successfully" : output
        } else {
            throw CommandError.executionFailed(output)
        }
    }

    // MARK: - Configuration Helpers

    /// Load project configurations from the command prompt file
    /// Format in prompt: "- ProjectName: /path/to/project"
    private func getConfiguredProjects() -> [String: String] {
        guard let promptContent = PromptManager.shared.loadPrompt(named: "command") else {
            return [:]
        }

        var projects: [String: String] = [:]
        let lines = promptContent.components(separatedBy: .newlines)

        for line in lines {
            // Match lines like "- Parakeet: ~/code/Parakeet"
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("-") {
                let content = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                let parts = content.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    let name = String(parts[0]).trimmingCharacters(in: .whitespaces).lowercased()
                    let path = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    projects[name] = path
                }
            }
        }

        logger.notice("Loaded \(projects.count) projects from command prompt")
        return projects
    }

    private func getConfiguredProjectNames() -> [String] {
        return Array(getConfiguredProjects().keys).sorted()
    }

    private func bundleIdentifier(for appName: String) -> String {
        // Common app bundle identifiers
        let knownApps: [String: String] = [
            "safari": "com.apple.Safari",
            "finder": "com.apple.finder",
            "terminal": "com.apple.Terminal",
            "xcode": "com.apple.dt.Xcode",
            "vscode": "com.microsoft.VSCode",
            "code": "com.microsoft.VSCode",
            "slack": "com.tinyspeck.slackmacgap",
            "discord": "com.hnc.Discord",
            "chrome": "com.google.Chrome",
            "firefox": "org.mozilla.firefox"
        ]
        return knownApps[appName.lowercased()] ?? "com.apple.\(appName)"
    }
}

// MARK: - Errors

enum CommandError: LocalizedError {
    case invalidArguments
    case missingParameter(String)
    case unknownTool(String)
    case projectNotFound(String)
    case appNotFound(String)
    case invalidURL(String)
    case dangerousCommand(String)
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "Invalid arguments for tool call"
        case .missingParameter(let param):
            return "Missing required parameter: \(param)"
        case .unknownTool(let name):
            return "Unknown tool: \(name)"
        case .projectNotFound(let name):
            return "Project not found: \(name)"
        case .appNotFound(let name):
            return "Application not found: \(name)"
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .dangerousCommand(let cmd):
            return "Refused to execute dangerous command: \(cmd)"
        case .executionFailed(let msg):
            return "Execution failed: \(msg)"
        }
    }
}
```

---

## Phase 5: Update DictationManager

### 5.1 Handle Command Mode in processRecording

**File:** `DictationManager.swift` - in `processRecording(url:)` method

After the existing enhanced/reply mode handling, add command mode:

```swift
// Check if we're in command mode
if currentMode == .command {
    state = .enhancing  // Reuse enhancing state for tool processing
    logger.notice("Processing voice command...")

    let commandExecutor = CommandExecutorService.shared
    let tools = commandExecutor.getToolDefinitions()

    // Build messages with command prompt
    var systemPrompt = "You are a voice command assistant. Execute the user's spoken command using the available tools."
    if let prompt = currentPrompt {
        systemPrompt = prompt
    }

    let messages = [
        ChatMessage(role: "system", content: systemPrompt),
        ChatMessage(role: "user", content: transcription)
    ]

    let result = try await llmClient.chatWithTools(messages: messages, tools: tools)

    switch result {
    case .content(let content):
        // LLM responded with text instead of tool call
        logger.notice("LLM returned text response: \(content.prefix(50))...")
        // Could paste this or show notification

    case .toolCalls(let toolCalls):
        // Execute each tool call
        for toolCall in toolCalls {
            do {
                let output = try await commandExecutor.execute(toolCall: toolCall)
                logger.notice("Tool executed successfully: \(output)")
                // Optionally show notification with result
            } catch {
                logger.error("Tool execution failed: \(error.localizedDescription)")
                state = .error("Command failed: \(error.localizedDescription)")
                // ... error handling
            }
        }
    }

    indicatorManager.hide()
    hotkeyManager.cancelRecording()
    state = .idle
    return
}
```

---

## Phase 6: Create Command Prompt

### 6.1 Create Default Command Prompt

**File:** `Resources/prompts/command.md` (bundle with app)

```markdown
You are a voice command assistant for a macOS dictation app. The user will speak commands.

## Available Projects

These are the user's coding projects. When they say "open [name]", use the open_project tool:

- Parakeet: ~/code/Parakeet
- ParaDict: ~/code/ParaDict
- VoiceInk: ~/code/VoiceInk

## Guidelines

1. Match project names flexibly (e.g., "Parakeet", "parakeet", "pair of keet" should all match "Parakeet")
2. For ambiguous commands, prefer the most likely interpretation
3. If the command doesn't match any tool, respond with helpful text
4. Never ask for confirmation - execute the command directly

## Examples

- "open Parakeet" → open_project("Parakeet")
- "open Safari" → open_app("Safari")
- "open github.com" → open_url("https://github.com")
- "show me the desktop" → run_shell("open ~/Desktop")
```

---

## Phase 7: Configuration

### 7.1 Add Shortcut to config.yaml

Users can add this to their config:

```yaml
shortcuts:
  - name: command
    shortcut: "ctrl+cmd+c"
    mode: command
    prompt_file: command
```

---

## Implementation Order

1. **Phase 2:** Add tool calling structs to `LLMClient.swift`
2. **Phase 3:** Add `chatWithTools()` method to `LLMClient.swift`
3. **Phase 1:** Add `.command` case to `DictationMode`
4. **Phase 4:** Create `CommandExecutorService.swift`
5. **Phase 6:** Create `command.md` prompt file
6. **Phase 5:** Update `DictationManager` to handle command mode
7. **Phase 7:** Update default config

---

## Files Summary

### New Files

| File | Purpose |
|------|---------|
| `Services/CommandExecutorService.swift` | Tool definitions and execution |
| `Resources/prompts/command.md` | System prompt with project list |

### Modified Files

| File | Changes |
|------|---------|
| `ConfigManager.swift` | Add `.command` to `DictationMode`, add default shortcut |
| `Services/LLMClient.swift` | Add tool calling types and `chatWithTools()` method |
| `DictationManager.swift` | Handle `.command` mode in `processRecording()` |

---

## Testing Plan

1. **Unit test tool definitions:** Verify JSON encoding matches OpenAI format
2. **Test tool parsing:** Mock LLM response and verify `ToolCall` decoding
3. **Test project matching:** Verify case-insensitive fuzzy matching works
4. **Integration test:** Say "open Parakeet" and verify VS Code opens
5. **Error cases:** Test unknown project, missing VS Code, invalid commands

---

## Future Enhancements

- **Multi-turn conversation:** Return tool results to LLM for confirmation
- **Notification feedback:** Show macOS notification when command executes
- **Custom tools:** Let users define tools in config file
- **Tool result pasting:** Option to paste tool output at cursor
- **Voice confirmation:** "Did you mean Parakeet?" before executing
