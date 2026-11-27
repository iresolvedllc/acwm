//! Port of the size/state/XWayland clipping helpers in src/manage/client.c
//! (Phase 5, client slice 2, slice 59).

const std = @import("std");
const c = @import("cc");
const build_options = @import("build_options");

const Client = c.Client;
const Monitor = c.Monitor;
const Box = c.struct_wlr_box;
const FBox = c.struct_wlr_fbox;

extern fn client_get_x11_geometry(cl: [*c]Client, xgeo: *Box) callconv(.c) void;
extern fn get_client_tag_idx(cl: ?*const Client) callconv(.c) u32;
extern fn is_monocle_layout(m: *Monitor) callconv(.c) bool;

fn isX11(cl: *Client) bool {
    return build_options.xwayland and cl.type == c.X11;
}

fn tbl(cl: *Client) [*c]c.struct_wlr_xdg_toplevel {
    if (cl.surface.xdg == null)
        return null;
    return cl.surface.xdg.*.unnamed_0.toplevel;
}

fn roundI32(x: f32) i32 {
    return @intFromFloat(@round(x));
}

fn xwaylandDeviceLength(length: i32, offset: i32, scale: f32) i32 {
    return roundI32(@as(f32, @floatFromInt(offset + length)) * scale) -
        roundI32(@as(f32, @floatFromInt(offset)) * scale);
}

fn xwaylandDeviceSourceBox(cl: *Client, win_x: i32, win_y: i32, dest_x: i32, dest_y: i32, dest_w: i32, dest_h: i32, src: *FBox) void {
    const scale: f32 = if (cl.xwayland_scale > 0) cl.xwayland_scale else 1.0;
    const mon_x: i32 = if (cl.mon != null) cl.mon.*.m.x else 0;
    const mon_y: i32 = if (cl.mon != null) cl.mon.*.m.y else 0;

    src.x = @floatFromInt(roundI32(@as(f32, @floatFromInt(dest_x - mon_x)) * scale) -
        roundI32(@as(f32, @floatFromInt(win_x - mon_x)) * scale));
    src.y = @floatFromInt(roundI32(@as(f32, @floatFromInt(dest_y - mon_y)) * scale) -
        roundI32(@as(f32, @floatFromInt(win_y - mon_y)) * scale));
    src.width = @floatFromInt(xwaylandDeviceLength(dest_w, dest_x - mon_x, scale));
    src.height = @floatFromInt(xwaylandDeviceLength(dest_h, dest_y - mon_y, scale));
}

export fn client_update_xwayland_clip(cl: *Client, clip: *Box) callconv(.c) void {
    if (!build_options.xwayland)
        return;
    if (cl.xwl_root_buffer == null or cl.xwl_root_buffer.*.buffer == null)
        return;
    const buf = cl.xwl_root_buffer.*.buffer;
    const scale: f32 = if (cl.xwayland_scale > 0) cl.xwayland_scale else 1.0;

    cl.xwl_clip = clip.*;
    cl.xwl_clip_active = true;

    if (clip.width <= 0 or clip.height <= 0)
        return;

    const bw: i32 = @intCast(cl.bw);
    const win_x = cl.geom.x + bw;
    const win_y = cl.geom.y + bw;
    const inner_w = cl.geom.width - 2 * bw;
    const inner_h = cl.geom.height - 2 * bw;

    var src: FBox = std.mem.zeroes(FBox);
    var nearest = false;
    var device_aligned = clip.x == 0 and clip.y == 0 and
        clip.width == inner_w and clip.height == inner_h;
    if (device_aligned) {
        var dev: FBox = std.mem.zeroes(FBox);
        xwaylandDeviceSourceBox(cl, win_x, win_y, win_x, win_y, inner_w, inner_h, &dev);
        const buf_w: f32 = @floatFromInt(buf.*.width);
        const buf_h: f32 = @floatFromInt(buf.*.height);
        const overhang = dev.width > buf_w or dev.height > buf_h;
        if (dev.width <= 0 or dev.height <= 0 or
            (overhang and (dev.width - buf_w > 2 or dev.height - buf_h > 2)))
        {
            device_aligned = false;
        } else {
            nearest = overhang;
            src = .{
                .x = dev.x,
                .y = dev.y,
                .width = @min(dev.width, buf_w - dev.x),
                .height = @min(dev.height, buf_h - dev.y),
            };
        }
    }

    if (!device_aligned) {
        src = .{
            .x = @as(f32, @floatFromInt(clip.x)) * scale,
            .y = @as(f32, @floatFromInt(clip.y)) * scale,
            .width = @as(f32, @floatFromInt(clip.width)) * scale,
            .height = @as(f32, @floatFromInt(clip.height)) * scale,
        };
        const zoom_like = clip.x == 0 and clip.y == 0 and
            clip.width < inner_w and clip.height < inner_h;
        if (zoom_like) {
            src.x = 0;
            src.y = 0;
            src.width = @floatFromInt(buf.*.width);
            src.height = @floatFromInt(buf.*.height);
        }
        if (src.x < 0) src.x = 0;
        if (src.y < 0) src.y = 0;
        if (src.x + src.width > @as(f32, @floatFromInt(buf.*.width)))
            src.width = @as(f32, @floatFromInt(buf.*.width)) - src.x;
        if (src.y + src.height > @as(f32, @floatFromInt(buf.*.height)))
            src.height = @as(f32, @floatFromInt(buf.*.height)) - src.y;
        if (src.width < 0) src.width = 0;
        if (src.height < 0) src.height = 0;
    }

    c.wlr_scene_buffer_set_source_box(cl.xwl_root_buffer, &src);
    c.wlr_scene_buffer_set_filter_mode(cl.xwl_root_buffer, @intCast(if (nearest) c.WLR_SCALE_FILTER_NEAREST else c.WLR_SCALE_FILTER_BILINEAR));
    c.wlr_scene_buffer_set_dest_size(cl.xwl_root_buffer, clip.width, clip.height);
    c.wlr_scene_node_set_position(&cl.xwl_root_buffer.*.node, clip.x, clip.y);
}

