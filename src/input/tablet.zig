//! Port of input/tablet.c (Phase 5, input slice 3, slice 70).

const std = @import("std");
const c = @import("cc");
const build_options = @import("build_options");

const Client = c.Client;
const Monitor = c.Monitor;
const LayerSurface = c.LayerSurface;
const Tablet = c.Tablet;
const TabletPad = c.TabletPad;
const TabletTool = c.TabletTool;

extern fn wlr_input_device_is_libinput(device: [*c]c.struct_wlr_input_device) callconv(.c) bool;
extern fn wlr_libinput_get_device_handle(device: [*c]c.struct_wlr_input_device) callconv(.c) ?*c.struct_libinput_device;
extern fn libinput_device_config_send_events_get_modes(device: [*c]c.struct_libinput_device) callconv(.c) u32;
extern fn libinput_device_config_send_events_set_mode(device: [*c]c.struct_libinput_device, mode: u32) callconv(.c) c_int;
extern fn libinput_device_get_device_group(device: [*c]c.struct_libinput_device) callconv(.c) ?*c.struct_libinput_device_group;
extern fn wlr_tablet_create(manager: [*c]c.struct_wlr_tablet_manager_v2, seat: [*c]c.struct_wlr_seat, device: [*c]c.struct_wlr_input_device) callconv(.c) [*c]c.struct_wlr_tablet_v2_tablet;
extern fn wlr_tablet_pad_create(manager: [*c]c.struct_wlr_tablet_manager_v2, seat: [*c]c.struct_wlr_seat, device: [*c]c.struct_wlr_input_device) callconv(.c) [*c]c.struct_wlr_tablet_v2_tablet_pad;
extern fn wlr_tablet_tool_create(manager: [*c]c.struct_wlr_tablet_manager_v2, seat: [*c]c.struct_wlr_seat, tool: [*c]c.struct_wlr_tablet_tool) callconv(.c) [*c]c.struct_wlr_tablet_v2_tablet_tool;
extern fn wlr_cursor_attach_input_device(cursor: [*c]c.struct_wlr_cursor, device: [*c]c.struct_wlr_input_device) callconv(.c) void;
extern fn wlr_cursor_move(cursor: [*c]c.struct_wlr_cursor, device: [*c]c.struct_wlr_input_device, dx: f64, dy: f64) callconv(.c) void;
extern fn wlr_cursor_warp_absolute(cursor: [*c]c.struct_wlr_cursor, device: [*c]c.struct_wlr_input_device, x: f64, y: f64) callconv(.c) void;
extern fn wlr_cursor_set_surface(cursor: [*c]c.struct_wlr_cursor, surface: [*c]c.struct_wlr_surface, hotspot_x: i32, hotspot_y: i32) callconv(.c) void;
extern fn wlr_cursor_map_input_to_output(cursor: [*c]c.struct_wlr_cursor, device: [*c]c.struct_wlr_input_device, output: [*c]c.struct_wlr_output) callconv(.c) void;
extern fn wlr_seat_client_for_wl_client(seat: [*c]c.struct_wlr_seat, client: ?*c.struct_wl_client) callconv(.c) [*c]c.struct_wlr_seat_client;
extern fn wl_resource_get_client(resource: ?*c.struct_wl_resource) callconv(.c) ?*c.struct_wl_client;
extern fn pointer_process_motion(time: u32, device: [*c]c.struct_wlr_input_device, dx: f64, dy: f64, dx_unaccel: f64, dy_unaccel: f64) callconv(.c) void;
extern fn pointer_process_button_press(event: *c.struct_wlr_pointer_button_event) callconv(.c) bool;
extern fn pointer_cursor_activity() callconv(.c) void;
extern fn monitor_at_point(x: f64, y: f64) callconv(.c) [*c]Monitor;
extern fn set_selected_monitor(m: [*c]Monitor) callconv(.c) void;
extern fn printstatus(t: c.enum_ipc_watch_type) callconv(.c) void;
extern fn node_at_point(x: f64, y: f64, psurface: [*c][*c]c.struct_wlr_surface, pc: [*c][*c]Client, pl: [*c]?*anyopaque, bar: [*c]?*anyopaque, nx: *f64, ny: *f64) callconv(.c) void;
extern fn toplevel_from_wlr_surface(s: [*c]c.struct_wlr_surface, pc: [*c][*c]Client, pl: [*c][*c]LayerSurface) callconv(.c) i32;
extern fn client_focus(cl: [*c]Client, lift: i32) callconv(.c) void;
extern fn client_is_unmanaged(cl: [*c]Client) callconv(.c) i32;
extern fn client_is_x11(cl: [*c]Client) callconv(.c) i32;
extern fn wlr_surface_accepts_tablet_v2(surface: [*c]c.struct_wlr_surface, tablet: [*c]c.struct_wlr_tablet_v2_tablet) callconv(.c) bool;
extern fn find_device_rule(device: [*c]c.struct_wlr_input_device) callconv(.c) [*c]c.ConfigDeviceRule;
extern fn device_target_monitor(device: [*c]c.struct_wlr_input_device) callconv(.c) [*c]Monitor;
extern fn acwm_notify_activity(seat: [*c]c.struct_wlr_seat) callconv(.c) void;
extern fn wlr_tablet_v2_tablet_tool_notify_proximity_in(tool: [*c]c.struct_wlr_tablet_v2_tablet_tool, tablet: [*c]c.struct_wlr_tablet_v2_tablet, surface: [*c]c.struct_wlr_surface) callconv(.c) void;
extern fn wlr_tablet_v2_tablet_tool_notify_proximity_out(tool: [*c]c.struct_wlr_tablet_v2_tablet_tool) callconv(.c) void;
extern fn wlr_tablet_v2_tablet_tool_notify_motion(tool: [*c]c.struct_wlr_tablet_v2_tablet_tool, x: f64, y: f64) callconv(.c) void;
extern fn wlr_tablet_v2_tablet_tool_notify_pressure(tool: [*c]c.struct_wlr_tablet_v2_tablet_tool, pressure: f64) callconv(.c) void;
extern fn wlr_tablet_v2_tablet_tool_notify_distance(tool: [*c]c.struct_wlr_tablet_v2_tablet_tool, distance: f64) callconv(.c) void;
extern fn wlr_tablet_v2_tablet_tool_notify_tilt(tool: [*c]c.struct_wlr_tablet_v2_tablet_tool, x: f64, y: f64) callconv(.c) void;
extern fn wlr_tablet_v2_tablet_tool_notify_rotation(tool: [*c]c.struct_wlr_tablet_v2_tablet_tool, degrees: f64) callconv(.c) void;
extern fn wlr_tablet_v2_tablet_tool_notify_slider(tool: [*c]c.struct_wlr_tablet_v2_tablet_tool, position: f64) callconv(.c) void;
extern fn wlr_tablet_v2_tablet_tool_notify_wheel(tool: [*c]c.struct_wlr_tablet_v2_tablet_tool, degrees: f64, clicks: i32) callconv(.c) void;
extern fn wlr_tablet_v2_tablet_tool_notify_button(tool: [*c]c.struct_wlr_tablet_v2_tablet_tool, button: u32, state: c.enum_zwp_tablet_pad_v2_button_state) callconv(.c) void;
extern fn wlr_tablet_v2_tablet_tool_notify_down(tool: [*c]c.struct_wlr_tablet_v2_tablet_tool) callconv(.c) void;
extern fn wlr_tablet_v2_tablet_tool_notify_up(tool: [*c]c.struct_wlr_tablet_v2_tablet_tool) callconv(.c) void;
extern fn wlr_tablet_v2_tablet_pad_notify_enter(pad: [*c]c.struct_wlr_tablet_v2_tablet_pad, tablet: [*c]c.struct_wlr_tablet_v2_tablet, surface: [*c]c.struct_wlr_surface) callconv(.c) u32;
extern fn wlr_tablet_v2_tablet_pad_notify_leave(pad: [*c]c.struct_wlr_tablet_v2_tablet_pad, surface: [*c]c.struct_wlr_surface) callconv(.c) u32;
extern fn wlr_tablet_tool_v2_start_implicit_grab(tool: [*c]c.struct_wlr_tablet_v2_tablet_tool) callconv(.c) void;

