//! Port of the client map/commit/unmap/destroy and request handlers in
//! src/manage/client.c (Phase 5, client slice 6, slice 63).

const std = @import("std");
const c = @import("cc");
const build_options = @import("build_options");

const Client = c.Client;
const Monitor = c.Monitor;
const Arg = c.Arg;
const Box = c.struct_wlr_box;

fn clientOpt(p: [*c]Client) ?*Client {
    return if (p == null) null else @ptrCast(p);
}

extern fn generate_client_id() callconv(.c) u32;
extern fn client_init_xwayland(cl: [*c]Client) callconv(.c) void;
extern fn client_init_unmanaged(cl: [*c]Client) callconv(.c) bool;
extern fn client_apply_xwayland(cl: [*c]Client) callconv(.c) void;
extern fn init_client_properties(cl: [*c]Client) callconv(.c) void;
extern fn client_apply_rules(cl: [*c]Client, rule_mon: [*c][*c]Monitor, rule_tags: [*c]u32) callconv(.c) void;
extern fn client_negotiate_initial_size(cl: [*c]Client, m: ?*Monitor, tags: u32) callconv(.c) void;
extern fn client_insert_tiling_order(cl: [*c]Client) callconv(.c) void;
extern fn client_set_monitor(cl: [*c]Client, m: [*c]Monitor, tags: u32, focus: bool) callconv(.c) void;
extern fn client_set_scale(s: [*c]c.struct_wlr_surface, scale: f32) callconv(.c) void;
extern fn client_set_tiled(cl: [*c]Client, edges: u32) callconv(.c) void;
extern fn client_update_border_color(cl: [*c]Client) callconv(.c) void;
extern fn client_add_group_bar(cl: [*c]Client) callconv(.c) void;
extern fn client_remove_group_bar(cl: [*c]Client) callconv(.c) void;
extern fn client_add_tab_bar(cl: [*c]Client) callconv(.c) void;
extern fn client_remove_tab_bar(cl: [*c]Client) callconv(.c) void;
extern fn client_update_group_bar_title(cl: [*c]Client) callconv(.c) void;
extern fn client_update_tab_bar_title(cl: [*c]Client) callconv(.c) void;
extern fn client_add_jump_label_node(cl: [*c]Client) callconv(.c) void;
extern fn client_add_dim_node(cl: [*c]Client) callconv(.c) void;
extern fn acwm_jump_label_node_destroy(node: [*c]c.AcwmJumpLabel) callconv(.c) void;
extern fn acwm_dim_node_destroy(node: [*c]c.AcwmDimNode) callconv(.c) void;
extern fn client_is_parked(cl: [*c]Client) callconv(.c) bool;
extern fn client_is_group_member(cl: [*c]const Client) callconv(.c) bool;
extern fn client_group_detach(cl: [*c]Client) callconv(.c) void;
extern fn client_replace(cl: [*c]Client, w: [*c]Client, is_group_change_member: bool, apply_rule: bool) callconv(.c) void;
extern fn client_set_maximize_screen(cl: [*c]Client, maximizescreen: i32, rearrange: bool) callconv(.c) void;
extern fn client_apply_fullscreen(cl: [*c]Client, fullscreen: i32, rearrange: bool) callconv(.c) void;
extern fn set_minimized(cl: [*c]Client) callconv(.c) void;
extern fn unminimize(cl: [*c]Client) callconv(.c) void;
extern fn set_float_malposition(cl: [*c]Client) callconv(.c) void;
extern fn resize(cl: [*c]Client, geo: Box, opts: c.ResizeOpts) callconv(.c) void;
extern fn client_focus(cl: ?*Client, lift: i32) callconv(.c) void;
extern fn client_focus_top(m: [*c]Monitor) callconv(.c) [*c]Client;
extern fn client_view_on_monitor(arg: *const Arg, want_animation: bool, m: [*c]Monitor, from_rule: bool) callconv(.c) void;
extern fn client_surface(cl: [*c]Client) callconv(.c) [*c]c.struct_wlr_surface;
extern fn client_get_geometry(cl: [*c]Client, geom: *Box) callconv(.c) void;
extern fn client_get_appid(cl: [*c]Client) callconv(.c) [*c]const u8;
extern fn client_get_title(cl: [*c]Client) callconv(.c) [*c]const u8;
extern fn client_is_x11(cl: [*c]Client) callconv(.c) i32;
extern fn client_is_unmanaged(cl: [*c]Client) callconv(.c) i32;
extern fn client_is_x11_popup(cl: [*c]Client) callconv(.c) i32;
extern fn client_should_global(cl: [*c]Client) callconv(.c) i32;
extern fn client_wants_fullscreen(cl: [*c]Client) callconv(.c) i32;
extern fn client_request_maximize(cl: [*c]Client, data: ?*anyopaque) callconv(.c) bool;
extern fn client_request_minimize(cl: [*c]Client, data: ?*anyopaque) callconv(.c) bool;
extern fn client_send_close(cl: [*c]Client) callconv(.c) void;
extern fn client_set_minimized(cl: [*c]Client, minimized: bool) callconv(.c) void;
extern fn printstatus(t: c.enum_ipc_watch_type) callconv(.c) void;
extern fn toplevel_from_wlr_surface(s: [*c]c.struct_wlr_surface, pc: [*c][*c]Client, pl: [*c][*c]c.LayerSurface) callconv(.c) i32;
extern fn tab_detach_client(cl: [*c]Client) callconv(.c) void;
extern fn switcher_remove_client(cl: [*c]Client) callconv(.c) void;
extern fn find_scroller_node(state: [*c]c.struct_TagScrollerState, cl: [*c]Client) callconv(.c) [*c]c.struct_ScrollerStackNode;
extern fn scroller_remove_client(cl: [*c]Client) callconv(.c) void;
extern fn dwindle_remove_client(cl: [*c]Client) callconv(.c) void;
extern fn client_set_drop_area(cl: [*c]Client) callconv(.c) void;
extern fn pointer_client_destroyed(cl: [*c]Client) callconv(.c) void;
extern fn pointer_process_motion(time: u32, device: [*c]c.struct_wlr_input_device, dx: f64, dy: f64, dx_unaccel: f64, dy_unaccel: f64) callconv(.c) void;
extern fn toggle_overview(arg: [*c]const Arg) callconv(.c) i32;
extern fn init_fadeout_client(cl: [*c]Client) callconv(.c) void;
extern fn overview_backup_surface(cl: [*c]Client) callconv(.c) void;
extern fn iter_xdg_scene_buffers(buffer: [*c]c.struct_wlr_scene_buffer, sx: i32, sy: i32, data: ?*anyopaque) callconv(.c) void;
extern fn wayland_string_set(dst: *c.struct_wayland_string, src: [*c]const u8) callconv(.c) [*c]const u8;
extern fn handle_xdg_decoration_mode_request(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn xwayland_apply_scale(cl: [*c]Client) callconv(.c) void;

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

fn surfaceOf(cl: *Client) [*c]c.struct_wlr_surface {
    return client_surface(cl);
}

fn setSceneEnabled(node: [*c]c.struct_wlr_scene_node, enabled: bool) void {
    if (node != null)
        c.wlr_scene_node_set_enabled(node, enabled);
}

fn createRect(parent: [*c]c.struct_wlr_scene_tree, color: [*c]const f32) [*c]c.struct_wlr_scene_rect {
    return c.wlr_scene_rect_create(parent, 0, 0, color);
}

export fn handle_client_map(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const cl = @as(*Client, @ptrFromInt(@intFromPtr(listener) - @offsetOf(Client, "map")));
    cl.id = generate_client_id();

    cl.scene = c.wlr_scene_tree_create(c.server.layers[@intCast(c.LyrTile)]);
    if (surfaceOf(cl) != null)
        surfaceOf(cl).*.data = @ptrCast(cl.scene);
    setSceneEnabled(if (cl.scene != null) &cl.scene.*.node else null, cl.type != @as(u32, @as(u32, @intCast(c.XDGShell))));
    cl.scene_surface = if (cl.type == @as(u32, @intCast(c.XDGShell)))
        c.wlr_scene_xdg_surface_create(cl.scene, cl.surface.xdg)
    else
        c.wlr_scene_subsurface_tree_create(cl.scene, surfaceOf(cl));
    _ = c.acwm_scene_node_set(if (cl.scene != null) &cl.scene.*.node else null, cl.type, cl);

    client_init_xwayland(cl);

    if (isX11(cl))
        xwayland_apply_scale(cl);
    client_get_geometry(cl, &cl.geom);

    if (isX11(cl))
        init_client_properties(cl);

    if (c.client_is_unmanaged(cl) != 0 or c.client_is_x11_popup(cl) != 0) {
        cl.bw = 0;
        cl.no_border = 1;
    } else {
        cl.bw = c.config.borderpx;
    }
    if (client_should_global(cl) != 0)
        cl.isunglobal = 1;

    cl.geom.width += 2 * @as(i32, @intCast(cl.bw));
    cl.geom.height += 2 * @as(i32, @intCast(cl.bw));
    cl.float_geom = cl.geom;
    cl.overview_backup_geom = cl.geom;

    var appid: c.struct_wayland_string = std.mem.zeroes(c.struct_wayland_string);
    var title: c.struct_wayland_string = std.mem.zeroes(c.struct_wayland_string);
    var foreign_state = std.mem.zeroes(c.struct_wlr_ext_foreign_toplevel_handle_v1_state);
    foreign_state.app_id = wayland_string_set(&appid, client_get_appid(cl));
    foreign_state.title = wayland_string_set(&title, client_get_title(cl));

    cl.image_capture_scene = c.wlr_scene_create();
    cl.ext_foreign_toplevel = c.wlr_ext_foreign_toplevel_handle_v1_create(c.server.foreign_toplevel_list, &foreign_state);
    if (cl.ext_foreign_toplevel != null)
        cl.ext_foreign_toplevel.*.data = @ptrCast(cl);

    if (isX11(cl)) {
        if (cl.image_capture_scene != null)
            cl.image_capture_scene_surface = c.wlr_scene_surface_create(&cl.image_capture_scene.*.tree, surfaceOf(cl));
    } else {
        if (cl.image_capture_scene != null)
            cl.image_capture_tree = c.wlr_scene_xdg_surface_create(&cl.image_capture_scene.*.tree, cl.surface.xdg);
    }

    if (client_init_unmanaged(cl))
        return;

    var i: usize = 0;
    while (i < 2) : (i += 1) {
        cl.splitindicator[i] = createRect(cl.scene, if (cl.isurgent != 0) &c.config.urgentcolor else &c.config.splitcolor);
        if (cl.splitindicator[i] != null) {
            c.wlr_scene_node_lower_to_bottom(&cl.splitindicator[i].*.node);
            c.wlr_scene_node_set_enabled(&cl.splitindicator[i].*.node, false);
        }
    }

    client_add_group_bar(cl);
    client_add_tab_bar(cl);
    client_add_jump_label_node(cl);
    client_add_dim_node(cl);

    cl.droparea = createRect(cl.scene, &c.config.dropcolor);
    if (cl.droparea != null) {
        c.wlr_scene_node_lower_to_bottom(&cl.droparea.*.node);
        c.wlr_scene_node_set_position(&cl.droparea.*.node, 0, 0);
        c.wlr_scene_node_set_enabled(&cl.droparea.*.node, false);
    }

    cl.border = createRect(cl.scene, if (cl.isurgent != 0) &c.config.urgentcolor else &c.config.bordercolor);
    if (cl.border != null) {
        c.wlr_scene_node_lower_to_bottom(&cl.border.*.node);
        c.wlr_scene_node_set_position(&cl.border.*.node, 0, 0);
        c.wlr_scene_rect_set_corner_radii(cl.border, c.corner_radii_all(c.config.border_radius));
        c.wlr_scene_node_set_enabled(&cl.border.*.node, true);
    }

    cl.shadow = c.wlr_scene_shadow_create(cl.scene, 0, 0, c.config.border_radius, c.config.shadows_blur, &c.config.shadowscolor);
    cl.blur = c.wlr_scene_blur_create(cl.scene, 0, 0);
    if (cl.blur != null)
        c.wlr_scene_node_lower_to_bottom(&cl.blur.*.node);
    if (cl.shadow != null) {
        c.wlr_scene_node_lower_to_bottom(&cl.shadow.*.node);
        c.wlr_scene_node_set_enabled(&cl.shadow.*.node, true);
    }

    const shield_color = [4]f32{ 0, 0, 0, 255 };
    cl.shield = createRect(cl.scene, &shield_color);
    if (cl.shield != null) {
        c.wlr_scene_node_lower_to_bottom(&cl.shield.*.node);
        c.wlr_scene_node_set_enabled(&cl.shield.*.node, false);
    }

    client_insert_tiling_order(cl);
    c.wl_list_insert(&c.server.focus_stack, &cl.flink);
    client_apply_rules(cl, null, null);
    client_apply_xwayland(cl);

    if (cl.isfloating == 0 or cl.force_tiled_state != 0)
        client_set_tiled(cl, @intCast(c.WLR_EDGE_TOP | c.WLR_EDGE_BOTTOM | c.WLR_EDGE_LEFT | c.WLR_EDGE_RIGHT));

    c.wlr_scene_node_for_each_buffer(&cl.scene_surface.*.node, iter_xdg_scene_buffers, cl);
    c.wlr_scene_node_set_position(&cl.scene_surface.*.node, @intCast(cl.bw), @intCast(cl.bw));

    client_update_border_color(cl);
    if (cl.mon != null and cl.mon.*.isoverview != 0)
        overview_backup_surface(cl);

    cl.is_pending_open_animation = true;
    var opts = std.mem.zeroes(c.ResizeOpts);
    opts.interact = false;
    resize(cl, cl.geom, opts);
    printstatus(@intCast(c.IPC_WATCH_ARRANGGE));
}

fn clientXdgSizePending(cl: *Client) bool {
    const toplevel = cl.surface.xdg.*.unnamed_0.toplevel;
    if (toplevel == null)
        return false;
    const state = toplevel.*.current;
    const bw: i32 = @intCast(cl.bw);
    return state.width != cl.geom.width - 2 * bw or
        state.height != cl.geom.height - 2 * bw;
}

export fn handle_client_commit(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const cl = @as(*Client, @ptrFromInt(@intFromPtr(listener) - @offsetOf(Client, "commit")));
    if (cl.surface.xdg == null)
        return;

    if (cl.surface.xdg.*.initial_commit) {
        init_client_properties(cl);
        var rule_mon: [*c]Monitor = null;
        var rule_tags: u32 = 0;
        client_apply_rules(cl, &rule_mon, &rule_tags);
        client_negotiate_initial_size(cl, if (rule_mon != null) @as(*Monitor, @ptrCast(rule_mon)) else null, rule_tags);
        if (cl.mon != null and cl.mon.*.wlr_output != null)
            client_set_scale(surfaceOf(cl), cl.mon.*.wlr_output.*.scale);
        client_set_monitor(cl, null, 0, true);

        const serial = c.wlr_xdg_surface_schedule_configure(cl.surface.xdg);
        if (serial > 0)
            cl.configure_serial = serial;

        var wm_caps: u32 = @intCast(c.WLR_XDG_TOPLEVEL_WM_CAPABILITIES_FULLSCREEN);
        if (cl.ignore_minimize == 0)
            wm_caps |= @as(u32, @intCast(c.WLR_XDG_TOPLEVEL_WM_CAPABILITIES_MINIMIZE));
        if (cl.ignore_maximize == 0)
            wm_caps |= @as(u32, @intCast(c.WLR_XDG_TOPLEVEL_WM_CAPABILITIES_MAXIMIZE));
        if (cl.surface.xdg.*.unnamed_0.toplevel != null) {
            const toplevel = cl.surface.xdg.*.unnamed_0.toplevel;
            _ = c.wlr_xdg_toplevel_set_wm_capabilities(toplevel, wm_caps);
            if (cl.mon != null) {
                _ = c.wlr_xdg_toplevel_set_bounds(
                    toplevel,
                    @as(i32, @intCast(cl.mon.*.w.width - 2 * @as(i32, @intCast(cl.bw)))),
                    @as(i32, @intCast(cl.mon.*.w.height - 2 * @as(i32, @intCast(cl.bw)))),
                );
            }
        }
        if (cl.decoration != null)
            handle_xdg_decoration_mode_request(&cl.set_decoration_mode, cl.decoration);
        return;
    }

    if (client_is_parked(cl))
        return;
    if (cl.iskilling != 0 or cl.animation.tagouting or cl.animation.tagouted or cl.animation.tagining)
        return;
    if (cl.configure_serial != 0 and cl.configure_serial <= cl.surface.xdg.*.current.configure_serial)
        cl.configure_serial = 0;

    if (!cl.dirty) {
        const new_geo = &cl.surface.xdg.*.geometry;
        cl.dirty = clientXdgSizePending(cl) or new_geo.x != cl.xdg_geo_x or new_geo.y != cl.xdg_geo_y;
    }
    if (c.server.grab_client != null and cl == c.server.grab_client)
        return;
    if (!cl.dirty)
        return;

    var opts = std.mem.zeroes(c.ResizeOpts);
    opts.interact = false;
    resize(cl, cl.geom, opts);

    const new_geo = &cl.surface.xdg.*.geometry;
    cl.xdg_geo_x = new_geo.x;
    cl.xdg_geo_y = new_geo.y;
    cl.dirty = clientXdgSizePending(cl);
}

export fn handle_client_unmap(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const cl = @as(*Client, @ptrFromInt(@intFromPtr(listener) - @offsetOf(Client, "unmap")));
    cl.iskilling = 1;
    if (cl.tab_prev != null or cl.tab_next != null)
        tab_detach_client(cl);
    switcher_remove_client(cl);

    var target_node: [*c]c.struct_ScrollerStackNode = null;
    if (cl.mon != null and cl.mon.*.pertag != null)
        target_node = find_scroller_node(cl.mon.*.pertag.*.scroller_state[@intCast(getClientTagIdx(cl))], cl);
    const prev_node = if (target_node != null) target_node.*.prev_in_stack else null;
    const next_node = if (target_node != null) target_node.*.next_in_stack else null;

    if (c.config.animations != 0 and !client_is_parked(cl) and !cl.is_clip_to_hide and
        cl.isminimized == 0 and (cl.mon == null or VISIBLEON(cl, cl.mon)))
        init_fadeout_client(cl);

    if (cl.swallowing != null) {
        cl.swallowing.*.mon = cl.mon;
        client_replace(cl.swallowing, cl, false, true);
    } else if (client_is_group_member(cl) and cl.is_group_focus) {
        const replacement = if (cl.group_next != null) cl.group_next else cl.group_prev;
        replacement.*.mon = cl.mon;
        client_replace(replacement, cl, false, false);
    } else {
        scroller_remove_client(cl);
        dwindle_remove_client(cl);
    }

    if (c.server.grab_client != null and @intFromPtr(c.server.grab_client) == @intFromPtr(cl)) {
        c.server.cursor_mode = c.CurNormal;
        c.server.grab_client = null;
        if (c.server.drop_client != null) {
            c.server.drop_client.*.enable_drop_area_draw = false;
            client_set_drop_area(c.server.drop_client);
            c.server.drop_client = null;
        }
    }
    if (c.server.drop_client != null and @intFromPtr(c.server.drop_client) == @intFromPtr(cl))
        c.server.drop_client = null;

    var pos = c.server.monitors.next;
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.monitors);
    while (pos != head) : (pos = pos.*.next) {
        const m = @as(*Monitor, @ptrFromInt(@intFromPtr(pos) - @offsetOf(Monitor, "link")));
        if (m.wlr_output == null or !m.wlr_output.*.enabled)
            continue;
        if (cl == m.sel)
            m.sel = null;
        if (cl == m.prevsel)
            m.prevsel = null;
    }

    if (cl.mon != null and cl.mon == c.server.selected_monitor) {
        var nextfocus: [*c]Client = null;
        if (next_node != null and cl.swallowing == null) {
            nextfocus = next_node.*.client;
        } else if (prev_node != null and cl.swallowing == null) {
            nextfocus = prev_node.*.client;
        } else {
            nextfocus = client_focus_top(c.server.selected_monitor);
        }
        if (nextfocus != null and !VISIBLEON(nextfocus, c.server.selected_monitor))
            nextfocus = client_focus_top(c.server.selected_monitor);
        if (nextfocus != null)
            client_focus(nextfocus, 1);
        if (nextfocus == null and c.server.selected_monitor.*.isoverview != 0) {
            var arg = std.mem.zeroes(Arg);
            _ = toggle_overview(&arg);
        }
    }

    if (build_options.xwayland and isX11(cl)) {
        if (cl.commmitx11.link.prev != null and cl.commmitx11.link.next != null and
            cl.commmitx11.link.prev != &cl.commmitx11.link)
        {
            c.wl_list_remove(&cl.commmitx11.link);
            c.wl_list_init(&cl.commmitx11.link);
        }
    }

    if (c.client_is_unmanaged(cl) != 0) {
        if (build_options.xwayland and isX11(cl)) {
            if (cl.set_geometry.link.prev != null and cl.set_geometry.link.next != null and
                cl.set_geometry.link.prev != &cl.set_geometry.link)
            {
                c.wl_list_remove(&cl.set_geometry.link);
                c.wl_list_init(&cl.set_geometry.link);
            }
        }
        if (c.server.exclusive_focus != null and @intFromPtr(c.server.exclusive_focus.?) == @intFromPtr(cl))
            c.server.exclusive_focus = null;
        if (c.server.seat != null and surfaceOf(cl) == c.server.seat.*.keyboard_state.focused_surface)
            client_focus(client_focus_top(c.server.selected_monitor), 1);
    } else {
        client_group_detach(cl);
        if (c.wl_list_empty(&cl.link) == 0)
            c.wl_list_remove(&cl.link);
        client_set_monitor(cl, null, 0, true);
        if (c.wl_list_empty(&cl.flink) == 0)
            c.wl_list_remove(&cl.flink);
    }

    if (cl.foreign_toplevel != null) {
        c.wlr_foreign_toplevel_handle_v1_destroy(cl.foreign_toplevel);
        cl.foreign_toplevel = null;
    }
    if (cl.ext_foreign_toplevel != null) {
        c.wlr_ext_foreign_toplevel_handle_v1_destroy(cl.ext_foreign_toplevel);
        cl.ext_foreign_toplevel = null;
    }

    if (cl.swallowing != null) {
        client_set_maximize_screen(cl.swallowing, cl.ismaximizescreen, true);
        client_apply_fullscreen(cl.swallowing, cl.isfullscreen, true);
        cl.swallowing.*.swallowdby = null;
        cl.swallowing = null;
    }
    if (cl.swallowdby != null) {
        cl.swallowdby.*.swallowing = null;
        cl.swallowdby = null;
    }

    if (cl.jump_label_node != null) {
        acwm_jump_label_node_destroy(cl.jump_label_node);
        cl.jump_label_node = null;
    }
    client_remove_group_bar(cl);
    client_remove_tab_bar(cl);
    if (cl.dim_node != null) {
        acwm_dim_node_destroy(cl.dim_node);
        cl.dim_node = null;
    }
    if (cl.image_capture_scene != null) {
        c.wlr_scene_node_destroy(&cl.image_capture_scene.*.tree.node);
        cl.image_capture_scene = null;
    }

    init_client_properties(cl);
    if (cl.scene != null)
        c.wlr_scene_node_destroy(&cl.scene.*.node);
    printstatus(@intCast(c.IPC_WATCH_ARRANGGE));
    pointer_process_motion(0, null, 0, 0, 0, 0);
}

