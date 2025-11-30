import SwiftUI
import AppKit

class CorrectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .fullSizeContentView],
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
        isMovable = true
        isMovableByWindowBackground = true
        backgroundColor = NSColor.windowBackgroundColor
        isOpaque = true
        hasShadow = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        standardWindowButton(.closeButton)?.isHidden = false
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    static func calculateWindowMetrics(for size: NSSize? = nil) -> NSRect {
        guard let screen = NSScreen.main else {
            let defaultSize = size ?? NSSize(width: 540, height: 450)
            return NSRect(x: 0, y: 0, width: defaultSize.width, height: defaultSize.height)
        }

        let width = size?.width ?? 540
        let height = size?.height ?? 450

        let visibleFrame = screen.visibleFrame
        let centerX = visibleFrame.midX - (width / 2)
        let centerY = visibleFrame.midY - (height / 2)

        return NSRect(
            x: centerX,
            y: centerY,
            width: width,
            height: height
        )
    }

    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        orderOut(nil)
    }
}
