//! Port of input/touch.c (Phase 5, input slice 2, slice 69).

const std = @import("std");
const c = @import("cc");
const build_options = @import("build_options");

const Client = c.Client;
const Monitor = c.Monitor;

const TouchPoint = extern struct {
    touch_id: i32 = 0,
    x_offset: f64 = 0,
    y_offset: f64 = 0,
    surface: [*c]c.struct_wlr_surface = null,
    surface_destroy: c.struct_wl_listener = std.mem.zeroes(c.struct_wl_listener),
    touch_protocol: bool = false,
    link: c.struct_wl_list = std.mem.zeroes(c.struct_wl_list),
};

extern fn device_target_monitor(device: [*c]c.struct_wlr_input_device) callconv(.c) [*c]Monitor;
extern fn wlr_cursor_map_input_to_output(cursor: [*c]c.struct_wlr_cursor, device: [*c]c.struct_wlr_input_device, output: [*c]c.struct_wlr_output) callconv(.c) void;
extern fn wlr_cursor_attach_input_device(cursor: [*c]c.struct_wlr_cursor, device: [*c]c.struct_wlr_input_device) callconv(.c) void;
extern fn wlr_cursor_absolute_to_layout_coords(cursor: [*c]c.struct_wlr_cursor, device: [*c]c.struct_wlr_input_device, x: f64, y: f64, lx: *f64, ly: *f64) callconv(.c) void;
extern fn wlr_cursor_warp_absolute(cursor: [*c]c.struct_wlr_cursor, device: [*c]c.struct_wlr_input_device, x: f64, y: f64) callconv(.c) void;
extern fn node_at_point(x: f64, y: f64, psurface: [*c][*c]c.struct_wlr_surface, pc: [*c][*c]Client, pl: [*c]?*anyopaque, bar: [*c]?*anyopaque, nx: *f64, ny: *f64) callconv(.c) void;
extern fn pointer_process_motion(time: u32, device: [*c]c.struct_wlr_input_device, dx: f64, dy: f64, dx_unaccel: f64, dy_unaccel: f64) callconv(.c) void;
extern fn pointer_process_button_press(event: *c.struct_wlr_pointer_button_event) callconv(.c) bool;
extern fn pointer_hide_cursor(data: ?*anyopaque) callconv(.c) i32;
extern fn acwm_notify_activity(seat: [*c]c.struct_wlr_seat) callconv(.c) void;
extern fn ipc_notify_device_event(dev: [*c]c.struct_wlr_input_device) callconv(.c) void;
extern fn toplevel_from_wlr_surface(s: [*c]c.struct_wlr_surface, pc: [*c][*c]Client, pl: [*c]?*anyopaque) callconv(.c) i32;
extern fn client_is_x11(cl: [*c]Client) callconv(.c) i32;
extern fn libinput_device_config_send_events_get_modes(device: [*c]c.struct_libinput_device) callconv(.c) u32;
extern fn libinput_device_config_send_events_set_mode(device: [*c]c.struct_libinput_device, mode: u32) callconv(.c) c_int;
extern fn wlr_input_device_is_libinput(device: [*c]c.struct_wlr_input_device) callconv(.c) bool;
extern fn wlr_libinput_get_device_handle(device: [*c]c.struct_wlr_input_device) callconv(.c) ?*c.struct_libinput_device;

var simulating_pointer_from_touch: bool = false;
var pointer_touch_id: i32 = -1;

fn pointFromLink(link: [*c]c.struct_wl_list) *TouchPoint {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(TouchPoint, "link"));
}

fn pointFromListener(listener: [*c]c.struct_wl_listener) *TouchPoint {
    return @ptrFromInt(@intFromPtr(listener) - @offsetOf(TouchPoint, "surface_destroy"));
}

export fn touch_apply_monitor_mapping(touch: [*c]c.struct_wlr_touch) callconv(.c) void {
    if (touch == null)
        return;
    const target = device_target_monitor(&touch.*.base);
    if (target == null)
        return;
    c.wlr_cursor_map_input_to_output(c.server.cursor, &touch.*.base, target.*.wlr_output);
    c.acwm_error_impl(true, c.WLR_DEBUG, "src/input/touch.c", 56, "Mapping touch %s to output %s", touch.*.base.name, target.*.wlr_output.*.name);
}

