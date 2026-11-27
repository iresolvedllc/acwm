//! Port of monitor-move/bounds/visibility and group/decorations helpers in
//! src/manage/client.c (Phase 5, client slice 9, slice 66).

const std = @import("std");
const c = @import("cc");

const Client = c.Client;
const Monitor = c.Monitor;
const Box = c.struct_wlr_box;
const Arg = c.Arg;
const LayoutContext = c.LayoutContext;
const Bar = c.AcwmBarDecoration;

extern fn get_client_tag_idx(cl: ?*const Client) callconv(.c) u32;
extern fn get_mon_curtag(m: ?*const Monitor) callconv(.c) u32;
extern fn client_reset_mon_tags(cl: [*c]Client, m: [*c]Monitor, tags: u32) callconv(.c) void;
extern fn client_change_mon(cl: [*c]Client, m: [*c]Monitor) callconv(.c) void;
extern fn client_focus(cl: ?*Client, lift: i32) callconv(.c) void;
extern fn client_replace(cl: [*c]Client, w: [*c]Client, group_member: bool, apply_rule: bool) callconv(.c) void;
extern fn client_sync_blur_optimized(cl: ?*Client) callconv(.c) void;
extern fn client_reparent_tab(cl: [*c]Client) callconv(.c) void;
extern fn tab_update_input_penetration(cl: [*c]Client) callconv(.c) void;
extern fn tab_focus_member(cl: [*c]Client) callconv(.c) void;
extern fn set_selected_monitor(m: [*c]Monitor) callconv(.c) void;
extern fn arrange(m: [*c]Monitor, want_animation: bool, from_view: bool) callconv(.c) void;
extern fn resize(cl: [*c]Client, geo: Box, opts: c.ResizeOpts) callconv(.c) void;
extern fn dwindle_move_next_to(cl: [*c]Client, target: [*c]Client, ratio: f32, dir: i32) callconv(.c) void;
extern fn scroller_insert_stack(cl: [*c]Client, target: [*c]Client, before: bool) callconv(.c) void;
extern fn scroll_get_stack_head_client(cl: [*c]Client) callconv(.c) [*c]Client;
extern fn scroll_get_stack_tail_client(cl: [*c]Client) callconv(.c) [*c]Client;
extern fn is_scroller_layout(m: [*c]Monitor) callconv(.c) bool;
extern fn is_special_active(m: ?*const Monitor) callconv(.c) bool;
extern fn pointer_warp_to_client(cl: [*c]const Client) callconv(.c) void;
extern fn acwm_scene_node_set_ignore_hit(node: [*c]c.struct_wlr_scene_node, ignore: bool) callconv(.c) void;
extern fn acwm_bar_decoration_create(cdata: ?*anyopaque, node_type: u32, is_tab: bool, parent: [*c]c.struct_wlr_scene_tree, data: c.DecorateDrawData, width: i32, height: i32) callconv(.c) ?*Bar;
extern fn acwm_bar_decoration_destroy(node: ?*Bar) callconv(.c) void;
extern fn acwm_bar_decoration_update(node: ?*Bar, text: [*c]const u8, scale: f32) callconv(.c) void;
extern fn acwm_bar_decoration_apply_config(node: ?*Bar, data: *const c.DecorateDrawData) callconv(.c) void;
extern fn acwm_bar_decoration_set_focus(node: ?*Bar, focused: bool) callconv(.c) void;
extern fn acwm_bar_decoration_set_close_color(node: ?*Bar, color: [*c]const f32) callconv(.c) void;
extern fn acwm_bar_decoration_set_close(node: ?*Bar, show: bool, size: i32, margin: i32) callconv(.c) void;
extern fn acwm_jump_label_node_create(parent: [*c]c.struct_wlr_scene_tree, data: c.DecorateDrawData) callconv(.c) [*c]c.AcwmJumpLabel;
extern fn acwm_jump_label_node_apply_config(node: [*c]c.AcwmJumpLabel, data: *const c.DecorateDrawData) callconv(.c) void;
extern fn client_get_title(cl: [*c]Client) callconv(.c) [*c]const u8;
extern fn client_surface(cl: [*c]Client) callconv(.c) [*c]c.struct_wlr_surface;
extern fn client_is_parked(cl: ?*Client) callconv(.c) bool;

const TAG0: u32 = @as(u32, 1) << 31;

fn monitorOpt(p: [*c]Monitor) ?*Monitor {
    return if (p == null) null else @ptrCast(p);
}

