import Foundation
import AVFoundation
import CoreAudio
import os

enum AudioConfigurationError: LocalizedError {
    case failedToSetInputDevice(status: OSStatus)
    case failedToSetOutputDevice(status: OSStatus)
    case deviceNotFound(String)

    var errorDescription: String? {
        switch self {
        case .failedToSetInputDevice(let status):
            return "Failed to set input device: \(status)"
        case .failedToSetOutputDevice(let status):
            return "Failed to set output device: \(status)"
        case .deviceNotFound(let name):
            return "Audio device not found: \(name)"
        }
    }
}

class AudioDeviceConfig {
    private static let logger = Logger(subsystem: "com.paradict", category: "AudioDeviceConfig")

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

    // MARK: - Output Device Management

    /// Returns all available output devices as (id, uid, name) tuples
    static func getOutputDevices() -> [(id: AudioDeviceID, uid: String, name: String)] {
        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var result = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize
        )

        guard result == noErr else {
            logger.error("Error getting audio device count: \(result)")
            return []
        }

        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        result = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )

        guard result == noErr else {
            logger.error("Error getting audio devices: \(result)")
            return []
        }

        return deviceIDs.compactMap { deviceID -> (id: AudioDeviceID, uid: String, name: String)? in
            guard isOutputDevice(deviceID: deviceID),
                  let name = getDeviceName(deviceID: deviceID),
                  let uid = getDeviceUID(deviceID: deviceID) else {
                return nil
            }
            return (id: deviceID, uid: uid, name: name)
        }
    }

    static func getDefaultOutputDevice() -> AudioDeviceID? {
        var defaultDeviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
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
            logger.error("Failed to get current default output device: \(status)")
            return nil
        }
        return defaultDeviceID
    }

    static func setDefaultOutputDevice(_ deviceID: AudioDeviceID) throws {
        if let currentDefault = getDefaultOutputDevice(), currentDefault == deviceID {
            logger.notice("Output device \(deviceID) is already the default")
            return
        }

        var deviceIDCopy = deviceID
        let propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
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
            logger.error("Failed to set output device: \(setDeviceResult)")
            throw AudioConfigurationError.failedToSetOutputDevice(status: setDeviceResult)
        }

        logger.notice("Successfully set output device to \(deviceID)")
    }

    /// Set output device by name (fuzzy matching)
    static func setOutputDeviceByName(_ searchName: String) throws -> String {
        let devices = getOutputDevices()
        let searchLower = searchName.lowercased()

        // Try exact match first
        if let device = devices.first(where: { $0.name.lowercased() == searchLower }) {
            try setDefaultOutputDevice(device.id)
            return device.name
        }

        // Try contains match
        if let device = devices.first(where: { $0.name.lowercased().contains(searchLower) }) {
            try setDefaultOutputDevice(device.id)
            return device.name
        }

        // Try matching parts of the search term
        let searchParts = searchLower.split(separator: " ").map(String.init)
        for device in devices {
            let nameLower = device.name.lowercased()
            if searchParts.allSatisfy({ nameLower.contains($0) }) {
                try setDefaultOutputDevice(device.id)
                return device.name
            }
        }

        let availableNames = devices.map { $0.name }.joined(separator: ", ")
        logger.error("Output device '\(searchName)' not found. Available: \(availableNames)")
        throw AudioConfigurationError.deviceNotFound(searchName)
    }

    // MARK: - Private Helpers

    private static func isOutputDevice(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var propertySize: UInt32 = 0
        var result = AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &propertySize
        )

        guard result == noErr, propertySize > 0 else { return false }

        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(propertySize))
        defer { bufferList.deallocate() }

        result = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            bufferList
        )

        guard result == noErr else { return false }

        return Int(bufferList.pointee.mNumberBuffers) > 0
    }

    private static func getDeviceName(deviceID: AudioDeviceID) -> String? {
        var name: CFString?
        var propertySize = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &name
        )

        return status == noErr ? name as String? : nil
    }

    private static func getDeviceUID(deviceID: AudioDeviceID) -> String? {
        var uid: CFString?
        var propertySize = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &uid
        )

        return status == noErr ? uid as String? : nil
    }
}