export fn touch_create(touch: [*c]c.struct_wlr_touch) callconv(.c) void {
    if (c.wlr_input_device_is_libinput(&touch.*.base)) {
        const device = c.wlr_libinput_get_device_handle(&touch.*.base);
        if (device != null and c.libinput_device_config_send_events_get_modes(device) != 0) {
            _ = c.libinput_device_config_send_events_set_mode(device, c.config.send_events_mode);
        }
    }
    c.wlr_cursor_attach_input_device(c.server.cursor, &touch.*.base);
    touch_apply_monitor_mapping(touch);
}

export fn handle_touch_point_surface_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const point = pointFromListener(listener);
    point.surface = null;
    c.wl_list_remove(&listener.*.link);
    c.wl_list_init(&listener.*.link);
}

export fn touch_get_coords(touch: [*c]c.struct_wlr_touch, x: f64, y: f64, x_offset: *f64, y_offset: *f64, pc: [*c][*c]Client) callconv(.c) [*c]c.struct_wlr_surface {
    var lx: f64 = 0;
    var ly: f64 = 0;
    var sx: f64 = 0;
    var sy: f64 = 0;
    var surface: [*c]c.struct_wlr_surface = null;
    var cl: [*c]Client = null;

    c.wlr_cursor_absolute_to_layout_coords(c.server.cursor, &touch.*.base, x, y, &lx, &ly);
    c.node_at_point(lx, ly, &surface, &cl, null, null, &sx, &sy);

    x_offset.* = lx - sx;
    y_offset.* = ly - sy;
    if (pc != null)
        pc.* = cl;
    return surface;
}

export fn touch_emulate_move_absolute(touch: [*c]c.struct_wlr_touch, x: f64, y: f64, time: u32) callconv(.c) void {
    var lx: f64 = 0;
    var ly: f64 = 0;
    c.wlr_cursor_absolute_to_layout_coords(c.server.cursor, &touch.*.base, x, y, &lx, &ly);
    const dx = lx - c.server.cursor.*.x;
    const dy = ly - c.server.cursor.*.y;
    pointer_process_motion(time, &touch.*.base, dx, dy, dx, dy);
    c.wlr_seat_pointer_notify_frame(c.server.seat);
}

export fn touch_emulate_button(button: u32, state: u32, time: u32) callconv(.c) void {
    var ev = std.mem.zeroes(c.struct_wlr_pointer_button_event);
    ev.button = button;
    ev.state = @intCast(state);
    ev.time_msec = time;
    if (!pointer_process_button_press(&ev))
        _ = c.wlr_seat_pointer_notify_button(c.server.seat, ev.time_msec, ev.button, ev.state);
    c.wlr_seat_pointer_notify_frame(c.server.seat);
}

export fn touch_apply_xwayland_scale(surface: [*c]c.struct_wlr_surface, sx: *f64, sy: *f64) callconv(.c) void {
    if (!build_options.xwayland)
        return;
    var cl: [*c]Client = null;
    _ = toplevel_from_wlr_surface(surface, &cl, null);
    if (cl != null and client_is_x11(cl) != 0 and c.config.xwayland_ignore_scale != 0 and
        cl.*.xwayland_scale > 0)
    {
        sx.* *= cl.*.xwayland_scale;
        sy.* *= cl.*.xwayland_scale;
    }
}

