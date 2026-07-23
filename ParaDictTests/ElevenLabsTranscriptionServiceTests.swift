import XCTest
@testable import ParaDict

final class ElevenLabsTranscriptionServiceTests: XCTestCase {
    @MainActor
    func testScribeV2RequestUsesSynchronousAutomaticLanguageDetection() {
        let body = ElevenLabsTranscriptionService.transcriptionBodyForTesting(
            audioSamples: [0, 0.25, -0.25]
        )

        XCTAssertTrue(body.containsUTF8("name=\"model_id\"\r\n\r\nscribe_v2"))
        XCTAssertTrue(body.containsUTF8("name=\"webhook\"\r\n\r\nfalse"))
        XCTAssertTrue(body.containsUTF8("name=\"file\"; filename=\"dictation.wav\""))
        XCTAssertTrue(body.containsUTF8("Content-Type: audio/wav"))
        XCTAssertFalse(body.containsUTF8("language_code"))
    }

    func testProviderMetadataIncludesElevenLabs() {
        XCTAssertTrue(TranscriptionProvider.allCases.contains(.elevenLabs))
        XCTAssertEqual(TranscriptionProvider.elevenLabs.rawValue, "elevenLabs")
        XCTAssertEqual(TranscriptionProvider.elevenLabs.displayName, "ElevenLabs")
    }
}

private extension Data {
    func containsUTF8(_ string: String) -> Bool {
        range(of: Data(string.utf8)) != nil
    }
}
