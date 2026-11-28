//! Port of ext-protocol/text-input.c (Phase 5, ext-protocol slice 4, slice 78).

const std = @import("std");
const c = @import("cc");

const Relay = c.struct_acwm_input_method_relay;
const TextInput = c.struct_text_input;
const Popup = c.struct_acwm_input_method_popup;
const KeyboardGroup = c.KeyboardGroup;
const Monitor = c.Monitor;
const Box = c.struct_wlr_box;

extern fn wlr_input_device_get_virtual_keyboard(device: [*c]c.struct_wlr_input_device) callconv(.c) [*c]c.struct_wlr_virtual_keyboard_v1;
extern fn wl_resource_get_client(resource: [*c]c.struct_wl_resource) callconv(.c) ?*c.struct_wl_client;
extern fn wlr_input_method_keyboard_grab_v2_set_keyboard(grab: [*c]c.struct_wlr_input_method_keyboard_grab_v2, keyboard: [*c]c.struct_wlr_keyboard) callconv(.c) void;
extern fn wlr_input_method_keyboard_grab_v2_send_modifiers(grab: [*c]c.struct_wlr_input_method_keyboard_grab_v2, modifiers: [*c]c.struct_wlr_keyboard_modifiers) callconv(.c) void;
extern fn wlr_input_method_keyboard_grab_v2_send_key(grab: [*c]c.struct_wlr_input_method_keyboard_grab_v2, time: u32, key: u32, state: u32) callconv(.c) void;
extern fn wlr_input_method_v2_send_activate(input_method: [*c]c.struct_wlr_input_method_v2) callconv(.c) void;
extern fn wlr_input_method_v2_send_deactivate(input_method: [*c]c.struct_wlr_input_method_v2) callconv(.c) void;
extern fn wlr_input_method_v2_send_done(input_method: [*c]c.struct_wlr_input_method_v2) callconv(.c) void;
extern fn wlr_input_method_v2_send_unavailable(input_method: [*c]c.struct_wlr_input_method_v2) callconv(.c) void;
extern fn wlr_input_method_v2_send_surrounding_text(input_method: [*c]c.struct_wlr_input_method_v2, text: [*c]const u8, cursor: u32, anchor: u32) callconv(.c) void;
extern fn wlr_input_method_v2_send_text_change_cause(input_method: [*c]c.struct_wlr_input_method_v2, cause: u32) callconv(.c) void;
extern fn wlr_input_method_v2_send_content_type(input_method: [*c]c.struct_wlr_input_method_v2, hint: u32, purpose: u32) callconv(.c) void;
extern fn wlr_text_input_v3_send_preedit_string(input: [*c]c.struct_wlr_text_input_v3, text: [*c]const u8, cursor_begin: u32, cursor_end: u32) callconv(.c) void;
extern fn wlr_text_input_v3_send_commit_string(input: [*c]c.struct_wlr_text_input_v3, text: [*c]const u8) callconv(.c) void;
extern fn wlr_text_input_v3_send_delete_surrounding_text(input: [*c]c.struct_wlr_text_input_v3, before: u32, after: u32) callconv(.c) void;
extern fn wlr_text_input_v3_send_done(input: [*c]c.struct_wlr_text_input_v3) callconv(.c) void;
extern fn wlr_text_input_v3_send_leave(input: [*c]c.struct_wlr_text_input_v3) callconv(.c) void;
extern fn wlr_text_input_v3_send_enter(input: [*c]c.struct_wlr_text_input_v3, surface: [*c]c.struct_wlr_surface) callconv(.c) void;
extern fn wlr_seat_keyboard_notify_modifiers(seat: [*c]c.struct_wlr_seat, modifiers: [*c]const c.struct_wlr_keyboard_modifiers) callconv(.c) void;
extern fn wlr_seat_get_keyboard(seat: [*c]c.struct_wlr_seat) callconv(.c) [*c]c.struct_wlr_keyboard;
extern fn wlr_xdg_surface_try_from_wlr_surface(s: [*c]c.struct_wlr_surface) callconv(.c) [*c]c.struct_wlr_xdg_surface;
extern fn wlr_layer_surface_v1_try_from_wlr_surface(s: [*c]c.struct_wlr_surface) callconv(.c) [*c]c.struct_wlr_layer_surface_v1;
extern fn wlr_scene_node_coords(node: [*c]c.struct_wlr_scene_node, lx: *i32, ly: *i32) callconv(.c) void;
extern fn wlr_scene_node_set_position(node: [*c]c.struct_wlr_scene_node, x: i32, y: i32) callconv(.c) void;
extern fn wlr_scene_node_raise_to_top(node: [*c]c.struct_wlr_scene_node) callconv(.c) void;
extern fn wlr_scene_node_destroy(node: [*c]c.struct_wlr_scene_node) callconv(.c) void;
extern fn wlr_scene_tree_create(parent: [*c]c.struct_wlr_scene_tree) callconv(.c) [*c]c.struct_wlr_scene_tree;
extern fn wlr_scene_subsurface_tree_create(parent: [*c]c.struct_wlr_scene_tree, surface: [*c]c.struct_wlr_surface) callconv(.c) [*c]c.struct_wlr_scene_tree;
extern fn wlr_output_layout_get_box(layout: [*c]c.struct_wlr_output_layout, output: [*c]c.struct_wlr_output, box: *Box) callconv(.c) void;
extern fn wlr_xdg_positioner_rules_get_geometry(rules: *const c.struct_wlr_xdg_positioner_rules, box: *Box) callconv(.c) void;
extern fn wlr_xdg_positioner_rules_unconstrain_box(rules: *const c.struct_wlr_xdg_positioner_rules, bounds: *const Box, box: *Box) callconv(.c) void;
extern fn wlr_input_popup_surface_v2_send_text_input_rectangle(popup: [*c]c.struct_wlr_input_popup_surface_v2, rect: *Box) callconv(.c) void;
extern fn get_monitor_nearest_to(lx: i32, ly: i32) callconv(.c) [*c]Monitor;
extern fn acwm_scene_node_set(node: [*c]c.struct_wlr_scene_node, type: u32, owner: ?*anyopaque) callconv(.c) bool;

