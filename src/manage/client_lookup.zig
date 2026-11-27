//! Port of the client lookup / direction / stack helpers in
//! src/manage/client.c (Phase 5, client slice 3, slice 60).

const std = @import("std");
const c = @import("cc");

const Client = c.Client;
const Monitor = c.Monitor;
const Box = c.struct_wlr_box;
const DwindleNode = c.DwindleNode;
const Arg = c.Arg;

extern fn is_descendant_process(p: c.pid_t, child: c.pid_t) callconv(.c) c_int;
extern fn client_get_appid(cl: [*c]Client) callconv(.c) [*c]const u8;
extern fn client_get_title(cl: [*c]Client) callconv(.c) [*c]const u8;
extern fn client_surface(cl: [*c]Client) callconv(.c) [*c]c.struct_wlr_surface;
extern fn client_is_unmanaged(cl: [*c]Client) callconv(.c) i32;
extern fn check_hit_no_border(cl: [*c]Client) callconv(.c) bool;
extern fn is_scroller_layout(m: [*c]Monitor) callconv(.c) bool;
extern fn scroll_get_stack_head_client(cl: [*c]Client) callconv(.c) [*c]Client;
extern fn dwindle_find_leaf(node: [*c]DwindleNode, cl: [*c]Client) callconv(.c) [*c]DwindleNode;
extern fn regex_match(pattern_mb: [*c]const u8, str_mb: [*c]const u8) callconv(.c) i32;
extern fn get_client_tag_idx(cl: ?*const Client) callconv(.c) u32;

const broken = "broken";

fn clientOpt(p: [*c]Client) ?*Client {
    return if (p == null) null else @ptrCast(p);
}

fn monitorOpt(p: [*c]Monitor) ?*Monitor {
    return if (p == null) null else @ptrCast(p);
}

fn containerOf(comptime T: type, comptime field: []const u8, link: anytype) *T {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(T, field));
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

fn cSpanZ(p: [*c]const u8) ?[]const u8 {
    if (p == null)
        return null;
    return std.mem.span(@as([*:0]const u8, @ptrCast(p)));
}

export fn client_find_terminal(w: *Client) callconv(.c) ?*Client {
    if (w.pid == 0 or w.isterm != 0 or w.no_swallow != 0)
        return null;
    var pos = c.server.focus_stack.next;
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.focus_stack);
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "flink", pos);
        if (cl.isterm != 0 and cl.swallowdby == null and cl.pid != 0 and
            is_descendant_process(cl.pid, w.pid) != 0)
            return cl;
    }
    return null;
}

export fn get_client_by_id_or_title(arg_id_in: [*c]const u8, arg_title_in: [*c]const u8) callconv(.c) ?*Client {
    var pos = c.server.clients.next;
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (c.config.scratchpad_cross_monitor == 0 and
            cl.mon != c.server.selected_monitor)
            continue;

        var appid: [*c]const u8 = undefined;
        var title: [*c]const u8 = undefined;
        if (cl.swallowing != null) {
            appid = client_get_appid(cl.swallowing);
            title = client_get_title(cl.swallowing);
        } else {
            appid = client_get_appid(cl);
            title = client_get_title(cl);
        }
        if (appid == null)
            appid = @ptrCast(broken.ptr);
        if (title == null)
            title = @ptrCast(broken.ptr);

        var arg_id = arg_id_in;
        var arg_title = arg_title_in;
        if (arg_id != null and std.mem.startsWith(u8, std.mem.span(@as([*:0]const u8, @ptrCast(arg_id))), "none"))
            arg_id = null;
        if (arg_title != null and std.mem.startsWith(u8, std.mem.span(@as([*:0]const u8, @ptrCast(arg_title))), "none"))
            arg_title = null;

        const title_match = arg_title != null and regex_match(arg_title, title) != 0;
        const id_match = arg_id != null and regex_match(arg_id, appid) != 0;
        if ((title_match and arg_id == null) or
            (id_match and arg_title == null) or
            (id_match and title_match))
            return cl;
    }
    return null;
}

export fn client_center_geometry(cl: ?*Client, tm: [*c]Monitor, geom: Box, offsetx: i32, offsety: i32) callconv(.c) Box {
    const m = monitorOpt(tm) orelse monitorOpt(c.server.selected_monitor) orelse return geom;
    var tempbox = std.mem.zeroes(Box);
    const cbw: u32 = if (cl != null and check_hit_no_border(cl.?)) cl.?.bw else 0;

    if ((cl == null or cl.?.no_force_center == 0)) {
        tempbox.x = m.w.x + @divTrunc(m.w.width - geom.width, 2);
        tempbox.y = m.w.y + @divTrunc(m.w.height - geom.height, 2);
    } else {
        tempbox.x = geom.x;
        tempbox.y = geom.y;
    }
    tempbox.width = geom.width;
    tempbox.height = geom.height;

    if (offsetx != 0) {
        const len = @divTrunc(m.w.width - tempbox.width - 2 * m.gappoh, 2);
        const offset: i32 = @intFromFloat(@as(f64, @floatFromInt(len)) * (@as(f64, @floatFromInt(offsetx)) / 100.0));
        tempbox.x += offset;
        if (tempbox.x < m.m.x)
            tempbox.x = m.m.x - @as(i32, @intCast(cbw));
        if (tempbox.x + tempbox.width > m.m.x + m.m.width)
            tempbox.x = m.m.x + m.m.width - tempbox.width + @as(i32, @intCast(cbw));
    }
    if (offsety != 0) {
        const len = @divTrunc(m.w.height - tempbox.height - 2 * m.gappov, 2);
        const offset: i32 = @intFromFloat(@as(f64, @floatFromInt(len)) * (@as(f64, @floatFromInt(offsety)) / 100.0));
        tempbox.y += offset;
        if (tempbox.y < m.m.y)
            tempbox.y = m.m.y - @as(i32, @intCast(cbw));
        if (tempbox.y + tempbox.height > m.m.y + m.m.height)
            tempbox.y = m.m.y + m.m.height - tempbox.height + @as(i32, @intCast(cbw));
    }
    return tempbox;
}

