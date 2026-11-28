//! Port of the remaining unguarded helpers in ipc/ipc.c
//! (Phase 5, IPC cleanup slice, slice 96).

const std = @import("std");
const c = @import("cc");

const Client = c.Client;
const Monitor = c.Monitor;

extern fn wlr_input_device_is_libinput(dev: [*c]c.struct_wlr_input_device) callconv(.c) bool;
extern fn wlr_libinput_get_device_handle(dev: [*c]c.struct_wlr_input_device) callconv(.c) ?*c.struct_libinput_device;
extern fn libinput_device_config_tap_get_finger_count(dev: ?*c.struct_libinput_device) callconv(.c) c_int;
extern fn xkb_state_serialize_layout(state: ?*c.struct_xkb_state, components: c.enum_xkb_state_component) callconv(.c) c.xkb_layout_index_t;
extern fn xkb_keymap_layout_get_name(keymap: ?*c.struct_xkb_keymap, idx: c.xkb_layout_index_t) callconv(.c) [*c]const u8;
extern fn build_client_json(cl: [*c]Client) callconv(.c) [*c]c.cJSON;
extern fn client_is_group_member(cl: [*c]const Client) callconv(.c) bool;
extern fn client_is_parked(cl: [*c]Client) callconv(.c) bool;
extern fn client_group_head(cl: [*c]Client) callconv(.c) [*c]Client;
extern fn send(fd: c_int, buf: ?*const anyopaque, len: usize, flags: c_int) callconv(.c) isize;
extern fn strlen(s: [*c]const u8) callconv(.c) usize;
extern fn snprintf(buf: [*c]u8, len: usize, fmt: [*c]const u8, ...) callconv(.c) c_int;

export var ipc_watch_clients: c.struct_wl_list = std.mem.zeroes(c.struct_wl_list);
export var ipc_device_watch_count: c_int = 0;

fn clientFromLink(link: [*c]c.struct_wl_list) *Client {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(Client, "link"));
}

export fn ipc_device_type_str(dev: [*c]c.struct_wlr_input_device) callconv(.c) [*c]const u8 {
    if (dev == null)
        return "unknown";

    var ld: ?*c.struct_libinput_device = null;
    if (wlr_input_device_is_libinput(dev))
        ld = wlr_libinput_get_device_handle(dev);

    return switch (dev.*.type) {
        c.WLR_INPUT_DEVICE_KEYBOARD => "keyboard",
        c.WLR_INPUT_DEVICE_POINTER => if (ld != null and
            libinput_device_config_tap_get_finger_count(ld) > 0)
            "trackpad"
        else
            "pointer",
        c.WLR_INPUT_DEVICE_TOUCH => "touch",
        c.WLR_INPUT_DEVICE_SWITCH => "switch",
        c.WLR_INPUT_DEVICE_TABLET => "tablet",
        c.WLR_INPUT_DEVICE_TABLET_PAD => "pad",
        else => "unknown",
    };
}

export fn monitor_by_name(name: [*c]const u8) callconv(.c) [*c]Monitor {
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.monitors);
    var pos = c.server.monitors.next;
    while (pos != head) : (pos = pos.*.next) {
        const m: *Monitor = @ptrFromInt(@intFromPtr(pos) - @offsetOf(Monitor, "link"));
        if (c.strcmp(m.wlr_output.*.name, name) == 0)
            return m;
    }
    return null;
}

export fn client_by_id(id: u32) callconv(.c) [*c]Client {
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    var pos = c.server.clients.next;
    while (pos != head) : (pos = pos.*.next) {
        const cl = clientFromLink(pos);
        if (cl.id == id)
            return cl;
    }
    return null;
}

export fn client_by_id_all(id: u32) callconv(.c) [*c]Client {
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    var pos = c.server.clients.next;
    while (pos != head) : (pos = pos.*.next) {
        const cl = clientFromLink(pos);
        if (cl.id == id)
            return cl;
        if (!client_is_group_member(cl))
            continue;
        var it = client_group_head(cl);
        while (it != null) : (it = it.*.group_next) {
            if (it.*.id == id)
                return it;
        }
    }
    return null;
}

var layout_buf: [64]u8 = std.mem.zeroes([64]u8);
var empty_buf: [1]u8 = .{0};

export fn ipc_get_layout_str() callconv(.c) [*c]const u8 {
    const keyboard: [*c]c.struct_wlr_keyboard = if (c.server.last_active_keyboard != null)
        c.server.last_active_keyboard
    else if (c.server.keyboard_group != null)
        c.server.keyboard_group.*.keyboard
    else
        null;
    if (keyboard == null or keyboard.*.keymap == null or keyboard.*.xkb_state == null)
        return @ptrCast(&empty_buf);

    const current = xkb_state_serialize_layout(keyboard.*.xkb_state, c.XKB_STATE_LAYOUT_EFFECTIVE);
    const name = xkb_keymap_layout_get_name(keyboard.*.keymap, current);
    const name_ptr: [*c]const u8 = if (name != null) name else @ptrCast(&empty_buf);
    _ = snprintf(&layout_buf, layout_buf.len, "%s", name_ptr);
    return &layout_buf;
}

export fn send_static_json(fd: c_int, json_str: [*c]const u8) callconv(.c) void {
    const len = strlen(json_str);
    _ = send(fd, json_str, len, 0);
}

export fn build_all_clients_array() callconv(.c) [*c]c.cJSON {
    const arr = c.cJSON_CreateArray();
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    var pos = c.server.clients.next;
    while (pos != head) : (pos = pos.*.next) {
        const cl = clientFromLink(pos);
        _ = c.cJSON_AddItemToArray(arr, build_client_json(cl));
        if (!client_is_group_member(cl))
            continue;
        var it = client_group_head(cl);
        while (it != null) : (it = it.*.group_next) {
            if (client_is_parked(it))
                _ = c.cJSON_AddItemToArray(arr, build_client_json(it));
        }
    }
    return arr;
}