export fn handle_cursor_touch_down(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as(*c.struct_wlr_touch_down_event, @ptrCast(@alignCast(data.?)));
    const raw = c.ecalloc(1, @sizeOf(TouchPoint)) orelse return;
    const point = @as(*TouchPoint, @ptrCast(@alignCast(raw)));
    var x_offset: f64 = 0;
    var y_offset: f64 = 0;
    var cl: [*c]Client = null;

    ipc_notify_device_event(&event.*.touch.*.base);

    if (c.config.touch_enable == 0) {
        touch_finish_all();
        return;
    }

    touch_apply_monitor_mapping(event.*.touch);
    acwm_notify_activity(c.server.seat);

    point.surface = touch_get_coords(event.*.touch, event.*.x, event.*.y, &x_offset, &y_offset, &cl);
    point.touch_id = event.*.touch_id;
    point.x_offset = x_offset;
    point.y_offset = y_offset;
    point.touch_protocol = point.surface != null and c.wlr_surface_accepts_touch(point.surface, c.server.seat);

    c.wl_list_insert(&c.server.touch_points, &point.link);
    const touch_point_count = c.wl_list_length(&c.server.touch_points);

    _ = pointer_hide_cursor(null);

    if (point.touch_protocol) {
        simulating_pointer_from_touch = false;
        c.wlr_seat_pointer_notify_clear_focus(c.server.seat);

        var lx: f64 = 0;
        var ly: f64 = 0;
        c.wlr_cursor_absolute_to_layout_coords(c.server.cursor, &event.*.touch.*.base, event.*.x, event.*.y, &lx, &ly);
        var sx = lx - x_offset;
        var sy = ly - y_offset;

        touch_apply_xwayland_scale(point.surface, &sx, &sy);

        if (touch_point_count == 1)
            c.wlr_cursor_warp_absolute(c.server.cursor, &event.*.touch.*.base, event.*.x, event.*.y);

        c.wl_signal_add(&point.surface.*.events.destroy, &point.surface_destroy);
        point.surface_destroy.notify = handle_touch_point_surface_destroy;

        _ = c.wlr_seat_touch_notify_down(c.server.seat, point.surface, event.*.time_msec, event.*.touch_id, sx, sy);
    } else if (c.config.touch_enable_mouse_emulation != 0 and !simulating_pointer_from_touch) {
        simulating_pointer_from_touch = true;
        pointer_touch_id = event.*.touch_id;
        touch_emulate_move_absolute(event.*.touch, event.*.x, event.*.y, event.*.time_msec);
        touch_emulate_button(c.BTN_LEFT, c.WL_POINTER_BUTTON_STATE_PRESSED, event.*.time_msec);
    }
}

export fn handle_cursor_touch_motion(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as(*c.struct_wlr_touch_motion_event, @ptrCast(@alignCast(data.?)));
    ipc_notify_device_event(&event.*.touch.*.base);

    if (c.config.touch_enable == 0) {
        touch_finish_all();
        return;
    }

    acwm_notify_activity(c.server.seat);

    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.touch_points);
    var pos = c.server.touch_points.next;
    while (pos != head) : (pos = pos.*.next) {
        const point = pointFromLink(pos);
        if (point.touch_id != event.*.touch_id)
            continue;

        if (point.touch_protocol and point.surface != null) {
            var lx: f64 = 0;
            var ly: f64 = 0;
            c.wlr_cursor_absolute_to_layout_coords(c.server.cursor, &event.*.touch.*.base, event.*.x, event.*.y, &lx, &ly);
            var sx = lx - point.x_offset;
            var sy = ly - point.y_offset;
            touch_apply_xwayland_scale(point.surface, &sx, &sy);
            c.wlr_seat_touch_notify_motion(c.server.seat, event.*.time_msec, event.*.touch_id, sx, sy);
        } else if (c.config.touch_enable_mouse_emulation != 0 and
            simulating_pointer_from_touch and point.touch_id == pointer_touch_id)
        {
            touch_emulate_move_absolute(event.*.touch, event.*.x, event.*.y, event.*.time_msec);
        }
        return;
    }
}

export fn handle_cursor_touch_up(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as(*c.struct_wlr_touch_up_event, @ptrCast(@alignCast(data.?)));
    ipc_notify_device_event(&event.*.touch.*.base);

    if (c.config.touch_enable == 0) {
        touch_finish_all();
        return;
    }

    acwm_notify_activity(c.server.seat);

    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.touch_points);
    var pos = c.server.touch_points.next;
    while (pos != head) {
        const next = pos.*.next;
        const point = pointFromLink(pos);
        if (point.touch_id != event.*.touch_id) {
            pos = next;
            continue;
        }

        if (point.touch_protocol and point.surface != null) {
            _ = c.wlr_seat_touch_notify_up(c.server.seat, event.*.time_msec, event.*.touch_id);
            c.wl_list_remove(&point.surface_destroy.link);
        } else if (c.config.touch_enable_mouse_emulation != 0 and
            simulating_pointer_from_touch and point.touch_id == pointer_touch_id)
        {
            touch_emulate_button(c.BTN_LEFT, c.WL_POINTER_BUTTON_STATE_RELEASED, event.*.time_msec);
            simulating_pointer_from_touch = false;
            pointer_touch_id = -1;
        }

        c.wl_list_remove(&point.link);
        c.free(point);
        break;
    }
}