fn relayFromListener(listener: [*c]c.struct_wl_listener, comptime field: []const u8) *Relay {
    return @ptrFromInt(@intFromPtr(listener) - @offsetOf(Relay, field));
}

fn textInputFromListener(listener: [*c]c.struct_wl_listener, comptime field: []const u8) *TextInput {
    return @ptrFromInt(@intFromPtr(listener) - @offsetOf(TextInput, field));
}

fn popupFromListener(listener: [*c]c.struct_wl_listener, comptime field: []const u8) *Popup {
    return @ptrFromInt(@intFromPtr(listener) - @offsetOf(Popup, field));
}

export fn output_from_wlr_output(wlr_output: [*c]c.struct_wlr_output) callconv(.c) [*c]Monitor {
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.monitors);
    var pos = c.server.monitors.next;
    while (pos != head) : (pos = pos.*.next) {
        const m = @as([*c]Monitor, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Monitor, "link")));
        if (m.*.wlr_output == wlr_output)
            return m;
    }
    return null;
}

export fn output_is_usable(m: [*c]Monitor) callconv(.c) bool {
    return m != null and m.*.wlr_output.*.enabled;
}

export fn is_keyboard_emulated_by_input_method(keyboard: [*c]c.struct_wlr_keyboard, input_method: [*c]c.struct_wlr_input_method_v2) callconv(.c) bool {
    if (keyboard == null or input_method == null)
        return false;
    const virtual_keyboard = c.wlr_input_device_get_virtual_keyboard(&keyboard.*.base);
    return virtual_keyboard != null and
        c.wl_resource_get_client(virtual_keyboard.*.resource) == c.wl_resource_get_client(input_method.*.resource);
}

export fn get_keyboard_grab(keyboard: [*c]KeyboardGroup) callconv(.c) [*c]c.struct_wlr_input_method_keyboard_grab_v2 {
    const input_method = c.server.input_method_relay.*.input_method;
    if (input_method == null or input_method.*.keyboard_grab == null)
        return null;
    if (is_keyboard_emulated_by_input_method(keyboard.*.virtual_keyboard, input_method))
        return null;
    return input_method.*.keyboard_grab;
}

export fn acwm_im_keyboard_grab_forward_modifiers(keyboard: [*c]KeyboardGroup) callconv(.c) bool {
    const grab = get_keyboard_grab(keyboard);
    const modifiers = &keyboard.*.keyboard.*.modifiers;
    if (grab != null) {
        c.wlr_input_method_keyboard_grab_v2_set_keyboard(grab, keyboard.*.keyboard);
        c.wlr_input_method_keyboard_grab_v2_send_modifiers(grab, modifiers);
        return true;
    }
    return false;
}

export fn acwm_im_keyboard_grab_forward_key(keyboard: [*c]KeyboardGroup, event: [*c]c.struct_wlr_keyboard_key_event) callconv(.c) bool {
    const grab = get_keyboard_grab(keyboard);
    if (grab != null) {
        c.wlr_input_method_keyboard_grab_v2_set_keyboard(grab, keyboard.*.keyboard);
        c.wlr_input_method_keyboard_grab_v2_send_key(grab, event.*.time_msec, event.*.keycode, event.*.state);
        return true;
    }
    return false;
}

export fn get_active_text_input(relay: [*c]Relay) callconv(.c) [*c]TextInput {
    if (relay.*.input_method == null)
        return null;
    const head: [*c]c.struct_wl_list = @ptrCast(&relay.*.text_inputs);
    var pos = relay.*.text_inputs.next;
    while (pos != head) : (pos = pos.*.next) {
        const ti = @as([*c]TextInput, @ptrFromInt(@intFromPtr(pos) - @offsetOf(TextInput, "link")));
        if (ti.*.input.*.focused_surface != null and ti.*.input.*.current_enabled)
            return ti;
    }
    return null;
}

export fn update_active_text_input(relay: [*c]Relay) callconv(.c) void {
    const active = get_active_text_input(relay);
    if (relay.*.input_method != null and relay.*.active_text_input != active) {
        if (active != null)
            c.wlr_input_method_v2_send_activate(relay.*.input_method)
        else
            c.wlr_input_method_v2_send_deactivate(relay.*.input_method);
        c.wlr_input_method_v2_send_done(relay.*.input_method);
    }
    relay.*.active_text_input = active;
}

