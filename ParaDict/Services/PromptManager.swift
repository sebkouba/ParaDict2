import Foundation
import Combine
import os

@MainActor
class PromptManager: ObservableObject {
    static let shared = PromptManager()

    private let logger = Logger(subsystem: "com.paradict", category: "PromptManager")

    @Published var availablePrompts: [String] = []

    private var promptsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("ParaDict/prompts", isDirectory: true)
    }

    private var eventStream: FSEventStreamRef?
    private let watcherQueue = DispatchQueue(label: "com.paradict.promptwatcher", qos: .utility)

    private init() {
        ensurePromptsDirectory()
        copyBundledPromptsIfNeeded()
        refreshPromptList()
        startDirectoryWatcher()
    }

    deinit {
        stopDirectoryWatcher()
    }

    // MARK: - Directory Setup

    private func ensurePromptsDirectory() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: promptsDirectory.path) {
            do {
                try fm.createDirectory(at: promptsDirectory, withIntermediateDirectories: true)
                logger.notice("Created prompts directory at \(self.promptsDirectory.path)")
            } catch {
                logger.error("Failed to create prompts directory: \(error.localizedDescription)")
            }
        }
    }

    private func copyBundledPromptsIfNeeded() {
        // Xcode flattens the Resources/prompts folder, so .md files end up directly in Resources/
        guard let resourcesURL = Bundle.main.resourceURL else {
            logger.notice("No resources URL found in app bundle")
            return
        }

        let fm = FileManager.default

        do {
            let resourceFiles = try fm.contentsOfDirectory(at: resourcesURL, includingPropertiesForKeys: nil)
            let promptFiles = resourceFiles.filter { $0.pathExtension == "md" }

            if promptFiles.isEmpty {
                logger.notice("No bundled .md prompt files found in Resources")
                return
            }

            for file in promptFiles {
                let destURL = promptsDirectory.appendingPathComponent(file.lastPathComponent)
                if !fm.fileExists(atPath: destURL.path) {
                    try fm.copyItem(at: file, to: destURL)
                    logger.notice("Copied bundled prompt: \(file.lastPathComponent)")
                }
            }
        } catch {
            logger.error("Failed to copy bundled prompts: \(error.localizedDescription)")
        }
    }

    // MARK: - Prompt Loading

    func refreshPromptList() {
        let fm = FileManager.default
        do {
            let files = try fm.contentsOfDirectory(at: promptsDirectory, includingPropertiesForKeys: nil)
            availablePrompts = files
                .filter { $0.pathExtension == "md" }
                .map { $0.deletingPathExtension().lastPathComponent }
                .sorted()
            logger.notice("Found \(self.availablePrompts.count) prompts: \(self.availablePrompts.joined(separator: ", "))")
        } catch {
            logger.error("Failed to list prompts: \(error.localizedDescription)")
            availablePrompts = []
        }
    }

    func loadPrompt(named name: String) -> String? {
        // Strip .md extension if provided (config can use either "default" or "default.md")
        let baseName = name.hasSuffix(".md") ? String(name.dropLast(3)) : name
        let fileURL = promptsDirectory.appendingPathComponent("\(baseName).md")
        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            logger.notice("Loaded prompt '\(baseName)' (\(content.count) chars)")
            return content
        } catch {
            logger.error("Failed to load prompt '\(baseName)': \(error.localizedDescription)")
            return nil
        }
    }

    func promptExists(named name: String) -> Bool {
        let baseName = name.hasSuffix(".md") ? String(name.dropLast(3)) : name
        let fileURL = promptsDirectory.appendingPathComponent("\(baseName).md")
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    // MARK: - Prompt Management

    func createPrompt(name: String, content: String) throws {
        // Strip .md extension if provided to prevent double extension (.md.md)
        let baseName = name.hasSuffix(".md") ? String(name.dropLast(3)) : name
        let fileURL = promptsDirectory.appendingPathComponent("\(baseName).md")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        logger.notice("Created prompt '\(name)'")
        refreshPromptList()
    }

    func deletePrompt(name: String) throws {
        let baseName = name.hasSuffix(".md") ? String(name.dropLast(3)) : name
        let fileURL = promptsDirectory.appendingPathComponent("\(baseName).md")
        try FileManager.default.removeItem(at: fileURL)
        logger.notice("Deleted prompt '\(name)'")
        refreshPromptList()
    }

    func getPromptsDirectoryPath() -> String {
        promptsDirectory.path
    }

    // MARK: - Directory Watcher

    private nonisolated func startDirectoryWatcher() {
        // Capture the path before going off MainActor
        let directoryPath = MainActor.assumeIsolated { promptsDirectory.path }

        let pathsToWatch = [directoryPath] as CFArray

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { (_, clientCallBackInfo, _, _, _, _) in
            guard let clientCallBackInfo = clientCallBackInfo else { return }
            let manager = Unmanaged<PromptManager>.fromOpaque(clientCallBackInfo).takeUnretainedValue()

            Task { @MainActor in
                manager.refreshPromptList()
            }
        }

        let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,  // Latency in seconds
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )

        if let stream = stream {
            FSEventStreamSetDispatchQueue(stream, watcherQueue)
            FSEventStreamStart(stream)

            Task { @MainActor in
                self.eventStream = stream
                self.logger.notice("Started prompts directory watcher")
            }
        }
    }

    private nonisolated func stopDirectoryWatcher() {
        let stream = MainActor.assumeIsolated { eventStream }
        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)

            Task { @MainActor in
                self.eventStream = nil
                self.logger.notice("Stopped prompts directory watcher")
            }
        }
    }
}
