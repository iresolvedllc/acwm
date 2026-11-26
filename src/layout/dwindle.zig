//! Port of src/layout/dwindle.c (strangler-fig Phase 4, layout slice 2,
//! slice 30).
//!
//! Every public symbol from dwindle.h is exported: tree helpers
//! (count/find/first/free), removal with the manual-split proportional
//! rollback, assignment, insertion (generic + config-driven), swap/move,
//! cursor drag resize, monitor cleanup, the dwindle layout core and predict.
//! The C twin is guarded with ACWM_ZIG_LAYOUT_DWINDLE.
//!
//! Pointer-of-pointer roots match the C ABI: monitor slots are
//! `[*c]DwindleNode` and are passed as `*[*c]DwindleNode`. Ratios stay f32
//! (as in the C struct); insertion N arithmetic is f32 too.
//!
//! Still in C: get_mon_curtag, client_focus_top, client_tile_resize,
//! client_jump_to_monitor, monitor_from_direction, the swap helpers,
//! arrange and wl_list_swap. Tests stub all of them.

const std = @import("std");
const c = @import("cc");

const Node = c.DwindleNode;
const Client = c.Client;
const Monitor = c.Monitor;
const Box = c.struct_wlr_box;
const LayoutContext = c.LayoutContext;
const WlList = c.struct_wl_list;

extern fn get_mon_curtag(m: *const Monitor) callconv(.c) u32;
extern fn client_focus_top(m: *Monitor) callconv(.c) [*c]Client;
extern fn client_tile_resize(cl: *Client, geo: Box, interact: i32, ctx: ?*const LayoutContext) callconv(.c) void;
extern fn client_jump_to_monitor(cl: *Client, m: ?*Monitor, dir: i32) callconv(.c) bool;
extern fn monitor_from_direction(dir: c.enum_wlr_direction) callconv(.c) ?*Monitor;
extern fn client_swap_layout_properties(a: *Client, b: *Client) callconv(.c) void;
extern fn client_swap_monitors_and_tags(a: *Client, b: *Client) callconv(.c) void;
extern fn finish_exchange_arrange_and_focus(a: *Client, b: *Client, m1: *Monitor, m2: *Monitor) callconv(.c) void;
extern fn arrange(m: *Monitor, want_animation: bool, from_view: bool) callconv(.c) void;
extern fn wl_list_swap(l1: *WlList, l2: *WlList) callconv(.c) void;

extern "c" fn calloc(nmemb: usize, size: usize) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;

var locked_horizontal_node: ?*Node = null;
var locked_vertical_node: ?*Node = null;

fn nodeOpt(p: [*c]Node) ?*Node {
    return if (p == null) null else @ptrCast(p);
}

fn clientOpt(p: [*c]Client) ?*Client {
    return if (p == null) null else @ptrCast(p);
}

fn monitorOpt(p: [*c]Monitor) ?*Monitor {
    return if (p == null) null else @ptrCast(p);
}

fn nodePtr(n: ?*Node) [*c]Node {
    return @ptrCast(n);
}

fn clientPtr(cl: ?*Client) [*c]Client {
    return @ptrCast(cl);
}

fn monitorPtr(m: ?*Monitor) [*c]Monitor {
    return @ptrCast(m);
}

fn allocNode() ?*Node {
    return @ptrCast(@alignCast(calloc(1, @sizeOf(Node)) orelse return null));
}

fn allocNodeArray(n: usize) ?[*]*Node {
    return @ptrCast(@alignCast(calloc(n, @sizeOf(*Node)) orelse return null));
}

fn allocClientArray(n: usize) ?[*]*Client {
    return @ptrCast(@alignCast(calloc(n, @sizeOf(*Client)) orelse return null));
}

fn allocStackArray(n: usize) ?[*][*c]Node {
    return @ptrCast(@alignCast(calloc(n, @sizeOf([*c]Node)) orelse return null));
}

fn allocFloats(n: usize) ?[*]f32 {
    return @ptrCast(@alignCast(calloc(n, @sizeOf(f32)) orelse return null));
}

fn freeAny(ptr: anytype) void {
    if (ptr) |p| free(@ptrCast(p));
}

inline fn truncI32(x: f32) i32 {
    return @intFromFloat(x);
}

inline fn clampRatio(x: f32) f32 {
    return @min(@max(x, 0.001), 0.999);
}

fn ISTILED(cl: ?*const Client) bool {
    const x = cl orelse return false;
    return x.isfloating == 0 and x.isminimized == 0 and x.iskilling == 0 and
        x.ismaximizescreen == 0 and x.isfullscreen == 0 and x.isunglobal == 0;
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

fn containerOf(comptime T: type, comptime link_field: []const u8, link: [*c]WlList) *T {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(T, link_field));
}

fn listHead(head: *WlList) [*c]WlList {
    return @ptrCast(head);
}

// ---------------------------------------------------------------------------
// tree helpers
// ---------------------------------------------------------------------------

export fn count_block_items(node_in: ?*Node, split_h: bool) callconv(.c) c_int {
    const node = node_in orelse return 0;
    if (!node.is_split or node.split_h != split_h)
        return 1;
    return count_block_items(nodeOpt(node.first), split_h) +
        count_block_items(nodeOpt(node.second), split_h);
}

export fn dwindle_find_leaf(node_in: ?*Node, cl: ?*Client) callconv(.c) ?*Node {
    const node = node_in orelse return null;
    if (!node.is_split) {
        if (node.client == clientPtr(cl))
            return node;
        return null;
    }
    return dwindle_find_leaf(nodeOpt(node.first), cl) orelse
        dwindle_find_leaf(nodeOpt(node.second), cl);
}

export fn dwindle_first_leaf(node_in: ?*Node) callconv(.c) ?*Node {
    var node = node_in orelse return null;
    while (node.is_split) {
        node = nodeOpt(node.first) orelse return null;
    }
    return node;
}

export fn dwindle_free_tree(node_in: ?*Node) callconv(.c) void {
    const node = node_in orelse return;
    dwindle_free_tree(nodeOpt(node.first));
    dwindle_free_tree(nodeOpt(node.second));
    free(@ptrCast(node));
}

