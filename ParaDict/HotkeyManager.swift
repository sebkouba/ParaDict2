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

    var onStartRecording: ((DictationMode, String?) -> Void)?
    var onStopRecording: (() -> Void)?

    private var configObserver: NSObjectProtocol?

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
    }

    private func applyShortcutsFromConfig() {
        let shortcuts = ConfigManager.shared.config.shortcuts
        logger.notice("Applying shortcuts from config: \(shortcuts.count) shortcuts")

        // Get the desired shortcuts from config
        let localConfig = shortcuts.first(where: { $0.mode == .local })
        let enhancedConfig = shortcuts.first(where: { $0.mode == .enhanced })

        let desiredLocal = localConfig?.shortcut.flatMap { ShortcutParser.parse($0) }
        let desiredEnhanced = enhancedConfig?.shortcut.flatMap { ShortcutParser.parse($0) }

        let currentLocal = KeyboardShortcuts.getShortcut(for: .localDictation)
        let currentEnhanced = KeyboardShortcuts.getShortcut(for: .enhancedDictation)

        // Check if we need to swap (new local == old enhanced, or new enhanced == old local)
        // In this case, we must clear both first to avoid conflicts
        let needsClear = (desiredLocal != nil && desiredLocal == currentEnhanced) ||
                         (desiredEnhanced != nil && desiredEnhanced == currentLocal)

        if needsClear {
            logger.notice("Clearing shortcuts before swap to avoid conflicts")
            KeyboardShortcuts.setShortcut(nil, for: .localDictation)
            KeyboardShortcuts.setShortcut(nil, for: .enhancedDictation)
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

        // Local dictation shortcut
        KeyboardShortcuts.onKeyDown(for: .localDictation) { [weak self] in
            Task { @MainActor in
                self?.logger.notice("LOCAL DICTATION: Key DOWN detected")
                self?.handleShortcutDown(mode: .local, promptFile: nil)
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
                // Get the prompt file from config
                let shortcuts = ConfigManager.shared.config.shortcuts
                let promptFile = shortcuts.first(where: { $0.mode == .enhanced })?.promptFile
                self?.handleShortcutDown(mode: .enhanced, promptFile: promptFile)
            }
        }

        KeyboardShortcuts.onKeyUp(for: .enhancedDictation) { [weak self] in
            Task { @MainActor in
                self?.logger.notice("ENHANCED DICTATION: Key UP detected")
                self?.handleShortcutUp()
            }
        }

        logger.notice("Keyboard shortcuts configured successfully")
    }

    private var keyPressStartTime: Date?
    private let briefPressThreshold = 1.0
    private var isHandsFreeMode = false
    private var currentPromptFile: String?

    private func handleShortcutDown(mode: DictationMode, promptFile: String?) {
        logger.notice("handleShortcutDown called - mode: \(mode.rawValue), isProcessing: \(self.isProcessing), isRecording: \(self.isRecording), isHandsFreeMode: \(self.isHandsFreeMode)")

        guard !isProcessing else {
            logger.warning("Ignoring shortcut - currently processing")
            return
        }

        keyPressStartTime = Date()
        activeMode = mode
        currentPromptFile = promptFile

        if isHandsFreeMode {
            logger.notice("Exiting hands-free mode, stopping recording")
            isHandsFreeMode = false
            isRecording = false  // Set immediately to prevent race condition
            onStopRecording?()
            return
        }

        if !isRecording {
            logger.notice("Starting recording in \(mode.rawValue) mode")
            // Load prompt content from file if specified
            var promptContent: String? = nil
            if let file = promptFile {
                promptContent = PromptManager.shared.loadPrompt(named: file)
                if promptContent == nil {
                    logger.warning("Could not load prompt file: \(file)")
                }
            }
            onStartRecording?(mode, promptContent)
        } else {
            logger.notice("Already recording, ignoring key down")
        }
    }

    private func handleShortcutUp() {
        logger.notice("handleShortcutUp called - isProcessing: \(self.isProcessing), keyPressStartTime: \(String(describing: self.keyPressStartTime))")

        guard !isProcessing else {
            logger.warning("Ignoring key up - currently processing")
            return
        }

        if let startTime = keyPressStartTime {
            let pressDuration = Date().timeIntervalSince(startTime)
            logger.notice("Key held for \(String(format: "%.2f", pressDuration)) seconds (threshold: \(self.briefPressThreshold)s)")

            if pressDuration < briefPressThreshold {
                // Only activate hands-free mode if recording actually started
                if isRecording {
                    isHandsFreeMode = true
                    logger.notice("Hands-free mode activated - press shortcut again to stop recording")
                } else {
                    logger.notice("Brief press but recording not active - ignoring")
                }
            } else {
                logger.notice("Long press released - stopping recording")
                onStopRecording?()
            }
        } else {
            logger.warning("Key up without key down time recorded")
        }

        keyPressStartTime = nil
    }

    func cancelRecording() {
        logger.notice("cancelRecording called - resetting state")
        isHandsFreeMode = false
        keyPressStartTime = nil
        activeMode = nil
        currentPromptFile = nil
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
