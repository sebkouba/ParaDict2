# ParaDict UI Style Guide

A design system for clarity, consistency, and calm.

---

## Philosophy

1. **Reduce visual noise.** Every element earns its place.
2. **Guide the eye.** Clear hierarchy from title to action.
3. **Feel native.** Respect macOS conventions while adding warmth.
4. **Animate with purpose.** Motion confirms action, never distracts.

---

## Color System

### Backgrounds (Layered Depth)

The UI uses three background layers to create subtle depth without shadows:

| Layer | Color | Use |
|-------|-------|-----|
| Canvas | `Color(NSColor.windowBackgroundColor)` | Outermost view background |
| Surface | `Color(NSColor.controlBackgroundColor)` | Cards, elevated containers |
| Inset | `Color(NSColor.textBackgroundColor)` | Input fields, nested elements |

```swift
// Canvas: the view itself
.background(Color(NSColor.windowBackgroundColor))

// Surface: cards float on canvas
.background(Color(NSColor.controlBackgroundColor))

// Inset: inputs sink into surface
.background(Color(NSColor.textBackgroundColor))
```

### Accent Colors

| State | Color |
|-------|-------|
| Primary accent | `.accentColor` (system blue) |
| Success | `Color.green` |
| Warning | `Color.orange` |
| Error | `Color.red` |
| Muted/inactive | `Color.gray` or `.secondary` |

### Semantic Backgrounds

For status indicators with colored backgrounds:

```swift
// Success background
Color.green.opacity(0.15)

// Warning background
Color.orange.opacity(0.15)

// Selected/active background
Color.accentColor.opacity(0.1)
```

---

## Typography

| Element | Style | Example |
|---------|-------|---------|
| Page title | `.font(.system(size: 28, weight: .bold))` | "LLM Settings" |
| Page subtitle | `.font(.system(size: 15))` + `.foregroundStyle(.secondary)` | "Configure AI enhancement" |
| Section header | `.font(.headline)` | "API Key" |
| Body text | `.font(.body)` | Control labels |
| Description | `.font(.subheadline)` + `.foregroundColor(.secondary)` | Helper text below controls |
| Caption | `.font(.caption)` + `.foregroundColor(.secondary)` | Hints, metadata |
| Monospace | `.font(.system(.body, design: .monospaced))` | Code, paths, IDs |

### Hierarchy Rules

1. One page title per view (size 28, bold)
2. Section headers use `.headline` with optional icon via `Label`
3. Never use bold for body text unless it's a list item title
4. Secondary text is always `.foregroundColor(.secondary)`

---

## Spacing System

Use multiples of 4 for all spacing. Prefer these values:

| Token | Value | Use |
|-------|-------|-----|
| `xs` | `4` | Tight inline spacing |
| `sm` | `8` | Related elements (title/subtitle) |
| `md` | `12` | Control internal spacing |
| `lg` | `16` | Card internal spacing, between controls |
| `xl` | `24` | Between sections, view padding |
| `2xl` | `32` | Between cards |
| `3xl` | `40` | Header vertical padding |

### View Structure

```swift
ScrollView {
    VStack(spacing: 32) {        // 2xl between major sections
        headerSection            // Contains 3xl vertical padding
        contentCards             // Each card separated by 32
    }
    .padding(24)                 // xl edge padding
}
.background(Color(NSColor.windowBackgroundColor))  // Canvas layer
```

---

## Page Header

Every settings tab opens with a centered header:

```swift
VStack(spacing: 24) {
    // Icon in circle
    Image(systemName: "icon.name")
        .font(.system(size: 40))
        .foregroundStyle(.accentColor)
        .padding(20)
        .background(
            Circle()
                .fill(Color(NSColor.controlBackgroundColor))
        )

    // Title block
    VStack(spacing: 8) {
        Text("Page Title")
            .font(.system(size: 28, weight: .bold))
        Text("Brief description of this page's purpose")
            .font(.system(size: 15))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}
.padding(.vertical, 40)
```

### Tab Icons

| Tab | Icon |
|-----|------|
| Permissions | `shield.lefthalf.filled` |
| Audio | `mic.fill` |
| Shortcuts | `keyboard` |
| LLM | `brain.head.profile` |
| Chat | `bubble.left.and.bubble.right` |
| Watcher | `folder.badge.gearshape` |

