//! Port of src/manage/tab.c (Phase 5, manage slice 1, slice 48).
//! Tab chain membership, focus/visibility refresh, input penetration,
//! bar-node lifecycle and the side-by-side tab strip drawing.

const std = @import("std");
const c = @import("cc");

const Client = c.Client;
const Monitor = c.Monitor;
const Bar = c.AcwmBarDecoration;
const SceneNode = c.struct_wlr_scene_node;
const SceneTree = c.struct_wlr_scene_tree;

extern fn client_chain_head(cl: *Client, prev_off: usize) callconv(.c) ?*Client;
extern fn client_chain_unlink(cl: *Client, prev_off: usize, next_off: usize) callconv(.c) void;
extern fn client_update_visibility(cl: ?*Client) callconv(.c) void;
extern fn client_target_layer(cl: *Client) callconv(.c) u32;
extern fn client_focus(cl: ?*Client, lift: i32) callconv(.c) void;
extern fn client_wants_group_bar(cl: *Client) callconv(.c) bool;
extern fn client_get_title(cl: *Client) callconv(.c) [*:0]const u8;
extern fn arrange(m: *Monitor, want_animation: bool, from_view: bool) callconv(.c) void;
extern fn get_mon_curtag(m: *const Monitor) callconv(.c) u32;
extern fn acwm_scene_node_set_ignore_hit(node: *SceneNode, ignore: bool) callconv(.c) void;
extern fn acwm_bar_decoration_create(cdata: ?*anyopaque, node_type: u32, is_tab: bool, parent: [*c]SceneTree, data: c.DecorateDrawData, width: i32, height: i32) callconv(.c) ?*Bar;
extern fn acwm_bar_decoration_destroy(node: ?*Bar) callconv(.c) void;
extern fn acwm_bar_decoration_update(node: ?*Bar, text: [*c]const u8, scale: f32) callconv(.c) void;
extern fn acwm_bar_decoration_apply_config(node: ?*Bar, data: *const c.DecorateDrawData) callconv(.c) void;
extern fn acwm_bar_decoration_set_size(node: ?*Bar, width: i32, height: i32) callconv(.c) void;
extern fn acwm_bar_decoration_set_focus(node: ?*Bar, focused: bool) callconv(.c) void;

fn clientOpt(p: [*c]Client) ?*Client {
    return if (p == null) null else @ptrCast(p);
}

