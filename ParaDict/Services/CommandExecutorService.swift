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

/// Defines available tools and executes tool calls from LLM
@MainActor
class CommandExecutorService {
    static let shared = CommandExecutorService()

    private let logger = Logger(subsystem: "com.paradict", category: "CommandExecutor")
    private var toolsConfig: ToolsFile?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var fileWatcherDescriptor: Int32 = -1

    private var toolsFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("ParaDict/tools.json")
    }

    private init() {
        loadToolsFile()
        setupFileWatcher()
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

    private func setupFileWatcher() {
        // Ensure the file exists first
        guard FileManager.default.fileExists(atPath: toolsFileURL.path) else {
            logger.warning("tools.json doesn't exist yet - skipping file watcher setup")
            return
        }

        let fileDescriptor = open(toolsFileURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            logger.warning("Could not watch tools.json for changes")
            return
        }

        fileWatcherDescriptor = fileDescriptor

        fileWatcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: .main
        )

        fileWatcher?.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.logger.notice("tools.json changed - reloading")
                self?.loadToolsFile()
            }
        }

        fileWatcher?.setCancelHandler { [fd = fileDescriptor] in
            close(fd)
        }

        fileWatcher?.resume()
        logger.notice("Watching tools.json for changes")
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

    // MARK: - Executors

    private func openProject(name: String, projects: [String: String]) async throws -> String {
        guard let projectPath = projects[name.lowercased()] else {
            throw CommandError.projectNotFound(name)
        }

        let expandedPath = (projectPath as NSString).expandingTildeInPath

        // Use VS Code's URL scheme - works reliably from GUI apps
        // vscode://file/path/to/folder opens the folder in VS Code
        let vscodeURL = URL(string: "vscode://file\(expandedPath)")!

        let opened = NSWorkspace.shared.open(vscodeURL)

        if opened {
            logger.notice("Opened project: \(name) at \(expandedPath)")
            return "Opened \(name) in VS Code"
        } else {
            // Fallback: try using 'open -a' command
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", "Visual Studio Code", expandedPath]

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                logger.notice("Opened project (fallback): \(name) at \(expandedPath)")
                return "Opened \(name) in VS Code"
            } else {
                throw CommandError.executionFailed("Failed to open VS Code")
            }
        }
    }

    private func openApp(name: String) throws -> String {
        let workspace = NSWorkspace.shared

        // Try to find and launch the app by bundle identifier
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
        var finalURLString = urlString

        // Add https:// if no scheme is present
        if !urlString.contains("://") {
            finalURLString = "https://\(urlString)"
        }

        guard let url = URL(string: finalURLString) else {
            throw CommandError.invalidURL(urlString)
        }

        NSWorkspace.shared.open(url)
        return "Opened \(finalURLString)"
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

    // MARK: - Helpers

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
            "firefox": "org.mozilla.firefox",
            "messages": "com.apple.MobileSMS",
            "mail": "com.apple.mail",
            "notes": "com.apple.Notes",
            "calendar": "com.apple.iCal",
            "music": "com.apple.Music",
            "spotify": "com.spotify.client"
        ]
        return knownApps[appName.lowercased()] ?? "com.apple.\(appName)"
    }
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
        case .invalidArguments:
            return "Invalid arguments for tool call"
        case .missingParameter(let param):
            return "Missing required parameter: \(param)"
        case .unknownTool(let name):
            return "Unknown tool: \(name)"
        case .unknownExecutor(let name):
            return "Unknown executor: \(name)"
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
