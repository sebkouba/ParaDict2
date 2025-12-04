# Changelog

All notable changes to ParaDict will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- YouTube Mode: voice-controlled media pause/resume during dictation (say "youtube mode on/off" to toggle)
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
- Directory Watcher now uses native AVFoundation for audio conversion (no ffmpeg required)
- Improved how corrections are written into the dictionary
- Removed legacy state manager in favor of new DictationStateMachine

### Fixed
- WAV to float sample conversion optimized (eliminated 81M Data slice allocations)
- Audio conversion no longer blocks UI (moved to GCD background queue)
- Live dictation no longer blocks UI during transcription (moved to background thread)
- Directory Watcher no longer blocks live dictation (uses separate transcription instance)
- Directory Watcher activity log now shows processing duration instead of "time ago"
- Continuous mode bug fix
