import Foundation
import os

/// Actor that serializes all CoreML transcription operations.
/// Parakeet's CoreML model cannot handle concurrent calls — both streaming partial
/// transcriptions and final file-based transcriptions must go through this actor.
actor TranscriptionExecutor {
    static let shared = TranscriptionExecutor()

    private let logger = Logger(subsystem: "com.paradict", category: "TranscriptionExecutor")

    private init() {}

    /// Transcribe an audio file (used for final transcription after recording stops)
    func transcribe(audioURL: URL, using service: ParakeetTranscriptionService) async throws -> String {
        logger.notice("Executor: transcribing file \(audioURL.lastPathComponent)")
        return try await service.transcribe(audioURL: audioURL)
    }

    /// Transcribe in-memory audio samples (used for streaming preview during recording)
    func transcribe(audioSamples: [Float], using service: ParakeetTranscriptionService) async throws -> String {
        logger.notice("Executor: transcribing \(audioSamples.count) samples")
        return try await service.transcribe(audioSamples: audioSamples)
    }
}