fn tabletFromListener(listener: [*c]c.struct_wl_listener) *Tablet {
    return @ptrFromInt(@intFromPtr(listener) - @offsetOf(Tablet, "destroy"));
}

fn padFromListener(listener: [*c]c.struct_wl_listener, comptime field: []const u8) *TabletPad {
    return @ptrFromInt(@intFromPtr(listener) - @offsetOf(TabletPad, field));
}

fn toolFromListener(listener: [*c]c.struct_wl_listener, comptime field: []const u8) *TabletTool {
    return @ptrFromInt(@intFromPtr(listener) - @offsetOf(TabletTool, field));
}

export fn tablet_create(device: [*c]c.struct_wlr_input_device) callconv(.c) void {
    const raw = c.calloc(1, @sizeOf(Tablet)) orelse {
        c.acwm_error_impl(true, c.WLR_ERROR, "src/input/tablet.c", 23, "could not allocate tablet");
        return;
    };
    const tablet = @as(*Tablet, @ptrCast(@alignCast(raw)));

    if (!c.wlr_input_device_is_libinput(device)) {
        c.free(tablet);
        return;
    }
    const device_handle = c.wlr_libinput_get_device_handle(device);
    if (device_handle == null) {
        c.free(tablet);
        return;
    }

    tablet.device = device;
    tablet.tablet_v2 = c.wlr_tablet_create(c.server.tablet_manager, c.server.seat, device);
    if (tablet.tablet_v2 == null) {
        c.free(tablet);
        return;
    }

    tablet.tablet_v2.*.wlr_tablet.*.data = tablet;
    tablet.destroy.notify = handle_tablet_destroy;
    c.wl_signal_add(&tablet.device.*.events.destroy, &tablet.destroy);

    if (c.libinput_device_config_send_events_get_modes(device_handle) != 0) {
        _ = c.libinput_device_config_send_events_set_mode(device_handle, c.config.send_events_mode);
        c.wlr_cursor_attach_input_device(c.server.cursor, device);
    }

    c.wl_list_insert(&c.server.tablets, &tablet.link);

    const group = c.libinput_device_get_device_group(c.wlr_libinput_get_device_handle(device));
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.tablet_pads);
    var pos = c.server.tablet_pads.next;
    while (pos != head) : (pos = pos.*.next) {
        const tablet_pad = @as(*TabletPad, @ptrFromInt(@intFromPtr(pos) - @offsetOf(TabletPad, "link")));
        const pad_device = tablet_pad.device;
        if (!c.wlr_input_device_is_libinput(pad_device))
            continue;
        const pad_group = c.libinput_device_get_device_group(c.wlr_libinput_get_device_handle(pad_device));
        if (pad_group == group) {
            attach_tablet_pad(tablet_pad, tablet);
            break;
        }
    }
}

export fn handle_tablet_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const tablet = tabletFromListener(listener);
    c.wl_list_remove(&listener.*.link);
    c.wl_list_remove(&tablet.link);
    c.free(tablet);
}

export fn handle_tablet_pad_tablet_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const tablet_pad = padFromListener(listener, "tablet_destroy");
    tablet_pad.tablet = null;
    c.wl_list_remove(&tablet_pad.tablet_destroy.link);
    c.wl_list_init(&tablet_pad.tablet_destroy.link);
}

export fn attach_tablet_pad(tablet_pad: [*c]TabletPad, tablet: [*c]Tablet) callconv(.c) void {
    tablet_pad.*.tablet = tablet;
    c.wl_list_remove(&tablet_pad.*.tablet_destroy.link);
    tablet_pad.*.tablet_destroy.notify = handle_tablet_pad_tablet_destroy;
    c.wl_signal_add(&tablet.*.device.*.events.destroy, &tablet_pad.*.tablet_destroy);
}

export fn handle_tablet_pad_attach(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    const tablet_pad = padFromListener(listener, "attach");
    const wlr_tool = @as([*c]c.struct_wlr_tablet_tool, @ptrCast(@alignCast(data.?)));
    const tool = @as(?*TabletTool, @ptrCast(@alignCast(wlr_tool.*.data)));
    if (tool == null)
        return;
    attach_tablet_pad(tablet_pad, tool.?.tablet);
}

export fn tablet_pad_create(device: [*c]c.struct_wlr_input_device) callconv(.c) void {
    const raw = c.calloc(1, @sizeOf(TabletPad)) orelse {
        c.acwm_error_impl(true, c.WLR_ERROR, "src/input/tablet.c", 131, "could not allocate tablet_pad");
        return;
    };
    const tablet_pad = @as(*TabletPad, @ptrCast(@alignCast(raw)));
    tablet_pad.device = device;
    tablet_pad.pad_v2 = c.wlr_tablet_pad_create(c.server.tablet_manager, c.server.seat, device);
    if (tablet_pad.pad_v2 == null) {
        c.acwm_error_impl(true, c.WLR_ERROR, "src/input/tablet.c", 139, "could not create tablet_pad_v2 wrapper");
        c.free(tablet_pad);
        return;
    }

    tablet_pad.destroy.notify = handle_tablet_pad_destroy;
    tablet_pad.attach.notify = handle_tablet_pad_attach;
    c.wl_list_init(&tablet_pad.tablet_destroy.link);
    c.wl_signal_add(&device.*.events.destroy, &tablet_pad.destroy);
    c.wl_signal_add(&tablet_pad.pad_v2.*.wlr_pad.*.events.attach_tablet, &tablet_pad.attach);
    c.wl_list_insert(&c.server.tablet_pads, &tablet_pad.link);

    if (!c.wlr_input_device_is_libinput(device))
        return;

    const group = c.libinput_device_get_device_group(c.wlr_libinput_get_device_handle(device));
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.tablets);
    var pos = c.server.tablets.next;
    while (pos != head) : (pos = pos.*.next) {
        const tablet = @as(*Tablet, @ptrFromInt(@intFromPtr(pos) - @offsetOf(Tablet, "link")));
        const tablet_device = tablet.device;
        if (!c.wlr_input_device_is_libinput(tablet_device))
            continue;
        const tablet_group = c.libinput_device_get_device_group(c.wlr_libinput_get_device_handle(tablet_device));
        if (tablet_group == group) {
            attach_tablet_pad(tablet_pad, tablet);
            break;
        }
    }
}

export fn handle_tablet_pad_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const tablet_pad = padFromListener(listener, "destroy");
    c.wl_list_remove(&listener.*.link);
    c.wl_list_remove(&tablet_pad.link);
    c.wl_list_remove(&tablet_pad.tablet_destroy.link);
    c.wl_list_remove(&tablet_pad.attach.link);
    c.free(tablet_pad);
}

