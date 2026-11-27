//! Port of the XWayland integration in src/manage/client.c
//! (Phase 5, client slice 10, slice 67).

const std = @import("std");
const c = @import("cc");
const build_options = @import("build_options");

const Client = c.Client;
const Monitor = c.Monitor;
const Box = c.struct_wlr_box;
const Arg = c.Arg;

extern fn client_surface(cl: [*c]Client) callconv(.c) [*c]c.struct_wlr_surface;
extern fn client_is_x11(cl: [*c]Client) callconv(.c) i32;
extern fn client_is_unmanaged(cl: [*c]Client) callconv(.c) i32;
extern fn client_is_parked(cl: [*c]Client) callconv(.c) bool;
extern fn client_set_scale(s: [*c]c.struct_wlr_surface, scale: f32) callconv(.c) void;
extern fn client_update_xwayland_dest_size(cl: [*c]Client) callconv(.c) void;
extern fn client_focus(cl: ?*Client, lift: i32) callconv(.c) void;
extern fn client_focus_top(m: [*c]Monitor) callconv(.c) [*c]Client;
extern fn client_view_on_monitor(arg: *const Arg, want_animation: bool, m: [*c]Monitor, from_rule: bool) callconv(.c) void;
extern fn client_update_border_color(cl: [*c]Client) callconv(.c) void;
extern fn client_pending_minimized_state(cl: [*c]Client, minimized: i32) callconv(.c) void;
extern fn resize(cl: [*c]Client, geo: Box, opts: c.ResizeOpts) callconv(.c) void;
extern fn arrange(m: [*c]Monitor, want_animation: bool, from_view: bool) callconv(.c) void;
extern fn pointer_process_motion(time: u32, device: [*c]c.struct_wlr_input_device, dx: f64, dy: f64, dx_unaccel: f64, dy_unaccel: f64) callconv(.c) void;
extern fn printstatus(t: c.enum_ipc_watch_type) callconv(.c) void;
extern fn xwayland_primary_init() callconv(.c) void;
extern fn handle_client_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_client_request_fullscreen(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_client_request_maximize(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_client_request_minimize(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_client_set_title(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_client_map(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_client_unmap(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;

const TAG0: u32 = @as(u32, 1) << 31;

fn monitorOpt(p: [*c]Monitor) ?*Monitor {
    return if (p == null) null else @ptrCast(p);
}

fn VISIBLEON(cl: *const Client, m: *const Monitor) bool {
    if (cl.mon != @as([*c]Monitor, @ptrCast(@constCast(m))))
        return false;
    if (cl.isminimized != 0)
        return false;
    return (cl.tags & m.tagset[m.seltags]) != 0 or cl.isglobal != 0 or cl.isunglobal != 0;
}

fn roundI32(x: f32) i32 {
    return @intFromFloat(@round(x));
}

export fn xwayland_monitor(cl: ?*Client) callconv(.c) ?*Monitor {
    if (!build_options.xwayland)
        return null;
    if (cl != null and cl.?.mon != null)
        return @ptrCast(cl.?.mon);
    return monitorOpt(c.server.selected_monitor);
}

export fn xwayland_client_scale(cl: ?*Client) callconv(.c) f32 {
    if (!build_options.xwayland)
        return 1.0;
    if (c.config.xwayland_ignore_scale != 0) {
        const m = xwayland_monitor(cl);
        if (m != null and m.?.wlr_output != null)
            return m.?.wlr_output.*.scale;
        return 1.0;
    }
    return 1.0;
}

export fn xwayland_preferred_scale(cl: ?*Client) callconv(.c) f32 {
    if (!build_options.xwayland)
        return 1.0;
    if (c.config.xwayland_ignore_scale != 0)
        return 1.0;
    const m = xwayland_monitor(cl);
    if (m != null and m.?.wlr_output != null)
        return m.?.wlr_output.*.scale;
    return 1.0;
}

export fn xwayland_apply_scale(cl: *Client) callconv(.c) void {
    if (!build_options.xwayland or client_is_x11(cl) == 0 or client_surface(cl) == null)
        return;
    cl.xwayland_scale = xwayland_client_scale(cl);
    client_set_scale(client_surface(cl), xwayland_preferred_scale(cl));
}

export fn xwayland_screen_origin(x: *i32, y: *i32) callconv(.c) void {
    x.* = c.server.scene_geometry.x;
    y.* = c.server.scene_geometry.y;
}

export fn xwayland_logical_to_x11(box: *Box, scale_in: f32) callconv(.c) void {
    const scale: f32 = if (scale_in <= 0) 1.0 else scale_in;
    var ox: i32 = 0;
    var oy: i32 = 0;
    xwayland_screen_origin(&ox, &oy);
    box.x = roundI32(@as(f32, @floatFromInt(box.x - ox)) * scale);
    box.y = roundI32(@as(f32, @floatFromInt(box.y - oy)) * scale);
    box.width = roundI32(@as(f32, @floatFromInt(box.width)) * scale);
    box.height = roundI32(@as(f32, @floatFromInt(box.height)) * scale);
}

export fn xwayland_x11_to_logical(box: *Box, scale_in: f32) callconv(.c) void {
    const scale: f32 = if (scale_in <= 0) 1.0 else scale_in;
    var ox: i32 = 0;
    var oy: i32 = 0;
    xwayland_screen_origin(&ox, &oy);
    box.x = roundI32(@as(f32, @floatFromInt(box.x)) / scale) + ox;
    box.y = roundI32(@as(f32, @floatFromInt(box.y)) / scale) + oy;
    box.width = roundI32(@as(f32, @floatFromInt(box.width)) / scale);
    box.height = roundI32(@as(f32, @floatFromInt(box.height)) / scale);
}

export fn client_get_x11_geometry(cl: *Client, xgeo: *Box) callconv(.c) void {
    if (c.config.xwayland_ignore_scale != 0 and cl.isfullscreen != 0 and cl.mon != null and
        client_is_unmanaged(cl) == 0)
    {
        var width: c_int = 0;
        var height: c_int = 0;
        var ox: i32 = 0;
        var oy: i32 = 0;
        c.wlr_output_transformed_resolution(cl.mon.*.wlr_output, &width, &height);
        xwayland_screen_origin(&ox, &oy);
        xgeo.x = roundI32(@as(f32, @floatFromInt(cl.mon.*.m.x - ox)) * cl.xwayland_scale);
        xgeo.y = roundI32(@as(f32, @floatFromInt(cl.mon.*.m.y - oy)) * cl.xwayland_scale);
        xgeo.width = width;
        xgeo.height = height;
    } else {
        const bw: i32 = @intCast(cl.bw);
        xgeo.x = cl.geom.x + bw;
        xgeo.y = cl.geom.y + bw;
        xgeo.width = cl.geom.width - 2 * bw;
        xgeo.height = cl.geom.height - 2 * bw;
        xwayland_logical_to_x11(xgeo, cl.xwayland_scale);
    }
}

export fn fix_xwayland_coordinate(geom: *Box) callconv(.c) void {
    const m = monitorOpt(c.server.selected_monitor) orelse return;
    if (geom.x >= m.m.x and geom.x <= m.m.x + m.m.width and
        geom.y >= m.m.y and geom.y <= m.m.y + m.m.height)
        return;
    geom.x = m.m.x + @divTrunc(m.m.width - geom.width, 2);
    geom.y = m.m.y + @divTrunc(m.m.height - geom.height, 2);
}

export fn handle_xwayland_surface_request_activate(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    if (!build_options.xwayland)
        return;
    const cl = @as(*Client, @ptrFromInt(@intFromPtr(listener) - @offsetOf(Client, "activate")));
    if (cl.iskilling != 0 or cl.mon == null or cl.foreign_toplevel == null or
        client_is_unmanaged(cl) != 0)
        return;
    if (cl.swallowdby != null)
        return;

    var need_arrange = false;
    if (cl.isminimized != 0) {
        client_pending_minimized_state(cl, 0);
        cl.tags = cl.mon.*.tagset[cl.mon.*.seltags];
        cl.is_in_scratchpad = 0;
        cl.isnamedscratchpad = 0;
        client_update_border_color(cl);
        if (VISIBLEON(cl, cl.mon)) 
            need_arrange = true;
    }

    if (c.config.focus_on_activate != 0 and cl.istagsilent == 0 and
        (c.server.selected_monitor == null or cl != c.server.selected_monitor.*.sel))
    {
        if (!(cl.mon == c.server.selected_monitor and
            (cl.tags & cl.mon.*.tagset[cl.mon.*.seltags]) != 0))
        {
            var arg = std.mem.zeroes(Arg);
            arg.ui = cl.tags;
            client_view_on_monitor(&arg, true, cl.mon, true);
        }
        c.wlr_xwayland_surface_activate(cl.surface.xwayland, true);
        client_focus(cl, 1);
        need_arrange = true;
    } else if (cl != client_focus_top(c.server.selected_monitor)) {
        cl.isurgent = 1;
        if (client_surface(cl) != null and client_surface(cl).*.mapped)
            client_update_border_color(cl);
    }

    if (need_arrange)
        arrange(cl.mon, false, false);
    printstatus(@intCast(c.IPC_WATCH_ARRANGGE));
}

export fn handle_xwayland_surface_request_configure(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    if (!build_options.xwayland)
        return;
    const cl = @as(*Client, @ptrFromInt(@intFromPtr(listener) - @offsetOf(Client, "configure")));
    const event = @as(*c.struct_wlr_xwayland_surface_configure_event, @ptrCast(@alignCast(data.?)));
    var new_geo = Box{
        .x = event.x,
        .y = event.y,
        .width = event.width,
        .height = event.height,
    };
    xwayland_x11_to_logical(&new_geo, cl.xwayland_scale);
    fix_xwayland_coordinate(&new_geo);

    if (client_surface(cl) == null or !client_surface(cl).*.mapped) {
        var xgeo = new_geo;
        xwayland_logical_to_x11(&xgeo, cl.xwayland_scale);
        c.wlr_xwayland_surface_configure(cl.surface.xwayland, @intCast(xgeo.x), @intCast(xgeo.y), @intCast(xgeo.width), @intCast(xgeo.height));
        return;
    }
    if (client_is_parked(cl))
        return;

    if (client_is_unmanaged(cl) != 0) {
        var xgeo = new_geo;
        xwayland_logical_to_x11(&xgeo, cl.xwayland_scale);
        if (cl.scene != null)
            c.wlr_scene_node_set_position(&cl.scene.*.node, new_geo.x, new_geo.y);
        c.wlr_xwayland_surface_configure(cl.surface.xwayland, @intCast(xgeo.x), @intCast(xgeo.y), @intCast(xgeo.width), @intCast(xgeo.height));
        return;
    }

    cl.xwl_req_valid = false;
    var opts = std.mem.zeroes(c.ResizeOpts);
    opts.force_configure = true;

    if (cl.isfloating != 0 and (c.server.grab_client == null or @intFromPtr(c.server.grab_client) != @intFromPtr(cl))) {
        const bw: i32 = @intCast(cl.bw);
        new_geo.x -= bw;
        new_geo.y -= bw;
        new_geo.width += bw * 2;
        new_geo.height += bw * 2;
        fix_xwayland_coordinate(&new_geo);
        resize(cl, new_geo, opts);
    } else {
        resize(cl, cl.geom, opts);
        arrange(cl.mon, false, false);
    }
}

export fn handle_new_xwayland_surface(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    if (!build_options.xwayland)
        return;
    const xsurface = @as(*c.struct_wlr_xwayland_surface, @ptrCast(@alignCast(data.?)));
    const raw = c.ecalloc(1, @sizeOf(Client)) orelse return;
    const cl = @as(*Client, @ptrCast(@alignCast(raw)));
    xsurface.data = @ptrCast(cl);
    cl.animation_type_open = c.ANIM_TYPE_UNSET;
    cl.animation_type_close = c.ANIM_TYPE_UNSET;
    cl.surface.xwayland = xsurface;
    cl.type = @intCast(c.X11);

    cl.associate.notify = handle_xwayland_surface_associate;
    c.wl_signal_add(&xsurface.events.associate, &cl.associate);
    cl.destroy.notify = handle_client_destroy;
    c.wl_signal_add(&xsurface.events.destroy, &cl.destroy);
    cl.dissociate.notify = handle_xwayland_surface_dissociate;
    c.wl_signal_add(&xsurface.events.dissociate, &cl.dissociate);
    cl.activate.notify = handle_xwayland_surface_request_activate;
    c.wl_signal_add(&xsurface.events.request_activate, &cl.activate);
    cl.configure.notify = handle_xwayland_surface_request_configure;
    c.wl_signal_add(&xsurface.events.request_configure, &cl.configure);
    cl.fullscreen.notify = handle_client_request_fullscreen;
    c.wl_signal_add(&xsurface.events.request_fullscreen, &cl.fullscreen);
    cl.set_hints.notify = handle_xwayland_surface_set_hints;
    c.wl_signal_add(&xsurface.events.set_hints, &cl.set_hints);
    cl.set_title.notify = handle_client_set_title;
    c.wl_signal_add(&xsurface.events.set_title, &cl.set_title);
    cl.maximize.notify = handle_client_request_maximize;
    c.wl_signal_add(&xsurface.events.request_maximize, &cl.maximize);
    cl.minimize.notify = handle_client_request_minimize;
    c.wl_signal_add(&xsurface.events.request_minimize, &cl.minimize);
}

export fn handle_xwayland_surface_commit(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    if (!build_options.xwayland)
        return;
    const cl = @as(*Client, @ptrFromInt(@intFromPtr(listener) - @offsetOf(Client, "commmitx11")));
    const state = &cl.surface.xwayland.*.surface.*.current;
    var xgeo: Box = undefined;
    client_get_x11_geometry(cl, &xgeo);
    if (xgeo.width == @as(i32, @intCast(state.width)) and
        xgeo.height == @as(i32, @intCast(state.height)) and
        cl.surface.xwayland.*.x == xgeo.x and cl.surface.xwayland.*.y == xgeo.y)
        cl.configure_serial = 0;
    client_update_xwayland_dest_size(cl);
}

export fn handle_xwayland_surface_associate(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    if (!build_options.xwayland)
        return;
    const cl = @as(*Client, @ptrFromInt(@intFromPtr(listener) - @offsetOf(Client, "associate")));
    const s = client_surface(cl);
    if (s == null)
        return;
    cl.map.notify = handle_client_map;
    c.wl_signal_add(&s.*.events.map, &cl.map);
    cl.unmap.notify = handle_client_unmap;
    c.wl_signal_add(&s.*.events.unmap, &cl.unmap);
}

export fn handle_xwayland_surface_dissociate(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    if (!build_options.xwayland)
        return;
    const cl = @as(*Client, @ptrFromInt(@intFromPtr(listener) - @offsetOf(Client, "dissociate")));
    c.wl_list_remove(&cl.map.link);
    c.wl_list_remove(&cl.unmap.link);
    cl.xwl_root_buffer = null;
    cl.xwl_clip_active = false;
}

export fn handle_xwayland_surface_set_hints(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    if (!build_options.xwayland)
        return;
    const cl = @as(*Client, @ptrFromInt(@intFromPtr(listener) - @offsetOf(Client, "set_hints")));
    if (cl == client_focus_top(c.server.selected_monitor) or cl.surface.xwayland == null or
        cl.surface.xwayland.*.hints == null)
        return;
    cl.isurgent = @intCast(c.xcb_icccm_wm_hints_get_urgency(cl.surface.xwayland.*.hints));
    printstatus(@intCast(c.IPC_WATCH_ARRANGGE));
    const s = client_surface(cl);
    if (cl.isurgent != 0 and s != null and s.*.mapped)
        client_update_border_color(cl);
}

export fn handle_xwayland_ready(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    _ = data;
    if (!build_options.xwayland)
        return;
    c.wlr_xwayland_set_seat(c.server.xwayland, c.server.seat);
    xwayland_primary_init();

    var cursor_scale: f32 = 1.0;
    if (c.server.selected_monitor != null and c.server.selected_monitor.*.wlr_output != null and
        c.server.selected_monitor.*.wlr_output.*.scale > 0)
        cursor_scale = c.server.selected_monitor.*.wlr_output.*.scale;

    const xcursor = c.wlr_xcursor_manager_get_xcursor(c.server.cursor_manager, "default", cursor_scale);
    if (xcursor != null and xcursor.*.images != null and xcursor.*.images[0] != null) {
        const image = xcursor.*.images[0];
        const buffer = c.wlr_xcursor_image_get_buffer(image);
        c.wlr_xwayland_set_cursor(c.server.xwayland, buffer, @intCast(image.*.hotspot_x), @intCast(image.*.hotspot_y));
    }

    _ = c.wl_event_source_timer_update(c.server.sync_keymap, 500);
}

export fn handle_xwayland_surface_set_geometry(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    if (!build_options.xwayland)
        return;
    const cl = @as(*Client, @ptrFromInt(@intFromPtr(listener) - @offsetOf(Client, "set_geometry")));
    var geo = Box{
        .x = cl.surface.xwayland.*.x,
        .y = cl.surface.xwayland.*.y,
        .width = cl.surface.xwayland.*.width,
        .height = cl.surface.xwayland.*.height,
    };
    xwayland_x11_to_logical(&geo, cl.xwayland_scale);
    if (cl.scene != null)
        c.wlr_scene_node_set_position(&cl.scene.*.node, geo.x, geo.y);
    pointer_process_motion(0, null, 0, 0, 0, 0);
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/client_xwayland_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_set_scale_calls: c_int;
extern var stub_set_scale_value: f32;
extern var stub_is_x11: c_int;
extern var stub_is_unmanaged: c_int;
extern var stub_is_parked: c_int;
extern var stub_client_surface: [*c]c.struct_wlr_surface;
extern var stub_surface: c.struct_wlr_surface;
extern var stub_update_dest_calls: c_int;
extern var stub_focus_calls: c_int;
extern var stub_focus_top_client: [*c]Client;
extern var stub_view_calls: c_int;
extern var stub_view_tags: u32;
extern var stub_border_calls: c_int;
extern var stub_pending_min_calls: c_int;
extern var stub_pending_min_value: i32;
extern var stub_resize_calls: c_int;
extern var stub_resize_geo: Box;
extern var stub_resize_force: i32;
extern var stub_arrange_calls: c_int;
extern var stub_motion_calls: c_int;
extern var stub_printstatus_calls: c_int;
extern var stub_primary_init_calls: c_int;
extern var stub_activate_calls: c_int;
extern var stub_configure_calls: c_int;
extern var stub_conf_x: i32;
extern var stub_conf_y: i32;
extern var stub_conf_w: i32;
extern var stub_conf_h: i32;
extern var stub_list_remove_calls: c_int;
extern var stub_set_position_calls: c_int;
extern var stub_pos_x: i32;
extern var stub_pos_y: i32;
extern var stub_urgency: c_int;
extern var stub_seat_calls: c_int;
extern var stub_cursor_calls: c_int;
extern var stub_cursor_hotspot_x: i32;
extern var stub_cursor_hotspot_y: i32;
extern var stub_timer_calls: c_int;
extern var stub_timer_ms: i32;
extern var stub_cursor_scale: f32;
extern var stub_transformed_w: i32;
extern var stub_transformed_h: i32;
extern var stub_xcursor: c.struct_wlr_xcursor;

fn listInit(head: *c.struct_wl_list) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

fn listIsEmpty(head: *c.struct_wl_list) bool {
    return head.next == @as([*c]c.struct_wl_list, @ptrCast(head));
}

fn mkBox(x: i32, y: i32, w: i32, h: i32) Box {
    return .{ .x = x, .y = y, .width = w, .height = h };
}

fn resetXwWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    stub_set_scale_calls = 0;
    stub_set_scale_value = 0;
    stub_is_x11 = 0;
    stub_is_unmanaged = 0;
    stub_is_parked = 0;
    stub_surface = std.mem.zeroes(c.struct_wlr_surface);
    stub_client_surface = &stub_surface;
    stub_update_dest_calls = 0;
    stub_focus_calls = 0;
    stub_focus_top_client = null;
    stub_view_calls = 0;
    stub_view_tags = 0;
    stub_border_calls = 0;
    stub_pending_min_calls = 0;
    stub_pending_min_value = -1;
    stub_resize_calls = 0;
    stub_resize_geo = std.mem.zeroes(Box);
    stub_resize_force = -1;
    stub_arrange_calls = 0;
    stub_motion_calls = 0;
    stub_printstatus_calls = 0;
    stub_primary_init_calls = 0;
    stub_activate_calls = 0;
    stub_configure_calls = 0;
    stub_conf_x = 0;
    stub_conf_y = 0;
    stub_conf_w = 0;
    stub_conf_h = 0;
    stub_list_remove_calls = 0;
    stub_set_position_calls = 0;
    stub_pos_x = 0;
    stub_pos_y = 0;
    stub_urgency = 0;
    stub_seat_calls = 0;
    stub_cursor_calls = 0;
    stub_cursor_hotspot_x = 0;
    stub_cursor_hotspot_y = 0;
    stub_timer_calls = 0;
    stub_timer_ms = 0;
    stub_cursor_scale = 0;
    stub_transformed_w = 0;
    stub_transformed_h = 0;
}

test "scales and monitor fallback" {
    resetXwWorld();
    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    out.scale = 2.0;
    var m: Monitor = std.mem.zeroes(Monitor);
    m.wlr_output = &out;
    var cl: Client = std.mem.zeroes(Client);
    cl.mon = &m;

    c.config.xwayland_ignore_scale = 0;
    try testing.expectApproxEqAbs(@as(f32, 1), xwayland_client_scale(&cl), 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 2), xwayland_preferred_scale(&cl), 1e-6);
    c.server.selected_monitor = &m;
    try testing.expect(xwayland_monitor(null) == &m);
    try testing.expect(xwayland_monitor(&cl) == &m);

    c.config.xwayland_ignore_scale = 1;
    try testing.expectApproxEqAbs(@as(f32, 2), xwayland_client_scale(&cl), 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 1), xwayland_preferred_scale(&cl), 1e-6);

    stub_is_x11 = 1;
    stub_client_surface = &stub_surface;
    xwayland_apply_scale(&cl);
    try testing.expectApproxEqAbs(@as(f32, 2), cl.xwayland_scale, 1e-6);
    try testing.expectEqual(@as(c_int, 1), stub_set_scale_calls);
    try testing.expectApproxEqAbs(@as(f32, 1), stub_set_scale_value, 1e-6);

    cl.mon = null;
    xwayland_apply_scale(&cl);
    try testing.expectApproxEqAbs(@as(f32, 2), cl.xwayland_scale, 1e-6);

    c.config.xwayland_ignore_scale = 0;
    xwayland_apply_scale(&cl);
    try testing.expectApproxEqAbs(@as(f32, 1), cl.xwayland_scale, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 2), stub_set_scale_value, 1e-6);
}

test "logical and x11 conversions round trip" {
    resetXwWorld();
    c.server.scene_geometry = mkBox(100, -50, 1920, 1080);
    var box = mkBox(110, -40, 300, 200);
    xwayland_logical_to_x11(&box, 2.0);
    try testing.expectEqual(@as(i32, 20), box.x);
    try testing.expectEqual(@as(i32, 20), box.y);
    try testing.expectEqual(@as(i32, 600), box.width);
    try testing.expectEqual(@as(i32, 400), box.height);

    xwayland_x11_to_logical(&box, 2.0);
    try testing.expectEqual(@as(i32, 110), box.x);
    try testing.expectEqual(@as(i32, -40), box.y);
    try testing.expectEqual(@as(i32, 300), box.width);
    try testing.expectEqual(@as(i32, 200), box.height);

    box = mkBox(100, -50, 10, 10);
    xwayland_logical_to_x11(&box, 0);
    try testing.expectEqual(@as(i32, 0), box.x);

    var ox: i32 = 0;
    var oy: i32 = 0;
    xwayland_screen_origin(&ox, &oy);
    try testing.expectEqual(@as(i32, 100), ox);
    try testing.expectEqual(@as(i32, -50), oy);
}

test "x11 geometry and coordinate fixing" {
    resetXwWorld();
    var cl: Client = std.mem.zeroes(Client);
    cl.geom = mkBox(100, 100, 300, 200);
    cl.bw = 2;
    cl.xwayland_scale = 1;
    var xgeo: Box = undefined;
    client_get_x11_geometry(&cl, &xgeo);
    try testing.expectEqual(@as(i32, 102), xgeo.x);
    try testing.expectEqual(@as(i32, 102), xgeo.y);
    try testing.expectEqual(@as(i32, 296), xgeo.width);
    try testing.expectEqual(@as(i32, 196), xgeo.height);

    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    var m: Monitor = std.mem.zeroes(Monitor);
    m.wlr_output = &out;
    m.m = mkBox(0, 0, 1000, 800);
    c.server.selected_monitor = &m;
    c.config.xwayland_ignore_scale = 1;
    cl.mon = &m;
    cl.isfullscreen = 1;
    cl.xwayland_scale = 2;
    stub_transformed_w = 1920;
    stub_transformed_h = 1080;
    client_get_x11_geometry(&cl, &xgeo);
    try testing.expectEqual(@as(i32, 0), xgeo.x);
    try testing.expectEqual(@as(i32, 1920), xgeo.width);
    try testing.expectEqual(@as(i32, 1080), xgeo.height);

    var geom = mkBox(2000, 2000, 600, 500);
    fix_xwayland_coordinate(&geom);
    try testing.expectEqual(@as(i32, 200), geom.x);
    try testing.expectEqual(@as(i32, 150), geom.y);
    geom = mkBox(10, 10, 600, 500);
    fix_xwayland_coordinate(&geom);
    try testing.expectEqual(@as(i32, 10), geom.x);
    try testing.expectEqual(@as(i32, 10), geom.y);
}

test "configure handler echoes and routes by role" {
    resetXwWorld();
    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    var m: Monitor = std.mem.zeroes(Monitor);
    m.wlr_output = &out;
    m.m = mkBox(0, 0, 1000, 800);
    c.server.selected_monitor = &m;
    var cl: Client = std.mem.zeroes(Client);
    cl.mon = &m;
    cl.xwayland_scale = 1;
    var event = std.mem.zeroes(c.struct_wlr_xwayland_surface_configure_event);
    event.x = 10;
    event.y = 20;
    event.width = 300;
    event.height = 200;

    stub_client_surface = null;
    handle_xwayland_surface_request_configure(&cl.configure, &event);
    try testing.expectEqual(@as(i32, 10), stub_conf_x);
    try testing.expectEqual(@as(i32, 20), stub_conf_y);
    try testing.expectEqual(@as(i32, 300), stub_conf_w);
    try testing.expectEqual(@as(i32, 200), stub_conf_h);
    try testing.expectEqual(@as(c_int, 0), stub_resize_calls);

    stub_client_surface = &stub_surface;
    stub_surface.mapped = true;
    stub_is_unmanaged = 1;
    var um_tree: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    cl.scene = &um_tree;
    event.x = 50;
    event.y = 60;
    event.width = 200;
    event.height = 100;
    handle_xwayland_surface_request_configure(&cl.configure, &event);
    try testing.expectEqual(@as(c_int, 1), stub_set_position_calls);
    try testing.expectEqual(@as(i32, 50), stub_pos_x);
    try testing.expectEqual(@as(i32, 50), stub_conf_x);
    try testing.expectEqual(@as(i32, 60), stub_conf_y);

    stub_is_unmanaged = 0;
    cl.scene = null;
    cl.isfloating = 1;
    cl.bw = 2;
    event.x = 100;
    event.y = 100;
    event.width = 300;
    event.height = 200;
    handle_xwayland_surface_request_configure(&cl.configure, &event);
    try testing.expectEqual(@as(c_int, 1), stub_resize_calls);
    try testing.expectEqual(@as(i32, 98), stub_resize_geo.x);
    try testing.expectEqual(@as(i32, 304), stub_resize_geo.width);
    try testing.expectEqual(@as(i32, 1), stub_resize_force);

    cl.isfloating = 0;
    cl.geom = mkBox(10, 10, 500, 400);
    handle_xwayland_surface_request_configure(&cl.configure, &event);
    try testing.expectEqual(@as(c_int, 2), stub_resize_calls);
    try testing.expectEqual(@as(i32, 500), stub_resize_geo.width);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);

    stub_is_parked = 1;
    const resizes = stub_resize_calls;
    handle_xwayland_surface_request_configure(&cl.configure, &event);
    try testing.expectEqual(resizes, stub_resize_calls);
}

test "activate restores minimized clients and marks urgency" {
    resetXwWorld();
    c.config.focus_on_activate = 1;
    var m: Monitor = std.mem.zeroes(Monitor);
    m.tagset[0] = 1;
    var cl: Client = std.mem.zeroes(Client);
    cl.mon = &m;
    cl.tags = 0;
    cl.isminimized = 1;
    cl.foreign_toplevel = @ptrFromInt(0x1000);
    stub_surface.mapped = true;
    handle_xwayland_surface_request_activate(&cl.activate, null);
    try testing.expectEqual(@as(c_int, 1), stub_pending_min_calls);
    try testing.expectEqual(@as(i32, 0), stub_pending_min_value);
    try testing.expectEqual(@as(u32, 1), cl.tags);
    try testing.expectEqual(@as(c_int, 0), cl.is_in_scratchpad);
    try testing.expectEqual(@as(c_int, 1), stub_border_calls);
    try testing.expectEqual(@as(c_int, 1), stub_view_calls);
    try testing.expectEqual(@as(u32, 1), stub_view_tags);
    try testing.expectEqual(@as(c_int, 1), stub_activate_calls);
    try testing.expectEqual(@as(c_int, 1), stub_focus_calls);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);
    try testing.expectEqual(@as(c_int, 1), stub_printstatus_calls);

    cl.swallowdby = @ptrFromInt(0x2000);
    handle_xwayland_surface_request_activate(&cl.activate, null);
    try testing.expectEqual(@as(c_int, 1), stub_focus_calls);
    cl.swallowdby = null;

    c.config.focus_on_activate = 0;
    cl.isminimized = 0;
    cl.isurgent = 0;
    handle_xwayland_surface_request_activate(&cl.activate, null);
    try testing.expectEqual(@as(i32, 1), cl.isurgent);
    try testing.expectEqual(@as(c_int, 2), stub_border_calls);
    try testing.expectEqual(@as(c_int, 2), stub_printstatus_calls);
}

test "set hints updates urgency" {
    resetXwWorld();
    var m: Monitor = std.mem.zeroes(Monitor);
    var cl: Client = std.mem.zeroes(Client);
    cl.mon = &m;
    var xsurface: c.struct_wlr_xwayland_surface = std.mem.zeroes(c.struct_wlr_xwayland_surface);
    var hints: c.xcb_icccm_wm_hints_t = std.mem.zeroes(c.xcb_icccm_wm_hints_t);
    xsurface.hints = &hints;
    cl.surface.xwayland = &xsurface;
    stub_surface.mapped = true;
    stub_urgency = 1;
    handle_xwayland_surface_set_hints(&cl.set_hints, null);
    try testing.expectEqual(@as(i32, 1), cl.isurgent);
    try testing.expectEqual(@as(c_int, 1), stub_border_calls);
    try testing.expectEqual(@as(c_int, 1), stub_printstatus_calls);

    stub_focus_top_client = &cl;
    cl.isurgent = 0;
    handle_xwayland_surface_set_hints(&cl.set_hints, null);
    try testing.expectEqual(@as(i32, 0), cl.isurgent);
}

test "new x11 surface allocates client and registers listeners" {
    resetXwWorld();
    var xsurface: c.struct_wlr_xwayland_surface = std.mem.zeroes(c.struct_wlr_xwayland_surface);
    listInit(&xsurface.events.associate.listener_list);
    listInit(&xsurface.events.destroy.listener_list);
    listInit(&xsurface.events.dissociate.listener_list);
    listInit(&xsurface.events.request_activate.listener_list);
    listInit(&xsurface.events.request_configure.listener_list);
    listInit(&xsurface.events.request_fullscreen.listener_list);
    listInit(&xsurface.events.set_hints.listener_list);
    listInit(&xsurface.events.set_title.listener_list);
    listInit(&xsurface.events.request_maximize.listener_list);
    listInit(&xsurface.events.request_minimize.listener_list);
    handle_new_xwayland_surface(null, &xsurface);
    try testing.expect(xsurface.data != null);
    const cl = @as(*Client, @ptrCast(@alignCast(xsurface.data)));
    try testing.expectEqual(@as(u32, @intCast(c.X11)), cl.type);
    try testing.expect(cl.surface.xwayland == &xsurface);
    try testing.expect(!listIsEmpty(&xsurface.events.associate.listener_list));
    try testing.expect(!listIsEmpty(&xsurface.events.request_configure.listener_list));
    try testing.expectEqual(@as(i32, @intCast(c.ANIM_TYPE_UNSET)), cl.animation_type_open);
    try testing.expect(cl.activate.notify != null);
    try testing.expect(cl.configure.notify != null);
    try testing.expect(cl.set_hints.notify != null);
    std.c.free(cl);
}

test "associate and dissociate manage surface listeners" {
    resetXwWorld();
    var cl: Client = std.mem.zeroes(Client);
    stub_client_surface = &stub_surface;
    listInit(&stub_surface.events.map.listener_list);
    listInit(&stub_surface.events.unmap.listener_list);
    handle_xwayland_surface_associate(&cl.associate, null);
    try testing.expect(!listIsEmpty(&stub_surface.events.map.listener_list));
    try testing.expect(!listIsEmpty(&stub_surface.events.unmap.listener_list));
    try testing.expect(cl.map.notify != null);
    try testing.expect(cl.unmap.notify != null);

    cl.xwl_root_buffer = @ptrFromInt(0x1000);
    cl.xwl_clip_active = true;
    handle_xwayland_surface_dissociate(&cl.dissociate, null);
    try testing.expectEqual(@as(c_int, 2), stub_list_remove_calls);
    try testing.expect(cl.xwl_root_buffer == null);
    try testing.expect(!cl.xwl_clip_active);
}

test "commit clears serial for matching geometry" {
    resetXwWorld();
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    surface.current.width = 296;
    surface.current.height = 196;
    var xsurface: c.struct_wlr_xwayland_surface = std.mem.zeroes(c.struct_wlr_xwayland_surface);
    xsurface.surface = &surface;
    xsurface.x = 102;
    xsurface.y = 102;
    var cl: Client = std.mem.zeroes(Client);
    cl.surface.xwayland = &xsurface;
    cl.geom = mkBox(100, 100, 300, 200);
    cl.bw = 2;
    cl.xwayland_scale = 1;
    cl.configure_serial = 55;
    handle_xwayland_surface_commit(&cl.commmitx11, null);
    try testing.expectEqual(@as(u32, 0), cl.configure_serial);
    try testing.expectEqual(@as(c_int, 1), stub_update_dest_calls);

    cl.configure_serial = 77;
    surface.current.width = 300;
    handle_xwayland_surface_commit(&cl.commmitx11, null);
    try testing.expectEqual(@as(u32, 77), cl.configure_serial);
    try testing.expectEqual(@as(c_int, 2), stub_update_dest_calls);
}

test "ready wires seat, cursor and keymap timer" {
    resetXwWorld();
    c.server.xwayland = @ptrFromInt(0x1000);
    c.server.seat = @ptrFromInt(0x2000);
    c.server.cursor_manager = @ptrFromInt(0x3000);
    c.server.sync_keymap = @ptrFromInt(0x4000);
    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    out.scale = 2.0;
    var m: Monitor = std.mem.zeroes(Monitor);
    m.wlr_output = &out;
    c.server.selected_monitor = &m;
    var image: c.struct_wlr_xcursor_image = std.mem.zeroes(c.struct_wlr_xcursor_image);
    image.hotspot_x = 5;
    image.hotspot_y = 7;
    var image_ptr: [*c]c.struct_wlr_xcursor_image = &image;
    const images: [*c][*c]c.struct_wlr_xcursor_image = &image_ptr;
    var xcursor: c.struct_wlr_xcursor = std.mem.zeroes(c.struct_wlr_xcursor);
    xcursor.images = images;
    stub_xcursor = xcursor;

    handle_xwayland_ready(null, null);
    try testing.expectEqual(@as(c_int, 1), stub_seat_calls);
    try testing.expectEqual(@as(c_int, 1), stub_primary_init_calls);
    try testing.expectApproxEqAbs(@as(f32, 2), stub_cursor_scale, 1e-6);
    try testing.expectEqual(@as(c_int, 1), stub_cursor_calls);
    try testing.expectEqual(@as(i32, 5), stub_cursor_hotspot_x);
    try testing.expectEqual(@as(i32, 7), stub_cursor_hotspot_y);
    try testing.expectEqual(@as(c_int, 1), stub_timer_calls);
    try testing.expectEqual(@as(i32, 500), stub_timer_ms);
}

test "surface geometry repositions the scene node" {
    resetXwWorld();
    var xsurface: c.struct_wlr_xwayland_surface = std.mem.zeroes(c.struct_wlr_xwayland_surface);
    xsurface.x = 20;
    xsurface.y = 30;
    var cl: Client = std.mem.zeroes(Client);
    cl.surface.xwayland = &xsurface;
    cl.xwayland_scale = 1;
    var tree: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    cl.scene = &tree;
    handle_xwayland_surface_set_geometry(&cl.set_geometry, null);
    try testing.expectEqual(@as(c_int, 1), stub_set_position_calls);
    try testing.expectEqual(@as(i32, 20), stub_pos_x);
    try testing.expectEqual(@as(i32, 30), stub_pos_y);
    try testing.expectEqual(@as(c_int, 1), stub_motion_calls);
}
