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
class RecordingService: NSObject, ObservableObject {
    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private let logger = Logger(subsystem: "com.paradict", category: "RecordingService")
    private let deviceManager = AudioDeviceManager.shared
    private let mediaControlService = MediaControlService.shared
    private var deviceObserver: NSObjectProtocol?
    private var isReconfiguring = false

    @Published var audioMeter = AudioMeter(averagePower: 0, peakPower: 0)
    @Published var isRecording = false

    /// Shared audio buffer for streaming transcription preview
    let audioBuffer = ThreadSafeAudioBuffer()

    /// The output format used for recording (16kHz mono Int16 WAV)
    private let targetSampleRate: Double = 16000.0
    private let targetChannels: AVAudioChannelCount = 1

    private var currentOutputURL: URL?

    enum RecordingError: LocalizedError {
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
        deviceObserver = AudioDeviceConfig.createDeviceChangeObserver { [weak self] in
            Task {
                await self?.handleDeviceChange()
            }
        }
    }

    private func handleDeviceChange() async {
        guard !isReconfiguring else { return }
        isReconfiguring = true

        if engine != nil {
            let currentURL = currentOutputURL
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
                try AudioDeviceConfig.setDefaultInputDevice(deviceID)
            } catch {
                logger.warning("Failed to configure audio session: \(error.localizedDescription)")
            }
        }

        do {
            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)

            logger.notice("Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch")

            // Create the target format for the tap: 16kHz mono Float32
            // AVAudioEngine will handle sample rate conversion from the hardware format
            guard let tapFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: targetSampleRate,
                channels: targetChannels,
                interleaved: false
            ) else {
                throw RecordingError.couldNotStartRecording
            }

            // Create the output WAV file in 16kHz mono Int16 format (same as before)
            guard let fileFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: targetSampleRate,
                channels: targetChannels,
                interleaved: true
            ) else {
                throw RecordingError.couldNotStartRecording
            }

            let audioFile = try AVAudioFile(forWriting: url, settings: fileFormat.settings)

            self.engine = engine
            self.audioFile = audioFile
            self.currentOutputURL = url
            audioBuffer.clear()

            // Install tap on input node — runs on CoreAudio realtime thread
            let buffer = self.audioBuffer
            let fileRef = audioFile
            let loggerRef = self.logger

            // Use a converter if the input format doesn't match our target
            // This handles cases where installTap with a different format isn't supported
            let needsConversion = inputFormat.sampleRate != targetSampleRate || inputFormat.channelCount != targetChannels

            if needsConversion {
                // Install tap with native input format, convert manually
                let converter = AVAudioConverter(from: inputFormat, to: tapFormat)

                inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] pcmBuffer, _ in
                    guard let converter = converter else { return }

                    // Convert to 16kHz mono
                    let frameCapacity = AVAudioFrameCount(
                        Double(pcmBuffer.frameLength) * (tapFormat.sampleRate / inputFormat.sampleRate)
                    )
                    guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: tapFormat, frameCapacity: frameCapacity + 1) else { return }

                    var error: NSError?
                    let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                        outStatus.pointee = .haveData
                        return pcmBuffer
                    }

                    guard status != .error, error == nil else { return }

                    // Append Float32 samples to shared buffer for streaming transcription
                    if let channelData = convertedBuffer.floatChannelData {
                        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(convertedBuffer.frameLength)))
                        buffer.append(samples)

                        // Compute metering from the samples
                        let (avg, peak) = Self.computeMetering(samples)
                        Task { @MainActor [weak self] in
                            self?.audioMeter = AudioMeter(averagePower: avg, peakPower: peak)
                        }
                    }

                    // Write to file
                    do {
                        try fileRef.write(from: convertedBuffer)
                    } catch {
                        loggerRef.error("Failed to write audio to file: \(error.localizedDescription)")
                    }
                }
            } else {
                // Input already matches target format, install tap directly
                inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] pcmBuffer, _ in
                    // Append Float32 samples to shared buffer for streaming transcription
                    if let channelData = pcmBuffer.floatChannelData {
                        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(pcmBuffer.frameLength)))
                        buffer.append(samples)

                        // Compute metering from the samples
                        let (avg, peak) = Self.computeMetering(samples)
                        Task { @MainActor [weak self] in
                            self?.audioMeter = AudioMeter(averagePower: avg, peakPower: peak)
                        }
                    }

                    // Write to file
                    do {
                        try fileRef.write(from: pcmBuffer)
                    } catch {
                        loggerRef.error("Failed to write audio to file: \(error.localizedDescription)")
                    }
                }
            }

            engine.prepare()
            try engine.start()

            isRecording = true

            // Mute system audio during recording if enabled
            if UserDefaults.standard.bool(forKey: SettingsKeys.muteDuringRecording) {
                Task {
                    _ = await mediaControlService.muteSystemAudio()
                }
            }

            logger.notice("Recording started with AVAudioEngine to: \(url.lastPathComponent)")

        } catch {
            logger.error("Failed to start audio engine: \(error.localizedDescription)")
            stopRecording()
            throw RecordingError.couldNotStartRecording
        }
    }

    func stopRecording() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        audioFile = nil
        currentOutputURL = nil
        audioMeter = AudioMeter(averagePower: 0, peakPower: 0)
        isRecording = false

        Task {
            await mediaControlService.unmuteSystemAudio()
        }
    }

    /// Compute RMS average power and peak power from Float32 samples, normalized to 0.0–1.0
    private static func computeMetering(_ samples: [Float]) -> (average: Double, peak: Double) {
        guard !samples.isEmpty else { return (0, 0) }

        var sumOfSquares: Float = 0
        var maxAbs: Float = 0

        for sample in samples {
            let abs = Swift.abs(sample)
            sumOfSquares += sample * sample
            if abs > maxAbs { maxAbs = abs }
        }

        let rms = sqrt(sumOfSquares / Float(samples.count))

        // Convert to dB then normalize to 0–1 range (same as the old AVAudioRecorder metering)
        let minDb: Float = -60.0
        let maxDb: Float = 0.0

        let rmsDb = rms > 0 ? 20 * log10(rms) : minDb
        let peakDb = maxAbs > 0 ? 20 * log10(maxAbs) : minDb

        let normalizedAvg = Double(max(0, min(1, (rmsDb - minDb) / (maxDb - minDb))))
        let normalizedPeak = Double(max(0, min(1, (peakDb - minDb) / (maxDb - minDb))))

        return (normalizedAvg, normalizedPeak)
    }

    deinit {
        if let observer = deviceObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