export fn client_update_xwayland_dest_size(cl: *Client) callconv(.c) void {
    if (!build_options.xwayland)
        return;
    if (cl.xwl_root_buffer == null or cl.xwl_root_buffer.*.buffer == null)
        return;
    if (cl.xwl_clip_active) {
        client_update_xwayland_clip(cl, &cl.xwl_clip);
        return;
    }
    const buf = cl.xwl_root_buffer.*.buffer;
    const scale: f32 = if (cl.xwayland_scale > 0) cl.xwayland_scale else 1.0;
    var w: i32 = 0;
    var h: i32 = 0;
    if (c.client_is_unmanaged(cl) != 0) {
        w = roundI32(@as(f32, @floatFromInt(buf.*.width)) / scale);
        h = roundI32(@as(f32, @floatFromInt(buf.*.height)) / scale);
    } else {
        const cur = cl.animation.current;
        const bw: i32 = @intCast(cl.bw);
        w = cur.width - 2 * bw;
        h = cur.height - 2 * bw;
    }
    if (w > 0 and h > 0) {
        c.wlr_scene_buffer_set_dest_size(cl.xwl_root_buffer, w, h);
        const full = FBox{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(buf.*.width),
            .height = @floatFromInt(buf.*.height),
        };
        c.wlr_scene_buffer_set_source_box(cl.xwl_root_buffer, &full);
        c.wlr_scene_node_set_position(&cl.xwl_root_buffer.*.node, 0, 0);
    }
}

export fn client_set_size(cl: *Client, width: u32, height: u32, force_configure: bool) callconv(.c) u32 {
    if (build_options.xwayland and isX11(cl)) {
        var xgeo: Box = undefined;
        client_get_x11_geometry(cl, &xgeo);
        var xw = xgeo.width;
        var xh = xgeo.height;
        const xx = xgeo.x;
        const xy = xgeo.y;

        const size_hints = cl.surface.xwayland.*.size_hints;
        var w = xw;
        var h = xh;
        if (size_hints != null and xw < @as(i32, @intCast(size_hints.*.min_width)))
            w = @intCast(size_hints.*.min_width);
        if (size_hints != null and xh < @as(i32, @intCast(size_hints.*.min_height)))
            h = @intCast(size_hints.*.min_height);
        _ = &xw;
        _ = &xh;

        if (!force_configure and cl.xwl_req_valid and cl.xwl_req_x == xx and
            cl.xwl_req_y == xy and cl.xwl_req_w == w and cl.xwl_req_h == h)
            return 0;

        cl.xwl_req_valid = true;
        cl.xwl_req_x = xx;
        cl.xwl_req_y = xy;
        cl.xwl_req_w = w;
        cl.xwl_req_h = h;
        c.wlr_xwayland_surface_configure(cl.surface.xwayland, @intCast(xx), @intCast(xy), @intCast(w), @intCast(h));
        return 1;
    }
    const toplevel = tbl(cl) orelse return 0;
    if (@as(i32, @intCast(width)) == toplevel.*.current.width and
        @as(i32, @intCast(height)) == toplevel.*.current.height)
        return 0;
    return c.wlr_xdg_toplevel_set_size(toplevel, @intCast(width), @intCast(height));
}

export fn client_set_minimized(cl: *Client, minimize_window: bool) callconv(.c) void {
    if (build_options.xwayland and isX11(cl)) {
        c.wlr_xwayland_surface_set_minimized(cl.surface.xwayland, minimize_window);
        return;
    }
}

