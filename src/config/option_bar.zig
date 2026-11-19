//! Port of the bar option group from src/config/option_defs.c
//! (strangler-fig Phase 4, slice 1).
//!
//! Exports one C symbol: acwm_config_apply_bar_option(), which parse_option()
//! calls before its strcmp chain (guarded by ACWM_ZIG_BAR_OPTION, defined
//! only in the Zig build). The 45 keys of the bar family route through the
//! comptime row table below — table rows are unrolled at comptime, so the
//! generated code is a plain strcmp chain, same as the C twin.
//!
//! Return contract (tri-state, because parse_option() uses false for both
//! "unknown key" and "invalid value"):
//!   1  key belongs to the bar group and was applied
//!  -1  key belongs to the bar group but had an invalid value (error logged)
//!   0  key is not a bar-group option — caller continues its own chain
//!
//! The C twin's branches stay in option_defs.c (the meson/nix build still
//! compiles them; this build routes bar keys here first).
//!
//! Tests live at the bottom and need the stub in tests/option_bar_stub.c,
//! which stands in for parse_color()/convert_hex_to_rgba() (real ones are
//! tested by the value_parse port) and the variadic logging functions.

const std = @import("std");
const c = @import("cc");

const WLR_ERROR: c_uint = 1;

extern fn acwm_error_impl(
    log: bool,
    verbosity: c_uint,
    file: [*:0]const u8,
    line: c_int,
    fmt: [*:0]const u8,
    ...) callconv(.c) void;
extern fn acwm_error_untagged(verbosity: c_uint, fmt: [*:0]const u8, ...) callconv(.c) void;

// From the value_parse twin (src/config/value_parse.zig) in the compositor
// link; from tests/option_bar_stub.c in the test link.
extern fn parse_color(hex_str: [*:0]const u8) callconv(.c) i64;
extern fn convert_hex_to_rgba(color: [*]f32, hex: u32) callconv(.c) void;

extern "c" fn atoi(nptr: [*:0]const u8) c_int;
extern "c" fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern "c" fn free(ptr: ?*anyopaque) void;

// ---------------------------------------------------------------------------
// option table
// ---------------------------------------------------------------------------

/// How a key's value is applied to its destination field.
const Kind = enum {
    /// atoi -> int32_t Config field, no clamp (C parity: raw store).
    int_raw,
    /// atoi -> uint32_t Config field, no clamp. Negative atoi wraps like the
    /// C implicit int->uint conversion; replicated with @bitCast.
    uint_raw,
    /// CLAMP_INT(atoi, min, max) -> uint32_t Config field.
    uint_clamp,
    /// strdup over a Config char * (frees the old value first).
    string,
    /// parse_color + convert_hex_to_rgba over a Config float[4].
    color4,
    /// CLAMP_INT(atoi, min, max) -> int32_t DecorateDrawData member.
    deco_int_clamp,
    /// strdup over a DecorateDrawData const char * member.
    deco_string,
    /// parse_color + convert_hex_to_rgba over a DecorateDrawData float[4].
    deco_color4,
};

const Row = struct {
    key: [:0]const u8,
    kind: Kind,
    /// Config field name (all non-deco kinds).
    field: [:0]const u8,
    /// DecorateDrawData member of Config (bardata/groupbardata/tabbardata);
    /// required for the deco_* kinds.
    deco: ?[:0]const u8 = null,
    /// CLAMP_INT bounds for the *_clamp kinds.
    min: i32 = 0,
    max: i32 = 0,
};

