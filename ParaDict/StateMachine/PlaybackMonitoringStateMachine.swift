import Foundation

/// Distinguishes playback that was already active when recording began from
/// playback that starts during the recording.
nonisolated struct PlaybackMonitoringStateMachine {
    enum Action: Equatable {
        case reportPlaybackStarted
        case schedulePlaybackStopped
        case cancelPendingPlaybackStop
        case reportPlaybackStopped
    }

    private(set) var isWaitingForInitialPlaybackStop: Bool
    private(set) var isPlaybackActive = false
    private(set) var isPlaybackStopPending = false

    init(ignoreCurrentPlaybackUntilStopped: Bool = false) {
        isWaitingForInitialPlaybackStop = ignoreCurrentPlaybackUntilStopped
    }

    mutating func observe(isPlaying: Bool) -> [Action] {
        if isWaitingForInitialPlaybackStop {
            if !isPlaying {
                isWaitingForInitialPlaybackStop = false
            }
            return []
        }

        if isPlaying {
            var actions: [Action] = []

            if isPlaybackStopPending {
                isPlaybackStopPending = false
                actions.append(.cancelPendingPlaybackStop)
            }

            if !isPlaybackActive {
                isPlaybackActive = true
                actions.append(.reportPlaybackStarted)
            }

            return actions
        }

        guard isPlaybackActive, !isPlaybackStopPending else {
            return []
        }

        isPlaybackStopPending = true
        return [.schedulePlaybackStopped]
    }

    mutating func completePlaybackStopGracePeriod() -> [Action] {
        guard isPlaybackStopPending else {
            return []
        }

        isPlaybackStopPending = false
        guard isPlaybackActive else {
            return []
        }

        isPlaybackActive = false
        return [.reportPlaybackStopped]
    }
}
