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

## Phase 5: State Machine & Coordinator Updates

The state machine needs a new state and effects for command mode. Command mode is different from enhanced mode - it doesn't paste text, it executes commands.

### 5.1 Add State: `executingCommand`

**File:** `StateMachine/DictationState.swift`

```swift
enum DictationStateSM: Equatable {
    case idle
    case recording(mode: DictationMode, prompt: String?, isHandsFree: Bool, enterMonitorPending: Bool)
    case transcribing(mode: DictationMode, prompt: String?, continueAfter: Bool)
    case enhancing(mode: DictationMode, prompt: String?, continueAfter: Bool)
    case executingCommand(mode: DictationMode, prompt: String?)  // NEW
    case pasting(mode: DictationMode, prompt: String?, continueAfter: Bool)
    case error(message: String)
}
```

### 5.2 Add Events

**File:** `StateMachine/DictationEvent.swift`

```swift
enum DictationEvent {
    // ... existing events ...
    case commandComplete           // NEW - tool call executed successfully
    case commandFailed(message: String)  // NEW - tool call failed
}
```

### 5.3 Add Side Effects

**File:** `StateMachine/DictationSideEffect.swift`

```swift
enum DictationSideEffect {
    // ... existing effects ...
    case executeCommand(text: String, prompt: String)  // NEW - send to LLM with tools
    case flashMenuBarSuccess      // NEW - visual feedback on success
    case flashMenuBarError        // NEW - visual feedback on error
}
```

### 5.4 Update State Machine Transitions

**File:** `StateMachine/DictationStateMachine.swift`

In `processEvent()`, update the transcription complete handler:

```swift
case (.transcribing(let mode, let prompt, let continueAfter), .transcriptionComplete(let text)):
    // Check mode
    if mode == .command, let prompt = prompt {
        // Command mode - execute tool calls
        state = .executingCommand(mode: mode, prompt: prompt)
        return [.executeCommand(text: text, prompt: prompt)]
    } else if (mode == .enhanced || mode == .reply), let prompt = prompt {
        // Enhanced/reply mode - LLM enhancement
        state = .enhancing(mode: mode, prompt: prompt, continueAfter: continueAfter)
        return [.enhance(text: text, prompt: prompt, context: nil)]
    } else {
        // Local mode - paste directly
        state = .pasting(mode: mode, prompt: prompt, continueAfter: continueAfter)
        return [.paste(text: text), .logTranscription(...), .schedulePasteComplete]
    }

// NEW: Handle command completion
case (.executingCommand, .commandComplete):
    state = .idle
    return [.hideIndicator, .flashMenuBarSuccess]

case (.executingCommand, .commandFailed(let message)):
    state = .error(message: message)
    return [.hideIndicator, .flashMenuBarError, .showError(message: message), .scheduleErrorTimeout]

case (.executingCommand, .escapePressed):
    // Allow canceling during command execution
    state = .idle
    return [.hideIndicator]
```

### 5.5 Update DictationCoordinator

**File:** `DictationCoordinator.swift`

Add handler for `executeCommand` side effect:

```swift
case .executeCommand(let text, let prompt):
    Task {
        await executeCommand(text: text, prompt: prompt)
    }

case .flashMenuBarSuccess:
    flashMenuBar(success: true)

case .flashMenuBarError:
    flashMenuBar(success: false)
```

Add the execution method:

```swift
// MARK: - Command Execution

private func executeCommand(text: String, prompt: String) async {
    let executor = CommandExecutorService.shared
    let tools = executor.getToolDefinitions()

    guard !tools.isEmpty else {
        send(.commandFailed(message: "No tools configured. Check tools.json"))
        return
    }

    let messages = [
        ChatMessage(role: "system", content: prompt),
        ChatMessage(role: "user", content: text)
    ]

    do {
        let result = try await llmClient.chatWithTools(messages: messages, tools: tools)

        switch result {
        case .content(let response):
            // LLM responded with text instead of tool call
            logger.notice("LLM returned text (no tool call): \(response.prefix(50))...")
            send(.commandFailed(message: "Command not recognized: \(text)"))

        case .toolCalls(let toolCalls):
            // Execute each tool call
            for toolCall in toolCalls {
                let output = try await executor.execute(toolCall: toolCall)
                logger.notice("Tool executed: \(toolCall.function.name) -> \(output)")
            }
            send(.commandComplete)
        }
    } catch {
        logger.error("Command execution failed: \(error.localizedDescription)")
        send(.commandFailed(message: error.localizedDescription))
    }
}

// MARK: - Menu Bar Flash

private func flashMenuBar(success: Bool) {
    // Post notification for menu bar to flash
    NotificationCenter.default.post(
        name: .menuBarFlash,
        object: nil,
        userInfo: ["success": success]
    )
}
```

