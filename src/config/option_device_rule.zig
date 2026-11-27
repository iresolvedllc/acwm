//! Port of the device_rule branch from src/config/option_defs.c
//! (strangler-fig Phase 4, slice 16, rule tails 4).
//!
//! Exports one C symbol: acwm_config_apply_device_rule(), called by
//! parse_option() ahead of its strcmp chain (guarded by
//! ACWM_ZIG_DEVICE_RULE, defined only in the Zig build). The value is a
//! comma-separated key:value list parsed in place. 25 attributes:
//!   - name (strdup), type (whitelist: keyboard/pointer/trackpad/touch/
//!     switch/tablet/pad; the historical "touchpad" logs a deprecation
//!     warning and resolves to "trackpad")
//!   - repeat_rate (0..1000), repeat_delay (0..10000), kb_* strings
//!     (snprintf into char[128])
//!   - libinput params: natural_scrolling/left_handed/middle emulation/
//!     tap/drag/disable-while-typing/map_focus_monitor (0..1),
//!     accel_profile (0..2), accel_speed (double, -1..1),
//!     scroll/click methods and buttons plus button_map (uint32 from atoi)
//!   - monitor string (char[128])
//!
//! Sentinels preserved: ints default to -1, uint32 params to UINT32_MAX,
//! accel_speed to NAN (fall back to global config). Both an unknown
//! attribute and a token without a colon set parse_error, yet the rule is
//! still appended and counted — C returns the failure after the append.
//! Intentional divergence: realloc failure keeps the previous array
//! instead of overwriting it with NULL (C UB path).
//!
//! Tests live at the bottom and reuse tests/option_monitor_rule_stub.c
//! (trim_whitespace + error recorder).

const std = @import("std");
const c = @import("cc");

const WLR_ERROR: c_uint = 1;
const WLR_INFO: c_uint = 2;

extern fn acwm_error_impl(log: bool, verbosity: c_uint, file: [*:0]const u8, line: c_int, fmt: [*:0]const u8, ...) callconv(.c) void;
extern fn trim_whitespace(str: ?[*:0]u8) callconv(.c) void;

extern "c" fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque;
extern "c" fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern "c" fn strtok(str: ?[*:0]u8, delim: [*:0]const u8) ?[*:0]u8;
extern "c" fn strchr(s: [*:0]const u8, ch: c_int) ?[*:0]u8;
extern "c" fn atoi(nptr: [*:0]const u8) c_int;
extern "c" fn atof(nptr: [*:0]const u8) f64;
extern "c" fn snprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ...) c_int;

// ---------------------------------------------------------------------------
// attribute table
// ---------------------------------------------------------------------------

const Kind = enum {
    /// CLAMP_INT(atoi, min, max) -> int32_t field.
    int_clamp,
    /// (uint32_t)atoi -> uint32_t field (negative wraps).
    uint_raw,
    /// CLAMP over atof -> double field.
    double_clamp,
    /// snprintf into a fixed char[N] field.
    char_array,
    /// strdup over a char * field.
    string,
    /// Device type whitelist with deprecation alias handling.
    dev_type,
};

const Row = struct {
    key: [:0]const u8,
    kind: Kind,
    field: [:0]const u8,
    min: i32 = 0,
    max: i32 = 0,
    dmin: f64 = 0,
    dmax: f64 = 0,
};