/// All 45 bar-family keys of option_defs.c, verified against the C chain
/// (grep diff, 1:1). Grouped like the C file: main bar, group/tab geometry,
/// then the three decoration sets.
const rows = [_]Row{
    // --- main bar ---
    .{ .key = "bar_enable", .kind = .int_raw, .field = "bar_enable" },
    .{ .key = "bar_height", .kind = .uint_clamp, .field = "bar_height", .min = 8, .max = 300 },
    .{ .key = "bar_top_gap", .kind = .uint_clamp, .field = "bar_top_gap", .min = 0, .max = 200 },
    .{ .key = "bar_lr_gap", .kind = .uint_clamp, .field = "bar_lr_gap", .min = 0, .max = 200 },
    .{ .key = "bar_corner_radius", .kind = .uint_clamp, .field = "bar_corner_radius", .min = 0, .max = 200 },
    .{ .key = "bar_battery_interval", .kind = .uint_clamp, .field = "bar_battery_interval", .min = 1000, .max = 3600000 },
    .{ .key = "bar_tray_icon_size", .kind = .uint_clamp, .field = "bar_tray_icon_size", .min = 8, .max = 96 },
    .{ .key = "bar_clock_format", .kind = .string, .field = "bar_clock_format" },
    .{ .key = "bar_background_color", .kind = .color4, .field = "bar_bg_color" },
    // --- main bar decoration (bardata) ---
    .{ .key = "bar_decorate_font_desc", .kind = .deco_string, .field = "font_desc", .deco = "bardata" },
    .{ .key = "bar_decorate_fg_color", .kind = .deco_color4, .field = "fg_color", .deco = "bardata" },
    .{ .key = "bar_decorate_focus_fg_color", .kind = .deco_color4, .field = "focus_fg_color", .deco = "bardata" },
    .{ .key = "bar_decorate_focus_bg_color", .kind = .deco_color4, .field = "focus_bg_color", .deco = "bardata" },
    .{ .key = "bar_decorate_border_color", .kind = .deco_color4, .field = "border_color", .deco = "bardata" },
    .{ .key = "bar_decorate_border_width", .kind = .deco_int_clamp, .field = "border_width", .deco = "bardata", .min = 0, .max = 100 },
    .{ .key = "bar_decorate_corner_radius", .kind = .deco_int_clamp, .field = "corner_radius", .deco = "bardata", .min = 0, .max = 100 },
    .{ .key = "bar_decorate_padding_x", .kind = .deco_int_clamp, .field = "padding_x", .deco = "bardata", .min = 0, .max = 100 },
    .{ .key = "bar_decorate_padding_y", .kind = .deco_int_clamp, .field = "padding_y", .deco = "bardata", .min = 0, .max = 100 },
    // --- group / tab bar geometry (deliberately unclamped in C — keep) ---
    .{ .key = "group_bar_height", .kind = .uint_raw, .field = "group_bar_height" },
    .{ .key = "tab_bar_height", .kind = .uint_raw, .field = "tab_bar_height" },
    .{ .key = "always_show_group_bar", .kind = .int_raw, .field = "always_show_group_bar" },
    .{ .key = "group_bar_close_button_enable", .kind = .int_raw, .field = "group_bar_close_button_enable" },
    .{ .key = "group_bar_button_size", .kind = .uint_raw, .field = "group_bar_button_size" },
    .{ .key = "group_bar_button_margin", .kind = .uint_raw, .field = "group_bar_button_margin" },
    .{ .key = "group_bar_button_color", .kind = .color4, .field = "group_bar_button_color" },
    // --- group bar decoration (groupbardata) ---
    .{ .key = "group_bar_decorate_font_desc", .kind = .deco_string, .field = "font_desc", .deco = "groupbardata" },
    .{ .key = "group_bar_decorate_fg_color", .kind = .deco_color4, .field = "fg_color", .deco = "groupbardata" },
    .{ .key = "group_bar_decorate_bg_color", .kind = .deco_color4, .field = "bg_color", .deco = "groupbardata" },
    .{ .key = "group_bar_decorate_focus_fg_color", .kind = .deco_color4, .field = "focus_fg_color", .deco = "groupbardata" },
    .{ .key = "group_bar_decorate_focus_bg_color", .kind = .deco_color4, .field = "focus_bg_color", .deco = "groupbardata" },
    .{ .key = "group_bar_decorate_border_color", .kind = .deco_color4, .field = "border_color", .deco = "groupbardata" },
    .{ .key = "group_bar_decorate_border_width", .kind = .deco_int_clamp, .field = "border_width", .deco = "groupbardata", .min = 0, .max = 100 },
    .{ .key = "group_bar_decorate_corner_radius", .kind = .deco_int_clamp, .field = "corner_radius", .deco = "groupbardata", .min = 0, .max = 100 },
    .{ .key = "group_bar_decorate_padding_x", .kind = .deco_int_clamp, .field = "padding_x", .deco = "groupbardata", .min = 0, .max = 100 },
    .{ .key = "group_bar_decorate_padding_y", .kind = .deco_int_clamp, .field = "padding_y", .deco = "groupbardata", .min = 0, .max = 100 },
    // --- tab bar decoration (tabbardata) ---
    .{ .key = "tab_bar_decorate_font_desc", .kind = .deco_string, .field = "font_desc", .deco = "tabbardata" },
    .{ .key = "tab_bar_decorate_fg_color", .kind = .deco_color4, .field = "fg_color", .deco = "tabbardata" },
    .{ .key = "tab_bar_decorate_bg_color", .kind = .deco_color4, .field = "bg_color", .deco = "tabbardata" },
    .{ .key = "tab_bar_decorate_focus_fg_color", .kind = .deco_color4, .field = "focus_fg_color", .deco = "tabbardata" },
    .{ .key = "tab_bar_decorate_focus_bg_color", .kind = .deco_color4, .field = "focus_bg_color", .deco = "tabbardata" },
    .{ .key = "tab_bar_decorate_border_color", .kind = .deco_color4, .field = "border_color", .deco = "tabbardata" },
    .{ .key = "tab_bar_decorate_border_width", .kind = .deco_int_clamp, .field = "border_width", .deco = "tabbardata", .min = 0, .max = 100 },
    .{ .key = "tab_bar_decorate_corner_radius", .kind = .deco_int_clamp, .field = "corner_radius", .deco = "tabbardata", .min = 0, .max = 100 },
    .{ .key = "tab_bar_decorate_padding_x", .kind = .deco_int_clamp, .field = "padding_x", .deco = "tabbardata", .min = 0, .max = 100 },
    .{ .key = "tab_bar_decorate_padding_y", .kind = .deco_int_clamp, .field = "padding_y", .deco = "tabbardata", .min = 0, .max = 100 },
};

