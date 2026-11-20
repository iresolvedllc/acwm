//! Port of src/config/load.c (strangler-fig Phase 4, slice 22).
//!
//! Exports the same C symbols (parse_config_line, parse_config_file,
//! set_default_key_bindings, parse_config, config_get_file_paths,
//! config_current_file_index, config_file_path_at) plus the two data
//! symbols owned by the file (`Config config` and `default_jump_labels`);
//! the C twin is filtered from the compositor link.
//!
//! Behaviour preserved:
//!   - conf line format (key=value, comment stripping, 255-byte value
//!     limit, quote stripping, variable expansion via apply_option_expanded)
//!   - format detection (.toml/.conf extension, else first non-blank char)
//!   - path resolution (./ relative to the CLI config or ~/.config/acwm,
//!     ~/ via $HOME, otherwise as-is)
//!   - file-path table bookkeeping (the path is recorded even when the
//!     file fails to open; recursive saves/restores current_file_index)
//!   - xkb rules wiring, keymap rebuild + binding resolution with the
//!     us-layout fallback and the unresolved-keysym warning
//!   - the 12 CHVT default bindings (common mode, lock apply)
//!   - parse_config pipeline order: store begin, free_config, reset,
//!     keymap, file choice, defaults, parse, resolve, defaults bindings,
//!     overrides, the five conflict checks, store end, nag update
//!
//! Tests live at the bottom and need tests/load_stub.c.

const std = @import("std");
const c = @import("cc");

const WLR_ERROR: c_uint = 1;
const SYSCONFDIR = "/etc";

extern fn acwm_error_impl(
    log: bool,
    verbosity: c_uint,
    file: [*:0]const u8,
    line: c_int,
    fmt: [*:0]const u8,
    ...) callconv(.c) void;
extern fn trim_whitespace(str: ?[*:0]u8) callconv(.c) void;
extern fn strip_quotes(str: ?[*:0]u8) callconv(.c) void;
extern fn remove_comment(str: ?[*:0]u8) callconv(.c) void;
extern fn report_config_line_error(full_path: [*:0]const u8, line_number: c_int, line: [*:0]const u8) callconv(.c) void;
extern fn apply_option_expanded(config: *c.Config, key: [*:0]u8, value: [*:0]u8, line_number: c_int) callconv(.c) bool;
extern fn free_config() callconv(.c) void;
extern fn set_value_default() callconv(.c) void;
extern fn override_config() callconv(.c) void;
extern fn create_config_keymap() callconv(.c) void;
extern fn find_keycodes_for_keysym(keymap: ?*c.struct_xkb_keymap, sym: c.xkb_keysym_t, multi_kc: *c.MultiKeycode) callconv(.c) i32;
extern fn parse_toml_stream(config: *c.Config, file: ?*c.FILE, full_path: [*:0]const u8) callconv(.c) bool;
extern fn check_key_binding_conflicts(config: *c.Config) callconv(.c) bool;
extern fn check_mouse_binding_conflicts(config: *c.Config) callconv(.c) bool;
extern fn check_axis_binding_conflicts(config: *c.Config) callconv(.c) bool;
extern fn check_switch_binding_conflicts(config: *c.Config) callconv(.c) bool;
extern fn check_gesture_binding_conflicts(config: *c.Config) callconv(.c) bool;
extern fn config_error_store_begin() callconv(.c) void;
extern fn config_error_store_end() callconv(.c) void;
extern fn config_error_nag_update() callconv(.c) void;

extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*c.FILE;
extern "c" fn fclose(f: ?*c.FILE) c_int;
extern "c" fn fgets(buf: [*]u8, n: c_int, f: ?*c.FILE) ?[*:0]u8;
extern "c" fn fgetc(f: ?*c.FILE) c_int;
extern "c" fn ungetc(ch: c_int, f: ?*c.FILE) c_int;
extern "c" fn sscanf(str: [*:0]const u8, fmt: [*:0]const u8, ...) c_int;
extern "c" fn snprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ...) c_int;
extern "c" fn strchr(s: [*:0]const u8, ch: c_int) ?[*:0]u8;
extern "c" fn strrchr(s: [*:0]const u8, ch: c_int) ?[*:0]u8;
extern "c" fn strcspn(s: [*:0]const u8, reject: [*:0]const u8) usize;
extern "c" fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern "c" fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn getenv(name: [*:0]const u8) ?[*:0]u8;
extern "c" fn access(path: [*:0]const u8, mode: c_int) c_int;
extern "c" fn dirname(path: [*:0]u8) ?[*:0]u8;

