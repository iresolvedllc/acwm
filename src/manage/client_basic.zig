//! Port of the basic client query/state helpers in src/manage/client.c
//! (Phase 5, client slice 1, slice 58).

const std = @import("std");
const c = @import("cc");
const build_options = @import("build_options");

const Client = c.Client;
const Monitor = c.Monitor;
const LayerSurface = c.LayerSurface;
const Box = c.struct_wlr_box;

const broken = "broken";

extern fn get_tags_first_tag_num(source_tags: u32) callconv(.c) u32;
extern fn xwayland_x11_to_logical(box: *Box, scale: f32) callconv(.c) void;

fn clientOpt(p: [*c]Client) ?*Client {
    return if (p == null) null else @ptrCast(p);
}

fn isX11(cl: *Client) bool {
    return build_options.xwayland and cl.type == c.X11;
}

export fn client_is_x11(cl: *Client) callconv(.c) i32 {
    return if (isX11(cl)) 1 else 0;
}

export fn client_surface(cl: *Client) callconv(.c) [*c]c.struct_wlr_surface {
    if (build_options.xwayland and isX11(cl) and cl.surface.xwayland != null)
        return cl.surface.xwayland.*.surface;
    if (cl.surface.xdg == null)
        return null;
    return cl.surface.xdg.*.surface;
}

export fn toplevel_from_wlr_surface(s: [*c]c.struct_wlr_surface, pc: [*c][*c]Client, pl: [*c][*c]LayerSurface) callconv(.c) i32 {
    if (s == null)
        return -1;

    const root = c.wlr_surface_get_root_surface(s);
    var out_client: [*c]Client = null;
    var out_layer: [*c]LayerSurface = null;
    var out_type: i32 = -1;

    var done = false;
    if (build_options.xwayland) {
        const xsurface = c.wlr_xwayland_surface_try_from_wlr_surface(root);
        if (xsurface != null) {
            if (xsurface.*.data != null)
                out_client = @ptrCast(@alignCast(xsurface.*.data.?));
            if (out_client != null)
                out_type = @intCast(out_client.*.type);
            done = true;
        }
    }

    if (!done) {
        const layer_surface = c.wlr_layer_surface_v1_try_from_wlr_surface(root);
        if (layer_surface != null) {
            if (layer_surface.*.data != null)
                out_layer = @ptrCast(@alignCast(layer_surface.*.data.?));
            out_type = @intCast(c.LayerShell);
            done = true;
        }
    }

    if (!done) {
        var xdg = c.wlr_xdg_surface_try_from_wlr_surface(root);
        while (xdg != null) {
            const role = @as(c_int, @intCast(xdg.*.role));
            if (role == c.WLR_XDG_SURFACE_ROLE_POPUP) {
                if (xdg.*.unnamed_0.popup == null or xdg.*.unnamed_0.popup.*.parent == null)
                    return -1;
                const parent = c.wlr_xdg_surface_try_from_wlr_surface(xdg.*.unnamed_0.popup.*.parent);
                if (parent == null)
                    return toplevel_from_wlr_surface(xdg.*.unnamed_0.popup.*.parent, pc, pl);
                xdg = parent;
            } else if (role == c.WLR_XDG_SURFACE_ROLE_TOPLEVEL) {
                if (xdg.*.data != null)
                    out_client = @ptrCast(@alignCast(xdg.*.data.?));
                if (out_client != null)
                    out_type = @intCast(out_client.*.type);
                break;
            } else {
                return -1;
            }
        }
    }

    if (pl != null) pl[0] = out_layer;
    if (pc != null) pc[0] = out_client;
    return out_type;
}

export fn client_activate_surface(s: [*c]c.struct_wlr_surface, activated: i32) callconv(.c) void {
    if (build_options.xwayland) {
        const xsurface = c.wlr_xwayland_surface_try_from_wlr_surface(s);
        if (xsurface != null) {
            if (activated != 0 and xsurface.*.minimized)
                c.wlr_xwayland_surface_set_minimized(xsurface, false);
            c.wlr_xwayland_surface_activate(xsurface, activated != 0);
            return;
        }
    }

    const toplevel = c.wlr_xdg_toplevel_try_from_wlr_surface(s);
    if (toplevel != null)
        _ = c.wlr_xdg_toplevel_set_activated(toplevel, activated != 0);
}

