# ParaDict2 Commit History Retrospective

Analysis of 97 commits (2025-11-26 to 2026-01-07) to identify recurring problem patterns.

---

## Problem Category 1: Threading & UI Blocking (Most Severe)

**Commits involved:** `602b796`, `c3f84b6`, `8b9f30d`, `321c28a`, `ff5eb84`

### What happened

The UI repeatedly froze (rainbow wheel) when the DirectoryWatcherService triggered transcription. This was a **4-commit debugging saga**:

1. `321c28a` "fix ui bug" — initial attempt, modified DirectoryWatcherService
2. `602b796` "still blocks" — second attempt, still not fixed (commit message says it all)
3. `c3f84b6` "fixed watched transcription blocking ui - took a while" — finally fixed after touching 7 files
4. `8b9f30d` "restore GCD background queue for audio processing" — the fix was accidentally reverted by a cleanup commit, had to be restored

A separate instance: `ff5eb84` "menubar blocks window with invisible stats menu" — required creating an entirely new `StatusBarController.swift` (284 lines) to fix a window layering/blocking issue.

### Root cause

The entry point (FSEventStream callback / DirectoryWatcher) was dispatched on the main queue. All downstream work (transcription, audio conversion) therefore ran on the main thread. Wrapping individual operations in `Task.detached` or `DispatchQueue.global` didn't help because the *caller* was already on main.

**The lesson was significant enough to be codified in CLAUDE.md** as the "Debugging UI Blocking" section.

### What tests should have caught this

- **Thread assertion test**: Any transcription call should assert it's NOT on the main thread
- **Integration test**: Trigger a directory watcher event and verify the UI remains responsive (measure main thread blocking time)
- **Smoke test**: `XCTAssertFalse(Thread.isMainThread)` at the top of `ParakeetTranscriptionService.transcribe()`

### How the spec should have been written

> "Directory watching MUST dispatch file processing on a background queue. The transcription service MUST never be called from the main thread. Entry points that receive system callbacks MUST immediately hop to a background queue before doing any work."

### Root cause analysis

**Architecture flaw.** No threading contract was established. The codebase lacked a rule about which queue each component runs on. The fix in `8b9f30d` being accidentally reverted by cleanup proves there was no automated guard.

---

## Problem Category 2: State Machine Churn (Architecture Evolution)

**Commits involved:** `5c1ca6c`, `6927790`, `0bdd90b`, `df17f4a`, `e8f2008`, `a2f9fb9`, `f537091`, `d5cd3ce`

### What happened

The state management evolved through 3 phases over 12 commits:

1. **Ad-hoc DictationManager** (`4424c5d` — the "not working" commit with 2651 lines added) — initial monolithic manager
2. **State collision fixes** (`a2f9fb9`) — hotkey events arriving during transitions caused undefined behavior
3. **State machine extraction** (`5c1ca6c` through `6927790`) — 4 WIP commits to extract a proper state machine
4. **Testing attempts** (`0bdd90b`, `df17f4a`, `e8f2008`) — 3 commits trying to add tests, described as "really horrific"
5. **Council capture bug** (`f537091`) — CGEvent tap callback was capturing `self`, creating retain cycle
6. **Final cleanup** (`d5cd3ce`) — old DictationManager finally deleted

### Root cause

The DictationManager was built as a God Object handling recording, transcription, LLM calls, pasting, and state transitions all in one class. State collisions emerged because there was no formal state machine — just boolean flags and if/else chains.

### What tests should have caught this

- **State machine unit tests**: For every (state, event) pair, assert the expected (newState, sideEffects) — this is trivially testable for a pure state machine
- **Invalid transition tests**: Verify that events in wrong states are rejected gracefully
- **Retain cycle detection**: Use `weak` expectations in tests to verify no strong reference cycles

### How the spec should have been written

> "Dictation flow uses a pure state machine (no side effects in the state machine itself). States: idle → recording → transcribing → enhancing → pasting → idle. The coordinator executes side effects returned by the state machine. State machine transitions must be unit tested for every valid and invalid (state, event) combination."

### Root cause analysis

**Architecture flaw → scaffolding gap.** Starting with a monolith is fine for prototyping, but the absence of a state machine pattern from the start meant state bugs accumulated until a rewrite was necessary. The testing infrastructure wasn't set up early enough to catch regressions.

---

## Problem Category 3: Correction Mechanism Rewrites (Unclear Spec)

**Commits involved:** `6851684`, `42b5d46`, `af27b61`, `22fc423`, `7052849`, `455d3fd`, `242b89f`

### What happened

The correction feature (for fixing transcription errors) was rewritten **at least 5 times** across 7 commits:

