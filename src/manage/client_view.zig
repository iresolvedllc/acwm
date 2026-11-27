//! Port of client focus, opacity and view/tag/monitor transitions in
//! src/manage/client.c (Phase 5, client slice 7, slice 64).

const std = @import("std");
const c = @import("cc");

const Client = c.Client;
const Monitor = c.Monitor;
const Arg = c.Arg;
const Box = c.struct_wlr_box;
const TAG0: u32 = @as(u32, 1) << 31;

extern fn blur_layer_on_wallpaper(layer: u32) callconv(.c) bool;
extern fn client_target_layer(cl: [*c]Client) callconv(.c) u32;
extern fn client_set_unfocused_opacity_animation(cl: [*c]Client) callconv(.c) void;
extern fn client_set_focused_opacity_animation(cl: [*c]Client) callconv(.c) void;
extern fn client_check_tab_node_visible(cl: [*c]Client) callconv(.c) void;
extern fn client_raise_group(cl: [*c]Client) callconv(.c) void;
extern fn client_raise_tab(cl: [*c]Client) callconv(.c) void;
extern fn client_activate_surface(s: [*c]c.struct_wlr_surface, activated: i32) callconv(.c) void;
extern fn client_notify_enter(s: [*c]c.struct_wlr_surface, kb: [*c]c.struct_wlr_keyboard) callconv(.c) void;
extern fn client_should_ignore_focus(cl: [*c]Client) callconv(.c) i32;
extern fn client_is_x11_popup(cl: [*c]Client) callconv(.c) i32;
extern fn client_is_unmanaged(cl: [*c]Client) callconv(.c) i32;
extern fn client_wants_focus(cl: [*c]Client) callconv(.c) i32;
extern fn client_surface(cl: [*c]Client) callconv(.c) [*c]c.struct_wlr_surface;
extern fn toplevel_from_wlr_surface(s: [*c]c.struct_wlr_surface, pc: [*c][*c]Client, pl: [*c][*c]c.LayerSurface) callconv(.c) i32;
extern fn client_focus_top(m: [*c]Monitor) callconv(.c) [*c]Client;
extern fn tab_sync_focus(cl: [*c]Client) callconv(.c) void;
extern fn check_keep_idle_inhibit(cl: [*c]Client) callconv(.c) void;
extern fn check_vrr_enable(cl: [*c]Client) callconv(.c) void;
extern fn pointer_constrain_cursor(constraint: ?*c.struct_wlr_pointer_constraint_v1) callconv(.c) void;
extern fn pointer_check_confine_client() callconv(.c) void;
extern fn pointer_process_motion(time: u32, device: [*c]c.struct_wlr_input_device, dx: f64, dy: f64, dx_unaccel: f64, dy_unaccel: f64) callconv(.c) void;
extern fn acwm_im_relay_set_focus(relay: ?*anyopaque, surface: [*c]c.struct_wlr_surface) callconv(.c) void;
extern fn is_scroller_layout(m: [*c]Monitor) callconv(.c) bool;
extern fn is_monocle_layout(m: [*c]Monitor) callconv(.c) bool;
extern fn get_tags_first_tag(tags: u32) callconv(.c) u32;
extern fn get_tags_first_tag_num(tags: u32) callconv(.c) u32;
extern fn get_tag_status(tag: u32, m: [*c]Monitor) callconv(.c) u32;
extern fn set_selected_monitor(m: [*c]Monitor) callconv(.c) void;
extern fn set_size_per(m: [*c]Monitor, cl: [*c]Client, reset_proportion: bool) callconv(.c) void;
extern fn arrange(m: [*c]Monitor, want_animation: bool, from_view: bool) callconv(.c) void;
extern fn resize(cl: [*c]Client, geo: Box, opts: c.ResizeOpts) callconv(.c) void;
extern fn client_set_floating(cl: [*c]Client, floating: i32) callconv(.c) void;
extern fn client_reset_mon_tags(cl: [*c]Client, m: [*c]Monitor, tags: u32) callconv(.c) void;
extern fn client_center_geometry(cl: [*c]Client, m: [*c]Monitor, geom: Box, ox: i32, oy: i32) callconv(.c) Box;
extern fn check_match_tag_floating_rule(cl: [*c]Client, m: [*c]Monitor) callconv(.c) void;
extern fn client_apply_fullscreen(cl: [*c]Client, fullscreen: i32, rearrange: bool) callconv(.c) void;
extern fn client_pending_minimized_state(cl: [*c]Client, minimized: i32) callconv(.c) void;
extern fn client_reparent_group(cl: [*c]Client) callconv(.c) void;
extern fn client_group_swap_focus(cl: [*c]Client) callconv(.c) bool;
extern fn client_update_border_color(cl: [*c]Client) callconv(.c) void;
extern fn clear_fullscreen_flag(cl: [*c]Client) callconv(.c) void;
extern fn reset_foreign_tolevel(cl: [*c]Client, oldmon: [*c]Monitor, newmon: [*c]Monitor) callconv(.c) void;
extern fn tag_remap_mask(tags: u32, map: [*c]const u32) callconv(.c) u32;
extern fn tag_gather_move_pertag(m: [*c]Monitor, dst: u32, src: u32) callconv(.c) void;
extern fn printstatus(t: c.enum_ipc_watch_type) callconv(.c) void;

fn clientOpt(p: [*c]Client) ?*Client {
    return if (p == null) null else @ptrCast(p);
}

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

