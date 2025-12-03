import AVFoundation
import os

/// Converts audio files to 16kHz mono WAV format required by Parakeet using native AVFoundation
class AudioConverterService {
    static let shared = AudioConverterService()

    private let logger = Logger(subsystem: "com.paradict", category: "AudioConverter")

    enum AudioConverterError: LocalizedError {
        case invalidAudioFile
        case conversionFailed(String)
        case inputFileNotFound

        var errorDescription: String? {
            switch self {
            case .invalidAudioFile:
                return "Could not read audio file"
            case .conversionFailed(let message):
                return "Audio conversion failed: \(message)"
            case .inputFileNotFound:
                return "Input audio file not found"
            }
        }
    }

    private init() {}

    /// Convert any audio file to 16kHz mono WAV using native AVFoundation
    /// - Parameter inputURL: URL of the input audio file (mp3, m4a, wav, etc.)
    /// - Returns: URL of the converted WAV file in temp directory
    func convertToWAV(inputURL: URL) async throws -> URL {
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw AudioConverterError.inputFileNotFound
        }

        logger.notice("Converting \(inputURL.lastPathComponent) to WAV (native)...")

        // Run heavy conversion work on background thread to avoid blocking UI
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [logger] in
                do {
                    let result = try self.performConversion(inputURL: inputURL, logger: logger)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Synchronous conversion work - runs on background thread
    private func performConversion(inputURL: URL, logger: Logger) throws -> URL {
        // 1. Read input with AVAudioFile (handles mp3, m4a, wav, aac, etc.)
        guard let audioFile = try? AVAudioFile(forReading: inputURL) else {
            throw AudioConverterError.invalidAudioFile
        }
        let inputFormat = audioFile.processingFormat

        logger.notice("Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch")

        // 2. Define target format: 16kHz mono 16-bit PCM
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000.0,
            channels: 1,
            interleaved: true
        ) else {
            throw AudioConverterError.conversionFailed("Could not create target format")
        }

        // 3. Create converter
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioConverterError.conversionFailed("Could not create audio converter")
        }

        // 4. Read input buffer
        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: AVAudioFrameCount(audioFile.length)
        ) else {
            throw AudioConverterError.conversionFailed("Could not create input buffer")
        }
        try audioFile.read(into: inputBuffer)

        // 5. Calculate output size and create buffer
        let ratio = 16000.0 / inputFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCount
        ) else {
            throw AudioConverterError.conversionFailed("Could not create output buffer")
        }

        // 6. Convert
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if let error = error {
            throw AudioConverterError.conversionFailed(error.localizedDescription)
        }

        if status == .error {
            throw AudioConverterError.conversionFailed("Conversion returned error status")
        }

        // 7. Write to temp WAV file
        let tempDir = FileManager.default.temporaryDirectory
        let outputFilename = inputURL.deletingPathExtension().lastPathComponent + "_converted.wav"
        let outputURL = tempDir.appendingPathComponent(outputFilename)

        try? FileManager.default.removeItem(at: outputURL)

        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: targetFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        try outputFile.write(from: outputBuffer)

        logger.notice("Conversion complete: \(outputURL.lastPathComponent)")
        return outputURL
    }

    /// Check if a file is already a 16kHz mono WAV
    func isCompatibleWAV(url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "wav" else { return false }

        // Read WAV header to check format
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              data.count > 44 else { return false }

        let headerBytes = [UInt8](data.prefix(44))

        // Check RIFF header
        guard String(bytes: headerBytes[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: headerBytes[8..<12], encoding: .ascii) == "WAVE" else {
            return false
        }

        // Parse format info
        let numChannels = UInt16(headerBytes[22]) | (UInt16(headerBytes[23]) << 8)
        let sampleRate = UInt32(headerBytes[24]) | (UInt32(headerBytes[25]) << 8) |
                        (UInt32(headerBytes[26]) << 16) | (UInt32(headerBytes[27]) << 24)
        let bitsPerSample = UInt16(headerBytes[34]) | (UInt16(headerBytes[35]) << 8)

        // Check if compatible: 16kHz, mono, 16-bit
        let compatible = sampleRate == 16000 && numChannels == 1 && bitsPerSample == 16

        if !compatible {
            logger.notice("WAV not compatible: \(sampleRate)Hz, \(numChannels)ch, \(bitsPerSample)bit")
        }

        return compatible
    }

    /// Clean up a temporary converted file
    func cleanupTempFile(_ url: URL) {
        if url.path.contains("_converted.wav") {
            try? FileManager.default.removeItem(at: url)
            logger.notice("Cleaned up temp file: \(url.lastPathComponent)")
        }
    }
}
