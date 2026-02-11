import SwiftUI
import AppKit

/// Manages the floating preview panel lifecycle. Follows the same singleton pattern
/// as RecordingIndicatorWindowManager.
@MainActor
class TranscriptionPreviewWindowManager {
    static let shared = TranscriptionPreviewWindowManager()

    private var panel: TranscriptionPreviewPanel?
    private var windowController: NSWindowController?
    private var isVisible = false

    private init() {}

    func show(placement: StreamingPreviewPlacement) {
        guard placement != .disabled else { return }
        if isVisible { return }

        let charLimit = AppSettings.shared.streamingPreviewCharLimit

        let frame: NSRect
        switch placement {
        case .indicator:
            frame = TranscriptionPreviewPanel.indicatorFrame()
        case .subtitle:
            frame = TranscriptionPreviewPanel.subtitleFrame()
        case .cursor:
            frame = TranscriptionPreviewPanel.cursorFrame()
        case .disabled:
            return
        }

        deinitializeWindow()

        let panel = TranscriptionPreviewPanel(contentRect: frame)
        let previewView = TranscriptionPreviewView(charLimit: charLimit)
        let hostingController = NSHostingController(rootView: previewView)
        panel.contentView = hostingController.view

        self.panel = panel
        self.windowController = NSWindowController(window: panel)
        self.isVisible = true

        panel.orderFrontRegardless()
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        deinitializeWindow()
    }

    private func deinitializeWindow() {
        panel?.orderOut(nil)
        windowController?.close()
        windowController = nil
        panel = nil
    }
}