export fn handle_tablet_tool_surface_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const tool = toolFromListener(listener, "surface_destroy");
    c.wl_list_remove(&tool.surface_destroy.link);
    tool.curr_surface = null;
}

export fn handle_tablet_tool_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const tool = toolFromListener(listener, "destroy");
    if (tool.curr_surface != null)
        c.wl_list_remove(&tool.surface_destroy.link);
    c.wl_list_remove(&tool.set_cursor.link);
    c.wl_list_remove(&listener.*.link);
    c.free(tool);
}

export fn handle_tablet_tool_set_cursor(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    const tool = toolFromListener(listener, "set_cursor");
    const event = @as(*c.struct_wlr_tablet_v2_event_cursor, @ptrCast(@alignCast(data.?)));

    var focused_client: [*c]c.struct_wlr_seat_client = null;
    if (tool.tool_v2.*.focused_surface != null) {
        const resource = tool.tool_v2.*.focused_surface.*.resource;
        focused_client = c.wlr_seat_client_for_wl_client(c.server.seat, c.wl_resource_get_client(resource));
    }

    if (focused_client != event.seat_client)
        return;

    c.wlr_cursor_set_surface(c.server.cursor, event.surface, event.hotspot_x, event.hotspot_y);
}

export fn tablet_tool_motion(tool: [*c]TabletTool, change_x: bool, change_y: bool, x: f64, y: f64, dx: f64, dy: f64) callconv(.c) void {
    if (!change_x and !change_y)
        return;

    var surface: [*c]c.struct_wlr_surface = null;
    var cl: [*c]Client = null;
    var w: [*c]Client = null;
    var l: [*c]LayerSurface = null;
    const tablet = tool.*.tablet;

    switch (tool.*.tool_v2.*.wlr_tool.*.type) {
        c.WLR_TABLET_TOOL_TYPE_LENS, c.WLR_TABLET_TOOL_TYPE_MOUSE => {
            c.wlr_cursor_move(c.server.cursor, tablet.*.device, dx, dy);
        },
        else => {
            c.wlr_cursor_warp_absolute(c.server.cursor, tablet.*.device, if (change_x) x else std.math.nan(f64), if (change_y) y else std.math.nan(f64));
        },
    }

    pointer_process_motion(0, null, 0, 0, 0, 0);

    if (c.config.sloppyfocus != 0) {
        const oldmon = c.server.selected_monitor;
        set_selected_monitor(monitor_at_point(c.server.cursor.*.x, c.server.cursor.*.y));
        if (oldmon != c.server.selected_monitor)
            printstatus(@intCast(c.IPC_WATCH_MONITOR | c.IPC_WATCH_ALL_MONITORS));
    }

    var sx: f64 = 0;
    var sy: f64 = 0;
    node_at_point(c.server.cursor.*.x, c.server.cursor.*.y, &surface, &cl, null, null, &sx, &sy);
    if (c.server.cursor_mode == c.CurPressed and c.server.seat.*.drag == null and
        surface != c.server.seat.*.pointer_state.focused_surface and
        toplevel_from_wlr_surface(c.server.seat.*.pointer_state.focused_surface, &w, &l) >= 0)
    {
        cl = w;
        surface = c.server.seat.*.pointer_state.focused_surface;
        sx = c.server.cursor.*.x - @as(f64, @floatFromInt(if (l != null) l.*.scene.*.node.x else w.*.geom.x));
        sy = c.server.cursor.*.y - @as(f64, @floatFromInt(if (l != null) l.*.scene.*.node.y else w.*.geom.y));
    }

    if (c.config.sloppyfocus != 0 and cl != null and cl.*.scene != null and cl.*.scene.*.node.enabled and
        (surface != c.server.seat.*.pointer_state.focused_surface or
            (c.server.selected_monitor != null and c.server.selected_monitor.*.sel != null and
                cl != c.server.selected_monitor.*.sel)) and
        client_is_unmanaged(cl) == 0)
    {
        client_focus(cl, 0);
    }

    if (surface != null and !c.wlr_surface_accepts_tablet_v2(surface, tablet.*.tablet_v2))
        surface = null;

    if (surface != tool.*.curr_surface) {
        if (tool.*.curr_surface != null) {
            wlr_tablet_v2_tablet_tool_notify_proximity_out(tool.*.tool_v2);
            const head: [*c]c.struct_wl_list = @ptrCast(&c.server.tablet_pads);
            var pos = c.server.tablet_pads.next;
            while (pos != head) : (pos = pos.*.next) {
                const tablet_pad = @as(*TabletPad, @ptrFromInt(@intFromPtr(pos) - @offsetOf(TabletPad, "link")));
                if (tablet_pad.tablet != null and tablet_pad.tablet == tablet)
                    _ = wlr_tablet_v2_tablet_pad_notify_leave(tablet_pad.pad_v2, tool.*.curr_surface);
            }
            c.wl_list_remove(&tool.*.surface_destroy.link);
        }
        if (surface != null) {
            const head: [*c]c.struct_wl_list = @ptrCast(&c.server.tablet_pads);
            var pos = c.server.tablet_pads.next;
            while (pos != head) : (pos = pos.*.next) {
                const tablet_pad = @as(*TabletPad, @ptrFromInt(@intFromPtr(pos) - @offsetOf(TabletPad, "link")));
                if (tablet_pad.tablet != null and tablet_pad.tablet == tablet)
                    _ = wlr_tablet_v2_tablet_pad_notify_enter(tablet_pad.pad_v2, tablet.*.tablet_v2, surface);
            }
            wlr_tablet_v2_tablet_tool_notify_proximity_in(tool.*.tool_v2, tablet.*.tablet_v2, surface);
            c.wl_signal_add(&surface.*.events.destroy, &tool.*.surface_destroy);
        }
        tool.*.curr_surface = surface;
    }

    if (build_options.xwayland and cl != null and client_is_x11(cl) != 0 and
        c.config.xwayland_ignore_scale != 0 and cl.*.xwayland_scale > 0)
    {
        sx *= cl.*.xwayland_scale;
        sy *= cl.*.xwayland_scale;
    }

    if (surface != null)
        wlr_tablet_v2_tablet_tool_notify_motion(tool.*.tool_v2, sx, sy);

    acwm_notify_activity(c.server.seat);
    pointer_cursor_activity();
}

