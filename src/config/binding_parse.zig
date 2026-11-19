//! Port of src/config/binding_parse.c (strangler-fig Phase 4, slice 21).
//!
//! Exports the same 12 C symbols; the C twin is filtered from the composer
//! link. Covers keymap lifecycle (create/cleanup + a lazily built reference
//! keymap), bind-flag parsing, modifier parsing (names and raw keycodes),
//! keysym/keycode resolution against the xkb keymap, button and
//! mouse-action parsing, comma argument combination and the 93-entry
//! parse_func_name dispatch table.
//!
//! Dispatch handlers are resolved at comptime with @extern, so no per
//! function declarations are needed and the Zig name table stays checkable
//! against the C source. All C quirks are preserved: "code:"-prefixed mods,
//! strtok_r on '+', the case-insensitive key names, unresolved keysym
//! bookkeeping, the initialised-to-"0" argument placeholders (including
//! setoption's literal \"0\" concatenation) and the uint32 cast of
//! xkb keycodes.
//!
//! Tests live at the bottom and need tests/binding_parse_stub.c (xkb + list
//! of dispatch handlers + trim).

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
/// value_parse twins in the compositor link; stubbed in tests.
extern fn trim_whitespace(str: ?[*:0]u8) callconv(.c) void;
extern fn parse_direction(str: [*:0]const u8) callconv(.c) i32;
extern fn parse_circle_direction(str: [*:0]const u8) callconv(.c) i32;
extern fn parse_overcircle_direction(str: [*:0]const u8) callconv(.c) i32;
extern fn parse_force(str: [*:0]const u8) callconv(.c) i32;
extern fn parse_tag_mask(str: [*:0]u8) callconv(.c) u32;
extern fn parse_num_type(str: [*:0]u8) callconv(.c) u32;
extern fn parse_monitor_arg(str: [*:0]const u8) callconv(.c) i32;

extern "c" fn atoi(nptr: [*:0]const u8) c_int;
extern "c" fn atof(nptr: [*:0]const u8) f64;
extern "c" fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern "c" fn malloc(size: usize) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn strlen(s: [*:0]const u8) usize;
extern "c" fn strcmp(a: [*:0]const u8, b: [*:0]const u8) c_int;
extern "c" fn strncmp(a: [*:0]const u8, b: [*:0]const u8, n: usize) c_int;
extern "c" fn memcpy(dest: [*]u8, src: [*]const u8, n: usize) [*]u8;
extern "c" fn snprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ...) c_int;
extern "c" fn strtol(nptr: [*:0]const u8, endptr: *?[*:0]u8, base: c_int) c_long;
extern "c" fn strtoul(nptr: [*:0]const u8, endptr: *?[*:0]u8, base: c_int) c_ulong;
extern "c" fn strtok_r(str: ?[*:0]u8, delim: [*:0]const u8, saveptr: *?[*:0]u8) ?[*:0]u8;

// ---------------------------------------------------------------------------
// keymap lifecycle
// ---------------------------------------------------------------------------

var reference_keymap_instance: ?*c.struct_xkb_keymap = null;

fn referenceKeymap() ?*c.struct_xkb_keymap {
    if (reference_keymap_instance == null and c.config.ctx != null) {
        reference_keymap_instance = c.xkb_keymap_new_from_names(
            c.config.ctx,
            &c.xkb_fallback_rules,
            c.XKB_KEYMAP_COMPILE_NO_FLAGS,
        );
    }
    return reference_keymap_instance;
}

export fn cleanup_config_keymap() callconv(.c) void {
    if (c.config.keymap != null) {
        c.xkb_keymap_unref(c.config.keymap);
        c.config.keymap = null;
    }
    if (reference_keymap_instance != null) {
        c.xkb_keymap_unref(reference_keymap_instance);
        reference_keymap_instance = null;
    }
    if (c.config.ctx != null) {
        c.xkb_context_unref(c.config.ctx);
        c.config.ctx = null;
    }
}

export fn create_config_keymap() callconv(.c) void {
    if (c.config.ctx == null)
        c.config.ctx = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS);
    if (c.config.keymap == null) {
        c.config.keymap = c.xkb_keymap_new_from_names(
            c.config.ctx,
            &c.xkb_fallback_rules,
            c.XKB_KEYMAP_COMPILE_NO_FLAGS,
        );
    }
}

// ---------------------------------------------------------------------------
// bind flags / keymode
// ---------------------------------------------------------------------------

/// Parses the bind combination string (bind[s|l|r|p|c] suffixes).
export fn parse_bind_flags(str: [*:0]const u8, kb: *c.KeyBinding) callconv(.c) void {
    if (strncmp(str, "bind", 4) != 0)
        return;

    var i: usize = 4;
    while (str[i] != 0) : (i += 1) {
        switch (str[i]) {
            's' => kb.keysymcode.type = c.KEY_TYPE_SYM,
            'l' => kb.islockapply = true,
            'r' => kb.isreleaseapply = true,
            'p' => kb.ispassapply = true,
            'c' => kb.isallowconflict = true,
            else => acwm_error_impl(
                false,
                WLR_ERROR,
                @src().file,
                @src().line,
                "Unknown bind flag: \x1b[1m\x1b[31m%c\x1b[0m\n",
                @as(c_int, str[i]),
            ),
        }
    }
}

export fn set_binding_keymode(config: *c.Config, mode: [*]u8, iscommonmode: *bool, isdefaultmode: *bool) callconv(.c) void {
    // strcpy(mode, config->keymode) — keymode is a char[28] with guaranteed NUL.
    const src: [*:0]const u8 = @ptrCast(&config.keymode);
    _ = snprintf(mode, 28, "%s", src);
    const mode_z: [*:0]const u8 = @ptrCast(mode);
    if (strcmp(mode_z, "common") == 0) {
        iscommonmode.* = true;
        isdefaultmode.* = false;
    } else if (strcmp(mode_z, "default") == 0) {
        isdefaultmode.* = true;
        iscommonmode.* = false;
    } else {
        isdefaultmode.* = false;
        iscommonmode.* = false;
    }
}

// ---------------------------------------------------------------------------
// parse_mod
// ---------------------------------------------------------------------------

