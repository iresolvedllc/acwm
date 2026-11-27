//! Port of the tag_rule and layer_rule branches from
//! src/config/option_defs.c (strangler-fig Phase 4, slice 14, rule tails 2).
//!
//! Exports one C symbol: acwm_config_apply_rules_option(), called by
//! parse_option() ahead of its strcmp chain (guarded by
//! ACWM_ZIG_RULES_OPTION, defined only in the Zig build). Both rules are
//! comma-separated key:value lists parsed in place:
//!   - tag_rule: id (number or "*" wildcard, 0..tag_num_MAX), layout_name,
//!     monitor_name/make/model/serial, master_count (1..99), master_factor
//!     (0.1..0.9), scroller proportions (0..1), no_render_border/
//!     open_as_floating/no_hide/scroller_ignore_proportion_single (0..1)
//!   - layer_rule: layer_name (defaults to "default"), animation_type_open/
//!     close (animation_type_from_string, default ANIM_TYPE_UNSET),
//!     shield_when_capture/no_blur/no_animation/no_shadow (0..1)
//!
//! Both append to realloc'd arrays and increment the count even when an
//! unknown attribute set parse_error (C returns the failure after the
//! append). No other validation exists — an empty tag rule is accepted,
//! matching C. Intentional divergence: realloc failure keeps the previous
//! array instead of overwriting it with NULL (C UB path).
//!
//! Tests live at the bottom and need tests/option_rules_stub.c.

const std = @import("std");
const c = @import("cc");

const WLR_ERROR: c_uint = 1;

extern fn acwm_error_impl(log: bool, verbosity: c_uint, file: [*:0]const u8, line: c_int, fmt: [*:0]const u8, ...) callconv(.c) void;
extern fn trim_whitespace(str: ?[*:0]u8) callconv(.c) void;
extern fn animation_type_from_string(value: [*:0]const u8) callconv(.c) i32;

extern "c" fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque;
extern "c" fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern "c" fn strtok(str: ?[*:0]u8, delim: [*:0]const u8) ?[*:0]u8;
extern "c" fn strchr(s: [*:0]const u8, ch: c_int) ?[*:0]u8;
extern "c" fn atoi(nptr: [*:0]const u8) c_int;
extern "c" fn atof(nptr: [*:0]const u8) f64;

const TAG_COUNT: i32 = @intCast(c.tag_num_MAX);

fn clampInt(x: i32, comptime min: i32, comptime max: i32) i32 {
    return if (x < min) min else if (x > max) max else x;
}

fn clampFloat(x: f32, comptime min: f32, comptime max: f32) f32 {
    return if (x < min) min else if (x > max) max else x;
}

fn eq(a: [*:0]const u8, comptime lit: []const u8) bool {
    return std.mem.eql(u8, std.mem.span(a), lit);
}

fn reportUnknown(comptime kind: []const u8, key: [*:0]const u8) void {
    const fmt = "Unknown " ++ kind ++ " rule option:\x1b[1m\x1b[31m%s\x1b[0m\n";
    acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, fmt.ptr, key);
}