fn getClientTagIdx(cl: *Client) u32 {
    return c.get_client_tag_idx(cl);
}

export fn handle_client_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const cl = @as(*Client, @ptrFromInt(@intFromPtr(listener) - @offsetOf(Client, "destroy")));
    c.wl_list_remove(&cl.destroy.link);
    c.wl_list_remove(&cl.set_title.link);
    c.wl_list_remove(&cl.fullscreen.link);
    c.wl_list_remove(&cl.maximize.link);
    c.wl_list_remove(&cl.minimize.link);
    if (build_options.xwayland and cl.type != @as(u32, @intCast(c.XDGShell))) {
        c.wl_list_remove(&cl.activate.link);
        c.wl_list_remove(&cl.associate.link);
        c.wl_list_remove(&cl.configure.link);
        c.wl_list_remove(&cl.dissociate.link);
        c.wl_list_remove(&cl.set_hints.link);
    } else {
        c.wl_list_remove(&cl.commit.link);
        c.wl_list_remove(&cl.map.link);
        c.wl_list_remove(&cl.unmap.link);
    }
    if (cl.decoration != null) {
        c.wl_list_remove(&cl.destroy_decoration.link);
        c.wl_list_remove(&cl.set_decoration_mode.link);
    }
    switcher_remove_client(cl);
    pointer_client_destroyed(cl);
    c.free(cl);
}

