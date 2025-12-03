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
                params[key] = ParameterDefinition(
                    type: param.type,
                    description: param.description,
                    enumValues: param.enum
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
            guard let path = args["path"] as? String else {
                throw CommandError.missingParameter("path")
            }
            return try openProject(path: path)

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
            return try runShell(command: command)

        case "set_audio_output":
            guard let deviceName = args["device_name"] as? String else {
                throw CommandError.missingParameter("device_name")
            }
            return try setAudioOutput(deviceName: deviceName)

        case "list_audio_outputs":
            return listAudioOutputs()

        default:
            throw CommandError.unknownExecutor(tool.executor)
        }
    }

    // MARK: - Executors

    private func openProject(path: String) throws -> String {
        // Check for remote project format: ssh://host/remote/path
        if path.hasPrefix("ssh://") {
            return try openRemoteProject(sshPath: path)
        }

        let expandedPath = (path as NSString).expandingTildeInPath

        // Use VS Code's URL scheme - works reliably from GUI apps
        // vscode://file/path/to/folder opens the folder in VS Code
        let vscodeURL = URL(string: "vscode://file\(expandedPath)")!

        let opened = NSWorkspace.shared.open(vscodeURL)

        if opened {
            logger.notice("Opened project at \(expandedPath)")
            return "Opened \(path) in VS Code"
        } else {
            // Fallback: try using 'open -a' command
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", "Visual Studio Code", expandedPath]

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                logger.notice("Opened project (fallback) at \(expandedPath)")
                return "Opened \(path) in VS Code"
            } else {
                throw CommandError.executionFailed("Failed to open VS Code")
            }
        }
    }

    /// Opens a remote project via VS Code SSH Remote
    /// Path format: ssh://ssh-config-host/remote/path
    private func openRemoteProject(sshPath: String) throws -> String {
        // Parse ssh://host/path format
        let withoutScheme = String(sshPath.dropFirst("ssh://".count))
        guard let firstSlash = withoutScheme.firstIndex(of: "/") else {
            throw CommandError.executionFailed("Invalid SSH path format. Use: ssh://host/remote/path")
        }

        let sshHost = String(withoutScheme[..<firstSlash])
        let remotePath = String(withoutScheme[firstSlash...])

        logger.notice("Opening remote project: host=\(sshHost), path=\(remotePath)")

        // Use 'code' CLI with --remote flag
        // code --remote ssh-remote+host /remote/path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/code")
        process.arguments = ["--remote", "ssh-remote+\(sshHost)", remotePath]

        // Try common VS Code CLI locations
        let codePaths = [
            "/usr/local/bin/code",
            "/opt/homebrew/bin/code",
            "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
        ]

        var foundPath: String?
        for codePath in codePaths {
            if FileManager.default.fileExists(atPath: codePath) {
                foundPath = codePath
                break
            }
        }

        guard let executablePath = foundPath else {
            throw CommandError.executionFailed("VS Code CLI not found. Install 'code' command from VS Code.")
        }

        process.executableURL = URL(fileURLWithPath: executablePath)

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            logger.notice("Opened remote project \(sshHost):\(remotePath)")
            return "Opened remote project on \(sshHost)"
        } else {
            throw CommandError.executionFailed("Failed to open remote project")
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

    private func runShell(command: String) throws -> String {
        // Security check: reject dangerous commands
        let dangerousPatterns = ["rm -rf", "sudo", "mkfs", "dd if=", "> /dev/"]
        for pattern in dangerousPatterns {
            if command.contains(pattern) {
                throw CommandError.dangerousCommand(command)
            }
        }

        // Run command in Terminal so user can see the output
        // Escape double quotes and backslashes for AppleScript string
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Terminal"
            activate
            if (count of windows) > 0 then
                -- Use the frontmost window
                do script "\(escapedCommand)" in front window
            else
                -- No window open, create one
                do script "\(escapedCommand)"
            end if
        end tell
        """

        guard let appleScript = NSAppleScript(source: script) else {
            throw CommandError.executionFailed("Failed to create AppleScript")
        }

        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)

        if let error = error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            throw CommandError.executionFailed(message)
        }

        logger.notice("Ran command in Terminal: \(command)")
        return "Running '\(command)' in Terminal"
    }

    private func setAudioOutput(deviceName: String) throws -> String {
        do {
            let actualName = try AudioDeviceConfig.setOutputDeviceByName(deviceName)
            logger.notice("Switched audio output to: \(actualName)")
            return "Switched audio output to \(actualName)"
        } catch let error as AudioConfigurationError {
            throw CommandError.executionFailed(error.localizedDescription ?? "Unknown audio error")
        }
    }

    private func listAudioOutputs() -> String {
        let devices = AudioDeviceConfig.getOutputDevices()
        let currentDefault = AudioDeviceConfig.getDefaultOutputDevice()

        let deviceList = devices.map { device in
            let isCurrent = device.id == currentDefault ? " (current)" : ""
            return "- \(device.name)\(isCurrent)"
        }.joined(separator: "\n")

        logger.notice("Listed \(devices.count) output devices")
        return "Available audio outputs:\n\(deviceList)"
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
