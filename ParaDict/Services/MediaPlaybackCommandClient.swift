import Foundation

/// Commands and queries the system's current media playback session.
@MainActor
protocol MediaPlaybackCommandClient: AnyObject {
    func isPlaying() async -> Bool?
    func startCommandSession()
    func endCommandSession()
    func pause()
    func play()
}
