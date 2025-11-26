import Foundation
import AVFoundation
import CoreAudio
import os

enum AudioConfigurationError: LocalizedError {
    case failedToSetInputDevice(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .failedToSetInputDevice(let status):
            return "Failed to set input device: \(status)"
        }
    }
}

class AudioDeviceConfiguration {
    private static let logger = Logger(subsystem: "com.paradict", category: "AudioDeviceConfiguration")

    static func getDefaultInputDevice() -> AudioDeviceID? {
        var defaultDeviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &defaultDeviceID
        )

        if status != noErr {
            logger.error("Failed to get current default input device: \(status)")
            return nil
        }
        return defaultDeviceID
    }

    static func setDefaultInputDevice(_ deviceID: AudioDeviceID) throws {
        if let currentDefault = getDefaultInputDevice(), currentDefault == deviceID {
            return
        }

        var deviceIDCopy = deviceID
        let propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let setDeviceResult = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            propertySize,
            &deviceIDCopy
        )

        if setDeviceResult != noErr {
            logger.error("Failed to set input device: \(setDeviceResult)")
            throw AudioConfigurationError.failedToSetInputDevice(status: setDeviceResult)
        }
    }

    static func createDeviceChangeObserver(
        handler: @escaping () -> Void,
        queue: OperationQueue = .main
    ) -> NSObjectProtocol {
        return NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AudioDeviceChanged"),
            object: nil,
            queue: queue,
            using: { _ in handler() }
        )
    }
}
