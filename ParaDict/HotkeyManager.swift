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
        logger.notice("HotkeyManager initializing...")
        setupKeyboardShortcuts()
    }

    func setupKeyboardShortcuts() {
        logger.notice("Setting up keyboard shortcut handlers...")

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
                self?.handleShortcutDown(mode: .local, prompt: nil)
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
                let prompt = ConfigManager.shared.enhancedDictationPrompt
                self?.handleShortcutDown(mode: .enhanced, prompt: prompt)
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
    private var currentPrompt: String?

    private func handleShortcutDown(mode: DictationMode, prompt: String?) {
        logger.notice("handleShortcutDown called - mode: \(mode.rawValue), isProcessing: \(self.isProcessing), isRecording: \(self.isRecording), isHandsFreeMode: \(self.isHandsFreeMode)")

        guard !isProcessing else {
            logger.warning("Ignoring shortcut - currently processing")
            return
        }

        keyPressStartTime = Date()
        activeMode = mode
        currentPrompt = prompt

        if isHandsFreeMode {
            logger.notice("Exiting hands-free mode, stopping recording")
            isHandsFreeMode = false
            isRecording = false  // Set immediately to prevent race condition
            onStopRecording?()
            return
        }

        if !isRecording {
            logger.notice("Starting recording in \(mode.rawValue) mode")
            onStartRecording?(mode, prompt)
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
        currentPrompt = nil
    }
}
