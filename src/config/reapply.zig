//! Port of src/config/reapply.c (strangler-fig Phase 4, slice 24).
//!
//! Exports the same 21 C symbols; the C twin is filtered from the composer
//! link. This is the hot-reload application layer: it pushes freshly parsed
//! config values into the live session (environment, exec commands, client
//! borders, per-tag rules, monitor rules, blur nodes, cursor style, keyboard
//! repeat/device rules) and ends with a full arrange pass.
//!
//! wl_list_for_each is replaced with explicit circular-list walks plus a
//! container_of helper (offset-based). ISTILED and TAGMASK are replicated
//! inline. wlroots entry points come from the translate-c module; acwm
//! functions stay extern. All orderings and guards mirror the C.
//!
//! Tests live at the bottom and need tests/reapply_stub.c.

const std = @import("std");
const c = @import("cc");

const WLR_ERROR: c_uint = @intCast(c.WLR_ERROR);
const PERTAG_SLOTS: usize = @intCast(c.PERTAG_SLOTS);

// acwm functions (C twin still compiled or ported elsewhere)
extern fn spawn_shell(arg: [*c]const c.Arg) callconv(.c) i32;
extern fn client_set_group_config(cl: *c.Client) callconv(.c) void;
extern fn client_apply_tab_bar_config(cl: *c.Client) callconv(.c) void;
extern fn configure_pointer(wlr_device: ?*c.struct_wlr_input_device, device: ?*c.struct_libinput_device) callconv(.c) void;
extern fn init_baked_points() callconv(.c) void;
extern fn pointer_cursor_activity() callconv(.c) void;
extern fn reset_keyboard_layout() callconv(.c) void;
extern fn arrange(m: *c.Monitor, want_animation: bool, from_view: bool) callconv(.c) void;
extern fn monitor_matches_rule(m: *c.Monitor, rule: *const c.ConfigMonitorRule) callconv(.c) bool;
extern fn apply_rule_to_state(m: *c.Monitor, rule: *const c.ConfigMonitorRule, state: *c.struct_wlr_output_state) callconv(.c) bool;
extern fn acwm_scene_output_commit(scene_output: ?*c.struct_wlr_scene_output, state: *c.struct_wlr_output_state) callconv(.c) bool;
extern fn output_state_setup_hdr(m: *c.Monitor, silent: bool, state: *c.struct_wlr_output_state) callconv(.c) void;
extern fn output_enable_hdr(m: *c.Monitor, state: *c.struct_wlr_output_state, enabled: bool, force: bool) callconv(.c) void;
extern fn handle_output_layout_change(listener: ?*c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn find_device_rule(device: ?*c.struct_wlr_input_device) callconv(.c) ?*c.ConfigDeviceRule;
extern fn device_rule_has_keyboard_settings(rule: ?*c.ConfigDeviceRule) callconv(.c) bool;
extern fn create_standalone_keyboard(input_dev: *c.InputDevice, keyboard: *c.struct_wlr_keyboard, rule: ?*c.ConfigDeviceRule) callconv(.c) void;
extern fn standalone_keyboard_apply_config(group: ?*c.KeyboardGroup, rule: ?*c.ConfigDeviceRule) callconv(.c) void;
extern fn handle_standalone_keyboard_destroy(listener: ?*c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn update_seat_capabilities() callconv(.c) void;
extern fn apply_primary_selection() callconv(.c) void;
extern fn bar_config_reload() callconv(.c) void;
extern fn printstatus(kind: c_uint) callconv(.c) void;
extern fn config_watcher_update() callconv(.c) void;
extern fn rearm_idle_check() callconv(.c) void;
extern fn regex_match(pattern: [*:0]const u8, str: [*:0]const u8) callconv(.c) i32;
extern fn sync_workspaces_to_tag_num(m: *c.Monitor) callconv(.c) void;
extern fn pointer_hide_cursor(data: ?*anyopaque) callconv(.c) i32;
extern fn config_error_nag_update() callconv(.c) void;

// parse_config and cleanup entries are ported in the same library
extern fn parse_config() callconv(.c) bool;
extern var layouts: [14]c.Layout;

extern "c" fn wlr_input_device_is_libinput(device: ?*c.struct_wlr_input_device) bool;
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn snprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ...) c_int;
extern "c" fn strcmp(a: [*:0]const u8, b: [*:0]const u8) c_int;

// IPC_WATCH_ARRANGGE composition
const IPC_WATCH_ARRANGGE: c_uint =
    @as(c_uint, @intCast(c.IPC_WATCH_MONITOR)) |
    @as(c_uint, @intCast(c.IPC_WATCH_CLIENT)) |
    @as(c_uint, @intCast(c.IPC_WATCH_TAGS)) |
    @as(c_uint, @intCast(c.IPC_WATCH_ALL_MONITORS)) |
    @as(c_uint, @intCast(c.IPC_WATCH_ALL_TAGS)) |
    @as(c_uint, @intCast(c.IPC_WATCH_ALL_CLIENTS)) |
    @as(c_uint, @intCast(c.IPC_WATCH_LAST_OPEN_SURFACE)) |
    @as(c_uint, @intCast(c.IPC_WATCH_FOCUSING_CLIENT));

// ---------------------------------------------------------------------------
// list helpers
// ---------------------------------------------------------------------------

fn containerOf(comptime T: type, comptime link_field: []const u8, link: [*c]c.struct_wl_list) *T {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(T, link_field));
}

fn listHead(head: *c.struct_wl_list) [*c]c.struct_wl_list {
    return @ptrCast(head);
}

fn output(m: *c.Monitor) *c.struct_wlr_output {
    return @ptrCast(m.wlr_output);
}