export fn is_window_rule_matches(r: *const c.ConfigWinRule, appid: [*c]const u8, title: [*c]const u8) callconv(.c) bool {
    const title_match = r.title != null and regex_match(r.title, title) != 0;
    const id_match = r.id != null and regex_match(r.id, appid) != 0;
    return (title_match and r.id == null) or
        (id_match and r.title == null) or
        (id_match and title_match);
}

export fn center_tiled_select(m: *Monitor) callconv(.c) ?*Client {
    var target: [*c]Client = null;
    var mini_distance: i64 = -1;
    var pos = c.server.clients.next;
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        const surface = client_surface(cl);
        if (VISIBLEON(cl, m) and ISSCROLLTILED(cl) and surface != null and surface.*.mapped and
            cl.isfloating == 0 and client_is_unmanaged(cl) == 0)
        {
            const dirx = cl.geom.x + @divTrunc(cl.geom.width, 2) - (m.w.x + @divTrunc(m.w.width, 2));
            const diry = cl.geom.y + @divTrunc(cl.geom.height, 2) - (m.w.y + @divTrunc(m.w.height, 2));
            const distance: i64 = @as(i64, dirx) * dirx + @as(i64, diry) * diry;
            if (distance < mini_distance or mini_distance == -1) {
                mini_distance = distance;
                target = cl;
            }
        }
    }
    return clientOpt(target);
}

export fn find_client_by_direction(tc: *Client, arg: *const Arg, findfloating: bool) callconv(.c) ?*Client {
    var distance: i64 = std.math.maxInt(i64);
    var same_monitor_distance: i64 = std.math.maxInt(i64);
    var best_center_dist: i64 = std.math.maxInt(i64);
    var best_same_monitor_center_dist: i64 = std.math.maxInt(i64);
    var temp_focus: [*c]Client = null;
    var temp_same_monitor: [*c]Client = null;

    const tc_l = tc.geom.x;
    const tc_r = tc.geom.x + tc.geom.width;
    const tc_t = tc.geom.y;
    const tc_b = tc.geom.y + tc.geom.height;
    const tc_cx = tc_l + @divTrunc(tc.geom.width, 2);
    const tc_cy = tc_t + @divTrunc(tc.geom.height, 2);

    var step: i32 = 0;
    while (step < 2) : (step += 1) {
        if (step == 1 and temp_focus != null)
            break;

        var pos = c.server.clients.next;
        const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
        while (pos != head) : (pos = pos.*.next) {
            const cl = containerOf(Client, "link", pos);
            if (cl.mon == null or cl == tc)
                continue;
            if (!findfloating and cl.isfloating != 0)
                continue;
            const cm = cl.mon;
            if (!VISIBLEON(cl, cm))
                continue;
            if (cl.isunglobal != 0)
                continue;
            if (c.config.focus_cross_monitor == 0 and cm != tc.mon)
                continue;
            if ((cl.tags & cm.*.tagset[cm.*.seltags]) == 0 and cl.isglobal == 0)
                continue;

            const c_l = cl.geom.x;
            const c_r = cl.geom.x + cl.geom.width;
            const c_t = cl.geom.y;
            const c_b = cl.geom.y + cl.geom.height;
            const c_cx = c_l + @divTrunc(cl.geom.width, 2);
            const c_cy = c_t + @divTrunc(cl.geom.height, 2);

            var main_dist: i64 = 0;
            var orth_dist: i64 = 0;
            var match_dir = false;
            switch (arg.i) {
                c.LEFT => {
                    if (c_cx < tc_cx or (c_cx == tc_cx and c_l < tc_l)) {
                        match_dir = true;
                        main_dist = tc_l - c_r;
                        orth_dist = if (c_b < tc_t) tc_t - c_b else if (c_t > tc_b) c_t - tc_b else 0;
                    }
                },
                c.RIGHT => {
                    if (c_cx > tc_cx or (c_cx == tc_cx and c_l > tc_l)) {
                        match_dir = true;
                        main_dist = c_l - tc_r;
                        orth_dist = if (c_b < tc_t) tc_t - c_b else if (c_t > tc_b) c_t - tc_b else 0;
                    }
                },
                c.UP => {
                    if (c_cy < tc_cy or (c_cy == tc_cy and c_t < tc_t)) {
                        match_dir = true;
                        main_dist = tc_t - c_b;
                        orth_dist = if (c_r < tc_l) tc_l - c_r else if (c_l > tc_r) c_l - tc_r else 0;
                    }
                },
                c.DOWN => {
                    if (c_cy > tc_cy or (c_cy == tc_cy and c_t > tc_t)) {
                        match_dir = true;
                        main_dist = c_t - tc_b;
                        orth_dist = if (c_r < tc_l) tc_l - c_r else if (c_l > tc_r) c_l - tc_r else 0;
                    }
                },
                else => continue,
            }
            if (!match_dir)
                continue;

            const orth_overlap = if (arg.i == c.LEFT or arg.i == c.RIGHT)
                (c_b >= tc_t and c_t <= tc_b)
            else
                (c_r >= tc_l and c_l <= tc_r);
            if (c.config.focusdir_only_zone_overlap != 0 and !orth_overlap)
                continue;

            if (step == 0) {
                if (tc.mon == null or cm != tc.mon)
                    continue;
                if (tc.mon.*.isoverview == 0 and !client_is_in_same_stack(tc, cl, null))
                    continue;
            }

            var penalty: i64 = 0;
            if (main_dist < 0) {
                penalty = 10000000000;
                main_dist = -main_dist;
            }
            const tmp_distance = penalty + main_dist * main_dist + orth_dist * orth_dist;
            var center_dist: i64 = if (arg.i == c.UP or arg.i == c.DOWN)
                @as(i64, c_cx) - tc_cx
            else
                @as(i64, c_cy) - tc_cy;
            if (center_dist < 0)
                center_dist = -center_dist;

            if (tmp_distance < distance or
                (tmp_distance == distance and center_dist < best_center_dist))
            {
                distance = tmp_distance;
                best_center_dist = center_dist;
                temp_focus = cl;
            }

            if (cm == tc.mon and
                (tmp_distance < same_monitor_distance or
                    (tmp_distance == same_monitor_distance and center_dist < best_same_monitor_center_dist)))
            {
                same_monitor_distance = tmp_distance;
                best_same_monitor_center_dist = center_dist;
                temp_same_monitor = cl;
            }
        }
    }

    if (temp_same_monitor != null)
        return @ptrCast(temp_same_monitor);
    return clientOpt(temp_focus);
}

