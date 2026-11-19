//! Port of the binding branches + key_mode from src/config/option_defs.c
//! (strangler-fig Phase 4, slice 18 — closes parse_option).
//!
//! Exports one C symbol: acwm_config_apply_bind_option(), called by
//! parse_option() ahead of its strcmp chain (guarded by
//! ACWM_ZIG_BIND_OPTION, defined only in the Zig build). Covers:
//!   - key_mode: snprintf("%.27s") into config->keymode
//!   - bind/binds/bindl/bindr/bindp/bindc(+combinations): the C regex
//!     "^bind[s|l|r|p|c]*$" — its character class literally includes '|',
//!     replicated exactly — with the 8-field sscanf, mode copy from
//!     config->keymode, parse_bind_flags, parse_key/parse_mod and
//!     parse_func_name; failure (unknown dispatch, parse_mod == UINT32_MAX,
//!     SYM+NoSymbol) frees arg strings and does NOT append
//!   - mousebind/axisbind/switchbind/gesturebind (prefix matches) with
//!     set_binding_keymode, their per-kind sscanf field counts
//!     (3/3/3/4 minimum) and silent-vs-logged failure split identical to C
//!
//! parse_bind_flags/set_binding_keymode/parse_mod/parse_key/parse_button/
//! parse_direction/parse_fold_state/parse_func_name still live in
//! binding_parse.c (parse_direction/parse_fold_state in value_parse);
//! config_current_file_index in load.c. All stay extern; tests stub them
//! with real header types.
//!
//! Tests live at the bottom and need tests/option_bind_stub.c.

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
extern fn trim_whitespace(str: ?[*:0]u8) callconv(.c) void;
extern fn parse_bind_flags(str: [*:0]const u8, kb: *c.KeyBinding) callconv(.c) void;
extern fn set_binding_keymode(config: *c.Config, mode: [*]u8, iscommonmode: *bool, isdefaultmode: *bool) callconv(.c) void;
extern fn parse_key(key_str: [*:0]const u8, isbindsym: bool) callconv(.c) c.KeySymCode;
extern fn parse_mod(mod_str: [*:0]const u8) callconv(.c) u32;
extern fn parse_button(str: [*:0]const u8) callconv(.c) u32;
extern fn parse_direction(str: [*:0]const u8) callconv(.c) i32;
extern fn parse_fold_state(str: [*:0]const u8) callconv(.c) i32;
extern fn parse_func_name(
    func_name: [*:0]u8,
    arg: *c.Arg,
    arg_value: [*:0]u8,
    arg_value2: [*:0]u8,
    arg_value3: [*:0]u8,
    arg_value4: [*:0]u8,
    arg_value5: [*:0]u8,
) callconv(.c) c.FuncType;
extern fn config_current_file_index() callconv(.c) c_int;

extern "c" fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn strtok(str: ?[*:0]u8, delim: [*:0]const u8) ?[*:0]u8;
extern "c" fn atoi(nptr: [*:0]const u8) c_int;
extern "c" fn sscanf(str: [*:0]const u8, fmt: [*:0]const u8, ...) c_int;
extern "c" fn snprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ...) c_int;

const MAX32: u32 = std.math.maxInt(u32);

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

fn eq(a: [*:0]const u8, comptime lit: []const u8) bool {
    return std.mem.eql(u8, std.mem.span(a), lit);
}

/// C regex "^bind[s|l|r|p|c]*$" — the "|"s inside the character class are
/// literal members, not alternation.
fn isBindKey(key: [:0]const u8) bool {
    if (!std.mem.startsWith(u8, key, "bind"))
        return false;
    for (key[4..]) |ch| {
        switch (ch) {
            's', 'l', 'r', 'p', 'c', '|' => {},
            else => return false,
        }
    }
    return true;
}

fn invalidFormat(comptime kind: []const u8, value: [*:0]const u8) void {
    const fmt = "Invalid " ++ kind ++ " format: \x1b[1m\x1b[31m%s\x1b[0m\n";
    acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, fmt.ptr, value);
}

fn unknownDispatch(comptime kind: []const u8, func_name: [*:0]const u8) void {
    const fmt = "Unknown dispatch in " ++ kind ++ ": \x1b[1m\x1b[31m%s\x1b[0m\n";
    acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, fmt.ptr, func_name);
}