fn isTiled(cl: *c.Client) bool {
    return cl.isfloating == 0 and cl.isminimized == 0 and cl.iskilling == 0 and
        cl.ismaximizescreen == 0 and cl.isfullscreen == 0 and cl.isunglobal == 0;
}

// ---------------------------------------------------------------------------
// environment / exec
// ---------------------------------------------------------------------------

export fn set_env_without_display() callconv(.c) void {
    var i: usize = 0;
    while (i < @as(usize, @intCast(c.config.env_count))) : (i += 1) {
        const env = c.config.env[i];
        if (strcmp(@ptrCast(env.*.type), "DISPLAY") == 0)
            continue;
        _ = setenv(@ptrCast(env.*.type), @ptrCast(env.*.value), 1);
    }
}

export fn set_env_display() callconv(.c) void {
    var i: usize = 0;
    while (i < @as(usize, @intCast(c.config.env_count))) : (i += 1) {
        const env = c.config.env[i];
        if (strcmp(@ptrCast(env.*.type), "DISPLAY") == 0)
            _ = setenv("DISPLAY", @ptrCast(env.*.value), 1);
    }
}

export fn run_exec() callconv(.c) void {
    var arg: c.Arg = std.mem.zeroes(c.Arg);
    var i: usize = 0;
    while (i < @as(usize, @intCast(c.config.exec_count))) : (i += 1) {
        arg.v = c.config.exec[i];
        _ = spawn_shell(&arg);
    }
}

export fn run_exec_once() callconv(.c) void {
    var arg: c.Arg = std.mem.zeroes(c.Arg);
    var i: usize = 0;
    while (i < @as(usize, @intCast(c.config.exec_once_count))) : (i += 1) {
        arg.v = c.config.exec_once[i];
        _ = spawn_shell(&arg);
    }
}

fn applyExplicitXcursorEnv() void {
    var i: usize = 0;
    while (i < @as(usize, @intCast(c.config.env_count))) : (i += 1) {
        const env = c.config.env[i];
        if (env.*.type != null and
            (strcmp(@ptrCast(env.*.type), "XCURSOR_SIZE") == 0 or
                strcmp(@ptrCast(env.*.type), "XCURSOR_THEME") == 0))
        {
            _ = setenv(@ptrCast(env.*.type), @ptrCast(env.*.value), 1);
        }
    }
}

export fn set_xcursor_env() callconv(.c) void {
    var size_str: [16]u8 = undefined;
    if (c.config.cursor_size > 0) {
        _ = snprintf(&size_str, size_str.len, "%d", c.config.cursor_size);
        _ = setenv("XCURSOR_SIZE", @ptrCast(&size_str), 1);
    } else {
        _ = setenv("XCURSOR_SIZE", "24", 1);
    }

    if (c.config.cursor_theme != null)
        _ = setenv("XCURSOR_THEME", @ptrCast(c.config.cursor_theme), 1);

    // Explicit env=XCURSOR_SIZE/XCURSOR_THEME entries take precedence.
    applyExplicitXcursorEnv();
}

// ---------------------------------------------------------------------------
// scene / rootbg / property
// ---------------------------------------------------------------------------

export fn reapply_rootbg() callconv(.c) void {
    c.wlr_scene_rect_set_color(c.server.root_bg, &c.config.rootcolor);
}

export fn reapply_property() callconv(.c) void {
    var pos = c.server.clients.next;
    const head = listHead(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(c.Client, "link", pos);
        if (cl.iskilling == 0) {
            if (cl.no_border == 0 and cl.isfullscreen == 0)
                cl.bw = c.config.borderpx;
            client_set_group_config(cl);
            client_apply_tab_bar_config(cl);
        }
    }
}

// ---------------------------------------------------------------------------
// pointer / tagrule
// ---------------------------------------------------------------------------

export fn reapply_pointer() callconv(.c) void {
    var pos = c.server.input_devices.next;
    const head = listHead(&c.server.input_devices);
    while (pos != head) : (pos = pos.*.next) {
        const id = containerOf(c.InputDevice, "link", pos);
        if (output_device_type(id.wlr_device) != c.WLR_INPUT_DEVICE_POINTER)
            continue;

        const device = id.libinput_device;
        if (c.wlr_input_device_is_libinput(id.wlr_device) and device != null)
            configure_pointer(id.wlr_device, device);
    }
}

fn output_device_type(device: ?*c.struct_wlr_input_device) c_int {
    return @intCast(device.?.type);
}

export fn reapply_tagrule() callconv(.c) void {
    var pos = c.server.monitors.next;
    const head = listHead(&c.server.monitors);
    while (pos != head) : (pos = pos.*.next) {
        const m = containerOf(c.Monitor, "link", pos);
        if (output(m).*.enabled == false)
            continue;
        parse_tagrule(m);
    }
}

// ---------------------------------------------------------------------------
// reset paths
// ---------------------------------------------------------------------------

export fn reset_option() callconv(.c) void {
    init_baked_points();
    pointer_cursor_activity();
    reset_keyboard_layout();
    reset_blur_params();
    set_env_without_display();
    set_env_display();
    run_exec();

    reapply_cursor_style();
    reapply_property();
    reapply_rootbg();
    reapply_keyboard();
    reapply_pointer();
    reapply_master();

    reapply_tagrule();
    reapply_monitor_rules();

    // A global reload must re-apply every monitor, not just the selected one.
    var pos = c.server.monitors.next;
    const head = listHead(&c.server.monitors);
    while (pos != head) : (pos = pos.*.next) {
        const m = containerOf(c.Monitor, "link", pos);
        if (output(m).*.enabled)
            arrange(m, false, false);
    }
}

