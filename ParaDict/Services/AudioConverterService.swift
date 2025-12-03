import Foundation
import os

/// Converts audio files to 16kHz mono WAV format required by Parakeet
class AudioConverterService {
    static let shared = AudioConverterService()

    private let logger = Logger(subsystem: "com.paradict", category: "AudioConverter")

    enum AudioConverterError: LocalizedError {
        case ffmpegNotFound
        case conversionFailed(String)
        case inputFileNotFound

        var errorDescription: String? {
            switch self {
            case .ffmpegNotFound:
                return "ffmpeg not found. Please install ffmpeg via Homebrew: brew install ffmpeg"
            case .conversionFailed(let message):
                return "Audio conversion failed: \(message)"
            case .inputFileNotFound:
                return "Input audio file not found"
            }
        }
    }

    private init() {}

    /// Convert an audio file to 16kHz mono WAV format
    /// - Parameter inputURL: URL of the input audio file
    /// - Returns: URL of the converted WAV file in temp directory
    func convertToWAV(inputURL: URL) async throws -> URL {
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw AudioConverterError.inputFileNotFound
        }

        // Check if ffmpeg is available
        let ffmpegPath = try await findFFmpeg()

        // Create temp output file
        let tempDir = FileManager.default.temporaryDirectory
        let outputFilename = inputURL.deletingPathExtension().lastPathComponent + "_converted.wav"
        let outputURL = tempDir.appendingPathComponent(outputFilename)

        // Remove existing temp file if any
        try? FileManager.default.removeItem(at: outputURL)

        logger.notice("Converting \(inputURL.lastPathComponent) to WAV...")

        // Run ffmpeg conversion: 16kHz, mono, 16-bit PCM WAV
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-y",                    // Overwrite output
            "-i", inputURL.path,     // Input file
            "-ar", "16000",          // Sample rate: 16kHz
            "-ac", "1",              // Channels: mono
            "-acodec", "pcm_s16le",  // Codec: 16-bit PCM little-endian
            "-f", "wav",             // Format: WAV
            outputURL.path           // Output file
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            logger.error("ffmpeg conversion failed: \(errorString)")
            throw AudioConverterError.conversionFailed(errorString)
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw AudioConverterError.conversionFailed("Output file was not created")
        }

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

    /// Find ffmpeg executable
    private func findFFmpeg() async throws -> String {
        // Common locations for ffmpeg
        let possiblePaths = [
            "/opt/homebrew/bin/ffmpeg",  // Apple Silicon Homebrew
            "/usr/local/bin/ffmpeg",     // Intel Homebrew
            "/usr/bin/ffmpeg",           // System
            "/opt/local/bin/ffmpeg"      // MacPorts
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Try which command as fallback
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ffmpeg"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        }

        throw AudioConverterError.ffmpegNotFound
    }

    /// Clean up a temporary converted file
    func cleanupTempFile(_ url: URL) {
        if url.path.contains("_converted.wav") {
            try? FileManager.default.removeItem(at: url)
            logger.notice("Cleaned up temp file: \(url.lastPathComponent)")
        }
    }
}
