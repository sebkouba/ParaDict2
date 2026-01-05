import Foundation
import os

private let logger = Logger(subsystem: "com.paradict", category: "DictionaryManager")

/// Manages the central custom dictionary file that gets appended to all LLM prompts.
class DictionaryManager {
    static let shared = DictionaryManager()

    private var dictionaryPath: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let promptsDir = appSupport.appendingPathComponent("ParaDict/prompts")
        return promptsDir.appendingPathComponent("dictionary.md")
    }

    private let defaultTemplate = """
    # Custom Dictionary

    This dictionary is automatically appended to all LLM prompts.
    Add your custom vocabulary and corrections below.

    ## Vocabulary
    Words and phrases that should be recognized correctly:
    - [Your Name]
    - [Company Name]
    - [Technical terms you use]

    ## Corrections
    Common transcription errors and their fixes:
    - "[misheard phrase]" → "[correct phrase]"

    <!-- Corrections added via the correction feature will appear below -->
    """

    private init() {
        ensureDictionaryExists()
    }

    private func ensureDictionaryExists() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let promptsDir = appSupport.appendingPathComponent("ParaDict/prompts")

        if !FileManager.default.fileExists(atPath: promptsDir.path) {
            do {
                try FileManager.default.createDirectory(at: promptsDir, withIntermediateDirectories: true)
                logger.notice("Created prompts directory")
            } catch {
                logger.error("Failed to create prompts directory: \(error.localizedDescription)")
            }
        }

        if !FileManager.default.fileExists(atPath: dictionaryPath.path) {
            do {
                try defaultTemplate.write(to: dictionaryPath, atomically: true, encoding: .utf8)
                logger.notice("Created dictionary file with default template at \(self.dictionaryPath.path)")
            } catch {
                logger.error("Failed to create dictionary file: \(error.localizedDescription)")
            }
        }
    }

    /// Load the current dictionary content
    func loadDictionary() -> String? {
        do {
            let content = try String(contentsOf: dictionaryPath, encoding: .utf8)
            logger.notice("Loaded dictionary (\(content.count) chars)")
            return content
        } catch {
            logger.error("Failed to load dictionary: \(error.localizedDescription)")
            return nil
        }
    }

    /// Save updated dictionary content
    func saveDictionary(_ content: String) {
        do {
            try content.write(to: dictionaryPath, atomically: true, encoding: .utf8)
            logger.notice("Saved dictionary (\(content.count) chars)")
        } catch {
            logger.error("Failed to save dictionary: \(error.localizedDescription)")
        }
    }

    /// Get the path to the dictionary file
    func getDictionaryPath() -> URL {
        return dictionaryPath
    }
}
