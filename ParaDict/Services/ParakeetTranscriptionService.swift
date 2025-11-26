import Foundation
import CoreML
import AVFoundation
import FluidAudio
import os

enum ASRError: LocalizedError {
    case notInitialized
    case invalidAudioData
    case transcriptionFailed(String)
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "ASR Manager not initialized"
        case .invalidAudioData:
            return "Invalid audio data"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .emptyAudio:
            return "Audio contains no speech"
        }
    }
}

class ParakeetTranscriptionService {
    static let shared = ParakeetTranscriptionService()

    private var asrManager: AsrManager?
    private var vadManager: VadManager?
    private let logger = Logger(subsystem: "com.paradict", category: "ParakeetTranscriptionService")

    private init() {
        logger.notice("ParakeetTranscriptionService initialized")
    }

    private func ensureModelsLoaded() async throws {
        if asrManager != nil {
            logger.notice("ASR models already loaded")
            return
        }

        logger.notice("Loading Parakeet v3 models...")
        let manager = AsrManager(config: .default)
        let models = try await AsrModels.loadFromCache(
            configuration: nil,
            version: .v3
        )
        try await manager.initialize(models: models)
        self.asrManager = manager
        logger.notice("Parakeet v3 models loaded successfully")
    }

    func transcribe(audioURL: URL) async throws -> String {
        logger.notice("transcribe called with URL: \(audioURL.path)")

        // Check file exists
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            logger.error("Audio file does not exist: \(audioURL.path)")
            throw ASRError.invalidAudioData
        }

        // Get file size
        if let attrs = try? FileManager.default.attributesOfItem(atPath: audioURL.path),
           let size = attrs[.size] as? Int64 {
            logger.notice("Audio file size: \(size) bytes")
        }

        try await ensureModelsLoaded()

        guard let asrManager = asrManager else {
            logger.error("ASR Manager is nil after loading")
            throw ASRError.notInitialized
        }

        let audioSamples = try readAudioSamples(from: audioURL)
        logger.notice("Read \(audioSamples.count) audio samples")

        if audioSamples.isEmpty {
            logger.error("No audio samples read from file")
            throw ASRError.emptyAudio
        }

        // Check audio levels
        let maxSample = audioSamples.max() ?? 0
        let minSample = audioSamples.min() ?? 0
        let avgAbsSample = audioSamples.reduce(0) { $0 + abs($1) } / Float(audioSamples.count)
        logger.notice("Audio stats - min: \(minSample), max: \(maxSample), avgAbs: \(avgAbsSample)")

        if avgAbsSample < 0.001 {
            logger.warning("Audio appears to be silent (avgAbs < 0.001)")
        }

        let durationSeconds = Double(audioSamples.count) / 16000.0
        logger.notice("Transcribing audio: \(String(format: "%.1f", durationSeconds))s (\(audioSamples.count) samples)")

        var speechAudio = audioSamples

        // Use VAD for longer audio (>20s)
        if durationSeconds >= 20.0 {
            logger.notice("Audio > 20s, using VAD")
            let vadConfig = VadConfig(defaultThreshold: 0.7)
            if vadManager == nil {
                do {
                    vadManager = try await VadManager(config: vadConfig)
                    logger.notice("VAD initialized")
                } catch {
                    logger.notice("VAD init failed; using full audio: \(error.localizedDescription)")
                }
            }

            if let vadManager {
                do {
                    let segments = try await vadManager.segmentSpeechAudio(audioSamples)
                    logger.notice("VAD found \(segments.count) speech segments")
                    speechAudio = segments.isEmpty ? audioSamples : segments.flatMap { $0 }
                } catch {
                    logger.notice("VAD segmentation failed; using full audio: \(error.localizedDescription)")
                }
            }
        }

        logger.notice("Starting ASR transcription with \(speechAudio.count) samples...")
        let result = try await asrManager.transcribe(speechAudio)
        logger.notice("ASR result - text length: \(result.text.count), text: '\(result.text.prefix(200))'")

        return result.text
    }

    private func readAudioSamples(from url: URL) throws -> [Float] {
        logger.notice("Reading audio samples from: \(url.lastPathComponent)")

        let data = try Data(contentsOf: url)
        logger.notice("Read \(data.count) bytes from file")

        guard data.count > 44 else {
            logger.error("File too small - only \(data.count) bytes (need > 44 for WAV header)")
            throw ASRError.invalidAudioData
        }

        // Log WAV header info
        let headerBytes = [UInt8](data.prefix(44))
        let riff = String(bytes: headerBytes[0..<4], encoding: .ascii) ?? "?"
        let wave = String(bytes: headerBytes[8..<12], encoding: .ascii) ?? "?"
        logger.notice("WAV header - RIFF: '\(riff)', WAVE: '\(wave)'")

        // Extract format info from WAV header
        let audioFormat = UInt16(headerBytes[20]) | (UInt16(headerBytes[21]) << 8)
        let numChannels = UInt16(headerBytes[22]) | (UInt16(headerBytes[23]) << 8)
        let sampleRate = UInt32(headerBytes[24]) | (UInt32(headerBytes[25]) << 8) | (UInt32(headerBytes[26]) << 16) | (UInt32(headerBytes[27]) << 24)
        let bitsPerSample = UInt16(headerBytes[34]) | (UInt16(headerBytes[35]) << 8)

        logger.notice("WAV format - audioFormat: \(audioFormat), channels: \(numChannels), sampleRate: \(sampleRate), bitsPerSample: \(bitsPerSample)")

        // Skip WAV header (44 bytes) and convert 16-bit PCM to float
        let floats = stride(from: 44, to: data.count, by: 2).map {
            return data[$0..<$0 + 2].withUnsafeBytes {
                let short = Int16(littleEndian: $0.load(as: Int16.self))
                return max(-1.0, min(Float(short) / 32767.0, 1.0))
            }
        }

        logger.notice("Converted to \(floats.count) float samples")
        return floats
    }

    func cleanup() {
        logger.notice("Cleaning up ASR resources")
        asrManager?.cleanup()
        asrManager = nil
        vadManager = nil
    }
}
