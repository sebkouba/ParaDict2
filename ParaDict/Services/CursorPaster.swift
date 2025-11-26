import Foundation
import AppKit
import os

private let logger = Logger(subsystem: "com.paradict", category: "CursorPaster")

class CursorPaster {

    static func pasteAtCursor(_ text: String) {
        logger.info("pasteAtCursor called - text length: \(text.count) chars")

        // Check accessibility permission first
        let isTrusted = AXIsProcessTrusted()
        logger.info("Accessibility trusted: \(isTrusted)")

        if !isTrusted {
            logger.error("Accessibility permission not granted - cannot paste")
            return
        }

        let pasteboard = NSPasteboard.general
        let preserveClipboard = !UserDefaults.standard.bool(forKey: "preserveTranscriptInClipboard")
        logger.info("Preserve clipboard: \(preserveClipboard)")

        var savedContents: [(NSPasteboard.PasteboardType, Data)] = []

        // Save clipboard contents if we plan to restore them
        if preserveClipboard {
            let currentItems = pasteboard.pasteboardItems ?? []
            logger.info("Saving \(currentItems.count) clipboard items")

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
        logger.info("Set clipboard string: \(success)")

        if preserveClipboard {
            pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        }

        logger.info("Scheduling Cmd+V keystroke in 50ms...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            logger.info("Executing Cmd+V keystroke")
            pasteUsingCommandV()
        }

        // Restore clipboard after paste
        if preserveClipboard {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                if !savedContents.isEmpty {
                    logger.info("Restoring \(savedContents.count) clipboard items")
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

        logger.info("Cmd+V keystroke sent")
    }

    static func pressEnter() {
        logger.info("pressEnter called")
        guard AXIsProcessTrusted() else {
            logger.error("pressEnter: Accessibility not trusted")
            return
        }
        let source = CGEventSource(stateID: .hidSystemState)
        let enterDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
        let enterUp = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)
        enterDown?.post(tap: .cghidEventTap)
        enterUp?.post(tap: .cghidEventTap)
        logger.info("Enter keystroke sent")
    }
}