1. `6851684` "correction feature" — initial implementation
2. `42b5d46` "Improved correction mechanism - but wip" — rewrite, acknowledged as incomplete
3. `22fc423` "Improve the correction mechanism" — another attempt
4. `7052849` "change correction mechanism" — yet another approach
5. `455d3fd` "correction mechanism for new manager" — adapted for state machine
6. `242b89f` "Change how corrections are written into the dictionary" — changed storage format

### Root cause

There was no clear specification for what "correction" means:
- Is it a word-level replacement dictionary?
- Is it a UI for reviewing and fixing transcriptions?
- Is it automatic or manual?
- Where are corrections stored?
- How do corrections feed back into future transcriptions?

Each commit tried a different answer to these questions.

### What tests should have caught this

- **Behavioral tests**: "Given a correction 'X → Y', when 'X' appears in transcription, then it should be replaced with 'Y'"
- **Persistence tests**: Corrections survive app restart
- **Edge case tests**: Empty corrections, duplicate entries, overlapping corrections

### How the spec should have been written

> "Corrections are a user-maintained dictionary of word replacements stored in `~/Library/Application Support/ParaDict/corrections.json`. When the user speaks a correction keyword (configurable, default: 'correct'), the last transcription is shown in an editable window. The diff between original and edited text is saved as a correction pair. Future transcriptions automatically apply all stored corrections via string replacement before pasting."

### Root cause analysis

**Unclear specification.** The feature was started without defining the UX flow, data model, or storage format. Each commit was an exploration of a different design, not a progression toward a defined goal.

---

## Problem Category 4: File Watcher / Directory Watcher Bugs

**Commits involved:** `68478c5`, `4fc8ad4`, `c6bd798`, `4b8b8ff`

### What happened

The directory watcher (batch transcription of audio files dropped into a folder) had a sequence of bugs:

1. `68478c5` "ffmpeg file watch" — initial implementation using ffmpeg for audio conversion
2. `4fc8ad4` "ffmpeg to native" — switched from ffmpeg dependency to native AVFoundation
3. `c6bd798` "fix file watcher dir bug" — directory path handling bug
4. `4b8b8ff` "Fix filewatcher bugs" — additional edge case fixes

The dependency switch from ffmpeg to native was forced because bundling ffmpeg is problematic for distribution.

### What tests should have caught this

- **File format tests**: Verify transcription works with .mp3, .m4a, .wav, .webm input
- **Directory handling tests**: Verify watcher handles missing directories, permission errors, nested files
- **Integration test**: Drop a file into watched directory → verify transcription output appears

### How the spec should have been written

> "The directory watcher monitors a user-configured folder for new audio files (.mp3, .m4a, .wav, .webm). Files are converted to 16kHz mono WAV using AVFoundation (no external dependencies like ffmpeg). Transcription results are written to a .txt file alongside the original. The watcher must handle: missing directory (create it), permission errors (log and skip), and duplicate events (debounce within 1 second)."

### Root cause analysis

**Scaffolding issue + dependency decision.** The ffmpeg dependency was a shortcut that had to be undone. The directory handling bugs were straightforward missing edge cases that tests would have caught immediately.

---

## Problem Category 5: Race Conditions in Feature Composition

**Commits involved:** `8cd70fc`, `d61f556`, `87ced93`, `7966642`

### What happened

The YouTube/playback pausing mode was built across 4 commits:

1. `8cd70fc` "Add YouTube Mode" — initial feature
2. `d61f556` "works but resume after paste" — timing issue: video resumed before text was pasted
3. `87ced93` "pausing works faster except disabling playback pausing resumes the video..." — another ordering bug
4. `7966642` merge commit — finally merged

The commit message for `87ced93` is a 21-word run-on sentence describing a race condition where disabling the feature triggered a resume before the transcription was processed.

### What tests should have caught this

- **Sequence test**: Assert that paste completes BEFORE media resume
- **State test**: Disabling playback pausing mid-transcription should not trigger resume
- **Mock-based test**: Use a mock media controller to verify call ordering

### How the spec should have been written

> "Playback pausing mode: on recording start, send media pause. On transcription complete AND paste complete (both must succeed), send media resume. If the mode is disabled while a transcription is in progress, do NOT send resume — let the current cycle complete normally. Ordering: pause → record → transcribe → paste → resume (strictly sequential)."

### Root cause analysis

**Architecture flaw.** The media control was bolted onto the dictation flow without being integrated into the state machine. The state machine should have explicit states for "paused media, awaiting paste completion" to prevent race conditions.

---

## Problem Category 6: WIP / Vague Commits (Process Issue)