fn parseTagRule(cfg: *c.Config, value: [*:0]u8) c_int {
    const new_count = @as(usize, @intCast(cfg.tag_rules_count)) + 1;
    const raw = realloc(@ptrCast(cfg.tag_rules), new_count * @sizeOf(c.ConfigTagRule)) orelse {
        acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Failed to allocate memory for tag rules\n");
        return -1;
    };
    cfg.tag_rules = @ptrCast(@alignCast(raw));

    const r = &cfg.tag_rules[@intCast(cfg.tag_rules_count)];
    r.* = std.mem.zeroes(c.ConfigTagRule);

    r.id = 0;
    r.id_wildcard = false;
    r.layout_name = null;
    r.monitor_name = null;
    r.monitor_make = null;
    r.monitor_model = null;
    r.monitor_serial = null;
    r.nmaster = 0;
    r.mfact = 0.0;
    r.no_render_border = 0;
    r.open_as_floating = 0;
    r.no_hide = 0;
    r.scroller_default_proportion = 0.0;
    r.scroller_default_proportion_single = 0.0;
    r.scroller_ignore_proportion_single = -1;

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

            if (eq(attr, "id")) {
                if (eq(val, "*")) {
                    r.id_wildcard = true;
                    r.id = 0;
                } else {
                    r.id_wildcard = false;
                    r.id = clampInt(atoi(val), 0, TAG_COUNT);
                }
            } else if (eq(attr, "layout_name")) {
                r.layout_name = strdup(val);
            } else if (eq(attr, "monitor_name")) {
                r.monitor_name = strdup(val);
            } else if (eq(attr, "monitor_make")) {
                r.monitor_make = strdup(val);
            } else if (eq(attr, "monitor_model")) {
                r.monitor_model = strdup(val);
            } else if (eq(attr, "monitor_serial")) {
                r.monitor_serial = strdup(val);
            } else if (eq(attr, "no_render_border")) {
                r.no_render_border = clampInt(atoi(val), 0, 1);
            } else if (eq(attr, "open_as_floating")) {
                r.open_as_floating = clampInt(atoi(val), 0, 1);
            } else if (eq(attr, "no_hide")) {
                r.no_hide = clampInt(atoi(val), 0, 1);
            } else if (eq(attr, "master_count")) {
                r.nmaster = clampInt(atoi(val), 1, 99);
            } else if (eq(attr, "master_factor")) {
                r.mfact = clampFloat(@floatCast(atof(val)), 0.1, 0.9);
            } else if (eq(attr, "scroller_default_proportion")) {
                r.scroller_default_proportion = clampFloat(@floatCast(atof(val)), 0.0, 1.0);
            } else if (eq(attr, "scroller_default_proportion_single")) {
                r.scroller_default_proportion_single = clampFloat(@floatCast(atof(val)), 0.0, 1.0);
            } else if (eq(attr, "scroller_ignore_proportion_single")) {
                r.scroller_ignore_proportion_single = clampInt(atoi(val), 0, 1);
            } else {
                reportUnknown("tag", attr);
                parse_error = true;
            }
        }
        token = strtok(null, ",");
    }

    cfg.tag_rules_count += 1;
    return if (parse_error) -1 else 1;
}

fn parseLayerRule(cfg: *c.Config, value: [*:0]u8) c_int {
    const new_count = @as(usize, @intCast(cfg.layer_rules_count)) + 1;
    const raw = realloc(@ptrCast(cfg.layer_rules), new_count * @sizeOf(c.ConfigLayerRule)) orelse {
        acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Failed to allocate memory for layer rules\n");
        return -1;
    };
    cfg.layer_rules = @ptrCast(@alignCast(raw));

    const r = &cfg.layer_rules[@intCast(cfg.layer_rules_count)];
    r.* = std.mem.zeroes(c.ConfigLayerRule);

    r.layer_name = null;
    r.animation_type_open = c.ANIM_TYPE_UNSET;
    r.animation_type_close = c.ANIM_TYPE_UNSET;
    r.shield_when_capture = 0;
    r.no_blur = 0;
    r.no_animation = 0;
    r.no_shadow = 0;

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

            if (eq(attr, "layer_name")) {
                r.layer_name = strdup(val);
            } else if (eq(attr, "animation_type_open")) {
                r.animation_type_open = animation_type_from_string(val);
            } else if (eq(attr, "animation_type_close")) {
                r.animation_type_close = animation_type_from_string(val);
            } else if (eq(attr, "shield_when_capture")) {
                r.shield_when_capture = clampInt(atoi(val), 0, 1);
            } else if (eq(attr, "no_blur")) {
                r.no_blur = clampInt(atoi(val), 0, 1);
            } else if (eq(attr, "no_animation")) {
                r.no_animation = clampInt(atoi(val), 0, 1);
            } else if (eq(attr, "no_shadow")) {
                r.no_shadow = clampInt(atoi(val), 0, 1);
            } else {
                reportUnknown("layer", attr);
                parse_error = true;
            }
        }
        token = strtok(null, ",");
    }

    // Uses the default value when no layout name is given.
    if (r.layer_name == null)
        r.layer_name = strdup("default");

    cfg.layer_rules_count += 1;
    return if (parse_error) -1 else 1;
}