export fn update_text_inputs_focused_surface(relay: [*c]Relay) callconv(.c) void {
    const head: [*c]c.struct_wl_list = @ptrCast(&relay.*.text_inputs);
    var pos = relay.*.text_inputs.next;
    while (pos != head) : (pos = pos.*.next) {
        const ti = @as([*c]TextInput, @ptrFromInt(@intFromPtr(pos) - @offsetOf(TextInput, "link")));
        const input = ti.*.input;
        var new_focused: [*c]c.struct_wlr_surface = null;
        if (relay.*.input_method != null and relay.*.focused_surface != null and
            c.wl_resource_get_client(input.*.resource) == c.wl_resource_get_client(relay.*.focused_surface.*.resource))
            new_focused = relay.*.focused_surface;
        if (input.*.focused_surface == new_focused)
            continue;
        if (input.*.focused_surface != null)
            c.wlr_text_input_v3_send_leave(input);
        if (new_focused != null)
            c.wlr_text_input_v3_send_enter(input, new_focused);
    }
}

export fn update_popup_position(popup: [*c]Popup) callconv(.c) void {
    const relay = popup.*.relay;
    const ti = relay.*.active_text_input;
    if (ti == null or relay.*.focused_surface == null or !popup.*.popup_surface.*.surface.*.mapped)
        return;
    var cursor_rect = std.mem.zeroes(Box);
    const xdg_surface = c.wlr_xdg_surface_try_from_wlr_surface(relay.*.focused_surface);
    const layer_surface = c.wlr_layer_surface_v1_try_from_wlr_surface(relay.*.focused_surface);
    if ((ti.*.input.*.current.features & c.WLR_TEXT_INPUT_V3_FEATURE_CURSOR_RECTANGLE) != 0 and
        (xdg_surface != null or layer_surface != null))
    {
        cursor_rect = ti.*.input.*.current.cursor_rectangle;
        const tree = @as([*c]c.struct_wlr_scene_tree, @ptrCast(@alignCast(relay.*.focused_surface.*.data)));
        var lx: i32 = 0;
        var ly: i32 = 0;
        _ = c.wlr_scene_node_coords(&tree.*.node, &lx, &ly);
        cursor_rect.x += lx;
        cursor_rect.y += ly;
        if (xdg_surface != null) {
            cursor_rect.x -= xdg_surface.*.geometry.x;
            cursor_rect.y -= xdg_surface.*.geometry.y;
        }
    }
    const output = get_monitor_nearest_to(cursor_rect.x, cursor_rect.y);
    if (!output_is_usable(output))
        return;
    var output_box = std.mem.zeroes(Box);
    c.wlr_output_layout_get_box(c.server.output_layout, output.*.wlr_output, &output_box);
    var rules = std.mem.zeroes(c.struct_wlr_xdg_positioner_rules);
    rules.anchor_rect = cursor_rect;
    rules.anchor = c.XDG_POSITIONER_ANCHOR_BOTTOM_LEFT;
    rules.gravity = c.XDG_POSITIONER_GRAVITY_BOTTOM_RIGHT;
    rules.size.width = popup.*.popup_surface.*.surface.*.current.width;
    rules.size.height = popup.*.popup_surface.*.surface.*.current.height;
    rules.constraint_adjustment = c.XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_FLIP_Y |
        c.XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_X;
    var popup_box = std.mem.zeroes(Box);
    c.wlr_xdg_positioner_rules_get_geometry(&rules, &popup_box);
    c.wlr_xdg_positioner_rules_unconstrain_box(&rules, &output_box, &popup_box);
    c.wlr_scene_node_set_position(&popup.*.tree.*.node, popup_box.x, popup_box.y);
    c.wlr_scene_node_raise_to_top(&relay.*.popup_tree.*.node);
    var rect = Box{
        .x = cursor_rect.x - popup_box.x,
        .y = cursor_rect.y - popup_box.y,
        .width = cursor_rect.width,
        .height = cursor_rect.height,
    };
    c.wlr_input_popup_surface_v2_send_text_input_rectangle(popup.*.popup_surface, &rect);
}

export fn update_popups_position(relay: [*c]Relay) callconv(.c) void {
    const head: [*c]c.struct_wl_list = @ptrCast(&relay.*.popups);
    var pos = relay.*.popups.next;
    while (pos != head) : (pos = pos.*.next)
        update_popup_position(@ptrFromInt(@intFromPtr(pos) - @offsetOf(Popup, "link")));
}

export fn handle_input_method_commit(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const relay = relayFromListener(listener, "input_method_commit");
    const ti = relay.*.active_text_input;
    if (ti == null)
        return;
    const input_method = relay.*.input_method;
    if (input_method.*.current.preedit.text != null)
        c.wlr_text_input_v3_send_preedit_string(ti.*.input, input_method.*.current.preedit.text, input_method.*.current.preedit.cursor_begin, input_method.*.current.preedit.cursor_end);
    if (input_method.*.current.commit_text != null)
        c.wlr_text_input_v3_send_commit_string(ti.*.input, input_method.*.current.commit_text);
    if (input_method.*.current.delete.before_length != 0 or input_method.*.current.delete.after_length != 0)
        c.wlr_text_input_v3_send_delete_surrounding_text(ti.*.input, input_method.*.current.delete.before_length, input_method.*.current.delete.after_length);
    c.wlr_text_input_v3_send_done(ti.*.input);
}

