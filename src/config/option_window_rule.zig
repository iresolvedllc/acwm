//! Port of the window_rule branch from src/config/option_defs.c
//! (strangler-fig Phase 4, slice 15, rule tails 3).
//!
//! Exports one C symbol: acwm_config_apply_window_rule(), called by
//! parse_option() ahead of its strcmp chain (guarded by
//! ACWM_ZIG_WINDOW_RULE, defined only in the Zig build). Handles both
//! window_rule and window_rule_once; the value is a comma-separated
//! key:value list parsed in place. 49 attributes:
//!   - 36 raw ints (atoi) — booleans/relays, -1 means "unset"
//!   - 6 raw floats (atof): width/height, scroller proportions, focused/
//!     unfocused window opacity
//!   - title/app_id/monitor strings (strdup)
//!   - animation_type_open/close via animation_type_from_string
//!   - tags via parse_tag_mask
//!   - global_key_binding: "MOD-KEY" pair (sscanf scanset), parse_mod +
//!     parse_key(..., false)
//!
//! C semantics preserved: 34 int fields default to -1, animation types to
//! ANIM_TYPE_UNSET, strings to NULL, globalkeybinding zeroed; window_rule_once
//! sets is_once=1. Unknown attributes log and set parse_error but the rule is
//! still appended. In contrast, global_key_binding failures (bad format,
//! parse_mod == UINT32_MAX, keysym == XKB_KEY_NoSymbol) abort WITHOUT
//! appending — exactly like the C early returns.
//!
//! parse_mod/parse_key live in binding_parse.c (still C); parse_tag_mask and
//! animation_type_from_string come from the value_parse twin. Tests stub
//! them all. Intentional divergence: realloc failure keeps the previous
//! array instead of overwriting it with NULL (C UB path).
//!
//! Tests live at the bottom and need tests/option_window_rule_stub.c.

const std = @import("std");
const c = @import("cc");

const WLR_ERROR: c_uint = 1;

extern fn acwm_error_impl(log: bool, verbosity: c_uint, file: [*:0]const u8, line: c_int, fmt: [*:0]const u8, ...) callconv(.c) void;
extern fn trim_whitespace(str: ?[*:0]u8) callconv(.c) void;
extern fn animation_type_from_string(value: [*:0]const u8) callconv(.c) i32;
extern fn parse_tag_mask(str: [*:0]u8) callconv(.c) u32;
extern fn parse_mod(mod_str: [*:0]const u8) callconv(.c) u32;
extern fn parse_key(key_str: [*:0]const u8, isbindsym: bool) callconv(.c) c.KeySymCode;

extern "c" fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque;
extern "c" fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern "c" fn strtok(str: ?[*:0]u8, delim: [*:0]const u8) ?[*:0]u8;
extern "c" fn strchr(s: [*:0]const u8, ch: c_int) ?[*:0]u8;
extern "c" fn atoi(nptr: [*:0]const u8) c_int;
extern "c" fn atof(nptr: [*:0]const u8) f64;
extern "c" fn sscanf(str: [*:0]const u8, fmt: [*:0]const u8, ...) c_int;

// ---------------------------------------------------------------------------
// attribute table
// ---------------------------------------------------------------------------

const Kind = enum {
    /// atoi -> int32_t ConfigWinRule field.
    int_raw,
    /// atof -> float ConfigWinRule field.
    float_raw,
    /// strdup over a char * field.
    string,
    /// animation_type_from_string -> int32_t field.
    anim_type,
    /// parse_tag_mask -> uint32_t tags.
    tag_mask,
    /// "MOD-KEY" global binding (may hard-abort the rule).
    global_key,
};

const Row = struct {
    key: [:0]const u8,
    kind: Kind,
    field: [:0]const u8,
};