fn clientPtr(cl: ?*Client) [*c]Client {
    return @ptrCast(cl);
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

fn tabBarSetEnabled(cl: ?*Client, on: bool) void {
    const cli = cl orelse return;
    if (cli.tab_bar == null)
        return;
    c.wlr_scene_node_set_enabled(&cli.tab_bar.*.scene.*.node, on);
}

var tab_member_count: i32 = 0;

fn tabHead(cl: *Client) ?*Client {
    return client_chain_head(cl, @offsetOf(Client, "tab_prev"));
}

fn tabIsMember(cl: *const Client) bool {
    return cl.tab_prev != null or cl.tab_next != null;
}

fn tabLayoutIdSupported(id: u32) bool {
    if (id == c.MONOCLE)
        return c.config.monocle_tab_mode != 0;
    if (id == c.DECK or id == c.VERTICAL_DECK)
        return c.config.deck_tab_mode != 0;
    return false;
}

fn tabLayoutEnabled(m: *const Monitor) bool {
    if (m.pertag == null)
        return false;
    const layout = m.pertag.*.ltidxs[@intCast(get_mon_curtag(m))];
    return tabLayoutIdSupported(layout.*.id);
}

fn tabLayoutActive(m: *const Monitor) bool {
    return m.isoverview == 0 and tabLayoutEnabled(m);
}

export fn tab_layout_active(m: ?*const Monitor) callconv(.c) bool {
    const mon = m orelse return false;
    return tabLayoutActive(mon);
}

fn tabStateOk(cl: *const Client) bool {
    if (cl.mon == null or cl.iskilling != 0 or cl.isminimized != 0)
        return false;
    if (cl.isfloating != 0 or cl.isunglobal != 0 or cl.is_in_scratchpad != 0)
        return false;
    return true;
}

fn tabIsStackCandidate(m: *Monitor, target: *Client) bool {
    const id = m.pertag.*.ltidxs[@intCast(get_mon_curtag(m))].*.id;
    if (id == c.MONOCLE)
        return true;
    if (id != c.DECK and id != c.VERTICAL_DECK)
        return false;
    return !target.ismaster;
}

fn tabMemberKept(m: *Monitor, cur: u32, cl: *Client) bool {
    return tabLayoutEnabled(m) and (cl.tags & cur) != 0 and tabStateOk(cl) and
        tabIsStackCandidate(m, cl);
}

fn tabMemberInView(cl: *const Client, m: *const Monitor) bool {
    return VISIBLEON(cl, m);
}

fn tabMemberShownInView(cl: *const Client, m: *const Monitor) bool {
    return cl.mon == @as([*c]Monitor, @ptrCast(@constCast(m))) and
        cl.isfullscreen == 0 and cl.ismaximizescreen == 0 and
        m.isoverview == 0 and VISIBLEON(cl, m);
}

fn tabChainFocus(head: ?*Client) void {
    var sel: ?*Client = null;
    var focus: ?*Client = null;

    var it = head;
    while (it) |cl| : (it = clientOpt(cl.tab_next)) {
        if (cl.mon != null and cl == cl.mon.*.sel)
            sel = cl;
        if (focus == null and cl.is_tab_focus)
            focus = cl;
    }
    focus = sel orelse (focus orelse head);

    it = head;
    while (it) |cl| : (it = clientOpt(cl.tab_next))
        cl.is_tab_focus = (cl == focus);
}

fn tabLeave(cl: *Client) void {
    client_chain_unlink(cl, @offsetOf(Client, "tab_prev"), @offsetOf(Client, "tab_next"));
    cl.is_tab_focus = false;
    tabBarSetEnabled(cl, false);
    tab_member_count -= 1;
    client_update_visibility(cl);
}

fn tabRefreshBars(head: ?*Client) void {
    const hd = head orelse return;

    var shown: i32 = 0;
    var focus: *Client = hd;

    var it: ?*Client = head;
    while (it) |cl| : (it = clientOpt(cl.tab_next)) {
        if (cl.is_tab_focus)
            focus = cl;
        if (tabMemberShownInView(cl, hd.mon.?))
            shown += 1;
    }

    const stacked = shown >= 2;
    const strip = stacked and tabMemberShownInView(focus, hd.mon.?);
    const layer = client_target_layer(focus);

    it = head;
    while (it) |cl| : (it = clientOpt(cl.tab_next)) {
        if (cl.tab_bar != null and cl.tab_bar.*.scene.*.node.parent != c.server.layers[layer]) {
            c.wlr_scene_node_reparent(&cl.tab_bar.*.scene.*.node, c.server.layers[layer]);
        }

        const in_view = tabMemberInView(cl, hd.mon.?);
        const is_shown = tabMemberShownInView(cl, hd.mon.?);
        if (in_view)
            cl.is_tab_hidden = stacked and is_shown and !cl.is_tab_focus;
        tabBarSetEnabled(cl, strip and is_shown);
        client_update_visibility(cl);
    }
}

export fn tab_update_input_penetration(cl_in: ?*Client) callconv(.c) void {
    const cl = cl_in orelse return;
    const m = monitorOpt(cl.mon) orelse return;
    if (!tabIsMember(cl))
        return;

    const head = tabHead(cl);
    var focus: *Client = head orelse cl;
    var shown: i32 = 0;

    var it: ?*Client = head;
    while (it) |cur| : (it = clientOpt(cur.tab_next)) {
        if (cur.is_tab_focus)
            focus = cur;
        if (tabMemberShownInView(cur, m))
            shown += 1;
    }

    const strip = shown >= 2 and tabLayoutActive(m) and tabMemberShownInView(focus, m);
    const ignore_hit = !strip;

    it = head;
    while (it) |cur| : (it = clientOpt(cur.tab_next)) {
        if (cur.tab_bar == null)
            continue;
        acwm_scene_node_set_ignore_hit(&cur.tab_bar.*.scene.*.node, ignore_hit);
    }
}

export fn tab_sync_focus(cl_in: ?*Client) callconv(.c) void {
    const cl = cl_in orelse return;
    if (!tabIsMember(cl) or cl.is_tab_focus)
        return;

    const head = tabHead(cl);
    var it = head;
    while (it) |cur| : (it = clientOpt(cur.tab_next))
        cur.is_tab_focus = (cur == cl);

    tabRefreshBars(head);
}

export fn tab_detach_client(cl_in: ?*Client) callconv(.c) void {
    const cl = cl_in orelse return;
    if (!tabIsMember(cl))
        return;

    const head = tabHead(cl);
    const next = clientOpt(cl.tab_next);

    tabLeave(cl);

    const rest = if (head != null and head.? == cl) next else head;
    const rest_cl = rest orelse return;

    if (rest_cl.tab_next == null) {
        tabLeave(rest_cl);
        return;
    }

    tabChainFocus(rest);
    tabRefreshBars(rest);
}

export fn tab_replace_client(old_in: ?*Client, new_in: ?*Client) callconv(.c) void {
    const old = old_in orelse return;
    const new = new_in orelse return;
    if (!tabIsMember(old))
        return;

    const was_focus = old.is_tab_focus;
    const was_hidden = old.is_tab_hidden;

    if (tabIsMember(new)) {
        const old_head = tabHead(old);
        const new_head = tabHead(new);
        if (old_head != null and new_head != null and old_head.? == new_head.?) {
            tab_detach_client(old);
            if (was_focus)
                tab_sync_focus(new);
            return;
        }
        tabLeave(new);
    }

    new.tab_prev = old.tab_prev;
    new.tab_next = old.tab_next;
    if (old.tab_prev != null)
        old.tab_prev.*.tab_next = @ptrCast(new);
    if (old.tab_next != null)
        old.tab_next.*.tab_prev = @ptrCast(new);

    old.tab_prev = null;
    old.tab_next = null;
    old.is_tab_focus = false;
    old.is_tab_hidden = false;
    tabBarSetEnabled(old, false);

    new.is_tab_focus = was_focus;
    new.is_tab_hidden = was_hidden;
}

export fn tab_sync_monitor(m_in: ?*Monitor) callconv(.c) void {
    const m = m_in orelse return;
    if (m.wlr_output == null or m.wlr_output.*.enabled == false or m.iscleanuping)
        return;
    if (m.isoverview != 0)
        return;
    if (!tabLayoutEnabled(m) and tab_member_count == 0)
        return;

    const cur = m.tagset[m.seltags];
    const can_merge = tabLayoutEnabled(m);

    var pos = c.server.clients.next;
    const list_head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    while (pos != list_head) : (pos = pos.*.next) {
        const cl = @as(*Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(Client, "link")));
        if (!tabIsMember(cl) or cl.mon != @as([*c]Monitor, @ptrCast(m)))
            continue;
        if (tabMemberKept(m, cur, cl))
            continue;
        tab_detach_client(cl);
    }

    var head: ?*Client = null;
    var tail: ?*Client = null;

    pos = c.server.clients.next;
    while (pos != list_head) : (pos = pos.*.next) {
        const cl = @as(*Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(Client, "link")));
        if (cl.mon != @as([*c]Monitor, @ptrCast(m)) or (cl.tags & cur) == 0)
            continue;
        if (!tabIsMember(cl)) {
            if (cl.is_tab_hidden) {
                cl.is_tab_hidden = false;
                client_update_visibility(cl);
            }
            if (!can_merge)
                continue;
            if (!tabStateOk(cl) or !tabIsStackCandidate(m, cl))
                continue;
            tab_member_count += 1;
        }

        if (tabIsMember(cl))
            client_chain_unlink(cl, @offsetOf(Client, "tab_prev"), @offsetOf(Client, "tab_next"));

        cl.tab_prev = clientPtr(tail);
        cl.tab_next = null;
        if (tail) |t|
            t.tab_next = @ptrCast(cl)
        else
            head = cl;
        tail = cl;
    }

    const hd = head orelse return;
    if (hd.tab_next == null) {
        tab_member_count -= 1;
        return;
    }

    tabChainFocus(head);
    tabRefreshBars(head);
}

