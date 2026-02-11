import SwiftUI
import AppKit
import Combine

/// Manages the floating preview panel lifecycle with dynamic height.
/// Panel grows as transcription text accumulates, like an expanding chat input.
@MainActor
class TranscriptionPreviewWindowManager {
    static let shared = TranscriptionPreviewWindowManager()

    private let streamingService = StreamingTranscriptionService.shared
    private var panel: TranscriptionPreviewPanel?
    private var windowController: NSWindowController?
    private var textObserver: AnyCancellable?
    private var isVisible = false

    /// Font matching the SwiftUI view for height calculation
    private let measureFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    /// Text width = panel width minus horizontal padding (12pt each side)
    private let textWidth: CGFloat = TranscriptionPreviewPanel.panelWidth - 24

    private init() {}

    func show() {
        if isVisible { return }

        deinitializeWindow()

        let panel = TranscriptionPreviewPanel()
        let previewView = TranscriptionPreviewView()
        let hostingController = NSHostingController(rootView: previewView)
        panel.contentView = hostingController.view

        self.panel = panel
        self.windowController = NSWindowController(window: panel)
        self.isVisible = true

        // Observe text changes to resize the panel dynamically
        textObserver = streamingService.$partialTranscription
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                self?.updatePanelHeight(for: text)
            }

        panel.orderFrontRegardless()
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        textObserver?.cancel()
        textObserver = nil
        deinitializeWindow()
    }

    private func deinitializeWindow() {
        panel?.orderOut(nil)
        windowController?.close()
        windowController = nil
        panel = nil
    }

    /// Calculate text height and resize the panel to fit
    private func updatePanelHeight(for text: String) {
        guard let panel = panel else { return }

        let displayText = text.isEmpty ? "Listening..." : text

        let boundingRect = (displayText as NSString).boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: measureFont]
        )

        // Text height + vertical padding (8pt top + 8pt bottom)
        let panelHeight = ceil(boundingRect.height) + 16
        panel.updateHeight(panelHeight)
    }
}