**Commits involved:** `4424c5d`, `3f14028`, `dcd324d`, `1e6a9eb`, `b6a84bc`, `ef04cc0`, `42b5d46`

### What happened

Multiple commits have messages that provide no information:

| Hash | Message | Files Changed |
|------|---------|---------------|
| `4424c5d` | "not working" | 23 files, +2651 lines |
| `3f14028` | "idk" | 1 file |
| `dcd324d` | "tweaks" | unknown |
| `1e6a9eb` | "claude tweak" | unknown |
| `b6a84bc` | "daily note wip" | unknown |
| `ef04cc0` | "wip: read context" | unknown |

The worst offender is `4424c5d`: 2651 lines of new code committed with "not working" — this was the entire initial scaffold of the app. When you come back to debug, this commit is almost useless for understanding what was attempted and what failed.

### What tests should have caught this

N/A — this is a process issue, not a code issue. But if CI required tests to pass before commit, "not working" commits wouldn't exist.

### How the spec should have been written

N/A — this requires a process rule, not a feature spec.

### Root cause analysis

**Process/discipline gap.** No commit message convention was enforced. Large changes were committed as single monolithic commits, making it impossible to bisect issues or understand the evolution of decisions.

---

## Problem Category 7: Testing Infrastructure Failure

**Commits involved:** `e8f2008`, `df17f4a`, `0bdd90b`

### What happened

Three consecutive commits tried to set up testing:

1. `0bdd90b` "testing setup, state machine tweaks"
2. `df17f4a` "testing and state"
3. `e8f2008` "Really horrific attempt at including some tests" — 131-line `TranscriptionIntegrationTests.swift`

The developer's own assessment: "Really horrific attempt." The tests were integration tests that depended on the actual Parakeet model being available, making them slow and flaky.

### What tests should have caught this

The irony: the testing infrastructure itself was the problem. What was needed:

- **Protocol-based mocking**: Define `TranscriptionServiceProtocol` so tests can use a mock
- **Pure state machine tests**: The state machine is pure functions — trivially testable
- **Unit test scaffolding first**: Set up test targets, mocks, and helpers before writing actual tests

### How the spec should have been written

> "Testing strategy: (1) State machine transitions are tested exhaustively with unit tests. (2) Services are defined by protocols to enable mock injection. (3) Integration tests use pre-recorded audio fixtures, not live recording. (4) No test should take more than 2 seconds."

### Root cause analysis

**Scaffolding issue.** Testing was attempted after the architecture was already built without testability in mind. Services were concrete classes without protocols, making mocking impossible without refactoring.

---

## Summary: Pattern Distribution

| Category | Commits Involved | Root Cause Type | Severity |
|----------|-----------------|-----------------|----------|
| Threading/UI blocking | 5 | Architecture flaw | Critical |
| State machine churn | 8 | Architecture → scaffolding | High |
| Correction rewrites | 7 | Unclear spec | Medium |
| File watcher bugs | 4 | Scaffolding + dependency | Medium |
| Race conditions | 4 | Architecture flaw | High |
| Vague commits | 7 | Process gap | Low (but compounds) |
| Testing failure | 3 | Scaffolding issue | High (systemic) |

---

## Recommendations

### 1. Architecture: Establish Threading Contracts

Every service should document which queue it expects to be called on. Use runtime assertions:

```swift
func transcribe(audioURL: URL) async throws -> String {
    assert(!Thread.isMainThread, "transcribe() must not be called on main thread")
    // ...
}
```

### 2. Architecture: State Machine First

For any feature with more than 2 states, define the state machine BEFORE writing any UI or service code. The state machine should be a pure function that returns side effects — never performs them directly.

### 3. Specifications: Define Before Building

For any feature that involves user interaction, write a one-paragraph spec covering:
- **Trigger**: What starts it?
- **Data model**: What's stored, where?
- **Flow**: Step-by-step sequence
- **Edge cases**: What happens on failure, cancellation, or concurrent access?

### 4. Testing: Protocol-Based Services

Every service should conform to a protocol. This enables:
- Mock injection for unit tests
- Testing coordinator logic without real audio/network/transcription

### 5. Testing: State Machine Coverage

The state machine is the easiest thing to test and the most valuable. Every `(state, event) → (newState, sideEffects)` transition should be a test case.

### 6. Process: Granular Commits

Commit after every meaningful change. A "meaningful change" is:
- A single bug fix
- A single feature addition
- A single refactoring step
- NOT "2651 lines of scaffolding that doesn't work"

### 7. Process: Descriptive Commit Messages

Every commit message should answer: "What changed and why?" Never commit with messages like "idk", "tweaks", or "not working." If something doesn't work, describe what was attempted and what failed.
