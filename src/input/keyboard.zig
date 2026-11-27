//! Port of input/keyboard.c (Phase 5, input slice 5, slice 72).

const std = @import("std");
const c = @import("cc");
const build_options = @import("build_options");

const Client = c.Client;
const Monitor = c.Monitor;
const InputDevice = c.InputDevice;
const KeyboardGroup = c.KeyboardGroup;
const ConfigDeviceRule = c.ConfigDeviceRule;
const ConfigWinRule = c.ConfigWinRule;
const KeyboardShortcutsInhibitor = c.KeyboardShortcutsInhibitor;
const LayerSurface = c.LayerSurface;

extern fn ipc_notify_device_event(dev: [*c]c.struct_wlr_input_device) callconv(.c) void;
extern fn wlr_input_device_is_libinput(device: [*c]c.struct_wlr_input_device) callconv(.c) bool;
extern fn wlr_libinput_get_device_handle(device: [*c]c.struct_wlr_input_device) callconv(.c) ?*c.struct_libinput_device;
extern fn libinput_device_get_id_vendor(device: [*c]c.struct_libinput_device) callconv(.c) c_int;
extern fn libinput_device_get_id_product(device: [*c]c.struct_libinput_device) callconv(.c) c_int;
extern fn libinput_device_config_tap_get_finger_count(device: [*c]c.struct_libinput_device) callconv(.c) c_int;
extern fn seat_device_add(device: [*c]c.struct_wlr_input_device) callconv(.c) void;
extern fn handle_input_device_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn client_focus_top(m: [*c]Monitor) callconv(.c) [*c]Client;
extern fn client_get_appid(cl: [*c]Client) callconv(.c) [*c]const u8;
extern fn client_get_title(cl: [*c]Client) callconv(.c) [*c]const u8;
extern fn client_surface(cl: [*c]Client) callconv(.c) [*c]c.struct_wlr_surface;
extern fn client_focus(cl: [*c]Client, lift: i32) callconv(.c) void;
extern fn regex_match(regex: [*c]const u8, str: [*c]const u8) callconv(.c) bool;
extern fn toplevel_from_wlr_surface(s: [*c]c.struct_wlr_surface, pc: [*c][*c]Client, pl: [*c][*c]LayerSurface) callconv(.c) i32;
extern fn acwm_notify_activity(seat: [*c]c.struct_wlr_seat) callconv(.c) void;
extern fn pointer_hide_cursor(data: ?*anyopaque) callconv(.c) i32;
extern fn session_lock_focus_missing() callconv(.c) bool;
extern fn session_lock_focus_restore() callconv(.c) void;
extern fn switcher_is_active() callconv(.c) bool;
extern fn switcher_close() callconv(.c) void;
extern fn switcher_commit() callconv(.c) void;
extern fn toggle_overview(arg: [*c]const c.Arg) callconv(.c) i32;
extern fn toggle_jump(arg: [*c]const c.Arg) callconv(.c) i32;
extern fn printstatus(t: c.enum_ipc_watch_type) callconv(.c) void;
extern fn acwm_im_keyboard_grab_forward_key(kb: [*c]KeyboardGroup, event: [*c]c.struct_wlr_keyboard_key_event) callconv(.c) bool;
extern fn acwm_im_keyboard_grab_forward_modifiers(kb: [*c]KeyboardGroup) callconv(.c) bool;
extern fn wlr_keyboard_set_keymap(kb: [*c]c.struct_wlr_keyboard, keymap: ?*c.struct_xkb_keymap) callconv(.c) bool;
extern fn wlr_keyboard_notify_modifiers(kb: [*c]c.struct_wlr_keyboard, depressed: u32, latched: u32, locked: u32, group: u32) callconv(.c) void;
extern fn wlr_keyboard_set_repeat_info(kb: [*c]c.struct_wlr_keyboard, rate: i32, delay: i32) callconv(.c) void;
extern fn wlr_keyboard_get_modifiers(kb: [*c]c.struct_wlr_keyboard) callconv(.c) u32;
extern fn wlr_keyboard_group_create() callconv(.c) [*c]c.struct_wlr_keyboard_group;
extern fn wlr_keyboard_group_add_keyboard(group: [*c]c.struct_wlr_keyboard_group, kb: [*c]c.struct_wlr_keyboard) callconv(.c) bool;
extern fn wlr_keyboard_group_destroy(group: [*c]c.struct_wlr_keyboard_group) callconv(.c) void;
extern fn wlr_seat_get_keyboard(seat: [*c]c.struct_wlr_seat) callconv(.c) [*c]c.struct_wlr_keyboard;
extern fn wlr_seat_set_keyboard(seat: [*c]c.struct_wlr_seat, kb: [*c]c.struct_wlr_keyboard) callconv(.c) void;
extern fn wlr_seat_keyboard_enter(seat: [*c]c.struct_wlr_seat, surface: [*c]c.struct_wlr_surface, keycodes: [*c]const u32, num_keycodes: usize, modifiers: [*c]const c.struct_wlr_keyboard_modifiers) callconv(.c) void;
extern fn wlr_seat_keyboard_send_key(seat: [*c]c.struct_wlr_seat, time: u32, key: u32, state: u32) callconv(.c) void;
extern fn wlr_seat_keyboard_notify_key(seat: [*c]c.struct_wlr_seat, time: u32, key: u32, state: u32) callconv(.c) void;
extern fn wlr_seat_keyboard_notify_modifiers(seat: [*c]c.struct_wlr_seat, modifiers: [*c]const c.struct_wlr_keyboard_modifiers) callconv(.c) void;
extern fn wlr_xdg_surface_try_from_wlr_surface(s: [*c]c.struct_wlr_surface) callconv(.c) [*c]c.struct_wlr_xdg_surface;
extern fn wlr_xwayland_surface_try_from_wlr_surface(s: [*c]c.struct_wlr_surface) callconv(.c) [*c]c.struct_wlr_xwayland_surface;
extern fn wlr_keyboard_shortcuts_inhibitor_v1_activate(inhibitor: [*c]c.struct_wlr_keyboard_shortcuts_inhibitor_v1) callconv(.c) void;
extern fn wl_event_source_timer_update(source: ?*c.struct_wl_event_source, ms: i32) callconv(.c) c_int;
extern fn wl_event_source_remove(source: ?*c.struct_wl_event_source) callconv(.c) c_int;
extern fn wl_event_loop_add_timer(loop: ?*c.struct_wl_event_loop, func: ?*const fn (?*anyopaque) callconv(.c) c_int, data: ?*anyopaque) callconv(.c) ?*c.struct_wl_event_source;

fn inputDeviceFromListener(listener: [*c]c.struct_wl_listener) *InputDevice {
    return @ptrFromInt(@intFromPtr(listener) - @offsetOf(InputDevice, "key_watch"));
}

fn groupFromListener(listener: [*c]c.struct_wl_listener, comptime field: []const u8) *KeyboardGroup {
    return @ptrFromInt(@intFromPtr(listener) - @offsetOf(KeyboardGroup, field));
}

fn inhibitorFromListener(listener: [*c]c.struct_wl_listener) *KeyboardShortcutsInhibitor {
    return @ptrFromInt(@intFromPtr(listener) - @offsetOf(KeyboardShortcutsInhibitor, "destroy"));
}

fn hasString(value: []const u8) bool {
    return value.len > 0 and value[0] != 0;
}

export fn handle_keyboard_key_watch(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const id = inputDeviceFromListener(listener);
    ipc_notify_device_event(id.wlr_device);
}

export fn device_rule_has_keyboard_settings(rule: [*c]ConfigDeviceRule) callconv(.c) bool {
    if (rule == null)
        return false;
    const r = rule.*;
    return r.repeat_rate != -1 or r.repeat_delay != -1 or
        hasString(r.kb_rules[0..]) or hasString(r.kb_model[0..]) or
        hasString(r.kb_layout[0..]) or hasString(r.kb_variant[0..]) or
        hasString(r.kb_options[0..]);
}