export fn tab_focus_member(cl_in: ?*Client) callconv(.c) void {
    const cl = cl_in orelse return;
    const m = monitorOpt(cl.mon) orelse return;
    if (!tabIsMember(cl))
        return;
    client_focus(cl, 1);
    arrange(m, false, false);
}

export fn client_raise_tab(cl_in: ?*Client) callconv(.c) void {
    const cl = cl_in orelse return;
    if (cl.mon == null or !tabIsMember(cl))
        return;

    const head = tabHead(cl);
    var it = head;
    while (it) |cur| : (it = clientOpt(cur.tab_next)) {
        if (cur != cl and cur.scene.*.node.parent == cl.scene.*.node.parent)
            c.wlr_scene_node_place_above(&cl.scene.*.node, &cur.scene.*.node);
        if (cur.tab_bar != null)
            c.wlr_scene_node_raise_to_top(&cur.tab_bar.*.scene.*.node);
    }
}

export fn client_reparent_tab(cl_in: ?*Client) callconv(.c) void {
    const cl = cl_in orelse return;
    if (cl.mon == null or !tabIsMember(cl))
        return;

    const head = tabHead(cl);
    var focus: *Client = head orelse cl;
    var it = head;
    while (it) |cur| : (it = clientOpt(cur.tab_next)) {
        if (cur.is_tab_focus)
            focus = cur;
    }

    const layer = client_target_layer(focus);
    it = head;
    while (it) |cur| : (it = clientOpt(cur.tab_next)) {
        if (cur.tab_bar == null)
            continue;
        c.wlr_scene_node_reparent(&cur.tab_bar.*.scene.*.node, c.server.layers[layer]);
    }
}

