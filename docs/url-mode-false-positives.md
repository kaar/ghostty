# URL Hint Mode: False Positive Analysis

## Problem

URL hint mode incorrectly identifies file paths and HTML fragments as URLs.

Examples from `urls.txt`:
- `~/repos/kaar/ghostty` — matched as a URL (it's a directory path)
- `</h1>` — matched as a URL (`/h1` looks like an absolute path)

## Root Cause

The regex in `src/config/url.zig` is **not buggy** — it intentionally matches
both URLs and file paths for ctrl+click link opening, and that behavior is
correct for its original purpose.

The issue is that URL hint mode (`src/Surface.zig:4712`) reuses the same
`self.config.links` patterns without filtering out path-only matches. This
surfaces the pre-existing path matching in a context where only URLs are
expected. The regex has three branches:

### Branch 1: Scheme URLs (line 76)
Matches URLs with explicit schemes like `https://`, `mailto:`, `ftp://`, etc.
This branch works correctly for URL hint mode.

### Branch 2: Absolute/relative paths (line 88) — causes false positives
The prefix pattern on line 82:
```
(?:\.\.\/|\.\/|(?<!\w)~\/|...|(?<![\w~\/])\/(?!\/))
```

- `(?<!\w)~\/` matches `~/repos/kaar/ghostty` because `~` is not preceded by a
  word character
- `(?<![\w~\/])\/(?!\/)` matches `/h1` in `</h1>` because `<` is not a word
  char, `~`, or `/`, and `h` is not `/`

The non-dotted sub-branch (lines 97-101) does not require a `.` in the path,
so any directory-like path matches freely.

### Branch 3: Bare relative paths (line 109)
Matches paths like `src/config/url.zig`. Requires a dot somewhere in the path
so it's less prone to false positives.

## Where the code connects

1. **Regex definition**: `src/config/url.zig:117-122` — combines all three branches
2. **Config registration**: `src/config/Config.zig:3768-3773` — adds regex as a default link
3. **Hint mode consumer**: `src/Surface.zig:4712-4719` — iterates all `config.links` with `.open` action

## Fix: URL-only regex for hint mode

Export the existing `scheme_url_branch` (branch 1 only) as a new public
constant `url_regex` from `src/config/url.zig`. Use it in
`startUrlHintModeInner` instead of iterating `self.config.links`.

### Files to modify

1. **`src/config/url.zig`** — export `pub const url_regex = scheme_url_branch`
   and add a `test "url regex (urls only)"` block
2. **`src/Surface.zig`** — use the URL-only regex in `startUrlHintModeInner`
   instead of `self.config.links` for regex matching (keep OSC8 scanning as-is)

### Tests

Add `test "url regex (urls only)"` in `src/config/url.zig` following the same
pattern as the existing `test "url regex"`.

**Positive cases** (URLs that must match):
- `"hello https://example.com world"` → `"https://example.com"`
- `"https://example.com/foo(bar) more"` → `"https://example.com/foo(bar)"`
- `"Link inside (https://example.com) parens"` → `"https://example.com"`
- `"Link period https://example.com. More text."` → `"https://example.com"`
- `"match http://example.com non-secure"` → `"http://example.com"`
- `"match ftp://example.com ftp links"` → `"ftp://example.com"`
- `"match ssh://example.com ssh links"` → `"ssh://example.com"`
- `"match git://example.com git links"` → `"git://example.com"`
- `"http://[::]:8000/"` → `"http://[::]:8000/"`
- `"https://[2001:db8::1]:8080/path"` → `"https://[2001:db8::1]:8080/path"`

**Negative cases** (must NOT match):
- `"~/repos/kaar/ghostty"` — home-relative path
- `"</h1>"` — HTML closing tag
- `"/tmp/test.txt"` — absolute path
- `"./foo/bar.txt"` — dot-relative path
- `"../example.py"` — parent-relative path
- `"src/config/url.zig"` — bare relative path
- `"$HOME/src/config/url.zig"` — env var path
- `"foo/bar"` — directory path

### Testing patterns in this project

Tests use Zig's built-in `test` blocks inside the source file:

```zig
test "test name" {
    const testing = std.testing;
    // ...
}
```

Key functions:
- `testing.expectEqual(expected, actual)` — compare values
- `testing.expectEqualStrings(expected, actual)` — compare strings

Regex test pattern (see existing `test "url regex"` at line 124):
1. `oni.testing.ensureInit()` — initialize Oniguruma runtime
2. `oni.Regex.init(pattern, .{}, oni.Encoding.utf8, oni.Syntax.default, null)` — compile regex
3. `defer re.deinit()` — always clean up
4. `re.search(input, .{})` — returns error union; success = match found
5. `reg.starts()[0]` / `reg.ends()[0]` — byte offsets of first match
6. `defer reg.deinit()` — clean up match result
7. For no-match cases: `if (result) |*reg| { reg.deinit(); return error.TestUnexpectedResult; } else |_| {}`

Run tests:
```bash
zig build test -Dtest-filter="url regex"
```