fn TAGMATCH(cl: *const Client, m: *const Monitor) bool {
    return cl.mon == @as([*c]Monitor, @ptrCast(@constCast(m))) and cl.isminimized == 0 and
        (cl.tags & m.tagset[m.seltags]) != 0;
}

fn ISFULLSCREEN(cl: *const Client) bool {
    return cl.isfullscreen != 0 or cl.ismaximizescreen != 0 or
        cl.overview_ismaximizescreenbak != 0 or cl.overview_isfullscreenbak != 0;
}

export fn client_blur_uses_wallpaper(cl: ?*Client) callconv(.c) bool {
    const client = cl orelse return false;
    return c.config.blur_optimized != 0 or
        blur_layer_on_wallpaper(client_target_layer(client));
}

export fn client_sync_blur_optimized(cl: ?*Client) callconv(.c) void {
    const client = cl orelse return;
    if (client.blur == null)
        return;
    c.wlr_scene_blur_set_should_only_blur_bottom_layer(client.blur, client_blur_uses_wallpaper(client));
}

export fn iter_xdg_scene_buffers(buffer: [*c]c.struct_wlr_scene_buffer, sx: i32, sy: i32, user_data: ?*anyopaque) callconv(.c) void {
    _ = sx;
    _ = sy;
    const scene_surface = c.wlr_scene_surface_try_from_buffer(buffer);
    if (scene_surface == null)
        return;
    const surface = scene_surface.*.surface;
    if (c.wlr_subsurface_try_from_wlr_surface(surface) != null)
        return;
    const cl = clientOpt(@as([*c]Client, @ptrCast(@alignCast(user_data.?))));
    if (c.config.blur != 0 and cl != null and cl.?.no_blur == 0)
        client_sync_blur_optimized(cl);
}

export fn scene_buffer_apply_opacity(buffer: [*c]c.struct_wlr_scene_buffer, sx: i32, sy: i32, data: ?*anyopaque) callconv(.c) void {
    _ = sx;
    _ = sy;
    const opacity = @as(*const f64, @ptrCast(@alignCast(data.?))).*;
    c.wlr_scene_buffer_set_opacity(buffer, @floatCast(opacity));
}

export fn client_set_opacity(cl: *Client, opacity_in: f64) callconv(.c) void {
    var opacity = opacity_in;
    if (opacity < 0.0) opacity = 0.0;
    if (opacity > 1.0) opacity = 1.0;
    if (cl.scene_surface != null)
        c.wlr_scene_node_for_each_buffer(&cl.scene_surface.*.node, scene_buffer_apply_opacity, &opacity);
}

export fn client_ensure_constraint(cl: ?*Client) callconv(.c) void {
    const client = cl orelse return;
    const surface = client_surface(client);
    if (surface == null or c.server.pointer_constraints == null)
        return;
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.pointer_constraints.*.constraints);
    var pos = c.server.pointer_constraints.*.constraints.next;
    while (pos != head) : (pos = pos.*.next) {
        const constraint = @as(*c.struct_wlr_pointer_constraint_v1, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.struct_wlr_pointer_constraint_v1, "link")));
        if (constraint.surface == surface) {
            pointer_constrain_cursor(constraint);
            break;
        }
    }
}

