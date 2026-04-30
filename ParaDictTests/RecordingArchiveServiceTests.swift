import XCTest
@testable import ParaDict

final class RecordingArchiveServiceTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordingArchiveServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testArchiveWritesWAVAndJSONSidecar() async throws {
        let service = RecordingArchiveService()
        let recordedAt = Date(timeIntervalSince1970: 1_775_000_000)

        try await service.archive(
            audioSamples: [0, 0.25, -0.25, 1],
            recordedAt: recordedAt,
            mode: .enhanced,
            transcriptionProvider: .parakeet,
            rawTranscription: "raw text",
            enhancedText: "enhanced text",
            targetApp: "com.example.App",
            directory: temporaryDirectory,
            retentionDays: 30
        )

        let archiveDirectories = try FileManager.default.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        let dayDirectory = try XCTUnwrap(archiveDirectories.first)
        let files = try FileManager.default.contentsOfDirectory(at: dayDirectory, includingPropertiesForKeys: nil)
        let wavURL = try XCTUnwrap(files.first { $0.pathExtension == "wav" })
        let jsonURL = try XCTUnwrap(files.first { $0.pathExtension == "json" })

        let wavData = try Data(contentsOf: wavURL)
        XCTAssertEqual(String(data: wavData.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: Data(wavData[8..<12]), encoding: .ascii), "WAVE")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadata = try decoder.decode(RecordingArchiveService.Metadata.self, from: Data(contentsOf: jsonURL))

        XCTAssertEqual(metadata.audioFile, wavURL.lastPathComponent)
        XCTAssertEqual(metadata.mode, "enhanced")
        XCTAssertEqual(metadata.transcriptionProvider, "parakeet")
        XCTAssertEqual(metadata.rawTranscription, "raw text")
        XCTAssertEqual(metadata.enhancedText, "enhanced text")
        XCTAssertEqual(metadata.targetApp, "com.example.App")
        XCTAssertEqual(metadata.sampleRate, 16_000)
        XCTAssertEqual(metadata.channels, 1)
        XCTAssertEqual(metadata.durationSeconds, 4.0 / 16_000.0, accuracy: 0.0001)
    }

}
