# FluidVoice Transcription Preview Widget: Technical Analysis

Source: `/Users/sebastian/code/cloned/FluidVoice`

---

## 1. Overview

FluidVoice provides a **real-time transcription preview** that shows what the user is saying while they are still speaking. The text appears in a floating overlay widget that sits either in the macOS notch area (using DynamicNotchKit) or as a bottom-of-screen floating panel (using a custom `NSPanel`).

From the user's perspective:
- Press the hotkey to start recording
- A widget appears showing an audio waveform visualization and mode label ("Dictate", "Rewrite", "Command")
- As the user speaks, transcribed text streams into the widget in real-time
- When the user stops, the widget shows a "Transcribing..." / "Refining..." shimmer animation while final processing occurs
- The widget dismisses automatically when done, or can be dismissed with Escape

The user can toggle this feature on/off via a **"Show Live Preview"** toggle in Settings, and can configure the character limit for how much preview text is shown (50-800 characters, default 150).

---

## 2. Architecture

### Key Components

| Component | File | Role |
|-----------|------|------|
| `ASRService` | `Sources/Fluid/Services/ASRService.swift` | Audio capture, streaming transcription engine, publishes `partialTranscription` |
| `MenuBarManager` | `Sources/Fluid/Services/MenuBarManager.swift` | Subscribes to ASR state, bridges transcription text to the overlay |
| `NotchOverlayManager` | `Sources/Fluid/Services/NotchOverlayManager.swift` | Manages overlay lifecycle (show/hide), routes to notch or bottom overlay |
| `NotchContentState` | `Sources/Fluid/Views/NotchContentViews.swift` | Singleton `ObservableObject` holding all overlay state (`transcriptionText`, `isProcessing`, `mode`) |
| `NotchExpandedView` | `Sources/Fluid/Views/NotchContentViews.swift` | SwiftUI view for the notch overlay (waveform + preview text) |
| `BottomOverlayView` | `Sources/Fluid/Views/BottomOverlayView.swift` | SwiftUI view for the bottom-of-screen overlay (alternative layout) |
| `BottomOverlayWindowController` | `Sources/Fluid/Views/BottomOverlayView.swift` | `NSPanel`-based window controller for the bottom overlay |
| `ContentView` | `Sources/Fluid/ContentView.swift` | Orchestrates the dictation flow end-to-end, updates overlay with status messages |
| `SettingsStore` | `Sources/Fluid/Persistence/SettingsStore.swift` | Stores `enableStreamingPreview`, `transcriptionPreviewCharLimit`, `overlayPosition` |

### Dependency Graph

```
ASRService
  |
  |-- @Published partialTranscription (Combine)
  |-- audioLevelPublisher (Combine PassthroughSubject)
  |
  v
MenuBarManager (subscribes via Combine)
  |
  |-- Calls NotchOverlayManager.show() on recording start
  |-- Calls NotchOverlayManager.updateTranscriptionText() on partial updates
  |-- Calls NotchOverlayManager.hide() on recording stop
  |
  v
NotchOverlayManager
  |
  |-- Routes to NotchExpandedView (DynamicNotchKit) or BottomOverlayWindowController
  |-- Forwards text to NotchContentState.shared.updateTranscription()
  |
  v
NotchContentState (ObservableObject singleton)
  |
  |-- @Published transcriptionText
  |-- @Published cachedPreviewText (tail-truncated to char limit)
  |-- @Published isProcessing
  |-- @Published mode
  |
  v
NotchExpandedView / BottomOverlayView (SwiftUI, observe NotchContentState)
```

---

## 3. Key Code Sections

### 3.1 Streaming Transcription Engine

**File:** `Sources/Fluid/Services/ASRService.swift`

The streaming engine runs a timer-based loop that transcribes audio chunks at a 0.6-second interval:

```swift
// Line 361
private let chunkDurationSeconds: Double = 0.6

// Line 1937-1946
private func startStreamingTranscription() {
    self.streamingTask?.cancel()
    guard self.isAsrReady else { return }
    self.streamingTask = Task { [weak self] in
        await self?.runStreamingLoop()
    }
}
```

The loop (line 1972) calls `processStreamingChunk()` every 0.6 seconds. Each chunk gets the full audio buffer, transcribes it, then computes a smart diff against the previous transcription to avoid text jumping:

```swift
// Lines 2081-2088
if !newText.isEmpty {
    let updatedText = self.smartDiffUpdate(previous: self.previousFullTranscription, current: newText)
    self.partialTranscription = updatedText
    self.previousFullTranscription = newText
}
```

