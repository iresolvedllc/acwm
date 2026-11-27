//! Port of the jump-label decoration option group from
//! src/config/option_defs.c (strangler-fig Phase 4, slice 10).
//!
//! Exports one C symbol: acwm_config_apply_jumplabel_option(), called by
//! parse_option() ahead of its strcmp chain (guarded by
//! ACWM_ZIG_JUMLABEL_OPTION, defined only in the Zig build). Covers the
//! ten jump_label_decorate_* keys: the font description string, five RGBA
//! members and four 0..100 clamped ints, all writing config->jumplabeldata
//! (the DecorateDrawData shared with the bar decorations).
//!
//! Error messages use the full key names (no legacy aliases here), with the
//! C-identical ANSI format and uint32 truncation of parse_color output.
//!
//! Tests live at the bottom and reuse tests/option_bar_stub.c.

const std = @import("std");
const c = @import("cc");

const WLR_ERROR: c_uint = 1;

extern fn acwm_error_impl(log: bool, verbosity: c_uint, file: [*:0]const u8, line: c_int, fmt: [*:0]const u8, ...) callconv(.c) void;
extern fn parse_color(hex_str: [*:0]const u8) callconv(.c) i64;
extern fn convert_hex_to_rgba(color: [*]f32, hex: u32) callconv(.c) void;

extern "c" fn atoi(nptr: [*:0]const u8) c_int;
extern "c" fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern "c" fn free(ptr: ?*anyopaque) void;

// ---------------------------------------------------------------------------
// option table
// ---------------------------------------------------------------------------

const Kind = enum {
    /// strdup over jumplabeldata.font_desc (const char *).
    deco_string,
    /// parse_color + convert_hex_to_rgba over a jumplabeldata float[4].
    deco_color4,
    /// CLAMP_INT(atoi, 0, 100) -> int32_t jumplabeldata member.
    deco_int_clamp,
};

const Row = struct {
    key: [:0]const u8,
    kind: Kind,
    field: [:0]const u8,
};

/// The 10 keys, in C chain order.
const rows = [_]Row{
    .{ .key = "jump_label_decorate_font_desc", .kind = .deco_string, .field = "font_desc" },
    .{ .key = "jump_label_decorate_fg_color", .kind = .deco_color4, .field = "fg_color" },
    .{ .key = "jump_label_decorate_bg_color", .kind = .deco_color4, .field = "bg_color" },
    .{ .key = "jump_label_decorate_focus_fg_color", .kind = .deco_color4, .field = "focus_fg_color" },
    .{ .key = "jump_label_decorate_focus_bg_color", .kind = .deco_color4, .field = "focus_bg_color" },
    .{ .key = "jump_label_decorate_border_color", .kind = .deco_color4, .field = "border_color" },
    .{ .key = "jump_label_decorate_border_width", .kind = .deco_int_clamp, .field = "border_width" },
    .{ .key = "jump_label_decorate_corner_radius", .kind = .deco_int_clamp, .field = "corner_radius" },
    .{ .key = "jump_label_decorate_padding_x", .kind = .deco_int_clamp, .field = "padding_x" },
    .{ .key = "jump_label_decorate_padding_y", .kind = .deco_int_clamp, .field = "padding_y" },
};

// ---------------------------------------------------------------------------
// apply helpers
// ---------------------------------------------------------------------------

fn Target(comptime row: Row) type {
    return *@TypeOf(@field(@as(c.DecorateDrawData, undefined), row.field));
}

fn target(cfg: *c.Config, comptime row: Row) Target(row) {
    const d = &cfg.jumplabeldata;
    return &@field(d, row.field);
}

fn clampInt(x: i32, comptime min: i32, comptime max: i32) i32 {
    return if (x < min) min else if (x > max) max else x;
}

fn setStringSlot(slot: anytype, value: [*:0]const u8) void {
    if (slot.* != null)
        free(@ptrCast(@constCast(slot.*)));
    slot.* = strdup(value);
}

fn invalidColor(comptime key: [:0]const u8, value: [*:0]const u8) void {
    const fmt = "Invalid " ++ key ++ " format: \x1b[1m\x1b[31m%s\x1b[0m\n";
    acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, fmt.ptr, value);
}

fn applyColor(dst: *[4]f32, comptime key: [:0]const u8, value: [*:0]const u8) c_int {
    const color = parse_color(value);
    if (color == -1) {
        invalidColor(key, value);
        return -1;
    }
    convert_hex_to_rgba(dst, @truncate(@as(u64, @bitCast(color))));
    return 1;
}