export fn handle_tablet_tool_proximity(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as(*c.struct_wlr_tablet_tool_proximity_event, @ptrCast(@alignCast(data.?)));
    const wlr_tool = event.*.tool;
    var tool = @as(?*TabletTool, @ptrCast(@alignCast(wlr_tool.*.data)));

    if (tool == null) {
        const raw = c.calloc(1, @sizeOf(TabletTool)) orelse {
            c.acwm_error_impl(true, c.WLR_ERROR, "src/input/tablet.c", 281, "could not allocate tablet_tool");
            return;
        };
        const new_tool = @as(*TabletTool, @ptrCast(@alignCast(raw)));
        new_tool.tool_v2 = c.wlr_tablet_tool_create(c.server.tablet_manager, c.server.seat, wlr_tool);
        new_tool.surface_destroy.notify = handle_tablet_tool_surface_destroy;
        new_tool.destroy.notify = handle_tablet_tool_destroy;
        new_tool.set_cursor.notify = handle_tablet_tool_set_cursor;
        new_tool.tablet = @as([*c]Tablet, @ptrCast(@alignCast(event.*.tablet.*.data)));
        wlr_tool.*.data = new_tool;
        c.wl_signal_add(&new_tool.tool_v2.*.wlr_tool.*.events.destroy, &new_tool.destroy);
        c.wl_signal_add(&new_tool.tool_v2.*.events.set_cursor, &new_tool.set_cursor);
        tool = new_tool;
    }

    const rule = c.find_device_rule(&event.*.tablet.*.base);
    const should_map = rule != null and (rule.*.monitor[0] != 0 or rule.*.map_focus_monitor == 1);
    if (should_map) {
        const target = c.device_target_monitor(&event.*.tablet.*.base);
        if (target != null) {
            c.wlr_cursor_map_input_to_output(c.server.cursor, &event.*.tablet.*.base, target.*.wlr_output);
            c.acwm_error_impl(true, c.WLR_DEBUG, "src/input/tablet.c", 302, "Mapping tablet %s to output %s", event.*.tablet.*.base.name, target.*.wlr_output.*.name);
        }
    }

    switch (event.*.state) {
        c.WLR_TABLET_TOOL_PROXIMITY_OUT => {
            wlr_tablet_v2_tablet_tool_notify_proximity_out(tool.?.tool_v2);
            if (tool.?.curr_surface != null)
                c.wl_list_remove(&tool.?.surface_destroy.link);
            tool.?.curr_surface = null;
        },
        c.WLR_TABLET_TOOL_PROXIMITY_IN => {
            tablet_tool_motion(tool.?, true, true, event.*.x, event.*.y, 0, 0);
        },
        else => {},
    }
}

export fn handle_tablet_tool_axis(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as(*c.struct_wlr_tablet_tool_axis_event, @ptrCast(@alignCast(data.?)));
    const tool = @as(?*TabletTool, @ptrCast(@alignCast(event.*.tool.*.data)));
    if (tool == null)
        return;

    tablet_tool_motion(tool.?, (event.*.updated_axes & c.WLR_TABLET_TOOL_AXIS_X) != 0, (event.*.updated_axes & c.WLR_TABLET_TOOL_AXIS_Y) != 0, event.*.x, event.*.y, event.*.dx, event.*.dy);

    if ((event.*.updated_axes & c.WLR_TABLET_TOOL_AXIS_PRESSURE) != 0)
        wlr_tablet_v2_tablet_tool_notify_pressure(tool.?.tool_v2, event.*.pressure);
    if ((event.*.updated_axes & c.WLR_TABLET_TOOL_AXIS_DISTANCE) != 0)
        wlr_tablet_v2_tablet_tool_notify_distance(tool.?.tool_v2, event.*.distance);
    if ((event.*.updated_axes & c.WLR_TABLET_TOOL_AXIS_TILT_X) != 0)
        tool.?.tilt_x = event.*.tilt_x;
    if ((event.*.updated_axes & c.WLR_TABLET_TOOL_AXIS_TILT_Y) != 0)
        tool.?.tilt_y = event.*.tilt_y;
    if ((event.*.updated_axes & (c.WLR_TABLET_TOOL_AXIS_TILT_X | c.WLR_TABLET_TOOL_AXIS_TILT_Y)) != 0)
        wlr_tablet_v2_tablet_tool_notify_tilt(tool.?.tool_v2, tool.?.tilt_x, tool.?.tilt_y);
    if ((event.*.updated_axes & c.WLR_TABLET_TOOL_AXIS_ROTATION) != 0)
        wlr_tablet_v2_tablet_tool_notify_rotation(tool.?.tool_v2, event.*.rotation);
    if ((event.*.updated_axes & c.WLR_TABLET_TOOL_AXIS_SLIDER) != 0)
        wlr_tablet_v2_tablet_tool_notify_slider(tool.?.tool_v2, event.*.slider);
    if ((event.*.updated_axes & c.WLR_TABLET_TOOL_AXIS_WHEEL) != 0)
        wlr_tablet_v2_tablet_tool_notify_wheel(tool.?.tool_v2, event.*.wheel_delta, 0);
}

export fn handle_tablet_tool_button(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as(*c.struct_wlr_tablet_tool_button_event, @ptrCast(@alignCast(data.?)));
    const tool = @as(?*TabletTool, @ptrCast(@alignCast(event.*.tool.*.data)));
    if (tool == null)
        return;
    wlr_tablet_v2_tablet_tool_notify_button(tool.?.tool_v2, event.*.button, @intCast(event.*.state));
}

