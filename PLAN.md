# UI Style Consistency Implementation Plan

See `STYLE_GUIDE.md` for the complete design system.

---

## Key Style Changes (from current implementation)

Based on the updated style guide, existing views also need updates:

| Element | Current | New (per style guide) |
|---------|---------|----------------------|
| View background | `controlBackgroundColor` | `windowBackgroundColor` (Canvas) |
| Header icon color | `.blue` | `.accentColor` |
| Header icon bg | `windowBackgroundColor.opacity(0.9)` | `controlBackgroundColor` (Surface) |
| Card corner radius | `16` | `12` |
| Card shadow | varies | `color: .black.opacity(0.06), radius: 8, y: 2` |
| Title subtitle | - | Add `.multilineTextAlignment(.center)` |

---

## Views Requiring Updates

### Priority 1: Non-compliant views (major rework)

**ShortcutsSettingsView** (in ParaDictApp.swift)
- Missing: ScrollView, header, canvas background
- Wrong: Uses GroupBox instead of styled cards
- Action: Extract to own file, full restyle

**ChatSettingsView**
- Missing: Page header with icon, canvas background
- Action: Add header section, update background

### Priority 2: Existing views needing alignment

**PermissionsView**
- Fix: View background → `windowBackgroundColor`
- Fix: Header icon → `.accentColor`
- Fix: Header icon bg → `controlBackgroundColor`
- Fix: Card corner radius → `12`
- Fix: Add card shadow

**AudioInputView**
- Same fixes as PermissionsView

**LLMSettingsView**
- Same fixes as PermissionsView

**DirectoryWatcherView**
- Same fixes as PermissionsView

---

## Implementation Steps

### Step 1: Create ShortcutsSettingsView.swift
1. Create `Views/ShortcutsSettingsView.swift`
2. Move `ShortcutsSettingsView` and `PromptFileLink` from ParaDictApp.swift
3. Apply full style guide:
   - Canvas background (`windowBackgroundColor`)
   - Page header with `keyboard` icon, `.accentColor`
   - Cards with 12pt radius and shadow
   - 32pt spacing between cards

### Step 2: Update ChatSettingsView.swift
1. Add page header with `bubble.left.and.bubble.right` icon
2. Change view background to canvas color
3. Keep chat interface functional layout
4. Style header bar to complement (not compete with) page header

### Step 3: Align existing views to style guide
For each of: PermissionsView, AudioInputView, LLMSettingsView, DirectoryWatcherView

1. Change view `.background()` to `windowBackgroundColor`
2. Change header icon from `.foregroundStyle(.blue)` to `.foregroundStyle(.accentColor)`
3. Change header icon circle fill to `controlBackgroundColor`
4. Change card `.cornerRadius(16)` to `.cornerRadius(12)`
5. Add card shadow: `.shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)`
6. Add `.multilineTextAlignment(.center)` to subtitle

### Step 4: Update ParaDictApp.swift
1. Remove `ShortcutsSettingsView` (moved to own file)
2. Remove `PromptFileLink` (moved to own file)

### Step 5: Verify
- Build and run
- Check all 6 tabs side by side
- Verify in both light and dark mode
- Check hover animations work

---

## Files to Modify

| File | Changes |
|------|---------|
| `ParaDictApp.swift` | Remove ShortcutsSettingsView, PromptFileLink |
| `Views/ShortcutsSettingsView.swift` | **Create new**, full style guide compliance |
| `Views/ChatSettingsView.swift` | Add header, fix background |
| `Views/PermissionsView.swift` | Align colors, radius, shadow |
| `Views/AudioInputView.swift` | Align colors, radius, shadow |
| `Views/LLMSettingsView.swift` | Align colors, radius, shadow |
| `Views/DirectoryWatcherView.swift` | Align colors, radius, shadow |

---

## Checklist per View

For each settings view, verify:

- [ ] Background is `windowBackgroundColor` (Canvas)
- [ ] Has page header with 40pt icon
- [ ] Icon uses `.accentColor`
- [ ] Icon circle uses `controlBackgroundColor` (Surface)
- [ ] Title is 28pt bold
- [ ] Subtitle is 15pt secondary, center-aligned
- [ ] Header has 40pt vertical padding
- [ ] Cards use `controlBackgroundColor` (Surface)
- [ ] Cards have 12pt corner radius
- [ ] Cards have shadow (0.06 opacity, 8 radius, y: 2)
- [ ] Cards have 16pt internal padding
- [ ] 32pt spacing between cards
- [ ] 24pt view edge padding