export fn client_add_tab_bar(cl_in: ?*Client) callconv(.c) void {
    const cl = cl_in orelse return;
    if (@as(i32, @intCast(c.config.tab_bar_height)) <= 0)
        return;

    cl.tab_bar = acwm_bar_decoration_create(cl, c.TabBar, true, c.server.layers[client_target_layer(cl)], c.config.tabbardata, 0, 0);
    if (cl.tab_bar == null)
        return;
    c.wlr_scene_node_lower_to_bottom(&cl.tab_bar.*.scene.*.node);
    c.wlr_scene_node_set_enabled(&cl.tab_bar.*.scene.*.node, false);
    client_update_tab_bar_title(cl);
}

export fn client_remove_tab_bar(cl_in: ?*Client) callconv(.c) void {
    const cl = cl_in orelse return;
    if (cl.tab_bar == null)
        return;
    acwm_bar_decoration_destroy(cl.tab_bar);
    cl.tab_bar = null;
}

export fn client_update_tab_bar_title(cl_in: ?*Client) callconv(.c) void {
    const cl = cl_in orelse return;
    if (cl.tab_bar == null)
        return;

    var scale: f32 = 1.0;
    if (monitorOpt(cl.mon)) |m| {
        if (m.wlr_output != null)
            scale = m.wlr_output.*.scale;
    } else if (monitorOpt(c.server.selected_monitor)) |m| {
        if (m.wlr_output != null)
            scale = m.wlr_output.*.scale;
    }
    acwm_bar_decoration_update(cl.tab_bar, client_get_title(cl), scale);
}