fn freeArgStrings(arg: *c.Arg) void {
    if (arg.v != null) {
        free(@ptrCast(arg.v));
        arg.v = null;
    }
    if (arg.v2 != null) {
        free(@ptrCast(arg.v2));
        arg.v2 = null;
    }
    if (arg.v3 != null) {
        free(@ptrCast(arg.v3));
        arg.v3 = null;
    }
}

const Buf = [256]u8;

fn initArgBufs(bufs: *[5]Buf) void {
    for (bufs) |*b| {
        b[0] = '0';
        b[1] = 0;
    }
}

fn ptr(buf: *Buf) [*]u8 {
    return @ptrCast(buf);
}

fn z(buf: *Buf) [*:0]u8 {
    return @ptrCast(buf);
}

// ---------------------------------------------------------------------------
// key_mode
// ---------------------------------------------------------------------------

fn applyKeyMode(cfg: *c.Config, value: [*:0]const u8) c_int {
    _ = snprintf(&cfg.keymode, cfg.keymode.len, "%.27s", value);
    return 1;
}

// ---------------------------------------------------------------------------
// bind
// ---------------------------------------------------------------------------

fn parseBind(cfg: *c.Config, key: [*:0]const u8, value: [*:0]u8, line_number: c_int) c_int {
    const new_count = @as(usize, @intCast(cfg.key_bindings_count)) + 1;
    const raw = realloc(@ptrCast(cfg.key_bindings), new_count * @sizeOf(c.KeyBinding)) orelse {
        acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Failed to allocate memory for key bindings\n");
        return -1;
    };
    cfg.key_bindings = @ptrCast(@alignCast(raw));

    const b: *c.KeyBinding = @ptrCast(&cfg.key_bindings[@intCast(cfg.key_bindings_count)]);
    b.* = std.mem.zeroes(c.KeyBinding);
    b.line_number = line_number;
    b.file_index = config_current_file_index();

    var mod_str: Buf = undefined;
    var keysym_str: Buf = undefined;
    var func_name: Buf = undefined;
    var args: [5]Buf = undefined;
    initArgBufs(&args);

    if (sscanf(
        value,
        "%255[^,],%255[^,],%255[^,],%255[^,],%255[^,],%255[^,],%255[^,],%255[^\n]",
        ptr(&mod_str),
        ptr(&keysym_str),
        ptr(&func_name),
        ptr(&args[0]),
        ptr(&args[1]),
        ptr(&args[2]),
        ptr(&args[3]),
        ptr(&args[4]),
    ) < 3) {
        invalidFormat("bind", value);
        return -1;
    }
    trim_whitespace(z(&mod_str));
    trim_whitespace(z(&keysym_str));
    trim_whitespace(z(&func_name));
    for (&args) |*a| trim_whitespace(z(a));

    // strcpy(binding->mode, config->keymode) + common/default classification.
    b.mode = cfg.keymode;
    const mode = std.mem.sliceTo(&b.mode, 0);
    if (std.mem.eql(u8, mode, "common")) {
        b.iscommonmode = true;
        b.isdefaultmode = false;
    } else if (std.mem.eql(u8, mode, "default")) {
        b.isdefaultmode = true;
        b.iscommonmode = false;
    } else {
        b.isdefaultmode = false;
        b.iscommonmode = false;
    }

    parse_bind_flags(key, b);
    b.keysymcode = parse_key(z(&keysym_str), b.keysymcode.type == c.KEY_TYPE_SYM);
    b.mod = parse_mod(z(&mod_str));
    b.func = parse_func_name(
        z(&func_name),
        &b.arg,
        z(&args[0]),
        z(&args[1]),
        z(&args[2]),
        z(&args[3]),
        z(&args[4]),
    );
    if (b.func == null or b.mod == MAX32 or
        (b.keysymcode.type == c.KEY_TYPE_SYM and b.keysymcode.keysym == c.XKB_KEY_NoSymbol))
    {
        freeArgStrings(&b.arg);
        if (b.func == null)
            unknownDispatch("bind", z(&func_name));
        return -1;
    }
    cfg.key_bindings_count += 1;
    return 1;
}

// ---------------------------------------------------------------------------
// mousebind
// ---------------------------------------------------------------------------