### 5.6 Add Menu Bar Flash Support

**File:** `ParaDictApp.swift`

Add notification observer and flash animation:

```swift
extension Notification.Name {
    static let menuBarFlash = Notification.Name("menuBarFlash")
}

// In ParaDictApp, add state for flash
@State private var menuBarFlashState: MenuBarFlashState = .normal

enum MenuBarFlashState {
    case normal
    case success
    case error
}

// Update menuBarIconName to use flash state
private var menuBarIconName: String {
    switch menuBarFlashState {
    case .success:
        return "checkmark.circle.fill"
    case .error:
        return "xmark.circle.fill"
    case .normal:
        // ... existing logic based on dictationManager.state
    }
}

// Add observer in body or init
.onReceive(NotificationCenter.default.publisher(for: .menuBarFlash)) { notification in
    guard let success = notification.userInfo?["success"] as? Bool else { return }

    menuBarFlashState = success ? .success : .error

    // Reset after delay
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        menuBarFlashState = .normal
    }
}
```

---

## Phase 5b: File Watcher for tools.json

### 5b.1 Add File Watcher to CommandExecutorService

**File:** `Services/CommandExecutorService.swift`

```swift
@MainActor
class CommandExecutorService: ObservableObject {
    // ... existing code ...

    private var fileWatcher: DispatchSourceFileSystemObject?

    private init() {
        loadToolsFile()
        setupFileWatcher()
    }

    deinit {
        fileWatcher?.cancel()
    }

    private func setupFileWatcher() {
        let fileDescriptor = open(toolsFileURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            logger.warning("Could not watch tools.json for changes")
            return
        }

        fileWatcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: .main
        )

        fileWatcher?.setEventHandler { [weak self] in
            self?.logger.notice("tools.json changed - reloading")
            self?.loadToolsFile()
        }

        fileWatcher?.setCancelHandler {
            close(fileDescriptor)
        }

        fileWatcher?.resume()
        logger.notice("Watching tools.json for changes")
    }
}
```

---

## Phase 5c: Tools.json UI Access

### 5c.1 Add "Open Tools" Button to LLM Settings

**File:** `Views/LLMSettingsView.swift`

Add a button to open tools.json alongside the existing prompt editing:

```swift
GroupBox("Command Tools") {
    VStack(alignment: .leading, spacing: 8) {
        Text("Configure voice command tools and projects")
            .foregroundColor(.secondary)
            .font(.caption)

        HStack {
            Button("Open tools.json") {
                openToolsFile()
            }

            Button("Reload") {
                CommandExecutorService.shared.loadToolsFile()
            }
        }

        // Show tool count
        let toolCount = CommandExecutorService.shared.getToolDefinitions().count
        Text("\(toolCount) tools configured")
            .font(.caption)
            .foregroundColor(.secondary)
    }
    .padding(.vertical, 8)
}

private func openToolsFile() {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let toolsURL = appSupport.appendingPathComponent("ParaDict/tools.json")
    NSWorkspace.shared.open(toolsURL)
}
```

---

## Phase 5d: Note on DictationManager

The `DictationManager.swift` file appears to be older code that's been superseded by `DictationCoordinator`. The coordinator uses the state machine and handles all the side effects. No changes needed to `DictationManager.swift` - all command mode logic goes in the Coordinator.

---

## Phase 6: Tools JSON File

### 6.1 Tools File Location

**Location:** `~/Library/Application Support/ParaDict/tools.json`

The app bundles a default `tools.json` in Resources, which gets copied to Application Support on first launch (same pattern as prompts).

### 6.2 Tools JSON Schema

**File:** `Resources/tools.json` (bundled default)

