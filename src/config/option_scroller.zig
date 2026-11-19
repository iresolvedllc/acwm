//! Port of the scroller/focus option group from src/config/option_defs.c
//! (strangler-fig Phase 4, slice 8).
//!
//! Exports one C symbol: acwm_config_apply_scroller_option(), called by
//! parse_option() ahead of its strcmp chain (guarded by
//! ACWM_ZIG_SCROLLER_OPTION, defined only in the Zig build). Covers the
//! contiguous scroller_structs..view_current_to_back block: scroller
//! struct/proportion settings, edge-scroller focus, and the cross-monitor/
//! cross-tag focus policy switches (15 keys).
//!
//! C parity: proportion fields are float (atof narrows), but
//! edge_scroller_focus_allow_speed is a double (no narrowing);
//! focus_direction_only_zone_overlap maps to the differently named
//! focusdir_only_zone_overlap field.
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
    /// atoi -> int32_t Config field.
    int_raw,
    /// atof -> float Config field (double->float narrowing like C).
    float_raw,
    /// atof -> double Config field (no narrowing).
    double_raw,
};

const Row = struct {
    key: [:0]const u8,
    kind: Kind,
    field: [:0]const u8,
};

/// The 15 keys, in C chain order.
const rows = [_]Row{
    .{ .key = "scroller_structs", .kind = .int_raw, .field = "scroller_structs" },
    .{ .key = "scroller_default_proportion", .kind = .float_raw, .field = "scroller_default_proportion" },
    .{ .key = "scroller_default_proportion_single", .kind = .float_raw, .field = "scroller_default_proportion_single" },
    .{ .key = "scroller_ignore_proportion_single", .kind = .int_raw, .field = "scroller_ignore_proportion_single" },
    .{ .key = "scroller_focus_center", .kind = .int_raw, .field = "scroller_focus_center" },
    .{ .key = "scroller_prefer_center", .kind = .int_raw, .field = "scroller_prefer_center" },
    .{ .key = "scroller_prefer_overspread", .kind = .int_raw, .field = "scroller_prefer_overspread" },
    .{ .key = "edge_scroller_pointer_focus", .kind = .int_raw, .field = "edge_scroller_pointer_focus" },
    .{ .key = "edge_scroller_focus_allow_speed", .kind = .double_raw, .field = "edge_scroller_focus_allow_speed" },
    .{ .key = "focus_cross_monitor", .kind = .int_raw, .field = "focus_cross_monitor" },
    .{ .key = "focus_direction_only_zone_overlap", .kind = .int_raw, .field = "focusdir_only_zone_overlap" },
    .{ .key = "exchange_cross_monitor", .kind = .int_raw, .field = "exchange_cross_monitor" },
    .{ .key = "scratchpad_cross_monitor", .kind = .int_raw, .field = "scratchpad_cross_monitor" },
    .{ .key = "focus_cross_tag", .kind = .int_raw, .field = "focus_cross_tag" },
    .{ .key = "view_current_to_back", .kind = .int_raw, .field = "view_current_to_back" },
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
        .float_raw => {
            @field(cfg, row.field) = @floatCast(atof(value));
            return 1;
        },
        .double_raw => {
            @field(cfg, row.field) = atof(value);
            return 1;
        },
    }
}

/// C entry point (tri-state: 1 applied, -1 invalid value, 0 not ours).
export fn acwm_config_apply_scroller_option(
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
    return acwm_config_apply_scroller_option(cfg, key, value, 19);
}

test "tri-state dispatch: scroller key, adjacent-group keys, unknown" {
    var config: c.Config = std.mem.zeroes(c.Config);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "scroller_structs", "3"));
    // animation block precedes, blur block follows, single_scratchpad
    // follows the visuals block
    try testing.expectEqual(@as(c_int, 0), apply(&config, "animations", "1"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "blur", "1"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "single_scratchpad", "1"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "scroller_structsx", "1"));
}

test "int fields store atoi verbatim" {
    var config: c.Config = std.mem.zeroes(c.Config);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "scroller_structs", "5"));
    try testing.expectEqual(@as(i32, 5), config.scroller_structs);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "scroller_ignore_proportion_single", "1"));
    try testing.expectEqual(@as(i32, 1), config.scroller_ignore_proportion_single);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "scroller_focus_center", "-1"));
    try testing.expectEqual(@as(i32, -1), config.scroller_focus_center);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "scroller_prefer_center", "1"));
    try testing.expectEqual(@as(i32, 1), config.scroller_prefer_center);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "scroller_prefer_overspread", "1"));
    try testing.expectEqual(@as(i32, 1), config.scroller_prefer_overspread);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "edge_scroller_pointer_focus", "2"));
    try testing.expectEqual(@as(i32, 2), config.edge_scroller_pointer_focus);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "focus_cross_monitor", "1"));
    try testing.expectEqual(@as(i32, 1), config.focus_cross_monitor);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "exchange_cross_monitor", "1"));
    try testing.expectEqual(@as(i32, 1), config.exchange_cross_monitor);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "scratchpad_cross_monitor", "1"));
    try testing.expectEqual(@as(i32, 1), config.scratchpad_cross_monitor);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "focus_cross_tag", "1"));
    try testing.expectEqual(@as(i32, 1), config.focus_cross_tag);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "view_current_to_back", "1"));
    try testing.expectEqual(@as(i32, 1), config.view_current_to_back);
}

test "renamed field mapping: focus_direction_only_zone_overlap" {
    var config: c.Config = std.mem.zeroes(c.Config);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "focus_direction_only_zone_overlap", "1"));
    try testing.expectEqual(@as(i32, 1), config.focusdir_only_zone_overlap);
}

test "float vs double precision follows the C field types" {
    var config: c.Config = std.mem.zeroes(c.Config);

    // proportions are float fields
    try testing.expectEqual(@as(c_int, 1), apply(&config, "scroller_default_proportion", "0.6"));
    try testing.expectEqual(@as(f32, 0.6), config.scroller_default_proportion);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "scroller_default_proportion_single", "0.9"));
    try testing.expectEqual(@as(f32, 0.9), config.scroller_default_proportion_single);

    // edge focus speed is a double field — no narrowing
    try testing.expectEqual(@as(c_int, 1), apply(&config, "edge_scroller_focus_allow_speed", "0.1"));
    try testing.expectEqual(@as(f64, 0.1), config.edge_scroller_focus_allow_speed);
}

test "every table row dispatches through the C entry" {
    var config: c.Config = std.mem.zeroes(c.Config);

    for (rows) |row| {
        const r = acwm_config_apply_scroller_option(&config, row.key, "5", 0);
        if (r != 1) {
            std.debug.print("row failed to dispatch: {s}\n", .{row.key});
            return error.RowFailedToDispatch;
        }
    }
    try testing.expectEqual(@as(usize, 15), rows.len);
}
