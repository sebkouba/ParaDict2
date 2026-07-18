import Foundation
import FluidAudio
import os

enum ParakeetTranscriptionError: LocalizedError {
    case invalidAudioData
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .invalidAudioData:
            return "Invalid audio data"
        case .emptyAudio:
            return "Audio contains no speech"
        }
    }
}

/// Owns one FluidAudio model instance and protects its model-loading state.
actor ParakeetTranscriptionService {
    static let shared = ParakeetTranscriptionService()

    /// A separate model instance keeps background file transcription from delaying live dictation.
    static let background = ParakeetTranscriptionService()

    private var asrManager: AsrManager?
    private var modelLoadTask: Task<AsrManager, Error>?
    private let logger = Logger(subsystem: "com.paradict", category: "ParakeetTranscriptionService")

    private init() {
        logger.notice("ParakeetTranscriptionService initialized")
    }

    /// Preload models at app startup so the first dictation does not pay the loading cost.
    nonisolated func preloadModels() {
        Task(priority: .utility) { [weak self] in
            do {
                try await self?.ensureModelsLoaded()
            } catch {
                self?.logger.error("Failed to preload models: \(error.localizedDescription)")
            }
        }
    }

    private func ensureModelsLoaded() async throws {
        if asrManager != nil {
            return
        }

        if let modelLoadTask {
            asrManager = try await modelLoadTask.value
            return
        }

        logger.notice("Loading Parakeet v3 models...")
        let task = Task(priority: .utility) {
            let models = try await AsrModels.downloadAndLoad(version: .v3)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            return manager
        }
        modelLoadTask = task

        do {
            asrManager = try await task.value
            modelLoadTask = nil
            logger.notice("Parakeet v3 models loaded successfully")
        } catch {
            modelLoadTask = nil
            throw error
        }
    }

    /// Let FluidAudio decode and resample the file instead of assuming a fixed 44-byte WAV header.
    func transcribe(audioURL: URL) async throws -> String {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            logger.error("Audio file does not exist: \(audioURL.path)")
            throw ParakeetTranscriptionError.invalidAudioData
        }

        try await ensureModelsLoaded()
        guard let asrManager else {
            throw ASRError.notInitialized
        }

        logger.notice("Transcribing file: \(audioURL.lastPathComponent)")
        var decoderState = TdtDecoderState.make()
        let result = try await asrManager.transcribe(audioURL, decoderState: &decoderState)
        logger.notice("ASR file result length: \(result.text.count)")
        return result.text
    }

    /// Transcribe 16 kHz mono Float32 samples captured by RecordingService.
    func transcribe(audioSamples: [Float]) async throws -> String {
        guard !audioSamples.isEmpty else {
            throw ParakeetTranscriptionError.emptyAudio
        }

        try await ensureModelsLoaded()
        guard let asrManager else {
            throw ASRError.notInitialized
        }

        let durationSeconds = Double(audioSamples.count) / 16_000
        logger.notice(
            "Transcribing \(audioSamples.count) samples (\(durationSeconds, format: .fixed(precision: 1))s)"
        )
        var decoderState = TdtDecoderState.make()
        let result = try await asrManager.transcribe(audioSamples, decoderState: &decoderState)
        logger.notice("ASR sample result length: \(result.text.count)")
        return result.text
    }

    func cleanup() async {
        logger.notice("Cleaning up ASR resources")
        modelLoadTask?.cancel()
        modelLoadTask = nil
        await asrManager?.cleanup()
        asrManager = nil
    }
}