/// The 49 attributes, in C chain order.
const rows = [_]Row{
    .{ .key = "is_floating", .kind = .int_raw, .field = "isfloating" },
    .{ .key = "title", .kind = .string, .field = "title" },
    .{ .key = "app_id", .kind = .string, .field = "id" },
    .{ .key = "animation_type_open", .kind = .anim_type, .field = "animation_type_open" },
    .{ .key = "animation_type_close", .kind = .anim_type, .field = "animation_type_close" },
    .{ .key = "tags", .kind = .tag_mask, .field = "tags" },
    .{ .key = "monitor", .kind = .string, .field = "monitor" },
    .{ .key = "offset_x", .kind = .int_raw, .field = "offsetx" },
    .{ .key = "offset_y", .kind = .int_raw, .field = "offsety" },
    .{ .key = "no_focus", .kind = .int_raw, .field = "no_focus" },
    .{ .key = "no_fade_in", .kind = .int_raw, .field = "no_fade_in" },
    .{ .key = "no_fade_out", .kind = .int_raw, .field = "no_fade_out" },
    .{ .key = "no_force_center", .kind = .int_raw, .field = "no_force_center" },
    .{ .key = "width", .kind = .float_raw, .field = "width" },
    .{ .key = "height", .kind = .float_raw, .field = "height" },
    .{ .key = "no_border", .kind = .int_raw, .field = "no_border" },
    .{ .key = "no_shadow", .kind = .int_raw, .field = "no_shadow" },
    .{ .key = "no_radius", .kind = .int_raw, .field = "no_radius" },
    .{ .key = "no_animation", .kind = .int_raw, .field = "no_animation" },
    .{ .key = "is_open_silent", .kind = .int_raw, .field = "isopensilent" },
    .{ .key = "is_tag_silent", .kind = .int_raw, .field = "istagsilent" },
    .{ .key = "is_named_scratchpad", .kind = .int_raw, .field = "isnamedscratchpad" },
    .{ .key = "is_unmanaged_global", .kind = .int_raw, .field = "isunglobal" },
    .{ .key = "is_global", .kind = .int_raw, .field = "isglobal" },
    .{ .key = "scroller_proportion_single", .kind = .float_raw, .field = "scroller_proportion_single" },
    .{ .key = "unfocused_opacity", .kind = .float_raw, .field = "unfocused_opacity" },
    .{ .key = "focused_opacity", .kind = .float_raw, .field = "focused_opacity" },
    .{ .key = "is_overlay", .kind = .int_raw, .field = "isoverlay" },
    .{ .key = "shield_when_capture", .kind = .int_raw, .field = "shield_when_capture" },
    .{ .key = "allow_shortcuts_inhibit", .kind = .int_raw, .field = "allow_shortcuts_inhibit" },
    .{ .key = "ignore_maximize", .kind = .int_raw, .field = "ignore_maximize" },
    .{ .key = "ignore_minimize", .kind = .int_raw, .field = "ignore_minimize" },
    .{ .key = "no_size_hint", .kind = .int_raw, .field = "no_size_hint" },
    .{ .key = "idle_inhibit_when_focus", .kind = .int_raw, .field = "idleinhibit_when_focus" },
    .{ .key = "vrr_only_fullscreen", .kind = .int_raw, .field = "vrr_only_fullscreen" },
    .{ .key = "force_render", .kind = .int_raw, .field = "force_render" },
    .{ .key = "activation_bypass", .kind = .int_raw, .field = "activation_bypass" },
    .{ .key = "is_term", .kind = .int_raw, .field = "isterm" },
    .{ .key = "allow_csd", .kind = .int_raw, .field = "allow_csd" },
    .{ .key = "force_fake_maximize", .kind = .int_raw, .field = "force_fakemaximize" },
    .{ .key = "force_tiled_state", .kind = .int_raw, .field = "force_tiled_state" },
    .{ .key = "force_tearing", .kind = .int_raw, .field = "force_tearing" },
    .{ .key = "no_swallow", .kind = .int_raw, .field = "no_swallow" },
    .{ .key = "confine_pointer", .kind = .int_raw, .field = "confine_pointer" },
    .{ .key = "no_blur", .kind = .int_raw, .field = "no_blur" },
    .{ .key = "scroller_proportion", .kind = .float_raw, .field = "scroller_proportion" },
    .{ .key = "is_fullscreen", .kind = .int_raw, .field = "isfullscreen" },
    .{ .key = "is_fake_fullscreen", .kind = .int_raw, .field = "isfakefullscreen" },
    .{ .key = "global_key_binding", .kind = .global_key, .field = "globalkeybinding" },
};

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

