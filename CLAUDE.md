# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Log files
use this command to watch or view the logs
```
log stream --predicate 'subsystem == "com.paradict"' | sed -E 's/^.+ParaDict: \([^)]+\) //'

log show --last 5m --predicate 'subsystem == "com.paradict"' | sed -E 's/^.+ParaDict: \([^)]+\) //'
```

## Build Commands

```bash
# Build the project
xcodebuild -project ParaDict.xcodeproj -scheme ParaDict -configuration Debug build

# Clean and build
xcodebuild -project ParaDict.xcodeproj -scheme ParaDict clean build

# List available schemes
xcodebuild -list -project ParaDict.xcodeproj
```

Use the `xcode-build` agent for building and automatically fixing Swift compilation errors.

## Architecture Overview

ParaDict is a macOS menu bar voice dictation app using Parakeet V3 for local transcription with optional LLM enhancement via Groq.

### Core Flow

```
Hotkey Press → Recorder → ParakeetTranscriptionService → [Optional: LLMClient] → CursorPaster
```

### Two Dictation Modes

1. **Local**: Hotkey → Record → Parakeet V3 transcription → Paste at cursor
2. **Enhanced**: Hotkey → Record → Parakeet V3 → LLM (Groq) enhancement → Paste at cursor

### Key Components

- **DictationManager** (`DictationManager.swift`): Orchestrates the recording/transcription/pasting pipeline. Manages state machine: `idle → recording → transcribing → [enhancing] → idle`
- **HotkeyManager** (`HotkeyManager.swift`): Handles keyboard shortcuts via KeyboardShortcuts library. Supports hold-to-record and tap-for-hands-free modes
- **ConfigManager** (`ConfigManager.swift`): YAML-based configuration at `~/Library/Application Support/ParaDict/config.yaml`. File watcher for live reloading
- **ParakeetTranscriptionService** (`Services/ParakeetTranscriptionService.swift`): Parakeet V3 ASR via FluidAudio. Includes VAD for audio > 20 seconds
- **LLMClient** (`Services/LLMClient.swift`): Groq API client (OpenAI-compatible). API key from `GROQ_API_KEY` environment variable
- **Recorder** (`Services/Recorder.swift`): AVAudioRecorder wrapper. 16kHz mono WAV output for Parakeet
- **CursorPaster** (`Services/CursorPaster.swift`): Pastes text at cursor without polluting clipboard
- **PermissionManager** (in `Views/PermissionsView.swift`): Manages Microphone, Accessibility, and Screen Recording permissions

### Dependencies (Swift Package Manager)

- **FluidAudio**: Parakeet V3 ASR models
- **KeyboardShortcuts**: Global hotkey handling
- **LaunchAtLogin**: Login item management
- **Yams**: YAML parsing for config file

### UI Structure

Menu bar app with a single window containing tabs:
- Permissions (microphone, accessibility, screen recording status)
- Audio Input (device selection)
- Shortcuts (keyboard shortcut configuration)
- Chat (LLM-powered settings assistant)

### Config File Schema

Config is YAML at `~/Library/Application Support/ParaDict/config.yaml`:
- `app`: hide_dock_icon, launch_at_login, mute_during_recording
- `audio`: device selection
- `llm`: provider, model, api_key_env
- `hotkeys`: array of shortcut → mode → prompt mappings
- `custom_vocabulary`: words for transcription hints

**Reference Codebase:** `/Users/sebastian/code/VoiceInk`
If you are having problems with implementation, or I tell you to look at the reference implementation at this location, there's a Swift application that is more feature-rich than what we've built thus far. You can always go there to look for working code.