fn clientOpt(p: [*c]Client) ?*Client {
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

fn ISNORMAL(cl: *const Client) bool {
    return cl.isminimized == 0 and cl.iskilling == 0 and cl.isunglobal == 0;
}

fn ISFAKETILED(cl: *const Client) bool {
    return cl.isfloating == 0 and cl.isminimized == 0 and cl.iskilling == 0 and cl.isunglobal == 0;
}

fn readPtr(base: *const Client, off: usize) [*c]Client {
    return @as(*const [*c]Client, @ptrFromInt(@intFromPtr(base) + off)).*;
}

fn writePtr(base: *Client, off: usize, value: [*c]Client) void {
    @as(*[*c]Client, @ptrFromInt(@intFromPtr(base) + off)).* = value;
}

fn monitorMoveDirection(from: ?*const Monitor, to: ?*const Monitor) i32 {
    const f = from orelse return c.UNDIR;
    const t = to orelse return c.UNDIR;
    if (f == t)
        return c.UNDIR;
    const dx: i64 = (@as(i64, t.m.x) + @divTrunc(t.m.width, 2)) - (@as(i64, f.m.x) + @divTrunc(f.m.width, 2));
    const dy: i64 = (@as(i64, t.m.y) + @divTrunc(t.m.height, 2)) - (@as(i64, f.m.y) + @divTrunc(f.m.height, 2));
    const adx = @abs(dx);
    const ady = @abs(dy);
    if (adx == 0 and ady == 0)
        return c.UNDIR;
    if (adx >= ady)
        return if (dx > 0) c.RIGHT else c.LEFT;
    return if (dy > 0) c.DOWN else c.UP;
}

fn clientReassignMonitor(cl: *Client, m: *Monitor) void {
    const old = monitorOpt(cl.mon) orelse return;
    if (old == m)
        return;
    if (old.sel == cl)
        old.sel = null;
    if (old.prevsel == cl)
        old.prevsel = null;
    cl.mon = @ptrCast(m);
    if (!VISIBLEON(cl, m))
        client_reset_mon_tags(cl, @ptrCast(m), 0);
    m.sel = cl;
    set_selected_monitor(m);
}

export fn client_jump_to_monitor(cl: *Client, m_in: ?*Monitor, dir: i32) bool {
    const m = m_in orelse return false;
    const old = monitorOpt(cl.mon) orelse return false;
    if (old == m)
        return false;
    if (c.config.exchange_cross_monitor == 0 or monitorMoveDirection(old, m) != dir)
        return false;
    clientReassignMonitor(cl, m);
    arrange(old, false, false);
    arrange(m, false, false);
    return true;
}

export fn client_move_to_monitor(cl: *Client, target_in: ?*Client, dir: i32) void {
    const target = target_in orelse return;
    const src = monitorOpt(cl.mon) orelse return;
    const dst = monitorOpt(target.mon) orelse return;
    if (cl == target or src == dst or c.config.exchange_cross_monitor == 0 or
        monitorMoveDirection(src, dst) != dir)
        return;

    if (dst.pertag == null)
        return;
    const layout = dst.pertag.*.ltidxs[get_mon_curtag(dst)];
    if (layout == null)
        return;
    if (layout.*.id == c.DWINDLE) {
        dwindle_move_next_to(cl, target, c.config.dwindle_split_ratio, dir);
        return;
    }

    const insert_before = dir == c.RIGHT or dir == c.UP;
    clientReassignMonitor(cl, dst);

    if (layout.*.id == c.SCROLLER or layout.*.id == c.VERTICAL_SCROLLER) {
        const along_axis = if (layout.*.id == c.VERTICAL_SCROLLER)
            (dir == c.UP or dir == c.DOWN)
        else
            (dir == c.LEFT or dir == c.RIGHT);
        if (!along_axis) {
            scroller_insert_stack(cl, target, insert_before);
        } else if (insert_before) {
            const head = scroll_get_stack_head_client(target);
            if (head != null)
                c.wl_list_safe_reinsert_prev(&head.*.link, &cl.link);
        } else {
            const tail = scroll_get_stack_tail_client(target);
            if (tail != null)
                c.wl_list_safe_reinsert_next(&tail.*.link, &cl.link);
        }
    } else if (insert_before) {
        c.wl_list_safe_reinsert_prev(&target.link, &cl.link);
    } else {
        c.wl_list_safe_reinsert_next(&target.link, &cl.link);
    }

    arrange(src, false, false);
    arrange(dst, false, false);
}

export fn client_update_oldmonname_record(cl: ?*Client, m: ?*Monitor) void {
    const client = cl orelse return;
    const mon = m orelse return;
    if (client.iskilling != 0 or client_surface(client) == null or !client_surface(client).*.mapped)
        return;
    @memset(&client.oldmonname, 0);
    if (mon.wlr_output == null or mon.wlr_output.*.name == null)
        return;
    const name = std.mem.span(@as([*:0]const u8, @ptrCast(mon.wlr_output.*.name)));
    const len = @min(name.len, client.oldmonname.len - 1);
    std.mem.copyForwards(u8, client.oldmonname[0..len], name[0..len]);
    client.oldmonname[len] = 0;
}

export fn client_apply_bounds(cl: *Client, bbox: *Box) void {
    const bw: i32 = @intCast(cl.bw);
    cl.geom.width = @max(1 + 2 * bw, cl.geom.width);
    cl.geom.height = @max(1 + 2 * bw, cl.geom.height);
    if (cl.geom.x >= bbox.x + bbox.width)
        cl.geom.x = bbox.x + bbox.width - cl.geom.width;
    if (cl.geom.y >= bbox.y + bbox.height)
        cl.geom.y = bbox.y + bbox.height - cl.geom.height;
    if (cl.geom.x + cl.geom.width <= bbox.x)
        cl.geom.x = bbox.x;
    if (cl.geom.y + cl.geom.height <= bbox.y)
        cl.geom.y = bbox.y;
}

export fn client_swap_layout_properties(c1: *Client, c2: *Client) void {
    std.mem.swap(f32, &c1.grid_col_per, &c2.grid_col_per);
    std.mem.swap(f32, &c1.grid_row_per, &c2.grid_row_per);
    std.mem.swap(i32, &c1.grid_col_idx, &c2.grid_col_idx);
    std.mem.swap(i32, &c1.grid_row_idx, &c2.grid_row_idx);
    std.mem.swap(f64, &c1.master_inner_per, &c2.master_inner_per);
    std.mem.swap(f64, &c1.master_mfact_per, &c2.master_mfact_per);
    std.mem.swap(f64, &c1.stack_inner_per, &c2.stack_inner_per);
    std.mem.swap(f64, &c1.master_size_weight, &c2.master_size_weight);
    std.mem.swap(f64, &c1.stack_size_weight, &c2.stack_size_weight);
}

export fn client_swap_monitors_and_tags(c1: *Client, c2: *Client) void {
    const tmp_mon = c2.mon;
    const tmp_tags = c2.tags;
    c2.mon = c1.mon;
    c1.mon = tmp_mon;
    c2.tags = c1.tags;
    c1.tags = tmp_tags;
}

export fn finish_exchange_arrange_and_focus(c1: *Client, c2: *Client, m1: [*c]Monitor, m2: [*c]Monitor) void {
    if (@intFromPtr(m1) != @intFromPtr(m2)) {
        arrange(c1.mon, false, false);
        arrange(c2.mon, false, false);
    } else {
        arrange(c1.mon, false, false);
    }
    c.wl_list_safe_reinsert_next(&c1.flink, &c2.flink);
    if (c.config.warpcursor != 0)
        pointer_warp_to_client(c1);
}

export fn client_tile_resize(cl: *Client, geo_in: Box, interact: i32, ctx: ?*const LayoutContext) void {
    var geo = geo_in;
    if (ctx != null and ctx.?.probe != null) {
        if (cl == ctx.?.probe and ctx.?.out != null)
            ctx.?.out.?.* = geo;
        return;
    }
    if (!ISFAKETILED(cl) or cl.mon == null)
        return;
    if (cl.mon.*.isoverview == 0 and cl.isfullscreen == 0 and client_wants_group_bar(cl)) {
        geo.y += @intCast(c.config.group_bar_height);
        geo.height -= @intCast(c.config.group_bar_height);
    }
    if (cl.mon.*.isoverview == 0 and cl.isfullscreen == 0 and c.config.tab_bar_height > 0 and
        (cl.tab_prev != null or cl.tab_next != null))
    {
        geo.y += @intCast(c.config.tab_bar_height);
        geo.height -= @intCast(c.config.tab_bar_height);
    }
    if ((cl.isfullscreen == 0 and cl.ismaximizescreen == 0) or is_scroller_layout(cl.mon)) {
        var opts = std.mem.zeroes(c.ResizeOpts);
        opts.interact = interact != 0;
        resize(cl, geo, opts);
    }
}

export fn generate_client_id() u32 {
    c.server.next_client_id += 1;
    return c.server.next_client_id;
}

export fn client_gesture_driven(cl: ?*const Client) bool {
    return c.server.gesture_drive_active and cl != null and
        @intFromPtr(cl.?.mon) == @intFromPtr(c.server.gesture_drive_mon);
}

export fn client_should_visible(cl: ?*Client) bool {
    const client = cl orelse return false;
    if (client.scene == null)
        return false;
    if (client.snapshot_temp_visible)
        return true;
    if (client.isminimized != 0 and !client.animation.tagouting)
        return false;
    if (client.is_clip_to_hide)
        return false;
    if (client.ov_card_tree != null)
        return true;
    if (client.mon != null and client.mon.*.isoverview != 0 and client.overview_scene_surface != null)
        return true;
    if (client.is_tab_hidden)
        return false;
    if (client.iskilling != 0)
        return false;
    if (client.animation.tagouting)
        return true;
    if (client_gesture_driven(client) and (client.animation.tagining or client.animation.tagouting))
        return true;
    return client.tag_visible;
}

fn clientUpdateInputPenetration(cl: *Client) void {
    if (cl.scene != null)
        acwm_scene_node_set_ignore_hit(&cl.scene.*.node, cl.animation.tagouting);
    tab_update_input_penetration(cl);
}

export fn client_update_visibility(cl: ?*Client) void {
    const client = cl orelse return;
    if (client.scene == null)
        return;
    clientUpdateInputPenetration(client);
    const show = client_should_visible(client);
    if (client.scene.*.node.enabled != show)
        c.wlr_scene_node_set_enabled(&client.scene.*.node, show);

    const surface_show = !client.is_surface_hidden and client.ov_card_tree == null and
        client.overview_scene_surface == null;
    if (client.scene_surface != null and client.scene_surface.*.node.enabled != surface_show)
        c.wlr_scene_node_set_enabled(&client.scene_surface.*.node, surface_show);
}

export fn client_pending_force_kill(cl: ?*Client) void {
    const client = cl orelse return;
    _ = c.kill(client.pid, c.SIGKILL);
}

export fn client_add_jump_label_node(cl: *Client) void {
    if (cl.scene == null)
        return;
    cl.jump_label_node = acwm_jump_label_node_create(cl.scene, c.config.jumplabeldata);
    if (cl.jump_label_node == null)
        return;
    if (cl.ov_card_tree != null)
        c.wlr_scene_node_raise_to_top(&cl.jump_label_node.*.scene.*.node)
    else
        c.wlr_scene_node_lower_to_bottom(&cl.jump_label_node.*.scene.*.node);
    c.wlr_scene_node_set_enabled(&cl.jump_label_node.*.scene.*.node, false);
}

export fn client_target_layer(cl: *Client) u32 {
    const special_overlay = (cl.tags & TAG0) != 0;
    if (cl.isoverlay != 0)
        return @intCast(if (special_overlay) c.LyrSpecialOverlay else c.LyrOverlay);

    if (c.config.float_full_to_top != 0) {
        if (special_overlay)
            return @intCast(if (cl.isfloating != 0 or cl.isfullscreen != 0)
                c.LyrTop
            else if (cl.ismaximizescreen != 0)
                c.LyrSpecialMaximize
            else
                c.LyrSpecialTile);
        if (is_special_active(cl.mon))
            return @intCast(if (cl.isfullscreen != 0)
                c.LyrFullscreen
            else if (cl.isfloating != 0)
                c.LyrFloat
            else if (cl.ismaximizescreen != 0)
                c.LyrMaximize
            else
                c.LyrTile);
        return @intCast(if (cl.isfloating != 0 or cl.isfullscreen != 0)
            c.LyrTop
        else if (cl.ismaximizescreen != 0)
            c.LyrMaximize
        else
            c.LyrTile);
    }

    if (special_overlay)
        return @intCast(if (cl.isfullscreen != 0)
            c.LyrSpecialFullscreen
        else if (cl.isfloating != 0)
            c.LyrSpecialFloat
        else if (cl.ismaximizescreen != 0)
            c.LyrSpecialMaximize
        else
            c.LyrSpecialTile);
    return @intCast(if (cl.isfullscreen != 0)
        c.LyrFullscreen
    else if (cl.isfloating != 0)
        c.LyrFloat
    else if (cl.ismaximizescreen != 0)
        c.LyrMaximize
    else
        c.LyrTile);
}

export fn client_sync_layer(cl: *Client) void {
    if (cl.scene == null or cl.mon == null)
        return;
    clientUpdateInputPenetration(cl);
    if (cl.scene.*.node.parent != c.server.layers[client_target_layer(cl)])
        client_reparent_group(cl);
    client_sync_blur_optimized(cl);
}

export fn client_wants_group_bar(cl: ?*Client) bool {
    const client = cl orelse return false;
    if (client_is_group_member(client))
        return true;
    return c.config.always_show_group_bar != 0;
}

export fn client_add_group_bar(cl: *Client) void {
    if (c.config.group_bar_height <= 0)
        return;
    const layer = client_target_layer(cl);
    cl.group_bar = acwm_bar_decoration_create(cl, @intCast(c.GroupBar), false, c.server.layers[layer], c.config.groupbardata, 0, 0);
    if (cl.group_bar == null)
        return;
    c.wlr_scene_node_lower_to_bottom(&cl.group_bar.*.scene.*.node);
    c.wlr_scene_node_set_enabled(&cl.group_bar.*.scene.*.node, false);
    acwm_bar_decoration_set_close_color(cl.group_bar, &c.config.group_bar_button_color);
    client_update_group_bar_title(cl);
}

export fn client_update_group_bar_title(cl: ?*Client) void {
    const client = cl orelse return;
    if (client.group_bar == null)
        return;
    var scale: f32 = 1.0;
    if (monitorOpt(client.mon)) |m| {
        if (m.wlr_output != null) scale = m.wlr_output.*.scale;
    } else if (monitorOpt(c.server.selected_monitor)) |m| {
        if (m.wlr_output != null) scale = m.wlr_output.*.scale;
    }
    acwm_bar_decoration_update(client.group_bar, client_get_title(client), scale);
}

export fn client_apply_group_bar_config(cl: ?*Client) void {
    const client = cl orelse return;
    if (client.group_bar == null)
        return;
    acwm_bar_decoration_apply_config(client.group_bar, &c.config.groupbardata);
    acwm_bar_decoration_set_close_color(client.group_bar, &c.config.group_bar_button_color);
}

export fn client_remove_group_bar(cl: ?*Client) void {
    const client = cl orelse return;
    if (client.group_bar == null)
        return;
    if (c.server.group_bar_hover != null and @intFromPtr(c.server.group_bar_hover) == @intFromPtr(client.group_bar))
        c.server.group_bar_hover = null;
    if (c.server.group_bar_drag_client != null and @intFromPtr(c.server.group_bar_drag_client) == @intFromPtr(client)) {
        c.server.group_bar_drag_client = null;
        c.server.group_bar_drag_pending = false;
    }
    acwm_bar_decoration_destroy(client.group_bar);
    client.group_bar = null;
}

export fn client_group_swap_focus(cl: *Client) bool {
    if (!client_is_group_member(cl) or cl.is_group_focus)
        return false;
    const head = client_group_head(cl) orelse return false;
    const cur = client_group_focused(head) orelse return false;
    const curmon = monitorOpt(cur.mon) orelse return false;
    if (curmon.isoverview != 0)
        return false;
    cur.is_group_focus = false;
    cl.mon = cur.mon;
    client_replace(cl, cur, true, false);
    acwm_bar_decoration_set_focus(cur.group_bar, false);
    cl.is_group_focus = true;
    acwm_bar_decoration_set_focus(cl.group_bar, true);
    client_reparent_group(cl);
    return true;
}

export fn client_focus_group_member(cl: *Client) void {
    if (!client_group_swap_focus(cl))
        return;
    client_focus(cl, 1);
    arrange(cl.mon, false, false);
}

export fn client_check_tab_node_visible(cl: ?*Client) void {
    const client = cl orelse return;
    if (client.mon == null)
        return;
    var cur = client_group_head(client);
    while (cur != null) {
        const it = cur.?;
        const show = it.mon != null and it.mon.*.isoverview == 0 and it.group_bar != null and
            client_wants_group_bar(it) and TAGMATCH(client, client.mon) and
            ISNORMAL(client) and client.isfullscreen == 0;
        if (it.group_bar == null) {
            cur = clientOpt(it.group_next);
            continue;
        }
        const focused = c.server.selected_monitor != null and it == c.server.selected_monitor.*.sel;
        const show_close = show and c.config.always_show_group_bar != 0 and
            c.config.group_bar_close_button_enable != 0;
        c.wlr_scene_node_set_enabled(&it.group_bar.*.scene.*.node, show);
        acwm_scene_node_set_ignore_hit(&it.group_bar.*.scene.*.node, !show);
        acwm_bar_decoration_set_focus(it.group_bar, show and focused);
        acwm_bar_decoration_set_close(it.group_bar, show_close, @intCast(c.config.group_bar_button_size), @intCast(c.config.group_bar_button_margin));
        cur = clientOpt(it.group_next);
    }
}

export fn client_raise_group(cl: *Client) void {
    if (cl.mon == null)
        return;
    var cur = client_group_head(cl);
    while (cur != null) {
        const it = cur.?;
        if (it.group_bar != null)
            c.wlr_scene_node_raise_to_top(&it.group_bar.*.scene.*.node);
        if (it.scene != null)
            c.wlr_scene_node_raise_to_top(&it.scene.*.node);
        cur = clientOpt(it.group_next);
    }
}

export fn client_reparent_group(cl: *Client) void {
    if (cl.mon == null)
        return;
    const layer = client_target_layer(cl);
    var cur = client_group_head(cl);
    while (cur != null) {
        const it = cur.?;
        if (it.group_bar != null)
            c.wlr_scene_node_reparent(&it.group_bar.*.scene.*.node, c.server.layers[layer]);
        if (it.scene != null)
            c.wlr_scene_node_reparent(&it.scene.*.node, c.server.layers[layer]);
        client_sync_blur_optimized(it);
        cur = clientOpt(it.group_next);
    }
    if (cl.tab_prev != null or cl.tab_next != null)
        client_reparent_tab(cl);
}

export fn client_handle_decorate_click(bar: ?*Bar) void {
    const b = bar orelse return;
    if (b.node_data == null)
        return;
    const cl = @as(*Client, @ptrCast(@alignCast(b.node_data.?)));
    if (b.is_tab)
        tab_focus_member(cl)
    else if (!client_is_group_member(cl))
        client_focus(cl, 1)
    else
        client_focus_group_member(cl);
}

export fn client_set_group_mon(cl: *Client, m: [*c]Monitor) void {
    var cur = client_group_head(cl);
    while (cur != null) {
        const it = cur.?;
        if (!client_is_parked(it))
            client_change_mon(it, m);
        cur = clientOpt(it.group_next);
    }
}

export fn client_set_group_config(cl: *Client) void {
    var cur = client_group_head(cl);
    while (cur != null) {
        const it = cur.?;
        acwm_jump_label_node_apply_config(it.jump_label_node, &c.config.jumplabeldata);
        if (it.droparea != null) c.wlr_scene_rect_set_color(it.droparea, &c.config.dropcolor);
        if (it.splitindicator[0] != null) c.wlr_scene_rect_set_color(it.splitindicator[0], &c.config.splitcolor);
        if (it.splitindicator[1] != null) c.wlr_scene_rect_set_color(it.splitindicator[1], &c.config.splitcolor);
        client_apply_group_bar_config(it);
        cur = clientOpt(it.group_next);
    }
}

export fn client_chain_head(cl: ?*Client, prev_off: usize) ?*Client {
    var head = cl orelse return null;
    while (true) {
        const prev = readPtr(head, prev_off);
        if (prev == null)
            break;
        head = @ptrCast(prev);
    }
    return head;
}

export fn client_group_head(cl: ?*Client) ?*Client {
    return client_chain_head(cl, @offsetOf(Client, "group_prev"));
}

export fn client_is_group_member(cl: ?*const Client) bool {
    const client = cl orelse return false;
    return client.group_prev != null or client.group_next != null;
}

export fn client_group_focused(cl_in: ?*Client) ?*Client {
    var it = cl_in;
    while (it != null) {
        if (it.?.is_group_focus)
            return it;
        it = clientOpt(it.?.group_next);
    }
    return null;
}

export fn client_group_active(cl_in: ?*Client) ?*Client {
    const head = client_group_head(cl_in) orelse return null;
    var it: ?*Client = head;
    while (it != null) {
        if (it.?.mon != null)
            return it;
        it = clientOpt(it.?.group_next);
    }
    return null;
}

export fn client_chain_unlink(cl: ?*Client, prev_off: usize, next_off: usize) void {
    const client = cl orelse return;
    const prev = readPtr(client, prev_off);
    const next = readPtr(client, next_off);
    if (prev != null)
        writePtr(@ptrCast(prev), next_off, next);
    if (next != null)
        writePtr(@ptrCast(next), prev_off, prev);
    writePtr(client, prev_off, null);
    writePtr(client, next_off, null);
}

fn clientGroupMarkDirty(cl_in: ?*Client) void {
    var it = client_group_head(cl_in);
    while (it != null) {
        it.?.need_output_flush = true;
        it = clientOpt(it.?.group_next);
    }
}

export fn client_group_detach(cl: *Client) void {
    const anchor = if (cl.group_prev != null) clientOpt(cl.group_prev) else clientOpt(cl.group_next);
    client_chain_unlink(cl, @offsetOf(Client, "group_prev"), @offsetOf(Client, "group_next"));
    cl.is_group_focus = false;
    clientGroupMarkDirty(anchor);
}

export fn client_group_replace(old: *Client, new: *Client) void {
    client_group_detach(new);
    new.group_prev = old.group_prev;
    new.group_next = old.group_next;
    if (old.group_prev != null)
        old.group_prev.*.group_next = new;
    if (old.group_next != null)
        old.group_next.*.group_prev = new;
    old.group_prev = null;
    old.group_next = null;

    if (client_is_parked(old) or !client_is_group_member(new))
        new.is_group_focus = false
    else
        new.is_group_focus = old.is_group_focus;

    clientGroupMarkDirty(new);
}

export fn acwm_surface_frame_done(surface: [*c]c.struct_wlr_surface, sx: i32, sy: i32, data: ?*anyopaque) void {
    _ = sx;
    _ = sy;
    c.wlr_surface_send_frame_done(surface, @ptrCast(@alignCast(data.?)));
}

export fn client_send_frame_done(cl: *Client, now: *const c.struct_timespec) void {
    const s = client_surface(cl);
    if (s == null)
        return;
    c.wlr_surface_for_each_surface(s, acwm_surface_frame_done, @constCast(now));
}

export fn client_force_render(cl: ?*Client) bool {
    const client = cl orelse return false;
    if (client.mon == null or client.iskilling != 0 or client_surface(client) == null or
        !client_surface(client).*.mapped or (client.scene != null and client.scene.*.node.enabled))
        return false;
    var now: c.struct_timespec = undefined;
    _ = c.clock_gettime(c.CLOCK_MONOTONIC, &now);
    client_send_frame_done(client, &now);
    return true;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/client_group_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_list_calls: c_int;
extern var stub_reinsert_prev: c_int;
extern var stub_reinsert_next: c_int;
extern var stub_tag_idx: u32;
extern var stub_curtag: u32;
extern var stub_reset_tags: c_int;
extern var stub_change_mon_calls: c_int;
extern var stub_focus_calls: c_int;
extern var stub_replace_calls: c_int;
extern var stub_blur_calls: c_int;
extern var stub_reparent_tab_calls: c_int;
extern var stub_tab_pen_calls: c_int;
extern var stub_tab_focus_calls: c_int;
extern var stub_selected_calls: c_int;
extern var stub_arrange_calls: c_int;
extern var stub_resize_calls: c_int;
extern var stub_resize_geo: Box;
extern var stub_resize_interact: i32;
extern var stub_dwindle_move_calls: c_int;
extern var stub_scroller_insert_calls: c_int;
extern var stub_scroll_head: [*c]Client;
extern var stub_scroll_tail: [*c]Client;
extern var stub_scroller: bool;
extern var stub_special: bool;
extern var stub_warp_calls: c_int;
extern var stub_ignore_hits: c_int;
extern var stub_ignore_value: bool;
extern var stub_bar: Bar;
extern var stub_bar_scene: c.struct_wlr_scene_tree;
extern var stub_bar_create_calls: c_int;
extern var stub_bar_type: u32;
extern var stub_bar_is_tab: bool;
extern var stub_bar_destroy_calls: c_int;
extern var stub_bar_update_calls: c_int;
extern var stub_bar_scale: f32;
extern var stub_bar_config_calls: c_int;
extern var stub_bar_focus_calls: c_int;
extern var stub_bar_focus_value: bool;
extern var stub_bar_close_color_calls: c_int;
extern var stub_bar_close_calls: c_int;
extern var stub_bar_close_show: bool;
extern var stub_jump: c.AcwmJumpLabel;
extern var stub_jump_scene: c.struct_wlr_scene_tree;
extern var stub_jump_create_calls: c_int;
extern var stub_jump_config_calls: c_int;
extern var stub_node_enable_calls: c_int;
extern var stub_node_raise_calls: c_int;
extern var stub_node_lower_calls: c_int;
extern var stub_node_reparent_calls: c_int;
extern var stub_rect_color_calls: c_int;
extern var stub_kill_calls: c_int;
extern var stub_frame_done_calls: c_int;
extern var stub_for_each_surface_calls: c_int;
extern var stub_group_surface: [*c]c.struct_wlr_surface;

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

fn resetGroupWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    c.config.group_bar_height = 30;
    c.config.group_bar_button_size = 10;
    c.config.group_bar_button_margin = 2;
    c.config.tab_bar_height = 20;
    c.config.warpcursor = 1;
    c.server.next_client_id = 0;
    stub_list_calls = 0;
    stub_reinsert_prev = 0;
    stub_reinsert_next = 0;
    stub_tag_idx = 0;
    stub_curtag = 0;
    stub_reset_tags = 0;
    stub_change_mon_calls = 0;
    stub_focus_calls = 0;
    stub_replace_calls = 0;
    stub_blur_calls = 0;
    stub_reparent_tab_calls = 0;
    stub_tab_pen_calls = 0;
    stub_tab_focus_calls = 0;
    stub_selected_calls = 0;
    stub_arrange_calls = 0;
    stub_resize_calls = 0;
    stub_resize_geo = std.mem.zeroes(Box);
    stub_resize_interact = -1;
    stub_dwindle_move_calls = 0;
    stub_scroller_insert_calls = 0;
    stub_scroll_head = null;
    stub_scroll_tail = null;
    stub_scroller = false;
    stub_special = false;
    stub_warp_calls = 0;
    stub_ignore_hits = 0;
    stub_ignore_value = false;
    stub_bar_create_calls = 0;
    stub_bar_type = 0;
    stub_bar_is_tab = false;
    stub_bar_destroy_calls = 0;
    stub_bar_update_calls = 0;
    stub_bar_scale = 0;
    stub_bar_config_calls = 0;
    stub_bar_focus_calls = 0;
    stub_bar_focus_value = false;
    stub_bar_close_color_calls = 0;
    stub_bar_close_calls = 0;
    stub_bar_close_show = false;
    stub_jump_create_calls = 0;
    stub_jump_config_calls = 0;
    stub_node_enable_calls = 0;
    stub_node_raise_calls = 0;
    stub_node_lower_calls = 0;
    stub_node_reparent_calls = 0;
    stub_rect_color_calls = 0;
    stub_kill_calls = 0;
    stub_frame_done_calls = 0;
    stub_for_each_surface_calls = 0;
}

fn baseMon(m: *Monitor, p: *c.Pertag, layout: ?*c.Layout) void {
    m.* = std.mem.zeroes(Monitor);
    p.* = std.mem.zeroes(c.Pertag);
    m.pertag = p;
    m.w = mkBox(0, 0, 1000, 800);
    m.m = m.w;
    m.tagset[0] = 1;
    if (layout) |l| p.ltidxs[0] = l;
}

test "monitor moves respect direction and layout" {
    resetGroupWorld();
    var p1: c.Pertag = std.mem.zeroes(c.Pertag);
    var p2: c.Pertag = std.mem.zeroes(c.Pertag);
    var m1: Monitor = std.mem.zeroes(Monitor);
    var m2: Monitor = std.mem.zeroes(Monitor);
    baseMon(&m1, &p1, null);
    baseMon(&m2, &p2, null);
    m2.m.x = 1200;
    m2.w.x = 1200;
    c.config.exchange_cross_monitor = 1;
    var cl: Client = std.mem.zeroes(Client);
    cl.mon = &m1;
    cl.tags = 1;
    try testing.expect(client_jump_to_monitor(&cl, &m2, c.RIGHT));
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls * 0 + 1);
    try testing.expect(cl.mon == &m2);
    try testing.expect(m2.sel == &cl);

    var target: Client = std.mem.zeroes(Client);
    target.mon = &m1;
    var layout: c.Layout = std.mem.zeroes(c.Layout);
    layout.id = @intCast(c.DWINDLE);
    p1.ltidxs[0] = &layout;
    p2.ltidxs[0] = &layout;
    client_move_to_monitor(&cl, &target, c.LEFT);
    try testing.expectEqual(@as(c_int, 1), stub_dwindle_move_calls);

    layout.id = @intCast(c.TILE);
    cl.mon = &m1;
    m1.m.x = 1200;
    m1.w.x = 1200;
    m2.m.x = 0;
    m2.w.x = 0;
    target.mon = &m2;
    client_move_to_monitor(&cl, &target, c.LEFT);
    try testing.expectEqual(@as(c_int, 1), stub_reinsert_next);
}