The `smartDiffUpdate` (line 2102) finds the longest common prefix between previous and current transcription and keeps stable text, only appending truly new words.

Streaming is only enabled for models that support it (line 569):
```swift
let model = SettingsStore.shared.selectedSpeechModel
if model.supportsStreaming {
    self.startStreamingTranscription()
}
```

Models like Whisper Medium/Large are marked `supportsStreaming = false` because they are too slow for real-time chunk processing.

### 3.2 Combine Bridge: ASRService to Overlay

**File:** `Sources/Fluid/Services/MenuBarManager.swift`, lines 92-103

```swift
// Subscribe to partial transcription updates for streaming preview
asrService.$partialTranscription
    .receive(on: DispatchQueue.main)
    .sink { [weak self] newText in
        guard self != nil else { return }
        if SettingsStore.shared.enableStreamingPreview {
            NotchOverlayManager.shared.updateTranscriptionText(newText)
        }
    }
    .store(in: &self.cancellables)
```

This is the critical bridge. `ASRService.partialTranscription` is a `@Published var` that gets updated every ~0.6 seconds with the latest streaming transcription. `MenuBarManager` subscribes to it and forwards the text to `NotchOverlayManager`, but **only if the user has enabled streaming preview**.

### 3.3 Overlay State Management

**File:** `Sources/Fluid/Views/NotchContentViews.swift`, lines 14-117

`NotchContentState` is a `@MainActor` singleton `ObservableObject` that holds all state for the overlay UI:

```swift
@MainActor
class NotchContentState: ObservableObject {
    static let shared = NotchContentState()
    private static let maxStoredTranscriptionCharacters = SettingsStore.transcriptionPreviewCharLimitRange.upperBound // 800

    @Published var transcriptionText: String = ""
    @Published var mode: OverlayMode = .dictation
    @Published var isProcessing: Bool = false
    @Published private(set) var cachedPreviewText: String = ""
```

The `updateTranscription()` method (line 86) bounds the stored text to 800 characters max and recomputes the preview:

```swift
func updateTranscription(_ text: String) {
    let boundedText = Self.tailCharacters(in: text, maxCharacters: Self.maxStoredTranscriptionCharacters)
    guard boundedText != self.transcriptionText else { return }
    self.transcriptionText = boundedText
    self.recomputeTranscriptionLines()
}
```

The `recomputeTranscriptionLines()` method (line 95) further truncates to the user's configured `transcriptionPreviewCharLimit` (default 150 chars) and stores the result in `cachedPreviewText` to avoid recomputing on every SwiftUI render.

### 3.4 Transcription Preview in the Notch View

**File:** `Sources/Fluid/Views/NotchContentViews.swift`, lines 452-483

```swift
// Transcription preview (wrapped, fixed width)
if self.hasTranscription && !self.contentState.isProcessing {
    let previewText = self.contentState.cachedPreviewText
    if !previewText.isEmpty {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                Text(previewText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(height: 1).id("bottom")
            }
            .frame(width: self.previewMaxWidth, alignment: .leading) // 180pt
            .frame(maxHeight: self.previewMaxHeight, alignment: .leading) // 60pt
            .clipped()
            .onChange(of: previewText) { _, _ in
                DispatchQueue.main.async {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }
}
```

Key design decisions:
- Uses `ScrollViewReader` + `ScrollView` with auto-scroll to bottom so new text is always visible
- Fixed max width of 180pt and max height of 60pt
- Hidden when `isProcessing` is true (replaced by shimmer animation)
- Font: system 10pt medium, white at 75% opacity on black background

---

## 4. Data Flow

Here is the complete data flow from microphone to screen:

```
1. AVAudioEngine tap (CoreAudio realtime thread)
     |
     v
2. AudioCapturePipeline (off-main-thread)
     |
     |-- Appends PCM samples to ThreadSafeAudioBuffer
     |-- Computes audio level -> DispatchQueue.main -> audioLevelSubject.send(level)
     |
     v
3. ASRService.runStreamingLoop() (main actor, every 0.6s)
     |
     |-- Reads audioBuffer.getPrefix(count) -> [Float] chunk
     |-- TranscriptionExecutor.run { provider.transcribe(chunk) }
     |-- smartDiffUpdate() to stabilize text
     |-- Sets partialTranscription = updatedText  (@Published)
     |
     v
4. MenuBarManager (Combine subscriber on DispatchQueue.main)
     |
     |-- Checks SettingsStore.shared.enableStreamingPreview
     |-- Calls NotchOverlayManager.shared.updateTranscriptionText(newText)
     |
     v
5. NotchOverlayManager.updateTranscriptionText()
     |
     |-- Calls NotchContentState.shared.updateTranscription(text)
     |
     v
6. NotchContentState.updateTranscription()
     |
     |-- Bounds to maxStoredTranscriptionCharacters (800)
     |-- Recomputes cachedPreviewText (tail chars to user limit, default 150)
     |-- @Published properties fire
     |
     v
7. SwiftUI View (@ObservedObject NotchContentState.shared)
     |
     |-- NotchExpandedView or BottomOverlayView re-renders
     |-- ScrollViewReader auto-scrolls to bottom
```