fn parseMousebind(cfg: *c.Config, value: [*:0]u8, line_number: c_int) c_int {
    const new_count = @as(usize, @intCast(cfg.mouse_bindings_count)) + 1;
    const raw = realloc(@ptrCast(cfg.mouse_bindings), new_count * @sizeOf(c.MouseBinding)) orelse {
        acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Failed to allocate memory for mouse bindings\n");
        return -1;
    };
    cfg.mouse_bindings = @ptrCast(@alignCast(raw));

    const b: *c.MouseBinding = @ptrCast(&cfg.mouse_bindings[@intCast(cfg.mouse_bindings_count)]);
    b.* = std.mem.zeroes(c.MouseBinding);
    set_binding_keymode(cfg, &b.mode, &b.iscommonmode, &b.isdefaultmode);
    b.line_number = line_number;
    b.file_index = config_current_file_index();

    var mod_str: Buf = undefined;
    var button_str: Buf = undefined;
    var func_name: Buf = undefined;
    var args: [5]Buf = undefined;
    initArgBufs(&args);

    if (sscanf(
        value,
        "%255[^,],%255[^,],%255[^,],%255[^,],%255[^,],%255[^,],%255[^,],%255[^\n]",
        ptr(&mod_str),
        ptr(&button_str),
        ptr(&func_name),
        ptr(&args[0]),
        ptr(&args[1]),
        ptr(&args[2]),
        ptr(&args[3]),
        ptr(&args[4]),
    ) < 3) {
        invalidFormat("mousebind", value);
        return -1;
    }
    trim_whitespace(z(&mod_str));
    trim_whitespace(z(&button_str));
    trim_whitespace(z(&func_name));
    for (&args) |*a| trim_whitespace(z(a));

    b.mod = parse_mod(z(&mod_str));
    b.button = parse_button(z(&button_str));
    b.func = parse_func_name(z(&func_name), &b.arg, z(&args[0]), z(&args[1]), z(&args[2]), z(&args[3]), z(&args[4]));
    if (b.func == null or b.mod == MAX32 or b.button == MAX32) {
        freeArgStrings(&b.arg);
        if (b.func == null)
            unknownDispatch("mousebind", z(&func_name));
        return -1;
    }
    cfg.mouse_bindings_count += 1;
    return 1;
}

// ---------------------------------------------------------------------------
// axisbind
// ---------------------------------------------------------------------------

fn parseAxisbind(cfg: *c.Config, value: [*:0]u8, line_number: c_int) c_int {
    const new_count = @as(usize, @intCast(cfg.axis_bindings_count)) + 1;
    const raw = realloc(@ptrCast(cfg.axis_bindings), new_count * @sizeOf(c.AxisBinding)) orelse {
        acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Failed to allocate memory for axis bindings\n");
        return -1;
    };
    cfg.axis_bindings = @ptrCast(@alignCast(raw));

    const b: *c.AxisBinding = @ptrCast(&cfg.axis_bindings[@intCast(cfg.axis_bindings_count)]);
    b.* = std.mem.zeroes(c.AxisBinding);
    set_binding_keymode(cfg, &b.mode, &b.iscommonmode, &b.isdefaultmode);
    b.line_number = line_number;
    b.file_index = config_current_file_index();

    var mod_str: Buf = undefined;
    var dir_str: Buf = undefined;
    var func_name: Buf = undefined;
    var args: [5]Buf = undefined;
    initArgBufs(&args);

    if (sscanf(
        value,
        "%255[^,],%255[^,],%255[^,],%255[^,],%255[^,],%255[^,],%255[^,],%255[^\n]",
        ptr(&mod_str),
        ptr(&dir_str),
        ptr(&func_name),
        ptr(&args[0]),
        ptr(&args[1]),
        ptr(&args[2]),
        ptr(&args[3]),
        ptr(&args[4]),
    ) < 3) {
        invalidFormat("axisbind", value);
        return -1;
    }
    trim_whitespace(z(&mod_str));
    trim_whitespace(z(&dir_str));
    trim_whitespace(z(&func_name));
    for (&args) |*a| trim_whitespace(z(a));

    b.mod = parse_mod(z(&mod_str));
    b.dir = @bitCast(parse_direction(z(&dir_str)));
    b.func = parse_func_name(z(&func_name), &b.arg, z(&args[0]), z(&args[1]), z(&args[2]), z(&args[3]), z(&args[4]));
    if (b.func == null or b.mod == MAX32) {
        freeArgStrings(&b.arg);
        if (b.func == null)
            unknownDispatch("axisbind", z(&func_name));
        return -1;
    }
    cfg.axis_bindings_count += 1;
    return 1;
}

