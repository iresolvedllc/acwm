//! Port of the input/cursor/drag option group from src/config/option_defs.c
//! (strangler-fig Phase 4, slice 4).
//!
//! Exports one C symbol: acwm_config_apply_input_option(), called by
//! parse_option() ahead of its strcmp chain (guarded by
//! ACWM_ZIG_INPUT_OPTION, defined only in the Zig build). Covers the
//! cursor/jump-label block (jump_labels, cursor_hide_*,
//! axis_bind_apply_timeout) plus the contiguous drag..cursor_theme block:
//! drag/border-resize tuning, tab modes, key repeat, trackpad/touch toggles,
//! natural scrolling, cursor size/theme (23 keys). Device acceleration and
//! button mapping keys follow the bar block and belong to a later slice.
//!
//! C parity: raw atoi stores (post-parse clamps stay in override_config);
//! uint32_t fields (cursor_hide_*, axis_bind_apply_timeout, cursor_size)
//! wrap negatives via @bitCast; jump_labels/cursor_theme strdup over the
//! previous value.
//!
//! Tests live at the bottom; no C stub is needed (libc + cc types only).

const std = @import("std");
const c = @import("cc");

extern "c" fn atoi(nptr: [*:0]const u8) c_int;
extern "c" fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern "c" fn free(ptr: ?*anyopaque) void;

// ---------------------------------------------------------------------------
// option table
// ---------------------------------------------------------------------------

const Kind = enum {
    /// atoi -> int32_t Config field, no clamp.
    int_raw,
    /// atoi -> uint32_t Config field; negative wraps like C.
    uint_raw,
    /// strdup over a Config char * (frees the old value first).
    string,
};

const Row = struct {
    key: [:0]const u8,
    kind: Kind,
    field: [:0]const u8,
};

/// The 23 keys, in C chain order.
const rows = [_]Row{
    .{ .key = "jump_labels", .kind = .string, .field = "jump_labels" },
    .{ .key = "cursor_hide_timeout", .kind = .uint_raw, .field = "cursor_hide_timeout" },
    .{ .key = "cursor_hide_on_keypress", .kind = .uint_raw, .field = "cursor_hide_on_keypress" },
    .{ .key = "axis_bind_apply_timeout", .kind = .uint_raw, .field = "axis_bind_apply_timeout" },
    .{ .key = "drag_corner", .kind = .int_raw, .field = "drag_corner" },
    .{ .key = "drag_warp_cursor", .kind = .int_raw, .field = "drag_warp_cursor" },
    .{ .key = "enable_border_resize", .kind = .int_raw, .field = "enable_border_resize" },
    .{ .key = "border_resize_size", .kind = .int_raw, .field = "border_resize_size" },
    .{ .key = "smart_gaps", .kind = .int_raw, .field = "smartgaps" },
    .{ .key = "monocle_tab_mode", .kind = .int_raw, .field = "monocle_tab_mode" },
    .{ .key = "deck_tab_mode", .kind = .int_raw, .field = "deck_tab_mode" },
    .{ .key = "repeat_rate", .kind = .int_raw, .field = "repeat_rate" },
    .{ .key = "repeat_delay", .kind = .int_raw, .field = "repeat_delay" },
    .{ .key = "disable_trackpad", .kind = .int_raw, .field = "disable_trackpad" },
    .{ .key = "touch_enable", .kind = .int_raw, .field = "touch_enable" },
    .{ .key = "touch_enable_mouse_emulation", .kind = .int_raw, .field = "touch_enable_mouse_emulation" },
    .{ .key = "tap_to_click", .kind = .int_raw, .field = "tap_to_click" },
    .{ .key = "tap_and_drag", .kind = .int_raw, .field = "tap_and_drag" },
    .{ .key = "drag_lock", .kind = .int_raw, .field = "drag_lock" },
    .{ .key = "mouse_natural_scrolling", .kind = .int_raw, .field = "mouse_natural_scrolling" },
    .{ .key = "trackpad_natural_scrolling", .kind = .int_raw, .field = "trackpad_natural_scrolling" },
    .{ .key = "cursor_size", .kind = .uint_raw, .field = "cursor_size" },
    .{ .key = "cursor_theme", .kind = .string, .field = "cursor_theme" },
};

// ---------------------------------------------------------------------------
// apply helpers
// ---------------------------------------------------------------------------

fn setStringSlot(slot: anytype, value: [*:0]const u8) void {
    if (slot.* != null)
        free(@ptrCast(@constCast(slot.*)));
    slot.* = strdup(value);
}

fn applyRow(cfg: *c.Config, comptime row: Row, value: [*:0]const u8) c_int {
    switch (comptime row.kind) {
        .int_raw => {
            @field(cfg, row.field) = atoi(value);
            return 1;
        },
        .uint_raw => {
            @field(cfg, row.field) = @bitCast(atoi(value));
            return 1;
        },
        .string => {
            setStringSlot(&@field(cfg, row.field), value);
            return 1;
        },
    }
}

