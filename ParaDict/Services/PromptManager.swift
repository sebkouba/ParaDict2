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

    private init() {
        ensurePromptsDirectory()
        copyBundledPromptsIfNeeded()
        refreshPromptList()
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
        guard let bundledPromptsURL = Bundle.main.resourceURL?.appendingPathComponent("prompts") else {
            logger.notice("No bundled prompts directory found in app bundle")
            return
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: bundledPromptsURL.path) else {
            logger.notice("Bundled prompts directory does not exist")
            return
        }

        do {
            let bundledFiles = try fm.contentsOfDirectory(at: bundledPromptsURL, includingPropertiesForKeys: nil)
            for file in bundledFiles where file.pathExtension == "md" {
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
        let fileURL = promptsDirectory.appendingPathComponent("\(name).md")
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    // MARK: - Prompt Management

    func createPrompt(name: String, content: String) throws {
        let fileURL = promptsDirectory.appendingPathComponent("\(name).md")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        logger.notice("Created prompt '\(name)'")
        refreshPromptList()
    }

    func deletePrompt(name: String) throws {
        let fileURL = promptsDirectory.appendingPathComponent("\(name).md")
        try FileManager.default.removeItem(at: fileURL)
        logger.notice("Deleted prompt '\(name)'")
        refreshPromptList()
    }

    func getPromptsDirectoryPath() -> String {
        promptsDirectory.path
    }
}