// ---------------------------------------------------------------------------
// switchbind
// ---------------------------------------------------------------------------

fn parseSwitchbind(cfg: *c.Config, value: [*:0]u8, line_number: c_int) c_int {
    const new_count = @as(usize, @intCast(cfg.switch_bindings_count)) + 1;
    const raw = realloc(@ptrCast(cfg.switch_bindings), new_count * @sizeOf(c.SwitchBinding)) orelse {
        acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Failed to allocate memory for switch bindings\n");
        return -1;
    };
    cfg.switch_bindings = @ptrCast(@alignCast(raw));

    const b: *c.SwitchBinding = @ptrCast(&cfg.switch_bindings[@intCast(cfg.switch_bindings_count)]);
    b.* = std.mem.zeroes(c.SwitchBinding);
    set_binding_keymode(cfg, &b.mode, &b.iscommonmode, &b.isdefaultmode);
    b.line_number = line_number;
    b.file_index = config_current_file_index();

    var fold_str: Buf = undefined;
    var func_name: Buf = undefined;
    var args: [5]Buf = undefined;
    initArgBufs(&args);

    if (sscanf(
        value,
        "%255[^,],%255[^,],%255[^,],%255[^,],%255[^,],%255[^,],%255[^\n]",
        ptr(&fold_str),
        ptr(&func_name),
        ptr(&args[0]),
        ptr(&args[1]),
        ptr(&args[2]),
        ptr(&args[3]),
        ptr(&args[4]),
    ) < 3) {
        invalidFormat("switchbind", value);
        return -1;
    }
    trim_whitespace(z(&fold_str));
    trim_whitespace(z(&func_name));
    for (&args) |*a| trim_whitespace(z(a));

    b.fold = @bitCast(parse_fold_state(z(&fold_str)));
    b.func = parse_func_name(z(&func_name), &b.arg, z(&args[0]), z(&args[1]), z(&args[2]), z(&args[3]), z(&args[4]));
    if (b.func == null) {
        freeArgStrings(&b.arg);
        unknownDispatch("switchbind", z(&func_name));
        return -1;
    }
    cfg.switch_bindings_count += 1;
    return 1;
}

// ---------------------------------------------------------------------------
// gesturebind
// ---------------------------------------------------------------------------

fn parseGesturebind(cfg: *c.Config, value: [*:0]u8, line_number: c_int) c_int {
    const new_count = @as(usize, @intCast(cfg.gesture_bindings_count)) + 1;
    const raw = realloc(@ptrCast(cfg.gesture_bindings), new_count * @sizeOf(c.GestureBinding)) orelse {
        acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Failed to allocate memory for axis gesturebind\n");
        return -1;
    };
    cfg.gesture_bindings = @ptrCast(@alignCast(raw));

    const b: *c.GestureBinding = @ptrCast(&cfg.gesture_bindings[@intCast(cfg.gesture_bindings_count)]);
    b.* = std.mem.zeroes(c.GestureBinding);
    set_binding_keymode(cfg, &b.mode, &b.iscommonmode, &b.isdefaultmode);
    b.line_number = line_number;
    b.file_index = config_current_file_index();

    var mod_str: Buf = undefined;
    var motion_str: Buf = undefined;
    var fingers_str: Buf = undefined;
    var func_name: Buf = undefined;
    var args: [5]Buf = undefined;
    initArgBufs(&args);

    if (sscanf(
        value,
        "%255[^,],%255[^,],%255[^,],%255[^,],%255[^,],%255[^,],%255[^,],%255[^,],%255[^\n]",
        ptr(&mod_str),
        ptr(&motion_str),
        ptr(&fingers_str),
        ptr(&func_name),
        ptr(&args[0]),
        ptr(&args[1]),
        ptr(&args[2]),
        ptr(&args[3]),
        ptr(&args[4]),
    ) < 4) {
        invalidFormat("gesturebind", value);
        return -1;
    }
    trim_whitespace(z(&mod_str));
    trim_whitespace(z(&motion_str));
    trim_whitespace(z(&fingers_str));
    trim_whitespace(z(&func_name));
    for (&args) |*a| trim_whitespace(z(a));

    b.mod = parse_mod(z(&mod_str));
    b.motion = @bitCast(parse_direction(z(&motion_str)));
    b.fingers_count = @bitCast(atoi(z(&fingers_str)));
    b.func = parse_func_name(z(&func_name), &b.arg, z(&args[0]), z(&args[1]), z(&args[2]), z(&args[3]), z(&args[4]));
    if (b.func == null or b.mod == MAX32) {
        freeArgStrings(&b.arg);
        if (b.func == null)
            unknownDispatch("gesturebind", z(&func_name));
        return -1;
    }
    cfg.gesture_bindings_count += 1;
    return 1;
}

