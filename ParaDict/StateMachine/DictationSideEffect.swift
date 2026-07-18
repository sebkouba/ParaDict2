import Foundation

/// Side effects that should be executed when state transitions occur.
/// The state machine returns these, but doesn't execute them directly.
/// The coordinator is responsible for executing side effects.
enum DictationSideEffect: Equatable {
    // MARK: - Recording

    /// Start recording audio
    /// - mode: The dictation mode
    /// - prompt: The prompt for enhancement (stored for later use)
    /// - context: Selected text context (for reply mode)
    case startRecording(mode: DictationMode, prompt: String?, context: String?)

    /// Stop the current recording (will trigger recordingComplete event)
    case stopRecording

    /// Cancel recording and discard the audio
    case cancelRecording

    /// Cancel transcription, enhancement, or command work that is still in flight
    case cancelProcessing

    // MARK: - Processing

    /// Enhance text with LLM
    /// - text: The transcription to enhance
    /// - prompt: The system prompt for the LLM
    /// - context: Selected text context (for reply mode)
    case enhance(text: String, prompt: String, context: String?)

    /// Paste text at cursor
    /// - text: The text to paste
    case paste(text: String)

    /// Press the Enter key (to submit in chat)
    case pressEnterKey

    // MARK: - UI

    /// Show the recording indicator
    case showIndicator

    /// Hide the recording indicator
    case hideIndicator

    /// Show an error message (will auto-dismiss)
    case showError(message: String)

    // MARK: - Key Monitoring

    /// Start monitoring for Escape key only
    case startEscapeMonitor

    /// Stop monitoring for Escape key
    case stopEscapeMonitor

    /// Start monitoring for Enter key only
    case startEnterMonitor

    /// Stop monitoring for Enter key
    case stopEnterMonitor

    /// Start monitoring for Command key (send and stop)
    case startCommandMonitor

    /// Stop monitoring for Command key
    case stopCommandMonitor

    /// Schedule a timer to start Enter monitor after delay (avoids catching programmatic Enter)
    case scheduleEnterMonitorStart

    /// Schedule a timer to start Command monitor after delay (avoids catching Command key-up from shortcut)
    case scheduleCommandMonitorStart

    // MARK: - Timers

    /// Schedule a timer to dismiss error after delay
    case scheduleErrorTimeout

    /// Schedule paste completion event after paste delay
    case schedulePasteComplete

    // MARK: - History

    /// Log the transcription to history
    /// - transcription: The raw transcription
    /// - enhanced: The enhanced text (if any)
    /// - mode: The dictation mode
    case logTranscription(transcription: String, enhanced: String?, mode: DictationMode)

    // MARK: - Command Execution

    /// Execute a voice command via LLM tool calling
    /// - text: The transcribed command text
    /// - prompt: The system prompt for command parsing
    case executeCommand(text: String, prompt: String)

    /// Flash the menu bar to indicate success
    case flashMenuBarSuccess

    /// Flash the menu bar to indicate error
    case flashMenuBarError

    // MARK: - Correction

    /// Show the correction window with previous dictation
    /// - originalTranscription: Raw transcription from Parakeet
    /// - llmOutput: What was actually pasted
    case showCorrectionWindow(originalTranscription: String, llmOutput: String)

    // MARK: - Streaming Preview

    /// Start the streaming transcription preview (during recording)
    case startStreamingPreview

    /// Stop the streaming transcription preview (when recording stops)
    case stopStreamingPreview
}

// MARK: - CustomStringConvertible

extension DictationSideEffect: CustomStringConvertible {
    var description: String {
        switch self {
        case .startRecording(let mode, let prompt, let context):
            return "startRecording(\(mode.rawValue), hasPrompt: \(prompt != nil), hasContext: \(context != nil))"
        case .stopRecording:
            return "stopRecording"
        case .cancelRecording:
            return "cancelRecording"
        case .cancelProcessing:
            return "cancelProcessing"
        case .enhance(let text, _, _):
            return "enhance(\(text.prefix(20))...)"
        case .paste(let text):
            return "paste(\(text.prefix(20))...)"
        case .pressEnterKey:
            return "pressEnterKey"
        case .showIndicator:
            return "showIndicator"
        case .hideIndicator:
            return "hideIndicator"
        case .showError(let message):
            return "showError(\(message.prefix(30))...)"
        case .startEscapeMonitor:
            return "startEscapeMonitor"
        case .stopEscapeMonitor:
            return "stopEscapeMonitor"
        case .startEnterMonitor:
            return "startEnterMonitor"
        case .stopEnterMonitor:
            return "stopEnterMonitor"
        case .startCommandMonitor:
            return "startCommandMonitor"
        case .stopCommandMonitor:
            return "stopCommandMonitor"
        case .scheduleEnterMonitorStart:
            return "scheduleEnterMonitorStart"
        case .scheduleCommandMonitorStart:
            return "scheduleCommandMonitorStart"
        case .scheduleErrorTimeout:
            return "scheduleErrorTimeout"
        case .schedulePasteComplete:
            return "schedulePasteComplete"
        case .logTranscription(_, _, let mode):
            return "logTranscription(\(mode.rawValue))"
        case .executeCommand(let text, _):
            return "executeCommand(\(text.prefix(20))...)"
        case .flashMenuBarSuccess:
            return "flashMenuBarSuccess"
        case .flashMenuBarError:
            return "flashMenuBarError"
        case .showCorrectionWindow(let original, let output):
            return "showCorrectionWindow(orig: \(original.prefix(20))..., out: \(output.prefix(20))...)"
        case .startStreamingPreview:
            return "startStreamingPreview"
        case .stopStreamingPreview:
            return "stopStreamingPreview"
        }
    }
}