export fn handle_client_request_fullscreen(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const cl = @as(*Client, @ptrFromInt(@intFromPtr(listener) - @offsetOf(Client, "fullscreen")));
    if (cl.iskilling != 0 or client_is_parked(cl))
        return;
    client_apply_fullscreen(cl, client_wants_fullscreen(cl), true);
}

export fn handle_client_request_maximize(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    const cl = @as(*Client, @ptrFromInt(@intFromPtr(listener) - @offsetOf(Client, "maximize")));
    if (cl.mon == null or cl.iskilling != 0 or cl.ignore_maximize != 0 or client_is_parked(cl))
        return;
    if (client_is_x11(cl) == 0 and (cl.surface.xdg == null or !cl.surface.xdg.*.initialized))
        return;
    if (client_request_maximize(cl, data))
        client_set_maximize_screen(cl, 1, true)
    else
        client_set_maximize_screen(cl, 0, true);
}

export fn handle_client_request_minimize(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    const cl = @as(*Client, @ptrFromInt(@intFromPtr(listener) - @offsetOf(Client, "minimize")));
    if (cl.mon == null or cl.iskilling != 0 or cl.isminimized != 0 or client_is_parked(cl))
        return;
    if (client_request_minimize(cl, data) and cl.ignore_minimize == 0) {
        if (cl.isminimized == 0)
            set_minimized(cl);
        client_set_minimized(cl, true);
    } else {
        if (cl.isminimized != 0)
            unminimize(cl);
        client_set_minimized(cl, false);
    }
}