// ---------------------------------------------------------------------------
// C entry
// ---------------------------------------------------------------------------

/// C entry point (tri-state: 1 applied, -1 invalid value, 0 not ours).
export fn acwm_config_apply_bind_option(
    config: ?*c.Config,
    key: [*:0]const u8,
    value: [*:0]u8,
    line_number: c_int,
) callconv(.c) c_int {
    const cfg = config orelse return 0;
    const k = std.mem.span(key);

    if (std.mem.eql(u8, k, "key_mode"))
        return applyKeyMode(cfg, value);
    if (isBindKey(k))
        return parseBind(cfg, key, value, line_number);
    if (std.mem.startsWith(u8, k, "mousebind"))
        return parseMousebind(cfg, value, line_number);
    if (std.mem.startsWith(u8, k, "axisbind"))
        return parseAxisbind(cfg, value, line_number);
    if (std.mem.startsWith(u8, k, "switchbind"))
        return parseSwitchbind(cfg, value, line_number);
    if (std.mem.startsWith(u8, k, "gesturebind"))
        return parseGesturebind(cfg, value, line_number);
    return 0;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: see tests/option_bind_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_last_error: [1024]u8;
extern var stub_error_count: c_int;
extern var stub_bind_calls: c_int;
extern var stub_bind_key: [64]u8;
extern var stub_bind_sym: c_int;
extern var stub_mod_return: u32;
extern var stub_button_return: u32;
extern var stub_direction_return: i32;
extern var stub_fold_return: i32;
extern var stub_key_type: i32;
extern var stub_key_keysym: u32;
extern var stub_key_bindsym: c_int;
extern var stub_key_input: [64]u8;
extern var stub_func_null: c_int;
extern var stub_func_calls: c_int;
extern var stub_func_name: [128]u8;
extern var stub_arg1: [128]u8;
extern var stub_arg2: [128]u8;
extern var stub_file_index: c_int;

fn resetStub() void {
    stub_error_count = 0;
    stub_last_error[0] = 0;
    stub_bind_calls = 0;
    stub_bind_key[0] = 0;
    stub_bind_sym = 0;
    stub_mod_return = 64;
    stub_button_return = 272;
    stub_direction_return = 0;
    stub_fold_return = 1;
    stub_key_type = c.KEY_TYPE_SYM;
    stub_key_keysym = 'q';
    stub_key_bindsym = -1;
    stub_key_input[0] = 0;
    stub_func_null = 0;
    stub_func_calls = 0;
    stub_func_name[0] = 0;
    stub_arg1[0] = 0;
    stub_arg2[0] = 0;
    stub_file_index = -1;
}

fn apply(cfg: *c.Config, key: [*:0]const u8, value: []const u8) c_int {
    var buf: [512:0]u8 = undefined;
    @memcpy(buf[0..value.len], value);
    buf[value.len] = 0;
    return acwm_config_apply_bind_option(cfg, key, &buf, 67);
}

fn lastError() []const u8 {
    return std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&stub_last_error)), 0);
}

fn keyBinding(cfg: *c.Config, i: usize) *c.KeyBinding {
    return @ptrCast(&cfg.key_bindings[i]);
}

fn mouseBinding(cfg: *c.Config, i: usize) *c.MouseBinding {
    return @ptrCast(&cfg.mouse_bindings[i]);
}

fn axisBinding(cfg: *c.Config, i: usize) *c.AxisBinding {
    return @ptrCast(&cfg.axis_bindings[i]);
}

fn switchBinding(cfg: *c.Config, i: usize) *c.SwitchBinding {
    return @ptrCast(&cfg.switch_bindings[i]);
}

fn gestureBinding(cfg: *c.Config, i: usize) *c.GestureBinding {
    return @ptrCast(&cfg.gesture_bindings[i]);
}

fn spanC(p: [*c]const u8) []const u8 {
    return std.mem.span(@as([*:0]const u8, @ptrCast(p)));
}