---

## Cards

Cards group related controls. They sit on the canvas with a subtle border for visibility in dark mode.

```swift
VStack(alignment: .leading, spacing: 16) {
    // Content
}
.padding(16)
.background(Color(NSColor.controlBackgroundColor))
.cornerRadius(12)
.overlay(
    RoundedRectangle(cornerRadius: 12)
        .stroke(Color.white.opacity(0.08), lineWidth: 1)
)
```

### Card Variants

**Standard card** (most common):
```swift
.cornerRadius(12)
.overlay(
    RoundedRectangle(cornerRadius: 12)
        .stroke(Color.white.opacity(0.08), lineWidth: 1)
)
```

**Flat card** (for dense lists, no shadow):
```swift
.cornerRadius(12)
// No shadow
```

**Interactive card** (selectable options):
```swift
.cornerRadius(10)
.overlay(
    RoundedRectangle(cornerRadius: 10)
        .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: isSelected ? 2 : 1)
)
.shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
```

### Section Headers Inside Cards

```swift
// Text only
Text("Section Title")
    .font(.headline)

// With icon
Label("Section Title", systemImage: "icon.name")
    .font(.headline)
```

### Dividers Inside Cards

Use `Divider()` to separate logical sections within a single card. Never use dividers between cards.

```swift
VStack(alignment: .leading, spacing: 16) {
    sectionOne

    Divider()

    sectionTwo
}
```

---

## Corner Radius

| Element | Radius |
|---------|--------|
| Cards | `12` |
| Buttons, inputs, interactive cards | `10` |
| Small elements (badges, pills) | `8` |
| Icons in circles | Full circle |

---

## Buttons

### Primary Action
The main action on a page or card.

```swift
Button("Save") { }
    .buttonStyle(.borderedProminent)
```

### Secondary Action
Alternative actions, less visual weight.

```swift
Button("Cancel") { }
    .buttonStyle(.bordered)
```

### Tertiary/Text Action
Inline actions, minimal chrome.

```swift
Button("Learn more") { }
    .buttonStyle(.borderless)
    .font(.caption)
```

### Destructive Action
Dangerous operations (delete, clear, reset).

```swift
Button("Delete", role: .destructive) { }
    .buttonStyle(.bordered)
```

### Icon Button
For compact actions like refresh.

```swift
Button {
    // action
} label: {
    Image(systemName: "arrow.clockwise")
        .font(.system(size: 14, weight: .medium))
}
.buttonStyle(.borderless)
.foregroundColor(.secondary)
```

### Full-Width Action Button
For prominent card actions.

```swift
Button {
    // action
} label: {
    HStack {
        Text("Open System Settings")
        Spacer()
        Image(systemName: "arrow.right")
    }
    .font(.headline)
    .foregroundColor(.white)
    .padding()
    .frame(maxWidth: .infinity)
    .background(Color.accentColor)
    .cornerRadius(10)
}
.buttonStyle(.plain)
```

---

## Form Controls

### Text Field

```swift
TextField("Placeholder", text: $value)
    .textFieldStyle(.roundedBorder)
```

For monospace content (API keys, code, paths):
```swift
TextField("gsk_...", text: $apiKey)
    .textFieldStyle(.roundedBorder)
    .font(.system(.body, design: .monospaced))
```

### Secure Field

```swift
SecureField("Password", text: $password)
    .textFieldStyle(.roundedBorder)
```

### Toggle

Toggles align to the trailing edge in a row:

```swift
HStack {
    VStack(alignment: .leading, spacing: 4) {
        Text("Feature Name")
            .font(.body)
        Text("Description of what this does")
            .font(.caption)
            .foregroundColor(.secondary)
    }
    Spacer()
    Toggle("", isOn: $isEnabled)
        .toggleStyle(.switch)
        .labelsHidden()
}
```

### Picker

```swift
Picker("Label", selection: $selection) {
    ForEach(options, id: \.self) { option in
        Text(option).tag(option)
    }
}
.pickerStyle(.menu)
```

---

## Selectable List Items

For lists where users select one option (like audio devices):

```swift
struct SelectableRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 20))
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isSelected ? Color.accentColor : Color.gray.opacity(0.2),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
```

---

## Hoverable List Items

For lists with hover interaction (like prompt files):