/// The 25 attributes, in C chain order.
const rows = [_]Row{
    .{ .key = "name", .kind = .string, .field = "name" },
    .{ .key = "type", .kind = .dev_type, .field = "type" },
    .{ .key = "repeat_rate", .kind = .int_clamp, .field = "repeat_rate", .min = 0, .max = 1000 },
    .{ .key = "repeat_delay", .kind = .int_clamp, .field = "repeat_delay", .min = 0, .max = 10000 },
    .{ .key = "kb_rules", .kind = .char_array, .field = "kb_rules" },
    .{ .key = "kb_model", .kind = .char_array, .field = "kb_model" },
    .{ .key = "kb_layout", .kind = .char_array, .field = "kb_layout" },
    .{ .key = "kb_variant", .kind = .char_array, .field = "kb_variant" },
    .{ .key = "kb_options", .kind = .char_array, .field = "kb_options" },
    .{ .key = "natural_scrolling", .kind = .int_clamp, .field = "natural_scrolling", .min = 0, .max = 1 },
    .{ .key = "accel_profile", .kind = .int_clamp, .field = "accel_profile", .min = 0, .max = 2 },
    .{ .key = "accel_speed", .kind = .double_clamp, .field = "accel_speed", .dmin = -1.0, .dmax = 1.0 },
    .{ .key = "left_handed", .kind = .int_clamp, .field = "left_handed", .min = 0, .max = 1 },
    .{ .key = "middle_button_emulation", .kind = .int_clamp, .field = "middle_button_emulation", .min = 0, .max = 1 },
    .{ .key = "scroll_method", .kind = .uint_raw, .field = "scroll_method" },
    .{ .key = "scroll_button", .kind = .uint_raw, .field = "scroll_button" },
    .{ .key = "click_method", .kind = .uint_raw, .field = "click_method" },
    .{ .key = "send_events_mode", .kind = .uint_raw, .field = "send_events_mode" },
    .{ .key = "tap_to_click", .kind = .int_clamp, .field = "tap_to_click", .min = 0, .max = 1 },
    .{ .key = "tap_and_drag", .kind = .int_clamp, .field = "tap_and_drag", .min = 0, .max = 1 },
    .{ .key = "drag_lock", .kind = .int_clamp, .field = "drag_lock", .min = 0, .max = 1 },
    .{ .key = "button_map", .kind = .uint_raw, .field = "button_map" },
    .{ .key = "disable_while_typing", .kind = .int_clamp, .field = "disable_while_typing", .min = 0, .max = 1 },
    .{ .key = "monitor", .kind = .char_array, .field = "monitor" },
    .{ .key = "map_focus_monitor", .kind = .int_clamp, .field = "map_focus_monitor", .min = 0, .max = 1 },
};

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

fn eq(a: [*:0]const u8, comptime lit: []const u8) bool {
    return std.mem.eql(u8, std.mem.span(a), lit);
}

fn clampInt(x: i32, comptime min: i32, comptime max: i32) i32 {
    return if (x < min) min else if (x > max) max else x;
}

fn clampDouble(x: f64, comptime min: f64, comptime max: f64) f64 {
    return if (x < min) min else if (x > max) max else x;
}

fn warnDeprecatedType() void {
    acwm_error_impl(
        false,
        WLR_INFO,
        @src().file,
        @src().line,
        "device rule type \x1b[1;36mtouchpad\x1b[0m is deprecated, use \x1b[1;36mtrackpad\x1b[0m instead\n",
    );
}

fn invalidType(val: [*:0]const u8) void {
    acwm_error_impl(
        false,
        WLR_ERROR,
        @src().file,
        @src().line,
        "Invalid device rule type: \x1b[1m\x1b[31m%s\x1b[0m (expected one of keyboard, pointer, trackpad, touch, switch, tablet, pad)\n",
        val,
    );
}

