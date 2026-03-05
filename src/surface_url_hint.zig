//! URL hint labeling and matching for the terminal surface.
//!
//! Generates short, home-row-friendly labels (e.g. "S", "AD") for detected
//! URLs and matches user-typed prefixes against them. Uses a BFS-style
//! expansion algorithm where single-char labels that would become prefixes
//! of multi-char labels are "consumed", guaranteeing that typing any single
//! character either selects a hint immediately or narrows to a group — never
//! both.
//!
//! With a 14-char alphabet this supports up to 14 + 14*14 = 210 labels.

const std = @import("std");
const testing = std.testing;

/// A detected URL hint with its label, URL string, and viewport position.
pub const Hint = struct {
    /// Two-character hint label, null-terminated. Single-char labels use
    /// a null byte in the second position (e.g. "S\x00").
    label: [2:0]u8,
    /// The URL string (allocated by the caller).
    url: []const u8,
    /// Viewport column where the URL starts.
    x: u16,
    /// Viewport row where the URL starts (viewport-relative).
    y: u16,
};

/// Result of matching a typed prefix against hint labels.
pub const MatchResult = union(enum) {
    /// No hints match the typed prefix.
    none,
    /// Exactly one hint matches — return its index.
    exact: usize,
    /// Multiple hints still match — need more input.
    multiple,
};

/// Default home-row-friendly alphabet for hint labels (from foot terminal).
pub const default_alphabet = "SADFJKLEWCMPGH";

/// Assign short labels to each hint using a BFS-style expansion algorithm.
///
/// The `alphabet` parameter specifies the characters to use for labels.
/// If it has fewer than 2 characters, the default alphabet is used.
///
/// The first `prefixes_needed` characters of the alphabet are consumed as
/// prefixes for two-character labels; the remaining characters become
/// standalone single-character labels. This ensures no ambiguity between
/// single-char and multi-char labels.
pub fn generateLabels(items: []Hint, alphabet: []const u8) void {
    const alpha = if (alphabet.len >= 2) alphabet else default_alphabet;
    const alpha_len = alpha.len;
    const count = items.len;

    if (count == 0) return;

    // Each prefix char replaces 1 single-char label with `alpha_len`
    // two-char labels, a net gain of (alpha_len - 1).
    const prefixes_needed: usize = if (count <= alpha_len)
        0
    else
        std.math.divCeil(usize, count - alpha_len, alpha_len - 1) catch unreachable;

    // Assign labels. The first `prefixes_needed` alphabet entries become
    // prefixes for 2-char labels; the rest are standalone 1-char labels.
    var idx: usize = 0;
    for (0..alpha_len) |i| {
        if (idx >= count) break;

        if (i < prefixes_needed) {
            // This alphabet char is consumed as a prefix.
            for (0..alpha_len) |j| {
                if (idx >= count) break;
                items[idx].label = .{ alpha[i], alpha[j] };
                idx += 1;
            }
        } else {
            // Standalone single-char label.
            items[idx].label = .{ alpha[i], 0 };
            idx += 1;
        }
    }
}

/// Match a typed prefix against all hint labels and return whether there
/// are zero, one, or multiple matches.
pub fn matchTyped(items: []const Hint, typed: []const u8) MatchResult {
    var match_count: usize = 0;
    var last_match_idx: usize = 0;
    for (items, 0..) |item, i| {
        const label = std.mem.sliceTo(&item.label, 0);
        if (typed.len > label.len) continue;
        if (std.mem.eql(u8, label[0..typed.len], typed)) {
            match_count += 1;
            last_match_idx = i;
        }
    }
    return switch (match_count) {
        0 => .none,
        1 => .{ .exact = last_match_idx },
        else => .multiple,
    };
}

fn makeTestHints(comptime n: usize) [n]Hint {
    return .{Hint{ .label = .{ 0, 0 }, .url = "", .x = 0, .y = 0 }} ** n;
}

test "generateLabels: zero items" {
    var items = makeTestHints(0);
    generateLabels(&items, default_alphabet);
}

test "generateLabels: single item" {
    var items = makeTestHints(1);
    generateLabels(&items, default_alphabet);
    try testing.expectEqualSlices(u8, "S", std.mem.sliceTo(&items[0].label, 0));
}

