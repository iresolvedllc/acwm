//! Port of the animation option group from src/config/option_defs.c
//! (strangler-fig Phase 4, slice 7).
//!
//! Exports one C symbol: acwm_config_apply_animation_option(), called by
//! parse_option() ahead of its strcmp chain (guarded by
//! ACWM_ZIG_ANIMATION_OPTION, defined only in the Zig build). Covers the
//! opening animation block: enable flags, open/close types (delegated to
//! animation_type_from_string), fade/direction ints, zoom + fade opacity
//! floats, the five uint32 durations, and the seven 4-double Bezier curve
//! arrays parsed with parse_double_array (25 keys).
//!
//! Parity quirks preserved: the curve error messages use the C legacy names
//! (animation_curve_opacity_fade_in logs "animation_curve_opafadein",
//! ..._fade_out logs "animation_curve_opafadeout"), and a curve value that
//! does not yield exactly 4 doubles fails the option (tri-state -1).
//! animation_type_from_string/parse_double_array resolve to the
//! value_parse object in the compositor link; tests stub them.
//!
//! Tests live at the bottom and need tests/option_animation_stub.c.

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
extern fn animation_type_from_string(value: [*:0]const u8) callconv(.c) i32;
extern fn parse_double_array(input: [*:0]const u8, output: [*]f64, max_count: i32) callconv(.c) i32;

extern "c" fn atoi(nptr: [*:0]const u8) c_int;
extern "c" fn atof(nptr: [*:0]const u8) f64;

// ---------------------------------------------------------------------------
// option table
// ---------------------------------------------------------------------------

const Kind = enum {
    /// atoi -> int32_t Config field.
    int_raw,
    /// animation_type_from_string -> int32_t Config field.
    anim_type,
    /// atof -> float Config field (double->float narrowing like C).
    float_raw,
    /// atoi -> uint32_t Config field; negative wraps like C.
    uint_raw,
    /// parse_double_array(4) -> double[4] Config field; != 4 fails.
    curve4,
};

const Row = struct {
    key: [:0]const u8,
    kind: Kind,
    field: [:0]const u8,
    /// Legacy name used in the curve parse error when it differs from key.
    err_name: ?[:0]const u8 = null,
};

/// The 25 keys, in C chain order.
const rows = [_]Row{
    .{ .key = "animations", .kind = .int_raw, .field = "animations" },
    .{ .key = "layer_animations", .kind = .int_raw, .field = "layer_animations" },
    .{ .key = "animation_type_open", .kind = .anim_type, .field = "animation_type_open" },
    .{ .key = "animation_type_close", .kind = .anim_type, .field = "animation_type_close" },
    .{ .key = "layer_animation_type_open", .kind = .anim_type, .field = "layer_animation_type_open" },
    .{ .key = "layer_animation_type_close", .kind = .anim_type, .field = "layer_animation_type_close" },
    .{ .key = "animation_fade_in", .kind = .int_raw, .field = "animation_fade_in" },
    .{ .key = "animation_fade_out", .kind = .int_raw, .field = "animation_fade_out" },
    .{ .key = "tag_animation_direction", .kind = .int_raw, .field = "tag_animation_direction" },
    .{ .key = "zoom_initial_ratio", .kind = .float_raw, .field = "zoom_initial_ratio" },
    .{ .key = "zoom_end_ratio", .kind = .float_raw, .field = "zoom_end_ratio" },
    .{ .key = "fade_in_begin_opacity", .kind = .float_raw, .field = "fadein_begin_opacity" },
    .{ .key = "fade_out_begin_opacity", .kind = .float_raw, .field = "fadeout_begin_opacity" },
    .{ .key = "animation_duration_move", .kind = .uint_raw, .field = "animation_duration_move" },
    .{ .key = "animation_duration_open", .kind = .uint_raw, .field = "animation_duration_open" },
    .{ .key = "animation_duration_tag", .kind = .uint_raw, .field = "animation_duration_tag" },
    .{ .key = "animation_duration_close", .kind = .uint_raw, .field = "animation_duration_close" },
    .{ .key = "animation_duration_focus", .kind = .uint_raw, .field = "animation_duration_focus" },
    .{ .key = "animation_curve_move", .kind = .curve4, .field = "animation_curve_move" },
    .{ .key = "animation_curve_open", .kind = .curve4, .field = "animation_curve_open" },
    .{ .key = "animation_curve_tag", .kind = .curve4, .field = "animation_curve_tag" },
    .{ .key = "animation_curve_close", .kind = .curve4, .field = "animation_curve_close" },
    .{ .key = "animation_curve_focus", .kind = .curve4, .field = "animation_curve_focus" },
    .{ .key = "animation_curve_opacity_fade_in", .kind = .curve4, .field = "animation_curve_opafadein", .err_name = "animation_curve_opafadein" },
    .{ .key = "animation_curve_opacity_fade_out", .kind = .curve4, .field = "animation_curve_opafadeout", .err_name = "animation_curve_opafadeout" },
};

// ---------------------------------------------------------------------------
// apply helpers
// ---------------------------------------------------------------------------

fn invalidCurve(comptime name: [:0]const u8, value: [*:0]const u8) void {
    const fmt = "Failed to parse " ++ name ++ ": \x1b[1m\x1b[31m%s\x1b[0m\n";
    acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, fmt.ptr, value);
}