fn eq(a: [*:0]const u8, comptime lit: []const u8) bool {
    return std.mem.eql(u8, std.mem.span(a), lit);
}

fn reportUnknown(key: [*:0]const u8) void {
    acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Unknown window rule option:\x1b[1m\x1b[31m%s\x1b[0m\n", key);
}

fn invalidGlobalKey(val: [*:0]const u8) void {
    acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Invalid globalkeybinding: \x1b[1m\x1b[31m%s\x1b[0m\n", val);
}

/// Returns 1 on success, -2 for the C early-return (hard abort, no append).
fn applyRow(r: *c.ConfigWinRule, comptime row: Row, val: [*:0]u8) c_int {
    switch (comptime row.kind) {
        .int_raw => {
            @field(r, row.field) = atoi(val);
            return 1;
        },
        .float_raw => {
            @field(r, row.field) = @floatCast(atof(val));
            return 1;
        },
        .string => {
            @field(r, row.field) = strdup(val);
            return 1;
        },
        .anim_type => {
            @field(r, row.field) = animation_type_from_string(val);
            return 1;
        },
        .tag_mask => {
            r.tags = parse_tag_mask(val);
            return 1;
        },
        .global_key => {
            var mod_str: [256]u8 = undefined;
            var keysym_str: [256]u8 = undefined;
            if (sscanf(
                val,
                "%255[^-]-%255s",
                @as([*]u8, @ptrCast(&mod_str)),
                @as([*]u8, @ptrCast(&keysym_str)),
            ) != 2) {
                invalidGlobalKey(val);
                return -2;
            }
            const mod_z: [*:0]u8 = @ptrCast(&mod_str);
            const keysym_z: [*:0]u8 = @ptrCast(&keysym_str);
            trim_whitespace(mod_z);
            trim_whitespace(keysym_z);

            r.globalkeybinding.mod = parse_mod(mod_z);
            r.globalkeybinding.keysymcode = parse_key(keysym_z, false);
            if (r.globalkeybinding.mod == std.math.maxInt(u32))
                return -2;
            if (r.globalkeybinding.keysymcode.type == c.KEY_TYPE_SYM and
                r.globalkeybinding.keysymcode.keysym == c.XKB_KEY_NoSymbol)
                return -2;
            return 1;
        },
    }
}

// ---------------------------------------------------------------------------
// C entry
// ---------------------------------------------------------------------------

/// C entry point (tri-state: 1 applied, -1 invalid value, 0 not ours).
export fn acwm_config_apply_window_rule(
    config: ?*c.Config,
    key: [*:0]const u8,
    value: [*:0]u8,
    line_number: c_int,
) callconv(.c) c_int {
    _ = line_number;
    const cfg = config orelse return 0;

    const once = eq(key, "window_rule_once");
    if (!once and !eq(key, "window_rule"))
        return 0;

    const new_count = @as(usize, @intCast(cfg.window_rules_count)) + 1;
    const raw = realloc(@ptrCast(cfg.window_rules), new_count * @sizeOf(c.ConfigWinRule)) orelse {
        acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Failed to allocate memory for window rules\n");
        return -1;
    };
    cfg.window_rules = @ptrCast(@alignCast(raw));

    const r: *c.ConfigWinRule = @ptrCast(&cfg.window_rules[@intCast(cfg.window_rules_count)]);
    r.* = std.mem.zeroes(c.ConfigWinRule);

    r.is_once = if (once) 1 else 0;
    r.is_once_applied = 0;

    // 34 int fields default to -1 ("unset") so partial rules merge.
    r.isfloating = -1;
    r.isfullscreen = -1;
    r.isfakefullscreen = -1;
    r.no_border = -1;
    r.no_shadow = -1;
    r.no_radius = -1;
    r.no_animation = -1;
    r.isopensilent = -1;
    r.istagsilent = -1;
    r.isnamedscratchpad = -1;
    r.isunglobal = -1;
    r.isglobal = -1;
    r.isoverlay = -1;
    r.shield_when_capture = -1;
    r.allow_shortcuts_inhibit = -1;
    r.ignore_maximize = -1;
    r.ignore_minimize = -1;
    r.no_size_hint = -1;
    r.idleinhibit_when_focus = -1;
    r.vrr_only_fullscreen = -1;
    r.force_render = -1;
    r.activation_bypass = -1;
    r.isterm = -1;
    r.allow_csd = -1;
    r.force_fakemaximize = -1;
    r.force_tiled_state = -1;
    r.force_tearing = -1;
    r.no_swallow = -1;
    r.confine_pointer = -1;
    r.no_blur = -1;
    r.no_focus = -1;
    r.no_fade_in = -1;
    r.no_fade_out = -1;
    r.no_force_center = -1;

    r.animation_type_open = c.ANIM_TYPE_UNSET;
    r.animation_type_close = c.ANIM_TYPE_UNSET;

    r.focused_opacity = 0;
    r.unfocused_opacity = 0;
    r.scroller_proportion_single = 0.0;
    r.scroller_proportion = 0;

    r.tags = 0;
    r.offsetx = 0;
    r.offsety = 0;
    r.width = 0;
    r.height = 0;
    r.monitor = null;
    r.id = null;
    r.title = null;

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
                    const rc = applyRow(r, row, val);
                    if (rc == -2)
                        return -1; // hard abort: rule not appended
                }
            }
            if (!matched) {
                reportUnknown(attr);
                parse_error = true;
            }
        }
        token = strtok(null, ",");
    }

    cfg.window_rules_count += 1;
    return if (parse_error) -1 else 1;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: see tests/option_window_rule_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_last_error: [1024]u8;
extern var stub_error_count: c_int;
extern var stub_anim_type_return: i32;
extern var stub_tag_mask_return: u32;
extern var stub_tag_mask_input: [128]u8;
extern var stub_mod_return: u32;
extern var stub_mod_input: [128]u8;
extern var stub_key_type: i32;
extern var stub_key_keysym: u32;
extern var stub_key_input: [128]u8;

fn resetStub() void {
    stub_error_count = 0;
    stub_last_error[0] = 0;
    stub_anim_type_return = 0;
    stub_tag_mask_return = 0;
    stub_tag_mask_input[0] = 0;
    stub_mod_return = 0;
    stub_mod_input[0] = 0;
    stub_key_type = c.KEY_TYPE_SYM;
    stub_key_keysym = 'a';
    stub_key_input[0] = 0;
}

/// Copies the rule string into a mutable buffer — the parser mutates it.
fn apply(cfg: *c.Config, comptime key: [:0]const u8, value: []const u8) c_int {
    var buf: [1024:0]u8 = undefined;
    @memcpy(buf[0..value.len], value);
    buf[value.len] = 0;
    return acwm_config_apply_window_rule(cfg, key, &buf, 53);
}

fn lastError() []const u8 {
    return std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&stub_last_error)), 0);
}

