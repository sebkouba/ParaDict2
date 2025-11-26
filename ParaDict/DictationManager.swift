import Foundation
import Combine
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

    private let recorder = Recorder()
    private let transcriptionService = ParakeetTranscriptionService.shared
    private let llmClient = LLMClient.shared
    private let logger = Logger(subsystem: "com.paradict", category: "DictationManager")

    private var currentMode: DictationMode = .local
    private var currentPrompt: String?
    private var recordingURL: URL?

    private init() {
        logger.info("DictationManager initializing...")
        setupHotkeyManager()
        logger.info("DictationManager initialized")
    }

    private func setupHotkeyManager() {
        logger.info("Setting up HotkeyManager callbacks...")

        HotkeyManager.shared.onStartRecording = { [weak self] mode, prompt in
            self?.logger.info("onStartRecording callback triggered - mode: \(mode.rawValue)")
            Task { @MainActor in
                await self?.startRecording(mode: mode, prompt: prompt)
            }
        }

        HotkeyManager.shared.onStopRecording = { [weak self] in
            self?.logger.info("onStopRecording callback triggered")
            Task { @MainActor in
                await self?.stopRecording()
            }
        }

        logger.info("HotkeyManager callbacks configured")
    }

    private var hotkeyManager: HotkeyManager {
        HotkeyManager.shared
    }

    func startRecording(mode: DictationMode, prompt: String?) async {
        logger.info("startRecording called - current state: \(String(describing: self.state)), mode: \(mode.rawValue)")

        guard state == .idle else {
            logger.warning("Cannot start recording - state is not idle: \(String(describing: self.state))")
            return
        }

        currentMode = mode
        currentPrompt = prompt

        // Create temporary file for recording
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "paradict_recording_\(Date().timeIntervalSince1970).wav"
        recordingURL = tempDir.appendingPathComponent(fileName)

        guard let url = recordingURL else {
            logger.error("Failed to create recording URL")
            return
        }

        logger.info("Recording to: \(url.path)")

        do {
            try await recorder.startRecording(toOutputFile: url)
            state = .recording
            hotkeyManager.isRecording = true
            logger.info("Recording started successfully in \(mode.rawValue) mode")
        } catch {
            state = .error("Failed to start recording: \(error.localizedDescription)")
            logger.error("Failed to start recording: \(error.localizedDescription)")
        }
    }

    func stopRecording() async {
        logger.info("stopRecording called - current state: \(String(describing: self.state))")

        guard state == .recording else {
            logger.warning("Cannot stop recording - state is not recording: \(String(describing: self.state))")
            return
        }

        recorder.stopRecording()
        hotkeyManager.isRecording = false
        logger.info("Recorder stopped")

        guard let url = recordingURL else {
            logger.error("No recording URL available")
            state = .idle
            return
        }

        // Check file exists and has content
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            logger.info("Recording file size: \(size) bytes")
        }

        await processRecording(url: url)
    }

    private func processRecording(url: URL) async {
        logger.info("processRecording called - file: \(url.lastPathComponent)")
        state = .transcribing
        hotkeyManager.isProcessing = true

        defer {
            logger.info("Cleaning up recording file")
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
            hotkeyManager.isProcessing = false
            hotkeyManager.cancelRecording()
        }

        do {
            // Transcribe with Parakeet
            logger.info("Starting Parakeet transcription...")
            let transcription = try await transcriptionService.transcribe(audioURL: url)
            lastTranscription = transcription
            logger.info("Transcription complete (\(transcription.count) chars): \(transcription.prefix(100))...")

            // Check if we need LLM enhancement
            if currentMode == .enhanced, let prompt = currentPrompt ?? defaultEnhancementPrompt {
                state = .enhancing
                logger.info("Starting LLM enhancement with prompt: \(prompt.prefix(50))...")

                let enhanced = try await llmClient.enhance(text: transcription, systemPrompt: prompt)
                lastEnhancement = enhanced
                logger.info("Enhancement complete (\(enhanced.count) chars)")

                // Paste the enhanced text
                logger.info("Pasting enhanced text at cursor...")
                CursorPaster.pasteAtCursor(enhanced)
            } else {
                // Local mode - paste transcription directly
                logger.info("Pasting transcription at cursor (local mode)...")
                CursorPaster.pasteAtCursor(transcription)
            }

            logger.info("Processing complete - returning to idle state")
            state = .idle
        } catch {
            logger.error("Processing failed: \(error.localizedDescription)")
            state = .error(error.localizedDescription)

            // Reset to idle after a delay
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if case .error = self.state {
                    logger.info("Resetting from error state to idle")
                    self.state = .idle
                }
            }
        }

        currentPrompt = nil
    }

    private var defaultEnhancementPrompt: String? {
        ConfigManager.shared.config.hotkeys.first { $0.mode == .enhanced }?.prompt
    }

    func cancelRecording() {
        logger.info("cancelRecording called - current state: \(String(describing: self.state))")
        if state == .recording {
            recorder.stopRecording()
            hotkeyManager.isRecording = false
            hotkeyManager.cancelRecording()

            if let url = recordingURL {
                try? FileManager.default.removeItem(at: url)
            }
            recordingURL = nil
        }
        state = .idle
    }

    var audioMeter: AudioMeter {
        recorder.audioMeter
    }
}

// Singleton accessor for HotkeyManager
extension HotkeyManager {
    @MainActor
    static let shared = HotkeyManager()
}