export fn find_device_rule(device: [*c]c.struct_wlr_input_device) callconv(.c) [*c]ConfigDeviceRule {
    if (device == null or c.config.device_rules == null or c.config.device_rules_count <= 0)
        return null;

    var vendor: i32 = 0;
    var product: i32 = 0;
    if (c.wlr_input_device_is_libinput(device)) {
        const libinput_dev = c.wlr_libinput_get_device_handle(device);
        if (libinput_dev != null) {
            vendor = @intCast(c.libinput_device_get_id_vendor(libinput_dev));
            product = @intCast(c.libinput_device_get_id_product(libinput_dev));
        }
    }
    var identifier: [512]u8 = undefined;
    const name = if (device.*.name != null) device.*.name else @as([*c]u8, @constCast(""));
    _ = c.snprintf(&identifier, identifier.len, "%d:%d:%s", vendor, product, name);

    var i: i32 = 0;
    while (i < c.config.device_rules_count) : (i += 1) {
        const rule = &c.config.device_rules[@intCast(i)];
        if (rule.name == null)
            continue;
        if (c.strcmp(rule.name, device.*.name) == 0 or c.strcmp(rule.name, &identifier) == 0)
            return rule;
    }

    var device_type: ?[*:0]const u8 = null;
    switch (device.*.type) {
        c.WLR_INPUT_DEVICE_KEYBOARD => device_type = "keyboard",
        c.WLR_INPUT_DEVICE_POINTER => {
            if (c.wlr_input_device_is_libinput(device)) {
                const libinput_dev = c.wlr_libinput_get_device_handle(device);
                if (libinput_dev != null and c.libinput_device_config_tap_get_finger_count(libinput_dev) > 0)
                    device_type = "trackpad"
                else
                    device_type = "pointer";
            } else device_type = "pointer";
        },
        c.WLR_INPUT_DEVICE_TOUCH => device_type = "touch",
        c.WLR_INPUT_DEVICE_SWITCH => device_type = "switch",
        c.WLR_INPUT_DEVICE_TABLET => device_type = "tablet",
        c.WLR_INPUT_DEVICE_TABLET_PAD => device_type = "pad",
        else => return null,
    }

    i = 0;
    while (i < c.config.device_rules_count) : (i += 1) {
        const rule = &c.config.device_rules[@intCast(i)];
        if (rule.type[0] != 0 and c.strcmp(&rule.type, device_type.?) == 0)
            return rule;
    }
    return null;
}

export fn keyboard_create(keyboard: [*c]c.struct_wlr_keyboard) callconv(.c) void {
    var input_dev: [*c]InputDevice = null;

    if (c.wlr_input_device_is_libinput(&keyboard.*.base)) {
        const device = c.wlr_libinput_get_device_handle(&keyboard.*.base);
        if (device != null) {
            const raw = c.calloc(1, @sizeOf(InputDevice)) orelse return;
            const dev = @as(*InputDevice, @ptrCast(@alignCast(raw)));
            dev.wlr_device = &keyboard.*.base;
            dev.libinput_device = device;
            dev.device_data = keyboard;
            dev.key_watch.notify = handle_keyboard_key_watch;
            c.wl_signal_add(&keyboard.*.events.key, &dev.key_watch);
            dev.destroy_listener.notify = handle_input_device_destroy;
            c.wl_signal_add(&keyboard.*.base.events.destroy, &dev.destroy_listener);
            c.wl_list_insert(&c.server.input_devices, &dev.link);
            input_dev = dev;
        }
    }

    const rule = find_device_rule(&keyboard.*.base);
    if (rule != null and device_rule_has_keyboard_settings(rule) and input_dev != null) {
        input_dev.*.standalone = true;
        create_standalone_keyboard(input_dev, keyboard, rule);
        return;
    }

    _ = wlr_keyboard_set_keymap(keyboard, c.server.keyboard_group.*.keyboard.*.keymap);
    wlr_keyboard_notify_modifiers(keyboard, 0, 0, c.server.locked_modifiers, 0);
    _ = wlr_keyboard_group_add_keyboard(c.server.keyboard_group.*.wlr_group, keyboard);
}

export fn compile_rule_keymap(rule: [*c]ConfigDeviceRule) callconv(.c) ?*c.struct_xkb_keymap {
    const context = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS);
    if (context == null)
        return null;

    var names = std.mem.zeroes(c.struct_xkb_rule_names);
    if (rule != null) {
        const r = rule.*;
        if (r.kb_rules[0] != 0) names.rules = &r.kb_rules;
        if (r.kb_model[0] != 0) names.model = &r.kb_model;
        if (r.kb_layout[0] != 0) names.layout = &r.kb_layout;
        if (r.kb_variant[0] != 0) names.variant = &r.kb_variant;
        if (r.kb_options[0] != 0) names.options = &r.kb_options;
    }

    const keymap = c.xkb_keymap_new_from_names(context, &names, c.XKB_KEYMAP_COMPILE_NO_FLAGS);
    c.xkb_context_unref(context);
    return keymap;
}

export fn keyboard_repeat(data: ?*anyopaque) callconv(.c) i32 {
    const group = @as(*KeyboardGroup, @ptrCast(@alignCast(data.?)));
    if (group.nsyms == 0 or group.keyboard.*.repeat_info.rate <= 0)
        return 0;

    _ = wl_event_source_timer_update(group.key_repeat_source, @divTrunc(1000, group.keyboard.*.repeat_info.rate));
    var i: i32 = 0;
    while (i < group.nsyms) : (i += 1)
        _ = keyboard_check_keybinding(c.WL_KEYBOARD_KEY_STATE_PRESSED, false, group.mods, group.keysyms[@intCast(i)], group.keycode);
    return 0;
}

export fn is_keyboard_shortcut_inhibitor(surface: [*c]c.struct_wlr_surface) callconv(.c) bool {
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.keyboard_shortcut_inhibitors);
    var pos = c.server.keyboard_shortcut_inhibitors.next;
    while (pos != head) : (pos = pos.*.next) {
        const inhibitor = @as(*KeyboardShortcutsInhibitor, @ptrFromInt(@intFromPtr(pos) - @offsetOf(KeyboardShortcutsInhibitor, "link")));
        if (inhibitor.inhibitor.*.surface == surface)
            return true;
    }
    return false;
}

export fn keyboard_process_global_keypress(last_surface: [*c]c.struct_wlr_surface, keyboard: [*c]c.struct_wlr_keyboard, event: [*c]c.struct_wlr_keyboard_key_event, mods: u32, keysym: c.xkb_keysym_t, keycode: u32) callconv(.c) bool {
    const lastc = client_focus_top(c.server.selected_monitor);
    var keycodes: [32]u32 = std.mem.zeroes([32]u32);
    var reset = false;

    var ji: i32 = 0;
    while (ji < c.config.window_rules_count) : (ji += 1) {
        const r = &c.config.window_rules[@intCast(ji)];
        if (r.globalkeybinding.mod == 0 or
            (r.globalkeybinding.keysymcode.keysym == 0 and
                r.globalkeybinding.keysymcode.keycode.keycode1 == 0 and
                r.globalkeybinding.keysymcode.keycode.keycode2 == 0 and
                r.globalkeybinding.keysymcode.keycode.keycode3 == 0))
            continue;

        const key_matches = (r.globalkeybinding.keysymcode.type == c.KEY_TYPE_SYM and
            r.globalkeybinding.keysymcode.keysym == keysym) or
            (r.globalkeybinding.keysymcode.type == c.KEY_TYPE_CODE and
                (r.globalkeybinding.keysymcode.keycode.keycode1 == keycode or
                    r.globalkeybinding.keysymcode.keycode.keycode2 == keycode or
                    r.globalkeybinding.keysymcode.keycode.keycode3 == keycode));
        if (key_matches and r.globalkeybinding.mod == mods) {
            const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
            var pos = c.server.clients.next;
            while (pos != head) : (pos = pos.*.next) {
                const cl = @as([*c]Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Client, "link")));
                if (cl != null and cl != lastc) {
                    const appid = client_get_appid(cl);
                    const title = client_get_title(cl);
                    const match = (r.title != null and regex_match(r.title, title) and r.id == null) or
                        (r.id != null and regex_match(r.id, appid) and r.title == null) or
                        (r.id != null and regex_match(r.id, appid) and r.title != null and regex_match(r.title, title));
                    if (match) {
                        reset = true;
                        c.wlr_seat_keyboard_enter(c.server.seat, client_surface(cl), &keycodes, 0, &keyboard.*.modifiers);
                        c.wlr_seat_keyboard_send_key(c.server.seat, event.*.time_msec, event.*.keycode, event.*.state);
                        if (reset)
                            c.wlr_seat_keyboard_enter(c.server.seat, last_surface, &keycodes, 0, &keyboard.*.modifiers);
                        return reset;
                    }
                }
            }
        }
    }

    return reset;
}

export fn handle_keyboard_shortcuts_inhibitor_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const inhibitor = inhibitorFromListener(listener);
    c.acwm_error_impl(true, c.WLR_DEBUG, "src/input/keyboard.c", 292, "Removing keyboard shortcuts inhibitor");
    c.wl_list_remove(&inhibitor.link);
    c.wl_list_remove(&inhibitor.destroy.link);
    c.free(inhibitor);
}

