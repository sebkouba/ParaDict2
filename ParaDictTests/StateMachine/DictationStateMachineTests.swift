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

        XCTAssertEqual(sut.state, .recording(mode: .local, prompt: nil, isHandsFree: false, enterMonitorPending: false))
        XCTAssertTrue(effects.contains(.startRecording(mode: .local, prompt: nil, context: nil)))
        XCTAssertTrue(effects.contains(.showIndicator))
        XCTAssertTrue(effects.contains(.startEscapeMonitor))
        XCTAssertTrue(effects.contains(.startEnterMonitor))
    }

    func testIdleToRecordingWithPrompt() {
        let prompt = "Test prompt"
        let effects = sut.handle(.hotkeyDown(mode: .enhanced, prompt: prompt, context: nil))

        XCTAssertEqual(sut.state, .recording(mode: .enhanced, prompt: prompt, isHandsFree: false, enterMonitorPending: false))
        XCTAssertTrue(effects.contains(.startRecording(mode: .enhanced, prompt: prompt, context: nil)))
    }

    func testIdleIgnoresOtherEvents() {
        let eventsToIgnore: [DictationEvent] = [
            .hotkeyUp(duration: 0.5),
            .enterPressed,
            .escapePressed,
            .transcriptionEmpty,
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
        XCTAssertEqual(sut.state, .recording(mode: .local, prompt: nil, isHandsFree: false, enterMonitorPending: false))

        // Brief release (< 1 second)
        let effects = sut.handle(.hotkeyUp(duration: 0.3))

        XCTAssertEqual(sut.state, .recording(mode: .local, prompt: nil, isHandsFree: true, enterMonitorPending: false))
        XCTAssertTrue(effects.isEmpty, "No side effects for hands-free activation")
    }

    // MARK: - Recording: Long Press (Stop)

    func testLongPressStopsRecording() {
        // Start recording
        _ = sut.handle(.hotkeyDown(mode: .local, prompt: nil, context: nil))

        // Long release (>= 1 second)
        let effects = sut.handle(.hotkeyUp(duration: 1.5))

        if case .transcribing(let mode, _, let postPasteAction) = sut.state {
            XCTAssertEqual(mode, .local)
            XCTAssertEqual(postPasteAction, .stop)
        } else {
            XCTFail("Expected transcribing state, got \(sut.state)")
        }
        XCTAssertTrue(effects.contains(.stopRecording))
        XCTAssertTrue(effects.contains(.stopEscapeMonitor))
        XCTAssertTrue(effects.contains(.stopEnterMonitor))
        XCTAssertTrue(effects.contains(.stopCommandMonitor))
    }

    // MARK: - Hands-Free: Second Press Stops

    func testSecondPressInHandsFreeModeStops() {
        // Start in hands-free mode
        _ = sut.handle(.hotkeyDown(mode: .enhanced, prompt: "test", context: nil))
        _ = sut.handle(.hotkeyUp(duration: 0.2))
        XCTAssertEqual(sut.state, .recording(mode: .enhanced, prompt: "test", isHandsFree: true, enterMonitorPending: false))

        // Second press
        let effects = sut.handle(.hotkeyDown(mode: .enhanced, prompt: nil, context: nil))

        if case .transcribing(let mode, _, let postPasteAction) = sut.state {
            XCTAssertEqual(mode, .enhanced)
            XCTAssertEqual(postPasteAction, .stop)
        } else {
            XCTFail("Expected transcribing state, got \(sut.state)")
        }
        XCTAssertTrue(effects.contains(.stopRecording))
    }

    // MARK: - Hands-Free: Enter Pressed (Submit and Continue)

    func testEnterPressedInHandsFreeModeSetsSendAndContinue() {
        // Start in hands-free mode
        _ = sut.handle(.hotkeyDown(mode: .local, prompt: nil, context: nil))
        _ = sut.handle(.hotkeyUp(duration: 0.2))

        // Press Enter
        let effects = sut.handle(.enterPressed)

        if case .transcribing(let mode, _, let postPasteAction) = sut.state {
            XCTAssertEqual(mode, .local)
            XCTAssertEqual(postPasteAction, .sendAndContinue)
        } else {
            XCTFail("Expected transcribing state, got \(sut.state)")
        }
        XCTAssertTrue(effects.contains(.stopRecording))
    }

    func testEnterIgnoredWhenNotHandsFree() {
        // Start recording (not hands-free)
        _ = sut.handle(.hotkeyDown(mode: .local, prompt: nil, context: nil))
        XCTAssertEqual(sut.state, .recording(mode: .local, prompt: nil, isHandsFree: false, enterMonitorPending: false))

        // Press Enter - should be ignored
        let effects = sut.handle(.enterPressed)

        XCTAssertEqual(sut.state, .recording(mode: .local, prompt: nil, isHandsFree: false, enterMonitorPending: false))
        XCTAssertTrue(effects.isEmpty)
    }

    // MARK: - Escape Cancels Recording

    func testEscapeCancelsFromRecording() {
        _ = sut.handle(.hotkeyDown(mode: .local, prompt: nil, context: nil))

        let effects = sut.handle(.escapePressed)

        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(effects.contains(.cancelRecording))
        XCTAssertTrue(effects.contains(.hideIndicator))
        XCTAssertTrue(effects.contains(.stopEscapeMonitor))
        XCTAssertTrue(effects.contains(.stopEnterMonitor))
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
        sut.setState(.transcribing(mode: .enhanced, prompt: "test prompt", postPasteAction: .stop))

        let effects = sut.handle(.transcriptionComplete(text: "Hello world"))

        if case .enhancing(let mode, let prompt, let postPasteAction) = sut.state {
            XCTAssertEqual(mode, .enhanced)
            XCTAssertEqual(prompt, "test prompt")
            XCTAssertEqual(postPasteAction, .stop)
        } else {
            XCTFail("Expected enhancing state, got \(sut.state)")
        }
        XCTAssertTrue(effects.contains(.enhance(text: "Hello world", prompt: "test prompt", context: nil)))
    }

    func testTranscriptionCompleteLocalModeToPasting() {
        // Set up transcribing state for local mode (no prompt)
        sut.setState(.transcribing(mode: .local, prompt: nil, postPasteAction: .stop))

        let effects = sut.handle(.transcriptionComplete(text: "Hello world"))

        if case .pasting(let mode, _, let postPasteAction) = sut.state {
            XCTAssertEqual(mode, .local)
            XCTAssertEqual(postPasteAction, .stop)
        } else {
            XCTFail("Expected pasting state, got \(sut.state)")
        }
        XCTAssertTrue(effects.contains(.paste(text: "Hello world")))
        XCTAssertTrue(effects.contains(.schedulePasteComplete))
    }

    func testEmptyTranscriptionGoesToError() {
        sut.setState(.transcribing(mode: .local, prompt: nil, postPasteAction: .stop))

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
        sut.setState(.enhancing(mode: .enhanced, prompt: "test", postPasteAction: .stop))

        let effects = sut.handle(.enhancementComplete(text: "Enhanced text"))

        if case .pasting(let mode, _, let postPasteAction) = sut.state {
            XCTAssertEqual(mode, .enhanced)
            XCTAssertEqual(postPasteAction, .stop)
        } else {
            XCTFail("Expected pasting state, got \(sut.state)")
        }
        XCTAssertTrue(effects.contains(.paste(text: "Enhanced text")))
    }

    func testEnhancementSkippedToPasting() {
        sut.setState(.enhancing(mode: .enhanced, prompt: "test", postPasteAction: .sendAndContinue))

        let effects = sut.handle(.enhancementSkipped(text: "Raw text"))

        if case .pasting(let mode, _, let postPasteAction) = sut.state {
            XCTAssertEqual(mode, .enhanced)
            XCTAssertEqual(postPasteAction, .sendAndContinue)
        } else {
            XCTFail("Expected pasting state, got \(sut.state)")
        }
        XCTAssertTrue(effects.contains(.paste(text: "Raw text")))
    }

    // MARK: - Paste Complete

    func testPasteCompleteReturnsToIdle() {
        sut.setState(.pasting(mode: .local, prompt: nil, postPasteAction: .stop))

        let effects = sut.handle(.pasteComplete)

        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(effects.contains(.hideIndicator))
    }

    // MARK: - Continue After Submit

    func testPasteCompleteWithSendAndContinueRestartsRecording() {
        sut.setState(.pasting(mode: .enhanced, prompt: "test prompt", postPasteAction: .sendAndContinue))

        let effects = sut.handle(.pasteComplete)

        // Should restart in hands-free recording mode (with enterMonitorPending true)
        XCTAssertEqual(sut.state, .recording(mode: .enhanced, prompt: "test prompt", isHandsFree: true, enterMonitorPending: true))

        // Should press Enter and restart (no showIndicator - it's already visible)
        XCTAssertTrue(effects.contains(.pressEnterKey))
        XCTAssertTrue(effects.contains(.startRecording(mode: .enhanced, prompt: "test prompt", context: nil)))
        XCTAssertFalse(effects.contains(.showIndicator), "showIndicator should NOT be included to avoid white flash")
        XCTAssertTrue(effects.contains(.startEscapeMonitor))
        XCTAssertTrue(effects.contains(.scheduleEnterMonitorStart))
        XCTAssertTrue(effects.contains(.startCommandMonitor))
    }

    func testPostPasteActionPreservesThroughFlow() {
        // Start and activate hands-free
        _ = sut.handle(.hotkeyDown(mode: .local, prompt: nil, context: nil))
        _ = sut.handle(.hotkeyUp(duration: 0.2))

        // Press Enter - sets postPasteAction = .sendAndContinue
        _ = sut.handle(.enterPressed)

        // Verify postPasteAction is preserved through transitions
        if case .transcribing(_, _, let postPasteAction) = sut.state {
            XCTAssertEqual(postPasteAction, .sendAndContinue)
        } else {
            XCTFail("Expected transcribing state")
        }

        // Complete transcription (local mode - no enhancement)
        _ = sut.handle(.transcriptionComplete(text: "test"))

        if case .pasting(_, _, let postPasteAction) = sut.state {
            XCTAssertEqual(postPasteAction, .sendAndContinue)
        } else {
            XCTFail("Expected pasting state")
        }
    }

    // MARK: - Error Handling

    func testErrorFromAnyState() {
        let states: [DictationState] = [
            .recording(mode: .local, prompt: nil, isHandsFree: false, enterMonitorPending: false),
            .recording(mode: .local, prompt: nil, isHandsFree: true, enterMonitorPending: false),
            .transcribing(mode: .local, prompt: nil, postPasteAction: .stop),
            .enhancing(mode: .enhanced, prompt: "test", postPasteAction: .stop),
            .pasting(mode: .local, prompt: nil, postPasteAction: .stop),
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
            XCTAssertTrue(effects.contains(.stopEscapeMonitor))
            XCTAssertTrue(effects.contains(.stopEnterMonitor))
            XCTAssertTrue(effects.contains(.stopCommandMonitor))
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

        XCTAssertEqual(sut.state, .recording(mode: .local, prompt: nil, isHandsFree: false, enterMonitorPending: false))
        XCTAssertTrue(effects.contains(.startRecording(mode: .local, prompt: nil, context: nil)))
    }

    // MARK: - State Properties

    func testStateIsRecordingProperty() {
        XCTAssertFalse(DictationState.idle.isRecording)
        XCTAssertTrue(DictationState.recording(mode: .local, prompt: nil, isHandsFree: false, enterMonitorPending: false).isRecording)
        XCTAssertTrue(DictationState.recording(mode: .local, prompt: nil, isHandsFree: true, enterMonitorPending: false).isRecording)
        XCTAssertFalse(DictationState.transcribing(mode: .local, prompt: nil, postPasteAction: .stop).isRecording)
    }

    func testStateIsProcessingProperty() {
        XCTAssertFalse(DictationState.idle.isProcessing)
        XCTAssertFalse(DictationState.recording(mode: .local, prompt: nil, isHandsFree: false, enterMonitorPending: false).isProcessing)
        XCTAssertTrue(DictationState.transcribing(mode: .local, prompt: nil, postPasteAction: .stop).isProcessing)
        XCTAssertTrue(DictationState.enhancing(mode: .enhanced, prompt: "test", postPasteAction: .stop).isProcessing)
        XCTAssertTrue(DictationState.pasting(mode: .local, prompt: nil, postPasteAction: .stop).isProcessing)
        XCTAssertFalse(DictationState.error(message: "test").isProcessing)
    }

    func testStateIsHandsFreeProperty() {
        XCTAssertFalse(DictationState.idle.isHandsFree)
        XCTAssertFalse(DictationState.recording(mode: .local, prompt: nil, isHandsFree: false, enterMonitorPending: false).isHandsFree)
        XCTAssertTrue(DictationState.recording(mode: .local, prompt: nil, isHandsFree: true, enterMonitorPending: false).isHandsFree)
        XCTAssertFalse(DictationState.transcribing(mode: .local, prompt: nil, postPasteAction: .stop).isHandsFree)
    }

    func testStateShouldContinueAfterProperty() {
        XCTAssertFalse(DictationState.idle.shouldContinueAfter)
        XCTAssertFalse(DictationState.recording(mode: .local, prompt: nil, isHandsFree: true, enterMonitorPending: false).shouldContinueAfter)
        XCTAssertFalse(DictationState.transcribing(mode: .local, prompt: nil, postPasteAction: .stop).shouldContinueAfter)
        XCTAssertTrue(DictationState.transcribing(mode: .local, prompt: nil, postPasteAction: .sendAndContinue).shouldContinueAfter)
        XCTAssertTrue(DictationState.pasting(mode: .local, prompt: nil, postPasteAction: .sendAndContinue).shouldContinueAfter)
        XCTAssertFalse(DictationState.pasting(mode: .local, prompt: nil, postPasteAction: .sendAndStop).shouldContinueAfter)
    }

    // MARK: - Multiple Enter Presses (Regression Test)

    func testMultipleEnterPressesWorkCorrectly() {
        // First recording session
        _ = sut.handle(.hotkeyDown(mode: .local, prompt: nil, context: nil))
        _ = sut.handle(.hotkeyUp(duration: 0.2))  // Hands-free

        // First Enter press
        _ = sut.handle(.enterPressed)
        XCTAssertEqual(sut.state.postPasteAction, .sendAndContinue)

        // Simulate transcription complete
        _ = sut.handle(.transcriptionComplete(text: "first message"))

        // Paste complete triggers restart (with enterMonitorPending = true)
        let effects1 = sut.handle(.pasteComplete)
        XCTAssertEqual(sut.state, .recording(mode: .local, prompt: nil, isHandsFree: true, enterMonitorPending: true))
        XCTAssertTrue(effects1.contains(.pressEnterKey))

        // Simulate Enter monitor becoming ready
        _ = sut.handle(.enterMonitorReady)
        XCTAssertEqual(sut.state, .recording(mode: .local, prompt: nil, isHandsFree: true, enterMonitorPending: false))

        // Second Enter press should also work
        let effects2 = sut.handle(.enterPressed)
        if case .transcribing(_, _, let postPasteAction) = sut.state {
            XCTAssertEqual(postPasteAction, .sendAndContinue)
        } else {
            XCTFail("Expected transcribing state after second Enter")
        }
        XCTAssertTrue(effects2.contains(.stopRecording))
    }

    // MARK: - Integration Tests (Complete User Flows)

    /// Test: Start dictation with hold-to-record, release to stop
    func testFlow_HoldToRecord() {
        // User holds hotkey
        let startEffects = sut.handle(.hotkeyDown(mode: .enhanced, prompt: "test prompt", context: nil))
        XCTAssertEqual(sut.state, .recording(mode: .enhanced, prompt: "test prompt", isHandsFree: false, enterMonitorPending: false))
        XCTAssertTrue(startEffects.contains(.startRecording(mode: .enhanced, prompt: "test prompt", context: nil)))
        XCTAssertTrue(startEffects.contains(.showIndicator))

        // User releases after 2 seconds (long press)
        let stopEffects = sut.handle(.hotkeyUp(duration: 2.0))
        if case .transcribing(let mode, let prompt, let postPasteAction) = sut.state {
            XCTAssertEqual(mode, .enhanced)
            XCTAssertEqual(prompt, "test prompt")
            XCTAssertEqual(postPasteAction, .stop)
        } else {
            XCTFail("Expected transcribing state")
        }
        XCTAssertTrue(stopEffects.contains(.stopRecording))

        // Transcription completes
        _ = sut.handle(.transcriptionComplete(text: "hello world"))
        XCTAssertTrue(sut.state.isProcessing)

        // Enhancement completes
        _ = sut.handle(.enhancementComplete(text: "Hello, world!"))
        if case .pasting = sut.state {
            // Good
        } else {
            XCTFail("Expected pasting state")
        }

        // Paste completes
        let finalEffects = sut.handle(.pasteComplete)
        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(finalEffects.contains(.hideIndicator))
    }

    /// Test: Tap for hands-free mode, tap again to stop
    func testFlow_HandsFreeMode() {
        // Quick tap to start
        _ = sut.handle(.hotkeyDown(mode: .local, prompt: nil, context: nil))
        XCTAssertEqual(sut.state, .recording(mode: .local, prompt: nil, isHandsFree: false, enterMonitorPending: false))

        // Quick release activates hands-free
        _ = sut.handle(.hotkeyUp(duration: 0.3))
        XCTAssertEqual(sut.state, .recording(mode: .local, prompt: nil, isHandsFree: true, enterMonitorPending: false))

        // Second tap stops recording
        let stopEffects = sut.handle(.hotkeyDown(mode: .local, prompt: nil, context: nil))
        if case .transcribing(_, _, let postPasteAction) = sut.state {
            XCTAssertEqual(postPasteAction, .stop)
        } else {
            XCTFail("Expected transcribing state")
        }
        XCTAssertTrue(stopEffects.contains(.stopRecording))
    }

    /// Test: Hands-free with Enter to submit and continue, then Enter again, then cancel
    func testFlow_EnterToContinueThenCancel() {
        // Start hands-free recording
        _ = sut.handle(.hotkeyDown(mode: .enhanced, prompt: "dictation", context: nil))
        _ = sut.handle(.hotkeyUp(duration: 0.2))
        XCTAssertEqual(sut.state, .recording(mode: .enhanced, prompt: "dictation", isHandsFree: true, enterMonitorPending: false))

        // First Enter - submit and continue
        let enter1Effects = sut.handle(.enterPressed)
        if case .transcribing(_, _, let postPasteAction) = sut.state {
            XCTAssertEqual(postPasteAction, .sendAndContinue)
        } else {
            XCTFail("Expected transcribing state")
        }
        XCTAssertTrue(enter1Effects.contains(.stopRecording))

        // Simulate full transcription/enhancement/paste cycle
        _ = sut.handle(.transcriptionComplete(text: "first message"))
        _ = sut.handle(.enhancementComplete(text: "First message."))
        let paste1Effects = sut.handle(.pasteComplete)

        // Should restart in hands-free recording (with enterMonitorPending = true)
        XCTAssertEqual(sut.state, .recording(mode: .enhanced, prompt: "dictation", isHandsFree: true, enterMonitorPending: true))
        XCTAssertTrue(paste1Effects.contains(.pressEnterKey))
        XCTAssertTrue(paste1Effects.contains(.startRecording(mode: .enhanced, prompt: "dictation", context: nil)))

        // Simulate Enter monitor becoming ready
        _ = sut.handle(.enterMonitorReady)
        XCTAssertEqual(sut.state, .recording(mode: .enhanced, prompt: "dictation", isHandsFree: true, enterMonitorPending: false))

        // Second Enter - submit and continue again
        _ = sut.handle(.enterPressed)
        if case .transcribing(_, _, let postPasteAction) = sut.state {
            XCTAssertEqual(postPasteAction, .sendAndContinue)
        } else {
            XCTFail("Expected transcribing state after second Enter")
        }

        // Complete second cycle
        _ = sut.handle(.transcriptionComplete(text: "second message"))
        _ = sut.handle(.enhancementComplete(text: "Second message."))
        _ = sut.handle(.pasteComplete)

        // Should be recording again (with enterMonitorPending = true)
        XCTAssertEqual(sut.state, .recording(mode: .enhanced, prompt: "dictation", isHandsFree: true, enterMonitorPending: true))

        // Cancel with Escape
        let cancelEffects = sut.handle(.escapePressed)
        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(cancelEffects.contains(.cancelRecording))
        XCTAssertTrue(cancelEffects.contains(.hideIndicator))
    }

    /// Test: Cancel during recording
    func testFlow_CancelDuringRecording() {
        _ = sut.handle(.hotkeyDown(mode: .local, prompt: nil, context: nil))
        XCTAssertTrue(sut.state.isRecording)

        let cancelEffects = sut.handle(.escapePressed)
        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(cancelEffects.contains(.cancelRecording))
        XCTAssertTrue(cancelEffects.contains(.hideIndicator))
    }

    /// Test: Cancel during transcription
    func testFlow_CancelDuringTranscription() {
        _ = sut.handle(.hotkeyDown(mode: .local, prompt: nil, context: nil))
        _ = sut.handle(.hotkeyUp(duration: 2.0))  // Long press to stop

        if case .transcribing = sut.state {
            // Good
        } else {
            XCTFail("Expected transcribing state")
        }

        let cancelEffects = sut.handle(.escapePressed)
        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(cancelEffects.contains(.hideIndicator))
    }

    /// Test: Cancel during enhancement
    func testFlow_CancelDuringEnhancement() {
        _ = sut.handle(.hotkeyDown(mode: .enhanced, prompt: "test", context: nil))
        _ = sut.handle(.hotkeyUp(duration: 2.0))
        _ = sut.handle(.transcriptionComplete(text: "hello"))

        if case .enhancing = sut.state {
            // Good
        } else {
            XCTFail("Expected enhancing state")
        }

        let cancelEffects = sut.handle(.escapePressed)
        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(cancelEffects.contains(.hideIndicator))
    }

    /// Test: Local mode skips enhancement
    func testFlow_LocalModeSkipsEnhancement() {
        _ = sut.handle(.hotkeyDown(mode: .local, prompt: nil, context: nil))
        _ = sut.handle(.hotkeyUp(duration: 2.0))

        // Transcription complete should go directly to pasting (no enhancement)
        let effects = sut.handle(.transcriptionComplete(text: "hello world"))
        if case .pasting(let mode, _, _) = sut.state {
            XCTAssertEqual(mode, .local)
        } else {
            XCTFail("Expected pasting state for local mode")
        }
        XCTAssertTrue(effects.contains(.paste(text: "hello world")))
        // Should NOT contain enhance
        XCTAssertFalse(effects.contains(where: {
            if case .enhance = $0 { return true }
            return false
        }))
    }

    /// Test: Empty transcription shows error
    func testFlow_EmptyTranscriptionShowsError() {
        _ = sut.handle(.hotkeyDown(mode: .local, prompt: nil, context: nil))
        _ = sut.handle(.hotkeyUp(duration: 2.0))

        let effects = sut.handle(.transcriptionEmpty)
        if case .error(let message) = sut.state {
            XCTAssertEqual(message, "No speech detected")
        } else {
            XCTFail("Expected error state")
        }
        XCTAssertTrue(effects.contains(.hideIndicator))
        XCTAssertTrue(effects.contains(.scheduleErrorTimeout))

        // Error timeout returns to idle
        _ = sut.handle(.errorTimeout)
        XCTAssertEqual(sut.state, .idle)
    }

    /// Test: Can start new recording from error state
    func testFlow_StartFromErrorState() {
        sut.setState(.error(message: "Previous error"))

        let effects = sut.handle(.hotkeyDown(mode: .local, prompt: nil, context: nil))
        XCTAssertEqual(sut.state, .recording(mode: .local, prompt: nil, isHandsFree: false, enterMonitorPending: false))
        XCTAssertTrue(effects.contains(.startRecording(mode: .local, prompt: nil, context: nil)))
    }

    // MARK: - Command Key (Send and Stop)

    func testCommandPressedInHandsFreeModeSetsSendAndStop() {
        // Start in hands-free mode
        _ = sut.handle(.hotkeyDown(mode: .local, prompt: nil, context: nil))
        _ = sut.handle(.hotkeyUp(duration: 0.2))

        // Press Command
        let effects = sut.handle(.commandPressed)

        if case .transcribing(let mode, _, let postPasteAction) = sut.state {
            XCTAssertEqual(mode, .local)
            XCTAssertEqual(postPasteAction, .sendAndStop)
        } else {
            XCTFail("Expected transcribing state, got \(sut.state)")
        }
        XCTAssertTrue(effects.contains(.stopRecording))
        XCTAssertTrue(effects.contains(.stopEscapeMonitor))
        XCTAssertTrue(effects.contains(.stopEnterMonitor))
        XCTAssertTrue(effects.contains(.stopCommandMonitor))
    }

    func testPasteCompleteWithSendAndStop_PressesEnterAndGoesIdle() {
        sut.setState(.pasting(mode: .enhanced, prompt: "test prompt", postPasteAction: .sendAndStop))

        let effects = sut.handle(.pasteComplete)

        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(effects.contains(.pressEnterKey))
        XCTAssertTrue(effects.contains(.hideIndicator))
        // Should NOT restart recording
        XCTAssertFalse(effects.contains(where: {
            if case .startRecording = $0 { return true }
            return false
        }))
    }

    func testCommandIgnoredWhenNotHandsFree() {
        // Start recording (not hands-free)
        _ = sut.handle(.hotkeyDown(mode: .local, prompt: nil, context: nil))
        XCTAssertEqual(sut.state, .recording(mode: .local, prompt: nil, isHandsFree: false, enterMonitorPending: false))

        // Press Command - should be ignored
        let effects = sut.handle(.commandPressed)

        XCTAssertEqual(sut.state, .recording(mode: .local, prompt: nil, isHandsFree: false, enterMonitorPending: false))
        XCTAssertTrue(effects.isEmpty)
    }

    func testSendAndStopPreservesThroughEnhancementFlow() {
        // Start in hands-free mode
        _ = sut.handle(.hotkeyDown(mode: .enhanced, prompt: "dictation", context: nil))
        _ = sut.handle(.hotkeyUp(duration: 0.2))

        // Command press - send and stop
        _ = sut.handle(.commandPressed)

        if case .transcribing(_, _, let postPasteAction) = sut.state {
            XCTAssertEqual(postPasteAction, .sendAndStop)
        } else {
            XCTFail("Expected transcribing state")
        }

        // Through enhancement
        _ = sut.handle(.transcriptionComplete(text: "test message"))
        if case .enhancing(_, _, let postPasteAction) = sut.state {
            XCTAssertEqual(postPasteAction, .sendAndStop)
        } else {
            XCTFail("Expected enhancing state")
        }

        // Through pasting
        _ = sut.handle(.enhancementComplete(text: "Test message."))
        if case .pasting(_, _, let postPasteAction) = sut.state {
            XCTAssertEqual(postPasteAction, .sendAndStop)
        } else {
            XCTFail("Expected pasting state")
        }

        // Paste complete - should press Enter and go idle
        let effects = sut.handle(.pasteComplete)
        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(effects.contains(.pressEnterKey))
        XCTAssertTrue(effects.contains(.hideIndicator))
    }
}