test "key_mode sets and truncates the mode" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "key_mode", "resize"));
    try testing.expectEqualStrings("resize", std.mem.sliceTo(&config.keymode, 0));

    var long_buf: [41]u8 = undefined;
    @memset(&long_buf, 'a');
    long_buf[40] = 0;
    var val_buf: [41:0]u8 = undefined;
    @memcpy(val_buf[0..41], &long_buf);
    try testing.expectEqual(@as(c_int, 1), acwm_config_apply_bind_option(&config, "key_mode", &val_buf, 0));
    try testing.expectEqual(@as(usize, 27), std.mem.sliceTo(&config.keymode, 0).len);
}

test "bind: appends with mode classification and parse routing" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();
    @memcpy(config.keymode[0..7], "default");

    try testing.expectEqual(@as(c_int, 1), apply(&config, "bind", "SUPER,q,quit"));
    try testing.expectEqual(@as(i32, 1), config.key_bindings_count);
    const b = keyBinding(&config, 0);
    try testing.expectEqual(@as(u32, 64), b.mod);
    try testing.expect(b.func != null);
    try testing.expectEqual(@as(i32, 67), b.line_number);
    try testing.expectEqual(@as(i32, -1), b.file_index);
    try testing.expectEqualStrings("default", std.mem.sliceTo(&b.mode, 0));
    try testing.expect(b.isdefaultmode);
    try testing.expect(!b.iscommonmode);
    try testing.expectEqual(@as(c_int, 1), stub_bind_calls);
    try testing.expectEqualStrings("bind", std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&stub_bind_key)), 0));
    try testing.expectEqualStrings("quit", std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&stub_func_name)), 0));
    // missing args default to "0"
    try testing.expectEqualStrings("0", std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&stub_arg1)), 0));
}

test "bind: arguments are routed to parse_func_name" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "bind", "SUPER,Return,spawn,foot,-e,sh"));
    try testing.expectEqualStrings("spawn", std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&stub_func_name)), 0));
    try testing.expectEqualStrings("foot", std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&stub_arg1)), 0));
    try testing.expectEqualStrings("-e", std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&stub_arg2)), 0));
}

test "bind: binds flag drives parse_key isbindsym" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();
    stub_bind_sym = 1;

    try testing.expectEqual(@as(c_int, 1), apply(&config, "binds", "SUPER,q,quit"));
    try testing.expectEqualStrings("binds", std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&stub_bind_key)), 0));
    try testing.expectEqual(@as(c_int, 1), stub_key_bindsym);
}

test "bind: failure paths do not append" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    // unknown dispatch
    stub_func_null = 1;
    try testing.expectEqual(@as(c_int, -1), apply(&config, "bind", "SUPER,q,bogus"));
    try testing.expectEqual(@as(i32, 0), config.key_bindings_count);
    try testing.expect(std.mem.startsWith(u8, lastError(), "Unknown dispatch in bind: \x1b[1m\x1b[31mbogus"));

    // invalid mod: silent
    resetStub();
    stub_mod_return = std.math.maxInt(u32);
    try testing.expectEqual(@as(c_int, -1), apply(&config, "bind", "BAD,q,quit"));
    try testing.expectEqual(@as(i32, 0), config.key_bindings_count);
    try testing.expectEqual(@as(c_int, 0), stub_error_count);

    // SYM + NoSymbol: silent
    resetStub();
    stub_key_type = c.KEY_TYPE_SYM;
    stub_key_keysym = c.XKB_KEY_NoSymbol;
    try testing.expectEqual(@as(c_int, -1), apply(&config, "bind", "SUPER,nosuchkey,quit"));
    try testing.expectEqual(@as(i32, 0), config.key_bindings_count);
    try testing.expectEqual(@as(c_int, 0), stub_error_count);
}

test "bind key regex matches the C character class (including |)" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    for ([_][*:0]const u8{ "bind", "binds", "bindlr", "bindspc", "bind|" }) |k| {
        resetStub();
        try testing.expectEqual(@as(c_int, 1), apply(&config, k, "SUPER,q,quit"));
    }
    const count_after = config.key_bindings_count;

    for ([_][*:0]const u8{ "bindings", "bindx", "bind_s", "bindsrq" }) |k| {
        try testing.expectEqual(@as(c_int, 0), apply(&config, k, "SUPER,q,quit"));
    }
    try testing.expectEqual(count_after, config.key_bindings_count);
}