export fn client_set_maximized(cl: *Client, maximized: bool) callconv(.c) void {
    if (build_options.xwayland and isX11(cl)) {
        c.wlr_xwayland_surface_set_maximized(cl.surface.xwayland, maximized, maximized);
        return;
    }
    if (tbl(cl)) |toplevel|
        _ = c.wlr_xdg_toplevel_set_maximized(toplevel, maximized);
}

export fn client_set_tiled(cl: *Client, edges: u32) callconv(.c) void {
    if (build_options.xwayland and isX11(cl) and cl.force_fakemaximize != 0) {
        const on = edges != @as(u32, @intCast(c.WLR_EDGE_NONE));
        c.wlr_xwayland_surface_set_maximized(cl.surface.xwayland, on, on);
        return;
    }
    const toplevel = tbl(cl) orelse return;
    if (toplevel.*.resource != null and
        c.wl_resource_get_version(toplevel.*.resource) >= c.XDG_TOPLEVEL_STATE_TILED_RIGHT_SINCE_VERSION)
        _ = c.wlr_xdg_toplevel_set_tiled(toplevel, edges);
    if (cl.force_fakemaximize != 0)
        _ = c.wlr_xdg_toplevel_set_maximized(toplevel, edges != @as(u32, @intCast(c.WLR_EDGE_NONE)));
}

export fn client_sync_tiled_hint(cl: ?*Client) callconv(.c) void {
    const client = cl orelse return;
    if (client.isfloating == 0 or client.force_tiled_state != 0) {
        client_set_tiled(client, @intCast(c.WLR_EDGE_TOP | c.WLR_EDGE_BOTTOM | c.WLR_EDGE_LEFT | c.WLR_EDGE_RIGHT));
    } else {
        client_set_tiled(client, @intCast(c.WLR_EDGE_NONE));
    }
}

export fn client_should_ignore_focus(cl: *Client) callconv(.c) i32 {
    if (build_options.xwayland and isX11(cl)) {
        const surface = cl.surface.xwayland;
        if (surface == null or surface.*.hints == null)
            return 0;
        return if (surface.*.hints.*.input == 0) 1 else 0;
    }
    return 0;
}

export fn client_is_x11_popup(cl: *Client) callconv(.c) i32 {
    if (build_options.xwayland and isX11(cl)) {
        const surface = cl.surface.xwayland;
        if (surface == null)
            return 0;
        const no_focus = [_]c_int{
            c.WLR_XWAYLAND_NET_WM_WINDOW_TYPE_COMBO,
            c.WLR_XWAYLAND_NET_WM_WINDOW_TYPE_DND,
            c.WLR_XWAYLAND_NET_WM_WINDOW_TYPE_DROPDOWN_MENU,
            c.WLR_XWAYLAND_NET_WM_WINDOW_TYPE_MENU,
            c.WLR_XWAYLAND_NET_WM_WINDOW_TYPE_NOTIFICATION,
            c.WLR_XWAYLAND_NET_WM_WINDOW_TYPE_POPUP_MENU,
            c.WLR_XWAYLAND_NET_WM_WINDOW_TYPE_SPLASH,
            c.WLR_XWAYLAND_NET_WM_WINDOW_TYPE_TOOLTIP,
            c.WLR_XWAYLAND_NET_WM_WINDOW_TYPE_UTILITY,
        };
        for (no_focus) |t| {
            if (c.wlr_xwayland_surface_has_window_type(surface, @intCast(t)))
                return 1;
        }
    }
    return 0;
}

export fn client_should_global(cl: *Client) callconv(.c) i32 {
    if (build_options.xwayland and isX11(cl)) {
        const surface = cl.surface.xwayland;
        if (surface != null and surface.*.sticky)
            return 1;
    }
    return 0;
}

export fn client_should_overtop(cl: *Client) callconv(.c) i32 {
    if (build_options.xwayland and isX11(cl)) {
        const surface = cl.surface.xwayland;
        if (surface != null and surface.*.above)
            return 1;
    }
    return 0;
}

export fn client_wants_focus(cl: *Client) callconv(.c) i32 {
    if (build_options.xwayland) {
        if (c.client_is_unmanaged(cl) == 0)
            return 0;
        return if (c.wlr_xwayland_surface_override_redirect_wants_focus(cl.surface.xwayland) and
            c.wlr_xwayland_surface_icccm_input_model(cl.surface.xwayland) != c.WLR_ICCCM_INPUT_MODEL_NONE) 1 else 0;
    }
    return 0;
}

export fn client_wants_fullscreen(cl: *Client) callconv(.c) i32 {
    if (build_options.xwayland and isX11(cl))
        return if (cl.surface.xwayland.*.fullscreen) 1 else 0;
    const toplevel = tbl(cl) orelse return 0;
    return if (toplevel.*.requested.fullscreen) 1 else 0;
}

