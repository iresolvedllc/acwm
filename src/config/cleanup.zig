//! Port of src/config/cleanup.c (strangler-fig Phase 4, slice 23).
//!
//! Exports the same three C symbols (free_circle_layout, free_baked_points,
//! free_config); the C twin is filtered from the compositor link. Deep-frees
//! every heap allocation reachable from the global `Config config` plus the
//! animation baked-point arrays on the server, resetting pointers and counts
//! so repeated calls and reloads are safe (the C does the same nulling).
//!
//! Tests live at the bottom and need tests/cleanup_stub.c (server global +
//! cleanup_config_keymap stand-in).

const std = @import("std");
const c = @import("cc");

extern "c" fn free(ptr: ?*anyopaque) void;
extern fn cleanup_config_keymap() callconv(.c) void;

fn freeZ(ptr: anytype) void {
    free(@ptrCast(@constCast(ptr)));
}

export fn free_circle_layout(config: *c.Config) callconv(.c) void {
    if (config.circle_layout != null) {
        var i: usize = 0;
        while (i < @as(usize, @intCast(config.circle_layout_count))) : (i += 1) {
            if (config.circle_layout[i] != null) {
                freeZ(config.circle_layout[i]);
                config.circle_layout[i] = null;
            }
        }
        free(@ptrCast(config.circle_layout));
        config.circle_layout = null;
    }
    config.circle_layout_count = 0;
}

export fn free_baked_points() callconv(.c) void {
    inline for (.{
        "baked_points_move",
        "baked_points_open",
        "baked_points_close",
        "baked_points_tag",
        "baked_points_focus",
        "baked_points_opafadein",
        "baked_points_opafadeout",
    }) |field| {
        if (@field(c.server, field) != null) {
            freeZ(@field(c.server, field));
            @field(c.server, field) = null;
        }
    }
}

fn freeArgStrings(arg: *c.Arg) void {
    if (arg.v != null) {
        freeZ(arg.v);
        arg.v = null;
    }
    if (arg.v2 != null) {
        freeZ(arg.v2);
        arg.v2 = null;
    }
    if (arg.v3 != null) {
        freeZ(arg.v3);
        arg.v3 = null;
    }
}