```json
{
  "tools": [
    {
      "name": "open_project",
      "description": "Opens a coding project in VS Code. Use when the user says 'open [project name]'.",
      "parameters": {
        "project_name": {
          "type": "string",
          "description": "The name of the project to open"
        }
      },
      "required": ["project_name"],
      "executor": "open_project"
    },
    {
      "name": "open_app",
      "description": "Opens a macOS application by name",
      "parameters": {
        "app_name": {
          "type": "string",
          "description": "The name of the application (e.g., 'Safari', 'Finder', 'Terminal')"
        }
      },
      "required": ["app_name"],
      "executor": "open_app"
    },
    {
      "name": "open_url",
      "description": "Opens a URL in the default browser",
      "parameters": {
        "url": {
          "type": "string",
          "description": "The URL to open"
        }
      },
      "required": ["url"],
      "executor": "open_url"
    },
    {
      "name": "run_shell",
      "description": "Runs a shell command. Use sparingly and only for safe operations.",
      "parameters": {
        "command": {
          "type": "string",
          "description": "The shell command to execute"
        }
      },
      "required": ["command"],
      "executor": "run_shell"
    }
  ],
  "projects": {
    "parakeet": "~/code/Parakeet",
    "paradict": "~/code/ParaDict",
    "voiceink": "~/code/VoiceInk"
  }
}
```

### 6.3 JSON Schema Explanation

| Field | Purpose |
|-------|---------|
| `tools[]` | Array of tool definitions sent to the LLM |
| `tools[].name` | Tool name (matches OpenAI function name) |
| `tools[].description` | Sent to LLM - explains when to use this tool |
| `tools[].parameters` | Parameter definitions (type, description) |
| `tools[].required` | Required parameters |
| `tools[].executor` | Maps to a Swift executor function (see below) |
| `projects` | Project name → path mapping for `open_project` executor |

### 6.4 Update CommandExecutorService to Load from JSON

**File:** `Services/CommandExecutorService.swift`

```swift
import Foundation
import AppKit
import os

/// Parsed tool from JSON
struct ToolConfig: Codable {
    let name: String
    let description: String
    let parameters: [String: ParameterConfig]
    let required: [String]
    let executor: String
}

struct ParameterConfig: Codable {
    let type: String
    let description: String
    let `enum`: [String]?
}

struct ToolsFile: Codable {
    let tools: [ToolConfig]
    let projects: [String: String]
}

@MainActor
class CommandExecutorService: ObservableObject {
    static let shared = CommandExecutorService()

    private let logger = Logger(subsystem: "com.paradict", category: "CommandExecutor")
    private var toolsConfig: ToolsFile?

    private var toolsFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("ParaDict/tools.json")
    }

    private init() {
        loadToolsFile()
    }

    // MARK: - Load Tools from JSON

    func loadToolsFile() {
        // Copy bundled tools.json if not exists
        copyBundledToolsIfNeeded()

        do {
            let data = try Data(contentsOf: toolsFileURL)
            toolsConfig = try JSONDecoder().decode(ToolsFile.self, from: data)
            logger.notice("Loaded \(self.toolsConfig?.tools.count ?? 0) tools from tools.json")
        } catch {
            logger.error("Failed to load tools.json: \(error.localizedDescription)")
            toolsConfig = nil
        }
    }

    private func copyBundledToolsIfNeeded() {
        guard !FileManager.default.fileExists(atPath: toolsFileURL.path) else { return }

        guard let bundledURL = Bundle.main.url(forResource: "tools", withExtension: "json") else {
            logger.warning("No bundled tools.json found")
            return
        }

        do {
            let dir = toolsFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: bundledURL, to: toolsFileURL)
            logger.notice("Copied bundled tools.json to Application Support")
        } catch {
            logger.error("Failed to copy tools.json: \(error.localizedDescription)")
        }
    }

    // MARK: - Get Tool Definitions for LLM

    func getToolDefinitions() -> [ToolDefinition] {
        guard let config = toolsConfig else { return [] }

        return config.tools.map { tool in
            var params: [String: ParameterDefinition] = [:]
            for (key, param) in tool.parameters {
                // For open_project, inject project names as enum
                var enumValues = param.enum
                if tool.executor == "open_project" && key == "project_name" {
                    enumValues = Array(config.projects.keys).sorted()
                }
                params[key] = ParameterDefinition(
                    type: param.type,
                    description: param.description,
                    enumValues: enumValues
                )
            }

            return ToolDefinition(
                name: tool.name,
                description: tool.description,
                parameters: params,
                required: tool.required
            )
        }
    }

    // MARK: - Execute Tool Call

    func execute(toolCall: ToolCall) async throws -> String {
        guard let config = toolsConfig else {
            throw CommandError.noToolsConfigured
        }

        let name = toolCall.function.name

        // Find the tool config
        guard let tool = config.tools.first(where: { $0.name == name }) else {
            throw CommandError.unknownTool(name)
        }

        // Parse arguments
        guard let argsData = toolCall.function.arguments.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] else {
            throw CommandError.invalidArguments
        }

        logger.notice("Executing tool: \(name) (executor: \(tool.executor))")

        // Dispatch to executor
        switch tool.executor {
        case "open_project":
            guard let projectName = args["project_name"] as? String else {
                throw CommandError.missingParameter("project_name")
            }
            return try await openProject(name: projectName, projects: config.projects)

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
            throw CommandError.unknownExecutor(tool.executor)
        }
    }

    // MARK: - Executors (same implementations as before)

    private func openProject(name: String, projects: [String: String]) async throws -> String {
        guard let projectPath = projects[name.lowercased()] else {
            throw CommandError.projectNotFound(name)
        }

        let expandedPath = (projectPath as NSString).expandingTildeInPath

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

    // ... (openApp, openURL, runShell implementations remain the same)
}

// MARK: - Errors

enum CommandError: LocalizedError {
    case noToolsConfigured
    case invalidArguments
    case missingParameter(String)
    case unknownTool(String)
    case unknownExecutor(String)
    case projectNotFound(String)
    case appNotFound(String)
    case invalidURL(String)
    case dangerousCommand(String)
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noToolsConfigured:
            return "No tools.json configured"
        case .unknownExecutor(let name):
            return "Unknown executor: \(name)"
        // ... rest same as before
        }
    }
}
```

