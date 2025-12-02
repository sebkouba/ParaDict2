import XCTest
@testable import ParaDict

final class DictationStateMachineTests: XCTestCase {

    var sut: DictationStateMachine!

    override func setUp() {
        super.setUp()
        sut = DictationStateMachine()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialStateIsIdle() {
        XCTAssertEqual(sut.state, .idle)
    }

    // MARK: - Idle to Recording

    func testIdleToRecordingOnHotkeyDown() {
        let effects = sut.handle(.hotkeyDown(mode: .local, prompt: nil, context: nil))

        XCTAssertEqual(sut.state, .recording(mode: .local, isHandsFree: false))
        XCTAssertTrue(effects.contains(.startRecording(mode: .local, prompt: nil, context: nil)))
        XCTAssertTrue(effects.contains(.showIndicator))
        XCTAssertTrue(effects.contains(.startKeyMonitors))
    }

    func testIdleToRecordingWithPrompt() {
        let prompt = "Test prompt"
        let effects = sut.handle(.hotkeyDown(mode: .enhanced, prompt: prompt, context: nil))

        XCTAssertEqual(sut.state, .recording(mode: .enhanced, isHandsFree: false))
        XCTAssertTrue(effects.contains(.startRecording(mode: .enhanced, prompt: prompt, context: nil)))
    }

    func testIdleIgnoresOtherEvents() {
        let eventsToIgnore: [DictationEvent] = [
            .hotkeyUp(duration: 0.5),
            .enterPressed,
            .escapePressed,
            .recordingComplete(url: URL(fileURLWithPath: "/test")),
            .transcriptionComplete(text: "test"),
            .pasteComplete,
        ]

        for event in eventsToIgnore {
            sut.reset()
            let effects = sut.handle(event)

            XCTAssertEqual(sut.state, .idle, "State should remain idle for event: \(event)")
            XCTAssertTrue(effects.isEmpty, "No effects expected for event: \(event)")
        }
    }

    // MARK: - Recording: Brief Press (Hands-Free Activation)

    func testBriefPressActivatesHandsFreeMode() {
        // Start recording
        _ = sut.handle(.hotkeyDown(mode: .local, prompt: nil, context: nil))
        XCTAssertEqual(sut.state, .recording(mode: .local, isHandsFree: false))

        // Brief release (< 1 second)
        let effects = sut.handle(.hotkeyUp(duration: 0.3))

        XCTAssertEqual(sut.state, .recording(mode: .local, isHandsFree: true))
        XCTAssertTrue(effects.isEmpty, "No side effects for hands-free activation")
    }

    // MARK: - Recording: Long Press (Stop)

    func testLongPressStopsRecording() {
        // Start recording
        _ = sut.handle(.hotkeyDown(mode: .local, prompt: nil, context: nil))

        // Long release (>= 1 second)
        let effects = sut.handle(.hotkeyUp(duration: 1.5))

        if case .transcribing(let mode, _, let continueAfter) = sut.state {
            XCTAssertEqual(mode, .local)
            XCTAssertFalse(continueAfter)
        } else {
            XCTFail("Expected transcribing state, got \(sut.state)")
        }
        XCTAssertTrue(effects.contains(.stopRecording))
        XCTAssertTrue(effects.contains(.stopKeyMonitors))
    }

    // MARK: - Hands-Free: Second Press Stops

    func testSecondPressInHandsFreeModeStops() {
        // Start in hands-free mode
        _ = sut.handle(.hotkeyDown(mode: .enhanced, prompt: "test", context: nil))
        _ = sut.handle(.hotkeyUp(duration: 0.2))
        XCTAssertEqual(sut.state, .recording(mode: .enhanced, isHandsFree: true))

        // Second press
        let effects = sut.handle(.hotkeyDown(mode: .enhanced, prompt: nil, context: nil))

        if case .transcribing(let mode, _, let continueAfter) = sut.state {
            XCTAssertEqual(mode, .enhanced)
            XCTAssertFalse(continueAfter)
        } else {
            XCTFail("Expected transcribing state, got \(sut.state)")
        }
        XCTAssertTrue(effects.contains(.stopRecording))
    }

    // MARK: - Hands-Free: Enter Pressed (Submit and Continue)

    func testEnterPressedInHandsFreeModeSetsContinueAfter() {
        // Start in hands-free mode
        _ = sut.handle(.hotkeyDown(mode: .local, prompt: nil, context: nil))
        _ = sut.handle(.hotkeyUp(duration: 0.2))

        // Press Enter
        let effects = sut.handle(.enterPressed)

        if case .transcribing(let mode, _, let continueAfter) = sut.state {
            XCTAssertEqual(mode, .local)
            XCTAssertTrue(continueAfter, "continueAfter should be true when Enter pressed")
        } else {
            XCTFail("Expected transcribing state, got \(sut.state)")
        }
        XCTAssertTrue(effects.contains(.stopRecording))
    }

    func testEnterIgnoredWhenNotHandsFree() {
        // Start recording (not hands-free)
        _ = sut.handle(.hotkeyDown(mode: .local, prompt: nil, context: nil))
        XCTAssertEqual(sut.state, .recording(mode: .local, isHandsFree: false))

        // Press Enter - should be ignored
        let effects = sut.handle(.enterPressed)

        XCTAssertEqual(sut.state, .recording(mode: .local, isHandsFree: false))
        XCTAssertTrue(effects.isEmpty)
    }

    // MARK: - Escape Cancels Recording

    func testEscapeCancelsFromRecording() {
        _ = sut.handle(.hotkeyDown(mode: .local, prompt: nil, context: nil))

        let effects = sut.handle(.escapePressed)

        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(effects.contains(.cancelRecording))
        XCTAssertTrue(effects.contains(.hideIndicator))
        XCTAssertTrue(effects.contains(.stopKeyMonitors))
    }

    func testEscapeCancelsFromHandsFreeRecording() {
        _ = sut.handle(.hotkeyDown(mode: .local, prompt: nil, context: nil))
        _ = sut.handle(.hotkeyUp(duration: 0.2))

        let effects = sut.handle(.escapePressed)

        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(effects.contains(.cancelRecording))
    }

    // MARK: - Transcription Flow

    func testTranscriptionCompleteToEnhancing() {
        // Set up transcribing state for enhanced mode
        sut.setState(.transcribing(mode: .enhanced, prompt: "test prompt", continueAfter: false))

        let effects = sut.handle(.transcriptionComplete(text: "Hello world"))

        if case .enhancing(let mode, let prompt, let continueAfter) = sut.state {
            XCTAssertEqual(mode, .enhanced)
            XCTAssertEqual(prompt, "test prompt")
            XCTAssertFalse(continueAfter)
        } else {
            XCTFail("Expected enhancing state, got \(sut.state)")
        }
        XCTAssertTrue(effects.contains(.enhance(text: "Hello world", prompt: "test prompt", context: nil)))
    }

    func testTranscriptionCompleteLocalModeToPasting() {
        // Set up transcribing state for local mode (no prompt)
        sut.setState(.transcribing(mode: .local, prompt: nil, continueAfter: false))

        let effects = sut.handle(.transcriptionComplete(text: "Hello world"))

        if case .pasting(let mode, _, let continueAfter) = sut.state {
            XCTAssertEqual(mode, .local)
            XCTAssertFalse(continueAfter)
        } else {
            XCTFail("Expected pasting state, got \(sut.state)")
        }
        XCTAssertTrue(effects.contains(.paste(text: "Hello world")))
        XCTAssertTrue(effects.contains(.schedulePasteComplete))
    }

    func testEmptyTranscriptionGoesToError() {
        sut.setState(.transcribing(mode: .local, prompt: nil, continueAfter: false))

        let effects = sut.handle(.transcriptionEmpty)

        if case .error(let message) = sut.state {
            XCTAssertEqual(message, "No speech detected")
        } else {
            XCTFail("Expected error state, got \(sut.state)")
        }
        XCTAssertTrue(effects.contains(.hideIndicator))
        XCTAssertTrue(effects.contains(.scheduleErrorTimeout))
    }

    // MARK: - Enhancement Flow

    func testEnhancementCompleteToPasting() {
        sut.setState(.enhancing(mode: .enhanced, prompt: "test", continueAfter: false))

        let effects = sut.handle(.enhancementComplete(text: "Enhanced text"))

        if case .pasting(let mode, _, let continueAfter) = sut.state {
            XCTAssertEqual(mode, .enhanced)
            XCTAssertFalse(continueAfter)
        } else {
            XCTFail("Expected pasting state, got \(sut.state)")
        }
        XCTAssertTrue(effects.contains(.paste(text: "Enhanced text")))
    }

    func testEnhancementSkippedToPasting() {
        sut.setState(.enhancing(mode: .enhanced, prompt: "test", continueAfter: true))

        let effects = sut.handle(.enhancementSkipped(text: "Raw text"))

        if case .pasting(let mode, _, let continueAfter) = sut.state {
            XCTAssertEqual(mode, .enhanced)
            XCTAssertTrue(continueAfter)
        } else {
            XCTFail("Expected pasting state, got \(sut.state)")
        }
        XCTAssertTrue(effects.contains(.paste(text: "Raw text")))
    }

    // MARK: - Paste Complete

    func testPasteCompleteReturnsToIdle() {
        sut.setState(.pasting(mode: .local, prompt: nil, continueAfter: false))

        let effects = sut.handle(.pasteComplete)

        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(effects.contains(.hideIndicator))
    }

    // MARK: - Continue After Submit

    func testPasteCompleteWithContinueAfterRestartsRecording() {
        sut.setState(.pasting(mode: .enhanced, prompt: "test prompt", continueAfter: true))

        let effects = sut.handle(.pasteComplete)

        // Should restart in hands-free recording mode
        XCTAssertEqual(sut.state, .recording(mode: .enhanced, isHandsFree: true))

        // Should press Enter and restart
        XCTAssertTrue(effects.contains(.pressEnterKey))
        XCTAssertTrue(effects.contains(.startRecording(mode: .enhanced, prompt: "test prompt", context: nil)))
        XCTAssertTrue(effects.contains(.showIndicator))
        XCTAssertTrue(effects.contains(.startKeyMonitors))
    }

    func testContinueAfterPreservesThroughFlow() {
        // Start and activate hands-free
        _ = sut.handle(.hotkeyDown(mode: .local, prompt: nil, context: nil))
        _ = sut.handle(.hotkeyUp(duration: 0.2))

        // Press Enter - sets continueAfter = true
        _ = sut.handle(.enterPressed)

        // Verify continueAfter is preserved through transitions
        if case .transcribing(_, _, let continueAfter) = sut.state {
            XCTAssertTrue(continueAfter)
        } else {
            XCTFail("Expected transcribing state")
        }

        // Complete transcription (local mode - no enhancement)
        _ = sut.handle(.transcriptionComplete(text: "test"))

        if case .pasting(_, _, let continueAfter) = sut.state {
            XCTAssertTrue(continueAfter)
        } else {
            XCTFail("Expected pasting state")
        }
    }

    // MARK: - Error Handling

    func testErrorFromAnyState() {
        let states: [DictationStateSM] = [
            .recording(mode: .local, isHandsFree: false),
            .recording(mode: .local, isHandsFree: true),
            .transcribing(mode: .local, prompt: nil, continueAfter: false),
            .enhancing(mode: .enhanced, prompt: "test", continueAfter: false),
            .pasting(mode: .local, prompt: nil, continueAfter: false),
        ]

        for initialState in states {
            sut.setState(initialState)

            let effects = sut.handle(.error(message: "Test error"))

            if case .error(let message) = sut.state {
                XCTAssertEqual(message, "Test error")
            } else {
                XCTFail("Expected error state from \(initialState)")
            }
            XCTAssertTrue(effects.contains(.hideIndicator))
            XCTAssertTrue(effects.contains(.stopKeyMonitors))
            XCTAssertTrue(effects.contains(.scheduleErrorTimeout))
        }
    }

    func testErrorTimeoutReturnsToIdle() {
        sut.setState(.error(message: "Test error"))

        let effects = sut.handle(.errorTimeout)

        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(effects.isEmpty)
    }

    func testCanStartRecordingFromErrorState() {
        sut.setState(.error(message: "Previous error"))

        let effects = sut.handle(.hotkeyDown(mode: .local, prompt: nil, context: nil))

        XCTAssertEqual(sut.state, .recording(mode: .local, isHandsFree: false))
        XCTAssertTrue(effects.contains(.startRecording(mode: .local, prompt: nil, context: nil)))
    }

    // MARK: - State Properties

    func testStateIsRecordingProperty() {
        XCTAssertFalse(DictationStateSM.idle.isRecording)
        XCTAssertTrue(DictationStateSM.recording(mode: .local, isHandsFree: false).isRecording)
        XCTAssertTrue(DictationStateSM.recording(mode: .local, isHandsFree: true).isRecording)
        XCTAssertFalse(DictationStateSM.transcribing(mode: .local, prompt: nil, continueAfter: false).isRecording)
    }

    func testStateIsProcessingProperty() {
        XCTAssertFalse(DictationStateSM.idle.isProcessing)
        XCTAssertFalse(DictationStateSM.recording(mode: .local, isHandsFree: false).isProcessing)
        XCTAssertTrue(DictationStateSM.transcribing(mode: .local, prompt: nil, continueAfter: false).isProcessing)
        XCTAssertTrue(DictationStateSM.enhancing(mode: .enhanced, prompt: "test", continueAfter: false).isProcessing)
        XCTAssertTrue(DictationStateSM.pasting(mode: .local, prompt: nil, continueAfter: false).isProcessing)
        XCTAssertFalse(DictationStateSM.error(message: "test").isProcessing)
    }

    func testStateIsHandsFreeProperty() {
        XCTAssertFalse(DictationStateSM.idle.isHandsFree)
        XCTAssertFalse(DictationStateSM.recording(mode: .local, isHandsFree: false).isHandsFree)
        XCTAssertTrue(DictationStateSM.recording(mode: .local, isHandsFree: true).isHandsFree)
        XCTAssertFalse(DictationStateSM.transcribing(mode: .local, prompt: nil, continueAfter: false).isHandsFree)
    }

    func testStateShouldContinueAfterProperty() {
        XCTAssertFalse(DictationStateSM.idle.shouldContinueAfter)
        XCTAssertFalse(DictationStateSM.recording(mode: .local, isHandsFree: true).shouldContinueAfter)
        XCTAssertFalse(DictationStateSM.transcribing(mode: .local, prompt: nil, continueAfter: false).shouldContinueAfter)
        XCTAssertTrue(DictationStateSM.transcribing(mode: .local, prompt: nil, continueAfter: true).shouldContinueAfter)
        XCTAssertTrue(DictationStateSM.pasting(mode: .local, prompt: nil, continueAfter: true).shouldContinueAfter)
    }

    // MARK: - Multiple Enter Presses (Regression Test)

    func testMultipleEnterPressesWorkCorrectly() {
        // First recording session
        _ = sut.handle(.hotkeyDown(mode: .local, prompt: nil, context: nil))
        _ = sut.handle(.hotkeyUp(duration: 0.2))  // Hands-free

        // First Enter press
        _ = sut.handle(.enterPressed)
        XCTAssertTrue(sut.state.shouldContinueAfter)

        // Simulate transcription complete
        _ = sut.handle(.transcriptionComplete(text: "first message"))

        // Paste complete triggers restart
        let effects1 = sut.handle(.pasteComplete)
        XCTAssertEqual(sut.state, .recording(mode: .local, isHandsFree: true))
        XCTAssertTrue(effects1.contains(.pressEnterKey))

        // Second Enter press should also work
        let effects2 = sut.handle(.enterPressed)
        if case .transcribing(_, _, let continueAfter) = sut.state {
            XCTAssertTrue(continueAfter)
        } else {
            XCTFail("Expected transcribing state after second Enter")
        }
        XCTAssertTrue(effects2.contains(.stopRecording))
    }
}
