import Foundation
import AppKit
import Combine
import KeyboardShortcuts
import os

@MainActor
class HotkeyManager: ObservableObject {
    private let logger = Logger(subsystem: "com.paradict", category: "HotkeyManager")

    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var activeMode: DictationMode?

    /// Flag indicating we should press Enter and restart recording after the current dictation completes
    var shouldContinueAfterSubmit = false

    /// Callback: (mode, prompt, selectionContext) -> Void
    var onStartRecording: ((DictationMode, String?, String?) -> Void)?
    var onStopRecording: (() -> Void)?
    var onCancelRecording: (() -> Void)?

    private var escapeEventTap: CFMachPort?
    private var escapeEventTapSource: CFRunLoopSource?
    private var enterEventTap: CFMachPort?
    private var enterEventTapSource: CFRunLoopSource?
    private var commandEventTap: CFMachPort?
    private var commandEventTapSource: CFRunLoopSource?
    /// Tracks whether Command is currently held (to fire only once per press)
    private var commandKeyIsDown = false


    init() {
        logger.notice("HotkeyManager initializing...")
        setupKeyboardShortcuts()
    }

    deinit {
        // Clean up CGEvent taps (can't call MainActor methods from deinit)
        if let source = escapeEventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = escapeEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = enterEventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = enterEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = commandEventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = commandEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }

    // MARK: - Key Monitor Control (Public for DictationCoordinator)

