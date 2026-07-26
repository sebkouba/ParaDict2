import Foundation

/// Thread-safe gate used by the realtime microphone callback.
///
/// The audio engine stays running while capture is paused so a recording can
/// resume without reconfiguring the input device. Suppressed buffers keep their
/// original length but contain silence, preserving word boundaries across gaps.
nonisolated final class AudioCaptureGateService: @unchecked Sendable {
    private let lock = NSLock()
    private var suppressed = false

    /// Update capture suppression and return whether the state changed.
    @discardableResult
    func setSuppressed(_ newValue: Bool) -> Bool {
        lock.lock()
        let changed = suppressed != newValue
        suppressed = newValue
        lock.unlock()
        return changed
    }

    func reset() {
        _ = setSuppressed(false)
    }

    /// Append a microphone buffer atomically with respect to gate changes.
    ///
    /// Holding the gate lock through the buffer append guarantees that once
    /// `setSuppressed(true)` returns, no in-flight unsuppressed callback can
    /// append behind the retroactive silence cleanup.
    func append(
        _ samples: [Float],
        to buffer: ThreadSafeAudioBuffer,
        generation: UInt64
    ) -> (capturedSamples: [Float], didAppend: Bool) {
        lock.lock()
        let capturedSamples = suppressed
            ? Array(repeating: 0, count: samples.count)
            : samples
        let didAppend = buffer.append(capturedSamples, generation: generation)
        lock.unlock()

        return (capturedSamples, didAppend)
    }
}