export fn reset_blur_params() callconv(.c) void {
    if (c.config.blur != 0) {
        var pos = c.server.monitors.next;
        const head = listHead(&c.server.monitors);
        while (pos != head) : (pos = pos.*.next) {
            const m = containerOf(c.Monitor, "link", pos);
            if (m.blur != null)
                c.wlr_scene_node_destroy(&m.blur.*.node);
            m.blur = c.wlr_scene_optimized_blur_create(&c.server.scene.*.tree, 0, 0);
            c.wlr_scene_node_reparent(&m.blur.*.node, c.server.layers[@intCast(c.LyrBlur)]);
            c.wlr_scene_node_set_position(&m.blur.*.node, m.m.x, m.m.y);
            c.wlr_scene_optimized_blur_set_size(m.blur, @intCast(m.m.width), @intCast(m.m.height));
            c.wlr_scene_set_blur_data(
                c.server.scene,
                c.config.blur_params.num_passes,
                @intFromFloat(c.config.blur_params.radius),
                c.config.blur_params.noise,
                c.config.blur_params.brightness,
                c.config.blur_params.contrast,
                c.config.blur_params.saturation,
            );
        }
    } else {
        var pos = c.server.monitors.next;
        const head = listHead(&c.server.monitors);
        while (pos != head) : (pos = pos.*.next) {
            const m = containerOf(c.Monitor, "link", pos);
            if (m.blur != null) {
                c.wlr_scene_node_destroy(&m.blur.*.node);
                m.blur = null;
            }
        }
    }
}

export fn reapply_monitor_rules() callconv(.c) void {
    var pos = c.server.monitors.next;
    const head = listHead(&c.server.monitors);
    while (pos != head) : (pos = pos.*.next) {
        const m = containerOf(c.Monitor, "link", pos);
        const out = output(m);
        const was_enabled = out.*.enabled;

        var mr: ?*c.ConfigMonitorRule = null;
        // Match disabled outputs too, so a rule can re-enable them.
        var ji: c_int = c.config.monitor_rules_count - 1;
        while (ji >= 0) : (ji -= 1) {
            if (monitor_matches_rule(m, @ptrCast(&c.config.monitor_rules[@intCast(ji)]))) {
                mr = @ptrCast(&c.config.monitor_rules[@intCast(ji)]);
                break;
            }
        }

        if (mr) |rule| {
            _ = apply_rule_to_state(m, rule, &m.pending);
        } else {
            c.wlr_output_state_set_enabled(&m.pending, true);
        }

        // Enable the output first so it can safely enter the layout.
        if (m.pending.enabled and !out.*.enabled and
            !acwm_scene_output_commit(m.scene_output, &m.pending))
            continue;

        if (mr != null and out.*.enabled) {
            const rule = mr.?;
            if (rule.x == std.math.maxInt(i32) and rule.y == std.math.maxInt(i32)) {
                if (!was_enabled)
                    _ = c.wlr_output_layout_add_auto(c.server.output_layout, out);
            } else {
                const mx: i32 = if (rule.x == std.math.maxInt(i32)) m.m.x else rule.x;
                const my: i32 = if (rule.y == std.math.maxInt(i32)) m.m.y else rule.y;
                _ = c.wlr_output_layout_add(c.server.output_layout, out, mx, my);
            }
        }

        // HDR takes effect only in a commit carrying a buffer.
        const was_hdr = m.is_hdr_enabling;
        if (m.hdr_enable) {
            output_state_setup_hdr(m, false, &m.pending);
        } else {
            output_enable_hdr(m, &m.pending, false, false);
        }

        if (m.is_hdr_enabling != was_hdr) {
            m.pending.allow_reconfiguration = true;
            if (m.scene_output != null)
                c.wlr_damage_ring_add_whole(&m.scene_output.*.damage_ring);
        }

        if (!acwm_scene_output_commit(m.scene_output, &m.pending)) {
            if (m.hdr_enable)
                output_state_setup_hdr(m, true, &m.pending);
        }

        c.wlr_output_schedule_frame(out);
        c.wlr_output_effective_resolution(out, &m.m.width, &m.m.height);
    }

    handle_output_layout_change(null, null);
}

// ---------------------------------------------------------------------------
// cursor style
// ---------------------------------------------------------------------------

export fn reapply_cursor_style() callconv(.c) void {
    if (c.server.hide_cursor_source != null) {
        _ = c.wl_event_source_timer_update(c.server.hide_cursor_source, 0);
        _ = c.wl_event_source_remove(c.server.hide_cursor_source);
        c.server.hide_cursor_source = null;
    }

    c.wlr_cursor_unset_image(c.server.cursor);
    c.wlr_cursor_set_surface(c.server.cursor, null, 0, 0);

    if (c.server.cursor_manager != null) {
        c.wlr_xcursor_manager_destroy(c.server.cursor_manager);
        c.server.cursor_manager = null;
    }

    set_xcursor_env();

    c.server.cursor_manager = c.wlr_xcursor_manager_create(c.config.cursor_theme, c.config.cursor_size);

    var pos = c.server.monitors.next;
    const head = listHead(&c.server.monitors);
    while (pos != head) : (pos = pos.*.next) {
        const m = containerOf(c.Monitor, "link", pos);
        _ = c.wlr_xcursor_manager_load(c.server.cursor_manager, output(m).*.scale);
    }

    c.wlr_cursor_set_xcursor(c.server.cursor, c.server.cursor_manager, "left_ptr");

    c.server.hide_cursor_source = c.wl_event_loop_add_timer(
        c.wl_display_get_event_loop(c.server.display),
        pointer_hide_cursor,
        c.server.cursor,
    );
    if (c.server.cursor_hidden) {
        c.wlr_cursor_unset_image(c.server.cursor);
    } else {
        _ = c.wl_event_source_timer_update(
            c.server.hide_cursor_source,
            @intCast(c.config.cursor_hide_timeout * 1000),
        );
    }
}

