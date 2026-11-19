//! Port of the gaps/scratchpad option group from src/config/option_defs.c
//! (strangler-fig Phase 4, slice 11).
//!
//! Exports one C symbol: acwm_config_apply_gaps_option(), called by
//! parse_option() ahead of its strcmp chain (guarded by
//! ACWM_ZIG_GAPS_OPTION, defined only in the Zig build). Covers the
//! gap_inner_horizontal..border_px block: inner/outer gaps, scratchpad
//! proportions, the special-tag gap set and the border width (12 keys).
//!
//! C parity: every gap and border_px is a uint32_t field assigned from
//! atoi — negatives wrap via @bitCast; scratchpad_width/height_ratio and
//! special_dim are float fields (atof narrows).
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

/// The 12 keys, in C chain order.
const rows = [_]Row{
    .{ .key = "gap_inner_horizontal", .kind = .uint_raw, .field = "gappih" },
    .{ .key = "gap_inner_vertical", .kind = .uint_raw, .field = "gappiv" },
    .{ .key = "gap_outer_horizontal", .kind = .uint_raw, .field = "gappoh" },
    .{ .key = "gap_outer_vertical", .kind = .uint_raw, .field = "gappov" },
    .{ .key = "scratchpad_width_ratio", .kind = .float_raw, .field = "scratchpad_width_ratio" },
    .{ .key = "scratchpad_height_ratio", .kind = .float_raw, .field = "scratchpad_height_ratio" },
    .{ .key = "special_dim", .kind = .float_raw, .field = "special_dim" },
    .{ .key = "special_gap_inner_horizontal", .kind = .uint_raw, .field = "special_gappih" },
    .{ .key = "special_gap_inner_vertical", .kind = .uint_raw, .field = "special_gappiv" },
    .{ .key = "special_gap_outer_horizontal", .kind = .uint_raw, .field = "special_gappoh" },
    .{ .key = "special_gap_outer_vertical", .kind = .uint_raw, .field = "special_gappov" },
    .{ .key = "border_px", .kind = .uint_raw, .field = "borderpx" },
};

// ---------------------------------------------------------------------------
// apply helpers
// ---------------------------------------------------------------------------

fn applyRow(cfg: *c.Config, comptime row: Row, value: [*:0]const u8) c_int {
    switch (comptime row.kind) {
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
export fn acwm_config_apply_gaps_option(
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
    return acwm_config_apply_gaps_option(cfg, key, value, 31);
}

test "tri-state dispatch: gaps key, adjacent-group keys, unknown" {
    var config: c.Config = std.mem.zeroes(c.Config);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "border_px", "2"));
    // bar geometry (bar slice) and scratchpad policy (misc slice) must not match
    try testing.expectEqual(@as(c_int, 0), apply(&config, "bar_height", "30"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "group_bar_height", "20"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "single_scratchpad", "1"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "border_pxx", "2"));
}

test "gaps store atoi with uint wrap" {
    var config: c.Config = std.mem.zeroes(c.Config);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "gap_inner_horizontal", "5"));
    try testing.expectEqual(@as(u32, 5), config.gappih);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "gap_inner_vertical", "-1"));
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), config.gappiv);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "gap_outer_horizontal", "10"));
    try testing.expectEqual(@as(u32, 10), config.gappoh);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "gap_outer_vertical", "0"));
    try testing.expectEqual(@as(u32, 0), config.gappov);
}

test "special gaps and border width" {
    var config: c.Config = std.mem.zeroes(c.Config);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "special_gap_inner_horizontal", "3"));
    try testing.expectEqual(@as(u32, 3), config.special_gappih);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "special_gap_inner_vertical", "4"));
    try testing.expectEqual(@as(u32, 4), config.special_gappiv);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "special_gap_outer_horizontal", "6"));
    try testing.expectEqual(@as(u32, 6), config.special_gappoh);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "special_gap_outer_vertical", "7"));
    try testing.expectEqual(@as(u32, 7), config.special_gappov);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "special_gap_outer_vertical", "-2"));
    try testing.expectEqual(@as(u32, 0xFFFFFFFE), config.special_gappov);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "border_px", "4"));
    try testing.expectEqual(@as(u32, 4), config.borderpx);
}

test "scratchpad ratios and special_dim are floats" {
    var config: c.Config = std.mem.zeroes(c.Config);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "scratchpad_width_ratio", "0.8"));
    try testing.expectEqual(@as(f32, 0.8), config.scratchpad_width_ratio);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "scratchpad_height_ratio", "0.9"));
    try testing.expectEqual(@as(f32, 0.9), config.scratchpad_height_ratio);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "special_dim", "0.6"));
    try testing.expectEqual(@as(f32, 0.6), config.special_dim);
}

test "every table row dispatches through the C entry" {
    var config: c.Config = std.mem.zeroes(c.Config);

    for (rows) |row| {
        const r = acwm_config_apply_gaps_option(&config, row.key, "5", 0);
        if (r != 1) {
            std.debug.print("row failed to dispatch: {s}\n", .{row.key});
            return error.RowFailedToDispatch;
        }
    }
    try testing.expectEqual(@as(usize, 12), rows.len);
}