fn applyRow(cfg: *c.Config, comptime row: Row, value: [*:0]const u8) c_int {
    switch (comptime row.kind) {
        .deco_string => {
            setStringSlot(target(cfg, row), value);
            return 1;
        },
        .deco_color4 => {
            return applyColor(target(cfg, row), row.key, value);
        },
        .deco_int_clamp => {
            target(cfg, row).* = clampInt(atoi(value), 0, 100);
            return 1;
        },
    }
}

/// C entry point (tri-state: 1 applied, -1 invalid value, 0 not ours).
export fn acwm_config_apply_jumplabel_option(
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
// tests (stub-backed via tests/option_bar_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_parse_color: i64;
extern var stub_converted_hex: u32;
extern var stub_convert_calls: c_int;
extern var stub_last_error: [512]u8;
extern var stub_error_count: c_int;

fn resetStub() void {
    stub_parse_color = 0x11223344;
    stub_converted_hex = 0;
    stub_convert_calls = 0;
    stub_error_count = 0;
    stub_last_error[0] = 0;
}

fn apply(cfg: *c.Config, key: [:0]const u8, value: [:0]const u8) c_int {
    return acwm_config_apply_jumplabel_option(cfg, key, value, 29);
}

test "tri-state dispatch: jumplabel key, bar deco key, unknown" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "jump_label_decorate_border_width", "4"));
    // the bar decorations belong to the bar slice
    try testing.expectEqual(@as(c_int, 0), apply(&config, "bar_decorate_border_width", "4"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "tab_bar_decorate_border_width", "4"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "jump_label_decorate_border_widthx", "4"));
}

test "clamped ints: 0..100 in the int32 domain" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "jump_label_decorate_border_width", "-3"));
    try testing.expectEqual(@as(i32, 0), config.jumplabeldata.border_width);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "jump_label_decorate_border_width", "150"));
    try testing.expectEqual(@as(i32, 100), config.jumplabeldata.border_width);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "jump_label_decorate_corner_radius", "12"));
    try testing.expectEqual(@as(i32, 12), config.jumplabeldata.corner_radius);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "jump_label_decorate_padding_x", "200"));
    try testing.expectEqual(@as(i32, 100), config.jumplabeldata.padding_x);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "jump_label_decorate_padding_y", "4"));
    try testing.expectEqual(@as(i32, 4), config.jumplabeldata.padding_y);
}

test "font description frees the old value" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "jump_label_decorate_font_desc", "Fira 12"));
    try testing.expectEqualStrings(
        "Fira 12",
        std.mem.span(@as([*:0]const u8, @ptrCast(config.jumplabeldata.font_desc))),
    );
    try testing.expectEqual(@as(c_int, 1), apply(&config, "jump_label_decorate_font_desc", "Sans 10"));
    try testing.expectEqualStrings(
        "Sans 10",
        std.mem.span(@as([*:0]const u8, @ptrCast(config.jumplabeldata.font_desc))),
    );
}

test "colors and the invalid-color path" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    stub_parse_color = 0x0A0B0C0D;
    try testing.expectEqual(@as(c_int, 1), apply(&config, "jump_label_decorate_fg_color", "#0A0B0C0D"));
    try testing.expectEqual(@as(u32, 0x0A0B0C0D), stub_converted_hex);
    try testing.expectEqualSlices(f32, &.{ 0.25, 0.5, 0.75, 1.0 }, &config.jumplabeldata.fg_color);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "jump_label_decorate_focus_bg_color", "#010203"));
    try testing.expectEqualSlices(f32, &.{ 0.25, 0.5, 0.75, 1.0 }, &config.jumplabeldata.focus_bg_color);

    stub_parse_color = -1;
    try testing.expectEqual(@as(c_int, -1), apply(&config, "jump_label_decorate_border_color", "zz"));
    try testing.expectEqual(@as(c_int, 1), stub_error_count);
    try testing.expect(std.mem.startsWith(
        u8,
        std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&stub_last_error)), 0),
        "Invalid jump_label_decorate_border_color format: \x1b[1m\x1b[31m",
    ));
}

test "every table row dispatches through the C entry" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    for (rows) |row| {
        const r = acwm_config_apply_jumplabel_option(&config, row.key, "5", 0);
        if (r != 1) {
            std.debug.print("row failed to dispatch: {s}\n", .{row.key});
            return error.RowFailedToDispatch;
        }
    }
    try testing.expectEqual(@as(usize, 10), rows.len);
}
