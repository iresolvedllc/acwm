//! Port of the comma-list option parsers from src/config/option_defs.c
//! (strangler-fig Phase 4, slice 12).
//!
//! Exports one C symbol: acwm_config_apply_array_option(), called by
//! parse_option() ahead of its strcmp chain (guarded by
//! ACWM_ZIG_ARRAY_OPTION, defined only in the Zig build). Covers the two
//! heap-allocating list options:
//!   - scroller_proportion_preset: comma-separated floats, each clamped to
//!     0.1..1.0, stored in a malloc'd float array with a count
//!   - circle_layout: comma-separated strings, sanitized (leading/trailing
//!     non-printable chars removed), stored in a malloc'd char* array
//!
//! The C implementation's exact mechanics are preserved because its edge
//! cases are user-visible: comma counting decides the expected item count,
//! strtok skips empty fields (so "a,,c" fails the count check), sscanf
//! validates floats, a failed re-set frees the old array first, and every
//! failure path frees partial allocations and nulls the config field.
//! Error strings are byte-identical (`"Memory allocation failed\n"`, the
//! two "Invalid ... format" forms and the per-token float error).
//!
//! sanitize_string resolves to the value_parse object in the compositor
//! link; tests stub it. Tests use the real libc strtok/sscanf.
//!
//! Tests live at the bottom and need tests/option_array_stub.c.

const std = @import("std");
const c = @import("cc");

const WLR_ERROR: c_uint = 1;

extern fn acwm_error_impl(log: bool, verbosity: c_uint, file: [*:0]const u8, line: c_int, fmt: [*:0]const u8, ...) callconv(.c) void;
extern fn sanitize_string(str: [*:0]u8) callconv(.c) [*:0]u8;

extern "c" fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn strtok(str: ?[*:0]u8, delim: [*:0]const u8) ?[*:0]u8;
extern "c" fn sscanf(str: [*:0]const u8, fmt: [*:0]const u8, ...) c_int;

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

fn memFail() void {
    acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Memory allocation failed\n");
}

fn invalidPresetFloat(token: [*:0]const u8) void {
    acwm_error_impl(
        false,
        WLR_ERROR,
        @src().file,
        @src().line,
        "Invalid float value in scroller_proportion_preset: \x1b[1m\x1b[31m%s\x1b[0m\n",
        token,
    );
}

fn invalidPresetFormat(value: [*:0]const u8) void {
    acwm_error_impl(
        false,
        WLR_ERROR,
        @src().file,
        @src().line,
        "Invalid scroller_proportion_preset format: \x1b[1m\x1b[31m%s\x1b[0m\n",
        value,
    );
}

fn invalidCircleLayout(value: [*:0]const u8) void {
    acwm_error_impl(
        false,
        WLR_ERROR,
        @src().file,
        @src().line,
        "Invalid circle_layout format: \x1b[1m\x1b[31m%s\x1b[0m\n",
        value,
    );
}

fn memFailString(token: [*:0]const u8) void {
    acwm_error_impl(
        false,
        WLR_ERROR,
        @src().file,
        @src().line,
        "Memory allocation failed for string: %s\n",
        token,
    );
}

/// CLAMP_FLOAT macro semantics (NaN passes through, like C comparisons).
fn clampFloat(x: f32, min: f32, max: f32) f32 {
    return if (x < min) min else if (x > max) max else x;
}

fn itemCount(value: [*:0]const u8) usize {
    return std.mem.count(u8, std.mem.span(value), ",") + 1;
}

// ---------------------------------------------------------------------------
// scroller_proportion_preset
// ---------------------------------------------------------------------------