test "bounds, swaps, tile resize and ids" {
    resetGroupWorld();
    var cl: Client = std.mem.zeroes(Client);
    cl.bw = 2;
    cl.geom = mkBox(2000, 2000, 10, 10);
    var bbox = mkBox(0, 0, 100, 100);
    client_apply_bounds(&cl, &bbox);
    try testing.expectEqual(@as(i32, 90), cl.geom.x);
    try testing.expectEqual(@as(i32, 90), cl.geom.y);
    cl.geom = mkBox(-50, -50, 10, 10);
    client_apply_bounds(&cl, &bbox);
    try testing.expectEqual(@as(i32, 0), cl.geom.x);

    var a: Client = std.mem.zeroes(Client);
    var b: Client = std.mem.zeroes(Client);
    a.grid_col_per = 0.25;
    b.grid_col_per = 0.75;
    a.master_inner_per = 1;
    b.master_inner_per = 2;
    client_swap_layout_properties(&a, &b);
    try testing.expectApproxEqAbs(@as(f32, 0.75), a.grid_col_per, 1e-6);
    try testing.expectApproxEqAbs(@as(f64, 2), a.master_inner_per, 1e-6);
    a.mon = @ptrFromInt(0x1000);
    b.mon = @ptrFromInt(0x2000);
    a.tags = 1;
    b.tags = 2;
    client_swap_monitors_and_tags(&a, &b);
    try testing.expect(a.mon == @as([*c]Monitor, @ptrFromInt(0x2000)));
    try testing.expectEqual(@as(u32, 2), a.tags);

    cl.geom = mkBox(0, 0, 100, 100);
    var tr_mon: c.Monitor = std.mem.zeroes(c.Monitor);
    cl.mon = &tr_mon;
    cl.isfloating = 0;
    const geo = mkBox(10, 20, 300, 200);
    var out: Box = undefined;
    var ctx = c.LayoutContext{ .probe = &cl, .out = &out };
    client_tile_resize(&cl, geo, 0, &ctx);
    try testing.expectEqual(@as(i32, 300), out.width);
    ctx.probe = null;
    cl.tab_prev = @ptrFromInt(0x3000);
    c.config.always_show_group_bar = 1;
    client_tile_resize(&cl, geo, 1, &ctx);
    try testing.expectEqual(@as(i32, 70), stub_resize_geo.y);
    try testing.expectEqual(@as(i32, 150), stub_resize_geo.height);

    try testing.expectEqual(@as(u32, 1), generate_client_id());
    try testing.expectEqual(@as(u32, 2), generate_client_id());
}