export fn client_get_appid(cl: *Client) callconv(.c) [*c]const u8 {
    if (build_options.xwayland and isX11(cl)) {
        const xsurface = cl.surface.xwayland;
        return if (xsurface != null and xsurface.*.class != null) xsurface.*.class else @ptrCast(broken.ptr);
    }
    const xdg = cl.surface.xdg;
    if (xdg == null or xdg.*.unnamed_0.toplevel == null)
        return @ptrCast(broken.ptr);
    const app_id = xdg.*.unnamed_0.toplevel.*.app_id;
    return if (app_id != null) app_id else @ptrCast(broken.ptr);
}

export fn get_client_tag_idx(cl: ?*const Client) callconv(.c) u32 {
    const client = cl orelse return 0;
    if ((client.tags & @as(u32, 1) << 31) != 0)
        return 0;
    return get_tags_first_tag_num(client.tags);
}

export fn client_get_pid(cl: *Client) callconv(.c) i32 {
    if (build_options.xwayland and isX11(cl)) {
        const xsurface = cl.surface.xwayland;
        return if (xsurface != null) xsurface.*.pid else 0;
    }
    const xdg = cl.surface.xdg;
    if (xdg == null or xdg.*.client == null or xdg.*.client.*.client == null)
        return 0;
    var pid: c.pid_t = 0;
    c.wl_client_get_credentials(xdg.*.client.*.client, &pid, null, null);
    return @intCast(pid);
}

export fn client_get_clip(cl: *Client, clip: *Box) callconv(.c) void {
    clip.* = .{
        .x = 0,
        .y = 0,
        .width = cl.geom.width - 2 * @as(i32, @intCast(cl.bw)),
        .height = cl.geom.height - 2 * @as(i32, @intCast(cl.bw)),
    };

    if (build_options.xwayland and isX11(cl))
        return;

    if (cl.surface.xdg == null)
        return;
    clip.x = cl.surface.xdg.*.geometry.x;
    clip.y = cl.surface.xdg.*.geometry.y;
}

export fn client_get_geometry(cl: *Client, geom: *Box) callconv(.c) void {
    if (build_options.xwayland and isX11(cl)) {
        const xsurface = cl.surface.xwayland;
        var xgeo = Box{
            .x = if (xsurface != null) xsurface.*.x else 0,
            .y = if (xsurface != null) xsurface.*.y else 0,
            .width = if (xsurface != null) xsurface.*.width else 0,
            .height = if (xsurface != null) xsurface.*.height else 0,
        };
        xwayland_x11_to_logical(&xgeo, cl.xwayland_scale);
        geom.* = xgeo;
        return;
    }
    if (cl.surface.xdg != null)
        geom.* = cl.surface.xdg.*.geometry;
}

export fn client_get_parent(cl: *Client) callconv(.c) ?*Client {
    var parent: [*c]Client = null;
    if (build_options.xwayland and isX11(cl)) {
        const xsurface = cl.surface.xwayland;
        if (xsurface != null and xsurface.*.parent != null)
            _ = toplevel_from_wlr_surface(xsurface.*.parent.*.surface, &parent, null);
        return clientOpt(parent);
    }
    const xdg = cl.surface.xdg;
    if (xdg != null and xdg.*.unnamed_0.toplevel != null and xdg.*.unnamed_0.toplevel.*.parent != null)
        _ = toplevel_from_wlr_surface(xdg.*.unnamed_0.toplevel.*.parent.*.base.*.surface, &parent, null);
    return clientOpt(parent);
}

export fn client_has_children(cl: *Client) callconv(.c) i32 {
    if (build_options.xwayland and isX11(cl)) {
        const xsurface = cl.surface.xwayland;
        return if (xsurface != null and c.wl_list_empty(&xsurface.*.children) == 0) 1 else 0;
    }
    if (cl.surface.xdg == null)
        return 0;
    return if (c.wl_list_length(&cl.surface.xdg.*.link) > 1) 1 else 0;
}

export fn client_get_title(cl: *Client) callconv(.c) [*c]const u8 {
    if (build_options.xwayland and isX11(cl)) {
        const xsurface = cl.surface.xwayland;
        return if (xsurface != null and xsurface.*.title != null) xsurface.*.title else @ptrCast(broken.ptr);
    }
    const xdg = cl.surface.xdg;
    if (xdg == null or xdg.*.unnamed_0.toplevel == null)
        return @ptrCast(broken.ptr);
    const title = xdg.*.unnamed_0.toplevel.*.title;
    return if (title != null) title else @ptrCast(broken.ptr);
}

