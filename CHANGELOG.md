# Changelog

All notable changes to ParaDict will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Audio recording archive: Audio settings can store dictation WAV files with JSON sidecars in a chosen folder, with retention configurable up to 999 days
- x.ai transcription provider option with Settings controls for choosing Parakeet or x.ai and managing the x.ai API key
- Menu bar toggle to send Enter immediately after pasting, making it possible to submit chat messages in one dictation step
- Voice command dictation re-enabled: hold the Command Dictation shortcut and speak to execute commands like "open ParaDict" or "switch to speakers"
- VS Code project opening via voice: command mode dynamically reads recent VS Code projects from state database and injects them into the LLM prompt for fuzzy name matching (e.g., "open pixel" opens /Users/sebastian/code/pixel)
- LLM response time logging: enhancement requests now log elapsed time in milliseconds on both success and timeout, making it easy to diagnose Groq latency issues

### Fixed
- Groq and x.ai API keys now live in the macOS Keychain; existing UserDefaults keys migrate automatically and their plaintext copies are removed
- Long recordings no longer lose quiet final phrases in FluidAudio's short final decoding window
- Stopping dictation now captures a 220 ms post-roll, drains its recording session, and flushes the sample-rate converter before transcription
- Microphone changes preserve already recorded audio, while late callbacks from an old input can no longer contaminate the next dictation
- Audio conversion now fails visibly when no converter can be created and supplies each tap buffer exactly once
- Realtime capture sessions and sample buffers no longer inherit main-actor lifetime handling
- Live preview and final transcription are now strictly serialized so they cannot enter the shared Core ML model concurrently
- Escape cancels in-flight transcription, enhancement, and command tasks without allowing stale results to paste later
- Each recording keeps the transcription provider selected when it began, and paused media resumes only after audio capture has actually stopped
- File transcription now uses FluidAudio's format-aware converter instead of assuming a 44-byte, 16-bit WAV header
- open_project tool parameter mismatch: tools.json defined `project_name` but executor expected `path`, causing all project-open commands to fail
- Command-mode project opening no longer depends entirely on Groq tool calls: simple commands like "open robin" now resolve recent VS Code projects locally before falling back to the LLM

### Fixed
- Recording indicator missing after LLM enhancement timeout: the timeout flash timer from a timed-out enhancement could fire during the next dictation session and hide the indicator window, making it appear as if no indicator was shown
- Command key monitor debounce: releasing Command from the shortcut key combo no longer falsely triggers "Send and Stop" during hands-free dictation

### Added
- Pause media during dictation: automatically pause system media (including browser audio like YouTube) when recording starts, resume when done. Toggle via Advanced settings, menu bar, or voice command ("pause playback")
- Command key "Send and Stop" during hands-free dictation: press Command to transcribe, paste, send Enter, and stop (vs Enter which sends and continues)
- Utterance-level text finalization in streaming preview: confirmed words turn white on silence detection, in-progress words stay gray
- Live transcription preview: streaming transcription shown in a floating overlay while recording (configurable placement: above indicator, subtitle bar, near cursor, or disabled)
- AVAudioEngine-based recording with in-memory audio buffer for real-time transcription access
- TranscriptionExecutor actor serializing CoreML model access to prevent concurrent transcription crashes
- Smart word-level diff algorithm preventing preview text from jumping during streaming updates
- Priority-ordered audio input selection: drag-and-drop to reorder, first available device is used automatically, unchecked devices act as fallback
- Beta expiration system with freedom codes: app expires after hardcoded date, users can enter email + code to unlock permanently
- License tab in settings showing beta status and freedom code entry
- CLI tool (`tools/generate-freedom-code.swift`) to generate unlock codes from email addresses
- Enhancement timeout: configurable timeout that falls back to original transcription when LLM is slow (Advanced settings)
- Advanced settings tab with Obsidian integration (configure vault name and enable/disable "daily" keyword)
- "Daily" voice keyword: say "daily" to open Obsidian daily note via URI
- Voice commands for text formatting toggles: say "remove trailing punctuation", "add trailing space", or "add trailing line break" to toggle (matches menu item names)
- Text formatting toggles in menu bar: remove trailing punctuation, add trailing space, add trailing line break (persisted)
- Directory Watcher: Cancel button to stop ongoing transcription queue
- Directory Watcher: "Skip Existing Files" button to mark all current files as processed
- Directory Watcher: Shows pending files count during batch processing
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
- Upgrade FluidAudio to pinned commit `300165b` with final-window and chunk-seam transcription fixes
- Live transcription preview now processes at most the latest 30 seconds and merges overlapping words, keeping long hands-free recordings responsive without changing final transcription
- Recording level updates are capped at 20 Hz to reduce main-thread work from the realtime audio callback
- Recording archive retention can now be edited by clicking the day count and typing a value
- Live dictation transcribes directly from in-memory audio buffer, eliminating WAV file round-trip to disk
- Upgrade FluidAudio from commit 064164de to v0.12.0 (bug fixes for chunk boundary transcription loss, vocabulary rescoring for long audio)
- Default prompts neutralized for public release with placeholder examples
- Settings now use native macOS UserDefaults/@AppStorage instead of YAML config file
- Removed Chat tab (LLM-powered settings assistant)
- Existing config.yaml settings automatically migrate to UserDefaults on first launch
- Unified UI styling across all settings tabs (Permissions, Audio, Shortcuts, LLM, Watcher, Advanced)
- Shortcuts tab now has its own dedicated view with styled cards for each shortcut
- Directory Watcher now uses native AVFoundation for audio conversion (no ffmpeg required)
- Improved how corrections are written into the dictionary
- Removed legacy state manager in favor of new DictationStateMachine

### Removed
- Command Dictation shortcut from Shortcuts UI (experimental feature hidden for public beta, code preserved for re-enabling)
- "Open Config File" menu item (settings now managed in-app via native tabs)
- LLM chat() method for conversational settings changes (kept enhance() and chatWithTools())
- ConfigManager.swift and YAML config file dependency (Yams kept only for migration)

### Fixed
- Red visual feedback when enhancement times out and falls back to original transcription
- LLMSettings config migration now handles missing timeout fields without losing shortcuts
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
- WAV to float sample conversion optimized (eliminated 81M Data slice allocations)
- Audio conversion no longer blocks UI (moved to GCD background queue)
- Live dictation no longer blocks UI during transcription (moved to background thread)
- Directory Watcher no longer blocks live dictation (uses separate transcription instance)
- Directory Watcher activity log now shows processing duration instead of "time ago"
- Continuous mode bug fix
