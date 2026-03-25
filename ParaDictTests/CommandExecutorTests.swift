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

    // MARK: - Project Matching

    @MainActor
    func testDirectProjectPath_ResolvesOpenRobinLocally() {
        let projects = [
            "/Users/sebastian/personal_synced/Robin",
            "/Users/sebastian/code/ParaDict2"
        ]

        let path = ProjectCommandMatcherService.resolveProjectPath(
            command: "open robin",
            recentProjectPaths: projects
        )

        XCTAssertEqual(path, "/Users/sebastian/personal_synced/Robin")
    }

    @MainActor
    func testDirectProjectPath_StripsFillerWordsAndMatchesPrefix() {
        let projects = ["/Users/sebastian/code/ParaDict2"]

        let path = ProjectCommandMatcherService.resolveProjectPath(
            command: "can you open the para dict project for me",
            recentProjectPaths: projects
        )

        XCTAssertEqual(path, "/Users/sebastian/code/ParaDict2")
    }

    @MainActor
    func testDirectProjectPath_IgnoresNonProjectOpenCommands() {
        let projects = ["/Users/sebastian/personal_synced/Robin"]

        let path = ProjectCommandMatcherService.resolveProjectPath(
            command: "open github.com",
            recentProjectPaths: projects
        )

        XCTAssertNil(path)
    }

    func testProjectMatching_CaseInsensitive() {
        // Test the parsing logic
        let mockProjects = """
        - Parakeet: ~/code/Parakeet
        - ParaDict: ~/code/ParaDict
        - VoiceInk: ~/code/VoiceInk
        """

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

    // MARK: - Command Error Tests

    func testCommandErrorDescriptions() {
        let errors: [CommandError] = [
            .noToolsConfigured,
            .invalidArguments,
            .missingParameter("path"),
            .unknownTool("unknown_tool"),
            .unknownExecutor("unknown_executor"),
            .appNotFound("FakeApp"),
            .invalidURL("not a url"),
            .dangerousCommand("rm -rf /"),
            .executionFailed("Something went wrong")
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    // MARK: - State Machine Command Mode Tests

    func testCommandModeTransition_TranscriptionToExecutingCommand() {
        let sut = DictationStateMachine()

        // Start recording in command mode
        _ = sut.handle(.hotkeyDown(mode: .command, prompt: "command prompt", context: nil))
        XCTAssertEqual(sut.state, .recording(mode: .command, prompt: "command prompt", isHandsFree: false, enterMonitorPending: false))

        // Long press to stop
        _ = sut.handle(.hotkeyUp(duration: 1.5))

        // Transcription complete should go to executingCommand, not enhancing
        let effects = sut.handle(.transcriptionComplete(text: "open Parakeet"))

        if case .executingCommand(let mode, let prompt) = sut.state {
            XCTAssertEqual(mode, .command)
            XCTAssertEqual(prompt, "command prompt")
        } else {
            XCTFail("Expected executingCommand state, got \(sut.state)")
        }

        XCTAssertTrue(effects.contains(.executeCommand(text: "open Parakeet", prompt: "command prompt")))
    }

    func testCommandComplete_ReturnsToIdle() {
        let sut = DictationStateMachine()

        // Set up executingCommand state
        sut.setState(.executingCommand(mode: .command, prompt: "test"))

        let effects = sut.handle(.commandComplete)

        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(effects.contains(.hideIndicator))
        XCTAssertTrue(effects.contains(.flashMenuBarSuccess))
    }

    func testCommandFailed_GoesToError() {
        let sut = DictationStateMachine()

        // Set up executingCommand state
        sut.setState(.executingCommand(mode: .command, prompt: "test"))

        let effects = sut.handle(.commandFailed(message: "Command not recognized"))

        if case .error(let message) = sut.state {
            XCTAssertEqual(message, "Command not recognized")
        } else {
            XCTFail("Expected error state, got \(sut.state)")
        }
        XCTAssertTrue(effects.contains(.hideIndicator))
        XCTAssertTrue(effects.contains(.flashMenuBarError))
        XCTAssertTrue(effects.contains(.scheduleErrorTimeout))
    }

    func testEscapeDuringCommandExecution_Cancels() {
        let sut = DictationStateMachine()

        // Set up executingCommand state
        sut.setState(.executingCommand(mode: .command, prompt: "test"))

        let effects = sut.handle(.escapePressed)

        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(effects.contains(.hideIndicator))
    }

    // MARK: - State Properties for Command Mode

    func testExecutingCommandState_IsProcessing() {
        let state = DictationState.executingCommand(mode: .command, prompt: "test")
        XCTAssertTrue(state.isProcessing)
        XCTAssertEqual(state.mode, .command)
        XCTAssertEqual(state.prompt, "test")
    }

    func testExecutingCommandState_IsActiveForIndicator() {
        let state = DictationState.executingCommand(mode: .command, prompt: "test")
        XCTAssertTrue(state.isActiveForIndicator)
    }

    // MARK: - Tools.json Loading Tests

    func testToolsFileStructure_DecodesCorrectly() throws {
        let toolsJSON = """
        {
          "tools": [
            {
              "name": "open_project",
              "description": "Opens a project in VS Code",
              "parameters": {
                "path": {
                  "type": "string",
                  "description": "The path to the project folder"
                }
              },
              "required": ["path"],
              "executor": "open_project"
            }
          ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let toolsFile = try decoder.decode(ToolsFile.self, from: toolsJSON)

        XCTAssertEqual(toolsFile.tools.count, 1)
        XCTAssertEqual(toolsFile.tools[0].name, "open_project")
        XCTAssertEqual(toolsFile.tools[0].executor, "open_project")
        XCTAssertEqual(toolsFile.tools[0].parameters["path"]?.type, "string")
    }
}