export fn client_is_float_type(cl: *Client) callconv(.c) i32 {
    if (build_options.xwayland and isX11(cl)) {
        const xsurface = cl.surface.xwayland;
        if (xsurface == null or xsurface.*.size_hints == null)
            return 0;
        const hints = xsurface.*.size_hints;
        if (xsurface.*.modal)
            return 1;
        if (c.wlr_xwayland_surface_has_window_type(xsurface, c.WLR_XWAYLAND_NET_WM_WINDOW_TYPE_DIALOG) or
            c.wlr_xwayland_surface_has_window_type(xsurface, c.WLR_XWAYLAND_NET_WM_WINDOW_TYPE_SPLASH) or
            c.wlr_xwayland_surface_has_window_type(xsurface, c.WLR_XWAYLAND_NET_WM_WINDOW_TYPE_TOOLBAR) or
            c.wlr_xwayland_surface_has_window_type(xsurface, c.WLR_XWAYLAND_NET_WM_WINDOW_TYPE_UTILITY))
            return 1;
        return if (hints.*.min_width > 0 and hints.*.min_height > 0 and
            (hints.*.max_width == hints.*.min_width or hints.*.max_height == hints.*.min_height)) 1 else 0;
    }

    const xdg = cl.surface.xdg;
    if (xdg == null or xdg.*.unnamed_0.toplevel == null)
        return 0;
    const toplevel = xdg.*.unnamed_0.toplevel;
    const state = toplevel.*.current;
    return if (toplevel.*.parent != null or
        (state.min_width != 0 and state.min_height != 0 and
            (state.min_width == state.max_width or state.min_height == state.max_height))) 1 else 0;
}

export fn client_is_rendered_on_mon(cl: *Client, m: *Monitor) callconv(.c) i32 {
    var lx: c_int = 0;
    var ly: c_int = 0;
    if (cl.scene == null or !c.wlr_scene_node_coords(&cl.scene.*.node, &lx, &ly))
        return 0;
    const surface = client_surface(cl);
    if (surface == null)
        return 0;
    const head: [*c]c.struct_wl_list = @ptrCast(&surface.*.current_outputs);
    var pos = surface.*.current_outputs.next;
    while (pos != head) : (pos = pos.*.next) {
        const so: *c.struct_wlr_surface_output = @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.struct_wlr_surface_output, "link"));
        if (so.output == m.wlr_output)
            return 1;
    }
    return 0;
}

export fn client_is_unmanaged(cl: *Client) callconv(.c) i32 {
    if (build_options.xwayland and isX11(cl)) {
        const xsurface = cl.surface.xwayland;
        return if (xsurface != null and xsurface.*.override_redirect) 1 else 0;
    }
    return 0;
}

export fn client_notify_enter(s: [*c]c.struct_wlr_surface, kb: [*c]c.struct_wlr_keyboard) callconv(.c) void {
    if (kb != null) {
        c.wlr_seat_keyboard_notify_enter(c.server.seat, s, &kb.*.keycodes, kb.*.num_keycodes, &kb.*.modifiers);
    } else {
        c.wlr_seat_keyboard_notify_enter(c.server.seat, s, null, 0, null);
    }
}

export fn client_send_close(cl: *Client) callconv(.c) void {
    if (build_options.xwayland and isX11(cl)) {
        if (cl.surface.xwayland != null)
            c.wlr_xwayland_surface_close(cl.surface.xwayland);
        return;
    }
    if (cl.surface.xdg != null and cl.surface.xdg.*.unnamed_0.toplevel != null)
        c.wlr_xdg_toplevel_send_close(cl.surface.xdg.*.unnamed_0.toplevel);
}

export fn client_set_border_color(cl: *Client, color: [*c]const f32) callconv(.c) void {
    if (cl.border != null)
        c.wlr_scene_rect_set_color(cl.border, color);
}

export fn client_set_state_colors(cl: *Client, border_color: [*c]const f32, dim_color: [*c]const f32) callconv(.c) void {
    client_set_border_color(cl, border_color);
    if (cl.dim_node != null)
        c.acwm_dim_node_set_color(cl.dim_node, dim_color);
}

export fn client_set_fullscreen(cl: *Client, fullscreen: i32) callconv(.c) void {
    if (build_options.xwayland and isX11(cl)) {
        if (cl.surface.xwayland != null)
            c.wlr_xwayland_surface_set_fullscreen(cl.surface.xwayland, fullscreen != 0);
        return;
    }
    if (cl.surface.xdg != null and cl.surface.xdg.*.unnamed_0.toplevel != null)
        _ = c.wlr_xdg_toplevel_set_fullscreen(cl.surface.xdg.*.unnamed_0.toplevel, fullscreen != 0);
}