export fn dwindle_new_leaf(cl: ?*Client) callconv(.c) ?*Node {
    const n = allocNode() orelse return null;
    n.client = clientPtr(cl);
    return n;
}

// ---------------------------------------------------------------------------
// removal with manual-split proportional rollback
// ---------------------------------------------------------------------------

export fn dwindle_remove(root: *[*c]Node, cl: ?*Client) callconv(.c) void {
    const leaf = dwindle_find_leaf(nodeOpt(root.*), cl) orelse return;
    const parent = nodeOpt(leaf.parent);

    if (locked_horizontal_node == leaf or locked_horizontal_node == parent)
        locked_horizontal_node = null;
    if (locked_vertical_node == leaf or locked_vertical_node == parent)
        locked_vertical_node = null;

    if (parent == null) {
        free(@ptrCast(leaf));
        root.* = null;
        return;
    }
    const par = parent.?;

    if (c.config.dwindle_manual_split != 0) {
        const split_h = par.split_h;

        var path_len: c_int = 1;
        var cnt = nodeOpt(par.parent);
        while (cnt != null and cnt.?.split_h == split_h) {
            path_len += 1;
            cnt = nodeOpt(cnt.?.parent);
        }

        const plen: usize = @intCast(path_len);
        const path = allocNodeArray(plen);
        const p = allocFloats(plen);
        if (path != null and p != null) {
            var n: usize = 0;
            path.?[n] = par;
            n += 1;
            var curr = nodeOpt(par.parent);
            while (curr != null and curr.?.split_h == split_h) {
                path.?[n] = curr.?;
                n += 1;
                curr = nodeOpt(curr.?.parent);
            }

            p.?[n - 1] = 1.0;
            var i: usize = n - 1;
            while (i > 0) : (i -= 1) {
                const S = path.?[i];
                const child = path.?[i - 1];
                if (S.first == nodePtr(child))
                    p.?[i - 1] = p.?[i] * S.ratio
                else
                    p.?[i - 1] = p.?[i] * (1.0 - S.ratio);
            }

            var p_del = p.?[0] *
                (if (par.first == nodePtr(leaf)) par.ratio else (1.0 - par.ratio));
            if (p_del > 0.999)
                p_del = 0.999;

            i = n - 1;
            while (i > 0) : (i -= 1) {
                const S = path.?[i];
                const child = path.?[i - 1];
                const p_S = p.?[i];
                const p_first = p_S * S.ratio;

                var denom = p_S - p_del;
                if (denom < 0.0001)
                    denom = 0.0001;

                if (S.first == nodePtr(child))
                    S.ratio = (p_first - p_del) / denom
                else
                    S.ratio = p_first / denom;

                if (S.ratio < 0.001)
                    S.ratio = 0.001;
                if (S.ratio > 0.999)
                    S.ratio = 0.999;
            }
        }
        freeAny(path);
        freeAny(p);
    }

    const sibling = nodeOpt(if (par.first == nodePtr(leaf)) par.second else par.first) orelse return;
    const grandparent = nodeOpt(par.parent);

    sibling.parent = nodePtr(grandparent);

    if (!sibling.is_split or
        (c.config.dwindle_preserve_split == 0 and c.config.dwindle_smart_split == 0))
    {
        sibling.container_w = 0;
        sibling.container_h = 0;
    }

    if (grandparent == null) {
        root.* = nodePtr(sibling);
    } else {
        if (grandparent.?.first == nodePtr(par))
            grandparent.?.first = nodePtr(sibling)
        else
            grandparent.?.second = nodePtr(sibling);
    }

    free(@ptrCast(leaf));
    free(@ptrCast(par));
}

// ---------------------------------------------------------------------------
// assignment
// ---------------------------------------------------------------------------

export fn dwindle_assign(
    node_in: ?*Node,
    ax: i32,
    ay: i32,
    aw: i32,
    ah: i32,
    gap_h: i32,
    gap_v: i32,
    ctx: ?*const LayoutContext,
) callconv(.c) void {
    const node = node_in orelse return;

    if (!node.is_split) {
        const cl = clientOpt(node.client) orelse return;
        if (cl.isfullscreen == 0 and cl.ismaximizescreen == 0) {
            const box = Box{
                .x = ax,
                .y = ay,
                .width = @max(1, aw),
                .height = @max(1, ah),
            };
            if (ctx != null and ctx.?.probe != null) {
                if (node.client == ctx.?.probe and ctx.?.out != null)
                    ctx.?.out.* = box;
            } else {
                client_tile_resize(cl, box, 0, null);
            }
        }
        return;
    }

    if (!node.split_locked and node.container_w == 0 and node.container_h == 0)
        node.split_h = aw >= ah;

    node.container_x = ax;
    node.container_y = ay;
    node.container_w = aw;
    node.container_h = ah;

    if (node.split_h) {
        const w1 = @max(1, truncI32(@as(f32, @floatFromInt(aw)) * node.ratio) - @divTrunc(gap_h, 2));
        dwindle_assign(nodeOpt(node.first), ax, ay, w1, ah, gap_h, gap_v, ctx);
        dwindle_assign(nodeOpt(node.second), ax + w1 + gap_h, ay, aw - w1 - gap_h, ah, gap_h, gap_v, ctx);
    } else {
        const h1 = @max(1, truncI32(@as(f32, @floatFromInt(ah)) * node.ratio) - @divTrunc(gap_v, 2));
        dwindle_assign(nodeOpt(node.first), ax, ay, aw, h1, gap_h, gap_v, ctx);
        dwindle_assign(nodeOpt(node.second), ax, ay + h1 + gap_v, aw, ah - h1 - gap_v, gap_h, gap_v, ctx);
    }
}

// ---------------------------------------------------------------------------
// block path / ratios
// ---------------------------------------------------------------------------

