//! Port of the bind.c tail cluster: monitor enable/sleep, scroller stack
//! moves, all-floating toggle, dwindle split controls and config reload
//! (strangler-fig Phase 4, dispatch slice 6, slice 42).

const std = @import("std");
const c = @import("cc");

const Arg = c.Arg;
const Client = c.Client;
const Monitor = c.Monitor;
const Node = c.DwindleNode;

extern fn acwm_output_commit(m: *Monitor) callconv(.c) bool;
extern fn wlr_output_state_set_enabled(state: *c.struct_wlr_output_state, enabled: bool) callconv(.c) void;
extern fn handle_output_layout_change(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn match_monitor_spec(spec: [*c]const u8, m: *Monitor) callconv(.c) bool;

extern fn is_scroller_layout(m: *Monitor) callconv(.c) bool;
extern fn get_client_tag_idx(cl: *const Client) callconv(.c) u32;
extern fn ensure_scroller_state(m: *Monitor, tag: u32) callconv(.c) ?*c.TagScrollerState;
extern fn find_scroller_node(st: ?*c.TagScrollerState, cl: ?*Client) callconv(.c) ?*c.ScrollerStackNode;
extern fn scroller_node_remove(st: ?*c.TagScrollerState, node: ?*c.ScrollerStackNode) callconv(.c) void;
extern fn update_scroller_state(m: *Monitor) callconv(.c) void;
extern fn scroll_get_stack_head_client(cl: ?*Client) callconv(.c) ?*Client;
extern fn scroll_get_stack_tail_client(cl: ?*Client) callconv(.c) ?*Client;
extern fn scroller_insert_stack(cl: *Client, target: ?*Client, before: bool) callconv(.c) void;
extern fn sync_scroller_state_to_clients(m: *Monitor, tag: u32) callconv(.c) void;
extern fn wl_list_safe_reinsert_prev(l1: *c.struct_wl_list, l2: *c.struct_wl_list) callconv(.c) void;
extern fn wl_list_safe_reinsert_next(l1: *c.struct_wl_list, l2: *c.struct_wl_list) callconv(.c) void;
extern fn find_client_by_direction(tc: *Client, arg: *const Arg, findfloating: bool) callconv(.c) ?*Client;

extern fn set_size_per(m: *Monitor, cl: *Client, reset: bool) callconv(.c) void;
extern fn client_set_floating(cl: *Client, floating: i32) callconv(.c) void;
extern fn client_raise_group(cl: *Client) callconv(.c) void;
extern fn client_raise_tab(cl: *Client) callconv(.c) void;

extern fn dwindle_find_leaf(node: ?*Node, cl: ?*Client) callconv(.c) ?*Node;
extern fn check_hit_no_border(cl: *Client) callconv(.c) bool;
extern fn compute_edge_offsets(cl: *Client) callconv(.c) c.struct_ivec2;
extern fn client_draw_split_border(cl: *Client, hit_no_border: bool, offsets: c.struct_ivec2) callconv(.c) void;
extern fn arrange(m: *Monitor, want_animation: bool, from_view: bool) callconv(.c) void;

extern fn reload_config(arg: *const Arg) callconv(.c) c_int;
extern "c" fn snprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ...) c_int;

fn clientOpt(p: [*c]Client) ?*Client {
    return if (p == null) null else @ptrCast(p);
}

fn monitorOpt(p: [*c]Monitor) ?*Monitor {
    return if (p == null) null else @ptrCast(p);
}

fn nodeOpt(p: [*c]Node) ?*Node {
    return if (p == null) null else @ptrCast(p);
}

fn scrollerNodeOpt(p: [*c]c.ScrollerStackNode) ?*c.ScrollerStackNode {
    return if (p == null) null else @ptrCast(p);
}

fn containerOf(comptime T: type, comptime link_field: []const u8, link: [*c]c.struct_wl_list) *T {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(T, link_field));
}

fn listHead(head: *c.struct_wl_list) [*c]c.struct_wl_list {
    return @ptrCast(head);
}