### Audio Level Flow (for waveform visualization)

Runs in parallel to the transcription flow:

```
AudioCapturePipeline.onLevel callback
  -> DispatchQueue.main
  -> audioLevelSubject.send(level)
  -> audioLevelPublisher (AnyPublisher<CGFloat, Never>)
  -> Passed to NotchOverlayManager.show(audioLevelPublisher:mode:)
  -> Passed to NotchExpandedView(audioPublisher:) or routed through
     NotchContentState.bottomOverlayAudioLevel for bottom overlay
  -> AudioVisualizationData @StateObject subscribes
  -> NotchWaveformView / BottomWaveformView animate bars
```

---

## 5. UI Implementation

### Two Overlay Modes

FluidVoice supports two overlay positions, controlled by `SettingsStore.shared.overlayPosition`:

#### 5.1 Top/Notch Overlay (DynamicNotchKit)

**File:** `Sources/Fluid/Services/NotchOverlayManager.swift`, lines 199-239

Uses the third-party library [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) (from Package.swift line 15):

```swift
let newNotch = DynamicNotch(
    hoverBehavior: [.keepVisible, .hapticFeedback],
    style: .auto
) {
    NotchExpandedView(audioPublisher: audioLevelPublisher)
} compactLeading: {
    NotchCompactLeadingView()
} compactTrailing: {
    NotchCompactTrailingView()
}
```

DynamicNotchKit provides a macOS notch-area overlay with expand/compact states. FluidVoice uses:
- **Expanded state**: Shows waveform, mode label, transcription preview text, prompt selector
- **Compact leading**: Pulsing waveform icon
- **Compact trailing**: Pulsing circle indicator

The notch is shown with `await newNotch.expand()` and hidden with `await notch.hide()`.

#### 5.2 Bottom Overlay (Custom NSPanel)

**File:** `Sources/Fluid/Views/BottomOverlayView.swift`, lines 15-194

A custom `NSPanel` with these properties:
```swift
let panel = NSPanel(
    contentRect: .zero,
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
panel.isFloatingPanel = true
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = false
panel.isMovableByWindowBackground = false
panel.hidesOnDeactivate = false
```

Key characteristics:
- `nonactivatingPanel` -- does not steal focus from the user's active app
- `isFloatingPanel` + `.floating` level -- stays above other windows
- `.canJoinAllSpaces` -- follows the user across Spaces/desktops
- `.fullScreenAuxiliary` -- can overlay fullscreen apps
- Position: horizontally centered, vertically offset from bottom (configurable via `overlayBottomOffset`, default 80pt)
- Supports three sizes (small/medium/large) via `LayoutConstants`

The SwiftUI content is hosted via `NSHostingView<BottomOverlayView>`.

Show/hide animations use `NSAnimationContext`:
```swift
// Show
NSAnimationContext.runAnimationGroup { context in
    context.duration = 0.25
    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
    self.window?.animator().alphaValue = 1
}

// Hide
NSAnimationContext.runAnimationGroup { context in
    context.duration = 0.2
    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
    window.animator().alphaValue = 0
}
```

---

## 6. Update Mechanism

The real-time update mechanism uses **Combine publishers + SwiftUI observation**:

1. **ASRService** publishes `@Published var partialTranscription: String` which is updated every ~0.6 seconds by the streaming loop.

2. **MenuBarManager** subscribes to `asrService.$partialTranscription` via Combine `.sink()` and forwards to the overlay manager.

3. **NotchContentState** is an `ObservableObject` singleton. When `updateTranscription()` is called, it sets `@Published var transcriptionText` and `@Published var cachedPreviewText`.

4. **SwiftUI views** (`NotchExpandedView`, `BottomOverlayView`) hold `@ObservedObject private var contentState = NotchContentState.shared` and automatically re-render when published properties change.

5. **Auto-scroll**: `ScrollViewReader` with `.onChange(of: previewText)` calls `proxy.scrollTo("bottom")` to keep the latest text visible.

