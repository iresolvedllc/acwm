//! Port of client geometry/initialisation and xdg-toplevel setup in
//! src/manage/client.c (Phase 5, client slice 5, slice 62).

const std = @import("std");
const c = @import("cc");
const build_options = @import("build_options");

const Client = c.Client;
const Monitor = c.Monitor;
const Box = c.struct_wlr_box;

extern fn xwayland_apply_scale(cl: [*c]Client) callconv(.c) void;
extern fn fix_xwayland_coordinate(box: *Box) callconv(.c) void;
extern fn xwayland_logical_to_x11(box: *Box, scale: f32) callconv(.c) void;
extern fn client_update_xwayland_dest_size(cl: [*c]Client) callconv(.c) void;
extern fn handle_xwayland_surface_set_geometry(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_xwayland_surface_commit(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn client_focus(cl: ?*Client, lift: i32) callconv(.c) void;
extern fn client_wants_focus(cl: [*c]Client) callconv(.c) i32;
extern fn client_get_geometry(cl: [*c]Client, geom: *Box) callconv(.c) void;
extern fn client_surface(cl: [*c]Client) callconv(.c) [*c]c.struct_wlr_surface;
extern fn client_set_size(cl: [*c]Client, width: u32, height: u32, force: bool) callconv(.c) u32;
extern fn client_reset_mon_tags(cl: [*c]Client, m: [*c]Monitor, tags: u32) callconv(.c) void;
extern fn check_match_tag_floating_rule(cl: [*c]Client, m: [*c]Monitor) callconv(.c) void;
extern fn client_wants_fullscreen(cl: [*c]Client) callconv(.c) i32;
extern fn center_tiled_select(m: [*c]Monitor) callconv(.c) [*c]Client;
extern fn scroll_get_stack_tail_client(cl: [*c]Client) callconv(.c) [*c]Client;
extern fn pre_calculate_before_arrange(m: [*c]Monitor, want_animation: bool, from_view: bool, force: bool) callconv(.c) void;
extern fn overview_destroy_card(cl: [*c]Client) callconv(.c) void;
extern fn is_scroller_layout(m: [*c]Monitor) callconv(.c) bool;
extern fn get_mon_curtag(m: ?*const Monitor) callconv(.c) u32;
extern fn acwm_scene_node_find(node: [*c]c.struct_wlr_scene_node) callconv(.c) [*c]c.AcwmSceneNode;
extern fn handle_client_commit(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_client_map(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_client_unmap(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_client_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_client_request_fullscreen(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_client_request_maximize(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_client_request_minimize(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_client_set_title(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;

fn isX11(cl: *Client) bool {
    return build_options.xwayland and cl.type == c.X11;
}

fn VISIBLEON(cl: *const Client, m: *const Monitor) bool {
    if (cl.mon != @as([*c]Monitor, @ptrCast(@constCast(m))))
        return false;
    if (cl.isminimized != 0)
        return false;
    return (cl.tags & m.tagset[m.seltags]) != 0 or cl.isglobal != 0 or cl.isunglobal != 0;
}

fn ISSCROLLTILED(cl: *const Client) bool {
    return cl.isfloating == 0 and cl.isminimized == 0 and cl.iskilling == 0 and cl.isunglobal == 0;
}

fn nodeTypeIs(node: *const c.struct_wlr_scene_node, t: c_int) bool {
    return node.type == @as(c.enum_wlr_scene_node_type, @intCast(t));
}

export fn client_update_geometry(cl: *Client) callconv(.c) void {
    if (isX11(cl)) {
        xwayland_apply_scale(cl);
        client_get_geometry(cl, &cl.geom);
        if (cl.isfloating != 0) {
            fix_xwayland_coordinate(&cl.geom);
            cl.float_geom = cl.geom;
        }
    }
}

export fn client_init_xwayland(cl: *Client) callconv(.c) void {
    if (!isX11(cl) or cl.scene_surface == null)
        return;

    const head: [*c]c.struct_wl_list = @ptrCast(&cl.scene_surface.*.children);
    var pos = cl.scene_surface.*.children.next;
    while (pos != head) : (pos = pos.*.next) {
        const child = @as(*c.struct_wlr_scene_node, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.struct_wlr_scene_node, "link")));
        if (!nodeTypeIs(child, c.WLR_SCENE_NODE_BUFFER))
            continue;
        const buffer = c.wlr_scene_buffer_from_node(child);
        if (c.wlr_scene_surface_try_from_buffer(buffer) != null) {
            cl.xwl_root_buffer = buffer;
            if (buffer != null)
                buffer.*.point_accepts_input = xwayland_scene_buffer_point_accepts_input;
            break;
        }
    }

    if (client_surface(cl) != null) {
        cl.commmitx11.notify = handle_xwayland_surface_commit;
        c.wl_signal_add(&client_surface(cl).*.events.commit, &cl.commmitx11);
    }
}

export fn client_init_unmanaged(cl: *Client) callconv(.c) bool {
    if (c.client_is_unmanaged(cl) == 0)
        return false;
    if (!build_options.xwayland)
        return true;

    xwayland_apply_scale(cl);
    client_get_geometry(cl, &cl.geom);
    var geo = cl.geom;
    fix_xwayland_coordinate(&geo);
    var xgeo = geo;
    xwayland_logical_to_x11(&xgeo, cl.xwayland_scale);
    c.wlr_scene_node_set_position(&cl.scene.*.node, geo.x, geo.y);
    c.wlr_xwayland_surface_configure(cl.surface.xwayland, @intCast(xgeo.x), @intCast(xgeo.y), @intCast(xgeo.width), @intCast(xgeo.height));
    client_update_xwayland_dest_size(cl);
    cl.set_geometry.notify = handle_xwayland_surface_set_geometry;
    c.wl_signal_add(&cl.surface.xwayland.*.events.set_geometry, &cl.set_geometry);
    c.wlr_scene_node_reparent(&cl.scene.*.node, c.server.layers[@intCast(c.LyrOverlay)]);
    if (client_wants_focus(cl) != 0) {
        client_focus(cl, 1);
        c.server.exclusive_focus = @ptrCast(cl);
    }
    return true;
}

export fn client_apply_xwayland(cl: *Client) callconv(.c) void {
    if (isX11(cl))
        xwayland_apply_scale(cl);
}

export fn xwayland_scene_buffer_point_accepts_input(buffer: [*c]c.struct_wlr_scene_buffer, sx: [*c]f64, sy: [*c]f64) callconv(.c) bool {
    const scene_surface = c.wlr_scene_surface_try_from_buffer(buffer);
    if (scene_surface == null)
        return false;

    var tx = sx.*;
    var ty = sy.*;
    const scene_data = acwm_scene_node_find(&buffer.*.node);
    if (scene_data != null and scene_data.*.type == @as(u32, @intCast(c.X11))) {
        if (scene_data.*.owner != null and c.config.xwayland_ignore_scale != 0) {
            const cl = @as(*Client, @ptrCast(@alignCast(scene_data.*.owner.?)));
            if (cl.xwayland_scale > 0) {
                tx *= cl.xwayland_scale;
                ty *= cl.xwayland_scale;
            }
        }
    }
    return c.wlr_surface_point_accepts_input(scene_surface.*.surface, tx, ty);
}

export fn handle_new_xdg_toplevel(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const toplevel = @as(*c.struct_wlr_xdg_toplevel, @ptrCast(@alignCast(data.?)));

    const raw = c.ecalloc(1, @sizeOf(Client)) orelse return;
    const cl = @as(*Client, @ptrCast(@alignCast(raw)));
    toplevel.base.*.data = @ptrCast(cl);
    cl.animation_type_open = c.ANIM_TYPE_UNSET;
    cl.animation_type_close = c.ANIM_TYPE_UNSET;
    cl.surface.xdg = toplevel.base;
    cl.bw = c.config.borderpx;

    cl.commit.notify = handle_client_commit;
    c.wl_signal_add(&toplevel.base.*.surface.*.events.commit, &cl.commit);
    cl.map.notify = handle_client_map;
    c.wl_signal_add(&toplevel.base.*.surface.*.events.map, &cl.map);
    cl.unmap.notify = handle_client_unmap;
    c.wl_signal_add(&toplevel.base.*.surface.*.events.unmap, &cl.unmap);
    cl.destroy.notify = handle_client_destroy;
    c.wl_signal_add(&toplevel.events.destroy, &cl.destroy);
    cl.fullscreen.notify = handle_client_request_fullscreen;
    c.wl_signal_add(&toplevel.events.request_fullscreen, &cl.fullscreen);
    cl.maximize.notify = handle_client_request_maximize;
    c.wl_signal_add(&toplevel.events.request_maximize, &cl.maximize);
    cl.minimize.notify = handle_client_request_minimize;
    c.wl_signal_add(&toplevel.events.request_minimize, &cl.minimize);
    cl.set_title.notify = handle_client_set_title;
    c.wl_signal_add(&toplevel.events.set_title, &cl.set_title);
}

fn copyColor(dst: *[4]f32, src: [*c]const f32) void {
    var i: usize = 0;
    while (i < 4) : (i += 1)
        dst[i] = src[i];
}

export fn init_client_properties(cl: *Client) callconv(.c) void {
    cl.xwl_req_valid = false;
    cl.xwl_req_x = 0;
    cl.xwl_req_y = 0;
    cl.xwl_req_w = 0;
    cl.xwl_req_h = 0;
    cl.blur_opacity = 1.0;
    cl.is_group_focus = false;
    cl.group_prev = null;
    cl.group_next = null;
    cl.is_tab_focus = false;
    cl.is_tab_hidden = false;
    cl.tab_prev = null;
    cl.tab_next = null;
    cl.tag_visible = false;
    cl.snapshot_temp_visible = false;
    cl.is_surface_hidden = false;
    cl.grid_col_per = 1.0;
    cl.grid_row_per = 1.0;
    cl.jump_label_node = null;
    cl.group_bar = null;
    cl.tab_bar = null;
    cl.dim_node = null;
    cl.overview_scene_surface = null;
    cl.drop_direction = c.UNDIR;
    cl.enable_drop_area_draw = false;
    cl.isfocusing = false;
    cl.isfloating = 0;
    cl.isfakefullscreen = 0;
    cl.no_animation = 0;
    cl.isopensilent = 0;
    cl.istagsilent = 0;
    cl.no_swallow = 0;
    cl.isterm = 0;
    cl.no_blur = 0;
    cl.tearing_hint = 0;
    cl.overview_isfullscreenbak = 0;
    cl.overview_ismaximizescreenbak = 0;
    cl.overview_isfloatingbak = 0;
    cl.pid = 0;
    cl.swallowdby = null;
    cl.swallowing = null;
    cl.ismaster = false;
    cl.old_ismaster = false;
    cl.isleftstack = false;
    cl.ismaximizescreen = 0;
    cl.isfullscreen = 0;
    cl.need_float_size_reduce = 0;
    cl.iskilling = 0;
    cl.isglobal = 0;
    cl.isminimized = 0;
    cl.isoverlay = 0;
    cl.isunglobal = 0;
    cl.is_in_scratchpad = 0;
    cl.isnamedscratchpad = 0;
    cl.need_float_size_reduce = 0;
    cl.is_clip_to_hide = false;
    cl.is_restoring_from_ov = false;
    cl.isurgent = 0;
    cl.need_output_flush = false;
    cl.scroller_proportion = c.config.scroller_default_proportion;
    cl.is_pending_open_animation = true;
    cl.drag_to_tile = false;
    cl.scratchpad_switching_mon = false;
    cl.scratchpad_tagin = false;
    cl.fake_no_border = false;
    cl.focused_opacity = c.config.focused_opacity;
    cl.unfocused_opacity = c.config.unfocused_opacity;
    cl.no_focus = 0;
    cl.no_fade_in = 0;
    cl.no_fade_out = 0;
    cl.no_force_center = 0;
    cl.no_border = 0;
    cl.no_size_hint = 0;
    cl.no_radius = 0;
    cl.no_shadow = 0;
    cl.ignore_maximize = 1;
    cl.ignore_minimize = 1;
    cl.iscustomsize = 0;
    cl.iscustompos = 0;
    cl.iscustom_scroller_proportion = 0;
    cl.iscustom_scroller_proportion_single = 0;
    cl.master_mfact_per = 0.0;
    cl.master_inner_per = 0.0;
    cl.stack_inner_per = 0.0;
    cl.master_size_weight = 0.0;
    cl.stack_size_weight = 0.0;
    cl.old_stack_inner_per = 0.0;
    cl.old_master_inner_per = 0.0;
    cl.old_master_mfact_per = 0.0;
    cl.allow_csd = 0;
    cl.force_fakemaximize = 0;
    cl.force_tiled_state = 1;
    cl.force_tearing = 0;
    cl.allow_shortcuts_inhibit = c.SHORTCUTS_INHIBIT_ENABLE;
    cl.idleinhibit_when_focus = 0;
    cl.vrr_only_fullscreen = 0;
    overview_destroy_card(cl);
    cl.ov_card_tree = null;
    c.wl_list_init(&cl.ov_card_surfaces);
    cl.force_render = 0;
    cl.activation_bypass = 0;
    cl.scroller_proportion_single = 0.0;
    cl.float_geom.width = 0;
    cl.float_geom.height = 0;
    cl.float_geom.x = 0;
    cl.float_geom.y = 0;
    cl.scroller_stack_proportion = 0.0;
    @memset(&cl.oldmonname, 0);
    copyColor(&cl.opacity_animation.initial_border_color, &c.config.bordercolor);
    copyColor(&cl.opacity_animation.current_border_color, &c.config.bordercolor);
    copyColor(&cl.opacity_animation.initial_dim_color, &c.config.dim_unfocused_color);
    copyColor(&cl.opacity_animation.current_dim_color, &c.config.dim_unfocused_color);
    cl.opacity_animation.initial_opacity = cl.unfocused_opacity;
    cl.opacity_animation.current_opacity = cl.unfocused_opacity;
    cl.animation.tagining = false;
    cl.animation.running = false;
    cl.animation.overining = false;
    cl.animation.overview_enter_anim_set = false;
    cl.animation.tagouting = false;
    cl.animation.tagouted = false;
    cl.image_capture_scene_surface = null;
    cl.image_capture_tree = null;
    cl.image_capture_source = null;
    c.wl_list_init(&cl.link);
    c.wl_list_init(&cl.flink);
}

fn client_insert_tiling_order(cl: *Client) void {
    var at_client: [*c]Client = null;
    const selected = if (c.server.selected_monitor != null) @as(*Monitor, @ptrCast(c.server.selected_monitor)) else null;

    if (c.config.new_is_master != 0 and selected != null and !is_scroller_layout(selected)) {
        c.wl_list_insert(&c.server.clients, &cl.link);
    } else if (selected != null and is_scroller_layout(selected) and
        selected.?.visible_scroll_tiling_clients > 0)
    {
        if (selected.?.sel != null and ISSCROLLTILED(selected.?.sel) and
            VISIBLEON(selected.?.sel, selected.?))
            at_client = scroll_get_stack_tail_client(selected.?.sel)
        else
            at_client = center_tiled_select(selected);
        if (at_client != null)
            c.wl_list_insert(&at_client.*.link, &cl.link)
        else
            c.wl_list_insert(c.server.clients.prev, &cl.link);
    } else {
        c.wl_list_insert(c.server.clients.prev, &cl.link);
    }
}

fn client_configure_size(cl: *Client, geo: Box, bw: i32) void {
    if (geo.width <= 2 * bw or geo.height <= 2 * bw)
        return;
    _ = client_set_size(cl, @intCast(geo.width - 2 * bw), @intCast(geo.height - 2 * bw), false);
}

fn client_negotiate_initial_size(cl: *Client, rule_mon: ?*Monitor, rule_tags: u32) void {
    const m = rule_mon orelse (if (cl.mon != null) @as(*Monitor, @ptrCast(cl.mon)) else if (c.server.selected_monitor != null) @as(*Monitor, @ptrCast(c.server.selected_monitor)) else null);
    if (m == null or m.?.isoverview != 0)
        return;

    const bw: i32 = @intCast(cl.bw);
    const saved_mon = cl.mon;
    const saved_tags = cl.tags;
    cl.mon = m;
    client_reset_mon_tags(cl, m, rule_tags);
    check_match_tag_floating_rule(cl, m);

    if (cl.isfloating != 0 or cl.isfullscreen != 0 or cl.ismaximizescreen != 0 or
        client_wants_fullscreen(cl) != 0)
    {
        if (cl.isfullscreen != 0 or client_wants_fullscreen(cl) != 0)
            client_configure_size(cl, m.?.m, 0)
        else if (cl.ismaximizescreen != 0)
            client_configure_size(cl, m.?.w, bw)
        else
            client_configure_size(cl, if (cl.float_geom.width > 0 and cl.float_geom.height > 0) cl.float_geom else cl.geom, bw);
        cl.mon = saved_mon;
        cl.tags = saved_tags;
        return;
    }

    const tag = get_mon_curtag(m);
    const layout = if (m.?.pertag != null) m.?.pertag.*.ltidxs[tag] else null;
    if (layout == null or layout.*.predict == null) {
        cl.mon = saved_mon;
        cl.tags = saved_tags;
        return;
    }

    client_insert_tiling_order(cl);
    pre_calculate_before_arrange(m, false, false, true);

    var geo = std.mem.zeroes(Box);
    if (layout.*.predict.?(m, cl, &geo))
        client_configure_size(cl, geo, bw);

    c.wl_list_remove(&cl.link);
    c.wl_list_init(&cl.link);
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/client_init_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_list_insert_calls: c_int;
extern var stub_unmanaged: bool;
extern var stub_xwayland_scale_calls: c_int;
extern var stub_fix_coord_calls: c_int;
extern var stub_logical_to_x11_calls: c_int;
extern var stub_logical_x11: Box;
extern var stub_dest_size_calls: c_int;
extern var stub_set_geometry_listener_calls: c_int;
extern var stub_x11_commit_listener_calls: c_int;
extern var stub_focus_calls: c_int;
extern var stub_wants_focus: i32;
extern var stub_surface: [*c]c.struct_wlr_surface;
extern var stub_geom: Box;
extern var stub_get_geometry_calls: c_int;
extern var stub_set_size_calls: c_int;
extern var stub_set_size_w: u32;
extern var stub_set_size_h: u32;
extern var stub_reset_tags: u32;
extern var stub_reset_tags_calls: c_int;
extern var stub_tag_float_calls: c_int;
extern var stub_wants_fullscreen: i32;
extern var stub_center_client: [*c]Client;
extern var stub_scroll_tail: [*c]Client;
extern var stub_pre_calc_calls: c_int;
extern var stub_overview_destroy_calls: c_int;
extern var stub_scroller: bool;
extern var stub_curtag: u32;
extern var stub_scene_data: [*c]c.AcwmSceneNode;
extern var stub_buffer: [*c]c.struct_wlr_scene_buffer;
extern var stub_scene_surface: [*c]c.struct_wlr_scene_surface;
extern var stub_point_accepts_calls: c_int;
extern var stub_point_tx: f64;
extern var stub_point_ty: f64;
extern var stub_point_accepts_result: bool;
extern var stub_x11_configure_calls: c_int;
extern var stub_scene_pos_calls: c_int;
extern var stub_reparent_calls: c_int;

fn predictFalse(m: [*c]Monitor, cl: [*c]Client, out: [*c]Box) callconv(.c) bool {
    _ = m;
    _ = cl;
    _ = out;
    return false;
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

fn mkBox(x: i32, y: i32, w: i32, h: i32) Box {
    return .{ .x = x, .y = y, .width = w, .height = h };
}

fn resetInitWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    listInit(&c.server.clients);
    listInit(&c.server.monitors);
    stub_list_insert_calls = 0;
    stub_unmanaged = false;
    stub_xwayland_scale_calls = 0;
    stub_fix_coord_calls = 0;
    stub_logical_to_x11_calls = 0;
    stub_logical_x11 = std.mem.zeroes(Box);
    stub_dest_size_calls = 0;
    stub_set_geometry_listener_calls = 0;
    stub_x11_commit_listener_calls = 0;
    stub_focus_calls = 0;
    stub_wants_focus = 0;
    stub_surface = null;
    stub_geom = std.mem.zeroes(Box);
    stub_get_geometry_calls = 0;
    stub_set_size_calls = 0;
    stub_set_size_w = 0;
    stub_set_size_h = 0;
    stub_reset_tags = 0;
    stub_reset_tags_calls = 0;
    stub_tag_float_calls = 0;
    stub_wants_fullscreen = 0;
    stub_center_client = null;
    stub_scroll_tail = null;
    stub_pre_calc_calls = 0;
    stub_overview_destroy_calls = 0;
    stub_scroller = false;
    stub_curtag = 0;
    stub_scene_data = null;
    stub_buffer = null;
    stub_scene_surface = null;
    stub_point_accepts_calls = 0;
    stub_point_tx = 0;
    stub_point_ty = 0;
    stub_point_accepts_result = true;
    stub_x11_configure_calls = 0;
    stub_scene_pos_calls = 0;
    stub_reparent_calls = 0;
}

fn baseX11(cl: *Client, xs: *c.struct_wlr_xwayland_surface) void {
    cl.* = std.mem.zeroes(Client);
    xs.* = std.mem.zeroes(c.struct_wlr_xwayland_surface);
    cl.type = @intCast(c.X11);
    cl.surface.xwayland = xs;
}

test "update geometry only touches X11 clients" {
    resetInitWorld();
    var cl: Client = std.mem.zeroes(Client);
    var xs: c.struct_wlr_xwayland_surface = std.mem.zeroes(c.struct_wlr_xwayland_surface);
    baseX11(&cl, &xs);
    cl.isfloating = 1;
    stub_geom = mkBox(10, 20, 100, 50);
    client_update_geometry(&cl);
    try testing.expectEqual(@as(c_int, 1), stub_xwayland_scale_calls);
    try testing.expectEqual(@as(c_int, 1), stub_get_geometry_calls);
    try testing.expectEqual(@as(c_int, 1), stub_fix_coord_calls);
    try testing.expectEqual(@as(i32, 100), cl.float_geom.width);

    resetInitWorld();
    cl.type = @intCast(c.XDGShell);
    client_update_geometry(&cl);
    try testing.expectEqual(@as(c_int, 0), stub_xwayland_scale_calls);
}

test "init xwayland finds the root buffer and listens for commits" {
    resetInitWorld();
    var cl: Client = std.mem.zeroes(Client);
    var xs: c.struct_wlr_xwayland_surface = std.mem.zeroes(c.struct_wlr_xwayland_surface);
    baseX11(&cl, &xs);
    var scene_surface: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    listInit(&scene_surface.children);
    cl.scene_surface = &scene_surface;
    var node: c.struct_wlr_scene_node = std.mem.zeroes(c.struct_wlr_scene_node);
    node.type = @intCast(c.WLR_SCENE_NODE_BUFFER);
    listInsert(&scene_surface.children, &node.link);
    var buffer: c.struct_wlr_scene_buffer = std.mem.zeroes(c.struct_wlr_scene_buffer);
    var ss: c.struct_wlr_scene_surface = std.mem.zeroes(c.struct_wlr_scene_surface);
    stub_buffer = &buffer;
    stub_scene_surface = &ss;
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    stub_surface = &surface;

    client_init_xwayland(&cl);
    try testing.expect(cl.xwl_root_buffer == &buffer);
    try testing.expect(buffer.point_accepts_input != null);
    try testing.expectEqual(@as(c_int, 1), stub_list_insert_calls);
    try testing.expect(cl.commmitx11.notify != null);
}

test "init unmanaged configures the overlay and optional focus" {
    resetInitWorld();
    var cl: Client = std.mem.zeroes(Client);
    var xs: c.struct_wlr_xwayland_surface = std.mem.zeroes(c.struct_wlr_xwayland_surface);
    baseX11(&cl, &xs);
    var scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    cl.scene = &scene;
    stub_geom = mkBox(5, 6, 100, 50);
    stub_logical_x11 = mkBox(10, 12, 200, 100);
    stub_wants_focus = 1;
    try testing.expect(!client_init_unmanaged(&cl));
    stub_unmanaged = true;
    try testing.expect(client_init_unmanaged(&cl));
    try testing.expectEqual(@as(c_int, 1), stub_x11_configure_calls);
    try testing.expectEqual(@as(c_int, 1), stub_scene_pos_calls);
    try testing.expectEqual(@as(c_int, 1), stub_dest_size_calls);
    try testing.expectEqual(@as(c_int, 1), stub_reparent_calls);
    try testing.expectEqual(@as(c_int, 1), stub_focus_calls);
    try testing.expect(c.server.exclusive_focus != null);
    try testing.expect(cl.set_geometry.notify != null);
}

test "xwayland point input scales coordinates for X11 owners" {
    resetInitWorld();
    var buffer: c.struct_wlr_scene_buffer = std.mem.zeroes(c.struct_wlr_scene_buffer);
    var sx: f64 = 10;
    var sy: f64 = 20;
    try testing.expect(!xwayland_scene_buffer_point_accepts_input(&buffer, &sx, &sy));

    var ss: c.struct_wlr_scene_surface = std.mem.zeroes(c.struct_wlr_scene_surface);
    stub_scene_surface = &ss;
    var data: c.AcwmSceneNode = std.mem.zeroes(c.AcwmSceneNode);
    data.type = @intCast(c.X11);
    var cl: Client = std.mem.zeroes(Client);
    cl.xwayland_scale = 1.5;
    data.owner = @ptrCast(&cl);
    stub_scene_data = &data;
    c.config.xwayland_ignore_scale = 1;
    try testing.expect(xwayland_scene_buffer_point_accepts_input(&buffer, &sx, &sy));
    try testing.expectApproxEqAbs(@as(f64, 15), stub_point_tx, 1e-6);
    try testing.expectApproxEqAbs(@as(f64, 30), stub_point_ty, 1e-6);
}

test "new xdg toplevel allocates and installs listeners" {
    resetInitWorld();
    c.config.borderpx = 3;
    var base: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    var toplevel: c.struct_wlr_xdg_toplevel = std.mem.zeroes(c.struct_wlr_xdg_toplevel);
    base.surface = &surface;
    toplevel.base = &base;
    handle_new_xdg_toplevel(null, &toplevel);
    try testing.expect(base.data != null);
    const cl = @as(*Client, @ptrCast(@alignCast(base.data.?)));
    try testing.expectEqual(@as(i32, c.ANIM_TYPE_UNSET), cl.animation_type_open);
    try testing.expectEqual(@as(i32, c.ANIM_TYPE_UNSET), cl.animation_type_close);
    try testing.expect(cl.surface.xdg == &base);
    try testing.expectEqual(@as(u32, 3), cl.bw);
    try testing.expectEqual(@as(c_int, 8), stub_list_insert_calls);
    try testing.expect(cl.commit.notify != null);
    try testing.expect(cl.map.notify != null);
    try testing.expect(cl.unmap.notify != null);
    try testing.expect(cl.destroy.notify != null);
    try testing.expect(cl.fullscreen.notify != null);
    try testing.expect(cl.maximize.notify != null);
    try testing.expect(cl.minimize.notify != null);
    try testing.expect(cl.set_title.notify != null);
}

test "client property init resets state, colors and lists" {
    resetInitWorld();
    c.config.bordercolor[0] = 1;
    c.config.dim_unfocused_color[0] = 0.5;
    c.config.scroller_default_proportion = 0.6;
    c.config.focused_opacity = 0.9;
    c.config.unfocused_opacity = 0.7;
    var cl: Client = std.mem.zeroes(Client);
    cl.isfloating = 1;
    init_client_properties(&cl);
    try testing.expectEqual(@as(i32, 0), cl.isfloating);
    try testing.expectEqual(@as(i32, 1), cl.force_tiled_state);
    try testing.expectEqual(@as(i32, 1), cl.ignore_maximize);
    try testing.expectEqual(@as(i32, c.SHORTCUTS_INHIBIT_ENABLE), cl.allow_shortcuts_inhibit);
    try testing.expect(cl.is_pending_open_animation);
    try testing.expectEqual(@as(c_int, 1), stub_overview_destroy_calls);
    try testing.expectEqual(@as(u8, 0), cl.oldmonname[0]);
    try testing.expectApproxEqAbs(@as(f32, 1), cl.opacity_animation.initial_border_color[0], 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.5), cl.opacity_animation.current_dim_color[0], 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.6), cl.scroller_proportion, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.9), cl.focused_opacity, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.7), cl.unfocused_opacity, 1e-6);
    try testing.expect(@intFromPtr(cl.link.next) == @intFromPtr(&cl.link));
    try testing.expect(@intFromPtr(cl.flink.next) == @intFromPtr(&cl.flink));
}

test "tiling order respects master and scroller preferences" {
    resetInitWorld();
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var m: Monitor = std.mem.zeroes(Monitor);
    m.pertag = &p;
    c.server.selected_monitor = &m;
    var cl: Client = std.mem.zeroes(Client);
    c.config.new_is_master = 1;
    client_insert_tiling_order(&cl);
    try testing.expect(@intFromPtr(c.server.clients.next) == @intFromPtr(&cl.link));

    resetInitWorld();
    c.server.selected_monitor = &m;
    stub_scroller = true;
    m.visible_scroll_tiling_clients = 1;
    var sel: Client = std.mem.zeroes(Client);
    sel.mon = &m;
    sel.tags = 1;
    m.tagset[0] = 1;
    m.seltags = 0;
    m.sel = &sel;
    var tail: Client = std.mem.zeroes(Client);
    listInsert(&c.server.clients, &tail.link);
    stub_scroll_tail = &tail;
    var c2: Client = std.mem.zeroes(Client);
    client_insert_tiling_order(&c2);
    try testing.expect(@intFromPtr(c2.link.prev) == @intFromPtr(&tail.link));

    resetInitWorld();
    c.server.selected_monitor = &m;
    var c3: Client = std.mem.zeroes(Client);
    client_insert_tiling_order(&c3);
    try testing.expect(@intFromPtr(c3.link.prev) == @intFromPtr(&c.server.clients));
}

test "configure size guards borders" {
    resetInitWorld();
    var cl: Client = std.mem.zeroes(Client);
    cl.bw = 2;
    client_configure_size(&cl, mkBox(0, 0, 4, 100), 2);
    try testing.expectEqual(@as(c_int, 0), stub_set_size_calls);
    client_configure_size(&cl, mkBox(0, 0, 100, 50), 2);
    try testing.expectEqual(@as(c_int, 1), stub_set_size_calls);
    try testing.expectEqual(@as(u32, 96), stub_set_size_w);
    try testing.expectEqual(@as(u32, 46), stub_set_size_h);
}

test "initial size negotiation follows floating and layout paths" {
    resetInitWorld();
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var m: Monitor = std.mem.zeroes(Monitor);
    m.pertag = &p;
    m.m = mkBox(0, 0, 1000, 800);
    m.w = m.m;
    c.server.selected_monitor = &m;
    var cl: Client = std.mem.zeroes(Client);
    cl.mon = &m;
    cl.bw = 1;
    cl.isfloating = 1;
    cl.float_geom = mkBox(0, 0, 300, 200);
    client_negotiate_initial_size(&cl, &m, 0);
    try testing.expectEqual(@as(u32, 298), stub_set_size_w);
    try testing.expectEqual(@as(u32, 198), stub_set_size_h);

    cl.isfloating = 0;
    cl.isfullscreen = 1;
    stub_set_size_calls = 0;
    client_negotiate_initial_size(&cl, &m, 0);
    try testing.expectEqual(@as(u32, 1000), stub_set_size_w);
    try testing.expectEqual(@as(u32, 800), stub_set_size_h);

    cl.isfullscreen = 0;
    cl.ismaximizescreen = 1;
    stub_set_size_calls = 0;
    client_negotiate_initial_size(&cl, &m, 0);
    try testing.expectEqual(@as(u32, 998), stub_set_size_w);

    cl.ismaximizescreen = 0;
    cl.isfloating = 0;
    var layout: c.Layout = std.mem.zeroes(c.Layout);
    layout.predict = predictFalse;
    p.ltidxs[0] = &layout;
    stub_curtag = 0;
    stub_reset_tags = 0b10;
    stub_set_size_calls = 0;
    stub_reset_tags_calls = 0;
    stub_tag_float_calls = 0;
    client_negotiate_initial_size(&cl, &m, 0b10);
    try testing.expectEqual(@as(c_int, 1), stub_reset_tags_calls);
    try testing.expectEqual(@as(c_int, 1), stub_tag_float_calls);
    try testing.expectEqual(@as(c_int, 1), stub_pre_calc_calls);
    try testing.expectEqual(@as(c_int, 0), stub_set_size_calls);
    try testing.expect(@intFromPtr(cl.link.next) == @intFromPtr(&cl.link));

    m.isoverview = 1;
    stub_reset_tags_calls = 0;
    client_negotiate_initial_size(&cl, &m, 0);
    try testing.expectEqual(@as(c_int, 0), stub_reset_tags_calls);
}