fn VISIBLEON(cl: *const Client, m: *const Monitor) bool {
    if (cl.mon != @as([*c]Monitor, @ptrCast(@constCast(m))))
        return false;
    if (cl.isminimized != 0)
        return false;
    return (cl.tags & m.tagset[m.seltags]) != 0 or cl.isglobal != 0 or cl.isunglobal != 0;
}

fn selectedClient(arg: *const Arg) ?*Client {
    if (clientOpt(arg.tc)) |cl|
        return cl;
    const m = monitorOpt(c.server.selected_monitor) orelse return null;
    return clientOpt(m.sel);
}

// ---------------------------------------------------------------------------
// monitors
// ---------------------------------------------------------------------------

fn setMonitorEnabled(arg: *const Arg, enabled: bool, only_sleep: i32) void {
    var pos = c.server.monitors.next;
    const head = listHead(&c.server.monitors);
    while (pos != head) : (pos = pos.*.next) {
        const m = containerOf(Monitor, "link", pos);
        if (match_monitor_spec(arg.v, m)) {
            wlr_output_state_set_enabled(&m.pending, enabled);
            _ = acwm_output_commit(m);
            m.only_sleep = only_sleep;
            handle_output_layout_change(null, null);
            break;
        }
    }
}

export fn disable_monitor(arg: *const Arg) callconv(.c) i32 {
    setMonitorEnabled(arg, false, 0);
    return 0;
}

export fn enable_monitor(arg: *const Arg) callconv(.c) i32 {
    setMonitorEnabled(arg, true, 0);
    return 0;
}

export fn toggle_monitor(arg: *const Arg) callconv(.c) i32 {
    var pos = c.server.monitors.next;
    const head = listHead(&c.server.monitors);
    while (pos != head) : (pos = pos.*.next) {
        const m = containerOf(Monitor, "link", pos);
        if (match_monitor_spec(arg.v, m)) {
            wlr_output_state_set_enabled(&m.pending, !m.wlr_output.*.enabled);
            _ = acwm_output_commit(m);
            m.only_sleep = 0;
            handle_output_layout_change(null, null);
            break;
        }
    }
    return 0;
}

export fn sleep_monitor(arg: *const Arg) callconv(.c) i32 {
    setMonitorEnabled(arg, false, 1);
    return 0;
}

export fn wakeup_monitor(arg: *const Arg) callconv(.c) i32 {
    setMonitorEnabled(arg, true, 0);
    return 0;
}

export fn sleep_toggle_monitor(arg: *const Arg) callconv(.c) i32 {
    var pos = c.server.monitors.next;
    const head = listHead(&c.server.monitors);
    while (pos != head) : (pos = pos.*.next) {
        const m = containerOf(Monitor, "link", pos);
        if (match_monitor_spec(arg.v, m)) {
            const was_enabled = m.wlr_output.*.enabled;
            wlr_output_state_set_enabled(&m.pending, !was_enabled);
            _ = acwm_output_commit(m);
            m.only_sleep = if (was_enabled) 1 else 0;
            handle_output_layout_change(null, null);
            break;
        }
    }
    return 0;
}

// ---------------------------------------------------------------------------
// scroller stack moves
// ---------------------------------------------------------------------------

