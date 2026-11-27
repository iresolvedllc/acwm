//! Port of floating/fullscreen/scratchpad/minimized transitions and
//! exchange/park/replace helpers in src/manage/client.c
//! (Phase 5, client slice 8, slice 65).

const std = @import("std");
const c = @import("cc");

const Client = c.Client;
const Monitor = c.Monitor;
const Box = c.struct_wlr_box;
const DwindleNode = c.DwindleNode;
const ScrollerStackNode = c.struct_ScrollerStackNode;
const TagScrollerState = c.struct_TagScrollerState;

extern fn client_surface(cl: [*c]Client) callconv(.c) [*c]c.struct_wlr_surface;
extern fn client_is_x11(cl: [*c]Client) callconv(.c) i32;
extern fn client_set_fullscreen(cl: [*c]Client, fullscreen: i32) callconv(.c) void;
extern fn client_set_maximized(cl: [*c]Client, maximized: bool) callconv(.c) void;
extern fn client_sync_tiled_hint(cl: [*c]Client) callconv(.c) void;
extern fn client_update_visibility(cl: [*c]Client) callconv(.c) void;
extern fn client_reparent_group(cl: [*c]Client) callconv(.c) void;
extern fn client_group_replace(old: [*c]Client, new: [*c]Client) callconv(.c) void;
extern fn client_update_oldmonname_record(cl: [*c]Client, m: [*c]Monitor) callconv(.c) void;
extern fn client_wants_group_bar(cl: [*c]Client) callconv(.c) bool;
extern fn client_swap_layout_properties(c1: [*c]Client, c2: [*c]Client) callconv(.c) void;
extern fn client_swap_monitors_and_tags(c1: [*c]Client, c2: [*c]Client) callconv(.c) void;
extern fn finish_exchange_arrange_and_focus(c1: [*c]Client, c2: [*c]Client, m1: [*c]Monitor, m2: [*c]Monitor) callconv(.c) void;
extern fn exchange_two_scroller_clients(c1: [*c]Client, c2: [*c]Client) callconv(.c) void;
extern fn dwindle_swap_clients(c1: [*c]Client, c2: [*c]Client) callconv(.c) void;
extern fn dwindle_remove(root: [*c][*c]DwindleNode, cl: [*c]Client) callconv(.c) void;
extern fn dwindle_find_leaf(node: [*c]DwindleNode, cl: [*c]Client) callconv(.c) [*c]DwindleNode;
extern fn sync_scroller_state_to_clients(m: [*c]Monitor, tag: u32) callconv(.c) void;
extern fn find_scroller_node(st: [*c]TagScrollerState, cl: [*c]Client) callconv(.c) [*c]ScrollerStackNode;
extern fn scroller_node_remove(st: [*c]TagScrollerState, node: [*c]ScrollerStackNode) callconv(.c) void;
extern fn tab_detach_client(cl: [*c]Client) callconv(.c) void;
extern fn tab_replace_client(old: [*c]Client, new: [*c]Client) callconv(.c) void;
extern fn show_hide_client(cl: [*c]Client) callconv(.c) void;
extern fn add_foreign_toplevel(cl: [*c]Client) callconv(.c) void;
extern fn overview_destroy_card(cl: [*c]Client) callconv(.c) void;
extern fn overview_backup_surface(cl: [*c]Client) callconv(.c) void;
extern fn reset_foreign_tolevel(cl: [*c]Client, oldmon: [*c]Monitor, newmon: [*c]Monitor) callconv(.c) void;
extern fn client_center_geometry(cl: [*c]Client, m: [*c]Monitor, geom: Box, ox: i32, oy: i32) callconv(.c) Box;
extern fn get_client_tag_idx(cl: ?*const Client) callconv(.c) u32;
extern fn get_tags_first_tag(tags: u32) callconv(.c) u32;
extern fn is_scroller_layout(m: [*c]Monitor) callconv(.c) bool;
extern fn is_monocle_layout(m: [*c]Monitor) callconv(.c) bool;
extern fn set_size_per(m: [*c]Monitor, cl: [*c]Client, reset: bool) callconv(.c) void;
extern fn arrange(m: [*c]Monitor, want_animation: bool, from_view: bool) callconv(.c) void;
extern fn resize(cl: [*c]Client, geo: Box, opts: c.ResizeOpts) callconv(.c) void;
extern fn client_focus(cl: ?*Client, lift: i32) callconv(.c) void;
extern fn client_focus_top(m: [*c]Monitor) callconv(.c) [*c]Client;
extern fn check_vrr_enable(cl: [*c]Client) callconv(.c) void;
extern fn check_keep_idle_inhibit(cl: [*c]Client) callconv(.c) void;
extern fn acwm_dim_node_create(parent: [*c]c.struct_wlr_scene_tree, color: [*c]const f32) callconv(.c) [*c]c.AcwmDimNode;
extern fn acwm_dim_node_set_enabled(node: [*c]c.AcwmDimNode, enabled: bool) callconv(.c) void;
extern fn client_set_state_colors(cl: [*c]Client, border: [*c]const f32, dim: [*c]const f32) callconv(.c) void;
extern fn get_border_color(cl: [*c]Client) callconv(.c) [*c]f32;
extern fn get_dim_color(cl: [*c]Client) callconv(.c) [*c]f32;
extern fn printstatus(t: c.enum_ipc_watch_type) callconv(.c) void;
extern fn acwm_bar_decoration_set_focus(node: [*c]c.AcwmBarDecoration, focused: bool) callconv(.c) void;

const TAG0: u32 = @as(u32, 1) << 31;

fn VISIBLEON(cl: *const Client, m: *const Monitor) bool {
    if (cl.mon != @as([*c]Monitor, @ptrCast(@constCast(m))))
        return false;
    if (cl.isminimized != 0)
        return false;
    return (cl.tags & m.tagset[m.seltags]) != 0 or cl.isglobal != 0 or cl.isunglobal != 0;
}

fn ISFULLSCREEN(cl: *const Client) bool {
    return cl.isfullscreen != 0 or cl.ismaximizescreen != 0 or
        cl.overview_ismaximizescreenbak != 0 or cl.overview_isfullscreenbak != 0;
}

fn SCRATCHPAD_SHOWN(cl: *const Client) bool {
    return cl.is_in_scratchpad != 0 and cl.isminimized == 0;
}

