//! Port of src/layout/scroll.c (strangler-fig Phase 4, layout slice 4,
//! slice 32).
//!
//! Horizontal and vertical scroller layouts with their persistent per-tag
//! stack state, plus the state mutation API (insert/remove/drop/swap/
//! exchange). The C twin is guarded with ACWM_ZIG_LAYOUT_SCROLL.
//!
//! State lives in Monitor->pertag->scroller_state[tag] as a singly linked
//! all-list of ScrollerStackNode plus doubly linked stack chains. Nodes are
//! libc-allocated like the C. Geometry arithmetic keeps the C domains:
//! proportions are f32, client geometry is int32 with truncating float
//! conversions.

const std = @import("std");
const c = @import("cc");

const Node = c.ScrollerStackNode;
const State = c.TagScrollerState;
const Client = c.Client;
const Monitor = c.Monitor;
const Box = c.struct_wlr_box;
const LayoutContext = c.LayoutContext;
const WlList = c.struct_wl_list;
const CoreFn = *const fn (*Monitor, ?*const LayoutContext) void;

extern fn get_mon_curtag(m: *const Monitor) callconv(.c) u32;
extern fn get_client_tag_idx(cl: *const Client) callconv(.c) u32;
extern fn client_tile_resize(cl: *Client, geo: Box, interact: i32, ctx: ?*const LayoutContext) callconv(.c) void;
extern fn client_set_floating(cl: *Client, floating: i32) callconv(.c) void;
extern fn client_apply_fullscreen(cl: *Client, fullscreen: i32, rearrange: bool) callconv(.c) void;
extern fn client_set_maximize_screen(cl: *Client, maximizescreen: i32, rearrange: bool) callconv(.c) void;
extern fn client_wants_group_bar(cl: *Client) callconv(.c) bool;
extern fn client_swap_layout_properties(a: *Client, b: *Client) callconv(.c) void;
extern fn client_swap_monitors_and_tags(a: *Client, b: *Client) callconv(.c) void;
extern fn finish_exchange_arrange_and_focus(a: *Client, b: *Client, m1: *Monitor, m2: *Monitor) callconv(.c) void;
extern fn arrange(m: *Monitor, want_animation: bool, from_view: bool) callconv(.c) void;
extern fn wl_list_swap(l1: *WlList, l2: *WlList) callconv(.c) void;
extern fn wl_list_safe_reinsert_prev(l1: *WlList, l2: *WlList) callconv(.c) void;
extern fn wl_list_safe_reinsert_next(l1: *WlList, l2: *WlList) callconv(.c) void;

extern "c" fn calloc(nmemb: usize, size: usize) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;

fn nodeOpt(p: [*c]Node) ?*Node {
    return if (p == null) null else @ptrCast(p);
}

fn clientOpt(p: [*c]Client) ?*Client {
    return if (p == null) null else @ptrCast(p);
}

fn monitorOpt(p: [*c]Monitor) ?*Monitor {
    return if (p == null) null else @ptrCast(p);
}

fn stateOpt(p: [*c]State) ?*State {
    return if (p == null) null else @ptrCast(p);
}

fn nodePtr(n: ?*Node) [*c]Node {
    return @ptrCast(n);
}

fn clientPtr(cl: ?*Client) [*c]Client {
    return @ptrCast(cl);
}

fn statePtr(st: ?*State) [*c]State {
    return @ptrCast(st);
}

fn containerOf(comptime T: type, comptime link_field: []const u8, link: [*c]WlList) *T {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(T, link_field));
}

fn listHead(head: *WlList) [*c]WlList {
    return @ptrCast(head);
}

inline fn truncF(x: f32) i32 {
    return @intFromFloat(x);
}

fn ISSCROLLTILED(cl: ?*const Client) bool {
    const x = cl orelse return false;
    return x.isfloating == 0 and x.isminimized == 0 and
        x.iskilling == 0 and x.isunglobal == 0;
}

fn VISIBLEON(cl: ?*const Client, m: ?*const Monitor) bool {
    const x = cl orelse return false;
    const mon = m orelse return false;
    if (x.mon != @as([*c]Monitor, @ptrCast(@constCast(mon))))
        return false;
    if (x.isminimized != 0)
        return false;
    return (x.tags & mon.tagset[mon.seltags]) != 0 or x.isglobal != 0 or x.isunglobal != 0;
}

fn INSIDEMON(cl: *const Client) bool {
    const mon = monitorOpt(cl.mon) orelse return false;
    return cl.geom.x >= mon.m.x and cl.geom.y >= mon.m.y and
        cl.geom.x + cl.geom.width <= mon.m.x + mon.m.width and
        cl.geom.y + cl.geom.height <= mon.m.y + mon.m.height;
}

fn GEOMINSIDEMON(box: *const Box, mon: *const Monitor) bool {
    return box.x >= mon.m.x and box.y >= mon.m.y and
        box.x + box.width <= mon.m.x + mon.m.width and
        box.y + box.height <= mon.m.y + mon.m.height;
}

// ---------------------------------------------------------------------------
// state helpers
// ---------------------------------------------------------------------------

export fn ensure_scroller_state(m: *Monitor, tag: u32) callconv(.c) ?*State {
    const idx: usize = @intCast(tag);
    if (m.pertag.*.scroller_state[idx] == null) {
        const st: ?*State = @ptrCast(@alignCast(calloc(1, @sizeOf(State)) orelse return null));
        m.pertag.*.scroller_state[idx] = statePtr(st);
    }
    return stateOpt(m.pertag.*.scroller_state[idx]);
}

export fn find_scroller_node(st_in: ?*State, cl: ?*Client) callconv(.c) ?*Node {
    const st = st_in orelse return null;
    const target = clientPtr(cl);
    var n = st.all_first;
    while (n != null) : (n = n.*.all_next) {
        if (n.*.client == target)
            return @ptrCast(n);
    }
    return null;
}

export fn scroller_node_create(st_in: ?*State, cl: ?*Client) callconv(.c) ?*Node {
    const st = st_in orelse return null;
    const ccl = cl orelse return null;
    const n: *Node = @ptrCast(@alignCast(calloc(1, @sizeOf(Node)) orelse return null));
    n.client = clientPtr(ccl);
    n.scroller_proportion = ccl.scroller_proportion;
    n.scroller_stack_weight = ccl.scroller_stack_proportion;
    n.scroller_proportion_single = ccl.scroller_proportion_single;
    n.next_in_stack = null;
    n.prev_in_stack = null;
    n.all_next = st.all_first;
    st.all_first = nodePtr(n);
    st.count += 1;
    return n;
}

export fn scroller_node_remove(st_in: ?*State, target_in: ?*Node) callconv(.c) void {
    const st = st_in orelse return;
    const target = target_in orelse return;

    const prev = nodeOpt(target.prev_in_stack);
    const next = nodeOpt(target.next_in_stack);

    if (prev) |p|
        p.next_in_stack = nodePtr(next);
    if (next) |nx|
        nx.prev_in_stack = nodePtr(prev);

    if (st.all_first == nodePtr(target)) {
        st.all_first = target.all_next;
        st.count -= 1;
    } else {
        var indirect: [*c]Node = st.all_first;
        var prev_all: ?*Node = null;
        while (indirect != null and indirect != nodePtr(target)) {
            prev_all = @ptrCast(indirect);
            indirect = indirect.*.all_next;
        }
        if (indirect == nodePtr(target)) {
            if (prev_all) |pa|
                pa.all_next = target.all_next;
            st.count -= 1;
        }
    }
    free(@ptrCast(target));
}

export fn clear_scroller_state(st_in: ?*State) callconv(.c) void {
    const st = st_in orelse return;
    var n = st.all_first;
    while (n != null) {
        const next = n.*.all_next;
        free(@ptrCast(n));
        n = next;
    }
    free(@ptrCast(st));
}

export fn cleanup_monitor_scroller(m: *Monitor) callconv(.c) void {
    for (&m.pertag.*.scroller_state) |*slot| {
        if (slot.* != null) {
            clear_scroller_state(stateOpt(slot.*));
            slot.* = null;
        }
    }
}

