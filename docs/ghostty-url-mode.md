# URL Hint Mode Implementation Plan

## Context

Ghostty has comprehensive URL detection and click-to-open support, but lacks a keyboard-driven way to open URLs. Foot terminal has a popular "URL mode" where pressing a keybind highlights all visible URLs with hint labels (e.g., "A", "AB"), and typing the label opens that URL. This plan adds that feature to Ghostty.

Reference: [Ghostty Discussion #3922](https://github.com/ghostty-org/ghostty/discussions/3922)

## Design

When the user activates URL hint mode (default: `ctrl+shift+u`):
1. All visible URLs are detected and assigned short hint labels (A, B, C, ... AA, AB, ...)
2. Hint labels are rendered at the start of each URL, replacing the underlying cells visually
3. URLs are underlined/highlighted
4. Keyboard input is intercepted — typing hint characters filters and selects a URL
5. When a unique hint is matched, the URL is opened with the system opener
6. Escape exits hint mode without action

## Architecture

**Data flow**: Surface (state + input) → renderer.State (hint data) → generic.zig (cell injection) → GPU

Hint labels are rendered by injecting cells into the GPU cell buffer, following the same pattern as preedit/IME text (`addPreeditCell` in `generic.zig:3270`). This is cross-platform and reuses the existing text rendering pipeline.

## Stages

### Stage 1: Core Data Structures and Binding Action
**Goal**: Define the URL hint mode state and add the keybinding action.
**Files to modify**:
- `src/input/Binding.zig` — Add `url_hint_open` action (~line 472 in the Action enum)
- `src/input/command.zig` — Add command entry for the action (~line 286)
- `src/config/Config.zig` — Add default keybind `ctrl+shift+u` → `url_hint_open` (~line 6237)
- `src/Surface.zig` — Add `url_hints: ?UrlHintState = null` field, create `UrlHintState` struct

**`UrlHintState` struct** (new, in Surface.zig or a new file):
```zig
const UrlHintState = struct {
    /// Each detected URL with its hint label and position
    hints: std.ArrayListUnmanaged(Hint),
    /// Characters typed so far to filter hints
    typed: std.ArrayListUnmanaged(u8),

    const Hint = struct {
        label: [2]u8,       // e.g. "A\0" or "AB"
        label_len: u8,      // 1 or 2
        url: []const u8,    // the URL string (allocated)
        start: terminal.point.Coordinate, // viewport start position
        end: terminal.point.Coordinate,   // viewport end position
    };
};
```

**Success criteria**: Code compiles, `url_hint_open` appears in keybind config.

### Stage 2: URL Detection and Hint Assignment
**Goal**: When hint mode activates, scan visible URLs and assign labels.
**Files to modify**:
- `src/Surface.zig` — Implement `startUrlHintMode()` handler for the binding action

**Logic**:
1. Call the existing link detection: use `linkAtPin()` iteration or walk visible rows with the URL regex from `src/config/url.zig`
2. Also detect OSC8 hyperlinks by checking cell `hyperlink` flags
3. Assign hint labels: A-Z for ≤26 URLs, AA-ZZ for more
4. Store results in `self.url_hints`
5. Trigger a render

**Reuse**: `src/renderer/link.zig:Set.renderCellMap()` already finds all regex-matched links in the viewport. The URL regex is in `src/config/url.zig`.

**Success criteria**: Activating the keybind populates `url_hints` with detected URLs (verify via logging).

### Stage 3: Input Handling in Hint Mode
**Goal**: Intercept keyboard input during hint mode to filter and select hints.
**Files to modify**:
- `src/Surface.zig` — Add hint mode input handling in `keyCallback()` (~line 2598)

**Logic** (early in `keyCallback`, before normal binding processing):
```
if (self.url_hints != null) {
    if (key == escape) → exit hint mode, return .consumed
    if (key is letter a-z) →
        append to typed prefix
        filter hints matching prefix
        if exactly one match → open URL, exit hint mode
        if zero matches → beep or exit
        trigger re-render
        return .consumed
    return .consumed  // swallow all other keys
}
```

**Success criteria**: Typing hint characters filters the list; escape exits; matching a hint triggers URL open.

### Stage 4: Rendering Hint Labels
**Goal**: Display hint labels visually on screen during hint mode.
**Files to modify**:
- `src/renderer/State.zig` — Add hint data field to pass from Surface to renderer
- `src/renderer/generic.zig` — Add hint cell injection in `rebuildCells()` (~line 2535, after preedit setup)

**Approach** (following `addPreeditCell` pattern at `generic.zig:3270`):
1. Add a `url_hints` field to `renderer.State` (like `preedit`)
2. In `updateFrame()` (~line 1170), copy hint data from terminal state to arena
3. In `rebuildCells()`, after the main cell loop, iterate hints and call `addPreeditCell`-like function for each hint label character at the hint's start position
4. Style hint labels with a distinct background color and bold text

**Data to pass through renderer.State**:
```zig
url_hints: ?[]const UrlHint = null,

pub const UrlHint = struct {
    label: [2]u8,
    label_len: u8,
    x: CellCountInt,
    y: CellCountInt,
    end_x: CellCountInt,
    end_y: CellCountInt,
    matched: bool, // dimmed if not matching typed prefix
};
```

**Success criteria**: Hint labels appear on screen at URL positions with clear styling.

### Stage 5: Highlight URLs and Polish
**Goal**: Underline/highlight full URLs, handle edge cases, add config.
**Files to modify**:
- `src/renderer/Overlay.zig` — Optionally highlight URL regions during hint mode
- `src/Surface.zig` — Handle edge cases: scrollback, resize during hint mode, mouse events

**Edge cases**:
- Exit hint mode on terminal resize
- Exit hint mode on focus loss
- Exit hint mode if terminal content changes (new output)
- Handle URLs that span multiple lines

**Success criteria**: Full working feature with clean UX.

## Key Files Reference

| File | Role |
|------|------|
| `src/input/Binding.zig:472` | Action enum — add `url_hint_open` |
| `src/input/command.zig:286` | Command metadata |
| `src/config/Config.zig:6237` | Default keybinding |
| `src/Surface.zig:81,2598,4487` | State, key handling, link processing |
| `src/renderer/State.zig:46` | Preedit pattern to follow |
| `src/renderer/generic.zig:2535,3270` | Cell injection (preedit model) |
| `src/renderer/link.zig:58` | `renderCellMap()` — finds all visible links |
| `src/config/url.zig` | URL regex |
| `src/os/open.zig` | Cross-platform URL opener |

## Verification

1. Build: `zig build` compiles without errors
2. Manual test: Open a terminal with URLs visible, press `ctrl+shift+u`, verify hint labels appear
3. Type a hint label character, verify filtering works
4. Complete a hint, verify URL opens in browser
5. Press Escape, verify hint mode exits cleanly
6. Test with: no URLs visible, many URLs (>26), OSC8 hyperlinks, URLs spanning lines
7. Run existing tests: `zig build test` — no regressions