export fn client_focus(cl_in: ?*Client, lift: i32) callconv(.c) void {
    const cl = cl_in;
    const old_focus_surface = if (c.server.seat != null) c.server.seat.*.keyboard_state.focused_surface else null;

    if (c.server.session_locked != 0)
        return;
    if (cl != null and cl.?.iskilling != 0)
        return;
    if (cl != null and (client_surface(cl.?) == null or !client_surface(cl.?).*.mapped))
        return;
    if (cl != null and client_should_ignore_focus(cl.?) != 0 and client_is_x11_popup(cl.?) != 0)
        return;
    if (cl != null and cl.?.no_focus != 0)
        return;

    if (cl != null and lift != 0) {
        client_raise_group(cl.?);
        client_raise_tab(cl.?);
    }

    const selected = monitorOpt(c.server.selected_monitor);
    if (cl != null and selected != null and selected.?.sel != null and
        client_surface(cl.?) == old_focus_surface)
    {
        client_ensure_constraint(cl);
        return;
    }

    if (selected != null and selected.?.sel != null and
        (cl == null or selected.?.sel != cl.?) and selected.?.sel.*.foreign_toplevel != null)
    {
        c.wlr_foreign_toplevel_handle_v1_set_activated(selected.?.sel.*.foreign_toplevel, false);
    }

    if (cl != null and cl.?.iskilling == 0 and client_is_unmanaged(cl.?) == 0 and cl.?.mon != null) {
        const last_focus = if (selected != null) selected.?.sel else null;
        set_selected_monitor(cl.?.mon);
        const selmon = @as(*Monitor, @ptrCast(c.server.selected_monitor));
        selmon.prevsel = selmon.sel;
        selmon.sel = cl.?;
        cl.?.isfocusing = true;

        tab_sync_focus(cl.?);
        if (last_focus != null and last_focus != cl)
            client_check_tab_node_visible(last_focus);
        client_check_tab_node_visible(cl.?);

        check_keep_idle_inhibit(cl.?);
        check_vrr_enable(cl.?);

        if (last_focus != null and last_focus.*.iskilling == 0 and last_focus != cl) {
            last_focus.*.isfocusing = false;
            client_set_unfocused_opacity_animation(last_focus);
        }
        client_set_focused_opacity_animation(cl.?);

        c.wl_list_remove(&cl.?.flink);
        c.wl_list_insert(&c.server.focus_stack, &cl.?.flink);

        if (selmon.prevsel != null and TAGMATCH(selmon.prevsel, selmon) and
            TAGMATCH(cl.?, selmon) and cl.?.isfloating == 0 and
            (is_scroller_layout(selmon) or is_monocle_layout(selmon) or
                cl.?.tab_prev != null or cl.?.tab_next != null))
            arrange(selmon, false, false);

        cl.?.isurgent = 0;
    }

    var pos = c.server.monitors.next;
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.monitors);
    while (pos != head) : (pos = pos.*.next) {
        const um = @as(*Monitor, @ptrFromInt(@intFromPtr(pos) - @offsetOf(Monitor, "link")));
        if (um.wlr_output != null and um.wlr_output.*.enabled and
            (c.server.selected_monitor == null or um != c.server.selected_monitor) and
            um.sel != null and um.sel.*.iskilling == 0 and um.sel.*.isfocusing)
        {
            um.sel.*.isfocusing = false;
            client_set_unfocused_opacity_animation(um.sel);
            if (um.sel.*.foreign_toplevel != null)
                c.wlr_foreign_toplevel_handle_v1_set_activated(um.sel.*.foreign_toplevel, false);
        }
    }

    if (cl != null and cl.?.iskilling == 0 and cl.?.foreign_toplevel != null)
        c.wlr_foreign_toplevel_handle_v1_set_activated(cl.?.foreign_toplevel, true);

    if (old_focus_surface != null and (cl == null or client_surface(cl.?) != old_focus_surface)) {
        var w: [*c]Client = null;
        var l: [*c]c.LayerSurface = null;
        const kind = toplevel_from_wlr_surface(old_focus_surface, &w, &l);
        if (kind == c.LayerShell and l != null and l.*.scene != null and l.*.scene.*.node.enabled and
            @as(c_int, @intCast(l.*.layer_surface.*.current.layer)) >= c.ZWLR_LAYER_SHELL_V1_LAYER_TOP and
            c.server.exclusive_focus != null and @intFromPtr(l) == @intFromPtr(c.server.exclusive_focus.?))
        {
            return;
        } else if (w != null and c.server.exclusive_focus != null and
            @intFromPtr(w) == @intFromPtr(c.server.exclusive_focus.?) and client_wants_focus(w) != 0)
        {
            return;
        } else if (w != null and client_is_unmanaged(w) == 0 and
            (cl == null or client_wants_focus(cl.?) == 0))
        {
            client_activate_surface(old_focus_surface, 0);
        }
    }
    printstatus(@intCast(c.IPC_WATCH_ARRANGGE));

    if (cl == null) {
        if (selected != null and selected.?.sel != null and
            (!VISIBLEON(selected.?.sel, selected.?) or selected.?.sel.*.iskilling != 0 or
                !client_surface(selected.?.sel).*.mapped))
        {
            selected.?.sel.*.isfocusing = false;
            client_set_unfocused_opacity_animation(selected.?.sel);
            selected.?.sel = null;
        }
        acwm_im_relay_set_focus(c.server.input_method_relay, null);
        if (c.server.seat != null)
            c.wlr_seat_keyboard_notify_clear_focus(c.server.seat);
        check_vrr_enable(null);
        if (c.server.active_constraint != null)
            pointer_constrain_cursor(null);
        pointer_check_confine_client();
        return;
    }

    pointer_process_motion(0, null, 0, 0, 0, 0);
    acwm_im_relay_set_focus(c.server.input_method_relay, client_surface(cl.?));
    client_notify_enter(client_surface(cl.?), c.wlr_seat_get_keyboard(c.server.seat));
    client_activate_surface(client_surface(cl.?), 1);

    if (c.server.active_constraint != null and
        c.server.active_constraint.?.*.surface != client_surface(cl.?))
        pointer_constrain_cursor(null);

    client_ensure_constraint(cl);
    pointer_check_confine_client();
}

export fn client_active(cl: *Client) callconv(.c) void {
    if (client_is_unmanaged(cl) != 0) {
        client_focus(cl, 1);
        return;
    }
    if (cl.swallowdby != null)
        return;
    if (cl.mon == null and !client_group_swap_focus(cl))
        return;
    if (cl.isminimized != 0) {
        cl.is_in_scratchpad = 0;
        cl.isnamedscratchpad = 0;
        client_update_border_color(cl);
        show_hide_client(cl);
        arrange(cl.mon, true, false);
        return;
    }
    var arg = std.mem.zeroes(Arg);
    arg.ui = get_tags_first_tag(cl.tags);
    client_view_on_monitor(&arg, true, cl.mon, true);
    client_focus(cl, 1);
}