fn reportUnknown(key: [*:0]const u8) void {
    acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Unknown device rule option: \x1b[1m\x1b[31m%s\x1b[0m\n", key);
}

fn reportBadFormat(token: [*:0]const u8) void {
    acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Invalid device rule format: \x1b[1m\x1b[31m%s\x1b[0m\n", token);
}

/// Returns 1 on success; sets parse_error via -2 for invalid values.
fn applyRow(r: *c.ConfigDeviceRule, comptime row: Row, val: [*:0]u8) c_int {
    switch (comptime row.kind) {
        .int_clamp => {
            @field(r, row.field) = clampInt(atoi(val), row.min, row.max);
            return 1;
        },
        .uint_raw => {
            @field(r, row.field) = @bitCast(atoi(val));
            return 1;
        },
        .double_clamp => {
            @field(r, row.field) = clampDouble(atof(val), row.dmin, row.dmax);
            return 1;
        },
        .char_array => {
            const dst = &@field(r, row.field); // *[N]u8
            _ = snprintf(dst, dst.len, "%s", val);
            return 1;
        },
        .string => {
            @field(r, row.field) = strdup(val);
            return 1;
        },
        .dev_type => {
            // "touchpad" is the historical name; keep it as a deprecated
            // alias so existing rules are not silently dropped.
            var resolved: [*:0]const u8 = val;
            if (eq(val, "touchpad")) {
                warnDeprecatedType();
                resolved = "trackpad";
            }
            if (eq(resolved, "keyboard") or eq(resolved, "pointer") or
                eq(resolved, "trackpad") or eq(resolved, "touch") or
                eq(resolved, "switch") or eq(resolved, "tablet") or
                eq(resolved, "pad"))
            {
                _ = snprintf(&r.type, r.type.len, "%s", resolved);
                return 1;
            }
            invalidType(val);
            return -2;
        },
    }
}

// ---------------------------------------------------------------------------
// C entry
// ---------------------------------------------------------------------------

/// C entry point (tri-state: 1 applied, -1 invalid value, 0 not ours).
export fn acwm_config_apply_device_rule(
    config: ?*c.Config,
    key: [*:0]const u8,
    value: [*:0]u8,
    line_number: c_int,
) callconv(.c) c_int {
    _ = line_number;
    const cfg = config orelse return 0;
    if (!eq(key, "device_rule"))
        return 0;

    const new_count = @as(usize, @intCast(cfg.device_rules_count)) + 1;
    const raw = realloc(@ptrCast(cfg.device_rules), new_count * @sizeOf(c.ConfigDeviceRule)) orelse {
        acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Failed to allocate memory for device rules\n");
        return -1;
    };
    cfg.device_rules = @ptrCast(@alignCast(raw));

    const r: *c.ConfigDeviceRule = @ptrCast(&cfg.device_rules[@intCast(cfg.device_rules_count)]);
    r.* = std.mem.zeroes(c.ConfigDeviceRule);

    // Defaults: -1 / UINT32_MAX / NAN mean unset and fall back to the
    // global config.
    r.repeat_rate = -1;
    r.repeat_delay = -1;
    r.natural_scrolling = -1;
    r.accel_profile = -1;
    r.left_handed = -1;
    r.middle_button_emulation = -1;
    r.scroll_method = std.math.maxInt(u32);
    r.scroll_button = std.math.maxInt(u32);
    r.click_method = std.math.maxInt(u32);
    r.send_events_mode = std.math.maxInt(u32);
    r.tap_to_click = -1;
    r.tap_and_drag = -1;
    r.drag_lock = -1;
    r.button_map = std.math.maxInt(u32);
    r.disable_while_typing = -1;
    r.map_focus_monitor = -1;
    r.accel_speed = std.math.nan(f64);

    var parse_error = false;
    var token = strtok(value, ",");
    while (token != null) {
        const colon = strchr(token.?, ':');
        if (colon != null) {
            colon.?[0] = 0;
            const attr = token.?;
            const val = colon.? + 1;

            trim_whitespace(attr);
            trim_whitespace(val);

            var matched = false;
            inline for (rows) |row| {
                if (!matched and eq(attr, row.key)) {
                    matched = true;
                    if (applyRow(r, row, val) == -2)
                        parse_error = true;
                }
            }
            if (!matched) {
                reportUnknown(attr);
                parse_error = true;
            }
        } else {
            // C reports non key:value tokens on this branch too.
            reportBadFormat(token.?);
            parse_error = true;
        }
        token = strtok(null, ",");
    }

    cfg.device_rules_count += 1;
    return if (parse_error) -1 else 1;
}

// ---------------------------------------------------------------------------
// tests (stub-backed via tests/option_monitor_rule_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_last_error: [1024]u8;
extern var stub_error_count: c_int;

fn resetStub() void {
    stub_error_count = 0;
    stub_last_error[0] = 0;
}

/// Copies the rule string into a mutable buffer — the parser mutates it.
fn apply(cfg: *c.Config, value: []const u8) c_int {
    var buf: [512:0]u8 = undefined;
    @memcpy(buf[0..value.len], value);
    buf[value.len] = 0;
    return acwm_config_apply_device_rule(cfg, "device_rule", &buf, 59);
}

fn lastError() []const u8 {
    return std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&stub_last_error)), 0);
}

fn devRule(cfg: *c.Config, i: usize) *c.ConfigDeviceRule {
    return @ptrCast(&cfg.device_rules[i]);
}

fn span(ptr: [*c]const u8) []const u8 {
    return std.mem.span(@as([*:0]const u8, @ptrCast(ptr)));
}

test "tri-state dispatch: device_rule only" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    var x_buf: [2:0]u8 = .{ 'x', 0 };
    try testing.expectEqual(@as(c_int, 0), acwm_config_apply_device_rule(&config, "window_rule", &x_buf, 0));
    try testing.expectEqual(@as(c_int, 0), acwm_config_apply_device_rule(&config, "device_rulex", &x_buf, 0));

    try testing.expectEqual(@as(c_int, 1), apply(&config, "name:AT Keyboard"));
    try testing.expectEqual(@as(i32, 1), config.device_rules_count);
    try testing.expectEqualStrings("AT Keyboard", span(devRule(&config, 0).name));
}

test "unset sentinels: -1, UINT32_MAX, NAN, empty strings" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, ""));
    const r = devRule(&config, 0);
    try testing.expectEqual(@as(i32, -1), r.repeat_rate);
    try testing.expectEqual(@as(i32, -1), r.natural_scrolling);
    try testing.expectEqual(@as(i32, -1), r.map_focus_monitor);
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), r.scroll_method);
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), r.button_map);
    try testing.expect(std.math.isNan(r.accel_speed));
    try testing.expectEqual(@as(u8, 0), r.type[0]);
    try testing.expectEqual(@as(u8, 0), r.monitor[0]);
}

