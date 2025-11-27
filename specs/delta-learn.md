# Feature: Track User Edits to Transcriptions

## Overview
Implement a system to track when users edit text that was pasted from our speech-to-text transcriptions. Log the original transcription and the final edited version to a file for later analysis.

## Requirements

### 1. Accessibility Permissions
- Request accessibility permissions if not already granted
- Guide user to System Preferences > Privacy & Security > Accessibility if needed

### 2. Track Pasted Transcriptions
- When a transcription is pasted to the clipboard or inserted into another app, store:
  - The original text
  - Timestamp
  - Target app bundle identifier (if detectable)
  - Reference to the focused AXUIElement

### 3. Monitor for Edits
- Use AXObserver to watch for `AXValueChanged` on the text element where we pasted
- Continue monitoring until:
  - Focus leaves the element, OR
  - A timeout occurs (e.g., 60 seconds of no edits), OR
  - The app loses focus

### 4. Capture Final State
- When monitoring ends, retrieve the current value of the text element
- Compare against original transcription
- If different, log the edit

### 5. Log Format
- Write to: `~/Library/Application Support/[AppName]/transcription_edits.log`
- Format (tab-separated, one entry per line):
```
  [ISO8601 timestamp]\t[original text]\t[edited text]\t[app bundle id]
```
- Escape newlines in text as `\n` literal
- Create file if it doesn't exist, append otherwise

## Implementation Notes
- Keep a dictionary of actively monitored elements, keyed by some identifier
- Clean up observers when monitoring ends
- Handle edge cases: user closes target app, user undoes paste entirely
- Don't log if original and final are identical