export fn client_view_on_monitor(arg: *const Arg, want_animation_in: bool, m_in: [*c]Monitor, changefocus: bool) callconv(.c) void {
    const m = monitorOpt(m_in) orelse return;
    var want_animation = want_animation_in;

    const full_normal = ~@as(u32, 0) & c.server.tagmask;
    if (arg.ui != full_normal and m.isoverview != 0)
        return;
    if (arg.ui == 0)
        return;

    var toggleseltags = false;
    if (arg.ui == std.math.maxInt(u32)) {
        if (m.tagset[0] != m.tagset[1]) {
            m.pertag.*.prevtag = get_tags_first_tag_num(m.tagset[m.seltags]);
            m.seltags ^= 1;
            m.pertag.*.curtag = get_tags_first_tag_num(m.tagset[m.seltags]);
            toggleseltags = true;
        } else {
            return;
        }
    }

    if (!toggleseltags) {
        if ((m.tagset[m.seltags] & arg.ui & (c.server.tagmask | TAG0)) != 0)
            want_animation = false;

        m.seltags ^= 1;
        if ((arg.ui & (c.server.tagmask | TAG0)) != 0) {
            m.tagset[m.seltags] = arg.ui & (c.server.tagmask | TAG0);
            const tmptag = m.pertag.*.curtag;
            if ((arg.ui & TAG0) != 0) {
                m.pertag.*.curtag = 0;
            } else {
                var i: u32 = 0;
                while ((arg.ui & (@as(u32, 1) << @intCast(i))) == 0 and
                    i < @as(u32, @intCast(c.config.tag_num)) and arg.ui != 0) : (i += 1)
                {}
                m.pertag.*.curtag = if (i >= @as(u32, @intCast(c.config.tag_num)))
                    @intCast(c.config.tag_num)
                else
                    i + 1;
            }
            m.pertag.*.prevtag = if (tmptag == m.pertag.*.curtag) m.pertag.*.prevtag else tmptag;
        } else {
            const tmptag = m.pertag.*.prevtag;
            m.pertag.*.prevtag = m.pertag.*.curtag;
            m.pertag.*.curtag = tmptag;
        }
    }

    if (changefocus)
        client_focus(client_focus_top(m), 1);
    arrange(m, want_animation, true);
    printstatus(@intCast(c.IPC_WATCH_ARRANGGE));
}

export fn client_switch_view(arg: *const Arg, want_animation: bool) callconv(.c) void {
    if (arg.i != 0) {
        client_view_on_monitor(arg, want_animation, c.server.selected_monitor, true);
        var pos = c.server.monitors.next;
        const head: [*c]c.struct_wl_list = @ptrCast(&c.server.monitors);
        while (pos != head) : (pos = pos.*.next) {
            const m = @as(*Monitor, @ptrFromInt(@intFromPtr(pos) - @offsetOf(Monitor, "link")));
            if (m.wlr_output == null or !m.wlr_output.*.enabled or
                (c.server.selected_monitor != null and @intFromPtr(m) == @intFromPtr(c.server.selected_monitor)))
                continue;
            client_view_on_monitor(arg, want_animation, m, false);
        }
    } else {
        client_view_on_monitor(arg, want_animation, c.server.selected_monitor, true);
    }
}

export fn tag_client(arg: *const Arg, target_in: ?*Client) callconv(.c) void {
    const target = target_in;
    if (target != null and (arg.ui & (c.server.tagmask | TAG0)) != 0) {
        target.?.tags = if ((arg.ui & TAG0) != 0) TAG0 else arg.ui & c.server.tagmask;
        client_reparent_group(target.?);

        var pos = c.server.clients.next;
        const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
        while (pos != head) : (pos = pos.*.next) {
            const fc = @as(*Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(Client, "link")));
            if (fc != target.? and (target.?.tags & fc.tags) != 0 and ISFULLSCREEN(fc) and
                target.?.isfloating == 0)
                clear_fullscreen_flag(fc);
        }
        if ((arg.ui & TAG0) != 0)
            arrange(target.?.mon, false, false);
        var view_arg = std.mem.zeroes(Arg);
        view_arg.ui = arg.ui;
        view_arg.i = arg.i;
        client_switch_view(&view_arg, true);
    } else {
        client_switch_view(arg, true);
    }

    client_focus(target, 1);
    printstatus(@intCast(c.IPC_WATCH_ARRANGGE));
}

export fn show_hide_client(cl: *Client) callconv(.c) void {
    if (cl.mon == null)
        return;
    set_size_per(cl.mon, cl, false);
    var arg = std.mem.zeroes(Arg);
    arg.ui = get_tags_first_tag(cl.oldtags);

    if (cl.is_in_scratchpad == 0) {
        tag_client(&arg, cl);
    } else {
        cl.tags = cl.mon.*.tagset[cl.mon.*.seltags];
        cl.isminimized = 0;
        arrange(cl.mon, false, false);
    }
    client_pending_minimized_state(cl, 0);
    client_focus(cl, 1);
    if (cl.foreign_toplevel != null)
        c.wlr_foreign_toplevel_handle_v1_set_activated(cl.foreign_toplevel, true);
}

export fn client_set_monitor(cl: *Client, m_in: [*c]Monitor, newtags: u32, focus: bool) callconv(.c) void {
    const oldmon = cl.mon;
    if (@intFromPtr(oldmon) == @intFromPtr(m_in))
        return;

    if (oldmon != null and oldmon.*.sel == cl)
        oldmon.*.sel = null;
    if (oldmon != null and oldmon.*.prevsel == cl)
        oldmon.*.prevsel = null;

    cl.mon = m_in;
    if (oldmon != null)
        arrange(oldmon, false, false);
    if (c.client_is_parked(cl))
        return;

    if (m_in != null) {
        reset_foreign_tolevel(cl, oldmon, m_in);
        var opts = std.mem.zeroes(c.ResizeOpts);
        opts.interact = false;
        resize(cl, cl.geom, opts);
        client_reset_mon_tags(cl, m_in, newtags);
        check_match_tag_floating_rule(cl, m_in);
        client_set_floating(cl, cl.isfloating);
        client_apply_fullscreen(cl, cl.isfullscreen, true);
    }

    if (focus and c.client_is_x11_popup(cl) == 0)
        client_focus(client_focus_top(c.server.selected_monitor), 1);
}