export fn handle_tablet_tool_tip(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as(*c.struct_wlr_tablet_tool_tip_event, @ptrCast(@alignCast(data.?)));
    const tool = @as(?*TabletTool, @ptrCast(@alignCast(event.*.tool.*.data)));
    if (tool == null)
        return;

    var fakeptrbtnevent = std.mem.zeroes(c.struct_wlr_pointer_button_event);
    fakeptrbtnevent.button = c.BTN_LEFT;
    fakeptrbtnevent.state = @intCast(if (event.*.state == c.WLR_TABLET_TOOL_TIP_UP)
        c.WL_POINTER_BUTTON_STATE_RELEASED
    else
        c.WL_POINTER_BUTTON_STATE_PRESSED);
    fakeptrbtnevent.time_msec = event.*.time_msec;

    if (pointer_process_button_press(&fakeptrbtnevent))
        return;

    if (tool.?.curr_surface == null) {
        _ = c.wlr_seat_pointer_notify_button(c.server.seat, fakeptrbtnevent.time_msec, fakeptrbtnevent.button, fakeptrbtnevent.state);
        return;
    }

    if (event.*.state == c.WLR_TABLET_TOOL_TIP_UP) {
        wlr_tablet_v2_tablet_tool_notify_up(tool.?.tool_v2);
        return;
    }

    wlr_tablet_v2_tablet_tool_notify_down(tool.?.tool_v2);
    wlr_tablet_tool_v2_start_implicit_grab(tool.?.tool_v2);
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/tablet_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_list_insert_calls: c_int;
extern var stub_list_remove_calls: c_int;
extern var stub_list_init_calls: c_int;
extern var stub_is_libinput: bool;
extern var stub_send_modes: u32;
extern var stub_set_mode_calls: c_int;
extern var stub_set_mode_value: u32;
extern var stub_tablet_create_calls: c_int;
extern var stub_pad_create_calls: c_int;
extern var stub_tool_create_calls: c_int;
extern var stub_created_tablet: [*c]c.struct_wlr_tablet_v2_tablet;
extern var stub_created_pad: [*c]c.struct_wlr_tablet_v2_tablet_pad;
extern var stub_created_tool: [*c]c.struct_wlr_tablet_v2_tablet_tool;
extern var stub_tablet_v2: c.struct_wlr_tablet_v2_tablet;
extern var stub_tablet_pad_v2: c.struct_wlr_tablet_v2_tablet_pad;
extern var stub_tool_v2: c.struct_wlr_tablet_v2_tablet_tool;
extern var stub_wlr_tablet: c.struct_wlr_tablet;
extern var stub_wlr_pad: c.struct_wlr_tablet_pad;
extern var stub_wlr_tool: c.struct_wlr_tablet_tool;
extern var stub_attach_calls: c_int;
extern var stub_move_calls: c_int;
extern var stub_move_dx: f64;
extern var stub_move_dy: f64;
extern var stub_warp_calls: c_int;
extern var stub_warp_x: f64;
extern var stub_warp_y: f64;
extern var stub_set_surface_calls: c_int;
extern var stub_set_surface: [*c]c.struct_wlr_surface;
extern var stub_set_surface_hx: i32;
extern var stub_set_surface_hy: i32;
extern var stub_map_output_calls: c_int;
extern var stub_wl_client: ?*c.struct_wl_client;
extern var stub_seat_client: [*c]c.struct_wlr_seat_client;
extern var stub_motion_calls: c_int;
extern var stub_press_handled: bool;
extern var stub_press_event: c.struct_wlr_pointer_button_event;
extern var stub_cursor_activity_calls: c_int;
extern var stub_monitor: [*c]Monitor;
extern var stub_selected_calls: c_int;
extern var stub_selected_monitor_arg: [*c]Monitor;
extern var stub_printstatus_calls: c_int;
extern var stub_node_surface: [*c]c.struct_wlr_surface;
extern var stub_node_client: [*c]Client;
extern var stub_node_x: f64;
extern var stub_node_y: f64;
extern var stub_toplevel_result: i32;
extern var stub_toplevel_client: [*c]Client;
extern var stub_toplevel_layer: [*c]LayerSurface;
extern var stub_focus_calls: c_int;
extern var stub_unmanaged: i32;
extern var stub_is_x11: i32;
extern var stub_accepts_tablet: bool;
extern var stub_rule: [*c]c.ConfigDeviceRule;
extern var stub_target_monitor: [*c]Monitor;
extern var stub_error_calls: c_int;
extern var stub_activity_calls: c_int;
extern var stub_prox_in_calls: c_int;
extern var stub_prox_out_calls: c_int;
extern var stub_tool_motion_calls: c_int;
extern var stub_tool_motion_x: f64;
extern var stub_tool_motion_y: f64;
extern var stub_pressure_calls: c_int;
extern var stub_pressure: f64;
extern var stub_distance_calls: c_int;
extern var stub_distance: f64;
extern var stub_tilt_calls: c_int;
extern var stub_tilt_x: f64;
extern var stub_tilt_y: f64;
extern var stub_rotation_calls: c_int;
extern var stub_rotation: f64;
extern var stub_slider_calls: c_int;
extern var stub_slider: f64;
extern var stub_wheel_calls: c_int;
extern var stub_wheel: f64;
extern var stub_tool_button_calls: c_int;
extern var stub_tool_button: u32;
extern var stub_down_calls: c_int;
extern var stub_up_calls: c_int;
extern var stub_pad_enter_calls: c_int;
extern var stub_pad_leave_calls: c_int;
extern var stub_grab_calls: c_int;
extern var stub_seat_button_calls: c_int;

var test_cursor: c.struct_wlr_cursor = undefined;
var test_seat: c.struct_wlr_seat = undefined;

fn listInit(head: *c.struct_wl_list) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

fn listIsEmpty(head: *c.struct_wl_list) bool {
    return head.next == @as([*c]c.struct_wl_list, @ptrCast(head));
}

fn resetTabletWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    listInit(&c.server.tablets);
    listInit(&c.server.tablet_pads);
    test_cursor = std.mem.zeroes(c.struct_wlr_cursor);
    test_seat = std.mem.zeroes(c.struct_wlr_seat);
    c.server.cursor = &test_cursor;
    c.server.seat = &test_seat;
    c.server.tablet_manager = @ptrFromInt(0x9000);
    stub_list_insert_calls = 0;
    stub_list_remove_calls = 0;
    stub_list_init_calls = 0;
    stub_is_libinput = true;
    stub_send_modes = 0;
    stub_set_mode_calls = 0;
    stub_set_mode_value = 0;
    stub_tablet_create_calls = 0;
    stub_pad_create_calls = 0;
    stub_tool_create_calls = 0;
    stub_created_tablet = &stub_tablet_v2;
    stub_created_pad = &stub_tablet_pad_v2;
    stub_created_tool = &stub_tool_v2;
    stub_tablet_v2 = std.mem.zeroes(c.struct_wlr_tablet_v2_tablet);
    stub_tablet_v2.wlr_tablet = &stub_wlr_tablet;
    stub_tablet_pad_v2 = std.mem.zeroes(c.struct_wlr_tablet_v2_tablet_pad);
    stub_tablet_pad_v2.wlr_pad = &stub_wlr_pad;
    stub_tool_v2 = std.mem.zeroes(c.struct_wlr_tablet_v2_tablet_tool);
    stub_tool_v2.wlr_tool = &stub_wlr_tool;
    stub_wlr_tablet = std.mem.zeroes(c.struct_wlr_tablet);
    stub_wlr_pad = std.mem.zeroes(c.struct_wlr_tablet_pad);
    stub_wlr_tool = std.mem.zeroes(c.struct_wlr_tablet_tool);
    stub_wlr_tool.type = @intCast(c.WLR_TABLET_TOOL_TYPE_PEN);
    stub_attach_calls = 0;
    stub_move_calls = 0;
    stub_move_dx = 0;
    stub_move_dy = 0;
    stub_warp_calls = 0;
    stub_warp_x = 0;
    stub_warp_y = 0;
    stub_set_surface_calls = 0;
    stub_set_surface = null;
    stub_set_surface_hx = 0;
    stub_set_surface_hy = 0;
    stub_map_output_calls = 0;
    stub_motion_calls = 0;
    stub_press_handled = false;
    stub_cursor_activity_calls = 0;
    stub_monitor = null;
    stub_selected_calls = 0;
    stub_selected_monitor_arg = null;
    stub_printstatus_calls = 0;
    stub_node_surface = null;
    stub_node_client = null;
    stub_node_x = 0;
    stub_node_y = 0;
    stub_toplevel_result = -1;
    stub_toplevel_client = null;
    stub_toplevel_layer = null;
    stub_focus_calls = 0;
    stub_unmanaged = 0;
    stub_is_x11 = 0;
    stub_accepts_tablet = false;
    stub_rule = null;
    stub_target_monitor = null;
    stub_error_calls = 0;
    stub_activity_calls = 0;
    stub_prox_in_calls = 0;
    stub_prox_out_calls = 0;
    stub_tool_motion_calls = 0;
    stub_tool_motion_x = 0;
    stub_tool_motion_y = 0;
    stub_pressure_calls = 0;
    stub_pressure = 0;
    stub_distance_calls = 0;
    stub_distance = 0;
    stub_tilt_calls = 0;
    stub_tilt_x = 0;
    stub_tilt_y = 0;
    stub_rotation_calls = 0;
    stub_rotation = 0;
    stub_slider_calls = 0;
    stub_slider = 0;
    stub_wheel_calls = 0;
    stub_wheel = 0;
    stub_tool_button_calls = 0;
    stub_tool_button = 0;
    stub_down_calls = 0;
    stub_up_calls = 0;
    stub_pad_enter_calls = 0;
    stub_pad_leave_calls = 0;
    stub_grab_calls = 0;
    stub_seat_button_calls = 0;
}

fn mkDevice(dev: *c.struct_wlr_input_device, t: c_uint) void {
    dev.* = std.mem.zeroes(c.struct_wlr_input_device);
    dev.type = t;
    listInit(&dev.events.destroy.listener_list);
}

fn firstTablet() ?*Tablet {
    if (listIsEmpty(&c.server.tablets))
        return null;
    return @ptrFromInt(@intFromPtr(c.server.tablets.next) - @offsetOf(Tablet, "link"));
}