export fn free_config() callconv(.c) void {
    const cfg = &c.config;

    // window_rules
    if (cfg.window_rules != null) {
        var i: usize = 0;
        while (i < @as(usize, @intCast(cfg.window_rules_count))) : (i += 1) {
            const rule = &cfg.window_rules[i];
            if (rule.id != null) {
                freeZ(rule.id);
                rule.id = null;
            }
            if (rule.title != null) {
                freeZ(rule.title);
                rule.title = null;
            }
            if (rule.monitor != null) {
                freeZ(rule.monitor);
                rule.monitor = null;
            }
            rule.animation_type_open = c.ANIM_TYPE_UNSET;
            rule.animation_type_close = c.ANIM_TYPE_UNSET;
            freeArgStrings(@ptrCast(&rule.globalkeybinding.arg));
        }
        free(@ptrCast(cfg.window_rules));
        cfg.window_rules = null;
        cfg.window_rules_count = 0;
    }

    // device_rules
    if (cfg.device_rules != null) {
        var i: usize = 0;
        while (i < @as(usize, @intCast(cfg.device_rules_count))) : (i += 1) {
            if (cfg.device_rules[i].name != null)
                freeZ(cfg.device_rules[i].name);
        }
        free(@ptrCast(cfg.device_rules));
        cfg.device_rules = null;
        cfg.device_rules_count = 0;
    }

    // key / mouse / axis / switch / gesture bindings
    if (cfg.key_bindings != null) {
        var i: usize = 0;
        while (i < @as(usize, @intCast(cfg.key_bindings_count))) : (i += 1)
            freeArgStrings(@ptrCast(&cfg.key_bindings[i].arg));
        free(@ptrCast(cfg.key_bindings));
        cfg.key_bindings = null;
        cfg.key_bindings_count = 0;
    }
    if (cfg.mouse_bindings != null) {
        var i: usize = 0;
        while (i < @as(usize, @intCast(cfg.mouse_bindings_count))) : (i += 1)
            freeArgStrings(@ptrCast(&cfg.mouse_bindings[i].arg));
        free(@ptrCast(cfg.mouse_bindings));
        cfg.mouse_bindings = null;
        cfg.mouse_bindings_count = 0;
    }
    if (cfg.axis_bindings != null) {
        var i: usize = 0;
        while (i < @as(usize, @intCast(cfg.axis_bindings_count))) : (i += 1)
            freeArgStrings(@ptrCast(&cfg.axis_bindings[i].arg));
        free(@ptrCast(cfg.axis_bindings));
        cfg.axis_bindings = null;
        cfg.axis_bindings_count = 0;
    }
    if (cfg.switch_bindings != null) {
        var i: usize = 0;
        while (i < @as(usize, @intCast(cfg.switch_bindings_count))) : (i += 1)
            freeArgStrings(@ptrCast(&cfg.switch_bindings[i].arg));
        free(@ptrCast(cfg.switch_bindings));
        cfg.switch_bindings = null;
        cfg.switch_bindings_count = 0;
    }
    if (cfg.gesture_bindings != null) {
        var i: usize = 0;
        while (i < @as(usize, @intCast(cfg.gesture_bindings_count))) : (i += 1)
            freeArgStrings(@ptrCast(&cfg.gesture_bindings[i].arg));
        free(@ptrCast(cfg.gesture_bindings));
        cfg.gesture_bindings = null;
        cfg.gesture_bindings_count = 0;
    }

    // tag_rules
    if (cfg.tag_rules != null) {
        var i: usize = 0;
        while (i < @as(usize, @intCast(cfg.tag_rules_count))) : (i += 1) {
            const rule = &cfg.tag_rules[i];
            if (rule.layout_name != null) freeZ(rule.layout_name);
            if (rule.monitor_name != null) freeZ(rule.monitor_name);
            if (rule.monitor_make != null) freeZ(rule.monitor_make);
            if (rule.monitor_model != null) freeZ(rule.monitor_model);
            if (rule.monitor_serial != null) freeZ(rule.monitor_serial);
        }
        free(@ptrCast(cfg.tag_rules));
        cfg.tag_rules = null;
        cfg.tag_rules_count = 0;
    }

    // monitor_rules
    if (cfg.monitor_rules != null) {
        var i: usize = 0;
        while (i < @as(usize, @intCast(cfg.monitor_rules_count))) : (i += 1) {
            const rule = &cfg.monitor_rules[i];
            if (rule.name != null) freeZ(rule.name);
            if (rule.make != null) freeZ(rule.make);
            if (rule.model != null) freeZ(rule.model);
            if (rule.serial != null) freeZ(rule.serial);
            if (rule.icc != null) freeZ(rule.icc);
        }
        free(@ptrCast(cfg.monitor_rules));
        cfg.monitor_rules = null;
        cfg.monitor_rules_count = 0;
    }

    // layer_rules
    if (cfg.layer_rules != null) {
        var i: usize = 0;
        while (i < @as(usize, @intCast(cfg.layer_rules_count))) : (i += 1) {
            const rule = &cfg.layer_rules[i];
            if (rule.layer_name != null)
                freeZ(rule.layer_name);
            rule.animation_type_open = c.ANIM_TYPE_UNSET;
            rule.animation_type_close = c.ANIM_TYPE_UNSET;
        }
        free(@ptrCast(cfg.layer_rules));
        cfg.layer_rules = null;
        cfg.layer_rules_count = 0;
    }

    // env
    if (cfg.env != null) {
        var i: usize = 0;
        while (i < @as(usize, @intCast(cfg.env_count))) : (i += 1) {
            const env = cfg.env[i];
            if (env != null) {
                if (env.*.type != null) freeZ(env.*.type);
                if (env.*.value != null) freeZ(env.*.value);
                free(@ptrCast(env));
            }
        }
        free(@ptrCast(cfg.env));
        cfg.env = null;
        cfg.env_count = 0;
    }

    // vars
    if (cfg.vars != null) {
        var i: usize = 0;
        while (i < @as(usize, @intCast(cfg.vars_count))) : (i += 1) {
            const v = cfg.vars[i];
            if (v != null) {
                freeZ(v.*.name);
                freeZ(v.*.value);
                free(@ptrCast(v));
            }
        }
        free(@ptrCast(cfg.vars));
        cfg.vars = null;
        cfg.vars_count = 0;
    }

    // exec / exec_once
    if (cfg.exec != null) {
        var i: usize = 0;
        while (i < @as(usize, @intCast(cfg.exec_count))) : (i += 1)
            freeZ(cfg.exec[i]);
        free(@ptrCast(cfg.exec));
        cfg.exec = null;
        cfg.exec_count = 0;
    }
    if (cfg.exec_once != null) {
        var i: usize = 0;
        while (i < @as(usize, @intCast(cfg.exec_once_count))) : (i += 1)
            freeZ(cfg.exec_once[i]);
        free(@ptrCast(cfg.exec_once));
        cfg.exec_once = null;
        cfg.exec_once_count = 0;
    }

    if (cfg.scroller_proportion_preset != null) {
        free(@ptrCast(cfg.scroller_proportion_preset));
        cfg.scroller_proportion_preset = null;
        cfg.scroller_proportion_preset_count = 0;
    }

    if (cfg.cursor_theme != null) {
        freeZ(cfg.cursor_theme);
        cfg.cursor_theme = null;
    }

    inline for (.{ "jumplabeldata", "groupbardata", "tabbardata", "bardata" }) |data_field| {
        const d = &@field(cfg, data_field);
        if (d.*.font_desc != null) {
            freeZ(d.*.font_desc);
            d.*.font_desc = null;
        }
    }

    if (cfg.bar_clock_format != null) {
        freeZ(cfg.bar_clock_format);
        cfg.bar_clock_format = null;
    }
    if (cfg.idle_command != null) {
        freeZ(cfg.idle_command);
        cfg.idle_command = null;
    }
    if (cfg.resume_command != null) {
        freeZ(cfg.resume_command);
        cfg.resume_command = null;
    }
    if (cfg.jump_labels != null) {
        freeZ(cfg.jump_labels);
        cfg.jump_labels = null;
    }

    free_circle_layout(&c.config);
    free_baked_points();
    cleanup_config_keymap();
}