export fn direction_select(arg: *const Arg) callconv(.c) ?*Client {
    const selected = monitorOpt(c.server.selected_monitor) orelse return null;
    const tc = if (arg.tc != null) @as(*Client, @ptrCast(arg.tc)) else if (selected.sel != null) @as(*Client, @ptrCast(selected.sel)) else null;
    const target = tc orelse return null;

    if ((target.isfullscreen != 0 or target.ismaximizescreen != 0) and
        (!is_scroller_layout(selected) or target.isfloating != 0))
        return null;
    return find_client_by_direction(target, arg, true);
}

export fn client_focus_top(m: [*c]Monitor) callconv(.c) ?*Client {
    const monitor = monitorOpt(m) orelse return null;
    var pos = c.server.focus_stack.next;
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.focus_stack);
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "flink", pos);
        if (cl.iskilling != 0 or cl.isunglobal != 0)
            continue;
        const surface = client_surface(cl);
        if (VISIBLEON(cl, monitor) and surface != null and surface.*.mapped)
            return cl;
    }
    return null;
}

export fn get_next_stack_client(cl: ?*Client, reverse: bool) callconv(.c) ?*Client {
    const client = cl orelse return null;
    if (client.mon == null)
        return null;

    const self_link: [*c]c.struct_wl_list = @ptrCast(&client.link);
    const sentinel: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    var pos = if (reverse) client.link.prev else client.link.next;
    while (pos != self_link) : (pos = if (reverse) pos.*.prev else pos.*.next) {
        if (pos == sentinel)
            continue;
        const next = containerOf(Client, "link", pos);
        if (next.isunglobal != 0)
            continue;
        if (next != client and next.mon != null and VISIBLEON(next, client.mon))
            return next;
    }
    return null;
}

export fn get_border_color(cl: *Client) callconv(.c) [*c]f32 {
    const selected = monitorOpt(c.server.selected_monitor);
    if (cl.mon != c.server.selected_monitor)
        return @ptrCast(&c.config.bordercolor);
    if (cl.isurgent != 0)
        return @ptrCast(&c.config.urgentcolor);
    if (cl.is_in_scratchpad != 0 and selected != null and cl == selected.?.sel)
        return @ptrCast(&c.config.scratchpadcolor);
    if (cl.isglobal != 0 and selected != null and cl == selected.?.sel)
        return @ptrCast(&c.config.globalcolor);
    if (cl.isoverlay != 0 and selected != null and cl == selected.?.sel)
        return @ptrCast(&c.config.overlaycolor);
    if (cl.ismaximizescreen != 0 and selected != null and cl == selected.?.sel)
        return @ptrCast(&c.config.maximizescreencolor);
    if (selected != null and cl == selected.?.sel)
        return @ptrCast(&c.config.focuscolor);
    return @ptrCast(&c.config.bordercolor);
}

export fn get_dim_color(cl: *Client) callconv(.c) [*c]f32 {
    if (c.server.selected_monitor != null and c.server.selected_monitor.*.sel == cl)
        return @ptrCast(&c.config.dim_focused_color);
    return @ptrCast(&c.config.dim_unfocused_color);
}

export fn is_single_bit_set(x: u32) callconv(.c) i32 {
    return if (x != 0 and (x & (x - 1)) == 0) 1 else 0;
}

