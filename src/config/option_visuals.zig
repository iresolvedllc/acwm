//! Port of the visuals option group from src/config/option_defs.c
//! (strangler-fig Phase 4, slice 5).
//!
//! Exports one C symbol: acwm_config_apply_visuals_option(), called by
//! parse_option() ahead of its strcmp chain (guarded by
//! ACWM_ZIG_VISUALS_OPTION, defined only in the Zig build). Covers four
//! chain regions that share one domain — appearance:
//!   - blur block (10): blur toggles, border_radius, scenefx blur_params
//!     (nested struct: num_passes int, radius float from atoi, the rest
//!     floats from atof)
//!   - shadows block (7): shadows toggles, size (uint32), blur, position
//!   - window opacity (2): focused/unfocused floats
//!   - color block (14): root/shadow/dim/border/drop/split/focus/maximized/
//!     urgent/scratchpad/global/overlay RGBA arrays + dim_enable (int)
//!
//! Parity quirks preserved: several color keys log "Invalid <name>" with a
//! legacy name that differs from the key (root_color -> "rootcolor",
//! shadows_color -> "shadowscolor", maximized_screen_color ->
//! "maximizescreencolor", ...); the error strings are generated from those
//! names so the bytes match option_defs.c.
//!
//! Tests live at the bottom and reuse tests/option_bar_stub.c (controllable
//! parse_color / recording convert + error stubs).

const std = @import("std");
const c = @import("cc");

const WLR_ERROR: c_uint = 1;

extern fn acwm_error_impl(log: bool, verbosity: c_uint, file: [*:0]const u8, line: c_int, fmt: [*:0]const u8, ...) callconv(.c) void;
extern fn parse_color(hex_str: [*:0]const u8) callconv(.c) i64;
extern fn convert_hex_to_rgba(color: [*]f32, hex: u32) callconv(.c) void;

extern "c" fn atoi(nptr: [*:0]const u8) c_int;
extern "c" fn atof(nptr: [*:0]const u8) f64;

// ---------------------------------------------------------------------------
// option table
// ---------------------------------------------------------------------------

const Kind = enum {
    /// atoi -> int32_t field.
    int_raw,
    /// atoi -> uint32_t field; negative wraps like C.
    uint_raw,
    /// atof -> float field (double->float narrowing like C).
    float_raw,
    /// atoi (int) -> float field, like C's int-to-float assignment
    /// (blur_params.radius is float but parsed with atoi).
    int_to_float,
    /// parse_color + convert_hex_to_rgba over float[4].
    color4,
};

const Row = struct {
    key: [:0]const u8,
    kind: Kind,
    /// Config field, or the member of `nest` when set.
    field: [:0]const u8,
    /// Optional nested struct member of Config (blur_params).
    nest: ?[:0]const u8 = null,
    /// Legacy name used in the invalid-color message when it differs from
    /// the key (e.g. root_color -> "rootcolor").
    err_name: ?[:0]const u8 = null,
};

