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

    /// Show the correction window
    /// - Parameters:
    ///   - originalTranscription: Raw transcription from Parakeet
    ///   - llmOutput: What was actually pasted (may be same as transcription if local mode)
    func show(originalTranscription: String, llmOutput: String) {
        if isVisible {
            hide()
        }

        logger.notice("Showing correction window - transcription: \(originalTranscription.prefix(30))..., llmOutput: \(llmOutput.prefix(30))...")

        initializeWindow(originalTranscription: originalTranscription, llmOutput: llmOutput)
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

    private func initializeWindow(originalTranscription: String, llmOutput: String) {
        deinitializeWindow()

        let metrics = CorrectionPanel.calculateWindowMetrics()
        let panel = CorrectionPanel(contentRect: metrics)

        let correctionView = CorrectionView(
            originalTranscription: originalTranscription,
            llmOutput: llmOutput,
            onSubmit: { [weak self] correctedText, explanation in
                self?.handleSubmit(
                    originalTranscription: originalTranscription,
                    llmOutput: llmOutput,
                    correction: correctedText,
                    explanation: explanation
                )
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

    private func handleSubmit(originalTranscription: String, llmOutput: String, correction: String, explanation: String?) {
        logger.notice("Saving correction - transcription: \(originalTranscription.prefix(30))..., correction: \(correction.prefix(30))...")

        CorrectionLogger.shared.logCorrection(
            originalTranscription: originalTranscription,
            llmOutput: llmOutput,
            correction: correction,
            explanation: explanation
        )

        hide()
    }
}