fn parsePreset(cfg: *c.Config, value: [*:0]const u8) c_int {
    const float_count = itemCount(value);

    // Free the old array first (repeated sets must not leak).
    if (cfg.scroller_proportion_preset != null) {
        free(@ptrCast(cfg.scroller_proportion_preset));
        cfg.scroller_proportion_preset = null;
        cfg.scroller_proportion_preset_count = 0;
    }
    const raw = c.malloc(float_count * @sizeOf(f32)) orelse {
        memFail();
        return -1;
    };
    const preset: [*]f32 = @ptrCast(@alignCast(raw));
    cfg.scroller_proportion_preset = preset;

    const value_copy = strdup(value) orelse {
        memFail();
        free(raw);
        cfg.scroller_proportion_preset = null;
        return -1;
    };

    var token = strtok(value_copy, ",");
    var i: usize = 0;
    var value_set: f32 = undefined;
    while (token != null and i < float_count) : (i += 1) {
        if (sscanf(token.?, "%f", &value_set) != 1) {
            invalidPresetFloat(token.?);
            free(@ptrCast(value_copy));
            free(raw);
            cfg.scroller_proportion_preset = null;
            return -1;
        }
        preset[i] = clampFloat(value_set, 0.1, 1.0);
        token = strtok(null, ",");
    }

    if (i != float_count) {
        invalidPresetFormat(value);
        free(@ptrCast(value_copy));
        free(raw);
        cfg.scroller_proportion_preset = null;
        cfg.scroller_proportion_preset_count = 0;
        return -1;
    }

    cfg.scroller_proportion_preset_count = @intCast(float_count);
    free(@ptrCast(value_copy));
    return 1;
}

// ---------------------------------------------------------------------------
// circle_layout
// ---------------------------------------------------------------------------

fn freeCircleLayout(cfg: *c.Config) void {
    if (cfg.circle_layout != null) {
        var j: usize = 0;
        while (j < @as(usize, @intCast(cfg.circle_layout_count))) : (j += 1) {
            if (cfg.circle_layout[j] != null)
                free(@ptrCast(cfg.circle_layout[j]));
        }
        free(@ptrCast(cfg.circle_layout));
        cfg.circle_layout = null;
        cfg.circle_layout_count = 0;
    }
}

fn parseCircleLayout(cfg: *c.Config, value: [*:0]const u8) c_int {
    const string_count = itemCount(value);

    freeCircleLayout(cfg);

    const raw = c.malloc(string_count * @sizeOf(?[*:0]u8)) orelse {
        memFail();
        return -1;
    };
    const arr: [*]?[*:0]u8 = @ptrCast(@alignCast(raw));
    @memset(arr[0..string_count], null);

    const value_copy = strdup(value) orelse {
        memFail();
        free(raw);
        return -1;
    };

    var token = strtok(value_copy, ",");
    var i: usize = 0;
    while (token != null and i < string_count) : (i += 1) {
        const cleaned = sanitize_string(token.?);
        arr[i] = strdup(cleaned);
        if (arr[i] == null) {
            memFailString(token.?);
            var j: usize = 0;
            while (j < i) : (j += 1)
                free(@ptrCast(arr[j]));
            free(raw);
            free(@ptrCast(value_copy));
            cfg.circle_layout = null;
            cfg.circle_layout_count = 0;
            return -1;
        }
        token = strtok(null, ",");
    }

    if (i != string_count) {
        invalidCircleLayout(value);
        var j: usize = 0;
        while (j < i) : (j += 1)
            free(@ptrCast(arr[j]));
        free(raw);
        free(@ptrCast(value_copy));
        cfg.circle_layout = null;
        cfg.circle_layout_count = 0;
        return -1;
    }

    cfg.circle_layout = @ptrCast(arr);
    cfg.circle_layout_count = @intCast(string_count);
    free(@ptrCast(value_copy));
    return 1;
}

// ---------------------------------------------------------------------------
// C entry
// ---------------------------------------------------------------------------

/// C entry point (tri-state: 1 applied, -1 invalid value, 0 not ours).
export fn acwm_config_apply_array_option(
    config: ?*c.Config,
    key: [*:0]const u8,
    value: [*:0]const u8,
    line_number: c_int,
) callconv(.c) c_int {
    _ = line_number;
    const cfg = config orelse return 0;

    if (std.mem.eql(u8, std.mem.span(key), "scroller_proportion_preset"))
        return parsePreset(cfg, value);
    if (std.mem.eql(u8, std.mem.span(key), "circle_layout"))
        return parseCircleLayout(cfg, value);
    return 0;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: see tests/option_array_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_last_error: [1024]u8;
extern var stub_error_count: c_int;
extern var stub_sanitize_calls: c_int;

fn resetStub() void {
    stub_error_count = 0;
    stub_last_error[0] = 0;
    stub_sanitize_calls = 0;
}

fn apply(cfg: *c.Config, key: [:0]const u8, value: [:0]const u8) c_int {
    return acwm_config_apply_array_option(cfg, key, value, 37);
}

fn lastError() []const u8 {
    return std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&stub_last_error)), 0);
}

