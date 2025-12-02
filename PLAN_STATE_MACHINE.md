# Dictation State Machine Implementation Plan

## Overview

Replace scattered boolean flags with a single, well-defined finite state machine that makes all states and transitions explicit.

## Current Problems

1. State scattered across DictationManager and HotkeyManager
2. Multiple boolean flags that can get out of sync: `isRecording`, `isProcessing`, `isHandsFreeMode`, `shouldContinueAfterSubmit`
3. Implicit transition logic buried in methods
4. Hard to test - side effects mixed with state logic

## State Machine Design

### States

```swift
enum DictationState: Equatable {
    case idle
    case recording(mode: DictationMode, isHandsFree: Bool)
    case transcribing(mode: DictationMode, continueAfter: Bool)
    case enhancing(mode: DictationMode, continueAfter: Bool)
    case pasting(mode: DictationMode, continueAfter: Bool)
    case error(message: String)
}
```

Key insight: `isHandsFree` and `continueAfter` are associated WITH the state, not separate flags.

### Events

```swift
enum DictationEvent: Equatable {
    // User input
    case hotkeyDown(mode: DictationMode, prompt: String?, context: String?)
    case hotkeyUp(duration: TimeInterval)
    case enterPressed
    case escapePressed

    // Processing milestones
    case recordingComplete(url: URL)
    case transcriptionComplete(text: String)
    case transcriptionEmpty
    case enhancementComplete(text: String)
    case enhancementSkipped(text: String)  // No LLM configured, use raw text
    case pasteComplete

    // Errors
    case error(message: String)
    case errorTimeout
}
```

### Side Effects

```swift
enum DictationSideEffect: Equatable {
    case startRecording(mode: DictationMode, prompt: String?, context: String?)
    case stopRecording
    case cancelRecording
    case transcribe(url: URL)
    case enhance(text: String, prompt: String)
    case paste(text: String)
    case pressEnterKey
    case restartRecording(mode: DictationMode, prompt: String?)
    case showIndicator
    case hideIndicator
    case startKeyMonitors
    case stopKeyMonitors
    case scheduleErrorTimeout
    case cleanupRecordingFile(url: URL)
}
```

### State Transition Table

| Current State | Event | New State | Side Effects |
|---------------|-------|-----------|--------------|
| idle | hotkeyDown(mode, prompt, ctx) | recording(mode, handsFree: false) | startRecording, showIndicator, startKeyMonitors |
| recording(_, handsFree: false) | hotkeyUp(< 1s) | recording(_, handsFree: true) | (none) |
| recording(_, handsFree: false) | hotkeyUp(>= 1s) | transcribing(_, continueAfter: false) | stopRecording |
| recording(_, handsFree: true) | hotkeyDown | transcribing(_, continueAfter: false) | stopRecording, stopKeyMonitors |
| recording(_, handsFree: true) | enterPressed | transcribing(_, continueAfter: true) | stopRecording, stopKeyMonitors |
| recording(_) | escapePressed | idle | cancelRecording, hideIndicator, stopKeyMonitors |
| transcribing(mode, continue) | transcriptionComplete(text) | enhancing/pasting | transcribe or enhance |
| transcribing(_) | transcriptionEmpty | error | hideIndicator, showError |
| enhancing(mode, continue) | enhancementComplete(text) | pasting(mode, continue) | paste(text) |
| pasting(_, continueAfter: false) | pasteComplete | idle | hideIndicator |
| pasting(mode, continueAfter: true) | pasteComplete | recording(mode, handsFree: true) | pressEnterKey, restartRecording, startKeyMonitors |
| error | errorTimeout | idle | (none) |
| any | error(msg) | error(msg) | hideIndicator, stopKeyMonitors, scheduleErrorTimeout |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     HotkeyManager                            │
│  (Keyboard shortcuts, monitors - emits events)               │
└─────────────────────────┬───────────────────────────────────┘
                          │ DictationEvent
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                   DictationCoordinator                       │
│  - Owns DictationStateMachine                                │
│  - Receives events                                           │
│  - Executes side effects                                     │
│  - Bridges to services                                       │
└─────────────────────────┬───────────────────────────────────┘
                          │ calls
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                   DictationStateMachine                      │
│  - Pure state transition logic                               │
│  - No side effects                                           │
│  - handle(event) -> [SideEffect]                             │
│  - Fully testable                                            │
└─────────────────────────────────────────────────────────────┘
                          │ uses
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                      Services                                │
│  RecordingService, TranscriptionService, LLMClient,          │
│  PastingService, IndicatorManager                            │
└─────────────────────────────────────────────────────────────┘
```

## File Structure

```
ParaDict/
├── StateMachine/
│   ├── DictationState.swift         # State enum
│   ├── DictationEvent.swift         # Event enum
│   ├── DictationSideEffect.swift    # Side effect enum
│   └── DictationStateMachine.swift  # Pure state machine logic
├── DictationCoordinator.swift       # Replaces DictationManager
└── HotkeyManager.swift              # Updated to emit events
```

## Testing Strategy

### 1. Unit Tests for State Machine (Pure Logic)

File: `ParaDictTests/StateMachine/DictationStateMachineTests.swift`

Test categories:
- **Happy path transitions**: idle → recording → transcribing → pasting → idle
- **Hands-free mode**: brief press activates hands-free
- **Continue after submit**: Enter press sets continueAfter, leads to restart
- **Cancellation**: Escape from any recording state → idle
- **Error handling**: Errors from any state → error → idle
- **Invalid transitions**: Events that should be ignored

Example tests:
```swift
func testIdleToRecordingOnHotkeyDown() {
    let sm = DictationStateMachine()
    let effects = sm.handle(.hotkeyDown(mode: .local, prompt: nil, context: nil))

    XCTAssertEqual(sm.state, .recording(mode: .local, isHandsFree: false))
    XCTAssertTrue(effects.contains(.startRecording(mode: .local, prompt: nil, context: nil)))
    XCTAssertTrue(effects.contains(.showIndicator))
    XCTAssertTrue(effects.contains(.startKeyMonitors))
}