fn applyRow(cfg: *c.Config, comptime row: Row, value: [*:0]const u8) c_int {
    switch (comptime row.kind) {
        .int_raw => {
            @field(cfg, row.field) = atoi(value);
            return 1;
        },
        .anim_type => {
            @field(cfg, row.field) = animation_type_from_string(value);
            return 1;
        },
        .float_raw => {
            @field(cfg, row.field) = @floatCast(atof(value));
            return 1;
        },
        .uint_raw => {
            @field(cfg, row.field) = @bitCast(atoi(value));
            return 1;
        },
        .curve4 => {
            const dst = &@field(cfg, row.field);
            const num = parse_double_array(value, dst, 4);
            if (num != 4) {
                invalidCurve(row.err_name orelse row.key, value);
                return -1;
            }
            return 1;
        },
    }
}

/// C entry point (tri-state: 1 applied, -1 invalid value, 0 not ours).
export fn acwm_config_apply_animation_option(
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
// tests (stub-backed: see tests/option_animation_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_anim_type_return: i32;
extern var stub_anim_type_value: [128]u8;
extern var stub_double_array_return: i32;
extern var stub_double_array_calls: c_int;
extern var stub_double_array_input: [128]u8;
extern var stub_last_error: [512]u8;
extern var stub_error_count: c_int;

fn resetStub() void {
    stub_anim_type_return = 0;
    stub_anim_type_value[0] = 0;
    stub_double_array_return = 4;
    stub_double_array_calls = 0;
    stub_double_array_input[0] = 0;
    stub_error_count = 0;
    stub_last_error[0] = 0;
}

fn apply(cfg: *c.Config, key: [:0]const u8, value: [:0]const u8) c_int {
    return acwm_config_apply_animation_option(cfg, key, value, 17);
}

fn lastError() []const u8 {
    return std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&stub_last_error)), 0);
}

test "tri-state dispatch: animation key, adjacent-group keys, unknown" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "animations", "1"));
    // key_mode is the first chain key (outside every group for now)
    try testing.expectEqual(@as(c_int, 0), apply(&config, "key_mode", "default"));
    // blur (visuals) and scroller (later slice) must not match
    try testing.expectEqual(@as(c_int, 0), apply(&config, "blur", "1"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "scroller_structs", "3"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "animationsx", "1"));
}

test "int fields, uint durations wrap, floats narrow" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "animations", "1"));
    try testing.expectEqual(@as(i32, 1), config.animations);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "animation_fade_in", "-1"));
    try testing.expectEqual(@as(i32, -1), config.animation_fade_in);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "tag_animation_direction", "2"));
    try testing.expectEqual(@as(i32, 2), config.tag_animation_direction);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "animation_duration_move", "500"));
    try testing.expectEqual(@as(u32, 500), config.animation_duration_move);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "animation_duration_focus", "-1"));
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), config.animation_duration_focus);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "zoom_initial_ratio", "0.4"));
    try testing.expectEqual(@as(f32, 0.4), config.zoom_initial_ratio);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "fade_out_begin_opacity", "0.5"));
    try testing.expectEqual(@as(f32, 0.5), config.fadeout_begin_opacity);
}

test "animation types delegate to animation_type_from_string" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    stub_anim_type_return = 7;
    try testing.expectEqual(@as(c_int, 1), apply(&config, "animation_type_open", "zoom"));
    try testing.expectEqual(@as(i32, 7), config.animation_type_open);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "layer_animation_type_close", "slide"));
    try testing.expectEqual(@as(i32, 7), config.layer_animation_type_close);
    try testing.expectEqualStrings("slide", std.mem.sliceTo(
        @as([*:0]const u8, @ptrCast(&stub_anim_type_value)),
        0,
    ));
}

test "curves fill the double[4] and fail on wrong counts" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "animation_curve_move", "0.1,0.2,0.3,0.4"));
    try testing.expectEqual(@as(c_int, 1), stub_double_array_calls);
    try testing.expectEqualSlices(f64, &.{ 0.1, 0.2, 0.3, 0.4 }, &config.animation_curve_move);
    try testing.expectEqualStrings("0.1,0.2,0.3,0.4", std.mem.sliceTo(
        @as([*:0]const u8, @ptrCast(&stub_double_array_input)),
        0,
    ));

    // count != 4 fails the option and logs with the key name
    resetStub();
    stub_double_array_return = 2;
    try testing.expectEqual(@as(c_int, -1), apply(&config, "animation_curve_tag", "0.1,0.2"));
    try testing.expectEqual(@as(c_int, 1), stub_error_count);
    try testing.expect(std.mem.startsWith(u8, lastError(), "Failed to parse animation_curve_tag: \x1b[1m\x1b[31m"));

    // legacy names in the opacity curve messages
    resetStub();
    stub_double_array_return = 0;
    try testing.expectEqual(@as(c_int, -1), apply(&config, "animation_curve_opacity_fade_in", "x"));
    try testing.expect(std.mem.startsWith(u8, lastError(), "Failed to parse animation_curve_opafadein: \x1b[1m\x1b[31m"));

    resetStub();
    stub_double_array_return = 0;
    try testing.expectEqual(@as(c_int, -1), apply(&config, "animation_curve_opacity_fade_out", "x"));
    try testing.expect(std.mem.startsWith(u8, lastError(), "Failed to parse animation_curve_opafadeout: \x1b[1m\x1b[31m"));
}

test "every table row dispatches through the C entry" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    for (rows) |row| {
        const r = acwm_config_apply_animation_option(&config, row.key, "5", 0);
        if (r != 1) {
            std.debug.print("row failed to dispatch: {s}\n", .{row.key});
            return error.RowFailedToDispatch;
        }
    }
    try testing.expectEqual(@as(usize, 25), rows.len);
}