export fn sync_scroller_state_to_clients(m: *Monitor, tag: u32) callconv(.c) void {
    const st = stateOpt(m.pertag.*.scroller_state[@intCast(tag)]) orelse return;
    var n = st.all_first;
    while (n != null) : (n = n.*.all_next) {
        const cl = clientOpt(n.*.client) orelse continue;
        cl.scroller_proportion = n.*.scroller_proportion;
        cl.scroller_stack_proportion = n.*.scroller_stack_weight;
        cl.scroller_proportion_single = n.*.scroller_proportion_single;
    }
}

// ---------------------------------------------------------------------------
// fullscreen/maximized geometry and monitor clamping
// ---------------------------------------------------------------------------

export fn vertical_scroll_adjust_fullandmax(cl_in: ?*Client, target_geom: *Box) callconv(.c) void {
    const cl = cl_in orelse return;
    const m = monitorOpt(cl.mon) orelse return;
    var cur_gappiv: i32 = if (c.server.enable_gaps != 0) m.gappiv else 0;
    var cur_gappov: i32 = if (c.server.enable_gaps != 0) m.gappov else 0;
    var cur_gappoh: i32 = if (c.server.enable_gaps != 0) m.gappoh else 0;

    if (c.config.smartgaps != 0 and m.visible_scroll_tiling_clients == 1) {
        cur_gappiv = 0;
        cur_gappov = 0;
        cur_gappoh = 0;
    }

    if (cl.isfullscreen != 0) {
        target_geom.width = m.m.width;
        target_geom.height = m.m.height;
        target_geom.x = m.m.x;
        return;
    }
    if (cl.ismaximizescreen != 0) {
        target_geom.width = m.w.width - 2 * cur_gappoh;
        target_geom.height = m.w.height - 2 * cur_gappov;
        target_geom.x = m.w.x + cur_gappoh;
        return;
    }
    target_geom.width = m.w.width - 2 * cur_gappoh;
    target_geom.x = m.w.x + @divTrunc(m.w.width - target_geom.width, 2);
}

export fn vertical_check_scroller_root_inside_mon(cl_in: ?*Client, geometry: *Box) callconv(.c) void {
    const cl = cl_in orelse return;
    const m = monitorOpt(cl.mon) orelse return;
    if (!GEOMINSIDEMON(geometry, m))
        geometry.y = m.w.y + @divTrunc(m.w.height - geometry.height, 2);
}

export fn horizontal_scroll_adjust_fullandmax(cl_in: ?*Client, target_geom: *Box) callconv(.c) void {
    const cl = cl_in orelse return;
    const m = monitorOpt(cl.mon) orelse return;
    var cur_gappih: i32 = if (c.server.enable_gaps != 0) m.gappih else 0;
    var cur_gappoh: i32 = if (c.server.enable_gaps != 0) m.gappoh else 0;
    var cur_gappov: i32 = if (c.server.enable_gaps != 0) m.gappov else 0;

    if (c.config.smartgaps != 0 and m.visible_scroll_tiling_clients == 1) {
        cur_gappih = 0;
        cur_gappoh = 0;
        cur_gappov = 0;
    }

    if (cl.isfullscreen != 0) {
        target_geom.height = m.m.height;
        target_geom.width = m.m.width;
        target_geom.y = m.m.y;
        return;
    }
    if (cl.ismaximizescreen != 0) {
        target_geom.height = m.w.height - 2 * cur_gappov;
        target_geom.width = m.w.width - 2 * cur_gappoh;
        target_geom.y = m.w.y + cur_gappov;
        return;
    }
    target_geom.height = m.w.height - 2 * cur_gappov;
    target_geom.y = m.w.y + @divTrunc(m.w.height - target_geom.height, 2);
}

export fn horizontal_check_scroller_root_inside_mon(cl_in: ?*Client, geometry: *Box) callconv(.c) void {
    const cl = cl_in orelse return;
    const m = monitorOpt(cl.mon) orelse return;
    if (!GEOMINSIDEMON(geometry, m))
        geometry.x = m.w.x + @divTrunc(m.w.width - geometry.width, 2);
}

// ---------------------------------------------------------------------------
// stack arrangement
// ---------------------------------------------------------------------------

fn normalizeStackWeights(head_in: ?*Node) void {
    const head = head_in orelse return;
    var total_weight: f32 = 0.0;
    var counted: i32 = 0;

    var iter: ?*Node = head;
    while (iter) |n| : (iter = nodeOpt(n.next_in_stack)) {
        if (n.scroller_stack_weight > 0.0) {
            total_weight += n.scroller_stack_weight;
            counted += 1;
        }
    }

    if (total_weight <= 0.0) {
        iter = head;
        while (iter) |n| : (iter = nodeOpt(n.next_in_stack)) {
            n.scroller_stack_weight = 1.0;
            total_weight += 1.0;
        }
    } else {
        const average = total_weight / @as(f32, @floatFromInt(counted));
        iter = head;
        while (iter) |n| : (iter = nodeOpt(n.next_in_stack)) {
            if (n.scroller_stack_weight <= 0.0) {
                n.scroller_stack_weight = average;
                total_weight += average;
            }
        }
    }

    iter = head;
    while (iter) |n| : (iter = nodeOpt(n.next_in_stack))
        n.scroller_stack_proportion = n.scroller_stack_weight / total_weight;
}

export fn scroller_arrange_stack_node(
    head_in: ?*Node,
    geometry: Box,
    gappiv: i32,
    ctx: ?*const LayoutContext,
) callconv(.c) void {
    var stack_size: i32 = 0;
    var iter = head_in;
    while (iter) |n| : (iter = nodeOpt(n.next_in_stack))
        stack_size += 1;
    if (stack_size == 0)
        return;

    normalizeStackWeights(head_in);

    var current_y = geometry.y;
    var remain_client_height = geometry.height - (stack_size - 1) * gappiv;
    var remain_proportion: f32 = 1.0;

    iter = head_in;
    while (iter) |n| : (iter = nodeOpt(n.next_in_stack)) {
        const client_height = truncF(@as(f32, @floatFromInt(remain_client_height)) *
            (n.scroller_stack_proportion / remain_proportion));
        client_tile_resize(clientOpt(n.client).?, .{
            .x = geometry.x,
            .y = current_y,
            .width = geometry.width,
            .height = client_height,
        }, 0, ctx);
        remain_proportion -= n.scroller_stack_proportion;
        remain_client_height -= client_height;
        current_y += client_height + gappiv;
    }
}

export fn scroller_arrange_stack_vertical_node(
    head_in: ?*Node,
    geometry: Box,
    gappih: i32,
    ctx: ?*const LayoutContext,
) callconv(.c) void {
    var stack_size: i32 = 0;
    var iter = head_in;
    while (iter) |n| : (iter = nodeOpt(n.next_in_stack))
        stack_size += 1;
    if (stack_size == 0)
        return;

    normalizeStackWeights(head_in);

    var current_x = geometry.x;
    var remain_client_width = geometry.width - (stack_size - 1) * gappih;
    var remain_proportion: f32 = 1.0;

    iter = head_in;
    while (iter) |n| : (iter = nodeOpt(n.next_in_stack)) {
        const client_width = truncF(@as(f32, @floatFromInt(remain_client_width)) *
            (n.scroller_stack_proportion / remain_proportion));
        client_tile_resize(clientOpt(n.client).?, .{
            .x = current_x,
            .y = geometry.y,
            .width = client_width,
            .height = geometry.height,
        }, 0, ctx);
        remain_proportion -= n.scroller_stack_proportion;
        remain_client_width -= client_width;
        current_x += client_width + gappih;
    }
}

// ---------------------------------------------------------------------------
// horizontal scroller core
// ---------------------------------------------------------------------------