export fn handle_client_set_title(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const cl = @as(*Client, @ptrFromInt(@intFromPtr(listener) - @offsetOf(Client, "set_title")));
    if (cl.iskilling != 0)
        return;
    const title = client_get_title(cl);
    client_update_group_bar_title(cl);
    client_update_tab_bar_title(cl);

    var wayland_title: c.struct_wayland_string = std.mem.zeroes(c.struct_wayland_string);
    const clamped = wayland_string_set(&wayland_title, title);
    if (cl.foreign_toplevel != null)
        c.wlr_foreign_toplevel_handle_v1_set_title(cl.foreign_toplevel, clamped);
    if (cl.ext_foreign_toplevel != null) {
        var state = std.mem.zeroes(c.struct_wlr_ext_foreign_toplevel_handle_v1_state);
        state.title = clamped;
        state.app_id = cl.ext_foreign_toplevel.*.app_id;
        c.wlr_ext_foreign_toplevel_handle_v1_update_state(cl.ext_foreign_toplevel, &state);
    }
    if (c.client_focus_top(cl.mon) == cl)
        printstatus(@intCast(c.IPC_WATCH_ARRANGGE));
}

export fn handle_client_activation_request(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as(*c.struct_wlr_xdg_activation_v1_request_activate_event, @ptrCast(@alignCast(data.?)));
    var cl_ptr: [*c]Client = null;
    _ = toplevel_from_wlr_surface(event.surface, &cl_ptr, null);
    const cl = clientOpt(cl_ptr);
    if (cl == null or cl.?.foreign_toplevel == null)
        return;

    if (c.config.focus_on_activate != 0 and cl.?.istagsilent == 0 and
        (c.server.selected_monitor == null or cl != c.server.selected_monitor.*.sel))
    {
        if (!(cl.?.mon == c.server.selected_monitor and
            (cl.?.tags & cl.?.mon.*.tagset[cl.?.mon.*.seltags]) != 0))
        {
            var arg = std.mem.zeroes(Arg);
            arg.ui = cl.?.tags;
            client_view_on_monitor(&arg, true, cl.?.mon, true);
        }
        client_focus(cl.?, 1);
    } else if (cl != client_focus_top(c.server.selected_monitor)) {
        cl.?.isurgent = 1;
        if (surfaceOf(cl.?) != null and surfaceOf(cl.?).*.mapped)
            client_update_border_color(cl.?);
        printstatus(@intCast(c.IPC_WATCH_ARRANGGE));
    }
}