fn surfaceMapped(cl: *Client) bool {
    const s = client_surface(cl);
    return s != null and s.*.mapped;
}

fn resizeInteract(cl: *Client, geo: Box, interact: i32) void {
    var opts = std.mem.zeroes(c.ResizeOpts);
    opts.interact = interact != 0;
    resize(cl, geo, opts);
}

fn isGrab(cl: *Client) bool {
    return c.server.grab_client != null and @intFromPtr(c.server.grab_client) == @intFromPtr(cl);
}

export fn client_set_floating(cl: *Client, floating: i32) void {
    const old_floating = cl.isfloating;
    cl.isfloating = floating;
    if (cl.mon == null or !surfaceMapped(cl) or cl.iskilling != 0)
        return;

    var target_box = cl.geom;
    var window_size_outofrange = false;

    if (floating == 1 and !isGrab(cl)) {
        if (cl.isfullscreen != 0) {
            client_pending_fullscreen_state(cl, 0);
            client_set_fullscreen(cl, 0);
        }
        client_pending_maximized_state(cl, 0);
        exit_scroller_stack(cl);

        if (client_is_x11(cl) == 0 and cl.iscustompos == 0)
            target_box = client_center_geometry(cl, cl.mon, target_box, 0, 0)
        else
            target_box = cl.geom;

        if (cl.float_geom.width > 0 and cl.float_geom.height > 0) {
            if (cl.mon.*.w.width - @as(i32, @intCast(c.config.gappoh)) <= cl.float_geom.width) {
                cl.float_geom.width = @intFromFloat(@as(f32, @floatFromInt(cl.mon.*.w.width)) * 0.9);
                window_size_outofrange = true;
            }
            if (cl.mon.*.w.height - @as(i32, @intCast(c.config.gappov)) <= cl.float_geom.height) {
                cl.float_geom.height = @intFromFloat(@as(f32, @floatFromInt(cl.mon.*.w.height)) * 0.9);
                window_size_outofrange = true;
            }
            if (window_size_outofrange)
                cl.float_geom = client_center_geometry(cl, cl.mon, cl.float_geom, 0, 0);
            resizeInteract(cl, cl.float_geom, 0);
        } else {
            resizeInteract(cl, target_box, 0);
        }
        cl.need_float_size_reduce = 0;
    } else if (cl.isfloating != 0 and isGrab(cl)) {
        cl.need_float_size_reduce = 0;
    } else {
        cl.need_float_size_reduce = 1;
        cl.is_in_scratchpad = 0;
        cl.isnamedscratchpad = 0;
        set_size_per(cl.mon, cl, false);

        var pos = c.server.clients.next;
        const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
        while (pos != head) : (pos = pos.*.next) {
            const fc = @as(*Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(Client, "link")));
            if (fc != cl and VISIBLEON(fc, cl.mon) and (cl.tags & fc.tags) != 0 and
                ISFULLSCREEN(fc) and old_floating != 0)
                clear_fullscreen_flag(fc);
        }
    }

    client_reparent_group(cl);
    if (cl.force_fakemaximize == 0)
        client_set_maximized(cl, false);
    client_sync_tiled_hint(cl);
    arrange(cl.mon, false, false);

    if (cl.isfloating == 0) {
        cl.old_master_inner_per = cl.master_inner_per;
        cl.old_stack_inner_per = cl.stack_inner_per;
    }
    client_update_border_color(cl);
    printstatus(@intCast(c.IPC_WATCH_ARRANGGE));
}

export fn client_apply_fullscreen(cl: *Client, fullscreen: i32, rearrange: bool) void {
    if (cl.mon == null or !surfaceMapped(cl) or cl.iskilling != 0 or isGrab(cl))
        return;
    if (cl.mon.*.isoverview != 0)
        return;

    cl.isfullscreen = fullscreen;
    client_set_fullscreen(cl, fullscreen);
    client_pending_fullscreen_state(cl, fullscreen);

    if (fullscreen != 0) {
        if (cl.ismaximizescreen != 0 and cl.force_fakemaximize == 0)
            client_set_maximized(cl, false);
        client_pending_maximized_state(cl, 0);
        exit_scroller_stack(cl);
        cl.isfakefullscreen = 0;
        cl.bw = 0;
        if (!is_scroller_layout(cl.mon) or cl.isfloating != 0)
            resizeInteract(cl, cl.mon.*.m, 1);
    } else {
        cl.bw = if (cl.no_border != 0) 0 else c.config.borderpx;
        if (cl.isfloating != 0)
            client_set_floating(cl, 1);
    }

    client_reparent_group(cl);
    check_vrr_enable(cl);
    check_keep_idle_inhibit(cl);
    if (rearrange)
        arrange(cl.mon, false, false);
}

export fn client_set_fake_fullscreen(cl: *Client, fakefullscreen: i32) void {
    cl.isfakefullscreen = fakefullscreen;
    if (cl.mon == null)
        return;
    if (cl.isfullscreen != 0)
        client_apply_fullscreen(cl, 0, true);
    client_set_fullscreen(cl, fakefullscreen);
}

fn maximizeScreenGaps(cl: *Client, gappoh: *i32, gappov: *i32) void {
    gappoh.* = @intCast(c.config.gappoh);
    gappov.* = @intCast(c.config.gappov);
    if (c.config.monocle_no_gap != 0 and cl.mon != null and cl.mon.*.isoverview == 0 and
        is_monocle_layout(cl.mon))
    {
        gappoh.* = 0;
        gappov.* = 0;
    }
}

export fn client_set_maximize_screen(cl: *Client, maximizescreen: i32, rearrange: bool) void {
    if (cl.mon == null or !surfaceMapped(cl) or cl.iskilling != 0 or isGrab(cl))
        return;
    if (cl.mon.*.isoverview != 0)
        return;

    client_pending_maximized_state(cl, maximizescreen);

    if (maximizescreen != 0) {
        if (cl.isfullscreen != 0) {
            client_pending_fullscreen_state(cl, 0);
            client_set_fullscreen(cl, 0);
        }
        exit_scroller_stack(cl);

        var gappoh: i32 = 0;
        var gappov: i32 = 0;
        maximizeScreenGaps(cl, &gappoh, &gappov);

        var box = Box{
            .x = cl.mon.*.w.x + gappoh,
            .y = cl.mon.*.w.y + gappov,
            .width = cl.mon.*.w.width - 2 * gappoh,
            .height = cl.mon.*.w.height - 2 * gappov,
        };
        if (client_wants_group_bar(cl)) {
            box.height -= @intCast(c.config.group_bar_height);
            box.y += @intCast(c.config.group_bar_height);
        }
        if (!is_scroller_layout(cl.mon) or cl.isfloating != 0)
            resizeInteract(cl, box, 0);
    } else {
        cl.bw = if (cl.no_border != 0) 0 else c.config.borderpx;
        if (cl.isfloating != 0)
            client_set_floating(cl, 1);
    }

    client_reparent_group(cl);
    if (cl.force_fakemaximize == 0 and cl.ismaximizescreen == 0)
        client_set_maximized(cl, false)
    else if (cl.force_fakemaximize == 0 and cl.ismaximizescreen != 0)
        client_set_maximized(cl, true);
    if (rearrange)
        arrange(cl.mon, false, false);
}

