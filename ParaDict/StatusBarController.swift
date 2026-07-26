import AppKit
import Combine
import os

private let logger = Logger(subsystem: "com.paradict", category: "StatusBarController")

/// Controls the NSStatusItem in the menu bar using traditional AppKit (not SwiftUI MenuBarExtra)
/// Uses manual menu popup to avoid ghost window issues that occur with statusItem.menu assignment.
class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var cancellables = Set<AnyCancellable>()

    // References to app state
    private weak var dictationCoordinator: DictationCoordinator?
    private weak var menuBarManager: MenuBarManager?

    // Menu items that need dynamic updates
    private var statusMenuItem: NSMenuItem?
    private var playbackPausingItem: NSMenuItem?
    private var microphonePausingItem: NSMenuItem?
    private var trailingPunctuationItem: NSMenuItem?
    private var trailingSpaceItem: NSMenuItem?
    private var trailingLineBreakItem: NSMenuItem?
    private var trailingEnterItem: NSMenuItem?
    private var copyTranscriptionItem: NSMenuItem?
    private var copyEnhancementItem: NSMenuItem?
    private var copySeparator: NSMenuItem?

    override init() {
        super.init()
    }

    func setup(
        dictationCoordinator: DictationCoordinator,
        menuBarManager: MenuBarManager
    ) {
        self.dictationCoordinator = dictationCoordinator
        self.menuBarManager = menuBarManager

        createStatusItem()
        setupObservers()

        logger.notice("StatusBarController setup complete")
    }

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else {
            logger.error("Failed to get status item button")
            return
        }

        button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "ParaDict")
        button.image?.isTemplate = true

        // Use button action instead of assigning menu directly
        // This gives us control over menu lifecycle and avoids ghost window issues
        button.action = #selector(statusBarButtonClicked(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // Create the menu (but don't assign to statusItem.menu)
        menu = NSMenu()
        menu?.delegate = self

        // Status item (disabled, shows current state)
        statusMenuItem = NSMenuItem(title: "Status: Ready", action: nil, keyEquivalent: "")
        statusMenuItem?.isEnabled = false
        menu?.addItem(statusMenuItem!)

        menu?.addItem(NSMenuItem.separator())

        // Open ParaDict
        let openItem = NSMenuItem(title: "Open ParaDict", action: #selector(openParaDict), keyEquivalent: "")
        openItem.target = self
        menu?.addItem(openItem)

        menu?.addItem(NSMenuItem.separator())

        // Playback pausing toggle
        playbackPausingItem = NSMenuItem(title: "Pause Playback", action: #selector(togglePlaybackPausing), keyEquivalent: "")
        playbackPausingItem?.target = self
        playbackPausingItem?.state = dictationCoordinator?.isPlaybackPausingEnabled == true ? .on : .off
        menu?.addItem(playbackPausingItem!)

        microphonePausingItem = NSMenuItem(
            title: "Pause Mic for Playback",
            action: #selector(toggleMicrophonePausingForPlayback),
            keyEquivalent: ""
        )
        microphonePausingItem?.target = self
        microphonePausingItem?.state =
            dictationCoordinator?.isMicrophonePausingForPlaybackEnabled == true ? .on : .off
        menu?.addItem(microphonePausingItem!)

        menu?.addItem(NSMenuItem.separator())

        // Text formatting toggles
        trailingPunctuationItem = NSMenuItem(title: "Remove Trailing Punctuation", action: #selector(toggleTrailingPunctuation), keyEquivalent: "")
        trailingPunctuationItem?.target = self
        trailingPunctuationItem?.state = dictationCoordinator?.isTrailingPunctuationRemovalEnabled == true ? .on : .off
        menu?.addItem(trailingPunctuationItem!)

        trailingSpaceItem = NSMenuItem(title: "Add Trailing Space", action: #selector(toggleTrailingSpace), keyEquivalent: "")
        trailingSpaceItem?.target = self
        trailingSpaceItem?.state = dictationCoordinator?.isTrailingSpaceEnabled == true ? .on : .off
        menu?.addItem(trailingSpaceItem!)

        trailingLineBreakItem = NSMenuItem(title: "Add Trailing Line Break", action: #selector(toggleTrailingLineBreak), keyEquivalent: "")
        trailingLineBreakItem?.target = self
        trailingLineBreakItem?.state = dictationCoordinator?.isTrailingLineBreakEnabled == true ? .on : .off
        menu?.addItem(trailingLineBreakItem!)

        trailingEnterItem = NSMenuItem(title: "Send Enter After Paste", action: #selector(toggleTrailingEnter), keyEquivalent: "")
        trailingEnterItem?.target = self
        trailingEnterItem?.state = dictationCoordinator?.isTrailingEnterEnabled == true ? .on : .off
        menu?.addItem(trailingEnterItem!)

        menu?.addItem(NSMenuItem.separator())

        // Copy items (initially hidden, shown when there's content)
        copyTranscriptionItem = NSMenuItem(title: "Copy Last Transcription", action: #selector(copyLastTranscription), keyEquivalent: "")
        copyTranscriptionItem?.target = self
        copyTranscriptionItem?.isHidden = true
        menu?.addItem(copyTranscriptionItem!)

        copyEnhancementItem = NSMenuItem(title: "Copy Last Enhancement", action: #selector(copyLastEnhancement), keyEquivalent: "")
        copyEnhancementItem?.target = self
        copyEnhancementItem?.isHidden = true
        menu?.addItem(copyEnhancementItem!)

        copySeparator = NSMenuItem.separator()
        copySeparator?.isHidden = true
        menu?.addItem(copySeparator!)

        // Quit
        let quitItem = NSMenuItem(title: "Quit ParaDict", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu?.addItem(quitItem)

        // NOTE: We intentionally do NOT set statusItem?.menu = menu
        // Instead we show it manually via popUpMenu to have full control
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        logger.notice("Status bar button clicked")
        guard let menu = menu, let button = statusItem?.button else { return }

        // Update menu state before showing
        updateCopyItems()

        // Show menu manually - this gives us control over when it closes
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    private func setupObservers() {
        // Observe dictation state changes to update icon
        dictationCoordinator?.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateIcon(for: state)
                self?.updateStatusText(for: state)
            }
            .store(in: &cancellables)

        // Observe transcription/enhancement changes
        dictationCoordinator?.$lastTranscription
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateCopyItems()
            }
            .store(in: &cancellables)

        dictationCoordinator?.$lastEnhancement
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateCopyItems()
            }
            .store(in: &cancellables)

        // Observe flash notifications
        NotificationCenter.default.publisher(for: .menuBarFlash)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let success = notification.userInfo?["success"] as? Bool else { return }
                self?.flashIcon(success: success)
            }
            .store(in: &cancellables)

        // Observe playback pausing state
        dictationCoordinator?.$isPlaybackPausingEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                self?.playbackPausingItem?.state = isEnabled ? .on : .off
            }
            .store(in: &cancellables)

        dictationCoordinator?.$isMicrophonePausingForPlaybackEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                self?.microphonePausingItem?.state = isEnabled ? .on : .off
            }
            .store(in: &cancellables)

        // Observe text formatting states
        dictationCoordinator?.$isTrailingPunctuationRemovalEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                self?.trailingPunctuationItem?.state = isEnabled ? .on : .off
            }
            .store(in: &cancellables)

        dictationCoordinator?.$isTrailingSpaceEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                self?.trailingSpaceItem?.state = isEnabled ? .on : .off
            }
            .store(in: &cancellables)

        dictationCoordinator?.$isTrailingLineBreakEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                self?.trailingLineBreakItem?.state = isEnabled ? .on : .off
            }
            .store(in: &cancellables)

        dictationCoordinator?.$isTrailingEnterEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                self?.trailingEnterItem?.state = isEnabled ? .on : .off
            }
            .store(in: &cancellables)
    }

    private func updateIcon(for state: DictationState) {
        let iconName: String
        switch state {
        case .idle:
            iconName = "waveform"
        case .recording:
            iconName = "waveform.circle.fill"
        case .transcribing:
            iconName = "text.bubble"
        case .enhancing:
            iconName = "sparkles"
        case .pasting:
            iconName = "doc.on.clipboard"
        case .executingCommand:
            iconName = "terminal"
        case .error:
            iconName = "exclamationmark.triangle"
        }

        statusItem?.button?.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "ParaDict")
        statusItem?.button?.image?.isTemplate = true
    }

    private func updateStatusText(for state: DictationState) {
        let text: String
        switch state {
        case .idle:
            text = "Status: Ready"
        case .recording:
            text = "Status: Recording..."
        case .transcribing:
            text = "Status: Transcribing..."
        case .enhancing:
            text = "Status: Enhancing..."
        case .pasting:
            text = "Status: Pasting..."
        case .executingCommand:
            text = "Status: Executing..."
        case .error(let message):
            text = "Error: \(message)"
        }
        statusMenuItem?.title = text
    }

    private func updateCopyItems() {
        let hasTranscription = dictationCoordinator?.lastTranscription != nil
        let hasEnhancement = dictationCoordinator?.lastEnhancement != nil
        let hasAny = hasTranscription || hasEnhancement

        copyTranscriptionItem?.isHidden = !hasTranscription
        copyEnhancementItem?.isHidden = !hasEnhancement
        copySeparator?.isHidden = !hasAny
    }

    private func flashIcon(success: Bool) {
        let flashIconName = success ? "checkmark.circle.fill" : "xmark.circle.fill"
        statusItem?.button?.image = NSImage(systemSymbolName: flashIconName, accessibilityDescription: "ParaDict")
        statusItem?.button?.image?.isTemplate = true

        // Reset after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, let state = self.dictationCoordinator?.state else { return }
            self.updateIcon(for: state)
        }
    }

    // MARK: - Menu Actions

    /// Ensures the menu is fully closed before performing an action
    /// This prevents ghost windows when actions change app activation state
    private func closeMenuThen(_ action: @escaping () -> Void) {
        // Cancel tracking immediately
        menu?.cancelTracking()

        // Perform action after a brief delay to let the menu window close
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            action()
        }
    }

    @objc private func openParaDict() {
        logger.notice("Opening main window")
        closeMenuThen { [weak self] in
            self?.menuBarManager?.showMainWindow()
        }
    }

    @objc private func togglePlaybackPausing() {
        logger.notice("Toggling playback pausing")
        dictationCoordinator?.togglePlaybackPausing()
    }

    @objc private func toggleMicrophonePausingForPlayback() {
        logger.notice("Toggling microphone pausing for playback")
        dictationCoordinator?.toggleMicrophonePausingForPlayback()
    }

    @objc private func toggleTrailingPunctuation() {
        logger.notice("Toggling trailing punctuation removal")
        dictationCoordinator?.toggleTrailingPunctuationRemoval()
    }

    @objc private func toggleTrailingSpace() {
        logger.notice("Toggling trailing space")
        dictationCoordinator?.toggleTrailingSpace()
    }

    @objc private func toggleTrailingLineBreak() {
        logger.notice("Toggling trailing line break")
        dictationCoordinator?.toggleTrailingLineBreak()
    }

    @objc private func toggleTrailingEnter() {
        logger.notice("Toggling trailing enter")
        dictationCoordinator?.toggleTrailingEnter()
    }

    @objc private func copyLastTranscription() {
        logger.notice("Copying last transcription to clipboard")
        if let transcription = dictationCoordinator?.lastTranscription {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(transcription, forType: .string)
        }
    }

    @objc private func copyLastEnhancement() {
        logger.notice("Copying last enhancement to clipboard")
        if let enhancement = dictationCoordinator?.lastEnhancement {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(enhancement, forType: .string)
        }
    }

    @objc private func quitApp() {
        logger.notice("Quit requested")
        NSApplication.shared.terminate(nil)
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        logger.notice("Menu will open")
        // Update copy items visibility right before showing
        updateCopyItems()
    }

    func menuDidClose(_ menu: NSMenu) {
        logger.notice("Menu did close - forcing cleanup")
        // Force the menu to fully cancel tracking to ensure its window is released
        menu.cancelTracking()
    }
}
