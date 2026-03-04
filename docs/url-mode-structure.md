# URL Mode: Codebase Patterns and Restructuring Guide

## Problem

The current `add-url-mode` branch adds ~370 lines to `Surface.zig`. Since Surface.zig is a hot file (6765 lines, touched by many PRs), this creates a high risk of merge conflicts. This document analyzes existing patterns for extracting feature logic out of Surface and recommends an approach for URL mode.

## Existing Extraction Patterns in Ghostty

### Pattern 1: Companion File (`surface_mouse.zig`)

**Files**: `src/surface_mouse.zig` (336 lines)
**Integration**: `src/Surface.zig` line 38 — `const SurfaceMouse = @import("surface_mouse.zig");`

A flat struct at the `src/` level. Pure data + pure functions — no reference back to Surface. Surface constructs it with data, calls methods, reads results.

```zig
// surface_mouse.zig — no Surface import
const SurfaceMouse = @This();
physical_key: input.Key,
mouse_event: terminal.Terminal.MouseEvents,
// ...
pub fn keyToMouseShape(self: SurfaceMouse) ?MouseShape { ... }
```

```zig
// Surface.zig — thin call site
const sm: SurfaceMouse = .{
    .physical_key = ...,
    .mouse_event = ...,
};
if (sm.keyToMouseShape()) |shape| { ... }
```

**Characteristics**:
- No lifecycle (not heap-allocated, no init/deinit)
- No back-reference to Surface
- Self-contained tests in the same file
- Lightest-weight extraction

### Pattern 2: Owned Object (`inspector/Inspector.zig`)

**Files**: `src/inspector/Inspector.zig`, `src/inspector/main.zig`, `src/inspector/widgets/`
**Integration**: `Surface.zig` lines 124, 869-912

A heap-allocated object that Surface creates/destroys. Passed into `renderer_state` for the renderer to read. Has its own directory with sub-modules.

```zig
// Surface.zig fields
inspector: ?*inspectorpkg.Inspector = null,

// Surface.zig — activate
pub fn activateInspector(self: *Surface) !void {
    const ptr = try self.alloc.create(inspectorpkg.Inspector);
    ptr.* = try inspectorpkg.Inspector.init(self.alloc);
    self.inspector = ptr;
    self.renderer_state.inspector = self.inspector;  // share with renderer
    // notify renderer thread + io thread
}

// Surface.zig — deactivate
pub fn deactivateInspector(self: *Surface) void {
    self.renderer_state.inspector = null;
    insp.deinit(self.alloc);
    self.inspector = null;
}
```

**Characteristics**:
- Heap-allocated, has init/deinit
- Shared with renderer via `renderer_state`
- The Inspector imports Surface back (for types), but communicates via method params
- Medium weight — good for features with their own rendering and data

### Pattern 3: Optional Struct with Thread (`terminal/search/`)

**Files**: `src/terminal/search/Thread.zig`, `src/terminal/search/*.zig`
**Integration**: `Surface.zig` lines 166, 190-208, 5262-5307

An optional struct directly on Surface, wrapping a background thread with event loop and mailbox.

```zig
// Surface.zig
search: ?Search = null,

const Search = struct {
    state: terminal.search.Thread,
    thread: std.Thread,
    pub fn deinit(self: *Search) void { ... }
};

// Starting search
self.search = .{
    .state = try .init(self.alloc, .{ .mutex = ..., .terminal = ..., ... }),
    .thread = undefined,
};
s.thread = try .spawn(.{}, terminal.search.Thread.threadMain, .{&s.state});
```

**Characteristics**:
- Heaviest pattern — own OS thread, event loop, mailbox
- Used for features with ongoing background work
- Communication via callback + mailbox

### Pattern 4: Pure Data Types (`terminal/highlight.zig`, `input/Link.zig`)

Standalone types in `terminal/` or `input/` with no awareness of Surface.

- `terminal/highlight.zig` — Untracked, Tracked, Flattened highlight types
- `input/Link.zig` — Link definition with regex, action, highlight mode
- `terminal/Selection.zig` — Selection bounds with tracked/untracked pins

Surface and the renderer import and use these freely.

## Current URL Mode Implementation (Branch State)

### Lines added per file

| File | Lines added | Risk |
|------|-------------|------|
| `src/Surface.zig` | +374 | **High** — hot file, many concurrent PRs |
| `src/renderer/generic.zig` | +82 | Medium — rendering logic |
| `src/renderer/State.zig` | +21 | Low — data struct |
| `src/input/Binding.zig` | +6 | Low |
| `src/input/command.zig` | +6 | Low |
| `src/config/Config.zig` | +7 | Low |

### What lives in Surface.zig today

1. **`UrlHintState` struct** (lines 213-241) — data definition
2. **`startUrlHintMode` / `startUrlHintModeInner`** (~100 lines) — URL detection, label assignment
3. **`handleUrlHintInput`** (~70 lines) — key event handling, prefix matching
4. **`exitUrlHintMode`** (~10 lines) — cleanup
5. **`syncUrlHintsToRenderer`** (~35 lines) — copy state to renderer
6. **Integration points** (~20 lines) — field, deinit, keyCallback intercept, resize/focus exit, performBindingAction