// ---------------------------------------------------------------------------
// apply helpers (all reached with comptime-known rows)
// ---------------------------------------------------------------------------

/// Replicates the CLAMP_INT macro: clamp in int32 domain.
fn clampInt(x: i32, comptime min: i32, comptime max: i32) i32 {
    return if (x < min) min else if (x > max) max else x;
}

/// C-parity error emission for invalid colors. The format string and ANSI
/// escapes are byte-identical to option_defs.c's.
fn invalidColor(comptime key: [:0]const u8, value: [*:0]const u8) void {
    const fmt = "Invalid " ++ key ++ " format: \x1b[1m\x1b[31m%s\x1b[0m\n";
    acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, fmt.ptr, value);
}

fn setStringSlot(slot: anytype, value: [*:0]const u8) void {
    if (slot.* != null)
        free(@ptrCast(@constCast(slot.*)));
    slot.* = strdup(value);
}

/// parse_color + convert_hex_to_rgba with C-parity uint32 truncation of the
/// parsed i64 (C converts implicitly; (uint32_t) keeps the low 32 bits).
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
        .int_raw => {
            @field(cfg, row.field) = atoi(value);
            return 1;
        },
        .uint_raw => {
            @field(cfg, row.field) = @bitCast(atoi(value));
            return 1;
        },
        .uint_clamp => {
            @field(cfg, row.field) = @bitCast(clampInt(atoi(value), row.min, row.max));
            return 1;
        },
        .string => {
            setStringSlot(&@field(cfg, row.field), value);
            return 1;
        },
        .color4 => {
            return applyColor(&@field(cfg, row.field), row.key, value);
        },
        .deco_int_clamp => {
            const d = &@field(cfg, row.deco.?);
            @field(d, row.field) = clampInt(atoi(value), row.min, row.max);
            return 1;
        },
        .deco_string => {
            const d = &@field(cfg, row.deco.?);
            setStringSlot(&@field(d, row.field), value);
            return 1;
        },
        .deco_color4 => {
            const d = &@field(cfg, row.deco.?);
            return applyColor(&@field(d, row.field), row.key, value);
        },
    }
}

