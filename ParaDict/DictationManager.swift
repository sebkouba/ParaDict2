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

    private let recorder = Recorder()
    private let transcriptionService = ParakeetTranscriptionService.shared
    private let llmClient = LLMClient.shared
    private let logger = Logger(subsystem: "com.paradict", category: "DictationManager")

    private var currentMode: DictationMode = .local
    private var currentPrompt: String?
    private var recordingURL: URL?

    private init() {
        logger.notice("DictationManager initializing...")
        setupHotkeyManager()
        logger.notice("DictationManager initialized")
    }

    private func setupHotkeyManager() {
        logger.notice("Setting up HotkeyManager callbacks...")

        HotkeyManager.shared.onStartRecording = { [weak self] mode, prompt in
            self?.logger.notice("onStartRecording callback triggered - mode: \(mode.rawValue)")
            Task { @MainActor in
                await self?.startRecording(mode: mode, prompt: prompt)
            }
        }

        HotkeyManager.shared.onStopRecording = { [weak self] in
            self?.logger.notice("onStopRecording callback triggered")
            Task { @MainActor in
                await self?.stopRecording()
            }
        }

        logger.notice("HotkeyManager callbacks configured")
    }

    private var hotkeyManager: HotkeyManager {
        HotkeyManager.shared
    }

    func startRecording(mode: DictationMode, prompt: String?) async {
        logger.notice("startRecording called - current state: \(String(describing: self.state)), mode: \(mode.rawValue)")

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
            try await recorder.startRecording(toOutputFile: url)
            state = .recording
            hotkeyManager.isRecording = true
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

        recorder.stopRecording()
        hotkeyManager.isRecording = false
        logger.notice("Recorder stopped")

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
            hotkeyManager.cancelRecording()
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
                state = .error("No speech detected. Please check microphone permission and try speaking louder.")
                Task {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    if case .error = self.state {
                        self.state = .idle
                    }
                }
                return
            }

            // Check accessibility permission before attempting to paste
            let canPaste = AXIsProcessTrusted()
            if !canPaste {
                logger.warning("Accessibility permission not granted - copying to clipboard only")
            }

            // Check if we need LLM enhancement
            if currentMode == .enhanced, let prompt = currentPrompt ?? defaultEnhancementPrompt {
                state = .enhancing
                logger.notice("Starting LLM enhancement with prompt: \(prompt.prefix(50))...")

                let enhanced = try await llmClient.enhance(text: transcription, systemPrompt: prompt)
                lastEnhancement = enhanced
                logger.notice("Enhancement complete (\(enhanced.count) chars)")

                // Paste the enhanced text
                if canPaste {
                    logger.notice("Pasting enhanced text at cursor...")
                    CursorPaster.pasteAtCursor(enhanced)
                } else {
                    // Fall back to just copying to clipboard
                    logger.notice("Copying enhanced text to clipboard (no accessibility)...")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(enhanced, forType: .string)
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
                    CursorPaster.pasteAtCursor(transcription)
                } else {
                    // Fall back to just copying to clipboard
                    logger.notice("Copying transcription to clipboard (no accessibility)...")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(transcription, forType: .string)
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

            logger.notice("Processing complete - returning to idle state")
            state = .idle
        } catch {
            logger.error("Processing failed: \(error.localizedDescription)")
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
    }

    private var defaultEnhancementPrompt: String? {
        ConfigManager.shared.enhancedDictationPrompt
    }

    func cancelRecording() {
        logger.notice("cancelRecording called - current state: \(String(describing: self.state))")
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