fn winRule(cfg: *c.Config, i: usize) *c.ConfigWinRule {
    return @ptrCast(&cfg.window_rules[i]);
}

fn span(ptr: [*c]const u8) []const u8 {
    return std.mem.span(@as([*:0]const u8, @ptrCast(ptr)));
}

test "tri-state dispatch: window_rule/window_rule_once vs other rules" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    var x_buf: [2:0]u8 = .{ 'x', 0 };
    try testing.expectEqual(@as(c_int, 0), acwm_config_apply_window_rule(&config, "tag_rule", &x_buf, 0));
    try testing.expectEqual(@as(c_int, 0), acwm_config_apply_window_rule(&config, "window_rulex", &x_buf, 0));
    try testing.expectEqual(@as(c_int, 0), acwm_config_apply_window_rule(&config, "device_rule", &x_buf, 0));

    try testing.expectEqual(@as(c_int, 1), apply(&config, "window_rule", "title:foo"));
    try testing.expectEqual(@as(c_int, 1), apply(&config, "window_rule_once", "title:bar"));
    try testing.expectEqual(@as(i32, 2), config.window_rules_count);
}

test "once flag and unset defaults" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "window_rule", ""));
    const r = winRule(&config, 0);
    try testing.expectEqual(@as(i32, 0), r.is_once);
    try testing.expectEqual(@as(i32, 0), r.is_once_applied);
    // unset sentinels
    try testing.expectEqual(@as(i32, -1), r.isfloating);
    try testing.expectEqual(@as(i32, -1), r.no_border);
    try testing.expectEqual(@as(i32, -1), r.force_fakemaximize);
    try testing.expectEqual(@as(i32, -1), r.no_force_center);
    try testing.expectEqual(@as(i32, -1), r.animation_type_open);
    try testing.expectEqual(@as(i32, -1), r.animation_type_close);
    try testing.expect(r.id == null);
    try testing.expect(r.title == null);
    try testing.expect(r.monitor == null);
    try testing.expectEqual(@as(f32, 0), r.focused_opacity);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "window_rule_once", "title:x"));
    try testing.expectEqual(@as(i32, 1), winRule(&config, 1).is_once);
}