fn scrollerCore(m: *Monitor, ctx: ?*const LayoutContext) void {
    const tag = get_mon_curtag(m);
    const st = ensure_scroller_state(m, tag) orelse return;
    const default_single = m.pertag.*.scroller_default_proportion_single[@intCast(tag)];
    const ignore_single = m.pertag.*.scroller_ignore_proportion_single[@intCast(tag)];

    var n_heads: i32 = 0;
    var pos = c.server.clients.next;
    const head = listHead(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (VISIBLEON(cl, m) and ISSCROLLTILED(cl)) {
            const node = find_scroller_node(st, cl);
            if (node != null and node.?.prev_in_stack == null)
                n_heads += 1;
        }
    }

    if (n_heads == 0) {
        sync_scroller_state_to_clients(m, tag);
        return;
    }

    const heads_raw = calloc(@intCast(n_heads), @sizeOf(*Node)) orelse {
        sync_scroller_state_to_clients(m, tag);
        return;
    };
    const heads: [*]*Node = @ptrCast(@alignCast(heads_raw));
    defer free(heads_raw);

    var head_idx: i32 = 0;
    pos = c.server.clients.next;
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (VISIBLEON(cl, m) and ISSCROLLTILED(cl)) {
            const node = find_scroller_node(st, cl);
            if (node != null and node.?.prev_in_stack == null) {
                var already = false;
                var k: i32 = 0;
                while (k < head_idx) : (k += 1) {
                    if (heads[@intCast(k)] == node.?) {
                        already = true;
                        break;
                    }
                }
                if (!already) {
                    heads[@intCast(head_idx)] = node.?;
                    head_idx += 1;
                }
            }
        }
    }
    n_heads = head_idx;
    m.visible_scroll_tiling_clients = @intCast(n_heads);

    var cur_gappih: i32 = if (c.server.enable_gaps != 0) m.gappih else 0;
    var cur_gappoh: i32 = if (c.server.enable_gaps != 0) m.gappoh else 0;
    var cur_gappov: i32 = if (c.server.enable_gaps != 0) m.gappov else 0;
    const cur_gappiv: i32 = if (c.server.enable_gaps != 0) m.gappiv else 0;
    if (c.config.smartgaps != 0 and n_heads == 1) {
        cur_gappih = 0;
        cur_gappoh = 0;
        cur_gappov = 0;
    }
    const max_client_width = m.w.width - 2 * c.config.scroller_structs - cur_gappih;

    if (n_heads == 1 and ignore_single == 0 and
        heads[0].client.*.isfullscreen == 0 and
        heads[0].client.*.ismaximizescreen == 0)
    {
        const hd = heads[0];
        const single_prop: f32 = if (hd.scroller_proportion_single > 0.0)
            hd.scroller_proportion_single
        else
            default_single;
        var target: Box = undefined;
        target.height = m.w.height - 2 * cur_gappov;
        target.width = truncF(@as(f32, @floatFromInt(m.w.width - 2 * cur_gappoh)) * single_prop);
        target.x = m.w.x + @divTrunc(m.w.width - target.width, 2);
        target.y = m.w.y + @divTrunc(m.w.height - target.height, 2);
        horizontal_check_scroller_root_inside_mon(clientOpt(hd.client), &target);
        scroller_arrange_stack_node(hd, target, cur_gappiv, ctx);
        sync_scroller_state_to_clients(m, tag);
        return;
    }

    var root_node: ?*Node = null;
    if (m.sel != null and ISSCROLLTILED(clientOpt(m.sel))) {
        root_node = find_scroller_node(st, clientOpt(m.sel));
        if (root_node) |rn| {
            var walk = rn;
            while (walk.prev_in_stack != null)
                walk = nodeOpt(walk.prev_in_stack).?;
            root_node = walk;
        }
    }
    if (root_node == null and m.prevsel != null and ISSCROLLTILED(clientOpt(m.prevsel))) {
        root_node = find_scroller_node(st, clientOpt(m.prevsel));
        if (root_node) |rn| {
            var walk = rn;
            while (walk.prev_in_stack != null)
                walk = nodeOpt(walk.prev_in_stack).?;
            root_node = walk;
        }
    }
    if (root_node == null)
        root_node = heads[@intCast(@divTrunc(n_heads, 2))];

    var focus_index: i32 = -1;
    var i: i32 = 0;
    while (i < n_heads) : (i += 1) {
        if (heads[@intCast(i)] == root_node.?) {
            focus_index = i;
            break;
        }
    }
    if (focus_index < 0)
        focus_index = @divTrunc(n_heads, 2);

    var need_scroller = false;
    var over_overspread_to_left = false;
    const root_client = clientOpt(root_node.?.client).?;

    if (root_client.geom.x >= m.w.x + c.config.scroller_structs and
        root_client.geom.x + root_client.geom.width <=
            m.w.x + m.w.width - c.config.scroller_structs)
    {
        need_scroller = false;
    } else {
        need_scroller = true;
    }

    var need_apply_overspread =
        c.config.scroller_prefer_overspread != 0 and n_heads > 1 and
        (focus_index == 0 or focus_index == n_heads - 1) and
        heads[@intCast(focus_index)].scroller_proportion < 1.0;

    if (need_apply_overspread) {
        if (focus_index == 0)
            over_overspread_to_left = true
        else
            over_overspread_to_left = false;

        if (over_overspread_to_left and
            (!INSIDEMON(clientOpt(heads[1].client).?) or
                (heads[1].scroller_proportion + heads[0].scroller_proportion >= 1.0)))
        {
            need_scroller = true;
        } else if (!over_overspread_to_left and
            (!INSIDEMON(clientOpt(heads[@intCast(focus_index - 1)].client).?) or
                (heads[@intCast(focus_index - 1)].scroller_proportion +
                    heads[@intCast(focus_index)].scroller_proportion >= 1.0)))
        {
            need_scroller = true;
        } else {
            need_apply_overspread = false;
        }
    }

    const need_apply_center =
        c.config.scroller_focus_center != 0 or n_heads == 1 or
        (c.config.scroller_prefer_center != 0 and !need_apply_overspread and
            (m.prevsel == null or
                (ISSCROLLTILED(clientOpt(m.prevsel)) and
                    (clientOpt(m.prevsel).?.scroller_proportion * @as(f32, @floatFromInt(max_client_width)) +
                        heads[@intCast(focus_index)].scroller_proportion * @as(f32, @floatFromInt(max_client_width))) >
                        @as(f32, @floatFromInt(m.w.width - 2 * c.config.scroller_structs - cur_gappih)))));

    if (n_heads == 1 and ignore_single != 0)
        need_scroller = true;
    if (c.server.start_drag_window)
        need_scroller = false;

    var target: Box = undefined;
    target.height = m.w.height - 2 * cur_gappov;
    target.width = truncF(@as(f32, @floatFromInt(max_client_width)) *
        heads[@intCast(focus_index)].scroller_proportion);
    target.y = m.w.y + @divTrunc(m.w.height - target.height, 2);
    horizontal_scroll_adjust_fullandmax(clientOpt(heads[@intCast(focus_index)].client), &target);

    if (heads[@intCast(focus_index)].client.*.isfullscreen != 0) {
        target.x = m.m.x;
        horizontal_check_scroller_root_inside_mon(clientOpt(heads[@intCast(focus_index)].client), &target);
        scroller_arrange_stack_node(heads[@intCast(focus_index)], target, cur_gappiv, ctx);
    } else if (heads[@intCast(focus_index)].client.*.ismaximizescreen != 0) {
        target.x = m.w.x + cur_gappoh;
        horizontal_check_scroller_root_inside_mon(clientOpt(heads[@intCast(focus_index)].client), &target);
        scroller_arrange_stack_node(heads[@intCast(focus_index)], target, cur_gappiv, ctx);
    } else if (need_scroller) {
        const focus_prop_width = heads[@intCast(focus_index)].scroller_proportion *
            @as(f32, @floatFromInt(max_client_width));
        if (need_apply_center) {
            target.x = m.w.x + @divTrunc(m.w.width - target.width, 2);
        } else if (need_apply_overspread) {
            if (over_overspread_to_left) {
                target.x = m.w.x + c.config.scroller_structs;
            } else {
                target.x = truncF(@as(f32, @floatFromInt(m.w.x)) +
                    (@as(f32, @floatFromInt(m.w.width)) - focus_prop_width -
                        @as(f32, @floatFromInt(c.config.scroller_structs))));
            }
        } else {
            target.x = if (root_client.geom.x > m.w.x + @divTrunc(m.w.width, 2))
                truncF(@as(f32, @floatFromInt(m.w.x)) +
                    (@as(f32, @floatFromInt(m.w.width)) - focus_prop_width -
                        @as(f32, @floatFromInt(c.config.scroller_structs))))
            else
                m.w.x + c.config.scroller_structs;
        }
        horizontal_check_scroller_root_inside_mon(clientOpt(heads[@intCast(focus_index)].client), &target);
        scroller_arrange_stack_node(heads[@intCast(focus_index)], target, cur_gappiv, ctx);
    } else {
        target.x = root_client.geom.x;
        horizontal_check_scroller_root_inside_mon(clientOpt(heads[@intCast(focus_index)].client), &target);
        scroller_arrange_stack_node(heads[@intCast(focus_index)], target, cur_gappiv, ctx);
    }

    i = 1;
    while (i <= focus_index) : (i += 1) {
        const cur = heads[@intCast(focus_index - i)];
        var left: Box = undefined;
        left.height = m.w.height - 2 * cur_gappov;
        left.width = truncF(@as(f32, @floatFromInt(max_client_width)) * cur.scroller_proportion);
        horizontal_scroll_adjust_fullandmax(clientOpt(cur.client), &left);
        left.x = clientOpt(heads[@intCast(focus_index - i + 1)].client).?.geom.x -
            cur_gappih - left.width;
        scroller_arrange_stack_node(cur, left, cur_gappiv, ctx);
    }

    i = 1;
    while (i < n_heads - focus_index) : (i += 1) {
        const cur = heads[@intCast(focus_index + i)];
        var right: Box = undefined;
        right.height = m.w.height - 2 * cur_gappov;
        right.width = truncF(@as(f32, @floatFromInt(max_client_width)) * cur.scroller_proportion);
        horizontal_scroll_adjust_fullandmax(clientOpt(cur.client), &right);
        right.x = clientOpt(heads[@intCast(focus_index + i - 1)].client).?.geom.x +
            cur_gappih + clientOpt(heads[@intCast(focus_index + i - 1)].client).?.geom.width;
        scroller_arrange_stack_node(cur, right, cur_gappiv, ctx);
    }

    sync_scroller_state_to_clients(m, tag);
}

