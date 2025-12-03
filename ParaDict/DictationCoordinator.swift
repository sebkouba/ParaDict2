import Foundation
import AppKit
import Combine
import os

/// Coordinates the dictation flow by owning the state machine and executing side effects.
/// This is the bridge between events (from HotkeyManager) and services (recording, transcription, etc.)
@MainActor
final class DictationCoordinator: ObservableObject {
    static let shared = DictationCoordinator()

    private let logger = Logger(subsystem: "com.paradict", category: "DictationCoordinator")

    // MARK: - State Machine

    private let stateMachine = DictationStateMachine()

    /// Published state for UI binding (derived from state machine)
    @Published private(set) var state: DictationStateSM = .idle

    // MARK: - Services

    let recordingService = RecordingService()
    private let transcriptionService = ParakeetTranscriptionService.shared
    private let llmClient = LLMClient.shared
    private let indicatorManager = RecordingIndicatorWindowManager.shared
    private let historyLogger = TranscriptionHistoryLogger.shared
    private let correctionWindowManager = CorrectionWindowManager.shared

    // MARK: - State

    private var currentRecordingURL: URL?
    private var currentContext: String?  // For reply mode
    private var errorTimeoutTask: Task<Void, Never>?
    private var pasteCompleteTask: Task<Void, Never>?
    private var enterMonitorStartTask: Task<Void, Never>?

    /// Tracks the last raw transcription from Parakeet (for correction feature)
    private var lastRawTranscription: String?
    /// Tracks the last text that was actually pasted - may be LLM-enhanced (for correction feature)
    private var lastPastedText: String?

    // MARK: - Initialization

    private init() {
        logger.notice("DictationCoordinator initializing...")
    }

    // MARK: - Event Handling

    /// Send an event to the state machine and execute resulting side effects
    func send(_ event: DictationEvent) {
        logger.notice("Received event: \(event.description)")

        let effects = stateMachine.handle(event)
        state = stateMachine.state

        // Execute side effects
        for effect in effects {
            execute(effect)
        }
    }

    // MARK: - Side Effect Execution

    private func execute(_ effect: DictationSideEffect) {
        logger.notice("Executing: \(effect.description)")

        switch effect {
        case .startRecording(let mode, let prompt, let context):
            Task {
                await startRecording(mode: mode, prompt: prompt, context: context)
            }

        case .stopRecording:
            stopRecording()

        case .cancelRecording:
            cancelRecording()

        case .cleanupRecordingFile(let url):
            cleanupFile(url)

        case .transcribe(let url):
            Task {
                await transcribe(url: url)
            }

        case .enhance(let text, let prompt, let context):
            Task {
                await enhance(text: text, prompt: prompt, context: context)
            }

        case .paste(let text):
            paste(text)

        case .pressEnterKey:
            PastingService.pressEnter()

        case .showIndicator:
            indicatorManager.show()

        case .hideIndicator:
            indicatorManager.hide()

        case .showError(let message):
            // Error is shown via state - UI observes state.error
            logger.error("Error: \(message)")

        case .startEscapeMonitor:
            HotkeyManager.shared.startEscapeKeyMonitor()

        case .stopEscapeMonitor:
            HotkeyManager.shared.stopEscapeKeyMonitor()

        case .startEnterMonitor:
            HotkeyManager.shared.startEnterKeyMonitor()

        case .stopEnterMonitor:
            HotkeyManager.shared.stopEnterKeyMonitor()

        case .scheduleEnterMonitorStart:
            scheduleEnterMonitorStart()

        case .scheduleErrorTimeout:
            scheduleErrorTimeout()

        case .schedulePasteComplete:
            schedulePasteComplete()

        case .logTranscription(let transcription, let enhanced, let mode):
            logTranscription(transcription: transcription, enhanced: enhanced, mode: mode)

        case .executeCommand(let text, let prompt):
            Task {
                await executeCommand(text: text, prompt: prompt)
            }

        case .flashMenuBarSuccess:
            flashMenuBar(success: true)

        case .flashMenuBarError:
            flashMenuBar(success: false)

        case .showCorrectionWindow(let originalTranscription, let llmOutput):
            logger.notice("Showing correction window - raw: \(originalTranscription.prefix(30))..., pasted: \(llmOutput.prefix(30))...")
            correctionWindowManager.show(originalTranscription: originalTranscription, llmOutput: llmOutput)
        }
    }

    // MARK: - Recording

    private func startRecording(mode: DictationMode, prompt: String?, context: String?) async {
        // Store context for later use
        currentContext = context

        // Create temp file for recording
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "paradict_recording_\(Date().timeIntervalSinceReferenceDate).wav"
        let url = tempDir.appendingPathComponent(fileName)
        currentRecordingURL = url

        logger.notice("Starting recording to: \(url.lastPathComponent)")

        do {
            try await recordingService.startRecording(toOutputFile: url)
            logger.notice("Recording started successfully")
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
            send(.error(message: "Failed to start recording: \(error.localizedDescription)"))
        }
    }

    private func stopRecording() {
        recordingService.stopRecording()
        logger.notice("Recording stopped")

        // Transcribe immediately - the state machine has already transitioned to transcribing
        if let url = currentRecordingURL {
            Task {
                await transcribe(url: url)
            }
        }
    }

    private func cancelRecording() {
        recordingService.stopRecording()

        if let url = currentRecordingURL {
            cleanupFile(url)
        }
        currentRecordingURL = nil
        currentContext = nil

        logger.notice("Recording cancelled")
    }