/// The 33 keys, in C chain order within each block.
const rows = [_]Row{
    // --- blur ---
    .{ .key = "blur", .kind = .int_raw, .field = "blur" },
    .{ .key = "blur_layer", .kind = .int_raw, .field = "blur_layer" },
    .{ .key = "blur_optimized", .kind = .int_raw, .field = "blur_optimized" },
    .{ .key = "border_radius", .kind = .int_raw, .field = "border_radius" },
    .{ .key = "blur_params_num_passes", .kind = .int_raw, .field = "num_passes", .nest = "blur_params" },
    .{ .key = "blur_params_radius", .kind = .int_to_float, .field = "radius", .nest = "blur_params" },
    .{ .key = "blur_params_noise", .kind = .float_raw, .field = "noise", .nest = "blur_params" },
    .{ .key = "blur_params_brightness", .kind = .float_raw, .field = "brightness", .nest = "blur_params" },
    .{ .key = "blur_params_contrast", .kind = .float_raw, .field = "contrast", .nest = "blur_params" },
    .{ .key = "blur_params_saturation", .kind = .float_raw, .field = "saturation", .nest = "blur_params" },
    // --- shadows ---
    .{ .key = "shadows", .kind = .int_raw, .field = "shadows" },
    .{ .key = "shadow_only_floating", .kind = .int_raw, .field = "shadow_only_floating" },
    .{ .key = "layer_shadows", .kind = .int_raw, .field = "layer_shadows" },
    .{ .key = "shadows_size", .kind = .uint_raw, .field = "shadows_size" },
    .{ .key = "shadows_blur", .kind = .float_raw, .field = "shadows_blur" },
    .{ .key = "shadows_position_x", .kind = .int_raw, .field = "shadows_position_x" },
    .{ .key = "shadows_position_y", .kind = .int_raw, .field = "shadows_position_y" },
    // --- window opacity ---
    .{ .key = "focused_opacity", .kind = .float_raw, .field = "focused_opacity" },
    .{ .key = "unfocused_opacity", .kind = .float_raw, .field = "unfocused_opacity" },
    // --- colors (legacy message names preserved) ---
    .{ .key = "root_color", .kind = .color4, .field = "rootcolor", .err_name = "rootcolor" },
    .{ .key = "shadows_color", .kind = .color4, .field = "shadowscolor", .err_name = "shadowscolor" },
    .{ .key = "dim_enable", .kind = .int_raw, .field = "dim_enable" },
    .{ .key = "dim_focused_color", .kind = .color4, .field = "dim_focused_color" },
    .{ .key = "dim_unfocused_color", .kind = .color4, .field = "dim_unfocused_color" },
    .{ .key = "border_color", .kind = .color4, .field = "bordercolor", .err_name = "bordercolor" },
    .{ .key = "drop_color", .kind = .color4, .field = "dropcolor", .err_name = "dropcolor" },
    .{ .key = "split_color", .kind = .color4, .field = "splitcolor", .err_name = "splitcolor" },
    .{ .key = "focus_color", .kind = .color4, .field = "focuscolor", .err_name = "focuscolor" },
    .{ .key = "maximized_screen_color", .kind = .color4, .field = "maximizescreencolor", .err_name = "maximizescreencolor" },
    .{ .key = "urgent_color", .kind = .color4, .field = "urgentcolor", .err_name = "urgentcolor" },
    .{ .key = "scratchpad_color", .kind = .color4, .field = "scratchpadcolor", .err_name = "scratchpadcolor" },
    .{ .key = "global_color", .kind = .color4, .field = "globalcolor", .err_name = "globalcolor" },
    .{ .key = "overlay_color", .kind = .color4, .field = "overlaycolor", .err_name = "overlaycolor" },
};

// ---------------------------------------------------------------------------
// apply helpers
// ---------------------------------------------------------------------------

fn Target(comptime row: Row) type {
    if (row.nest) |n| {
        const Holder = @TypeOf(@field(@as(c.Config, undefined), n));
        return *@TypeOf(@field(@as(Holder, undefined), row.field));
    }
    return *@TypeOf(@field(@as(c.Config, undefined), row.field));
}

fn target(cfg: *c.Config, comptime row: Row) Target(row) {
    if (comptime row.nest) |n| {
        const sub = &@field(cfg, n);
        return &@field(sub, row.field);
    }
    return &@field(cfg, row.field);
}

fn invalidColor(comptime name: [:0]const u8, value: [*:0]const u8) void {
    const fmt = "Invalid " ++ name ++ " format: \x1b[1m\x1b[31m%s\x1b[0m\n";
    acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, fmt.ptr, value);
}

/// parse_color + convert_hex_to_rgba with C-parity uint32 truncation.
fn applyColor(dst: *[4]f32, comptime name: [:0]const u8, value: [*:0]const u8) c_int {
    const color = parse_color(value);
    if (color == -1) {
        invalidColor(name, value);
        return -1;
    }
    convert_hex_to_rgba(dst, @truncate(@as(u64, @bitCast(color))));
    return 1;
}

fn applyRow(cfg: *c.Config, comptime row: Row, value: [*:0]const u8) c_int {
    switch (comptime row.kind) {
        .int_raw => {
            target(cfg, row).* = atoi(value);
            return 1;
        },
        .uint_raw => {
            target(cfg, row).* = @bitCast(atoi(value));
            return 1;
        },
        .float_raw => {
            target(cfg, row).* = @floatCast(atof(value));
            return 1;
        },
        .int_to_float => {
            target(cfg, row).* = @floatFromInt(atoi(value));
            return 1;
        },
        .color4 => {
            return applyColor(target(cfg, row), row.err_name orelse row.key, value);
        },
    }
}

/// C entry point (tri-state: 1 applied, -1 invalid value, 0 not ours).
export fn acwm_config_apply_visuals_option(
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
    return acwm_config_apply_visuals_option(cfg, key, value, 11);
}

fn lastError() []const u8 {
    return std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&stub_last_error)), 0);
}

test "tri-state dispatch: visuals key, other-group keys, unknown" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "blur", "1"));
    // neighbors from other slices
    try testing.expectEqual(@as(c_int, 0), apply(&config, "single_scratchpad", "1"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "group_bar_button_color", "#000"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "monitor_rule", "DP-1"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "blurx", "1"));
}