export fn pending_kill_client(cl: ?*Client) callconv(.c) void {
    const client = cl orelse return;
    if (client.iskilling != 0)
        return;
    client_send_close(client);
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/client_lifecycle_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_list_insert_calls: c_int;
extern var stub_list_remove_calls: c_int;
extern var stub_generate_id_calls: c_int;
extern var stub_init_xwayland_calls: c_int;
extern var stub_unmanaged: bool;
extern var stub_apply_xwayland_calls: c_int;
extern var stub_init_props_calls: c_int;
extern var stub_apply_rules_calls: c_int;
extern var stub_insert_tiling_calls: c_int;
extern var stub_negotiate_calls: c_int;
extern var stub_set_monitor_calls: c_int;
extern var stub_scale_calls: c_int;
extern var stub_set_tiled_calls: c_int;
extern var stub_tiled_edges: u32;
extern var stub_border_color_calls: c_int;
extern var stub_group_bar_add: c_int;
extern var stub_group_bar_remove: c_int;
extern var stub_tab_bar_add: c_int;
extern var stub_tab_bar_remove: c_int;
extern var stub_group_title_calls: c_int;
extern var stub_tab_title_calls: c_int;
extern var stub_jump_add: c_int;
extern var stub_jump_destroy: c_int;
extern var stub_dim_add: c_int;
extern var stub_dim_destroy: c_int;
extern var stub_parked: bool;
extern var stub_group_member: bool;
extern var stub_group_detach_calls: c_int;
extern var stub_replace_calls: c_int;
extern var stub_maximize_screen_calls: c_int;
extern var stub_fullscreen_calls: c_int;
extern var stub_fullscreen_value: i32;
extern var stub_minimize_client_calls: c_int;
extern var stub_unminimize_calls: c_int;
extern var stub_set_minimized_calls: c_int;
extern var stub_resize_calls: c_int;
extern var stub_focus_calls: c_int;
extern var stub_top_client: [*c]Client;
extern var stub_view_calls: c_int;
extern var stub_surface: [*c]c.struct_wlr_surface;
extern var stub_geom: Box;
extern var stub_appid: [*c]const u8;
extern var stub_title: [*c]const u8;
extern var stub_x11: i32;
extern var stub_unmanaged_flag: i32;
extern var stub_x11_popup: i32;
extern var stub_should_global: i32;
extern var stub_wants_fs: i32;
extern var stub_request_max: bool;
extern var stub_request_min: bool;
extern var stub_send_close_calls: c_int;
extern var stub_toplevel_client: [*c]Client;
extern var stub_tab_detach_calls: c_int;
extern var stub_switcher_remove_calls: c_int;
extern var stub_scroller_node: [*c]c.struct_ScrollerStackNode;
extern var stub_scroller_remove_calls: c_int;
extern var stub_dwindle_remove_calls: c_int;
extern var stub_drop_area_calls: c_int;
extern var stub_pointer_destroyed_calls: c_int;
extern var stub_pointer_motion_calls: c_int;
extern var stub_toggle_overview_calls: c_int;
extern var stub_fadeout_calls: c_int;
extern var stub_backup_surface_calls: c_int;
extern var stub_iter_buffers_calls: c_int;
extern var stub_deco_request_calls: c_int;
extern var stub_xwayland_scale_calls: c_int;
extern var stub_printstatus_calls: c_int;
extern var stub_tree_next: c_int;
extern var stub_rect_next: c_int;
extern var stub_rect_calls: c_int;
extern var stub_shadow_calls: c_int;
extern var stub_node_enable_calls: c_int;
extern var stub_node_pos_calls: c_int;
extern var stub_node_destroy_calls: c_int;
extern var stub_for_each_calls: c_int;
extern var stub_scene: c.struct_wlr_scene;
extern var stub_ext_handle: c.struct_wlr_ext_foreign_toplevel_handle_v1;
extern var stub_ft_set_title_calls: c_int;
extern var stub_schedule_serial: u32;
extern var stub_wm_caps_calls: c_int;
extern var stub_wm_caps: u32;
extern var stub_bounds_calls: c_int;

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

fn resetLifecycleWorld2() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    listInit(&c.server.clients);
    listInit(&c.server.monitors);
    listInit(&c.server.focus_stack);
    c.config.borderpx = 2;
    c.server.tagmask = 0xffffffff;
    stub_list_insert_calls = 0;
    stub_list_remove_calls = 0;
    stub_generate_id_calls = 0;
    stub_init_xwayland_calls = 0;
    stub_unmanaged = false;
    stub_apply_xwayland_calls = 0;
    stub_init_props_calls = 0;
    stub_apply_rules_calls = 0;
    stub_insert_tiling_calls = 0;
    stub_negotiate_calls = 0;
    stub_set_monitor_calls = 0;
    stub_scale_calls = 0;
    stub_set_tiled_calls = 0;
    stub_tiled_edges = 0;
    stub_border_color_calls = 0;
    stub_group_bar_add = 0;
    stub_group_bar_remove = 0;
    stub_tab_bar_add = 0;
    stub_tab_bar_remove = 0;
    stub_group_title_calls = 0;
    stub_tab_title_calls = 0;
    stub_jump_add = 0;
    stub_jump_destroy = 0;
    stub_dim_add = 0;
    stub_dim_destroy = 0;
    stub_parked = false;
    stub_group_member = false;
    stub_group_detach_calls = 0;
    stub_replace_calls = 0;
    stub_maximize_screen_calls = 0;
    stub_fullscreen_calls = 0;
    stub_fullscreen_value = -1;
    stub_minimize_client_calls = 0;
    stub_unminimize_calls = 0;
    stub_set_minimized_calls = 0;
    stub_resize_calls = 0;
    stub_focus_calls = 0;
    stub_top_client = null;
    stub_view_calls = 0;
    stub_surface = null;
    stub_geom = std.mem.zeroes(Box);
    stub_appid = "app";
    stub_title = "title";
    stub_x11 = 0;
    stub_unmanaged_flag = 0;
    stub_x11_popup = 0;
    stub_should_global = 0;
    stub_wants_fs = 0;
    stub_request_max = false;
    stub_request_min = false;
    stub_send_close_calls = 0;
    stub_toplevel_client = null;
    stub_tab_detach_calls = 0;
    stub_switcher_remove_calls = 0;
    stub_scroller_node = null;
    stub_scroller_remove_calls = 0;
    stub_dwindle_remove_calls = 0;
    stub_drop_area_calls = 0;
    stub_pointer_destroyed_calls = 0;
    stub_pointer_motion_calls = 0;
    stub_toggle_overview_calls = 0;
    stub_fadeout_calls = 0;
    stub_backup_surface_calls = 0;
    stub_iter_buffers_calls = 0;
    stub_deco_request_calls = 0;
    stub_xwayland_scale_calls = 0;
    stub_printstatus_calls = 0;
    stub_tree_next = 0;
    stub_rect_next = 0;
    stub_rect_calls = 0;
    stub_shadow_calls = 0;
    stub_node_enable_calls = 0;
    stub_node_pos_calls = 0;
    stub_node_destroy_calls = 0;
    stub_for_each_calls = 0;
    stub_ft_set_title_calls = 0;
    stub_schedule_serial = 5;
    stub_wm_caps_calls = 0;
    stub_wm_caps = 0;
    stub_bounds_calls = 0;
}