// ---------------------------------------------------------------------------
// vertical scroller core
// ---------------------------------------------------------------------------

fn verticalScrollerCore(m: *Monitor, ctx: ?*const LayoutContext) void {
    const tag = get_mon_curtag(m);
    const st = ensure_scroller_state(m, tag) orelse return;
    const default_single = m.pertag.*.scroller_default_proportion_single[@intCast(tag)];
    const ignore_single = m.pertag.*.scroller_ignore_proportion_single[@intCast(tag)];

    var n_heads: i32 = 0;
    var pos = c.server.clients.next;
    const head = listHead(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (VISIBLEON(cl, m) and ISSCROLLTILED(cl)) {
            const node = find_scroller_node(st, cl);
            if (node != null and node.?.prev_in_stack == null)
                n_heads += 1;
        }
    }

    if (n_heads == 0) {
        sync_scroller_state_to_clients(m, tag);
        return;
    }

    const heads_raw = calloc(@intCast(n_heads), @sizeOf(*Node)) orelse {
        sync_scroller_state_to_clients(m, tag);
        return;
    };
    const heads: [*]*Node = @ptrCast(@alignCast(heads_raw));
    defer free(heads_raw);

    var head_idx: i32 = 0;
    pos = c.server.clients.next;
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (VISIBLEON(cl, m) and ISSCROLLTILED(cl)) {
            const node = find_scroller_node(st, cl);
            if (node != null and node.?.prev_in_stack == null) {
                var already = false;
                var k: i32 = 0;
                while (k < head_idx) : (k += 1) {
                    if (heads[@intCast(k)] == node.?) {
                        already = true;
                        break;
                    }
                }
                if (!already) {
                    heads[@intCast(head_idx)] = node.?;
                    head_idx += 1;
                }
            }
        }
    }
    n_heads = head_idx;
    m.visible_scroll_tiling_clients = @intCast(n_heads);

    var cur_gappiv: i32 = if (c.server.enable_gaps != 0) m.gappiv else 0;
    var cur_gappov: i32 = if (c.server.enable_gaps != 0) m.gappov else 0;
    var cur_gappoh: i32 = if (c.server.enable_gaps != 0) m.gappoh else 0;
    const cur_gappih: i32 = if (c.server.enable_gaps != 0) m.gappih else 0;
    if (c.config.smartgaps != 0 and n_heads == 1) {
        cur_gappiv = 0;
        cur_gappov = 0;
        cur_gappoh = 0;
    }
    const max_client_height = m.w.height - 2 * c.config.scroller_structs - cur_gappiv;

    if (n_heads == 1 and ignore_single == 0 and
        heads[0].client.*.isfullscreen == 0 and
        heads[0].client.*.ismaximizescreen == 0)
    {
        const hd = heads[0];
        const single_prop: f32 = if (hd.scroller_proportion_single > 0.0)
            hd.scroller_proportion_single
        else
            default_single;
        var target: Box = undefined;
        target.width = m.w.width - 2 * cur_gappoh;
        target.height = truncF(@as(f32, @floatFromInt(m.w.height - 2 * cur_gappov)) * single_prop);
        target.y = m.w.y + @divTrunc(m.w.height - target.height, 2);
        target.x = m.w.x + @divTrunc(m.w.width - target.width, 2);
        vertical_check_scroller_root_inside_mon(clientOpt(hd.client), &target);
        scroller_arrange_stack_vertical_node(hd, target, cur_gappih, ctx);
        sync_scroller_state_to_clients(m, tag);
        return;
    }

    var root_node: ?*Node = null;
    if (m.sel != null and ISSCROLLTILED(clientOpt(m.sel))) {
        root_node = find_scroller_node(st, clientOpt(m.sel));
        if (root_node) |rn| {
            var walk = rn;
            while (walk.prev_in_stack != null)
                walk = nodeOpt(walk.prev_in_stack).?;
            root_node = walk;
        }
    }
    if (root_node == null and m.prevsel != null and ISSCROLLTILED(clientOpt(m.prevsel))) {
        root_node = find_scroller_node(st, clientOpt(m.prevsel));
        if (root_node) |rn| {
            var walk = rn;
            while (walk.prev_in_stack != null)
                walk = nodeOpt(walk.prev_in_stack).?;
            root_node = walk;
        }
    }
    if (root_node == null)
        root_node = heads[@intCast(@divTrunc(n_heads, 2))];

    var focus_index: i32 = -1;
    var i: i32 = 0;
    while (i < n_heads) : (i += 1) {
        if (heads[@intCast(i)] == root_node.?) {
            focus_index = i;
            break;
        }
    }
    if (focus_index < 0)
        focus_index = @divTrunc(n_heads, 2);

    var need_scroller = false;
    var over_overspread_to_up = false;
    const root_client = clientOpt(root_node.?.client).?;

    if (root_client.geom.y >= m.w.y + c.config.scroller_structs and
        root_client.geom.y + root_client.geom.height <=
            m.w.y + m.w.height - c.config.scroller_structs)
    {
        need_scroller = false;
    } else {
        need_scroller = true;
    }

    var need_apply_overspread =
        c.config.scroller_prefer_overspread != 0 and n_heads > 1 and
        (focus_index == 0 or focus_index == n_heads - 1) and
        heads[@intCast(focus_index)].scroller_proportion < 1.0;

    if (need_apply_overspread) {
        if (focus_index == 0)
            over_overspread_to_up = true
        else
            over_overspread_to_up = false;

        if (over_overspread_to_up and
            (!INSIDEMON(clientOpt(heads[1].client).?) or
                (heads[1].scroller_proportion + heads[0].scroller_proportion >= 1.0)))
        {
            need_scroller = true;
        } else if (!over_overspread_to_up and
            (!INSIDEMON(clientOpt(heads[@intCast(focus_index - 1)].client).?) or
                (heads[@intCast(focus_index - 1)].scroller_proportion +
                    heads[@intCast(focus_index)].scroller_proportion >= 1.0)))
        {
            need_scroller = true;
        } else {
            need_apply_overspread = false;
        }
    }

    const need_apply_center =
        c.config.scroller_focus_center != 0 or n_heads == 1 or
        (c.config.scroller_prefer_center != 0 and !need_apply_overspread and
            (m.prevsel == null or
                (ISSCROLLTILED(clientOpt(m.prevsel)) and
                    (clientOpt(m.prevsel).?.scroller_proportion * @as(f32, @floatFromInt(max_client_height)) +
                        heads[@intCast(focus_index)].scroller_proportion * @as(f32, @floatFromInt(max_client_height))) >
                        @as(f32, @floatFromInt(m.w.height - 2 * c.config.scroller_structs - cur_gappiv)))));

    if (n_heads == 1 and ignore_single != 0)
        need_scroller = true;
    if (c.server.start_drag_window)
        need_scroller = false;

    var target: Box = undefined;
    target.width = m.w.width - 2 * cur_gappoh;
    target.height = truncF(@as(f32, @floatFromInt(max_client_height)) *
        heads[@intCast(focus_index)].scroller_proportion);
    target.x = m.w.x + @divTrunc(m.w.width - target.width, 2);
    vertical_scroll_adjust_fullandmax(clientOpt(heads[@intCast(focus_index)].client), &target);

    var bar_height: i32 = 0;
    if (heads[@intCast(focus_index)].client.*.isfullscreen != 0) {
        target.y = m.m.y;
        vertical_check_scroller_root_inside_mon(clientOpt(heads[@intCast(focus_index)].client), &target);
        scroller_arrange_stack_vertical_node(heads[@intCast(focus_index)], target, cur_gappih, ctx);
    } else if (heads[@intCast(focus_index)].client.*.ismaximizescreen != 0) {
        target.y = m.w.y + cur_gappov;
        vertical_check_scroller_root_inside_mon(clientOpt(heads[@intCast(focus_index)].client), &target);
        scroller_arrange_stack_vertical_node(heads[@intCast(focus_index)], target, cur_gappih, ctx);
    } else if (need_scroller) {
        const focus_prop_height = heads[@intCast(focus_index)].scroller_proportion *
            @as(f32, @floatFromInt(max_client_height));
        if (need_apply_center) {
            target.y = m.w.y + @divTrunc(m.w.height - target.height, 2);
        } else if (need_apply_overspread) {
            if (over_overspread_to_up) {
                target.y = m.w.y + c.config.scroller_structs;
            } else {
                target.y = truncF(@as(f32, @floatFromInt(m.w.y)) +
                    (@as(f32, @floatFromInt(m.w.height)) - focus_prop_height -
                        @as(f32, @floatFromInt(c.config.scroller_structs))));
            }
        } else {
            target.y = if (root_client.geom.y > m.w.y + @divTrunc(m.w.height, 2))
                truncF(@as(f32, @floatFromInt(m.w.y)) +
                    (@as(f32, @floatFromInt(m.w.height)) - focus_prop_height -
                        @as(f32, @floatFromInt(c.config.scroller_structs))))
            else
                m.w.y + c.config.scroller_structs;
        }
        vertical_check_scroller_root_inside_mon(clientOpt(heads[@intCast(focus_index)].client), &target);
        scroller_arrange_stack_vertical_node(heads[@intCast(focus_index)], target, cur_gappih, ctx);
    } else {
        bar_height = if (root_client.isfullscreen == 0 and client_wants_group_bar(root_client))
            @intCast(c.config.group_bar_height)
        else
            0;
        target.y = root_client.geom.y - bar_height;
        vertical_check_scroller_root_inside_mon(clientOpt(heads[@intCast(focus_index)].client), &target);
        scroller_arrange_stack_vertical_node(heads[@intCast(focus_index)], target, cur_gappih, ctx);
    }

    i = 1;
    while (i <= focus_index) : (i += 1) {
        const cur = heads[@intCast(focus_index - i)];
        var up: Box = undefined;
        up.width = m.w.width - 2 * cur_gappoh;
        up.height = truncF(@as(f32, @floatFromInt(max_client_height)) * cur.scroller_proportion);
        vertical_scroll_adjust_fullandmax(clientOpt(cur.client), &up);

        bar_height = if (heads[@intCast(focus_index - i + 1)].client.*.isfullscreen == 0 and
            client_wants_group_bar(clientOpt(heads[@intCast(focus_index - i + 1)].client).?))
            @intCast(c.config.group_bar_height)
        else
            0;

        up.y = clientOpt(heads[@intCast(focus_index - i + 1)].client).?.geom.y -
            cur_gappiv - up.height - bar_height;
        scroller_arrange_stack_vertical_node(cur, up, cur_gappih, ctx);
    }

    i = 1;
    while (i < n_heads - focus_index) : (i += 1) {
        const cur = heads[@intCast(focus_index + i)];
        var down: Box = undefined;
        down.width = m.w.width - 2 * cur_gappoh;
        down.height = truncF(@as(f32, @floatFromInt(max_client_height)) * cur.scroller_proportion);
        vertical_scroll_adjust_fullandmax(clientOpt(cur.client), &down);
        down.y = clientOpt(heads[@intCast(focus_index + i - 1)].client).?.geom.y +
            cur_gappiv + clientOpt(heads[@intCast(focus_index + i - 1)].client).?.geom.height;
        scroller_arrange_stack_vertical_node(cur, down, cur_gappih, ctx);
    }

    sync_scroller_state_to_clients(m, tag);
}

