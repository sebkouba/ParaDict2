import Foundation
#if arch(arm64)
import MediaRemoteAdapter
#endif

/// MediaRemoteAdapter-backed playback command client.
@MainActor
final class MediaRemotePlaybackClient: MediaPlaybackCommandClient {
    #if arch(arm64)
    private let controller = MediaController()
    private var commandSessionController: MediaController?
    #endif

    func isPlaying() async -> Bool? {
        #if arch(arm64)
        return await withCheckedContinuation { continuation in
            controller.getTrackInfo { trackInfo in
                guard let trackInfo else {
                    continuation.resume(returning: nil)
                    return
                }

                if let isPlaying = trackInfo.payload.isPlaying {
                    continuation.resume(returning: isPlaying)
                } else {
                    continuation.resume(
                        returning: (trackInfo.payload.playbackRate ?? 0) > 0
                    )
                }
            }
        }
        #else
        return nil
        #endif
    }

    func startCommandSession() {
        #if arch(arm64)
        guard commandSessionController == nil else { return }

        let controller = MediaController()
        commandSessionController = controller
        controller.startListening()
        #endif
    }

    func endCommandSession() {
        #if arch(arm64)
        commandSessionController?.stopListening()
        commandSessionController = nil
        #endif
    }

    func pause() {
        #if arch(arm64)
        controller.pause()
        #endif
    }

    func play() {
        #if arch(arm64)
        controller.play()
        #endif
    }
}