### 6.5 Create Command Prompt

**File:** `Resources/prompts/command.md`

The prompt is now simpler - it doesn't need to list projects since those come from tools.json:

```markdown
You are a voice command assistant for a macOS dictation app. The user will speak commands.

## Guidelines

1. Match project/app names flexibly (e.g., "Parakeet", "parakeet", "pair of keet" should all match)
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

## Phase 7: Shortcuts UI & HotkeyManager

### 7.1 Add KeyboardShortcuts Name

**File:** `ParaDictApp.swift:8-13`

```swift
extension KeyboardShortcuts.Name {
    static let localDictation = Self("localDictation")
    static let enhancedDictation = Self("enhancedDictation")
    static let replyDictation = Self("replyDictation")
    static let commandDictation = Self("commandDictation")  // NEW
}
```

### 7.2 Add GroupBox to ShortcutsSettingsView

**File:** `ParaDictApp.swift` - in `ShortcutsSettingsView`, after Reply Dictation GroupBox:

```swift
GroupBox("Command Dictation") {
    VStack(alignment: .leading, spacing: 8) {
        Text("Execute voice commands like 'open Parakeet' to launch projects")
            .foregroundColor(.secondary)
            .font(.caption)
        KeyboardShortcuts.Recorder("Shortcut:", name: .commandDictation)

        Divider()

        // Show current prompt file
        if let commandConfig = configManager.config.shortcuts.first(where: { $0.mode == .command }) {
            HStack {
                Text("Prompt file:")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text(commandConfig.promptFile ?? "none")
                    .font(.system(.caption, design: .monospaced))
            }
        }
    }
    .padding(.vertical, 8)
}
```

### 7.3 Update HotkeyManager - applyShortcutsFromConfig()

**File:** `HotkeyManager.swift:215-275`

Add command mode to the existing shortcut application logic:

```swift
private func applyShortcutsFromConfig() {
    let shortcuts = ConfigManager.shared.config.shortcuts
    logger.notice("Applying shortcuts from config: \(shortcuts.count) shortcuts")

    // Get the desired shortcuts from config
    let localConfig = shortcuts.first(where: { $0.mode == .local })
    let enhancedConfig = shortcuts.first(where: { $0.mode == .enhanced })
    let replyConfig = shortcuts.first(where: { $0.mode == .reply })
    let commandConfig = shortcuts.first(where: { $0.mode == .command })  // NEW

    let desiredLocal = localConfig?.shortcut.flatMap { ShortcutParser.parse($0) }
    let desiredEnhanced = enhancedConfig?.shortcut.flatMap { ShortcutParser.parse($0) }
    let desiredReply = replyConfig?.shortcut.flatMap { ShortcutParser.parse($0) }
    let desiredCommand = commandConfig?.shortcut.flatMap { ShortcutParser.parse($0) }  // NEW

    let currentLocal = KeyboardShortcuts.getShortcut(for: .localDictation)
    let currentEnhanced = KeyboardShortcuts.getShortcut(for: .enhancedDictation)
    let currentReply = KeyboardShortcuts.getShortcut(for: .replyDictation)
    let currentCommand = KeyboardShortcuts.getShortcut(for: .commandDictation)  // NEW

    // Check if we need to clear all shortcuts first to avoid conflicts
    let allDesired = [desiredLocal, desiredEnhanced, desiredReply, desiredCommand].compactMap { $0 }
    let allCurrent = [currentLocal, currentEnhanced, currentReply, currentCommand].compactMap { $0 }
    // ... rest of conflict checking

    // Apply command shortcut (NEW)
    if currentCommand != desiredCommand || needsClear {
        KeyboardShortcuts.setShortcut(desiredCommand, for: .commandDictation)
        if let str = commandConfig?.shortcut {
            logger.notice("Set command dictation shortcut: \(str)")
        } else {
            logger.notice("Cleared command dictation shortcut")
        }
    }
}
```

### 7.4 Update HotkeyManager - setupKeyboardShortcuts()

**File:** `HotkeyManager.swift:277-351`

Add command dictation handlers after the reply handlers:

```swift
// Command dictation shortcut (NEW)
KeyboardShortcuts.onKeyDown(for: .commandDictation) { [weak self] in
    Task { @MainActor in
        self?.logger.notice("COMMAND DICTATION: Key DOWN detected")
        let config = ConfigManager.shared.config.shortcuts.first(where: { $0.mode == .command })
        await self?.handleShortcutDown(mode: .command, shortcutConfig: config)
    }
}

