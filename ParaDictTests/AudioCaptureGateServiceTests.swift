import XCTest
@testable import ParaDict

final class AudioCaptureGateServiceTests: XCTestCase {
    func testDisabledGateLeavesSamplesUnchanged() {
        let gate = AudioCaptureGateService()
        let buffer = ThreadSafeAudioBuffer()
        let generation = buffer.beginSession()
        let samples: [Float] = [0.1, -0.2, 0.3]

        let capture = gate.append(samples, to: buffer, generation: generation)

        XCTAssertTrue(capture.didAppend)
        XCTAssertEqual(capture.capturedSamples, samples)
        XCTAssertEqual(buffer.readAll(), samples)
    }

    func testEnabledGateProducesEqualDurationSilence() {
        let gate = AudioCaptureGateService()
        let buffer = ThreadSafeAudioBuffer()
        let generation = buffer.beginSession()
        XCTAssertTrue(gate.setSuppressed(true))

        let capture = gate.append(
            [0.1, -0.2, 0.3],
            to: buffer,
            generation: generation
        )

        XCTAssertTrue(capture.didAppend)
        XCTAssertEqual(capture.capturedSamples, [0, 0, 0])
        XCTAssertEqual(buffer.readAll(), [0, 0, 0])
        XCTAssertFalse(gate.setSuppressed(true))
    }

    func testResetReopensCapture() {
        let gate = AudioCaptureGateService()
        let buffer = ThreadSafeAudioBuffer()
        let generation = buffer.beginSession()
        gate.setSuppressed(true)
        gate.reset()

        let capture = gate.append([0.25], to: buffer, generation: generation)
        XCTAssertEqual(capture.capturedSamples, [0.25])
    }
}
