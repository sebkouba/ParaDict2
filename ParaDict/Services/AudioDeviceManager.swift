import Foundation
import CoreAudio
import AVFoundation
import Combine
import os

class AudioDeviceManager: ObservableObject {
    private let logger = Logger(subsystem: "com.paradict", category: "AudioDeviceManager")
    @Published var availableDevices: [(id: AudioDeviceID, uid: String, name: String)] = []
    @Published var selectedDeviceUID: String?
    var fallbackDeviceID: AudioDeviceID?

    static let shared = AudioDeviceManager()

    private init() {
        setupFallbackDevice()
        loadAvailableDevices()
        loadSelectedDevice()
        setupDeviceChangeNotifications()
    }

    private func setupFallbackDevice() {
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

        if status == noErr {
            fallbackDeviceID = defaultDeviceID
            logger.notice("Fallback device ID: \(defaultDeviceID)")
        }
    }

    private func loadSelectedDevice() {
        // Device is now loaded from ConfigManager, not UserDefaults
        // This is called before ConfigManager is fully initialized,
        // so we don't read from it here. ConfigManager will call applyAudioDevice() later.
    }

    func loadAvailableDevices() {
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
            return
        }

        let devices = deviceIDs.compactMap { deviceID -> (id: AudioDeviceID, uid: String, name: String)? in
            guard let name = getDeviceName(deviceID: deviceID),
                  let uid = getDeviceUID(deviceID: deviceID),
                  isInputDevice(deviceID: deviceID) else {
                return nil
            }
            return (id: deviceID, uid: uid, name: name)
        }

        DispatchQueue.main.async {
            self.availableDevices = devices
            self.logger.notice("Found \(devices.count) input devices")
        }
    }

    /// Select an audio device by UID. Set fromUI=true when called from user interaction.
    func selectDevice(uid: String, fromUI: Bool = false) {
        selectedDeviceUID = uid
        logger.notice("Selected device UID: \(uid)")

        // Sync back to config file if this was a user action
        if fromUI {
            Task { @MainActor in
                ConfigManager.shared.syncAudioDeviceFromUI()
            }
        }
    }

    /// Use the system default device. Set fromUI=true when called from user interaction.
    func useSystemDefault(fromUI: Bool = false) {
        selectedDeviceUID = nil
        logger.notice("Using system default device")

        // Sync back to config file if this was a user action
        if fromUI {
            Task { @MainActor in
                ConfigManager.shared.syncAudioDeviceFromUI()
            }
        }
    }

    func getCurrentDevice() -> AudioDeviceID {
        if let uid = selectedDeviceUID,
           let device = availableDevices.first(where: { $0.uid == uid }) {
            return device.id
        }
        return fallbackDeviceID ?? 0
    }

    private func getDeviceName(deviceID: AudioDeviceID) -> String? {
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

    private func getDeviceUID(deviceID: AudioDeviceID) -> String? {
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

    private func isInputDevice(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
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

        guard result == noErr else { return false }

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

    private func setupDeviceChangeNotifications() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            { (_, _, _, userData) -> OSStatus in
                let manager = Unmanaged<AudioDeviceManager>.fromOpaque(userData!).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.loadAvailableDevices()
                }
                return noErr
            },
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
    }
}