export fn handle_cursor_touch_cancel(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as(*c.struct_wlr_touch_cancel_event, @ptrCast(@alignCast(data.?)));
    ipc_notify_device_event(&event.*.touch.*.base);

    if (c.config.touch_enable == 0) {
        touch_finish_all();
        return;
    }

    acwm_notify_activity(c.server.seat);

    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.touch_points);
    var pos = c.server.touch_points.next;
    while (pos != head) {
        const next = pos.*.next;
        const point = pointFromLink(pos);
        if (point.touch_id != event.*.touch_id) {
            pos = next;
            continue;
        }

        if (point.touch_protocol and point.surface != null) {
            c.wlr_seat_touch_notify_cancel(c.server.seat, null);
            c.wl_list_remove(&point.surface_destroy.link);
        } else if (c.config.touch_enable_mouse_emulation != 0 and
            simulating_pointer_from_touch and point.touch_id == pointer_touch_id)
        {
            touch_emulate_button(c.BTN_LEFT, c.WL_POINTER_BUTTON_STATE_RELEASED, event.*.time_msec);
            simulating_pointer_from_touch = false;
            pointer_touch_id = -1;
        }

        c.wl_list_remove(&point.link);
        c.free(point);
        break;
    }
}

export fn handle_cursor_touch_frame(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    _ = data;
    if (simulating_pointer_from_touch)
        c.wlr_seat_pointer_notify_frame(c.server.seat)
    else
        c.wlr_seat_touch_notify_frame(c.server.seat);
}

export fn touch_finish_all() callconv(.c) void {
    if (simulating_pointer_from_touch and c.config.touch_enable_mouse_emulation != 0)
        touch_emulate_button(c.BTN_LEFT, c.WL_POINTER_BUTTON_STATE_RELEASED, 0);
    simulating_pointer_from_touch = false;
    pointer_touch_id = -1;

    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.touch_points);
    var pos = c.server.touch_points.next;
    while (pos != head) {
        const next = pos.*.next;
        const point = pointFromLink(pos);
        if (point.touch_protocol and point.surface != null)
            c.wl_list_remove(&point.surface_destroy.link);
        c.wl_list_remove(&point.link);
        c.free(point);
        pos = next;
    }
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/touch_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_list_insert_calls: c_int;
extern var stub_list_remove_calls: c_int;
extern var stub_map_output_calls: c_int;
extern var stub_mapped_output: [*c]c.struct_wlr_output;
extern var stub_error_calls: c_int;
extern var stub_target_monitor: [*c]Monitor;
extern var stub_is_libinput: bool;
extern var stub_libinput_device: ?*c.struct_libinput_device;
extern var stub_send_modes: u32;
extern var stub_set_mode_calls: c_int;
extern var stub_set_mode_value: u32;
extern var stub_attach_calls: c_int;
extern var stub_lx: f64;
extern var stub_ly: f64;
extern var stub_warp_calls: c_int;
extern var stub_warp_x: f64;
extern var stub_warp_y: f64;
extern var stub_node_surface: [*c]c.struct_wlr_surface;
extern var stub_node_client: [*c]Client;
extern var stub_node_x: f64;
extern var stub_node_y: f64;
extern var stub_motion_calls: c_int;
extern var stub_motion_dx: f64;
extern var stub_motion_dy: f64;
extern var stub_motion_time: u32;
extern var stub_press_calls: c_int;
extern var stub_press_handled: bool;
extern var stub_press_event: c.struct_wlr_pointer_button_event;
extern var stub_button_calls: c_int;
extern var stub_button: u32;
extern var stub_button_state: c_uint;
extern var stub_button_time: u32;
extern var stub_pointer_frame_calls: c_int;
extern var stub_clear_focus_calls: c_int;
extern var stub_hide_cursor_calls: c_int;
extern var stub_activity_calls: c_int;
extern var stub_ipc_device_calls: c_int;
extern var stub_accepts_touch: bool;
extern var stub_toplevel_result: i32;
extern var stub_toplevel_client: [*c]Client;
extern var stub_is_x11: c_int;
extern var stub_touch_down_calls: c_int;
extern var stub_down_id: i32;
extern var stub_down_sx: f64;
extern var stub_down_sy: f64;
extern var stub_down_time: u32;
extern var stub_touch_motion_calls: c_int;
extern var stub_touch_motion_id: i32;
extern var stub_touch_motion_sx: f64;
extern var stub_touch_motion_sy: f64;
extern var stub_touch_up_calls: c_int;
extern var stub_touch_up_id: i32;
extern var stub_touch_cancel_calls: c_int;
extern var stub_touch_frame_calls: c_int;

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

