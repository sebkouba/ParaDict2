import XCTest
@testable import ParaDict

final class ThreadSafeAudioBufferTests: XCTestCase {
    func testReadAllPreservesChunkOrder() {
        let buffer = ThreadSafeAudioBuffer()
        let generation = buffer.beginSession()

        XCTAssertTrue(buffer.append([1, 2], generation: generation))
        XCTAssertTrue(buffer.append([3, 4, 5], generation: generation))

        XCTAssertEqual(buffer.count, 5)
        XCTAssertEqual(buffer.readAll(), [1, 2, 3, 4, 5])
    }

    func testReadTailSpansChunkBoundaries() {
        let buffer = ThreadSafeAudioBuffer()
        let generation = buffer.beginSession()
        buffer.append([1, 2, 3], generation: generation)
        buffer.append([4], generation: generation)
        buffer.append([5, 6], generation: generation)

        XCTAssertEqual(buffer.readTail(count: 4), [3, 4, 5, 6])
        XCTAssertEqual(buffer.readTail(count: 20), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(buffer.readTail(count: 0), [])
    }

    func testNewSessionRejectsLateCallbacksFromPreviousRecording() {
        let buffer = ThreadSafeAudioBuffer()
        let oldGeneration = buffer.beginSession()
        buffer.append([1], generation: oldGeneration)

        let newGeneration = buffer.beginSession()

        XCTAssertFalse(buffer.append([99], generation: oldGeneration))
        XCTAssertTrue(buffer.append([2], generation: newGeneration))
        XCTAssertEqual(buffer.readAll(), [2])
    }

    func testDeviceRestartPreservesSamplesAndInvalidatesOldTap() {
        let buffer = ThreadSafeAudioBuffer()
        let oldGeneration = buffer.beginSession()
        buffer.append([1, 2], generation: oldGeneration)

        let restartedGeneration = buffer.beginSession(clearExisting: false)

        XCTAssertFalse(buffer.append([99], generation: oldGeneration))
        XCTAssertTrue(buffer.append([3, 4], generation: restartedGeneration))
        XCTAssertEqual(buffer.readAll(), [1, 2, 3, 4])
    }

    func testConcurrentAppendsDoNotLoseSamples() {
        let buffer = ThreadSafeAudioBuffer()
        let generation = buffer.beginSession()

        DispatchQueue.concurrentPerform(iterations: 200) { value in
            buffer.append([Float(value)], generation: generation)
        }

        let samples = buffer.readAll()
        XCTAssertEqual(samples.count, 200)
        XCTAssertEqual(Set(samples).count, 200)
    }
}
