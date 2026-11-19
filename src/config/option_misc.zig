//! Port of the early misc option group from src/config/option_defs.c
//! (strangler-fig Phase 4, slice 9).
//!
//! Exports one C symbol: acwm_config_apply_misc_option(), called by
//! parse_option() ahead of its strcmp chain (guarded by
//! ACWM_ZIG_MISC_OPTION, defined only in the Zig build). Covers the
//! single_scratchpad..gesture_swipe_min_speed_to_force block plus the
//! xkb_rules_* strings: scratchpad persistence, xwayland knobs, explicit
//! sync, tearing/hdr, shortcuts/middle-paste/lock transparency, auto
//! reload, monocle/no-border switches, snap & drag tuning, gesture
//! tuning, and the five fixed-size xkb rule strings (30 keys).
//!
//! C parity: raw atoi stores; swipe_min_threshold/gesture_swipe_distance
//! are uint32 (negative wrap via @bitCast); gesture ratios are double
//! (no narrowing); xkb rule strings use strncpy into char[128] with a
//! forced NUL at index 127 (truncation semantics preserved);
//! sync_obj_enable maps to the syncobj_enable field.
//!
//! Tests live at the bottom; no C stub is needed (libc + cc types only).

const std = @import("std");
const c = @import("cc");

extern "c" fn atoi(nptr: [*:0]const u8) c_int;
extern "c" fn atof(nptr: [*:0]const u8) f64;
extern "c" fn strncpy(dest: [*]u8, src: [*:0]const u8, n: usize) [*]u8;

// ---------------------------------------------------------------------------
// option table
// ---------------------------------------------------------------------------

const Kind = enum {
    /// atoi -> int32_t Config field.
    int_raw,
    /// atoi -> uint32_t Config field; negative wraps like C.
    uint_raw,
    /// atof -> double Config field (no narrowing).
    double_raw,
    /// strncpy into char[N] with a forced NUL at the last slot.
    char128,
};

const Row = struct {
    key: [:0]const u8,
    kind: Kind,
    field: [:0]const u8,
};

/// The 30 keys, in C chain order.
const rows = [_]Row{
    .{ .key = "single_scratchpad", .kind = .int_raw, .field = "single_scratchpad" },
    .{ .key = "xwayland_persistence", .kind = .int_raw, .field = "xwayland_persistence" },
    .{ .key = "xwayland_ignore_scale", .kind = .int_raw, .field = "xwayland_ignore_scale" },
    .{ .key = "sync_obj_enable", .kind = .int_raw, .field = "syncobj_enable" },
    .{ .key = "tag_carousel", .kind = .int_raw, .field = "tag_carousel" },
    .{ .key = "allow_tearing", .kind = .int_raw, .field = "allow_tearing" },
    .{ .key = "hdr_depth", .kind = .int_raw, .field = "hdr_depth" },
    .{ .key = "allow_shortcuts_inhibit", .kind = .int_raw, .field = "allow_shortcuts_inhibit" },
    .{ .key = "disable_middle_paste", .kind = .int_raw, .field = "disable_middle_paste" },
    .{ .key = "allow_lock_transparent", .kind = .int_raw, .field = "allow_lock_transparent" },
    .{ .key = "auto_reload_config", .kind = .int_raw, .field = "auto_reload_config" },
    .{ .key = "no_border_when_single", .kind = .int_raw, .field = "no_border_when_single" },
    .{ .key = "no_radius_when_single", .kind = .int_raw, .field = "no_radius_when_single" },
    .{ .key = "monocle_no_border", .kind = .int_raw, .field = "monocle_no_border" },
    .{ .key = "monocle_no_gap", .kind = .int_raw, .field = "monocle_no_gap" },
    .{ .key = "snap_distance", .kind = .int_raw, .field = "snap_distance" },
    .{ .key = "enable_floating_snap", .kind = .int_raw, .field = "enable_floating_snap" },
    .{ .key = "float_full_to_top", .kind = .int_raw, .field = "float_full_to_top" },
    .{ .key = "drag_tile_to_tile", .kind = .int_raw, .field = "drag_tile_to_tile" },
    .{ .key = "drag_tile_small", .kind = .int_raw, .field = "drag_tile_small" },
    .{ .key = "swipe_min_threshold", .kind = .uint_raw, .field = "swipe_min_threshold" },
    .{ .key = "gesture_live", .kind = .int_raw, .field = "gesture_live" },
    .{ .key = "gesture_swipe_distance", .kind = .uint_raw, .field = "gesture_swipe_distance" },
    .{ .key = "gesture_swipe_cancel_ratio", .kind = .double_raw, .field = "gesture_swipe_cancel_ratio" },
    .{ .key = "gesture_swipe_min_speed_to_force", .kind = .double_raw, .field = "gesture_swipe_min_speed_to_force" },
    .{ .key = "xkb_rules_rules", .kind = .char128, .field = "xkb_rules_rules" },
    .{ .key = "xkb_rules_model", .kind = .char128, .field = "xkb_rules_model" },
    .{ .key = "xkb_rules_layout", .kind = .char128, .field = "xkb_rules_layout" },
    .{ .key = "xkb_rules_variant", .kind = .char128, .field = "xkb_rules_variant" },
    .{ .key = "xkb_rules_options", .kind = .char128, .field = "xkb_rules_options" },
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
        .char128 => {
            const dst = &@field(cfg, row.field); // *[128]u8
            _ = strncpy(dst, value, dst.len - 1);
            dst[dst.len - 1] = 0;
            return 1;
        },
    }
}

