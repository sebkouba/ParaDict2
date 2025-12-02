import Foundation
import Combine
import AVFoundation
import AppKit
import os

enum DictationState: Equatable {
    case idle
    case recording
    case transcribing
    case enhancing
    case error(String)

    var isProcessing: Bool {
        switch self {
        case .transcribing, .enhancing:
            return true
        default:
            return false
        }
    }
}

@MainActor
class DictationManager: ObservableObject {
    static let shared = DictationManager()

    @Published var state: DictationState = .idle
    @Published var lastTranscription: String?
    @Published var lastEnhancement: String?

    /// Tracks the last raw transcription from Parakeet (for correction feature)
    private var lastRawTranscription: String?
    /// Tracks the last text that was actually pasted - may be LLM-enhanced (for correction feature)
    private var lastPastedText: String?
    private let correctionWindowManager = CorrectionWindowManager.shared

    let recordingService = RecordingService()  // Exposed for audio meter observation
    private let transcriptionService = ParakeetTranscriptionService.shared
    private let llmClient = LLMClient.shared
    private let logger = Logger(subsystem: "com.paradict", category: "DictationManager")
    private let indicatorManager = RecordingIndicatorWindowManager.shared
    private let historyLogger = TranscriptionHistoryLogger.shared

    private var currentMode: DictationMode = .local
    private var currentPrompt: String?
    private var currentSelectionContext: String?
    private var recordingURL: URL?

    private init() {
        logger.notice("DictationManager initializing...")
        setupHotkeyManager()
        logger.notice("DictationManager initialized")
    }

    private func setupHotkeyManager() {
        logger.notice("Setting up HotkeyManager callbacks...")

        HotkeyManager.shared.onStartRecording = { [weak self] mode, prompt, selectionContext in
            self?.logger.notice("onStartRecording callback triggered - mode: \(mode.rawValue), hasContext: \(selectionContext != nil)")
            Task { @MainActor in
                await self?.startRecording(mode: mode, prompt: prompt, selectionContext: selectionContext)
            }
        }

        HotkeyManager.shared.onStopRecording = { [weak self] in
            self?.logger.notice("onStopRecording callback triggered")
            Task { @MainActor in
                await self?.stopRecording()
            }
        }

        HotkeyManager.shared.onCancelRecording = { [weak self] in
            self?.logger.notice("onCancelRecording callback triggered (Escape pressed)")
            Task { @MainActor in
                self?.cancelRecording()
            }
        }

        logger.notice("HotkeyManager callbacks configured")
    }

    private var hotkeyManager: HotkeyManager {
        HotkeyManager.shared
    }

    func startRecording(mode: DictationMode, prompt: String?, selectionContext: String? = nil) async {
        logger.notice("startRecording called - current state: \(String(describing: self.state)), mode: \(mode.rawValue), hasContext: \(selectionContext != nil)")

        // Allow starting from error state (user wants to try again)
        if case .error = state {
            logger.notice("Clearing error state to start new recording")
            state = .idle
        }

        guard state == .idle else {
            logger.warning("Cannot start recording - state is not idle: \(String(describing: self.state))")
            return
        }

        // Check microphone permission BEFORE recording
        let permissionManager = PermissionManager.shared
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        logger.notice("Checking audio permission before recording - status: \(audioStatus.rawValue)")

        if audioStatus == .notDetermined {
            // Request permission
            logger.notice("Audio permission not determined - requesting...")
            let granted = await permissionManager.requestAudioPermissionAsync()
            if !granted {
                logger.error("Audio permission denied - cannot record")
                state = .error("Microphone access denied. Please grant permission in System Settings > Privacy & Security > Microphone")
                Task {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if case .error = self.state {
                        self.state = .idle
                    }
                }
                return
            }
        } else if audioStatus != .authorized {
            logger.error("Audio permission not authorized (status: \(audioStatus.rawValue)) - cannot record")
            state = .error("Microphone access required. Please grant permission in System Settings > Privacy & Security > Microphone")
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if case .error = self.state {
                    self.state = .idle
                }
            }
            return
        }

        logger.notice("Audio permission verified - proceeding with recording")

        currentMode = mode
        currentPrompt = prompt
        currentSelectionContext = selectionContext

        // Create temporary file for recording
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "paradict_recording_\(Date().timeIntervalSince1970).wav"
        recordingURL = tempDir.appendingPathComponent(fileName)

        guard let url = recordingURL else {
            logger.error("Failed to create recording URL")
            return
        }

        logger.notice("Recording to: \(url.path)")