export fn handle_keyboard_grab_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const relay = relayFromListener(listener, "keyboard_grab_destroy");
    const grab = relay.*.input_method.*.keyboard_grab;
    c.wl_list_remove(&relay.*.keyboard_grab_destroy.link);
    if (grab.*.keyboard != null)
        c.wlr_seat_keyboard_notify_modifiers(grab.*.input_method.*.seat, &grab.*.keyboard.*.modifiers);
}

export fn handle_input_method_grab_keyboard(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    const relay = relayFromListener(listener, "input_method_grab_keyboard");
    const grab = @as([*c]c.struct_wlr_input_method_keyboard_grab_v2, @ptrCast(@alignCast(data.?)));
    const active_keyboard = c.wlr_seat_get_keyboard(c.server.seat);
    if (!is_keyboard_emulated_by_input_method(active_keyboard, relay.*.input_method))
        c.wlr_input_method_keyboard_grab_v2_set_keyboard(grab, active_keyboard);
    relay.*.keyboard_grab_destroy.notify = handle_keyboard_grab_destroy;
    c.wl_signal_add(&grab.*.events.destroy, &relay.*.keyboard_grab_destroy);
}

export fn handle_input_method_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const relay = relayFromListener(listener, "input_method_destroy");
    c.wl_list_remove(&relay.*.input_method_commit.link);
    c.wl_list_remove(&relay.*.input_method_grab_keyboard.link);
    c.wl_list_remove(&relay.*.input_method_new_popup_surface.link);
    c.wl_list_remove(&relay.*.input_method_destroy.link);
    relay.*.input_method = null;
    update_text_inputs_focused_surface(relay);
    update_active_text_input(relay);
}

export fn handle_popup_surface_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const popup = popupFromListener(listener, "destroy");
    c.wlr_scene_node_destroy(&popup.*.tree.*.node);
    c.wl_list_remove(&popup.*.destroy.link);
    c.wl_list_remove(&popup.*.commit.link);
    c.wl_list_remove(&popup.*.link);
    c.free(popup);
}

export fn handle_popup_surface_commit(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    update_popup_position(popupFromListener(listener, "commit"));
}

export fn handle_input_method_new_popup_surface(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    const relay = relayFromListener(listener, "input_method_new_popup_surface");
    const raw = c.ecalloc(1, @sizeOf(Popup)) orelse return;
    const popup = @as(*Popup, @ptrCast(@alignCast(raw)));
    popup.popup_surface = @as([*c]c.struct_wlr_input_popup_surface_v2, @ptrCast(@alignCast(data.?)));
    popup.relay = relay;
    popup.destroy.notify = handle_popup_surface_destroy;
    c.wl_signal_add(&popup.popup_surface.*.events.destroy, &popup.destroy);
    popup.commit.notify = handle_popup_surface_commit;
    c.wl_signal_add(&popup.popup_surface.*.surface.*.events.commit, &popup.commit);
    popup.tree = c.wlr_scene_tree_create(c.server.layers[c.LyrIMPopup]);
    popup.scene_surface = c.wlr_scene_subsurface_tree_create(popup.tree, popup.popup_surface.*.surface);
    popup.type = c.XdgImPopup;
    _ = c.acwm_scene_node_set(&popup.scene_surface.*.node, c.XdgImPopup, popup);
    c.wl_list_insert(&relay.*.popups, &popup.link);
    update_popup_position(popup);
}

export fn handle_new_input_method(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    const relay = relayFromListener(listener, "new_input_method");
    const input_method = @as([*c]c.struct_wlr_input_method_v2, @ptrCast(@alignCast(data.?)));
    if (c.server.seat != input_method.*.seat)
        return;
    if (relay.*.input_method != null) {
        c.wlr_input_method_v2_send_unavailable(input_method);
        return;
    }
    relay.*.input_method = input_method;
    relay.*.input_method_commit.notify = handle_input_method_commit;
    c.wl_signal_add(&input_method.*.events.commit, &relay.*.input_method_commit);
    relay.*.input_method_grab_keyboard.notify = handle_input_method_grab_keyboard;
    c.wl_signal_add(&input_method.*.events.grab_keyboard, &relay.*.input_method_grab_keyboard);
    relay.*.input_method_destroy.notify = handle_input_method_destroy;
    c.wl_signal_add(&input_method.*.events.destroy, &relay.*.input_method_destroy);
    relay.*.input_method_new_popup_surface.notify = handle_input_method_new_popup_surface;
    c.wl_signal_add(&input_method.*.events.new_popup_surface, &relay.*.input_method_new_popup_surface);
    update_text_inputs_focused_surface(relay);
    update_active_text_input(relay);
}

export fn send_state_to_input_method(relay: [*c]Relay) callconv(.c) void {
    const input_method = relay.*.input_method;
    std.debug.assert(relay.*.active_text_input != null and input_method != null);
    const input = relay.*.active_text_input.*.input;
    if ((input.*.active_features & c.WLR_TEXT_INPUT_V3_FEATURE_SURROUNDING_TEXT) != 0)
        c.wlr_input_method_v2_send_surrounding_text(input_method, input.*.current.surrounding.text, input.*.current.surrounding.cursor, input.*.current.surrounding.anchor);
    c.wlr_input_method_v2_send_text_change_cause(input_method, input.*.current.text_change_cause);
    if ((input.*.active_features & c.WLR_TEXT_INPUT_V3_FEATURE_CONTENT_TYPE) != 0)
        c.wlr_input_method_v2_send_content_type(input_method, input.*.current.content_type.hint, input.*.current.content_type.purpose);
    c.wlr_input_method_v2_send_done(input_method);
}