fn clientResetMonTags(cl: *Client, m: [*c]Monitor, tags: u32) void {
    _ = cl;
    _ = m;
    _ = tags;
}

export fn client_change_mon(cl: *Client, m: [*c]Monitor) callconv(.c) void {
    client_set_monitor(cl, m, cl.tags, true);
    if (cl.isfloating != 0) {
        const geom = client_center_geometry(cl, cl.mon, cl.geom, 0, 0);
        cl.float_geom = geom;
        cl.geom = geom;
    }
}

export fn view_insert_shift_tags(m_in: [*c]Monitor, target: u32) callconv(.c) void {
    const m = monitorOpt(m_in) orelse return;
    const tag_num: u32 = @intCast(c.config.tag_num);
    if (target < 1 or target >= tag_num)
        return;
    if (get_tag_status(tag_num, m) != 0)
        return;

    var map: [32]u32 = std.mem.zeroes([32]u32);
    var i: u32 = 1;
    while (i <= tag_num) : (i += 1) {
        if (i < target) {
            map[i] = i;
        } else if (i < tag_num) {
            map[i] = i + 1;
        } else {
            map[i] = i;
        }
    }

    var pos = c.server.clients.next;
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = @as(*Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(Client, "link")));
        if (cl.mon != m or cl.iskilling != 0)
            continue;
        cl.tags = tag_remap_mask(cl.tags, &map);
    }

    m.tagset[m.seltags] = tag_remap_mask(m.tagset[m.seltags], &map);
    m.tagset[m.seltags ^ 1] = tag_remap_mask(m.tagset[m.seltags ^ 1], &map);
    m.ovbk_current_tagset = tag_remap_mask(m.ovbk_current_tagset, &map);
    m.ovbk_prev_tagset = tag_remap_mask(m.ovbk_prev_tagset, &map);

    if (m.pertag.*.curtag <= tag_num and map[m.pertag.*.curtag] != 0)
        m.pertag.*.curtag = map[m.pertag.*.curtag];
    if (m.pertag.*.prevtag <= tag_num and map[m.pertag.*.prevtag] != 0)
        m.pertag.*.prevtag = map[m.pertag.*.prevtag];

    var j: i32 = @as(i32, @intCast(tag_num)) - 1;
    while (j >= @as(i32, @intCast(target))) : (j -= 1)
        tag_gather_move_pertag(m, @intCast(j + 1), @intCast(j));
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/client_view_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_list_insert_calls: c_int;
extern var stub_list_remove_calls: c_int;
extern var stub_wallpaper: bool;
extern var stub_wallpaper_calls: c_int;
extern var stub_target_layer: u32;
extern var stub_blur_bottom_calls: c_int;
extern var stub_blur_bottom_value: bool;
extern var stub_scene_surface: [*c]c.struct_wlr_scene_surface;
extern var stub_subsurface: [*c]c.struct_wlr_subsurface;
extern var stub_buffer_opacity_calls: c_int;
extern var stub_buffer_opacity: f32;
extern var stub_for_each_calls: c_int;
extern var stub_constrain_calls: c_int;
extern var stub_confine_check_calls: c_int;
extern var stub_pointer_motion_calls: c_int;
extern var stub_relay_calls: c_int;
extern var stub_raise_group_calls: c_int;
extern var stub_raise_tab_calls: c_int;
extern var stub_unfocused_calls: c_int;
extern var stub_focused_calls: c_int;
extern var stub_tab_sync_calls: c_int;
extern var stub_tab_visible_calls: c_int;
extern var stub_idle_calls: c_int;
extern var stub_vrr_calls: c_int;
extern var stub_clear_focus_calls: c_int;
extern var stub_activate_calls: c_int;
extern var stub_activate_value: i32;
extern var stub_notify_calls: c_int;
extern var stub_set_selected_calls: c_int;
extern var stub_selected_value: [*c]Monitor;
extern var stub_arrange_calls: c_int;
extern var stub_resize_calls: c_int;
extern var stub_set_floating_calls: c_int;
extern var stub_apply_fs_calls: c_int;
extern var stub_pending_min_calls: c_int;
extern var stub_reparent_calls: c_int;
extern var stub_group_swap: bool;
extern var stub_border_color_calls: c_int;
extern var stub_clear_fullscreen_calls: c_int;
extern var stub_reset_foreign_calls: c_int;
extern var stub_reset_tags_calls: c_int;
extern var stub_tag_float_calls: c_int;
extern var stub_center_box: Box;
extern var stub_center_calls: c_int;
extern var stub_gather_calls: c_int;
extern var stub_gather_dst: u32;
extern var stub_gather_src: u32;
extern var stub_status: c_int;
extern var stub_scroller: bool;
extern var stub_monocle: bool;
extern var stub_set_size_per_calls: c_int;
extern var stub_printstatus_calls: c_int;
extern var stub_unmanaged: i32;
extern var stub_x11_popup: i32;
extern var stub_ignore_focus: i32;
extern var stub_wants_focus: i32;
extern var stub_surface: [*c]c.struct_wlr_surface;
extern var stub_toplevel_kind: i32;
extern var stub_toplevel_client: [*c]Client;
extern var stub_toplevel_layer: [*c]c.LayerSurface;
extern var stub_top_client: [*c]Client;
extern var stub_ft_activate_calls: c_int;
extern var stub_ft_activate_value: bool;

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

