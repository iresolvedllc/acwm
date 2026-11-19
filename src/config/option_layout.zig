//! Port of the layout option group from src/config/option_defs.c
//! (strangler-fig Phase 4, slice 3).
//!
//! Exports one C symbol: acwm_config_apply_layout_option(), called by
//! parse_option() ahead of its strcmp chain (guarded by
//! ACWM_ZIG_LAYOUT_OPTION, defined only in the Zig build). Covers the
//! contiguous chain block new_is_master..overcircle_center_ratio — master
//! defaults, tag count/gather, dwindle tuning, hotarea, overview gaps and
//! the overcircle ratio (22 keys). Cursor/gesture keys after it and
//! jump_labels before it belong to other slices.
//!
//! C parity: no clamps at parse time (post-parse clamping lives in
//! override_config) — atoi/atof st() verbatim. new_is_master and
//! default_nmaster are uint32_t fields assigned from atoi: negatives wrap
//! via @bitCast. Floats narrow double->float via @floatCast like the C
//! assignment.
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
    /// atof -> float Config field (double->float narrowing like C).
    float_raw,
};

const Row = struct {
    key: [:0]const u8,
    kind: Kind,
    field: [:0]const u8,
};

/// The 22 keys of the new_is_master..overcircle_center_ratio block, in C order.
const rows = [_]Row{
    .{ .key = "new_is_master", .kind = .uint_raw, .field = "new_is_master" },
    .{ .key = "default_master_factor", .kind = .float_raw, .field = "default_mfact" },
    .{ .key = "default_master_count", .kind = .uint_raw, .field = "default_nmaster" },
    .{ .key = "tag_num", .kind = .int_raw, .field = "tag_num" },
    .{ .key = "tag_gather", .kind = .int_raw, .field = "tag_gather" },
    .{ .key = "center_master_overspread", .kind = .int_raw, .field = "center_master_overspread" },
    .{ .key = "center_when_single_stack", .kind = .int_raw, .field = "center_when_single_stack" },
    .{ .key = "dwindle_vertical_split", .kind = .int_raw, .field = "dwindle_vsplit" },
    .{ .key = "dwindle_horizontal_split", .kind = .int_raw, .field = "dwindle_hsplit" },
    .{ .key = "dwindle_preserve_split", .kind = .int_raw, .field = "dwindle_preserve_split" },
    .{ .key = "dwindle_smart_split", .kind = .int_raw, .field = "dwindle_smart_split" },
    .{ .key = "dwindle_smart_resize", .kind = .int_raw, .field = "dwindle_smart_resize" },
    .{ .key = "dwindle_drop_simple_split", .kind = .int_raw, .field = "dwindle_drop_simple_split" },
    .{ .key = "dwindle_manual_split", .kind = .int_raw, .field = "dwindle_manual_split" },
    .{ .key = "dwindle_split_ratio", .kind = .float_raw, .field = "dwindle_split_ratio" },
    .{ .key = "hotarea_size", .kind = .int_raw, .field = "hotarea_size" },
    .{ .key = "hotarea_corner", .kind = .int_raw, .field = "hotarea_corner" },
    .{ .key = "enable_hotarea", .kind = .int_raw, .field = "enable_hotarea" },
    .{ .key = "hotarea_disable_on_fullscreen", .kind = .int_raw, .field = "hotarea_disable_on_fullscreen" },
    .{ .key = "overview_gap_inner", .kind = .int_raw, .field = "overviewgappi" },
    .{ .key = "overview_gap_outer", .kind = .int_raw, .field = "overviewgappo" },
    .{ .key = "overcircle_center_ratio", .kind = .float_raw, .field = "overcircle_center_ratio" },
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
        .float_raw => {
            @field(cfg, row.field) = @floatCast(atof(value));
            return 1;
        },
    }
}

/// C entry point (tri-state: 1 applied, -1 invalid value, 0 not ours).
export fn acwm_config_apply_layout_option(
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
    return acwm_config_apply_layout_option(cfg, key, value, 5);
}

test "tri-state dispatch: layout key, neighbor-slice keys, unknown" {
    var config: c.Config = std.mem.zeroes(c.Config);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "tag_num", "9"));
    // string option before this block — next slice
    try testing.expectEqual(@as(c_int, 0), apply(&config, "jump_labels", "abc"));
    // cursor key after this block — input slice
    try testing.expectEqual(@as(c_int, 0), apply(&config, "cursor_hide_timeout", "100"));
    // earlier slices
    try testing.expectEqual(@as(c_int, 0), apply(&config, "bar_enable", "1"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "idle_after", "60"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "tag_numx", "1"));
}

test "int fields store atoi verbatim, negatives included" {
    var config: c.Config = std.mem.zeroes(c.Config);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "tag_num", "5"));
    try testing.expectEqual(@as(i32, 5), config.tag_num);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "tag_gather", "-1"));
    try testing.expectEqual(@as(i32, -1), config.tag_gather);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "center_master_overspread", "2"));
    try testing.expectEqual(@as(i32, 2), config.center_master_overspread);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "dwindle_smart_resize", "1"));
    try testing.expectEqual(@as(i32, 1), config.dwindle_smart_resize);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "enable_hotarea", "3"));
    try testing.expectEqual(@as(i32, 3), config.enable_hotarea);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "overview_gap_inner", "40"));
    try testing.expectEqual(@as(i32, 40), config.overviewgappi);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "overview_gap_outer", "50"));
    try testing.expectEqual(@as(i32, 50), config.overviewgappo);
}

test "uint fields wrap negatives like the C implicit conversion" {
    var config: c.Config = std.mem.zeroes(c.Config);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "new_is_master", "1"));
    try testing.expectEqual(@as(u32, 1), config.new_is_master);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "new_is_master", "-1"));
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), config.new_is_master);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "default_master_count", "4"));
    try testing.expectEqual(@as(u32, 4), config.default_nmaster);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "default_master_count", "-2"));
    try testing.expectEqual(@as(u32, 0xFFFFFFFE), config.default_nmaster);
}

test "float fields narrow double to float like C assignment" {
    var config: c.Config = std.mem.zeroes(c.Config);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "default_master_factor", "0.618"));
    try testing.expectEqual(@as(f32, 0.618), config.default_mfact);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "dwindle_split_ratio", "0.5"));
    try testing.expectEqual(@as(f32, 0.5), config.dwindle_split_ratio);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "overcircle_center_ratio", "-1.5"));
    try testing.expectEqual(@as(f32, -1.5), config.overcircle_center_ratio);

    // atof tolerance: garbage parses as 0.0, like C
    try testing.expectEqual(@as(c_int, 1), apply(&config, "default_master_factor", "bogus"));
    try testing.expectEqual(@as(f32, 0.0), config.default_mfact);
}

test "every table row dispatches through the C entry" {
    var config: c.Config = std.mem.zeroes(c.Config);

    for (rows) |row| {
        const r = acwm_config_apply_layout_option(&config, row.key, "5", 0);
        if (r != 1) {
            std.debug.print("row failed to dispatch: {s}\n", .{row.key});
            return error.RowFailedToDispatch;
        }
    }
    try testing.expectEqual(@as(usize, 22), rows.len);
}