/// C entry point (tri-state: 1 applied, -1 invalid value, 0 not ours).
export fn acwm_config_apply_input_option(
    config: ?*c.Config,
    key: [*:0]const u8,
    value: [*:0]const u8,
    line_number: c_int,
) callconv(.c) c_int {
    _ = line_number;
    const cfg = config orelse return 0;
    const k = std.mem.span(key);

    inline for (rows) |row| {
        if (std.mem.eql(u8, k, row.key))
            return applyRow(cfg, row, value);
    }
    return 0;
}

// ---------------------------------------------------------------------------
// tests (no stub needed)
// ---------------------------------------------------------------------------

const testing = std.testing;

fn apply(cfg: *c.Config, key: [:0]const u8, value: [:0]const u8) c_int {
    return acwm_config_apply_input_option(cfg, key, value, 9);
}

test "tri-state dispatch: input key, adjacent-group keys, unknown" {
    var config: c.Config = std.mem.zeroes(c.Config);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "repeat_rate", "40"));
    // bar decoration (bar slice) and device accel (later slice) must not match
    try testing.expectEqual(@as(c_int, 0), apply(&config, "bar_decorate_font_desc", "Sans"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "group_bar_decorate_fg_color", "#fff"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "mouse_accel_profile", "1"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "trackpad_accel_speed", "0.5"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "repeat_ratex", "1"));
}

test "int fields store atoi verbatim" {
    var config: c.Config = std.mem.zeroes(c.Config);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "drag_corner", "2"));
    try testing.expectEqual(@as(i32, 2), config.drag_corner);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "enable_border_resize", "-1"));
    try testing.expectEqual(@as(i32, -1), config.enable_border_resize);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "smart_gaps", "1"));
    try testing.expectEqual(@as(i32, 1), config.smartgaps);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "monocle_tab_mode", "3"));
    try testing.expectEqual(@as(i32, 3), config.monocle_tab_mode);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "deck_tab_mode", "4"));
    try testing.expectEqual(@as(i32, 4), config.deck_tab_mode);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "repeat_rate", "25"));
    try testing.expectEqual(@as(i32, 25), config.repeat_rate);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "repeat_delay", "600"));
    try testing.expectEqual(@as(i32, 600), config.repeat_delay);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "disable_trackpad", "0"));
    try testing.expectEqual(@as(i32, 0), config.disable_trackpad);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "touch_enable", "1"));
    try testing.expectEqual(@as(i32, 1), config.touch_enable);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "touch_enable_mouse_emulation", "1"));
    try testing.expectEqual(@as(i32, 1), config.touch_enable_mouse_emulation);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "tap_to_click", "1"));
    try testing.expectEqual(@as(i32, 1), config.tap_to_click);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "tap_and_drag", "1"));
    try testing.expectEqual(@as(i32, 1), config.tap_and_drag);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "drag_lock", "1"));
    try testing.expectEqual(@as(i32, 1), config.drag_lock);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "mouse_natural_scrolling", "1"));
    try testing.expectEqual(@as(i32, 1), config.mouse_natural_scrolling);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "trackpad_natural_scrolling", "0"));
    try testing.expectEqual(@as(i32, 0), config.trackpad_natural_scrolling);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "border_resize_size", "12"));
    try testing.expectEqual(@as(i32, 12), config.border_resize_size);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "drag_warp_cursor", "1"));
    try testing.expectEqual(@as(i32, 1), config.drag_warp_cursor);
}

test "uint fields wrap negatives like the C implicit conversion" {
    var config: c.Config = std.mem.zeroes(c.Config);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "cursor_hide_timeout", "2000"));
    try testing.expectEqual(@as(u32, 2000), config.cursor_hide_timeout);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "cursor_hide_timeout", "-1"));
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), config.cursor_hide_timeout);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "axis_bind_apply_timeout", "150"));
    try testing.expectEqual(@as(u32, 150), config.axis_bind_apply_timeout);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "cursor_size", "24"));
    try testing.expectEqual(@as(u32, 24), config.cursor_size);
}

test "string options free the old value and store the new" {
    var config: c.Config = std.mem.zeroes(c.Config);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "jump_labels", "abcdefghijklmnop"));
    try testing.expectEqualStrings(
        "abcdefghijklmnop",
        std.mem.span(@as([*:0]const u8, @ptrCast(config.jump_labels))),
    );
    // overwrite exercises the free-old path
    try testing.expectEqual(@as(c_int, 1), apply(&config, "jump_labels", "asdfghjkl"));
    try testing.expectEqualStrings(
        "asdfghjkl",
        std.mem.span(@as([*:0]const u8, @ptrCast(config.jump_labels))),
    );

    try testing.expectEqual(@as(c_int, 1), apply(&config, "cursor_theme", "Adwaita"));
    try testing.expectEqualStrings(
        "Adwaita",
        std.mem.span(@as([*:0]const u8, @ptrCast(config.cursor_theme))),
    );
}

test "every table row dispatches through the C entry" {
    var config: c.Config = std.mem.zeroes(c.Config);

    for (rows) |row| {
        const r = acwm_config_apply_input_option(&config, row.key, "5", 0);
        if (r != 1) {
            std.debug.print("row failed to dispatch: {s}\n", .{row.key});
            return error.RowFailedToDispatch;
        }
    }
    try testing.expectEqual(@as(usize, 23), rows.len);
}