There is **no polling**. The entire pipeline is reactive:
- Audio tap -> buffer (CoreAudio thread)
- Timer fires every 0.6s -> transcribes chunk -> updates `@Published` property
- Combine propagates to MenuBarManager
- MenuBarManager writes to NotchContentState
- SwiftUI observes NotchContentState and re-renders

### Performance Optimizations

- **Cached preview text**: `NotchContentState.cachedPreviewText` is recomputed only when `transcriptionText` actually changes (line 88: `guard boundedText != self.transcriptionText else { return }`), avoiding redundant SwiftUI re-renders.
- **Bounded storage**: Text is capped at 800 characters max to prevent memory growth during long recordings.
- **Smart diff**: `ASRService.smartDiffUpdate()` prevents the text from jumping around by finding common prefixes between consecutive transcriptions.
- **Chunk skip**: If transcription takes longer than the 0.6s interval, the next chunk is skipped to prevent queue buildup.
- **TranscriptionExecutor actor**: Serializes all CoreML transcription operations to prevent concurrent access issues.
- **drawingGroup()** on streaming command output text (line 1026 of NotchContentViews.swift) flattens to bitmap for faster rendering during rapid updates.

---

## 7. Lifecycle

### Appearance

1. User presses hotkey
2. `ContentView` calls `asr.start()` which sets `asr.isRunning = true`
3. `MenuBarManager` receives this via Combine subscription on `asrService.$isRunning`
4. `handleOverlayState(isRunning: true)` is called
5. After a 30ms debounce delay, `NotchOverlayManager.shared.show(audioLevelPublisher:mode:)` is called
6. Based on `SettingsStore.shared.overlayPosition`:
   - **Top**: Creates a `DynamicNotch` with SwiftUI views and calls `await newNotch.expand()`
   - **Bottom**: `BottomOverlayWindowController.shared.show()` creates/shows the `NSPanel`
7. Overlay is now visible with waveform animation

### During Recording

- Every 0.6 seconds, `partialTranscription` is updated
- If `enableStreamingPreview` is true, text flows through to the overlay
- Waveform animates based on `audioLevelPublisher` (Combine `PassthroughSubject<CGFloat, Never>`)
- User sees rolling transcription text with auto-scroll

### Processing Phase

1. User stops recording (releases hotkey or presses again)
2. `ContentView` calls `menuBarManager.setProcessing(true)` and `NotchOverlayManager.shared.updateTranscriptionText("Transcribing...")`
3. `isProcessing` becomes true in `NotchContentState`
4. The transcription preview text is hidden; a `ShimmerText` animation shows "Transcribing..." / "Refining..."
5. The overlay stays visible (processing flag prevents `handleOverlayState` from hiding it)

### Disappearance

1. Final transcription + optional AI processing completes
2. `menuBarManager.setProcessing(false)` is called
3. This sets `isProcessingActive = false` and `overlayVisible = false`
4. After a 30ms debounce, `NotchOverlayManager.shared.hide()` is called
5. For notch: `await notch.hide()` collapses the DynamicNotch
6. For bottom: `NSAnimationContext` fades alpha to 0, then `window.orderOut(nil)`

### Positioning

- **Notch overlay**: Positioned by DynamicNotchKit in the macOS notch area
- **Bottom overlay**: Horizontally centered on screen, vertical position = `visibleFrame.minY + overlayBottomOffset` (default 80pt from bottom), clamped to stay within visible frame. Listens for `OverlayOffsetChanged` notifications to reposition live when user changes the setting.

### Dismissal

- **Escape key**: Both global and local `NSEvent` monitors watch for keyCode 53 (Escape) and call `hide()` or `hideExpandedCommandOutput()` as appropriate.
- **Auto-dismiss**: Hides when recording + processing is complete.
- **Mode transitions**: If expanded command output is showing and user starts a non-command recording, the expanded view is closed and the regular overlay is shown.

---

## 8. Applicability to ParaDict

### What ParaDict Already Has