fn resetViewWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    listInit(&c.server.clients);
    listInit(&c.server.monitors);
    listInit(&c.server.focus_stack);
    c.server.tagmask = 0xffffffff;
    stub_list_insert_calls = 0;
    stub_list_remove_calls = 0;
    stub_wallpaper = false;
    stub_wallpaper_calls = 0;
    stub_target_layer = 5;
    stub_blur_bottom_calls = 0;
    stub_blur_bottom_value = false;
    stub_scene_surface = null;
    stub_subsurface = null;
    stub_buffer_opacity_calls = 0;
    stub_buffer_opacity = -1;
    stub_for_each_calls = 0;
    stub_constrain_calls = 0;
    stub_confine_check_calls = 0;
    stub_pointer_motion_calls = 0;
    stub_relay_calls = 0;
    stub_raise_group_calls = 0;
    stub_raise_tab_calls = 0;
    stub_unfocused_calls = 0;
    stub_focused_calls = 0;
    stub_tab_sync_calls = 0;
    stub_tab_visible_calls = 0;
    stub_idle_calls = 0;
    stub_vrr_calls = 0;
    stub_clear_focus_calls = 0;
    stub_activate_calls = 0;
    stub_activate_value = -1;
    stub_notify_calls = 0;
    stub_set_selected_calls = 0;
    stub_selected_value = null;
    stub_arrange_calls = 0;
    stub_resize_calls = 0;
    stub_set_floating_calls = 0;
    stub_apply_fs_calls = 0;
    stub_pending_min_calls = 0;
    stub_reparent_calls = 0;
    stub_group_swap = false;
    stub_border_color_calls = 0;
    stub_clear_fullscreen_calls = 0;
    stub_reset_foreign_calls = 0;
    stub_reset_tags_calls = 0;
    stub_tag_float_calls = 0;
    stub_center_box = std.mem.zeroes(Box);
    stub_center_calls = 0;
    stub_gather_calls = 0;
    stub_gather_dst = 0;
    stub_gather_src = 0;
    stub_status = 0;
    stub_scroller = false;
    stub_monocle = false;
    stub_set_size_per_calls = 0;
    stub_printstatus_calls = 0;
    stub_unmanaged = 0;
    stub_x11_popup = 0;
    stub_ignore_focus = 0;
    stub_wants_focus = 0;
    stub_surface = null;
    stub_toplevel_kind = -1;
    stub_toplevel_client = null;
    stub_toplevel_layer = null;
    stub_top_client = null;
    stub_ft_activate_calls = 0;
    stub_ft_activate_value = false;
}

test "blur, opacity and constraints follow scene state" {
    resetViewWorld();
    try testing.expect(!client_blur_uses_wallpaper(null));
    var cl: Client = std.mem.zeroes(Client);
    c.config.blur_optimized = 1;
    try testing.expect(client_blur_uses_wallpaper(&cl));
    c.config.blur_optimized = 0;
    stub_wallpaper = true;
    try testing.expect(client_blur_uses_wallpaper(&cl));

    cl.blur = @ptrFromInt(0x1000);
    client_sync_blur_optimized(&cl);
    try testing.expectEqual(@as(c_int, 1), stub_blur_bottom_calls);
    try testing.expect(stub_blur_bottom_value);
    client_sync_blur_optimized(null);

    cl.no_blur = 0;
    c.config.blur = 1;
    var buffer: c.struct_wlr_scene_buffer = std.mem.zeroes(c.struct_wlr_scene_buffer);
    iter_xdg_scene_buffers(&buffer, 0, 0, &cl);
    try testing.expectEqual(@as(c_int, 1), stub_blur_bottom_calls);
    var ss: c.struct_wlr_scene_surface = std.mem.zeroes(c.struct_wlr_scene_surface);
    stub_scene_surface = &ss;
    iter_xdg_scene_buffers(&buffer, 0, 0, &cl);
    try testing.expectEqual(@as(c_int, 2), stub_blur_bottom_calls);
    var sub: c.struct_wlr_subsurface = std.mem.zeroes(c.struct_wlr_subsurface);
    stub_subsurface = &sub;
    iter_xdg_scene_buffers(&buffer, 0, 0, &cl);
    try testing.expectEqual(@as(c_int, 2), stub_blur_bottom_calls);
    stub_subsurface = null;

    var scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    cl.scene_surface = &scene;
    client_set_opacity(&cl, 1.5);
    try testing.expectApproxEqAbs(@as(f32, 1), stub_buffer_opacity, 1e-6);
    client_set_opacity(&cl, -0.5);
    try testing.expectApproxEqAbs(@as(f32, 0), stub_buffer_opacity, 1e-6);
    try testing.expectEqual(@as(c_int, 2), stub_for_each_calls);

    var constraints: c.struct_wlr_pointer_constraints_v1 = std.mem.zeroes(c.struct_wlr_pointer_constraints_v1);
    listInit(&constraints.constraints);
    c.server.pointer_constraints = &constraints;
    var surf: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    stub_surface = &surf;
    var constraint: c.struct_wlr_pointer_constraint_v1 = std.mem.zeroes(c.struct_wlr_pointer_constraint_v1);
    constraint.surface = &surf;
    listInsert(&constraints.constraints, &constraint.link);
    client_ensure_constraint(&cl);
    try testing.expectEqual(@as(c_int, 1), stub_constrain_calls);
    client_ensure_constraint(null);
}

