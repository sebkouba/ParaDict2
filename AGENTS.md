# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

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

### Required Deployment and Relaunch

After completing any user-requested change in this repository, do not stop at a successful Xcode build or leave a DerivedData copy running. Before reporting completion:

1. Build the current `ParaDict` Debug scheme successfully.
2. Terminate any running `ParaDict` process.
3. Replace `/Applications/ParaDict.app` with the freshly built app bundle.
4. Launch `/Applications/ParaDict.app`.
5. Verify that ParaDict is running and that its executable path is `/Applications/ParaDict.app/Contents/MacOS/ParaDict`.

The user should always have the newly changed version installed and running when the task is handed back.

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

### Building and installing a signed release locally

`script/build_and_run.sh` (Debug build, see "Required Deployment and Relaunch") needs an **Apple Development** certificate for team `2VVZV5X37Y`. On a Mac that only has the **Developer ID Application** certificate, use `script/archive_release.sh` instead to do the same deployment: it builds a Developer ID-signed Release, which then replaces `/Applications/ParaDict.app`.

macOS keeps Microphone/Accessibility permissions based on the code signature (bundle ID `com.hiq.ParaDict` + signing certificate). Rebuilding with the same certificate keeps the existing permissions. Switching between Apple Development (Debug) and Developer ID (Release) builds counts as a different app, so macOS asks again.

```bash
# Build and sign. Output goes to build/release.XXXXXX/ (the script prints the .app path)
# Leave off DEVELOPER_DIR if `xcode-select -p` already points at /Applications/Xcode.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/archive_release.sh

# Install and relaunch (replace release.XXXXXX with the folder the script printed)
osascript -e 'quit app "ParaDict"'
rm -rf /Applications/ParaDict.app
ditto build/release.XXXXXX/ParaDict.xcarchive/Products/Applications/ParaDict.app /Applications/ParaDict.app
open /Applications/ParaDict.app
```

Requirements:
- The "Developer ID Application: Sebastian Kouba (2VVZV5X37Y)" certificate with its private key must be in the login keychain (check with `security find-identity -v -p codesigning`).
- Local installs don't need notarization. Only downloaded copies do.
- Set `PARADICT_RELEASE_OUTPUT_DIR` to choose a fixed output folder (it must not already contain an archive).

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
- **AppSettings** (`Settings/AppSettings.swift`): Observable singleton for app-wide settings using UserDefaults/@AppStorage
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
- **Yams**: YAML parsing (for one-time migration from legacy config)

### UI Structure

Menu bar app with a single window containing tabs:
- Permissions (microphone, accessibility, screen recording status)
- Audio Input (device selection)
- Shortcuts (keyboard shortcut configuration)
- LLM (model selection, timeout settings)
- Directory Watcher (batch transcription)
- Advanced (dock icon, Obsidian integration)
- License (beta license management)

### Settings Storage

All settings are stored using native macOS patterns:
- **UserDefaults/@AppStorage**: All app preferences (see `Settings/SettingsKeys.swift`)
- **KeyboardShortcuts library**: Handles shortcut persistence automatically
- **Keychain**: API keys (via environment variable `GROQ_API_KEY`)

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

Every Swift file MUST use one of these suffixes. The suffix tells Codex exactly what the file does:

| Suffix | Purpose | Contains | Example |
|--------|---------|----------|---------|
| `*Manager` | Orchestrates other components, holds state | Class with dependencies on services | `HotkeyManager`, `MenuBarManager` |
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
├── Settings/               # Settings infrastructure
│   ├── SettingsKeys.swift  # UserDefaults key constants
│   ├── AppSettings.swift   # Observable settings singleton
│   └── SettingsMigration.swift # Legacy config migration
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

### Principles for Codex

1. **One type per file**: Each file contains exactly one public type. The filename matches the type name.

2. **Suffix determines location**: If you're creating a `*Service`, it goes in `Services/`. If it's a `*View`, it goes in `Views/`.

3. **Name describes the domain, suffix describes the role**: `Transcription` + `Service` = handles transcription. `Dictation` + `Manager` = orchestrates dictation flow.

4. **When uncertain, check existing patterns**: Before creating a new file, glob for similar suffixes to match existing conventions.

5. **Feature folders at 3+ files**: When a feature needs 3 or more view files, create a subfolder (like `RecordingIndicator/`).

## Debugging UI Blocking (Rainbow Wheel)

**When the UI freezes, check the ENTRY POINT first, not the processing code.**

Before wrapping code in `Task.detached`, `DispatchQueue.global()`, or optimizing algorithms, ask:

1. **What triggers this code path?** (callback, notification, timer, etc.)
2. **What thread/queue is the trigger running on?**

Search for these patterns:
```bash
grep -rn "DispatchQueue.main" ParaDict/
grep -rn "FSEventStreamSetDispatchQueue" ParaDict/
grep -rn "@MainActor" ParaDict/
```

If ANY entry point runs on `DispatchQueue.main` or is `@MainActor`, everything downstream blocks the UI—no matter how much async/await wrapping you add inside.

**Fix the entry point, not the symptoms.**

## Custom principles
- for any voice action that changes settings, what to say should be a toggle and the words should be visible in the task bar menu so they are easy to check and learn and get feedback on. maybe the toggle could be confirmed with a flash of words in the speaking indicator window. This doesn't work for real tool calls, but we should always check whether it makes sense for a particular feature
