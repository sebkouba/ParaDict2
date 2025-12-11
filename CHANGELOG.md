# Changelog

All notable changes to ParaDict will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Advanced settings tab with Obsidian integration (configure vault name and enable/disable "daily" keyword)
- "Daily" voice keyword: say "daily" to open Obsidian daily note via URI
- Voice commands for text formatting toggles: say "remove trailing punctuation", "add trailing space", or "add trailing line break" to toggle (matches menu item names)
- Text formatting toggles in menu bar: remove trailing punctuation, add trailing space, add trailing line break (persisted)
- Directory Watcher: Cancel button to stop ongoing transcription queue
- Directory Watcher: "Skip Existing Files" button to mark all current files as processed
- Directory Watcher: Shows pending files count during batch processing
- Playback Pausing Mode: voice-controlled media pause/resume during dictation (say "playback pausing on/off") with menu bar toggle
- Directory Watcher shows processing indicator when transcribing a file
- Directory Watcher feature: automatically transcribe audio files dropped into a watched folder
- Clickable prompts in shortcuts view for quick configuration
- Correction mechanism for dictionary entries
- Remote code project support via tool calls
- Audio source selection tool call
- Terminal command execution in existing windows
- Tool call system (V1) for LLM-powered commands
- Voice command specifications
- Continuous dictation mode (hands-free recording)
- State machine architecture for dictation flow

### Changed
- Config file migration now preserves existing settings when new fields are added (custom decoder with fallback defaults)
- Unified UI styling across all settings tabs (Permissions, Audio, Shortcuts, LLM, Chat, Watcher, Advanced)
- Shortcuts tab now has its own dedicated view with styled cards for each shortcut
- Directory Watcher now uses native AVFoundation for audio conversion (no ffmpeg required)
- Improved how corrections are written into the dictionary
- Removed legacy state manager in favor of new DictationStateMachine

### Fixed
- Crash in TranscriptionEditTracker when extracting edited text from a region shorter than original position
- Menu bar "Open ParaDict" now reliably shows window on current Space (added WindowManager pattern from VoiceInk)
- Replace SwiftUI MenuBarExtra with traditional NSStatusItem to fix intermittent ghost window blocking mouse clicks
- Recording indicator no longer briefly flashes blue after yellow (enhancing) before hiding
- Bundled prompts now correctly copy to Application Support on first launch (were looking in wrong directory)
- Prompts list in LLM Settings now updates automatically when files change (added directory watcher)
- Prompts list now properly refreshes when Refresh button is clicked (view now observes PromptManager)
- Prompt file double extension bug (e.g., `dictation.md.md`) when saving prompts with `.md` in the name
- Directory Watcher now properly restarts when input/output directories change in UI
- Restore GCD background queue for audio sample reading (regression from cleanup commit)
- Playback pausing mode resumes immediately when recording stops (not after paste)
- WAV to float sample conversion optimized (eliminated 81M Data slice allocations)
- Audio conversion no longer blocks UI (moved to GCD background queue)
- Live dictation no longer blocks UI during transcription (moved to background thread)
- Directory Watcher no longer blocks live dictation (uses separate transcription instance)
- Directory Watcher activity log now shows processing duration instead of "time ago"
- Continuous mode bug fix
