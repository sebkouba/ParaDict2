# Plan: Replace Playback Pausing with FluidVoice's MediaRemoteAdapter Approach

## Problem
Our custom `MRMediaRemoteGetNowPlayingInfo` / `MRMediaRemoteGetNowPlayingApplicationIsPlaying` calls via `CFBundleCreate` don't detect browser media (YouTube). FluidVoice uses the `MediaRemoteAdapter` SPM package which runs a Perl+C subprocess via `dlopen` — this works because the subprocess is unsandboxed and can query the MediaRemote framework properly.

## Step 1: Remove all existing playback pausing code

### MediaControlService.swift
- Remove the entire MediaRemote framework bridge section: `mediaRemoteBundle`, typedefs, `MRMediaRemoteSendCommand`, `MRMediaRemoteGetNowPlayingInfo`, `kMRNowPlayingInfoPlaybackRate`, `kMRPlay`, `kMRPause`
- Remove init checks for those symbols
- Remove all media playback control methods: `isMediaPlaying()`, `pauseIfPlaying()`, `pauseMedia()`, `resumeMedia()`
- Keep: audio mute/unmute functionality

### DictationCoordinator.swift
- Remove `isPlaybackPausingEnabled` property + `didPauseMedia`
- Remove init line loading from settings
- Remove `didPauseMedia = false` reset in recording start
- Remove `resumeMediaIfNeeded()` calls in stop/cancel/error
- Remove media pause logic in recording start
- Remove `resumeMediaIfNeeded()` method
- Remove `PlaybackPausingCommand` enum
- Remove voice command parsing branch for playback commands
- Remove `parsePlaybackPausingCommand()` method
- Remove `handlePlaybackPausingCommand()` method
- Remove `togglePlaybackPausing()` method
- Remove `syncPlaybackPausing()` method

### SettingsKeys.swift + AppSettings.swift
- Remove `pauseMediaDuringDictation` key, default, and property

### AdvancedSettingsView.swift
- Remove `@AppStorage` binding and entire "Media Playback" section

### StatusBarController.swift
- Remove `playbackPausingItem`, menu item creation, observer, and toggle action

### CHANGELOG.md
- Remove playback pausing entries

**Verify: build + launch successfully**

## Step 2: Add FluidVoice's MediaRemoteAdapter-based implementation

### Pin MediaRemoteAdapter to correct revision
ParaDict already has MediaRemoteAdapter as SPM dependency but at revision `3529aa2` which removed `getTrackInfo()`. Pin to `78aae86` (same as FluidVoice) which has `getTrackInfo()` and `get` command in the Perl/C layer.

### Create Services/MediaPlaybackService.swift (new file)
Port FluidVoice's `MediaPlaybackService.swift` — a clean wrapper around `MediaController`:
- `pauseIfPlaying() async -> Bool` — uses `mediaController.getTrackInfo()` to check `isPlaying`/`playbackRate`, then `mediaController.pause()`
- `resumeIfWePaused(_ wePaused: Bool) async` — calls `mediaController.play()` only if we paused
- `#if arch(arm64)` guards with Intel stubs
- Uses ParaDict's `Logger` instead of FluidVoice's `DebugLogger`

### Re-add integration in DictationCoordinator.swift
- Add `didPauseMedia` tracking + `isPlaybackPausingEnabled` (persisted)
- On recording start (after audio setup): `MediaPlaybackService.shared.pauseIfPlaying()`
- On stop/cancel/error: `MediaPlaybackService.shared.resumeIfWePaused(didPauseMedia)`

### Re-add settings + UI
- `pauseMediaDuringDictation` in SettingsKeys, AppSettings
- Toggle in AdvancedSettingsView
- Menu bar toggle in StatusBarController
- Voice command parsing

### Re-add CHANGELOG entries

**Verify: build + launch + test with YouTube playing**
