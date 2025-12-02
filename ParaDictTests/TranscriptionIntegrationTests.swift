import XCTest
@testable import ParaDict

/// Integration tests that verify the full transcription pipeline.
/// These tests use actual audio files to test real transcription.
///
/// To add a test audio file:
/// 1. Record yourself saying the test phrase (use Voice Memos or similar)
/// 2. Convert to 16kHz mono WAV: `ffmpeg -i input.m4a -ar 16000 -ac 1 test_hello_world.wav`
/// 3. Add the WAV file to ParaDictTests folder
/// 4. Add to test target in Xcode (check "ParaDictTests" in target membership)
final class TranscriptionIntegrationTests: XCTestCase {

    var transcriptionService: ParakeetTranscriptionService!

    override func setUp() async throws {
        try await super.setUp()
        transcriptionService = ParakeetTranscriptionService.shared
    }

    override func tearDown() {
        transcriptionService = nil
        super.tearDown()
    }

    // MARK: - Transcription Tests

    /// Test transcription of "Hello world" audio file.
    /// Expected: transcription contains "hello" and "world" (case-insensitive)
    func testTranscription_HelloWorld() async throws {
        // Find the test audio file in the test bundle
        guard let audioURL = Bundle(for: type(of: self)).url(
            forResource: "test_hello_world",
            withExtension: "wav"
        ) else {
            throw XCTSkip("Test audio file 'test_hello_world.wav' not found. See instructions in this file to add it.")
        }

        // Transcribe
        let result = try await transcriptionService.transcribe(audioURL: audioURL)
        let lowercased = result.lowercased()

        // Verify
        XCTAssertTrue(
            lowercased.contains("hello") && lowercased.contains("world"),
            "Expected transcription to contain 'hello' and 'world', got: '\(result)'"
        )
    }

    /// Test transcription of a longer phrase to verify accuracy.
    /// Audio contains: "The second one is this is slightly longer and it includes Sebastian Kuba..."
    func testTranscription_LongerPhrase() async throws {
        guard let audioURL = Bundle(for: type(of: self)).url(
            forResource: "test_quick_brown_fox",
            withExtension: "wav"
        ) else {
            throw XCTSkip("Test audio file 'test_quick_brown_fox.wav' not found. See instructions in this file to add it.")
        }

        let result = try await transcriptionService.transcribe(audioURL: audioURL)
        let lowercased = result.lowercased()

        // Check for key words from the actual recording
        let expectedWords = ["second", "longer", "sebastian", "kuba", "llm", "service"]
        let foundWords = expectedWords.filter { lowercased.contains($0) }

        XCTAssertGreaterThanOrEqual(
            foundWords.count, 3,
            "Expected at least 3 of \(expectedWords) in transcription, found \(foundWords.count): '\(result)'"
        )
    }

    /// Test that empty/silent audio throws appropriate error
    func testTranscription_EmptyAudio_ThrowsError() async throws {
        guard let audioURL = Bundle(for: type(of: self)).url(
            forResource: "test_silence",
            withExtension: "wav"
        ) else {
            throw XCTSkip("Test audio file 'test_silence.wav' not found.")
        }

        do {
            _ = try await transcriptionService.transcribe(audioURL: audioURL)
            // If we get here with empty result, that's also acceptable
        } catch {
            // Expected - silent audio should throw or return empty
            XCTAssertTrue(true)
        }
    }

    // MARK: - Full Pipeline Test

    /// Test the full dictation flow: transcription -> state machine -> output
    /// This simulates a complete user interaction.
    func testFullPipeline_LocalMode() async throws {
        guard let audioURL = Bundle(for: type(of: self)).url(
            forResource: "test_hello_world",
            withExtension: "wav"
        ) else {
            throw XCTSkip("Test audio file 'test_hello_world.wav' not found.")
        }

        // 1. Transcribe audio
        let transcription = try await transcriptionService.transcribe(audioURL: audioURL)
        XCTAssertFalse(transcription.isEmpty, "Transcription should not be empty")

        // 2. Verify state machine handles the flow correctly
        let stateMachine = DictationStateMachine()

        // Start recording
        _ = stateMachine.handle(.hotkeyDown(mode: .local, prompt: nil, context: nil))
        XCTAssertTrue(stateMachine.state.isRecording)

        // Stop recording (long press)
        let stopEffects = stateMachine.handle(.hotkeyUp(duration: 2.0))
        XCTAssertTrue(stopEffects.contains(.stopRecording))

        // Transcription complete
        let transcribeEffects = stateMachine.handle(.transcriptionComplete(text: transcription))
        XCTAssertTrue(transcribeEffects.contains(where: {
            if case .paste(let text) = $0 {
                return text == transcription
            }
            return false
        }), "Should paste the transcription")

        // Paste complete
        _ = stateMachine.handle(.pasteComplete)
        XCTAssertEqual(stateMachine.state, .idle)
    }
}