test "representative attributes: ints, floats, strings, renames" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(
        &config,
        "window_rule",
        "is_floating:1,title:Firefox,app_id:firefox,monitor:DP-1," ++
            "offset_x:10,offset_y:-20,no_border:1,no_shadow:0,no_radius:1," ++
            "is_open_silent:1,is_tag_silent:1,is_named_scratchpad:1," ++
            "is_unmanaged_global:1,is_global:1,is_overlay:1," ++
            "is_term:1,allow_csd:1,force_fake_maximize:1,is_fullscreen:1," ++
            "is_fake_fullscreen:1,force_tiled_state:1,force_tearing:1," ++
            "no_swallow:1,confine_pointer:1,no_blur:1," ++
            "width:800.5,height:600.25,scroller_proportion:0.6," ++
            "scroller_proportion_single:0.7,focused_opacity:0.95,unfocused_opacity:0.85",
    ));
    const r = winRule(&config, 0);
    try testing.expectEqual(@as(i32, 1), r.isfloating);
    try testing.expectEqualStrings("Firefox", span(r.title));
    try testing.expectEqualStrings("firefox", span(r.id));
    try testing.expectEqualStrings("DP-1", span(r.monitor));
    try testing.expectEqual(@as(i32, 10), r.offsetx);
    try testing.expectEqual(@as(i32, -20), r.offsety);
    try testing.expectEqual(@as(i32, 1), r.no_border);
    try testing.expectEqual(@as(i32, 0), r.no_shadow);
    try testing.expectEqual(@as(i32, 1), r.isopensilent);
    try testing.expectEqual(@as(i32, 1), r.istagsilent);
    try testing.expectEqual(@as(i32, 1), r.isnamedscratchpad);
    try testing.expectEqual(@as(i32, 1), r.isunglobal);
    try testing.expectEqual(@as(i32, 1), r.isglobal);
    try testing.expectEqual(@as(i32, 1), r.isoverlay);
    try testing.expectEqual(@as(i32, 1), r.isterm);
    try testing.expectEqual(@as(i32, 1), r.allow_csd);
    try testing.expectEqual(@as(i32, 1), r.force_fakemaximize);
    try testing.expectEqual(@as(i32, 1), r.isfullscreen);
    try testing.expectEqual(@as(i32, 1), r.isfakefullscreen);
    try testing.expectEqual(@as(i32, 1), r.force_tiled_state);
    try testing.expectEqual(@as(i32, 1), r.force_tearing);
    try testing.expectEqual(@as(i32, 1), r.no_swallow);
    try testing.expectEqual(@as(i32, 1), r.confine_pointer);
    try testing.expectEqual(@as(i32, 1), r.no_blur);
    try testing.expectEqual(@as(f32, 800.5), r.width);
    try testing.expectEqual(@as(f32, 600.25), r.height);
    try testing.expectEqual(@as(f32, 0.6), r.scroller_proportion);
    try testing.expectEqual(@as(f32, 0.7), r.scroller_proportion_single);
    try testing.expectEqual(@as(f32, 0.95), r.focused_opacity);
    try testing.expectEqual(@as(f32, 0.85), r.unfocused_opacity);
}

