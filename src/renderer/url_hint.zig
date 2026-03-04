const std = @import("std");
const Allocator = std.mem.Allocator;
const font = @import("../font/main.zig");
const terminal = @import("../terminal/main.zig");
const renderer = @import("../renderer.zig");
const cellpkg = @import("cell.zig");

const log = std.log.scoped(.url_hint);

/// Render all URL hint labels over the terminal grid.
pub fn renderHints(
    cells: *cellpkg.Contents,
    alloc: Allocator,
    font_grid: *font.SharedGrid,
    grid_metrics: font.Metrics,
    hints: []const renderer.State.UrlHint,
    state: *const terminal.RenderState,
) void {
    for (hints) |hint| {
        const label = hint.label[0..hint.label_len];
        for (label, 0..) |ch, i| {
            addCell(
                cells,
                alloc,
                font_grid,
                grid_metrics,
                ch,
                .{
                    .x = hint.x +| @as(terminal.size.CellCountInt, @intCast(i)),
                    .y = hint.y,
                },
                hint.matched,
                state,
            ) catch |err| {
                log.warn("error building URL hint cell err={}", .{err});
            };
        }
    }
}

/// Render a single URL hint character cell.
fn addCell(
    cells: *cellpkg.Contents,
    alloc: Allocator,
    font_grid: *font.SharedGrid,
    grid_metrics: font.Metrics,
    ch: u8,
    coord: terminal.Coordinate,
    matched: bool,
    state: *const terminal.RenderState,
) !void {
    // Bounds check
    if (coord.x >= cells.size.columns or
        @as(u32, coord.y) >= cells.size.rows)
        return;

    // Use a bold style for the hint label
    const render_ = font_grid.renderCodepoint(
        alloc,
        @intCast(ch),
        .bold,
        .text,
        .{ .grid_metrics = grid_metrics },
    ) catch |err| {
        log.warn("error rendering URL hint glyph err={}", .{err});
        return;
    };
    const render = render_ orelse {
        log.warn("failed to find font for URL hint char={c}", .{ch});
        return;
    };

    // Set a background for the hint cell: yellow if matched, dim gray if not.
    const bg_color: [4]u8 = if (matched) .{ 220, 180, 30, 255 } else .{ 80, 80, 80, 200 };
    cells.bgCell(coord.y, coord.x).* = bg_color;

    // Foreground: dark text on yellow bg if matched, lighter if dimmed.
    const fg = if (matched)
        terminal.color.RGB{ .r = 30, .g = 30, .b = 30 }
    else
        state.colors.foreground;

    // Add the text glyph
    try cells.add(alloc, .text, .{
        .atlas = .grayscale,
        .grid_pos = .{ @intCast(coord.x), @intCast(coord.y) },
        .color = .{ fg.r, fg.g, fg.b, 255 },
        .glyph_pos = .{ render.glyph.atlas_x, render.glyph.atlas_y },
        .glyph_size = .{ render.glyph.width, render.glyph.height },
        .bearings = .{
            @intCast(render.glyph.offset_x),
            @intCast(render.glyph.offset_y),
        },
    });
}