export fn client_set_scale(s: [*c]c.struct_wlr_surface, scale: f32) callconv(.c) void {
    c.wlr_fractional_scale_v1_notify_scale(s, scale);
    c.wlr_surface_set_preferred_buffer_scale(s, @intFromFloat(@ceil(scale)));
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/client_basic_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_first_tag: u32;
extern var stub_logical_box: Box;
extern var stub_x11_to_logical_calls: c_int;
extern var stub_x11_scale_arg: f32;
extern var stub_root_result: [*c]c.struct_wlr_surface;
extern var stub_xsurface_result: [*c]c.struct_wlr_xwayland_surface;
extern var stub_layer_result: [*c]c.struct_wlr_layer_surface_v1;
extern var stub_xdg_result: [*c]c.struct_wlr_xdg_surface;
extern var stub_xdg_queue: [4][*c]c.struct_wlr_xdg_surface;
extern var stub_xdg_count: c_int;
extern var stub_xdg_index: c_int;
extern var stub_toplevel_result: [*c]c.struct_wlr_xdg_toplevel;
extern var stub_xwayland_minimize_calls: c_int;
extern var stub_xwayland_minimize_value: bool;
extern var stub_xwayland_activate_calls: c_int;
extern var stub_xwayland_activate_value: bool;
extern var stub_xwayland_close_calls: c_int;
extern var stub_xwayland_fullscreen_calls: c_int;
extern var stub_xwayland_fullscreen_value: bool;
extern var stub_window_type: c_int;
extern var stub_activated_calls: c_int;
extern var stub_activated_value: bool;
extern var stub_send_close_calls: c_int;
extern var stub_xdg_fullscreen_calls: c_int;
extern var stub_xdg_fullscreen_value: bool;
extern var stub_pid: c.pid_t;
extern var stub_credentials_calls: c_int;
extern var stub_notify_enter_calls: c_int;
extern var stub_notify_enter_surface: [*c]c.struct_wlr_surface;
extern var stub_notify_keycode_count: c_int;
extern var stub_coords_ok: bool;
extern var stub_coords_calls: c_int;
extern var stub_rect_color_calls: c_int;
extern var stub_rect_color: [4]f32;
extern var stub_dim_color_calls: c_int;
extern var stub_dim_color: [4]f32;
extern var stub_fractional_scale_calls: c_int;
extern var stub_fractional_scale: f64;
extern var stub_buffer_scale_calls: c_int;
extern var stub_buffer_scale: i32;

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

fn resetBasicWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    stub_first_tag = 0;
    stub_logical_box = std.mem.zeroes(Box);
    stub_x11_to_logical_calls = 0;
    stub_x11_scale_arg = 0;
    stub_root_result = null;
    stub_xsurface_result = null;
    stub_layer_result = null;
    stub_xdg_result = null;
    stub_xdg_count = 0;
    stub_xdg_index = 0;
    stub_toplevel_result = null;
    stub_xwayland_minimize_calls = 0;
    stub_xwayland_minimize_value = true;
    stub_xwayland_activate_calls = 0;
    stub_xwayland_activate_value = false;
    stub_xwayland_close_calls = 0;
    stub_xwayland_fullscreen_calls = 0;
    stub_xwayland_fullscreen_value = false;
    stub_window_type = -1;
    stub_activated_calls = 0;
    stub_activated_value = false;
    stub_send_close_calls = 0;
    stub_xdg_fullscreen_calls = 0;
    stub_xdg_fullscreen_value = false;
    stub_pid = 0;
    stub_credentials_calls = 0;
    stub_notify_enter_calls = 0;
    stub_notify_enter_surface = null;
    stub_notify_keycode_count = -1;
    stub_coords_ok = true;
    stub_coords_calls = 0;
    stub_rect_color_calls = 0;
    stub_rect_color = std.mem.zeroes([4]f32);
    stub_dim_color_calls = 0;
    stub_dim_color = std.mem.zeroes([4]f32);
    stub_fractional_scale_calls = 0;
    stub_fractional_scale = 0;
    stub_buffer_scale_calls = 0;
    stub_buffer_scale = 0;
}

