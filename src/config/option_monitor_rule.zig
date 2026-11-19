//! Port of the monitor_rule branch from src/config/option_defs.c
//! (strangler-fig Phase 4, slice 13, rule tails part 1).
//!
//! Exports one C symbol: acwm_config_apply_monitor_rule(), called by
//! parse_option() ahead of its strcmp chain (guarded by
//! ACWM_ZIG_MONITOR_RULE, defined only in the Zig build). The rule value is
//! a comma-separated list of key:value pairs parsed in place:
//!   name/make/model/serial (strdup), rr (0..7), scale (0.001..1000),
//!   x/y, width/height (1..INT32_MAX), refresh (0.001..1000), vrr/hdr/
//!   hdr_force/disable/primary/custom (0..1), hdr lum triple (0..10000,
//!   fractions allowed for OLED blacks), icc (free+strdup).
//!
//! Validation gates preserved in order: at least one identity matcher,
//! width/height/refresh must be set together, custom requires the size
//! triple, x and y must be set together. Unknown attributes log and set
//! parse_error but still increment the rule count (C returns false after
//! appending) — replicated exactly.
//!
//! The value buffer is mutated in place (strtok/colon split), matching the
//! C contract. Intentional divergence: on realloc failure the old rule
//! array is kept instead of being overwritten with NULL (C UB path).
//!
//! Tests live at the bottom and need tests/option_monitor_rule_stub.c
//! (trim_whitespace + variadic error recorder).

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
/// value_parse twin in the compositor link; stubbed in tests.
extern fn trim_whitespace(str: ?[*:0]u8) callconv(.c) void;

extern "c" fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque;
extern "c" fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn strtok(str: ?[*:0]u8, delim: [*:0]const u8) ?[*:0]u8;
extern "c" fn strchr(s: [*:0]const u8, ch: c_int) ?[*:0]u8;
extern "c" fn atoi(nptr: [*:0]const u8) c_int;
extern "c" fn atof(nptr: [*:0]const u8) f64;

const INT32_MAX: i32 = std.math.maxInt(i32);

fn clampInt(x: i32, comptime min: i32, comptime max: i32) i32 {
    return if (x < min) min else if (x > max) max else x;
}

fn clampFloat(x: f32, comptime min: f32, comptime max: f32) f32 {
    return if (x < min) min else if (x > max) max else x;
}

fn eq(a: [*:0]const u8, comptime lit: []const u8) bool {
    return std.mem.eql(u8, std.mem.span(a), lit);
}

// error helpers (byte-identical format strings)
fn allocFail() void {
    acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Failed to allocate memory for monitor rules\n");
}