export fn reset_maximizescreen_size(cl: *Client) void {
    var gappoh: i32 = 0;
    var gappov: i32 = 0;
    maximizeScreenGaps(cl, &gappoh, &gappov);
    var box = Box{
        .x = cl.mon.*.w.x + gappoh,
        .y = cl.mon.*.w.y + gappov,
        .width = cl.mon.*.w.width - 2 * gappoh,
        .height = cl.mon.*.w.height - 2 * gappov,
    };
    if (client_wants_group_bar(cl)) {
        box.height -= @intCast(c.config.group_bar_height);
        box.y += @intCast(c.config.group_bar_height);
    }
    resizeInteract(cl, box, 0);
}

export fn set_minimized(cl: *Client) void {
    if (cl.mon == null or isGrab(cl))
        return;
    cl.isglobal = 0;
    cl.oldtags = cl.mon.*.tagset[cl.mon.*.seltags];
    cl.tags = 0;
    client_pending_minimized_state(cl, 1);
    cl.is_in_scratchpad = 1;
    client_reparent_group(cl);

    client_focus(client_focus_top(c.server.selected_monitor), 1);
    arrange(cl.mon, false, false);
    if (cl.foreign_toplevel != null)
        c.wlr_foreign_toplevel_handle_v1_set_activated(cl.foreign_toplevel, false);

    c.wl_list_remove(&cl.link);
    c.wl_list_insert(c.server.clients.prev, &cl.link);
}

export fn unminimize(cl: *Client) void {
    if (cl.mon == null)
        return;
    if (SCRATCHPAD_SHOWN(cl)) {
        client_pending_minimized_state(cl, 0);
        cl.is_in_scratchpad = 0;
        cl.isnamedscratchpad = 0;
        client_reparent_group(cl);
        client_update_border_color(cl);
        return;
    }
    if (cl.isminimized != 0) {
        set_size_per(cl.mon, cl, false);
        cl.tags = cl.mon.*.tagset[cl.mon.*.seltags];
        cl.is_in_scratchpad = 0;
        cl.isnamedscratchpad = 0;
        client_pending_minimized_state(cl, 0);
        client_reparent_group(cl);
        client_update_border_color(cl);
        arrange(cl.mon, false, false);
        client_focus(cl, 1);
        if (cl.foreign_toplevel != null)
            c.wlr_foreign_toplevel_handle_v1_set_activated(cl.foreign_toplevel, true);
    }
}

export fn exit_scroller_stack(cl: *Client) void {
    if (cl.mon == null or cl.mon.*.pertag == null)
        return;
    const tag = get_client_tag_idx(cl);
    const st = cl.mon.*.pertag.*.scroller_state[tag];
    if (st != null) {
        const node = find_scroller_node(st, cl);
        if (node != null) {
            cl.scroller_proportion = node.*.scroller_proportion;
            cl.scroller_proportion_single = node.*.scroller_proportion_single;
            cl.scroller_stack_proportion = node.*.scroller_stack_weight;
            scroller_node_remove(st, node);
        }
    }
}

export fn clear_fullscreen_and_maximized_state(m: [*c]Monitor) void {
    var pos = c.server.clients.next;
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const fc = @as(*Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(Client, "link")));
        if (VISIBLEON(fc, m) and ISFULLSCREEN(fc))
            clear_fullscreen_flag(fc);
    }
}

export fn clear_fullscreen_flag(cl: *Client) void {
    if (cl.mon == null or cl.mon.*.pertag == null)
        return;
    const layout = cl.mon.*.pertag.*.ltidxs[get_client_tag_idx(cl)];
    if (layout != null and (layout.*.id == c.SCROLLER or layout.*.id == c.VERTICAL_SCROLLER) and
        cl.isfloating == 0)
        return;
    if (cl.isfullscreen != 0)
        client_apply_fullscreen(cl, 0, true);
    if (cl.ismaximizescreen != 0)
        client_set_maximize_screen(cl, 0, true);
}

export fn client_pending_fullscreen_state(cl: *Client, isfullscreen: i32) void {
    cl.isfullscreen = isfullscreen;
    if (cl.foreign_toplevel != null and cl.iskilling == 0)
        c.wlr_foreign_toplevel_handle_v1_set_fullscreen(cl.foreign_toplevel, isfullscreen != 0);
}

export fn client_pending_maximized_state(cl: *Client, ismaximized: i32) void {
    cl.ismaximizescreen = ismaximized;
    if (cl.foreign_toplevel != null and cl.iskilling == 0)
        c.wlr_foreign_toplevel_handle_v1_set_maximized(cl.foreign_toplevel, ismaximized != 0);
}

export fn client_pending_minimized_state(cl: *Client, isminimized: i32) void {
    cl.isminimized = isminimized;
    if (cl.foreign_toplevel != null and cl.iskilling == 0)
        c.wlr_foreign_toplevel_handle_v1_set_minimized(cl.foreign_toplevel, isminimized != 0);
}