fn xdgClient(cl: *Client, xdg: *c.struct_wlr_xdg_surface, surface: *c.struct_wlr_surface) void {
    cl.* = std.mem.zeroes(Client);
    xdg.* = std.mem.zeroes(c.struct_wlr_xdg_surface);
    cl.type = @intCast(c.XDGShell);
    cl.surface.xdg = xdg;
    xdg.surface = surface;
}

test "client surface selection follows the role" {
    resetBasicWorld();
    var cl: Client = std.mem.zeroes(Client);
    var xdg: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    xdgClient(&cl, &xdg, &surface);
    try testing.expectEqual(@as(i32, 0), client_is_x11(&cl));
    try testing.expect(client_surface(&cl) == &surface);

    var xs: c.struct_wlr_xwayland_surface = std.mem.zeroes(c.struct_wlr_xwayland_surface);
    var xsurface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    xs.surface = &xsurface;
    cl.type = @intCast(c.X11);
    cl.surface.xwayland = &xs;
    try testing.expectEqual(@as(i32, 1), client_is_x11(&cl));
    try testing.expect(client_surface(&cl) == &xsurface);
}

test "toplevel resolution walks x11, layer and xdg roles" {
    resetBasicWorld();
    try testing.expectEqual(@as(i32, -1), toplevel_from_wlr_surface(null, null, null));

    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    var layer: LayerSurface = std.mem.zeroes(LayerSurface);
    var layer_surface: c.struct_wlr_layer_surface_v1 = std.mem.zeroes(c.struct_wlr_layer_surface_v1);
    layer_surface.data = &layer;
    layer_surface.surface = &surface;
    stub_layer_result = &layer_surface;
    var out_layer: [*c]LayerSurface = null;
    try testing.expectEqual(@as(i32, c.LayerShell), toplevel_from_wlr_surface(&surface, null, &out_layer));
    try testing.expect(out_layer == &layer);

    resetBasicWorld();
    var cl: Client = std.mem.zeroes(Client);
    var xdg: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    xdgClient(&cl, &xdg, &surface);
    xdg.role = @intCast(c.WLR_XDG_SURFACE_ROLE_TOPLEVEL);
    xdg.data = &cl;
    stub_xdg_result = &xdg;
    var out_client: [*c]Client = null;
    try testing.expectEqual(@as(i32, c.XDGShell), toplevel_from_wlr_surface(&surface, &out_client, null));
    try testing.expect(out_client == &cl);

    resetBasicWorld();
    var popup: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    var toplevel: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    var parent_surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    popup.role = @intCast(c.WLR_XDG_SURFACE_ROLE_POPUP);
    var xdg_popup: c.struct_wlr_xdg_popup = std.mem.zeroes(c.struct_wlr_xdg_popup);
    popup.unnamed_0.popup = &xdg_popup;
    popup.unnamed_0.popup.*.parent = &parent_surface;
    toplevel.role = @intCast(c.WLR_XDG_SURFACE_ROLE_TOPLEVEL);
    toplevel.data = &cl;
    stub_xdg_count = 2;
    stub_xdg_queue[0] = &popup;
    stub_xdg_queue[1] = &toplevel;
    try testing.expectEqual(@as(i32, c.XDGShell), toplevel_from_wlr_surface(&surface, &out_client, null));

    resetBasicWorld();
    stub_xdg_count = 1;
    stub_xdg_queue[0] = &popup;
    popup.unnamed_0.popup.*.parent = null;
    try testing.expectEqual(@as(i32, -1), toplevel_from_wlr_surface(&surface, null, null));
}

test "surface activation handles x11 minimize and xdg toplevels" {
    resetBasicWorld();
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    var xs: c.struct_wlr_xwayland_surface = std.mem.zeroes(c.struct_wlr_xwayland_surface);
    xs.minimized = true;
    stub_xsurface_result = &xs;
    client_activate_surface(&surface, 1);
    try testing.expectEqual(@as(c_int, 1), stub_xwayland_minimize_calls);
    try testing.expect(!stub_xwayland_minimize_value);
    try testing.expect(stub_xwayland_activate_value);

    stub_xsurface_result = null;
    var toplevel: c.struct_wlr_xdg_toplevel = std.mem.zeroes(c.struct_wlr_xdg_toplevel);
    stub_toplevel_result = &toplevel;
    client_activate_surface(&surface, 0);
    try testing.expectEqual(@as(c_int, 1), stub_activated_calls);
    try testing.expect(!stub_activated_value);
}