fn baseClient(cl: *Client, xdg: *c.struct_wlr_xdg_surface, toplevel: *c.struct_wlr_xdg_toplevel, surface: *c.struct_wlr_surface) void {
    cl.* = std.mem.zeroes(Client);
    xdg.* = std.mem.zeroes(c.struct_wlr_xdg_surface);
    toplevel.* = std.mem.zeroes(c.struct_wlr_xdg_toplevel);
    surface.* = std.mem.zeroes(c.struct_wlr_surface);
    cl.type = @intCast(c.XDGShell);
    cl.surface.xdg = xdg;
    xdg.surface = surface;
    xdg.unnamed_0.toplevel = toplevel;
    toplevel.base = xdg;
    stub_surface = surface;
}

test "map creates scene wiring and honours unmanaged early return" {
    resetLifecycleWorld2();
    var cl: Client = undefined;
    var xdg: c.struct_wlr_xdg_surface = undefined;
    var toplevel: c.struct_wlr_xdg_toplevel = undefined;
    var surface: c.struct_wlr_surface = undefined;
    baseClient(&cl, &xdg, &toplevel, &surface);
    stub_unmanaged = true;
    stub_geom = mkBox(10, 20, 100, 50);

    handle_client_map(&cl.map, null);
    try testing.expectEqual(@as(u32, 42), cl.id);
    try testing.expect(cl.scene != null);
    try testing.expect(surface.data == @as(?*anyopaque, @ptrCast(cl.scene)));
    try testing.expectEqual(@as(c_int, 1), stub_generate_id_calls);
    try testing.expectEqual(@as(c_int, 1), stub_init_xwayland_calls);
    try testing.expect(cl.image_capture_scene != null);
    try testing.expect(cl.ext_foreign_toplevel != null);
    try testing.expectEqual(@as(c_int, 0), stub_rect_calls);
    try testing.expectEqual(@as(c_int, 0), stub_group_bar_add);
    try testing.expectEqual(@as(c_int, 0), stub_resize_calls);
    try testing.expectEqual(@as(c_int, 0), stub_printstatus_calls);
}

