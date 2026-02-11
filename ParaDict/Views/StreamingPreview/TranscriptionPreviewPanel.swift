import AppKit

/// Floating panel for the streaming transcription preview.
/// Positioned directly above the recording indicator, grows in height with content.
class TranscriptionPreviewPanel: NSPanel {
    static let panelWidth: CGFloat = 300
    static let maxHeight: CGFloat = 160
    static let gap: CGFloat = 8

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        let frame = Self.calculateFrame(height: 36)
        super.init(
            contentRect: frame,
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

    /// Calculate the panel frame positioned above the recording indicator
    static func calculateFrame(height: CGFloat) -> NSRect {
        let indicatorMetrics = RecordingIndicatorPanel.calculateWindowMetrics()
        let centerX = indicatorMetrics.midX
        let xPosition = centerX - (panelWidth / 2)
        let yPosition = indicatorMetrics.maxY + gap

        return NSRect(x: xPosition, y: yPosition, width: panelWidth, height: height)
    }

    /// Update the panel height (repositions to stay above the indicator)
    func updateHeight(_ height: CGFloat) {
        let clampedHeight = min(max(height, 36), Self.maxHeight)
        let frame = Self.calculateFrame(height: clampedHeight)
        setFrame(frame, display: true)
    }
}