export fn client_apply_tab_bar_config(cl_in: ?*Client) callconv(.c) void {
    const cl = cl_in orelse return;
    if (cl.tab_bar == null)
        return;
    acwm_bar_decoration_apply_config(cl.tab_bar, &c.config.tabbardata);
}

export fn global_draw_tab_bar(cl_in: ?*Client, x: i32, y: i32, width: i32, height: i32) callconv(.c) void {
    const cl = cl_in orelse return;
    if (cl.tab_bar == null)
        return;
    c.wlr_scene_node_set_position(&cl.tab_bar.*.scene.*.node, x, y);
    acwm_bar_decoration_set_size(cl.tab_bar, width, height);
}

export fn client_draw_tabbar(cl_in: ?*Client, offsets: c.struct_ivec2) callconv(.c) void {
    const cl = cl_in orelse return;
    if (cl.tab_bar == null or cl.mon == null or !cl.is_tab_focus)
        return;
    const m = monitorOpt(cl.mon).?;

    if (!tabLayoutActive(m)) {
        const head = tabHead(cl);
        var it = head;
        while (it) |cur| : (it = clientOpt(cur.tab_next))
            tabBarSetEnabled(cur, false);
        return;
    }

    const head = tabHead(cl);
    var count: i32 = 0;
    var it = head;
    while (it) |cur| : (it = clientOpt(cur.tab_next)) {
        if (tabMemberShownInView(cur, m))
            count += 1;
    }
    if (count < 2)
        return;

    var anchor = cl.animation.current;
    if (cl.animation.running and cl.animation.action == c.OPEN)
        anchor = cl.geom;

    var tab_x = anchor.x;
    const group_h: i32 = if (client_wants_group_bar(cl)) @intCast(c.config.group_bar_height) else 0;
    var tab_y = anchor.y - @as(i32, @intCast(c.config.tab_bar_height)) - group_h;
    var tw = anchor.width;
    var th: i32 = @intCast(c.config.tab_bar_height);

    const top_over = offsets.y;
    const bottom_over = offsets.height;
    const left_over = offsets.x;
    const right_over = offsets.width;

    if (top_over > 0) {
        tab_y = m.m.y;
        th = @as(i32, @intCast(c.config.tab_bar_height)) - top_over;
    }
    if (bottom_over > 0)
        th = th - @max(bottom_over - anchor.height, 0);
    if (right_over > 0)
        tw = tw - right_over;
    if (left_over > 0) {
        tab_x = m.m.x;
        tw = tw - left_over;
    }

    if (tw <= 0 or th <= 0)
        return;

    const bar_w = @divTrunc(tw, count);
    const rem = @rem(tw, count);
    var x = tab_x;
    var i: i32 = 0;
    var cur = head;
    while (cur != null and i < count) : (cur = clientOpt(cur.?.tab_next)) {
        const cc = cur.?;
        if (!tabMemberShownInView(cc, m))
            continue;
        const w = bar_w + (if (i < rem) @as(i32, 1) else 0);
        global_draw_tab_bar(cc, x, tab_y, w, th);
        acwm_bar_decoration_set_focus(cc.tab_bar, cc.is_tab_focus);
        x += w;
        i += 1;
    }
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/tab_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_bar_scenes: [8]c.struct_wlr_scene_tree;
extern var stub_bars: [8]Bar;
extern var stub_bar_next: c_int;
extern var stub_visibility_calls: c_int;
extern var stub_focus_calls: c_int;
extern var stub_layer: u32;
extern var stub_arrange_calls: c_int;
extern var stub_group_bar: bool;
extern var stub_reparent_calls: c_int;
extern var stub_place_above_calls: c_int;
extern var stub_raise_calls: c_int;
extern var stub_lower_calls: c_int;
extern var stub_enable_calls: c_int;
extern var stub_enable_enabled: c_int;
extern var stub_position_calls: c_int;
extern var stub_ignore_hits: c_int;
extern var stub_last_ignore: bool;
extern var stub_bar_update_calls: c_int;
extern var stub_bar_title: [128]u8;
extern var stub_bar_scale: f32;
extern var stub_bar_apply_calls: c_int;
extern var stub_bar_size_calls: c_int;
extern var stub_bar_w: i32;
extern var stub_bar_h: i32;
extern var stub_bar_focus_calls: c_int;
extern var stub_bar_focus: bool;
extern var stub_bar_destroy_calls: c_int;

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

var layer_tree: c.struct_wlr_scene_tree = undefined;

fn resetTabWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    listInit(&c.server.clients);
    listInit(&c.server.monitors);
    stub_bar_next = 0;
    stub_visibility_calls = 0;
    stub_focus_calls = 0;
    stub_layer = 2;
    stub_arrange_calls = 0;
    stub_group_bar = false;
    stub_reparent_calls = 0;
    stub_place_above_calls = 0;
    stub_raise_calls = 0;
    stub_lower_calls = 0;
    stub_enable_calls = 0;
    stub_enable_enabled = 0;
    stub_position_calls = 0;
    stub_ignore_hits = 0;
    stub_last_ignore = false;
    stub_bar_update_calls = 0;
    stub_bar_title = std.mem.zeroes([128]u8);
    stub_bar_scale = 0;
    stub_bar_apply_calls = 0;
    stub_bar_size_calls = 0;
    stub_bar_w = 0;
    stub_bar_h = 0;
    stub_bar_focus_calls = 0;
    stub_bar_focus = false;
    stub_bar_destroy_calls = 0;
    tab_member_count = 0;
    layer_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    c.server.layers[stub_layer] = &layer_tree;
}