fn scrollerApplyStack(cl_in: ?*Client, target_in: ?*Client, direction: i32) void {
    const cl = cl_in orelse return;
    const m = monitorOpt(cl.mon) orelse return;
    if (cl.isfloating != 0 or !is_scroller_layout(m))
        return;

    const tag = get_client_tag_idx(cl);
    const layout = m.pertag.*.ltidxs[@intCast(tag)];
    const is_horizontal = layout.*.id == c.SCROLLER;

    if (is_horizontal and (direction == c.UP or direction == c.DOWN))
        return;
    if (!is_horizontal and (direction == c.LEFT or direction == c.RIGHT))
        return;

    const st = ensure_scroller_state(m, tag) orelse return;
    const cnode = find_scroller_node(st, cl) orelse return;
    const target = clientOpt(target_in);
    const tnode = if (target) |t| find_scroller_node(st, t) else null;

    if (direction == c.UNDIR and target != null and target.?.mon == @as([*c]Monitor, @ptrCast(m))) {
        scroller_insert_stack(cl, target, false);
        return;
    }

    if (cnode.prev_in_stack != null or cnode.next_in_stack != null) {
        const refer = scrollerNodeOpt(if (cnode.prev_in_stack != null) cnode.prev_in_stack else cnode.next_in_stack) orelse return;
        scroller_node_remove(st, cnode);
        update_scroller_state(m);

        const stack_head = scroll_get_stack_head_client(refer.client);
        const stack_tail = scroll_get_stack_tail_client(refer.client);

        if (direction == c.LEFT or direction == c.UP) {
            if (stack_head != null and cl != stack_head.?)
                wl_list_safe_reinsert_prev(&stack_head.?.link, &cl.link);
        } else if (direction == c.RIGHT or direction == c.DOWN) {
            if (stack_tail != null and cl != stack_tail.?)
                wl_list_safe_reinsert_next(&stack_head.?.link, &cl.link);
        }
        sync_scroller_state_to_clients(m, tag);
        arrange(m, false, false);
        return;
    }

    const tn = tnode orelse return;
    if (target == null or target.?.mon != @as([*c]Monitor, @ptrCast(m)))
        return;

    var tail = tn;
    while (tail.next_in_stack != null)
        tail = scrollerNodeOpt(tail.next_in_stack).?;

    scroller_insert_stack(cl, clientOpt(tail.client), false);

    const tail_client = clientOpt(tail.client) orelse return;
    if (cl != tail_client) {
        c.wl_list_remove(&cl.link);
        c.wl_list_insert(&tail_client.link, &cl.link);
    }
}

export fn scroller_stack(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    const cl = selectedClient(arg) orelse return 0;
    if (cl.mon == null or cl.isfloating != 0 or !is_scroller_layout(m))
        return 0;

    const target = find_client_by_direction(cl, arg, false);
    scrollerApplyStack(cl, target, arg.i);
    return 0;
}

// ---------------------------------------------------------------------------
// all-floating toggle
// ---------------------------------------------------------------------------

export fn toggle_all_floating(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    const ref = selectedClient(arg) orelse return 0;
    const should_floating = ref.isfloating == 0;

    var pos = c.server.clients.next;
    const head = listHead(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (VISIBLEON(cl, m)) {
            if (cl.isfloating != 0 and !should_floating) {
                cl.old_master_inner_per = 0.0;
                cl.old_stack_inner_per = 0.0;
                set_size_per(m, cl, false);
            }
            if ((cl.isfloating != 0) != should_floating)
                client_set_floating(cl, if (should_floating) 1 else 0);
        }
    }

    var rpos = c.server.focus_stack.prev;
    while (rpos != @as([*c]c.struct_wl_list, @ptrCast(&c.server.focus_stack))) : (rpos = rpos.*.prev) {
        const cl = containerOf(Client, "flink", rpos);
        if (!VISIBLEON(cl, m))
            continue;
        client_raise_group(cl);
        client_raise_tab(cl);
    }
    return 0;
}

// ---------------------------------------------------------------------------
// dwindle split controls
// ---------------------------------------------------------------------------

fn dwindleSetSplitDirection(cl: *Client, istoggle: bool, horizontal: bool) void {
    const m = monitorOpt(cl.mon) orelse return;
    const tag = get_client_tag_idx(cl);
    const layout = m.pertag.*.ltidxs[@intCast(tag)];
    if (layout.*.id != c.DWINDLE)
        return;

    const root: *[*c]Node = &m.pertag.*.dwindle_root[@intCast(tag)];
    const leaf = dwindle_find_leaf(nodeOpt(root.*), cl) orelse return;

    if (istoggle) {
        leaf.custom_leaf_split_h = !leaf.custom_leaf_split_h;
    } else if (horizontal) {
        leaf.custom_leaf_split_h = true;
    } else {
        leaf.custom_leaf_split_h = false;
    }
    const hit_no_border = check_hit_no_border(cl);
    const offsets = compute_edge_offsets(cl);
    client_draw_split_border(cl, hit_no_border, offsets);
}

export fn dwindle_set_split_direction(cl_in: ?*Client, istoggle: bool, horizontal: bool) callconv(.c) void {
    const cl = cl_in orelse return;
    dwindleSetSplitDirection(cl, istoggle, horizontal);
}