export fn get_block_path_and_ratios(
    target_in: ?*Node,
    split_h: bool,
    path_out: *?[*]*Node,
    p_out: *?[*]f32,
) callconv(.c) c_int {
    const target = target_in orelse return 0;

    var depth: usize = 1;
    var curr = nodeOpt(target.parent);
    while (curr != null and curr.?.split_h == split_h) {
        depth += 1;
        curr = nodeOpt(curr.?.parent);
    }

    path_out.* = allocNodeArray(depth);
    p_out.* = allocFloats(depth);
    if (path_out.* == null or p_out.* == null)
        return 0;

    const path = path_out.*.?;
    const p = p_out.*.?;

    var path_len: usize = 0;
    path[path_len] = target;
    path_len += 1;
    curr = nodeOpt(target.parent);
    while (curr != null and curr.?.split_h == split_h) {
        path[path_len] = curr.?;
        path_len += 1;
        curr = nodeOpt(curr.?.parent);
    }

    p[path_len - 1] = 1.0;
    var i: usize = path_len - 1;
    while (i > 0) : (i -= 1) {
        const S = path[i];
        const child = path[i - 1];
        if (S.first == nodePtr(child))
            p[i - 1] = p[i] * S.ratio
        else
            p[i - 1] = p[i] * (1.0 - S.ratio);
    }
    return @intCast(path_len);
}

// ---------------------------------------------------------------------------
// insertion
// ---------------------------------------------------------------------------

export fn dwindle_insert(
    root: *[*c]Node,
    new_c: ?*Client,
    focused: ?*Client,
    ratio: f32,
    as_first: bool,
    split_h: bool,
    lock: bool,
) callconv(.c) void {
    const new_leaf = dwindle_new_leaf(new_c) orelse return;

    if (root.* == null) {
        new_leaf.custom_leaf_split_h = true;
        root.* = nodePtr(new_leaf);
        return;
    }

    var target = if (focused != null) dwindle_find_leaf(nodeOpt(root.*), focused) else null;
    if (target == null)
        target = dwindle_first_leaf(nodeOpt(root.*));
    const tgt = target orelse {
        free(@ptrCast(new_leaf));
        return;
    };

    if (c.config.dwindle_manual_split != 0) {
        var path: ?[*]*Node = null;
        var p: ?[*]f32 = null;
        const path_len = get_block_path_and_ratios(tgt, split_h, &path, &p);

        if (path != null and p != null) {
            var n_old: c_int = 1;
            if (path_len > 1)
                n_old = count_block_items(path.?[@intCast(path_len - 1)], split_h);
            const N: f32 = @floatFromInt(n_old + 1);

            var i: usize = @intCast(path_len - 1);
            while (i > 0) : (i -= 1) {
                const S = path.?[i];
                const child = path.?[i - 1];
                const p_S = p.?[i];
                const p_first = p_S * S.ratio;

                if (S.first == nodePtr(child)) {
                    const p_first_new = p_first * (N - 1.0) / N + 1.0 / N;
                    const p_S_new = p_S * (N - 1.0) / N + 1.0 / N;
                    S.ratio = p_first_new / p_S_new;
                } else {
                    const p_first_new = p_first * (N - 1.0) / N;
                    const p_S_new = p_S * (N - 1.0) / N + 1.0 / N;
                    S.ratio = p_first_new / p_S_new;
                }
                if (S.ratio < 0.001)
                    S.ratio = 0.001;
                if (S.ratio > 0.999)
                    S.ratio = 0.999;
            }
        }
        freeAny(path);
        freeAny(p);
    }

    const split = allocNode() orelse {
        free(@ptrCast(new_leaf));
        return;
    };
    split.is_split = true;
    split.split_h = split_h;
    split.split_locked = lock;
    split.custom_leaf_split_h = tgt.custom_leaf_split_h;
    new_leaf.custom_leaf_split_h = tgt.custom_leaf_split_h;

    if (as_first) {
        split.first = nodePtr(new_leaf);
        split.second = nodePtr(tgt);
    } else {
        split.first = nodePtr(tgt);
        split.second = nodePtr(new_leaf);
    }

    split.ratio = ratio;
    split.parent = tgt.parent;
    tgt.parent = nodePtr(split);
    new_leaf.parent = nodePtr(split);

    if (split.parent == null) {
        root.* = nodePtr(split);
    } else {
        const sp = nodeOpt(split.parent).?;
        if (sp.first == nodePtr(tgt))
            sp.first = nodePtr(split)
        else
            sp.second = nodePtr(split);
    }
}

// ---------------------------------------------------------------------------
// move / swap
// ---------------------------------------------------------------------------

export fn dwindle_move_next_to(
    cl_in: ?*Client,
    target_in: ?*Client,
    ratio: f32,
    dir: i32,
) callconv(.c) void {
    const cl = cl_in orelse return;
    if (cl.mon == null)
        return;
    if (target_in != null and cl == target_in.?)
        return;

    if (target_in == null) {
        _ = client_jump_to_monitor(cl, monitor_from_direction(@intCast(dir)), dir);
        return;
    }
    const t = target_in.?;

    const crossed = cl.mon != t.mon;
    const c_cx = cl.geom.x + @divTrunc(cl.geom.width, 2);
    const c_cy = cl.geom.y + @divTrunc(cl.geom.height, 2);
    const tgeom = t.geom;

    if (!client_jump_to_monitor(cl, monitorOpt(t.mon), dir) and cl.mon != t.mon)
        return;

    const m = monitorOpt(cl.mon) orelse return;
    const tag = get_mon_curtag(m);
    const root: *[*c]Node = &m.pertag.*.dwindle_root[tag];
    const c_leaf = dwindle_find_leaf(nodeOpt(root.*), cl) orelse return;
    const target_leaf = dwindle_find_leaf(nodeOpt(root.*), t) orelse return;

    if (!crossed and c_leaf.parent != null and c_leaf.parent == target_leaf.parent) {
        const split = nodeOpt(c_leaf.parent).?;
        const first = split.first;
        split.first = split.second;
        split.second = first;
        arrange(m, false, false);
        return;
    }

    var area = tgeom;
    const parent = nodeOpt(c_leaf.parent);
    if (!crossed and parent != null) {
        const par = parent.?;
        const sibling = nodeOpt(if (par.first == nodePtr(c_leaf)) par.second else par.first);
        if (par.container_w > 0 and par.container_h > 0 and
            dwindle_find_leaf(sibling, t) != null)
        {
            area = .{
                .x = par.container_x,
                .y = par.container_y,
                .width = par.container_w,
                .height = par.container_h,
            };
        }
    }

    const split_h = area.width >= area.height;
    const as_first = if (split_h)
        c_cx < (tgeom.x + @divTrunc(tgeom.width, 2))
    else
        c_cy < (tgeom.y + @divTrunc(tgeom.height, 2));

    dwindle_remove(root, cl);
    dwindle_insert(root, cl, t, ratio, as_first, split_h, true);
    arrange(m, false, false);
}