test "map builds borders, bars and applies rules for managed clients" {
    resetLifecycleWorld2();
    var cl: Client = undefined;
    var xdg: c.struct_wlr_xdg_surface = undefined;
    var toplevel: c.struct_wlr_xdg_toplevel = undefined;
    var surface: c.struct_wlr_surface = undefined;
    baseClient(&cl, &xdg, &toplevel, &surface);
    stub_geom = mkBox(10, 20, 100, 50);
    stub_should_global = 1;

    handle_client_map(&cl.map, null);
    try testing.expectEqual(@as(u32, 2), cl.bw);
    try testing.expectEqual(@as(i32, 104), cl.geom.width);
    try testing.expectEqual(@as(i32, 54), cl.geom.height);
    try testing.expectEqual(@as(i32, 1), cl.isunglobal);
    try testing.expectEqual(@as(c_int, 5), stub_rect_calls);
    try testing.expectEqual(@as(c_int, 1), stub_shadow_calls);
    try testing.expectEqual(@as(c_int, 1), stub_group_bar_add);
    try testing.expectEqual(@as(c_int, 1), stub_tab_bar_add);
    try testing.expectEqual(@as(c_int, 1), stub_jump_add);
    try testing.expectEqual(@as(c_int, 1), stub_dim_add);
    try testing.expectEqual(@as(c_int, 1), stub_insert_tiling_calls);
    try testing.expectEqual(@as(c_int, 1), stub_apply_rules_calls);
    try testing.expectEqual(@as(c_int, 1), stub_apply_xwayland_calls);
    try testing.expectEqual(@as(c_int, 1), stub_set_tiled_calls);
    try testing.expectEqual(@as(u32, 15), stub_tiled_edges);
    try testing.expectEqual(@as(c_int, 1), stub_for_each_calls);
    try testing.expectEqual(@as(c_int, 1), stub_border_color_calls);
    try testing.expectEqual(@as(c_int, 1), stub_resize_calls);
    try testing.expectEqual(@as(c_int, 1), stub_printstatus_calls);
}

test "commit handles initial configuration and dirty relocation" {
    resetLifecycleWorld2();
    var cl: Client = undefined;
    var xdg: c.struct_wlr_xdg_surface = undefined;
    var toplevel: c.struct_wlr_xdg_toplevel = undefined;
    var surface: c.struct_wlr_surface = undefined;
    baseClient(&cl, &xdg, &toplevel, &surface);
    var mon: Monitor = std.mem.zeroes(Monitor);
    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    out.scale = 2.0;
    mon.wlr_output = &out;
    mon.w = mkBox(0, 0, 1000, 800);
    cl.mon = &mon;
    cl.bw = 2;
    cl.ignore_minimize = 0;
    cl.ignore_maximize = 0;
    cl.decoration = @ptrFromInt(0x1000);
    xdg.initial_commit = true;

    handle_client_commit(&cl.commit, null);
    try testing.expectEqual(@as(c_int, 1), stub_init_props_calls);
    try testing.expectEqual(@as(c_int, 1), stub_apply_rules_calls);
    try testing.expectEqual(@as(c_int, 1), stub_negotiate_calls);
    try testing.expectEqual(@as(c_int, 1), stub_scale_calls);
    try testing.expectEqual(@as(c_int, 1), stub_set_monitor_calls);
    try testing.expectEqual(@as(u32, 5), cl.configure_serial);
    try testing.expectEqual(@as(c_int, 1), stub_wm_caps_calls);
    const expected_caps: u32 = @as(u32, @intCast(c.WLR_XDG_TOPLEVEL_WM_CAPABILITIES_FULLSCREEN)) |
        @as(u32, @intCast(c.WLR_XDG_TOPLEVEL_WM_CAPABILITIES_MINIMIZE)) |
        @as(u32, @intCast(c.WLR_XDG_TOPLEVEL_WM_CAPABILITIES_MAXIMIZE));
    try testing.expectEqual(expected_caps, stub_wm_caps);
    try testing.expectEqual(@as(c_int, 1), stub_bounds_calls);
    try testing.expectEqual(@as(c_int, 1), stub_deco_request_calls);

    xdg.initial_commit = false;
    cl.dirty = false;
    cl.configure_serial = 2;
    xdg.current.configure_serial = 3;
    xdg.geometry = mkBox(1, 2, 50, 50);
    cl.xdg_geo_x = 0;
    cl.xdg_geo_y = 0;
    cl.geom = mkBox(0, 0, 104, 54);
    toplevel.current.width = 100;
    toplevel.current.height = 50;
    handle_client_commit(&cl.commit, null);
    try testing.expectEqual(@as(u32, 0), cl.configure_serial);
    try testing.expectEqual(@as(c_int, 1), stub_resize_calls);
    try testing.expectEqual(@as(i32, 1), cl.xdg_geo_x);
    try testing.expect(!cl.dirty);

    cl.iskilling = 1;
    stub_resize_calls = 0;
    handle_client_commit(&cl.commit, null);
    try testing.expectEqual(@as(c_int, 0), stub_resize_calls);
}

test "unmap detaches stacks, focus and scene nodes" {
    resetLifecycleWorld2();
    var cl: Client = undefined;
    var xdg: c.struct_wlr_xdg_surface = undefined;
    var toplevel: c.struct_wlr_xdg_toplevel = undefined;
    var surface: c.struct_wlr_surface = undefined;
    baseClient(&cl, &xdg, &toplevel, &surface);
    var mon: Monitor = std.mem.zeroes(Monitor);
    mon.tagset[0] = 1;
    mon.seltags = 0;
    cl.mon = &mon;
    c.server.selected_monitor = &mon;
    listInsert(&c.server.monitors, &mon.link);
    listInsert(&c.server.clients, &cl.link);
    listInsert(&c.server.focus_stack, &cl.flink);
    cl.tab_prev = @ptrFromInt(0x1000);
    cl.scene = @ptrFromInt(0x1000);
    var image_scene: c.struct_wlr_scene = std.mem.zeroes(c.struct_wlr_scene);
    cl.image_capture_scene = &image_scene;
    cl.foreign_toplevel = @ptrFromInt(0x2000);
    cl.ext_foreign_toplevel = &stub_ext_handle;
    cl.jump_label_node = @ptrFromInt(0x3000);
    cl.dim_node = @ptrFromInt(0x4000);

    handle_client_unmap(&cl.unmap, null);
    try testing.expectEqual(@as(i32, 1), cl.iskilling);
    try testing.expectEqual(@as(c_int, 1), stub_tab_detach_calls);
    try testing.expectEqual(@as(c_int, 1), stub_switcher_remove_calls);
    try testing.expectEqual(@as(c_int, 1), stub_scroller_remove_calls);
    try testing.expectEqual(@as(c_int, 1), stub_dwindle_remove_calls);
    try testing.expectEqual(@as(c_int, 1), stub_group_detach_calls);
    try testing.expectEqual(@as(c_int, 1), stub_set_monitor_calls);
    try testing.expectEqual(@as(c_int, 1), stub_jump_destroy);
    try testing.expectEqual(@as(c_int, 1), stub_dim_destroy);
    try testing.expectEqual(@as(c_int, 1), stub_group_bar_remove);
    try testing.expectEqual(@as(c_int, 1), stub_tab_bar_remove);
    try testing.expectEqual(@as(c_int, 2), stub_node_destroy_calls);
    try testing.expectEqual(@as(c_int, 1), stub_pointer_motion_calls);
    try testing.expectEqual(@as(c_int, 1), stub_printstatus_calls);
    try testing.expect(cl.foreign_toplevel == null);
    try testing.expect(cl.ext_foreign_toplevel == null);
    try testing.expect(cl.image_capture_scene == null);
}

