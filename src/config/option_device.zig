//! Port of the device option group from src/config/option_defs.c
//! (strangler-fig Phase 4, slice 6).
//!
//! Exports one C symbol: acwm_config_apply_device_option(), called by
//! parse_option() ahead of its strcmp chain (guarded by
//! ACWM_ZIG_DEVICE_OPTION, defined only in the Zig build). Covers the
//! contiguous mouse_accel_profile..trackpad_scroll_factor block: pointer and
//! trackpad acceleration, left-handed/middle-emulation toggles, click and
//! scroll methods, send-events modes, button_map, scroll factors (21 keys).
//!
//! C parity: raw atoi stores; uint32 fields (accel profiles, scroll/click
//! methods, send-events modes, button_map) wrap negatives via @bitCast;
//! mouse_accel_speed / trackpad_accel_speed / axis_scroll_factor /
//! trackpad_scroll_factor are double fields assigned straight from atof —
//! no float narrowing (double_raw kind).
//!
//! Tests live at the bottom; no C stub is needed (libc + cc types only).

const std = @import("std");
const c = @import("cc");

extern "c" fn atoi(nptr: [*:0]const u8) c_int;
extern "c" fn atof(nptr: [*:0]const u8) f64;

// ---------------------------------------------------------------------------
// option table
// ---------------------------------------------------------------------------

const Kind = enum {
    /// atoi -> int32_t Config field, no clamp.
    int_raw,
    /// atoi -> uint32_t Config field; negative wraps like C.
    uint_raw,
    /// atof -> double Config field (no narrowing).
    double_raw,
};

const Row = struct {
    key: [:0]const u8,
    kind: Kind,
    field: [:0]const u8,
};

/// The 21 keys of the device block, in C order.
const rows = [_]Row{
    .{ .key = "mouse_accel_profile", .kind = .uint_raw, .field = "mouse_accel_profile" },
    .{ .key = "mouse_accel_speed", .kind = .double_raw, .field = "mouse_accel_speed" },
    .{ .key = "trackpad_accel_profile", .kind = .uint_raw, .field = "trackpad_accel_profile" },
    .{ .key = "trackpad_accel_speed", .kind = .double_raw, .field = "trackpad_accel_speed" },
    .{ .key = "mouse_left_handed", .kind = .int_raw, .field = "mouse_left_handed" },
    .{ .key = "mouse_middle_button_emulation", .kind = .int_raw, .field = "mouse_middle_button_emulation" },
    .{ .key = "mouse_scroll_method", .kind = .uint_raw, .field = "mouse_scroll_method" },
    .{ .key = "mouse_scroll_button", .kind = .uint_raw, .field = "mouse_scroll_button" },
    .{ .key = "mouse_click_method", .kind = .uint_raw, .field = "mouse_click_method" },
    .{ .key = "mouse_send_events_mode", .kind = .uint_raw, .field = "mouse_send_events_mode" },
    .{ .key = "trackpad_left_handed", .kind = .int_raw, .field = "trackpad_left_handed" },
    .{ .key = "trackpad_middle_button_emulation", .kind = .int_raw, .field = "trackpad_middle_button_emulation" },
    .{ .key = "trackpad_disable_while_typing", .kind = .int_raw, .field = "trackpad_disable_while_typing" },
    .{ .key = "trackpad_scroll_method", .kind = .uint_raw, .field = "trackpad_scroll_method" },
    .{ .key = "trackpad_scroll_button", .kind = .uint_raw, .field = "trackpad_scroll_button" },
    .{ .key = "trackpad_click_method", .kind = .uint_raw, .field = "trackpad_click_method" },
    .{ .key = "trackpad_send_events_mode", .kind = .uint_raw, .field = "trackpad_send_events_mode" },
    .{ .key = "send_events_mode", .kind = .uint_raw, .field = "send_events_mode" },
    .{ .key = "button_map", .kind = .uint_raw, .field = "button_map" },
    .{ .key = "axis_scroll_factor", .kind = .double_raw, .field = "axis_scroll_factor" },
    .{ .key = "trackpad_scroll_factor", .kind = .double_raw, .field = "trackpad_scroll_factor" },
};

// ---------------------------------------------------------------------------
// apply helpers
// ---------------------------------------------------------------------------

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
        .double_raw => {
            @field(cfg, row.field) = atof(value);
            return 1;
        },
    }
}

/// C entry point (tri-state: 1 applied, -1 invalid value, 0 not ours).
export fn acwm_config_apply_device_option(
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
    return acwm_config_apply_device_option(cfg, key, value, 13);
}

test "tri-state dispatch: device key, adjacent-group keys, unknown" {
    var config: c.Config = std.mem.zeroes(c.Config);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "mouse_left_handed", "1"));
    // gaps block follows in the chain (later slice); gap_corner precedes it
    try testing.expectEqual(@as(c_int, 0), apply(&config, "gap_inner_horizontal", "5"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "border_px", "2"));
    // bar block precedes this one
    try testing.expectEqual(@as(c_int, 0), apply(&config, "bar_height", "30"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "mouse_accel_profilex", "1"));
}

test "uint fields wrap negatives, int fields store verbatim" {
    var config: c.Config = std.mem.zeroes(c.Config);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "mouse_accel_profile", "2"));
    try testing.expectEqual(@as(u32, 2), config.mouse_accel_profile);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "trackpad_accel_profile", "-1"));
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), config.trackpad_accel_profile);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "mouse_scroll_method", "4"));
    try testing.expectEqual(@as(u32, 4), config.mouse_scroll_method);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "mouse_click_method", "1"));
    try testing.expectEqual(@as(u32, 1), config.mouse_click_method);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "button_map", "3"));
    try testing.expectEqual(@as(u32, 3), config.button_map);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "send_events_mode", "1"));
    try testing.expectEqual(@as(u32, 1), config.send_events_mode);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "mouse_left_handed", "-1"));
    try testing.expectEqual(@as(i32, -1), config.mouse_left_handed);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "trackpad_disable_while_typing", "1"));
    try testing.expectEqual(@as(i32, 1), config.trackpad_disable_while_typing);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "trackpad_middle_button_emulation", "0"));
    try testing.expectEqual(@as(i32, 0), config.trackpad_middle_button_emulation);
}

test "double fields keep full atof precision (no float narrowing)" {
    var config: c.Config = std.mem.zeroes(c.Config);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "mouse_accel_speed", "0.35"));
    try testing.expectEqual(@as(f64, 0.35), config.mouse_accel_speed);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "trackpad_accel_speed", "-0.75"));
    try testing.expectEqual(@as(f64, -0.75), config.trackpad_accel_speed);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "axis_scroll_factor", "1.25"));
    try testing.expectEqual(@as(f64, 1.25), config.axis_scroll_factor);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "trackpad_scroll_factor", "0.5"));
    try testing.expectEqual(@as(f64, 0.5), config.trackpad_scroll_factor);

    // a value that would lose bits if narrowed to f32 stays exact in f64
    try testing.expectEqual(@as(c_int, 1), apply(&config, "axis_scroll_factor", "0.1"));
    try testing.expectEqual(@as(f64, 0.1), config.axis_scroll_factor);
}

test "every table row dispatches through the C entry" {
    var config: c.Config = std.mem.zeroes(c.Config);

    for (rows) |row| {
        const r = acwm_config_apply_device_option(&config, row.key, "5", 0);
        if (r != 1) {
            std.debug.print("row failed to dispatch: {s}\n", .{row.key});
            return error.RowFailedToDispatch;
        }
    }
    try testing.expectEqual(@as(usize, 21), rows.len);
}