test "type whitelist, invalid type and touchpad deprecation" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "type:keyboard"));
    try testing.expectEqualStrings("keyboard", std.mem.sliceTo(&devRule(&config, 0).type, 0));

    // deprecated alias resolves to trackpad and warns at INFO
    try testing.expectEqual(@as(c_int, 1), apply(&config, "type:touchpad"));
    try testing.expectEqualStrings("trackpad", std.mem.sliceTo(&devRule(&config, 1).type, 0));
    try testing.expect(std.mem.startsWith(u8, lastError(), "device rule type \x1b[1;36mtouchpad\x1b[0m is deprecated"));

    // invalid type: parse_error but the rule is still appended
    resetStub();
    try testing.expectEqual(@as(c_int, -1), apply(&config, "type:joystick"));
    try testing.expectEqual(@as(i32, 3), config.device_rules_count);
    try testing.expect(std.mem.startsWith(u8, lastError(), "Invalid device rule type: \x1b[1m\x1b[31mjoystick"));
}

test "clamps, uint casts and fixed char arrays" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(
        &config,
        "name:Touchpad,type:trackpad,repeat_rate:5000,repeat_delay:-5," ++
            "kb_layout:us,kb_options:ctrl:nocaps,kb_model:pc105," ++
            "natural_scrolling:2,accel_profile:9,accel_speed:2.5," ++
            "left_handed:-1,middle_button_emulation:1," ++
            "scroll_method:-1,scroll_button:272,click_method:1," ++
            "send_events_mode:-2,tap_to_click:1,tap_and_drag:1," ++
            "drag_lock:0,button_map:-1,disable_while_typing:1," ++
            "monitor:DP-1,map_focus_monitor:1",
    ));
    const r = devRule(&config, 0);
    try testing.expectEqual(@as(i32, 1000), r.repeat_rate);
    try testing.expectEqual(@as(i32, 0), r.repeat_delay);
    try testing.expectEqualStrings("us", std.mem.sliceTo(&r.kb_layout, 0));
    try testing.expectEqualStrings("ctrl:nocaps", std.mem.sliceTo(&r.kb_options, 0));
    try testing.expectEqualStrings("pc105", std.mem.sliceTo(&r.kb_model, 0));
    try testing.expectEqual(@as(i32, 1), r.natural_scrolling);
    try testing.expectEqual(@as(i32, 2), r.accel_profile);
    try testing.expectEqual(@as(f64, 1.0), r.accel_speed);
    try testing.expectEqual(@as(i32, 0), r.left_handed);
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), r.scroll_method);
    try testing.expectEqual(@as(u32, 272), r.scroll_button);
    try testing.expectEqual(@as(u32, 0xFFFFFFFE), r.send_events_mode);
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), r.button_map);
    try testing.expectEqualStrings("DP-1", std.mem.sliceTo(&r.monitor, 0));
    try testing.expectEqual(@as(i32, 1), r.map_focus_monitor);
    try testing.expectEqual(@as(c_int, 0), stub_error_count);
}

test "accel_speed clamps to -1..1 in double domain" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "accel_speed:-2.5"));
    try testing.expectEqual(@as(f64, -1.0), devRule(&config, 0).accel_speed);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "accel_speed:0.1"));
    try testing.expectEqual(@as(f64, 0.1), devRule(&config, 1).accel_speed);
}

test "unknown attribute and colon-less token append anyway (C parity)" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, -1), apply(&config, "name:x,bogus:1"));
    try testing.expectEqual(@as(i32, 1), config.device_rules_count);
    try testing.expect(std.mem.startsWith(u8, lastError(), "Unknown device rule option: \x1b[1m\x1b[31mbogus"));

    resetStub();
    try testing.expectEqual(@as(c_int, -1), apply(&config, "garbage"));
    try testing.expectEqual(@as(i32, 2), config.device_rules_count);
    try testing.expect(std.mem.startsWith(u8, lastError(), "Invalid device rule format: \x1b[1m\x1b[31mgarbage"));
}

test "every table row dispatches (type row uses a valid value)" {
    var rule: c.ConfigDeviceRule = std.mem.zeroes(c.ConfigDeviceRule);

    inline for (rows) |row| {
        const value: []const u8 = if (row.kind == .dev_type) "keyboard" else "1";
        var buf: [64:0]u8 = undefined;
        @memcpy(buf[0..value.len], value);
        buf[value.len] = 0;
        const rc = applyRow(&rule, row, &buf);
        try testing.expectEqual(@as(c_int, 1), rc);
    }
}
