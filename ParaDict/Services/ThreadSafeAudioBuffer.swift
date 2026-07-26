import Foundation

/// Thread-safe audio storage shared by the Core Audio tap and transcription tasks.
/// Samples are retained as immutable chunks so snapshots do not copy the entire recording
/// while holding the realtime tap's lock.
nonisolated final class ThreadSafeAudioBuffer: @unchecked Sendable {
    private var chunks: [[Float]] = []
    private var sampleCount = 0
    private var generation: UInt64 = 0
    private let lock = NSLock()

    /// Start a new capture generation. Old tap callbacks cannot append into the new recording.
    @discardableResult
    func beginSession(clearExisting: Bool = true) -> UInt64 {
        lock.lock()
        generation &+= 1
        if clearExisting {
            chunks.removeAll(keepingCapacity: true)
            sampleCount = 0
        }
        let currentGeneration = generation
        lock.unlock()
        return currentGeneration
    }

    /// Append samples only if they belong to the active recording generation.
    @discardableResult
    func append(_ samples: [Float], generation expectedGeneration: UInt64) -> Bool {
        guard !samples.isEmpty else { return true }

        lock.lock()
        guard generation == expectedGeneration else {
            lock.unlock()
            return false
        }
        chunks.append(samples)
        sampleCount += samples.count
        lock.unlock()
        return true
    }

    /// Append to the active generation. Used for converter tail flushes and tests.
    func append(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        lock.lock()
        chunks.append(samples)
        sampleCount += samples.count
        lock.unlock()
    }

    /// Snapshot chunk references under the lock, then flatten after releasing it.
    func readAll() -> [Float] {
        lock.lock()
        let snapshot = chunks
        let count = sampleCount
        lock.unlock()

        var result: [Float] = []
        result.reserveCapacity(count)
        for chunk in snapshot {
            result.append(contentsOf: chunk)
        }
        return result
    }

    /// Read the last N samples without copying the entire accumulated recording.
    func readTail(count requestedCount: Int) -> [Float] {
        guard requestedCount > 0 else { return [] }

        lock.lock()
        let snapshot = chunks
        let availableCount = sampleCount
        lock.unlock()

        let resultCount = min(requestedCount, availableCount)
        guard resultCount > 0 else { return [] }

        var reversedPieces: [[Float]] = []
        reversedPieces.reserveCapacity(snapshot.count)
        var remaining = resultCount

        for chunk in snapshot.reversed() where remaining > 0 {
            let takeCount = min(remaining, chunk.count)
            reversedPieces.append(Array(chunk.suffix(takeCount)))
            remaining -= takeCount
        }

        var result: [Float] = []
        result.reserveCapacity(resultCount)
        for piece in reversedPieces.reversed() {
            result.append(contentsOf: piece)
        }
        return result
    }

    /// Replace recent samples with silence without changing the recording duration.
    ///
    /// Used when playback detection arrives shortly after audible output starts,
    /// removing the small amount that may already have reached the microphone.
    @discardableResult
    func silenceTail(count requestedCount: Int) -> Int {
        guard requestedCount > 0 else { return 0 }

        lock.lock()
        var remaining = min(requestedCount, sampleCount)
        let silencedCount = remaining

        for index in chunks.indices.reversed() where remaining > 0 {
            let countToSilence = min(remaining, chunks[index].count)
            let startIndex = chunks[index].count - countToSilence
            chunks[index].replaceSubrange(
                startIndex..<chunks[index].count,
                with: repeatElement(Float.zero, count: countToSilence)
            )
            remaining -= countToSilence
        }

        lock.unlock()
        return silencedCount
    }

    var count: Int {
        lock.lock()
        let count = sampleCount
        lock.unlock()
        return count
    }

    /// Clear all samples and invalidate callbacks from the previous capture generation.
    func clear() {
        _ = beginSession(clearExisting: true)
    }
}