/// C entry point (see file header for the tri-state contract).
export fn acwm_config_apply_bar_option(
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
// tests (stub-backed: see tests/option_bar_stub.c)
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
    return acwm_config_apply_bar_option(cfg, key, value, 7);
}

fn expectErrContains(prefix: []const u8) !void {
    try testing.expect(stub_error_count == 1);
    try testing.expectEqualStrings(
        prefix,
        std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&stub_last_error)), 0)[0..prefix.len],
    );
}

test "tri-state dispatch: bar key, foreign key, unknown bar key" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "bar_enable", "1"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "key_mode", "default"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "gap_inner_horizontal", "3"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "bar_no_such_key", "1"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "group_bar_nonexistent", "1"));
}

test "uint clamps match CLAMP_INT semantics" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "bar_height", "5"));
    try testing.expectEqual(@as(u32, 8), config.bar_height); // below min

    try testing.expectEqual(@as(c_int, 1), apply(&config, "bar_height", "400"));
    try testing.expectEqual(@as(u32, 300), config.bar_height); // above max

    try testing.expectEqual(@as(c_int, 1), apply(&config, "bar_height", "100"));
    try testing.expectEqual(@as(u32, 100), config.bar_height);

    // negative atoi clamps in int32 domain before the uint store
    try testing.expectEqual(@as(c_int, 1), apply(&config, "bar_height", "-5"));
    try testing.expectEqual(@as(u32, 8), config.bar_height);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "bar_battery_interval", "500"));
    try testing.expectEqual(@as(u32, 1000), config.bar_battery_interval);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "bar_battery_interval", "40000000"));
    try testing.expectEqual(@as(u32, 3600000), config.bar_battery_interval);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "bar_tray_icon_size", "200"));
    try testing.expectEqual(@as(u32, 96), config.bar_tray_icon_size);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "bar_top_gap", "-1"));
    try testing.expectEqual(@as(u32, 0), config.bar_top_gap);
}

test "raw uint fields wrap negatives like the C implicit conversion" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    // group_bar_height/tab_bar_height have no clamp in the C chain
    try testing.expectEqual(@as(c_int, 1), apply(&config, "group_bar_height", "-5"));
    try testing.expectEqual(@as(u32, 0xFFFFFFFB), config.group_bar_height);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "tab_bar_height", "27"));
    try testing.expectEqual(@as(u32, 27), config.tab_bar_height);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "group_bar_button_size", "-1"));
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), config.group_bar_button_size);
}

test "int raw fields store atoi verbatim" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "bar_enable", "1"));
    try testing.expectEqual(@as(i32, 1), config.bar_enable);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "bar_enable", "-1"));
    try testing.expectEqual(@as(i32, -1), config.bar_enable);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "always_show_group_bar", "7"));
    try testing.expectEqual(@as(i32, 7), config.always_show_group_bar);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "group_bar_close_button_enable", "0"));
    try testing.expectEqual(@as(i32, 0), config.group_bar_close_button_enable);
}

test "string option frees the old value and stores the new" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "bar_clock_format", "%H:%M"));
    try testing.expectEqualStrings(
        "%H:%M",
        std.mem.span(@as([*:0]const u8, @ptrCast(config.bar_clock_format))),
    );

    // overwrite exercises the free-old path
    try testing.expectEqual(@as(c_int, 1), apply(&config, "bar_clock_format", "%Y-%m-%d"));
    try testing.expectEqualStrings(
        "%Y-%m-%d",
        std.mem.span(@as([*:0]const u8, @ptrCast(config.bar_clock_format))),
    );
}