export fn client_only_in_one_tag(cl: *Client) callconv(.c) bool {
    if ((cl.tags & (@as(u32, 1) << 31)) != 0)
        return true;
    const masked = cl.tags & c.server.tagmask;
    return is_single_bit_set(masked) != 0;
}

export fn client_is_in_same_stack(sc: *Client, tc: *Client, fc: [*c]Client) callconv(.c) bool {
    if (sc.mon == null)
        return false;
    const tag = get_client_tag_idx(sc);
    const layout = sc.mon.*.pertag.*.ltidxs[tag];
    if (layout == null)
        return false;
    const id = layout.*.id;

    if (id != c.SCROLLER and id != c.VERTICAL_SCROLLER and
        tc.mon != c.server.selected_monitor and
        (tc.isfullscreen != 0 or tc.ismaximizescreen != 0))
        return true;

    if (id == c.MONOCLE)
        return !tc.is_tab_hidden;

    if (id == c.SCROLLER or id == c.VERTICAL_SCROLLER) {
        const source_head = scroll_get_stack_head_client(sc);
        const target_head = scroll_get_stack_head_client(tc);
        const fc_head = if (fc != null) scroll_get_stack_head_client(fc) else null;
        if (fc != null and fc_head == source_head)
            return false;
        return source_head == target_head;
    }

    if (id == c.TILE or id == c.VERTICAL_TILE or id == c.DECK or
        id == c.VERTICAL_DECK or id == c.RIGHT_TILE)
    {
        if (tc.tab_prev != null or tc.tab_next != null)
            return !tc.is_tab_hidden;
        if (tc.ismaster != sc.ismaster)
            return false;
        if (fc != null and (fc.*.ismaster != sc.ismaster))
            return false;
        return true;
    }

    if (id == c.CENTER_TILE) {
        if (tc.ismaster != sc.ismaster)
            return false;
        if (fc != null and (fc.*.ismaster != sc.ismaster))
            return false;
        return sc.geom.x == tc.geom.x;
    }

    return false;
}

fn dwindleNodeDepth(node_in: [*c]DwindleNode) i32 {
    var node = node_in;
    var depth: i32 = 0;
    while (node != null and node.*.parent != null) : (node = node.*.parent)
        depth += 1;
    return depth;
}

fn dwindleNodeLca(a_in: [*c]DwindleNode, b_in: [*c]DwindleNode) [*c]DwindleNode {
    var a = a_in;
    var b = b_in;
    if (a == null or b == null)
        return null;
    var da = dwindleNodeDepth(a);
    var db = dwindleNodeDepth(b);
    while (da > db) {
        a = a.*.parent;
        da -= 1;
    }
    while (db > da) {
        b = b.*.parent;
        db -= 1;
    }
    while (a != null and b != null and a != b) {
        a = a.*.parent;
        b = b.*.parent;
    }
    return a;
}

fn dwindleFocusBlockRoot(root: [*c]DwindleNode, sc: *Client, fc: *Client) [*c]DwindleNode {
    const sc_leaf = dwindle_find_leaf(root, sc);
    const fc_leaf = dwindle_find_leaf(root, fc);
    if (sc_leaf == null or fc_leaf == null or sc_leaf == fc_leaf or fc_leaf.*.parent == null)
        return null;
    const lca = dwindleNodeLca(sc_leaf, fc_leaf);
    if (lca != fc_leaf.*.parent)
        return null;
    const branch = if (lca.*.first == fc_leaf) lca.*.second else lca.*.first;
    if (branch == null or !branch.*.is_split)
        return null;
    return branch;
}

fn dwindleFocusBlockHasClient(node_in: [*c]DwindleNode, cl: *Client) bool {
    const node = node_in;
    if (node == null)
        return false;
    if (!node.*.is_split)
        return node.*.client == cl;
    return dwindleFocusBlockHasClient(node.*.first, cl) or
        dwindleFocusBlockHasClient(node.*.second, cl);
}

export fn get_focused_stack_client(sc_in: ?*Client, custom_focus_client: [*c]Client) callconv(.c) ?*Client {
    const sc = sc_in orelse return null;
    if (sc.isfloating != 0 or c.server.selected_monitor == null)
        return sc;
    const selected = monitorOpt(c.server.selected_monitor).?;
    const fc: *Client = if (custom_focus_client != null)
        @ptrCast(custom_focus_client)
    else if (selected.sel != null)
        selected.sel
    else
        return sc;

    if (fc.isfloating != 0 or sc.isfloating != 0)
        return sc;

    var is_dwindle = false;
    var dwindle_block: [*c]DwindleNode = null;
    if (sc.mon != null and sc.mon.*.pertag != null) {
        const tag = get_client_tag_idx(sc);
        const layout = sc.mon.*.pertag.*.ltidxs[tag];
        if (layout != null and layout.*.id == c.DWINDLE) {
            is_dwindle = true;
            dwindle_block = dwindleFocusBlockRoot(sc.mon.*.pertag.*.dwindle_root[tag], sc, fc);
        }
    }

    var pos = c.server.focus_stack.next;
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.focus_stack);
    while (pos != head) : (pos = pos.*.next) {
        const tc = containerOf(Client, "flink", pos);
        if (tc.iskilling != 0 or tc.isunglobal != 0)
            continue;
        if (!VISIBLEON(tc, sc.mon))
            continue;
        if (tc == fc)
            continue;
        if (is_dwindle) {
            if (dwindle_block != null and dwindleFocusBlockHasClient(dwindle_block, tc))
                return tc;
            continue;
        }
        if (client_is_in_same_stack(sc, tc, fc))
            return tc;
    }
    return sc;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/client_lookup_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_descendant: i32;
