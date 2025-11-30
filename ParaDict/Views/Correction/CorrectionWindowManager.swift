import SwiftUI
import AppKit
import Combine
import os

private let logger = Logger(subsystem: "com.paradict", category: "CorrectionWindowManager")

@MainActor
class CorrectionWindowManager: ObservableObject {
    static let shared = CorrectionWindowManager()

    @Published var isVisible = false
    private var windowController: NSWindowController?
    private var correctionPanel: CorrectionPanel?

    private init() {}

    func show(originalText: String) {
        if isVisible {
            hide()
        }

        logger.notice("Showing correction window for text: \(originalText.prefix(50))...")

        initializeWindow(originalText: originalText)
        isVisible = true
        correctionPanel?.show()
    }

    func hide() {
        guard isVisible else { return }

        logger.notice("Hiding correction window")
        isVisible = false
        correctionPanel?.hide()
        deinitializeWindow()
    }

    private func initializeWindow(originalText: String) {
        deinitializeWindow()

        let metrics = CorrectionPanel.calculateWindowMetrics()
        let panel = CorrectionPanel(contentRect: metrics)

        let correctionView = CorrectionView(
            originalText: originalText,
            onSubmit: { [weak self] correctedText, explanation in
                self?.handleSubmit(original: originalText, correction: correctedText, explanation: explanation)
            },
            onCancel: { [weak self] in
                self?.hide()
            }
        )

        let hostingController = NSHostingController(rootView: correctionView)
        panel.contentView = hostingController.view

        self.correctionPanel = panel
        self.windowController = NSWindowController(window: panel)

        panel.makeKeyAndOrderFront(nil)
    }

    private func deinitializeWindow() {
        correctionPanel?.orderOut(nil)
        windowController?.close()
        windowController = nil
        correctionPanel = nil
    }

    private func handleSubmit(original: String, correction: String, explanation: String?) {
        logger.notice("Saving correction - original: \(original.prefix(30))..., correction: \(correction.prefix(30))...")

        CorrectionLogger.shared.logCorrection(
            original: original,
            correction: correction,
            explanation: explanation
        )

        hide()
    }
}
