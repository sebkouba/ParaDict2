import XCTest
@testable import ParaDict

@MainActor
final class MediaPlaybackServiceTests: XCTestCase {
    func testPauseWaitsUntilPlaybackActuallyReportsStopped() async {
        let commandClient = StubMediaPlaybackCommandClient(
            playbackStates: [true, true, false]
        )
        let service = MediaPlaybackService(
            commandClient: commandClient,
            pauseConfirmationPollNanoseconds: 0,
            pauseConfirmationAttempts: 3
        )

        let didPause = await service.pauseIfPlaying()

        XCTAssertTrue(didPause)
        XCTAssertEqual(commandClient.pauseCallCount, 1)
        XCTAssertEqual(commandClient.playbackStateQueryCount, 3)
        XCTAssertEqual(commandClient.startCommandSessionCallCount, 1)
        XCTAssertEqual(commandClient.endCommandSessionCallCount, 1)
    }

    func testPauseDoesNothingWhenPlaybackIsAlreadyStopped() async {
        let commandClient = StubMediaPlaybackCommandClient(
            playbackStates: [false]
        )
        let service = MediaPlaybackService(
            commandClient: commandClient,
            pauseConfirmationPollNanoseconds: 0
        )

        let didPause = await service.pauseIfPlaying()

        XCTAssertFalse(didPause)
        XCTAssertEqual(commandClient.pauseCallCount, 0)
        XCTAssertEqual(commandClient.playbackStateQueryCount, 1)
        XCTAssertEqual(commandClient.startCommandSessionCallCount, 0)
        XCTAssertEqual(commandClient.endCommandSessionCallCount, 0)
    }

    func testPauseRetriesWhenPlaybackDoesNotInitiallyStop() async {
        let commandClient = StubMediaPlaybackCommandClient(
            playbackStates: [true, true, true, true, false]
        )
        let service = MediaPlaybackService(
            commandClient: commandClient,
            pauseConfirmationPollNanoseconds: 0,
            pauseConfirmationAttempts: 4
        )

        let didPause = await service.pauseIfPlaying()

        XCTAssertTrue(didPause)
        XCTAssertEqual(commandClient.pauseCallCount, 2)
        XCTAssertEqual(commandClient.playbackStateQueryCount, 5)
    }

    func testResumeRetriesUntilPlaybackActuallyReportsPlaying() async {
        let commandClient = StubMediaPlaybackCommandClient(
            playbackStates: [false, false, false, true]
        )
        let service = MediaPlaybackService(
            commandClient: commandClient,
            pauseConfirmationPollNanoseconds: 0,
            pauseConfirmationAttempts: 4
        )

        service.resumeIfWePaused(true)
        await service.waitForPendingPlaybackResume()

        XCTAssertEqual(commandClient.playCallCount, 2)
        XCTAssertEqual(commandClient.playbackStateQueryCount, 4)
        XCTAssertEqual(commandClient.startCommandSessionCallCount, 1)
        XCTAssertEqual(commandClient.endCommandSessionCallCount, 1)
    }

    private final class StubMediaPlaybackCommandClient:
        MediaPlaybackCommandClient {
        private var playbackStates: [Bool?]
        private(set) var playbackStateQueryCount = 0
        private(set) var startCommandSessionCallCount = 0
        private(set) var endCommandSessionCallCount = 0
        private(set) var pauseCallCount = 0
        private(set) var playCallCount = 0

        init(playbackStates: [Bool?]) {
            self.playbackStates = playbackStates
        }

        func isPlaying() async -> Bool? {
            let index = min(
                playbackStateQueryCount,
                max(0, playbackStates.count - 1)
            )
            playbackStateQueryCount += 1
            return playbackStates.isEmpty ? nil : playbackStates[index]
        }

        func startCommandSession() {
            startCommandSessionCallCount += 1
        }

        func endCommandSession() {
            endCommandSessionCallCount += 1
        }

        func pause() {
            pauseCallCount += 1
        }

        func play() {
            playCallCount += 1
        }
    }
}
