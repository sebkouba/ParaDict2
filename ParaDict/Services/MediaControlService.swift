import AppKit
import Foundation
import Combine
import os

class MediaControlService: ObservableObject {
    static let shared = MediaControlService()

    private let logger = Logger(subsystem: "com.paradict", category: "MediaControlService")

    private var didMuteAudio = false
    private var wasAudioMutedBeforeRecording = false
    private var currentMuteTask: Task<Bool, Never>?

    private init() {}

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
}