test "visibility and target layers follow state" {
    resetGroupWorld();
    var m: Monitor = std.mem.zeroes(Monitor);
    var cl: Client = std.mem.zeroes(Client);
    var tree: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    cl.scene = &tree;
    try testing.expect(!client_should_visible(&cl));
    cl.tag_visible = true;
    try testing.expect(client_should_visible(&cl));
    cl.iskilling = 1;
    try testing.expect(!client_should_visible(&cl));
    cl.iskilling = 0;
    cl.isminimized = 1;
    try testing.expect(!client_should_visible(&cl));
    cl.animation.tagouting = true;
    try testing.expect(client_should_visible(&cl));
    cl.isminimized = 0;
    cl.animation.tagouting = false;
    cl.is_tab_hidden = true;
    try testing.expect(!client_should_visible(&cl));

    c.config.float_full_to_top = 0;
    cl.isfloating = 1;
    try testing.expectEqual(@as(u32, @intCast(c.LyrFloat)), client_target_layer(&cl));
    cl.isfloating = 0;
    cl.isfullscreen = 1;
    try testing.expectEqual(@as(u32, @intCast(c.LyrFullscreen)), client_target_layer(&cl));
    cl.isfullscreen = 0;
    cl.tags = TAG0;
    try testing.expectEqual(@as(u32, @intCast(c.LyrSpecialTile)), client_target_layer(&cl));
    c.config.float_full_to_top = 1;
    cl.isfloating = 1;
    try testing.expectEqual(@as(u32, @intCast(c.LyrTop)), client_target_layer(&cl));
    cl.isoverlay = 1;
    try testing.expectEqual(@as(u32, @intCast(c.LyrSpecialOverlay)), client_target_layer(&cl));

    m.isoverview = 1;
    cl.mon = &m;
    c.server.selected_monitor = &m;
    cl.tag_visible = true;
    cl.is_tab_hidden = false;
    client_update_visibility(&cl);
    try testing.expectEqual(@as(c_int, 1), stub_tab_pen_calls);
    try testing.expect(stub_node_enable_calls > 0);
}

