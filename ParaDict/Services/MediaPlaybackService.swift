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
    static let shared = MediaPlaybackService()

    private let logger = Logger(subsystem: "com.paradict", category: "MediaPlaybackService")

    #if arch(arm64)
    private let mediaController = MediaController()
    private var monitoringController: MediaController?
    private var monitoringGeneration: UInt64 = 0
    private var playbackStopGraceTask: Task<Void, Never>?
    private var playbackStateHandler: ((Bool) -> Void)?
    private var playbackMonitoringState = PlaybackMonitoringStateMachine()

    /// Avoid reopening capture during short pauses or while speaker output decays.
    private let playbackStopGraceNanoseconds: UInt64 = 800_000_000
    #endif

    private init() {}

    // MARK: - Public API

    #if arch(arm64)
    /// Pauses system media playback if something is currently playing.
    ///
    /// - Returns: `true` if we successfully paused playback, `false` if nothing was playing
    ///   or if we couldn't determine playback state.
    func pauseIfPlaying() async -> Bool {
        return await withCheckedContinuation { continuation in
            self.mediaController.getTrackInfo { [weak self] trackInfo in
                guard let self = self else {
                    continuation.resume(returning: false)
                    return
                }

                guard let trackInfo = trackInfo else {
                    self.logger.notice("No track info available, nothing to pause")
                    continuation.resume(returning: false)
                    return
                }

                // Determine if media is currently playing
                // Use isPlaying if available, otherwise check playbackRate
                let isPlaying: Bool
                if let playing = trackInfo.payload.isPlaying {
                    isPlaying = playing
                } else {
                    isPlaying = (trackInfo.payload.playbackRate ?? 0.0) > 0.0
                }

                self.logger.notice("Track: \(trackInfo.payload.applicationName ?? "Unknown") - \(trackInfo.payload.title ?? "Unknown"), isPlaying=\(trackInfo.payload.isPlaying?.description ?? "nil"), playbackRate=\(trackInfo.payload.playbackRate?.description ?? "nil"), determined=\(isPlaying)")

                if isPlaying {
                    self.logger.notice("Media is playing, sending pause command")
                    self.mediaController.pause()
                    continuation.resume(returning: true)
                } else {
                    self.logger.notice("Media is not playing, no action needed")
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// Resumes media playback only if we were the ones who paused it.
    ///
    /// - Parameter wePaused: `true` if `pauseIfPlaying()` returned `true` for this session.
    func resumeIfWePaused(_ wePaused: Bool) {
        guard wePaused else {
            return
        }

        logger.notice("Resuming media playback (we paused it)")
        // Use explicit play() command — never toggle (following cm rule b-mlrn5o09)
        mediaController.play()
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