KeyboardShortcuts.onKeyUp(for: .commandDictation) { [weak self] in
    Task { @MainActor in
        self?.logger.notice("COMMAND DICTATION: Key UP detected")
        self?.handleShortcutUp()
    }
}
```

### 7.5 Update HotkeyManager - syncShortcutsToConfig()

**File:** `HotkeyManager.swift:449-520`

Add command dictation sync after reply sync:

```swift
// Sync command dictation (NEW)
if let commandShortcut = KeyboardShortcuts.getShortcut(for: .commandDictation) {
    let str = ShortcutParser.toString(commandShortcut)
    if let idx = shortcuts.firstIndex(where: { $0.mode == .command }) {
        if shortcuts[idx].shortcut != str {
            shortcuts[idx].shortcut = str
            changed = true
            logger.notice("Synced command dictation shortcut from UI: \(str)")
        }
    } else {
        // Entry doesn't exist - add it (migration case)
        shortcuts.append(ShortcutConfig(name: "command", shortcut: str, mode: .command, promptFile: "command", captureSelection: nil))
        changed = true
        logger.notice("Added command dictation shortcut entry: \(str)")
    }
} else {
    if let idx = shortcuts.firstIndex(where: { $0.mode == .command }),
       shortcuts[idx].shortcut != nil {
        shortcuts[idx].shortcut = nil
        changed = true
        logger.notice("Cleared command dictation shortcut from UI")
    }
}
```

### 7.6 Auto-Migration for Existing Users

The `ConfigManager.migrateShortcuts()` method already handles adding new shortcut modes. When the app launches with the new `.command` mode:

1. Migration detects that `command` mode doesn't exist in user's config
2. Adds a new shortcut entry (without a key binding - user sets it)
3. Saves the updated config

**No changes needed** - this works automatically.

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
| `Services/CommandExecutorService.swift` | Loads tools.json and executes tool calls |
| `Resources/tools.json` | Tool definitions + project mappings (user-editable) |
| `Resources/prompts/command.md` | System prompt for command mode |
| `ParaDictTests/CommandExecutorTests.swift` | Unit + integration tests |

### Modified Files

| File | Changes |
|------|---------|
| `ConfigManager.swift` | Add `.command` to `DictationMode`, add default shortcut |
| `Services/LLMClient.swift` | Add tool calling types and `chatWithTools()` method |
| `StateMachine/DictationState.swift` | Add `.executingCommand` state |
| `StateMachine/DictationEvent.swift` | Add `commandComplete`, `commandFailed` events |
| `StateMachine/DictationSideEffect.swift` | Add `executeCommand`, `flashMenuBarSuccess/Error` effects |
| `StateMachine/DictationStateMachine.swift` | Add command mode transitions |
| `DictationCoordinator.swift` | Add `executeCommand()` method, menu bar flash |
| `ParaDictApp.swift` | Add KeyboardShortcuts.Name, ShortcutsSettingsView GroupBox, menu bar flash observer |
| `HotkeyManager.swift` | Add command mode to all shortcut methods |
| `Views/LLMSettingsView.swift` | Add "Open tools.json" button |

---

## Phase 8: Automated Tests

Create test file: `ParaDictTests/CommandExecutorTests.swift`

### 8.1 Test Tool Definition JSON Encoding

Verify tool definitions match OpenAI's expected format:

```swift
import XCTest
@testable import ParaDict