var test_cursor: c.struct_wlr_cursor = undefined;

fn resetTouchWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    listInit(&c.server.touch_points);
    c.server.seat = @ptrFromInt(0x1000);
    test_cursor = std.mem.zeroes(c.struct_wlr_cursor);
    c.server.cursor = &test_cursor;
    simulating_pointer_from_touch = false;
    pointer_touch_id = -1;
    stub_list_insert_calls = 0;
    stub_list_remove_calls = 0;
    stub_map_output_calls = 0;
    stub_error_calls = 0;
    stub_target_monitor = null;
    stub_is_libinput = false;
    stub_send_modes = 0;
    stub_set_mode_calls = 0;
    stub_set_mode_value = 0;
    stub_attach_calls = 0;
    stub_lx = 0;
    stub_ly = 0;
    stub_warp_calls = 0;
    stub_node_surface = null;
    stub_node_client = null;
    stub_node_x = 0;
    stub_node_y = 0;
    stub_motion_calls = 0;
    stub_motion_dx = 0;
    stub_motion_dy = 0;
    stub_motion_time = 0;
    stub_press_calls = 0;
    stub_press_handled = false;
    stub_button_calls = 0;
    stub_button = 0;
    stub_button_state = 0;
    stub_button_time = 0;
    stub_pointer_frame_calls = 0;
    stub_clear_focus_calls = 0;
    stub_hide_cursor_calls = 0;
    stub_activity_calls = 0;
    stub_ipc_device_calls = 0;
    stub_accepts_touch = false;
    stub_toplevel_result = 0;
    stub_toplevel_client = null;
    stub_is_x11 = 0;
    stub_touch_down_calls = 0;
    stub_down_id = -1;
    stub_down_sx = 0;
    stub_down_sy = 0;
    stub_down_time = 0;
    stub_touch_motion_calls = 0;
    stub_touch_motion_id = -1;
    stub_touch_motion_sx = 0;
    stub_touch_motion_sy = 0;
    stub_touch_up_calls = 0;
    stub_touch_up_id = -1;
    stub_touch_cancel_calls = 0;
    stub_touch_frame_calls = 0;
}

fn mkTouch(touch: *c.struct_wlr_touch) void {
    touch.* = std.mem.zeroes(c.struct_wlr_touch);
    touch.base.name = @constCast("touch0");
}

fn mkSurface(surface: *c.struct_wlr_surface) void {
    surface.* = std.mem.zeroes(c.struct_wlr_surface);
    listInit(&surface.events.destroy.listener_list);
}

test "touch create attaches devices and applies libinput modes" {
    resetTouchWorld();
    var touch: c.struct_wlr_touch = undefined;
    mkTouch(&touch);
    var output: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    output.name = @constCast("eDP-1");
    var m: Monitor = std.mem.zeroes(Monitor);
    m.wlr_output = &output;
    stub_target_monitor = &m;

    touch_create(&touch);
    try testing.expectEqual(@as(c_int, 1), stub_attach_calls);
    try testing.expectEqual(@as(c_int, 1), stub_map_output_calls);
    try testing.expect(stub_mapped_output == &output);
    try testing.expectEqual(@as(c_int, 1), stub_error_calls);
    try testing.expectEqual(@as(c_int, 0), stub_set_mode_calls);

    stub_is_libinput = true;
    stub_send_modes = 0;
    c.config.send_events_mode = 2;
    touch_create(&touch);
    try testing.expectEqual(@as(c_int, 0), stub_set_mode_calls);

    stub_send_modes = 3;
    touch_create(&touch);
    try testing.expectEqual(@as(c_int, 1), stub_set_mode_calls);
    try testing.expectEqual(@as(u32, 2), stub_set_mode_value);
}