export fn handle_keyboard_shortcuts_inhibit_new_inhibitor(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const inhibitor = @as([*c]c.struct_wlr_keyboard_shortcuts_inhibitor_v1, @ptrCast(@alignCast(data.?)));
    if (c.config.allow_shortcuts_inhibit == c.SHORTCUTS_INHIBIT_DISABLE)
        return;

    var cl: [*c]Client = null;
    var l: [*c]LayerSurface = null;
    const surface_type = toplevel_from_wlr_surface(inhibitor.*.surface, &cl, &l);
    if (surface_type < 0)
        return;
    if (surface_type != c.LayerShell and cl != null and cl.*.allow_shortcuts_inhibit == 0)
        return;

    c.acwm_error_impl(true, c.WLR_DEBUG, "src/input/keyboard.c", 319, "Adding keyboard shortcuts inhibitor");
    const raw = c.calloc(1, @sizeOf(KeyboardShortcutsInhibitor)) orelse return;
    const kbsinhibitor = @as(*KeyboardShortcutsInhibitor, @ptrCast(@alignCast(raw)));
    kbsinhibitor.inhibitor = inhibitor;
    kbsinhibitor.destroy.notify = handle_keyboard_shortcuts_inhibitor_destroy;
    c.wl_signal_add(&inhibitor.*.events.destroy, &kbsinhibitor.destroy);
    c.wl_list_insert(&c.server.keyboard_shortcut_inhibitors, &kbsinhibitor.link);
    c.wlr_keyboard_shortcuts_inhibitor_v1_activate(inhibitor);
}

export fn keyboard_sync_keymap(data: ?*anyopaque) callconv(.c) i32 {
    _ = data;
    if (!build_options.xwayland)
        return 0;
    reset_keyboard_layout();
    c.acwm_error_impl(true, c.WLR_INFO, "src/input/keyboard.c", 338, "timer to synckeymap done");
    _ = wl_event_source_timer_update(c.server.sync_keymap, 0);
    return 0;
}

export fn standalone_keyboard_apply_config(group: [*c]KeyboardGroup, rule: [*c]ConfigDeviceRule) callconv(.c) void {
    if (group == null or group.*.keyboard == null)
        return;

    const rate = if (rule != null and rule.*.repeat_rate != -1) rule.*.repeat_rate else c.config.repeat_rate;
    const delay = if (rule != null and rule.*.repeat_delay != -1) rule.*.repeat_delay else c.config.repeat_delay;
    wlr_keyboard_set_repeat_info(group.*.keyboard, rate, delay);

    var keymap = compile_rule_keymap(rule);
    if (keymap == null and rule != null) {
        const name = if (group.*.keyboard.*.base.name != null) group.*.keyboard.*.base.name else @as([*c]u8, @constCast("unknown device"));
        c.acwm_error_impl(false, c.WLR_ERROR, "src/input/keyboard.c", 365,
            "Failed to compile devicerule keymap for %s, falling back to the global layout", name);
        const context = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS);
        if (context != null) {
            keymap = c.xkb_keymap_new_from_names(context, &c.config.xkb_rules, c.XKB_KEYMAP_COMPILE_NO_FLAGS);
            c.xkb_context_unref(context);
        }
    }

    var borrowed = false;
    if (keymap == null and c.server.keyboard_group != null and c.server.keyboard_group.*.keyboard != null and
        c.server.keyboard_group.*.keyboard.*.keymap != null)
    {
        keymap = c.server.keyboard_group.*.keyboard.*.keymap;
        borrowed = true;
    }
    if (keymap == null)
        return;

    _ = wlr_keyboard_set_keymap(group.*.keyboard, keymap);
    if (!borrowed)
        c.xkb_keymap_unref(keymap);
    wlr_keyboard_notify_modifiers(group.*.keyboard, 0, 0, c.server.locked_modifiers, 0);
}

fn listen(listener: *c.struct_wl_listener, signal: *c.struct_wl_signal, handler: *const fn ([*c]c.struct_wl_listener, ?*anyopaque) callconv(.c) void) void {
    listener.notify = handler;
    c.wl_signal_add(signal, listener);
}

export fn create_standalone_keyboard(input_dev: [*c]InputDevice, keyboard: [*c]c.struct_wlr_keyboard, rule: [*c]ConfigDeviceRule) callconv(.c) void {
    const raw = c.ecalloc(1, @sizeOf(KeyboardGroup)) orelse return;
    const group = @as(*KeyboardGroup, @ptrCast(@alignCast(raw)));
    group.wlr_group = null;
    group.keyboard = keyboard;
    group.virtual_keyboard = null;
    c.wl_list_init(&group.link);
    standalone_keyboard_apply_config(group, rule);
    listen(&group.key, &keyboard.*.events.key, handle_keyboard_key);
    listen(&group.modifiers, &keyboard.*.events.modifiers, handle_keyboard_modifiers);
    listen(&group.destroy, &keyboard.*.base.events.destroy, handle_standalone_keyboard_destroy);
    group.key_repeat_source = wl_event_loop_add_timer(c.server.event_loop, keyboard_repeat, group);
    c.wl_list_insert(&c.server.standalone_keyboards, &group.link);
    input_dev.*.device_data = group;
}

fn invalidateSavedSeatKeyboard(keyboard: [*c]c.struct_wlr_keyboard) void {
    const vhead: [*c]c.struct_wl_list = @ptrCast(&c.server.virtual_keyboards);
    var pos = c.server.virtual_keyboards.next;
    while (pos != vhead) : (pos = pos.*.next) {
        const group = @as(*KeyboardGroup, @ptrFromInt(@intFromPtr(pos) - @offsetOf(KeyboardGroup, "link")));
        if (group.prev_seat_keyboard == keyboard)
            group.prev_seat_keyboard = null;
    }
    const shead: [*c]c.struct_wl_list = @ptrCast(&c.server.standalone_keyboards);
    pos = c.server.standalone_keyboards.next;
    while (pos != shead) : (pos = pos.*.next) {
        const group = @as(*KeyboardGroup, @ptrFromInt(@intFromPtr(pos) - @offsetOf(KeyboardGroup, "link")));
        if (group.prev_seat_keyboard == keyboard)
            group.prev_seat_keyboard = null;
    }
}

fn restoreSeatKeyboard(group: *KeyboardGroup) void {
    const active = wlr_seat_get_keyboard(c.server.seat);
    if (active != null and active != group.keyboard)
        return;
    var fallback = group.prev_seat_keyboard;
    if (fallback == null and c.server.keyboard_group != null)
        fallback = c.server.keyboard_group.*.keyboard;
    if (fallback != null)
        wlr_seat_set_keyboard(c.server.seat, fallback);
}

export fn keyboard_hard_modifiers() callconv(.c) u32 {
    var mods: u32 = 0;
    if (c.server.keyboard_group != null and c.server.keyboard_group.*.keyboard != null)
        mods |= wlr_keyboard_get_modifiers(c.server.keyboard_group.*.keyboard);
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.standalone_keyboards);
    var pos = c.server.standalone_keyboards.next;
    while (pos != head) : (pos = pos.*.next) {
        const group = @as(*KeyboardGroup, @ptrFromInt(@intFromPtr(pos) - @offsetOf(KeyboardGroup, "link")));
        if (group.keyboard != null)
            mods |= wlr_keyboard_get_modifiers(group.keyboard);
    }
    return mods;
}

export fn handle_standalone_keyboard_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const group = groupFromListener(listener, "destroy");
    if (group.keyboard == c.server.last_active_keyboard)
        c.server.last_active_keyboard = null;
    invalidateSavedSeatKeyboard(group.keyboard);
    restoreSeatKeyboard(group);
    c.wl_list_remove(&group.key.link);
    c.wl_list_remove(&group.modifiers.link);
    c.wl_list_remove(&group.destroy.link);
    if (group.key_repeat_source != null) {
        _ = wl_event_source_remove(group.key_repeat_source);
        group.key_repeat_source = null;
    }
    c.wl_list_remove(&group.link);
    c.free(group);
}