extern var stub_hit_no_border: bool;
extern var stub_scroller: bool;
extern var stub_scroll_head: [*c]Client;
extern var stub_scroll_head_b: [*c]Client;
extern var stub_scroll_client_b: [*c]Client;
extern var stub_dwindle_sc: [*c]DwindleNode;
extern var stub_dwindle_fc: [*c]DwindleNode;
extern var stub_dwindle_sc_client: [*c]Client;
extern var stub_dwindle_fc_client: [*c]Client;
extern var stub_tag_idx: u32;

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

fn resetLookupWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    listInit(&c.server.clients);
    listInit(&c.server.focus_stack);
    listInit(&c.server.monitors);
    c.config.focus_cross_monitor = 1;
    c.config.focusdir_only_zone_overlap = 0;
    c.config.scratchpad_cross_monitor = 1;
    c.server.tagmask = 0xffffffff;
    stub_descendant = 0;
    stub_hit_no_border = false;
    stub_scroller = false;
    stub_scroll_head = null;
    stub_scroll_head_b = null;
    stub_scroll_client_b = null;
    stub_dwindle_sc = null;
    stub_dwindle_fc = null;
    stub_dwindle_sc_client = null;
    stub_dwindle_fc_client = null;
    stub_tag_idx = 0;
}

fn mkBox(x: i32, y: i32, w: i32, h: i32) Box {
    return .{ .x = x, .y = y, .width = w, .height = h };
}

fn baseMonitor(m: *Monitor, p: *c.Pertag, layout: ?*c.Layout) void {
    m.* = std.mem.zeroes(Monitor);
    p.* = std.mem.zeroes(c.Pertag);
    m.pertag = p;
    m.w = mkBox(0, 0, 1000, 800);
    m.m = m.w;
    m.tagset[0] = 1;
    m.seltags = 0;
    if (layout) |l| {
        p.ltidxs[0] = l;
    }
}

fn baseClient(cl: *Client, m: *Monitor, xdg: *c.struct_wlr_xdg_surface, toplevel: *c.struct_wlr_xdg_toplevel, surface: *c.struct_wlr_surface, geom: Box) void {
    cl.* = std.mem.zeroes(Client);
    xdg.* = std.mem.zeroes(c.struct_wlr_xdg_surface);
    toplevel.* = std.mem.zeroes(c.struct_wlr_xdg_toplevel);
    surface.* = std.mem.zeroes(c.struct_wlr_surface);
    cl.type = @intCast(c.XDGShell);
    cl.mon = m;
    cl.tags = 1;
    cl.geom = geom;
    cl.surface.xdg = xdg;
    xdg.surface = surface;
    xdg.unnamed_0.toplevel = toplevel;
    toplevel.base = xdg;
}

test "find terminal walks the focus stack" {
    resetLookupWorld();
    var w: Client = std.mem.zeroes(Client);
    w.pid = 5;
    try testing.expect(client_find_terminal(&w) == null);

    var term: Client = std.mem.zeroes(Client);
    term.pid = 3;
    term.isterm = 1;
    listInsert(&c.server.focus_stack, &term.flink);
    stub_descendant = 1;
    try testing.expect(client_find_terminal(&w) == &term);

    term.swallowdby = &w;
    try testing.expect(client_find_terminal(&w) == null);
    term.swallowdby = null;
    term.isterm = 0;
    try testing.expect(client_find_terminal(&w) == null);
    term.isterm = 1;
    w.no_swallow = 1;
    try testing.expect(client_find_terminal(&w) == null);
    w.no_swallow = 0;
    w.pid = 0;
    try testing.expect(client_find_terminal(&w) == null);
}

test "client lookup by id, title and swallow target" {
    resetLookupWorld();
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var m: Monitor = std.mem.zeroes(Monitor);
    baseMonitor(&m, &p, null);
    c.server.selected_monitor = &m;

    var x1: c.struct_wlr_xdg_surface = undefined;
    var t1: c.struct_wlr_xdg_toplevel = undefined;
    var s1: c.struct_wlr_surface = undefined;
    var c1: Client = undefined;
    baseClient(&c1, &m, &x1, &t1, &s1, mkBox(0, 0, 10, 10));
    t1.app_id = @ptrCast(@constCast("app1"));
    t1.title = @ptrCast(@constCast("title1"));
    var x2: c.struct_wlr_xdg_surface = undefined;
    var t2: c.struct_wlr_xdg_toplevel = undefined;
    var s2: c.struct_wlr_surface = undefined;
    var c2: Client = undefined;
    baseClient(&c2, &m, &x2, &t2, &s2, mkBox(0, 0, 10, 10));
    t2.app_id = @ptrCast(@constCast("app2"));
    t2.title = @ptrCast(@constCast("title2"));
    listInsert(&c.server.clients, &c1.link);
    listInsert(&c.server.clients, &c2.link);

    try testing.expect(get_client_by_id_or_title(@ptrCast(@constCast("app1")), null) == &c1);
    try testing.expect(get_client_by_id_or_title(null, @ptrCast(@constCast("title2"))) == &c2);
    try testing.expect(get_client_by_id_or_title(@ptrCast(@constCast("app1")), @ptrCast(@constCast("title1"))) == &c1);
    try testing.expect(get_client_by_id_or_title(@ptrCast(@constCast("none")), @ptrCast(@constCast("title2"))) == &c2);
    try testing.expect(get_client_by_id_or_title(@ptrCast(@constCast("nope")), null) == null);

    c.config.scratchpad_cross_monitor = 0;
    var other: Monitor = std.mem.zeroes(Monitor);
    c2.mon = &other;
    try testing.expect(get_client_by_id_or_title(@ptrCast(@constCast("app2")), null) == null);
    c2.mon = &other;

    c1.swallowing = &c2;
    try testing.expect(get_client_by_id_or_title(@ptrCast(@constCast("app2")), null) == &c1);
}