test "generateLabels: all single-char labels" {
    const alpha = default_alphabet;
    var items = makeTestHints(alpha.len);
    generateLabels(&items, alpha);

    for (items, 0..) |item, i| {
        try testing.expectEqualSlices(u8, alpha[i .. i + 1], std.mem.sliceTo(&item.label, 0));
    }
}

test "generateLabels: one more than alphabet triggers two-char labels" {
    const alpha = default_alphabet;
    const count = alpha.len + 1;
    var items = makeTestHints(count);
    generateLabels(&items, alpha);

    // First prefix group: alpha_len two-char labels starting with alpha[0].
    for (0..alpha.len) |j| {
        const label = std.mem.sliceTo(&items[j].label, 0);
        try testing.expectEqual(@as(usize, 2), label.len);
        try testing.expectEqual(alpha[0], label[0]);
        try testing.expectEqual(alpha[j], label[1]);
    }

    // Remaining labels are single-char.
    for (alpha.len..count) |i| {
        try testing.expectEqual(@as(usize, 1), std.mem.sliceTo(&items[i].label, 0).len);
    }
}

test "generateLabels: no ambiguity between single and multi-char labels" {
    const alpha = default_alphabet;
    // Use enough items to need multiple prefix groups.
    const count = alpha.len * 2;
    var items = makeTestHints(count);
    generateLabels(&items, alpha);

    // Collect all single-char labels.
    var single_chars: [alpha.len]u8 = undefined;
    var single_count: usize = 0;
    for (items) |item| {
        const label = std.mem.sliceTo(&item.label, 0);
        if (label.len == 1) {
            single_chars[single_count] = label[0];
            single_count += 1;
        }
    }

    // Verify no two-char label starts with any single-char label.
    for (items) |item| {
        const label = std.mem.sliceTo(&item.label, 0);
        if (label.len == 2) {
            for (single_chars[0..single_count]) |sc| {
                try testing.expect(label[0] != sc);
            }
        }
    }
}

test "generateLabels: custom alphabet" {
    const alpha = "AB";
    var items = makeTestHints(3);
    generateLabels(&items, alpha);

    // With 2-char alphabet and 3 items: need 1 prefix.
    // Prefix "A" produces: AA, AB. Standalone: B.
    try testing.expectEqualSlices(u8, "AA", std.mem.sliceTo(&items[0].label, 0));
    try testing.expectEqualSlices(u8, "AB", std.mem.sliceTo(&items[1].label, 0));
    try testing.expectEqualSlices(u8, "B", std.mem.sliceTo(&items[2].label, 0));
}

test "generateLabels: short alphabet falls back to default" {
    var items = makeTestHints(1);
    generateLabels(&items, "");
    try testing.expectEqualSlices(u8, "S", std.mem.sliceTo(&items[0].label, 0));

    generateLabels(&items, "X");
    try testing.expectEqualSlices(u8, "S", std.mem.sliceTo(&items[0].label, 0));
}

test "matchTyped: empty typed matches all (multiple)" {
    var items = makeTestHints(3);
    generateLabels(&items, default_alphabet);
    try testing.expectEqual(MatchResult.multiple, matchTyped(&items, ""));
}

test "matchTyped: single char exact match" {
    var items = makeTestHints(1);
    generateLabels(&items, default_alphabet);
    try testing.expectEqual(MatchResult{ .exact = 0 }, matchTyped(&items, "S"));
}

test "matchTyped: no match" {
    var items = makeTestHints(3);
    generateLabels(&items, default_alphabet);
    try testing.expectEqual(MatchResult.none, matchTyped(&items, "Z"));
}

test "matchTyped: prefix narrows to multiple" {
    const alpha = default_alphabet;
    const count = alpha.len + 1;
    var items = makeTestHints(count);
    generateLabels(&items, alpha);
    // Typing the first prefix char matches all 14 two-char labels.
    try testing.expectEqual(MatchResult.multiple, matchTyped(&items, &.{alpha[0]}));
}

test "matchTyped: full two-char label gives exact" {
    const alpha = default_alphabet;
    const count = alpha.len + 1;
    var items = makeTestHints(count);
    generateLabels(&items, alpha);
    try testing.expectEqual(MatchResult{ .exact = 0 }, matchTyped(&items, &.{ alpha[0], alpha[0] }));
}