fn firstPad() ?*TabletPad {
    if (listIsEmpty(&c.server.tablet_pads))
        return null;
    return @ptrFromInt(@intFromPtr(c.server.tablet_pads.next) - @offsetOf(TabletPad, "link"));
}

fn addPad(pad_dev: [*c]c.struct_wlr_input_device, pad: *TabletPad) void {
    pad.* = std.mem.zeroes(TabletPad);
    pad.device = pad_dev;
    pad.pad_v2 = &stub_tablet_pad_v2;
    listInit(&pad.tablet_destroy.link);
    listInit(&pad.attach.link);
    c.wl_list_insert(&c.server.tablet_pads, &pad.link);
}

fn mkTool(tool: *TabletTool, tablet: *Tablet, surface: [*c]c.struct_wlr_surface) void {
    tool.* = std.mem.zeroes(TabletTool);
    tool.tool_v2 = &stub_tool_v2;
    tool.tablet = tablet;
    tool.curr_surface = surface;
    if (surface != null)
        listInit(&surface.*.events.destroy.listener_list);
}

test "tablet create registers devices and applies libinput modes" {
    resetTabletWorld();
    var dev: c.struct_wlr_input_device = undefined;
    mkDevice(&dev, c.WLR_INPUT_DEVICE_TABLET);

    stub_is_libinput = false;
    tablet_create(&dev);
    try testing.expect(firstTablet() == null);

    stub_is_libinput = true;
    stub_created_tablet = null;
    tablet_create(&dev);
    try testing.expect(firstTablet() == null);
    try testing.expectEqual(@as(c_int, 0), stub_attach_calls);

    resetTabletWorld();
    mkDevice(&dev, c.WLR_INPUT_DEVICE_TABLET);
    tablet_create(&dev);
    try testing.expectEqual(@as(c_int, 1), stub_tablet_create_calls);
    const tablet = firstTablet() orelse return error.TestUnexpectedResult;
    try testing.expect(tablet.device == &dev);
    try testing.expect(tablet.tablet_v2 == &stub_tablet_v2);
    try testing.expect(stub_wlr_tablet.data == @as(?*anyopaque, @ptrCast(tablet)));
    try testing.expect(tablet.destroy.notify != null);
    try testing.expect(!listIsEmpty(&dev.events.destroy.listener_list));
    try testing.expectEqual(@as(c_int, 0), stub_set_mode_calls);

    resetTabletWorld();
    mkDevice(&dev, c.WLR_INPUT_DEVICE_TABLET);
    stub_send_modes = 2;
    c.config.send_events_mode = 3;
    tablet_create(&dev);
    try testing.expectEqual(@as(c_int, 1), stub_set_mode_calls);
    try testing.expectEqual(@as(u32, 3), stub_set_mode_value);
    try testing.expectEqual(@as(c_int, 1), stub_attach_calls);
}

test "tablet create attaches a matching sibling pad" {
    resetTabletWorld();
    var dev: c.struct_wlr_input_device = undefined;
    var pad_dev: c.struct_wlr_input_device = undefined;
    mkDevice(&dev, c.WLR_INPUT_DEVICE_TABLET);
    mkDevice(&pad_dev, c.WLR_INPUT_DEVICE_TABLET_PAD);
    var pad: TabletPad = undefined;
    addPad(&pad_dev, &pad);

    tablet_create(&dev);
    const tablet = firstTablet() orelse return error.TestUnexpectedResult;
    try testing.expect(pad.tablet == tablet);
    try testing.expect(pad.tablet_destroy.notify != null);
    try testing.expect(!listIsEmpty(&tablet.device.*.events.destroy.listener_list));
}

test "tablet pad create wires attach and sibling tablets" {
    resetTabletWorld();
    var pad_dev: c.struct_wlr_input_device = undefined;
    mkDevice(&pad_dev, c.WLR_INPUT_DEVICE_TABLET_PAD);
    listInit(&stub_wlr_pad.events.attach_tablet.listener_list);

    tablet_pad_create(&pad_dev);
    try testing.expectEqual(@as(c_int, 1), stub_pad_create_calls);
    const pad = firstPad() orelse return error.TestUnexpectedResult;
    try testing.expect(pad.device == &pad_dev);
    try testing.expect(pad.pad_v2 == &stub_tablet_pad_v2);
    try testing.expect(pad.destroy.notify != null);
    try testing.expect(pad.attach.notify != null);
    try testing.expect(!listIsEmpty(&pad_dev.events.destroy.listener_list));
    try testing.expect(!listIsEmpty(&stub_wlr_pad.events.attach_tablet.listener_list));

    resetTabletWorld();
    mkDevice(&pad_dev, c.WLR_INPUT_DEVICE_TABLET_PAD);
    listInit(&stub_wlr_pad.events.attach_tablet.listener_list);
    var tablet_dev: c.struct_wlr_input_device = undefined;
    mkDevice(&tablet_dev, c.WLR_INPUT_DEVICE_TABLET);
    var tablet: Tablet = std.mem.zeroes(Tablet);
    tablet.device = &tablet_dev;
    tablet.tablet_v2 = &stub_tablet_v2;
    c.wl_list_insert(&c.server.tablets, &tablet.link);
    tablet_pad_create(&pad_dev);
    const new_pad = firstPad() orelse return error.TestUnexpectedResult;
    try testing.expect(new_pad.tablet == &tablet);
}

test "tablet destroy handlers remove listeners" {
    resetTabletWorld();
    const tablet = @as(*Tablet, @ptrCast(@alignCast(c.calloc(1, @sizeOf(Tablet)) orelse unreachable)));
    listInit(&tablet.link);
    listInit(&tablet.destroy.link);
    handle_tablet_destroy(&tablet.destroy, null);
    try testing.expectEqual(@as(c_int, 2), stub_list_remove_calls);

    const pad = @as(*TabletPad, @ptrCast(@alignCast(c.calloc(1, @sizeOf(TabletPad)) orelse unreachable)));
    listInit(&pad.link);
    listInit(&pad.tablet_destroy.link);
    listInit(&pad.attach.link);
    listInit(&pad.destroy.link);
    handle_tablet_pad_destroy(&pad.destroy, null);
    try testing.expectEqual(@as(c_int, 6), stub_list_remove_calls);

    const tool = @as(*TabletTool, @ptrCast(@alignCast(c.calloc(1, @sizeOf(TabletTool)) orelse unreachable)));
    listInit(&tool.destroy.link);
    listInit(&tool.set_cursor.link);
    handle_tablet_tool_destroy(&tool.destroy, null);
    try testing.expectEqual(@as(c_int, 8), stub_list_remove_calls);

    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    const tool2 = @as(*TabletTool, @ptrCast(@alignCast(c.calloc(1, @sizeOf(TabletTool)) orelse unreachable)));
    listInit(&tool2.destroy.link);
    listInit(&tool2.set_cursor.link);
    listInit(&tool2.surface_destroy.link);
    tool2.curr_surface = &surface;
    handle_tablet_tool_destroy(&tool2.destroy, null);
    try testing.expectEqual(@as(c_int, 11), stub_list_remove_calls);

    var tool3: TabletTool = std.mem.zeroes(TabletTool);
    tool3.curr_surface = &surface;
    listInit(&tool3.surface_destroy.link);
    handle_tablet_tool_surface_destroy(&tool3.surface_destroy, null);
    try testing.expect(tool3.curr_surface == null);
    try testing.expectEqual(@as(c_int, 12), stub_list_remove_calls);

    var pad2: TabletPad = std.mem.zeroes(TabletPad);
    listInit(&pad2.tablet_destroy.link);
    const inits = stub_list_init_calls;
    handle_tablet_pad_tablet_destroy(&pad2.tablet_destroy, null);
    try testing.expect(pad2.tablet == null);
    try testing.expectEqual(inits + 1, stub_list_init_calls);
}