test "blur toggles and nested blur_params" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "blur", "1"));
    try testing.expectEqual(@as(i32, 1), config.blur);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "border_radius", "12"));
    try testing.expectEqual(@as(i32, 12), config.border_radius);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "blur_params_num_passes", "3"));
    try testing.expectEqual(@as(i32, 3), config.blur_params.num_passes);

    // radius is a float field parsed with atoi in C
    try testing.expectEqual(@as(c_int, 1), apply(&config, "blur_params_radius", "7"));
    try testing.expectEqual(@as(f32, 7.0), config.blur_params.radius);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "blur_params_noise", "0.1"));
    try testing.expectEqual(@as(f32, 0.1), config.blur_params.noise);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "blur_params_saturation", "1.2"));
    try testing.expectEqual(@as(f32, 1.2), config.blur_params.saturation);
}

test "shadows and opacity" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "shadows", "1"));
    try testing.expectEqual(@as(i32, 1), config.shadows);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "shadows_size", "-1"));
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), config.shadows_size);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "shadows_blur", "8.5"));
    try testing.expectEqual(@as(f32, 8.5), config.shadows_blur);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "shadows_position_y", "-4"));
    try testing.expectEqual(@as(i32, -4), config.shadows_position_y);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "focused_opacity", "0.9"));
    try testing.expectEqual(@as(f32, 0.9), config.focused_opacity);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "unfocused_opacity", "0.8"));
    try testing.expectEqual(@as(f32, 0.8), config.unfocused_opacity);
}

test "color block writes RGBA arrays, dim_enable is an int" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    stub_parse_color = 0x0A0B0C0D;
    try testing.expectEqual(@as(c_int, 1), apply(&config, "root_color", "#0A0B0C0D"));
    try testing.expectEqual(@as(u32, 0x0A0B0C0D), stub_converted_hex);
    try testing.expectEqualSlices(f32, &.{ 0.25, 0.5, 0.75, 1.0 }, &config.rootcolor);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "border_color", "#112233"));
    try testing.expectEqualSlices(f32, &.{ 0.25, 0.5, 0.75, 1.0 }, &config.bordercolor);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "maximized_screen_color", "#445566"));
    try testing.expectEqualSlices(f32, &.{ 0.25, 0.5, 0.75, 1.0 }, &config.maximizescreencolor);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "overlay_color", "#778899"));
    try testing.expectEqualSlices(f32, &.{ 0.25, 0.5, 0.75, 1.0 }, &config.overlaycolor);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "dim_focused_color", "#AABBCC"));
    try testing.expectEqualSlices(f32, &.{ 0.25, 0.5, 0.75, 1.0 }, &config.dim_focused_color);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "dim_enable", "1"));
    try testing.expectEqual(@as(i32, 1), config.dim_enable);
    try testing.expectEqual(@as(c_int, 0), stub_error_count);
}

test "invalid colors keep the legacy message names and return -1" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();
    stub_parse_color = -1;

    try testing.expectEqual(@as(c_int, -1), apply(&config, "root_color", "zz"));
    try testing.expect(std.mem.startsWith(u8, lastError(), "Invalid rootcolor format: \x1b[1m\x1b[31m"));

    stub_error_count = 0;
    stub_last_error[0] = 0;
    try testing.expectEqual(@as(c_int, -1), apply(&config, "shadows_color", "zz"));
    try testing.expect(std.mem.startsWith(u8, lastError(), "Invalid shadowscolor format: \x1b[1m\x1b[31m"));

    stub_error_count = 0;
    stub_last_error[0] = 0;
    try testing.expectEqual(@as(c_int, -1), apply(&config, "border_color", "zz"));
    try testing.expect(std.mem.startsWith(u8, lastError(), "Invalid bordercolor format: \x1b[1m\x1b[31m"));

    // keys whose legacy name equals the key keep it verbatim
    stub_error_count = 0;
    stub_last_error[0] = 0;
    try testing.expectEqual(@as(c_int, -1), apply(&config, "dim_unfocused_color", "zz"));
    try testing.expect(std.mem.startsWith(u8, lastError(), "Invalid dim_unfocused_color format: \x1b[1m\x1b[31m"));

    try testing.expectEqual(@as(c_int, 0), stub_convert_calls);
}

test "every table row dispatches through the C entry" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    for (rows) |row| {
        const r = acwm_config_apply_visuals_option(&config, row.key, "5", 0);
        if (r != 1) {
            std.debug.print("row failed to dispatch: {s}\n", .{row.key});
            return error.RowFailedToDispatch;
        }
    }
    try testing.expectEqual(@as(usize, 33), rows.len);
}