export fn handle_text_input_enable(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const ti = textInputFromListener(listener, "enable");
    const relay = ti.*.relay;
    update_active_text_input(relay);
    if (relay.*.active_text_input == ti) {
        update_popups_position(relay);
        send_state_to_input_method(relay);
    }
    c.wlr_text_input_v3_send_done(ti.*.input);
}

export fn handle_text_input_disable(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const ti = textInputFromListener(listener, "disable");
    update_active_text_input(ti.*.relay);
}

export fn handle_text_input_commit(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const ti = textInputFromListener(listener, "commit");
    if (ti.*.relay.*.active_text_input == ti) {
        update_popups_position(ti.*.relay);
        send_state_to_input_method(ti.*.relay);
    }
}

export fn handle_text_input_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const ti = textInputFromListener(listener, "destroy");
    c.wl_list_remove(&ti.*.enable.link);
    c.wl_list_remove(&ti.*.disable.link);
    c.wl_list_remove(&ti.*.commit.link);
    c.wl_list_remove(&ti.*.destroy.link);
    c.wl_list_remove(&ti.*.link);
    update_active_text_input(ti.*.relay);
    c.free(ti);
}

export fn handle_new_text_input(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    const relay = relayFromListener(listener, "new_text_input");
    const wlr_text_input = @as([*c]c.struct_wlr_text_input_v3, @ptrCast(@alignCast(data.?)));
    const raw = c.ecalloc(1, @sizeOf(TextInput)) orelse return;
    const ti = @as(*TextInput, @ptrCast(@alignCast(raw)));
    if (c.server.seat != wlr_text_input.*.seat)
        return;
    ti.input = wlr_text_input;
    ti.relay = relay;
    c.wl_list_insert(&relay.*.text_inputs, &ti.link);
    ti.enable.notify = handle_text_input_enable;
    c.wl_signal_add(&wlr_text_input.*.events.enable, &ti.enable);
    ti.disable.notify = handle_text_input_disable;
    c.wl_signal_add(&wlr_text_input.*.events.disable, &ti.disable);
    ti.commit.notify = handle_text_input_commit;
    c.wl_signal_add(&wlr_text_input.*.events.commit, &ti.commit);
    ti.destroy.notify = handle_text_input_destroy;
    c.wl_signal_add(&wlr_text_input.*.events.destroy, &ti.destroy);
    update_text_inputs_focused_surface(relay);
}

export fn handle_focused_surface_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    const relay = relayFromListener(listener, "focused_surface_destroy");
    std.debug.assert(@intFromPtr(relay.*.focused_surface) == @intFromPtr(data.?));
    acwm_im_relay_set_focus(relay, null);
}

export fn acwm_im_relay_create() callconv(.c) [*c]Relay {
    const raw = c.ecalloc(1, @sizeOf(Relay)) orelse return null;
    const relay = @as(*Relay, @ptrCast(@alignCast(raw)));
    c.wl_list_init(&relay.text_inputs);
    c.wl_list_init(&relay.popups);
    relay.popup_tree = c.wlr_scene_tree_create(&c.server.scene.*.tree);
    relay.new_text_input.notify = handle_new_text_input;
    c.wl_signal_add(&c.server.text_input_manager.*.events.new_text_input, &relay.new_text_input);
    relay.new_input_method.notify = handle_new_input_method;
    c.wl_signal_add(&c.server.input_method_manager.*.events.new_input_method, &relay.new_input_method);
    relay.focused_surface_destroy.notify = handle_focused_surface_destroy;
    return relay;
}

export fn acwm_im_relay_finish(relay: [*c]Relay) callconv(.c) void {
    c.wl_list_remove(&relay.*.new_text_input.link);
    c.wl_list_remove(&relay.*.new_input_method.link);
    c.free(relay);
}