export fn keyboard_group_create() callconv(.c) [*c]KeyboardGroup {
    const raw = c.ecalloc(1, @sizeOf(KeyboardGroup)) orelse return null;
    const group = @as(*KeyboardGroup, @ptrCast(@alignCast(raw)));
    group.wlr_group = wlr_keyboard_group_create();
    group.wlr_group.*.data = group;
    group.keyboard = &group.wlr_group.*.keyboard;
    group.virtual_keyboard = null;
    c.wl_list_init(&group.link);

    const context = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS);
    if (context == null)
        c.die("failed to create xkb context");
    var keymap = c.xkb_keymap_new_from_names(context, &c.config.xkb_rules, c.XKB_KEYMAP_COMPILE_NO_FLAGS);
    if (keymap == null) {
        c.acwm_error_impl(false, c.WLR_ERROR, "src/input/keyboard.c", 432,
            "Failed to compile keymap (layout=\"%s\" variant=\"%s\" options=\"%s\"), falling back to the default layout",
            if (c.config.xkb_rules.layout != null) c.config.xkb_rules.layout else @as([*c]const u8, @constCast("")),
            if (c.config.xkb_rules.variant != null) c.config.xkb_rules.variant else @as([*c]const u8, @constCast("")),
            if (c.config.xkb_rules.options != null) c.config.xkb_rules.options else @as([*c]const u8, @constCast("")));
        keymap = c.xkb_keymap_new_from_names(context, &c.xkb_fallback_rules, c.XKB_KEYMAP_COMPILE_NO_FLAGS);
        if (keymap == null)
            c.die("failed to compile keymap");
    }

    _ = wlr_keyboard_set_keymap(group.keyboard, keymap);

    if (c.config.numlockon != 0) {
        const mod_index = c.xkb_keymap_mod_get_index(keymap, "Num Lock");
        if (mod_index != c.XKB_MOD_INVALID)
            c.server.locked_modifiers |= @as(u32, 1) << @intCast(mod_index);
    }
    if (c.config.capslock != 0) {
        const mod_index = c.xkb_keymap_mod_get_index(keymap, "Caps Lock");
        if (mod_index != c.XKB_MOD_INVALID)
            c.server.locked_modifiers |= @as(u32, 1) << @intCast(mod_index);
    }
    if (c.server.locked_modifiers != 0)
        wlr_keyboard_notify_modifiers(group.keyboard, 0, 0, c.server.locked_modifiers, 0);

    c.xkb_keymap_unref(keymap);
    c.xkb_context_unref(context);
    wlr_keyboard_set_repeat_info(group.keyboard, c.config.repeat_rate, c.config.repeat_delay);

    listen(&group.key, &group.keyboard.*.events.key, handle_keyboard_key);
    listen(&group.modifiers, &group.keyboard.*.events.modifiers, handle_keyboard_modifiers);
    group.key_repeat_source = wl_event_loop_add_timer(c.server.event_loop, keyboard_repeat, group);
    wlr_seat_set_keyboard(c.server.seat, group.keyboard);
    return group;
}

export fn keyboard_group_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const group = groupFromListener(listener, "destroy");
    if (group.keyboard == c.server.last_active_keyboard)
        c.server.last_active_keyboard = null;
    c.wl_list_remove(&group.link);
    invalidateSavedSeatKeyboard(group.keyboard);
    _ = wl_event_source_remove(group.key_repeat_source);
    c.wl_list_remove(&group.key.link);
    c.wl_list_remove(&group.modifiers.link);
    c.wl_list_remove(&group.destroy.link);
    wlr_keyboard_group_destroy(group.wlr_group);
    c.server.keyboard_group = null;
    c.free(group);
}

export fn keyboard_check_keybinding(state: u32, is_locked: bool, mods: u32, sym: c.xkb_keysym_t, keycode: u32) callconv(.c) i32 {
    var handled: i32 = 0;
    if (is_keyboard_shortcut_inhibitor(c.server.seat.*.keyboard_state.focused_surface))
        return 0;

    var ji: i32 = 0;
    while (ji < c.config.key_bindings_count) : (ji += 1) {
        const k = &c.config.key_bindings[@intCast(ji)];
        if (is_locked and !k.islockapply)
            continue;
        if (state == c.WL_KEYBOARD_KEY_STATE_RELEASED and !k.isreleaseapply)
            continue;
        if (state == c.WL_KEYBOARD_KEY_STATE_PRESSED and k.isreleaseapply)
            continue;
        if (state != c.WL_KEYBOARD_KEY_STATE_PRESSED and state != c.WL_KEYBOARD_KEY_STATE_RELEASED)
            continue;
        if (state == c.WL_KEYBOARD_KEY_STATE_RELEASED and keycode != c.server.last_hold_keycode)
            continue;

        const mode_matches = k.iscommonmode or
            (k.isdefaultmode and c.server.key_mode.isdefault) or
            c.strcmp(&c.server.key_mode.mode[0], &k.mode[0]) == 0;
        const key_matches = (k.keysymcode.type == c.KEY_TYPE_SYM and
            c.xkb_keysym_to_lower(sym) == c.xkb_keysym_to_lower(k.keysymcode.keysym)) or
            (k.keysymcode.type == c.KEY_TYPE_CODE and
                (keycode == k.keysymcode.keycode.keycode1 or
                    keycode == k.keysymcode.keycode.keycode2 or
                    keycode == k.keysymcode.keycode.keycode3));
        if (mode_matches and cleanMask(mods) == cleanMask(k.mod) and key_matches and k.func != null) {
            handled = if (!k.ispassapply) 1 else 0;
            if (k.func.?(&k.arg) != 0)
                break;
            if (!k.isallowconflict)
                break;
        }
    }
    return handled;
}

fn cleanMask(mask: u32) u32 {
    return mask & ~@as(u32, @intCast(c.WLR_MODIFIER_CAPS));
}

export fn keyboard_cancel_pending_release_bind() callconv(.c) void {
    c.server.last_hold_keycode = 0;
}

fn keyboardFindJumpClient(m: [*c]Monitor, keycode: u32) [*c]Client {
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    var pos = c.server.clients.next;
    while (pos != head) : (pos = pos.*.next) {
        const cl = @as([*c]Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Client, "link")));
        if (cl.*.mon != m)
            continue;
        if (keycode == cl.*.jump_keycodes.keycode1 or keycode == cl.*.jump_keycodes.keycode2 or
            keycode == cl.*.jump_keycodes.keycode3)
            return cl;
    }
    return null;
}

fn isModeKeycode(key: u32) bool {
    return key == 133 or key == 37 or key == 64 or key == 50 or
        key == 134 or key == 105 or key == 108 or key == 62;
}

export fn handle_keyboard_key(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    const group = groupFromListener(listener, "key");
    const event = @as(*c.struct_wlr_keyboard_key_event, @ptrCast(@alignCast(data.?)));

    if (session_lock_focus_missing())
        session_lock_focus_restore();

    const last_surface = c.server.seat.*.keyboard_state.focused_surface;
    const xdg_surface = if (last_surface != null) c.wlr_xdg_surface_try_from_wlr_surface(last_surface) else null;
    const xsurface = if (build_options.xwayland and last_surface != null)
        c.wlr_xwayland_surface_try_from_wlr_surface(last_surface)
    else
        null;
    var pass = false;
    var hit_global = false;

    if (group.keyboard.*.xkb_state == null)
        return;
    c.server.last_active_keyboard = group.keyboard;

    const keycode: u32 = event.*.keycode + 8;
    var syms: [*c]const c.xkb_keysym_t = null;
    var nsyms = c.xkb_state_key_get_syms(group.keyboard.*.xkb_state, keycode, &syms);
    if (nsyms > 8) nsyms = 8;
    if (nsyms > 0) {
        var i: usize = 0;
        while (i < @as(usize, @intCast(nsyms))) : (i += 1)
            group.keysyms[i] = syms[i];
    }
    const local_syms: [*c]c.xkb_keysym_t = &group.keysyms;

    var handled: i32 = 0;
    const mods = wlr_keyboard_get_modifiers(group.keyboard);
    acwm_notify_activity(c.server.seat);

    if (c.server.selected_monitor != null and c.server.selected_monitor.*.ov_tab_layout != 0 and
        c.server.selected_monitor.*.is_jump_mode == 0 and c.server.selected_monitor.*.isoverview != 0 and
        c.server.selected_monitor.*.sel != null and c.server.session_locked == 0 and group.virtual_keyboard == null and
        event.*.state == c.WL_KEYBOARD_KEY_STATE_RELEASED and isModeKeycode(keycode))
    {
        var arg = std.mem.zeroes(c.Arg);
        _ = toggle_overview(&arg);
    }

    if (switcher_is_active()) {
        if (c.server.session_locked != 0) {
            switcher_close();
        } else if (group.virtual_keyboard == null and event.*.state == c.WL_KEYBOARD_KEY_STATE_RELEASED and isModeKeycode(keycode)) {
            switcher_commit();
            group.nsyms = 0;
            _ = wl_event_source_timer_update(group.key_repeat_source, 0);
        }
    }

    if (c.config.cursor_hide_on_keypress != 0 and !c.server.cursor_hidden and event.*.state == c.WL_KEYBOARD_KEY_STATE_PRESSED)
        _ = pointer_hide_cursor(null);

    if (event.*.state == c.WL_KEYBOARD_KEY_STATE_RELEASED)
        c.server.tag_combo = false
    else
        c.server.last_hold_keycode = keycode;

    var i: i32 = 0;
    while (i < nsyms) : (i += 1) {
        const hit = keyboard_check_keybinding(event.*.state, c.server.session_locked != 0, mods, local_syms[@intCast(i)], keycode);
        handled = if (hit != 0 or handled != 0) 1 else 0;
    }

    if (handled != 0 and group.keyboard.*.repeat_info.delay > 0 and event.*.state == c.WL_KEYBOARD_KEY_STATE_PRESSED) {
        group.mods = mods;
        group.keycode = keycode;
        group.nsyms = nsyms;
        _ = wl_event_source_timer_update(group.key_repeat_source, group.keyboard.*.repeat_info.delay);
    } else {
        group.nsyms = 0;
        _ = wl_event_source_timer_update(group.key_repeat_source, 0);
    }

    if (handled != 0)
        return;

    if (c.server.selected_monitor != null and c.server.selected_monitor.*.is_jump_mode != 0 and
        event.*.state == c.WL_KEYBOARD_KEY_STATE_PRESSED)
    {
        const m = c.server.selected_monitor;
        var j: i32 = 0;
        while (j < nsyms) : (j += 1) {
            if (local_syms[@intCast(j)] == c.XKB_KEY_Escape) {
                var arg = std.mem.zeroes(c.Arg);
                _ = toggle_jump(&arg);
                return;
            }
        }
        const target = keyboardFindJumpClient(m, keycode);
        if (target != null) {
            client_focus(target, 1);
            var arg = std.mem.zeroes(c.Arg);
            arg.tc = target;
            _ = toggle_overview(&arg);
            return;
        }
    }

    pass = (xdg_surface != null and xdg_surface.*.role != c.WLR_XDG_SURFACE_ROLE_POPUP) or
        last_surface == null or (build_options.xwayland and xsurface != null);
    if (pass and nsyms > 0)
        hit_global = keyboard_process_global_keypress(last_surface, group.keyboard, event, mods, local_syms[0], keycode);

    if (hit_global)
        return;

    const kb_event: [*c]c.struct_wlr_keyboard_key_event = event;
    if (!acwm_im_keyboard_grab_forward_key(group, kb_event)) {
        const active = wlr_seat_get_keyboard(c.server.seat);
        if (active != group.keyboard)
            group.prev_seat_keyboard = active;
        wlr_seat_set_keyboard(c.server.seat, group.keyboard);
        wlr_seat_keyboard_notify_key(c.server.seat, event.*.time_msec, event.*.keycode, event.*.state);
    }
}

