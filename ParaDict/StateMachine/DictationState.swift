import Foundation

/// Represents all possible states in the dictation flow.
/// Associated data captures context that belongs WITH the state, not as separate flags.
/// Named with "SM" suffix to avoid conflict with existing DictationState during transition.
enum DictationStateSM: Equatable {
    /// Idle - waiting for user to start dictation
    case idle

    /// Recording audio
    /// - mode: The dictation mode (local, enhanced, reply)
    /// - prompt: The prompt to use for enhancement (if applicable)
    /// - isHandsFree: True if user did a brief press (tap-to-record), false if holding
    /// - enterMonitorPending: True if Enter key monitor hasn't started yet (after continueAfter)
    case recording(mode: DictationMode, prompt: String?, isHandsFree: Bool, enterMonitorPending: Bool = false)

    /// Transcribing recorded audio with Parakeet
    /// - mode: The dictation mode
    /// - prompt: The prompt to use for enhancement (if applicable)
    /// - continueAfter: True if we should press Enter and restart after pasting
    case transcribing(mode: DictationMode, prompt: String?, continueAfter: Bool)

    /// Enhancing transcription with LLM
    /// - mode: The dictation mode
    /// - prompt: The prompt used for enhancement
    /// - continueAfter: True if we should press Enter and restart after pasting
    case enhancing(mode: DictationMode, prompt: String?, continueAfter: Bool)

    /// Pasting text to cursor
    /// - mode: The dictation mode (needed for potential restart)
    /// - prompt: The prompt (needed for potential restart)
    /// - continueAfter: True if we should press Enter and restart after pasting
    case pasting(mode: DictationMode, prompt: String?, continueAfter: Bool)

    /// Error state - displays error message then returns to idle
    case error(message: String)

    // MARK: - Convenience Properties

    /// Returns the mode if in a state that has one
    var mode: DictationMode? {
        switch self {
        case .idle, .error:
            return nil
        case .recording(let mode, _, _, _),
             .transcribing(let mode, _, _),
             .enhancing(let mode, _, _),
             .pasting(let mode, _, _):
            return mode
        }
    }

    /// Returns true if currently recording
    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    /// Returns true if processing (transcribing, enhancing, or pasting)
    var isProcessing: Bool {
        switch self {
        case .transcribing, .enhancing, .pasting:
            return true
        default:
            return false
        }
    }

    /// Returns true if in hands-free recording mode
    var isHandsFree: Bool {
        if case .recording(_, _, let handsFree, _) = self {
            return handsFree
        }
        return false
    }

    /// Returns true if we should continue after this operation completes
    var shouldContinueAfter: Bool {
        switch self {
        case .transcribing(_, _, let continueAfter),
             .enhancing(_, _, let continueAfter),
             .pasting(_, _, let continueAfter):
            return continueAfter
        default:
            return false
        }
    }

    /// Returns true if this is an "active" state that should be shown in the indicator
    /// (not idle or error)
    var isActiveForIndicator: Bool {
        switch self {
        case .idle, .error:
            return false
        case .recording, .transcribing, .enhancing, .pasting:
            return true
        }
    }

    /// Returns the prompt if in a state that has one
    var prompt: String? {
        switch self {
        case .recording(_, let prompt, _, _),
             .transcribing(_, let prompt, _),
             .enhancing(_, let prompt, _),
             .pasting(_, let prompt, _):
            return prompt
        default:
            return nil
        }
    }
}

// MARK: - CustomStringConvertible

extension DictationStateSM: CustomStringConvertible {
    var description: String {
        switch self {
        case .idle:
            return "idle"
        case .recording(let mode, _, let isHandsFree, let enterMonitorPending):
            if enterMonitorPending {
                return "recording(\(mode.rawValue), handsFree: \(isHandsFree), enterMonitorPending)"
            } else {
                return "recording(\(mode.rawValue), handsFree: \(isHandsFree))"
            }
        case .transcribing(let mode, _, let continueAfter):
            return "transcribing(\(mode.rawValue), continueAfter: \(continueAfter))"
        case .enhancing(let mode, _, let continueAfter):
            return "enhancing(\(mode.rawValue), continueAfter: \(continueAfter))"
        case .pasting(let mode, _, let continueAfter):
            return "pasting(\(mode.rawValue), continueAfter: \(continueAfter))"
        case .error(let message):
            return "error(\(message.prefix(30))...)"
        }
    }
}