// ---------------------------------------------------------------------------
// data symbols owned by load.c
// ---------------------------------------------------------------------------

export var config: c.Config = std.mem.zeroes(c.Config);

/// Default jump-label character sequence (26 chars + NUL, matching the C
/// char array size).
export var default_jump_labels: [26:0]u8 = "HJKLASDFGQWERTYUIOPZXCVBNM".*;

var file_paths: ?[*]?[*:0]u8 = null;
var file_paths_count: c_int = 0;
var current_file_index: c_int = -1;

const MOD_CTRL: u32 = @intCast(c.WLR_MODIFIER_CTRL);
const MOD_ALT: u32 = @intCast(c.WLR_MODIFIER_ALT);

// XKB_KEY_XF86Switch_VT_1 .. _12
const VT_SYMS = [12]c.xkb_keysym_t{
    @intCast(c.XKB_KEY_XF86Switch_VT_1),
    @intCast(c.XKB_KEY_XF86Switch_VT_2),
    @intCast(c.XKB_KEY_XF86Switch_VT_3),
    @intCast(c.XKB_KEY_XF86Switch_VT_4),
    @intCast(c.XKB_KEY_XF86Switch_VT_5),
    @intCast(c.XKB_KEY_XF86Switch_VT_6),
    @intCast(c.XKB_KEY_XF86Switch_VT_7),
    @intCast(c.XKB_KEY_XF86Switch_VT_8),
    @intCast(c.XKB_KEY_XF86Switch_VT_9),
    @intCast(c.XKB_KEY_XF86Switch_VT_10),
    @intCast(c.XKB_KEY_XF86Switch_VT_11),
    @intCast(c.XKB_KEY_XF86Switch_VT_12),
};

// ---------------------------------------------------------------------------
// line/stream parsing
// ---------------------------------------------------------------------------

