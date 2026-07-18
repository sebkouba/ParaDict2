import Foundation
import AVFoundation
import CoreAudio
import Combine
import os

struct AudioMeter: Equatable {
    let averagePower: Double
    let peakPower: Double
}

private final class RecordingCaptureSession: @unchecked Sendable {
    let generation: UInt64

    private let lock = NSLock()
    private var inFlightCallbacks = 0
    private var acceptsCallbacks = true
    private var drainContinuation: CheckedContinuation<Void, Never>?
    private var callbackCount = 0
    private var inputFrameCount = 0
    private var outputFrameCount = 0
    private var conversionFailureCount = 0
    private var lastMeterPublishUptime: UInt64 = 0

    init(generation: UInt64) {
        self.generation = generation
    }

    func beginCallback(inputFrames: Int) -> Bool {
        lock.lock()
        guard acceptsCallbacks else {
            lock.unlock()
            return false
        }
        inFlightCallbacks += 1
        callbackCount += 1
        inputFrameCount += inputFrames
        lock.unlock()
        return true
    }

    func endCallback(outputFrames: Int, conversionFailed: Bool = false) {
        var continuation: CheckedContinuation<Void, Never>?

        lock.lock()
        outputFrameCount += outputFrames
        if conversionFailed {
            conversionFailureCount += 1
        }
        inFlightCallbacks = max(0, inFlightCallbacks - 1)
        if !acceptsCallbacks && inFlightCallbacks == 0 {
            continuation = drainContinuation
            drainContinuation = nil
        }
        lock.unlock()

        continuation?.resume()
    }

    func close() {
        var continuation: CheckedContinuation<Void, Never>?

        lock.lock()
        acceptsCallbacks = false
        if inFlightCallbacks == 0 {
            continuation = drainContinuation
            drainContinuation = nil
        }
        lock.unlock()

        continuation?.resume()
    }

    func waitUntilDrained() async {
        if isDrained() {
            return
        }

        await withCheckedContinuation { continuation in
            if !installDrainContinuation(continuation) {
                continuation.resume()
            }
        }
    }

    private func isDrained() -> Bool {
        lock.lock()
        let result = !acceptsCallbacks && inFlightCallbacks == 0
        lock.unlock()
        return result
    }

    private func installDrainContinuation(_ continuation: CheckedContinuation<Void, Never>) -> Bool {
        lock.lock()
        guard acceptsCallbacks || inFlightCallbacks > 0 else {
            lock.unlock()
            return false
        }
        drainContinuation = continuation
        lock.unlock()
        return true
    }

    func metrics() -> (callbacks: Int, inputFrames: Int, outputFrames: Int, conversionFailures: Int) {
        lock.lock()
        let result = (callbackCount, inputFrameCount, outputFrameCount, conversionFailureCount)
        lock.unlock()
        return result
    }

    /// Cap UI hops from fast hardware callbacks at 20 updates per second.
    func shouldPublishMeter() -> Bool {
        let now = DispatchTime.now().uptimeNanoseconds
        let minimumInterval: UInt64 = 50_000_000

        lock.lock()
        guard lastMeterPublishUptime == 0 || now - lastMeterPublishUptime >= minimumInterval else {
            lock.unlock()
            return false
        }
        lastMeterPublishUptime = now
        lock.unlock()
        return true
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
    private var isFinalizing = false
    private var captureSession: RecordingCaptureSession?
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
    /// Keep capturing beyond hotkey release so Core Audio emits the partially filled final tap buffer.
    private let stopPostRollNanoseconds: UInt64 = 220_000_000

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
        guard !isReconfiguring, !isFinalizing else { return }
        isReconfiguring = true

        if engine != nil {
            await stopForDeviceReconfiguration()

            do {
                try await startRecording(clearExistingAudio: false)
            } catch {
                logger.error("Failed to restart recording after device change: \(error.localizedDescription)")
            }
        }
        isReconfiguring = false
    }

    func startRecording() async throws {
        try await startRecording(clearExistingAudio: true)
    }