// ---------------------------------------------------------------------------
// tests (stub-backed: see tests/cleanup_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_cleanup_keymap_calls: c_int;
extern "c" fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern "c" fn malloc(size: usize) ?*anyopaque;

test "free_circle_layout frees, nulls and resets the count" {
    var cfg: c.Config = std.mem.zeroes(c.Config);
    const arr = @as(?[*]?[*:0]u8, @ptrCast(@alignCast(malloc(2 * @sizeOf(?[*:0]u8)).?)));
    arr.?[0] = strdup("a");
    arr.?[1] = strdup("b");
    cfg.circle_layout = @ptrCast(arr);
    cfg.circle_layout_count = 2;

    free_circle_layout(&cfg);
    try testing.expect(cfg.circle_layout == null);
    try testing.expectEqual(@as(i32, 0), cfg.circle_layout_count);

    // idempotent
    free_circle_layout(&cfg);
}

test "free_baked_points frees every animation cache" {
    inline for (.{
        "baked_points_move",
        "baked_points_open",
        "baked_points_close",
        "baked_points_tag",
        "baked_points_focus",
        "baked_points_opafadein",
        "baked_points_opafadeout",
    }) |field| {
        @field(c.server, field) = @ptrCast(@alignCast(malloc(32).?));
    }

    free_baked_points();

    inline for (.{
        "baked_points_move",
        "baked_points_open",
        "baked_points_close",
        "baked_points_tag",
        "baked_points_focus",
        "baked_points_opafadein",
        "baked_points_opafadeout",
    }) |field| {
        try testing.expect(@field(c.server, field) == null);
    }
    free_baked_points(); // idempotent
}

