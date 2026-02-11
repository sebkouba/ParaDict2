import Foundation
import Combine
import os

/// Service that periodically transcribes the growing audio buffer during recording
/// and publishes partial transcription results for the live preview overlay.
@MainActor
class StreamingTranscriptionService: ObservableObject {
    static let shared = StreamingTranscriptionService()

    private let logger = Logger(subsystem: "com.paradict", category: "StreamingTranscriptionService")
    private let transcriptionService = ParakeetTranscriptionService.shared
    private let executor = TranscriptionExecutor.shared

    /// The latest partial transcription text (observed by the preview UI)
    @Published var partialTranscription: String = ""

    /// Interval between transcription attempts
    private let transcriptionInterval: TimeInterval = 0.8

    /// Minimum number of samples before first transcription (0.5s at 16kHz)
    private let minSamples = 8000

    /// Previous full transcription for smart diff
    private var previousFullTranscription: String = ""

    /// The streaming loop task
    private var streamingTask: Task<Void, Never>?

    /// Whether the service is actively streaming
    private(set) var isStreaming = false

    private init() {}

    /// Start the streaming transcription loop
    func start(buffer: ThreadSafeAudioBuffer) {
        stop()
        previousFullTranscription = ""
        partialTranscription = ""
        isStreaming = true

        logger.notice("Starting streaming transcription")

        streamingTask = Task { [weak self] in
            guard let self = self else { return }
            await self.runStreamingLoop(buffer: buffer)
        }
    }

    /// Stop the streaming loop (keeps last partial text visible)
    func stop() {
        streamingTask?.cancel()
        streamingTask = nil
        isStreaming = false
        logger.notice("Stopped streaming transcription")
    }

    /// Clear the partial transcription text (called when indicator hides)
    func clear() {
        partialTranscription = ""
        previousFullTranscription = ""
    }

    // MARK: - Streaming Loop

    private func runStreamingLoop(buffer: ThreadSafeAudioBuffer) async {
        while !Task.isCancelled {
            // Wait for the interval
            try? await Task.sleep(nanoseconds: UInt64(transcriptionInterval * 1_000_000_000))
            guard !Task.isCancelled else { break }

            // Check minimum audio threshold
            let sampleCount = buffer.count
            guard sampleCount >= minSamples else {
                continue
            }

            // Read the full buffer
            let samples = buffer.readAll()
            guard !samples.isEmpty else { continue }

            // Transcribe through the executor (serializes with final transcription)
            do {
                let text = try await executor.transcribe(
                    audioSamples: samples,
                    using: transcriptionService
                )
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !Task.isCancelled else { break }

                if !trimmed.isEmpty {
                    let updated = smartDiffUpdate(previous: previousFullTranscription, current: trimmed)
                    partialTranscription = updated
                    previousFullTranscription = trimmed
                }
            } catch {
                // Don't log cancellation errors
                if !Task.isCancelled {
                    logger.warning("Streaming transcription failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Smart Diff

    /// Word-level longest common prefix diff to prevent text from jumping.
    /// Keeps stable prefix from previous transcription, appends new suffix from current.
    private func smartDiffUpdate(previous: String, current: String) -> String {
        guard !previous.isEmpty else { return current }

        let previousWords = previous.split(separator: " ", omittingEmptySubsequences: true)
        let currentWords = current.split(separator: " ", omittingEmptySubsequences: true)

        // Find longest matching prefix
        var matchLen = 0
        let minCount = min(previousWords.count, currentWords.count)
        for i in 0..<minCount {
            if previousWords[i].lowercased() == currentWords[i].lowercased() {
                matchLen = i + 1
            } else {
                break
            }
        }

        if matchLen == 0 {
            // No common prefix — use current as-is
            return current
        }

        // Keep stable prefix from previous, append new suffix from current
        let stablePrefix = previousWords[0..<matchLen].joined(separator: " ")
        if matchLen < currentWords.count {
            let newSuffix = currentWords[matchLen...].joined(separator: " ")
            return stablePrefix + " " + newSuffix
        }
        return stablePrefix
    }
}