export fn handle_keyboard_modifiers(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const group = groupFromListener(listener, "modifiers");
    if (session_lock_focus_missing())
        session_lock_focus_restore();
    if (group.keyboard.*.xkb_state == null)
        return;

    if (!acwm_im_keyboard_grab_forward_modifiers(group)) {
        const active = wlr_seat_get_keyboard(c.server.seat);
        if (active != group.keyboard)
            group.prev_seat_keyboard = active;
        wlr_seat_set_keyboard(c.server.seat, group.keyboard);
        wlr_seat_keyboard_notify_modifiers(c.server.seat, &group.keyboard.*.modifiers);
    }

    const current = c.xkb_state_serialize_layout(group.keyboard.*.xkb_state, c.XKB_STATE_LAYOUT_EFFECTIVE);
    if (current != group.layout_index) {
        group.layout_index = current;
        printstatus(@intCast(c.IPC_WATCH_KB_LAYOUT));
    }
}

export fn reset_keyboard_layout() callconv(.c) void {
    if (c.server.keyboard_group == null or c.server.keyboard_group.*.wlr_group == null or c.server.seat == null) {
        c.acwm_error_impl(true, c.WLR_ERROR, "src/input/keyboard.c", 754, "Invalid keyboard group or seat");
        return;
    }
    const keyboard = c.server.keyboard_group.*.keyboard;
    if (keyboard == null or keyboard.*.keymap == null) {
        c.acwm_error_impl(true, c.WLR_ERROR, "src/input/keyboard.c", 760, "Invalid keyboard or keymap");
        return;
    }

    var current = c.xkb_state_serialize_layout(keyboard.*.xkb_state, c.XKB_STATE_LAYOUT_EFFECTIVE);
    const num_layouts = c.xkb_keymap_num_layouts(keyboard.*.keymap);
    if (num_layouts < 1) {
        c.acwm_error_impl(true, c.WLR_INFO, "src/input/keyboard.c", 766, "No layouts available");
        return;
    }

    const context = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS);
    if (context == null) {
        c.acwm_error_impl(true, c.WLR_ERROR, "src/input/keyboard.c", 772, "Failed to create XKB context");
        return;
    }

    const new_keymap = c.xkb_keymap_new_from_names(context, &c.config.xkb_rules, c.XKB_KEYMAP_COMPILE_NO_FLAGS);
    if (new_keymap == null) {
        c.acwm_error_impl(true, c.WLR_ERROR, "src/input/keyboard.c", 780,
            "Failed to compile keymap (invalid layout?), keeping the current keymap");
        c.xkb_context_unref(context);
        return;
    }

    const new_num_layouts = c.xkb_keymap_num_layouts(new_keymap);
    if (new_num_layouts < 1) {
        c.acwm_error_impl(true, c.WLR_ERROR, "src/input/keyboard.c", 788, "New keymap has no layouts");
        c.xkb_keymap_unref(new_keymap);
        c.xkb_context_unref(context);
        return;
    }
    if (current >= new_num_layouts) {
        c.acwm_error_impl(true, c.WLR_INFO, "src/input/keyboard.c", 795,
            "Current layout index %u out of range for new keymap, resetting to 0", current);
        current = 0;
    }

    const depressed = keyboard.*.modifiers.depressed;
    const latched = keyboard.*.modifiers.latched;
    const locked_mods = keyboard.*.modifiers.locked;
    _ = wlr_keyboard_set_keymap(keyboard, new_keymap);
    wlr_keyboard_notify_modifiers(keyboard, depressed, latched, locked_mods, 0);
    keyboard.*.modifiers.group = current;
    wlr_seat_set_keyboard(c.server.seat, keyboard);
    wlr_seat_keyboard_notify_modifiers(c.server.seat, &keyboard.*.modifiers);

    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.input_devices);
    var pos = c.server.input_devices.next;
    while (pos != head) : (pos = pos.*.next) {
        const id = @as(*InputDevice, @ptrFromInt(@intFromPtr(pos) - @offsetOf(InputDevice, "link")));
        if (id.wlr_device.*.type != c.WLR_INPUT_DEVICE_KEYBOARD or id.standalone)
            continue;
        const tkb = @as([*c]c.struct_wlr_keyboard, @ptrCast(@alignCast(id.device_data)));
        _ = wlr_keyboard_set_keymap(tkb, keyboard.*.keymap);
        wlr_keyboard_notify_modifiers(tkb, depressed, latched, locked_mods, 0);
        tkb.*.modifiers.group = 0;
        wlr_seat_set_keyboard(c.server.seat, tkb);
        wlr_seat_keyboard_notify_modifiers(c.server.seat, &tkb.*.modifiers);
    }

    c.xkb_keymap_unref(new_keymap);
    c.xkb_context_unref(context);
}