        do {
            try await recordingService.startRecording(toOutputFile: url)
            state = .recording
            hotkeyManager.isRecording = true
            indicatorManager.show()
            logger.notice("Recording started successfully in \(mode.rawValue) mode")
        } catch {
            state = .error("Failed to start recording: \(error.localizedDescription)")
            logger.error("Failed to start recording: \(error.localizedDescription)")
        }
    }

    func stopRecording() async {
        logger.notice("stopRecording called - current state: \(String(describing: self.state))")

        guard state == .recording else {
            logger.warning("Cannot stop recording - state is not recording: \(String(describing: self.state))")
            return
        }

        recordingService.stopRecording()
        hotkeyManager.isRecording = false
        logger.notice("RecordingService stopped")

        guard let url = recordingURL else {
            logger.error("No recording URL available")
            state = .idle
            return
        }

        // Check file exists and has content
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            logger.notice("Recording file size: \(size) bytes")
        }

        await processRecording(url: url)
    }

    private func processRecording(url: URL) async {
        logger.notice("processRecording called - file: \(url.lastPathComponent)")
        state = .transcribing
        hotkeyManager.isProcessing = true

        defer {
            logger.notice("Cleaning up recording file")
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
            hotkeyManager.isProcessing = false
            // Note: Don't call cancelRecording() here - it corrupts state in submit-and-continue mode
            // We call it explicitly only when NOT continuing
        }

        do {
            // Transcribe with Parakeet
            logger.notice("Starting Parakeet transcription...")
            let transcription = try await transcriptionService.transcribe(audioURL: url)
            lastTranscription = transcription
            logger.notice("Transcription complete (\(transcription.count) chars): \(transcription.prefix(100))...")

            // Check for empty transcription (indicates silent recording or no speech)
            let trimmedTranscription = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedTranscription.isEmpty {
                logger.warning("Transcription is empty - no speech detected")
                indicatorManager.hide()
                hotkeyManager.shouldContinueAfterSubmit = false
                hotkeyManager.cancelRecording()
                state = .error("No speech detected. Please check microphone permission and try speaking louder.")
                Task {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    if case .error = self.state {
                        self.state = .idle
                    }
                }
                return
            }

            // Check for "correction" keyword to trigger correction popup
            if isCorrectionKeyword(trimmedTranscription) {
                logger.notice("Correction keyword detected")
                indicatorManager.hide()
                hotkeyManager.shouldContinueAfterSubmit = false
                hotkeyManager.cancelRecording()

                if let rawTranscription = lastRawTranscription, let pastedText = lastPastedText {
                    logger.notice("Opening correction window - raw: \(rawTranscription.prefix(30))..., pasted: \(pastedText.prefix(30))...")
                    correctionWindowManager.show(originalTranscription: rawTranscription, llmOutput: pastedText)
                } else {
                    logger.warning("No previous dictation to correct")
                    state = .error("No previous dictation to correct")
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        if case .error = self.state {
                            self.state = .idle
                        }
                    }
                }
                state = .idle
                return
            }

            // Check accessibility permission before attempting to paste
            let canPaste = AXIsProcessTrusted()
            if !canPaste {
                logger.warning("Accessibility permission not granted - copying to clipboard only")
            }

            // Check if we need LLM enhancement (enhanced or reply mode)
            if (currentMode == .enhanced || currentMode == .reply), let prompt = currentPrompt ?? defaultEnhancementPrompt {
                // Check if LLM is configured
                guard llmClient.isConfigured else {
                    logger.warning("LLM enhancement requested but no API key configured - falling back to raw transcription")
                    indicatorManager.hide()
                    hotkeyManager.shouldContinueAfterSubmit = false
                    hotkeyManager.cancelRecording()
                    state = .error("LLM not configured. Add your Groq API key in Settings > LLM")
                    // Still paste the raw transcription
                    if canPaste {
                        PastingService.pasteAtCursor(transcription)
                    }
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        if case .error = self.state {
                            self.state = .idle
                        }
                    }
                    return
                }

                state = .enhancing
                logger.notice("Starting LLM enhancement with prompt: \(prompt.prefix(50))...")

                // Build the user message based on mode
                let userMessage: String
                if currentMode == .reply, let context = currentSelectionContext {
                    // Reply mode: include highlighted text and user instructions
                    userMessage = """
                    HIGHLIGHTED TEXT:
                    \(context)

                    USER INSTRUCTIONS:
                    \(transcription)
                    """
                    logger.notice("Reply mode with context (\(context.count) chars)")
                } else {
                    // Enhanced mode: just the transcription
                    userMessage = transcription
                }

                let enhanced = try await llmClient.enhance(text: userMessage, systemPrompt: prompt)
                lastEnhancement = enhanced
                logger.notice("Enhancement complete (\(enhanced.count) chars)")

                // Paste the enhanced text
                if canPaste {
                    logger.notice("Pasting enhanced text at cursor...")
                    PastingService.pasteAtCursor(enhanced)
                    lastRawTranscription = transcription
                    lastPastedText = enhanced

                    // Log enhanced transcription with prompt and response
                    let targetApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                    historyLogger.logEnhancedTranscription(
                        transcription: transcription,
                        llmPrompt: prompt,
                        llmResponse: enhanced,
                        targetApp: targetApp
                    )
                } else {
                    // Fall back to just copying to clipboard
                    logger.notice("Copying enhanced text to clipboard (no accessibility)...")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(enhanced, forType: .string)
                    indicatorManager.hide()
                    hotkeyManager.shouldContinueAfterSubmit = false
                    hotkeyManager.cancelRecording()
                    state = .error("Text copied to clipboard. Grant Accessibility permission to auto-paste.")
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        if case .error = self.state {
                            self.state = .idle
                        }
                    }
                    return
                }
            } else {
                // Local mode - paste transcription directly
                if canPaste {
                    logger.notice("Pasting transcription at cursor (local mode)...")
                    PastingService.pasteAtCursor(transcription)
                    lastRawTranscription = transcription
                    lastPastedText = transcription

                    // Log local transcription
                    let targetApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                    historyLogger.logLocalTranscription(
                        transcription: transcription,
                        targetApp: targetApp
                    )
                } else {
                    // Fall back to just copying to clipboard
                    logger.notice("Copying transcription to clipboard (no accessibility)...")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(transcription, forType: .string)
                    indicatorManager.hide()
                    hotkeyManager.shouldContinueAfterSubmit = false
                    hotkeyManager.cancelRecording()
                    state = .error("Text copied to clipboard. Grant Accessibility permission to auto-paste.")
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        if case .error = self.state {
                            self.state = .idle
                        }
                    }
                    return
                }
            }

            logger.notice("Processing complete")
            indicatorManager.hide()

            // Check if we should submit (press Enter) and continue with a new recording
            if hotkeyManager.shouldContinueAfterSubmit {
                hotkeyManager.shouldContinueAfterSubmit = false
                let savedMode = currentMode

                logger.notice("Submit and continue mode - pressing Enter and restarting recording")

                // Wait for paste to complete (paste has 50ms delay, plus some buffer)
                try? await Task.sleep(nanoseconds: 150_000_000)

                // Press Enter to submit the message
                PastingService.pressEnter()

                // Small delay before starting new recording
                try? await Task.sleep(nanoseconds: 100_000_000)

                // Use HotkeyManager to start a new recording through the existing mechanism
                state = .idle
                hotkeyManager.startContinuedRecording(mode: savedMode)
            } else {
                hotkeyManager.cancelRecording()
                state = .idle
            }
        } catch {
            logger.error("Processing failed: \(error.localizedDescription)")
            indicatorManager.hide()
            hotkeyManager.shouldContinueAfterSubmit = false
            hotkeyManager.cancelRecording()
            state = .error(error.localizedDescription)

            // Reset to idle after a delay
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if case .error = self.state {
                    logger.notice("Resetting from error state to idle")
                    self.state = .idle
                }
            }
        }

        currentPrompt = nil
        currentSelectionContext = nil
    }

    private var defaultEnhancementPrompt: String? {
        // Get the prompt file from the enhanced shortcut config
        guard let enhancedConfig = ConfigManager.shared.config.shortcuts.first(where: { $0.mode == .enhanced }),
              let promptFile = enhancedConfig.promptFile else {
            return nil
        }
        return PromptManager.shared.loadPrompt(named: promptFile)
    }

    func cancelRecording() {
        logger.notice("cancelRecording called - current state: \(String(describing: self.state))")
        if state == .recording {
            recordingService.stopRecording()
            hotkeyManager.isRecording = false
            hotkeyManager.cancelRecording()
            indicatorManager.hide()

            if let url = recordingURL {
                try? FileManager.default.removeItem(at: url)
            }
            recordingURL = nil
        }
        hotkeyManager.shouldContinueAfterSubmit = false
        state = .idle
    }

    var audioMeter: AudioMeter {
        recordingService.audioMeter
    }

    /// Check if the transcription is just the correction keyword
    private func isCorrectionKeyword(_ text: String) -> Bool {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Match "correction", "correct", or common variations with punctuation
        let correctionPatterns = ["correction", "correction.", "correct", "correct."]
        return correctionPatterns.contains(normalized)
    }
}
