import SwiftUI
import AppKit
import Combine

@MainActor
class RecordingIndicatorWindowManager: ObservableObject {
    static let shared = RecordingIndicatorWindowManager()

    @Published var isVisible = false
    private var windowController: NSWindowController?
    private var indicatorPanel: RecordingIndicatorPanel?

    private init() {}

    func show() {
        if isVisible { return }

        let activeScreen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]

        initializeWindow(screen: activeScreen)
        self.isVisible = true
        indicatorPanel?.show()
    }

    func hide() {
        guard isVisible else { return }

        self.isVisible = false
        self.indicatorPanel?.hide { [weak self] in
            Task { @MainActor in
                self?.deinitializeWindow()
            }
        }
    }

    private func initializeWindow(screen: NSScreen) {
        deinitializeWindow()

        let metrics = RecordingIndicatorPanel.calculateWindowMetrics()
        let panel = RecordingIndicatorPanel(contentRect: metrics)

        // Access DictationManager.shared lazily here, not during init
        let indicatorView = RecordingIndicatorView(dictationManager: DictationManager.shared)
            .environmentObject(self)

        let hostingController = NSHostingController(rootView: indicatorView)
        panel.contentView = hostingController.view

        self.indicatorPanel = panel
        self.windowController = NSWindowController(window: panel)

        panel.orderFrontRegardless()
    }

    private func deinitializeWindow() {
        indicatorPanel?.orderOut(nil)
        windowController?.close()
        windowController = nil
        indicatorPanel = nil
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }
}