```swift
struct HoverableRow: View {
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 16))

                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isHovered ? .accentColor : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.accentColor.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
```

---

## Status Indicators

### Connection Dot

```swift
Circle()
    .fill(isConnected ? Color.green : Color.red)
    .frame(width: 10, height: 10)
```

### Permission Status Icon

```swift
// Granted
Image(systemName: "checkmark.seal.fill")
    .font(.system(size: 20))
    .foregroundColor(.green)

// Not granted
Image(systemName: "xmark.seal.fill")
    .font(.system(size: 20))
    .foregroundColor(.orange)
```

### Inline Status Badge

```swift
HStack(spacing: 6) {
    Circle()
        .fill(isActive ? Color.green : Color.gray)
        .frame(width: 8, height: 8)
    Text(isActive ? "Connected" : "Disconnected")
        .font(.subheadline)
        .foregroundColor(isActive ? .primary : .secondary)
}
```

### Loading State

```swift
ProgressView()
    .scaleEffect(0.8)
```

---

## Empty States

When a section has no content:

```swift
VStack(spacing: 12) {
    Image(systemName: "tray")
        .font(.system(size: 32))
        .foregroundColor(.secondary)

    Text("No items yet")
        .font(.headline)
        .foregroundColor(.secondary)

    Text("Add your first item to get started.")
        .font(.subheadline)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
}
.frame(maxWidth: .infinity)
.padding(.vertical, 32)
```

---

## Animation

### Principles

1. **Confirm, don't decorate.** Animate to show cause and effect.
2. **Be quick.** Most animations are 0.15-0.2 seconds.
3. **Use easing.** `.easeInOut` for most transitions.

### Standard Durations

| Type | Duration | Curve |
|------|----------|-------|
| Hover feedback | `0.15s` | `.easeInOut` |
| State change | `0.2s` | `.easeInOut` |
| Expand/collapse | `0.25s` | `.easeInOut` |
| Page transition | `0.3s` | `.easeInOut` |

### Common Patterns

```swift
// Hover effect
.onHover { hovering in
    withAnimation(.easeInOut(duration: 0.15)) {
        isHovered = hovering
    }
}

// State change
withAnimation(.easeInOut(duration: 0.2)) {
    isExpanded.toggle()
}

// Rotating refresh icon
Image(systemName: "arrow.clockwise")
    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
    .animation(.easeInOut(duration: 0.5), value: isRefreshing)
```

---

## Layout Constraints

### Maximum Content Width

For very wide windows, constrain content:

```swift
ScrollView {
    VStack(spacing: 32) {
        // content
    }
    .padding(24)
    .frame(maxWidth: 600)  // Prevents overly wide layouts
    .frame(maxWidth: .infinity)  // Centers the constrained content
}
```

### Minimum Touch Targets

All interactive elements: minimum 44x44 points.

---

## Accessibility

1. **Labels for icons.** Use `Label` or `.accessibilityLabel()`.
2. **Sufficient contrast.** Rely on system colors.
3. **Focusable controls.** SwiftUI handles this, don't break it.
4. **Reduced motion.** Respect `accessibilityReduceMotion`.

```swift
// Check for reduced motion preference
@Environment(\.accessibilityReduceMotion) var reduceMotion

// Apply conditionally
withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
    // state change
}
```

---

## Do's and Don'ts

### Do

- Use system colors for automatic dark mode support
- Let cards breathe with consistent padding
- Group related controls in the same card
- Use `.secondary` for supporting text
- Align buttons to the leading edge (except in dialogs)

### Don't

- Mix card styles on the same page
- Use custom colors when system colors work
- Add shadows to elements inside cards
- Nest cards inside cards
- Use dividers between cards (spacing is enough)
- Add animations without purpose

---

## Quick Reference

```
Canvas Background:    Color(NSColor.windowBackgroundColor)
Card Background:      Color(NSColor.controlBackgroundColor)
Input Background:     Color(NSColor.textBackgroundColor)

Card Corner Radius:   12
Card Border:          Color.white.opacity(0.08), lineWidth: 1
Card Padding:         16

View Padding:         24
Section Spacing:      32
Header V-Padding:     40

Page Title:           .system(size: 28, weight: .bold)
Section Header:       .headline
Body:                 .body
Caption:              .caption + .secondary
```