test "client center geometry respects offsets, borders and force flags" {
    resetLookupWorld();
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var m: Monitor = std.mem.zeroes(Monitor);
    baseMonitor(&m, &p, null);
    c.server.selected_monitor = &m;
    try testing.expect(!check_hit_no_border(null));

    var geom = mkBox(0, 0, 200, 100);
    var out = client_center_geometry(null, &m, geom, 0, 0);
    try testing.expectEqual(@as(i32, 400), out.x);
    try testing.expectEqual(@as(i32, 350), out.y);

    out = client_center_geometry(null, &m, geom, 100, 100);
    try testing.expectEqual(@as(i32, 800), out.x);
    try testing.expectEqual(@as(i32, 700), out.y);

    m.m.width = 900;
    out = client_center_geometry(null, &m, geom, 100, 0);
    try testing.expectEqual(@as(i32, 700), out.x);

    var cl: Client = std.mem.zeroes(Client);
    cl.bw = 5;
    stub_hit_no_border = true;
    out = client_center_geometry(&cl, &m, geom, -200, 0);
    try testing.expectEqual(@as(i32, -5), out.x);

    cl.no_force_center = 1;
    geom.x = 12;
    out = client_center_geometry(&cl, &m, geom, 0, 0);
    try testing.expectEqual(@as(i32, 12), out.x);

    c.server.selected_monitor = null;
    out = client_center_geometry(null, null, geom, 0, 0);
    try testing.expectEqual(@as(i32, 12), out.x);
}

test "window rule matching combines id and title" {
    resetLookupWorld();
    var r: c.ConfigWinRule = std.mem.zeroes(c.ConfigWinRule);
    try testing.expect(!is_window_rule_matches(&r, "app", "title"));
    r.id = @ptrCast(@constCast("app"));
    try testing.expect(is_window_rule_matches(&r, "app", "title"));
    try testing.expect(!is_window_rule_matches(&r, "other", "title"));
    r.title = @ptrCast(@constCast("title"));
    try testing.expect(is_window_rule_matches(&r, "app", "title"));
    try testing.expect(!is_window_rule_matches(&r, "app", "other"));
    r.id = null;
    try testing.expect(is_window_rule_matches(&r, "app", "title"));
}

test "center tiled select chooses the nearest visible tiled client" {
    resetLookupWorld();
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var m: Monitor = std.mem.zeroes(Monitor);
    baseMonitor(&m, &p, null);

    var x1: c.struct_wlr_xdg_surface = undefined;
    var t1: c.struct_wlr_xdg_toplevel = undefined;
    var s1: c.struct_wlr_surface = undefined;
    var c1: Client = undefined;
    baseClient(&c1, &m, &x1, &t1, &s1, mkBox(100, 100, 100, 100));
    s1.mapped = true;
    var x2: c.struct_wlr_xdg_surface = undefined;
    var t2: c.struct_wlr_xdg_toplevel = undefined;
    var s2: c.struct_wlr_surface = undefined;
    var c2: Client = undefined;
    baseClient(&c2, &m, &x2, &t2, &s2, mkBox(900, 900, 50, 50));
    s2.mapped = true;
    listInsert(&c.server.clients, &c1.link);
    listInsert(&c.server.clients, &c2.link);

    try testing.expect(center_tiled_select(&m) == &c1);
    c1.isminimized = 1;
    try testing.expect(center_tiled_select(&m) == &c2);
    c2.isfloating = 1;
    try testing.expect(center_tiled_select(&m) == null);
    c1.isminimized = 0;
    c2.isfloating = 0;
    s1.mapped = false;
    try testing.expect(center_tiled_select(&m) == &c2);
}

