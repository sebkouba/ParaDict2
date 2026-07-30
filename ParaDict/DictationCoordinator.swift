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
    @Published private(set) var state: DictationState = .idle

    /// Last transcription for UI (Copy Last Transcription menu item)
    @Published var lastTranscription: String?

    /// Last LLM enhancement for UI (Copy Last Enhancement menu item)
    @Published var lastEnhancement: String?

    // MARK: - Services

    let recordingService = RecordingService()
    private let transcriptionService = ParakeetTranscriptionService.shared
    private let transcriptionExecutor = TranscriptionExecutor.shared
    private let streamingService = StreamingTranscriptionService.shared
    private let llmClient = LLMClient.shared
    private let indicatorManager = RecordingIndicatorWindowManager.shared
    private let previewManager = TranscriptionPreviewWindowManager.shared
    private let historyService = DictationHistoryService.shared
    private let recordingArchiveService = RecordingArchiveService.shared
    private let correctionWindowManager = CorrectionWindowManager.shared

    // MARK: - State

    private var currentContext: String?  // For reply mode
    private var errorTimeoutTask: Task<Void, Never>?
    private var pasteCompleteTask: Task<Void, Never>?
    private var enterMonitorStartTask: Task<Void, Never>?
    private var commandMonitorStartTask: Task<Void, Never>?
    private var recordingStartTask: Task<Void, Never>?
    private var recordingPipelineTask: Task<Void, Never>?
    private var enhancementTask: Task<Void, Never>?
    private var commandExecutionTask: Task<Void, Never>?
    private var currentRecordingStartedAt: Date?
    private var currentRecordingSamples: [Float]?
    private var currentRecordingMode: DictationMode?
    private var currentRecordingProvider: TranscriptionProvider?
    private var didArchiveCurrentRecording = false

    /// Tracks the last raw transcription from Parakeet (for correction feature)
    private var lastRawTranscription: String?
    /// Tracks the last text that was actually pasted - may be LLM-enhanced (for correction feature)
    private var lastPastedText: String?

    // MARK: - Playback Pausing Mode

    /// When enabled, media is paused during dictation and resumed after (persisted)
    @Published private(set) var isPlaybackPausingEnabled: Bool {
        didSet { AppSettings.shared.pauseMediaDuringDictation = isPlaybackPausingEnabled }
    }
    /// Tracks if we actually paused media this session (to know whether to resume)
    private var didPauseMedia = false

    // MARK: - Playback Microphone Pausing

    /// When enabled, microphone capture is replaced with silence while media plays.
    @Published private(set) var isMicrophonePausingForPlaybackEnabled: Bool {
        didSet {
            AppSettings.shared.pauseMicrophoneDuringPlayback =
                isMicrophonePausingForPlaybackEnabled
        }
    }

    // MARK: - Text Formatting Options (persisted)

    /// When enabled, trailing punctuation (. ? !) is removed before pasting
    @Published private(set) var isTrailingPunctuationRemovalEnabled: Bool {
        didSet { UserDefaults.standard.set(isTrailingPunctuationRemovalEnabled, forKey: SettingsKeys.trailingPunctuationRemoval) }
    }
    /// When enabled, a trailing space is added before pasting (ignored if line break is enabled)
    @Published private(set) var isTrailingSpaceEnabled: Bool {
        didSet { UserDefaults.standard.set(isTrailingSpaceEnabled, forKey: SettingsKeys.trailingSpace) }
    }
    /// When enabled, a trailing line break is added before pasting
    @Published private(set) var isTrailingLineBreakEnabled: Bool {
        didSet { UserDefaults.standard.set(isTrailingLineBreakEnabled, forKey: SettingsKeys.trailingLineBreak) }
    }
    /// When enabled, press Enter after pasting to submit chat-style inputs
    @Published private(set) var isTrailingEnterEnabled: Bool {
        didSet { UserDefaults.standard.set(isTrailingEnterEnabled, forKey: SettingsKeys.trailingEnter) }
    }

    // MARK: - Initialization

    private init() {
        // Load persisted settings
        isPlaybackPausingEnabled = AppSettings.shared.pauseMediaDuringDictation
        isMicrophonePausingForPlaybackEnabled =
            AppSettings.shared.pauseMicrophoneDuringPlayback
        isTrailingPunctuationRemovalEnabled = UserDefaults.standard.object(forKey: SettingsKeys.trailingPunctuationRemoval) as? Bool ?? SettingsDefaults.trailingPunctuationRemoval
        isTrailingSpaceEnabled = UserDefaults.standard.object(forKey: SettingsKeys.trailingSpace) as? Bool ?? SettingsDefaults.trailingSpace
        isTrailingLineBreakEnabled = UserDefaults.standard.object(forKey: SettingsKeys.trailingLineBreak) as? Bool ?? SettingsDefaults.trailingLineBreak
        isTrailingEnterEnabled = UserDefaults.standard.object(forKey: SettingsKeys.trailingEnter) as? Bool ?? SettingsDefaults.trailingEnter

        logger.notice("DictationCoordinator initializing...")
        // Initialize HotkeyManager to set up keyboard shortcuts
        _ = HotkeyManager.shared
        logger.notice("DictationCoordinator initialized")
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
            didPauseMedia = false
            let provider = AppSettings.shared.transcriptionProvider
            recordingStartTask?.cancel()
            recordingStartTask = Task { [weak self] in
                await self?.startRecording(
                    mode: mode,
                    prompt: prompt,
                    context: context,
                    provider: provider
                )
            }

        case .stopRecording:
            stopRecording()

        case .cancelRecording:
            cancelRecording()

        case .cancelProcessing:
            cancelProcessing()

        case .enhance(let text, let prompt, let context):
            enhancementTask?.cancel()
            enhancementTask = Task { [weak self] in
                await self?.enhance(text: text, prompt: prompt, context: context)
            }

        case .paste(let text):
            paste(text)

        case .pressEnterKey:
            PastingService.pressEnter()

        case .showIndicator:
            indicatorManager.show()

        case .hideIndicator:
            indicatorManager.hide()
            previewManager.hide()
            streamingService.stop()
            streamingService.clear()

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

        case .startCommandMonitor:
            HotkeyManager.shared.startCommandKeyMonitor()

        case .stopCommandMonitor:
            HotkeyManager.shared.stopCommandKeyMonitor()

        case .scheduleEnterMonitorStart:
            scheduleEnterMonitorStart()

        case .scheduleCommandMonitorStart:
            scheduleCommandMonitorStart()

        case .scheduleErrorTimeout:
            scheduleErrorTimeout()

        case .schedulePasteComplete:
            schedulePasteComplete()

        case .logTranscription(let transcription, let enhanced, let mode):
            logTranscription(transcription: transcription, enhanced: enhanced, mode: mode)

        case .executeCommand(let text, let prompt):
            commandExecutionTask?.cancel()
            commandExecutionTask = Task { [weak self] in
                await self?.executeCommand(text: text, prompt: prompt)
            }

        case .flashMenuBarSuccess:
            flashMenuBar(success: true)

        case .flashMenuBarError:
            flashMenuBar(success: false)

        case .showCorrectionWindow(let originalTranscription, let llmOutput):
            logger.notice("Showing correction window - raw: \(originalTranscription.prefix(30))..., pasted: \(llmOutput.prefix(30))...")
            correctionWindowManager.show(originalTranscription: originalTranscription, llmOutput: llmOutput)

        case .startStreamingPreview:
            guard AppSettings.shared.streamingPreviewEnabled else { break }
            guard AppSettings.shared.transcriptionProvider == .parakeet else { break }
            streamingService.start(buffer: recordingService.audioBuffer)
            previewManager.show()

        case .stopStreamingPreview:
            streamingService.stop()
            // Keep preview panel visible with last text — it hides when indicator hides
        }
    }

    // MARK: - Recording

    private func startRecording(
        mode: DictationMode,
        prompt: String?,
        context: String?,
        provider: TranscriptionProvider
    ) async {
        guard !Task.isCancelled else { return }

        // Store context for later use
        currentContext = context
        currentRecordingStartedAt = Date()
        currentRecordingSamples = nil
        currentRecordingMode = mode
        currentRecordingProvider = provider
        didArchiveCurrentRecording = false

        logger.notice("Starting recording (buffer-only)")

        do {
            try await recordingService.startRecording()
            guard !Task.isCancelled else {
                recordingService.stopRecording()
                clearCurrentRecordingArchiveState()
                return
            }
            logger.notice("Recording started successfully")

            // Pause media AFTER successful audio setup to avoid pausing for sessions that fail to start.
            // Playback that was already active belongs to this pause operation, not to
            // the "playback began during dictation" microphone suppression path.
            var pausedInitialPlayback = false
            if isPlaybackPausingEnabled {
                pausedInitialPlayback =
                    await MediaPlaybackService.shared.pauseIfPlaying()

                guard !Task.isCancelled, recordingService.isRecording else {
                    MediaPlaybackService.shared.resumeIfWePaused(
                        pausedInitialPlayback
                    )
                    recordingService.stopRecording()
                    clearCurrentRecordingArchiveState()
                    return
                }

                didPauseMedia = pausedInitialPlayback
                logger.notice(
                    "Playback pausing: didPauseMedia=\(pausedInitialPlayback)"
                )
            }

            if isMicrophonePausingForPlaybackEnabled {
                recordingService.startPlaybackCaptureSuppression(
                    ignoreCurrentPlaybackUntilStopped: pausedInitialPlayback
                )
            }
        } catch {
            resumeMediaIfNeeded()
            logger.error("Failed to start recording: \(error.localizedDescription)")
            send(.error(message: "Failed to start recording: \(error.localizedDescription)"))
        }
    }

    private func stopRecording() {
        recordingPipelineTask?.cancel()
        guard let provider = currentRecordingProvider else {
            recordingPipelineTask = Task { [weak self] in
                guard let self else { return }
                _ = await recordingService.finalizeRecording()
                resumeMediaIfNeeded()
                send(.error(message: "Recording session lost its transcription provider"))
            }
            return
        }
        recordingPipelineTask = Task { [weak self] in
            guard let self else { return }
            let samples = await recordingService.finalizeRecording()
            resumeMediaIfNeeded()
            logger.notice("Recording stopped")

            guard !Task.isCancelled else {
                clearCurrentRecordingArchiveState()
                return
            }

            if samples.isEmpty {
                clearCurrentRecordingArchiveState()
                send(.transcriptionEmpty)
            } else {
                currentRecordingSamples = samples
                await transcribe(audioSamples: samples, provider: provider)
            }
        }
    }

    private func cancelRecording() {
        recordingStartTask?.cancel()
        recordingService.stopRecording()
        resumeMediaIfNeeded()
        currentContext = nil
        clearCurrentRecordingArchiveState()

        logger.notice("Recording cancelled")
    }

    private func cancelProcessing() {
        recordingPipelineTask?.cancel()
        enhancementTask?.cancel()
        commandExecutionTask?.cancel()
        clearCurrentRecordingArchiveState()
        logger.notice("Processing cancelled")
    }

    // MARK: - Transcription

    private func transcribe(audioSamples: [Float], provider: TranscriptionProvider) async {
        do {
            // Route through TranscriptionExecutor to serialize with streaming transcription
            let text = try await transcriptionExecutor.transcribe(
                audioSamples: audioSamples,
                provider: provider
            )
            guard !Task.isCancelled else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                send(.transcriptionEmpty)
            } else if isCorrectionKeyword(trimmed) {
                // Check for correction keyword
                await archiveCurrentRecording(rawTranscription: trimmed, enhancedText: nil)
                guard !Task.isCancelled else { return }
                logger.notice("Correction keyword detected")
                if let rawTranscription = lastRawTranscription, let pastedText = lastPastedText {
                    send(.correctionKeywordDetected(originalTranscription: rawTranscription, llmOutput: pastedText))
                } else {
                    logger.warning("No previous dictation to correct")
                    send(.error(message: "No previous dictation to correct"))
                }
            } else if isPlaybackPausingCommand(trimmed) {
                // Check for playback pausing voice command
                await archiveCurrentRecording(rawTranscription: trimmed, enhancedText: nil)
                guard !Task.isCancelled else { return }
                togglePlaybackPausing()
                send(.transcriptionEmpty)  // Don't paste anything, just toggle setting
            } else if isMicrophonePausingForPlaybackCommand(trimmed) {
                await archiveCurrentRecording(rawTranscription: trimmed, enhancedText: nil)
                guard !Task.isCancelled else { return }
                toggleMicrophonePausingForPlayback()
                send(.transcriptionEmpty)
            } else if let formattingCommand = parseTextFormattingCommand(trimmed) {
                // Check for text formatting command
                await archiveCurrentRecording(rawTranscription: trimmed, enhancedText: nil)
                guard !Task.isCancelled else { return }
                handleTextFormattingCommand(formattingCommand)
                send(.transcriptionEmpty)  // Don't paste anything, just toggle setting
            } else if isDailyNoteCommand(trimmed) {
                // Check for "daily" keyword to open Obsidian daily note
                await archiveCurrentRecording(rawTranscription: trimmed, enhancedText: nil)
                guard !Task.isCancelled else { return }
                handleDailyNoteCommand()
                send(.transcriptionEmpty)  // Don't paste anything
            } else {
                // Store raw transcription for correction feature and UI
                lastRawTranscription = trimmed
                lastTranscription = trimmed
                if currentRecordingMode == .local || currentRecordingMode == .command {
                    await archiveCurrentRecording(rawTranscription: trimmed, enhancedText: nil)
                    guard !Task.isCancelled else { return }
                }
                send(.transcriptionComplete(text: trimmed))
            }
        } catch is CancellationError {
            logger.notice("Transcription cancelled")
        } catch {
            guard !Task.isCancelled else { return }
            send(.error(message: "Transcription failed: \(error.localizedDescription)"))
        }
    }

    // MARK: - Media Playback Resume

    private func resumeMediaIfNeeded() {
        // Following cm rule b-mlrn5o09: use explicit play() command — never toggle
        MediaPlaybackService.shared.resumeIfWePaused(didPauseMedia)
        didPauseMedia = false
    }

    /// Check if the transcription is a playback pausing toggle command
    private func isPlaybackPausingCommand(_ text: String) -> Bool {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")

        let patterns = [
            "pause playback", "playback pausing",
            "pause media", "media pausing",
            "toggle playback pausing", "toggle media pausing"
        ]
        return patterns.contains(normalized)
    }

    /// Check for the menu-visible microphone pausing toggle phrase.
    private func isMicrophonePausingForPlaybackCommand(_ text: String) -> Bool {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")

        let patterns = [
            "pause mic for playback",
            "pause microphone for playback",
            "toggle pause mic for playback",
            "toggle microphone pausing for playback"
        ]
        return patterns.contains(normalized)
    }

    /// Check if the transcription is just the correction keyword
    private func isCorrectionKeyword(_ text: String) -> Bool {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Match "correction", "correct", or common variations with punctuation
        let correctionPatterns = ["correction", "correction.", "correct", "correct."]
        return correctionPatterns.contains(normalized)
    }

    // MARK: - Voice Command Keywords

    private enum TextFormattingCommand {
        case removeTrailingPunctuation(Bool?)  // nil = toggle
        case addTrailingSpace(Bool?)           // nil = toggle
        case addTrailingLineBreak(Bool?)       // nil = toggle
    }

    /// Check if the transcription is a text formatting command
    private func parseTextFormattingCommand(_ text: String) -> TextFormattingCommand? {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")

        logger.notice("Checking for text formatting command - normalized: '\(normalized)'")

        // Remove Trailing Punctuation
        if normalized == "remove trailing punctuation" {
            return .removeTrailingPunctuation(nil)  // toggle
        }
        if ["remove trailing punctuation on", "enable remove trailing punctuation"].contains(normalized) {
            return .removeTrailingPunctuation(true)
        }
        if ["remove trailing punctuation off", "disable remove trailing punctuation"].contains(normalized) {
            return .removeTrailingPunctuation(false)
        }

        // Add Trailing Space
        if normalized == "add trailing space" {
            return .addTrailingSpace(nil)  // toggle
        }
        if ["add trailing space on", "enable add trailing space", "enable trailing space"].contains(normalized) {
            return .addTrailingSpace(true)
        }
        if ["add trailing space off", "disable add trailing space", "disable trailing space"].contains(normalized) {
            return .addTrailingSpace(false)
        }

        // Add Trailing Line Break
        if normalized == "add trailing line break" {
            return .addTrailingLineBreak(nil)  // toggle
        }
        if ["add trailing line break on", "enable add trailing line break", "enable trailing line break"].contains(normalized) {
            return .addTrailingLineBreak(true)
        }
        if ["add trailing line break off", "disable add trailing line break", "disable trailing line break"].contains(normalized) {
            return .addTrailingLineBreak(false)
        }

        return nil
    }

    /// Handle text formatting command
    private func handleTextFormattingCommand(_ command: TextFormattingCommand) {
        switch command {
        case .removeTrailingPunctuation(let enabled):
            if let enabled = enabled {
                isTrailingPunctuationRemovalEnabled = enabled
            } else {
                isTrailingPunctuationRemovalEnabled.toggle()
            }
            logger.notice("Remove trailing punctuation: \(self.isTrailingPunctuationRemovalEnabled ? "ON" : "OFF")")

        case .addTrailingSpace(let enabled):
            if let enabled = enabled {
                isTrailingSpaceEnabled = enabled
            } else {
                isTrailingSpaceEnabled.toggle()
            }
            logger.notice("Add trailing space: \(self.isTrailingSpaceEnabled ? "ON" : "OFF")")

        case .addTrailingLineBreak(let enabled):
            if let enabled = enabled {
                isTrailingLineBreakEnabled = enabled
            } else {
                isTrailingLineBreakEnabled.toggle()
            }
            logger.notice("Add trailing line break: \(self.isTrailingLineBreakEnabled ? "ON" : "OFF")")
        }

        // Play feedback sound
        NSSound.beep()
    }

    // MARK: - Obsidian Daily Note

    /// Check if the transcription is the "daily" keyword
    private func isDailyNoteCommand(_ text: String) -> Bool {
        // Only check if the feature is enabled
        guard AppSettings.shared.obsidianDailyNoteEnabled else { return false }

        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")

        // Match "daily", "daily note", "open daily note"
        let patterns = ["daily", "daily note", "open daily note", "open daily"]
        return patterns.contains(normalized)
    }

    /// Open Obsidian daily note
    private func handleDailyNoteCommand() {
        // Build the URI
        var urlString = "obsidian://daily"
        if let vault = AppSettings.shared.obsidianVault, !vault.isEmpty {
            // URL-encode the vault name
            if let encodedVault = vault.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                urlString += "?vault=\(encodedVault)"
            }
        }

        logger.notice("Opening Obsidian daily note: \(urlString)")

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        } else {
            logger.error("Failed to create Obsidian URL: \(urlString)")
        }

        // Play feedback sound
        NSSound.beep()
    }

    // MARK: - Enhancement

    private func enhance(text: String, prompt: String, context: String?) async {
        guard !Task.isCancelled else { return }

        guard llmClient.isConfigured else {
            logger.warning("LLM not configured - skipping enhancement")
            await archiveCurrentRecording(rawTranscription: text, enhancedText: nil)
            guard !Task.isCancelled else { return }
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
            guard !Task.isCancelled else { return }

            // Store for UI and log
            lastEnhancement = enhanced
            await archiveCurrentRecording(rawTranscription: text, enhancedText: enhanced)
            guard !Task.isCancelled else { return }
            logTranscription(transcription: text, enhanced: enhanced, mode: stateMachine.state.mode ?? .enhanced)

            send(.enhancementComplete(text: enhanced))
        } catch let error as LLMError {
            switch error {
            case .timeout(let originalText):
                guard !Task.isCancelled else { return }
                // Timeout: fall back to original transcription and show red flash
                logger.warning("⚠️ ENHANCEMENT TIMEOUT - LLM took too long, falling back to original transcription")
                indicatorManager.showTimeoutFlash()
                await archiveCurrentRecording(rawTranscription: originalText, enhancedText: nil)
                guard !Task.isCancelled else { return }
                send(.enhancementSkipped(text: originalText))
            default:
                guard !Task.isCancelled else { return }
                logger.error("Enhancement failed: \(error.localizedDescription)")
                // Fall back to raw text on error
                await archiveCurrentRecording(rawTranscription: text, enhancedText: nil)
                guard !Task.isCancelled else { return }
                send(.enhancementSkipped(text: text))
            }
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("Enhancement failed: \(error.localizedDescription)")
            // Fall back to raw text on error
            await archiveCurrentRecording(rawTranscription: text, enhancedText: nil)
            guard !Task.isCancelled else { return }
            send(.enhancementSkipped(text: text))
        }
    }

    private func archiveCurrentRecording(rawTranscription: String?, enhancedText: String?) async {
        guard !didArchiveCurrentRecording,
              let samples = currentRecordingSamples,
              let recordedAt = currentRecordingStartedAt,
              let mode = currentRecordingMode,
              let provider = currentRecordingProvider else {
            return
        }

        didArchiveCurrentRecording = true
        let targetApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        await recordingArchiveService.archive(
            audioSamples: samples,
            recordedAt: recordedAt,
            mode: mode,
            transcriptionProvider: provider,
            rawTranscription: rawTranscription,
            enhancedText: enhancedText,
            targetApp: targetApp
        )
        clearCurrentRecordingArchiveState()
    }

    private func clearCurrentRecordingArchiveState() {
        currentRecordingStartedAt = nil
        currentRecordingSamples = nil
        currentRecordingMode = nil
        currentRecordingProvider = nil
        didArchiveCurrentRecording = false
    }

    // MARK: - Pasting

    private func paste(_ text: String) {
        let processed = applyTextFormatting(text)
        // Track pasted text for correction feature
        lastPastedText = processed
        PastingService.pasteAtCursor(processed, pressEnterAfterPaste: isTrailingEnterEnabled)
    }

    /// Apply text formatting options (trailing punctuation removal, space/line break)
    private func applyTextFormatting(_ text: String) -> String {
        var result = text

        // 1. Remove trailing punctuation if enabled
        if isTrailingPunctuationRemovalEnabled {
            // Remove trailing . ? ! (handles multiple, e.g., "..." becomes "")
            while let last = result.last, ".?!".contains(last) {
                result.removeLast()
            }
        }

        // 2. Add trailing space or line break (line break wins)
        if isTrailingLineBreakEnabled {
            result.append("\n")
        } else if isTrailingSpaceEnabled {
            result.append(" ")
        }

        return result
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

    private func scheduleCommandMonitorStart() {
        commandMonitorStartTask?.cancel()
        commandMonitorStartTask = Task {
            // Wait for Command key-up from the shortcut to be fully processed
            // 300ms is enough for the modifier key release to propagate
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !Task.isCancelled {
                send(.commandMonitorReady)
            }
        }
    }

    // MARK: - Logging

    private func logTranscription(transcription: String, enhanced: String?, mode: DictationMode) {
        let targetApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let retentionLimit = AppSettings.shared.dictationHistoryRetentionLimit

        Task {
            do {
                try await historyService.save(
                    transcription: transcription,
                    enhancedText: enhanced,
                    mode: mode,
                    targetApp: targetApp,
                    retentionLimit: retentionLimit
                )
            } catch {
                logger.error(
                    "Failed to save dictation history: \(error.localizedDescription)"
                )
            }
        }
    }

    // MARK: - Command Execution

    private func executeCommand(text: String, prompt: String) async {
        guard !Task.isCancelled else { return }
        let executor = CommandExecutorService.shared

        do {
            if let output = try executor.executeDirectCommandIfPossible(text) {
                guard !Task.isCancelled else { return }
                logger.notice("Command resolved locally without LLM: \(output)")
                send(.commandComplete)
                return
            }
        } catch {
            logger.error("Direct command execution failed: \(error.localizedDescription)")
            send(.commandFailed(message: error.localizedDescription))
            return
        }

        let tools = executor.getToolDefinitions()

        guard !tools.isEmpty else {
            send(.commandFailed(message: "No tools configured. Check tools.json"))
            return
        }

        // Inject dynamic context (e.g., VS Code recent projects) into the prompt
        let projectList = executor.getProjectListForPrompt()
        let enrichedPrompt = prompt + projectList

        let messages = [
            ChatMessage(role: "system", content: enrichedPrompt),
            ChatMessage(role: "user", content: text)
        ]

        do {
            let result = try await llmClient.chatWithTools(messages: messages, tools: tools)
            guard !Task.isCancelled else { return }

            switch result {
            case .content(let response):
                // LLM responded with text instead of tool call
                logger.notice("LLM returned text (no tool call): \(response.prefix(50))...")
                send(.commandFailed(message: "Command not recognized: \(text)"))

            case .toolCalls(let toolCalls):
                // Execute each tool call
                for toolCall in toolCalls {
                    let output = try await executor.execute(toolCall: toolCall)
                    guard !Task.isCancelled else { return }
                    logger.notice("Tool executed: \(toolCall.function.name) -> \(output)")
                }
                send(.commandComplete)
            }
        } catch {
            guard !Task.isCancelled else { return }
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
    var currentState: DictationState {
        stateMachine.state
    }

    func togglePlaybackPausing() {
        isPlaybackPausingEnabled.toggle()
        logger.notice("Playback pausing toggled: \(self.isPlaybackPausingEnabled)")
    }

    func setMicrophonePausingForPlaybackEnabled(_ isEnabled: Bool) {
        guard isMicrophonePausingForPlaybackEnabled != isEnabled else { return }

        isMicrophonePausingForPlaybackEnabled = isEnabled
        recordingService.setPlaybackCaptureSuppressionEnabled(isEnabled)
        logger.notice("Microphone pausing for playback set to: \(isEnabled)")
    }

    func toggleMicrophonePausingForPlayback() {
        setMicrophonePausingForPlaybackEnabled(!isMicrophonePausingForPlaybackEnabled)
    }

    func toggleTrailingPunctuationRemoval() {
        isTrailingPunctuationRemovalEnabled.toggle()
        logger.notice("Trailing punctuation removal toggled: \(self.isTrailingPunctuationRemovalEnabled)")
    }

    func toggleTrailingSpace() {
        isTrailingSpaceEnabled.toggle()
        logger.notice("Trailing space toggled: \(self.isTrailingSpaceEnabled)")
    }

    func toggleTrailingLineBreak() {
        isTrailingLineBreakEnabled.toggle()
        logger.notice("Trailing line break toggled: \(self.isTrailingLineBreakEnabled)")
    }

    func toggleTrailingEnter() {
        isTrailingEnterEnabled.toggle()
        logger.notice("Trailing enter toggled: \(self.isTrailingEnterEnabled)")
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
