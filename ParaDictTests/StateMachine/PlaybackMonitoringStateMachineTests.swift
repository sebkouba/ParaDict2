import XCTest
@testable import ParaDict

final class PlaybackMonitoringStateMachineTests: XCTestCase {
    func testIgnoresPlaybackThatWasAlreadyPlayingUntilItStops() {
        var stateMachine = PlaybackMonitoringStateMachine(
            ignoreCurrentPlaybackUntilStopped: true
        )

        XCTAssertEqual(stateMachine.observe(isPlaying: true), [])
        XCTAssertTrue(stateMachine.isWaitingForInitialPlaybackStop)
        XCTAssertFalse(stateMachine.isPlaybackActive)

        XCTAssertEqual(stateMachine.observe(isPlaying: false), [])
        XCTAssertFalse(stateMachine.isWaitingForInitialPlaybackStop)
        XCTAssertFalse(stateMachine.isPlaybackActive)
        XCTAssertFalse(stateMachine.isPlaybackStopPending)
    }

    func testReportsPlaybackThatStartsAfterInitialPlaybackStops() {
        var stateMachine = PlaybackMonitoringStateMachine(
            ignoreCurrentPlaybackUntilStopped: true
        )

        _ = stateMachine.observe(isPlaying: true)
        _ = stateMachine.observe(isPlaying: false)

        XCTAssertEqual(
            stateMachine.observe(isPlaying: true),
            [.reportPlaybackStarted]
        )
        XCTAssertTrue(stateMachine.isPlaybackActive)
    }

    func testReportsAlreadyActivePlaybackWhenNotIgnoringInitialState() {
        var stateMachine = PlaybackMonitoringStateMachine()

        XCTAssertEqual(
            stateMachine.observe(isPlaying: true),
            [.reportPlaybackStarted]
        )
        XCTAssertTrue(stateMachine.isPlaybackActive)
    }

    func testPlaybackStopUsesGracePeriodAndCanBeCancelled() {
        var stateMachine = PlaybackMonitoringStateMachine()

        _ = stateMachine.observe(isPlaying: true)
        XCTAssertEqual(
            stateMachine.observe(isPlaying: false),
            [.schedulePlaybackStopped]
        )
        XCTAssertEqual(
            stateMachine.observe(isPlaying: true),
            [.cancelPendingPlaybackStop]
        )
        XCTAssertEqual(stateMachine.completePlaybackStopGracePeriod(), [])

        XCTAssertEqual(
            stateMachine.observe(isPlaying: false),
            [.schedulePlaybackStopped]
        )
        XCTAssertEqual(
            stateMachine.completePlaybackStopGracePeriod(),
            [.reportPlaybackStopped]
        )
        XCTAssertFalse(stateMachine.isPlaybackActive)
    }
}