// ---------------------------------------------------------------------------
// client removal / insertion / drop
// ---------------------------------------------------------------------------

export fn scroller_remove_client(cl_in: ?*Client) callconv(.c) void {
    const cl = cl_in orelse return;
    var pos = c.server.monitors.next;
    const head = listHead(&c.server.monitors);
    while (pos != head) : (pos = pos.*.next) {
        const m = containerOf(Monitor, "link", pos);
        for (&m.pertag.*.scroller_state) |*slot| {
            const st = stateOpt(slot.*) orelse continue;
            if (find_scroller_node(st, cl)) |node|
                scroller_node_remove(st, node);
        }
    }
}

export fn scroller_insert_stack(
    cl_in: ?*Client,
    target_in: ?*Client,
    insert_before: bool,
) callconv(.c) void {
    const cl = cl_in orelse return;
    const target = target_in orelse return;
    if (target.mon != cl.mon)
        return;

    if (cl.isfullscreen != 0)
        client_apply_fullscreen(cl, 0, true);
    if (cl.ismaximizescreen != 0)
        client_set_maximize_screen(cl, 0, true);

    const m = monitorOpt(cl.mon) orelse return;
    const tag = get_mon_curtag(m);
    const st = ensure_scroller_state(m, tag) orelse return;

    if (find_scroller_node(st, cl)) |cn|
        scroller_node_remove(st, cn);

    var tnode = find_scroller_node(st, target);
    if (tnode == null)
        tnode = scroller_node_create(st, target);
    const tn = tnode orelse return;

    const newnode = scroller_node_create(st, cl) orelse return;

    if (insert_before) {
        newnode.next_in_stack = nodePtr(tn);
        newnode.prev_in_stack = tn.prev_in_stack;
        if (tn.prev_in_stack != null)
            tn.prev_in_stack.*.next_in_stack = nodePtr(newnode);
        tn.prev_in_stack = nodePtr(newnode);
        wl_list_safe_reinsert_prev(&clientOpt(tn.client).?.link, &cl.link);
    } else {
        newnode.prev_in_stack = nodePtr(tn);
        newnode.next_in_stack = tn.next_in_stack;
        if (tn.next_in_stack != null)
            tn.next_in_stack.*.prev_in_stack = nodePtr(newnode);
        tn.next_in_stack = nodePtr(newnode);
        wl_list_safe_reinsert_next(&clientOpt(tn.client).?.link, &cl.link);
    }

    var hd = tn;
    while (hd.prev_in_stack != null)
        hd = nodeOpt(hd.prev_in_stack).?;
    const stack_head = clientOpt(hd.client) orelse return;
    if (stack_head.ismaximizescreen != 0)
        client_set_maximize_screen(stack_head, 0, true);
    if (stack_head.isfullscreen != 0)
        client_apply_fullscreen(stack_head, 0, true);

    sync_scroller_state_to_clients(m, tag);
    arrange(m, false, false);
}