export fn client_request_minimize(cl: *Client, data: ?*anyopaque) callconv(.c) bool {
    if (build_options.xwayland and isX11(cl)) {
        const event = @as(*c.struct_wlr_xwayland_minimize_event, @ptrCast(@alignCast(data.?)));
        return event.minimize;
    }
    const toplevel = tbl(cl) orelse return false;
    return toplevel.*.requested.minimized;
}

export fn client_request_maximize(cl: *Client, data: ?*anyopaque) callconv(.c) bool {
    _ = data;
    if (build_options.xwayland and isX11(cl)) {
        const surface = cl.surface.xwayland;
        return surface.*.maximized_vert or surface.*.maximized_horz;
    }
    const toplevel = tbl(cl) orelse return false;
    return toplevel.*.requested.maximized;
}

export fn client_set_size_bound(cl: *Client) callconv(.c) void {
    if (build_options.xwayland and isX11(cl)) {
        const surface = cl.surface.xwayland;
        if (surface.*.size_hints == null)
            return;
        const hints = surface.*.size_hints;
        const scale: f32 = if (cl.xwayland_scale > 0) cl.xwayland_scale else 1.0;
        const min_w = roundI32(@as(f32, @floatFromInt(hints.*.min_width)) / scale);
        const min_h = roundI32(@as(f32, @floatFromInt(hints.*.min_height)) / scale);
        const max_w = roundI32(@as(f32, @floatFromInt(hints.*.max_width)) / scale);
        const max_h = roundI32(@as(f32, @floatFromInt(hints.*.max_height)) / scale);
        const bw: i32 = @intCast(cl.bw);

        if (@as(u32, @intCast(cl.geom.width - 2 * bw)) < @as(u32, @intCast(min_w)) and min_w > 0)
            cl.geom.width = min_w + 2 * bw;
        if (@as(u32, @intCast(cl.geom.height - 2 * bw)) < @as(u32, @intCast(min_h)) and min_h > 0)
            cl.geom.height = min_h + 2 * bw;
        if (@as(u32, @intCast(cl.geom.width - 2 * bw)) > @as(u32, @intCast(max_w)) and max_w > 0)
            cl.geom.width = max_w + 2 * bw;
        if (@as(u32, @intCast(cl.geom.height - 2 * bw)) > @as(u32, @intCast(max_h)) and max_h > 0)
            cl.geom.height = max_h + 2 * bw;
        return;
    }

    const toplevel = tbl(cl) orelse return;
    const state = toplevel.*.current;
    const bw: i32 = @intCast(cl.bw);
    if (@as(u32, @intCast(cl.geom.width - 2 * bw)) < state.min_width and state.min_width > 0)
        cl.geom.width = @as(i32, @intCast(state.min_width)) + 2 * bw;
    if (@as(u32, @intCast(cl.geom.height - 2 * bw)) < state.min_height and state.min_height > 0)
        cl.geom.height = @as(i32, @intCast(state.min_height)) + 2 * bw;
    if (@as(u32, @intCast(cl.geom.width - 2 * bw)) > state.max_width and state.max_width > 0)
        cl.geom.width = @as(i32, @intCast(state.max_width)) + 2 * bw;
    if (@as(u32, @intCast(cl.geom.height - 2 * bw)) > state.max_height and state.max_height > 0)
        cl.geom.height = @as(i32, @intCast(state.max_height)) + 2 * bw;
}

fn ISSCROLLTILED(cl: *const Client) bool {
    return cl.isfloating == 0 and cl.isminimized == 0 and cl.iskilling == 0 and cl.isunglobal == 0;
}

fn ISFAKETILED(cl: *const Client) bool {
    return cl.isfloating == 0 and cl.isminimized == 0 and cl.iskilling == 0 and cl.isunglobal == 0;
}