export fn dwindle_swap_clients(c1_in: ?*Client, c2_in: ?*Client) callconv(.c) void {
    const c1 = c1_in orelse return;
    const c2 = c2_in orelse return;
    if (c1.mon == null or c2.mon == null or c1 == c2)
        return;

    const m1 = monitorOpt(c1.mon).?;
    const m2 = monitorOpt(c2.mon).?;

    const c1_root: *[*c]Node = &m1.pertag.*.dwindle_root[get_mon_curtag(m1)];
    const c1node = dwindle_find_leaf(nodeOpt(c1_root.*), c1);
    const c2_root: *[*c]Node = &m2.pertag.*.dwindle_root[get_mon_curtag(m2)];
    const c2node = dwindle_find_leaf(nodeOpt(c2_root.*), c2);

    client_swap_layout_properties(c1, c2);

    if (c1node) |node|
        node.client = clientPtr(c2);
    if (c2node) |node|
        node.client = clientPtr(c1);

    if (m1 != m2)
        client_swap_monitors_and_tags(c1, c2);

    wl_list_swap(&c1.link, &c2.link);
    finish_exchange_arrange_and_focus(c1, c2, m1, m2);
}

// ---------------------------------------------------------------------------
// drag resize
// ---------------------------------------------------------------------------

export fn dwindle_resize_client(m: *Monitor, cl: *Client) callconv(.c) void {
    const tag = get_mon_curtag(m);
    const leaf = dwindle_find_leaf(nodeOpt(m.pertag.*.dwindle_root[tag]), cl) orelse return;

    if (!c.server.start_drag_window) {
        c.server.start_drag_window = true;
        locked_horizontal_node = null;
        locked_vertical_node = null;
        c.server.drag_begin_cursor_x = @intFromFloat(c.server.cursor.*.x);
        c.server.drag_begin_cursor_y = @intFromFloat(c.server.cursor.*.y);
        var node_opt = nodeOpt(leaf.parent);
        while (node_opt != null) {
            const node = node_opt.?;
            if (node.split_h and locked_horizontal_node == null) {
                locked_horizontal_node = node;
                node.drag_init_ratio = node.ratio;
            }
            if (!node.split_h and locked_vertical_node == null) {
                locked_vertical_node = node;
                node.drag_init_ratio = node.ratio;
            }
            if (locked_horizontal_node != null and locked_vertical_node != null)
                break;
            node_opt = nodeOpt(node.parent);
        }
    }

    if (locked_horizontal_node == null and locked_vertical_node == null)
        return;

    if (locked_horizontal_node) |node| {
        const cw: f32 = @floatFromInt(@max(1, node.container_w));
        var ox: f32 = @floatCast(c.server.cursor.*.x - @as(f64, @floatFromInt(c.server.drag_begin_cursor_x)));
        if (c.config.dwindle_smart_resize != 0) {
            const split_x = @as(f32, @floatFromInt(node.container_x)) + cw * node.drag_init_ratio;
            if (@as(f32, @floatFromInt(c.server.drag_begin_cursor_x)) >= split_x)
                ox = -ox;
        }
        node.ratio = node.drag_init_ratio + ox / cw;
        node.ratio = @min(@max(node.ratio, 0.05), 0.95);
    }

    if (locked_vertical_node) |node| {
        const ch: f32 = @floatFromInt(@max(1, node.container_h));
        var oy: f32 = @floatCast(c.server.cursor.*.y - @as(f64, @floatFromInt(c.server.drag_begin_cursor_y)));
        if (c.config.dwindle_smart_resize != 0) {
            const split_y = @as(f32, @floatFromInt(node.container_y)) + ch * node.drag_init_ratio;
            if (@as(f32, @floatFromInt(c.server.drag_begin_cursor_y)) >= split_y)
                oy = -oy;
        }
        node.ratio = node.drag_init_ratio + oy / ch;
        node.ratio = @min(@max(node.ratio, 0.05), 0.95);
    }

    const n: i32 = @intCast(m.visible_tiling_clients);
    var gap_ih: i32 = if (c.server.enable_gaps != 0) m.gappih else 0;
    var gap_iv: i32 = if (c.server.enable_gaps != 0) m.gappiv else 0;
    var gap_oh: i32 = if (c.server.enable_gaps != 0) m.gappoh else 0;
    var gap_ov: i32 = if (c.server.enable_gaps != 0) m.gappov else 0;
    if (c.config.smartgaps != 0 and n == 1) {
        gap_ih = 0;
        gap_iv = 0;
        gap_oh = 0;
        gap_ov = 0;
    }

    dwindle_assign(nodeOpt(m.pertag.*.dwindle_root[tag]), m.w.x + gap_oh, m.w.y + gap_ov, m.w.width - 2 * gap_oh, m.w.height - 2 * gap_ov, gap_ih, gap_iv, null);
}

