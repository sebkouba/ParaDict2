import Foundation

/// What to do after pasting text: stop, send (Enter) and continue, or send and stop.
enum PostPasteAction: Equatable {
    /// Normal: paste and go idle (no Enter)
    case stop
    /// Enter key: paste, press Enter, restart recording
    case sendAndContinue
    /// Command key: paste, press Enter, go idle
    case sendAndStop
}

/// Represents all possible states in the dictation flow.
/// Associated data captures context that belongs WITH the state, not as separate flags.
enum DictationState: Equatable {
    /// Idle - waiting for user to start dictation
    case idle

    /// Recording audio
    /// - mode: The dictation mode (local, enhanced, reply)
    /// - prompt: The prompt to use for enhancement (if applicable)
    /// - isHandsFree: True if user did a brief press (tap-to-record), false if holding
    /// - enterMonitorPending: True if Enter key monitor hasn't started yet (after sendAndContinue)
    /// - commandMonitorPending: True if Command key monitor hasn't started yet (after hotkeyDown)
    case recording(mode: DictationMode, prompt: String?, isHandsFree: Bool, enterMonitorPending: Bool = false, commandMonitorPending: Bool = false)

    /// Transcribing recorded audio with Parakeet
    /// - mode: The dictation mode
    /// - prompt: The prompt to use for enhancement (if applicable)
    /// - postPasteAction: What to do after pasting (stop, send+continue, send+stop)
    case transcribing(mode: DictationMode, prompt: String?, postPasteAction: PostPasteAction)

    /// Enhancing transcription with LLM
    /// - mode: The dictation mode
    /// - prompt: The prompt used for enhancement
    /// - postPasteAction: What to do after pasting (stop, send+continue, send+stop)
    case enhancing(mode: DictationMode, prompt: String?, postPasteAction: PostPasteAction)

    /// Pasting text to cursor
    /// - mode: The dictation mode (needed for potential restart)
    /// - prompt: The prompt (needed for potential restart)
    /// - postPasteAction: What to do after pasting (stop, send+continue, send+stop)
    case pasting(mode: DictationMode, prompt: String?, postPasteAction: PostPasteAction)

    /// Executing a voice command via tool calls
    /// - mode: The dictation mode
    /// - prompt: The prompt used for command parsing
    case executingCommand(mode: DictationMode, prompt: String?)

    /// Error state - displays error message then returns to idle
    case error(message: String)

    // MARK: - Convenience Properties

    /// Returns the mode if in a state that has one
    var mode: DictationMode? {
        switch self {
        case .idle, .error:
            return nil
        case .recording(let mode, _, _, _, _),
             .transcribing(let mode, _, postPasteAction: _),
             .enhancing(let mode, _, postPasteAction: _),
             .pasting(let mode, _, postPasteAction: _),
             .executingCommand(let mode, _):
            return mode
        }
    }

    /// Returns true if currently recording
    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    /// Returns true if processing (transcribing, enhancing, pasting, or executing command)
    var isProcessing: Bool {
        switch self {
        case .transcribing, .enhancing, .pasting, .executingCommand:
            return true
        default:
            return false
        }
    }

    /// Returns true if in hands-free recording mode
    var isHandsFree: Bool {
        if case .recording(_, _, let handsFree, _, _) = self {
            return handsFree
        }
        return false
    }

    /// Returns the post-paste action for the current state, if applicable
    var postPasteAction: PostPasteAction? {
        switch self {
        case .transcribing(_, _, let action),
             .enhancing(_, _, let action),
             .pasting(_, _, let action):
            return action
        default:
            return nil
        }
    }

    /// Returns true if we should continue after this operation completes
    var shouldContinueAfter: Bool {
        postPasteAction == .sendAndContinue
    }

    /// Returns true if this is an "active" state that should be shown in the indicator
    /// (not idle, error, or pasting - pasting inherits the previous state's color)
    var isActiveForIndicator: Bool {
        switch self {
        case .idle, .error, .pasting:
            return false
        case .recording, .transcribing, .enhancing, .executingCommand:
            return true
        }
    }

    /// Returns the prompt if in a state that has one
    var prompt: String? {
        switch self {
        case .recording(_, let prompt, _, _, _),
             .transcribing(_, let prompt, postPasteAction: _),
             .enhancing(_, let prompt, postPasteAction: _),
             .pasting(_, let prompt, postPasteAction: _),
             .executingCommand(_, let prompt):
            return prompt
        default:
            return nil
        }
    }
}

// MARK: - CustomStringConvertible

extension DictationState: CustomStringConvertible {
    var description: String {
        switch self {
        case .idle:
            return "idle"
        case .recording(let mode, _, let isHandsFree, let enterMonitorPending, let commandMonitorPending):
            var extras: [String] = []
            if enterMonitorPending { extras.append("enterMonitorPending") }
            if commandMonitorPending { extras.append("commandMonitorPending") }
            let suffix = extras.isEmpty ? "" : ", \(extras.joined(separator: ", "))"
            return "recording(\(mode.rawValue), handsFree: \(isHandsFree)\(suffix))"
        case .transcribing(let mode, _, let action):
            return "transcribing(\(mode.rawValue), postPasteAction: \(action))"
        case .enhancing(let mode, _, let action):
            return "enhancing(\(mode.rawValue), postPasteAction: \(action))"
        case .pasting(let mode, _, let action):
            return "pasting(\(mode.rawValue), postPasteAction: \(action))"
        case .executingCommand(let mode, _):
            return "executingCommand(\(mode.rawValue))"
        case .error(let message):
            return "error(\(message.prefix(30))...)"
        }
    }
}
