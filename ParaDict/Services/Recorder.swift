import Foundation
import AVFoundation
import CoreAudio
import Combine
import os

struct AudioMeter: Equatable {
    let averagePower: Double
    let peakPower: Double
}

@MainActor
class Recorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private let logger = Logger(subsystem: "com.paradict", category: "Recorder")
    private let deviceManager = AudioDeviceManager.shared
    private let mediaController = MediaController.shared
    private var deviceObserver: NSObjectProtocol?
    private var isReconfiguring = false

    @Published var audioMeter = AudioMeter(averagePower: 0, peakPower: 0)
    @Published var isRecording = false

    private var audioMeterUpdateTask: Task<Void, Never>?

    enum RecorderError: LocalizedError {
        case couldNotStartRecording

        var errorDescription: String? {
            switch self {
            case .couldNotStartRecording:
                return "Could not start recording"
            }
        }
    }

    override init() {
        super.init()
        setupDeviceChangeObserver()
    }

    private func setupDeviceChangeObserver() {
        deviceObserver = AudioDeviceConfiguration.createDeviceChangeObserver { [weak self] in
            Task {
                await self?.handleDeviceChange()
            }
        }
    }

    private func handleDeviceChange() async {
        guard !isReconfiguring else { return }
        isReconfiguring = true

        if recorder != nil {
            let currentURL = recorder?.url
            stopRecording()

            if let url = currentURL {
                do {
                    try await startRecording(toOutputFile: url)
                } catch {
                    logger.error("Failed to restart recording after device change: \(error.localizedDescription)")
                }
            }
        }
        isReconfiguring = false
    }

    func startRecording(toOutputFile url: URL) async throws {
        let deviceID = deviceManager.getCurrentDevice()
        if deviceID != 0 {
            do {
                try AudioDeviceConfiguration.setDefaultInputDevice(deviceID)
            } catch {
                logger.warning("Failed to configure audio session: \(error.localizedDescription)")
            }
        }

        let recordSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        do {
            recorder = try AVAudioRecorder(url: url, settings: recordSettings)
            recorder?.delegate = self
            recorder?.isMeteringEnabled = true

            if recorder?.record() == false {
                logger.error("Could not start recording")
                throw RecorderError.couldNotStartRecording
            }

            isRecording = true

            // Mute system audio during recording if enabled
            let config = ConfigManager.shared.config
            if config.app.muteDuringRecording {
                Task {
                    _ = await mediaController.muteSystemAudio()
                }
            }

            // Start audio meter updates
            audioMeterUpdateTask?.cancel()
            audioMeterUpdateTask = Task {
                while recorder != nil && !Task.isCancelled {
                    updateAudioMeter()
                    try? await Task.sleep(nanoseconds: 33_000_000) // ~30fps
                }
            }

        } catch {
            logger.error("Failed to create audio recorder: \(error.localizedDescription)")
            stopRecording()
            throw RecorderError.couldNotStartRecording
        }
    }

    func stopRecording() {
        audioMeterUpdateTask?.cancel()
        recorder?.stop()
        recorder = nil
        audioMeter = AudioMeter(averagePower: 0, peakPower: 0)
        isRecording = false

        Task {
            await mediaController.unmuteSystemAudio()
        }
    }

    private func updateAudioMeter() {
        guard let recorder = recorder else { return }
        recorder.updateMeters()

        let averagePower = recorder.averagePower(forChannel: 0)
        let peakPower = recorder.peakPower(forChannel: 0)

        let minVisibleDb: Float = -60.0
        let maxVisibleDb: Float = 0.0

        let normalizedAverage = normalize(power: averagePower, min: minVisibleDb, max: maxVisibleDb)
        let normalizedPeak = normalize(power: peakPower, min: minVisibleDb, max: maxVisibleDb)

        audioMeter = AudioMeter(averagePower: Double(normalizedAverage), peakPower: Double(normalizedPeak))
    }

    private func normalize(power: Float, min: Float, max: Float) -> Float {
        if power < min { return 0.0 }
        if power >= max { return 1.0 }
        return (power - min) / (max - min)
    }

    // MARK: - AVAudioRecorderDelegate

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            Task { @MainActor in
                logger.error("Recording finished unsuccessfully")
            }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            Task { @MainActor in
                logger.error("Recording encode error: \(error.localizedDescription)")
            }
        }
    }

    deinit {
        audioMeterUpdateTask?.cancel()
        if let observer = deviceObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
