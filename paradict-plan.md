# Development Plan: ParaDict

**Project Location:** `/Users/sebastian/code/ParaDict`

## Overview

Build a minimal macOS voice dictation app that uses Parakeet V3 exclusively for transcription, with optional LLM enhancement via Groq (Kimi K2). The "UI" is primarily an LLM chat interface that can read/modify the config file, replacing traditional settings screens.

**Reference Codebase:** `/Users/sebastian/code/VoiceInk`

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  config.yaml                                                     │
│  - hotkeys → prompt mappings                                    │
│  - LLM settings (provider, model, api_key env var)              │
│  - audio device preferences                                     │
│  - app settings (dock icon, launch at login, mute audio)        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Menu Bar App (daemon)                                          │
│  - Listens for configured hotkeys                               │
│  - Records → Parakeet V3 transcription                          │
│  - Routes to prompt based on hotkey (or pastes directly)        │
│  - Pastes result at cursor                                      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Chat Window (the only real UI)                                 │
│  - LLM has config.yaml in context                               │
│  - User asks questions about settings                           │
│  - LLM modifies config file directly                            │
│  - Also shows: Permissions status, Audio input selector         │
└─────────────────────────────────────────────────────────────────┘
```

## Two Dictation Modes

1. **Local Only**: Hotkey → Record → Parakeet V3 → Paste
2. **LLM Enhanced**: Hotkey → Record → Parakeet V3 → LLM (Groq/Kimi K2) → Paste

Each hotkey maps to either local-only or a specific LLM prompt.

---

## Files to Extract from VoiceInk

### Core Functionality (copy and adapt)

| File | Purpose | Modifications Needed |
|------|---------|---------------------|
| `VoiceInk/Services/ParakeetTranscriptionService.swift` | Parakeet V3 transcription | Simplify: remove v2 support, hardcode v3 |
| `VoiceInk/Recorder.swift` | Audio recording with AVAudioRecorder | Minimal changes |
| `VoiceInk/CursorPaster.swift` | Paste at cursor without clipboard pollution | Use as-is |
| `VoiceInk/MediaController.swift` | Mute/unmute system audio during recording | Use as-is |
| `VoiceInk/MenuBarManager.swift` | Hide dock icon functionality | Use as-is |

### Permissions (copy exactly)

| File | Purpose |
|------|---------|
| `VoiceInk/Views/PermissionsView.swift` | Permission cards with status indicators |
| Permission checking logic from PermissionsView | `AVCaptureDevice.authorizationStatus`, `AXIsProcessTrusted()`, `CGPreflightScreenCaptureAccess()` |

### Audio Input (copy exactly)

| File | Purpose |
|------|---------|
| `VoiceInk/Views/Settings/AudioInputSettingsView.swift` | Device selection UI |
| `VoiceInk/Services/AudioDeviceManager.swift` | Device enumeration and selection |
| `VoiceInk/Services/AudioDeviceConfiguration.swift` | Core Audio device configuration |

### Hotkey System (adapt)

| File | Purpose | Modifications |
|------|---------|---------------|
| `VoiceInk/HotkeyManager.swift` | Modifier key detection | Adapt to support N hotkeys mapped to prompts |

---

## New Components to Build

### 1. ConfigManager.swift
Loads and saves config.yaml, provides typed access to settings.

```yaml
# config.yaml example
app:
  hide_dock_icon: true
  launch_at_login: true
  mute_during_recording: true

audio:
  device: "system_default"  # or device UID

llm:
  provider: groq
  model: kimi-k2
  api_key_env: GROQ_API_KEY

hotkeys:
  - shortcut: right_option
    mode: local  # Parakeet only, no LLM

  - shortcut: right_command
    mode: enhanced
    prompt: |
      Clean up this transcription. Fix grammar, punctuation,
      and formatting. Output only the cleaned text.

  - shortcut: ctrl+shift+a
    mode: enhanced
    prompt: |
      Answer this question concisely. The user asked via voice:

custom_vocabulary:
  - "Parakeet"
  - "Groq"
  - "Kimi K2"
