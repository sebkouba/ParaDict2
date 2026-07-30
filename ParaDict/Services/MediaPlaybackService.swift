import Foundation
import os
#if arch(arm64)
import MediaRemoteAdapter
#endif

/// Service that wraps MediaRemoteAdapter's MediaController to provide
/// controlled pause/resume functionality during dictation.
///
/// Uses the MediaRemoteAdapter SPM package which runs a Perl+C subprocess
/// to query the MediaRemote private framework via dlopen. This works for
/// all media sources including browser-based media (YouTube, etc.).
@MainActor
final class MediaPlaybackService {
    static let shared = MediaPlaybackService(
        commandClient: MediaRemotePlaybackClient()
    )

    private let logger = Logger(subsystem: "com.paradict", category: "MediaPlaybackService")
    private let commandClient: any MediaPlaybackCommandClient
    private let pauseConfirmationPollNanoseconds: UInt64
    private let pauseConfirmationAttempts: Int
    private var playbackResumeTask: Task<Void, Never>?

    #if arch(arm64)
    private var monitoringController: MediaController?
    private var monitoringGeneration: UInt64 = 0
    private var playbackStopGraceTask: Task<Void, Never>?
    private var playbackStateHandler: ((Bool) -> Void)?
    private var playbackMonitoringState = PlaybackMonitoringStateMachine()

    /// Avoid reopening capture during short pauses or while speaker output decays.
    private let playbackStopGraceNanoseconds: UInt64 = 800_000_000
    #endif

    init(
        commandClient: any MediaPlaybackCommandClient,
        pauseConfirmationPollNanoseconds: UInt64 = 100_000_000,
        pauseConfirmationAttempts: Int = 8
    ) {
        self.commandClient = commandClient
        self.pauseConfirmationPollNanoseconds =
            pauseConfirmationPollNanoseconds
        self.pauseConfirmationAttempts = max(1, pauseConfirmationAttempts)
    }

    // MARK: - Public API

    #if arch(arm64)
    /// Pauses system media playback if something is currently playing.
    ///
    /// - Returns: `true` if we successfully paused playback, `false` if nothing was playing
    ///   or if we couldn't determine playback state.
    func pauseIfPlaying() async -> Bool {
        playbackResumeTask?.cancel()
        await playbackResumeTask?.value
        playbackResumeTask = nil

        guard let isPlaying = await commandClient.isPlaying() else {
            logger.notice("No playback state available, nothing to pause")
            return false
        }

        guard isPlaying else {
            logger.notice("Media is not playing, no action needed")
            return false
        }

        logger.notice("Media is playing, sending pause command")
        commandClient.startCommandSession()
        defer { commandClient.endCommandSession() }
        commandClient.pause()

        for attempt in 1...pauseConfirmationAttempts {
            do {
                try await Task.sleep(
                    nanoseconds: pauseConfirmationPollNanoseconds
                )
            } catch {
                logger.notice("Pause confirmation cancelled")
                return true
            }

            if await commandClient.isPlaying() == false {
                logger.notice(
                    "Confirmed media playback paused after \(attempt) check(s)"
                )
                return true
            }

            if attempt.isMultiple(of: 3),
               attempt < pauseConfirmationAttempts {
                logger.notice(
                    "Playback is still active; retrying pause command"
                )
                commandClient.pause()
            }
        }

        logger.warning(
            "Pause command was sent, but playback did not report a stopped state"
        )
        return true
    }

    /// Resumes media playback only if we were the ones who paused it.
    ///
    /// - Parameter wePaused: `true` if `pauseIfPlaying()` returned `true` for this session.
    func resumeIfWePaused(_ wePaused: Bool) {
        guard wePaused else {
            return
        }

        playbackResumeTask?.cancel()
        playbackResumeTask = Task { [weak self] in
            await self?.resumePlayback()
        }
    }

    func waitForPendingPlaybackResume() async {
        await playbackResumeTask?.value
    }

    private func resumePlayback() async {
        logger.notice("Resuming media playback (we paused it)")
        commandClient.startCommandSession()
        defer { commandClient.endCommandSession() }

        // Use explicit play() commands — never toggle (following cm rule b-mlrn5o09).
        commandClient.play()

        for attempt in 1...pauseConfirmationAttempts {
            do {
                try await Task.sleep(
                    nanoseconds: pauseConfirmationPollNanoseconds
                )
            } catch {
                logger.notice("Playback resume confirmation cancelled")
                return
            }

            if await commandClient.isPlaying() == true {
                logger.notice(
                    "Confirmed media playback resumed after \(attempt) check(s)"
                )
                return
            }

            if attempt.isMultiple(of: 3),
               attempt < pauseConfirmationAttempts {
                logger.notice(
                    "Playback is still stopped; retrying play command"
                )
                commandClient.play()
            }
        }

        logger.warning(
            "Play command was sent, but playback did not report an active state"
        )
    }

