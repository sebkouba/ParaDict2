import Foundation
import os

/// Pure state machine for dictation flow.
/// Contains only state transition logic - no side effects are executed here.
/// The coordinator is responsible for executing the returned side effects.
final class DictationStateMachine {
    private let logger = Logger(subsystem: "com.paradict", category: "StateMachine")

    /// Current state of the dictation flow
    private(set) var state: DictationStateSM = .idle

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
            state = .recording(mode: mode, prompt: prompt, isHandsFree: false)
            return [
                .startRecording(mode: mode, prompt: prompt, context: context),
                .showIndicator,
                .startKeyMonitors
            ]

        // Ignore other events in idle state
        case (.idle, _):
            return []

        // MARK: - From Recording (not hands-free)

        case (.recording(let mode, let prompt, false), .hotkeyUp(let duration)):
            if duration < briefPressThreshold {
                // Brief press - activate hands-free mode
                state = .recording(mode: mode, prompt: prompt, isHandsFree: true)
                return []
            } else {
                // Long press - stop recording
                state = .transcribing(mode: mode, prompt: prompt, continueAfter: false)
                return [.stopRecording, .stopKeyMonitors]
            }

        // MARK: - From Recording (hands-free)

        case (.recording(let mode, let prompt, true), .hotkeyDown):
            // Second press in hands-free mode - stop recording
            state = .transcribing(mode: mode, prompt: prompt, continueAfter: false)
            return [.stopRecording, .stopKeyMonitors]

        case (.recording(let mode, let prompt, true), .enterPressed):
            // Enter in hands-free mode - stop recording and continue after paste
            state = .transcribing(mode: mode, prompt: prompt, continueAfter: true)
            return [.stopRecording, .stopKeyMonitors]

        // MARK: - From Recording (any)

        case (.recording, .escapePressed):
            state = .idle
            return [.cancelRecording, .hideIndicator, .stopKeyMonitors]

        case (.recording(let mode, let prompt, _), .recordingComplete(let url)):
            // Recording stopped - start transcription
            state = .transcribing(mode: mode, prompt: prompt, continueAfter: state.shouldContinueAfter)
            return [.transcribe(url: url)]

        // MARK: - From Transcribing

        case (.transcribing(let mode, let prompt, let continueAfter), .transcriptionComplete(let text)):
            // Check if we need LLM enhancement
            if (mode == .enhanced || mode == .reply), let prompt = prompt {
                state = .enhancing(mode: mode, prompt: prompt, continueAfter: continueAfter)
                return [.enhance(text: text, prompt: prompt, context: nil)]
            } else {
                // Local mode or no prompt - go straight to pasting
                state = .pasting(mode: mode, prompt: prompt, continueAfter: continueAfter)
                return [
                    .paste(text: text),
                    .logTranscription(transcription: text, enhanced: nil, mode: mode),
                    .schedulePasteComplete
                ]
            }

        case (.transcribing, .transcriptionEmpty):
            state = .error(message: "No speech detected")
            return [.hideIndicator, .showError(message: "No speech detected"), .scheduleErrorTimeout]

        case (.transcribing, .escapePressed):
            // Allow canceling during transcription
            state = .idle
            return [.hideIndicator]

        // MARK: - From Enhancing

        case (.enhancing(let mode, let prompt, let continueAfter), .enhancementComplete(let text)):
            state = .pasting(mode: mode, prompt: prompt, continueAfter: continueAfter)
            return [
                .paste(text: text),
                .schedulePasteComplete
            ]

        case (.enhancing(let mode, let prompt, let continueAfter), .enhancementSkipped(let text)):
            // LLM not available - use raw transcription
            state = .pasting(mode: mode, prompt: prompt, continueAfter: continueAfter)
            return [
                .paste(text: text),
                .logTranscription(transcription: text, enhanced: nil, mode: mode),
                .schedulePasteComplete
            ]

        case (.enhancing, .escapePressed):
            // Allow canceling during enhancement
            state = .idle
            return [.hideIndicator]

        // MARK: - From Pasting

        case (.pasting(let mode, let prompt, true), .pasteComplete):
            // Continue after paste - press Enter and restart recording
            // Don't hide/show indicator - keep it visible to avoid white flash
            state = .recording(mode: mode, prompt: prompt, isHandsFree: true)
            return [
                .pressEnterKey,
                .startRecording(mode: mode, prompt: prompt, context: nil),
                .startKeyMonitors
            ]

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
            state = .recording(mode: mode, prompt: prompt, isHandsFree: false)
            return [
                .startRecording(mode: mode, prompt: prompt, context: context),
                .showIndicator,
                .startKeyMonitors
            ]

        // MARK: - Error from any state

        case (_, .error(let message)):
            state = .error(message: message)
            return [.hideIndicator, .stopKeyMonitors, .showError(message: message), .scheduleErrorTimeout]

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
    func setState(_ newState: DictationStateSM) {
        state = newState
    }

    /// Reset to idle state (for testing only)
    func reset() {
        state = .idle
    }
    #endif
}
