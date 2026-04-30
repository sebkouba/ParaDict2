import Foundation
import os

final class RecordingArchiveService {
    static let shared = RecordingArchiveService()

    struct Metadata: Codable, Equatable {
        let id: String
        let recordedAt: Date
        let durationSeconds: Double
        let sampleRate: Int
        let channels: Int
        let mode: String
        let transcriptionProvider: String
        let rawTranscription: String?
        let enhancedText: String?
        let targetApp: String?
        let audioFile: String
    }

    private let logger = Logger(subsystem: "com.paradict", category: "RecordingArchiveService")
    private let fileManager: FileManager
    private let calendar: Calendar
    private let sampleRate = 16_000

    init(fileManager: FileManager = .default, calendar: Calendar = .current) {
        self.fileManager = fileManager
        self.calendar = calendar
    }

    func archive(
        audioSamples: [Float],
        recordedAt: Date,
        mode: DictationMode,
        transcriptionProvider: TranscriptionProvider,
        rawTranscription: String?,
        enhancedText: String?,
        targetApp: String?
    ) async {
        guard !audioSamples.isEmpty else { return }

        let settings = await MainActor.run {
            (
                enabled: AppSettings.shared.recordingArchiveEnabled,
                directory: AppSettings.shared.recordingArchiveDirectory,
                retentionDays: AppSettings.shared.recordingArchiveRetentionDays
            )
        }

        guard settings.enabled, !settings.directory.isEmpty else { return }

        let directory = URL(fileURLWithPath: settings.directory, isDirectory: true)

        do {
            try await archive(
                audioSamples: audioSamples,
                recordedAt: recordedAt,
                mode: mode,
                transcriptionProvider: transcriptionProvider,
                rawTranscription: rawTranscription,
                enhancedText: enhancedText,
                targetApp: targetApp,
                directory: directory,
                retentionDays: settings.retentionDays
            )
        } catch {
            logger.error("Failed to archive recording: \(error.localizedDescription)")
        }
    }

    func archive(
        audioSamples: [Float],
        recordedAt: Date,
        mode: DictationMode,
        transcriptionProvider: TranscriptionProvider,
        rawTranscription: String?,
        enhancedText: String?,
        targetApp: String?,
        directory: URL,
        retentionDays: Int
    ) async throws {
        try writeArchive(
            audioSamples: audioSamples,
            recordedAt: recordedAt,
            mode: mode,
            transcriptionProvider: transcriptionProvider,
            rawTranscription: rawTranscription,
            enhancedText: enhancedText,
            targetApp: targetApp,
            directory: directory,
            retentionDays: retentionDays
        )
    }

    private func writeArchive(
        audioSamples: [Float],
        recordedAt: Date,
        mode: DictationMode,
        transcriptionProvider: TranscriptionProvider,
        rawTranscription: String?,
        enhancedText: String?,
        targetApp: String?,
        directory: URL,
        retentionDays: Int
    ) throws {
        let dayDirectory = directory.appendingPathComponent(Self.dayFormatter.string(from: recordedAt), isDirectory: true)
        try fileManager.createDirectory(at: dayDirectory, withIntermediateDirectories: true)

        let baseName = Self.fileFormatter.string(from: recordedAt)
        let audioURL = uniqueURL(in: dayDirectory, baseName: baseName, extension: "wav")
        let metadataURL = audioURL.deletingPathExtension().appendingPathExtension("json")

        try Self.wavData(from: audioSamples, sampleRate: sampleRate).write(to: audioURL, options: .atomic)

        let metadata = Metadata(
            id: audioURL.deletingPathExtension().lastPathComponent,
            recordedAt: recordedAt,
            durationSeconds: Double(audioSamples.count) / Double(sampleRate),
            sampleRate: sampleRate,
            channels: 1,
            mode: mode.rawValue,
            transcriptionProvider: transcriptionProvider.rawValue,
            rawTranscription: rawTranscription,
            enhancedText: enhancedText,
            targetApp: targetApp,
            audioFile: audioURL.lastPathComponent
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(metadata).write(to: metadataURL, options: .atomic)

        try cleanupExpiredRecordings(in: directory, retentionDays: retentionDays, now: Date())
        logger.notice("Archived recording to \(audioURL.path)")
    }

    private func uniqueURL(in directory: URL, baseName: String, extension pathExtension: String) -> URL {
        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension(pathExtension)
        var suffix = 2

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(suffix)").appendingPathExtension(pathExtension)
            suffix += 1
        }

        return candidate
    }

    func cleanupExpiredRecordings(in directory: URL, retentionDays: Int, now: Date = Date()) throws {
        let cutoff = now.addingTimeInterval(-Double(max(1, min(retentionDays, 999))) * 86_400)
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        var expiredFiles: [URL] = []

        for case let fileURL as URL in enumerator {
            guard ["wav", "json"].contains(fileURL.pathExtension.lowercased()) else { continue }
            let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true, let modifiedAt = values.contentModificationDate else { continue }
            if modifiedAt < cutoff {
                expiredFiles.append(fileURL)
            }
        }

        for fileURL in expiredFiles {
            try fileManager.removeItem(at: fileURL)
        }
    }

    static func wavData(from samples: [Float], sampleRate: Int) -> Data {
        let bytesPerSample = 2
        let dataSize = samples.count * bytesPerSample
        let fileSize = 36 + dataSize
        var data = Data()
        data.reserveCapacity(44 + dataSize)

        data.appendASCII("RIFF")
        data.appendUInt32LE(UInt32(fileSize))
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendUInt32LE(16)
        data.appendUInt16LE(1)
        data.appendUInt16LE(1)
        data.appendUInt32LE(UInt32(sampleRate))
        data.appendUInt32LE(UInt32(sampleRate * bytesPerSample))
        data.appendUInt16LE(UInt16(bytesPerSample))
        data.appendUInt16LE(16)
        data.appendASCII("data")
        data.appendUInt32LE(UInt32(dataSize))

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let intSample = Int16(clamped * Float(Int16.max))
            data.appendUInt16LE(UInt16(bitPattern: intSample))
        }

        return data
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let fileFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(string.data(using: .ascii)!)
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<UInt16>.size))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<UInt32>.size))
    }
}