    /// Start monitoring for Escape key (uses CGEvent tap to consume the key)
    func startEscapeKeyMonitor() {
        guard escapeEventTap == nil else { return }

        // Store reference for the C callback
        HotkeyManager.sharedInstance = self

        // Create an event tap for key down events
        let eventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                // Check if this is the Escape key (keyCode 53)
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                if keyCode == 53 {
                    // This monitor is only active during dictation (controlled by state machine)
                    // So if we're here, we should consume the Escape key
                    if let manager = HotkeyManager.sharedInstance {
                        Task { @MainActor in
                            manager.handleEscapePressed()
                        }
                        // Return nil to consume the event (don't pass to other apps)
                        return nil
                    }
                }
                // Pass through all other events
                return Unmanaged.passRetained(event)
            },
            userInfo: nil
        ) else {
            logger.error("Failed to create CGEvent tap for Escape key")
            return
        }

        escapeEventTap = tap

        // Create a run loop source and add it to the main run loop
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        escapeEventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

        // Enable the tap
        CGEvent.tapEnable(tap: tap, enable: true)

        logger.notice("Escape key event tap started (will consume Escape during dictation)")
    }

    /// Stop monitoring for Escape key
    func stopEscapeKeyMonitor() {
        if let source = escapeEventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            escapeEventTapSource = nil
        }
        if let tap = escapeEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            escapeEventTap = nil
        }
        logger.notice("Escape key event tap stopped")
    }

    private func handleEscapePressed() {
        logger.notice("Escape pressed - sending event to coordinator")
        // Send event to DictationCoordinator - it handles all state transitions
        DictationCoordinator.shared.send(.escapePressed)
    }

    // MARK: - Enter Key Event Tap (Submit and Continue)
    // Uses CGEvent tap instead of NSEvent monitor to intercept and consume the Enter key

    /// Static reference for the CGEvent callback (needed because CGEvent callbacks are C-style)
    private static weak var sharedInstance: HotkeyManager?

    /// Start monitoring for Enter key (uses CGEvent tap to consume the key)
    func startEnterKeyMonitor() {
        guard enterEventTap == nil else { return }

        // Store reference for the C callback
        HotkeyManager.sharedInstance = self

        // Create an event tap for key down events
        let eventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                // Check if this is the Enter key (0x24)
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                if keyCode == 0x24 {
                    // This monitor is only active during hands-free recording (controlled by state machine)
                    // So if we're here, we should consume the Enter key
                    if let manager = HotkeyManager.sharedInstance {
                        Task { @MainActor in
                            manager.handleEnterPressed()
                        }
                        // Return nil to consume the event (don't pass to other apps)
                        return nil
                    }
                }
                // Pass through all other events
                return Unmanaged.passRetained(event)
            },
            userInfo: nil
        ) else {
            logger.error("Failed to create CGEvent tap for Enter key")
            return
        }

        enterEventTap = tap

        // Create a run loop source and add it to the main run loop
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        enterEventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

        // Enable the tap
        CGEvent.tapEnable(tap: tap, enable: true)

        logger.notice("Enter key event tap started (will consume Enter during hands-free recording)")
    }

    /// Stop monitoring for Enter key
    func stopEnterKeyMonitor() {
        if let source = enterEventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            enterEventTapSource = nil
        }
        if let tap = enterEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            enterEventTap = nil
        }
        logger.notice("Enter key event tap stopped")
    }

    private func handleEnterPressed() {
        logger.notice("Enter pressed - sending event to coordinator")
        // Send event to DictationCoordinator - it handles all state transitions
        DictationCoordinator.shared.send(.enterPressed)
    }

    // MARK: - Command Key Event Tap (Send and Stop)
    // Uses CGEvent tap for flagsChanged events to detect Command key press

    /// Start monitoring for Command key (uses CGEvent tap to consume the key)
    func startCommandKeyMonitor() {
        guard commandEventTap == nil else { return }

        // Store reference for the C callback
        HotkeyManager.sharedInstance = self

        // Reset state tracking
        commandKeyIsDown = false

        // Create an event tap for flagsChanged events
        let eventMask = (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let manager = HotkeyManager.sharedInstance else {
                    return Unmanaged.passRetained(event)
                }

                let flags = event.flags

                // Check if Command is pressed without other modifiers (Shift, Option, Control)
                let commandOnly = flags.contains(.maskCommand)
                    && !flags.contains(.maskShift)
                    && !flags.contains(.maskAlternate)
                    && !flags.contains(.maskControl)

                if commandOnly && !manager.commandKeyIsDown {
                    // Command just pressed (key-down) — fire once
                    manager.commandKeyIsDown = true
                    Task { @MainActor in
                        manager.handleCommandPressed()
                    }
                    // Consume the event to prevent it reaching other apps
                    return nil
                } else if !flags.contains(.maskCommand) && manager.commandKeyIsDown {
                    // Command released — reset tracking, consume the release too
                    manager.commandKeyIsDown = false
                    return nil
                }

                // Pass through all other modifier events
                return Unmanaged.passRetained(event)
            },
            userInfo: nil
        ) else {
            logger.error("Failed to create CGEvent tap for Command key")
            return
        }

        commandEventTap = tap

        // Create a run loop source and add it to the main run loop
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        commandEventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

        // Enable the tap
        CGEvent.tapEnable(tap: tap, enable: true)

        logger.notice("Command key event tap started (will consume Command during hands-free recording)")
    }

    /// Stop monitoring for Command key
    func stopCommandKeyMonitor() {
        if let source = commandEventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            commandEventTapSource = nil
        }
        if let tap = commandEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            commandEventTap = nil
        }
        commandKeyIsDown = false
        logger.notice("Command key event tap stopped")
    }

    private func handleCommandPressed() {
        logger.notice("Command pressed - sending event to coordinator")
        // Send event to DictationCoordinator - it handles all state transitions
        DictationCoordinator.shared.send(.commandPressed)
    }

    func setupKeyboardShortcuts() {
        logger.notice("Setting up keyboard shortcut handlers...")

        // KeyboardShortcuts library handles its own persistence
        // Log current shortcuts
        if let localShortcut = KeyboardShortcuts.getShortcut(for: .localDictation) {
            logger.notice("Local dictation shortcut: \(localShortcut.description)")
        } else {
            logger.warning("No local dictation shortcut configured")
        }

        if let enhancedShortcut = KeyboardShortcuts.getShortcut(for: .enhancedDictation) {
            logger.notice("Enhanced dictation shortcut: \(enhancedShortcut.description)")
        } else {
            logger.notice("No enhanced dictation shortcut configured (optional)")
        }

        if let replyShortcut = KeyboardShortcuts.getShortcut(for: .replyDictation) {
            logger.notice("Reply dictation shortcut: \(replyShortcut.description)")
        } else {
            logger.notice("No reply dictation shortcut configured (optional)")
        }

        // Local dictation shortcut
        KeyboardShortcuts.onKeyDown(for: .localDictation) { [weak self] in
            Task { @MainActor in
                self?.logger.notice("LOCAL DICTATION: Key DOWN detected")
                await self?.handleShortcutDown(mode: .local)
            }
        }

        KeyboardShortcuts.onKeyUp(for: .localDictation) { [weak self] in
            Task { @MainActor in
                self?.logger.notice("LOCAL DICTATION: Key UP detected")
                self?.handleShortcutUp()
            }
        }

        // Enhanced dictation shortcut
        KeyboardShortcuts.onKeyDown(for: .enhancedDictation) { [weak self] in
            Task { @MainActor in
                self?.logger.notice("ENHANCED DICTATION: Key DOWN detected")
                await self?.handleShortcutDown(mode: .enhanced)
            }
        }

        KeyboardShortcuts.onKeyUp(for: .enhancedDictation) { [weak self] in
            Task { @MainActor in
                self?.logger.notice("ENHANCED DICTATION: Key UP detected")
                self?.handleShortcutUp()
            }
        }

        // Reply dictation shortcut
        KeyboardShortcuts.onKeyDown(for: .replyDictation) { [weak self] in
            Task { @MainActor in
                self?.logger.notice("REPLY DICTATION: Key DOWN detected")
                await self?.handleShortcutDown(mode: .reply)
            }
        }

        KeyboardShortcuts.onKeyUp(for: .replyDictation) { [weak self] in
            Task { @MainActor in
                self?.logger.notice("REPLY DICTATION: Key UP detected")
                self?.handleShortcutUp()
            }
        }

        // Command dictation shortcut
        KeyboardShortcuts.onKeyDown(for: .commandDictation) { [weak self] in
            Task { @MainActor in
                self?.logger.notice("COMMAND DICTATION: Key DOWN detected")
                await self?.handleShortcutDown(mode: .command)
            }
        }

        KeyboardShortcuts.onKeyUp(for: .commandDictation) { [weak self] in
            Task { @MainActor in
                self?.logger.notice("COMMAND DICTATION: Key UP detected")
                self?.handleShortcutUp()
            }
        }

        logger.notice("Keyboard shortcuts configured successfully")
    }

    private var keyPressStartTime: Date?
    private let briefPressThreshold = 1.0
    private var isHandsFreeMode = false
    private var currentMode: DictationMode?
    private var capturedSelection: String?

    private func handleShortcutDown(mode: DictationMode) async {
        logger.notice("handleShortcutDown called - mode: \(mode.rawValue)")

        // Store for later use
        keyPressStartTime = Date()
        currentMode = mode

        // Read clipboard context if this mode requires it
        var selectionContext: String? = nil
        if AppSettings.shared.shouldCaptureSelection(for: mode) {
            logger.notice("Reading clipboard for context...")
            selectionContext = SelectionService.shared.getClipboardContext()
            if selectionContext == nil {
                logger.notice("Clipboard empty - proceeding without context")
            }
        }
        capturedSelection = selectionContext

        // Load prompt content from file if specified for this mode
        var promptContent: String? = nil
        if let promptFile = AppSettings.shared.promptFile(for: mode) {
            promptContent = PromptManager.shared.loadPrompt(named: promptFile)
            if promptContent == nil {
                logger.warning("Could not load prompt file: \(promptFile)")
            }
        }

        // Send event to DictationCoordinator - it handles all state transitions
        DictationCoordinator.shared.send(.hotkeyDown(mode: mode, prompt: promptContent, context: selectionContext))
    }

    private func handleShortcutUp() {
        guard let startTime = keyPressStartTime else {
            logger.warning("Key up without key down time recorded")
            return
        }

        let pressDuration = Date().timeIntervalSince(startTime)
        logger.notice("handleShortcutUp - key held for \(String(format: "%.2f", pressDuration))s")

        keyPressStartTime = nil

        // Send event to DictationCoordinator - it handles all state transitions
        DictationCoordinator.shared.send(.hotkeyUp(duration: pressDuration))
    }

    func cancelRecording() {
        logger.notice("cancelRecording called - resetting state")
        isHandsFreeMode = false
        keyPressStartTime = nil
        activeMode = nil
        currentMode = nil
        capturedSelection = nil
        shouldContinueAfterSubmit = false
        stopEscapeKeyMonitor()
        stopEnterKeyMonitor()
        stopCommandKeyMonitor()
    }

    /// Start a new recording in continued hands-free mode after submit-and-continue
    /// This uses the EXACT same mechanism as pressing the hotkey to start a new recording
    func startContinuedRecording(mode: DictationMode) {
        logger.notice("Starting continued recording in \(mode.rawValue) mode")

        currentMode = mode
        activeMode = mode

        // Load prompt content from file if specified for this mode
        var promptContent: String? = nil
        if let promptFile = AppSettings.shared.promptFile(for: mode) {
            promptContent = PromptManager.shared.loadPrompt(named: promptFile)
            if promptContent == nil {
                logger.warning("Could not load prompt file: \(promptFile)")
            }
        }

        // Start monitors
        startEscapeKeyMonitor()
        startEnterKeyMonitor()

        // Trigger the recording through the existing callback (same as handleShortcutDown)
        // No selection context for continued recordings
        onStartRecording?(mode, promptContent, nil)

        // After onStartRecording returns, set up hands-free state
        // This is similar to what handleShortcutUp does for a brief press
        isHandsFreeMode = true
    }
}

// Singleton accessor for HotkeyManager
extension HotkeyManager {
    @MainActor
    static let shared = HotkeyManager()
}