export fn acwm_im_relay_set_focus(relay: [*c]Relay, surface: [*c]c.struct_wlr_surface) callconv(.c) void {
    if (relay.*.focused_surface == surface)
        return;
    if (relay.*.focused_surface != null)
        c.wl_list_remove(&relay.*.focused_surface_destroy.link);
    relay.*.focused_surface = surface;
    if (surface != null)
        c.wl_signal_add(&surface.*.events.destroy, &relay.*.focused_surface_destroy);
    update_text_inputs_focused_surface(relay);
    update_active_text_input(relay);
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/text_input_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_client: ?*c.struct_wl_client;
extern var stub_vk: c.struct_wlr_virtual_keyboard_v1;
extern var stub_virtual_keyboard: [*c]c.struct_wlr_virtual_keyboard_v1;
extern var stub_set_kb_calls: c_int;
extern var stub_send_mods_calls: c_int;
extern var stub_send_key_calls: c_int;
extern var stub_activate_calls: c_int;
extern var stub_deactivate_calls: c_int;
extern var stub_im_done_calls: c_int;
extern var stub_unavailable_calls: c_int;
extern var stub_surrounding_calls: c_int;
extern var stub_cause_calls: c_int;
extern var stub_content_calls: c_int;
extern var stub_preedit_calls: c_int;
extern var stub_commit_calls: c_int;
extern var stub_delete_calls: c_int;
extern var stub_ti_done_calls: c_int;
extern var stub_leave_calls: c_int;
extern var stub_enter_calls: c_int;
extern var stub_seat_mods_calls: c_int;
extern var stub_seat_kb: [*c]c.struct_wlr_keyboard;
extern var stub_xdg: [*c]c.struct_wlr_xdg_surface;
extern var stub_layer: [*c]c.struct_wlr_layer_surface_v1;
extern var stub_coords_calls: c_int;
extern var stub_coord_x: i32;
extern var stub_coord_y: i32;
extern var stub_pos_calls: c_int;
extern var stub_pos_x: i32;
extern var stub_pos_y: i32;
extern var stub_raise_calls: c_int;
extern var stub_destroy_node_calls: c_int;
extern var stub_tree: c.struct_wlr_scene_tree;
extern var stub_subtree: c.struct_wlr_scene_tree;
extern var stub_rect_calls: c_int;
extern var stub_rect: Box;
extern var stub_nearest: [*c]Monitor;
extern var stub_scene_set_calls: c_int;

var test_seat: c.struct_wlr_seat = undefined;

fn listInitL(head: *c.struct_wl_list) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

fn listCountL(head: *c.struct_wl_list) usize {
    var n: usize = 0;
    var pos = head.next;
    while (pos != @as([*c]c.struct_wl_list, @ptrCast(head))) : (pos = pos.*.next) n += 1;
    return n;
}

fn resetTiWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    listInitL(&c.server.monitors);
    test_seat = std.mem.zeroes(c.struct_wlr_seat);
    c.server.seat = &test_seat;
    stub_virtual_keyboard = null;
    stub_set_kb_calls = 0;
    stub_send_mods_calls = 0;
    stub_send_key_calls = 0;
    stub_activate_calls = 0;
    stub_deactivate_calls = 0;
    stub_im_done_calls = 0;
    stub_unavailable_calls = 0;
    stub_surrounding_calls = 0;
    stub_cause_calls = 0;
    stub_content_calls = 0;
    stub_preedit_calls = 0;
    stub_commit_calls = 0;
    stub_delete_calls = 0;
    stub_ti_done_calls = 0;
    stub_leave_calls = 0;
    stub_enter_calls = 0;
    stub_seat_mods_calls = 0;
    stub_seat_kb = null;
    stub_xdg = null;
    stub_layer = null;
    stub_coords_calls = 0;
    stub_coord_x = 0;
    stub_coord_y = 0;
    stub_pos_calls = 0;
    stub_pos_x = 0;
    stub_pos_y = 0;
    stub_raise_calls = 0;
    stub_destroy_node_calls = 0;
    stub_rect_calls = 0;
    stub_rect = std.mem.zeroes(Box);
    stub_nearest = null;
    stub_scene_set_calls = 0;
}

fn mkRelay(relay: *Relay) void {
    relay.* = std.mem.zeroes(Relay);
    listInitL(&relay.text_inputs);
    listInitL(&relay.popups);
    relay.popup_tree = &stub_tree;
}

fn mkTi(ti: *TextInput, relay: *Relay, input: *c.struct_wlr_text_input_v3) void {
    ti.* = std.mem.zeroes(TextInput);
    ti.relay = relay;
    ti.input = input;
    listInitL(&ti.link);
    c.wl_list_insert(&relay.text_inputs, &ti.link);
}

test "output lookup and usability" {
    resetTiWorld();
    var m1: Monitor = std.mem.zeroes(Monitor);
    var m2: Monitor = std.mem.zeroes(Monitor);
    var o1: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    var o2: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    o2.enabled = true;
    m1.wlr_output = &o1;
    m2.wlr_output = &o2;
    listInsertL(&c.server.monitors, &m1.link);
    listInsertL(&c.server.monitors, &m2.link);
    try testing.expect(output_from_wlr_output(&o2) == &m2);
    try testing.expect(output_from_wlr_output(null) == null);
    try testing.expect(!output_is_usable(&m1));
    try testing.expect(output_is_usable(&m2));
}

fn listInsertL(head: *c.struct_wl_list, link: *c.struct_wl_list) void {
    link.next = head.next;
    link.prev = @ptrCast(head);
    head.next.*.prev = @ptrCast(link);
    head.next = @ptrCast(link);
}

test "keyboard grabs forward unless emulated by the input method" {
    resetTiWorld();
    var relay: Relay = std.mem.zeroes(Relay);
    var im: c.struct_wlr_input_method_v2 = std.mem.zeroes(c.struct_wlr_input_method_v2);
    c.server.input_method_relay = &relay;
    relay.input_method = &im;
    var grab: c.struct_wlr_input_method_keyboard_grab_v2 = std.mem.zeroes(c.struct_wlr_input_method_keyboard_grab_v2);
    im.keyboard_grab = &grab;
    var kb: c.struct_wlr_keyboard = std.mem.zeroes(c.struct_wlr_keyboard);
    var group: KeyboardGroup = std.mem.zeroes(KeyboardGroup);
    group.keyboard = &kb;
    var virtual_keyboard: c.struct_wlr_virtual_keyboard_v1 = std.mem.zeroes(c.struct_wlr_virtual_keyboard_v1);
    group.virtual_keyboard = &kb;
    virtual_keyboard.resource = @ptrFromInt(0x1000);
    im.resource = @ptrFromInt(0x1000);
    group.virtual_keyboard = &kb;
    kb.base.type = c.WLR_INPUT_DEVICE_KEYBOARD;
    stub_virtual_keyboard = &virtual_keyboard;

    try testing.expect(get_keyboard_grab(&group) == null);
    stub_virtual_keyboard = null;
    var event: c.struct_wlr_keyboard_key_event = std.mem.zeroes(c.struct_wlr_keyboard_key_event);
    event.time_msec = 5;
    event.keycode = 30;
    event.state = c.WL_KEYBOARD_KEY_STATE_PRESSED;
    try testing.expect(acwm_im_keyboard_grab_forward_key(&group, &event));
    try testing.expectEqual(@as(c_int, 1), stub_send_key_calls);
    try testing.expect(acwm_im_keyboard_grab_forward_modifiers(&group));
    try testing.expectEqual(@as(c_int, 1), stub_send_mods_calls);

    stub_virtual_keyboard = null;
    try testing.expect(!is_keyboard_emulated_by_input_method(&kb, &im));
    try testing.expect(get_keyboard_grab(&group) == &grab);
}