/// C entry point (tri-state: 1 applied, -1 invalid value, 0 not ours).
export fn acwm_config_apply_rules_option(
    config: ?*c.Config,
    key: [*:0]const u8,
    value: [*:0]u8,
    line_number: c_int,
) callconv(.c) c_int {
    _ = line_number;
    const cfg = config orelse return 0;

    if (eq(key, "tag_rule"))
        return parseTagRule(cfg, value);
    if (eq(key, "layer_rule"))
        return parseLayerRule(cfg, value);
    return 0;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: see tests/option_rules_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_last_error: [1024]u8;
extern var stub_error_count: c_int;
extern var stub_anim_type_return: i32;
extern var stub_anim_type_value: [128]u8;

fn resetStub() void {
    stub_error_count = 0;
    stub_last_error[0] = 0;
    stub_anim_type_return = 0;
    stub_anim_type_value[0] = 0;
}

/// Copies the rule string into a mutable buffer — the parser mutates it.
fn apply(cfg: *c.Config, comptime key: [:0]const u8, value: []const u8) c_int {
    var buf: [512:0]u8 = undefined;
    @memcpy(buf[0..value.len], value);
    buf[value.len] = 0;
    return acwm_config_apply_rules_option(cfg, key, &buf, 47);
}

fn lastError() []const u8 {
    return std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&stub_last_error)), 0);
}

fn tagRule(cfg: *c.Config, i: usize) *c.ConfigTagRule {
    return @ptrCast(&cfg.tag_rules[i]);
}

fn layerRule(cfg: *c.Config, i: usize) *c.ConfigLayerRule {
    return @ptrCast(&cfg.layer_rules[i]);
}

fn span(ptr: [*c]const u8) []const u8 {
    return std.mem.span(@as([*:0]const u8, @ptrCast(ptr)));
}

test "tri-state dispatch: tag/layer vs monitor and unknown" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    var x_buf: [2:0]u8 = .{ 'x', 0 };
    try testing.expectEqual(@as(c_int, 0), acwm_config_apply_rules_option(&config, "monitor_rule", &x_buf, 0));
    try testing.expectEqual(@as(c_int, 0), acwm_config_apply_rules_option(&config, "tag_rulex", &x_buf, 0));
    try testing.expectEqual(@as(c_int, 0), acwm_config_apply_rules_option(&config, "window_rule", &x_buf, 0));

    try testing.expectEqual(@as(c_int, 1), apply(&config, "tag_rule", "id:3"));
    try testing.expectEqual(@as(c_int, 1), apply(&config, "layer_rule", "no_blur:1"));
}

test "tag rule: id number, wildcard, clamps, defaults" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "tag_rule", " id : 3 , layout_name : tile "));
    try testing.expectEqual(@as(i32, 1), config.tag_rules_count);
    const r = tagRule(&config, 0);
    try testing.expectEqual(@as(i32, 3), r.id);
    try testing.expect(!r.id_wildcard);
    try testing.expectEqualStrings("tile", span(r.layout_name));
    try testing.expectEqual(@as(i32, -1), r.scroller_ignore_proportion_single);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "tag_rule", "id:*"));
    try testing.expect(tagRule(&config, 1).id_wildcard);
    try testing.expectEqual(@as(i32, 0), tagRule(&config, 1).id);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "tag_rule", "id:99"));
    try testing.expectEqual(@as(i32, 31), tagRule(&config, 2).id);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "tag_rule", "id:-5"));
    try testing.expectEqual(@as(i32, 0), tagRule(&config, 3).id);
}