## Recommended Restructuring

### Create `src/surface_url_mode.zig`

Follow the `surface_mouse.zig` companion pattern. Move all URL mode logic into a new file. Surface.zig keeps only the field and thin delegation.

#### What moves to `surface_url_mode.zig`

- `UrlHintState` struct (renamed to just the file-level `@This()`)
- `Hint` sub-struct
- Label generation logic (currently inline in `startUrlHintModeInner`)
- Input handling logic (prefix matching, filtering)
- Result type for what action to take

#### What stays in `Surface.zig` (minimal diff)

```zig
// Field (~1 line)
url_hints: ?SurfaceUrlMode = null,

// In deinit (~1 line)
if (self.url_hints) |*h| h.deinit(self.alloc);

// In keyCallback (~5 lines)
if (self.url_hints) |*hints| {
    const result = hints.handleInput(event);
    // handle result (open url, exit, render)
    return .consumed;
}

// In performBindingAction (~3 lines)
.open_url_hint => {
    self.url_hints = SurfaceUrlMode.init(...) // or start method
    return true;
},

// In resize/focus (~2 lines each)
self.exitUrlHintMode();
```

This reduces the Surface.zig diff from ~370 lines to ~30-40 lines.

#### Interface sketch for `surface_url_mode.zig`

```zig
const SurfaceUrlMode = @This();

const terminal = @import("terminal/main.zig");
const input = @import("input.zig");
const rendererpkg = @import("renderer.zig");

hints: std.ArrayListUnmanaged(Hint),
typed: std.ArrayListUnmanaged(u8),

pub const Hint = struct {
    label: [2]u8,
    label_len: u8,
    url: []const u8,
    start: terminal.point.Coordinate,
    end: terminal.point.Coordinate,
};

pub const InputResult = union(enum) {
    /// No action needed, stay in hint mode (re-render).
    continue_mode,
    /// Exit hint mode without action.
    exit,
    /// Open the URL at this index then exit.
    open: []const u8,
};

/// Build hints from the visible viewport.
/// Caller provides the screen, links config, and allocator.
pub fn init(
    alloc: Allocator,
    screen: *terminal.Screen,
    links: []const LinkConfig,
) !?SurfaceUrlMode { ... }

pub fn deinit(self: *SurfaceUrlMode, alloc: Allocator) void { ... }

/// Process a key event. Returns what action the caller should take.
pub fn handleInput(self: *SurfaceUrlMode, alloc: Allocator, event: input.KeyEvent) !InputResult { ... }

/// Build the renderer-facing hint slice.
pub fn renderHints(self: *const SurfaceUrlMode, alloc: Allocator) ![]rendererpkg.State.UrlHint { ... }
```

### `renderer/generic.zig` changes stay as-is

The 82 lines in `generic.zig` are rendering code (`addUrlHintCell`, the loop in `rebuildCells`). This is the right place for them — it follows the `addPreeditCell` pattern exactly.

### `renderer/State.zig` changes stay as-is

The `UrlHint` struct (21 lines) is a pure data transfer type. It belongs in State.zig alongside `Preedit`.

### Label generation could be a standalone function

The current label assignment (A-Z, then AA-ZZ) is inline in `startUrlHintModeInner`. In `surface_url_mode.zig`, this becomes a testable function:

```zig
/// Assign labels to hints. Supports A-Z (26), then AA-ZZ (676 more).
fn assignLabels(hints: []Hint) void {
    for (hints, 0..) |*hint, i| {
        if (i < 26) {
            hint.label = .{ @intCast('A' + i), 0 };
            hint.label_len = 1;
        } else {
            const idx = i - 26;
            hint.label = .{ @intCast('A' + idx / 26), @intCast('A' + idx % 26) };
            hint.label_len = 2;
        }
    }
}
```

This is directly unit-testable without needing a terminal or Surface.

### The foot-style label algorithm is also extractable

The research in `docs/foot-url-mode-gen.md` describes a more sophisticated algorithm using configurable alphabet and BFS-like expansion. If you later adopt that, it slots cleanly into `surface_url_mode.zig` as a replacement for `assignLabels`.

## Summary

| Concern | Where it lives | Why |
|---------|---------------|-----|
| Hint state + logic | `src/surface_url_mode.zig` (new) | Bulk of code, testable in isolation |
| Hint rendering | `src/renderer/generic.zig` | Follows `addPreeditCell` pattern |
| Renderer data transfer | `src/renderer/State.zig` | Follows `Preedit` pattern |
| Binding action | `src/input/Binding.zig` | Existing pattern |
| Command metadata | `src/input/command.zig` | Existing pattern |
| Default keybind | `src/config/Config.zig` | Existing pattern |
| Surface integration | `src/Surface.zig` (~30 lines) | Field + delegation only |

The key insight: Surface.zig changes drop from ~370 lines to ~30-40 lines of thin delegation, while all the URL mode logic moves to a new file that won't conflict with other PRs.