test "appid, pid, title and tag index report role data or fallbacks" {
    resetBasicWorld();
    var cl: Client = std.mem.zeroes(Client);
    var xdg: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    xdgClient(&cl, &xdg, &surface);
    var toplevel: c.struct_wlr_xdg_toplevel = std.mem.zeroes(c.struct_wlr_xdg_toplevel);
    xdg.unnamed_0.toplevel = &toplevel;
    toplevel.app_id = @ptrCast(@constCast("app"));
    toplevel.title = @ptrCast(@constCast("title"));
    var wlclient: c.struct_wlr_xdg_client = std.mem.zeroes(c.struct_wlr_xdg_client);
    wlclient.client = @ptrFromInt(0x3000);
    xdg.client = &wlclient;
    stub_pid = 42;

    try testing.expectEqualStrings("app", std.mem.span(@as([*:0]const u8, @ptrCast(client_get_appid(&cl)))));
    try testing.expectEqualStrings("title", std.mem.span(@as([*:0]const u8, @ptrCast(client_get_title(&cl)))));
    try testing.expectEqual(@as(i32, 42), client_get_pid(&cl));
    try testing.expectEqual(@as(c_int, 1), stub_credentials_calls);

    toplevel.app_id = null;
    toplevel.title = null;
    xdg.client = null;
    try testing.expectEqualStrings("broken", std.mem.span(@as([*:0]const u8, @ptrCast(client_get_appid(&cl)))));
    try testing.expectEqualStrings("broken", std.mem.span(@as([*:0]const u8, @ptrCast(client_get_title(&cl)))));
    try testing.expectEqual(@as(i32, 0), client_get_pid(&cl));

    cl.type = @intCast(c.X11);
    var xs: c.struct_wlr_xwayland_surface = std.mem.zeroes(c.struct_wlr_xwayland_surface);
    xs.class = @ptrCast(@constCast("xapp"));
    xs.title = @ptrCast(@constCast("xtitle"));
    xs.pid = 99;
    cl.surface.xwayland = &xs;
    try testing.expectEqualStrings("xapp", std.mem.span(@as([*:0]const u8, @ptrCast(client_get_appid(&cl)))));
    try testing.expectEqualStrings("xtitle", std.mem.span(@as([*:0]const u8, @ptrCast(client_get_title(&cl)))));
    try testing.expectEqual(@as(i32, 99), client_get_pid(&cl));

    try testing.expectEqual(@as(u32, 0), get_client_tag_idx(null));
    cl.tags = 0;
    try testing.expectEqual(@as(u32, 0), get_client_tag_idx(&cl));
    cl.tags = @as(u32, 1) << 31;
    try testing.expectEqual(@as(u32, 0), get_client_tag_idx(&cl));
    cl.tags = 0b110;
    stub_first_tag = 3;
    try testing.expectEqual(@as(u32, 3), get_client_tag_idx(&cl));
}

test "clip and geometry use xdg state and x11 conversion" {
    resetBasicWorld();
    var cl: Client = std.mem.zeroes(Client);
    var xdg: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    xdgClient(&cl, &xdg, &surface);
    cl.geom = .{ .x = 0, .y = 0, .width = 100, .height = 50 };
    cl.bw = 2;
    xdg.geometry = .{ .x = 5, .y = 6, .width = 90, .height = 40 };
    var clip: Box = undefined;
    client_get_clip(&cl, &clip);
    try testing.expectEqual(@as(i32, 5), clip.x);
    try testing.expectEqual(@as(i32, 6), clip.y);
    try testing.expectEqual(@as(i32, 96), clip.width);
    try testing.expectEqual(@as(i32, 46), clip.height);

    var geom: Box = undefined;
    client_get_geometry(&cl, &geom);
    try testing.expectEqual(@as(i32, 5), geom.x);
    try testing.expectEqual(@as(i32, 90), geom.width);

    cl.type = @intCast(c.X11);
    var xs: c.struct_wlr_xwayland_surface = std.mem.zeroes(c.struct_wlr_xwayland_surface);
    xs.x = 10;
    xs.y = 20;
    xs.width = 200;
    xs.height = 100;
    cl.surface.xwayland = &xs;
    cl.xwayland_scale = 2.0;
    stub_logical_box = .{ .x = 10, .y = 20, .width = 100, .height = 50 };
    client_get_geometry(&cl, &geom);
    try testing.expectEqual(@as(c_int, 1), stub_x11_to_logical_calls);
    try testing.expectEqual(@as(f32, 2.0), stub_x11_scale_arg);
    try testing.expectEqual(@as(i32, 100), geom.width);
    client_get_clip(&cl, &clip);
    try testing.expectEqual(@as(i32, 0), clip.x);
    try testing.expectEqual(@as(i32, 96), clip.width);
}

