import XCTest
@testable import ParaDict

final class StreamingTranscriptionServiceTests: XCTestCase {
    func testRollingWindowAppendsOnlyWordsAfterOverlap() {
        let merged = StreamingTranscriptionService.mergeRollingWindow(
            previous: "We should ship this today",
            currentWindow: "this today and notify everyone"
        )

        XCTAssertEqual(merged, "We should ship this today and notify everyone")
    }

    func testRollingWindowMatchesOverlapIgnoringCaseAndPunctuation() {
        let merged = StreamingTranscriptionService.mergeRollingWindow(
            previous: "Please send it Today.",
            currentWindow: "IT today and archive it"
        )

        XCTAssertEqual(merged, "Please send it Today. and archive it")
    }

    func testRollingWindowKeepsPreviousTextWhenRecognitionHasNoReliableOverlap() {
        let merged = StreamingTranscriptionService.mergeRollingWindow(
            previous: "Keep this stable",
            currentWindow: "unrelated recognition result"
        )

        XCTAssertEqual(merged, "Keep this stable")
    }

    func testRollingWindowDoesNotDuplicateAWindowAlreadyInPreview() {
        let merged = StreamingTranscriptionService.mergeRollingWindow(
            previous: "One two three four",
            currentWindow: "three four"
        )

        XCTAssertEqual(merged, "One two three four")
    }
}