export fn dwindle_resize_client_step(m: *Monitor, cl: *Client, dx: i32, dy: i32) callconv(.c) void {
    const tag = get_mon_curtag(m);
    const leaf = dwindle_find_leaf(nodeOpt(m.pertag.*.dwindle_root[tag]), cl) orelse return;

    var h_node: ?*Node = null;
    var v_node: ?*Node = null;
    var node_opt = nodeOpt(leaf.parent);
    while (node_opt != null) {
        const node = node_opt.?;
        if (node.split_h and h_node == null)
            h_node = node;
        if (!node.split_h and v_node == null)
            v_node = node;
        if (h_node != null and v_node != null)
            break;
        node_opt = nodeOpt(node.parent);
    }

    if (h_node == null and v_node == null)
        return;

    if (h_node) |node| {
        if (dx != 0) {
            const cw: f32 = @floatFromInt(@max(1, node.container_w));
            const delta: f32 = @as(f32, @floatFromInt(dx)) / cw;
            node.ratio = @min(@max(node.ratio + delta, 0.05), 0.95);
        }
    }

    if (v_node) |node| {
        if (dy != 0) {
            const ch: f32 = @floatFromInt(@max(1, node.container_h));
            const delta: f32 = @as(f32, @floatFromInt(dy)) / ch;
            node.ratio = @min(@max(node.ratio + delta, 0.05), 0.95);
        }
    }

    const n_clients: i32 = @intCast(m.visible_tiling_clients);
    var gap_ih: i32 = if (c.server.enable_gaps != 0) m.gappih else 0;
    var gap_iv: i32 = if (c.server.enable_gaps != 0) m.gappiv else 0;
    var gap_oh: i32 = if (c.server.enable_gaps != 0) m.gappoh else 0;
    var gap_ov: i32 = if (c.server.enable_gaps != 0) m.gappov else 0;
    if (c.config.smartgaps != 0 and n_clients == 1) {
        gap_ih = 0;
        gap_iv = 0;
        gap_oh = 0;
        gap_ov = 0;
    }

    dwindle_assign(nodeOpt(m.pertag.*.dwindle_root[tag]), m.w.x + gap_oh, m.w.y + gap_ov, m.w.width - 2 * gap_oh, m.w.height - 2 * gap_ov, gap_ih, gap_iv, null);
}

export fn dwindle_remove_client(cl_in: ?*Client) callconv(.c) void {
    const cl = cl_in orelse return;
    var pos = c.server.monitors.next;
    const head = listHead(&c.server.monitors);
    while (pos != head) : (pos = pos.*.next) {
        const m = containerOf(Monitor, "link", pos);
        for (&m.pertag.*.dwindle_root) |*slot|
            dwindle_remove(slot, cl);
    }
}

// ---------------------------------------------------------------------------
// config-driven insertion
// ---------------------------------------------------------------------------

export fn dwindle_insert_with_config(
    root: *[*c]Node,
    new_c: ?*Client,
    focused: ?*Client,
    ratio_in: f32,
) callconv(.c) void {
    const new_cl = new_c orelse return;
    const foc = focused orelse return;
    _ = new_cl;

    var as_first = false;
    var split_h = false;
    var lock = false;
    var ratio = ratio_in;

    const fg = &foc.geom;
    const fcx: f64 = @as(f64, @floatFromInt(fg.x)) + @as(f64, @floatFromInt(fg.width)) * 0.5;
    const fcy: f64 = @as(f64, @floatFromInt(fg.y)) + @as(f64, @floatFromInt(fg.height)) * 0.5;

    if (c.config.dwindle_smart_split != 0) {
        const nx = (c.server.cursor.*.x - fcx) / (@as(f64, @floatFromInt(fg.width)) * 0.5);
        const ny = (c.server.cursor.*.y - fcy) / (@as(f64, @floatFromInt(fg.height)) * 0.5);

        if (@abs(ny) > @abs(nx)) {
            split_h = false;
            as_first = ny < 0;
        } else {
            split_h = true;
            as_first = nx < 0;
        }
        lock = true;
    } else {
        const likely_h = fg.width >= fg.height;
        split_h = likely_h;

        if (likely_h) {
            if (c.config.dwindle_hsplit == 0)
                as_first = c.server.cursor.*.x < fcx
            else
                as_first = c.config.dwindle_hsplit == 2;
        } else {
            if (c.config.dwindle_vsplit == 0)
                as_first = c.server.cursor.*.y < fcy
            else
                as_first = c.config.dwindle_vsplit == 2;
        }
    }

    var target = dwindle_find_leaf(nodeOpt(root.*), foc);
    if (target == null and root.* != null)
        target = dwindle_first_leaf(nodeOpt(root.*));

    if (c.config.dwindle_manual_split != 0 and target != null) {
        const tgt = target.?;
        split_h = tgt.custom_leaf_split_h;
        lock = true;
        as_first = false;

        var path: ?[*]*Node = null;
        var p: ?[*]f32 = null;
        const path_len = get_block_path_and_ratios(tgt, split_h, &path, &p);

        if (path != null and p != null) {
            var n_old: c_int = 1;
            if (path_len > 1)
                n_old = count_block_items(path.?[@intCast(path_len - 1)], split_h);
            const N: f32 = @floatFromInt(n_old + 1);

            const p_target_old = p.?[0];
            const p_split_new = p_target_old * (N - 1.0) / N + 1.0 / N;

            if (as_first)
                ratio = (1.0 / N) / p_split_new
            else
                ratio = (p_target_old * (N - 1.0) / N) / p_split_new;

            if (ratio < 0.001)
                ratio = 0.001;
            if (ratio > 0.999)
                ratio = 0.999;
        }
        freeAny(path);
        freeAny(p);
    }

    dwindle_insert(root, new_c, focused, ratio, as_first, split_h, lock);
}

// ---------------------------------------------------------------------------
// layout core
// ---------------------------------------------------------------------------