export fn parse_config_line(config_arg: *c.Config, line: [*:0]const u8, line_number: c_int) callconv(.c) bool {
    var processed_line: [512]u8 = undefined;
    _ = snprintf(&processed_line, processed_line.len, "%s", line);
    remove_comment(@ptrCast(&processed_line));

    var key: [256]u8 = undefined;
    var value: [256]u8 = undefined;
    if (sscanf(
        @ptrCast(&processed_line),
        "%255[^=]=%255[^\n]",
        @as([*]u8, @ptrCast(&key)),
        @as([*]u8, @ptrCast(&value)),
    ) != 2) {
        acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Invalid line format: \x1b[1m\x1b[31m%s\x1b[0m\n", line);
        return false;
    }

    const equals = strchr(@ptrCast(&processed_line), '=');
    if (equals != null and strcspn(equals.? + 1, "\n") >= value.len) {
        acwm_error_impl(
            false,
            WLR_ERROR,
            @src().file,
            @src().line,
            "Configuration value exceeds %zu bytes: \x1b[1m\x1b[31m%s\x1b[0m\n",
            @as(usize, value.len - 1),
            line,
        );
        return false;
    }

    trim_whitespace(@ptrCast(&key));
    trim_whitespace(@ptrCast(&value));
    strip_quotes(@ptrCast(&value));

    return apply_option_expanded(config_arg, @ptrCast(&key), @ptrCast(&value), line_number);
}

fn parseConfStream(config_arg: *c.Config, file: ?*c.FILE, full_path: [*:0]const u8) bool {
    var line: [512]u8 = undefined;
    var parse_correct = true;
    var line_count: c_int = 0;

    while (fgets(&line, line.len, file) != null) {
        line_count += 1;
        if (line[0] == '#' or line[0] == '\n')
            continue;

        if (!parse_config_line(config_arg, @ptrCast(&line), line_count)) {
            parse_correct = false;
            report_config_line_error(full_path, line_count, @ptrCast(&line));
        }
    }
    return parse_correct;
}

fn detectConfigFormat(full_path: [*:0]const u8, file: ?*c.FILE) c.ConfigFileFormat {
    const dot = strrchr(full_path, '.');
    if (dot != null) {
        const ext = std.mem.span(@as([*:0]const u8, @ptrCast(dot.?)));
        if (std.ascii.eqlIgnoreCase(ext, ".toml"))
            return c.CONFIG_FORMAT_TOML;
        if (std.ascii.eqlIgnoreCase(ext, ".conf"))
            return c.CONFIG_FORMAT_CONF;
    }

    while (true) {
        var ch = fgetc(file);
        if (ch == c.EOF)
            break;
        if (ch == '#') {
            while (true) {
                ch = fgetc(file);
                if (ch == c.EOF or ch == '\n')
                    break;
            }
            continue;
        }
        if (std.ascii.isWhitespace(@intCast(ch)))
            continue;
        _ = ungetc(ch, file);
        return if (ch == '[') c.CONFIG_FORMAT_TOML else c.CONFIG_FORMAT_CONF;
    }
    return c.CONFIG_FORMAT_CONF;
}

fn resolveConfigPath(file_path: [*:0]const u8, full_path: [*]u8, size: usize) bool {
    const fp = std.mem.span(file_path);

    if (fp.len >= 2 and fp[0] == '.' and fp[1] == '/') {
        const rel = file_path + 2;
        if (c.server.cli_config_path[0] != 0) {
            const config_path = strdup(@ptrCast(&c.server.cli_config_path)) orelse return false;
            const config_dir = dirname(config_path);
            _ = snprintf(full_path, size, "%s/%s", config_dir, rel);
            free(@ptrCast(config_path));
        } else {
            const home = getenv("HOME") orelse {
                acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "HOME environment variable not set.\n");
                return false;
            };
            _ = snprintf(full_path, size, "%s/.config/acwm/%s", home, rel);
        }
    } else if (fp.len >= 1 and fp[0] == '~' and (fp.len == 1 or fp[1] == '/')) {
        const home = getenv("HOME") orelse {
            acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "HOME environment variable not set.\n");
            return false;
        };
        _ = snprintf(full_path, size, "%s%s", home, file_path + 1);
    } else {
        _ = snprintf(full_path, size, "%s", file_path);
    }
    return true;
}

export fn parse_config_file(config_arg: *c.Config, file_path: [*:0]const u8, must_exist: bool) callconv(.c) bool {
    var full_path: [1024]u8 = undefined;
    if (!resolveConfigPath(file_path, &full_path, full_path.len))
        return false;

    const file = fopen(@ptrCast(&full_path), "r");

    // Saves the current file index to restore after recursion.
    const saved_file_index = current_file_index;

    // Adds the file path to the global list (even when the open fails).
    const raw = realloc(
        @ptrCast(file_paths),
        (@as(usize, @intCast(file_paths_count)) + 1) * @sizeOf(?[*:0]u8),
    ) orelse return false;
    file_paths = @ptrCast(@alignCast(raw));
    file_paths.?[@intCast(file_paths_count)] = strdup(@ptrCast(&full_path));
    current_file_index = file_paths_count;
    file_paths_count += 1;

    if (file == null) {
        current_file_index = saved_file_index;
        if (must_exist) {
            acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Failed to open config file: \x1b[1m\x1b[31m%s\x1b[0m\n", file_path);
            return false;
        }
        return true;
    }

    const format = detectConfigFormat(@ptrCast(&full_path), file);
    const parse_correct = if (format == c.CONFIG_FORMAT_TOML)
        parse_toml_stream(config_arg, file, @ptrCast(&full_path))
    else
        parseConfStream(config_arg, file, @ptrCast(&full_path));

    _ = fclose(file);
    current_file_index = saved_file_index;
    return parse_correct;
}

// ---------------------------------------------------------------------------
// binding layout resolution
// ---------------------------------------------------------------------------

fn resolveKeybindingLayout(keymap: ?*c.struct_xkb_keymap, binding: *c.KeyBinding) void {
    if (binding.keysymcode.keysym == c.XKB_KEY_NoSymbol)
        return;
    if (binding.keysymcode.type != c.KEY_TYPE_CODE and !binding.keysymcode.unresolved)
        return;

    var keycode = std.mem.zeroes(c.MultiKeycode);
    if (find_keycodes_for_keysym(keymap, binding.keysymcode.keysym, &keycode) > 0) {
        binding.keysymcode.keycode = keycode;
        binding.keysymcode.type = c.KEY_TYPE_CODE;
        binding.keysymcode.unresolved = false;
        return;
    }

    if (!binding.keysymcode.unresolved)
        return;

    var name: [64]u8 = std.mem.zeroes([64]u8);
    _ = c.xkb_keysym_get_name(binding.keysymcode.keysym, &name, name.len);
    acwm_error_impl(
        false,
        WLR_ERROR,
        @src().file,
        @src().line,
        "Key '\x1b[1m\x1b[31m%s\x1b[0m' has no keycode in the configured layouts; it is matched by keysym, which depends on the active layout\n",
        @as([*:0]const u8, @ptrCast(&name)),
    );
}

fn resolveBindingsToConfiguredLayouts(config_arg: *c.Config) void {
    if (config_arg.keymap != null) {
        c.xkb_keymap_unref(config_arg.keymap);
        config_arg.keymap = null;
    }

    if (config_arg.ctx != null) {
        config_arg.keymap = c.xkb_keymap_new_from_names(
            config_arg.ctx,
            &config_arg.xkb_rules,
            c.XKB_KEYMAP_COMPILE_NO_FLAGS,
        );
    }

    if (config_arg.keymap == null) {
        acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Invalid xkb_rules_* layout; key names are resolved with the us layout\n");
        if (config_arg.ctx != null) {
            config_arg.keymap = c.xkb_keymap_new_from_names(
                config_arg.ctx,
                &c.xkb_fallback_rules,
                c.XKB_KEYMAP_COMPILE_NO_FLAGS,
            );
        }
    }

    var i: usize = 0;
    while (i < @as(usize, @intCast(config_arg.key_bindings_count))) : (i += 1) {
        resolveKeybindingLayout(config_arg.keymap, @ptrCast(&config_arg.key_bindings[i]));
    }

    i = 0;
    while (i < @as(usize, @intCast(config_arg.window_rules_count))) : (i += 1) {
        const rule = &config_arg.window_rules[i];
        if (rule.globalkeybinding.mod != 0)
            resolveKeybindingLayout(config_arg.keymap, @ptrCast(&rule.globalkeybinding));
    }
}

// ---------------------------------------------------------------------------
// default CHVT bindings
// ---------------------------------------------------------------------------

export fn set_default_key_bindings(config_arg: *c.Config) callconv(.c) void {
    const count: usize = 12;
    const new_count = @as(usize, @intCast(config_arg.key_bindings_count)) + count;
    const raw = realloc(@ptrCast(config_arg.key_bindings), new_count * @sizeOf(c.KeyBinding)) orelse return;
    config_arg.key_bindings = @ptrCast(@alignCast(raw));

    const change_vt = @extern(c.FuncType, .{ .name = "change_vt" });

    var i: usize = 0;
    while (i < count) : (i += 1) {
        const b: *c.KeyBinding = @ptrCast(&config_arg.key_bindings[@intCast(config_arg.key_bindings_count + @as(c_int, @intCast(i)))]);
        b.* = std.mem.zeroes(c.KeyBinding);
        b.mod = MOD_CTRL | MOD_ALT;
        b.keysymcode.keysym = VT_SYMS[i];
        b.keysymcode.type = c.KEY_TYPE_SYM;
        b.func = change_vt;
        b.arg.ui = @intCast(i + 1);
        b.iscommonmode = true;
        b.islockapply = true;
        b.line_number = 0;
        _ = snprintf(&b.mode, b.mode.len, "common");
    }

    config_arg.key_bindings_count += @intCast(count);
}

// ---------------------------------------------------------------------------
// parse_config pipeline
// ---------------------------------------------------------------------------

export fn parse_config() callconv(.c) bool {
    var filename: [1024]u8 = undefined;

    config_error_store_begin();

    if (file_paths != null) {
        var i: usize = 0;
        while (i < @as(usize, @intCast(file_paths_count))) : (i += 1) {
            free(@ptrCast(file_paths.?[i]));
        }
        free(@ptrCast(file_paths));
        file_paths = null;
        file_paths_count = 0;
    }

    free_config();

    c.config = std.mem.zeroes(c.Config);

    // Points the xkb_rules pointers back to the static arrays.
    c.config.xkb_rules.layout = @ptrCast(&c.config.xkb_rules_layout);
    c.config.xkb_rules.variant = @ptrCast(&c.config.xkb_rules_variant);
    c.config.xkb_rules.options = @ptrCast(&c.config.xkb_rules_options);
    c.config.xkb_rules.rules = @ptrCast(&c.config.xkb_rules_rules);
    c.config.xkb_rules.model = @ptrCast(&c.config.xkb_rules_model);

    _ = snprintf(&c.config.keymode, c.config.keymode.len, "default");

    create_config_keymap();

    if (c.server.cli_config_path[0] != 0) {
        _ = snprintf(&filename, filename.len, "%s", @as([*:0]const u8, @ptrCast(&c.server.cli_config_path)));
    } else {
        const homedir = getenv("HOME") orelse {
            config_error_store_end();
            return false;
        };
        _ = snprintf(&filename, filename.len, "%s/.config/acwm/config.conf", homedir);
        if (access(@ptrCast(&filename), 0) != 0) {
            _ = snprintf(&filename, filename.len, "%s/.config/acwm/config.toml", homedir);
        }
        if (access(@ptrCast(&filename), 0) != 0) {
            _ = snprintf(&filename, filename.len, "%s/acwm/config.conf", SYSCONFDIR);
            if (access(@ptrCast(&filename), 0) != 0) {
                _ = snprintf(&filename, filename.len, "%s/acwm/config.toml", SYSCONFDIR);
            }
        }
    }

    set_value_default();
    const parse_correct = parse_config_file(&c.config, @ptrCast(&filename), true);
    resolveBindingsToConfiguredLayouts(&c.config);
    set_default_key_bindings(&c.config);
    override_config();

    var keybindings_conflict = check_key_binding_conflicts(&c.config);
    keybindings_conflict = check_mouse_binding_conflicts(&c.config) or keybindings_conflict;
    keybindings_conflict = check_axis_binding_conflicts(&c.config) or keybindings_conflict;
    keybindings_conflict = check_switch_binding_conflicts(&c.config) or keybindings_conflict;
    keybindings_conflict = check_gesture_binding_conflicts(&c.config) or keybindings_conflict;

    const result = parse_correct and !keybindings_conflict;
    config_error_store_end();
    config_error_nag_update();
    return result;
}

// ---------------------------------------------------------------------------
// file path accessors
// ---------------------------------------------------------------------------

export fn config_get_file_paths(count: ?*c_int) callconv(.c) [*c][*c]u8 {
    if (count) |n|
        n.* = file_paths_count;
    return @ptrCast(file_paths);
}

export fn config_current_file_index() callconv(.c) c_int {
    return current_file_index;
}

export fn config_file_path_at(index: c_int) callconv(.c) [*c]const u8 {
    if (index < 0 or index >= file_paths_count)
        return null;
    return @ptrCast(file_paths.?[@intCast(index)]);
}

// ---------------------------------------------------------------------------
// tests (stub-backed: see tests/load_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_last_error: [1024]u8;
extern var stub_error_count: c_int;
extern var stub_free_config_calls: c_int;
extern var stub_set_default_calls: c_int;
extern var stub_override_calls: c_int;
extern var stub_create_keymap_calls: c_int;
extern var stub_store_begin_calls: c_int;
extern var stub_store_end_calls: c_int;
extern var stub_nag_update_calls: c_int;
extern var stub_conflict_calls: c_int;
extern var stub_conflict_result: c_int;
extern var stub_toml_calls: c_int;
extern var stub_toml_result: c_int;
extern var stub_apply_key: [128]u8;
extern var stub_apply_value: [256]u8;
extern var stub_apply_calls: c_int;
extern var stub_apply_result: c_int;
extern var stub_report_path: [256]u8;
extern var stub_report_line: c_int;
extern var stub_report_calls: c_int;
extern var stub_find_count: c_int;
extern var stub_find_keycode: u32;
extern var stub_keymap_new: ?*c.struct_xkb_keymap;
extern var stub_keymap_unref_calls: c_int;
extern var stub_keysym_name: [64]u8;

extern "c" fn fputs(s: [*:0]const u8, f: ?*c.FILE) c_int;
extern "c" fn unlink(path: [*:0]const u8) c_int;
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;

fn resetStub() void {
    stub_error_count = 0;
    stub_last_error[0] = 0;
    stub_free_config_calls = 0;
    stub_set_default_calls = 0;
    stub_override_calls = 0;
    stub_create_keymap_calls = 0;
    stub_store_begin_calls = 0;
    stub_store_end_calls = 0;
    stub_nag_update_calls = 0;
    stub_conflict_calls = 0;
    stub_conflict_result = 0;
    stub_toml_calls = 0;
    stub_toml_result = 1;
    stub_apply_key[0] = 0;
    stub_apply_value[0] = 0;
    stub_apply_calls = 0;
    stub_apply_result = 1;
    stub_report_path[0] = 0;
    stub_report_line = 0;
    stub_report_calls = 0;
    stub_find_count = 0;
    stub_find_keycode = 7;
    stub_keymap_new = @ptrFromInt(@alignOf(usize));
    stub_keymap_unref_calls = 0;
    @memcpy(stub_keysym_name[0..3], "key");
    stub_keysym_name[3] = 0;
}

fn writeTemp(comptime path: [:0]const u8, content: []const u8) void {
    const file = fopen(path, "w").?;
    for (content) |ch| {
        const b = [2]u8{ ch, 0 };
        _ = fputs(@ptrCast(&b), file);
    }
    _ = fclose(file);
}

fn span(p: [*]const u8) []const u8 {
    return std.mem.sliceTo(@as([*:0]const u8, @ptrCast(p)), 0);
}

fn setStr(dst: []u8, src: []const u8) void {
    @memcpy(dst[0..src.len], src);
    dst[src.len] = 0;
}

test "parse_config_line splits, strips and applies" {
    resetStub();
    var line: [64:0]u8 = undefined;
    setStr(&line, "idle_after = 60 #x");

    try testing.expect(parse_config_line(&c.config, &line, 4));
    try testing.expectEqual(@as(c_int, 1), stub_apply_calls);
    try testing.expectEqualStrings("idle_after", span(&stub_apply_key));
    try testing.expectEqualStrings("60", span(&stub_apply_value));

    // quoted value
    resetStub();
    var quoted: [64:0]u8 = undefined;
    setStr(&quoted, "bar_clock_format=\"%H:%M\"");
    try testing.expect(parse_config_line(&c.config, &quoted, 5));
    try testing.expectEqualStrings("%H:%M", span(&stub_apply_value));

    // invalid line (no '=')
    resetStub();
    try testing.expect(!parse_config_line(&c.config, "no equals here", 6));
    try testing.expectEqual(@as(c_int, 1), stub_error_count);
    try testing.expect(std.mem.startsWith(u8, span(&stub_last_error), "Invalid line format:"));

    // oversized value
    resetStub();
    var big: [400:0]u8 = undefined;
    setStr(&big, "key=");
    @memset(big[4..304], 'a');
    big[304] = 0;
    try testing.expect(!parse_config_line(&c.config, &big, 7));
    try testing.expect(std.mem.startsWith(u8, span(&stub_last_error), "Configuration value exceeds 255 bytes:"));
}

test "format detection by extension and content" {
    writeTemp("/tmp/opencode/acwm-load-detect.toml", "[section]\n");
    defer _ = unlink("/tmp/opencode/acwm-load-detect.toml");
    writeTemp("/tmp/opencode/acwm-load-detect.conf", "idle_after=1\n");
    defer _ = unlink("/tmp/opencode/acwm-load-detect.conf");
    writeTemp("/tmp/opencode/acwm-load-detect", "\n# comment\n[key]\n");
    defer _ = unlink("/tmp/opencode/acwm-load-detect");
    writeTemp("/tmp/opencode/acwm-load-detect2", "key=value\n");
    defer _ = unlink("/tmp/opencode/acwm-load-detect2");

    const f1 = fopen("/tmp/opencode/acwm-load-detect.toml", "r").?;
    try testing.expectEqual(@as(c_uint, @intCast(c.CONFIG_FORMAT_TOML)), detectConfigFormat("/tmp/opencode/acwm-load-detect.toml", f1));
    _ = fclose(f1);

    const f2 = fopen("/tmp/opencode/acwm-load-detect.conf", "r").?;
    try testing.expectEqual(@as(c_uint, @intCast(c.CONFIG_FORMAT_CONF)), detectConfigFormat("/tmp/opencode/acwm-load-detect.conf", f2));
    _ = fclose(f2);

    const f3 = fopen("/tmp/opencode/acwm-load-detect", "r").?;
    try testing.expectEqual(@as(c_uint, @intCast(c.CONFIG_FORMAT_TOML)), detectConfigFormat("/tmp/opencode/acwm-load-detect", f3));
    _ = fclose(f3);

    const f4 = fopen("/tmp/opencode/acwm-load-detect2", "r").?;
    try testing.expectEqual(@as(c_uint, @intCast(c.CONFIG_FORMAT_CONF)), detectConfigFormat("/tmp/opencode/acwm-load-detect2", f4));
    _ = fclose(f4);
}

test "path resolution: relative, tilde and absolute" {
    resetStub();
    _ = setenv("HOME", "/home/tester", 1);

    var out: [1024]u8 = undefined;
    c.server.cli_config_path[0] = 0;

    // ./ relative to ~/.config/acwm
    try testing.expect(resolveConfigPath("./extra.conf", &out, out.len));
    try testing.expectEqualStrings("/home/tester/.config/acwm/extra.conf", span(&out));

    // ./ relative to the CLI config directory
    setStr(&c.server.cli_config_path, "/etc/acwm/main.conf");
    try testing.expect(resolveConfigPath("./extra.conf", &out, out.len));
    try testing.expectEqualStrings("/etc/acwm/extra.conf", span(&out));
    c.server.cli_config_path[0] = 0;

    // ~/ expansion
    try testing.expect(resolveConfigPath("~/x.conf", &out, out.len));
    try testing.expectEqualStrings("/home/tester/x.conf", span(&out));

    // absolute path passes through
    try testing.expect(resolveConfigPath("/tmp/abs.conf", &out, out.len));
    try testing.expectEqualStrings("/tmp/abs.conf", span(&out));
}

test "parse_config_file records paths, reports failures and restores the index" {
    resetStub();
    c.server.cli_config_path[0] = 0;

    writeTemp("/tmp/opencode/acwm-load-file.conf", "idle_after=5\n");
    defer _ = unlink("/tmp/opencode/acwm-load-file.conf");

    try testing.expect(parse_config_file(&c.config, "/tmp/opencode/acwm-load-file.conf", false));
    try testing.expectEqual(@as(c_int, 1), stub_apply_calls);
    try testing.expectEqualStrings("idle_after", span(&stub_apply_key));

    var count: c_int = 0;
    const paths = config_get_file_paths(&count);
    try testing.expectEqual(@as(c_int, 1), count);
    try testing.expectEqualStrings("/tmp/opencode/acwm-load-file.conf", span(@ptrCast(paths[0])));
    try testing.expectEqualStrings("/tmp/opencode/acwm-load-file.conf", span(config_file_path_at(0)));
    try testing.expectEqual(@as(c_int, -1), config_current_file_index()); // restored
    try testing.expect(config_file_path_at(1) == null);
    try testing.expect(config_file_path_at(-1) == null);

    // missing file with must_exist=false: recorded, returns true
    try testing.expect(parse_config_file(&c.config, "/tmp/opencode/acwm-load-missing.conf", false));
    _ = config_get_file_paths(&count);
    try testing.expectEqual(@as(c_int, 2), count);

    // missing file with must_exist=true: recorded, returns false, reports
    resetStub();
    try testing.expect(!parse_config_file(&c.config, "/tmp/opencode/acwm-load-missing.conf", true));
    _ = config_get_file_paths(&count);
    try testing.expectEqual(@as(c_int, 3), count);
    try testing.expect(std.mem.startsWith(u8, span(&stub_last_error), "Failed to open config file:"));
}

test "default bindings append 12 CHVT entries in common mode" {
    resetStub();
    var cfg: c.Config = std.mem.zeroes(c.Config);

    set_default_key_bindings(&cfg);
    try testing.expectEqual(@as(i32, 12), cfg.key_bindings_count);

    var i: usize = 0;
    while (i < 12) : (i += 1) {
        const b: *c.KeyBinding = @ptrCast(&cfg.key_bindings[i]);
        try testing.expectEqual(MOD_CTRL | MOD_ALT, b.mod);
        try testing.expectEqual(VT_SYMS[i], b.keysymcode.keysym);
        try testing.expectEqual(@as(c_int, c.KEY_TYPE_SYM), b.keysymcode.type);
        try testing.expect(b.func != null);
        try testing.expectEqual(@as(u32, @intCast(i + 1)), b.arg.ui);
        try testing.expect(b.iscommonmode);
        try testing.expect(b.islockapply);
        try testing.expectEqual(@as(c_int, 0), b.line_number);
        try testing.expectEqualStrings("common", std.mem.sliceTo(&b.mode, 0));
    }

    // appending again stacks another 12
    set_default_key_bindings(&cfg);
    try testing.expectEqual(@as(i32, 24), cfg.key_bindings_count);
}

test "parse_config runs the pipeline in order" {
    resetStub();
    writeTemp("/tmp/opencode/acwm-load-main.conf", "idle_after=60\n");
    defer _ = unlink("/tmp/opencode/acwm-load-main.conf");

    setStr(&c.server.cli_config_path, "/tmp/opencode/acwm-load-main.conf");

    try testing.expect(parse_config());

    try testing.expectEqual(@as(c_int, 1), stub_store_begin_calls);
    try testing.expectEqual(@as(c_int, 1), stub_store_end_calls);
    try testing.expectEqual(@as(c_int, 1), stub_free_config_calls);
    try testing.expectEqual(@as(c_int, 1), stub_set_default_calls);
    try testing.expectEqual(@as(c_int, 1), stub_override_calls);
    try testing.expectEqual(@as(c_int, 1), stub_create_keymap_calls);
    try testing.expectEqual(@as(c_int, 5), stub_conflict_calls);
    try testing.expectEqual(@as(c_int, 1), stub_nag_update_calls);
    try testing.expectEqual(@as(c_int, 1), stub_apply_calls);
    try testing.expectEqualStrings("idle_after", span(&stub_apply_key));
    try testing.expectEqualStrings("60", span(&stub_apply_value));
    try testing.expectEqualStrings("default", std.mem.sliceTo(&c.config.keymode, 0));

    var count: c_int = 0;
    _ = config_get_file_paths(&count);
    try testing.expectEqual(@as(c_int, 1), count);
    try testing.expectEqualStrings("/tmp/opencode/acwm-load-main.conf", span(config_file_path_at(0)));

    // defaults were appended and the xkb rules pointers are wired
    try testing.expectEqual(@as(i32, 12), c.config.key_bindings_count);
    try testing.expectEqual(@as([*c]const u8, @ptrCast(&c.config.xkb_rules_layout)), c.config.xkb_rules.layout);
    try testing.expectEqual(@as([*c]const u8, @ptrCast(&c.config.xkb_rules_model)), c.config.xkb_rules.model);

    // a reported conflict turns the result false
    resetStub();
    stub_conflict_result = 1;
    try testing.expect(!parse_config());
    try testing.expectEqual(@as(c_int, 5), stub_conflict_calls);

    // a failed option parse does too
    resetStub();
    stub_apply_result = 0;
    try testing.expect(!parse_config());
}

test "parse_config fails cleanly without a config path or HOME" {
    resetStub();
    c.server.cli_config_path[0] = 0;
    _ = unsetenv("HOME");

    try testing.expect(!parse_config());
    try testing.expectEqual(@as(c_int, 1), stub_store_begin_calls);
    try testing.expectEqual(@as(c_int, 1), stub_store_end_calls);
    // the keymap is created before the HOME check (C order)
    try testing.expectEqual(@as(c_int, 1), stub_create_keymap_calls);
    _ = setenv("HOME", "/home/tester", 1);
}