test "touch coordinates derive layout offsets and client" {
    resetTouchWorld();
    var touch: c.struct_wlr_touch = undefined;
    mkTouch(&touch);
    var surface: c.struct_wlr_surface = undefined;
    mkSurface(&surface);
    var cl: Client = std.mem.zeroes(Client);
    stub_lx = 120;
    stub_ly = 80;
    stub_node_surface = &surface;
    stub_node_client = &cl;
    stub_node_x = 20;
    stub_node_y = 30;

    var x_off: f64 = 0;
    var y_off: f64 = 0;
    var got_client: [*c]Client = null;
    const got = touch_get_coords(&touch, 0.5, 0.5, &x_off, &y_off, &got_client);
    try testing.expect(got == &surface);
    try testing.expect(got_client == &cl);
    try testing.expectEqual(@as(f64, 100), x_off);
    try testing.expectEqual(@as(f64, 50), y_off);

    x_off = 0;
    y_off = 0;
    _ = touch_get_coords(&touch, 0.5, 0.5, &x_off, &y_off, null);
    try testing.expectEqual(@as(f64, 100), x_off);
}

test "xwayland touch scale only applies to scaled X11 clients" {
    resetTouchWorld();
    if (!build_options.xwayland)
        return error.SkipZigTest;
    var surface: c.struct_wlr_surface = undefined;
    mkSurface(&surface);
    var cl: Client = std.mem.zeroes(Client);
    cl.type = @intCast(c.X11);
    cl.xwayland_scale = 2.0;
    stub_toplevel_client = &cl;
    stub_toplevel_result = 1;
    stub_is_x11 = 1;
    c.config.xwayland_ignore_scale = 1;

    var sx: f64 = 10;
    var sy: f64 = 20;
    touch_apply_xwayland_scale(&surface, &sx, &sy);
    try testing.expectEqual(@as(f64, 20), sx);
    try testing.expectEqual(@as(f64, 40), sy);

    c.config.xwayland_ignore_scale = 0;
    sx = 10;
    sy = 20;
    touch_apply_xwayland_scale(&surface, &sx, &sy);
    try testing.expectEqual(@as(f64, 10), sx);

    c.config.xwayland_ignore_scale = 1;
    cl.xwayland_scale = 0;
    touch_apply_xwayland_scale(&surface, &sx, &sy);
    try testing.expectEqual(@as(f64, 10), sx);

    cl.xwayland_scale = 2.0;
    stub_is_x11 = 0;
    touch_apply_xwayland_scale(&surface, &sx, &sy);
    try testing.expectEqual(@as(f64, 10), sx);
}

fn downEvent(touch: [*c]c.struct_wlr_touch, id: i32, time: u32) c.struct_wlr_touch_down_event {
    var event = std.mem.zeroes(c.struct_wlr_touch_down_event);
    event.touch = touch;
    event.touch_id = id;
    event.time_msec = time;
    event.x = 0.5;
    event.y = 0.5;
    return event;
}