fn dwindleCore(m: *Monitor, ctx: ?*const LayoutContext) void {
    const n: i32 = @intCast(m.visible_tiling_clients);
    if (n == 0)
        return;

    const tag = get_mon_curtag(m);
    const root: *[*c]Node = &m.pertag.*.dwindle_root[tag];
    const ratio = c.config.dwindle_split_ratio;

    var total_clients: i32 = 0;
    var pos = c.server.clients.next;
    const head = listHead(&c.server.clients);
    while (pos != head) : (pos = pos.*.next)
        total_clients += 1;

    const cap: usize = if (total_clients != 0) @intCast(total_clients) else 1;
    const vis = allocClientArray(cap);
    const leaves = allocNodeArray(cap);
    const stack = allocStackArray(@as(usize, @intCast(total_clients)) * 2 + 2);
    if (vis == null or leaves == null or stack == null) {
        freeAny(vis);
        freeAny(leaves);
        freeAny(stack);
        return;
    }
    defer freeAny(vis);
    defer freeAny(leaves);
    defer freeAny(stack);

    var count: i32 = 0;
    pos = c.server.clients.next;
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (VISIBLEON(cl, m) and ISTILED(cl)) {
            vis.?[@intCast(count)] = cl;
            count += 1;
        }
    }

    var lc: i32 = 0;
    var sp: usize = 0;
    if (root.* != null) {
        stack.?[sp] = root.*;
        sp += 1;
    }
    while (sp > 0) {
        sp -= 1;
        const nd = nodeOpt(stack.?[sp]) orelse continue;
        if (!nd.is_split) {
            leaves.?[@intCast(lc)] = nd;
            lc += 1;
        } else {
            if (nd.second != null) {
                stack.?[sp] = nd.second;
                sp += 1;
            }
            if (nd.first != null) {
                stack.?[sp] = nd.first;
                sp += 1;
            }
        }
    }

    var i: i32 = 0;
    while (i < lc) : (i += 1) {
        const leaf = leaves.?[@intCast(i)];
        var found = false;
        var j: i32 = 0;
        while (j < count) : (j += 1) {
            if (vis.?[@intCast(j)] == clientOpt(leaf.client)) {
                found = true;
                break;
            }
        }
        if (!found) {
            const leaf_cl = clientOpt(leaf.client);
            if (VISIBLEON(leaf_cl, m) and
                ((leaf_cl.?.isfullscreen != 0) or (leaf_cl.?.ismaximizescreen != 0)))
                continue;
            dwindle_remove(root, leaf_cl);
        }
    }

    var focused = clientOpt(client_focus_top(m));
    if (focused != null and dwindle_find_leaf(nodeOpt(root.*), focused) == null)
        focused = clientOpt(m.sel);

    if (focused == null and count > 0)
        focused = vis.?[0];

    i = 0;
    while (i < count) : (i += 1) {
        const cl = vis.?[@intCast(i)];
        if (dwindle_find_leaf(nodeOpt(root.*), cl) == null)
            dwindle_insert_with_config(root, cl, focused, ratio);
    }

    var gap_ih: i32 = if (c.server.enable_gaps != 0) m.gappih else 0;
    var gap_iv: i32 = if (c.server.enable_gaps != 0) m.gappiv else 0;
    var gap_oh: i32 = if (c.server.enable_gaps != 0) m.gappoh else 0;
    var gap_ov: i32 = if (c.server.enable_gaps != 0) m.gappov else 0;
    if (c.config.smartgaps != 0 and n == 1) {
        gap_ih = 0;
        gap_iv = 0;
        gap_oh = 0;
        gap_ov = 0;
    }

    dwindle_assign(nodeOpt(root.*), m.w.x + gap_oh, m.w.y + gap_ov, m.w.width - 2 * gap_oh, m.w.height - 2 * gap_ov, gap_ih, gap_iv, ctx);
}

export fn cleanup_monitor_dwindle(m: *Monitor) callconv(.c) void {
    for (&m.pertag.*.dwindle_root) |*slot|
        dwindle_free_tree(nodeOpt(slot.*));
}

export fn dwindle(m: *Monitor) callconv(.c) void {
    dwindleCore(m, null);
}

export fn dwindle_predict(m: *Monitor, cl: *Client, out: *Box) callconv(.c) bool {
    const tag = get_mon_curtag(m);
    const root: *[*c]Node = &m.pertag.*.dwindle_root[tag];

    var geo = std.mem.zeroes(Box);
    var ctx = LayoutContext{ .probe = cl, .out = &geo };
    dwindleCore(m, &ctx);
    out.* = geo;

    if (dwindle_find_leaf(nodeOpt(root.*), cl) != null)
        dwindle_remove(root, cl);

    return out.width > 0 and out.height > 0;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/layout_dwindle_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_cursor: c.struct_wlr_cursor;
extern var stub_focus_top: ?*Client;
extern var stub_direction_monitor: ?*Monitor;
extern var stub_jump_result: bool;
extern var stub_arrange_calls: c_int;
extern var stub_tile_calls: c_int;
extern var stub_tile_boxes: [256]Box;
extern var stub_tile_clients: [256]?*Client;
extern var stub_jump_calls: c_int;
extern var stub_swap_props_calls: c_int;
extern var stub_swap_monitors_calls: c_int;
extern var stub_finish_calls: c_int;

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
    c.server.cursor = @ptrCast(&stub_cursor);
    c.server.start_drag_window = false;
    stub_cursor.x = 0;
    stub_cursor.y = 0;
    stub_focus_top = null;
    stub_direction_monitor = null;
    stub_jump_result = true;
    stub_arrange_calls = 0;
    stub_tile_calls = 0;
    stub_jump_calls = 0;
    stub_swap_props_calls = 0;
    stub_swap_monitors_calls = 0;
    stub_finish_calls = 0;
}

fn baseMonitor(m: *Monitor, p: *c.Pertag) void {
    m.* = std.mem.zeroes(Monitor);
    p.* = std.mem.zeroes(c.Pertag);
    m.pertag = p;
    m.w = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
    m.tagset[0] = 0xffff;
    m.seltags = 0;
}

fn addClient(cl: *Client, m: *Monitor, tags: u32) void {
    cl.* = std.mem.zeroes(Client);
    cl.mon = @ptrCast(m);
    cl.tags = tags;
    listInsert(&c.server.clients, &cl.link);
}

fn rootOf(m: *Monitor) *[*c]Node {
    return &m.pertag.*.dwindle_root[0];
}