// ---------------------------------------------------------------------------
// keyboard
// ---------------------------------------------------------------------------

export fn reapply_keyboard() callconv(.c) void {
    const group = c.server.keyboard_group;
    if (group != null) {
        c.wlr_keyboard_set_repeat_info(
            &group.*.wlr_group.*.keyboard,
            c.config.repeat_rate,
            c.config.repeat_delay,
        );
    }

    var pos = c.server.input_devices.next;
    const head = listHead(&c.server.input_devices);
    while (pos != head) : (pos = pos.*.next) {
        const id = containerOf(c.InputDevice, "link", pos);
        if (output_device_type(id.wlr_device) != c.WLR_INPUT_DEVICE_KEYBOARD)
            continue;

        const rule = find_device_rule(id.wlr_device);
        const want_standalone = rule != null and device_rule_has_keyboard_settings(rule);

        if (want_standalone and !id.standalone) {
            const kb: *c.struct_wlr_keyboard = @ptrCast(@alignCast(id.device_data orelse continue));
            if (group != null)
                _ = c.wlr_keyboard_group_remove_keyboard(group.*.wlr_group, kb);
            id.standalone = true;
            create_standalone_keyboard(id, kb, rule);
        } else if (!want_standalone and id.standalone) {
            const g: ?*c.KeyboardGroup = @ptrCast(@alignCast(id.device_data));
            const kb: ?*c.struct_wlr_keyboard = if (g) |grp| grp.*.keyboard else null;
            if (g) |grp|
                handle_standalone_keyboard_destroy(&grp.*.destroy, null);
            id.standalone = false;
            id.device_data = @ptrCast(kb);
            if (kb) |keyboard| {
                if (group != null and group.*.keyboard != null)
                    _ = c.wlr_keyboard_set_keymap(keyboard, group.*.keyboard.*.keymap);
                c.wlr_keyboard_notify_modifiers(keyboard, 0, 0, c.server.locked_modifiers, 0);
                if (group != null)
                    _ = c.wlr_keyboard_group_add_keyboard(group.*.wlr_group, keyboard);
                c.wlr_keyboard_set_repeat_info(keyboard, c.config.repeat_rate, c.config.repeat_delay);
            }
        } else if (want_standalone) {
            const g: ?*c.KeyboardGroup = @ptrCast(@alignCast(id.device_data));
            if (g) |grp|
                standalone_keyboard_apply_config(grp, rule);
        } else {
            const kb: *c.struct_wlr_keyboard = @ptrCast(@alignCast(id.device_data orelse continue));
            c.wlr_keyboard_set_repeat_info(kb, c.config.repeat_rate, c.config.repeat_delay);
        }
    }
}

// ---------------------------------------------------------------------------
// pertag / master
// ---------------------------------------------------------------------------

export fn reapply_master() callconv(.c) void {
    var i: usize = 0;
    while (i < PERTAG_SLOTS) : (i += 1) {
        var pos = c.server.monitors.next;
        const head = listHead(&c.server.monitors);
        while (pos != head) : (pos = pos.*.next) {
            const m = containerOf(c.Monitor, "link", pos);
            if (!output(m).*.enabled)
                continue;
            m.pertag.*.nmasters[i] = @bitCast(c.config.default_nmaster);
            m.pertag.*.mfacts[i] = c.config.default_mfact;
            m.gappih = @bitCast(c.config.gappih);
            m.gappiv = @bitCast(c.config.gappiv);
            m.gappoh = @bitCast(c.config.gappoh);
            m.gappov = @bitCast(c.config.gappov);
            m.special_gappih = @bitCast(c.config.special_gappih);
            m.special_gappiv = @bitCast(c.config.special_gappiv);
            m.special_gappoh = @bitCast(c.config.special_gappoh);
            m.special_gappov = @bitCast(c.config.special_gappov);
        }
    }
}

export fn tag_slot_set_defaults(m: *c.Monitor, tag: u32) callconv(.c) void {
    m.pertag.*.nmasters[tag] = @bitCast(c.config.default_nmaster);
    m.pertag.*.mfacts[tag] = c.config.default_mfact;
    m.pertag.*.config_ltidxs[tag] = &layouts[0];
    m.pertag.*.scroller_default_proportion[tag] = c.config.scroller_default_proportion;
    m.pertag.*.scroller_default_proportion_single[tag] = c.config.scroller_default_proportion_single;
    m.pertag.*.scroller_ignore_proportion_single[tag] = c.config.scroller_ignore_proportion_single;
}

export fn tag_rule_matches_monitor(tr: *const c.ConfigTagRule, m: *c.Monitor) callconv(.c) bool {
    const out = output(m);
    if (tr.monitor_name != null and
        regex_match(@ptrCast(tr.monitor_name), @ptrCast(out.*.name)) == 0)
        return false;
    if (tr.monitor_make != null and
        (out.*.make == null or strcmp(@ptrCast(tr.monitor_make), @ptrCast(out.*.make)) != 0))
        return false;
    if (tr.monitor_model != null and
        (out.*.model == null or strcmp(@ptrCast(tr.monitor_model), @ptrCast(out.*.model)) != 0))
        return false;
    if (tr.monitor_serial != null and
        (out.*.serial == null or strcmp(@ptrCast(tr.monitor_serial), @ptrCast(out.*.serial)) != 0))
        return false;
    return true;
}