export fn show_scratchpad(cl: *Client) void {
    if (cl.isfullscreen != 0 or cl.ismaximizescreen != 0) {
        client_pending_fullscreen_state(cl, 0);
        client_pending_maximized_state(cl, 0);
        cl.bw = if (cl.no_border != 0) 0 else c.config.borderpx;
    }
    if (cl.isfloating == 0) {
        client_set_floating(cl, 1);
        cl.geom.width = if (cl.iscustomsize != 0)
            cl.float_geom.width
        else
            @intFromFloat(@as(f32, @floatFromInt(cl.mon.*.w.width)) * c.config.scratchpad_width_ratio);
        cl.geom.height = if (cl.iscustomsize != 0)
            cl.float_geom.height
        else
            @intFromFloat(@as(f32, @floatFromInt(cl.mon.*.w.height)) * c.config.scratchpad_height_ratio);
        const centered = client_center_geometry(cl, cl.mon, cl.geom, 0, 0);
        cl.float_geom = centered;
        cl.geom = centered;
        cl.animainit_geom = centered;
        cl.animation.current = centered;
        cl.iscustomsize = 1;
        resizeInteract(cl, cl.geom, 0);
    }
    client_reparent_group(cl);
    cl.oldtags = cl.mon.*.tagset[cl.mon.*.seltags];
    c.wl_list_safe_reinsert_next(&c.server.clients, &cl.link);
    show_hide_client(cl);
    client_update_border_color(cl);
}

export fn switch_scratchpad_client_state(cl: *Client) bool {
    if (cl.mon == null)
        return false;

    if (c.config.scratchpad_cross_monitor != 0 and c.server.selected_monitor != null and
        cl.mon != c.server.selected_monitor and cl.is_in_scratchpad != 0)
    {
        const oldmon = cl.mon;
        cl.scratchpad_switching_mon = true;
        cl.mon = c.server.selected_monitor;
        reset_foreign_tolevel(cl, oldmon, cl.mon);
        client_update_oldmonname_record(cl, c.server.selected_monitor);

        cl.float_geom.width = @divTrunc(cl.float_geom.width * cl.mon.*.w.width, oldmon.*.w.width);
        cl.float_geom.height = @divTrunc(cl.float_geom.height * cl.mon.*.w.height, oldmon.*.w.height);
        cl.float_geom = client_center_geometry(cl, cl.mon, cl.float_geom, 0, 0);

        if (SCRATCHPAD_SHOWN(cl)) {
            cl.tags = get_tags_first_tag(c.server.selected_monitor.*.tagset[c.server.selected_monitor.*.seltags]);
            resizeInteract(cl, cl.float_geom, 0);
            arrange(c.server.selected_monitor, false, false);
            client_focus(cl, 1);
            cl.scratchpad_switching_mon = false;
            return true;
        } else {
            resizeInteract(cl, cl.float_geom, 0);
            cl.scratchpad_switching_mon = false;
        }
    }

    if (SCRATCHPAD_SHOWN(cl) and (cl.mon.*.tagset[cl.mon.*.seltags] & cl.tags) != 0) {
        set_minimized(cl);
        return true;
    } else if (cl.is_in_scratchpad != 0) {
        cl.tags = cl.mon.*.tagset[cl.mon.*.seltags];
        cl.oldtags = cl.tags;
        cl.scratchpad_tagin = true;
        if (SCRATCHPAD_SHOWN(cl)) {
            arrange(cl.mon, false, false);
            client_focus(cl, 1);
        } else {
            show_scratchpad(cl);
        }
        return true;
    }
    return false;
}

export fn apply_named_scratchpad(target: *Client) void {
    var pos = c.server.clients.next;
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = @as(*Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(Client, "link")));
        if (c.config.scratchpad_cross_monitor == 0 and
            cl.mon != c.server.selected_monitor)
            continue;
        if (c.config.single_scratchpad != 0 and SCRATCHPAD_SHOWN(cl) and cl != target)
            set_minimized(cl);
    }
    if (target.is_in_scratchpad == 0) {
        set_minimized(target);
        _ = switch_scratchpad_client_state(target);
    } else {
        _ = switch_scratchpad_client_state(target);
    }
}

export fn client_update_border_color(cl: ?*Client) void {
    const client = cl orelse return;
    if (client.mon == null)
        return;
    const border_color = get_border_color(client);
    const dim_color = get_dim_color(client);
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        client.opacity_animation.target_border_color[i] = border_color[i];
        client.opacity_animation.target_dim_color[i] = dim_color[i];
    }
    client_set_state_colors(client, border_color, dim_color);
}

export fn client_add_dim_node(cl: *Client) void {
    if (cl.scene_surface == null)
        return;
    cl.dim_node = acwm_dim_node_create(cl.scene_surface, &c.config.dim_unfocused_color);
    if (cl.dim_node == null)
        return;
    acwm_dim_node_set_enabled(cl.dim_node, false);
}

export fn client_exchange(c1: ?*Client, c2: ?*Client) void {
    const a = c1 orelse return;
    const b = c2 orelse return;
    if (c.config.exchange_cross_monitor == 0 and a.mon != b.mon)
        return;
    if (a.mon == null or b.mon == null or a.mon.*.pertag == null or b.mon.*.pertag == null)
        return;
    const layout1 = a.mon.*.pertag.*.ltidxs[get_client_tag_idx(a)];
    const layout2 = b.mon.*.pertag.*.ltidxs[get_client_tag_idx(b)];
    if (layout1 == null or layout2 == null)
        return;
    if (layout1.*.id == c.SCROLLER or layout2.*.id == c.SCROLLER or
        layout1.*.id == c.VERTICAL_SCROLLER or layout2.*.id == c.VERTICAL_SCROLLER)
    {
        exchange_two_scroller_clients(a, b);
        return;
    }
    if (layout1.*.id == c.DWINDLE and layout2.*.id == c.DWINDLE) {
        dwindle_swap_clients(a, b);
        return;
    }
    client_swap_layout_properties(a, b);
    c.wl_list_swap(&a.link, &b.link);
    if (a.mon != b.mon)
        client_swap_monitors_and_tags(a, b);
    finish_exchange_arrange_and_focus(a, b, a.mon, b.mon);
}

export fn client_is_parked(cl: ?*Client) bool {
    const client = cl orelse return false;
    return c.wl_list_empty(&client.link) != 0;
}

fn clientUnlink(cl: *Client) void {
    if (client_is_parked(cl))
        return;
    c.wl_list_remove(&cl.link);
    c.wl_list_init(&cl.link);
    c.wl_list_remove(&cl.flink);
    c.wl_list_init(&cl.flink);
}

export fn client_park(cl: *Client) void {
    if (cl.tab_prev != null or cl.tab_next != null)
        tab_detach_client(cl);
    clientUnlink(cl);
    cl.animation.running = false;
    cl.mon = null;
}

