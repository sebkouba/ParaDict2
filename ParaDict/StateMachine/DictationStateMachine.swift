import Foundation
import os

/// Pure state machine for dictation flow.
/// Contains only state transition logic - no side effects are executed here.
/// The coordinator is responsible for executing the returned side effects.
nonisolated final class DictationStateMachine {
    private let logger = Logger(subsystem: "com.paradict", category: "StateMachine")

    /// Current state of the dictation flow
    private(set) var state: DictationState = .idle

    /// Threshold for distinguishing brief press (tap) from long press (hold)
    private let briefPressThreshold: TimeInterval = 1.0

    /// Handle an event and return any side effects that should be executed
    /// - Parameter event: The event to process
    /// - Returns: Array of side effects to execute (may be empty for invalid transitions)
    func handle(_ event: DictationEvent) -> [DictationSideEffect] {
        let previousState = state
        let effects = processEvent(event)

        if state != previousState {
            logger.notice("State transition: \(previousState.description) -> \(self.state.description)")
        }

        if !effects.isEmpty {
            logger.notice("Side effects: \(effects.map { $0.description }.joined(separator: ", "))")
        }

        return effects
    }

    /// Process an event and compute the new state and side effects
    private func processEvent(_ event: DictationEvent) -> [DictationSideEffect] {
        switch (state, event) {

        // MARK: - From Idle

        case (.idle, .hotkeyDown(let mode, let prompt, let context)):
            state = .recording(mode: mode, prompt: prompt, isHandsFree: false, commandMonitorPending: true)
            return [
                .startRecording(mode: mode, prompt: prompt, context: context),
                .showIndicator,
                .startEscapeMonitor,
                .startEnterMonitor,
                .scheduleCommandMonitorStart,
                .startStreamingPreview
            ]

        // Ignore other events in idle state
        case (.idle, _):
            return []

        // MARK: - From Recording (not hands-free)

        case (.recording(let mode, let prompt, false, _, let cmdPending), .hotkeyUp(let duration)):
            if duration < briefPressThreshold {
                // Brief press - activate hands-free mode, preserve commandMonitorPending
                state = .recording(mode: mode, prompt: prompt, isHandsFree: true, commandMonitorPending: cmdPending)
                return []
            } else {
                // Long press - stop recording
                state = .transcribing(mode: mode, prompt: prompt, postPasteAction: .stop)
                return [.stopRecording, .stopEscapeMonitor, .stopEnterMonitor, .stopCommandMonitor, .stopStreamingPreview]
            }

        // MARK: - From Recording (hands-free, monitor pending states)

        case (.recording(let mode, let prompt, true, true, let cmdPending), .enterMonitorReady):
            // Enter monitor delay completed - now safe to start monitoring
            state = .recording(mode: mode, prompt: prompt, isHandsFree: true, enterMonitorPending: false, commandMonitorPending: cmdPending)
            return [.startEnterMonitor]

        case (.recording(let mode, let prompt, true, let enterPending, true), .commandMonitorReady):
            // Command monitor delay completed - now safe to start monitoring
            state = .recording(mode: mode, prompt: prompt, isHandsFree: true, enterMonitorPending: enterPending, commandMonitorPending: false)
            return [.startCommandMonitor]

        // MARK: - From Recording (hands-free, monitors active)

        case (.recording(let mode, let prompt, true, false, _), .hotkeyDown):
            // Second press in hands-free mode - stop recording
            state = .transcribing(mode: mode, prompt: prompt, postPasteAction: .stop)
            return [.stopRecording, .stopEscapeMonitor, .stopEnterMonitor, .stopCommandMonitor, .stopStreamingPreview]

        case (.recording(let mode, let prompt, true, false, _), .enterPressed):
            // Enter in hands-free mode - stop recording and continue after paste
            state = .transcribing(mode: mode, prompt: prompt, postPasteAction: .sendAndContinue)
            return [.stopRecording, .stopEscapeMonitor, .stopEnterMonitor, .stopCommandMonitor, .stopStreamingPreview]

        case (.recording(let mode, let prompt, true, _, false), .commandPressed):
            // Command in hands-free mode (monitor active) - stop recording, send and stop
            state = .transcribing(mode: mode, prompt: prompt, postPasteAction: .sendAndStop)
            return [.stopRecording, .stopEscapeMonitor, .stopEnterMonitor, .stopCommandMonitor, .stopStreamingPreview]

        // MARK: - From Recording (any)

        case (.recording, .escapePressed):
            state = .idle
            return [.cancelRecording, .hideIndicator, .stopEscapeMonitor, .stopEnterMonitor, .stopCommandMonitor, .stopStreamingPreview]

        // MARK: - From Transcribing

        case (.transcribing(let mode, let prompt, let postPasteAction), .transcriptionComplete(let text)):
            // Check mode for appropriate processing
            if mode == .command, let prompt = prompt {
                // Command mode - execute tool calls
                state = .executingCommand(mode: mode, prompt: prompt)
                return [.executeCommand(text: text, prompt: prompt)]
            } else if (mode == .enhanced || mode == .reply), let prompt = prompt {
                // Enhanced/reply mode - LLM enhancement
                state = .enhancing(mode: mode, prompt: prompt, postPasteAction: postPasteAction)
                return [.enhance(text: text, prompt: prompt, context: nil)]
            } else {
                // Local mode or no prompt - go straight to pasting
                state = .pasting(mode: mode, prompt: prompt, postPasteAction: postPasteAction)
                return [
                    .paste(text: text),
                    .logTranscription(transcription: text, enhanced: nil, mode: mode),
                    .schedulePasteComplete
                ]
            }

        case (.transcribing(let mode, let prompt, let postPasteAction), .transcriptionEmpty):
            if postPasteAction == .sendAndContinue {
                // Continuous mode - restart recording instead of showing error
                state = .recording(mode: mode, prompt: prompt, isHandsFree: true, enterMonitorPending: true)
                return [
                    .startRecording(mode: mode, prompt: prompt, context: nil),
                    .startEscapeMonitor,
                    .scheduleEnterMonitorStart,
                    .startCommandMonitor,
                    .startStreamingPreview
                ]
            } else {
                // Normal mode or sendAndStop - show error
                state = .error(message: "No speech detected")
                return [.hideIndicator, .stopEscapeMonitor, .stopEnterMonitor, .stopCommandMonitor, .showError(message: "No speech detected"), .scheduleErrorTimeout]
            }

        case (.transcribing, .correctionKeywordDetected(let originalTranscription, let llmOutput)):
            state = .idle
            return [.hideIndicator, .stopEscapeMonitor, .stopEnterMonitor, .stopCommandMonitor, .showCorrectionWindow(originalTranscription: originalTranscription, llmOutput: llmOutput)]

        case (.transcribing, .escapePressed):
            // Allow canceling during transcription
            state = .idle
            return [.cancelProcessing, .hideIndicator]

        // MARK: - From Enhancing

        case (.enhancing(let mode, let prompt, let postPasteAction), .enhancementComplete(let text)):
            state = .pasting(mode: mode, prompt: prompt, postPasteAction: postPasteAction)
            return [
                .paste(text: text),
                .schedulePasteComplete
            ]

        case (.enhancing(let mode, let prompt, let postPasteAction), .enhancementSkipped(let text)):
            // LLM not available - use raw transcription
            state = .pasting(mode: mode, prompt: prompt, postPasteAction: postPasteAction)
            return [
                .paste(text: text),
                .logTranscription(transcription: text, enhanced: nil, mode: mode),
                .schedulePasteComplete
            ]

        case (.enhancing, .escapePressed):
            // Allow canceling during enhancement
            state = .idle
            return [.cancelProcessing, .hideIndicator]

        // MARK: - From Executing Command

        case (.executingCommand, .commandComplete):
            state = .idle
            return [.hideIndicator, .flashMenuBarSuccess]

        case (.executingCommand, .commandFailed(let message)):
            state = .error(message: message)
            return [.hideIndicator, .flashMenuBarError, .showError(message: message), .scheduleErrorTimeout]

        case (.executingCommand, .escapePressed):
            // Allow canceling during command execution
            state = .idle
            return [.cancelProcessing, .hideIndicator]

        // MARK: - From Pasting

        case (.pasting(let mode, let prompt, .sendAndContinue), .pasteComplete):
            // Continue after paste - press Enter and restart recording
            // Don't hide/show indicator - keep it visible to avoid white flash
            // IMPORTANT: Start Enter monitor LATER via scheduleEnterMonitorStart to avoid
            // catching the programmatic Enter key (CGEvents are async)
            state = .recording(mode: mode, prompt: prompt, isHandsFree: true, enterMonitorPending: true)
            return [
                .pressEnterKey,
                .startRecording(mode: mode, prompt: prompt, context: nil),
                .startEscapeMonitor,
                .scheduleEnterMonitorStart,
                .startCommandMonitor,
                .startStreamingPreview
            ]

        case (.pasting(_, _, .sendAndStop), .pasteComplete):
            // Send and stop - press Enter then go idle
            state = .idle
            return [.pressEnterKey, .hideIndicator]

        case (.pasting, .pasteComplete):
            // Normal paste complete - return to idle
            state = .idle
            return [.hideIndicator]

        // MARK: - From Error

        case (.error, .errorTimeout):
            state = .idle
            return []

        case (.error, .hotkeyDown(let mode, let prompt, let context)):
            // Allow starting new recording from error state
            state = .recording(mode: mode, prompt: prompt, isHandsFree: false, commandMonitorPending: true)
            return [
                .startRecording(mode: mode, prompt: prompt, context: context),
                .showIndicator,
                .startEscapeMonitor,
                .startEnterMonitor,
                .scheduleCommandMonitorStart,
                .startStreamingPreview
            ]

        // MARK: - Error from any state

        case (_, .error(let message)):
            state = .error(message: message)
            return [.hideIndicator, .stopEscapeMonitor, .stopEnterMonitor, .stopCommandMonitor, .showError(message: message), .scheduleErrorTimeout]

        // MARK: - Default (invalid transitions)

        default:
            logger.warning("Invalid transition: \(self.state.description) + \(event.description)")
            return []
        }
    }

    /// Get the prompt from the current state (for use in transitions)
    private var promptForState: String? {
        state.prompt
    }

    // MARK: - Testing Support

    #if DEBUG
    /// Set state directly (for testing only)
    func setState(_ newState: DictationState) {
        state = newState
    }

    /// Reset to idle state (for testing only)
    func reset() {
        state = .idle
    }
    #endif
}