test "touch down sends touch protocol events" {
    resetTouchWorld();
    c.config.touch_enable = 1;
    var touch: c.struct_wlr_touch = undefined;
    mkTouch(&touch);
    var surface: c.struct_wlr_surface = undefined;
    mkSurface(&surface);
    stub_accepts_touch = true;
    stub_node_surface = &surface;
    stub_node_x = 10;
    stub_node_y = 20;
    stub_lx = 110;
    stub_ly = 220;

    var event = downEvent(&touch, 7, 100);
    handle_cursor_touch_down(null, &event);
    try testing.expectEqual(@as(usize, 1), listCount(&c.server.touch_points));
    try testing.expectEqual(@as(c_int, 1), stub_ipc_device_calls);
    try testing.expectEqual(@as(c_int, 1), stub_activity_calls);
    try testing.expectEqual(@as(c_int, 1), stub_hide_cursor_calls);
    try testing.expectEqual(@as(c_int, 1), stub_clear_focus_calls);
    try testing.expectEqual(@as(c_int, 1), stub_warp_calls);
    try testing.expectEqual(@as(c_int, 1), stub_touch_down_calls);
    try testing.expectEqual(@as(i32, 7), stub_down_id);
    try testing.expectEqual(@as(f64, 10), stub_down_sx);
    try testing.expectEqual(@as(f64, 20), stub_down_sy);
    try testing.expect(!listIsEmptyLocal(&surface.events.destroy.listener_list));

    const point = pointFromLink(c.server.touch_points.next);
    try testing.expect(point.touch_id == 7);
    try testing.expect(point.touch_protocol);
    point.surface_destroy.notify.?(&point.surface_destroy, null);
    try testing.expect(point.surface == null);
}

fn listIsEmptyLocal(head: *c.struct_wl_list) bool {
    return head.next == @as([*c]c.struct_wl_list, @ptrCast(head));
}

test "touch down emulates pointer without touch support" {
    resetTouchWorld();
    c.config.touch_enable = 1;
    c.config.touch_enable_mouse_emulation = 1;
    var touch: c.struct_wlr_touch = undefined;
    mkTouch(&touch);
    stub_accepts_touch = false;
    stub_lx = 40;
    stub_ly = 60;
    c.server.cursor.*.x = 10;
    c.server.cursor.*.y = 20;

    var event = downEvent(&touch, 3, 50);
    handle_cursor_touch_down(null, &event);
    try testing.expectEqual(@as(usize, 1), listCount(&c.server.touch_points));
    try testing.expectEqual(@as(c_int, 1), stub_motion_calls);
    try testing.expectEqual(@as(f64, 30), stub_motion_dx);
    try testing.expectEqual(@as(f64, 40), stub_motion_dy);
    try testing.expectEqual(@as(c_int, 1), stub_press_calls);
    try testing.expectEqual(@as(u32, c.BTN_LEFT), stub_press_event.button);
    try testing.expectEqual(@as(c_int, 1), stub_button_calls);
    try testing.expectEqual(@as(c_int, 2), stub_pointer_frame_calls);
    try testing.expectEqual(@as(c_int, 0), stub_clear_focus_calls);

    var motion = std.mem.zeroes(c.struct_wlr_touch_motion_event);
    motion.touch = &touch;
    motion.touch_id = 3;
    motion.time_msec = 60;
    handle_cursor_touch_motion(null, &motion);
    try testing.expectEqual(@as(c_int, 2), stub_motion_calls);
    try testing.expectEqual(@as(c_int, 3), stub_pointer_frame_calls);

    var up = std.mem.zeroes(c.struct_wlr_touch_up_event);
    up.touch = &touch;
    up.touch_id = 3;
    up.time_msec = 70;
    handle_cursor_touch_up(null, &up);
    try testing.expectEqual(@as(c_int, 2), stub_button_calls);
    try testing.expectEqual(@as(c_uint, @intCast(c.WL_POINTER_BUTTON_STATE_RELEASED)), stub_button_state);
    try testing.expectEqual(@as(usize, 0), listCount(&c.server.touch_points));

    handle_cursor_touch_frame(null, null);
    try testing.expectEqual(@as(c_int, 1), stub_touch_frame_calls);
    try testing.expectEqual(@as(c_int, 4), stub_pointer_frame_calls);
}