    private func cleanupFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        if currentRecordingURL == url {
            currentRecordingURL = nil
        }
    }

    // MARK: - Transcription

    private func transcribe(url: URL) async {
        do {
            let text = try await transcriptionService.transcribe(audioURL: url)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

            // Clean up the recording file
            cleanupFile(url)

            if trimmed.isEmpty {
                send(.transcriptionEmpty)
            } else if isCorrectionKeyword(trimmed) {
                // Check for correction keyword
                logger.notice("Correction keyword detected")
                if let rawTranscription = lastRawTranscription, let pastedText = lastPastedText {
                    send(.correctionKeywordDetected(originalTranscription: rawTranscription, llmOutput: pastedText))
                } else {
                    logger.warning("No previous dictation to correct")
                    send(.error(message: "No previous dictation to correct"))
                }
            } else {
                // Store raw transcription for correction feature
                lastRawTranscription = trimmed
                send(.transcriptionComplete(text: trimmed))
            }
        } catch {
            cleanupFile(url)
            send(.error(message: "Transcription failed: \(error.localizedDescription)"))
        }
    }

    /// Check if the transcription is just the correction keyword
    private func isCorrectionKeyword(_ text: String) -> Bool {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Match "correction", "correct", or common variations with punctuation
        let correctionPatterns = ["correction", "correction.", "correct", "correct."]
        return correctionPatterns.contains(normalized)
    }

    // MARK: - Enhancement

    private func enhance(text: String, prompt: String, context: String?) async {
        guard llmClient.isConfigured else {
            logger.warning("LLM not configured - skipping enhancement")
            send(.enhancementSkipped(text: text))
            return
        }

        do {
            // Build the user message based on whether we have context
            let userMessage: String
            if let context = context ?? currentContext {
                userMessage = """
                HIGHLIGHTED TEXT:
                \(context)

                USER INSTRUCTIONS:
                \(text)
                """
            } else {
                userMessage = text
            }

            let enhanced = try await llmClient.enhance(text: userMessage, systemPrompt: prompt)

            // Log enhanced transcription
            logTranscription(transcription: text, enhanced: enhanced, mode: stateMachine.state.mode ?? .enhanced)

            send(.enhancementComplete(text: enhanced))
        } catch {
            logger.error("Enhancement failed: \(error.localizedDescription)")
            // Fall back to raw text on error
            send(.enhancementSkipped(text: text))
        }
    }

    // MARK: - Pasting

    private func paste(_ text: String) {
        // Track pasted text for correction feature
        lastPastedText = text
        PastingService.pasteAtCursor(text)
    }

    // MARK: - Timers

    private func scheduleErrorTimeout() {
        errorTimeoutTask?.cancel()
        errorTimeoutTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)  // 3 seconds
            if !Task.isCancelled {
                send(.errorTimeout)
            }
        }
    }

    private func schedulePasteComplete() {
        pasteCompleteTask?.cancel()
        pasteCompleteTask = Task {
            // Wait for paste to complete (paste has 50ms delay + 100ms buffer)
            try? await Task.sleep(nanoseconds: 250_000_000)
            if !Task.isCancelled {
                send(.pasteComplete)
            }
        }
    }

    private func scheduleEnterMonitorStart() {
        enterMonitorStartTask?.cancel()
        enterMonitorStartTask = Task {
            // Wait for programmatic Enter CGEvent to be fully processed
            // 300ms is enough for the async CGEvent to propagate through the system
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !Task.isCancelled {
                send(.enterMonitorReady)
            }
        }
    }

    // MARK: - Logging

    private func logTranscription(transcription: String, enhanced: String?, mode: DictationMode) {
        let targetApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        if let enhanced = enhanced {
            historyLogger.logEnhancedTranscription(
                transcription: transcription,
                llmPrompt: "",  // We don't have access to the full prompt here
                llmResponse: enhanced,
                targetApp: targetApp
            )
        } else {
            historyLogger.logLocalTranscription(
                transcription: transcription,
                targetApp: targetApp
            )
        }
    }

    // MARK: - Command Execution

    private func executeCommand(text: String, prompt: String) async {
        let executor = CommandExecutorService.shared
        let tools = executor.getToolDefinitions()

        guard !tools.isEmpty else {
            send(.commandFailed(message: "No tools configured. Check tools.json"))
            return
        }

        let messages = [
            ChatMessage(role: "system", content: prompt),
            ChatMessage(role: "user", content: text)
        ]

        do {
            let result = try await llmClient.chatWithTools(messages: messages, tools: tools)

            switch result {
            case .content(let response):
                // LLM responded with text instead of tool call
                logger.notice("LLM returned text (no tool call): \(response.prefix(50))...")
                send(.commandFailed(message: "Command not recognized: \(text)"))

            case .toolCalls(let toolCalls):
                // Execute each tool call
                for toolCall in toolCalls {
                    let output = try await executor.execute(toolCall: toolCall)
                    logger.notice("Tool executed: \(toolCall.function.name) -> \(output)")
                }
                send(.commandComplete)
            }
        } catch {
            logger.error("Command execution failed: \(error.localizedDescription)")
            send(.commandFailed(message: error.localizedDescription))
        }
    }

    // MARK: - Menu Bar Flash

    private func flashMenuBar(success: Bool) {
        // Post notification for menu bar to flash
        NotificationCenter.default.post(
            name: .menuBarFlash,
            object: nil,
            userInfo: ["success": success]
        )
    }

    // MARK: - Public Interface (for UI/debugging)

    /// Current state for UI observation
    var currentState: DictationStateSM {
        stateMachine.state
    }

    /// Whether currently recording
    var isRecording: Bool {
        stateMachine.state.isRecording
    }

    /// Whether currently processing
    var isProcessing: Bool {
        stateMachine.state.isProcessing
    }
}

// MARK: - Notification for menu bar flash

extension Notification.Name {
    static let menuBarFlash = Notification.Name("menuBarFlash")
}

