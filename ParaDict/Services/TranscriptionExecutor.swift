import Foundation
import os

/// Actor that serializes all CoreML transcription operations.
/// Parakeet's CoreML model cannot handle concurrent calls — both streaming partial
/// transcriptions and final file-based transcriptions must go through this actor.
actor TranscriptionExecutor {
    static let shared = TranscriptionExecutor()

    private let logger = Logger(subsystem: "com.paradict", category: "TranscriptionExecutor")
    private var tail: Task<Void, Never>

    private init() {
        tail = Task {}
    }

    /// Actors are reentrant at every `await`, so actor isolation alone does not serialize
    /// CoreML work. Chain each operation behind the previous task before awaiting its result.
    private func enqueue(
        _ operation: @escaping @Sendable () async throws -> String
    ) async throws -> String {
        let predecessor = tail
        let operationTask = Task<String, Error> {
            await predecessor.value
            try Task.checkCancellation()
            return try await operation()
        }

        tail = Task {
            _ = try? await operationTask.value
        }

        return try await withTaskCancellationHandler {
            try await operationTask.value
        } onCancel: {
            operationTask.cancel()
        }
    }

#if DEBUG
    /// Allows the test target to verify queue ordering without loading transcription models.
    func executeForTesting(
        _ operation: @escaping @Sendable () async throws -> String
    ) async throws -> String {
        try await enqueue(operation)
    }
#endif

    /// Transcribe an audio file (used for final transcription after recording stops)
    func transcribe(audioURL: URL, using service: ParakeetTranscriptionService) async throws -> String {
        logger.notice("Executor: transcribing file \(audioURL.lastPathComponent)")
        return try await enqueue {
            try await service.transcribe(audioURL: audioURL)
        }
    }

    /// Transcribe final recording samples with the selected provider.
    func transcribe(audioSamples: [Float], provider: TranscriptionProvider) async throws -> String {
        logger.notice("Executor: transcribing samples with \(provider.rawValue)")
        return try await enqueue {
            switch provider {
            case .parakeet:
                return try await ParakeetTranscriptionService.shared.transcribe(
                    audioSamples: audioSamples
                )
            case .xai:
                return try await XAITranscriptionService.shared.transcribe(
                    audioSamples: audioSamples
                )
            case .elevenLabs:
                return try await ElevenLabsTranscriptionService.shared.transcribe(
                    audioSamples: audioSamples
                )
            }
        }
    }

    /// Transcribe in-memory audio samples (used for streaming preview during recording)
    func transcribe(audioSamples: [Float], using service: ParakeetTranscriptionService) async throws -> String {
        logger.notice("Executor: transcribing \(audioSamples.count) samples")
        return try await enqueue {
            try await service.transcribe(audioSamples: audioSamples)
        }
    }
}
