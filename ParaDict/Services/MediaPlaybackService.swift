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
    #else
    // Intel Mac stub — media control not available
    func pauseIfPlaying() async -> Bool {
        logger.notice("Media control not available on Intel Macs")
        return false
    }

    func resumeIfWePaused(_ wePaused: Bool) {
        // No-op on Intel
    }
    #endif
}