export fn handle_new_virtual_keyboard(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const kb = @as(*c.struct_wlr_virtual_keyboard_v1, @ptrCast(@alignCast(data.?)));
    seat_device_add(&kb.keyboard.base);
    const prev = wlr_seat_get_keyboard(c.server.seat);

    const raw = c.ecalloc(1, @sizeOf(KeyboardGroup)) orelse return;
    const group = @as(*KeyboardGroup, @ptrCast(@alignCast(raw)));
    group.wlr_group = null;
    group.keyboard = &kb.keyboard;
    group.virtual_keyboard = &kb.keyboard;
    group.prev_seat_keyboard = prev;
    c.wl_list_init(&group.link);
    c.wl_list_insert(&c.server.virtual_keyboards, &group.link);

    const rule = find_device_rule(&kb.keyboard.base);
    const context = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS);
    const keymap = if (rule != null and device_rule_has_keyboard_settings(rule))
        compile_rule_keymap(rule)
    else if (context != null)
        c.xkb_keymap_new_from_names(context, &c.config.xkb_rules, c.XKB_KEYMAP_COMPILE_NO_FLAGS)
    else
        null;
    if (keymap != null) {
        _ = wlr_keyboard_set_keymap(&kb.keyboard, keymap);
        c.xkb_keymap_unref(keymap);
    }
    if (context != null)
        c.xkb_context_unref(context);

    const rate = if (rule != null and rule.*.repeat_rate != -1) rule.*.repeat_rate else c.config.repeat_rate;
    const delay = if (rule != null and rule.*.repeat_delay != -1) rule.*.repeat_delay else c.config.repeat_delay;
    wlr_keyboard_set_repeat_info(&kb.keyboard, rate, delay);

    listen(&group.key, &kb.keyboard.events.key, handle_keyboard_key);
    listen(&group.modifiers, &kb.keyboard.events.modifiers, handle_keyboard_modifiers);
    listen(&group.destroy, &kb.keyboard.base.events.destroy, handle_standalone_keyboard_destroy);
    group.key_repeat_source = wl_event_loop_add_timer(c.server.event_loop, keyboard_repeat, group);
    wlr_seat_set_keyboard(c.server.seat, &kb.keyboard);
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/keyboard_stub.c, real xkbcommon)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_list_insert_calls: c_int;
extern var stub_list_remove_calls: c_int;
extern var stub_is_libinput: bool;
extern var stub_vendor: c_int;
extern var stub_product: c_int;
extern var stub_tap_fingers: c_int;
extern var stub_seat_device_add_calls: c_int;
extern var stub_input_destroy_calls: c_int;
extern var stub_set_keymap_calls: c_int;
extern var stub_set_keymap_arg: ?*c.struct_xkb_keymap;
extern var stub_notify_mods_calls: c_int;
extern var stub_notify_mods_locked: u32;
extern var stub_repeat_info_calls: c_int;
extern var stub_repeat_rate: c_int;
extern var stub_repeat_delay: c_int;
extern var stub_group_keyboard: [*c]c.struct_wlr_keyboard;
extern var stub_standalone_keyboard: [*c]c.struct_wlr_keyboard;
extern var stub_group_mods: u32;
extern var stub_standalone_mods: u32;
extern var stub_group_add_calls: c_int;
extern var stub_group_destroy_calls: c_int;
extern var stub_seat_keyboard: [*c]c.struct_wlr_keyboard;
extern var stub_set_seat_keyboard_calls: c_int;
extern var stub_set_seat_keyboard_arg: [*c]c.struct_wlr_keyboard;
extern var stub_keyboard_enter_calls: c_int;
extern var stub_keyboard_enter_surface: [*c]c.struct_wlr_surface;
extern var stub_send_key_calls: c_int;
extern var stub_notify_key_calls: c_int;
extern var stub_notify_key_code: u32;
extern var stub_notify_key_state: u32;
extern var stub_seat_notify_mods_calls: c_int;
extern var stub_xdg_surface: [*c]c.struct_wlr_xdg_surface;
extern var stub_xwayland_surface: [*c]c.struct_wlr_xwayland_surface;
extern var stub_inhibitor_activate_calls: c_int;
extern var stub_timer_update_calls: c_int;
extern var stub_timer_ms: i32;
extern var stub_timer_remove_calls: c_int;
extern var stub_focus_top_client: [*c]Client;
extern var stub_appid: [*c]const u8;
extern var stub_title: [*c]const u8;
extern var stub_client_surface: [*c]c.struct_wlr_surface;
extern var stub_focus_calls: c_int;
extern var stub_regex_match: bool;
extern var stub_toplevel_result: i32;
extern var stub_toplevel_client: [*c]Client;
extern var stub_activity_calls: c_int;
extern var stub_hide_cursor_calls: c_int;
extern var stub_session_missing: bool;
extern var stub_session_restore_calls: c_int;
extern var stub_switcher_active: bool;
extern var stub_switcher_close_calls: c_int;
extern var stub_switcher_commit_calls: c_int;
extern var stub_toggle_overview_calls: c_int;
extern var stub_toggle_jump_calls: c_int;
extern var stub_printstatus_calls: c_int;
extern var stub_forward_key: bool;
extern var stub_forward_mods: bool;
extern var stub_error_calls: c_int;
extern var stub_die_calls: c_int;
extern var stub_keybinding_calls: c_int;
extern var stub_keybinding_result: i32;
extern fn stub_keybinding_func(arg: [*c]const c.Arg) callconv(.c) i32;

fn listInit(head: *c.struct_wl_list) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

fn listCount(head: *c.struct_wl_list) usize {
    var n: usize = 0;
    var pos = head.next;
    while (pos != @as([*c]c.struct_wl_list, @ptrCast(head))) : (pos = pos.*.next)
        n += 1;
    return n;
}

var test_seat: c.struct_wlr_seat = undefined;

fn resetKeyboardWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    listInit(&c.server.clients);
    listInit(&c.server.input_devices);
    listInit(&c.server.standalone_keyboards);
    listInit(&c.server.virtual_keyboards);
    listInit(&c.server.keyboard_shortcut_inhibitors);
    test_seat = std.mem.zeroes(c.struct_wlr_seat);
    c.server.seat = &test_seat;
    stub_list_insert_calls = 0;
    stub_list_remove_calls = 0;
    stub_is_libinput = true;
    stub_tap_fingers = 0;
    stub_seat_device_add_calls = 0;
    stub_input_destroy_calls = 0;
    stub_set_keymap_calls = 0;
    stub_set_keymap_arg = null;
    stub_notify_mods_calls = 0;
    stub_notify_mods_locked = 0;
    stub_repeat_info_calls = 0;
    stub_repeat_rate = 0;
    stub_repeat_delay = 0;
    stub_group_keyboard = null;
    stub_standalone_keyboard = null;
    stub_group_mods = 0;
    stub_standalone_mods = 0;
    stub_group_add_calls = 0;
    stub_group_destroy_calls = 0;
    stub_seat_keyboard = null;
    stub_set_seat_keyboard_calls = 0;
    stub_set_seat_keyboard_arg = null;
    stub_keyboard_enter_calls = 0;
    stub_keyboard_enter_surface = null;
    stub_send_key_calls = 0;
    stub_notify_key_calls = 0;
    stub_notify_key_code = 0;
    stub_notify_key_state = 0;
    stub_seat_notify_mods_calls = 0;
    stub_xdg_surface = null;
    stub_xwayland_surface = null;
    stub_inhibitor_activate_calls = 0;
    stub_timer_update_calls = 0;
    stub_timer_ms = 0;
    stub_timer_remove_calls = 0;
    stub_focus_top_client = null;
    stub_regex_match = false;
    stub_toplevel_result = -1;
    stub_toplevel_client = null;
    stub_activity_calls = 0;
    stub_hide_cursor_calls = 0;
    stub_session_missing = false;
    stub_session_restore_calls = 0;
    stub_switcher_active = false;
    stub_switcher_close_calls = 0;
    stub_switcher_commit_calls = 0;
    stub_toggle_overview_calls = 0;
    stub_toggle_jump_calls = 0;
    stub_printstatus_calls = 0;
    stub_forward_key = false;
    stub_forward_mods = false;
    stub_error_calls = 0;
    stub_die_calls = 0;
    stub_keybinding_calls = 0;
    stub_keybinding_result = 0;
}

fn mkDevice(dev: *c.struct_wlr_input_device, t: c_uint, name: [*c]u8) void {
    dev.* = std.mem.zeroes(c.struct_wlr_input_device);
    dev.type = t;
    dev.name = name;
}

fn makeXkb(keymap: *?*c.struct_xkb_keymap, state: *?*c.struct_xkb_state) void {
    const context = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS);
    var names = std.mem.zeroes(c.struct_xkb_rule_names);
    names.layout = "us";
    keymap.* = c.xkb_keymap_new_from_names(context, &names, c.XKB_KEYMAP_COMPILE_NO_FLAGS);
    state.* = if (keymap.* != null) c.xkb_state_new(keymap.*) else null;
    c.xkb_context_unref(context);
}

var rules: [4]c.ConfigDeviceRule = undefined;
var bindings: [1]c.KeyBinding = undefined;

fn setBinding(sym: u32, func: ?*const fn ([*c]const c.Arg) callconv(.c) i32) void {
    bindings[0] = std.mem.zeroes(c.KeyBinding);
    bindings[0].iscommonmode = true;
    bindings[0].keysymcode.type = c.KEY_TYPE_SYM;
    bindings[0].keysymcode.keysym = sym;
    bindings[0].func = func;
    c.config.key_bindings = &bindings[0];
    c.config.key_bindings_count = 1;
}