export fn scroller_drop_tile(cl_in: ?*Client, closest_in: ?*Client, vertical: i32) callconv(.c) void {
    const cl = cl_in orelse return;
    const closest = closest_in orelse return;
    const m = monitorOpt(cl.mon) orelse return;

    update_scroller_state(m);
    const stack_head = (scroll_get_stack_head_client(closest) orelse closest);
    const stack_tail = (scroll_get_stack_tail_client(closest) orelse closest);

    if (vertical != 0) {
        if (closest.drop_direction == c.LEFT) {
            client_set_floating(cl, 0);
            scroller_insert_stack(cl, closest, true);
            return;
        } else if (closest.drop_direction == c.RIGHT) {
            client_set_floating(cl, 0);
            scroller_insert_stack(cl, closest, false);
            return;
        } else if (closest.drop_direction == c.UP) {
            if (cl != stack_head)
                wl_list_safe_reinsert_prev(&stack_head.link, &cl.link);
        } else if (closest.drop_direction == c.DOWN) {
            if (cl != stack_tail)
                wl_list_safe_reinsert_next(&stack_head.link, &cl.link);
        }
    } else {
        if (closest.drop_direction == c.UP) {
            client_set_floating(cl, 0);
            scroller_insert_stack(cl, closest, true);
            return;
        } else if (closest.drop_direction == c.DOWN) {
            client_set_floating(cl, 0);
            scroller_insert_stack(cl, closest, false);
            return;
        } else if (closest.drop_direction == c.LEFT) {
            if (cl != stack_head)
                wl_list_safe_reinsert_prev(&stack_head.link, &cl.link);
        } else if (closest.drop_direction == c.RIGHT) {
            if (cl != stack_tail)
                wl_list_safe_reinsert_next(&stack_head.link, &cl.link);
        }
    }

    client_set_floating(cl, 0);
}

export fn scroll_get_stack_head_client(cl_in: ?*Client) callconv(.c) ?*Client {
    const cl = cl_in orelse return null;
    const m = monitorOpt(cl.mon) orelse return cl;
    const tag = get_client_tag_idx(cl);
    const st = stateOpt(m.pertag.*.scroller_state[@intCast(tag)]) orelse return cl;
    var n = find_scroller_node(st, cl) orelse return cl;
    while (n.prev_in_stack != null)
        n = nodeOpt(n.prev_in_stack).?;
    return clientOpt(n.client) orelse cl;
}

export fn scroll_get_stack_tail_client(cl_in: ?*Client) callconv(.c) ?*Client {
    const cl = cl_in orelse return null;
    const m = monitorOpt(cl.mon) orelse return cl;
    const tag = get_client_tag_idx(cl);
    const st = stateOpt(m.pertag.*.scroller_state[@intCast(tag)]) orelse return cl;
    var n = find_scroller_node(st, cl) orelse return cl;
    while (n.next_in_stack != null)
        n = nodeOpt(n.next_in_stack).?;
    return clientOpt(n.client) orelse cl;
}

export fn update_scroller_state(m: *Monitor) callconv(.c) void {
    const tag = get_mon_curtag(m);
    const st = ensure_scroller_state(m, tag) orelse return;

    var count: i32 = 0;
    var pos = c.server.clients.next;
    const head = listHead(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (VISIBLEON(cl, m) and ISSCROLLTILED(cl))
            count += 1;
    }

    const vis_raw = calloc(if (count != 0) @intCast(count) else 1, @sizeOf(*Client)) orelse return;
    const vis: [*]*Client = @ptrCast(@alignCast(vis_raw));
    defer free(vis_raw);

    var vi: i32 = 0;
    pos = c.server.clients.next;
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (VISIBLEON(cl, m) and ISSCROLLTILED(cl)) {
            vis[@intCast(vi)] = cl;
            vi += 1;
        }
    }

    var n = st.all_first;
    while (n != null) {
        var found = false;
        var i: i32 = 0;
        while (i < count) : (i += 1) {
            if (vis[@intCast(i)] == clientOpt(n.*.client)) {
                found = true;
                break;
            }
        }
        const next = n.*.all_next;
        if (!found)
            scroller_node_remove(st, @ptrCast(n));
        n = next;
    }

    var i: i32 = 0;
    while (i < count) : (i += 1) {
        if (find_scroller_node(st, vis[@intCast(i)]) == null)
            _ = scroller_node_create(st, vis[@intCast(i)]);
    }
}

// ---------------------------------------------------------------------------
// same-stack and cross-stack swaps
// ---------------------------------------------------------------------------

export fn scroller_swap_nodes_in_same_stack(n1_in: ?*Node, n2_in: ?*Node) callconv(.c) void {
    const n1 = n1_in orelse return;
    const n2 = n2_in orelse return;

    const tmp_sc = n1.scroller_proportion;
    const tmp_st = n1.scroller_stack_proportion;
    const tmp_sw = n1.scroller_stack_weight;
    n1.scroller_proportion = n2.scroller_proportion;
    n1.scroller_stack_proportion = n2.scroller_stack_proportion;
    n1.scroller_stack_weight = n2.scroller_stack_weight;
    n2.scroller_proportion = tmp_sc;
    n2.scroller_stack_proportion = tmp_st;
    n2.scroller_stack_weight = tmp_sw;

    const p1 = nodeOpt(n1.prev_in_stack);
    const next1 = nodeOpt(n1.next_in_stack);
    const p2 = nodeOpt(n2.prev_in_stack);
    const next2 = nodeOpt(n2.next_in_stack);

    if (n1.next_in_stack == nodePtr(n2)) {
        n1.next_in_stack = nodePtr(next2);
        n2.prev_in_stack = nodePtr(p1);
        n1.prev_in_stack = nodePtr(n2);
        n2.next_in_stack = nodePtr(n1);
        if (p1) |p|
            p.next_in_stack = nodePtr(n2);
        if (next2) |nx|
            nx.prev_in_stack = nodePtr(n1);
    } else if (n2.next_in_stack == nodePtr(n1)) {
        n2.next_in_stack = nodePtr(next1);
        n1.prev_in_stack = nodePtr(p2);
        n2.prev_in_stack = nodePtr(n1);
        n1.next_in_stack = nodePtr(n2);
        if (p2) |p|
            p.next_in_stack = nodePtr(n1);
        if (next1) |nx|
            nx.prev_in_stack = nodePtr(n2);
    } else {
        if (p1) |p|
            p.next_in_stack = nodePtr(n2);
        if (next1) |nx|
            nx.prev_in_stack = nodePtr(n2);
        if (p2) |p|
            p.next_in_stack = nodePtr(n1);
        if (next2) |nx|
            nx.prev_in_stack = nodePtr(n1);
        n1.prev_in_stack = nodePtr(p2);
        n1.next_in_stack = nodePtr(next2);
        n2.prev_in_stack = nodePtr(p1);
        n2.next_in_stack = nodePtr(next1);
    }
}

export fn scroller_swap_different_stacks(head1_in: ?*Node, head2_in: ?*Node) callconv(.c) void {
    const head1 = head1_in orelse return;
    const head2 = head2_in orelse return;
    const head1_c = clientOpt(head1.client) orelse return;
    const head2_c = clientOpt(head2.client) orelse return;
    const tail1_c = scroll_get_stack_tail_client(head1_c) orelse return;
    const tail2_c = scroll_get_stack_tail_client(head2_c) orelse return;

    const p1 = head1_c.link.prev;
    const n1_next = tail1_c.link.next;
    const p2 = head2_c.link.prev;
    const n2_next = tail2_c.link.next;

    if (n1_next == @as([*c]WlList, @ptrCast(&head2_c.link))) {
        p2.*.next = n2_next;
        n2_next.*.prev = p2;
        p1.*.next = @ptrCast(&head2_c.link);
        head2_c.link.prev = p1;
        tail2_c.link.next = @ptrCast(&head1_c.link);
        head1_c.link.prev = @ptrCast(&tail2_c.link);
    } else if (n2_next == @as([*c]WlList, @ptrCast(&head1_c.link))) {
        p1.*.next = n1_next;
        n1_next.*.prev = p1;
        p2.*.next = @ptrCast(&head1_c.link);
        head1_c.link.prev = p2;
        tail1_c.link.next = @ptrCast(&head2_c.link);
        head2_c.link.prev = @ptrCast(&tail1_c.link);
    } else {
        p1.*.next = @ptrCast(&head2_c.link);
        head2_c.link.prev = p1;
        tail2_c.link.next = n1_next;
        n1_next.*.prev = @ptrCast(&tail2_c.link);

        p2.*.next = @ptrCast(&head1_c.link);
        head1_c.link.prev = p2;
        tail1_c.link.next = n2_next;
        n2_next.*.prev = @ptrCast(&tail1_c.link);
    }
}