test "active text input activates and deactivates the input method" {
    resetTiWorld();
    var relay: Relay = std.mem.zeroes(Relay);
    mkRelay(&relay);
    var im: c.struct_wlr_input_method_v2 = std.mem.zeroes(c.struct_wlr_input_method_v2);
    relay.input_method = &im;
    var input: c.struct_wlr_text_input_v3 = std.mem.zeroes(c.struct_wlr_text_input_v3);
    input.focused_surface = &stub_surface;
    input.current_enabled = true;
    var ti: TextInput = std.mem.zeroes(TextInput);
    mkTi(&ti, &relay, &input);
    try testing.expect(get_active_text_input(&relay) == &ti);
    update_active_text_input(&relay);
    try testing.expectEqual(@as(c_int, 1), stub_activate_calls);
    try testing.expect(relay.active_text_input == &ti);

    input.current_enabled = false;
    update_active_text_input(&relay);
    try testing.expectEqual(@as(c_int, 1), stub_deactivate_calls);
}

test "focus updates enter and leave text inputs" {
    resetTiWorld();
    var relay: Relay = std.mem.zeroes(Relay);
    mkRelay(&relay);
    var im: c.struct_wlr_input_method_v2 = std.mem.zeroes(c.struct_wlr_input_method_v2);
    relay.input_method = &im;
    var input: c.struct_wlr_text_input_v3 = std.mem.zeroes(c.struct_wlr_text_input_v3);
    input.resource = @ptrFromInt(0x1000);
    var ti: TextInput = std.mem.zeroes(TextInput);
    mkTi(&ti, &relay, &input);
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    surface.resource = @ptrFromInt(0x1000);
    relay.focused_surface = &surface;
    update_text_inputs_focused_surface(&relay);
    try testing.expectEqual(@as(c_int, 1), stub_enter_calls);
    relay.focused_surface = null;
    update_text_inputs_focused_surface(&relay);
    try testing.expectEqual(@as(c_int, 1), stub_leave_calls);
}

test "input method commit forwards preedit, text and delete" {
    resetTiWorld();
    var relay: Relay = std.mem.zeroes(Relay);
    mkRelay(&relay);
    var im: c.struct_wlr_input_method_v2 = std.mem.zeroes(c.struct_wlr_input_method_v2);
    relay.input_method = &im;
    var input: c.struct_wlr_text_input_v3 = std.mem.zeroes(c.struct_wlr_text_input_v3);
    var ti: TextInput = std.mem.zeroes(TextInput);
    mkTi(&ti, &relay, &input);
    relay.active_text_input = &ti;
    im.current.preedit.text = @constCast("pre");
    im.current.preedit.cursor_begin = 1;
    im.current.preedit.cursor_end = 3;
    im.current.commit_text = @constCast("commit");
    im.current.delete.before_length = 2;
    im.current.delete.after_length = 4;
    handle_input_method_commit(&relay.input_method_commit, null);
    try testing.expectEqual(@as(c_int, 1), stub_preedit_calls);
    try testing.expectEqual(@as(c_int, 1), stub_commit_calls);
    try testing.expectEqual(@as(c_int, 1), stub_delete_calls);
    try testing.expectEqual(@as(c_int, 1), stub_ti_done_calls);
}

test "state sends surrounding text and content type" {
    resetTiWorld();
    var relay: Relay = std.mem.zeroes(Relay);
    mkRelay(&relay);
    var im: c.struct_wlr_input_method_v2 = std.mem.zeroes(c.struct_wlr_input_method_v2);
    relay.input_method = &im;
    var input: c.struct_wlr_text_input_v3 = std.mem.zeroes(c.struct_wlr_text_input_v3);
    input.active_features = c.WLR_TEXT_INPUT_V3_FEATURE_SURROUNDING_TEXT | c.WLR_TEXT_INPUT_V3_FEATURE_CONTENT_TYPE;
    input.current.surrounding.text = @constCast("around");
    input.current.text_change_cause = 7;
    input.current.content_type.hint = 3;
    input.current.content_type.purpose = 4;
    var ti: TextInput = std.mem.zeroes(TextInput);
    mkTi(&ti, &relay, &input);
    relay.active_text_input = &ti;
    send_state_to_input_method(&relay);
    try testing.expectEqual(@as(c_int, 1), stub_surrounding_calls);
    try testing.expectEqual(@as(c_int, 1), stub_cause_calls);
    try testing.expectEqual(@as(c_int, 1), stub_content_calls);
    try testing.expectEqual(@as(c_int, 1), stub_im_done_calls);

    input.active_features = 0;
    send_state_to_input_method(&relay);
    try testing.expectEqual(@as(c_int, 1), stub_surrounding_calls);
    try testing.expectEqual(@as(c_int, 2), stub_im_done_calls);
}