export fn parse_mod(mod_str: [*:0]const u8) callconv(.c) u32 {
    if (mod_str[0] == 0)
        return std.math.maxInt(u32);

    var input_copy: [256]u8 = undefined;
    _ = snprintf(&input_copy, input_copy.len, "%s", mod_str);
    for (&input_copy) |*ch| {
        if (ch.* == 0)
            break;
        ch.* = std.ascii.toLower(ch.*);
    }

    var mod: u32 = 0;
    var saveptr: ?[*:0]u8 = null;
    var match_success = false;

    var token = strtok_r(@ptrCast(&input_copy), "+", &saveptr);
    while (token != null) {
        trim_whitespace(token);
        if (token.?[0] == 0) {
            token = strtok_r(null, "+", &saveptr);
            continue;
        }

        if (strncmp(token.?, "code:", 5) == 0) {
            var endptr: ?[*:0]u8 = null;
            const keycode = strtol(token.? + 5, &endptr, 10);
            const end_z: [*:0]const u8 = endptr orelse token.? + 5;
            if (@intFromPtr(endptr) != @intFromPtr(token.? + 5) and
                (end_z[0] == 0 or end_z[0] == ' '))
            {
                switch (keycode) {
                    133, 134 => {
                        mod |= @intCast(c.WLR_MODIFIER_LOGO);
                        match_success = true;
                    },
                    37, 105 => {
                        mod |= @intCast(c.WLR_MODIFIER_CTRL);
                        match_success = true;
                    },
                    50, 62 => {
                        mod |= @intCast(c.WLR_MODIFIER_SHIFT);
                        match_success = true;
                    },
                    64, 108 => {
                        mod |= @intCast(c.WLR_MODIFIER_ALT);
                        match_success = true;
                    },
                    else => acwm_error_impl(
                        false,
                        WLR_ERROR,
                        @src().file,
                        @src().line,
                        "unknown modifier keycode: \x1b[1m\x1b[31m%s\x1b[0m\n",
                        token.?,
                    ),
                }
            }
        } else {
            if (strcmp(token.?, "super") == 0 or strcmp(token.?, "super_l") == 0 or strcmp(token.?, "super_r") == 0) {
                mod |= @intCast(c.WLR_MODIFIER_LOGO);
                match_success = true;
            }
            if (strcmp(token.?, "ctrl") == 0 or strcmp(token.?, "ctrl_l") == 0 or strcmp(token.?, "ctrl_r") == 0) {
                mod |= @intCast(c.WLR_MODIFIER_CTRL);
                match_success = true;
            }
            if (strcmp(token.?, "shift") == 0 or strcmp(token.?, "shift_l") == 0 or strcmp(token.?, "shift_r") == 0) {
                mod |= @intCast(c.WLR_MODIFIER_SHIFT);
                match_success = true;
            }
            if (strcmp(token.?, "alt") == 0 or strcmp(token.?, "alt_l") == 0 or strcmp(token.?, "alt_r") == 0) {
                mod |= @intCast(c.WLR_MODIFIER_ALT);
                match_success = true;
            }
            if (strcmp(token.?, "hyper") == 0 or strcmp(token.?, "hyper_l") == 0 or strcmp(token.?, "hyper_r") == 0) {
                mod |= @intCast(c.WLR_MODIFIER_MOD3);
                match_success = true;
            }
            if (strcmp(token.?, "none") == 0)
                match_success = true;
        }

        token = strtok_r(null, "+", &saveptr);
    }

    if (!match_success) {
        mod = std.math.maxInt(u32);
        acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Unknown modifier: \x1b[1m\x1b[31m%s\x1b[0m\n", mod_str);
    }
    return mod;
}

// ---------------------------------------------------------------------------
// keycodes / keysyms
// ---------------------------------------------------------------------------

fn findKeycodesInLayout(keymap: ?*c.struct_xkb_keymap, layout: c.xkb_layout_index_t, sym: c.xkb_keysym_t, multi_kc: *c.MultiKeycode) i32 {
    const min_keycode = c.xkb_keymap_min_keycode(keymap);
    const max_keycode = c.xkb_keymap_max_keycode(keymap);
    var found_count: i32 = 0;

    var keycode = min_keycode;
    while (keycode <= max_keycode and found_count < 3) : (keycode += 1) {
        const levels = c.xkb_keymap_num_levels_for_key(keymap, keycode, layout);
        var matched = false;

        var level: c.xkb_level_index_t = 0;
        while (level < levels and !matched) : (level += 1) {
            var syms: [*c]const c.xkb_keysym_t = null;
            const num_syms = c.xkb_keymap_key_get_syms_by_level(keymap, keycode, layout, level, &syms);
            if (num_syms > 0 and syms != null) {
                var i: usize = 0;
                while (i < @as(usize, @intCast(num_syms))) : (i += 1) {
                    if (syms[i] == sym) {
                        matched = true;
                        break;
                    }
                }
            }
        }

        if (!matched)
            continue;

        switch (found_count) {
            0 => multi_kc.keycode1 = keycode,
            1 => multi_kc.keycode2 = keycode,
            2 => multi_kc.keycode3 = keycode,
            else => {},
        }
        found_count += 1;
    }
    return found_count;
}

export fn find_keycodes_for_keysym(keymap: ?*c.struct_xkb_keymap, sym: c.xkb_keysym_t, multi_kc: *c.MultiKeycode) callconv(.c) i32 {
    multi_kc.keycode1 = 0;
    multi_kc.keycode2 = 0;
    multi_kc.keycode3 = 0;

    var found_count: i32 = 0;
    if (keymap != null) {
        const layouts = c.xkb_keymap_num_layouts(keymap);
        var layout: c.xkb_layout_index_t = 0;
        while (layout < layouts and found_count == 0) : (layout += 1) {
            found_count = findKeycodesInLayout(keymap, layout, sym, multi_kc);
        }
    }

    if (found_count == 0) {
        const fallback = referenceKeymap();
        if (fallback != null and fallback != keymap) {
            const layouts = c.xkb_keymap_num_layouts(fallback);
            var layout: c.xkb_layout_index_t = 0;
            while (layout < layouts and found_count == 0) : (layout += 1) {
                found_count = findKeycodesInLayout(fallback, layout, sym, multi_kc);
            }
        }
    }
    return found_count;
}

export fn find_keycodes_for_char(ch: u8, multi_kc: *c.MultiKeycode) callconv(.c) i32 {
    multi_kc.keycode1 = 0;
    multi_kc.keycode2 = 0;
    multi_kc.keycode3 = 0;
    if (ch == 0)
        return 0;
    return find_keycodes_for_keysym(c.config.keymap, c.xkb_utf32_to_keysym(@as(u32, ch)), multi_kc);
}

export fn parse_key(key_str: [*:0]const u8, isbindsym: bool) callconv(.c) c.KeySymCode {
    var kc = std.mem.zeroes(c.KeySymCode);

    if (c.config.keymap == null or c.config.ctx == null) {
        kc.type = c.KEY_TYPE_SYM;
        kc.keysym = c.XKB_KEY_NoSymbol;
        return kc;
    }

    if (strncmp(key_str, "code:", 5) == 0) {
        var endptr: ?[*:0]u8 = null;
        const keycode = strtol(key_str + 5, &endptr, 10);
        kc.type = c.KEY_TYPE_CODE;
        kc.keycode.keycode1 = @bitCast(@as(i32, @truncate(keycode)));
        kc.keycode.keycode2 = 0;
        kc.keycode.keycode3 = 0;
        return kc;
    }

    const sym = c.xkb_keysym_from_name(key_str, c.XKB_KEYSYM_CASE_INSENSITIVE);

    if (isbindsym) {
        kc.type = c.KEY_TYPE_SYM;
        kc.keysym = sym;
        return kc;
    }

    if (sym != c.XKB_KEY_NoSymbol) {
        const found_count = find_keycodes_for_keysym(c.config.keymap, sym, &kc.keycode);
        if (found_count > 0) {
            kc.type = c.KEY_TYPE_CODE;
            kc.keysym = sym;
        } else {
            kc.type = c.KEY_TYPE_SYM;
            kc.keysym = sym;
            kc.unresolved = true;
        }
    } else {
        kc.type = c.KEY_TYPE_SYM;
        kc.keysym = c.XKB_KEY_NoSymbol;
        acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Unknown key: \x1b[1m\x1b[31m%s\x1b[0m\n", key_str);
    }
    return kc;
}

// ---------------------------------------------------------------------------
// buttons / mouse actions
// ---------------------------------------------------------------------------

fn lowerCopy(str: [*:0]const u8, out: []u8) void {
    var i: usize = 0;
    while (str[i] != 0 and i + 1 < out.len) : (i += 1)
        out[i] = std.ascii.toLower(str[i]);
    out[i] = 0;
}

export fn parse_button(str: [*:0]const u8) callconv(.c) u32 {
    var lower_str: [20]u8 = undefined;
    lowerCopy(str, &lower_str);
    const lower: [*:0]const u8 = @ptrCast(&lower_str);

    if (strncmp(lower, "code:", 5) == 0) {
        var endptr: ?[*:0]u8 = null;
        const val = strtoul(lower + 5, &endptr, 10);
        const end_z: [*:0]const u8 = endptr orelse lower + 5;
        if (@intFromPtr(endptr) != @intFromPtr(lower + 5) and end_z[0] == 0 and val <= std.math.maxInt(u32)) {
            return @intCast(val);
        }
        acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Invalid code format: \x1b[1m\x1b[31m%s\x1b[0m\n", str);
        return std.math.maxInt(u32);
    }

    if (strcmp(lower, "btn_left") == 0) return @intCast(c.BTN_LEFT);
    if (strcmp(lower, "btn_right") == 0) return @intCast(c.BTN_RIGHT);
    if (strcmp(lower, "btn_middle") == 0) return @intCast(c.BTN_MIDDLE);
    if (strcmp(lower, "btn_side") == 0) return @intCast(c.BTN_SIDE);
    if (strcmp(lower, "btn_extra") == 0) return @intCast(c.BTN_EXTRA);
    if (strcmp(lower, "btn_forward") == 0) return @intCast(c.BTN_FORWARD);
    if (strcmp(lower, "btn_back") == 0) return @intCast(c.BTN_BACK);
    if (strcmp(lower, "btn_task") == 0) return @intCast(c.BTN_TASK);

    acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Unknown button: \x1b[1m\x1b[31m%s\x1b[0m\n", str);
    return std.math.maxInt(u32);
}

export fn parse_mouse_action(str: [*:0]const u8) callconv(.c) i32 {
    var lower_str: [20]u8 = undefined;
    lowerCopy(str, &lower_str);
    const lower: [*:0]const u8 = @ptrCast(&lower_str);

    if (strcmp(lower, "curmove") == 0) return c.CurMove;
    if (strcmp(lower, "curresize") == 0) return c.CurResize;
    if (strcmp(lower, "curnormal") == 0) return c.CurNormal;
    if (strcmp(lower, "curpressed") == 0) return c.CurPressed;
    return 0;
}

// ---------------------------------------------------------------------------
// combine_args_until_empty
// ---------------------------------------------------------------------------

export fn combine_args_until_empty(values: [*c][*c]u8, count: c_int) callconv(.c) [*c]u8 {
    if (count <= 0)
        return strdup("").?;

    var first_empty: c_int = count;
    var i: c_int = 0;
    while (i < count) : (i += 1) {
        const v = values[@intCast(i)];
        if (v == null)
            continue;
        if (v[0] == 0 or (strlen(@ptrCast(v)) == 1 and v[0] == '0')) {
            first_empty = i;
            break;
        }
    }
    if (first_empty == 0)
        return strdup("").?;

    var total_len: usize = 1;
    i = 0;
    while (i < first_empty) : (i += 1)
        total_len += strlen(@ptrCast(values[@intCast(i)]));
    total_len += @intCast(first_empty - 1);

    const raw = malloc(total_len) orelse return strdup("").?;
    const combined: [*:0]u8 = @ptrCast(raw);
    var pos: usize = 0;
    i = 0;
    while (i < first_empty) : (i += 1) {
        if (i > 0) {
            combined[pos] = ',';
            pos += 1;
        }
        const v = values[@intCast(i)];
        const n = strlen(@ptrCast(v));
        _ = memcpy(combined + pos, @ptrCast(v), n);
        pos += n;
    }
    combined[pos] = 0;
    return combined;
}

// ---------------------------------------------------------------------------
// parse_func_name
// ---------------------------------------------------------------------------

const ArgKind = enum {
    none,
    circle_dir,
    overcircle_dir,
    dir,
    i_atoi,
    bool_atoi,
    f_atof,
    ui_tagmask,
    force,
    clamp100,
    view_insert,
    togglehdr,
    switcher,
    setoption,
    str_dup,
    combine,
    spawn_on_empty,
    focusmon,
    tagmon,
    mouse_action,
    tag_view,
    crossmon,
    resize_move,
    named_scratchpad,
    virtual_output,
};

const FnRow = struct {
    name: [:0]const u8,
    sym: [:0]const u8,
    kind: ArgKind,
};

const funcs = [_]FnRow{
    .{ .name = "focusstack", .sym = "focus_stack", .kind = .circle_dir },
    .{ .name = "overcircle", .sym = "over_circle", .kind = .overcircle_dir },
    .{ .name = "groupfocus", .sym = "group_focus", .kind = .circle_dir },
    .{ .name = "focusdir", .sym = "focus_direction", .kind = .dir },
    .{ .name = "focus_window_or_workspace", .sym = "focus_window_or_workspace", .kind = .dir },
    .{ .name = "groupjoin", .sym = "group_join", .kind = .dir },
    .{ .name = "groupleave", .sym = "group_leave", .kind = .none },
    .{ .name = "focusid", .sym = "focus_by_id", .kind = .none },
    .{ .name = "incnmaster", .sym = "inc_nmaster", .kind = .i_atoi },
    .{ .name = "setmfact", .sym = "set_master_factor", .kind = .f_atof },
    .{ .name = "zoom", .sym = "zoom", .kind = .none },
    .{ .name = "exchange_client", .sym = "exchange_client", .kind = .dir },
    .{ .name = "move_client", .sym = "move_client", .kind = .dir },
    .{ .name = "exchange_stack_client", .sym = "exchange_stack_client", .kind = .circle_dir },
    .{ .name = "toggleglobal", .sym = "toggle_global", .kind = .none },
    .{ .name = "toggleoverview", .sym = "toggle_overview", .kind = .bool_atoi },
    .{ .name = "enteroverview", .sym = "enter_overview", .kind = .none },
    .{ .name = "leaveoverview", .sym = "leave_overview", .kind = .none },
    .{ .name = "togglejump", .sym = "toggle_jump", .kind = .none },
    .{ .name = "set_proportion", .sym = "set_proportion", .kind = .f_atof },
    .{ .name = "switch_proportion_preset", .sym = "switch_proportion_preset", .kind = .circle_dir },
    .{ .name = "viewtoleft", .sym = "view_to_left", .kind = .i_atoi },
    .{ .name = "viewtoright", .sym = "view_to_right", .kind = .i_atoi },
    .{ .name = "view_insert", .sym = "view_insert", .kind = .view_insert },
    .{ .name = "tagsilent", .sym = "tag_silent", .kind = .ui_tagmask },
    .{ .name = "tagtoleft", .sym = "tag_to_left", .kind = .i_atoi },
    .{ .name = "tagtoright", .sym = "tag_to_right", .kind = .i_atoi },
    .{ .name = "killclient", .sym = "kill_client", .kind = .force },
    .{ .name = "centerwin", .sym = "center_window", .kind = .none },
    .{ .name = "focuslast", .sym = "focus_last", .kind = .none },
    .{ .name = "switcher", .sym = "switcher", .kind = .switcher },
    .{ .name = "toggle_trackpad_enable", .sym = "toggle_trackpad_enable", .kind = .none },
    .{ .name = "setoption", .sym = "setoption", .kind = .setoption },
    .{ .name = "setkeymode", .sym = "set_key_mode", .kind = .str_dup },
    .{ .name = "switch_keyboard_layout", .sym = "switch_keyboard_layout", .kind = .clamp100 },
    .{ .name = "setlayout", .sym = "set_layout", .kind = .str_dup },
    .{ .name = "switch_layout", .sym = "switch_layout", .kind = .none },
    .{ .name = "togglefloating", .sym = "toggle_floating", .kind = .none },
    .{ .name = "togglefullscreen", .sym = "toggle_fullscreen", .kind = .none },
    .{ .name = "togglefakefullscreen", .sym = "toggle_fake_fullscreen", .kind = .none },
    .{ .name = "toggleoverlay", .sym = "toggle_overlay", .kind = .none },
    .{ .name = "minimized", .sym = "minimize_window", .kind = .none },
    .{ .name = "restore_minimized", .sym = "restore_minimized", .kind = .none },
    .{ .name = "toggle_scratchpad", .sym = "toggle_scratchpad", .kind = .none },
    .{ .name = "toggle_render_border", .sym = "toggle_render_border", .kind = .none },
    .{ .name = "focusmon", .sym = "focus_monitor", .kind = .focusmon },
    .{ .name = "tagmon", .sym = "tag_monitor", .kind = .tagmon },
    .{ .name = "incgaps", .sym = "increase_gaps", .kind = .i_atoi },
    .{ .name = "togglegaps", .sym = "toggle_gaps", .kind = .none },
    .{ .name = "togglegroupbar", .sym = "toggle_group_bar", .kind = .none },
    .{ .name = "chvt", .sym = "change_vt", .kind = .none },
    .{ .name = "spawn", .sym = "spawn", .kind = .combine },
    .{ .name = "spawn_shell", .sym = "spawn_shell", .kind = .combine },
    .{ .name = "spawn_on_empty", .sym = "spawn_on_empty", .kind = .spawn_on_empty },
    .{ .name = "quit", .sym = "quit", .kind = .none },
    .{ .name = "create_virtual_output", .sym = "create_virtual_output", .kind = .virtual_output },
    .{ .name = "destroy_all_virtual_output", .sym = "destroy_all_virtual_output", .kind = .none },
    .{ .name = "moveresize", .sym = "move_resize", .kind = .mouse_action },
    .{ .name = "togglemaximizescreen", .sym = "toggle_maximize_screen", .kind = .none },
    .{ .name = "viewprev_have_client", .sym = "viewprev_have_client", .kind = .i_atoi },
    .{ .name = "viewnext_have_client", .sym = "viewnext_have_client", .kind = .i_atoi },
    .{ .name = "viewtoleft_have_client", .sym = "view_to_left_have_client", .kind = .i_atoi },
    .{ .name = "viewtoright_have_client", .sym = "view_to_right_have_client", .kind = .i_atoi },
    .{ .name = "reload_config", .sym = "reload_config", .kind = .none },
    .{ .name = "load_config_file", .sym = "load_config_file", .kind = .str_dup },
    .{ .name = "tag", .sym = "tag", .kind = .tag_view },
    .{ .name = "view", .sym = "bind_to_view", .kind = .tag_view },
    .{ .name = "viewcrossmon", .sym = "view_cross_monitor", .kind = .crossmon },
    .{ .name = "tagcrossmon", .sym = "tag_cross_monitor", .kind = .crossmon },
    .{ .name = "toggletag", .sym = "toggle_tag", .kind = .ui_tagmask },
    .{ .name = "toggleview", .sym = "toggle_view", .kind = .ui_tagmask },
    .{ .name = "comboview", .sym = "combo_view", .kind = .ui_tagmask },
    .{ .name = "smartmovewin", .sym = "smart_move_window", .kind = .dir },
    .{ .name = "smartresizewin", .sym = "smart_resize_window", .kind = .dir },
    .{ .name = "resizewin", .sym = "resize_window", .kind = .resize_move },
    .{ .name = "movewin", .sym = "move_window", .kind = .resize_move },
    .{ .name = "toggle_named_scratchpad", .sym = "toggle_named_scratchpad", .kind = .named_scratchpad },
    .{ .name = "toggle_special_tag", .sym = "toggle_special_tag", .kind = .none },
    .{ .name = "tag_special_tag", .sym = "tag_special_tag", .kind = .none },
    .{ .name = "tag_special_silent", .sym = "tag_special_silent", .kind = .none },
    .{ .name = "disable_monitor", .sym = "disable_monitor", .kind = .str_dup },
    .{ .name = "enable_monitor", .sym = "enable_monitor", .kind = .str_dup },
    .{ .name = "toggle_monitor", .sym = "toggle_monitor", .kind = .str_dup },
    .{ .name = "sleep_monitor", .sym = "sleep_monitor", .kind = .str_dup },
    .{ .name = "wakeup_monitor", .sym = "wakeup_monitor", .kind = .str_dup },
    .{ .name = "sleep_toggle_monitor", .sym = "sleep_toggle_monitor", .kind = .str_dup },
    .{ .name = "scroller_stack", .sym = "scroller_stack", .kind = .dir },
    .{ .name = "toggle_all_floating", .sym = "toggle_all_floating", .kind = .none },
    .{ .name = "dwindle_toggle_split_direction", .sym = "dwindle_toggle_split_direction", .kind = .none },
    .{ .name = "dwindle_split_horizontal", .sym = "dwindle_split_horizontal", .kind = .none },
    .{ .name = "dwindle_split_vertical", .sym = "dwindle_split_vertical", .kind = .none },
    .{ .name = "dwindle_toggle_current_split", .sym = "dwindle_toggle_current_split", .kind = .none },
    .{ .name = "togglehdr", .sym = "toggle_hdr", .kind = .togglehdr },
};

fn handler(comptime row: FnRow) c.FuncType {
    return @extern(c.FuncType, .{ .name = row.sym });
}

fn concatArgs(arg_value2: [*:0]u8, arg_value3: [*:0]u8, arg_value4: [*:0]u8, arg_value5: [*:0]u8) ?[*:0]u8 {
    var params: [4]?[*:0]u8 = .{ null, null, null, null };
    var param_index: usize = 0;
    for ([_][*:0]u8{ arg_value2, arg_value3, arg_value4, arg_value5 }) |p| {
        if (p[0] != 0) {
            params[param_index] = p;
            param_index += 1;
        }
    }
    if (param_index == 0)
        return strdup("");

    var len: usize = 1 + (param_index - 1);
    for (params[0..param_index]) |p|
        len += strlen(p.?);

    const raw = malloc(len) orelse return null;
    const temp: [*:0]u8 = @ptrCast(raw);
    var pos: usize = 0;
    var i: usize = 0;
    while (i < param_index) : (i += 1) {
        if (i > 0) {
            temp[pos] = ',';
            pos += 1;
        }
        const n = strlen(params[i].?);
        _ = memcpy(temp + pos, params[i].?, n);
        pos += n;
    }
    temp[pos] = 0;
    return temp;
}

fn applyArg(
    arg: *c.Arg,
    comptime kind: ArgKind,
    arg_value: [*:0]u8,
    arg_value2: [*:0]u8,
    arg_value3: [*:0]u8,
    arg_value4: [*:0]u8,
    arg_value5: [*:0]u8,
) void {
    switch (kind) {
        .none => {},
        .circle_dir => arg.i = parse_circle_direction(arg_value),
        .overcircle_dir => arg.i = parse_overcircle_direction(arg_value),
        .dir => arg.i = parse_direction(arg_value),
        .i_atoi => arg.i = atoi(arg_value),
        .bool_atoi => arg.i = if (atoi(arg_value) == 1) 1 else 0,
        .f_atof => arg.f = @floatCast(atof(arg_value)),
        .ui_tagmask => arg.ui = parse_tag_mask(arg_value),
        .force => arg.i = parse_force(arg_value),
        .clamp100 => arg.i = std.math.clamp(atoi(arg_value), 0, 100),
        .view_insert => arg.i = if (strcmp(arg_value, "next") == 0) c.NEXT else c.PREV,
        .togglehdr => {
            if (strcmp(arg_value, "on") == 0) {
                arg.i = 1;
            } else if (strcmp(arg_value, "off") == 0) {
                arg.i = 0;
            } else {
                arg.i = -1;
            }
            const has_name = arg_value2[0] != 0 and
                !(strlen(arg_value2) == 1 and arg_value2[0] == '0');
            arg.v = if (has_name) strdup(arg_value2) else null;
        },
        .switcher => {
            if (strcmp(arg_value, "all_next") == 0) {
                arg.i = c.NEXT;
                arg.i2 = c.SW_ALL_MON;
            } else if (strcmp(arg_value, "all_prev") == 0) {
                arg.i = c.PREV;
                arg.i2 = c.SW_ALL_MON;
            } else if (strcmp(arg_value, "all_tag_next") == 0) {
                arg.i = c.NEXT;
                arg.i2 = c.SW_ALL_TAG;
            } else if (strcmp(arg_value, "all_tag_prev") == 0) {
                arg.i = c.PREV;
                arg.i2 = c.SW_ALL_TAG;
            } else if (strcmp(arg_value, "prev") == 0) {
                arg.i = c.PREV;
                arg.i2 = c.SW_CURRENT_TAG;
            } else {
                arg.i = c.NEXT;
                arg.i2 = c.SW_CURRENT_TAG;
            }
        },
        .setoption => {
            arg.v = strdup(arg_value);
            arg.v2 = concatArgs(arg_value2, arg_value3, arg_value4, arg_value5);
        },
        .str_dup => arg.v = strdup(arg_value),
        .combine => {
            var values = [5][*c]u8{ @ptrCast(arg_value), @ptrCast(arg_value2), @ptrCast(arg_value3), @ptrCast(arg_value4), @ptrCast(arg_value5) };
            arg.v = combine_args_until_empty(&values, 5);
        },
        .spawn_on_empty => {
            arg.v = strdup(arg_value);
            arg.ui = parse_tag_mask(arg_value2);
        },
        .focusmon => {
            arg.i = parse_monitor_arg(arg_value);
            if (arg.i == c.UNDIR)
                arg.v = strdup(arg_value);
        },
        .tagmon => {
            arg.i = parse_monitor_arg(arg_value);
            arg.i2 = atoi(arg_value2);
            if (arg.i == c.UNDIR)
                arg.v = strdup(arg_value);
        },
        .mouse_action => arg.ui = @bitCast(parse_mouse_action(arg_value)),
        .tag_view => {
            arg.ui = parse_tag_mask(arg_value);
            arg.i = atoi(arg_value2);
        },
        .crossmon => {
            arg.ui = parse_tag_mask(arg_value);
            arg.v = strdup(arg_value2);
        },
        .resize_move => {
            arg.ui = parse_num_type(arg_value);
            arg.ui2 = parse_num_type(arg_value2);
            arg.i = if (arg.ui == c.NUM_TYPE_DEFAULT) atoi(arg_value) else atoi(arg_value + 1);
            arg.i2 = if (arg.ui2 == c.NUM_TYPE_DEFAULT) atoi(arg_value2) else atoi(arg_value2 + 1);
        },
        .named_scratchpad => {
            arg.v = strdup(arg_value);
            arg.v2 = strdup(arg_value2);
            arg.v3 = strdup(arg_value3);
        },
        .virtual_output => {
            if (arg_value[0] != 0)
                arg.v = strdup(arg_value);
        },
    }
}

export fn parse_func_name(
    func_name: [*:0]u8,
    arg: *c.Arg,
    arg_value: [*:0]u8,
    arg_value2: [*:0]u8,
    arg_value3: [*:0]u8,
    arg_value4: [*:0]u8,
    arg_value5: [*:0]u8,
) callconv(.c) c.FuncType {
    arg.i = 0;
    arg.i2 = 0;
    arg.f = 0.0;
    arg.f2 = 0.0;
    arg.ui = 0;
    arg.ui2 = 0;
    arg.v = null;
    arg.v2 = null;
    arg.v3 = null;

    const name = std.mem.span(func_name);
    inline for (funcs) |row| {
        if (std.mem.eql(u8, name, row.name)) {
            applyArg(arg, row.kind, arg_value, arg_value2, arg_value3, arg_value4, arg_value5);
            return handler(row);
        }
    }
    return null;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: see tests/binding_parse_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_last_error: [1024]u8;
extern var stub_error_count: c_int;
extern var stub_keymap: ?*c.struct_xkb_keymap;
extern var stub_min_keycode: c.xkb_keycode_t;
extern var stub_max_keycode: c.xkb_keycode_t;
extern var stub_levels: c.xkb_level_index_t;
extern var stub_match_keycode: c_int;
extern var stub_scan_sym: c.xkb_keysym_t;
extern var stub_keysym_from_name: c.xkb_keysym_t;
extern var stub_utf32_keysym: c.xkb_keysym_t;
extern var stub_unref_calls: c_int;
extern var stub_direction: i32;
extern var stub_circle_direction: i32;
extern var stub_overcircle_direction: i32;
extern var stub_force: i32;
extern var stub_tag_mask: u32;
extern var stub_num_type: u32;
extern var stub_monitor_arg: i32;

fn resetStub() void {
    stub_error_count = 0;
    stub_last_error[0] = 0;
    stub_keymap = @ptrFromInt(@alignOf(usize));
    stub_min_keycode = 1;
    stub_max_keycode = 3;
    stub_levels = 1;
    stub_match_keycode = 2;
    stub_scan_sym = 0x61;
    stub_keysym_from_name = 0x61;
    stub_utf32_keysym = 0x61;
    stub_unref_calls = 0;
    stub_direction = 0;
    stub_circle_direction = 0;
    stub_overcircle_direction = 0;
    stub_force = 0;
    stub_tag_mask = 0;
    stub_num_type = 0;
    stub_monitor_arg = 0;
    reference_keymap_instance = null;
}

fn lastError() []const u8 {
    return std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&stub_last_error)), 0);
}

test "keymap lifecycle creates, references and cleans up" {
    resetStub();
    c.config.ctx = null;
    c.config.keymap = null;

    create_config_keymap();
    try testing.expect(c.config.ctx != null);
    try testing.expect(c.config.keymap != null);

    // a second create is a no-op
    const ctx = c.config.ctx;
    create_config_keymap();
    try testing.expectEqual(@as(?*c.struct_xkb_context, @ptrCast(ctx)), c.config.ctx);

    cleanup_config_keymap();
    try testing.expect(c.config.ctx == null);
    try testing.expect(c.config.keymap == null);
    try testing.expectEqual(@as(c_int, 1), stub_unref_calls); // keymap
}

test "parse_bind_flags sets every suffix flag and reports unknowns" {
    resetStub();
    var kb: c.KeyBinding = std.mem.zeroes(c.KeyBinding);

    parse_bind_flags("bindslrpc", &kb);
    try testing.expectEqual(@as(c_int, c.KEY_TYPE_SYM), kb.keysymcode.type);
    try testing.expect(kb.islockapply);
    try testing.expect(kb.isreleaseapply);
    try testing.expect(kb.ispassapply);
    try testing.expect(kb.isallowconflict);

    var kb2: c.KeyBinding = std.mem.zeroes(c.KeyBinding);
    parse_bind_flags("bindX", &kb2);
    try testing.expectEqual(@as(c_int, 1), stub_error_count);
    try testing.expect(std.mem.startsWith(u8, lastError(), "Unknown bind flag: \x1b[1m\x1b[31mX"));

    // not starting with bind: no-op
    var kb3: c.KeyBinding = std.mem.zeroes(c.KeyBinding);
    parse_bind_flags("mouse", &kb3);
    try testing.expect(!kb3.islockapply);
}

test "set_binding_keymode copies and classifies the mode" {
    resetStub();
    var cfg: c.Config = std.mem.zeroes(c.Config);
    var mode: [28]u8 = undefined;
    var common = false;
    var default = false;

    @memcpy(cfg.keymode[0..6], "common");
    set_binding_keymode(&cfg, &mode, &common, &default);
    try testing.expect(common);
    try testing.expect(!default);

    cfg = std.mem.zeroes(c.Config);
    @memcpy(cfg.keymode[0..7], "default");
    set_binding_keymode(&cfg, &mode, &common, &default);
    try testing.expect(!common);
    try testing.expect(default);

    cfg = std.mem.zeroes(c.Config);
    @memcpy(cfg.keymode[0..6], "resize");
    set_binding_keymode(&cfg, &mode, &common, &default);
    try testing.expect(!common);
    try testing.expect(!default);
    try testing.expectEqualStrings("resize", std.mem.sliceTo(&mode, 0));
}

test "parse_mod handles names, code: forms and errors" {
    resetStub();

    try testing.expectEqual(@as(u32, 0), parse_mod("none"));
    try testing.expectEqual(@as(u32, @intCast(c.WLR_MODIFIER_LOGO)) | @as(u32, @intCast(c.WLR_MODIFIER_SHIFT)), parse_mod("SUPER+Shift"));
    try testing.expectEqual(@as(u32, @intCast(c.WLR_MODIFIER_CTRL)) | @as(u32, @intCast(c.WLR_MODIFIER_ALT)), parse_mod("ctrl + alt"));
    try testing.expectEqual(@as(u32, @intCast(c.WLR_MODIFIER_MOD3)), parse_mod("hyper"));
    try testing.expectEqual(@as(u32, @intCast(c.WLR_MODIFIER_LOGO)), parse_mod("code:133"));
    try testing.expectEqual(@as(u32, @intCast(c.WLR_MODIFIER_ALT)), parse_mod("code:64"));
    // multiple tokens with a skip of an empty one
    try testing.expectEqual(@as(u32, @intCast(c.WLR_MODIFIER_LOGO)) | @as(u32, @intCast(c.WLR_MODIFIER_CTRL)), parse_mod("super++ctrl"));

    const max = std.math.maxInt(u32);
    try testing.expectEqual(max, parse_mod(""));
    try testing.expectEqual(max, parse_mod("bogus"));
    try testing.expectEqual(@as(c_int, 1), stub_error_count);
    try testing.expect(std.mem.startsWith(u8, lastError(), "Unknown modifier: \x1b[1m\x1b[31mbogus"));

    // unknown keycode logs, and because match_success never flips the whole
    // parse still fails with the generic modifier error (two messages, C
    // parity)
    resetStub();
    try testing.expectEqual(std.math.maxInt(u32), parse_mod("code:999"));
    try testing.expectEqual(@as(c_int, 2), stub_error_count);
    try testing.expect(std.mem.startsWith(u8, lastError(), "Unknown modifier: \x1b[1m\x1b[31mcode:999"));
}

test "keycode scanning finds keycodes from the fake keymap" {
    resetStub();

    var kc: c.MultiKeycode = undefined;
    const found = find_keycodes_for_keysym(stub_keymap, stub_scan_sym, &kc);
    try testing.expectEqual(@as(i32, 1), found);
    try testing.expectEqual(@as(u32, 2), kc.keycode1);
    try testing.expectEqual(@as(u32, 0), kc.keycode2);

    // a sym that never matches falls through to the reference keymap and
    // still returns zero with a zeroed struct
    const kc2 = find_keycodes_for_keysym(stub_keymap, 0x99, &kc);
    try testing.expectEqual(@as(i32, 0), kc2);
    try testing.expectEqual(@as(u32, 0), kc.keycode1);

    // char path maps through xkb_utf32_to_keysym (needs a keymap on config)
    c.config.keymap = stub_keymap;
    c.config.ctx = @ptrFromInt(@alignOf(usize));
    const found_c = find_keycodes_for_char('a', &kc);
    try testing.expectEqual(@as(i32, 1), found_c);
    try testing.expectEqual(@as(u32, 2), kc.keycode1);

    var kc3: c.MultiKeycode = undefined;
    try testing.expectEqual(@as(i32, 0), find_keycodes_for_char(0, &kc3));
}

test "parse_key: missing keymap, code:, sym and unresolved forms" {
    resetStub();

    // no keymap/ctx -> NoSymbol
    c.config.keymap = null;
    c.config.ctx = null;
    var kc = parse_key("a", false);
    try testing.expectEqual(@as(i32, c.KEY_TYPE_SYM), kc.type);
    try testing.expectEqual(@as(u32, @intCast(c.XKB_KEY_NoSymbol)), kc.keysym);

    // code: form bypasses the keymap requirement
    c.config.keymap = stub_keymap;
    c.config.ctx = @ptrFromInt(@alignOf(usize));
    kc = parse_key("code:5", false);
    try testing.expectEqual(@as(i32, c.KEY_TYPE_CODE), kc.type);
    try testing.expectEqual(@as(u32, 5), kc.keycode.keycode1);

    // isbindsym keeps the symbol
    kc = parse_key("a", true);
    try testing.expectEqual(@as(i32, c.KEY_TYPE_SYM), kc.type);
    try testing.expectEqual(@as(u32, 0x61), kc.keysym);

    // resolved keysym -> keycode
    kc = parse_key("a", false);
    try testing.expectEqual(@as(i32, c.KEY_TYPE_CODE), kc.type);
    try testing.expectEqual(@as(u32, 2), kc.keycode.keycode1);
    try testing.expectEqual(@as(u32, 0x61), kc.keysym);

    // resolvable sym with no matching keycode -> unresolved
    resetStub();
    stub_keysym_from_name = 0x77;
    stub_scan_sym = 0x61;
    kc = parse_key("w", false);
    try testing.expectEqual(@as(i32, c.KEY_TYPE_SYM), kc.type);
    try testing.expect(kc.unresolved);

    // unknown key name
    resetStub();
    stub_keysym_from_name = c.XKB_KEY_NoSymbol;
    kc = parse_key("nope", false);
    try testing.expectEqual(@as(i32, c.KEY_TYPE_SYM), kc.type);
    try testing.expectEqual(@as(u32, @intCast(c.XKB_KEY_NoSymbol)), kc.keysym);
    try testing.expect(std.mem.startsWith(u8, lastError(), "Unknown key: \x1b[1m\x1b[31mnope"));
}

test "parse_button and parse_mouse_action" {
    resetStub();

    try testing.expectEqual(@as(u32, c.BTN_LEFT), parse_button("BTN_LEFT"));
    try testing.expectEqual(@as(u32, c.BTN_RIGHT), parse_button("btn_right"));
    try testing.expectEqual(@as(u32, 272), parse_button("code:272"));
    try testing.expectEqual(std.math.maxInt(u32), parse_button("code:x"));
    try testing.expect(std.mem.startsWith(u8, lastError(), "Invalid code format:"));
    try testing.expectEqual(std.math.maxInt(u32), parse_button("wat"));
    try testing.expect(std.mem.startsWith(u8, lastError(), "Unknown button:"));

    try testing.expectEqual(@as(i32, c.CurMove), parse_mouse_action("curmove"));
    try testing.expectEqual(@as(i32, c.CurResize), parse_mouse_action("CURRESIZE"));
    try testing.expectEqual(@as(i32, 0), parse_mouse_action("nothing"));
}

test "combine_args_until_empty mirrors the C concatenation" {
    var ab: [64:0]u8 = undefined;
    var bb: [64:0]u8 = undefined;
    var cb: [64:0]u8 = undefined;
    var zb: [64:0]u8 = undefined;
    var eb: [64:0]u8 = undefined;
    const a = strArgZ("a", &ab);
    const b = strArgZ("b", &bb);
    const c0 = strArgZ("c", &cb);
    const zero = strArgZ("0", &zb);
    const empty = strArgZ("", &eb);
    var values = [5][*c]u8{ a.ptr, b.ptr, c0.ptr, zero.ptr, empty.ptr };
    const combined = combine_args_until_empty(&values, 5);
    defer free(@ptrCast(combined));
    try testing.expectEqualStrings("a,b,c", std.mem.span(@as([*:0]const u8, @ptrCast(combined))));

    // first element already empty -> empty string
    var values2 = [5][*c]u8{ empty.ptr, a.ptr, b.ptr, c0.ptr, zero.ptr };
    const combined2 = combine_args_until_empty(&values2, 5);
    defer free(@ptrCast(combined2));
    try testing.expectEqualStrings("", std.mem.span(@as([*:0]const u8, @ptrCast(combined2))));

    const combined3 = combine_args_until_empty(&values, 0);
    defer free(@ptrCast(combined3));
    try testing.expectEqualStrings("", std.mem.span(@as([*:0]const u8, @ptrCast(combined3))));
}

/// Convenience: passes explicit argument buffers to parse_func_name.
fn callFunc(name: [:0]u8, a1: [:0]u8, a2: [:0]u8, a3: [:0]u8, a4: [:0]u8, a5: [:0]u8, arg: *c.Arg) c.FuncType {
    return parse_func_name(name.ptr, arg, a1.ptr, a2.ptr, a3.ptr, a4.ptr, a5.ptr);
}

fn strArg(s: []const u8, buf: *[64:0]u8) [*:0]u8 {
    @memcpy(buf[0..s.len], s);
    buf[s.len] = 0;
    return buf;
}

test "parse_func_name resolves handlers and zeroes the arg" {
    resetStub();
    var arg: c.Arg = std.mem.zeroes(c.Arg);
    arg.i = 99; // must be zeroed by the call

    var name: [64:0]u8 = undefined;
    var b1: [64:0]u8 = undefined;
    var b2: [64:0]u8 = undefined;
    var b3: [64:0]u8 = undefined;
    var b4: [64:0]u8 = undefined;
    var b5: [64:0]u8 = undefined;

    const quit_ptr = @extern(c.FuncType, .{ .name = "quit" });
    const fn_ptr = callFunc(strArgZ("quit", &name), strArgZ("0", &b1), strArgZ("0", &b2), strArgZ("0", &b3), strArgZ("0", &b4), strArgZ("0", &b5), &arg);
    try testing.expect(fn_ptr != null);
    try testing.expectEqual(@intFromPtr(quit_ptr), @intFromPtr(fn_ptr));
    try testing.expectEqual(@as(i32, 0), arg.i);

    // unknown name -> null
    const unknown = callFunc(strArgZ("wat", &name), strArgZ("0", &b1), strArgZ("0", &b2), strArgZ("0", &b3), strArgZ("0", &b4), strArgZ("0", &b5), &arg);
    try testing.expect(unknown == null);
}

fn strArgZ(s: []const u8, buf: *[64:0]u8) [:0]u8 {
    @memcpy(buf[0..s.len], s);
    buf[s.len] = 0;
    return buf[0..s.len :0];
}

test "parse_func_name argument kinds" {
    resetStub();
    var arg: c.Arg = std.mem.zeroes(c.Arg);
    var name: [64:0]u8 = undefined;
    var b1: [64:0]u8 = undefined;
    var b2: [64:0]u8 = undefined;
    var b3: [64:0]u8 = undefined;
    var b4: [64:0]u8 = undefined;
    var b5: [64:0]u8 = undefined;

    // spawn combines the remaining arguments
    stub_tag_mask = 0;
    _ = callFunc(strArgZ("spawn", &name), strArgZ("foot", &b1), strArgZ("-e", &b2), strArgZ("sh", &b3), strArgZ("0", &b4), strArgZ("0", &b5), &arg);
    try testing.expect(arg.v != null);
    try testing.expectEqualStrings("foot,-e,sh", std.mem.span(@as([*:0]const u8, @ptrCast(arg.v))));

    // tag parses a mask and an index
    stub_tag_mask = 0b101;
    _ = callFunc(strArgZ("tag", &name), strArgZ("1,3", &b1), strArgZ("2", &b2), strArgZ("0", &b3), strArgZ("0", &b4), strArgZ("0", &b5), &arg);
    try testing.expectEqual(@as(u32, 0b101), arg.ui);
    try testing.expectEqual(@as(i32, 2), arg.i);

    // direction parsers
    stub_direction = 7;
    _ = callFunc(strArgZ("focusdir", &name), strArgZ("left", &b1), strArgZ("0", &b2), strArgZ("0", &b3), strArgZ("0", &b4), strArgZ("0", &b5), &arg);
    try testing.expectEqual(@as(i32, 7), arg.i);

    // switcher maps the mode strings
    _ = callFunc(strArgZ("switcher", &name), strArgZ("all_tag_prev", &b1), strArgZ("0", &b2), strArgZ("0", &b3), strArgZ("0", &b4), strArgZ("0", &b5), &arg);
    try testing.expectEqual(@as(i32, c.PREV), arg.i);
    try testing.expectEqual(@as(i32, c.SW_ALL_TAG), arg.i2);
}

test "parse_func_name special cases: togglehdr, setoption, focusmon" {
    resetStub();
    var arg: c.Arg = std.mem.zeroes(c.Arg);
    var name: [64:0]u8 = undefined;
    var b1: [64:0]u8 = undefined;
    var b2: [64:0]u8 = undefined;
    var b3: [64:0]u8 = undefined;
    var b4: [64:0]u8 = undefined;
    var b5: [64:0]u8 = undefined;

    // togglehdr on + monitor name
    _ = callFunc(strArgZ("togglehdr", &name), strArgZ("on", &b1), strArgZ("DP-1", &b2), strArgZ("0", &b3), strArgZ("0", &b4), strArgZ("0", &b5), &arg);
    try testing.expectEqual(@as(i32, 1), arg.i);
    try testing.expectEqualStrings("DP-1", std.mem.span(@as([*:0]const u8, @ptrCast(arg.v))));

    // togglehdr with the "0" placeholder must not set a name
    arg = std.mem.zeroes(c.Arg);
    _ = callFunc(strArgZ("togglehdr", &name), strArgZ("", &b1), strArgZ("0", &b2), strArgZ("0", &b3), strArgZ("0", &b4), strArgZ("0", &b5), &arg);
    try testing.expectEqual(@as(i32, -1), arg.i);
    try testing.expect(arg.v == null);

    // setoption keeps the literal "0" placeholders in the second argument
    arg = std.mem.zeroes(c.Arg);
    _ = callFunc(strArgZ("setoption", &name), strArgZ("gaps_in", &b1), strArgZ("5", &b2), strArgZ("0", &b3), strArgZ("", &b4), strArgZ("", &b5), &arg);
    try testing.expectEqualStrings("gaps_in", std.mem.span(@as([*:0]const u8, @ptrCast(arg.v))));
    try testing.expectEqualStrings("5,0", std.mem.span(@as([*:0]const u8, @ptrCast(arg.v2))));

    // focusmon with a name (UNDIR from parse_monitor_arg) stores the string
    arg = std.mem.zeroes(c.Arg);
    stub_monitor_arg = c.UNDIR;
    _ = callFunc(strArgZ("focusmon", &name), strArgZ("DP-1", &b1), strArgZ("0", &b2), strArgZ("0", &b3), strArgZ("0", &b4), strArgZ("0", &b5), &arg);
    try testing.expectEqual(@as(i32, c.UNDIR), arg.i);
    try testing.expectEqualStrings("DP-1", std.mem.span(@as([*:0]const u8, @ptrCast(arg.v))));

    // numeric monitor arg: no string stored
    arg = std.mem.zeroes(c.Arg);
    stub_monitor_arg = c.RIGHT;
    _ = callFunc(strArgZ("focusmon", &name), strArgZ("right", &b1), strArgZ("0", &b2), strArgZ("0", &b3), strArgZ("0", &b4), strArgZ("0", &b5), &arg);
    try testing.expect(arg.v == null);
}