export fn exchange_two_scroller_clients(c1_in: ?*Client, c2_in: ?*Client) callconv(.c) void {
    const c1 = c1_in orelse return;
    const c2 = c2_in orelse return;
    const m1 = monitorOpt(c1.mon) orelse return;
    const m2 = monitorOpt(c2.mon) orelse return;
    const tag1 = get_mon_curtag(m1);
    const tag2 = get_mon_curtag(m2);

    const st1 = ensure_scroller_state(m1, tag1) orelse return;
    const n1 = find_scroller_node(st1, c1);
    const st2 = ensure_scroller_state(m2, tag2) orelse return;
    const n2 = find_scroller_node(st2, c2);

    if (n1 == null and n2 == null)
        return;

    if (m1 != m2 and
        ((n1 != null and n1.?.prev_in_stack != null) or
            (n2 != null and n2.?.prev_in_stack != null) or
            (n1 != null and n1.?.next_in_stack != null) or
            (n2 != null and n2.?.next_in_stack != null)))
        return;

    client_swap_layout_properties(c1, c2);

    if (n1 != null and n2 != null) {
        var hd1 = n1.?;
        while (hd1.prev_in_stack != null)
            hd1 = nodeOpt(hd1.prev_in_stack).?;
        var hd2 = n2.?;
        while (hd2.prev_in_stack != null)
            hd2 = nodeOpt(hd2.prev_in_stack).?;

        if (hd1 == hd2) {
            scroller_swap_nodes_in_same_stack(n1, n2);
            sync_scroller_state_to_clients(m1, tag1);
            wl_list_swap(&c1.link, &c2.link);
        } else {
            scroller_swap_different_stacks(hd1, hd2);
        }
    } else {
        wl_list_swap(&c1.link, &c2.link);
    }

    if (m1 != m2)
        client_swap_monitors_and_tags(c1, c2);
    finish_exchange_arrange_and_focus(c1, c2, m1, m2);
}

// ---------------------------------------------------------------------------
// layout exports
// ---------------------------------------------------------------------------

fn layoutPredictBox(core: CoreFn, m: *Monitor, cl: *Client, out: *Box) bool {
    var geo = std.mem.zeroes(Box);
    var ctx = LayoutContext{ .probe = cl, .out = &geo };
    core(m, &ctx);
    out.* = geo;
    return geo.width > 0 and geo.height > 0;
}

export fn scroller(m: *Monitor) callconv(.c) void {
    scrollerCore(m, null);
}

export fn scroller_predict(m: *Monitor, cl: *Client, out: *Box) callconv(.c) bool {
    return layoutPredictBox(scrollerCore, m, cl, out);
}

export fn vertical_scroller(m: *Monitor) callconv(.c) void {
    verticalScrollerCore(m, null);
}

export fn vertical_scroller_predict(m: *Monitor, cl: *Client, out: *Box) callconv(.c) bool {
    return layoutPredictBox(verticalScrollerCore, m, cl, out);
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/layout_scroll_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_curtag: c_int;
extern var stub_client_tag: c_int;
extern var stub_tile_calls: c_int;
extern var stub_tile_boxes: [512]Box;
extern var stub_tile_clients: [512]?*Client;
extern var stub_floating_calls: c_int;
extern var stub_fullscreen_calls: c_int;
extern var stub_maximize_calls: c_int;
extern var stub_arrange_calls: c_int;
extern var stub_swap_props_calls: c_int;
extern var stub_swap_monitors_calls: c_int;
extern var stub_finish_calls: c_int;
extern var stub_group_bar: bool;

fn listInit(head: *WlList) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

fn listInsert(head: *WlList, link: *WlList) void {
    link.next = head.next;
    link.prev = @ptrCast(head);
    head.next.*.prev = @ptrCast(link);
    head.next = @ptrCast(link);
}

fn resetWorld() void {
    listInit(&c.server.clients);
    listInit(&c.server.monitors);
    c.config = std.mem.zeroes(c.Config);
    c.server.enable_gaps = 0;
    c.server.start_drag_window = false;
    stub_curtag = 0;
    stub_client_tag = 0;
    stub_tile_calls = 0;
    stub_floating_calls = 0;
    stub_fullscreen_calls = 0;
    stub_maximize_calls = 0;
    stub_arrange_calls = 0;
    stub_swap_props_calls = 0;
    stub_swap_monitors_calls = 0;
    stub_finish_calls = 0;
    stub_group_bar = false;
}

fn baseMonitor(m: *Monitor, p: *c.Pertag) void {
    m.* = std.mem.zeroes(Monitor);
    p.* = std.mem.zeroes(c.Pertag);
    m.pertag = p;
    m.w = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
    m.m = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
    m.tagset[0] = 0xffff;
    m.seltags = 0;
}

fn addClient(cl: *Client, m: *Monitor, tags: u32) void {
    cl.* = std.mem.zeroes(Client);
    cl.mon = @ptrCast(m);
    cl.tags = tags;
    listInsert(&c.server.clients, &cl.link);
}

fn stateOf(m: *Monitor) ?*State {
    return stateOpt(m.pertag.*.scroller_state[0]);
}

fn makeNode(m: *Monitor, cl: *Client) *Node {
    const st = ensure_scroller_state(m, 0).?;
    return scroller_node_create(st, cl).?;
}

fn linkNodes(a: *Node, b: *Node) void {
    a.next_in_stack = @ptrCast(b);
    b.prev_in_stack = @ptrCast(a);
}

fn expectBox(idx: usize, x: i32, y: i32, w: i32, h: i32) !void {
    const b = stub_tile_boxes[idx];
    try testing.expectEqual(x, b.x);
    try testing.expectEqual(y, b.y);
    try testing.expectEqual(w, b.width);
    try testing.expectEqual(h, b.height);
}

fn expectCount(n: usize) !void {
    try testing.expectEqual(@as(c_int, @intCast(n)), stub_tile_calls);
}

test "scroller state: create, find, sync, remove and clear" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);

    const st = ensure_scroller_state(&m, 0).?;
    try testing.expectEqual(@as(c_int, 0), st.count);
    const na = scroller_node_create(st, &a).?;
    const nb = scroller_node_create(st, &b).?;
    try testing.expectEqual(@as(c_int, 2), st.count);
    try testing.expect(find_scroller_node(st, &a) == na);
    try testing.expect(find_scroller_node(st, &b) == nb);

    na.scroller_proportion = 0.3;
    na.scroller_stack_weight = 2.0;
    na.scroller_proportion_single = 0.4;
    sync_scroller_state_to_clients(&m, 0);
    try testing.expectEqual(@as(f32, 0.3), a.scroller_proportion);
    try testing.expectEqual(@as(f32, 2.0), a.scroller_stack_proportion);
    try testing.expectEqual(@as(f32, 0.4), a.scroller_proportion_single);

    linkNodes(na, nb);
    scroller_node_remove(st, na);
    try testing.expectEqual(@as(c_int, 1), st.count);
    try testing.expect(find_scroller_node(st, &a) == null);
    try testing.expect(nb.prev_in_stack == null);

    cleanup_monitor_scroller(&m);
    try testing.expect(m.pertag.*.scroller_state[0] == null);
}