test "attach pad updates tablet and handles attach events" {
    resetTabletWorld();
    var pad: TabletPad = std.mem.zeroes(TabletPad);
    listInit(&pad.tablet_destroy.link);
    var dev: c.struct_wlr_input_device = undefined;
    mkDevice(&dev, c.WLR_INPUT_DEVICE_TABLET);
    var tablet: Tablet = std.mem.zeroes(Tablet);
    tablet.device = &dev;
    attach_tablet_pad(&pad, &tablet);
    try testing.expect(pad.tablet == &tablet);
    try testing.expect(pad.tablet_destroy.notify != null);
    try testing.expect(!listIsEmpty(&dev.events.destroy.listener_list));

    var tablet2: Tablet = std.mem.zeroes(Tablet);
    tablet2.device = &dev;
    var tool: TabletTool = std.mem.zeroes(TabletTool);
    tool.tablet = &tablet2;
    var wlr_tool: c.struct_wlr_tablet_tool = std.mem.zeroes(c.struct_wlr_tablet_tool);
    wlr_tool.data = &tool;
    handle_tablet_pad_attach(&pad.attach, &wlr_tool);
    try testing.expect(pad.tablet == &tablet2);

    wlr_tool.data = null;
    handle_tablet_pad_attach(&pad.attach, &wlr_tool);
    try testing.expect(pad.tablet == &tablet2);
}

test "tool set cursor requires the focused seat client" {
    resetTabletWorld();
    var tool: TabletTool = std.mem.zeroes(TabletTool);
    tool.tool_v2 = &stub_tool_v2;
    var focused: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    focused.resource = @ptrFromInt(0x1000);
    stub_tool_v2.focused_surface = &focused;
    var event: c.struct_wlr_tablet_v2_event_cursor = std.mem.zeroes(c.struct_wlr_tablet_v2_event_cursor);
    var cursor_surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    event.surface = &cursor_surface;
    event.hotspot_x = 7;
    event.hotspot_y = 9;
    event.seat_client = stub_seat_client;

    handle_tablet_tool_set_cursor(&tool.set_cursor, &event);
    try testing.expectEqual(@as(c_int, 1), stub_set_surface_calls);
    try testing.expect(stub_set_surface == &cursor_surface);
    try testing.expectEqual(@as(i32, 7), stub_set_surface_hx);
    try testing.expectEqual(@as(i32, 9), stub_set_surface_hy);

    event.seat_client = @ptrFromInt(0x10000);
    handle_tablet_tool_set_cursor(&tool.set_cursor, &event);
    try testing.expectEqual(@as(c_int, 1), stub_set_surface_calls);

    stub_tool_v2.focused_surface = null;
    event.seat_client = null;
    handle_tablet_tool_set_cursor(&tool.set_cursor, &event);
    try testing.expectEqual(@as(c_int, 2), stub_set_surface_calls);
}

test "tool motion moves, focuses and enters or leaves surfaces" {
    resetTabletWorld();
    var tablet: Tablet = std.mem.zeroes(Tablet);
    var dev: c.struct_wlr_input_device = undefined;
    mkDevice(&dev, c.WLR_INPUT_DEVICE_TABLET);
    tablet.device = &dev;
    tablet.tablet_v2 = &stub_tablet_v2;
    var tool: TabletTool = std.mem.zeroes(TabletTool);
    tool.tool_v2 = &stub_tool_v2;
    tool.tablet = &tablet;
    var pad: TabletPad = std.mem.zeroes(TabletPad);
    pad.tablet = &tablet;
    pad.pad_v2 = &stub_tablet_pad_v2;
    listInit(&pad.link);
    c.wl_list_insert(&c.server.tablet_pads, &pad.link);

    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    listInit(&surface.events.destroy.listener_list);
    var tree: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    tree.node.enabled = true;
    var cl: Client = std.mem.zeroes(Client);
    cl.scene = &tree;
    var m: Monitor = std.mem.zeroes(Monitor);
    m.sel = &cl;
    c.server.selected_monitor = &m;
    stub_monitor = &m;
    stub_node_surface = &surface;
    stub_node_client = &cl;
    stub_node_x = 30;
    stub_node_y = 40;
    stub_accepts_tablet = true;
    c.config.sloppyfocus = 1;
    stub_wlr_tool.type = @intCast(c.WLR_TABLET_TOOL_TYPE_MOUSE);
    test_cursor.x = 100;
    test_cursor.y = 200;

    tablet_tool_motion(&tool, true, true, 0.5, 0.5, 3, 4);
    try testing.expectEqual(@as(c_int, 1), stub_move_calls);
    try testing.expectEqual(@as(f64, 3), stub_move_dx);
    try testing.expectEqual(@as(f64, 4), stub_move_dy);
    try testing.expectEqual(@as(c_int, 1), stub_motion_calls);
    try testing.expectEqual(@as(c_int, 1), stub_selected_calls);
    try testing.expectEqual(@as(c_int, 0), stub_printstatus_calls);
    try testing.expectEqual(@as(c_int, 1), stub_focus_calls);
    try testing.expectEqual(@as(c_int, 1), stub_prox_in_calls);
    try testing.expectEqual(@as(c_int, 1), stub_pad_enter_calls);
    try testing.expect(tool.curr_surface == &surface);
    try testing.expect(!listIsEmpty(&surface.events.destroy.listener_list));
    try testing.expectEqual(@as(f64, 30), stub_tool_motion_x);
    try testing.expectEqual(@as(f64, 40), stub_tool_motion_y);
    try testing.expectEqual(@as(c_int, 1), stub_activity_calls);
    try testing.expectEqual(@as(c_int, 1), stub_cursor_activity_calls);

    tablet_tool_motion(&tool, true, true, 0.5, 0.5, 0, 0);
    try testing.expectEqual(@as(c_int, 1), stub_prox_in_calls);
    try testing.expectEqual(@as(c_int, 1), stub_pad_enter_calls);

    stub_accepts_tablet = false;
    tablet_tool_motion(&tool, true, true, 0.5, 0.5, 0, 0);
    try testing.expectEqual(@as(c_int, 1), stub_prox_out_calls);
    try testing.expectEqual(@as(c_int, 1), stub_pad_leave_calls);
    try testing.expect(tool.curr_surface == null);

    stub_wlr_tool.type = @intCast(c.WLR_TABLET_TOOL_TYPE_PEN);
    tablet_tool_motion(&tool, true, false, 0.25, 0.75, 0, 0);
    try testing.expectEqual(@as(c_int, 1), stub_warp_calls);
    try testing.expectEqual(@as(f64, 0.25), stub_warp_x);
    try testing.expect(std.math.isNan(stub_warp_y));

    if (build_options.xwayland) {
        stub_accepts_tablet = true;
        stub_wlr_tool.type = @intCast(c.WLR_TABLET_TOOL_TYPE_MOUSE);
        cl.type = @intCast(c.X11);
        cl.xwayland_scale = 2;
        stub_is_x11 = 1;
        c.config.xwayland_ignore_scale = 1;
        tablet_tool_motion(&tool, true, true, 0.5, 0.5, 0, 0);
        try testing.expectEqual(@as(f64, 60), stub_tool_motion_x);
        try testing.expectEqual(@as(f64, 80), stub_tool_motion_y);
    }
}

