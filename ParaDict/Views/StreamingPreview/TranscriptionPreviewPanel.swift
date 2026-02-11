import SwiftUI
import AppKit

/// Floating panel for the streaming transcription preview.
/// Matches RecordingIndicatorPanel configuration: non-activating, floating, joins all spaces.
class TranscriptionPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configurePanel()
    }

    private func configurePanel() {
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovable = false
        isMovableByWindowBackground = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        standardWindowButton(.closeButton)?.isHidden = true
    }

    /// Calculate frame for "above indicator" placement
    static func indicatorFrame() -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: 300, height: 60)
        }

        let indicatorMetrics = RecordingIndicatorPanel.calculateWindowMetrics()
        let width: CGFloat = 300
        let height: CGFloat = 60
        let gap: CGFloat = 8

        let centerX = indicatorMetrics.midX
        let xPosition = centerX - (width / 2)
        let yPosition = indicatorMetrics.maxY + gap

        return NSRect(x: xPosition, y: yPosition, width: width, height: height)
    }

    /// Calculate frame for "subtitle" placement (wide bar at bottom-center)
    static func subtitleFrame() -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: 400, height: 60)
        }

        let width: CGFloat = 400
        let height: CGFloat = 60
        let padding: CGFloat = 80  // Above dock

        let visibleFrame = screen.visibleFrame
        let xPosition = visibleFrame.midX - (width / 2)
        let yPosition = visibleFrame.minY + padding

        return NSRect(x: xPosition, y: yPosition, width: width, height: height)
    }

    /// Calculate frame for "near cursor" placement using Accessibility API
    static func cursorFrame() -> NSRect {
        if let cursorRect = getCursorPosition() {
            let width: CGFloat = 300
            let height: CGFloat = 60
            let gap: CGFloat = 4

            // Position above the cursor
            let xPosition = cursorRect.origin.x
            let yPosition = cursorRect.origin.y + cursorRect.height + gap

            return NSRect(x: xPosition, y: yPosition, width: width, height: height)
        }

        // Fallback to center-screen
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: 300, height: 60)
        }

        let width: CGFloat = 300
        let height: CGFloat = 60
        let visibleFrame = screen.visibleFrame

        return NSRect(
            x: visibleFrame.midX - (width / 2),
            y: visibleFrame.midY - (height / 2),
            width: width,
            height: height
        )
    }

    /// Try to get the cursor position from the focused app via Accessibility API
    private static func getCursorPosition() -> NSRect? {
        guard let focusedApp = NSWorkspace.shared.frontmostApplication else { return nil }

        let appElement = AXUIElementCreateApplication(focusedApp.processIdentifier)

        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            return nil
        }

        var selectedRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success else {
            return nil
        }

        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            focusedElement as! AXUIElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedRange!,
            &bounds
        ) == .success else {
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect) else {
            return nil
        }

        // Convert from screen coordinates (top-left origin) to Cocoa coordinates (bottom-left origin)
        guard let screen = NSScreen.main else { return nil }
        let screenHeight = screen.frame.height
        let cocoaY = screenHeight - rect.origin.y - rect.height

        return NSRect(x: rect.origin.x, y: cocoaY, width: rect.width, height: rect.height)
    }

    func show(placement: StreamingPreviewPlacement) {
        let frame: NSRect
        switch placement {
        case .indicator:
            frame = Self.indicatorFrame()
        case .subtitle:
            frame = Self.subtitleFrame()
        case .cursor:
            frame = Self.cursorFrame()
        case .disabled:
            return
        }
        setFrame(frame, display: true)
        orderFrontRegardless()
    }
}
