import SwiftUI
import AppKit
import Combine

@MainActor
class RecordingIndicatorWindowManager: ObservableObject {
    static let shared = RecordingIndicatorWindowManager()

    @Published var isVisible = false
    @Published var isShowingTimeoutFlash = false
    private var windowController: NSWindowController?
    private var indicatorPanel: RecordingIndicatorPanel?
    private var timeoutFlashTask: Task<Void, Never>?

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

        // Access DictationCoordinator.shared lazily here, not during init
        let indicatorView = RecordingIndicatorView(coordinator: DictationCoordinator.shared)
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

    /// Show a red flash for 2 seconds to indicate the enhancement timed out
    func showTimeoutFlash() {
        // Cancel any existing flash task
        timeoutFlashTask?.cancel()

        // Show the indicator if not already visible
        if !isVisible {
            let activeScreen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]
            initializeWindow(screen: activeScreen)
            indicatorPanel?.show()
        }

        isVisible = true
        isShowingTimeoutFlash = true

        // Hide after 2 seconds
        timeoutFlashTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled {
                self.isShowingTimeoutFlash = false
                self.hide()
            }
        }
    }
}