    private func startRecording(clearExistingAudio: Bool) async throws {
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
            let generation = audioBuffer.beginSession(clearExisting: clearExistingAudio)
            let captureSession = RecordingCaptureSession(generation: generation)
            self.captureSession = captureSession
            activeConverter = nil
            activeTapFormat = nil

            // Install tap on input node — runs on CoreAudio realtime thread
            let buffer = self.audioBuffer

            // Use a converter if the input format doesn't match our target
            // This handles cases where installTap with a different format isn't supported
            let needsConversion = inputFormat.sampleRate != targetSampleRate || inputFormat.channelCount != targetChannels

            if needsConversion {
                // Install tap with native input format, convert manually
                guard let converter = AVAudioConverter(from: inputFormat, to: tapFormat) else {
                    throw RecordingError.couldNotStartRecording(
                        reason: "Could not create an audio converter for the selected microphone"
                    )
                }
                activeConverter = converter
                activeTapFormat = tapFormat

                inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: inputFormat) { [weak self] pcmBuffer, _ in
                    guard captureSession.beginCallback(inputFrames: Int(pcmBuffer.frameLength)) else {
                        return
                    }
                    var outputFrames = 0
                    var conversionFailed = false
                    defer {
                        captureSession.endCallback(
                            outputFrames: outputFrames,
                            conversionFailed: conversionFailed
                        )
                    }

                    // Convert to 16kHz mono
                    let frameCapacity = AVAudioFrameCount(
                        ceil(Double(pcmBuffer.frameLength) * (tapFormat.sampleRate / inputFormat.sampleRate))
                    ) + 32
                    guard let convertedBuffer = AVAudioPCMBuffer(
                        pcmFormat: tapFormat,
                        frameCapacity: frameCapacity
                    ) else {
                        conversionFailed = true
                        return
                    }

                    var error: NSError?
                    var suppliedInput = false
                    let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                        guard !suppliedInput else {
                            outStatus.pointee = .noDataNow
                            return nil
                        }
                        suppliedInput = true
                        outStatus.pointee = .haveData
                        return pcmBuffer
                    }

                    guard status != .error, error == nil else {
                        conversionFailed = true
                        return
                    }

                    // Append Float32 samples to shared buffer
                    if let channelData = convertedBuffer.floatChannelData {
                        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(convertedBuffer.frameLength)))
                        outputFrames = samples.count
                        guard buffer.append(samples, generation: captureSession.generation) else {
                            return
                        }

                        if captureSession.shouldPublishMeter() {
                            let (avg, peak) = Self.computeMetering(samples)
                            Task { @MainActor [weak self] in
                                self?.audioMeter = AudioMeter(averagePower: avg, peakPower: peak)
                            }
                        }
                    }
                }
            } else {
                // Input already matches target format, install tap directly
                inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: tapFormat) { [weak self] pcmBuffer, _ in
                    guard captureSession.beginCallback(inputFrames: Int(pcmBuffer.frameLength)) else {
                        return
                    }
                    var outputFrames = 0
                    defer { captureSession.endCallback(outputFrames: outputFrames) }

                    // Append Float32 samples to shared buffer
                    if let channelData = pcmBuffer.floatChannelData {
                        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(pcmBuffer.frameLength)))
                        outputFrames = samples.count
                        guard buffer.append(samples, generation: captureSession.generation) else {
                            return
                        }

                        if captureSession.shouldPublishMeter() {
                            let (avg, peak) = Self.computeMetering(samples)
                            Task { @MainActor [weak self] in
                                self?.audioMeter = AudioMeter(averagePower: avg, peakPower: peak)
                            }
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
        let session = captureSession
        stopEngine(session: session)
        captureSession = nil
        activeConverter = nil
        activeTapFormat = nil

        Task {
            await mediaControlService.unmuteSystemAudio()
        }
    }

    /// Stop recording and wait for in-flight tap/converter work to finish so
    /// final transcription sees the complete utterance.
    func finalizeRecording() async -> [Float] {
        guard let session = captureSession else {
            stopEngine(session: nil)
            await mediaControlService.unmuteSystemAudio()
            return audioBuffer.readAll()
        }

        isFinalizing = true
        defer { isFinalizing = false }

        let callbacksAtStopRequest = session.metrics().callbacks

        // A tap only emits complete buffers. Keep the engine alive long enough for the
        // buffer containing hotkey release (and therefore the final syllable) to be delivered.
        try? await Task.sleep(nanoseconds: stopPostRollNanoseconds)

        let converter = activeConverter
        let tapFormat = activeTapFormat

        stopEngine(session: session)
        await session.waitUntilDrained()

        if let converter, let tapFormat {
            flushConverterTail(
                converter: converter,
                tapFormat: tapFormat,
                generation: session.generation
            )
        }

        let metrics = session.metrics()
        let postRollCallbacks = max(0, metrics.callbacks - callbacksAtStopRequest)
        let finalSamples = audioBuffer.readAll()
        logger.notice(
            "Capture finalized: callbacks=\(metrics.callbacks), postRollCallbacks=\(postRollCallbacks), inputFrames=\(metrics.inputFrames), convertedFrames=\(metrics.outputFrames), conversionFailures=\(metrics.conversionFailures), finalSamples=\(finalSamples.count)"
        )

        captureSession = nil
        activeConverter = nil
        activeTapFormat = nil

        await mediaControlService.unmuteSystemAudio()

        return finalSamples
    }

    private func stopForDeviceReconfiguration() async {
        guard let session = captureSession else { return }
        let converter = activeConverter
        let tapFormat = activeTapFormat

        stopEngine(session: session)
        await session.waitUntilDrained()

        if let converter, let tapFormat {
            flushConverterTail(
                converter: converter,
                tapFormat: tapFormat,
                generation: session.generation
            )
        }

        captureSession = nil
        activeConverter = nil
        activeTapFormat = nil
    }

    private func stopEngine(session: RecordingCaptureSession?) {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        session?.close()
        engine = nil
        audioMeter = AudioMeter(averagePower: 0, peakPower: 0)
        isRecording = false
    }

    private func flushConverterTail(
        converter: AVAudioConverter,
        tapFormat: AVAudioFormat,
        generation: UInt64
    ) {
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
                _ = audioBuffer.append(samples, generation: generation)
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