export fn tag_rule_apply_to_slot(m: *c.Monitor, tr: *const c.ConfigTagRule, tag: u32) callconv(.c) void {
    var jk: usize = 0;
    while (jk < layouts.len) : (jk += 1) {
        if (tr.layout_name != null and layouts[jk].name != null and
            strcmp(@ptrCast(layouts[jk].name), @ptrCast(tr.layout_name)) == 0)
        {
            m.pertag.*.config_ltidxs[tag] = &layouts[jk];
        }
    }

    if (tr.no_hide >= 0)
        m.pertag.*.no_hide[tag] = tr.no_hide;
    if (tr.nmaster >= 1)
        m.pertag.*.nmasters[tag] = tr.nmaster;
    if (tr.mfact > 0.0)
        m.pertag.*.mfacts[tag] = tr.mfact;
    if (tr.no_render_border >= 0)
        m.pertag.*.no_render_border[tag] = tr.no_render_border;
    if (tr.open_as_floating >= 0)
        m.pertag.*.open_as_floating[tag] = tr.open_as_floating;
    if (tr.scroller_default_proportion > 0.0)
        m.pertag.*.scroller_default_proportion[tag] = tr.scroller_default_proportion;
    if (tr.scroller_default_proportion_single > 0.0)
        m.pertag.*.scroller_default_proportion_single[tag] = tr.scroller_default_proportion_single;
    if (tr.scroller_ignore_proportion_single >= 0)
        m.pertag.*.scroller_ignore_proportion_single[tag] = tr.scroller_ignore_proportion_single;
}

export fn parse_tagrule(m: *c.Monitor) callconv(.c) void {
    var prev_config_ltidxs: [PERTAG_SLOTS][*c]const c.Layout = undefined;
    var i: usize = 0;
    while (i < PERTAG_SLOTS) : (i += 1)
        prev_config_ltidxs[i] = @ptrCast(m.pertag.*.config_ltidxs[i]);

    // Defaults for every tag (inclusive of tag_num).
    i = 0;
    while (i <= @as(usize, @intCast(c.config.tag_num))) : (i += 1)
        tag_slot_set_defaults(m, @intCast(i));

    i = 0;
    while (i < @as(usize, @intCast(c.config.tag_rules_count))) : (i += 1) {
        const tr: *c.ConfigTagRule = @ptrCast(&c.config.tag_rules[i]);
        if (tag_rule_matches_monitor(tr, m) and
            (tr.id_wildcard or tr.id <= c.config.tag_num))
        {
            const tag_id_start: i32 = if (tr.id_wildcard) 0 else tr.id;
            const tag_id_end: i32 = if (tr.id_wildcard) c.config.tag_num else tr.id;
            var ti: i32 = tag_id_start;
            while (ti <= tag_id_end) : (ti += 1)
                tag_rule_apply_to_slot(m, tr, @intCast(ti));
        }
    }

    i = 0;
    while (i <= @as(usize, @intCast(c.config.tag_num))) : (i += 1) {
        if (prev_config_ltidxs[i] != @as([*c]const c.Layout, @ptrCast(m.pertag.*.config_ltidxs[i])))
            m.pertag.*.ltidxs[i] = m.pertag.*.config_ltidxs[i];
    }

    i = 1;
    while (i <= @as(usize, @intCast(c.config.tag_num))) : (i += 1) {
        var pos = c.server.clients.next;
        const head = listHead(&c.server.clients);
        while (pos != head) : (pos = pos.*.next) {
            const cl = containerOf(c.Client, "link", pos);
            const bit: u32 = @as(u32, 1) << @intCast(i - 1);
            if ((cl.tags & bit & c.server.tagmask) != 0 and isTiled(cl)) {
                if (m.pertag.*.mfacts[i] > 0.0)
                    cl.master_mfact_per = m.pertag.*.mfacts[i];
            }
        }
    }
}

export fn reset_tag(old_tag_num: c_int) callconv(.c) void {
    if (c.config.tag_num != old_tag_num) {
        const last_tag_mask: u32 = @as(u32, 1) << @intCast(c.config.tag_num - 1);

        var pos = c.server.clients.next;
        var head = listHead(&c.server.clients);
        while (pos != head) : (pos = pos.*.next) {
            const cl = containerOf(c.Client, "link", pos);
            if ((cl.tags & ~c.server.tagmask) != 0) {
                cl.tags = last_tag_mask;
                cl.oldtags = last_tag_mask;
            }
        }

        pos = c.server.monitors.next;
        head = listHead(&c.server.monitors);
        while (pos != head) : (pos = pos.*.next) {
            const m = containerOf(c.Monitor, "link", pos);
            if (!output(m).*.enabled)
                continue;
            m.tagset[0] &= c.server.tagmask;
            m.tagset[1] &= c.server.tagmask;
            if (m.tagset[m.seltags] == 0)
                m.tagset[m.seltags] = last_tag_mask;
            if (m.pertag.*.curtag > @as(u32, @intCast(c.config.tag_num)))
                m.pertag.*.curtag = @intCast(c.config.tag_num);
            if (m.pertag.*.prevtag > @as(u32, @intCast(c.config.tag_num)))
                m.pertag.*.prevtag = @intCast(c.config.tag_num);
            sync_workspaces_to_tag_num(m);
        }
    }
}