export fn client_unpark(cl: *Client, anchor: ?*Client) void {
    const a = anchor;
    if (a != null and !client_is_parked(a.?)) {
        c.wl_list_safe_reinsert_next(&a.?.link, &cl.link);
        c.wl_list_safe_reinsert_prev(&a.?.flink, &cl.flink);
    } else if (client_is_parked(cl)) {
        c.wl_list_insert(c.server.clients.prev, &cl.link);
        c.wl_list_insert(&c.server.focus_stack, &cl.flink);
    }
}

export fn client_replace(cl: *Client, w: *Client, is_group_change_member: bool, is_swallow: bool) void {
    cl.bw = w.bw;
    cl.isfloating = w.isfloating;
    cl.isurgent = w.isurgent;
    cl.is_in_scratchpad = w.is_in_scratchpad;
    cl.tags = w.tags;
    cl.geom = w.geom;
    cl.float_geom = w.float_geom;
    cl.stack_inner_per = w.stack_inner_per;
    cl.master_inner_per = w.master_inner_per;
    cl.stack_size_weight = w.stack_size_weight;
    cl.master_size_weight = w.master_size_weight;
    cl.master_mfact_per = w.master_mfact_per;
    cl.scroller_proportion = w.scroller_proportion;
    cl.isglobal = w.isglobal;
    cl.overview_backup_geom = w.overview_backup_geom;
    cl.animation.current = w.animation.current;
    cl.scroller_stack_proportion = w.scroller_stack_proportion;

    if (is_swallow or !is_group_change_member)
        client_group_replace(w, cl);
    tab_replace_client(w, cl);
    client_unpark(cl, w);
    acwm_bar_decoration_set_focus(cl.group_bar, c.server.selected_monitor != null and
        cl == c.server.selected_monitor.*.sel);

    overview_destroy_card(w);
    if (w.overview_scene_surface != null)
        w.overview_scene_surface = null;
    if (cl.mon != null and cl.mon.*.isoverview != 0)
        overview_backup_surface(cl);

    if (w.group_bar != null and !is_group_change_member)
        c.wlr_scene_node_set_enabled(&w.group_bar.*.scene.*.node, false);
    if (w.jump_label_node != null and w.jump_label_node.*.scene != null)
        c.wlr_scene_node_set_enabled(&w.jump_label_node.*.scene.*.node, false);

    cl.tag_visible = w.tag_visible;
    w.tag_visible = false;
    client_update_visibility(w);
    client_update_visibility(cl);

    if (w.foreign_toplevel != null) {
        if (w.mon != null)
            c.wlr_foreign_toplevel_handle_v1_output_leave(w.foreign_toplevel, w.mon.*.wlr_output);
        c.wlr_foreign_toplevel_handle_v1_destroy(w.foreign_toplevel);
        w.foreign_toplevel = null;
    }
    if (cl.foreign_toplevel == null and cl.mon != null)
        add_foreign_toplevel(cl)
    else if (cl.foreign_toplevel != null and cl.mon != null)
        c.wlr_foreign_toplevel_handle_v1_output_enter(cl.foreign_toplevel, cl.mon.*.wlr_output);

    client_pending_fullscreen_state(cl, w.isfullscreen);
    client_pending_maximized_state(cl, w.ismaximizescreen);
    client_pending_minimized_state(cl, w.isminimized);

    if (w.mon == null or w.mon.*.pertag == null)
        return;
    const layout = w.mon.*.pertag.*.ltidxs[get_client_tag_idx(w)];
    if (layout == null)
        return;

    if (layout.*.id == c.DWINDLE or layout.*.id == c.SCROLLER or layout.*.id == c.VERTICAL_SCROLLER) {
        var t: usize = 0;
        while (t < 32) : (t += 1) {
            if (layout.*.id == c.DWINDLE) {
                const root = &w.mon.*.pertag.*.dwindle_root[t];
                dwindle_remove(root, cl);
                const dnode = dwindle_find_leaf(root.*, w);
                if (dnode != null)
                    dnode.*.client = cl;
            }
            if (layout.*.id == c.SCROLLER or layout.*.id == c.VERTICAL_SCROLLER) {
                const st = w.mon.*.pertag.*.scroller_state[t];
                if (st == null)
                    continue;
                const cn = find_scroller_node(st, cl);
                if (cn != null)
                    scroller_node_remove(st, cn);
                const wn = find_scroller_node(st, w);
                if (wn != null)
                    wn.*.client = cl;
            }
        }
    }

    if (layout.*.id == c.SCROLLER or layout.*.id == c.VERTICAL_SCROLLER)
        sync_scroller_state_to_clients(w.mon, get_client_tag_idx(w));

    if (w.iskilling != 0)
        clientUnlink(w)
    else
        client_park(w);
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/client_transition_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_list_insert_calls: c_int;
extern var stub_list_remove_calls: c_int;
extern var stub_list_swap_calls: c_int;
extern var stub_reinsert_next_calls: c_int;
extern var stub_reinsert_prev_calls: c_int;
extern var stub_surface: c.struct_wlr_surface;
extern var stub_x11: i32;
extern var stub_set_fs_calls: c_int;
extern var stub_set_fs_value: i32;
extern var stub_set_max_calls: c_int;
extern var stub_set_max_value: bool;
extern var stub_tiled_hint_calls: c_int;
extern var stub_visibility_calls: c_int;
extern var stub_reparent_group_calls: c_int;
extern var stub_group_replace_calls: c_int;
extern var stub_oldmonname_calls: c_int;
extern var stub_group_bar: bool;
extern var stub_swap_props_calls: c_int;
extern var stub_swap_mon_calls: c_int;
extern var stub_finish_exchange_calls: c_int;
extern var stub_exchange_scroller_calls: c_int;
extern var stub_exchange_dwindle_calls: c_int;
extern var stub_dwindle_remove_calls: c_int;
extern var stub_dwindle_leaf: [*c]DwindleNode;
extern var stub_sync_scroller_calls: c_int;
extern var stub_scroller_node: [*c]ScrollerStackNode;
extern var stub_scroller_remove_calls: c_int;
extern var stub_tab_detach_calls: c_int;
extern var stub_tab_replace_calls: c_int;
extern var stub_show_hide_calls: c_int;
extern var stub_add_foreign_calls: c_int;
extern var stub_overview_destroy_calls: c_int;
extern var stub_overview_backup_calls: c_int;
extern var stub_reset_foreign_calls: c_int;
extern var stub_center_box: Box;
extern var stub_center_passthrough: bool;
extern var stub_center_calls: c_int;
extern var stub_tag_idx: u32;
extern var stub_first_tag: u32;
extern var stub_scroller_layout: bool;
extern var stub_monocle_layout: bool;
extern var stub_size_per_calls: c_int;
extern var stub_arrange_calls: c_int;
extern var stub_resize_calls: c_int;
extern var stub_resize_geo: Box;
extern var stub_resize_interact: i32;
extern var stub_focus_calls: c_int;
extern var stub_top_client: [*c]Client;
extern var stub_vrr_calls: c_int;
extern var stub_idle_calls: c_int;
extern var stub_dim: c.AcwmDimNode;
extern var stub_dim_enable_calls: c_int;
extern var stub_state_colors_calls: c_int;
extern var stub_border: [4]f32;
extern var stub_dimc: [4]f32;
extern var stub_printstatus_calls: c_int;
extern var stub_ft_full_calls: c_int;
extern var stub_ft_max_calls: c_int;
extern var stub_ft_min_calls: c_int;
extern var stub_ft_activate_calls: c_int;
extern var stub_node_enable_calls: c_int;
extern var stub_bar_focus_calls: c_int;

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

fn resetTransWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    listInit(&c.server.clients);
    listInit(&c.server.monitors);
    listInit(&c.server.focus_stack);
    c.config.borderpx = 2;
    c.config.gappoh = 10;
    c.config.gappov = 20;
    stub_surface.mapped = true;
    stub_list_insert_calls = 0;
    stub_list_remove_calls = 0;
    stub_list_swap_calls = 0;
    stub_reinsert_next_calls = 0;
    stub_reinsert_prev_calls = 0;
    stub_x11 = 0;
    stub_set_fs_calls = 0;
    stub_set_fs_value = -1;
    stub_set_max_calls = 0;
    stub_set_max_value = false;
    stub_tiled_hint_calls = 0;
    stub_visibility_calls = 0;
    stub_reparent_group_calls = 0;
    stub_group_replace_calls = 0;
    stub_oldmonname_calls = 0;
    stub_group_bar = false;
    stub_swap_props_calls = 0;
    stub_swap_mon_calls = 0;
    stub_finish_exchange_calls = 0;
    stub_exchange_scroller_calls = 0;
    stub_exchange_dwindle_calls = 0;
    stub_dwindle_remove_calls = 0;
    stub_dwindle_leaf = null;
    stub_sync_scroller_calls = 0;
    stub_scroller_node = null;
    stub_scroller_remove_calls = 0;
    stub_tab_detach_calls = 0;
    stub_tab_replace_calls = 0;
    stub_show_hide_calls = 0;
    stub_add_foreign_calls = 0;
    stub_overview_destroy_calls = 0;
    stub_overview_backup_calls = 0;
    stub_reset_foreign_calls = 0;
    stub_center_box = std.mem.zeroes(Box);
    stub_center_passthrough = false;
    stub_center_calls = 0;
    stub_tag_idx = 0;
    stub_first_tag = 1;
    stub_scroller_layout = false;
    stub_monocle_layout = false;
    stub_size_per_calls = 0;
    stub_arrange_calls = 0;
    stub_resize_calls = 0;
    stub_resize_geo = std.mem.zeroes(Box);
    stub_resize_interact = -1;
    stub_focus_calls = 0;
    stub_top_client = null;
    stub_vrr_calls = 0;
    stub_idle_calls = 0;
    stub_dim_enable_calls = 0;
    stub_state_colors_calls = 0;
    stub_printstatus_calls = 0;
    stub_ft_full_calls = 0;
    stub_ft_max_calls = 0;
    stub_ft_min_calls = 0;
    stub_ft_activate_calls = 0;
    stub_node_enable_calls = 0;
    stub_bar_focus_calls = 0;
}