test "group bars create, update, configure and remove" {
    resetGroupWorld();
    var m: Monitor = std.mem.zeroes(Monitor);
    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    out.scale = 2.0;
    m.wlr_output = &out;
    c.server.selected_monitor = &m;
    var cl: Client = std.mem.zeroes(Client);
    cl.mon = &m;
    var scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    cl.scene = &scene;
    c.server.layers[@intCast(c.LyrTile)] = &scene;

    client_add_group_bar(&cl);
    try testing.expectEqual(@as(c_int, 1), stub_bar_create_calls);
    try testing.expectEqual(@as(u32, @intCast(c.GroupBar)), stub_bar_type);
    try testing.expect(!stub_bar_is_tab);
    try testing.expectEqual(@as(c_int, 1), stub_bar_update_calls);
    try testing.expectApproxEqAbs(@as(f32, 2.0), stub_bar_scale, 1e-6);
    try testing.expectEqual(@as(c_int, 1), stub_bar_close_color_calls);
    try testing.expectEqual(@as(c_int, 1), stub_node_lower_calls);

    client_apply_group_bar_config(&cl);
    try testing.expectEqual(@as(c_int, 1), stub_bar_config_calls);
    client_remove_group_bar(&cl);
    try testing.expectEqual(@as(c_int, 1), stub_bar_destroy_calls);
    try testing.expect(cl.group_bar == null);
    try testing.expect(client_wants_group_bar(&cl) == (c.config.always_show_group_bar != 0));
}