test "device rules match names, identifiers and types" {
    resetKeyboardWorld();
    var dev: c.struct_wlr_input_device = undefined;
    mkDevice(&dev, c.WLR_INPUT_DEVICE_KEYBOARD, @constCast("kbd"));
    var rule0: c.ConfigDeviceRule = std.mem.zeroes(c.ConfigDeviceRule);
    rule0.name = @constCast("other");
    var rule1: c.ConfigDeviceRule = std.mem.zeroes(c.ConfigDeviceRule);
    rule1.name = @constCast("kbd");
    rules[0] = rule0;
    rules[1] = rule1;
    c.config.device_rules = &rules[0];
    c.config.device_rules_count = 2;
    try testing.expect(find_device_rule(&dev) == &rules[1]);

    rules[0].name = @constCast("4660:22136:kbd");
    try testing.expect(find_device_rule(&dev) == &rules[0]);

    resetKeyboardWorld();
    mkDevice(&dev, c.WLR_INPUT_DEVICE_KEYBOARD, @constCast("kbd"));
    rules[0] = std.mem.zeroes(c.ConfigDeviceRule);
    const kbd_type = "keyboard";
    for (kbd_type, 0..) |ch, i| rules[0].type[i] = ch;
    c.config.device_rules = &rules[0];
    c.config.device_rules_count = 1;
    try testing.expect(find_device_rule(&dev) == &rules[0]);
    try testing.expect(find_device_rule(null) == null);

    resetKeyboardWorld();
    mkDevice(&dev, c.WLR_INPUT_DEVICE_POINTER, @constCast("pad"));
    stub_tap_fingers = 2;
    rules[0] = std.mem.zeroes(c.ConfigDeviceRule);
    const t = "trackpad";
    for (t, 0..) |ch, i| rules[0].type[i] = ch;
    c.config.device_rules = &rules[0];
    c.config.device_rules_count = 1;
    try testing.expect(find_device_rule(&dev) == &rules[0]);
}

test "device rule keyboard settings detection" {
    resetKeyboardWorld();
    var rule: c.ConfigDeviceRule = std.mem.zeroes(c.ConfigDeviceRule);
    rule.repeat_rate = -1;
    rule.repeat_delay = -1;
    try testing.expect(!device_rule_has_keyboard_settings(&rule));
    try testing.expect(!device_rule_has_keyboard_settings(null));
    rule.repeat_rate = 25;
    try testing.expect(device_rule_has_keyboard_settings(&rule));
    rule.repeat_rate = -1;
    rule.kb_layout[0] = 'u';
    rule.kb_layout[1] = 's';
    try testing.expect(device_rule_has_keyboard_settings(&rule));
}

test "rule keymaps compile through xkbcommon" {
    resetKeyboardWorld();
    var rule: c.ConfigDeviceRule = std.mem.zeroes(c.ConfigDeviceRule);
    rule.kb_layout[0] = 'u';
    rule.kb_layout[1] = 's';
    const keymap = compile_rule_keymap(&rule);
    try testing.expect(keymap != null);
    c.xkb_keymap_unref(keymap);
    const fallback = compile_rule_keymap(null);
    try testing.expect(fallback != null);
    c.xkb_keymap_unref(fallback);
}

test "repeat resends bindings on the keyboard group" {
    resetKeyboardWorld();
    var kb: c.struct_wlr_keyboard = std.mem.zeroes(c.struct_wlr_keyboard);
    var group: KeyboardGroup = std.mem.zeroes(KeyboardGroup);
    group.keyboard = &kb;
    group.nsyms = 1;
    group.keysyms[0] = 0x61;
    group.keycode = 38;
    kb.repeat_info.rate = 25;
    setBinding(0x61, stub_keybinding_func);
    try testing.expectEqual(@as(i32, 0), keyboard_repeat(&group));
    try testing.expectEqual(@as(c_int, 1), stub_timer_update_calls);
    try testing.expectEqual(@as(i32, 40), stub_timer_ms);
    try testing.expectEqual(@as(c_int, 1), stub_keybinding_calls);

    kb.repeat_info.rate = 0;
    try testing.expectEqual(@as(i32, 0), keyboard_repeat(&group));
    try testing.expectEqual(@as(c_int, 1), stub_timer_update_calls);
}

test "keybinding matching honours modes, types and release state" {
    resetKeyboardWorld();
    test_seat.keyboard_state.focused_surface = null;
    setBinding(0x61, stub_keybinding_func);
    try testing.expectEqual(@as(i32, 1), keyboard_check_keybinding(c.WL_KEYBOARD_KEY_STATE_PRESSED, false, 0, 0x61, 38));
    try testing.expectEqual(@as(c_int, 1), stub_keybinding_calls);

    stub_keybinding_calls = 0;
    try testing.expectEqual(@as(i32, 1), keyboard_check_keybinding(c.WL_KEYBOARD_KEY_STATE_PRESSED, false, @intCast(c.WLR_MODIFIER_CAPS), 0x61, 38));
    try testing.expectEqual(@as(c_int, 1), stub_keybinding_calls);

    bindings[0].mod = @intCast(c.WLR_MODIFIER_SHIFT);
    stub_keybinding_calls = 0;
    try testing.expectEqual(@as(i32, 0), keyboard_check_keybinding(c.WL_KEYBOARD_KEY_STATE_PRESSED, false, 0, 0x61, 38));
    try testing.expectEqual(@as(c_int, 0), stub_keybinding_calls);

    bindings[0].mod = 0;
    bindings[0].keysymcode.type = c.KEY_TYPE_CODE;
    bindings[0].keysymcode.keycode.keycode2 = 38;
    try testing.expectEqual(@as(i32, 1), keyboard_check_keybinding(c.WL_KEYBOARD_KEY_STATE_PRESSED, false, 0, 0, 38));

    bindings[0].ispassapply = true;
    try testing.expectEqual(@as(i32, 0), keyboard_check_keybinding(c.WL_KEYBOARD_KEY_STATE_PRESSED, false, 0, 0, 38));

    bindings[0].ispassapply = false;
    bindings[0].isreleaseapply = true;
    c.server.last_hold_keycode = 0;
    try testing.expectEqual(@as(i32, 0), keyboard_check_keybinding(c.WL_KEYBOARD_KEY_STATE_RELEASED, false, 0, 0, 38));
    c.server.last_hold_keycode = 38;
    try testing.expectEqual(@as(i32, 1), keyboard_check_keybinding(c.WL_KEYBOARD_KEY_STATE_RELEASED, false, 0, 0, 38));

    bindings[0].isreleaseapply = false;
    stub_keybinding_result = 1;
    stub_keybinding_calls = 0;
    try testing.expectEqual(@as(i32, 1), keyboard_check_keybinding(c.WL_KEYBOARD_KEY_STATE_PRESSED, false, 0, 0, 38));
    try testing.expectEqual(@as(c_int, 1), stub_keybinding_calls);

    var inhibitor: KeyboardShortcutsInhibitor = std.mem.zeroes(KeyboardShortcutsInhibitor);
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    var inhib: c.struct_wlr_keyboard_shortcuts_inhibitor_v1 = std.mem.zeroes(c.struct_wlr_keyboard_shortcuts_inhibitor_v1);
    inhib.surface = &surface;
    inhibitor.inhibitor = &inhib;
    test_seat.keyboard_state.focused_surface = &surface;
    listInit(&inhibitor.link);
    listInsertList(&c.server.keyboard_shortcut_inhibitors, &inhibitor.link);
    stub_keybinding_calls = 0;
    try testing.expectEqual(@as(i32, 0), keyboard_check_keybinding(c.WL_KEYBOARD_KEY_STATE_PRESSED, false, 0, 0, 38));
    try testing.expectEqual(@as(c_int, 0), stub_keybinding_calls);
}

fn listInsertList(head: *c.struct_wl_list, link: *c.struct_wl_list) void {
    link.next = head.next;
    link.prev = @ptrCast(head);
    head.next.*.prev = @ptrCast(link);
    head.next = @ptrCast(link);
}

test "hard modifiers union physical keyboards and release cancel" {
    resetKeyboardWorld();
    var group_kb: c.struct_wlr_keyboard = std.mem.zeroes(c.struct_wlr_keyboard);
    var standalone_kb: c.struct_wlr_keyboard = std.mem.zeroes(c.struct_wlr_keyboard);
    var virtual_kb: c.struct_wlr_keyboard = std.mem.zeroes(c.struct_wlr_keyboard);
    stub_group_keyboard = &group_kb;
    stub_standalone_keyboard = &standalone_kb;
    stub_group_mods = 1;
    stub_standalone_mods = 2;
    var group: KeyboardGroup = std.mem.zeroes(KeyboardGroup);
    group.keyboard = &group_kb;
    c.server.keyboard_group = &group;
    var standalone: KeyboardGroup = std.mem.zeroes(KeyboardGroup);
    standalone.keyboard = &standalone_kb;
    var virtual: KeyboardGroup = std.mem.zeroes(KeyboardGroup);
    virtual.keyboard = &virtual_kb;
    listInit(&standalone.link);
    listInsertList(&c.server.standalone_keyboards, &standalone.link);
    listInit(&virtual.link);
    listInsertList(&c.server.virtual_keyboards, &virtual.link);

    try testing.expectEqual(@as(u32, 3), keyboard_hard_modifiers());
    c.server.last_hold_keycode = 99;
    keyboard_cancel_pending_release_bind();
    try testing.expectEqual(@as(u32, 0), c.server.last_hold_keycode);
}