fn expectBox(idx: usize, x: i32, y: i32, w: i32, h: i32) !void {
    const b = stub_tile_boxes[idx];
    try testing.expectEqual(x, b.x);
    try testing.expectEqual(y, b.y);
    try testing.expectEqual(w, b.width);
    try testing.expectEqual(h, b.height);
}

fn expectApprox(expected: f32, actual: f32) !void {
    try testing.expectApproxEqAbs(expected, actual, 0.0001);
}

test "dwindle tree: count, find and first-leaf" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);

    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);

    var root: [*c]Node = null;
    dwindle_insert(&root, &a, null, 0.5, false, true, false);
    dwindle_insert(&root, &b, &a, 0.5, false, true, false);

    const r = nodeOpt(root).?;
    try testing.expect(r.is_split);
    try testing.expectEqual(@as(c_int, 2), count_block_items(r, true));
    try testing.expectEqual(@as(c_int, 1), count_block_items(r, false));
    try testing.expect(dwindle_find_leaf(r, &a) != null);
    try testing.expect(dwindle_find_leaf(r, &b) != null);
    try testing.expect(dwindle_first_leaf(r).?.client == &a);

    dwindle_free_tree(r);
}

test "dwindle_assign: horizontal, vertical, gaps and probe" {
    resetWorld();
    var a: Client = std.mem.zeroes(Client);
    var b: Client = std.mem.zeroes(Client);
    var leaf_a: Node = std.mem.zeroes(Node);
    var leaf_b: Node = std.mem.zeroes(Node);
    leaf_a.client = @ptrCast(&a);
    leaf_b.client = @ptrCast(&b);

    var split: Node = std.mem.zeroes(Node);
    split.is_split = true;
    split.split_h = true;
    split.ratio = 0.5;
    split.first = @ptrCast(&leaf_a);
    split.second = @ptrCast(&leaf_b);

    dwindle_assign(&split, 0, 0, 1000, 800, 10, 10, null);
    try testing.expectEqual(@as(c_int, 2), stub_tile_calls);
    try expectBox(0, 0, 0, 495, 800);
    try expectBox(1, 505, 0, 495, 800);

    stub_tile_calls = 0;
    split.split_h = false;
    dwindle_assign(&split, 0, 0, 1000, 800, 10, 10, null);
    try expectBox(0, 0, 0, 1000, 395);
    try expectBox(1, 0, 405, 1000, 395);

    // probe mode fills out and does not resize
    stub_tile_calls = 0;
    var out: Box = std.mem.zeroes(Box);
    var ctx = LayoutContext{ .probe = &a, .out = &out };
    dwindle_assign(&split, 0, 0, 1000, 800, 0, 0, &ctx);
    try testing.expectEqual(@as(c_int, 0), stub_tile_calls);
    try testing.expectEqual(@as(i32, 1000), out.width);

    // non-split node with a fullscreen client is skipped
    leaf_a.client.*.isfullscreen = 1;
    stub_tile_calls = 0;
    dwindle_assign(&leaf_a, 0, 0, 100, 100, 0, 0, null);
    try testing.expectEqual(@as(c_int, 0), stub_tile_calls);

    // auto split direction when the container is fresh
    leaf_a.client.*.isfullscreen = 0;
    split.split_h = false;
    split.split_locked = false;
    split.container_w = 0;
    split.container_h = 0;
    dwindle_assign(&split, 0, 0, 1920, 1080, 0, 0, null);
    try testing.expect(split.split_h);
    dwindle_assign(&split, 0, 0, 800, 1200, 0, 0, null);
    try testing.expect(split.split_h);
}

test "dwindle_remove: sibling promotion and root collapse" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);

    var root: [*c]Node = null;
    dwindle_insert(&root, &a, null, 0.5, false, true, false);
    dwindle_insert(&root, &b, &a, 0.5, true, true, false);

    var r = nodeOpt(root).?;
    try testing.expect(r.is_split);
    try testing.expect(r.first.*.client == &b);
    try testing.expect(r.second.*.client == &a);

    dwindle_remove(&root, &b);
    r = nodeOpt(root).?;
    try testing.expect(!r.is_split);
    try testing.expect(r.client == &a);

    dwindle_remove(&root, &a);
    try testing.expect(root == null);
}

test "dwindle_remove: manual-split rollback redistributes the freed ratio" {
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

    var root: [*c]Node = null;
    dwindle_insert(&root, &a, null, 0.5, false, true, false);
    dwindle_insert(&root, &b, &a, 0.5, false, true, false);
    dwindle_insert(&root, &c_cl, &b, 0.5, false, true, false);

    const r = nodeOpt(root).?;
    try expectApprox(0.5, r.ratio);

    c.config.dwindle_manual_split = 1;
    dwindle_remove(&root, &c_cl);

    try testing.expect(r.is_split);
    try expectApprox(2.0 / 3.0, r.ratio);
    try testing.expect(r.first.*.client == &a);
    try testing.expect(r.second.*.client == &b);
    try testing.expectEqual(@as(i32, 0), r.second.*.container_w);
}

test "dwindle_insert_with_config: smart split picks direction and order" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);
    a.geom = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };

    c.config.dwindle_smart_split = 1;
    stub_cursor.x = 900;
    stub_cursor.y = 400;

    var root: [*c]Node = null;
    dwindle_insert(&root, &a, null, 0.5, false, true, false);
    dwindle_insert_with_config(&root, &b, &a, 0.5);

    var r = nodeOpt(root).?;
    try testing.expect(r.split_h);
    try testing.expect(r.split_locked);
    try testing.expect(r.first.*.client == &a);
    try testing.expect(r.second.*.client == &b);

    resetWorld();
    baseMonitor(&m, &p);
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);
    a.geom = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
    c.config.dwindle_smart_split = 1;
    stub_cursor.x = 500;
    stub_cursor.y = 100;

    root = null;
    dwindle_insert(&root, &a, null, 0.5, false, true, false);
    dwindle_insert_with_config(&root, &b, &a, 0.5);

    r = nodeOpt(root).?;
    try testing.expect(!r.split_h);
    try testing.expect(r.first.*.client == &b);
    try testing.expect(r.second.*.client == &a);
}