export fn check_hit_no_border(cl: *Client) callconv(.c) bool {
    if (cl.mon == null)
        return false;
    if (cl.tags == 0)
        return false;

    var hit_no_border = false;
    if (!c.server.render_border)
        hit_no_border = true;

    const m = cl.mon;
    if (m.*.pertag != null and m.*.isoverview == 0 and
        m.*.pertag.*.no_render_border[@intCast(get_client_tag_idx(cl))] != 0)
        hit_no_border = true;

    if (c.config.no_border_when_single != 0 and
        ((ISSCROLLTILED(cl) and m.*.visible_fake_tiling_clients == 1) or m.*.visible_clients == 1))
        hit_no_border = true;

    if (c.config.monocle_no_border != 0 and ISFAKETILED(cl) and m.*.isoverview == 0 and
        is_monocle_layout(m))
        hit_no_border = true;

    return hit_no_border;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/client_state_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_x11_geo: Box;
extern var stub_x11_geo_calls: c_int;
extern var stub_tag_idx: u32;
extern var stub_monocle_layout: bool;
extern var stub_source_box_calls: c_int;
extern fn stub_source_x() f64;
extern fn stub_source_y() f64;
extern fn stub_source_width() f64;
extern fn stub_source_height() f64;
extern var stub_filter_calls: c_int;
extern var stub_filter_mode: c_int;
extern var stub_dest_calls: c_int;
extern var stub_dest_w: i32;
extern var stub_dest_h: i32;
extern var stub_node_pos_calls: c_int;
extern var stub_node_pos_x: i32;
extern var stub_node_pos_y: i32;
extern var stub_x11_configure_calls: c_int;
extern var stub_x11_configure_x: i16;
extern var stub_x11_configure_y: i16;
extern var stub_x11_configure_w: u16;
extern var stub_x11_configure_h: u16;
extern var stub_x11_minimize_calls: c_int;
extern var stub_x11_minimize_value: bool;
extern var stub_x11_maximize_calls: c_int;
extern var stub_x11_maximize_vert: bool;
extern var stub_x11_maximize_horz: bool;
extern var stub_xdg_set_size_calls: c_int;
extern var stub_xdg_set_size_w: i32;
extern var stub_xdg_set_size_h: i32;
extern var stub_xdg_set_size_result: u32;
extern var stub_xdg_maximize_calls: c_int;
extern var stub_xdg_maximize_value: bool;
extern var stub_xdg_tiled_calls: c_int;
extern var stub_xdg_tiled_edges: u32;
extern var stub_resource_version: c_int;
extern var stub_or_wants_focus: bool;
extern var stub_input_model: c_int;
extern var stub_window_type: c_int;

fn resetStateWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    c.server.render_border = true;
    stub_x11_geo = std.mem.zeroes(Box);
    stub_x11_geo_calls = 0;
    stub_tag_idx = 0;
    stub_monocle_layout = false;
    stub_source_box_calls = 0;
    stub_filter_calls = 0;
    stub_filter_mode = -1;
    stub_dest_calls = 0;
    stub_dest_w = 0;
    stub_dest_h = 0;
    stub_node_pos_calls = 0;
    stub_node_pos_x = 0;
    stub_node_pos_y = 0;
    stub_x11_configure_calls = 0;
    stub_x11_configure_x = 0;
    stub_x11_configure_y = 0;
    stub_x11_configure_w = 0;
    stub_x11_configure_h = 0;
    stub_x11_minimize_calls = 0;
    stub_x11_minimize_value = true;
    stub_x11_maximize_calls = 0;
    stub_x11_maximize_vert = false;
    stub_x11_maximize_horz = false;
    stub_xdg_set_size_calls = 0;
    stub_xdg_set_size_w = 0;
    stub_xdg_set_size_h = 0;
    stub_xdg_set_size_result = 7;
    stub_xdg_maximize_calls = 0;
    stub_xdg_maximize_value = false;
    stub_xdg_tiled_calls = 0;
    stub_xdg_tiled_edges = 0;
    stub_resource_version = 5;
    stub_or_wants_focus = false;
    stub_input_model = 1;
    stub_window_type = -1;
}

fn xdgClient(cl: *Client, xdg: *c.struct_wlr_xdg_surface, toplevel: *c.struct_wlr_xdg_toplevel) void {
    cl.* = std.mem.zeroes(Client);
    xdg.* = std.mem.zeroes(c.struct_wlr_xdg_surface);
    toplevel.* = std.mem.zeroes(c.struct_wlr_xdg_toplevel);
    cl.type = @intCast(c.XDGShell);
    cl.surface.xdg = xdg;
    xdg.unnamed_0.toplevel = toplevel;
    toplevel.base = xdg;
    toplevel.resource = @ptrFromInt(0x1000);
}

fn x11Client(cl: *Client, xs: *c.struct_wlr_xwayland_surface) void {
    cl.* = std.mem.zeroes(Client);
    xs.* = std.mem.zeroes(c.struct_wlr_xwayland_surface);
    cl.type = @intCast(c.X11);
    cl.surface.xwayland = xs;
}