test "touch up and cancel clean protocol points" {
    resetTouchWorld();
    c.config.touch_enable = 1;
    var touch: c.struct_wlr_touch = undefined;
    mkTouch(&touch);
    var surface: c.struct_wlr_surface = undefined;
    mkSurface(&surface);
    stub_accepts_touch = true;
    stub_node_surface = &surface;

    var event = downEvent(&touch, 9, 10);
    handle_cursor_touch_down(null, &event);
    const removes = stub_list_remove_calls;
    var up = std.mem.zeroes(c.struct_wlr_touch_up_event);
    up.touch = &touch;
    up.touch_id = 9;
    handle_cursor_touch_up(null, &up);
    try testing.expectEqual(@as(c_int, 1), stub_touch_up_calls);
    try testing.expectEqual(@as(i32, 9), stub_touch_up_id);
    try testing.expectEqual(@as(usize, 0), listCount(&c.server.touch_points));
    try testing.expectEqual(removes + 2, stub_list_remove_calls);

    handle_cursor_touch_down(null, &event);
    var cancel = std.mem.zeroes(c.struct_wlr_touch_cancel_event);
    cancel.touch = &touch;
    cancel.touch_id = 9;
    handle_cursor_touch_cancel(null, &cancel);
    try testing.expectEqual(@as(c_int, 1), stub_touch_cancel_calls);
    try testing.expectEqual(@as(usize, 0), listCount(&c.server.touch_points));
}

test "motion and frame follow the touch point mode" {
    resetTouchWorld();
    c.config.touch_enable = 1;
    var touch: c.struct_wlr_touch = undefined;
    mkTouch(&touch);
    var surface: c.struct_wlr_surface = undefined;
    mkSurface(&surface);
    stub_accepts_touch = true;
    stub_node_surface = &surface;
    stub_node_x = 10;
    stub_node_y = 20;
    stub_lx = 110;
    stub_ly = 220;
    var event = downEvent(&touch, 4, 10);
    handle_cursor_touch_down(null, &event);

    stub_lx = 130;
    stub_ly = 260;
    var motion = std.mem.zeroes(c.struct_wlr_touch_motion_event);
    motion.touch = &touch;
    motion.touch_id = 4;
    motion.time_msec = 20;
    handle_cursor_touch_motion(null, &motion);
    try testing.expectEqual(@as(c_int, 1), stub_touch_motion_calls);
    try testing.expectEqual(@as(f64, 30), stub_touch_motion_sx);
    try testing.expectEqual(@as(f64, 60), stub_touch_motion_sy);

    handle_cursor_touch_frame(null, null);
    try testing.expectEqual(@as(c_int, 1), stub_touch_frame_calls);
    try testing.expectEqual(@as(c_int, 0), stub_pointer_frame_calls);
}

test "disabling touch finishes all points and releases emulation" {
    resetTouchWorld();
    c.config.touch_enable = 1;
    c.config.touch_enable_mouse_emulation = 1;
    var touch: c.struct_wlr_touch = undefined;
    mkTouch(&touch);
    stub_accepts_touch = false;
    var event = downEvent(&touch, 5, 10);
    handle_cursor_touch_down(null, &event);
    try testing.expectEqual(@as(usize, 1), listCount(&c.server.touch_points));

    c.config.touch_enable = 0;
    var motion = std.mem.zeroes(c.struct_wlr_touch_motion_event);
    motion.touch = &touch;
    motion.touch_id = 5;
    handle_cursor_touch_motion(null, &motion);
    try testing.expectEqual(@as(usize, 0), listCount(&c.server.touch_points));
    try testing.expectEqual(@as(c_int, 2), stub_button_calls);
    try testing.expectEqual(@as(c_uint, @intCast(c.WL_POINTER_BUTTON_STATE_RELEASED)), stub_button_state);
    try testing.expectEqual(@as(u32, 0), stub_button_time);

    handle_cursor_touch_frame(null, null);
    try testing.expectEqual(@as(c_int, 1), stub_touch_frame_calls);
}

test "touch finish all removes protocol listeners" {
    resetTouchWorld();
    c.config.touch_enable = 1;
    var touch: c.struct_wlr_touch = undefined;
    mkTouch(&touch);
    var surface: c.struct_wlr_surface = undefined;
    mkSurface(&surface);
    stub_accepts_touch = true;
    stub_node_surface = &surface;
    var event = downEvent(&touch, 6, 10);
    handle_cursor_touch_down(null, &event);
    try testing.expectEqual(@as(usize, 1), listCount(&c.server.touch_points));
    touch_finish_all();
    try testing.expectEqual(@as(usize, 0), listCount(&c.server.touch_points));
    try testing.expect(listIsEmptyLocal(&surface.events.destroy.listener_list));
}
