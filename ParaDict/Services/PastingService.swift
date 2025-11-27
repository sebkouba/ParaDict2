import Foundation
import AppKit
import os

private let logger = Logger(subsystem: "com.paradict", category: "PastingService")

class PastingService {

    static func pasteAtCursor(_ text: String) {
        logger.notice("pasteAtCursor called - text length: \(text.count) chars")

        // Check accessibility permission first
        let isTrusted = AXIsProcessTrusted()
        logger.notice("Accessibility trusted: \(isTrusted)")

        if !isTrusted {
            logger.error("Accessibility permission not granted - cannot paste")
            return
        }

        let pasteboard = NSPasteboard.general
        let preserveClipboard = !UserDefaults.standard.bool(forKey: "preserveTranscriptInClipboard")
        logger.notice("Preserve clipboard: \(preserveClipboard)")

        var savedContents: [(NSPasteboard.PasteboardType, Data)] = []

        // Save clipboard contents if we plan to restore them
        if preserveClipboard {
            let currentItems = pasteboard.pasteboardItems ?? []
            logger.notice("Saving \(currentItems.count) clipboard items")

            for item in currentItems {
                for type in item.types {
                    if let data = item.data(forType: type) {
                        savedContents.append((type, data))
                    }
                }
            }
        }

        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        logger.notice("Set clipboard string: \(success)")

        if preserveClipboard {
            pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        }

        logger.notice("Scheduling Cmd+V keystroke in 50ms...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            logger.notice("Executing Cmd+V keystroke")
            pasteUsingCommandV()

            // Start tracking for edits after paste completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                TranscriptionEditTracker.shared.startTracking(originalText: text)
            }
        }

        // Restore clipboard after paste
        if preserveClipboard {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                if !savedContents.isEmpty {
                    logger.notice("Restoring \(savedContents.count) clipboard items")
                    pasteboard.clearContents()
                    for (type, data) in savedContents {
                        pasteboard.setData(data, forType: type)
                    }
                }
            }
        }
    }

    private static func pasteUsingCommandV() {
        guard AXIsProcessTrusted() else {
            logger.error("pasteUsingCommandV: Accessibility not trusted")
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)

        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)

        cmdDown?.flags = .maskCommand
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand

        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)

        logger.notice("Cmd+V keystroke sent")
    }

    static func pressEnter() {
        logger.notice("pressEnter called")
        guard AXIsProcessTrusted() else {
            logger.error("pressEnter: Accessibility not trusted")
            return
        }
        let source = CGEventSource(stateID: .hidSystemState)
        let enterDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
        let enterUp = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)
        enterDown?.post(tap: .cghidEventTap)
        enterUp?.post(tap: .cghidEventTap)
        logger.notice("Enter keystroke sent")
    }
}