fn baseMon(m: *Monitor, p: *c.Pertag, layout: ?*c.Layout) void {
    m.* = std.mem.zeroes(Monitor);
    p.* = std.mem.zeroes(c.Pertag);
    m.pertag = p;
    m.w = mkBox(0, 0, 1000, 800);
    m.m = m.w;
    m.tagset[0] = 1;
    m.seltags = 0;
    if (layout) |l|
        p.ltidxs[0] = l;
}

test "pending state setters update foreign toplevels" {
    resetTransWorld();
    var cl: Client = std.mem.zeroes(Client);
    cl.foreign_toplevel = @ptrFromInt(0x1000);
    client_pending_fullscreen_state(&cl, 1);
    client_pending_maximized_state(&cl, 1);
    client_pending_minimized_state(&cl, 1);
    try testing.expectEqual(@as(i32, 1), cl.isfullscreen);
    try testing.expectEqual(@as(i32, 1), cl.ismaximizescreen);
    try testing.expectEqual(@as(i32, 1), cl.isminimized);
    try testing.expectEqual(@as(c_int, 1), stub_ft_full_calls);
    try testing.expectEqual(@as(c_int, 1), stub_ft_max_calls);
    try testing.expectEqual(@as(c_int, 1), stub_ft_min_calls);
    cl.iskilling = 1;
    client_pending_fullscreen_state(&cl, 0);
    try testing.expectEqual(@as(c_int, 1), stub_ft_full_calls);
}