test "parent, children and float type infer role state" {
    resetBasicWorld();
    var cl: Client = std.mem.zeroes(Client);
    var xdg: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    xdgClient(&cl, &xdg, &surface);
    var toplevel: c.struct_wlr_xdg_toplevel = std.mem.zeroes(c.struct_wlr_xdg_toplevel);
    xdg.unnamed_0.toplevel = &toplevel;
    try testing.expect(client_get_parent(&cl) == null);

    var parent_cl: Client = std.mem.zeroes(Client);
    var parent_xdg: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    var parent_surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    parent_xdg.role = @intCast(c.WLR_XDG_SURFACE_ROLE_TOPLEVEL);
    parent_xdg.data = &parent_cl;
    parent_xdg.surface = &parent_surface;
    var parent_toplevel: c.struct_wlr_xdg_toplevel = std.mem.zeroes(c.struct_wlr_xdg_toplevel);
    parent_toplevel.base = &parent_xdg;
    toplevel.parent = &parent_toplevel;
    stub_xdg_count = 1;
    stub_xdg_queue[0] = &parent_xdg;
    try testing.expect(client_get_parent(&cl) == &parent_cl);

    xdg.link.next = &xdg.link;
    xdg.link.prev = &xdg.link;
    try testing.expectEqual(@as(i32, 0), client_has_children(&cl));
    var link1: c.struct_wl_list = std.mem.zeroes(c.struct_wl_list);
    var link2: c.struct_wl_list = std.mem.zeroes(c.struct_wl_list);
    xdg.link.next = &link1;
    xdg.link.prev = &link2;
    link1.prev = &xdg.link;
    link1.next = &link2;
    link2.prev = &link1;
    link2.next = &xdg.link;
    try testing.expectEqual(@as(i32, 1), client_has_children(&cl));

    toplevel.parent = null;
    toplevel.current = std.mem.zeroes(c.struct_wlr_xdg_toplevel_state);
    toplevel.current.min_width = 100;
    toplevel.current.min_height = 50;
    toplevel.current.max_width = 100;
    toplevel.current.max_height = 80;
    try testing.expectEqual(@as(i32, 1), client_is_float_type(&cl));
    toplevel.current.min_width = 100;
    toplevel.current.max_width = 200;
    try testing.expectEqual(@as(i32, 0), client_is_float_type(&cl));
    toplevel.parent = &parent_toplevel;
    try testing.expectEqual(@as(i32, 1), client_is_float_type(&cl));

    resetBasicWorld();
    cl.type = @intCast(c.X11);
    var xs: c.struct_wlr_xwayland_surface = std.mem.zeroes(c.struct_wlr_xwayland_surface);
    cl.surface.xwayland = &xs;
    try testing.expectEqual(@as(i32, 0), client_is_float_type(&cl));
    var hints: c.xcb_size_hints_t = std.mem.zeroes(c.xcb_size_hints_t);
    hints.min_width = 50;
    hints.min_height = 50;
    hints.max_width = 50;
    xs.size_hints = &hints;
    try testing.expectEqual(@as(i32, 1), client_is_float_type(&cl));
    xs.modal = true;
    try testing.expectEqual(@as(i32, 1), client_is_float_type(&cl));

    listInit(&xs.children);
    try testing.expectEqual(@as(i32, 0), client_has_children(&cl));
    var child: c.struct_wl_list = std.mem.zeroes(c.struct_wl_list);
    listInsert(&xs.children, &child);
    try testing.expectEqual(@as(i32, 1), client_has_children(&cl));
}