test "dwindle core: visible clients are inserted and laid out" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    m.visible_tiling_clients = 2;
    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);

    c.config.dwindle_split_ratio = 0.5;
    c.config.dwindle_hsplit = 2;
    stub_focus_top = &a;

    dwindle(&m);

    try testing.expectEqual(@as(c_int, 2), stub_tile_calls);
    try expectBox(0, 0, 0, 500, 800);
    try expectBox(1, 500, 0, 500, 800);
    try testing.expect(stub_tile_clients[0] == &a);
    try testing.expect(stub_tile_clients[1] == &b);
}

test "dwindle_predict: inserts a probe client, answers and removes it" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    m.visible_tiling_clients = 2;
    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);

    c.config.dwindle_hsplit = 2;
    c.config.dwindle_split_ratio = 0.5;
    stub_focus_top = &a;

    dwindle_insert(rootOf(&m), &a, null, 0.5, false, true, false);

    var out: Box = std.mem.zeroes(Box);
    try testing.expect(dwindle_predict(&m, &b, &out));
    try testing.expectEqual(@as(i32, 0), out.x);
    try testing.expectEqual(@as(i32, 0), out.y);
    try testing.expectEqual(@as(i32, 500), out.width);
    try testing.expectEqual(@as(i32, 800), out.height);

    try testing.expect(dwindle_find_leaf(nodeOpt(rootOf(&m).*), &a) != null);
    try testing.expect(dwindle_find_leaf(nodeOpt(rootOf(&m).*), &b) == null);
}

test "dwindle_resize_client_step and drag resize update split ratios" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);

    dwindle_insert(rootOf(&m), &a, null, 0.5, false, true, false);
    dwindle_insert(rootOf(&m), &b, &a, 0.5, false, true, false);
    const r = nodeOpt(rootOf(&m).*).?;
    dwindle_assign(r, 0, 0, 1000, 800, 0, 0, null);

    stub_tile_calls = 0;
    dwindle_resize_client_step(&m, &a, 100, 0);
    try expectApprox(0.6, r.ratio);
    try expectBox(0, 0, 0, 600, 800);
    try expectBox(1, 600, 0, 400, 800);

    // drag path: first call captures the ratio and redirects to the split
    resetWorld();
    baseMonitor(&m, &p);
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);
    rootOf(&m).* = null;
    dwindle_insert(rootOf(&m), &a, null, 0.5, false, true, false);
    dwindle_insert(rootOf(&m), &b, &a, 0.5, false, true, false);
    const r2 = nodeOpt(rootOf(&m).*).?;
    dwindle_assign(r2, 0, 0, 1000, 800, 0, 0, null);

    c.server.start_drag_window = false;
    stub_cursor.x = 500;
    stub_cursor.y = 400;
    dwindle_resize_client(&m, &a);
    stub_cursor.x = 600;
    stub_tile_calls = 0;
    dwindle_resize_client(&m, &a);
    try expectApprox(0.6, r2.ratio);
    try expectBox(0, 0, 0, 600, 800);
}

test "dwindle_move_next_to swaps siblings and null targets jump" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);

    dwindle_insert(rootOf(&m), &a, null, 0.5, false, true, false);
    dwindle_insert(rootOf(&m), &b, &a, 0.5, false, true, false);
    const r = nodeOpt(rootOf(&m).*).?;
    dwindle_assign(r, 0, 0, 1000, 800, 0, 0, null);

    dwindle_move_next_to(&a, &b, 0.5, c.RIGHT);
    try testing.expect(r.first.*.client == &b);
    try testing.expect(r.second.*.client == &a);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);

    dwindle_move_next_to(&a, null, 0.5, c.LEFT);
    try testing.expectEqual(@as(c_int, 2), stub_jump_calls);
}

test "dwindle_swap_clients swaps tree leaves and calls the swap helpers" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);

    var root: [*c]Node = null;
    dwindle_insert(&root, &a, null, 0.5, false, true, false);
    dwindle_insert(&root, &b, &a, 0.5, false, true, false);

    dwindle_swap_clients(&a, &b);
    try testing.expectEqual(@as(c_int, 1), stub_swap_props_calls);
    try testing.expectEqual(@as(c_int, 1), stub_finish_calls);
    try testing.expectEqual(@as(c_int, 0), stub_swap_monitors_calls);
    try testing.expect(dwindle_find_leaf(nodeOpt(root).?, &a) != null);
    try testing.expect(dwindle_find_leaf(nodeOpt(root).?, &b) != null);
}

test "dwindle_remove_client cleans every monitor root" {
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

    dwindle_insert(rootOf(&m1), &a, null, 0.5, false, true, false);
    dwindle_insert(rootOf(&m2), &a, null, 0.5, false, true, false);

    dwindle_remove_client(&a);
    try testing.expect(rootOf(&m1).* == null);
    try testing.expect(rootOf(&m2).* == null);
}

test "get_block_path_and_ratios walks the same-direction block" {
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

    var root: [*c]Node = null;
    dwindle_insert(&root, &a, null, 0.5, false, true, false);
    dwindle_insert(&root, &b, &a, 0.5, false, true, false);
    dwindle_insert(&root, &c_cl, &b, 0.5, false, true, false);

    const c_leaf = dwindle_find_leaf(nodeOpt(root).?, &c_cl).?;
    var path: ?[*]*Node = null;
    var ratios: ?[*]f32 = null;
    const len = get_block_path_and_ratios(c_leaf, true, &path, &ratios);

    try testing.expectEqual(@as(c_int, 3), len);
    try testing.expect(path.?[0].client == &c_cl);
    try testing.expect(path.?[1].is_split);
    try expectApprox(0.25, ratios.?[0]);
    try expectApprox(0.5, ratios.?[1]);
    try expectApprox(1.0, ratios.?[2]);

    freeAny(path);
    freeAny(ratios);
}
