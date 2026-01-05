# ParaDict

A macOS menu bar voice dictation app with local transcription using Parakeet V3 and optional LLM enhancement.

## Features

- **Local Transcription**: Fast, private speech-to-text using [Parakeet V3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) running entirely on your Mac
- **LLM Enhancement**: Optional text refinement via Groq API for formatting, punctuation, and context-aware corrections
- **Multiple Dictation Modes**: Configure different hotkeys for different use cases (casual notes, formal writing, code comments)
- **Hands-Free Mode**: Tap to start, tap to stop - no need to hold the key
- **Continuous Mode**: Keep dictating across multiple recordings with automatic pasting
- **Custom Prompts**: Create task-specific prompts for different writing styles
- **Edit Tracking**: Logs user corrections for potential model fine-tuning (delta learning)
- **Menu Bar App**: Runs quietly in your menu bar with minimal resource usage

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon Mac (M1/M2/M3) recommended for best transcription performance
- ~600MB disk space for Parakeet V3 model (downloaded on first launch)
- Groq API key (free tier available) for LLM enhancement mode

## Permissions

ParaDict requires the following macOS permissions:

| Permission | Why |
|------------|-----|
| **Microphone** | Record audio for transcription |
| **Accessibility** | Paste text at cursor position, detect focused text fields |
| **Screen Recording** | Read text from focused elements for edit tracking |

Grant these in System Settings > Privacy & Security when prompted.

## Installation

### Building from Source

```bash
# Clone, build, and install in one go
git clone https://github.com/sebkouba/ParaDict2.git
cd ParaDict
xcodebuild -project ParaDict.xcodeproj -scheme ParaDict -configuration Release build
cp -r ~/Library/Developer/Xcode/DerivedData/ParaDict-*/Build/Products/Release/ParaDict.app /Applications/
open /Applications/ParaDict.app
```

Or step by step:

1. Clone the repository:
   ```bash
   git clone https://github.com/sebkouba/ParaDict2.git
   cd ParaDict
   ```

2. Build:
   ```bash
   xcodebuild -project ParaDict.xcodeproj -scheme ParaDict -configuration Release build
   ```

3. Install and launch:
   ```bash
   cp -r ~/Library/Developer/Xcode/DerivedData/ParaDict-*/Build/Products/Release/ParaDict.app /Applications/
   open /Applications/ParaDict.app
   ```

## Configuration

Configuration files are stored in `~/Library/Application Support/ParaDict/`:

### config.yaml

Main configuration file with hotkeys, audio settings, and LLM configuration:

```yaml
app:
  hide_dock_icon: true
  launch_at_login: false
  mute_during_recording: true

audio:
  device: "default"

llm:
  provider: "groq"
  model: "moonshotai/kimi-k2-instruct-0905"

hotkeys:
  - shortcut: "option+d"
    mode: "local"
    prompt: null

  - shortcut: "option+shift+d"
    mode: "enhanced"
    prompt: "default"
```

### Prompts

Prompts are stored in `~/Library/Application Support/ParaDict/prompts/`. Reference them by name in your hotkey config (e.g., `prompt: "default"`).

Bundled prompts:
- `default.md` - General dictation cleanup (grammar, punctuation, formatting)
- `command.md` - Voice commands with tool execution
- `reply.md` - Generate replies based on clipboard context (copy text first, then dictate your response instructions)

You can create custom prompts by adding `.md` files to the prompts folder or editing existing ones in the app's LLM settings.

### Tools (Voice Commands)

When using the `command` prompt, ParaDict can execute actions via LLM tool calling. Tools are defined in `~/Library/Application Support/ParaDict/tools.json`.

Built-in tools:
| Tool | Description | Example |
|------|-------------|---------|
| `open_project` | Open a project in VS Code | "open ParaDict" |
| `open_app` | Launch macOS applications | "open Safari" |
| `open_url` | Open URLs in browser | "open github.com" |
| `run_shell` | Execute shell commands | "run ls" |
| `set_audio_output` | Switch audio output device | "switch to speakers" |
| `list_audio_outputs` | List available audio devices | "what audio devices do I have" |

