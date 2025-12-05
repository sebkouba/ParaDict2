import AppKit
import Foundation
import Combine
import os

// MARK: - MediaRemote Framework Bridge

private let mediaRemoteBundle: CFBundle? = {
    let bundleURL = NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
    return CFBundleCreate(kCFAllocatorDefault, bundleURL)
}()

private typealias MRMediaRemoteSendCommandFunction = @convention(c) (UInt32, UnsafeRawPointer?) -> Bool

private let MRMediaRemoteSendCommand: MRMediaRemoteSendCommandFunction? = {
    guard let bundle = mediaRemoteBundle,
          let pointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) else {
        return nil
    }
    return unsafeBitCast(pointer, to: MRMediaRemoteSendCommandFunction.self)
}()

private let kMRPlay: UInt32 = 0
private let kMRPause: UInt32 = 1

class MediaControlService: ObservableObject {
    static let shared = MediaControlService()

    private let logger = Logger(subsystem: "com.paradict", category: "MediaControlService")

    private var didMuteAudio = false
    private var wasAudioMutedBeforeRecording = false
    private var currentMuteTask: Task<Bool, Never>?

    private init() {
        if MRMediaRemoteSendCommand == nil {
            logger.error("Failed to load MRMediaRemoteSendCommand - media control unavailable")
        }
    }

    private func isSystemAudioMuted() -> Bool {
        let pipe = Pipe()
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", "output muted of (get volume settings)"]
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return output == "true"
            }
        } catch {
            // Silently fail
        }

        return false
    }

    func muteSystemAudio() async -> Bool {
        currentMuteTask?.cancel()

        let task = Task<Bool, Never> {
            wasAudioMutedBeforeRecording = isSystemAudioMuted()

            if wasAudioMutedBeforeRecording {
                return true
            }

            let success = executeAppleScript(command: "set volume with output muted")
            didMuteAudio = success
            return success
        }

        currentMuteTask = task
        return await task.value
    }

    func unmuteSystemAudio() async {
        if let muteTask = currentMuteTask {
            _ = await muteTask.value
        }

        if didMuteAudio && !wasAudioMutedBeforeRecording {
            _ = executeAppleScript(command: "set volume without output muted")
        }

        didMuteAudio = false
        currentMuteTask = nil
    }

    private func executeAppleScript(command: String) -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", command]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Media Playback Control (YouTube Mode)

    /// Send pause command to system media. Returns true if command was sent.
    func pauseMedia() -> Bool {
        guard let sendCommand = MRMediaRemoteSendCommand else {
            logger.warning("pauseMedia: MediaRemote not available")
            return false
        }
        let success = sendCommand(kMRPause, nil)
        logger.notice("pauseMedia: sent pause command, success=\(success)")
        return success
    }

    /// Send play command to system media. Returns true if command was sent.
    func resumeMedia() -> Bool {
        guard let sendCommand = MRMediaRemoteSendCommand else {
            logger.warning("resumeMedia: MediaRemote not available")
            return false
        }
        let success = sendCommand(kMRPlay, nil)
        logger.notice("resumeMedia: sent play command, success=\(success)")
        return success
    }
}
