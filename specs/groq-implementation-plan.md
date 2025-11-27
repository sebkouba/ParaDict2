# Groq LLM Implementation Plan

## Overview

Implement Groq LLM integration with external prompt files, multiple hotkey support, and proper API key management based on the VoiceInk reference implementation.

---

## Phase 1: External Prompt Files

### 1.1 Create Prompts Directory Structure

**Location:** `~/Library/Application Support/ParaDict/prompts/`

```
prompts/
├── default.md          # Default cleanup prompt
├── email.md            # Email formatting prompt
├── chat.md             # Casual chat style
└── custom/             # User-created prompts
    └── my-prompt.md
```

### 1.2 Update Config Schema

**Current config.yaml:**
```yaml
shortcuts:
  local_dictation:
    shortcut: "opt+cmd+e"
  enhanced_dictation:
    shortcut: "ctrl+cmd+d"
    prompt: "Clean up this transcription..."  # inline
```

**New config.yaml:**
```yaml
shortcuts:
  - name: "local"
    shortcut: "opt+cmd+e"
    mode: "local"
  - name: "enhanced"
    shortcut: "ctrl+cmd+d"
    mode: "enhanced"
    prompt_file: "default.md"
  - name: "email"
    shortcut: "ctrl+cmd+m"
    mode: "enhanced"
    prompt_file: "email.md"
```

### 1.3 Files to Modify

- `ConfigManager.swift`: Update `ShortcutsConfig` to support array of shortcuts with prompt file references
- Create `PromptManager.swift`: Load and cache prompts from .md files
- Bundle default prompts in app resources

---

## Phase 2: LLM Service Enhancement

### 2.1 API Key Management (from VoiceInk)

**Storage:** UserDefaults with key `"GROQAPIKey"`

**Validation Flow:**
1. User enters API key in UI
2. Send test request to Groq API
3. If HTTP 200, key is valid - save to UserDefaults
4. If error, show message and don't save

**Test Request (Groq):**
```swift
POST https://api.groq.com/openai/v1/chat/completions
Headers:
  Authorization: Bearer {apiKey}
  Content-Type: application/json
Body:
  {"model": "kimi-k2", "messages": [{"role": "user", "content": "test"}]}
```

### 2.2 Update LLMClient.swift

**Add:**
- `isConfigured: Bool` - Check if API key exists
- `validateAPIKey(_:) async throws -> Bool` - Test API key validity
- `saveAPIKey(_:)` - Store validated key
- `clearAPIKey()` - Remove stored key
- Change from env var to UserDefaults for API key storage

**Keep:**
- `enhance(text:systemPrompt:)` - Already implemented
- `chat(messages:configContext:)` - Already implemented

### 2.3 Create API Key Settings View

New SwiftUI view: `APIKeySettingsView.swift`
- Text field for API key input (secure)
- "Verify" button
- Status indicator (connected/not connected)
- "Clear" button to remove key

---

## Phase 3: Multiple Hotkeys Support

### 3.1 Update Data Models

**New ShortcutConfig struct:**
```swift
struct ShortcutConfig: Codable, Identifiable {
    var id: String { name }
    var name: String
    var shortcut: String
    var mode: DictationMode  // .local or .enhanced
    var promptFile: String?  // nil for local mode
}
```

### 3.2 Dynamic Hotkey Registration

**HotkeyManager changes:**
- Remove fixed `localDictation` / `enhancedDictation` names
- Register hotkeys dynamically from config array
- Map each shortcut to its mode and prompt file
- Handle hotkey changes when config reloads

### 3.3 Keyboard Shortcuts Library Integration

KeyboardShortcuts requires static `Name` declarations. Options:
1. **Pre-define a pool** of 10 shortcut names (`shortcut1`, `shortcut2`, etc.)
2. **Dynamic registration** using `KeyboardShortcuts.Name(rawValue:)`

Recommend option 2 for flexibility.

---

## Phase 4: Prompt Management

### 4.1 Create PromptManager Service

```swift
class PromptManager: ObservableObject {
    static let shared = PromptManager()

    @Published var availablePrompts: [String] = []

    func loadPrompt(named: String) -> String?
    func listPrompts() -> [String]
    func promptsDirectory() -> URL
    func createPrompt(name: String, content: String)
    func deletePrompt(name: String)
}
```

### 4.2 Bundle Default Prompts

In `Resources/prompts/`:
- `default.md` - General cleanup
- `email.md` - Email formatting
- `chat.md` - Casual style

Copy to Application Support on first launch if not exists.

---

## Phase 5: Integration & UI

### 5.1 Settings Tab Updates

**New "LLM" tab or section:**
- API key management (input, verify, status)
- Model selection (dropdown of Groq models)
- Current prompt preview

**Shortcuts tab:**
- List of configured shortcuts
- Each shows: name, key combo, mode, prompt file
- Add/edit/remove shortcuts

### 5.2 Menu Bar Status

Show in menu bar or tooltip:
- LLM status (connected / not configured)
- Active shortcuts count

---

## Implementation Order

1. **PromptManager** - Load prompts from files
2. **LLMClient updates** - API key validation and storage
3. **Config schema changes** - Array of shortcuts with prompt references
4. **HotkeyManager updates** - Dynamic registration
5. **APIKeySettingsView** - UI for key management
6. **Shortcuts UI** - Edit shortcuts in settings
7. **Bundle default prompts** - Include in app

---

## Files to Create

| File | Purpose |
|------|---------|
| `Services/PromptManager.swift` | Load/manage prompt .md files |
| `Views/APIKeySettingsView.swift` | API key management UI |
| `Views/ShortcutsSettingsView.swift` | Manage hotkey configurations |
| `Resources/prompts/default.md` | Default cleanup prompt |
| `Resources/prompts/email.md` | Email formatting prompt |

## Files to Modify

| File | Changes |
|------|---------|
| `ConfigManager.swift` | New shortcuts array schema, prompt file references |
| `Services/LLMClient.swift` | API key validation, UserDefaults storage |
| `HotkeyManager.swift` | Dynamic hotkey registration |
| `DictationManager.swift` | Load prompt from file via PromptManager |
| `Views/SettingsView.swift` | Add LLM settings tab |

---

## Key Code from VoiceInk to Adapt

### API Key Validation
From `AIService.swift:verifyAPIKey()`:
- OpenAI-compatible validation (Groq uses this)
- Send minimal test request
- Check for 200-299 response

### Request Structure
From `AIEnhancementService.swift:makeRequest()`:
- Proper error handling with retry logic
- Exponential backoff for rate limits
- System prompt construction

### Prompt Templates
From `AIPrompts.swift`:
- System instruction wrapper for transcription enhancement
- Context injection (clipboard, vocabulary)

---

## Model Support

**Groq models to support:**
- `kimi-k2` (Moonshot AI - requested by user)
- `llama-3.3-70b-versatile`
- `llama-3.1-8b-instant`
- `mixtral-8x7b-32768`
- `gemma2-9b-it`

Note: Verify `kimi-k2` is available on Groq. If not, check for similar model name.