/// C entry point (tri-state: 1 applied, -1 invalid value, 0 not ours).
export fn acwm_config_apply_misc_option(
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
    return acwm_config_apply_misc_option(cfg, key, value, 23);
}

test "tri-state dispatch: misc key, adjacent-group keys, unknown" {
    var config: c.Config = std.mem.zeroes(c.Config);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "allow_tearing", "1"));
    // neighbors owned by other slices / not yet ported
    try testing.expectEqual(@as(c_int, 0), apply(&config, "blur", "1"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "focused_opacity", "0.9"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "scroller_proportion_preset", "1,2"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "allow_tearingx", "1"));
}

test "int fields store atoi verbatim" {
    var config: c.Config = std.mem.zeroes(c.Config);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "single_scratchpad", "1"));
    try testing.expectEqual(@as(i32, 1), config.single_scratchpad);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "xwayland_persistence", "-1"));
    try testing.expectEqual(@as(i32, -1), config.xwayland_persistence);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "tag_carousel", "2"));
    try testing.expectEqual(@as(i32, 2), config.tag_carousel);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "hdr_depth", "10"));
    try testing.expectEqual(@as(i32, 10), config.hdr_depth);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "disable_middle_paste", "1"));
    try testing.expectEqual(@as(i32, 1), config.disable_middle_paste);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "auto_reload_config", "1"));
    try testing.expectEqual(@as(i32, 1), config.auto_reload_config);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "no_border_when_single", "1"));
    try testing.expectEqual(@as(i32, 1), config.no_border_when_single);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "monocle_no_gap", "1"));
    try testing.expectEqual(@as(i32, 1), config.monocle_no_gap);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "snap_distance", "30"));
    try testing.expectEqual(@as(i32, 30), config.snap_distance);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "float_full_to_top", "1"));
    try testing.expectEqual(@as(i32, 1), config.float_full_to_top);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "gesture_live", "1"));
    try testing.expectEqual(@as(i32, 1), config.gesture_live);
}

test "rename mapping: sync_obj_enable writes syncobj_enable" {
    var config: c.Config = std.mem.zeroes(c.Config);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "sync_obj_enable", "1"));
    try testing.expectEqual(@as(i32, 1), config.syncobj_enable);
}

test "uint wrap and double precision" {
    var config: c.Config = std.mem.zeroes(c.Config);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "swipe_min_threshold", "50"));
    try testing.expectEqual(@as(u32, 50), config.swipe_min_threshold);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "gesture_swipe_distance", "-1"));
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), config.gesture_swipe_distance);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "gesture_swipe_cancel_ratio", "0.35"));
    try testing.expectEqual(@as(f64, 0.35), config.gesture_swipe_cancel_ratio);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "gesture_swipe_min_speed_to_force", "0.1"));
    try testing.expectEqual(@as(f64, 0.1), config.gesture_swipe_min_speed_to_force);
}

test "xkb rule strings truncate to 127 chars with a forced NUL" {
    var config: c.Config = std.mem.zeroes(c.Config);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "xkb_rules_layout", "us,de,fr"));
    try testing.expectEqualStrings("us,de,fr", std.mem.sliceTo(&config.xkb_rules_layout, 0));

    // a 200-char value is clamped to 127 chars
    var long_buf: [201]u8 = undefined;
    @memset(&long_buf, 'a');
    long_buf[200] = 0;
    try testing.expectEqual(@as(c_int, 1), apply(&config, "xkb_rules_options", @ptrCast(&long_buf)));

    const stored = std.mem.sliceTo(&config.xkb_rules_options, 0);
    try testing.expectEqual(@as(usize, 127), stored.len);
    try testing.expectEqual(@as(u8, 'a'), stored[126]);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "xkb_rules_model", "pc105"));
    try testing.expectEqualStrings("pc105", std.mem.sliceTo(&config.xkb_rules_model, 0));
}

test "every table row dispatches through the C entry" {
    var config: c.Config = std.mem.zeroes(c.Config);

    for (rows) |row| {
        const r = acwm_config_apply_misc_option(&config, row.key, "5", 0);
        if (r != 1) {
            std.debug.print("row failed to dispatch: {s}\n", .{row.key});
            return error.RowFailedToDispatch;
        }
    }
    try testing.expectEqual(@as(usize, 30), rows.len);
}