test "color applies parse_color output through convert_hex_to_rgba" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    stub_parse_color = 0x0A0B0C0D;
    try testing.expectEqual(@as(c_int, 1), apply(&config, "bar_background_color", "#0A0B0C0D"));
    try testing.expectEqual(@as(c_int, 1), stub_convert_calls);
    try testing.expectEqual(@as(u32, 0x0A0B0C0D), stub_converted_hex);
    // stub fill values, proving the write hit config.bar_bg_color
    try testing.expectEqualSlices(f32, &.{ 0.25, 0.5, 0.75, 1.0 }, &config.bar_bg_color);

    // i64 parse output truncates to uint32 like the C (uint32_t) conversion
    stub_parse_color = 0x1_0000_0001;
    try testing.expectEqual(@as(c_int, 1), apply(&config, "bar_background_color", "#100000001"));
    try testing.expectEqual(@as(u32, 1), stub_converted_hex);
}

test "color error path returns -1 and logs with the C format string" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    stub_parse_color = -1;
    try testing.expectEqual(@as(c_int, -1), apply(&config, "bar_background_color", "zz"));
    try expectErrContains("Invalid bar_background_color format: \x1b[1m\x1b[31m");
    try testing.expectEqual(@as(c_int, 0), stub_convert_calls);
    try testing.expectEqualSlices(f32, &.{ 0, 0, 0, 0 }, &config.bar_bg_color);

    // same path through the group button color
    stub_error_count = 0;
    stub_last_error[0] = 0;
    try testing.expectEqual(@as(c_int, -1), apply(&config, "bar_decorate_border_color", "nope"));
    try expectErrContains("Invalid bar_decorate_border_color format: \x1b[1m\x1b[31m");
}

test "decorate options route into their DecorateDrawData member" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "bar_decorate_border_width", "-3"));
    try testing.expectEqual(@as(i32, 0), config.bardata.border_width);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "bar_decorate_border_width", "150"));
    try testing.expectEqual(@as(i32, 100), config.bardata.border_width);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "bar_decorate_padding_x", "42"));
    try testing.expectEqual(@as(i32, 42), config.bardata.padding_x);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "bar_decorate_fg_color", "#FFFFFF"));
    try testing.expectEqualSlices(f32, &.{ 0.25, 0.5, 0.75, 1.0 }, &config.bardata.fg_color);
    try testing.expectEqual(@as(c_int, 1), stub_convert_calls);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "bar_decorate_font_desc", "Fira 10"));
    try testing.expectEqualStrings(
        "Fira 10",
        std.mem.span(@as([*:0]const u8, @ptrCast(config.bardata.font_desc))),
    );
    try testing.expectEqual(@as(c_int, 1), apply(&config, "bar_decorate_font_desc", "JetBrains 12"));
    try testing.expectEqualStrings(
        "JetBrains 12",
        std.mem.span(@as([*:0]const u8, @ptrCast(config.bardata.font_desc))),
    );
}

test "group and tab decoration sets land in their own structs" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "group_bar_decorate_bg_color", "#010203"));
    try testing.expectEqualSlices(f32, &.{ 0.25, 0.5, 0.75, 1.0 }, &config.groupbardata.bg_color);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "group_bar_decorate_corner_radius", "12"));
    try testing.expectEqual(@as(i32, 12), config.groupbardata.corner_radius);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "group_bar_decorate_font_desc", "Sans 11"));
    try testing.expectEqualStrings(
        "Sans 11",
        std.mem.span(@as([*:0]const u8, @ptrCast(config.groupbardata.font_desc))),
    );

    try testing.expectEqual(@as(c_int, 1), apply(&config, "tab_bar_decorate_padding_x", "200"));
    try testing.expectEqual(@as(i32, 100), config.tabbardata.padding_x);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "tab_bar_decorate_border_color", "#0AFF00"));
    try testing.expectEqualSlices(f32, &.{ 0.25, 0.5, 0.75, 1.0 }, &config.tabbardata.border_color);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "group_bar_button_color", "#123456"));
    try testing.expectEqualSlices(f32, &.{ 0.25, 0.5, 0.75, 1.0 }, &config.group_bar_button_color);
}

test "every table row dispatches through the C entry" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    for (rows) |row| {
        const r = acwm_config_apply_bar_option(&config, row.key, "5", 0);
        if (r != 1) {
            std.debug.print("row failed to dispatch: {s}\n", .{row.key});
            return error.RowFailedToDispatch;
        }
    }
    try testing.expectEqual(@as(usize, 45), rows.len);
}