test "xwayland clip computes device-aligned source boxes" {
    resetStateWorld();
    var cl: Client = std.mem.zeroes(Client);
    var xs: c.struct_wlr_xwayland_surface = std.mem.zeroes(c.struct_wlr_xwayland_surface);
    x11Client(&cl, &xs);
    var sbuf: c.struct_wlr_scene_buffer = std.mem.zeroes(c.struct_wlr_scene_buffer);
    var buf: c.struct_wlr_buffer = std.mem.zeroes(c.struct_wlr_buffer);
    buf.width = 98;
    buf.height = 48;
    sbuf.buffer = &buf;
    cl.xwl_root_buffer = &sbuf;
    cl.geom = .{ .x = 10, .y = 20, .width = 100, .height = 50 };
    cl.bw = 1;
    cl.xwayland_scale = 1.0;

    var clip: Box = .{ .x = 0, .y = 0, .width = 98, .height = 48 };
    client_update_xwayland_clip(&cl, &clip);
    try testing.expectEqual(@as(c_int, 1), stub_source_box_calls);
    try testing.expectApproxEqAbs(@as(f32, 0), stub_source_x(), 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 98), stub_source_width(), 1e-6);
    try testing.expectEqual(@as(c_int, 0), stub_filter_mode);
    try testing.expectEqual(@as(i32, 98), stub_dest_w);
    try testing.expectEqual(@as(i32, 48), stub_dest_h);
    try testing.expect(cl.xwl_clip_active);
    try testing.expectEqual(@as(i32, 98), cl.xwl_clip.width);

    var partial: Box = .{ .x = 10, .y = 5, .width = 40, .height = 20 };
    client_update_xwayland_clip(&cl, &partial);
    try testing.expectApproxEqAbs(@as(f32, 10), stub_source_x(), 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 40), stub_source_width(), 1e-6);
    try testing.expectEqual(@as(i32, 40), stub_dest_w);
    try testing.expectEqual(@as(i32, 10), stub_node_pos_x);

    var negative: Box = .{ .x = -10, .y = -5, .width = 30, .height = 20 };
    client_update_xwayland_clip(&cl, &negative);
    try testing.expectApproxEqAbs(@as(f32, 0), stub_source_x(), 1e-6);
    try testing.expectEqual(@as(i32, -10), stub_node_pos_x);

    const calls = stub_dest_calls;
    sbuf.buffer = null;
    client_update_xwayland_clip(&cl, &partial);
    try testing.expectEqual(calls, stub_dest_calls);
}

test "xwayland dest size restores full sampling or reapplies the clip" {
    resetStateWorld();
    var cl: Client = std.mem.zeroes(Client);
    var xs: c.struct_wlr_xwayland_surface = std.mem.zeroes(c.struct_wlr_xwayland_surface);
    x11Client(&cl, &xs);
    var sbuf: c.struct_wlr_scene_buffer = std.mem.zeroes(c.struct_wlr_scene_buffer);
    var buf: c.struct_wlr_buffer = std.mem.zeroes(c.struct_wlr_buffer);
    buf.width = 196;
    buf.height = 96;
    sbuf.buffer = &buf;
    cl.xwl_root_buffer = &sbuf;
    cl.xwayland_scale = 2.0;
    cl.animation.current = .{ .x = 0, .y = 0, .width = 100, .height = 50 };
    cl.bw = 1;

    xs.override_redirect = true;
    client_update_xwayland_dest_size(&cl);
    try testing.expectEqual(@as(i32, 98), stub_dest_w);
    try testing.expectApproxEqAbs(@as(f32, 196), stub_source_width(), 1e-6);
    try testing.expectEqual(@as(i32, 0), stub_node_pos_x);

    xs.override_redirect = false;
    client_update_xwayland_dest_size(&cl);
    try testing.expectEqual(@as(i32, 98), stub_dest_w);
    try testing.expectEqual(@as(i32, 48), stub_dest_h);

    cl.xwl_clip_active = true;
    cl.xwl_clip = .{ .x = 0, .y = 0, .width = 20, .height = 10 };
    client_update_xwayland_dest_size(&cl);
    try testing.expect(cl.xwl_clip_active);
    const calls = stub_dest_calls;
    sbuf.buffer = null;
    client_update_xwayland_dest_size(&cl);
    try testing.expectEqual(calls, stub_dest_calls);
}

test "xdg set size skips identical current sizes" {
    resetStateWorld();
    var cl: Client = std.mem.zeroes(Client);
    var xdg: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    var toplevel: c.struct_wlr_xdg_toplevel = std.mem.zeroes(c.struct_wlr_xdg_toplevel);
    xdgClient(&cl, &xdg, &toplevel);
    toplevel.current.width = 100;
    toplevel.current.height = 50;

    try testing.expectEqual(@as(u32, 0), client_set_size(&cl, 100, 50, false));
    try testing.expectEqual(@as(c_int, 0), stub_xdg_set_size_calls);
    try testing.expectEqual(@as(u32, 7), client_set_size(&cl, 80, 40, false));
    try testing.expectEqual(@as(c_int, 1), stub_xdg_set_size_calls);
    try testing.expectEqual(@as(i32, 80), stub_xdg_set_size_w);
    try testing.expectEqual(@as(i32, 40), stub_xdg_set_size_h);
}