Edit `tools.json` to add custom tools or modify existing ones. Each tool needs a `name`, `description`, `parameters`, and `executor`.

### Resource Bundling

On first launch, ParaDict copies bundled prompts and tools to Application Support. Your customizations are preserved on subsequent launches—the app only copies files that don't already exist.

### Setting Up Groq API

1. Get a free API key from [console.groq.com](https://console.groq.com)
2. Open ParaDict settings and paste your API key in the LLM tab
   - The app will verify your key works before saving

## Usage

### Basic Dictation

1. **Hold-to-Record**: Hold your hotkey, speak, release to transcribe and paste
2. **Hands-Free Mode**: Tap hotkey to start recording, tap again to stop

### Audio Settings

**Input Device**: Choose your microphone in Settings > Audio Input. By default, ParaDict uses your system's default input device. Select any connected microphone from the dropdown.

**Mute During Recording**: When enabled (`mute_during_recording: true` in config), ParaDict automatically pauses system audio playback when you start recording and resumes it when done. This prevents music, podcasts, or video audio from being picked up by your microphone during dictation.

### Dictation Modes

- **Local Mode**: Direct transcription without LLM processing - fastest, most private
- **Enhanced Mode**: Transcription + LLM refinement for better formatting and corrections

Partially ready
- **Command Mode**: Execute voice commands via tool calling (experimental)
- **Reply Mode**: Copy the text that you want to respond to. Click in the field where you want the response to go, then dictate your instructions using the reply keyboard shortcut.

### Continuous Mode

Add `continueAfter: true` to a hotkey config to enable continuous mode:
- After pasting, recording automatically restarts
- Press Enter twice quickly to exit continuous mode

### Correction Feature
After any dictation, you can say "correction" and only that into the app. This will open a pop-up that allows you to write instructions that are saved in a dictionary for how to fix the error that happened in the future. This helps build up a custom dictionary with very low friction.

## Data & Privacy

- **Transcription**: All speech-to-text happens locally via Parakeet V3
- **LLM Enhancement**: Only enabled if you configure it; sends text to Groq API
- **Logging**: Transcription history stored locally for your review
- **Edit Tracking**: User corrections logged locally for potential model improvement

### Log Files

```bash
# View live logs
log stream --predicate 'subsystem == "com.paradict"'

# Transcription history
cat ~/Library/Application\ Support/ParaDict/transcription_history.csv

# User edits (for delta learning)
cat ~/Library/Application\ Support/ParaDict/transcription_edits.log

# Corrections (dictionary entries from correction feature)
cat ~/Library/Application\ Support/ParaDict/corrections.tsv
```

## Architecture

ParaDict uses a state machine architecture for reliable dictation flow:

```
Hotkey Press -> Recording -> Transcription -> [Enhancement] -> Pasting
```

Key components:
- `DictationCoordinator` - Orchestrates the recording/transcription/pasting pipeline
- `DictationStateMachine` - Pure state machine for predictable transitions
- `ParakeetTranscriptionService` - Local ASR via FluidAudio
- `LLMClient` - Groq API integration for text enhancement

See [CLAUDE.md](CLAUDE.md) for detailed architecture documentation.

## Contributing

Contributions are welcome! Please read [CLA.md](CLA.md) before submitting pull requests.

This project uses a dual-licensing model:
- **Open Source**: GNU General Public License v3 (GPLv3)
- **Commercial**: Contact for commercial licensing options

## License

This project is licensed under the GNU General Public License v3 - see [LICENSE](LICENSE) for details.

## Acknowledgments

- [Parakeet V3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) by NVIDIA for the ASR model
- [FluidAudio](https://github.com/argmaxinc/FluidAudio) for Swift Parakeet integration
- [Groq](https://groq.com) for fast LLM inference API