export fn dwindle_toggle_split_direction(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    _ = m;
    const cl = selectedClient(arg) orelse return 0;
    if (cl.mon == null or cl.isfloating != 0)
        return 0;
    dwindleSetSplitDirection(cl, true, false);
    return 0;
}

export fn dwindle_split_horizontal(arg: *const Arg) callconv(.c) i32 {
    const cl = selectedClient(arg) orelse return 0;
    if (cl.mon == null or cl.isfloating != 0)
        return 0;
    dwindleSetSplitDirection(cl, false, true);
    return 0;
}

export fn dwindle_split_vertical(arg: *const Arg) callconv(.c) i32 {
    const cl = selectedClient(arg) orelse return 0;
    if (cl.mon == null or cl.isfloating != 0)
        return 0;
    dwindleSetSplitDirection(cl, false, false);
    return 0;
}

export fn dwindle_toggle_current_split(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    _ = m;
    const cl = selectedClient(arg) orelse return 0;
    if (cl.mon == null or cl.isfloating != 0)
        return 0;

    const clmon = monitorOpt(cl.mon) orelse return 0;
    const tag = get_client_tag_idx(cl);
    const layout = clmon.pertag.*.ltidxs[@intCast(tag)];
    if (layout.*.id != c.DWINDLE)
        return 0;

    const root = clmon.pertag.*.dwindle_root[@intCast(tag)];
    const leaf = dwindle_find_leaf(nodeOpt(root), cl) orelse return 0;
    const parent = nodeOpt(leaf.parent) orelse return 0;

    parent.split_h = !parent.split_h;
    parent.split_locked = true;
    arrange(clmon, false, false);
    return 0;
}

// ---------------------------------------------------------------------------
// config reload
// ---------------------------------------------------------------------------

export fn load_config_file(arg: *const Arg) callconv(.c) i32 {
    if (arg.v == null)
        return 0;
    _ = snprintf(&c.server.cli_config_path, c.server.cli_config_path.len, "%s", arg.v);
    return reload_config(arg);
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/bind_tail_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_state: c.TagScrollerState;
extern var stub_node_c: c.ScrollerStackNode;
extern var stub_node_t: c.ScrollerStackNode;
extern var stub_c_client: ?*Client;
extern var stub_t_client: ?*Client;
extern var stub_leaf: ?*Node;
extern var stub_direction_client: ?*Client;
extern var stub_is_scroller: bool;
extern var stub_hit_noborder: bool;
extern var stub_enabled_calls: c_int;
extern var stub_enabled_arg: bool;
extern var stub_commit_calls: c_int;
extern var stub_layout_change_calls: c_int;
extern var stub_match_calls: c_int;
extern var stub_remove_calls: c_int;
extern var stub_update_calls: c_int;
extern var stub_insert_stack_calls: c_int;
extern var stub_insert_stack_client: ?*Client;
extern var stub_insert_stack_target: ?*Client;
extern var stub_insert_stack_before: bool;
extern var stub_sync_calls: c_int;
extern var stub_reinsert_prev_calls: c_int;
extern var stub_reinsert_next_calls: c_int;
extern var stub_set_size_calls: c_int;
extern var stub_floating_calls: c_int;
extern var stub_floating_arg: i32;
extern var stub_raise_group_calls: c_int;
extern var stub_raise_tab_calls: c_int;
extern var stub_arrange_calls: c_int;
extern var stub_draw_border_calls: c_int;
extern var stub_reload_calls: c_int;

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

fn resetWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    listInit(&c.server.clients);
    listInit(&c.server.monitors);
    listInit(&c.server.focus_stack);
    stub_state = std.mem.zeroes(c.TagScrollerState);
    stub_node_c = std.mem.zeroes(c.ScrollerStackNode);
    stub_node_t = std.mem.zeroes(c.ScrollerStackNode);
    stub_c_client = null;
    stub_t_client = null;
    stub_leaf = null;
    stub_direction_client = null;
    stub_is_scroller = false;
    stub_hit_noborder = false;
    stub_enabled_calls = 0;
    stub_commit_calls = 0;
    stub_layout_change_calls = 0;
    stub_match_calls = 0;
    stub_remove_calls = 0;
    stub_update_calls = 0;
    stub_insert_stack_calls = 0;
    stub_sync_calls = 0;
    stub_reinsert_prev_calls = 0;
    stub_reinsert_next_calls = 0;
    stub_set_size_calls = 0;
    stub_floating_calls = 0;
    stub_floating_arg = 0;
    stub_raise_group_calls = 0;
    stub_raise_tab_calls = 0;
    stub_arrange_calls = 0;
    stub_draw_border_calls = 0;
    stub_reload_calls = 0;
}