fn presetSlice(cfg: *c.Config) []const f32 {
    return cfg.scroller_proportion_preset[0..@intCast(cfg.scroller_proportion_preset_count)];
}

fn layoutAt(cfg: *c.Config, i: usize) []const u8 {
    return std.mem.span(@as([*:0]const u8, @ptrCast(cfg.circle_layout[i])));
}

test "tri-state dispatch: array keys vs everything else" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "scroller_proportion_preset", "0.5"));
    try testing.expectEqual(@as(c_int, 1), apply(&config, "circle_layout", "master,stack"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "scope_layout", "x"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "scroller_structs", "2"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "circle_layoutx", "x"));
}

test "preset parses floats, clamps to 0.1..1.0, records count" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "scroller_proportion_preset", "0.5,0.6,0.75"));
    try testing.expectEqual(@as(i32, 3), config.scroller_proportion_preset_count);
    try testing.expectEqualSlices(f32, &.{ 0.5, 0.6, 0.75 }, presetSlice(&config));

    // clamping on both sides
    try testing.expectEqual(@as(c_int, 1), apply(&config, "scroller_proportion_preset", "0,2.0"));
    try testing.expectEqual(@as(i32, 2), config.scroller_proportion_preset_count);
    try testing.expectEqualSlices(f32, &.{ 0.1, 1.0 }, presetSlice(&config));

    // resetting again replaces the array
    try testing.expectEqual(@as(c_int, 1), apply(&config, "scroller_proportion_preset", "0.42"));
    try testing.expectEqual(@as(i32, 1), config.scroller_proportion_preset_count);
    try testing.expectEqualSlices(f32, &.{0.42}, presetSlice(&config));
    try testing.expectEqual(@as(c_int, 0), stub_error_count);
}

test "preset rejects non-float tokens and cleans up" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, -1), apply(&config, "scroller_proportion_preset", "0.5,abc"));
    try testing.expectEqual(@as(c_int, 1), stub_error_count);
    try testing.expect(std.mem.startsWith(
        u8,
        lastError(),
        "Invalid float value in scroller_proportion_preset: \x1b[1m\x1b[31mabc",
    ));
    try testing.expect(config.scroller_proportion_preset == null);
    try testing.expectEqual(@as(i32, 0), config.scroller_proportion_preset_count);
}

test "preset rejects empty fields via the count check" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, -1), apply(&config, "scroller_proportion_preset", "0.5,,0.75"));
    try testing.expectEqual(@as(c_int, 1), stub_error_count);
    try testing.expect(std.mem.startsWith(
        u8,
        lastError(),
        "Invalid scroller_proportion_preset format: \x1b[1m\x1b[31m0.5,,0.75",
    ));
    try testing.expect(config.scroller_proportion_preset == null);
    try testing.expectEqual(@as(i32, 0), config.scroller_proportion_preset_count);
}

test "circle_layout stores sanitized strings and a count" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "circle_layout", "master, stack ,monocle"));
    try testing.expectEqual(@as(i32, 3), config.circle_layout_count);
    try testing.expectEqualStrings("master", layoutAt(&config, 0));
    try testing.expectEqualStrings("stack", layoutAt(&config, 1)); // stub trims spaces
    try testing.expectEqualStrings("monocle", layoutAt(&config, 2));
    try testing.expectEqual(@as(c_int, 3), stub_sanitize_calls);

    // reset replaces the old strings
    try testing.expectEqual(@as(c_int, 1), apply(&config, "circle_layout", "grid"));
    try testing.expectEqual(@as(i32, 1), config.circle_layout_count);
    try testing.expectEqualStrings("grid", layoutAt(&config, 0));
}

test "circle_layout rejects empty fields and cleans up" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, -1), apply(&config, "circle_layout", "master,,monocle"));
    try testing.expectEqual(@as(c_int, 1), stub_error_count);
    try testing.expect(std.mem.startsWith(
        u8,
        lastError(),
        "Invalid circle_layout format: \x1b[1m\x1b[31mmaster,,monocle",
    ));
    try testing.expect(config.circle_layout == null);
    try testing.expectEqual(@as(i32, 0), config.circle_layout_count);
}