test "directional selection picks candidates per direction" {
    resetLookupWorld();
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var m: Monitor = std.mem.zeroes(Monitor);
    baseMonitor(&m, &p, null);
    m.isoverview = 1;

    var xt: c.struct_wlr_xdg_surface = undefined;
    var tt: c.struct_wlr_xdg_toplevel = undefined;
    var st: c.struct_wlr_surface = undefined;
    var tc: Client = undefined;
    baseClient(&tc, &m, &xt, &tt, &st, mkBox(100, 100, 100, 100));
    st.mapped = true;

    var xl: c.struct_wlr_xdg_surface = undefined;
    var tl: c.struct_wlr_xdg_toplevel = undefined;
    var sl: c.struct_wlr_surface = undefined;
    var left: Client = undefined;
    baseClient(&left, &m, &xl, &tl, &sl, mkBox(0, 100, 80, 80));
    sl.mapped = true;
    var xr: c.struct_wlr_xdg_surface = undefined;
    var tr: c.struct_wlr_xdg_toplevel = undefined;
    var sr: c.struct_wlr_surface = undefined;
    var right: Client = undefined;
    baseClient(&right, &m, &xr, &tr, &sr, mkBox(300, 100, 80, 80));
    sr.mapped = true;
    var xu: c.struct_wlr_xdg_surface = undefined;
    var tu: c.struct_wlr_xdg_toplevel = undefined;
    var su: c.struct_wlr_surface = undefined;
    var up: Client = undefined;
    baseClient(&up, &m, &xu, &tu, &su, mkBox(100, 0, 80, 80));
    su.mapped = true;
    var xd: c.struct_wlr_xdg_surface = undefined;
    var td: c.struct_wlr_xdg_toplevel = undefined;
    var sd: c.struct_wlr_surface = undefined;
    var down: Client = undefined;
    baseClient(&down, &m, &xd, &td, &sd, mkBox(100, 300, 80, 80));
    sd.mapped = true;
    listInsert(&c.server.clients, &left.link);
    listInsert(&c.server.clients, &right.link);
    listInsert(&c.server.clients, &up.link);
    listInsert(&c.server.clients, &down.link);

    var arg: Arg = std.mem.zeroes(Arg);
    arg.i = c.LEFT;
    try testing.expect(find_client_by_direction(&tc, &arg, true) == &left);
    arg.i = c.RIGHT;
    try testing.expect(find_client_by_direction(&tc, &arg, true) == &right);
    arg.i = c.UP;
    try testing.expect(find_client_by_direction(&tc, &arg, true) == &up);
    arg.i = c.DOWN;
    try testing.expect(find_client_by_direction(&tc, &arg, true) == &down);

    arg.i = c.LEFT;
    right.isfloating = 1;
    try testing.expect(find_client_by_direction(&tc, &arg, false) == &left);
    right.isfloating = 0;
    left.isunglobal = 1;
    try testing.expect(find_client_by_direction(&tc, &arg, true) != &left);
    left.isunglobal = 0;

    c.config.focusdir_only_zone_overlap = 1;
    up.geom = mkBox(600, 0, 80, 80);
    arg.i = c.UP;
    try testing.expect(find_client_by_direction(&tc, &arg, true) == null);
}

test "direction select rejects fullscreen clients outside scroller" {
    resetLookupWorld();
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var m: Monitor = std.mem.zeroes(Monitor);
    baseMonitor(&m, &p, null);
    c.server.selected_monitor = &m;
    var cl: Client = std.mem.zeroes(Client);
    cl.mon = &m;
    cl.isfullscreen = 1;
    m.sel = &cl;
    var arg: Arg = std.mem.zeroes(Arg);
    try testing.expect(direction_select(&arg) == null);
    cl.isfullscreen = 0;
    cl.ismaximizescreen = 1;
    try testing.expect(direction_select(&arg) == null);
    cl.ismaximizescreen = 0;
    cl.isfloating = 1;
    stub_scroller = true;
    try testing.expect(direction_select(&arg) == null);
}

test "focus top and next stack skip hidden, killed and unglobal clients" {
    resetLookupWorld();
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var m: Monitor = std.mem.zeroes(Monitor);
    baseMonitor(&m, &p, null);

    var x1: c.struct_wlr_xdg_surface = undefined;
    var t1: c.struct_wlr_xdg_toplevel = undefined;
    var s1: c.struct_wlr_surface = undefined;
    var c1: Client = undefined;
    baseClient(&c1, &m, &x1, &t1, &s1, mkBox(0, 0, 10, 10));
    s1.mapped = true;
    c1.iskilling = 1;
    var x2: c.struct_wlr_xdg_surface = undefined;
    var t2: c.struct_wlr_xdg_toplevel = undefined;
    var s2: c.struct_wlr_surface = undefined;
    var c2: Client = undefined;
    baseClient(&c2, &m, &x2, &t2, &s2, mkBox(0, 0, 10, 10));
    s2.mapped = true;
    c2.tags = 2;
    var x3: c.struct_wlr_xdg_surface = undefined;
    var t3: c.struct_wlr_xdg_toplevel = undefined;
    var s3: c.struct_wlr_surface = undefined;
    var c3: Client = undefined;
    baseClient(&c3, &m, &x3, &t3, &s3, mkBox(0, 0, 10, 10));
    s3.mapped = true;

    listInsert(&c.server.focus_stack, &c1.flink);
    listInsert(&c.server.focus_stack, &c2.flink);
    listInsert(&c.server.focus_stack, &c3.flink);
    try testing.expect(client_focus_top(&m) == &c3);
    listInsert(&c.server.clients, &c1.link);
    listInsert(&c.server.clients, &c2.link);
    listInsert(&c.server.clients, &c3.link);

    c2.tags = 1;
    try testing.expect(get_next_stack_client(&c2, false) == &c1);
    try testing.expect(get_next_stack_client(&c1, false) == &c3);
    try testing.expect(get_next_stack_client(&c1, true) == &c2);
    c3.isunglobal = 1;
    c2.tags = 1;
    try testing.expect(get_next_stack_client(&c2, false) == &c1);
}