test "free_config clears every owned allocation and count" {
    stub_cleanup_keymap_calls = 0;
    c.config = std.mem.zeroes(c.Config);

    // window rules with strings, arg strings and globalkeybinding args
    const wr = @as(?[*]c.ConfigWinRule, @ptrCast(@alignCast(malloc(@sizeOf(c.ConfigWinRule)).?)));
    wr.?[0] = std.mem.zeroes(c.ConfigWinRule);
    wr.?[0].id = strdup("firefox");
    wr.?[0].title = strdup("Title");
    wr.?[0].monitor = strdup("DP-1");
    wr.?[0].globalkeybinding.arg.v = strdup("arg");
    c.config.window_rules = @ptrCast(wr);
    c.config.window_rules_count = 1;

    // device rules
    const dr = @as(?[*]c.ConfigDeviceRule, @ptrCast(@alignCast(malloc(@sizeOf(c.ConfigDeviceRule)).?)));
    dr.?[0] = std.mem.zeroes(c.ConfigDeviceRule);
    dr.?[0].name = strdup("kbd");
    c.config.device_rules = @ptrCast(dr);
    c.config.device_rules_count = 1;

    // key bindings with arg strings
    const kb = @as(?[*]c.KeyBinding, @ptrCast(@alignCast(malloc(@sizeOf(c.KeyBinding)).?)));
    kb.?[0] = std.mem.zeroes(c.KeyBinding);
    kb.?[0].arg.v = strdup("v");
    kb.?[0].arg.v2 = strdup("v2");
    kb.?[0].arg.v3 = strdup("v3");
    c.config.key_bindings = @ptrCast(kb);
    c.config.key_bindings_count = 1;

    // tag + monitor + layer rules
    const tr = @as(?[*]c.ConfigTagRule, @ptrCast(@alignCast(malloc(@sizeOf(c.ConfigTagRule)).?)));
    tr.?[0] = std.mem.zeroes(c.ConfigTagRule);
    tr.?[0].layout_name = strdup("tile");
    tr.?[0].monitor_name = strdup("DP-1");
    c.config.tag_rules = @ptrCast(tr);
    c.config.tag_rules_count = 1;

    const mr = @as(?[*]c.ConfigMonitorRule, @ptrCast(@alignCast(malloc(@sizeOf(c.ConfigMonitorRule)).?)));
    mr.?[0] = std.mem.zeroes(c.ConfigMonitorRule);
    mr.?[0].name = strdup("DP-1");
    mr.?[0].icc = strdup("/tmp/x.icc");
    c.config.monitor_rules = @ptrCast(mr);
    c.config.monitor_rules_count = 1;

    const lr = @as(?[*]c.ConfigLayerRule, @ptrCast(@alignCast(malloc(@sizeOf(c.ConfigLayerRule)).?)));
    lr.?[0] = std.mem.zeroes(c.ConfigLayerRule);
    lr.?[0].layer_name = strdup("waybar");
    c.config.layer_rules = @ptrCast(lr);
    c.config.layer_rules_count = 1;

    // env
    const env_arr = @as(?[*]?*c.ConfigEnv, @ptrCast(@alignCast(malloc(@sizeOf(?*c.ConfigEnv)).?)));
    const env = @as(?*c.ConfigEnv, @ptrCast(@alignCast(malloc(@sizeOf(c.ConfigEnv)).?)));
    env.?.* = .{ .type = strdup("env"), .value = strdup("X=1") };
    env_arr.?[0] = env;
    c.config.env = @ptrCast(env_arr);
    c.config.env_count = 1;

    // vars
    const var_arr = @as(?[*]?*c.ConfigVar, @ptrCast(@alignCast(malloc(@sizeOf(?*c.ConfigVar)).?)));
    const v = @as(?*c.ConfigVar, @ptrCast(@alignCast(malloc(@sizeOf(c.ConfigVar)).?)));
    v.?.* = .{ .name = strdup("term"), .value = strdup("foot") };
    var_arr.?[0] = v;
    c.config.vars = @ptrCast(var_arr);
    c.config.vars_count = 1;

    // exec + exec_once
    const exec_arr = @as(?[*]?[*:0]u8, @ptrCast(@alignCast(malloc(@sizeOf(?[*:0]u8)).?)));
    exec_arr.?[0] = strdup("foot");
    c.config.exec = @ptrCast(exec_arr);
    c.config.exec_count = 1;
    const exec_once_arr = @as(?[*]?[*:0]u8, @ptrCast(@alignCast(malloc(@sizeOf(?[*:0]u8)).?)));
    exec_once_arr.?[0] = strdup("once");
    c.config.exec_once = @ptrCast(exec_once_arr);
    c.config.exec_once_count = 1;

    // preset + strings
    c.config.scroller_proportion_preset = @ptrCast(@alignCast(malloc(4 * @sizeOf(f32)).?));
    c.config.scroller_proportion_preset_count = 1;
    c.config.cursor_theme = strdup("Adwaita");
    c.config.bar_clock_format = strdup("%H:%M");
    c.config.idle_command = strdup("idle");
    c.config.resume_command = strdup("resume");
    c.config.jump_labels = strdup("asdf");
    c.config.bardata.font_desc = strdup("mono 10");
    c.config.groupbardata.font_desc = strdup("mono 11");
    c.config.tabbardata.font_desc = strdup("mono 12");
    c.config.jumplabeldata.font_desc = strdup("mono 13");

    const cl_arr = @as(?[*]?[*:0]u8, @ptrCast(@alignCast(malloc(@sizeOf(?[*:0]u8)).?)));
    cl_arr.?[0] = strdup("master");
    c.config.circle_layout = @ptrCast(cl_arr);
    c.config.circle_layout_count = 1;

    free_config();

    try testing.expect(c.config.window_rules == null);
    try testing.expectEqual(@as(i32, 0), c.config.window_rules_count);
    try testing.expect(c.config.device_rules == null);
    try testing.expect(c.config.key_bindings == null);
    try testing.expect(c.config.mouse_bindings == null);
    try testing.expect(c.config.axis_bindings == null);
    try testing.expect(c.config.switch_bindings == null);
    try testing.expect(c.config.gesture_bindings == null);
    try testing.expect(c.config.tag_rules == null);
    try testing.expect(c.config.monitor_rules == null);
    try testing.expect(c.config.layer_rules == null);
    try testing.expect(c.config.env == null);
    try testing.expect(c.config.vars == null);
    try testing.expect(c.config.exec == null);
    try testing.expect(c.config.exec_once == null);
    try testing.expect(c.config.scroller_proportion_preset == null);
    try testing.expect(c.config.cursor_theme == null);
    try testing.expect(c.config.bar_clock_format == null);
    try testing.expect(c.config.idle_command == null);
    try testing.expect(c.config.resume_command == null);
    try testing.expect(c.config.jump_labels == null);
    try testing.expect(c.config.bardata.font_desc == null);
    try testing.expect(c.config.groupbardata.font_desc == null);
    try testing.expect(c.config.tabbardata.font_desc == null);
    try testing.expect(c.config.jumplabeldata.font_desc == null);
    try testing.expect(c.config.circle_layout == null);
    try testing.expectEqual(@as(c_int, 1), stub_cleanup_keymap_calls);

    // idempotent (second call must not double-free)
    free_config();
    try testing.expectEqual(@as(c_int, 2), stub_cleanup_keymap_calls);
}