fn baseMonitor(m: *Monitor, p: *c.Pertag, out: *c.struct_wlr_output) void {
    m.* = std.mem.zeroes(Monitor);
    p.* = std.mem.zeroes(c.Pertag);
    out.* = std.mem.zeroes(c.struct_wlr_output);
    m.pertag = p;
    m.wlr_output = @ptrCast(out);
    m.w = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
    m.tagset[0] = 1;
    m.seltags = 0;
}

fn addClient(cl: *Client, m: *Monitor, tags: u32) void {
    cl.* = std.mem.zeroes(Client);
    cl.mon = @ptrCast(m);
    cl.tags = tags;
    listInsert(&c.server.clients, &cl.link);
}

test "monitor enable/disable/sleep actions set state and only_sleep" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    out.enabled = false;
    listInsert(&c.server.monitors, &m.link);

    var arg = std.mem.zeroes(Arg);
    arg.v = @ptrCast(@constCast("DP-1"));

    _ = enable_monitor(&arg);
    try testing.expect(stub_enabled_arg);
    try testing.expectEqual(@as(i32, 0), m.only_sleep);
    try testing.expectEqual(@as(c_int, 1), stub_commit_calls);

    _ = disable_monitor(&arg);
    try testing.expect(!stub_enabled_arg);

    _ = sleep_monitor(&arg);
    try testing.expectEqual(@as(i32, 1), m.only_sleep);

    _ = wakeup_monitor(&arg);
    try testing.expectEqual(@as(i32, 0), m.only_sleep);

    out.enabled = false;
    _ = toggle_monitor(&arg);
    try testing.expect(stub_enabled_arg);
    out.enabled = true;
    _ = toggle_monitor(&arg);
    try testing.expect(!stub_enabled_arg);

    out.enabled = true;
    _ = sleep_toggle_monitor(&arg);
    try testing.expect(!stub_enabled_arg);
    try testing.expectEqual(@as(i32, 1), m.only_sleep);

    out.enabled = false;
    _ = sleep_toggle_monitor(&arg);
    try testing.expect(stub_enabled_arg);
    try testing.expectEqual(@as(i32, 0), m.only_sleep);
    try testing.expectEqual(@as(c_int, 8), stub_layout_change_calls);
}

test "scroller_apply_stack rejects the wrong axis and inserts on UNDIR" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);
    var layout: c.Layout = std.mem.zeroes(c.Layout);
    layout.id = @intCast(c.SCROLLER);
    p.ltidxs[0] = @ptrCast(&layout);
    stub_is_scroller = true;
    stub_c_client = &a;
    stub_t_client = &b;

    scrollerApplyStack(&a, &b, c.UP);
    try testing.expectEqual(@as(c_int, 0), stub_insert_stack_calls);

    scrollerApplyStack(&a, &b, c.UNDIR);
    try testing.expectEqual(@as(c_int, 1), stub_insert_stack_calls);
    try testing.expect(stub_insert_stack_client == &a);
    try testing.expect(stub_insert_stack_target == &b);
    try testing.expect(!stub_insert_stack_before);
}