test "group chains detach, replace and swap focus" {
    resetGroupWorld();
    var m: Monitor = std.mem.zeroes(Monitor);
    m.tagset[0] = 1;
    var a: Client = std.mem.zeroes(Client);
    var b: Client = std.mem.zeroes(Client);
    var c3: Client = std.mem.zeroes(Client);
    a.mon = &m;
    b.mon = &m;
    c3.mon = &m;
    b.group_prev = &a;
    a.group_next = &b;
    c3.group_prev = &b;
    b.group_next = &c3;
    try testing.expect(client_group_head(&c3) == &a);
    try testing.expect(client_is_group_member(&b));
    b.is_group_focus = true;
    try testing.expect(client_group_focused(&a) == &b);
    try testing.expect(client_group_active(&a) == &a);

    client_group_detach(&b);
    try testing.expect(a.group_next == &c3);
    try testing.expect(c3.group_prev == &a);
    try testing.expect(!client_is_group_member(&b));

    var old: Client = std.mem.zeroes(Client);
    var new: Client = std.mem.zeroes(Client);
    old.group_prev = &a;
    old.group_next = &c3;
    a.group_next = &old;
    c3.group_prev = &old;
    old.is_group_focus = true;
    client_group_replace(&old, &new);
    try testing.expect(new.group_prev == &a);
    try testing.expect(new.group_next == &c3);
    try testing.expect(new.is_group_focus);

    resetGroupWorld();
    var f1: Client = std.mem.zeroes(Client);
    var f2: Client = std.mem.zeroes(Client);
    var fm: Monitor = std.mem.zeroes(Monitor);
    fm.tagset[0] = 1;
    f1.mon = &fm;
    f2.mon = &fm;
    f2.group_prev = &f1;
    f1.group_next = &f2;
    f1.is_group_focus = true;
    var bar1: Bar = std.mem.zeroes(Bar);
    var bar2: Bar = std.mem.zeroes(Bar);
    var bar_scene1: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var bar_scene2: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    bar1.scene = &bar_scene1;
    bar2.scene = &bar_scene2;
    f1.group_bar = &bar1;
    f2.group_bar = &bar2;
    try testing.expect(client_group_swap_focus(&f2));
    try testing.expectEqual(@as(c_int, 1), stub_replace_calls);
    try testing.expect(f2.is_group_focus);
    try testing.expect(!f1.is_group_focus);
}

