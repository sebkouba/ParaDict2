import Foundation
import AppKit
import os

/// Service for reading context from the clipboard
class SelectionService {
    static let shared = SelectionService()

    private let logger = Logger(subsystem: "com.paradict", category: "SelectionService")

    private init() {}

    /// Read the current clipboard contents as context
    /// Workflow: User copies text they want to respond to, clicks target field, then triggers shortcut
    func getClipboardContext() -> String? {
        let pasteboard = NSPasteboard.general
        guard let contents = pasteboard.string(forType: .string), !contents.isEmpty else {
            logger.notice("Clipboard is empty - no context available")
            return nil
        }

        logger.notice("Read clipboard context: \(contents.prefix(50))... (\(contents.count) chars)")
        return contents
    }
}