test "tags and animation types delegate to their parsers" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    stub_tag_mask_return = 0b101;
    stub_anim_type_return = 4;
    // note: the rule value is comma-separated, so "tags:1,3" would split
    // before parse_tag_mask sees it (same limitation as the C twin) — use a
    // comma-free range mask instead.
    try testing.expectEqual(@as(c_int, 1), apply(
        &config,
        "window_rule",
        "tags:1-3,animation_type_open:zoom,animation_type_close:slide",
    ));
    const r = winRule(&config, 0);
    try testing.expectEqual(@as(u32, 0b101), r.tags);
    try testing.expectEqual(@as(i32, 4), r.animation_type_open);
    try testing.expectEqual(@as(i32, 4), r.animation_type_close);
    try testing.expectEqualStrings("1-3", std.mem.sliceTo(
        @as([*:0]const u8, @ptrCast(&stub_tag_mask_input)),
        0,
    ));
}

test "global_key_binding success records mod and key" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    stub_mod_return = 64; // LOGO
    stub_key_type = c.KEY_TYPE_SYM;
    stub_key_keysym = 'q';
    try testing.expectEqual(@as(c_int, 1), apply(&config, "window_rule", "title:x,global_key_binding:SUPER-q"));
    try testing.expectEqual(@as(i32, 1), config.window_rules_count);
    const r = winRule(&config, 0);
    try testing.expectEqual(@as(u32, 64), r.globalkeybinding.mod);
    try testing.expectEqual(@as(i32, c.KEY_TYPE_SYM), r.globalkeybinding.keysymcode.type);
    try testing.expectEqual(@as(u32, 'q'), r.globalkeybinding.keysymcode.keysym);
    try testing.expectEqualStrings("SUPER", std.mem.sliceTo(
        @as([*:0]const u8, @ptrCast(&stub_mod_input)),
        0,
    ));
    try testing.expectEqualStrings("q", std.mem.sliceTo(
        @as([*:0]const u8, @ptrCast(&stub_key_input)),
        0,
    ));
}

test "global_key_binding failures abort without appending (C parity)" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    // no dash: sscanf conversion count != 2
    try testing.expectEqual(@as(c_int, -1), apply(&config, "window_rule", "global_key_binding:garbage"));
    try testing.expectEqual(@as(i32, 0), config.window_rules_count);
    try testing.expect(std.mem.startsWith(u8, lastError(), "Invalid globalkeybinding: \x1b[1m\x1b[31mgarbage"));

    // parse_mod error sentinel
    resetStub();
    stub_mod_return = std.math.maxInt(u32);
    try testing.expectEqual(@as(c_int, -1), apply(&config, "window_rule", "global_key_binding:BAD-a"));
    try testing.expectEqual(@as(i32, 0), config.window_rules_count);
    try testing.expectEqual(@as(c_int, 0), stub_error_count); // silent

    // NoSymbol keysym
    resetStub();
    stub_key_type = c.KEY_TYPE_SYM;
    stub_key_keysym = c.XKB_KEY_NoSymbol;
    try testing.expectEqual(@as(c_int, -1), apply(&config, "window_rule", "global_key_binding:SUPER-nosuchkey"));
    try testing.expectEqual(@as(i32, 0), config.window_rules_count);
}

test "unknown attribute appends anyway (C parity)" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, -1), apply(&config, "window_rule", "title:x,bogus:1"));
    try testing.expectEqual(@as(i32, 1), config.window_rules_count);
    try testing.expect(std.mem.startsWith(u8, lastError(), "Unknown window rule option:\x1b[1m\x1b[31mbogus"));
}