fn baseMonitor(m: *Monitor, p: *c.Pertag, layout: *c.Layout, layout_id: c_int) void {
    m.* = std.mem.zeroes(Monitor);
    p.* = std.mem.zeroes(c.Pertag);
    layout.* = std.mem.zeroes(c.Layout);
    layout.id = @intCast(layout_id);
    m.pertag = p;
    p.ltidxs[0] = @ptrCast(layout);
    m.tagset[0] = 1;
    m.seltags = 0;
    m.w = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
    m.m = m.w;
    var out: *c.struct_wlr_output = @ptrFromInt(@intFromPtr(m) + 4096);
    _ = &out;
}

fn fakeOutput() *c.struct_wlr_output {
    const out: *c.struct_wlr_output = @ptrCast(@alignCast(std.heap.c_allocator.create(c.struct_wlr_output) catch @panic("oom")));
    out.* = std.mem.zeroes(c.struct_wlr_output);
    out.enabled = true;
    out.scale = 2.0;
    return out;
}

fn addTabClient(cl: *Client, m: *Monitor, tags: u32, scene: *c.struct_wlr_scene_tree) void {
    cl.* = std.mem.zeroes(Client);
    cl.mon = @ptrCast(m);
    cl.tags = tags;
    cl.scene = @ptrCast(scene);
    scene.node.enabled = true;
    cl.animation.current = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
    cl.geom = cl.animation.current;
    listInsert(&c.server.clients, &cl.link);
}

fn linkChain(a: *Client, b: *Client) void {
    a.tab_next = @ptrCast(b);
    b.tab_prev = @ptrCast(a);
}

test "tab_layout_active follows layout mode and overview" {
    resetTabWorld();
    var p: c.Pertag = undefined;
    var layout: c.Layout = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &layout, c.MONOCLE);

    try testing.expect(!tab_layout_active(&m));
    c.config.monocle_tab_mode = 1;
    try testing.expect(tab_layout_active(&m));
    m.isoverview = 1;
    try testing.expect(!tab_layout_active(&m));

    m.isoverview = 0;
    layout.id = @intCast(c.DECK);
    c.config.monocle_tab_mode = 1;
    try testing.expect(!tab_layout_active(&m));
    c.config.deck_tab_mode = 1;
    try testing.expect(tab_layout_active(&m));
    try testing.expect(!tab_layout_active(null));
}