test "floating transitions resize, clamp and clear peers" {
    resetTransWorld();
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var m: Monitor = std.mem.zeroes(Monitor);
    baseMon(&m, &p, null);
    var cl: Client = std.mem.zeroes(Client);
    cl.mon = &m;
    cl.geom = mkBox(10, 10, 300, 200);
    cl.float_geom = mkBox(0, 0, 300, 200);
    cl.isfullscreen = 1;
    cl.ismaximizescreen = 1;
    stub_center_box = mkBox(100, 100, 300, 200);

    client_set_floating(&cl, 1);
    try testing.expectEqual(@as(c_int, 1), stub_set_fs_calls);
    try testing.expectEqual(@as(i32, 0), stub_set_fs_value);
    try testing.expectEqual(@as(i32, 0), cl.isfullscreen);
    try testing.expectEqual(@as(i32, 0), cl.ismaximizescreen);
    try testing.expectEqual(@as(c_int, 1), stub_center_calls);
    try testing.expectEqual(@as(i32, 0), stub_resize_geo.x);
    try testing.expectEqual(@as(i32, 300), stub_resize_geo.width);
    try testing.expectEqual(@as(i32, 0), stub_resize_interact);
    try testing.expectEqual(@as(i32, 0), cl.need_float_size_reduce);
    try testing.expect(!stub_set_max_value);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);
    try testing.expectEqual(@as(c_int, 1), stub_printstatus_calls);

    cl.isfloating = 1;
    cl.float_geom = mkBox(0, 0, 990, 790);
    stub_center_passthrough = true;
    stub_resize_calls = 0;
    client_set_floating(&cl, 1);
    try testing.expectEqual(@as(i32, 900), cl.float_geom.width);
    try testing.expectEqual(@as(i32, 720), cl.float_geom.height);

    resetTransWorld();
    baseMon(&m, &p, null);
    cl = std.mem.zeroes(Client);
    cl.mon = &m;
    cl.isfloating = 1;
    cl.geom = mkBox(0, 0, 100, 100);
    cl.tags = 1;
    var peer: Client = std.mem.zeroes(Client);
    peer.mon = &m;
    peer.tags = 1;
    peer.isfullscreen = 1;
    listInsert(&c.server.clients, &peer.link);
    client_set_floating(&cl, 0);
    try testing.expectEqual(@as(i32, 1), cl.need_float_size_reduce);
    try testing.expectEqual(@as(c_int, 1), stub_size_per_calls);
    try testing.expectEqual(@as(i32, 0), peer.isfullscreen);
}

test "fullscreen and maximize-screen apply geometry and gaps" {
    resetTransWorld();
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var m: Monitor = std.mem.zeroes(Monitor);
    baseMon(&m, &p, null);
    var cl: Client = std.mem.zeroes(Client);
    cl.mon = &m;
    cl.geom = mkBox(0, 0, 100, 100);
    cl.ismaximizescreen = 1;

    client_apply_fullscreen(&cl, 1, true);
    try testing.expectEqual(@as(i32, 1), cl.isfullscreen);
    try testing.expectEqual(@as(u32, 0), cl.bw);
    try testing.expectEqual(@as(c_int, 1), stub_resize_calls);
    try testing.expectEqual(@as(i32, 1000), stub_resize_geo.width);
    try testing.expectEqual(@as(i32, 1), stub_resize_interact);
    try testing.expectEqual(@as(c_int, 1), stub_vrr_calls);
    try testing.expectEqual(@as(c_int, 1), stub_idle_calls);

    cl.isfloating = 1;
    cl.no_border = 0;
    stub_resize_calls = 0;
    client_apply_fullscreen(&cl, 0, true);
    try testing.expectEqual(@as(u32, 2), cl.bw);
    try testing.expect(stub_arrange_calls >= 2);

    cl = std.mem.zeroes(Client);
    cl.mon = &m;
    cl.geom = mkBox(0, 0, 100, 100);
    client_set_maximize_screen(&cl, 1, true);
    try testing.expectEqual(@as(i32, 1), cl.ismaximizescreen);
    try testing.expectEqual(@as(i32, 10), stub_resize_geo.x);
    try testing.expectEqual(@as(i32, 20), stub_resize_geo.y);
    try testing.expectEqual(@as(i32, 980), stub_resize_geo.width);
    try testing.expectEqual(@as(i32, 760), stub_resize_geo.height);

    stub_group_bar = true;
    c.config.group_bar_height = 30;
    cl.ismaximizescreen = 1;
    stub_resize_calls = 0;
    client_set_maximize_screen(&cl, 1, true);
    try testing.expectEqual(@as(i32, 50), stub_resize_geo.y);
    try testing.expectEqual(@as(i32, 730), stub_resize_geo.height);

    c.config.monocle_no_gap = 1;
    stub_monocle_layout = true;
    stub_resize_calls = 0;
    reset_maximizescreen_size(&cl);
    try testing.expectEqual(@as(i32, 0), stub_resize_geo.x);
    try testing.expectEqual(@as(i32, 1000), stub_resize_geo.width);
}

test "minimize and unminimize preserve tags and scratchpads" {
    resetTransWorld();
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var m: Monitor = std.mem.zeroes(Monitor);
    baseMon(&m, &p, null);
    m.tagset[0] = 0b101;
    var cl: Client = std.mem.zeroes(Client);
    cl.mon = &m;
    cl.tags = 1;
    cl.isglobal = 1;
    cl.foreign_toplevel = @ptrFromInt(0x1000);
    listInsert(&c.server.clients, &cl.link);
    stub_top_client = &cl;
    set_minimized(&cl);
    try testing.expectEqual(@as(i32, 0), cl.isglobal);
    try testing.expectEqual(@as(u32, 0b101), cl.oldtags);
    try testing.expectEqual(@as(u32, 0), cl.tags);
    try testing.expectEqual(@as(i32, 1), cl.isminimized);
    try testing.expectEqual(@as(i32, 1), cl.is_in_scratchpad);
    try testing.expectEqual(@as(c_int, 1), stub_focus_calls);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);
    try testing.expectEqual(@as(c_int, 1), stub_ft_activate_calls);
    try testing.expectEqual(@as(c_int, 1), stub_list_remove_calls);

    cl.is_in_scratchpad = 1;
    cl.isminimized = 0;
    client_update_border_color(&cl);
    unminimize(&cl);
    try testing.expectEqual(@as(i32, 0), cl.is_in_scratchpad);

    resetTransWorld();
    baseMon(&m, &p, null);
    cl = std.mem.zeroes(Client);
    cl.mon = &m;
    cl.isminimized = 1;
    cl.tags = 0;
    cl.foreign_toplevel = @ptrFromInt(0x1000);
    unminimize(&cl);
    try testing.expectEqual(@as(u32, 1), cl.tags);
    try testing.expectEqual(@as(i32, 0), cl.isminimized);
    try testing.expectEqual(@as(c_int, 1), stub_focus_calls);
    try testing.expectEqual(@as(c_int, 1), stub_ft_activate_calls);
}