```

### 2. LLMClient.swift
Simple HTTP client for Groq API (OpenAI-compatible).

```swift
struct LLMClient {
    func enhance(text: String, systemPrompt: String) async throws -> String
    func chat(messages: [Message], configContext: String) async throws -> String
}
```

### 3. ChatView.swift
SwiftUI view for chatting with the settings LLM.

- Shows conversation history
- Text input field
- LLM has config.yaml contents in system prompt
- LLM can output special commands to modify config (parsed and applied)

### 4. App Entry Point
Minimal SwiftUI app with:
- Menu bar icon (always)
- Single window with tabs: Chat | Permissions | Audio Input
- No complex navigation, no dashboard, no history

---

## Implementation Phases

### Phase 1: Project Setup
1. Create new Xcode project (macOS App, SwiftUI)
2. Add Swift Package dependencies:
   - FluidAudio (Parakeet)
   - KeyboardShortcuts
   - LaunchAtLogin-Modern
   - Yams (YAML parsing)
3. Set up basic menu bar app structure
4. Create config.yaml schema and ConfigManager

### Phase 2: Core Recording Pipeline
1. Copy and adapt Recorder.swift
2. Copy ParakeetTranscriptionService.swift (simplify to v3 only)
3. Copy CursorPaster.swift
4. Copy MediaController.swift
5. Wire up: hotkey → record → transcribe → paste

### Phase 3: LLM Enhancement
1. Build LLMClient for Groq API
2. Implement prompt routing based on hotkey config
3. Add custom vocabulary injection into prompts

### Phase 4: Settings UI
1. Copy PermissionsView.swift (exact copy of permission cards)
2. Copy AudioInputSettingsView.swift and AudioDeviceManager.swift
3. Add app settings toggles (dock icon, launch at login, mute audio)

### Phase 5: Chat Interface
1. Build ChatView with conversation history
2. Implement config-aware system prompt for LLM
3. Add config modification commands (LLM outputs YAML patches)
4. Parse and apply config changes

### Phase 6: Polish
1. Keyboard shortcut recorder UI for adding new hotkeys
2. Config file watcher for external edits
3. Error handling and user feedback
4. Menu bar status indicators during recording

---

## Dependencies

```swift
// Package.swift or Xcode SPM dependencies
.package(url: "https://github.com/FluidInference/FluidAudio", from: "1.0.0"),
.package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
.package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern", branch: "main"),
.package(url: "https://github.com/jpsim/Yams", from: "5.0.0"),
```

---

## Key Design Decisions

1. **Parakeet V3 only**: No model selection UI, no Whisper. Faster, simpler.

2. **Config file as source of truth**: All settings in YAML, human-readable, version-controllable.

3. **LLM-as-UI for settings**: Users can ask "how do I add a new hotkey?" and the LLM explains + modifies config.

4. **Groq with Kimi K2**: Hardcoded provider choice for speed + intelligence. API key via environment variable.

5. **Minimal traditional UI**: Only Permissions and Audio Input get dedicated views (complex enough to warrant UI). Everything else via chat or config file.

6. **No history/dashboard initially**: Can add later if needed, but not MVP.

---

## Files Reference from VoiceInk

### Must Copy (Core)
- `VoiceInk/Services/ParakeetTranscriptionService.swift` (~100 lines)
- `VoiceInk/Recorder.swift` (~240 lines)
- `VoiceInk/CursorPaster.swift` (~100 lines)
- `VoiceInk/MediaController.swift` (~120 lines)
- `VoiceInk/MenuBarManager.swift` (~80 lines)

### Must Copy (Settings UI)
- `VoiceInk/Views/PermissionsView.swift` (~300 lines)
- `VoiceInk/Views/Settings/AudioInputSettingsView.swift` (~400 lines)
- `VoiceInk/Services/AudioDeviceManager.swift` (~400 lines)
- `VoiceInk/Services/AudioDeviceConfiguration.swift`

### Reference Only (Adapt Patterns)
- `VoiceInk/HotkeyManager.swift` - hotkey detection patterns
- `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift` - LLM request patterns
- `VoiceInk/VoiceInk.swift` - app initialization patterns

### Do Not Copy
- All of `Views/` except Permissions and AudioInput
- Power Mode system
- Whisper integration
- Cloud transcription providers
- Onboarding
- License management
- History/Dashboard
- Dictionary/WordReplacement views

---

## Xcode Project Setup

When creating the project in Xcode:

1. **New Project** → macOS → App
2. **Product Name**: ParaDict
3. **Interface**: SwiftUI
4. **Language**: Swift
5. **Bundle Identifier**: something like `com.yourname.paradict`
6. **Deployment Target**: macOS 14.0+

Then add the Swift Package dependencies via File → Add Package Dependencies.