test "tab_sync_monitor builds and collapses the chain" {
    resetTabWorld();
    var p: c.Pertag = undefined;
    var layout: c.Layout = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &layout, c.MONOCLE);
    c.config.monocle_tab_mode = 1;
    c.config.tab_bar_height = 30;
    m.wlr_output = fakeOutput();

    var scene_a: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var scene_b: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var a: Client = undefined;
    var b: Client = undefined;
    addTabClient(&a, &m, 1, &scene_a);
    addTabClient(&b, &m, 1, &scene_b);
    m.sel = &b;
    client_add_tab_bar(&a);
    client_add_tab_bar(&b);

    tab_sync_monitor(&m);

    try testing.expectEqual(@as(i32, 2), tab_member_count);
    // newest client first: b is the head
    try testing.expect(b.tab_next == @as([*c]Client, @ptrCast(&a)));
    try testing.expect(a.tab_prev == @as([*c]Client, @ptrCast(&b)));
    try testing.expect(b.is_tab_focus);
    try testing.expect(!a.is_tab_focus);
    try testing.expect(stub_vision() > 0);

    a.tags = 2;
    tab_sync_monitor(&m);
    try testing.expectEqual(@as(i32, 0), tab_member_count);
    try testing.expect(b.tab_next == null);
    try testing.expect(a.tab_prev == null);
}

fn stub_vision() c_int {
    return stub_visibility_calls;
}

test "tab detach and replace relink chains" {
    resetTabWorld();
    var p: c.Pertag = undefined;
    var layout: c.Layout = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &layout, c.MONOCLE);
    c.config.monocle_tab_mode = 1;
    c.config.tab_bar_height = 30;
    m.wlr_output = fakeOutput();

    var sa: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var sb: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var sc: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var a: Client = undefined;
    var b: Client = undefined;
    var c_cl: Client = undefined;
    addTabClient(&a, &m, 1, &sa);
    addTabClient(&b, &m, 1, &sb);
    addTabClient(&c_cl, &m, 1, &sc);
    linkChain(&a, &b);
    linkChain(&b, &c_cl);
    client_add_tab_bar(&a);
    client_add_tab_bar(&b);
    client_add_tab_bar(&c_cl);
    tab_member_count = 3;

    tab_detach_client(&b);
    try testing.expectEqual(@as(i32, 2), tab_member_count);
    try testing.expect(a.tab_next == @as([*c]Client, @ptrCast(&c_cl)));
    try testing.expect(c_cl.tab_prev == @as([*c]Client, @ptrCast(&a)));
    try testing.expect(b.tab_prev == null and b.tab_next == null);

    a.is_tab_focus = true;
    var d: Client = undefined;
    var sd: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    addTabClient(&d, &m, 1, &sd);
    tab_replace_client(&a, &d);
    try testing.expect(d.tab_next == @as([*c]Client, @ptrCast(&c_cl)));
    try testing.expect(c_cl.tab_prev == @as([*c]Client, @ptrCast(&d)));
    try testing.expect(d.is_tab_focus);
    try testing.expect(a.tab_prev == null and a.tab_next == null);
}

test "tab input penetration depends on the visible strip" {
    resetTabWorld();
    var p: c.Pertag = undefined;
    var layout: c.Layout = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &layout, c.MONOCLE);
    c.config.monocle_tab_mode = 1;
    c.config.tab_bar_height = 30;
    m.wlr_output = fakeOutput();

    var sa: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var sb: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var a: Client = undefined;
    var b: Client = undefined;
    addTabClient(&a, &m, 1, &sa);
    addTabClient(&b, &m, 1, &sb);
    linkChain(&a, &b);
    client_add_tab_bar(&a);
    client_add_tab_bar(&b);

    tab_update_input_penetration(&a);
    try testing.expectEqual(@as(c_int, 2), stub_ignore_hits);
    try testing.expect(!stub_last_ignore);

    b.tags = 2;
    tab_update_input_penetration(&a);
    try testing.expect(stub_last_ignore);
}

