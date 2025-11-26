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

    init() {
        logger.info("HotkeyManager initializing...")
        setupKeyboardShortcuts()
    }

    func setupKeyboardShortcuts() {
        logger.info("Setting up keyboard shortcut handlers...")

        // Log current shortcuts
        if let localShortcut = KeyboardShortcuts.getShortcut(for: .localDictation) {
            logger.info("Local dictation shortcut: \(localShortcut.description)")
        } else {
            logger.warning("No local dictation shortcut configured")
        }

        if let enhancedShortcut = KeyboardShortcuts.getShortcut(for: .enhancedDictation) {
            logger.info("Enhanced dictation shortcut: \(enhancedShortcut.description)")
        } else {
            logger.info("No enhanced dictation shortcut configured (optional)")
        }

        // Local dictation shortcut
        KeyboardShortcuts.onKeyDown(for: .localDictation) { [weak self] in
            Task { @MainActor in
                self?.logger.info("LOCAL DICTATION: Key DOWN detected")
                self?.handleShortcutDown(mode: .local, prompt: nil)
            }
        }

        KeyboardShortcuts.onKeyUp(for: .localDictation) { [weak self] in
            Task { @MainActor in
                self?.logger.info("LOCAL DICTATION: Key UP detected")
                self?.handleShortcutUp()
            }
        }

        // Enhanced dictation shortcut
        KeyboardShortcuts.onKeyDown(for: .enhancedDictation) { [weak self] in
            Task { @MainActor in
                self?.logger.info("ENHANCED DICTATION: Key DOWN detected")
                let config = ConfigManager.shared.config
                let prompt = config.hotkeys.first { $0.mode == .enhanced }?.prompt
                self?.handleShortcutDown(mode: .enhanced, prompt: prompt)
            }
        }

        KeyboardShortcuts.onKeyUp(for: .enhancedDictation) { [weak self] in
            Task { @MainActor in
                self?.logger.info("ENHANCED DICTATION: Key UP detected")
                self?.handleShortcutUp()
            }
        }

        logger.info("Keyboard shortcuts configured successfully")
    }

    private var keyPressStartTime: Date?
    private let briefPressThreshold = 1.5
    private var isHandsFreeMode = false
    private var currentPrompt: String?

    private func handleShortcutDown(mode: DictationMode, prompt: String?) {
        logger.info("handleShortcutDown called - mode: \(mode.rawValue), isProcessing: \(self.isProcessing), isRecording: \(self.isRecording), isHandsFreeMode: \(self.isHandsFreeMode)")

        guard !isProcessing else {
            logger.warning("Ignoring shortcut - currently processing")
            return
        }

        keyPressStartTime = Date()
        activeMode = mode
        currentPrompt = prompt

        if isHandsFreeMode {
            logger.info("Exiting hands-free mode, stopping recording")
            isHandsFreeMode = false
            onStopRecording?()
            return
        }

        if !isRecording {
            logger.info("Starting recording in \(mode.rawValue) mode")
            onStartRecording?(mode, prompt)
        } else {
            logger.info("Already recording, ignoring key down")
        }
    }

    private func handleShortcutUp() {
        logger.info("handleShortcutUp called - isProcessing: \(self.isProcessing), keyPressStartTime: \(String(describing: self.keyPressStartTime))")

        guard !isProcessing else {
            logger.warning("Ignoring key up - currently processing")
            return
        }

        if let startTime = keyPressStartTime {
            let pressDuration = Date().timeIntervalSince(startTime)
            logger.info("Key held for \(String(format: "%.2f", pressDuration)) seconds (threshold: \(self.briefPressThreshold)s)")

            if pressDuration < briefPressThreshold {
                isHandsFreeMode = true
                logger.info("Hands-free mode activated - press shortcut again to stop recording")
            } else {
                logger.info("Long press released - stopping recording")
                onStopRecording?()
            }
        } else {
            logger.warning("Key up without key down time recorded")
        }

        keyPressStartTime = nil
    }

    func cancelRecording() {
        logger.info("cancelRecording called - resetting state")
        isHandsFreeMode = false
        keyPressStartTime = nil
        activeMode = nil
        currentPrompt = nil
    }
}
