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

    private var configObserver: NSObjectProtocol?
    private var escapeEventTap: CFMachPort?
    private var escapeEventTapSource: CFRunLoopSource?
    private var enterEventTap: CFMachPort?
    private var enterEventTapSource: CFRunLoopSource?

    init() {
        logger.notice("HotkeyManager initializing...")
        setupKeyboardShortcuts()
        observeConfigChanges()
    }

    private func observeConfigChanges() {
        configObserver = NotificationCenter.default.addObserver(
            forName: .configDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyShortcutsFromConfig()
            }
        }
    }

    deinit {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
        }
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

    private func applyShortcutsFromConfig() {
        let shortcuts = ConfigManager.shared.config.shortcuts
        logger.notice("Applying shortcuts from config: \(shortcuts.count) shortcuts")

        // Get the desired shortcuts from config
        let localConfig = shortcuts.first(where: { $0.mode == .local })
        let enhancedConfig = shortcuts.first(where: { $0.mode == .enhanced })
        let replyConfig = shortcuts.first(where: { $0.mode == .reply })

        let desiredLocal = localConfig?.shortcut.flatMap { ShortcutParser.parse($0) }
        let desiredEnhanced = enhancedConfig?.shortcut.flatMap { ShortcutParser.parse($0) }
        let desiredReply = replyConfig?.shortcut.flatMap { ShortcutParser.parse($0) }

        let currentLocal = KeyboardShortcuts.getShortcut(for: .localDictation)
        let currentEnhanced = KeyboardShortcuts.getShortcut(for: .enhancedDictation)
        let currentReply = KeyboardShortcuts.getShortcut(for: .replyDictation)

        // Check if we need to clear all shortcuts first to avoid conflicts
        let allDesired = [desiredLocal, desiredEnhanced, desiredReply].compactMap { $0 }
        let allCurrent = [currentLocal, currentEnhanced, currentReply].compactMap { $0 }
        let needsClear = allDesired.contains { desired in
            allCurrent.contains { current in desired == current }
        }

        if needsClear {
            logger.notice("Clearing shortcuts before applying to avoid conflicts")
            KeyboardShortcuts.setShortcut(nil, for: .localDictation)
            KeyboardShortcuts.setShortcut(nil, for: .enhancedDictation)
            KeyboardShortcuts.setShortcut(nil, for: .replyDictation)
        }

        // Apply local shortcut
        if currentLocal != desiredLocal || needsClear {
            KeyboardShortcuts.setShortcut(desiredLocal, for: .localDictation)
            if let str = localConfig?.shortcut {
                logger.notice("Set local dictation shortcut: \(str)")
            } else {
                logger.notice("Cleared local dictation shortcut")
            }
        }

        // Apply enhanced shortcut
        if currentEnhanced != desiredEnhanced || needsClear {
            KeyboardShortcuts.setShortcut(desiredEnhanced, for: .enhancedDictation)
            if let str = enhancedConfig?.shortcut {
                logger.notice("Set enhanced dictation shortcut: \(str)")
            } else {
                logger.notice("Cleared enhanced dictation shortcut")
            }
        }

        // Apply reply shortcut
        if currentReply != desiredReply || needsClear {
            KeyboardShortcuts.setShortcut(desiredReply, for: .replyDictation)
            if let str = replyConfig?.shortcut {
                logger.notice("Set reply dictation shortcut: \(str)")
            } else {
                logger.notice("Cleared reply dictation shortcut")
            }
        }
    }

    func setupKeyboardShortcuts() {
        logger.notice("Setting up keyboard shortcut handlers...")

        // Apply initial shortcuts from config
        applyShortcutsFromConfig()

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
                let config = ConfigManager.shared.config.shortcuts.first(where: { $0.mode == .local })
                await self?.handleShortcutDown(mode: .local, shortcutConfig: config)
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
                let config = ConfigManager.shared.config.shortcuts.first(where: { $0.mode == .enhanced })
                await self?.handleShortcutDown(mode: .enhanced, shortcutConfig: config)
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
                let config = ConfigManager.shared.config.shortcuts.first(where: { $0.mode == .reply })
                await self?.handleShortcutDown(mode: .reply, shortcutConfig: config)
            }
        }

        KeyboardShortcuts.onKeyUp(for: .replyDictation) { [weak self] in
            Task { @MainActor in
                self?.logger.notice("REPLY DICTATION: Key UP detected")
                self?.handleShortcutUp()
            }
        }

        logger.notice("Keyboard shortcuts configured successfully")
    }

    private var keyPressStartTime: Date?
    private let briefPressThreshold = 1.0
    private var isHandsFreeMode = false
    private var currentShortcutConfig: ShortcutConfig?
    private var capturedSelection: String?

    private func handleShortcutDown(mode: DictationMode, shortcutConfig: ShortcutConfig?) async {
        logger.notice("handleShortcutDown called - mode: \(mode.rawValue)")

        // Store for later use (prompt loading, etc.)
        keyPressStartTime = Date()
        currentShortcutConfig = shortcutConfig

        // Read clipboard context if this shortcut requires it
        var selectionContext: String? = nil
        if shortcutConfig?.shouldCaptureSelection == true {
            logger.notice("Reading clipboard for context...")
            selectionContext = SelectionService.shared.getClipboardContext()
            if selectionContext == nil {
                logger.notice("Clipboard empty - proceeding without context")
            }
        }
        capturedSelection = selectionContext

        // Load prompt content from file if specified
        var promptContent: String? = nil
        if let file = shortcutConfig?.promptFile {
            promptContent = PromptManager.shared.loadPrompt(named: file)
            if promptContent == nil {
                logger.warning("Could not load prompt file: \(file)")
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
        currentShortcutConfig = nil
        capturedSelection = nil
        shouldContinueAfterSubmit = false
        stopEscapeKeyMonitor()
        stopEnterKeyMonitor()
    }

    /// Start a new recording in continued hands-free mode after submit-and-continue
    /// This uses the EXACT same mechanism as pressing the hotkey to start a new recording
    func startContinuedRecording(mode: DictationMode) {
        logger.notice("Starting continued recording in \(mode.rawValue) mode")

        // Get the shortcut config for this mode (same as handleShortcutDown does)
        let shortcutConfig = ConfigManager.shared.config.shortcuts.first(where: { $0.mode == mode })
        currentShortcutConfig = shortcutConfig
        activeMode = mode

        // Load prompt content from file if specified (same as handleShortcutDown does)
        var promptContent: String? = nil
        if let file = shortcutConfig?.promptFile {
            promptContent = PromptManager.shared.loadPrompt(named: file)
            if promptContent == nil {
                logger.warning("Could not load prompt file: \(file)")
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

    /// Sync current KeyboardShortcuts state back to config
    func syncShortcutsToConfig() {
        var shortcuts = ConfigManager.shared.config.shortcuts
        var changed = false

        // Sync local dictation
        if let localShortcut = KeyboardShortcuts.getShortcut(for: .localDictation) {
            let str = ShortcutParser.toString(localShortcut)
            if let idx = shortcuts.firstIndex(where: { $0.mode == .local }) {
                if shortcuts[idx].shortcut != str {
                    shortcuts[idx].shortcut = str
                    changed = true
                    logger.notice("Synced local dictation shortcut from UI: \(str)")
                }
            }
        } else {
            if let idx = shortcuts.firstIndex(where: { $0.mode == .local }),
               shortcuts[idx].shortcut != nil {
                shortcuts[idx].shortcut = nil
                changed = true
                logger.notice("Cleared local dictation shortcut from UI")
            }
        }

        // Sync enhanced dictation
        if let enhancedShortcut = KeyboardShortcuts.getShortcut(for: .enhancedDictation) {
            let str = ShortcutParser.toString(enhancedShortcut)
            if let idx = shortcuts.firstIndex(where: { $0.mode == .enhanced }) {
                if shortcuts[idx].shortcut != str {
                    shortcuts[idx].shortcut = str
                    changed = true
                    logger.notice("Synced enhanced dictation shortcut from UI: \(str)")
                }
            }
        } else {
            if let idx = shortcuts.firstIndex(where: { $0.mode == .enhanced }),
               shortcuts[idx].shortcut != nil {
                shortcuts[idx].shortcut = nil
                changed = true
                logger.notice("Cleared enhanced dictation shortcut from UI")
            }
        }

        // Sync reply dictation
        if let replyShortcut = KeyboardShortcuts.getShortcut(for: .replyDictation) {
            let str = ShortcutParser.toString(replyShortcut)
            if let idx = shortcuts.firstIndex(where: { $0.mode == .reply }) {
                if shortcuts[idx].shortcut != str {
                    shortcuts[idx].shortcut = str
                    changed = true
                    logger.notice("Synced reply dictation shortcut from UI: \(str)")
                }
            } else {
                // Entry doesn't exist - add it (migration case)
                shortcuts.append(ShortcutConfig(name: "reply", shortcut: str, mode: .reply, promptFile: "reply", captureSelection: true))
                changed = true
                logger.notice("Added reply dictation shortcut entry: \(str)")
            }
        } else {
            if let idx = shortcuts.firstIndex(where: { $0.mode == .reply }),
               shortcuts[idx].shortcut != nil {
                shortcuts[idx].shortcut = nil
                changed = true
                logger.notice("Cleared reply dictation shortcut from UI")
            }
        }

        if changed {
            ConfigManager.shared.config.shortcuts = shortcuts
            ConfigManager.shared.saveConfig()
        }
    }
}

// Singleton accessor for HotkeyManager
extension HotkeyManager {
    @MainActor
    static let shared = HotkeyManager()
}