test "unmap transfers swallow state and overview fallback" {
    resetLifecycleWorld2();
    var cl: Client = undefined;
    var xdg: c.struct_wlr_xdg_surface = undefined;
    var toplevel: c.struct_wlr_xdg_toplevel = undefined;
    var surface: c.struct_wlr_surface = undefined;
    baseClient(&cl, &xdg, &toplevel, &surface);
    var mon: Monitor = std.mem.zeroes(Monitor);
    mon.isoverview = 1;
    cl.mon = &mon;
    c.server.selected_monitor = &mon;
    var swallow: Client = std.mem.zeroes(Client);
    cl.swallowing = &swallow;
    swallow.mon = &mon;
    cl.ismaximizescreen = 1;
    cl.isfullscreen = 1;
    cl.scene = @ptrFromInt(0x1000);
    listInsert(&c.server.clients, &cl.link);
    listInsert(&c.server.focus_stack, &cl.flink);

    handle_client_unmap(&cl.unmap, null);
    try testing.expectEqual(@as(c_int, 1), stub_replace_calls);
    try testing.expectEqual(@as(c_int, 1), stub_maximize_screen_calls);
    try testing.expectEqual(@as(c_int, 1), stub_fullscreen_calls);
    try testing.expectEqual(@as(i32, 1), stub_fullscreen_value);
    try testing.expect(swallow.swallowdby == null);
    try testing.expect(cl.swallowing == null);
    try testing.expectEqual(@as(c_int, 1), stub_toggle_overview_calls);
}

test "destroy removes listeners and frees the client" {
    resetLifecycleWorld2();
    const cl: *Client = @ptrCast(@alignCast(c.ecalloc(1, @sizeOf(Client)) orelse unreachable));
    cl.type = @intCast(c.XDGShell);
    cl.destroy.link = selfLink();
    cl.set_title.link = selfLink();
    cl.fullscreen.link = selfLink();
    cl.maximize.link = selfLink();
    cl.minimize.link = selfLink();
    cl.commit.link = selfLink();
    cl.map.link = selfLink();
    cl.unmap.link = selfLink();
    cl.decoration = @ptrFromInt(0x1000);
    cl.destroy_decoration.link = selfLink();
    cl.set_decoration_mode.link = selfLink();

    handle_client_destroy(&cl.destroy, null);
    try testing.expectEqual(@as(c_int, 10), stub_list_remove_calls);
    try testing.expectEqual(@as(c_int, 1), stub_switcher_remove_calls);
    try testing.expectEqual(@as(c_int, 1), stub_pointer_destroyed_calls);
}

fn selfLink() c.struct_wl_list {
    var link: c.struct_wl_list = undefined;
    link.next = &link;
    link.prev = &link;
    return link;
}

test "request handlers apply state and activation urgency" {
    resetLifecycleWorld2();
    var cl: Client = std.mem.zeroes(Client);
    stub_wants_fs = 1;
    handle_client_request_fullscreen(&cl.fullscreen, null);
    try testing.expectEqual(@as(c_int, 1), stub_fullscreen_calls);
    try testing.expectEqual(@as(i32, 1), stub_fullscreen_value);

    var mon: Monitor = std.mem.zeroes(Monitor);
    cl.mon = &mon;
    var mx: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    var mt: c.struct_wlr_xdg_toplevel = std.mem.zeroes(c.struct_wlr_xdg_toplevel);
    mx.initialized = true;
    mx.unnamed_0.toplevel = &mt;
    cl.surface.xdg = &mx;
    stub_request_max = true;
    handle_client_request_maximize(&cl.maximize, null);
    try testing.expectEqual(@as(c_int, 1), stub_maximize_screen_calls);

    stub_request_min = true;
    cl.ignore_minimize = 0;
    handle_client_request_minimize(&cl.minimize, null);
    try testing.expectEqual(@as(c_int, 1), stub_minimize_client_calls);
    try testing.expectEqual(@as(c_int, 1), stub_set_minimized_calls);

    cl.isminimized = 0;
    stub_request_min = false;
    handle_client_request_minimize(&cl.minimize, null);
    try testing.expectEqual(@as(c_int, 0), stub_unminimize_calls);
    try testing.expectEqual(@as(c_int, 2), stub_set_minimized_calls);

    var xdg: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    var toplevel: c.struct_wlr_xdg_toplevel = std.mem.zeroes(c.struct_wlr_xdg_toplevel);
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    baseClient(&cl, &xdg, &toplevel, &surface);
    cl.foreign_toplevel = @ptrFromInt(0x1000);
    cl.ext_foreign_toplevel = &stub_ext_handle;
    cl.mon = &mon;
    c.server.selected_monitor = &mon;
    handle_client_set_title(&cl.set_title, null);
    try testing.expectEqual(@as(c_int, 1), stub_group_title_calls);
    try testing.expectEqual(@as(c_int, 1), stub_tab_title_calls);
    try testing.expectEqual(@as(c_int, 1), stub_ft_set_title_calls);

    stub_toplevel_client = &cl;
    var event: c.struct_wlr_xdg_activation_v1_request_activate_event = std.mem.zeroes(c.struct_wlr_xdg_activation_v1_request_activate_event);
    c.config.focus_on_activate = 1;
    cl.istagsilent = 0;
    cl.mon = &mon;
    cl.tags = 1;
    mon.tagset[0] = 2;
    mon.seltags = 0;
    mon.sel = null;
    handle_client_activation_request(null, &event);
    try testing.expectEqual(@as(c_int, 1), stub_view_calls);
    try testing.expectEqual(@as(c_int, 1), stub_focus_calls);

    c.config.focus_on_activate = 0;
    handle_client_activation_request(null, &event);
    try testing.expectEqual(@as(i32, 1), cl.isurgent);

    pending_kill_client(&cl);
    try testing.expectEqual(@as(c_int, 1), stub_send_close_calls);
    pending_kill_client(null);
    cl.iskilling = 1;
    pending_kill_client(&cl);
    try testing.expectEqual(@as(c_int, 1), stub_send_close_calls);
}