fn unknownOption(key: [*:0]const u8) void {
    acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Unknown monitor rule option:\x1b[1m\x1b[31m%s\x1b[0m\n", key);
}

fn noIdentity() void {
    acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Monitor rule must have at least one of the following options: name, make, model, serial\n");
}

fn incompleteSize() void {
    acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Monitor rule must set width, height and refresh together\n");
}

fn customWithoutSize() void {
    acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Monitor rule with custom must set width, height and refresh\n");
}

fn unpairedXY() void {
    acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Monitor rule must set x and y together\n");
}

/// C entry point (tri-state: 1 applied, -1 invalid value, 0 not ours).
export fn acwm_config_apply_monitor_rule(
    config: ?*c.Config,
    key: [*:0]const u8,
    value: [*:0]u8,
    line_number: c_int,
) callconv(.c) c_int {
    _ = line_number;
    const cfg = config orelse return 0;
    if (!eq(key, "monitor_rule"))
        return 0;

    const new_count = @as(usize, @intCast(cfg.monitor_rules_count)) + 1;
    const raw = realloc(@ptrCast(cfg.monitor_rules), new_count * @sizeOf(c.ConfigMonitorRule)) orelse {
        allocFail();
        return -1;
    };
    cfg.monitor_rules = @ptrCast(@alignCast(raw));

    const r = &cfg.monitor_rules[@intCast(cfg.monitor_rules_count)];
    r.* = std.mem.zeroes(c.ConfigMonitorRule);

    // Defaults after the memset (C sets them explicitly).
    r.name = null;
    r.make = null;
    r.model = null;
    r.serial = null;
    r.rr = 0;
    r.scale = 1.0;
    r.x = INT32_MAX;
    r.y = INT32_MAX;
    r.width = -1;
    r.height = -1;
    r.refresh = 0.0;
    r.vrr = 0;
    r.hdr = 0;
    r.hdr_min_lum = 0.0;
    r.hdr_max_lum = 0.0;
    r.hdr_max_avg_lum = 0.0;
    r.hdr_force = 0;
    r.icc = null;
    r.custom = 0;
    r.disable = 0;
    r.primary = 0;

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

            if (eq(attr, "name")) {
                r.name = strdup(val);
            } else if (eq(attr, "make")) {
                r.make = strdup(val);
            } else if (eq(attr, "model")) {
                r.model = strdup(val);
            } else if (eq(attr, "serial")) {
                r.serial = strdup(val);
            } else if (eq(attr, "rr")) {
                r.rr = clampInt(atoi(val), 0, 7);
            } else if (eq(attr, "scale")) {
                r.scale = clampFloat(@floatCast(atof(val)), 0.001, 1000.0);
            } else if (eq(attr, "x")) {
                r.x = atoi(val);
            } else if (eq(attr, "y")) {
                r.y = atoi(val);
            } else if (eq(attr, "width")) {
                r.width = clampInt(atoi(val), 1, INT32_MAX);
            } else if (eq(attr, "height")) {
                r.height = clampInt(atoi(val), 1, INT32_MAX);
            } else if (eq(attr, "refresh")) {
                r.refresh = clampFloat(@floatCast(atof(val)), 0.001, 1000.0);
            } else if (eq(attr, "vrr")) {
                r.vrr = clampInt(atoi(val), 0, 1);
            } else if (eq(attr, "hdr")) {
                r.hdr = clampInt(atoi(val), 0, 1);
            } else if (eq(attr, "hdr_min_lum")) {
                // cd/m^2. OLED blacks sit well below 0.01, so fractions are
                // allowed (same comment as C).
                r.hdr_min_lum = clampFloat(@floatCast(atof(val)), 0.0, 10000.0);
            } else if (eq(attr, "hdr_max_lum")) {
                r.hdr_max_lum = clampFloat(@floatCast(atof(val)), 0.0, 10000.0);
            } else if (eq(attr, "hdr_max_avg_lum")) {
                r.hdr_max_avg_lum = clampFloat(@floatCast(atof(val)), 0.0, 10000.0);
            } else if (eq(attr, "hdr_force")) {
                r.hdr_force = clampInt(atoi(val), 0, 1);
            } else if (eq(attr, "icc")) {
                free(@ptrCast(r.icc));
                r.icc = strdup(val);
            } else if (eq(attr, "disable")) {
                r.disable = clampInt(atoi(val), 0, 1);
            } else if (eq(attr, "primary")) {
                r.primary = clampInt(atoi(val), 0, 1);
            } else if (eq(attr, "custom")) {
                r.custom = clampInt(atoi(val), 0, 1);
            } else {
                unknownOption(attr);
                parse_error = true;
            }
        }
        token = strtok(null, ",");
    }

    if (r.name == null and r.make == null and r.model == null and r.serial == null) {
        noIdentity();
        return -1;
    }

    const has_width = r.width > 0;
    const has_height = r.height > 0;
    const has_refresh = r.refresh > 0.0;
    if (has_width != has_height or has_width != has_refresh) {
        incompleteSize();
        return -1;
    }

    if (r.custom != 0 and !has_width) {
        customWithoutSize();
        return -1;
    }

    if ((r.x == INT32_MAX) != (r.y == INT32_MAX)) {
        unpairedXY();
        return -1;
    }

    cfg.monitor_rules_count += 1;
    return if (parse_error) -1 else 1;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: see tests/option_monitor_rule_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_last_error: [1024]u8;
extern var stub_error_count: c_int;
extern var stub_trim_calls: c_int;

fn resetStub() void {
    stub_error_count = 0;
    stub_last_error[0] = 0;
    stub_trim_calls = 0;
}

/// Copies the rule string into a mutable buffer — the parser mutates it.
fn apply(cfg: *c.Config, value: []const u8) c_int {
    var buf: [512:0]u8 = undefined;
    @memcpy(buf[0..value.len], value);
    buf[value.len] = 0;
    return acwm_config_apply_monitor_rule(cfg, "monitor_rule", &buf, 43);
}

fn lastError() []const u8 {
    return std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&stub_last_error)), 0);
}

fn rule(cfg: *c.Config, i: usize) *c.ConfigMonitorRule {
    return @ptrCast(&cfg.monitor_rules[i]);
}

fn span(ptr: [*c]const u8) []const u8 {
    return std.mem.span(@as([*:0]const u8, @ptrCast(ptr)));
}

test "tri-state dispatch: monitor_rule only" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    var x_buf: [2:0]u8 = .{ 'x', 0 };
    try testing.expectEqual(@as(c_int, 0), acwm_config_apply_monitor_rule(&config, "tag_rule", &x_buf, 0));
    try testing.expectEqual(@as(c_int, 0), acwm_config_apply_monitor_rule(&config, "monitor_rulex", &x_buf, 0));

    try testing.expectEqual(@as(c_int, 1), apply(&config, "name:DP-1"));
    try testing.expectEqual(@as(i32, 1), config.monitor_rules_count);
    try testing.expectEqualStrings("DP-1", span(rule(&config, 0).name));
}