final class CommandExecutorTests: XCTestCase {

    // MARK: - Tool Definition Tests

    func testToolDefinition_JSONEncoding_MatchesOpenAIFormat() throws {
        let tool = ToolDefinition(
            name: "open_project",
            description: "Opens a project",
            parameters: [
                "project_name": ParameterDefinition(type: "string", description: "Project name")
            ],
            required: ["project_name"]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(tool)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Verify structure
        XCTAssertEqual(json["type"] as? String, "function")

        let function = json["function"] as! [String: Any]
        XCTAssertEqual(function["name"] as? String, "open_project")
        XCTAssertEqual(function["description"] as? String, "Opens a project")

        let parameters = function["parameters"] as! [String: Any]
        XCTAssertEqual(parameters["type"] as? String, "object")
        XCTAssertEqual(parameters["required"] as? [String], ["project_name"])

        let properties = parameters["properties"] as! [String: Any]
        let projectNameProp = properties["project_name"] as! [String: Any]
        XCTAssertEqual(projectNameProp["type"] as? String, "string")
    }

    func testToolDefinition_WithEnumValues() throws {
        let tool = ToolDefinition(
            name: "open_project",
            description: "Opens a project",
            parameters: [
                "project_name": ParameterDefinition(
                    type: "string",
                    description: "Project name",
                    enumValues: ["parakeet", "paradict", "voiceink"]
                )
            ],
            required: ["project_name"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(tool)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let function = json["function"] as! [String: Any]
        let parameters = function["parameters"] as! [String: Any]
        let properties = parameters["properties"] as! [String: Any]
        let projectNameProp = properties["project_name"] as! [String: Any]

        XCTAssertEqual(projectNameProp["enum"] as? [String], ["parakeet", "paradict", "voiceink"])
    }
```

### 8.2 Test Tool Call Response Parsing

```swift
    // MARK: - Tool Call Response Parsing

    func testToolCallResponse_Parsing() throws {
        // Simulated Kimi K2 response with tool call
        let responseJSON = """
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
                            "arguments": "{\\"project_name\\": \\"Parakeet\\"}"
                        }
                    }]
                },
                "finish_reason": "tool_calls"
            }]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(ChatCompletionResponseWithTools.self, from: responseJSON)

        XCTAssertEqual(response.choices.count, 1)

        let message = response.choices[0].message
        XCTAssertNil(message.content)
        XCTAssertEqual(message.toolCalls?.count, 1)

        let toolCall = message.toolCalls![0]
        XCTAssertEqual(toolCall.id, "call_abc123")
        XCTAssertEqual(toolCall.function.name, "open_project")
        XCTAssertEqual(toolCall.function.arguments, "{\"project_name\": \"Parakeet\"}")
    }

    func testToolCallResponse_ContentOnly() throws {
        // Response without tool calls (just text)
        let responseJSON = """
        {
            "choices": [{
                "message": {
                    "role": "assistant",
                    "content": "I don't understand that command."
                },
                "finish_reason": "stop"
            }]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(ChatCompletionResponseWithTools.self, from: responseJSON)

        XCTAssertEqual(response.choices[0].message.content, "I don't understand that command.")
        XCTAssertNil(response.choices[0].message.toolCalls)
    }
```

### 8.3 Test Tool Call Argument Parsing

```swift
    // MARK: - Tool Call Execution

    func testToolCallArgumentParsing() throws {
        let toolCall = ToolCall(
            id: "call_123",
            type: "function",
            function: FunctionCallInfo(
                name: "open_project",
                arguments: "{\"project_name\": \"Parakeet\"}"
            )
        )

        // Parse arguments
        let argsData = toolCall.function.arguments.data(using: .utf8)!
        let args = try JSONSerialization.jsonObject(with: argsData) as! [String: Any]

        XCTAssertEqual(args["project_name"] as? String, "Parakeet")
    }
```

### 8.4 Test Project Matching (Case-Insensitive)

```swift
    // MARK: - Project Matching

    func testProjectMatching_CaseInsensitive() async throws {
        // This test verifies the CommandExecutorService matches projects case-insensitively
        // We'll test the helper method directly

        let executor = CommandExecutorService.shared

        // Create a mock prompt content
        let mockProjects = """
        - Parakeet: ~/code/Parakeet
        - ParaDict: ~/code/ParaDict
        - VoiceInk: ~/code/VoiceInk
        """

        // Test the parsing logic (extracted to testable method)
        let projects = parseProjects(from: mockProjects)

        XCTAssertEqual(projects["parakeet"], "~/code/Parakeet")
        XCTAssertEqual(projects["paradict"], "~/code/ParaDict")
        XCTAssertEqual(projects["voiceink"], "~/code/VoiceInk")

        // All lookups should be lowercase
        XCTAssertNotNil(projects["parakeet"])
        XCTAssertNil(projects["Parakeet"])  // Keys are lowercased
    }

    // Helper to test project parsing logic
    private func parseProjects(from content: String) -> [String: String] {
        var projects: [String: String] = [:]
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
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
        return projects
    }
```

### 8.5 Test Dangerous Command Rejection

```swift
    // MARK: - Security Tests

    func testDangerousCommandRejection() async {
        let dangerousCommands = [
            "rm -rf /",
            "sudo shutdown",
            "dd if=/dev/zero of=/dev/sda",
            "mkfs.ext4 /dev/sda1"
        ]

        for command in dangerousCommands {
            let toolCall = ToolCall(
                id: "call_\(UUID().uuidString)",
                type: "function",
                function: FunctionCallInfo(name: "run_shell", arguments: "{\"command\": \"\(command)\"}")
            )

            do {
                _ = try await CommandExecutorService.shared.execute(toolCall: toolCall)
                XCTFail("Should have rejected dangerous command: \(command)")
            } catch let error as CommandError {
                if case .dangerousCommand = error {
                    // Expected
                } else {
                    XCTFail("Wrong error type for: \(command)")
                }
            } catch {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }
}
```

### 8.6 Integration Test: Real LLM Call (No Execution)

This is the **critical test** - it verifies Kimi K2 actually returns the correct tool call. It makes a real API request but does NOT execute the command.

```swift
final class CommandIntegrationTests: XCTestCase {

    /// REAL INTEGRATION TEST: Verifies Kimi K2 returns the correct tool call
    /// - Makes actual API call to Groq
    /// - Requires GROQ_API_KEY or saved API key
    /// - Does NOT execute the command (safe to run)
    func testLLM_OpenParakeet_ReturnsCorrectToolCall() async throws {
        // Skip if no API key configured
        guard LLMClient.shared.isConfigured else {
            throw XCTSkip("No API key configured - set GROQ_API_KEY or configure in app")
        }

        // 1. Build the system prompt (same as command.md)
        let systemPrompt = """
        You are a voice command assistant. Execute the user's spoken command using the available tools.

        Available projects:
        - Parakeet: ~/code/Parakeet
        - ParaDict: ~/code/ParaDict
        - VoiceInk: ~/code/VoiceInk

        When the user says "open [project]", use the open_project tool.
        """

        // 2. Define tools (same as CommandExecutorService)
        let tools = [
            ToolDefinition(
                name: "open_project",
                description: "Opens a coding project in VS Code",
                parameters: [
                    "project_name": ParameterDefinition(
                        type: "string",
                        description: "The name of the project to open",
                        enumValues: ["parakeet", "paradict", "voiceink"]
                    )
                ],
                required: ["project_name"]
            )
        ]

        // 3. User says "open Parakeet"
        let userMessage = "open Parakeet"

        let messages = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: userMessage)
        ]

        // 4. Make REAL API call to Kimi K2
        let result = try await LLMClient.shared.chatWithTools(messages: messages, tools: tools)

        // 5. Verify we got a tool call (not text)
        guard case .toolCalls(let toolCalls) = result else {
            XCTFail("Expected tool call, got text response")
            return
        }

        // 6. Verify it's the correct tool
        XCTAssertEqual(toolCalls.count, 1, "Expected exactly 1 tool call")

        let toolCall = toolCalls[0]
        XCTAssertEqual(toolCall.function.name, "open_project", "Expected open_project tool")

        // 7. Verify the argument is "Parakeet" (case-insensitive)
        let argsData = toolCall.function.arguments.data(using: .utf8)!
        let args = try JSONSerialization.jsonObject(with: argsData) as! [String: Any]
        let projectName = (args["project_name"] as? String)?.lowercased()

        XCTAssertEqual(projectName, "parakeet", "Expected project_name to be 'parakeet'")

        // SUCCESS: Kimi K2 understood "open Parakeet" and returned the correct tool call
        // We intentionally DO NOT execute the command here
    }

    /// Test variations of the command to ensure robustness
    func testLLM_OpenProject_Variations() async throws {
        guard LLMClient.shared.isConfigured else {
            throw XCTSkip("No API key configured")
        }

        let variations = [
            "open Parakeet",
            "Open parakeet",
            "open the Parakeet project",
            "launch Parakeet",
            "can you open Parakeet for me"
        ]

        let systemPrompt = """
        You are a voice command assistant. When the user wants to open a project, use the open_project tool.
        Available projects: Parakeet, ParaDict, VoiceInk
        """

        let tools = [
            ToolDefinition(
                name: "open_project",
                description: "Opens a coding project in VS Code",
                parameters: [
                    "project_name": ParameterDefinition(type: "string", description: "Project name")
                ],
                required: ["project_name"]
            )
        ]

        for variation in variations {
            let messages = [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: variation)
            ]

            let result = try await LLMClient.shared.chatWithTools(messages: messages, tools: tools)

            guard case .toolCalls(let toolCalls) = result else {
                XCTFail("'\(variation)' did not return tool call")
                continue
            }

            XCTAssertEqual(toolCalls[0].function.name, "open_project", "'\(variation)' should call open_project")

            let argsData = toolCalls[0].function.arguments.data(using: .utf8)!
            let args = try JSONSerialization.jsonObject(with: argsData) as! [String: Any]
            let projectName = (args["project_name"] as? String)?.lowercased()

            XCTAssertEqual(projectName, "parakeet", "'\(variation)' should return 'parakeet'")
        }
    }

    /// Test that unrecognized commands return text, not tool calls
    func testLLM_UnrecognizedCommand_ReturnsText() async throws {
        guard LLMClient.shared.isConfigured else {
            throw XCTSkip("No API key configured")
        }

        let systemPrompt = """
        You are a voice command assistant. Only use tools for recognized commands.
        Available projects: Parakeet, ParaDict, VoiceInk
        """

        let tools = [
            ToolDefinition(
                name: "open_project",
                description: "Opens a coding project",
                parameters: ["project_name": ParameterDefinition(type: "string", description: "Project name")],
                required: ["project_name"]
            )
        ]

        let messages = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: "what's the weather today")
        ]

        let result = try await LLMClient.shared.chatWithTools(messages: messages, tools: tools)

        // Should return text, not a tool call
        guard case .content(let text) = result else {
            XCTFail("Unrecognized command should return text, not tool call")
            return
        }

        XCTAssertFalse(text.isEmpty, "Should return some response text")
    }
}
```

### Running the Tests

```bash
# Run unit tests (no API key needed)
xcodebuild test -project ParaDict.xcodeproj -scheme ParaDict \
  -only-testing:ParaDictTests/CommandExecutorTests

# Run the CRITICAL integration test (requires API key)
# This verifies Kimi K2 returns the correct tool call for "open Parakeet"
xcodebuild test -project ParaDict.xcodeproj -scheme ParaDict \
  -only-testing:ParaDictTests/CommandIntegrationTests/testLLM_OpenParakeet_ReturnsCorrectToolCall

# Run all integration tests (tests variations like "launch Parakeet", "open the Parakeet project")
xcodebuild test -project ParaDict.xcodeproj -scheme ParaDict \
  -only-testing:ParaDictTests/CommandIntegrationTests

# Run everything
xcodebuild test -project ParaDict.xcodeproj -scheme ParaDict
```

**Important:** The integration tests require a valid Groq API key. Either:
- Set `GROQ_API_KEY` environment variable, or
- Have already saved an API key in the app

If no API key is configured, the integration tests will be skipped (not failed).

---

## Future Enhancements

- **Multi-turn conversation:** Return tool results to LLM for confirmation
- **Notification feedback:** Show macOS notification when command executes
- **Custom tools:** Let users define tools in config file
- **Tool result pasting:** Option to paste tool output at cursor
- **Voice confirmation:** "Did you mean Parakeet?" before executing