test "tool axis notifies pressure, distance, tilt and wheel" {
    resetTabletWorld();
    var tablet: Tablet = std.mem.zeroes(Tablet);
    tablet.tablet_v2 = &stub_tablet_v2;
    var tool: TabletTool = std.mem.zeroes(TabletTool);
    tool.tool_v2 = &stub_tool_v2;
    tool.tablet = &tablet;
    stub_wlr_tool.data = &tool;
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    tool.curr_surface = &surface;

    var event: c.struct_wlr_tablet_tool_axis_event = std.mem.zeroes(c.struct_wlr_tablet_tool_axis_event);
    event.tool = &stub_wlr_tool;
    event.updated_axes = @intCast(c.WLR_TABLET_TOOL_AXIS_PRESSURE | c.WLR_TABLET_TOOL_AXIS_DISTANCE |
        c.WLR_TABLET_TOOL_AXIS_TILT_X | c.WLR_TABLET_TOOL_AXIS_TILT_Y |
        c.WLR_TABLET_TOOL_AXIS_ROTATION | c.WLR_TABLET_TOOL_AXIS_SLIDER | c.WLR_TABLET_TOOL_AXIS_WHEEL);
    event.pressure = 0.7;
    event.distance = 12;
    event.tilt_x = 0.2;
    event.tilt_y = 0.4;
    event.rotation = 45;
    event.slider = 0.6;
    event.wheel_delta = 15;
    handle_tablet_tool_axis(&tool.set_cursor, &event);
    try testing.expectEqual(@as(c_int, 1), stub_pressure_calls);
    try testing.expectEqual(@as(f64, 0.7), stub_pressure);
    try testing.expectEqual(@as(c_int, 1), stub_distance_calls);
    try testing.expectEqual(@as(f64, 12), stub_distance);
    try testing.expectEqual(@as(c_int, 1), stub_tilt_calls);
    try testing.expectEqual(@as(f64, 0.2), stub_tilt_x);
    try testing.expectEqual(@as(f64, 0.4), stub_tilt_y);
    try testing.expectEqual(@as(f64, 0.2), tool.tilt_x);
    try testing.expectEqual(@as(f64, 0.4), tool.tilt_y);
    try testing.expectEqual(@as(c_int, 1), stub_rotation_calls);
    try testing.expectEqual(@as(f64, 45), stub_rotation);
    try testing.expectEqual(@as(c_int, 1), stub_slider_calls);
    try testing.expectEqual(@as(f64, 0.6), stub_slider);
    try testing.expectEqual(@as(c_int, 1), stub_wheel_calls);
    try testing.expectEqual(@as(f64, 15), stub_wheel);
}

test "tool button and tip dispatch to tablet and seat" {
    resetTabletWorld();
    var tablet: Tablet = std.mem.zeroes(Tablet);
    var tool: TabletTool = std.mem.zeroes(TabletTool);
    tool.tool_v2 = &stub_tool_v2;
    tool.tablet = &tablet;
    stub_wlr_tool.data = &tool;
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    tool.curr_surface = &surface;

    var button_ev: c.struct_wlr_tablet_tool_button_event = std.mem.zeroes(c.struct_wlr_tablet_tool_button_event);
    button_ev.tool = &stub_wlr_tool;
    button_ev.button = 0x110;
    button_ev.state = @intCast(c.WLR_BUTTON_PRESSED);
    handle_tablet_tool_button(&tool.set_cursor, &button_ev);
    try testing.expectEqual(@as(c_int, 1), stub_tool_button_calls);
    try testing.expectEqual(@as(u32, 0x110), stub_tool_button);

    var tip: c.struct_wlr_tablet_tool_tip_event = std.mem.zeroes(c.struct_wlr_tablet_tool_tip_event);
    tip.tool = &stub_wlr_tool;
    tip.state = @intCast(c.WLR_TABLET_TOOL_TIP_DOWN);
    tip.time_msec = 5;
    handle_tablet_tool_tip(&tool.set_cursor, &tip);
    try testing.expectEqual(@as(u32, c.BTN_LEFT), stub_press_event.button);
    try testing.expectEqual(@as(c_int, 1), stub_down_calls);
    try testing.expectEqual(@as(c_int, 1), stub_grab_calls);

    tip.state = @intCast(c.WLR_TABLET_TOOL_TIP_UP);
    handle_tablet_tool_tip(&tool.set_cursor, &tip);
    try testing.expectEqual(@as(c_int, 1), stub_up_calls);

    tool.curr_surface = null;
    tip.state = @intCast(c.WLR_TABLET_TOOL_TIP_DOWN);
    handle_tablet_tool_tip(&tool.set_cursor, &tip);
    try testing.expectEqual(@as(c_int, 1), stub_seat_button_calls);

    stub_press_handled = true;
    const downs = stub_down_calls;
    tool.curr_surface = &surface;
    handle_tablet_tool_tip(&tool.set_cursor, &tip);
    try testing.expectEqual(downs, stub_down_calls);
}

test "tool proximity allocates, maps and enters or leaves" {
    resetTabletWorld();
    var tablet: Tablet = std.mem.zeroes(Tablet);
    var dev: c.struct_wlr_input_device = undefined;
    mkDevice(&dev, c.WLR_INPUT_DEVICE_TABLET);
    tablet.device = &dev;
    tablet.tablet_v2 = &stub_tablet_v2;
    stub_wlr_tablet.data = &tablet;
    stub_wlr_tool.data = null;
    listInit(&stub_wlr_tool.events.destroy.listener_list);
    listInit(&stub_tool_v2.events.set_cursor.listener_list);
    var rule: c.ConfigDeviceRule = std.mem.zeroes(c.ConfigDeviceRule);
    rule.monitor[0] = 'e';
    stub_rule = &rule;
    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    var m: Monitor = std.mem.zeroes(Monitor);
    m.wlr_output = &out;
    stub_target_monitor = &m;

    var event: c.struct_wlr_tablet_tool_proximity_event = std.mem.zeroes(c.struct_wlr_tablet_tool_proximity_event);
    event.tablet = &stub_wlr_tablet;
    event.tool = &stub_wlr_tool;
    event.state = @intCast(c.WLR_TABLET_TOOL_PROXIMITY_IN);
    event.x = 0.5;
    event.y = 0.5;
    handle_tablet_tool_proximity(null, &event);
    try testing.expectEqual(@as(c_int, 1), stub_tool_create_calls);
    try testing.expect(stub_wlr_tool.data != null);
    const tool = @as(*TabletTool, @ptrCast(@alignCast(stub_wlr_tool.data)));
    try testing.expect(tool.tablet == &tablet);
    try testing.expect(tool.destroy.notify != null);
    try testing.expect(tool.set_cursor.notify != null);
    try testing.expectEqual(@as(c_int, 1), stub_map_output_calls);
    try testing.expectEqual(@as(c_int, 1), stub_error_calls);

    event.state = @intCast(c.WLR_TABLET_TOOL_PROXIMITY_OUT);
    handle_tablet_tool_proximity(null, &event);
    try testing.expectEqual(@as(c_int, 1), stub_prox_out_calls);
    try testing.expect(tool.curr_surface == null);
}