test "shortcut inhibitors add and remove allowed surfaces" {
    resetKeyboardWorld();
    c.config.allow_shortcuts_inhibit = c.SHORTCUTS_INHIBIT_ENABLE;
    var inhibitor: c.struct_wlr_keyboard_shortcuts_inhibitor_v1 = std.mem.zeroes(c.struct_wlr_keyboard_shortcuts_inhibitor_v1);
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    inhibitor.surface = &surface;
    listInit(&inhibitor.events.destroy.listener_list);
    stub_toplevel_result = c.LayerShell;
    handle_keyboard_shortcuts_inhibit_new_inhibitor(null, &inhibitor);
    try testing.expectEqual(@as(usize, 1), listCount(&c.server.keyboard_shortcut_inhibitors));
    try testing.expectEqual(@as(c_int, 1), stub_inhibitor_activate_calls);

    const facade = @as(*KeyboardShortcutsInhibitor, @ptrFromInt(@intFromPtr(c.server.keyboard_shortcut_inhibitors.next) - @offsetOf(KeyboardShortcutsInhibitor, "link")));
    handle_keyboard_shortcuts_inhibitor_destroy(&facade.destroy, null);
    try testing.expectEqual(@as(usize, 0), listCount(&c.server.keyboard_shortcut_inhibitors));

    stub_toplevel_result = c.XDGShell;
    var cl: Client = std.mem.zeroes(Client);
    cl.allow_shortcuts_inhibit = 0;
    stub_toplevel_client = &cl;
    handle_keyboard_shortcuts_inhibit_new_inhibitor(null, &inhibitor);
    try testing.expectEqual(@as(usize, 0), listCount(&c.server.keyboard_shortcut_inhibitors));

    cl.allow_shortcuts_inhibit = 1;
    handle_keyboard_shortcuts_inhibit_new_inhibitor(null, &inhibitor);
    try testing.expectEqual(@as(usize, 1), listCount(&c.server.keyboard_shortcut_inhibitors));

    c.config.allow_shortcuts_inhibit = c.SHORTCUTS_INHIBIT_DISABLE;
    const before = listCount(&c.server.keyboard_shortcut_inhibitors);
    handle_keyboard_shortcuts_inhibit_new_inhibitor(null, &inhibitor);
    try testing.expectEqual(before, listCount(&c.server.keyboard_shortcut_inhibitors));
}

test "modifier handler notifies seat and reports layout changes" {
    resetKeyboardWorld();
    var kb: c.struct_wlr_keyboard = std.mem.zeroes(c.struct_wlr_keyboard);
    var keymap: ?*c.struct_xkb_keymap = null;
    var state: ?*c.struct_xkb_state = null;
    makeXkb(&keymap, &state);
    kb.xkb_state = state;
    kb.keymap = keymap;
    var group: KeyboardGroup = std.mem.zeroes(KeyboardGroup);
    group.keyboard = &kb;
    group.layout_index = 99;

    handle_keyboard_modifiers(&group.modifiers, null);
    try testing.expectEqual(@as(c_int, 1), stub_seat_notify_mods_calls);
    try testing.expectEqual(@as(c_int, 1), stub_printstatus_calls);
    try testing.expectEqual(@as(u32, 0), group.layout_index);

    handle_keyboard_modifiers(&group.modifiers, null);
    try testing.expectEqual(@as(c_int, 1), stub_printstatus_calls);

    stub_forward_mods = true;
    handle_keyboard_modifiers(&group.modifiers, null);
    try testing.expectEqual(@as(c_int, 2), stub_seat_notify_mods_calls);

    stub_session_missing = true;
    handle_keyboard_modifiers(&group.modifiers, null);
    try testing.expectEqual(@as(c_int, 1), stub_session_restore_calls);

    c.xkb_state_unref(state);
    c.xkb_keymap_unref(keymap);
}

test "key handler dispatches bindings and passes unhandled keys" {
    resetKeyboardWorld();
    var kb: c.struct_wlr_keyboard = std.mem.zeroes(c.struct_wlr_keyboard);
    var keymap: ?*c.struct_xkb_keymap = null;
    var state: ?*c.struct_xkb_state = null;
    makeXkb(&keymap, &state);
    kb.xkb_state = state;
    kb.keymap = keymap;
    kb.repeat_info.delay = 0;
    var group: KeyboardGroup = std.mem.zeroes(KeyboardGroup);
    group.keyboard = &kb;
    listInit(&kb.events.key.listener_list);
    listInit(&kb.events.modifiers.listener_list);
    listInit(&kb.base.events.destroy.listener_list);

    var event: c.struct_wlr_keyboard_key_event = std.mem.zeroes(c.struct_wlr_keyboard_key_event);
    event.keycode = 30;
    event.state = c.WL_KEYBOARD_KEY_STATE_PRESSED;
    event.time_msec = 5;
    handle_keyboard_key(&group.key, &event);
    try testing.expectEqual(@as(c_int, 1), stub_notify_key_calls);
    try testing.expectEqual(@as(u32, 30), stub_notify_key_code);
    try testing.expectEqual(@as(c_int, 1), stub_activity_calls);
    try testing.expectEqual(@as(u32, 38), c.server.last_hold_keycode);
    try testing.expect(c.server.last_active_keyboard == &kb);

    setBinding(0x61, stub_keybinding_func);
    stub_notify_key_calls = 0;
    stub_keybinding_calls = 0;
    handle_keyboard_key(&group.key, &event);
    try testing.expectEqual(@as(c_int, 0), stub_notify_key_calls);
    try testing.expectEqual(@as(c_int, 1), stub_keybinding_calls);

    event.state = c.WL_KEYBOARD_KEY_STATE_RELEASED;
    c.server.tag_combo = true;
    handle_keyboard_key(&group.key, &event);
    try testing.expect(!c.server.tag_combo);

    c.xkb_state_unref(state);
    c.xkb_keymap_unref(keymap);
}

test "keyboard create joins the group or creates a standalone device" {
    resetKeyboardWorld();
    var kb: c.struct_wlr_keyboard = std.mem.zeroes(c.struct_wlr_keyboard);
    var group_kb: c.struct_wlr_keyboard = std.mem.zeroes(c.struct_wlr_keyboard);
    var wlr_group: c.struct_wlr_keyboard_group = std.mem.zeroes(c.struct_wlr_keyboard_group);
    wlr_group.keyboard = group_kb;
    var group: KeyboardGroup = std.mem.zeroes(KeyboardGroup);
    group.keyboard = &group_kb;
    group.wlr_group = &wlr_group;
    c.server.keyboard_group = &group;
    var keymap: ?*c.struct_xkb_keymap = null;
    var state: ?*c.struct_xkb_state = null;
    makeXkb(&keymap, &state);
    group_kb.keymap = keymap;
    group_kb.xkb_state = state;
    listInit(&kb.events.key.listener_list);
    listInit(&kb.events.modifiers.listener_list);
    listInit(&kb.base.events.destroy.listener_list);

    keyboard_create(&kb);
    try testing.expectEqual(@as(usize, 1), listCount(&c.server.input_devices));
    try testing.expectEqual(@as(c_int, 1), stub_group_add_calls);
    try testing.expectEqual(@as(c_int, 1), stub_set_keymap_calls);

    resetKeyboardWorld();
    var kb2: c.struct_wlr_keyboard = std.mem.zeroes(c.struct_wlr_keyboard);
    var rule: c.ConfigDeviceRule = std.mem.zeroes(c.ConfigDeviceRule);
    rule.kb_layout[0] = 'u';
    rule.kb_layout[1] = 's';
    rule.repeat_rate = -1;
    rule.repeat_delay = -1;
    const kbd_type2 = "keyboard";
    for (kbd_type2, 0..) |ch, i| rule.type[i] = ch;
    rules[0] = rule;
    c.config.device_rules = &rules[0];
    c.config.device_rules_count = 1;
    listInit(&kb2.events.key.listener_list);
    listInit(&kb2.events.modifiers.listener_list);
    listInit(&kb2.base.events.destroy.listener_list);
    keyboard_create(&kb2);
    try testing.expectEqual(@as(usize, 1), listCount(&c.server.input_devices));
    try testing.expectEqual(@as(usize, 1), listCount(&c.server.standalone_keyboards));
    const dev = @as(*InputDevice, @ptrFromInt(@intFromPtr(c.server.input_devices.next) - @offsetOf(InputDevice, "link")));
    try testing.expect(dev.standalone);
    const standalone = @as(*KeyboardGroup, @ptrFromInt(@intFromPtr(c.server.standalone_keyboards.next) - @offsetOf(KeyboardGroup, "link")));
    try testing.expect(standalone.keyboard == &kb2);
    try testing.expect(dev.device_data == @as(?*anyopaque, @ptrCast(standalone)));
}