test "scroller_apply_stack moves within and across stacks" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);
    var layout: c.Layout = std.mem.zeroes(c.Layout);
    layout.id = @intCast(c.SCROLLER);
    p.ltidxs[0] = @ptrCast(&layout);
    stub_is_scroller = true;
    stub_c_client = &a;
    stub_t_client = &b;

    stub_node_c.client = @ptrCast(&a);
    stub_node_t.client = @ptrCast(&b);
    stub_node_c.prev_in_stack = @ptrCast(&stub_node_t);
    scrollerApplyStack(&a, &b, c.LEFT);
    try testing.expectEqual(@as(c_int, 1), stub_remove_calls);
    try testing.expectEqual(@as(c_int, 1), stub_update_calls);
    try testing.expectEqual(@as(c_int, 1), stub_reinsert_prev_calls);
    try testing.expectEqual(@as(c_int, 1), stub_sync_calls);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);

    stub_node_c.prev_in_stack = null;
    scrollerApplyStack(&a, &b, c.RIGHT);
    try testing.expectEqual(@as(c_int, 1), stub_insert_stack_calls);
    try testing.expect(stub_insert_stack_target == &b);
    try testing.expect(a.link.prev == @as([*c]c.struct_wl_list, @ptrCast(&b.link)));
}

test "scroller_stack dispatches the directional target" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);
    m.sel = &a;
    c.server.selected_monitor = &m;
    var layout: c.Layout = std.mem.zeroes(c.Layout);
    layout.id = @intCast(c.SCROLLER);
    p.ltidxs[0] = @ptrCast(&layout);
    stub_is_scroller = true;
    stub_c_client = &a;
    stub_t_client = &b;
    stub_direction_client = &b;

    var arg = std.mem.zeroes(Arg);
    arg.tc = @ptrCast(&a);
    arg.i = c.UNDIR;
    _ = scroller_stack(&arg);
    try testing.expectEqual(@as(c_int, 1), stub_insert_stack_calls);
}

test "toggle_all_floating converts visible clients and raises them" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);
    b.isfloating = 1;
    listInsert(&c.server.focus_stack, &a.flink);
    listInsert(&c.server.focus_stack, &b.flink);
    c.server.selected_monitor = &m;

    var arg = std.mem.zeroes(Arg);
    arg.tc = @ptrCast(&a);
    _ = toggle_all_floating(&arg);

    try testing.expectEqual(@as(c_int, 1), stub_floating_calls);
    try testing.expectEqual(@as(i32, 1), stub_floating_arg);
    try testing.expectEqual(@as(c_int, 0), stub_set_size_calls);
    try testing.expectEqual(@as(c_int, 2), stub_raise_group_calls);
    try testing.expectEqual(@as(c_int, 2), stub_raise_tab_calls);
}

test "dwindle split controls update leaf and parent flags" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    var a: Client = undefined;
    addClient(&a, &m, 1);
    var leaf: Node = std.mem.zeroes(Node);
    var parent: Node = std.mem.zeroes(Node);
    leaf.parent = @ptrCast(&parent);
    stub_leaf = &leaf;
    var layout: c.Layout = std.mem.zeroes(c.Layout);
    layout.id = @intCast(c.DWINDLE);
    p.ltidxs[0] = @ptrCast(&layout);
    c.server.selected_monitor = &m;

    dwindle_set_split_direction(&a, true, false);
    try testing.expect(leaf.custom_leaf_split_h);
    try testing.expectEqual(@as(c_int, 1), stub_draw_border_calls);

    dwindle_set_split_direction(&a, false, false);
    try testing.expect(!leaf.custom_leaf_split_h);

    var arg = std.mem.zeroes(Arg);
    arg.tc = @ptrCast(&a);
    _ = dwindle_toggle_current_split(&arg);
    try testing.expect(parent.split_h);
    try testing.expect(parent.split_locked);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);

    layout.id = @intCast(c.TILE);
    stub_draw_border_calls = 0;
    dwindle_set_split_direction(&a, true, true);
    try testing.expectEqual(@as(c_int, 0), stub_draw_border_calls);
}

test "load_config_file copies the path and reloads" {
    resetWorld();
    var arg = std.mem.zeroes(Arg);
    arg.v = @ptrCast(@constCast("/tmp/config"));
    _ = load_config_file(&arg);
    try testing.expectEqual(@as(c_int, 1), stub_reload_calls);
    try testing.expectEqualStrings("/tmp/config", std.mem.sliceTo(&c.server.cli_config_path, 0));
}