test "scroller stack arrangement normalizes weights and splits geometry" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    var clients: [3]Client = undefined;
    for (&clients) |*cl|
        addClient(cl, &m, 1);

    const st = ensure_scroller_state(&m, 0).?;
    var nodes: [3]*Node = undefined;
    for (&clients, 0..) |*cl, i|
        nodes[i] = scroller_node_create(st, cl).?;
    linkNodes(nodes[0], nodes[1]);
    linkNodes(nodes[1], nodes[2]);

    scroller_arrange_stack_node(nodes[0], .{ .x = 0, .y = 0, .width = 1000, .height = 800 }, 0, null);
    try expectCount(3);
    try expectBox(0, 0, 0, 1000, 266);
    try expectBox(1, 0, 266, 1000, 267);
    try expectBox(2, 0, 533, 1000, 267);

    stub_tile_calls = 0;
    scroller_arrange_stack_node(nodes[0], .{ .x = 0, .y = 0, .width = 1000, .height = 800 }, 10, null);
    try expectBox(0, 0, 0, 1000, 260);
    try expectBox(1, 0, 270, 1000, 260);
    try expectBox(2, 0, 540, 1000, 260);
}

test "scroller stack arrangement honors explicit weights" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    var clients: [3]Client = undefined;
    for (&clients) |*cl|
        addClient(cl, &m, 1);

    const st = ensure_scroller_state(&m, 0).?;
    var nodes: [3]*Node = undefined;
    for (&clients, 0..) |*cl, i|
        nodes[i] = scroller_node_create(st, cl).?;
    linkNodes(nodes[0], nodes[1]);
    linkNodes(nodes[1], nodes[2]);
    nodes[0].scroller_stack_weight = 1.0;
    nodes[1].scroller_stack_weight = 1.0;
    nodes[2].scroller_stack_weight = 2.0;

    scroller_arrange_stack_vertical_node(nodes[0], .{ .x = 0, .y = 0, .width = 1000, .height = 800 }, 0, null);
    try expectCount(3);
    try expectBox(0, 0, 0, 250, 800);
    try expectBox(1, 250, 0, 250, 800);
    try expectBox(2, 500, 0, 500, 800);
}

test "scroller insert stack links before/after and head/tail lookups" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    var a: Client = undefined;
    var b: Client = undefined;
    var c_cl: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);
    addClient(&c_cl, &m, 1);

    _ = makeNode(&m, &a);

    scroller_insert_stack(&b, &a, false);
    scroller_insert_stack(&c_cl, &a, true);

    const st = stateOf(&m).?;
    const na = find_scroller_node(st, &a).?;
    const nb = find_scroller_node(st, &b).?;
    const nc = find_scroller_node(st, &c_cl).?;
    try testing.expect(nc.next_in_stack == @as([*c]Node, @ptrCast(na)));
    try testing.expect(na.prev_in_stack == @as([*c]Node, @ptrCast(nc)));
    try testing.expect(na.next_in_stack == @as([*c]Node, @ptrCast(nb)));
    try testing.expect(nb.prev_in_stack == @as([*c]Node, @ptrCast(na)));

    try testing.expect(scroll_get_stack_head_client(&b) == &c_cl);
    try testing.expect(scroll_get_stack_tail_client(&c_cl) == &b);
    try testing.expectEqual(@as(c_int, 2), stub_arrange_calls);
}

test "scroller update state adds visible clients and removes stale nodes" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);

    update_scroller_state(&m);
    const st = stateOf(&m).?;
    try testing.expectEqual(@as(c_int, 2), st.count);
    try testing.expect(find_scroller_node(st, &a) != null);
    try testing.expect(find_scroller_node(st, &b) != null);

    b.isminimized = 1;
    update_scroller_state(&m);
    try testing.expectEqual(@as(c_int, 1), st.count);
    try testing.expect(find_scroller_node(st, &a) != null);
    try testing.expect(find_scroller_node(st, &b) == null);
}

test "scroller_remove_client clears nodes on every monitor" {
    resetWorld();
    var p1: c.Pertag = undefined;
    var p2: c.Pertag = undefined;
    var m1: Monitor = undefined;
    var m2: Monitor = undefined;
    baseMonitor(&m1, &p1);
    baseMonitor(&m2, &p2);
    listInsert(&c.server.monitors, &m1.link);
    listInsert(&c.server.monitors, &m2.link);
    var a: Client = undefined;
    addClient(&a, &m1, 1);
    a.mon = @ptrCast(&m1);

    _ = makeNode(&m1, &a);
    _ = makeNode(&m2, &a);

    scroller_remove_client(&a);
    try testing.expect(find_scroller_node(stateOf(&m1).?, &a) == null);
    try testing.expect(find_scroller_node(stateOf(&m2).?, &a) == null);
}

test "scroller same-stack swap exchanges ratios and order" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);

    const n1 = makeNode(&m, &a);
    const n2 = makeNode(&m, &b);
    linkNodes(n1, n2);
    n1.scroller_proportion = 0.3;
    n2.scroller_proportion = 0.7;
    n1.scroller_stack_weight = 1.0;
    n2.scroller_stack_weight = 3.0;

    scroller_swap_nodes_in_same_stack(n1, n2);

    try testing.expectEqual(@as(f32, 0.7), n1.scroller_proportion);
    try testing.expectEqual(@as(f32, 0.3), n2.scroller_proportion);
    try testing.expectEqual(@as(f32, 3.0), n1.scroller_stack_weight);
    try testing.expectEqual(@as(f32, 1.0), n2.scroller_stack_weight);
    try testing.expect(n2.next_in_stack == @as([*c]Node, @ptrCast(n1)));
    try testing.expect(n1.prev_in_stack == @as([*c]Node, @ptrCast(n2)));
}

test "exchange_two_scroller_clients swaps same-stack clients" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);

    const n1 = makeNode(&m, &a);
    const n2 = makeNode(&m, &b);
    linkNodes(n1, n2);
    n1.scroller_proportion = 0.25;
    n2.scroller_proportion = 0.75;

    exchange_two_scroller_clients(&a, &b);
    try testing.expectEqual(@as(c_int, 1), stub_swap_props_calls);
    try testing.expectEqual(@as(c_int, 1), stub_finish_calls);
    try testing.expectEqual(@as(f32, 0.75), n1.scroller_proportion);
    try testing.expectEqual(@as(f32, 0.25), n2.scroller_proportion);
}

test "scroller single head uses proportion_single and centers" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    var a: Client = undefined;
    addClient(&a, &m, 1);
    _ = makeNode(&m, &a);
    m.pertag.*.scroller_default_proportion_single[0] = 0.7;

    scroller(&m);

    try testing.expectEqual(@as(u32, 1), m.visible_scroll_tiling_clients);
    try expectCount(1);
    try expectBox(0, 150, 0, 700, 800);
}

test "scroller two heads centers the focused stack and places the left stack" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);

    const na = makeNode(&m, &a);
    const nb = makeNode(&m, &b);
    na.scroller_proportion = 0.5;
    nb.scroller_proportion = 0.5;
    a.geom = .{ .x = -200, .y = 0, .width = 500, .height = 800 };
    b.geom = .{ .x = 500, .y = 0, .width = 500, .height = 800 };
    c.config.scroller_focus_center = 1;

    scroller(&m);

    try expectCount(2);
    try testing.expect(stub_tile_clients[0] == &a);
    try expectBox(0, 250, 0, 500, 800);
    try testing.expect(stub_tile_clients[1] == &b);
    try expectBox(1, -250, 0, 500, 800);
}

test "vertical_scroller single head uses vertical proportions" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    var a: Client = undefined;
    addClient(&a, &m, 1);
    _ = makeNode(&m, &a);
    m.pertag.*.scroller_default_proportion_single[0] = 0.5;

    vertical_scroller(&m);

    try testing.expectEqual(@as(u32, 1), m.visible_scroll_tiling_clients);
    try expectCount(1);
    try expectBox(0, 0, 200, 1000, 400);
}

test "scroller predict answers the probe without resizing" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    var a: Client = undefined;
    addClient(&a, &m, 1);
    const na = makeNode(&m, &a);
    na.scroller_proportion_single = 0.5;

    var out: Box = std.mem.zeroes(Box);
    try testing.expect(scroller_predict(&m, &a, &out));
    try testing.expectEqual(@as(i32, 250), out.x);
    try testing.expectEqual(@as(i32, 0), out.y);
    try testing.expectEqual(@as(i32, 500), out.width);
    try testing.expectEqual(@as(i32, 800), out.height);
    try expectCount(0);
}
