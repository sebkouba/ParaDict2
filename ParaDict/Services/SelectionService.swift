import Foundation
import AppKit
import os

/// Service for capturing currently selected text from any application
/// Uses clipboard simulation (Cmd+C) as the most reliable cross-app approach
class SelectionService {
    static let shared = SelectionService()

    private let logger = Logger(subsystem: "com.paradict", category: "SelectionService")

    private init() {}

    /// Capture the currently selected text by simulating Cmd+C
    /// Returns nil if no text is selected or accessibility permission is missing
    func captureSelectedText() async -> String? {
        guard AXIsProcessTrusted() else {
            logger.warning("Accessibility permission not granted - cannot capture selection")
            return nil
        }

        // Save current clipboard contents
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)
        let previousChangeCount = pasteboard.changeCount

        // Clear clipboard before copying
        pasteboard.clearContents()

        // Simulate Cmd+C to copy selection
        simulateCopy()

        // Wait for clipboard to update (with timeout)
        let startTime = Date()
        let timeout: TimeInterval = 0.5
        var newContents: String?

        while Date().timeIntervalSince(startTime) < timeout {
            // Check if clipboard changed
            if pasteboard.changeCount != previousChangeCount {
                newContents = pasteboard.string(forType: .string)
                if newContents != nil && !newContents!.isEmpty {
                    break
                }
            }
            // Small delay to avoid busy-waiting
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        // Restore previous clipboard contents if we got a selection
        if let selected = newContents, !selected.isEmpty {
            // Schedule restoration after a brief delay to not interfere
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                if let previous = previousContents {
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                }
            }
            logger.notice("Captured selection: \(selected.prefix(50))... (\(selected.count) chars)")
            return selected
        }

        // Restore previous contents if copy failed
        if let previous = previousContents {
            pasteboard.clearContents()
            pasteboard.setString(previous, forType: .string)
        }

        logger.notice("No text selected or copy failed")
        return nil
    }

    /// Simulate Cmd+C keystroke
    private func simulateCopy() {
        let source = CGEventSource(stateID: .hidSystemState)

        // Key codes: C = 8, Command = 55
        let keyC: CGKeyCode = 8

        // Create key down event with Command modifier
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
        }

        // Create key up event
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: false) {
            keyUp.flags = .maskCommand
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
