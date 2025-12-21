import Foundation
import CoreAudio
import AVFoundation
import Combine
import SwiftUI
import os

class AudioDeviceManager: ObservableObject {
    private let logger = Logger(subsystem: "com.paradict", category: "AudioDeviceManager")
    @Published var availableDevices: [(id: AudioDeviceID, uid: String, name: String)] = []
    @Published var devicePriority: [String] = []  // Ordered UIDs (highest priority first)
    @Published var enabledDevices: Set<String> = []  // UIDs of enabled devices
    var fallbackDeviceID: AudioDeviceID?

    static let shared = AudioDeviceManager()

    private init() {
        setupFallbackDevice()
        loadAvailableDevices()
        loadPrioritySettings()
        migrateFromLegacySettings()
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

    private func loadPrioritySettings() {
        // Load priority order
        if let savedPriority = UserDefaults.standard.array(forKey: SettingsKeys.audioDevicePriority) as? [String] {
            devicePriority = savedPriority
            logger.notice("Loaded device priority: \(savedPriority.count) devices")
        }

        // Load enabled devices
        if let savedEnabled = UserDefaults.standard.array(forKey: SettingsKeys.audioDevicesEnabled) as? [String] {
            enabledDevices = Set(savedEnabled)
            logger.notice("Loaded enabled devices: \(savedEnabled.count) devices")
        }
    }

    private func migrateFromLegacySettings() {
        // Migrate from old single-device selection if present
        if let legacyUID = UserDefaults.standard.string(forKey: SettingsKeys.audioDeviceUID) {
            if devicePriority.isEmpty {
                // Put the legacy device first in priority
                devicePriority = [legacyUID]
                enabledDevices = [legacyUID]
                savePrioritySettings()
                logger.notice("Migrated legacy device UID: \(legacyUID)")
            }
            // Clear legacy setting
            UserDefaults.standard.removeObject(forKey: SettingsKeys.audioDeviceUID)
        }
    }

    private func savePrioritySettings() {
        UserDefaults.standard.set(devicePriority, forKey: SettingsKeys.audioDevicePriority)
        UserDefaults.standard.set(Array(enabledDevices), forKey: SettingsKeys.audioDevicesEnabled)
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

    // MARK: - Priority Management

    /// Set the complete device priority order
    func setDevicePriority(_ uids: [String]) {
        devicePriority = uids
        savePrioritySettings()
        logger.notice("Set device priority order: \(uids.count) devices")
    }

    /// Toggle whether a device is enabled (tried before fallback devices)
    func toggleEnabled(uid: String) {
        if enabledDevices.contains(uid) {
            enabledDevices.remove(uid)
        } else {
            enabledDevices.insert(uid)
        }
        savePrioritySettings()
        logger.notice("Toggled device \(uid) enabled: \(self.enabledDevices.contains(uid))")
    }

    /// Check if a device is enabled
    func isEnabled(uid: String) -> Bool {
        // If no devices are explicitly enabled, treat all as enabled
        if enabledDevices.isEmpty {
            return true
        }
        return enabledDevices.contains(uid)
    }

    /// Check if a device is currently available (connected)
    func isAvailable(uid: String) -> Bool {
        return availableDevices.contains(where: { $0.uid == uid })
    }

    /// Get the ordered list of devices for display (merges priority list with available devices)
    func getOrderedDevices() -> [(id: AudioDeviceID, uid: String, name: String)] {
        var result: [(id: AudioDeviceID, uid: String, name: String)] = []
        var seen = Set<String>()

        // First: add devices in priority order
        for uid in devicePriority {
            if let device = availableDevices.first(where: { $0.uid == uid }) {
                result.append(device)
                seen.insert(uid)
            }
        }

        // Then: add any new devices not yet in priority list
        for device in availableDevices {
            if !seen.contains(device.uid) {
                result.append(device)
                devicePriority.append(device.uid)  // Add to priority list
            }
        }

        if !seen.isEmpty || result.count != devicePriority.count {
            savePrioritySettings()
        }

        return result
    }

    func getCurrentDevice() -> AudioDeviceID {
        let availableUIDs = Set(availableDevices.map { $0.uid })

        // First: try enabled devices in priority order
        for uid in devicePriority {
            if isEnabled(uid: uid) && availableUIDs.contains(uid),
               let device = availableDevices.first(where: { $0.uid == uid }) {
                logger.debug("Using enabled device: \(device.name)")
                return device.id
            }
        }

        // Fallback: try disabled devices in priority order
        for uid in devicePriority {
            if !isEnabled(uid: uid) && availableUIDs.contains(uid),
               let device = availableDevices.first(where: { $0.uid == uid }) {
                logger.debug("Falling back to disabled device: \(device.name)")
                return device.id
            }
        }

        // Last resort: system default
        logger.debug("Using system fallback device")
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
