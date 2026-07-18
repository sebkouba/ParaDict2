import XCTest
@testable import ParaDict

final class TranscriptionExecutorTests: XCTestCase {
    func testOperationsExecuteStrictlyInOrder() async throws {
        let probe = SerialOperationProbe()
        let executor = TranscriptionExecutor.shared

        let first = Task {
            try await executor.executeForTesting {
                await probe.runFirst()
            }
        }
        await probe.waitUntilFirstStarts()

        let second = Task {
            try await executor.executeForTesting {
                await probe.runSecond()
            }
        }
        for _ in 0..<20 {
            await Task.yield()
        }

        let eventsWhileFirstIsBlocked = await probe.events
        XCTAssertEqual(eventsWhileFirstIsBlocked, ["first-start"])

        await probe.releaseFirst()
        let results = try await (first.value, second.value)

        XCTAssertEqual(results.0, "first")
        XCTAssertEqual(results.1, "second")
        let finalEvents = await probe.events
        XCTAssertEqual(finalEvents, ["first-start", "first-end", "second-start", "second-end"])
    }

    func testCancellingQueuedOperationPreventsItFromStarting() async throws {
        let probe = SerialOperationProbe()
        let executor = TranscriptionExecutor.shared

        let first = Task {
            try await executor.executeForTesting {
                await probe.runFirst()
            }
        }
        await probe.waitUntilFirstStarts()

        let queued = Task {
            try await executor.executeForTesting {
                await probe.runSecond()
            }
        }
        for _ in 0..<20 {
            await Task.yield()
        }
        queued.cancel()
        await probe.releaseFirst()

        let firstResult = try await first.value
        XCTAssertEqual(firstResult, "first")
        do {
            _ = try await queued.value
            XCTFail("Expected the queued operation to be cancelled")
        } catch is CancellationError {
            // Expected.
        }
        let finalEvents = await probe.events
        XCTAssertEqual(finalEvents, ["first-start", "first-end"])
    }
}

private actor SerialOperationProbe {
    private(set) var events: [String] = []
    private var firstContinuation: CheckedContinuation<Void, Never>?

    func runFirst() async -> String {
        events.append("first-start")
        await withCheckedContinuation { continuation in
            firstContinuation = continuation
        }
        events.append("first-end")
        return "first"
    }

    func runSecond() -> String {
        events.append("second-start")
        events.append("second-end")
        return "second"
    }

    func waitUntilFirstStarts() async {
        while !events.contains("first-start") {
            await Task.yield()
        }
    }

    func releaseFirst() {
        firstContinuation?.resume()
        firstContinuation = nil
    }
}
