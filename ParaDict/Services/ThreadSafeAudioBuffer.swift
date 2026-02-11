import Foundation

/// Thread-safe audio sample buffer for sharing between the AVAudioEngine tap (realtime thread)
/// and the streaming transcription service (main actor).
/// Uses NSLock since the audio tap callback runs on a realtime thread where actors/await are not safe.
final class ThreadSafeAudioBuffer: @unchecked Sendable {
    private var buffer: [Float] = []
    private let lock = NSLock()

    /// Append samples from the audio tap callback (called on realtime audio thread)
    func append(_ samples: [Float]) {
        lock.lock()
        buffer.append(contentsOf: samples)
        lock.unlock()
    }

    /// Read all accumulated samples (called from streaming transcription loop)
    func readAll() -> [Float] {
        lock.lock()
        let copy = buffer
        lock.unlock()
        return copy
    }

    /// Number of accumulated samples
    var count: Int {
        lock.lock()
        let c = buffer.count
        lock.unlock()
        return c
    }

    /// Clear the buffer (called when recording stops or indicator hides)
    func clear() {
        lock.lock()
        buffer.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}