test "focus updates selection, opacity, protocols and seat" {
    resetViewWorld();
    var seat: c.struct_wlr_seat = std.mem.zeroes(c.struct_wlr_seat);
    c.server.seat = &seat;
    var mon: Monitor = std.mem.zeroes(Monitor);
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    mon.pertag = &p;
    mon.tagset[0] = 1;
    c.server.selected_monitor = &mon;
    var cl: Client = std.mem.zeroes(Client);
    var surf: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    surf.mapped = true;
    stub_surface = &surf;
    cl.mon = &mon;
    cl.tags = 1;
    var old: Client = std.mem.zeroes(Client);
    var old_surf: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    old_surf.mapped = true;
    old.foreign_toplevel = @ptrFromInt(0x1000);
    mon.sel = &old;
    mon.prevsel = null;
    listInsert(&c.server.focus_stack, &cl.flink);

    c.server.session_locked = 1;
    client_focus(&cl, 1);
    try testing.expectEqual(@as(c_int, 0), stub_set_selected_calls);
    c.server.session_locked = 0;

    client_focus(&cl, 1);
    try testing.expectEqual(@as(c_int, 1), stub_set_selected_calls);
    try testing.expect(stub_selected_value == &mon);
    try testing.expect(mon.sel == &cl);
    try testing.expect(mon.prevsel == &old);
    try testing.expect(cl.isfocusing);
    try testing.expectEqual(@as(c_int, 1), stub_tab_sync_calls);
    try testing.expectEqual(@as(c_int, 1), stub_idle_calls);
    try testing.expectEqual(@as(c_int, 1), stub_vrr_calls);
    try testing.expectEqual(@as(c_int, 1), stub_focused_calls);
    try testing.expectEqual(@as(c_int, 1), stub_unfocused_calls);
    try testing.expectEqual(@as(i32, 0), cl.isurgent);
    try testing.expectEqual(@as(c_int, 1), stub_notify_calls);
    try testing.expectEqual(@as(c_int, 1), stub_activate_calls);
    try testing.expectEqual(@as(i32, 1), stub_activate_value);
    try testing.expectEqual(@as(c_int, 1), stub_relay_calls);
    try testing.expectEqual(@as(c_int, 1), stub_pointer_motion_calls);
    try testing.expectEqual(@as(c_int, 1), stub_printstatus_calls);

    cl.no_focus = 1;
    client_focus(&cl, 0);
    cl.no_focus = 0;
    cl.iskilling = 1;
    client_focus(&cl, 0);
    cl.iskilling = 0;

    mon.sel = &old;
    client_focus(null, 0);
    try testing.expect(mon.sel == null);
    try testing.expectEqual(@as(c_int, 1), stub_clear_focus_calls);
    try testing.expectEqual(@as(c_int, 2), stub_vrr_calls);
    try testing.expectEqual(@as(c_int, 2), stub_confine_check_calls);
}

test "client activation unminimizes scratchpads or focuses tags" {
    resetViewWorld();
    var cl: Client = std.mem.zeroes(Client);
    stub_unmanaged = 1;
    client_active(&cl);
    try testing.expectEqual(@as(c_int, 0), stub_set_selected_calls);
    stub_unmanaged = 0;

    var swallow: Client = std.mem.zeroes(Client);
    cl.swallowdby = &swallow;
    client_active(&cl);
    cl.swallowdby = null;
    stub_group_swap = false;
    client_active(&cl);
    try testing.expectEqual(@as(c_int, 0), stub_set_selected_calls);

    var mon: Monitor = std.mem.zeroes(Monitor);
    var perf: c.Pertag = std.mem.zeroes(c.Pertag);
    mon.pertag = &perf;
    mon.tagset[0] = 1;
    mon.seltags = 0;
    cl.mon = &mon;
    cl.isminimized = 1;
    cl.is_in_scratchpad = 1;
    cl.isnamedscratchpad = 1;
    client_active(&cl);
    try testing.expectEqual(@as(i32, 0), cl.is_in_scratchpad);
    try testing.expectEqual(@as(i32, 0), cl.isnamedscratchpad);
    try testing.expectEqual(@as(c_int, 1), stub_border_color_calls);
    try testing.expect(stub_arrange_calls >= 1);

    cl.isminimized = 0;
    cl.tags = 0b100;
    client_active(&cl);
    try testing.expect(stub_printstatus_calls >= 1);
}

