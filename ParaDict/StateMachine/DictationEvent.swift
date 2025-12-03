import Foundation

/// Events that can trigger state transitions in the dictation flow.
enum DictationEvent: Equatable {
    // MARK: - User Input Events

    /// User pressed the dictation hotkey
    /// - mode: The dictation mode for this shortcut
    /// - prompt: The prompt content (loaded from file)
    /// - context: Selected text context (for reply mode)
    case hotkeyDown(mode: DictationMode, prompt: String?, context: String?)

    /// User released the dictation hotkey
    /// - duration: How long the key was held (seconds)
    case hotkeyUp(duration: TimeInterval)

    /// User pressed Enter during hands-free recording (submit and continue)
    case enterPressed

    /// User pressed Escape to cancel
    case escapePressed

    // MARK: - Processing Events

    /// Recording stopped, audio file ready
    /// - url: Path to the recorded audio file
    case recordingComplete(url: URL)

    /// Transcription finished successfully
    /// - text: The transcribed text
    case transcriptionComplete(text: String)

    /// Transcription returned empty (no speech detected)
    case transcriptionEmpty

    /// LLM enhancement finished
    /// - text: The enhanced text
    case enhancementComplete(text: String)

    /// LLM not available, skip enhancement
    /// - text: The raw transcription to use instead
    case enhancementSkipped(text: String)

    /// Text has been pasted (after the paste delay)
    case pasteComplete

    // MARK: - Timer Events

    /// Enter key monitor delay completed - safe to start monitoring
    case enterMonitorReady

    // MARK: - Error Events

    /// An error occurred
    /// - message: Error description to display
    case error(message: String)

    /// Error display timeout - return to idle
    case errorTimeout
}

// MARK: - CustomStringConvertible

extension DictationEvent: CustomStringConvertible {
    var description: String {
        switch self {
        case .hotkeyDown(let mode, let prompt, let context):
            return "hotkeyDown(\(mode.rawValue), hasPrompt: \(prompt != nil), hasContext: \(context != nil))"
        case .hotkeyUp(let duration):
            return "hotkeyUp(duration: \(String(format: "%.2f", duration))s)"
        case .enterPressed:
            return "enterPressed"
        case .escapePressed:
            return "escapePressed"
        case .recordingComplete(let url):
            return "recordingComplete(\(url.lastPathComponent))"
        case .transcriptionComplete(let text):
            return "transcriptionComplete(\(text.prefix(30))...)"
        case .transcriptionEmpty:
            return "transcriptionEmpty"
        case .enhancementComplete(let text):
            return "enhancementComplete(\(text.prefix(30))...)"
        case .enhancementSkipped(let text):
            return "enhancementSkipped(\(text.prefix(30))...)"
        case .pasteComplete:
            return "pasteComplete"
        case .enterMonitorReady:
            return "enterMonitorReady"
        case .error(let message):
            return "error(\(message.prefix(30))...)"
        case .errorTimeout:
            return "errorTimeout"
        }
    }
}
