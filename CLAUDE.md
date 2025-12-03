# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Log files
use this command to watch or view the logs
```
/usr/bin/log stream --predicate 'subsystem == "com.paradict"' | sed -E 's/^.+ParaDict: \([^)]+\) //'

/usr/bin/log show --last 5m --predicate 'subsystem == "com.paradict"' | sed -E 's/^.+ParaDict: \([^)]+\) //'
```

## Build Commands

```bash
# Build the project
xcodebuild -project ParaDict.xcodeproj -scheme ParaDict -configuration Debug build

# Clean and build
xcodebuild -project ParaDict.xcodeproj -scheme ParaDict clean build

# List available schemes
xcodebuild -list -project ParaDict.xcodeproj

# Stop and restart Xcode (run after successful build)
osascript -e 'tell application "Xcode" to activate' -e 'delay 0.3' -e 'tell application "System Events" to keystroke "." using command down' -e 'delay 0.5' -e 'tell application "System Events" to keystroke "r" using command down'
```

**After successful builds:** Always stop and restart Xcode using the osascript command above. This lets the user see logs in the Xcode console.

### Changelog Maintenance

After every successful build that includes functional changes, update `CHANGELOG.md` in the project root. This tracks what has been implemented.

**When to update:** After a successful `xcodebuild` that compiles new or changed functionality (not just build verification of existing code).

**Format:** Use [Keep a Changelog](https://keepachangelog.com/) style:

```markdown
# Changelog

## [Unreleased]

### Added
- New feature description

### Changed
- Changed behavior description

### Fixed
- Bug fix description
```

**Entry guidelines:**
- Write entries from the user's perspective (what changed for them)
- Be concise but specific (e.g., "Add hold-to-record mode for dictation" not "Add feature")
- Group related changes into single entries
- Move entries from `[Unreleased]` to a version section when releasing

### When to use xcode-build agent vs direct xcodebuild

**Use direct xcodebuild** (via Bash tool) for:
- Simple builds after code changes
- Verifying a fix worked
- Quick "does it compile?" checks

**Use xcode-build agent** only when:
- Build fails with errors that need diagnosing and fixing
- Multiple related errors need to be analyzed together
- You need the analyze → fix → rebuild loop

The agent costs ~10k tokens per invocation. Don't use it for simple verification builds.

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

- **DictationCoordinator** (`DictationCoordinator.swift`): Orchestrates the recording/transcription/pasting pipeline using a state machine pattern. States: `idle → recording → transcribing → [enhancing] → pasting → idle`. Handles correction keyword detection.
- **DictationStateMachine** (`StateMachine/DictationStateMachine.swift`): Pure state machine for dictation flow. Returns side effects to be executed by the coordinator.
- **HotkeyManager** (`HotkeyManager.swift`): Handles keyboard shortcuts via KeyboardShortcuts library. Supports hold-to-record and tap-for-hands-free modes
- **ConfigManager** (`ConfigManager.swift`): YAML-based configuration at `~/Library/Application Support/ParaDict/config.yaml`. File watcher for live reloading
- **ParakeetTranscriptionService** (`Services/ParakeetTranscriptionService.swift`): Parakeet V3 ASR via FluidAudio. Includes VAD for audio > 20 seconds
- **LLMClient** (`Services/LLMClient.swift`): Groq API client (OpenAI-compatible). API key from `GROQ_API_KEY` environment variable
- **RecordingService** (`Services/RecordingService.swift`): AVAudioRecorder wrapper. 16kHz mono WAV output for Parakeet
- **PastingService** (`Services/PastingService.swift`): Pastes text at cursor without polluting clipboard
- **MediaControlService** (`Services/MediaControlService.swift`): System audio mute/unmute during recording
- **AudioDeviceConfig** (`Services/AudioDeviceConfig.swift`): Core Audio device configuration
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

### User Config Files (Important!)

Bundled resources are only copied to Application Support if no file exists. When modifying these files, **you must also update the user's copy**:

| Bundled File | User Copy (must also update) |
|--------------|------------------------------|
| `Resources/tools.json` | `~/Library/Application Support/ParaDict/tools.json` |
| `Resources/prompts/*.md` | `~/Library/Application Support/ParaDict/prompts/*.md` |

The app watches these files for changes, so updates take effect immediately without rebuilding.

```bash
# After editing tools.json, copy to Application Support:
cp ParaDict/Resources/tools.json ~/Library/Application\ Support/ParaDict/tools.json

# After editing prompts, copy them too:
cp ParaDict/Resources/prompts/command.md ~/Library/Application\ Support/ParaDict/prompts/
```

## Development Principles

### File Naming Convention (Strict)

Every Swift file MUST use one of these suffixes. The suffix tells Claude Code exactly what the file does:

| Suffix | Purpose | Contains | Example |
|--------|---------|----------|---------|
| `*Manager` | Orchestrates other components, holds state | Class with dependencies on services | `HotkeyManager`, `ConfigManager` |
| `*Coordinator` | Coordinates complex flows with state machines | Class that owns a state machine and executes side effects | `DictationCoordinator` |
| `*Service` | Single-responsibility capability | Stateless or internal-state-only class | `ParakeetTranscriptionService`, `RecordingService` |
| `*Client` | External API communication | HTTP/network calls, auth | `LLMClient`, `AnalyticsClient` |
| `*View` | SwiftUI view | `struct X: View` | `SettingsView`, `AudioInputView` |
| `*ViewModel` | View state + logic | `@Observable class` for a specific view | `SettingsViewModel` |
| `*Config` | Configuration data structure | Codable struct, no behavior | `AudioDeviceConfig` |
| `*Logger` | Writes to logs/files | Append-only output | `TranscriptionHistoryLogger` |
| `*Tracker` | Observes and records state changes | Metrics, analytics, history | `TranscriptionEditTracker` |

### Where to Put New Files

```
ParaDict/
├── *Manager.swift          # Core orchestration (root level)
├── *Coordinator.swift      # State machine coordinators (root level)
├── *App.swift              # App entry point
├── StateMachine/           # State machine components
│   ├── *StateMachine.swift # Pure state machines (no side effects)
│   ├── *State.swift        # State enums
│   ├── *Event.swift        # Event enums
│   └── *SideEffect.swift   # Side effect enums
├── Services/
│   ├── *Service.swift      # Capabilities (recording, transcription, pasting)
│   ├── *Client.swift       # External APIs
│   ├── *Logger.swift       # Logging/output
│   └── *Tracker.swift      # Observation/metrics
└── Views/
    ├── *View.swift         # Top-level views
    ├── *SettingsView.swift # Settings-related views
    └── FeatureName/        # Feature folders for 3+ related view files
        ├── *View.swift
        ├── *ViewModel.swift
        └── Supporting*.swift
```

### Principles for Claude Code

1. **One type per file**: Each file contains exactly one public type. The filename matches the type name.

2. **Suffix determines location**: If you're creating a `*Service`, it goes in `Services/`. If it's a `*View`, it goes in `Views/`.

3. **Name describes the domain, suffix describes the role**: `Transcription` + `Service` = handles transcription. `Dictation` + `Manager` = orchestrates dictation flow.

4. **When uncertain, check existing patterns**: Before creating a new file, glob for similar suffixes to match existing conventions.

5. **Feature folders at 3+ files**: When a feature needs 3 or more view files, create a subfolder (like `RecordingIndicator/`).

**Reference Codebase:** `/Users/sebastian/code/VoiceInk`
If you are having problems with implementation, or I tell you to look at the reference implementation at this location, there's a Swift application that is more feature-rich than what we've built thus far. You can always go there to look for working code.