test "x11 set size clamps to hints and skips repeats" {
    resetStateWorld();
    var cl: Client = std.mem.zeroes(Client);
    var xs: c.struct_wlr_xwayland_surface = std.mem.zeroes(c.struct_wlr_xwayland_surface);
    x11Client(&cl, &xs);
    stub_x11_geo = .{ .x = 10, .y = 20, .width = 100, .height = 50 };

    try testing.expectEqual(@as(u32, 1), client_set_size(&cl, 100, 50, false));
    try testing.expectEqual(@as(c_int, 1), stub_x11_configure_calls);
    try testing.expectEqual(@as(i16, 10), stub_x11_configure_x);
    try testing.expectEqual(@as(u16, 100), stub_x11_configure_w);
    try testing.expectEqual(@as(u32, 0), client_set_size(&cl, 100, 50, false));
    try testing.expectEqual(@as(c_int, 1), stub_x11_configure_calls);
    try testing.expectEqual(@as(u32, 1), client_set_size(&cl, 100, 50, true));
    try testing.expectEqual(@as(c_int, 2), stub_x11_configure_calls);

    var hints: c.xcb_size_hints_t = std.mem.zeroes(c.xcb_size_hints_t);
    hints.min_width = 120;
    hints.min_height = 60;
    xs.size_hints = &hints;
    _ = client_set_size(&cl, 100, 50, true);
    try testing.expectEqual(@as(u16, 120), stub_x11_configure_w);
    try testing.expectEqual(@as(u16, 60), stub_x11_configure_h);
}

test "minimize, maximize and tiled state follow the role" {
    resetStateWorld();
    var cl: Client = std.mem.zeroes(Client);
    var xs: c.struct_wlr_xwayland_surface = std.mem.zeroes(c.struct_wlr_xwayland_surface);
    x11Client(&cl, &xs);
    client_set_minimized(&cl, true);
    try testing.expectEqual(@as(c_int, 1), stub_x11_minimize_calls);
    try testing.expect(stub_x11_minimize_value);

    client_set_maximized(&cl, true);
    try testing.expectEqual(@as(c_int, 1), stub_x11_maximize_calls);
    try testing.expect(stub_x11_maximize_vert and stub_x11_maximize_horz);

    var xdg: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    var toplevel: c.struct_wlr_xdg_toplevel = std.mem.zeroes(c.struct_wlr_xdg_toplevel);
    xdgClient(&cl, &xdg, &toplevel);
    client_set_maximized(&cl, true);
    try testing.expectEqual(@as(c_int, 1), stub_xdg_maximize_calls);
    try testing.expect(stub_xdg_maximize_value);

    stub_resource_version = 1;
    cl.force_fakemaximize = 1;
    client_set_tiled(&cl, 0);
    try testing.expectEqual(@as(c_int, 0), stub_xdg_tiled_calls);
    try testing.expect(!stub_xdg_maximize_value);

    stub_resource_version = 5;
    cl.force_fakemaximize = 0;
    client_set_tiled(&cl, 15);
    try testing.expectEqual(@as(c_int, 1), stub_xdg_tiled_calls);
    try testing.expectEqual(@as(u32, 15), stub_xdg_tiled_edges);

    resetStateWorld();
    x11Client(&cl, &xs);
    cl.force_fakemaximize = 1;
    client_set_tiled(&cl, 0);
    try testing.expectEqual(@as(c_int, 1), stub_x11_maximize_calls);
    try testing.expect(!stub_x11_maximize_vert);
}

test "tiled hint follows floating and forced state" {
    resetStateWorld();
    var cl: Client = std.mem.zeroes(Client);
    var xdg: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    var toplevel: c.struct_wlr_xdg_toplevel = std.mem.zeroes(c.struct_wlr_xdg_toplevel);
    xdgClient(&cl, &xdg, &toplevel);

    client_sync_tiled_hint(&cl);
    try testing.expectEqual(@as(u32, 15), stub_xdg_tiled_edges);
    cl.isfloating = 1;
    client_sync_tiled_hint(&cl);
    try testing.expectEqual(@as(u32, 0), stub_xdg_tiled_edges);
    cl.force_tiled_state = 1;
    client_sync_tiled_hint(&cl);
    try testing.expectEqual(@as(u32, 15), stub_xdg_tiled_edges);
    client_sync_tiled_hint(null);
}