func testEnterPressedSetsContinueAfter() {
    let sm = DictationStateMachine()
    sm.handle(.hotkeyDown(mode: .enhanced, prompt: "test", context: nil))
    sm.handle(.hotkeyUp(duration: 0.2))  // Brief press → hands-free

    XCTAssertEqual(sm.state, .recording(mode: .enhanced, isHandsFree: true))

    let effects = sm.handle(.enterPressed)

    // Should transition to transcribing with continueAfter = true
    if case .transcribing(let mode, let continueAfter) = sm.state {
        XCTAssertEqual(mode, .enhanced)
        XCTAssertTrue(continueAfter)
    } else {
        XCTFail("Expected transcribing state")
    }
}

func testContinueAfterLeadsToRestart() {
    let sm = DictationStateMachine()
    // Set up state: pasting with continueAfter = true
    sm.setState(.pasting(mode: .local, continueAfter: true))

    let effects = sm.handle(.pasteComplete)

    XCTAssertEqual(sm.state, .recording(mode: .local, isHandsFree: true))
    XCTAssertTrue(effects.contains(.pressEnterKey))
    XCTAssertTrue(effects.contains(.restartRecording(mode: .local, prompt: nil)))
}

func testEscapeCancelsFromAnyRecordingState() {
    let states: [DictationState] = [
        .recording(mode: .local, isHandsFree: false),
        .recording(mode: .enhanced, isHandsFree: true),
    ]

    for initialState in states {
        let sm = DictationStateMachine()
        sm.setState(initialState)

        let effects = sm.handle(.escapePressed)

        XCTAssertEqual(sm.state, .idle)
        XCTAssertTrue(effects.contains(.cancelRecording))
        XCTAssertTrue(effects.contains(.hideIndicator))
    }
}

func testInvalidTransitionsAreIgnored() {
    let sm = DictationStateMachine()
    // In idle state, enterPressed should be ignored
    let effects = sm.handle(.enterPressed)

    XCTAssertEqual(sm.state, .idle)
    XCTAssertTrue(effects.isEmpty)
}
```

### 2. Integration Tests

File: `ParaDictTests/DictationCoordinatorTests.swift`

Test that side effects are executed correctly:
- Mock services
- Verify correct methods called on services
- Verify state published correctly for UI

### 3. Test Coverage Goals

- 100% of state transitions covered
- 100% of side effect mappings covered
- Edge cases: rapid key presses, errors during processing, empty transcriptions

## Implementation Steps

### Phase 1: Create State Machine (No Breaking Changes)

1. Create `StateMachine/` directory
2. Implement `DictationState.swift`
3. Implement `DictationEvent.swift`
4. Implement `DictationSideEffect.swift`
5. Implement `DictationStateMachine.swift`
6. Write unit tests for state machine
7. Verify all tests pass

### Phase 2: Create Coordinator

1. Create `DictationCoordinator.swift` that:
   - Owns the state machine
   - Has a `send(_ event: DictationEvent)` method
   - Executes side effects by calling existing services
2. Keep `DictationManager` working in parallel during transition

### Phase 3: Migrate HotkeyManager

1. Update HotkeyManager to emit events to coordinator
2. Remove boolean flags from HotkeyManager
3. Remove callbacks, use event-based communication

### Phase 4: Cleanup

1. Remove old DictationManager
2. Rename DictationCoordinator to DictationManager (or keep new name)
3. Update any UI bindings

## Rollback Plan

Since we're building the new system alongside the old one, we can:
1. Keep both systems working in parallel
2. Switch between them with a feature flag if needed
3. Only remove old code after new system is verified

## Success Criteria

1. All unit tests pass
2. All existing functionality works
3. "Submit and continue" (Enter key) works reliably for multiple iterations
4. Code is more readable and maintainable
5. State transitions are explicit and documented