test "tag rule: numeric clamps and monitor matchers" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(
        &config,
        "tag_rule",
        "id:1,master_count:0,master_factor:1.5,scroller_default_proportion:2.0," ++
            "scroller_default_proportion_single:-1,scroller_ignore_proportion_single:5," ++
            "no_render_border:2,open_as_floating:-1,no_hide:1," ++
            "monitor_name:DP-1,monitor_make:Acme,monitor_model:X1,monitor_serial:42",
    ));
    const r = tagRule(&config, 0);
    try testing.expectEqual(@as(i32, 1), r.nmaster); // clamped to 1
    try testing.expectEqual(@as(f32, 0.9), r.mfact); // clamped to 0.9
    try testing.expectEqual(@as(f32, 1.0), r.scroller_default_proportion);
    try testing.expectEqual(@as(f32, 0.0), r.scroller_default_proportion_single);
    try testing.expectEqual(@as(i32, 1), r.scroller_ignore_proportion_single);
    try testing.expectEqual(@as(i32, 1), r.no_render_border);
    try testing.expectEqual(@as(i32, 0), r.open_as_floating);
    try testing.expectEqual(@as(i32, 1), r.no_hide);
    try testing.expectEqualStrings("DP-1", span(r.monitor_name));
    try testing.expectEqualStrings("Acme", span(r.monitor_make));
    try testing.expectEqualStrings("X1", span(r.monitor_model));
    try testing.expectEqualStrings("42", span(r.monitor_serial));
}

test "tag rule: unknown attribute appends anyway (C parity)" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, -1), apply(&config, "tag_rule", "id:2,bogus:x"));
    try testing.expectEqual(@as(i32, 1), config.tag_rules_count);
    try testing.expectEqual(@as(c_int, 1), stub_error_count);
    try testing.expect(std.mem.startsWith(u8, lastError(), "Unknown tag rule option:\x1b[1m\x1b[31mbogus"));
}

test "layer rule: defaults, animation types and toggles" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "layer_rule", "no_blur:1"));
    const r = layerRule(&config, 0);
    // default layer name when omitted
    try testing.expectEqualStrings("default", span(r.layer_name));
    // animation types default to ANIM_TYPE_UNSET
    try testing.expectEqual(@as(i32, -1), r.animation_type_open);
    try testing.expectEqual(@as(i32, -1), r.animation_type_close);
    try testing.expectEqual(@as(i32, 1), r.no_blur);
    try testing.expectEqual(@as(i32, 0), r.no_shadow);

    stub_anim_type_return = 5;
    try testing.expectEqual(@as(c_int, 1), apply(
        &config,
        "layer_rule",
        "layer_name:waybar,animation_type_open:zoom,animation_type_close:slide," ++
            "shield_when_capture:2,no_animation:1,no_shadow:1",
    ));
    const r2 = layerRule(&config, 1);
    try testing.expectEqualStrings("waybar", span(r2.layer_name));
    try testing.expectEqual(@as(i32, 5), r2.animation_type_open);
    try testing.expectEqual(@as(i32, 5), r2.animation_type_close);
    try testing.expectEqual(@as(i32, 1), r2.shield_when_capture);
    try testing.expectEqual(@as(i32, 1), r2.no_animation);
    try testing.expectEqual(@as(i32, 1), r2.no_shadow);
    try testing.expectEqualStrings("slide", std.mem.sliceTo(
        @as([*:0]const u8, @ptrCast(&stub_anim_type_value)),
        0,
    ));
}

test "layer rule: unknown attribute appends anyway (C parity)" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, -1), apply(&config, "layer_rule", "bogus:x"));
    try testing.expectEqual(@as(i32, 1), config.layer_rules_count);
    try testing.expectEqual(@as(c_int, 1), stub_error_count);
    try testing.expect(std.mem.startsWith(u8, lastError(), "Unknown layer rule option:\x1b[1m\x1b[31mbogus"));
}