test "x11 focus, popup, global and request predicates" {
    resetStateWorld();
    var cl: Client = std.mem.zeroes(Client);
    var xs: c.struct_wlr_xwayland_surface = std.mem.zeroes(c.struct_wlr_xwayland_surface);
    x11Client(&cl, &xs);

    try testing.expectEqual(@as(i32, 0), client_should_ignore_focus(&cl));
    var hints: c.xcb_icccm_wm_hints_t = std.mem.zeroes(c.xcb_icccm_wm_hints_t);
    hints.input = 0;
    xs.hints = &hints;
    try testing.expectEqual(@as(i32, 1), client_should_ignore_focus(&cl));

    stub_window_type = c.WLR_XWAYLAND_NET_WM_WINDOW_TYPE_MENU;
    try testing.expectEqual(@as(i32, 1), client_is_x11_popup(&cl));
    stub_window_type = c.WLR_XWAYLAND_NET_WM_WINDOW_TYPE_NORMAL;
    try testing.expectEqual(@as(i32, 0), client_is_x11_popup(&cl));

    xs.sticky = true;
    xs.above = true;
    try testing.expectEqual(@as(i32, 1), client_should_global(&cl));
    try testing.expectEqual(@as(i32, 1), client_should_overtop(&cl));

    xs.override_redirect = true;
    stub_or_wants_focus = true;
    stub_input_model = 1;
    try testing.expectEqual(@as(i32, 1), client_wants_focus(&cl));
    stub_input_model = c.WLR_ICCCM_INPUT_MODEL_NONE;
    try testing.expectEqual(@as(i32, 0), client_wants_focus(&cl));

    xs.fullscreen = true;
    try testing.expectEqual(@as(i32, 1), client_wants_fullscreen(&cl));
    xs.maximized_vert = true;
    try testing.expect(client_request_maximize(&cl, null));
    var ev: c.struct_wlr_xwayland_minimize_event = std.mem.zeroes(c.struct_wlr_xwayland_minimize_event);
    ev.minimize = true;
    try testing.expect(client_request_minimize(&cl, &ev));

    var xdg: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    var toplevel: c.struct_wlr_xdg_toplevel = std.mem.zeroes(c.struct_wlr_xdg_toplevel);
    xdgClient(&cl, &xdg, &toplevel);
    toplevel.requested.fullscreen = true;
    toplevel.requested.minimized = true;
    toplevel.requested.maximized = true;
    try testing.expectEqual(@as(i32, 1), client_wants_fullscreen(&cl));
    try testing.expect(client_request_minimize(&cl, null));
    try testing.expect(client_request_maximize(&cl, null));
}

test "size bounds clamp xdg and scaled x11 windows" {
    resetStateWorld();
    var cl: Client = std.mem.zeroes(Client);
    var xdg: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    var toplevel: c.struct_wlr_xdg_toplevel = std.mem.zeroes(c.struct_wlr_xdg_toplevel);
    xdgClient(&cl, &xdg, &toplevel);
    cl.bw = 1;
    cl.geom = .{ .x = 0, .y = 0, .width = 50, .height = 30 };
    toplevel.current.min_width = 100;
    toplevel.current.min_height = 30;
    toplevel.current.max_width = 400;
    toplevel.current.max_height = 300;
    client_set_size_bound(&cl);
    try testing.expectEqual(@as(i32, 102), cl.geom.width);
    try testing.expectEqual(@as(i32, 32), cl.geom.height);

    cl.geom = .{ .x = 0, .y = 0, .width = 1000, .height = 1000 };
    client_set_size_bound(&cl);
    try testing.expectEqual(@as(i32, 402), cl.geom.width);
    try testing.expectEqual(@as(i32, 302), cl.geom.height);

    resetStateWorld();
    var xs: c.struct_wlr_xwayland_surface = std.mem.zeroes(c.struct_wlr_xwayland_surface);
    x11Client(&cl, &xs);
    cl.bw = 1;
    cl.xwayland_scale = 2.0;
    var hints: c.xcb_size_hints_t = std.mem.zeroes(c.xcb_size_hints_t);
    hints.min_width = 200;
    hints.min_height = 100;
    hints.max_width = 400;
    hints.max_height = 300;
    xs.size_hints = &hints;
    cl.geom = .{ .x = 0, .y = 0, .width = 50, .height = 30 };
    client_set_size_bound(&cl);
    try testing.expectEqual(@as(i32, 102), cl.geom.width);
    try testing.expectEqual(@as(i32, 52), cl.geom.height);
    cl.geom = .{ .x = 0, .y = 0, .width = 1000, .height = 1000 };
    client_set_size_bound(&cl);
    try testing.expectEqual(@as(i32, 202), cl.geom.width);
    try testing.expectEqual(@as(i32, 152), cl.geom.height);
}

test "border hit test honours global, per-tag and layout settings" {
    resetStateWorld();
    var cl: Client = std.mem.zeroes(Client);
    try testing.expect(!check_hit_no_border(&cl));

    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var m: Monitor = std.mem.zeroes(Monitor);
    m.pertag = &p;
    cl.mon = &m;
    cl.tags = 1;
    try testing.expect(!check_hit_no_border(&cl));

    c.server.render_border = false;
    try testing.expect(check_hit_no_border(&cl));
    c.server.render_border = true;

    stub_tag_idx = 2;
    p.no_render_border[2] = 1;
    try testing.expect(check_hit_no_border(&cl));
    p.no_render_border[2] = 0;

    c.config.no_border_when_single = 1;
    m.visible_clients = 1;
    try testing.expect(check_hit_no_border(&cl));
    m.visible_clients = 2;

    c.config.monocle_no_border = 1;
    stub_monocle_layout = true;
    try testing.expect(check_hit_no_border(&cl));
    stub_monocle_layout = false;
    try testing.expect(!check_hit_no_border(&cl));
}