export fn reload_config(arg: ?*const c.Arg) callconv(.c) i32 {
    _ = arg;
    const old_tag_num = c.config.tag_num;
    _ = parse_config();
    reset_tag(old_tag_num);
    reset_option();
    update_seat_capabilities();
    apply_primary_selection();
    bar_config_reload();
    printstatus(IPC_WATCH_ARRANGGE);
    config_watcher_update();
    rearm_idle_check();
    return 1;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: see tests/reapply_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_spawn_calls: c_int;
extern var stub_spawn_arg: [256]u8;
extern var stub_configure_pointer_calls: c_int;
extern var stub_client_property_calls: c_int;
extern var stub_arrange_calls: c_int;
extern var stub_parse_config_calls: c_int;
extern var stub_update_seat_calls: c_int;
extern var stub_primary_selection_calls: c_int;
extern var stub_bar_reload_calls: c_int;
extern var stub_printstatus_calls: c_int;
extern var stub_watcher_update_calls: c_int;
extern var stub_idle_rearm_calls: c_int;
extern var stub_sync_workspaces_calls: c_int;
extern var stub_regex_result: c_int;
extern var stub_monitor_matches: c_int;
extern var stub_apply_rule_calls: c_int;
extern var stub_commit_result: c_int;

extern "c" fn getenv(name: [*:0]const u8) ?[*:0]u8;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;
extern "c" fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern "c" fn malloc(size: usize) ?*anyopaque;

fn resetStub() void {
    stub_spawn_calls = 0;
    stub_spawn_arg[0] = 0;
    stub_configure_pointer_calls = 0;
    stub_client_property_calls = 0;
    stub_arrange_calls = 0;
    stub_parse_config_calls = 0;
    stub_update_seat_calls = 0;
    stub_primary_selection_calls = 0;
    stub_bar_reload_calls = 0;
    stub_printstatus_calls = 0;
    stub_watcher_update_calls = 0;
    stub_idle_rearm_calls = 0;
    stub_sync_workspaces_calls = 0;
    stub_regex_result = 1;
    stub_monitor_matches = 1;
    stub_apply_rule_calls = 0;
    stub_commit_result = 1;
}

fn listInit(head: *c.struct_wl_list) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

fn listInsert(head: *c.struct_wl_list, link: *c.struct_wl_list) void {
    link.next = head.next;
    link.prev = @ptrCast(head);
    head.next.*.prev = @ptrCast(link);
    head.next = @ptrCast(link);
}

fn span(p: [*]const u8) []const u8 {
    return std.mem.sliceTo(@as([*:0]const u8, @ptrCast(p)), 0);
}

fn getenvSpan(name: [*:0]const u8) []const u8 {
    const v = getenv(name) orelse return "";
    return span(v);
}

test "set_env functions skip and apply DISPLAY correctly" {
    c.config = std.mem.zeroes(c.Config);
    var envs: [2]?*c.ConfigEnv = undefined;
    const e1: *c.ConfigEnv = @ptrCast(@alignCast(malloc(@sizeOf(c.ConfigEnv)).?));
    e1.* = .{ .type = strdup("FOO"), .value = strdup("bar") };
    const e2: *c.ConfigEnv = @ptrCast(@alignCast(malloc(@sizeOf(c.ConfigEnv)).?));
    e2.* = .{ .type = strdup("DISPLAY"), .value = strdup(":9") };
    envs[0] = e1;
    envs[1] = e2;
    c.config.env = @ptrCast(&envs);
    c.config.env_count = 2;

    _ = unsetenv("FOO");
    _ = unsetenv("DISPLAY");
    set_env_without_display();
    try testing.expectEqualStrings("bar", getenvSpan("FOO"));
    try testing.expectEqualStrings("", getenvSpan("DISPLAY"));

    set_env_display();
    try testing.expectEqualStrings(":9", getenvSpan("DISPLAY"));
}

test "run_exec and run_exec_once route commands through spawn_shell" {
    c.config = std.mem.zeroes(c.Config);
    resetStub();

    var execs: [1]?[*:0]u8 = .{strdup("foot")};
    c.config.exec = @ptrCast(&execs);
    c.config.exec_count = 1;
    run_exec();
    try testing.expectEqual(@as(c_int, 1), stub_spawn_calls);
    try testing.expectEqualStrings("foot", span(&stub_spawn_arg));

    resetStub();
    var once: [1]?[*:0]u8 = .{strdup("welcome")};
    c.config.exec_once = @ptrCast(&once);
    c.config.exec_once_count = 1;
    run_exec_once();
    try testing.expectEqual(@as(c_int, 1), stub_spawn_calls);
    try testing.expectEqualStrings("welcome", span(&stub_spawn_arg));
}

test "set_xcursor_env derives and lets explicit env entries win" {
    c.config = std.mem.zeroes(c.Config);
    c.config.cursor_size = 32;
    c.config.cursor_theme = strdup("Adwaita");
    _ = unsetenv("XCURSOR_SIZE");
    _ = unsetenv("XCURSOR_THEME");

    set_xcursor_env();
    try testing.expectEqualStrings("32", getenvSpan("XCURSOR_SIZE"));
    try testing.expectEqualStrings("Adwaita", getenvSpan("XCURSOR_THEME"));

    // explicit env= entries take precedence
    var envs: [1]?*c.ConfigEnv = undefined;
    const e1: *c.ConfigEnv = @ptrCast(@alignCast(malloc(@sizeOf(c.ConfigEnv)).?));
    e1.* = .{ .type = strdup("XCURSOR_SIZE"), .value = strdup("48") };
    envs[0] = e1;
    c.config.env = @ptrCast(&envs);
    c.config.env_count = 1;
    set_xcursor_env();
    try testing.expectEqualStrings("48", getenvSpan("XCURSOR_SIZE"));

    // no size -> 24 fallback
    c.config.cursor_size = 0;
    c.config.env_count = 0;
    c.config.cursor_theme = null;
    set_xcursor_env();
    try testing.expectEqualStrings("24", getenvSpan("XCURSOR_SIZE"));
}

test "tag_slot_set_defaults copies config values" {
    c.config = std.mem.zeroes(c.Config);
    c.config.default_nmaster = 3;
    c.config.default_mfact = 0.65;
    c.config.scroller_default_proportion = 0.8;
    c.config.scroller_default_proportion_single = 0.9;
    c.config.scroller_ignore_proportion_single = 1;

    var m: c.Monitor = std.mem.zeroes(c.Monitor);
    var pertag: c.Pertag = std.mem.zeroes(c.Pertag);
    m.pertag = @ptrCast(&pertag);

    tag_slot_set_defaults(&m, 2);
    try testing.expectEqual(@as(i32, 3), pertag.nmasters[2]);
    try testing.expectEqual(@as(f32, 0.65), pertag.mfacts[2]);
    try testing.expectEqual(@as(f32, 0.8), pertag.scroller_default_proportion[2]);
    try testing.expectEqual(@as(f32, 0.9), pertag.scroller_default_proportion_single[2]);
    try testing.expectEqual(@as(i32, 1), pertag.scroller_ignore_proportion_single[2]);
    try testing.expect(pertag.config_ltidxs[2] == &layouts[0]);
}

test "tag_rule_matches_monitor checks name regex and make/model/serial" {
    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    out.name = @ptrCast(&name_buf);
    out.make = @ptrCast(&make_buf);
    out.model = @ptrCast(&model_buf);
    out.serial = @ptrCast(&serial_buf);
    var m: c.Monitor = std.mem.zeroes(c.Monitor);
    m.wlr_output = @ptrCast(&out);

    var tr: c.ConfigTagRule = std.mem.zeroes(c.ConfigTagRule);
    tr.monitor_name = @ptrCast(&name_pattern);
    resetStub();
    try testing.expect(tag_rule_matches_monitor(&tr, &m));

    stub_regex_result = 0;
    try testing.expect(!tag_rule_matches_monitor(&tr, &m));

    // exact matchers
    var tr2: c.ConfigTagRule = std.mem.zeroes(c.ConfigTagRule);
    tr2.monitor_make = @ptrCast(&make_buf);
    tr2.monitor_model = @ptrCast(&model_buf);
    tr2.monitor_serial = @ptrCast(&serial_buf);
    try testing.expect(tag_rule_matches_monitor(&tr2, &m));

    var other: [5:0]u8 = "Other".*;
    var tr3: c.ConfigTagRule = std.mem.zeroes(c.ConfigTagRule);
    tr3.monitor_make = @ptrCast(&other);
    try testing.expect(!tag_rule_matches_monitor(&tr3, &m));

    // a NULL output field fails a non-NULL rule field
    out.make = null;
    try testing.expect(!tag_rule_matches_monitor(&tr2, &m));
}

var name_pattern: [4:0]u8 = "DP-*".*;
var name_buf: [4:0]u8 = "DP-1".*;
var make_buf: [4:0]u8 = "Acme".*;
var model_buf: [2:0]u8 = "X1".*;
var serial_buf: [2:0]u8 = "42".*;

test "tag_rule_apply_to_slot sets layout and clamped fields" {
    c.config = std.mem.zeroes(c.Config);
    var m: c.Monitor = std.mem.zeroes(c.Monitor);
    var pertag: c.Pertag = std.mem.zeroes(c.Pertag);
    m.pertag = @ptrCast(&pertag);

    layouts[0].name = "tile";
    layouts[1].name = "grid";
    pertag.config_ltidxs[3] = &layouts[0];

    var tr: c.ConfigTagRule = std.mem.zeroes(c.ConfigTagRule);
    tr.layout_name = @ptrCast(@constCast(layouts[1].name));
    tr.no_hide = 1;
    tr.nmaster = 4;
    tr.mfact = 0.7;
    tr.no_render_border = 1;
    tr.open_as_floating = -1;
    tr.scroller_default_proportion = 0.6;
    tr.scroller_ignore_proportion_single = -1;

    tag_rule_apply_to_slot(&m, &tr, 3);
    try testing.expect(pertag.config_ltidxs[3] == &layouts[1]);
    try testing.expectEqual(@as(i32, 1), pertag.no_hide[3]);
    try testing.expectEqual(@as(i32, 4), pertag.nmasters[3]);
    try testing.expectEqual(@as(f32, 0.7), pertag.mfacts[3]);
    try testing.expectEqual(@as(i32, 1), pertag.no_render_border[3]);
    try testing.expectEqual(@as(f32, 0.6), pertag.scroller_default_proportion[3]);
    try testing.expectEqual(@as(i32, 0), pertag.open_as_floating[3]); // untouched (zeroed)
    try testing.expectEqual(@as(i32, 0), pertag.scroller_ignore_proportion_single[3]);
}

test "parse_tagrule applies defaults, rules and per-client mfacts" {
    c.config = std.mem.zeroes(c.Config);
    c.config.tag_num = 9;
    c.config.default_nmaster = 1;
    c.config.default_mfact = 0.5;
    c.server.tagmask = 511;

    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    out.enabled = true;
    out.name = @ptrCast(&name_buf);
    var m: c.Monitor = std.mem.zeroes(c.Monitor);
    var pertag: c.Pertag = std.mem.zeroes(c.Pertag);
    m.pertag = @ptrCast(&pertag);
    m.wlr_output = @ptrCast(&out);

    // one wildcard rule overriding mfact for all tags
    var rules: [1]c.ConfigTagRule = .{std.mem.zeroes(c.ConfigTagRule)};
    rules[0].id_wildcard = true;
    rules[0].mfact = 0.8;
    c.config.tag_rules = @ptrCast(&rules);
    c.config.tag_rules_count = 1;

    // one tiled client on tag 1
    listInit(&c.server.clients);
    var cl: c.Client = std.mem.zeroes(c.Client);
    cl.tags = 1;
    listInsert(&c.server.clients, &cl.link);
    defer listInit(&c.server.clients);

    parse_tagrule(&m);

    try testing.expectEqual(@as(f32, 0.8), pertag.mfacts[0]);
    try testing.expectEqual(@as(f32, 0.8), pertag.mfacts[9]);
    try testing.expect(@abs(cl.master_mfact_per - 0.8) < 1e-6);
}

test "reset_tag remaps clients and masks monitor tags" {
    c.config = std.mem.zeroes(c.Config);
    c.config.tag_num = 5;
    c.server.tagmask = 31; // 5 tags

    listInit(&c.server.clients);
    var cl: c.Client = std.mem.zeroes(c.Client);
    cl.tags = 1 << 7; // beyond the new mask
    cl.oldtags = 1 << 7;
    listInsert(&c.server.clients, &cl.link);
    defer listInit(&c.server.clients);

    listInit(&c.server.monitors);
    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    out.enabled = true;
    var m: c.Monitor = std.mem.zeroes(c.Monitor);
    var pertag: c.Pertag = std.mem.zeroes(c.Pertag);
    pertag.curtag = 9;
    pertag.prevtag = 12;
    m.pertag = @ptrCast(&pertag);
    m.wlr_output = @ptrCast(&out);
    m.tagset[0] = 0xFFFF;
    m.tagset[1] = 0xFFFF;
    m.seltags = 0;
    listInsert(&c.server.monitors, &m.link);
    defer listInit(&c.server.monitors);

    resetStub();
    reset_tag(9); // tag_num changed from 9 to 5
    try testing.expectEqual(@as(u32, 16), cl.tags); // 1 << (5-1)
    try testing.expectEqual(@as(u32, 16), cl.oldtags);
    try testing.expectEqual(@as(u32, 31), m.tagset[0]);
    try testing.expectEqual(@as(u32, 5), pertag.curtag);
    try testing.expectEqual(@as(u32, 5), pertag.prevtag);
    try testing.expectEqual(@as(c_int, 1), stub_sync_workspaces_calls);

    // unchanged tag count: no-op
    resetStub();
    reset_tag(5);
    try testing.expectEqual(@as(c_int, 0), stub_sync_workspaces_calls);
}

test "reapply_master copies defaults and gaps to every enabled monitor" {
    c.config = std.mem.zeroes(c.Config);
    c.config.default_nmaster = 2;
    c.config.default_mfact = 0.6;
    c.config.gappih = 7;
    c.config.gappiv = 8;
    c.config.gappoh = 9;
    c.config.gappov = 10;
    c.config.special_gappih = 11;
    c.config.special_gappiv = 12;
    c.config.special_gappoh = 13;
    c.config.special_gappov = 14;

    listInit(&c.server.monitors);
    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    out.enabled = true;
    var m: c.Monitor = std.mem.zeroes(c.Monitor);
    var pertag: c.Pertag = std.mem.zeroes(c.Pertag);
    m.pertag = @ptrCast(&pertag);
    m.wlr_output = @ptrCast(&out);
    listInsert(&c.server.monitors, &m.link);
    defer listInit(&c.server.monitors);

    reapply_master();

    try testing.expectEqual(@as(i32, 2), pertag.nmasters[0]);
    try testing.expectEqual(@as(i32, 2), pertag.nmasters[PERTAG_SLOTS - 1]);
    try testing.expectEqual(@as(f32, 0.6), pertag.mfacts[0]);
    try testing.expectEqual(@as(i32, 7), m.gappih);
    try testing.expectEqual(@as(i32, 14), m.special_gappov);
}

test "reapply_property updates tiled border widths" {
    c.config = std.mem.zeroes(c.Config);
    c.config.borderpx = 3;

    listInit(&c.server.clients);
    var active: c.Client = std.mem.zeroes(c.Client);
    active.bw = 1;
    listInsert(&c.server.clients, &active.link);
    var killing: c.Client = std.mem.zeroes(c.Client);
    killing.bw = 5;
    killing.iskilling = 1;
    listInsert(&c.server.clients, &killing.link);
    defer listInit(&c.server.clients);

    resetStub();
    reapply_property();
    try testing.expectEqual(@as(u32, 3), active.bw);
    try testing.expectEqual(@as(u32, 5), killing.bw);
    try testing.expectEqual(@as(c_int, 1), stub_client_property_calls);
}

test "reapply_pointer configures libinput pointers" {
    listInit(&c.server.input_devices);
    var wdev: c.struct_wlr_input_device = std.mem.zeroes(c.struct_wlr_input_device);
    wdev.type = c.WLR_INPUT_DEVICE_POINTER;
    var id: c.InputDevice = std.mem.zeroes(c.InputDevice);
    id.wlr_device = @ptrCast(&wdev);
    id.libinput_device = @ptrFromInt(@alignOf(usize));
    listInsert(&c.server.input_devices, &id.link);

    var keyboard_dev: c.struct_wlr_input_device = std.mem.zeroes(c.struct_wlr_input_device);
    keyboard_dev.type = c.WLR_INPUT_DEVICE_KEYBOARD;
    var id2: c.InputDevice = std.mem.zeroes(c.InputDevice);
    id2.wlr_device = @ptrCast(&keyboard_dev);
    listInsert(&c.server.input_devices, &id2.link);
    defer listInit(&c.server.input_devices);

    resetStub();
    reapply_pointer();
    try testing.expectEqual(@as(c_int, 1), stub_configure_pointer_calls);
}

test "reload_config runs the reload steps in order" {
    c.config = std.mem.zeroes(c.Config);
    c.config.tag_num = 9;
    resetStub();

    const rc = reload_config(null);
    try testing.expectEqual(@as(i32, 1), rc);
    try testing.expectEqual(@as(c_int, 1), stub_parse_config_calls);
    try testing.expectEqual(@as(c_int, 1), stub_update_seat_calls);
    try testing.expectEqual(@as(c_int, 1), stub_primary_selection_calls);
    try testing.expectEqual(@as(c_int, 1), stub_bar_reload_calls);
    try testing.expectEqual(@as(c_int, 1), stub_printstatus_calls);
    try testing.expectEqual(@as(c_int, 1), stub_watcher_update_calls);
    try testing.expectEqual(@as(c_int, 1), stub_idle_rearm_calls);
}
