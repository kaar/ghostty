/// Home-row-friendly alphabet for hint labels (from foot terminal).
pub const label_alphabet = "SADFJKLEWCMPGH";

/// Labels algorithm, BFS-style expansion where single-char labels that
/// become prefixes of multi-char labels are "consumed". This guarantees
/// that typing any single character either selects a hint immediately or
/// narrows to a group — never both.
///
/// With a 14-char alphabet, supports up to 14 + 14*14 = 210 labels.

/// Result of matching a typed prefix against hint labels.
pub const MatchResult = union(enum) {
    /// No hints match the typed prefix.
    none,
    /// Exactly one hint matches — return its index.
    exact: usize,
    /// Multiple hints still match — need more input.
    multiple,
};

/// Check how many labels match the given typed prefix.
pub fn match_typed(items: []const Hint, typed: []const u8) MatchResult {
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

pub fn generate_labels(items: []Hint) void {
    const alpha = label_alphabet;
    const alpha_len = alpha.len;
    const count = items.len;

    if (count == 0) return;

    // Each prefix char replaces 1 single-char label with `alpha_len`
    // two-char labels, a net gain of (alpha_len - 1).
    const prefixes_needed: usize = if (count <= alpha_len)
        0
    else
        std.math.divCeil(usize, count - alpha_len, alpha_len - 1) catch unreachable;

    // Assign labels. The first `prefixes_needed` label_alphabet entries become
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

const std = @import("std");
const Allocator = std.mem.Allocator;
const oni = @import("oniguruma");
const terminal = @import("terminal/main.zig");
const configpkg = @import("config.zig");

/// A detected URL hint with its label, URL string, and viewport position.
pub const Hint = struct {
    /// Hint label, e.g. "A" or "AB".
    label: [2:0]u8,
    /// The URL string (allocated).
    url: []const u8,
    /// Viewport position where the URL starts.
    start: terminal.point.Coordinate,
};

/// Collect URLs matching the scheme regex from the viewport string map.
pub fn collectRegexUrls(
    alloc: Allocator,
    screen: *terminal.Screen,
    strmap: *terminal.StringMap,
    hints: *std.ArrayListUnmanaged(Hint),
) !void {
    var url_re = try oni.Regex.init(
        configpkg.url.url_regex,
        .{},
        oni.Encoding.utf8,
        oni.Syntax.default,
        null,
    );
    defer url_re.deinit();

    var it = strmap.searchIterator(url_re);
    while (true) {
        var match = (try it.next()) orelse break;
        defer match.deinit();
        const sel = match.selection();

        const url_str = try screen.selectionString(alloc, .{
            .sel = sel,
            .trim = false,
        });

        const start_point = screen.pages.pointFromPin(.viewport, sel.start()) orelse continue;

        try hints.append(alloc, .{
            .label = undefined,
            .url = url_str,
            .start = start_point.coord(),
        });
    }
}

// TODO: Add support for OSC8 hyperlinks in URL hint mode.
// These are explicit hyperlinks embedded by applications via the OSC 8 escape
// sequence and should be included alongside regex-matched URLs.

/// Sort hints by position and remove duplicates at the same start coordinate.
pub fn sortAndDeduplicate(alloc: Allocator, hints: *std.ArrayListUnmanaged(Hint)) void {
    std.mem.sort(Hint, hints.items, {}, struct {
        fn lessThan(_: void, a: Hint, b: Hint) bool {
            if (a.start.y != b.start.y) return a.start.y < b.start.y;
            return a.start.x < b.start.x;
        }
    }.lessThan);

    var write_idx: usize = 0;
    for (hints.items, 0..) |hint, i| {
        if (i > 0 and hint.start.x == hints.items[write_idx - 1].start.x and
            hint.start.y == hints.items[write_idx - 1].start.y)
        {
            alloc.free(hint.url);
            continue;
        }
        hints.items[write_idx] = hint;
        write_idx += 1;
    }
    hints.shrinkRetainingCapacity(write_idx);
}

fn makeTestHints(comptime n: usize) [n]Hint {
    return .{Hint{ .label = .{ 0, 0 }, .url = "", .start = .{ .x = 0, .y = 0 } }} ** n;
}

test "zero items" {
    var items = makeTestHints(0);
    generate_labels(&items);
}

test "single item" {
    var items = makeTestHints(1);
    generate_labels(&items);
    try std.testing.expectEqualSlices(u8, "S", std.mem.sliceTo(&items[0].label, 0));
}

test "all single-char labels" {
    const alpha = label_alphabet;
    var items = makeTestHints(alpha.len);
    generate_labels(&items);

    for (items, 0..) |item, i| {
        try std.testing.expectEqualSlices(u8, alpha[i .. i + 1], std.mem.sliceTo(&item.label, 0));
    }
}

test "one more than alphabet triggers two-char labels" {
    const alpha = label_alphabet;
    const count = alpha.len + 1;
    var items = makeTestHints(count);
    generate_labels(&items);

    // First prefix group: alpha_len two-char labels starting with alpha[0].
    for (0..alpha.len) |j| {
        const label = std.mem.sliceTo(&items[j].label, 0);
        try std.testing.expectEqual(@as(usize, 2), label.len);
        try std.testing.expectEqual(alpha[0], label[0]);
        try std.testing.expectEqual(alpha[j], label[1]);
    }

    // Remaining labels are single-char.
    for (alpha.len..count) |i| {
        try std.testing.expectEqual(@as(usize, 1), std.mem.sliceTo(&items[i].label, 0).len);
    }
}

test "no ambiguity between single and multi-char labels" {
    const alpha = label_alphabet;
    // Use enough items to need multiple prefix groups.
    const count = alpha.len * 2;
    var items = makeTestHints(count);
    generate_labels(&items);

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
                if (label[0] == sc) {
                    std.debug.print("Ambiguity: single-char '{c}' is prefix of two-char '{c}{c}'\n", .{ sc, label[0], label[1] });
                    return error.TestUnexpectedResult;
                }
            }
        }
    }
}

test "match_typed: empty typed matches all (multiple)" {
    var items = makeTestHints(3);
    generate_labels(&items);
    try std.testing.expectEqual(MatchResult.multiple, match_typed(&items, ""));
}

test "match_typed: single char exact match" {
    var items = makeTestHints(1);
    generate_labels(&items);
    // Single item gets label "S".
    try std.testing.expectEqual(MatchResult{ .exact = 0 }, match_typed(&items, "S"));
}

test "match_typed: no match" {
    var items = makeTestHints(3);
    generate_labels(&items);
    try std.testing.expectEqual(MatchResult.none, match_typed(&items, "Z"));
}

test "match_typed: prefix narrows to multiple" {
    const alpha = label_alphabet;
    // 15 items: first alpha char becomes prefix for 14 two-char labels,
    // remaining 1 item gets a single-char label.
    const count = alpha.len + 1;
    var items = makeTestHints(count);
    generate_labels(&items);
    // Typing the first prefix char matches all 14 two-char labels.
    try std.testing.expectEqual(MatchResult.multiple, match_typed(&items, &.{alpha[0]}));
}

test "match_typed: full two-char label gives exact" {
    const alpha = label_alphabet;
    const count = alpha.len + 1;
    var items = makeTestHints(count);
    generate_labels(&items);
    // First two-char label is alpha[0] ++ alpha[0].
    try std.testing.expectEqual(MatchResult{ .exact = 0 }, match_typed(&items, &.{ alpha[0], alpha[0] }));
}