test "tab drawing lays out the strip and focus" {
    resetTabWorld();
    var p: c.Pertag = undefined;
    var layout: c.Layout = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &layout, c.MONOCLE);
    c.config.monocle_tab_mode = 1;
    c.config.tab_bar_height = 30;
    m.wlr_output = fakeOutput();

    var sa: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var sb: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var a: Client = undefined;
    var b: Client = undefined;
    addTabClient(&a, &m, 1, &sa);
    addTabClient(&b, &m, 1, &sb);
    linkChain(&a, &b);
    client_add_tab_bar(&a);
    client_add_tab_bar(&b);
    a.is_tab_focus = true;
    b.is_tab_focus = false;

    client_draw_tabbar(&a, std.mem.zeroes(c.struct_ivec2));

    try testing.expectEqual(@as(i32, 0), stub_bars[0].scene.*.node.x);
    try testing.expectEqual(@as(i32, 500), stub_bars[1].scene.*.node.x);
    try testing.expectEqual(@as(i32, -30), stub_bars[0].scene.*.node.y);
    try testing.expectEqual(@as(i32, 500), stub_bar_w);
    try testing.expectEqual(@as(i32, 30), stub_bar_h);
    try testing.expectEqual(@as(c_int, 2), stub_bar_focus_calls);
}

test "tab bar lifecycle, title and config" {
    resetTabWorld();
    var p: c.Pertag = undefined;
    var layout: c.Layout = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &layout, c.MONOCLE);
    c.config.tab_bar_height = 30;
    m.wlr_output = fakeOutput();
    var scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var a: Client = undefined;
    addTabClient(&a, &m, 1, &scene);

    client_add_tab_bar(&a);
    try testing.expect(a.tab_bar != null);
    try testing.expectEqual(@as(c_int, 1), stub_lower_calls);
    try testing.expectEqual(@as(c_int, 0), stub_enable_enabled);
    try testing.expectEqual(@as(c_int, 1), stub_bar_update_calls);
    try testing.expectEqualStrings("title", std.mem.span(@as([*:0]const u8, @ptrCast(&stub_bar_title))));
    try testing.expectEqual(@as(f32, 2.0), stub_bar_scale);

    client_update_tab_bar_title(&a);
    try testing.expectEqual(@as(c_int, 2), stub_bar_update_calls);
    client_apply_tab_bar_config(&a);
    try testing.expectEqual(@as(c_int, 1), stub_bar_apply_calls);
    client_remove_tab_bar(&a);
    try testing.expectEqual(@as(c_int, 1), stub_bar_destroy_calls);
    try testing.expect(a.tab_bar == null);

    c.config.tab_bar_height = 0;
    client_add_tab_bar(&a);
    try testing.expect(a.tab_bar == null);
}

test "tab raising and reparenting reach every member" {
    resetTabWorld();
    var p: c.Pertag = undefined;
    var layout: c.Layout = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &layout, c.MONOCLE);
    c.config.monocle_tab_mode = 1;
    c.config.tab_bar_height = 30;
    m.wlr_output = fakeOutput();
    var root: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);

    var a: Client = undefined;
    var b: Client = undefined;
    addTabClient(&a, &m, 1, &root);
    addTabClient(&b, &m, 1, &root);
    linkChain(&a, &b);
    client_add_tab_bar(&a);
    client_add_tab_bar(&b);
    a.is_tab_focus = true;

    client_raise_tab(&a);
    try testing.expectEqual(@as(c_int, 2), stub_raise_calls);

    client_reparent_tab(&a);
    try testing.expectEqual(@as(c_int, 2), stub_reparent_calls);
    try testing.expect(stub_bars[0].scene.*.node.parent == &layer_tree);
    try testing.expect(stub_bars[1].scene.*.node.parent == &layer_tree);
}
