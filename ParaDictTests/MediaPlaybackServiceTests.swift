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

    private final class StubMediaPlaybackCommandClient:
        MediaPlaybackCommandClient {
        private var playbackStates: [Bool?]
        private(set) var playbackStateQueryCount = 0
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

        func pause() {
            pauseCallCount += 1
        }

        func play() {
            playCallCount += 1
        }
    }
}