test "view switching updates tagsets and current tags" {
    resetViewWorld();
    var mon: Monitor = std.mem.zeroes(Monitor);
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    mon.pertag = &p;
    mon.tagset[0] = 1;
    mon.tagset[1] = 2;
    mon.seltags = 0;
    p.curtag = 1;
    p.prevtag = 2;
    var arg: Arg = std.mem.zeroes(Arg);

    arg.ui = 0;
    client_view_on_monitor(&arg, true, &mon, true);
    try testing.expectEqual(@as(c_int, 0), stub_arrange_calls);

    arg.ui = std.math.maxInt(u32);
    mon.tagset[0] = 1;
    mon.tagset[1] = 1;
    client_view_on_monitor(&arg, true, &mon, true);
    try testing.expectEqual(@as(c_int, 0), stub_arrange_calls);

    mon.tagset[0] = 0b100;
    mon.tagset[1] = 0b010;
    p.curtag = 3;
    p.prevtag = 2;
    client_view_on_monitor(&arg, true, &mon, true);
    try testing.expectEqual(@as(u32, 1), mon.seltags);
    try testing.expectEqual(@as(u32, 2), p.curtag);
    try testing.expectEqual(@as(u32, 3), p.prevtag);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);

    c.config.tag_num = 4;
    arg.ui = 0b1000;
    mon.seltags = 0;
    p.curtag = 1;
    p.prevtag = 3;
    client_view_on_monitor(&arg, true, &mon, true);
    try testing.expectEqual(@as(u32, 1), mon.seltags);
    try testing.expectEqual(@as(u32, 0b1000), mon.tagset[1]);
    try testing.expectEqual(@as(u32, 4), p.curtag);
    try testing.expectEqual(@as(u32, 1), p.prevtag);

    arg.ui = @as(u32, 1) << 31;
    client_view_on_monitor(&arg, true, &mon, false);
    try testing.expectEqual(@as(u32, 0), p.curtag);
}

test "switch view arranges other enabled monitors without focus" {
    resetViewWorld();
    var sel: Monitor = std.mem.zeroes(Monitor);
    var other: Monitor = std.mem.zeroes(Monitor);
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var p2: c.Pertag = std.mem.zeroes(c.Pertag);
    sel.pertag = &p;
    other.pertag = &p2;
    var out1: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    var out2: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    out1.enabled = true;
    out2.enabled = true;
    sel.wlr_output = &out1;
    other.wlr_output = &out2;
    sel.tagset[0] = 1;
    other.tagset[0] = 1;
    c.server.selected_monitor = &sel;
    listInsert(&c.server.monitors, &other.link);
    var arg: Arg = std.mem.zeroes(Arg);
    arg.ui = 0b10;
    arg.i = 1;
    client_switch_view(&arg, true);
    try testing.expectEqual(@as(c_int, 2), stub_arrange_calls);
}

test "tagging moves clients and remaps shifted tags" {
    resetViewWorld();
    var mon: Monitor = std.mem.zeroes(Monitor);
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    mon.pertag = &p;
    mon.tagset[0] = 1;
    c.server.selected_monitor = &mon;
    var cl: Client = std.mem.zeroes(Client);
    var peer: Client = std.mem.zeroes(Client);
    cl.mon = &mon;
    cl.tags = 1;
    peer.mon = &mon;
    peer.tags = 0b10;
    peer.isfullscreen = 1;
    listInsert(&c.server.clients, &cl.link);
    listInsert(&c.server.clients, &peer.link);
    var arg: Arg = std.mem.zeroes(Arg);
    arg.ui = 0b10;
    tag_client(&arg, &cl);
    try testing.expectEqual(@as(u32, 0b10), cl.tags);
    try testing.expectEqual(@as(c_int, 1), stub_reparent_calls);
    try testing.expectEqual(@as(c_int, 1), stub_clear_fullscreen_calls);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);

    c.config.tag_num = 4;
    mon.tagset[0] = 0b101;
    mon.tagset[1] = 0b110;
    p.curtag = 2;
    p.prevtag = 3;
    cl.tags = 0b110;
    view_insert_shift_tags(&mon, 2);
    try testing.expectEqual(@as(c_int, 2), stub_gather_calls);
    try testing.expectEqual(@as(u32, 3), stub_gather_dst);
    try testing.expectEqual(@as(u32, 2), stub_gather_src);
}

test "monitor moves update selection, tags and floating centering" {
    resetViewWorld();
    var old: Monitor = std.mem.zeroes(Monitor);
    var new: Monitor = std.mem.zeroes(Monitor);
    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    out.enabled = true;
    new.wlr_output = &out;
    new.tagset[0] = 0b10;
    var cl: Client = std.mem.zeroes(Client);
    cl.mon = &old;
    cl.tags = 1;
    old.sel = &cl;
    old.prevsel = &cl;

    client_set_monitor(&cl, &old, 0, true);
    try testing.expectEqual(@as(c_int, 0), stub_arrange_calls);

    client_set_monitor(&cl, &new, 0b100, true);
    try testing.expect(cl.mon == &new);
    try testing.expect(old.sel == null);
    try testing.expect(old.prevsel == null);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);
    try testing.expectEqual(@as(c_int, 1), stub_reset_foreign_calls);
    try testing.expectEqual(@as(c_int, 1), stub_resize_calls);
    try testing.expectEqual(@as(c_int, 1), stub_reset_tags_calls);
    try testing.expectEqual(@as(c_int, 1), stub_tag_float_calls);
    try testing.expectEqual(@as(c_int, 1), stub_set_floating_calls);
    try testing.expectEqual(@as(c_int, 1), stub_apply_fs_calls);

    cl.isfloating = 1;
    stub_center_box = mkBox2(50, 60, 300, 200);
    client_change_mon(&cl, &old);
    try testing.expectEqual(@as(i32, 50), cl.geom.x);
    try testing.expectEqual(@as(i32, 300), cl.float_geom.width);
}

fn mkBox2(x: i32, y: i32, w: i32, h: i32) Box {
    return .{ .x = x, .y = y, .width = w, .height = h };
}