test "rendered monitor and unmanaged flags inspect outputs and override" {
    resetBasicWorld();
    var cl: Client = std.mem.zeroes(Client);
    var xdg: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    xdgClient(&cl, &xdg, &surface);
    var scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    cl.scene = &scene;
    var m: Monitor = std.mem.zeroes(Monitor);
    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    m.wlr_output = &out;

    stub_coords_ok = false;
    try testing.expectEqual(@as(i32, 0), client_is_rendered_on_mon(&cl, &m));

    stub_coords_ok = true;
    listInit(&surface.current_outputs);
    try testing.expectEqual(@as(i32, 0), client_is_rendered_on_mon(&cl, &m));
    var so: c.struct_wlr_surface_output = std.mem.zeroes(c.struct_wlr_surface_output);
    so.output = &out;
    listInsert(&surface.current_outputs, &so.link);
    try testing.expectEqual(@as(i32, 1), client_is_rendered_on_mon(&cl, &m));

    try testing.expectEqual(@as(i32, 0), client_is_unmanaged(&cl));
    cl.type = @intCast(c.X11);
    var xs: c.struct_wlr_xwayland_surface = std.mem.zeroes(c.struct_wlr_xwayland_surface);
    cl.surface.xwayland = &xs;
    xs.override_redirect = true;
    try testing.expectEqual(@as(i32, 1), client_is_unmanaged(&cl));
}

test "keyboard enter and close requests use the right surface" {
    resetBasicWorld();
    var seat: c.struct_wlr_seat = std.mem.zeroes(c.struct_wlr_seat);
    c.server.seat = &seat;
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    var kb: c.struct_wlr_keyboard = std.mem.zeroes(c.struct_wlr_keyboard);
    kb.num_keycodes = 2;
    client_notify_enter(&surface, &kb);
    try testing.expectEqual(@as(c_int, 1), stub_notify_enter_calls);
    try testing.expect(stub_notify_enter_surface == &surface);
    try testing.expectEqual(@as(c_int, 2), stub_notify_keycode_count);

    client_notify_enter(&surface, null);
    try testing.expectEqual(@as(c_int, 0), stub_notify_keycode_count);

    var cl: Client = std.mem.zeroes(Client);
    var xdg: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    xdgClient(&cl, &xdg, &surface);
    var toplevel: c.struct_wlr_xdg_toplevel = std.mem.zeroes(c.struct_wlr_xdg_toplevel);
    xdg.unnamed_0.toplevel = &toplevel;
    client_send_close(&cl);
    try testing.expectEqual(@as(c_int, 1), stub_send_close_calls);

    cl.type = @intCast(c.X11);
    var xs: c.struct_wlr_xwayland_surface = std.mem.zeroes(c.struct_wlr_xwayland_surface);
    cl.surface.xwayland = &xs;
    client_send_close(&cl);
    try testing.expectEqual(@as(c_int, 1), stub_xwayland_close_calls);
}

test "colors, fullscreen and scale update scene and role state" {
    resetBasicWorld();
    var cl: Client = std.mem.zeroes(Client);
    var xdg: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    xdgClient(&cl, &xdg, &surface);
    var border: c.struct_wlr_scene_rect = std.mem.zeroes(c.struct_wlr_scene_rect);
    var dim: c.AcwmDimNode = std.mem.zeroes(c.AcwmDimNode);
    cl.border = &border;
    cl.dim_node = &dim;
    const border_color = [4]f32{ 1, 0.5, 0.25, 1 };
    const dim_color = [4]f32{ 0, 0, 0, 0.4 };
    client_set_state_colors(&cl, &border_color, &dim_color);
    try testing.expectEqual(@as(c_int, 1), stub_rect_color_calls);
    try testing.expectEqual(@as(c_int, 1), stub_dim_color_calls);
    try testing.expectApproxEqAbs(@as(f32, 0.5), stub_rect_color[1], 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.4), stub_dim_color[3], 1e-6);

    var toplevel: c.struct_wlr_xdg_toplevel = std.mem.zeroes(c.struct_wlr_xdg_toplevel);
    xdg.unnamed_0.toplevel = &toplevel;
    client_set_fullscreen(&cl, 1);
    try testing.expectEqual(@as(c_int, 1), stub_xdg_fullscreen_calls);
    try testing.expect(stub_xdg_fullscreen_value);

    cl.type = @intCast(c.X11);
    var xs: c.struct_wlr_xwayland_surface = std.mem.zeroes(c.struct_wlr_xwayland_surface);
    cl.surface.xwayland = &xs;
    client_set_fullscreen(&cl, 0);
    try testing.expectEqual(@as(c_int, 1), stub_xwayland_fullscreen_calls);
    try testing.expect(!stub_xwayland_fullscreen_value);

    client_set_scale(&surface, 1.5);
    try testing.expectEqual(@as(c_int, 1), stub_fractional_scale_calls);
    try testing.expectApproxEqAbs(@as(f64, 1.5), stub_fractional_scale, 1e-6);
    try testing.expectEqual(@as(i32, 2), stub_buffer_scale);
}