test "text input enable, commit, disable and destroy" {
    resetTiWorld();
    var relay: Relay = std.mem.zeroes(Relay);
    mkRelay(&relay);
    var im: c.struct_wlr_input_method_v2 = std.mem.zeroes(c.struct_wlr_input_method_v2);
    relay.input_method = &im;
    var input: c.struct_wlr_text_input_v3 = std.mem.zeroes(c.struct_wlr_text_input_v3);
    input.focused_surface = &stub_surface;
    input.current_enabled = true;
    const ti = @as(*TextInput, @ptrCast(@alignCast(c.calloc(1, @sizeOf(TextInput)) orelse unreachable)));
    mkTi(ti, &relay, &input);
    listInitL(&ti.enable.link);
    listInitL(&ti.disable.link);
    listInitL(&ti.commit.link);
    listInitL(&ti.destroy.link);
    handle_text_input_enable(&ti.enable, null);
    try testing.expectEqual(@as(c_int, 1), stub_activate_calls);
    try testing.expectEqual(@as(c_int, 1), stub_ti_done_calls);
    handle_text_input_commit(&ti.commit, null);
    try testing.expectEqual(@as(c_int, 3), stub_im_done_calls);
    input.current_enabled = false;
    handle_text_input_disable(&ti.disable, null);
    try testing.expectEqual(@as(c_int, 1), stub_deactivate_calls);
    handle_text_input_destroy(&ti.destroy, null);
    try testing.expectEqual(@as(usize, 0), listCountL(&relay.text_inputs));
}

test "popup position uses cursor rect and constrains to the monitor" {
    resetTiWorld();
    var relay: Relay = std.mem.zeroes(Relay);
    mkRelay(&relay);
    var input: c.struct_wlr_text_input_v3 = std.mem.zeroes(c.struct_wlr_text_input_v3);
    input.current.features = c.WLR_TEXT_INPUT_V3_FEATURE_CURSOR_RECTANGLE;
    input.current.cursor_rectangle = .{ .x = 10, .y = 20, .width = 5, .height = 6 };
    var ti: TextInput = std.mem.zeroes(TextInput);
    mkTi(&ti, &relay, &input);
    relay.active_text_input = &ti;
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    surface.mapped = true;
    surface.data = &stub_tree;
    relay.focused_surface = &surface;
    var xdg: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    xdg.geometry = .{ .x = 1, .y = 2, .width = 0, .height = 0 };
    stub_xdg = &xdg;
    stub_coord_x = 100;
    stub_coord_y = 200;
    var popup_surface: c.struct_wlr_input_popup_surface_v2 = std.mem.zeroes(c.struct_wlr_input_popup_surface_v2);
    popup_surface.surface = &surface;
    surface.current.width = 200;
    surface.current.height = 100;
    var popup: Popup = std.mem.zeroes(Popup);
    popup.popup_surface = &popup_surface;
    popup.relay = &relay;
    popup.tree = &stub_tree;
    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    out.enabled = true;
    var m: Monitor = std.mem.zeroes(Monitor);
    m.wlr_output = &out;
    stub_nearest = &m;
    update_popup_position(&popup);
    try testing.expectEqual(@as(c_int, 1), stub_coords_calls);
    try testing.expectEqual(@as(c_int, 1), stub_pos_calls);
    try testing.expectEqual(@as(c_int, 1), stub_raise_calls);
    try testing.expectEqual(@as(c_int, 1), stub_rect_calls);
    try testing.expectEqual(@as(i32, 0), stub_rect.x);
    try testing.expectEqual(@as(i32, -6), stub_rect.y);
}

test "relay create, focus and finish wire managers" {
    resetTiWorld();
    var tim: c.struct_wlr_text_input_manager_v3 = std.mem.zeroes(c.struct_wlr_text_input_manager_v3);
    var imm: c.struct_wlr_input_method_manager_v2 = std.mem.zeroes(c.struct_wlr_input_method_manager_v2);
    var scene: c.struct_wlr_scene = std.mem.zeroes(c.struct_wlr_scene);
    c.server.text_input_manager = &tim;
    c.server.input_method_manager = &imm;
    c.server.scene = &scene;
    listInitL(&tim.events.new_text_input.listener_list);
    listInitL(&imm.events.new_input_method.listener_list);
    const relay = acwm_im_relay_create();
    try testing.expect(relay != null);
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    listInitL(&surface.events.destroy.listener_list);
    acwm_im_relay_set_focus(relay, &surface);
    try testing.expect(relay.*.focused_surface == &surface);
    try testing.expect(!listIsEmptyL(&surface.events.destroy.listener_list));
    acwm_im_relay_set_focus(relay, null);
    try testing.expect(relay.*.focused_surface == null);
    acwm_im_relay_finish(relay);
}

fn listIsEmptyL(head: *c.struct_wl_list) bool {
    return head.next == @as([*c]c.struct_wl_list, @ptrCast(head));
}

extern var stub_surface: c.struct_wlr_surface;