test "border and dim colors follow focus and state" {
    resetLookupWorld();
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var m: Monitor = std.mem.zeroes(Monitor);
    baseMonitor(&m, &p, null);
    c.server.selected_monitor = &m;
    m.sel = null;
    var cl: Client = std.mem.zeroes(Client);
    cl.mon = &m;

    try testing.expectEqual(@intFromPtr(&c.config.bordercolor[0]), @intFromPtr(get_border_color(&cl)));
    m.sel = &cl;
    try testing.expectEqual(@intFromPtr(&c.config.focuscolor[0]), @intFromPtr(get_border_color(&cl)));
    try testing.expectEqual(@intFromPtr(&c.config.dim_focused_color[0]), @intFromPtr(get_dim_color(&cl)));
    cl.isurgent = 1;
    try testing.expectEqual(@intFromPtr(&c.config.urgentcolor[0]), @intFromPtr(get_border_color(&cl)));
    cl.isurgent = 0;
    cl.is_in_scratchpad = 1;
    try testing.expectEqual(@intFromPtr(&c.config.scratchpadcolor[0]), @intFromPtr(get_border_color(&cl)));
    cl.is_in_scratchpad = 0;
    cl.isoverlay = 1;
    try testing.expectEqual(@intFromPtr(&c.config.overlaycolor[0]), @intFromPtr(get_border_color(&cl)));
    cl.isoverlay = 0;
    cl.ismaximizescreen = 1;
    try testing.expectEqual(@intFromPtr(&c.config.maximizescreencolor[0]), @intFromPtr(get_border_color(&cl)));
    cl.ismaximizescreen = 0;
    m.sel = null;
    try testing.expectEqual(@intFromPtr(&c.config.dim_unfocused_color[0]), @intFromPtr(get_dim_color(&cl)));

    try testing.expectEqual(@as(i32, 0), is_single_bit_set(0));
    try testing.expectEqual(@as(i32, 1), is_single_bit_set(0b100));
    try testing.expectEqual(@as(i32, 0), is_single_bit_set(0b110));
    cl.tags = @as(u32, 1) << 31;
    try testing.expect(client_only_in_one_tag(&cl));
    cl.tags = 0b100;
    try testing.expect(client_only_in_one_tag(&cl));
    cl.tags = 0b110;
    try testing.expect(!client_only_in_one_tag(&cl));
}

test "same stack follows the current layout" {
    resetLookupWorld();
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var layout: c.Layout = std.mem.zeroes(c.Layout);
    var m: Monitor = std.mem.zeroes(Monitor);
    baseMonitor(&m, &p, &layout);
    c.server.selected_monitor = &m;
    var sc: Client = std.mem.zeroes(Client);
    var tc: Client = std.mem.zeroes(Client);
    sc.mon = &m;
    tc.mon = &m;

    layout.id = @intCast(c.MONOCLE);
    try testing.expect(client_is_in_same_stack(&sc, &tc, null));
    tc.is_tab_hidden = true;
    try testing.expect(!client_is_in_same_stack(&sc, &tc, null));

    layout.id = @intCast(c.TILE);
    tc.is_tab_hidden = false;
    sc.ismaster = true;
    tc.ismaster = true;
    try testing.expect(client_is_in_same_stack(&sc, &tc, null));
    tc.ismaster = false;
    try testing.expect(!client_is_in_same_stack(&sc, &tc, null));

    layout.id = @intCast(c.SCROLLER);
    stub_scroll_head = &sc;
    try testing.expect(client_is_in_same_stack(&sc, &tc, null));
    var other: Client = std.mem.zeroes(Client);
    stub_scroll_head_b = &other;
    stub_scroll_client_b = &tc;
    try testing.expect(!client_is_in_same_stack(&sc, &tc, null));
    stub_scroll_head = null;
    stub_scroll_head_b = null;
    stub_scroll_client_b = null;

    layout.id = @intCast(c.CENTER_TILE);
    sc.ismaster = true;
    tc.ismaster = true;
    sc.geom = mkBox(10, 0, 10, 10);
    tc.geom = mkBox(10, 20, 10, 10);
    try testing.expect(client_is_in_same_stack(&sc, &tc, null));
    tc.geom.x = 11;
    try testing.expect(!client_is_in_same_stack(&sc, &tc, null));
}

test "focused stack client uses focus order in the same stack" {
    resetLookupWorld();
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var layout: c.Layout = std.mem.zeroes(c.Layout);
    var m: Monitor = std.mem.zeroes(Monitor);
    baseMonitor(&m, &p, &layout);
    c.server.selected_monitor = &m;
    layout.id = @intCast(c.TILE);
    var sc: Client = std.mem.zeroes(Client);
    var tc: Client = std.mem.zeroes(Client);
    var fc: Client = std.mem.zeroes(Client);
    sc.mon = &m;
    tc.mon = &m;
    fc.mon = &m;
    sc.ismaster = true;
    tc.ismaster = true;
    fc.ismaster = true;
    sc.tags = 1;
    tc.tags = 1;
    m.sel = &fc;

    listInsert(&c.server.focus_stack, &tc.flink);
    try testing.expect(get_focused_stack_client(&sc, null) == &tc);
    tc.isunglobal = 1;
    try testing.expect(get_focused_stack_client(&sc, null) == &sc);
    tc.isunglobal = 0;
    sc.isfloating = 1;
    try testing.expect(get_focused_stack_client(&sc, &fc) == &sc);
}
