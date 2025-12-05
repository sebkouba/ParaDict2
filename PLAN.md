# UI Style Consistency Implementation Plan

See `STYLE_GUIDE.md` for the visual standards.

---

## Current Issues

### ShortcutsSettingsView
- No ScrollView wrapper
- No header with icon
- No view background color
- Uses `GroupBox` instead of styled cards
- Title is `.title2` instead of 28pt bold
- Lives in `ParaDictApp.swift` instead of own file

### ChatSettingsView
- Small header without icon
- No circular icon background
- Missing view background color
- Header uses `.headline` instead of 28pt bold

---

## Implementation Steps

### Step 1: Create ShortcutsSettingsView.swift
1. Create new file `Views/ShortcutsSettingsView.swift`
2. Move `ShortcutsSettingsView` from `ParaDictApp.swift`
3. Move `PromptFileLink` helper view as well
4. Apply style guide:
   - Add ScrollView wrapper
   - Add header with `keyboard` icon
   - Add view background color
   - Replace `GroupBox` with styled cards
   - Adjust spacing to 32pt between cards

### Step 2: Update ChatSettingsView.swift
1. Add header section with `bubble.left.and.bubble.right` icon
2. Add view background color
3. Keep chat interface layout (functionally different from other tabs)
4. Style the header bar to be more minimal since there's also the header section

### Step 3: Update ParaDictApp.swift
1. Remove `ShortcutsSettingsView` (moved to own file)
2. Remove `PromptFileLink` (moved to own file)
3. Add import if needed

### Step 4: Verify
- Build and run
- Check all 6 tabs visually
- Ensure headers align
- Verify spacing and colors match

---

## Files to Modify

| File | Action |
|------|--------|
| `ParaDictApp.swift` | Remove ShortcutsSettingsView, PromptFileLink |
| `Views/ShortcutsSettingsView.swift` | Create new, apply style guide |
| `Views/ChatSettingsView.swift` | Add header section, background |
