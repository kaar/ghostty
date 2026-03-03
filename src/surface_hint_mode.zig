/// Home-row-friendly alphabet for hint labels (from foot terminal).
pub const label_alphabet = "SADFJKLEWCMPGH";

/// Labels algorithm, BFS-style expansion where single-char labels that
/// become prefixes of multi-char labels are "consumed". This guarantees
/// that typing any single character either selects a hint immediately or
/// narrows to a group — never both.
///
/// Generate unambiguous key combos, writing into any slice of structs
/// with `label: [2]u8` and `label_len: u8` fields.
///
/// With a 14-char alphabet, supports up to 14 + 14*14 = 210 labels.
pub fn generate_labels(comptime T: type, items: []T) void {
    const alpha = label_alphabet;
    const alpha_len = alpha.len;
    const count = items.len;

    if (count == 0) return;

    // Determine how many single-char labels get consumed as prefixes
    // for 2-char labels.
    //
    // Each prefix group replaces 1 single-char label with `alpha_len`
    // two-char labels, a net gain of (alpha_len - 1).
    //
    // count <= (alpha_len - prefixes) + prefixes * alpha_len
    // Solving: prefixes = ceil((count - alpha_len) / (alpha_len - 1))
    const prefixes_needed: usize = if (count <= alpha_len)
        0
    else
        (count - alpha_len + (alpha_len - 2)) / (alpha_len - 1);

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
                items[idx].label_len = 2;
                idx += 1;
            }
        } else {
            // Standalone single-char label.
            items[idx].label = .{ alpha[i], 0 };
            items[idx].label_len = 1;
            idx += 1;
        }
    }
}

const std = @import("std");

const TestItem = struct {
    label: [2]u8,
    label_len: u8,
};

fn makeTestItems(comptime n: usize) [n]TestItem {
    return .{.{ .label = .{ 0, 0 }, .label_len = 0 }} ** n;
}

test "zero items" {
    var items = makeTestItems(0);
    generate_labels(TestItem, &items);
}

test "single item" {
    var items = makeTestItems(1);
    generate_labels(TestItem, &items);
    try std.testing.expectEqual(@as(u8, 1), items[0].label_len);
    try std.testing.expectEqual(@as(u8, 'S'), items[0].label[0]);
}

test "all single-char labels" {
    const alpha = label_alphabet;
    var items = makeTestItems(alpha.len);
    generate_labels(TestItem, &items);

    for (items, 0..) |item, i| {
        try std.testing.expectEqual(@as(u8, 1), item.label_len);
        try std.testing.expectEqual(alpha[i], item.label[0]);
    }
}

test "one more than alphabet triggers two-char labels" {
    const alpha = label_alphabet;
    const count = alpha.len + 1;
    var items = makeTestItems(count);
    generate_labels(TestItem, &items);

    // First prefix group: alpha_len two-char labels starting with alpha[0].
    for (0..alpha.len) |j| {
        try std.testing.expectEqual(@as(u8, 2), items[j].label_len);
        try std.testing.expectEqual(alpha[0], items[j].label[0]);
        try std.testing.expectEqual(alpha[j], items[j].label[1]);
    }

    // Remaining labels are single-char.
    for (alpha.len..count) |i| {
        try std.testing.expectEqual(@as(u8, 1), items[i].label_len);
    }
}

test "no ambiguity between single and multi-char labels" {
    const alpha = label_alphabet;
    // Use enough items to need multiple prefix groups.
    const count = alpha.len * 2;
    var items = makeTestItems(count);
    generate_labels(TestItem, &items);

    // Collect all single-char labels.
    var single_chars: [alpha.len]u8 = undefined;
    var single_count: usize = 0;
    for (items) |item| {
        if (item.label_len == 1) {
            single_chars[single_count] = item.label[0];
            single_count += 1;
        }
    }

    // Verify no two-char label starts with any single-char label.
    for (items) |item| {
        if (item.label_len == 2) {
            for (single_chars[0..single_count]) |sc| {
                if (item.label[0] == sc) {
                    std.debug.print("Ambiguity: single-char '{c}' is prefix of two-char '{c}{c}'\n", .{ sc, item.label[0], item.label[1] });
                    return error.TestUnexpectedResult;
                }
            }
        }
    }
}