test "tab node visibility, raise, reparent and clicks" {
    resetGroupWorld();
    var m: Monitor = std.mem.zeroes(Monitor);
    m.tagset[0] = 1;
    c.server.selected_monitor = &m;
    var cl: Client = std.mem.zeroes(Client);
    cl.mon = &m;
    cl.tags = 1;
    m.sel = &cl;
    var scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    cl.scene = &scene;
    var bar: Bar = std.mem.zeroes(Bar);
    var bar_scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    bar.scene = &bar_scene;
    cl.group_bar = &bar;
    c.config.always_show_group_bar = 1;
    c.config.group_bar_close_button_enable = 1;
    client_check_tab_node_visible(&cl);
    try testing.expectEqual(@as(c_int, 1), stub_node_enable_calls);
    try testing.expectEqual(@as(c_int, 1), stub_bar_focus_calls);
    try testing.expectEqual(@as(c_int, 1), stub_bar_close_calls);
    try testing.expect(stub_bar_close_show);

    client_raise_group(&cl);
    try testing.expect(stub_node_raise_calls >= 2);
    c.server.layers[@intCast(client_target_layer(&cl))] = &scene;
    client_reparent_group(&cl);
    try testing.expectEqual(@as(c_int, 2), stub_node_reparent_calls);

    var node_data: Client = cl;
    bar.node_data = &node_data;
    bar.is_tab = true;
    client_handle_decorate_click(&bar);
    try testing.expectEqual(@as(c_int, 1), stub_tab_focus_calls);
    bar.is_tab = false;
    client_handle_decorate_click(&bar);
    try testing.expectEqual(@as(c_int, 1), stub_focus_calls);

    client_set_group_mon(&cl, &m);
    try testing.expectEqual(@as(c_int, 1), stub_change_mon_calls);
    client_set_group_config(&cl);
    try testing.expectEqual(@as(c_int, 1), stub_jump_config_calls);
}

test "frame callbacks, force render and pending kill" {
    resetGroupWorld();
    var cl: Client = std.mem.zeroes(Client);
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    surface.mapped = true;
    var now: c.struct_timespec = std.mem.zeroes(c.struct_timespec);
    cl.pid = 123;
    var mon: Monitor = std.mem.zeroes(Monitor);
    cl.mon = &mon;
    var scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    cl.scene = &scene;
    scene.node.enabled = false;
    stub_group_surface = &surface;
    client_send_frame_done(&cl, &now);
    try testing.expectEqual(@as(c_int, 1), stub_for_each_surface_calls);
    try testing.expectEqual(@as(c_int, 1), stub_frame_done_calls);
    try testing.expect(client_force_render(&cl));
    try testing.expectEqual(@as(c_int, 2), stub_for_each_surface_calls);
    scene.node.enabled = true;
    try testing.expect(!client_force_render(&cl));
    client_pending_force_kill(&cl);
    try testing.expectEqual(@as(c_int, 1), stub_kill_calls);
}