    /// Monitor changes from the system's current media session.
    ///
    /// Playback starts are reported immediately unless the caller is already
    /// pausing the current playback session. Stops are reported after a short
    /// grace period so buffering pauses and speaker tails do not briefly reopen
    /// microphone capture.
    func startMonitoringPlayback(
        ignoreCurrentPlaybackUntilStopped: Bool = false,
        onStateChange: @escaping (Bool) -> Void
    ) {
        stopMonitoringPlayback()

        monitoringGeneration &+= 1
        let generation = monitoringGeneration
        playbackStateHandler = onStateChange
        playbackMonitoringState = PlaybackMonitoringStateMachine(
            ignoreCurrentPlaybackUntilStopped: ignoreCurrentPlaybackUntilStopped
        )

        let controller = MediaController()
        monitoringController = controller

        controller.onTrackInfoReceived = { [weak self] trackInfo in
            self?.handleMonitoredTrackInfo(trackInfo, generation: generation)
        }
        controller.onDecodingError = { [weak self] error, _ in
            self?.logger.warning("Could not decode media playback state: \(error.localizedDescription)")
        }
        controller.onListenerTerminated = { [weak self] in
            guard let self else { return }
            self.logger.warning("Media playback listener stopped unexpectedly")
            self.handleMonitoredPlaybackState(false, generation: generation)
        }

        controller.startListening()
        logger.notice(
            "Started media playback monitoring; ignoreCurrentPlaybackUntilStopped=\(ignoreCurrentPlaybackUntilStopped)"
        )
    }

    func stopMonitoringPlayback() {
        monitoringGeneration &+= 1
        playbackStopGraceTask?.cancel()
        playbackStopGraceTask = nil
        playbackStateHandler = nil
        playbackMonitoringState = PlaybackMonitoringStateMachine()

        let controller = monitoringController
        monitoringController = nil
        controller?.onTrackInfoReceived = nil
        controller?.onDecodingError = nil
        controller?.onListenerTerminated = nil
        controller?.stopListening()
        logger.notice("Stopped media playback monitoring")
    }

    private func handleMonitoredTrackInfo(_ trackInfo: TrackInfo?, generation: UInt64) {
        let isPlaying: Bool
        if let reportedPlaying = trackInfo?.payload.isPlaying {
            isPlaying = reportedPlaying
        } else {
            isPlaying = (trackInfo?.payload.playbackRate ?? 0) > 0
        }

        handleMonitoredPlaybackState(isPlaying, generation: generation)
    }

    private func handleMonitoredPlaybackState(_ isPlaying: Bool, generation: UInt64) {
        guard generation == monitoringGeneration else { return }

        let wasWaitingForInitialStop =
            playbackMonitoringState.isWaitingForInitialPlaybackStop
        let actions = playbackMonitoringState.observe(isPlaying: isPlaying)

        if wasWaitingForInitialStop &&
            !playbackMonitoringState.isWaitingForInitialPlaybackStop {
            logger.notice(
                "Initial playback paused by ParaDict has stopped; monitoring is now armed"
            )
        }

        performMonitoringActions(actions, generation: generation)
    }

    private func performMonitoringActions(
        _ actions: [PlaybackMonitoringStateMachine.Action],
        generation: UInt64
    ) {
        for action in actions {
            switch action {
            case .reportPlaybackStarted:
                logger.notice("Media playback started")
                playbackStateHandler?(true)

            case .schedulePlaybackStopped:
                schedulePlaybackStopped(generation: generation)

            case .cancelPendingPlaybackStop:
                playbackStopGraceTask?.cancel()
                playbackStopGraceTask = nil

            case .reportPlaybackStopped:
                logger.notice(
                    "Media playback remained stopped; microphone capture may resume"
                )
                playbackStateHandler?(false)
            }
        }
    }

    private func schedulePlaybackStopped(generation: UInt64) {
        playbackStopGraceTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(
                    nanoseconds: self.playbackStopGraceNanoseconds
                )
            } catch {
                return
            }

            guard generation == self.monitoringGeneration else { return }
            self.playbackStopGraceTask = nil
            let actions =
                self.playbackMonitoringState.completePlaybackStopGracePeriod()
            self.performMonitoringActions(actions, generation: generation)
        }
    }
    #else
    // Intel Mac stub — media control not available
    func pauseIfPlaying() async -> Bool {
        logger.notice("Media control not available on Intel Macs")
        return false
    }

    func resumeIfWePaused(_ wePaused: Bool) {
        // No-op on Intel
    }

    func startMonitoringPlayback(
        ignoreCurrentPlaybackUntilStopped: Bool = false,
        onStateChange: @escaping (Bool) -> Void
    ) {
        logger.notice("Media playback monitoring is not available on Intel Macs")
    }

    func stopMonitoringPlayback() {
        // No-op on Intel
    }
    #endif
}