test "bind: malformed value is rejected with the C message" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, -1), apply(&config, "bind", "SUPER,q"));
    try testing.expectEqual(@as(i32, 0), config.key_bindings_count);
    try testing.expect(std.mem.startsWith(u8, lastError(), "Invalid bind format: \x1b[1m\x1b[31mSUPER,q"));
}

test "mousebind: mode, button and failure paths" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();
    @memcpy(config.keymode[0..6], "common");

    try testing.expectEqual(@as(c_int, 1), apply(&config, "mousebind", "SUPER,272,close"));
    try testing.expectEqual(@as(i32, 1), config.mouse_bindings_count);
    const b = mouseBinding(&config, 0);
    try testing.expectEqual(@as(u32, 64), b.mod);
    try testing.expectEqual(@as(u32, 272), b.button);
    try testing.expect(b.iscommonmode);
    try testing.expectEqualStrings("common", std.mem.sliceTo(&b.mode, 0));

    // button == UINT32_MAX: silent failure
    resetStub();
    stub_button_return = std.math.maxInt(u32);
    try testing.expectEqual(@as(c_int, -1), apply(&config, "mousebind", "SUPER,999,close"));
    try testing.expectEqual(@as(i32, 1), config.mouse_bindings_count);
    try testing.expectEqual(@as(c_int, 0), stub_error_count);

    // format error
    resetStub();
    try testing.expectEqual(@as(c_int, -1), apply(&config, "mousebind", "SUPER,272"));
    try testing.expect(std.mem.startsWith(u8, lastError(), "Invalid mousebind format: \x1b[1m\x1b[31mSUPER,272"));
}

test "axisbind and switchbind: append and validation" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();
    stub_direction_return = 2;

    try testing.expectEqual(@as(c_int, 1), apply(&config, "axisbind", "SUPER,up,resize"));
    try testing.expectEqual(@as(i32, 1), config.axis_bindings_count);
    try testing.expectEqual(@as(u32, 2), axisBinding(&config, 0).dir);

    resetStub();
    try testing.expectEqual(@as(c_int, 1), apply(&config, "switchbind", "fold,spawn,foo"));
    try testing.expectEqual(@as(i32, 1), config.switch_bindings_count);
    try testing.expectEqual(@as(u32, 1), switchBinding(&config, 0).fold);
    try testing.expectEqualStrings("foo", std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&stub_arg1)), 0));

    // unknown dispatch on switchbind
    resetStub();
    stub_func_null = 1;
    try testing.expectEqual(@as(c_int, -1), apply(&config, "switchbind", "fold,bogus"));
    // note: 2 fields < 3 → format error, not dispatch
    try testing.expect(std.mem.startsWith(u8, lastError(), "Invalid switchbind format:"));

    resetStub();
    stub_func_null = 1;
    try testing.expectEqual(@as(c_int, -1), apply(&config, "switchbind", "fold,bogus,x"));
    try testing.expect(std.mem.startsWith(u8, lastError(), "Unknown dispatch in switchbind: \x1b[1m\x1b[31mbogus"));
}

test "gesturebind: 4-field minimum and append" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();
    stub_direction_return = 1;

    try testing.expectEqual(@as(c_int, 1), apply(&config, "gesturebind", "SUPER,left,3,workspace"));
    try testing.expectEqual(@as(i32, 1), config.gesture_bindings_count);
    const g = gestureBinding(&config, 0);
    try testing.expectEqual(@as(u32, 64), g.mod);
    try testing.expectEqual(@as(u32, 1), g.motion);
    try testing.expectEqual(@as(u32, 3), g.fingers_count);

    // 3 fields is below the gesturebind minimum
    resetStub();
    try testing.expectEqual(@as(c_int, -1), apply(&config, "gesturebind", "SUPER,left,3"));
    try testing.expect(std.mem.startsWith(u8, lastError(), "Invalid gesturebind format:"));
    try testing.expectEqual(@as(i32, 1), config.gesture_bindings_count);
}

test "bind: file index is taken from config_current_file_index" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();
    stub_file_index = 2;

    try testing.expectEqual(@as(c_int, 1), apply(&config, "bind", "SUPER,q,quit"));
    try testing.expectEqual(@as(i32, 2), keyBinding(&config, 0).file_index);
}