ParaDict uses Parakeet V3 via FluidAudio (same as FluidVoice's default model), with a `DictationCoordinator` state machine that goes through `idle -> recording -> transcribing -> [enhancing] -> pasting -> idle`. It already has a `RecordingService` wrapper for audio and a `PastingService` for output.

### What Would Need to Be Added

#### 8.1 Streaming Transcription During Recording

**This is the biggest piece.** ParaDict currently transcribes only after recording stops. To show a live preview, you need:

1. **A timer-based streaming loop** that transcribes accumulated audio every ~0.6 seconds while still recording. FluidVoice's approach (line 1937-2007 of ASRService.swift) is straightforward:
   - Maintain a thread-safe audio buffer that the audio tap appends to
   - Every 0.6s, copy the entire buffer and transcribe it
   - Use a smart diff to avoid text jumping
   - Publish the result as a `@Published` property

2. **A `TranscriptionExecutor` actor** (or similar) to serialize CoreML operations, since Parakeet's CoreML model cannot handle concurrent access.

3. **Skip logic**: If transcription takes longer than the interval, skip the next chunk to prevent queue buildup. This is important for keeping the system responsive on slower machines.

4. **A `@Published var partialTranscription`** on whatever service manages transcription, so the UI layer can observe it via Combine or async/await.

#### 8.2 Overlay Widget

ParaDict already has a recording indicator. The preview could be added there, or a new overlay could be created. Based on FluidVoice's approach:

- **Simplest path**: Use a floating `NSPanel` (like `BottomOverlayWindowController`). Key flags: `.borderless`, `.nonactivatingPanel`, `.isFloatingPanel`, `.floating` level, `.canJoinAllSpaces`. This does not steal focus and works across all Spaces.
- **Alternative**: Use DynamicNotchKit if you want the notch-area aesthetic. It's a single SPM dependency.
- **SwiftUI content**: Host via `NSHostingView`. The content is a simple `VStack` with waveform + transcription text.
- **Auto-scroll**: Use `ScrollViewReader` + `ScrollView` + `.onChange(of: text)` to scroll to bottom.

#### 8.3 State Container

Create an `ObservableObject` singleton (like `NotchContentState`) to hold:
- `transcriptionText: String` -- the streaming preview text
- `isProcessing: Bool` -- for showing "Transcribing..." / "Refining..." states
- `cachedPreviewText: String` -- tail-truncated to a configurable character limit

This keeps the overlay views simple -- they just observe and render.

#### 8.4 Settings

Add:
- `enableStreamingPreview: Bool` (default `true`) -- "Show Live Preview" toggle
- `transcriptionPreviewCharLimit: Int` (default 150, range 50-800) -- controls how much text is shown

#### 8.5 Gotchas and Considerations

1. **CoreML serialization is critical.** FluidVoice uses a custom `TranscriptionExecutor` actor to ensure only one CoreML transcription runs at a time. Without this, you will get race conditions and crashes. ParaDict's `ParakeetTranscriptionService` would need similar protection if streaming and final transcription can overlap.

2. **Buffer management.** The streaming loop reads the entire buffer each time (not just new samples). This means each transcription gets the full context, which improves accuracy but costs more compute. FluidVoice uses a `ThreadSafeAudioBuffer` with `getPrefix(count)` for safe concurrent access.

3. **Smart diff prevents visual jitter.** Without diffing, each 0.6s transcription of the full buffer could produce slightly different word choices, making the preview text jump around. FluidVoice's `smartDiffUpdate()` finds the longest common prefix and only appends truly new words.

4. **Model warmup.** The first streaming transcription after model load is often slower. FluidVoice tracks this with `hasCompletedFirstTranscription` and shows a "Loading model..." indicator.

5. **The overlay must not steal focus.** Use `NSPanel` with `nonactivatingPanel` style mask. This is essential for a dictation app -- you don't want the preview widget to take focus away from the text field the user is dictating into.

6. **Processing state keeps the overlay alive.** When recording stops, `isRunning` goes false, but you need to keep the overlay visible during the final transcription + AI enhancement phase. FluidVoice uses `isProcessingActive` in `MenuBarManager` and `isProcessing` in `NotchContentState` to prevent premature hiding.

7. **Audio level visualization is separate from transcription.** The waveform is driven by `audioLevelPublisher` (a Combine `PassthroughSubject<CGFloat, Never>`) updated from the audio tap callback. This runs at a much higher frequency than transcription and provides immediate visual feedback even before the first transcription completes.

### Recommended Implementation Order for ParaDict

1. **Add a `ThreadSafeAudioBuffer`** that the recording service fills and the transcription service reads from
2. **Add streaming transcription loop** to `ParakeetTranscriptionService` with a `@Published var partialTranscription`
3. **Add a transcription preview overlay** using `NSPanel` + `NSHostingView` + simple SwiftUI view
4. **Add a preview state singleton** (`@Observable class TranscriptionPreviewState`)
5. **Wire up the Combine/observation pipeline** from transcription service to overlay
6. **Add settings** for enabling/disabling and character limit
7. **Handle the processing phase** -- keep overlay visible with shimmer during final transcription + LLM enhancement
