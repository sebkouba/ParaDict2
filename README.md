# ParaDict

A macOS menu bar voice dictation app using Parakeet V3 for local transcription with optional LLM enhancement.

## Transcription Edit Tracking (Delta Learning)

**Status:** Work in progress

### What It Does

Tracks when users edit text that was pasted from speech-to-text transcriptions. Logs the original transcription and what it was edited to for later analysis (e.g., fine-tuning or improving transcription accuracy).

### How It Works

1. **After each paste** (`CursorPaster.swift:55-57`), the `TranscriptionEditTracker` starts monitoring:
   - Captures the focused AXUIElement and its current value
   - Records where the transcription appears in the text (position + length)
   - Stores the target app's bundle ID and PID

2. **Monitoring triggers** (event-driven, not polling):
   - `NSWorkspace.didActivateApplicationNotification` - fires when user switches to a different app
   - `kAXFocusedUIElementChangedNotification` - fires when focus changes within the same app
   - 60-second timeout as fallback

3. **When session ends**:
   - Gets the final value of the text element
   - If transcription exists unchanged → no log
   - If transcription was edited → extracts just the edited region using prefix/suffix anchoring
   - Logs: `original transcription` → `edited version`

### Log File Locations

**1. Transcription History (complete log of all dictations):**
```
~/Library/Application Support/ParaDict/transcription_history.csv
```

CSV columns:
- `timestamp` - ISO8601 timestamp
- `event_type` - `local_transcription`, `enhanced_transcription`, or `failed_transcription`
- `mode` - `local` or `enhanced`
- `target_app` - Bundle ID of the app where text was pasted
- `transcription` - Raw transcription from Parakeet
- `llm_prompt` - System prompt sent to LLM (empty for local mode)
- `llm_response` - LLM response (empty for local mode)
- `final_output` - What was actually pasted

**2. Transcription Edits (user corrections):**
```
~/Library/Application Support/ParaDict/transcription_edits.log
```

Tab-separated format:
```
[ISO8601 timestamp]\t[original transcription]\t[edited text]\t[app bundle id]
```

Newlines in text are escaped as `\n` literal.

### Key Files

- `ParaDict/Services/TranscriptionHistoryLogger.swift` - Complete transcription history logging
- `ParaDict/Services/TranscriptionEditTracker.swift` - User edit tracking (delta learning)
- `ParaDict/Services/CursorPaster.swift` - Integration point (calls tracker after paste)
- `ParaDict/DictationManager.swift` - Main orchestration (calls history logger)
- `specs/delta-learn.md` - Original feature spec

### Known Issues / TODO

1. **Extraction bug when transcription is deleted**: If the user sends a message (clearing the input field) or deletes the transcription entirely, the extraction logic can grab the wrong region. Should detect "deleted" case and skip logging or log differently.

2. **Full field content vs. just transcription**: The extraction uses prefix/suffix anchoring which works well when the user edits within the transcribed region, but can get confused if surrounding text changes significantly.

### Viewing Logs

```bash
# Watch live logs
log stream --predicate 'subsystem == "com.paradict"' | sed -E 's/^.+ParaDict: \([^)]+\) //'

# View recent logs
log show --last 5m --predicate 'subsystem == "com.paradict"' | sed -E 's/^.+ParaDict: \([^)]+\) //'

# View edit log file
cat ~/Library/Application\ Support/ParaDict/transcription_edits.log
```