test "attributes parse with clamps and defaults" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(
        &config,
        " name : DP-1 , scale : 1.5 , rr : 9 , vrr : 1 , hdr : 1 , hdr_force : 2 ," ++
            " hdr_max_lum : 0.005 , hdr_min_lum : 20000 , primary : 1 , disable : 1 , custom : 0",
    ));
    try testing.expectEqual(@as(i32, 1), config.monitor_rules_count);
    const r = rule(&config, 0);
    try testing.expectEqualStrings("DP-1", span(r.name));
    try testing.expectEqual(@as(f32, 1.5), r.scale);
    try testing.expectEqual(@as(i32, 7), r.rr); // clamped from 9
    try testing.expectEqual(@as(i32, 1), r.vrr);
    try testing.expectEqual(@as(i32, 1), r.hdr);
    try testing.expectEqual(@as(i32, 1), r.hdr_force); // clamped from 2
    try testing.expectEqual(@as(f32, 0.005), r.hdr_max_lum);
    try testing.expectEqual(@as(f32, 10000.0), r.hdr_min_lum); // clamped
    try testing.expectEqual(@as(i32, 1), r.primary);
    try testing.expectEqual(@as(i32, 1), r.disable);
    // defaults retained
    try testing.expectEqual(INT32_MAX, r.x);
    try testing.expectEqual(INT32_MAX, r.y);
    try testing.expectEqual(@as(i32, -1), r.width);
    try testing.expectEqual(@as(i32, -1), r.height);
    try testing.expect(stub_trim_calls > 0); // trim_whitespace was invoked
}

test "identity and size validation gates" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    // no identity matcher
    try testing.expectEqual(@as(c_int, -1), apply(&config, "scale:2"));
    try testing.expectEqual(@as(i32, 0), config.monitor_rules_count);
    try testing.expect(std.mem.startsWith(u8, lastError(), "Monitor rule must have at least one of the following options:"));

    // width without height/refresh
    try testing.expectEqual(@as(c_int, -1), apply(&config, "name:DP-1,width:1920"));
    try testing.expect(std.mem.startsWith(u8, lastError(), "Monitor rule must set width, height and refresh together"));

    // custom without the size triple
    try testing.expectEqual(@as(c_int, -1), apply(&config, "name:DP-1,custom:1"));
    try testing.expect(std.mem.startsWith(u8, lastError(), "Monitor rule with custom must set width, height and refresh"));

    // x without y
    try testing.expectEqual(@as(c_int, -1), apply(&config, "name:DP-1,x:10"));
    try testing.expect(std.mem.startsWith(u8, lastError(), "Monitor rule must set x and y together"));
}

test "full size triple + position passes; count grows per rule" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(
        &config,
        "name:DP-1,width:1920,height:1080,refresh:60,x:0,y:0",
    ));
    const r = rule(&config, 0);
    try testing.expectEqual(@as(i32, 1920), r.width);
    try testing.expectEqual(@as(i32, 1080), r.height);
    try testing.expectEqual(@as(f32, 60.0), r.refresh);
    try testing.expectEqual(@as(i32, 0), r.x);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "make:Acme,model:X1,serial:42"));
    try testing.expectEqual(@as(i32, 2), config.monitor_rules_count);
    try testing.expectEqualStrings("Acme", span(rule(&config, 1).make));
    try testing.expectEqualStrings("X1", span(rule(&config, 1).model));
    try testing.expectEqualStrings("42", span(rule(&config, 1).serial));
}

test "unknown attribute logs but still appends the rule (C parity)" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, -1), apply(&config, "name:DP-1,bogus:1"));
    try testing.expectEqual(@as(i32, 1), config.monitor_rules_count); // appended
    try testing.expectEqual(@as(c_int, 1), stub_error_count);
    try testing.expect(std.mem.startsWith(u8, lastError(), "Unknown monitor rule option:\x1b[1m\x1b[31mbogus"));
}

test "icc duplicates free the previous value" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "name:DP-1,icc:/tmp/a.icc,icc:/tmp/b.icc"));
    try testing.expectEqualStrings("/tmp/b.icc", span(rule(&config, 0).icc));
}

test "tokens without a colon are ignored" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "name:DP-1,garbage,scale:2"));
    try testing.expectEqual(@as(f32, 2.0), rule(&config, 0).scale);
    try testing.expectEqual(@as(i32, 1), config.monitor_rules_count);
}
