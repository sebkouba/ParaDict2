import Foundation
import AVFoundation
import CoreAudio
import Combine
import os

struct AudioMeter: Equatable {
    let averagePower: Double
    let peakPower: Double
}

private final class TapDrainState: @unchecked Sendable {
    private let lock = NSLock()
    private var inFlightCallbacks = 0
    private var drainContinuation: CheckedContinuation<Void, Never>?

    func reset() {
        lock.lock()
        inFlightCallbacks = 0
        drainContinuation = nil
        lock.unlock()
    }

    func beginCallback() {
        lock.lock()
        inFlightCallbacks += 1
        lock.unlock()
    }

    func endCallback() {
        var continuation: CheckedContinuation<Void, Never>?

        lock.lock()
        inFlightCallbacks -= 1
        if inFlightCallbacks == 0 {
            continuation = drainContinuation
            drainContinuation = nil
        }
        lock.unlock()

        continuation?.resume()
    }

    func waitUntilDrained() async {
        lock.lock()
        if inFlightCallbacks == 0 {
            lock.unlock()
            return
        }
        lock.unlock()

        await withCheckedContinuation { continuation in
            lock.lock()
            if inFlightCallbacks == 0 {
                lock.unlock()
                continuation.resume()
                return
            }
            drainContinuation = continuation
            lock.unlock()
        }
    }
}

@MainActor
class RecordingService: NSObject, ObservableObject {
    private var engine: AVAudioEngine?
    private let logger = Logger(subsystem: "com.paradict", category: "RecordingService")
    private let deviceManager = AudioDeviceManager.shared
    private let mediaControlService = MediaControlService.shared
    private var deviceObserver: NSObjectProtocol?
    private var isReconfiguring = false
    private let tapDrainState = TapDrainState()
    private var activeConverter: AVAudioConverter?
    private var activeTapFormat: AVAudioFormat?

    @Published var audioMeter = AudioMeter(averagePower: 0, peakPower: 0)
    @Published var isRecording = false

    /// Shared audio buffer for streaming transcription preview
    let audioBuffer = ThreadSafeAudioBuffer()

    /// The output format used for recording (16kHz mono Float32)
    private let targetSampleRate: Double = 16000.0
    private let targetChannels: AVAudioChannelCount = 1
    /// Smaller tap buffers reduce how much trailing speech can be stranded at stop time.
    private let tapBufferSize: AVAudioFrameCount = 1024

    enum RecordingError: LocalizedError {
        case couldNotStartRecording(reason: String)

        var errorDescription: String? {
            switch self {
            case .couldNotStartRecording(let reason):
                return reason
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
            stopRecording()

            do {
                try await startRecording()
            } catch {
                logger.error("Failed to restart recording after device change: \(error.localizedDescription)")
            }
        }
        isReconfiguring = false
    }

    func startRecording() async throws {
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

            if inputFormat.sampleRate == 0 || inputFormat.channelCount == 0 {
                throw RecordingError.couldNotStartRecording(
                    reason: "Microphone unavailable — check if laptop lid is closed or try a different input device"
                )
            }

            // Create the target format for the tap: 16kHz mono Float32
            // AVAudioEngine will handle sample rate conversion from the hardware format
            guard let tapFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: targetSampleRate,
                channels: targetChannels,
                interleaved: false
            ) else {
                throw RecordingError.couldNotStartRecording(reason: "Could not create audio format")
            }

            self.engine = engine
            audioBuffer.clear()
            tapDrainState.reset()
            activeConverter = nil
            activeTapFormat = nil

            // Install tap on input node — runs on CoreAudio realtime thread
            let buffer = self.audioBuffer
            let tapDrainState = self.tapDrainState

            // Use a converter if the input format doesn't match our target
            // This handles cases where installTap with a different format isn't supported
            let needsConversion = inputFormat.sampleRate != targetSampleRate || inputFormat.channelCount != targetChannels

            if needsConversion {
                // Install tap with native input format, convert manually
                let converter = AVAudioConverter(from: inputFormat, to: tapFormat)
                activeConverter = converter
                activeTapFormat = tapFormat

                inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: inputFormat) { [weak self] pcmBuffer, _ in
                    tapDrainState.beginCallback()
                    defer { tapDrainState.endCallback() }

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

                    // Append Float32 samples to shared buffer
                    if let channelData = convertedBuffer.floatChannelData {
                        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(convertedBuffer.frameLength)))
                        buffer.append(samples)

                        // Compute metering from the samples
                        let (avg, peak) = Self.computeMetering(samples)
                        Task { @MainActor [weak self] in
                            self?.audioMeter = AudioMeter(averagePower: avg, peakPower: peak)
                        }
                    }
                }
            } else {
                // Input already matches target format, install tap directly
                inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: tapFormat) { [weak self] pcmBuffer, _ in
                    tapDrainState.beginCallback()
                    defer { tapDrainState.endCallback() }

                    // Append Float32 samples to shared buffer
                    if let channelData = pcmBuffer.floatChannelData {
                        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(pcmBuffer.frameLength)))
                        buffer.append(samples)

                        // Compute metering from the samples
                        let (avg, peak) = Self.computeMetering(samples)
                        Task { @MainActor [weak self] in
                            self?.audioMeter = AudioMeter(averagePower: avg, peakPower: peak)
                        }
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

            logger.notice("Recording started with AVAudioEngine (buffer-only)")

        } catch let recordingError as RecordingError {
            logger.error("Recording failed: \(recordingError.localizedDescription)")
            stopRecording()
            throw recordingError
        } catch {
            logger.error("Failed to start audio engine: \(error.localizedDescription)")
            stopRecording()
            throw RecordingError.couldNotStartRecording(
                reason: "Audio engine error — try a different input device"
            )
        }
    }

    func stopRecording() {
        stopEngine()
        activeConverter = nil
        activeTapFormat = nil
        tapDrainState.reset()

        Task {
            await mediaControlService.unmuteSystemAudio()
        }
    }

    /// Stop recording and wait for in-flight tap/converter work to finish so
    /// final transcription sees the complete utterance.
    func finalizeRecording() async -> [Float] {
        let converter = activeConverter
        let tapFormat = activeTapFormat

        stopEngine()
        await tapDrainState.waitUntilDrained()

        if let converter, let tapFormat {
            flushConverterTail(converter: converter, tapFormat: tapFormat)
        }

        activeConverter = nil
        activeTapFormat = nil

        Task {
            await mediaControlService.unmuteSystemAudio()
        }

        return audioBuffer.readAll()
    }

    private func stopEngine() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        audioMeter = AudioMeter(averagePower: 0, peakPower: 0)
        isRecording = false
    }

    private func flushConverterTail(converter: AVAudioConverter, tapFormat: AVAudioFormat) {
        while true {
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: tapFormat,
                frameCapacity: tapBufferSize * 2
            ) else {
                return
            }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .endOfStream
                return nil
            }

            if let error {
                logger.error("Failed to flush converter tail: \(error.localizedDescription)")
                return
            }

            if let channelData = convertedBuffer.floatChannelData, convertedBuffer.frameLength > 0 {
                let samples = Array(
                    UnsafeBufferPointer(start: channelData[0], count: Int(convertedBuffer.frameLength))
                )
                audioBuffer.append(samples)
            }

            if status == .endOfStream || convertedBuffer.frameLength == 0 {
                return
            }
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