test "scroller stack exit restores proportions and clears modes" {
    resetTransWorld();
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var m: Monitor = std.mem.zeroes(Monitor);
    var layout: c.Layout = std.mem.zeroes(c.Layout);
    baseMon(&m, &p, &layout);
    var cl: Client = std.mem.zeroes(Client);
    cl.mon = &m;
    var node: c.struct_ScrollerStackNode = std.mem.zeroes(c.struct_ScrollerStackNode);
    node.scroller_proportion = 0.7;
    node.scroller_proportion_single = 0.6;
    node.scroller_stack_weight = 0.5;
    stub_scroller_node = &node;
    var st: c.struct_TagScrollerState = std.mem.zeroes(c.struct_TagScrollerState);
    p.scroller_state[0] = &st;
    exit_scroller_stack(&cl);
    try testing.expectApproxEqAbs(@as(f32, 0.7), cl.scroller_proportion, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.5), cl.scroller_stack_proportion, 1e-6);
    try testing.expectEqual(@as(c_int, 1), stub_scroller_remove_calls);

    layout.id = @intCast(c.SCROLLER);
    cl.isfloating = 0;
    cl.isfullscreen = 1;
    stub_set_fs_calls = 0;
    clear_fullscreen_flag(&cl);
    try testing.expectEqual(@as(c_int, 0), stub_set_fs_calls);
    cl.isfloating = 1;
    clear_fullscreen_flag(&cl);
    try testing.expectEqual(@as(c_int, 1), stub_set_fs_calls);
}

test "scratchpad show and switching move clients between tags" {
    resetTransWorld();
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var m: Monitor = std.mem.zeroes(Monitor);
    baseMon(&m, &p, null);
    var cl: Client = std.mem.zeroes(Client);
    cl.mon = &m;
    cl.geom = mkBox(0, 0, 100, 100);
    cl.isfloating = 0;
    stub_center_box = mkBox(500, 400, 600, 500);
    c.config.scratchpad_width_ratio = 0.6;
    c.config.scratchpad_height_ratio = 0.5;

    show_scratchpad(&cl);
    try testing.expectEqual(@as(i32, 1), cl.isfloating);
    try testing.expectEqual(@as(i32, 1), cl.iscustomsize);
    try testing.expectEqual(@as(i32, 600), cl.geom.width);
    try testing.expectEqual(@as(i32, 500), cl.geom.height);
    try testing.expectEqual(@as(i32, 500), cl.float_geom.x);
    try testing.expectEqual(@as(c_int, 1), stub_show_hide_calls);
    try testing.expectEqual(@as(c_int, 2), stub_resize_calls);

    c.server.selected_monitor = &m;
    cl.is_in_scratchpad = 1;
    cl.isminimized = 0;
    cl.tags = 1;
    m.tagset[0] = 1;
    try testing.expect(switch_scratchpad_client_state(&cl));
    try testing.expectEqual(@as(i32, 1), cl.isminimized);

    cl.isminimized = 1;
    cl.is_in_scratchpad = 1;
    m.tagset[0] = 0b10;
    cl.tags = 0b10;
    try testing.expect(switch_scratchpad_client_state(&cl));
    try testing.expectEqual(@as(u32, 0b10), cl.tags);
    try testing.expect(cl.scratchpad_tagin);
}

test "border colors, dim nodes and exchange paths" {
    resetTransWorld();
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var m: Monitor = std.mem.zeroes(c.Monitor);
    baseMon(&m, &p, null);
    var cl: Client = std.mem.zeroes(Client);
    cl.mon = &m;
    client_update_border_color(&cl);
    try testing.expectEqual(@as(c_int, 1), stub_state_colors_calls);
    try testing.expectApproxEqAbs(@as(f32, 1), cl.opacity_animation.target_border_color[0], 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.5), cl.opacity_animation.target_dim_color[3], 1e-6);

    var scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    cl.scene_surface = &scene;
    client_add_dim_node(&cl);
    try testing.expect(cl.dim_node != null);
    try testing.expectEqual(@as(c_int, 1), stub_dim_enable_calls);

    var b: Client = std.mem.zeroes(Client);
    b.mon = &m;
    c.config.exchange_cross_monitor = 1;
    var layout: c.Layout = std.mem.zeroes(c.Layout);
    p.ltidxs[0] = &layout;
    layout.id = @intCast(c.SCROLLER);
    client_exchange(&cl, &b);
    try testing.expectEqual(@as(c_int, 1), stub_exchange_scroller_calls);
    layout.id = @intCast(c.DWINDLE);
    client_exchange(&cl, &b);
    try testing.expectEqual(@as(c_int, 1), stub_exchange_dwindle_calls);
    layout.id = @intCast(c.TILE);
    client_exchange(&cl, &b);
    try testing.expectEqual(@as(c_int, 1), stub_swap_props_calls);
    try testing.expectEqual(@as(c_int, 1), stub_list_swap_calls);
}

test "parking and replacing transfer state and foreign handles" {
    resetTransWorld();
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var m: Monitor = std.mem.zeroes(Monitor);
    var layout: c.Layout = std.mem.zeroes(c.Layout);
    baseMon(&m, &p, &layout);
    layout.id = @intCast(c.TILE);
    var old: Client = std.mem.zeroes(Client);
    old.mon = &m;
    old.tags = 0b10;
    old.geom = mkBox(1, 2, 300, 200);
    old.float_geom = old.geom;
    old.isfloating = 1;
    old.bw = 3;
    old.tag_visible = true;
    old.isminimized = 1;
    old.foreign_toplevel = @ptrFromInt(0x1000);
    listInsert(&c.server.clients, &old.link);
    listInsert(&c.server.focus_stack, &old.flink);

    var cl: Client = std.mem.zeroes(Client);
    cl.mon = &m;
    client_replace(&cl, &old, false, true);
    try testing.expectEqual(@as(u32, 0b10), cl.tags);
    try testing.expectEqual(@as(i32, 300), cl.geom.width);
    try testing.expectEqual(@as(u32, 3), cl.bw);
    try testing.expectEqual(@as(i32, 1), cl.isfloating);
    try testing.expect(!old.tag_visible);
    try testing.expect(cl.tag_visible);
    try testing.expectEqual(@as(c_int, 1), stub_group_replace_calls);
    try testing.expectEqual(@as(c_int, 1), stub_tab_replace_calls);
    try testing.expectEqual(@as(c_int, 2), stub_visibility_calls);
    try testing.expectEqual(@as(c_int, 1), stub_add_foreign_calls);
    try testing.expect(old.foreign_toplevel == null);
    try testing.expectEqual(@as(i32, 1), cl.isminimized);

    var parked: Client = std.mem.zeroes(Client);
    parked.mon = &m;
    client_park(&parked);
    try testing.expect(client_is_parked(&parked));
    client_unpark(&parked, null);
    try testing.expect(!client_is_parked(&parked));
    try testing.expect(stub_list_insert_calls >= 2);
}
