//! Port of the focus/group cluster of src/dispatch/bind.c
//! (strangler-fig Phase 4, dispatch slice 2, slice 38).

const std = @import("std");
const c = @import("cc");

const Arg = c.Arg;
const Client = c.Client;
const Monitor = c.Monitor;
const WlList = c.struct_wl_list;

extern fn direction_select(arg: *const Arg) callconv(.c) ?*Client;
extern fn get_focused_stack_client(sc: ?*Client, custom: ?*Client) callconv(.c) ?*Client;
extern fn get_next_stack_client(cl: ?*Client, reverse: bool) callconv(.c) ?*Client;
extern fn client_focus(cl: ?*Client, lift: i32) callconv(.c) void;
extern fn client_focus_top(m: ?*Monitor) callconv(.c) ?*Client;
extern fn client_active(cl: ?*Client) callconv(.c) void;
extern fn pointer_warp_to_client(cl: *Client) callconv(.c) void;
extern fn pointer_warp_to_monitor(m: ?*Monitor) callconv(.c) void;
extern fn is_special_active(m: ?*const Monitor) callconv(.c) bool;
extern fn view_shift_tag(arg: *const Arg, dir: i32) callconv(.c) bool;
extern fn view_shift_tag_have_client(arg: *const Arg, dir: i32) callconv(.c) bool;
extern fn set_selected_monitor(m: ?*Monitor) callconv(.c) void;
extern fn monitor_from_cycle(dir: i32) callconv(.c) ?*Monitor;
extern fn monitor_from_direction(dir: c.enum_wlr_direction) callconv(.c) ?*Monitor;
extern fn match_monitor_spec(spec: [*c]const u8, m: *Monitor) callconv(.c) bool;
extern fn get_tags_first_tag(tags: u32) callconv(.c) u32;
extern fn client_switch_view(arg: *const Arg, animate: bool) callconv(.c) void;
extern fn arrange(m: *Monitor, want_animation: bool, from_view: bool) callconv(.c) void;
extern fn client_is_group_member(cl: ?*const Client) callconv(.c) bool;
extern fn client_focus_group_member(cl: ?*Client) callconv(.c) void;
extern fn client_sync_tiled_hint(cl: ?*Client) callconv(.c) void;
extern fn client_group_detach(cl: ?*Client) callconv(.c) void;
extern fn client_unpark(cl: ?*Client, anchor: ?*Client) callconv(.c) void;
extern fn client_update_visibility(cl: ?*Client) callconv(.c) void;
extern fn client_surface(cl: ?*Client) callconv(.c) ?*c.struct_wlr_surface;
extern fn client_is_unmanaged(cl: ?*Client) callconv(.c) c_int;
extern fn client_is_x11_popup(cl: ?*Client) callconv(.c) c_int;
extern fn wlr_seat_pointer_notify_clear_focus(seat: ?*c.struct_wlr_seat) callconv(.c) void;
extern fn wlr_seat_keyboard_notify_clear_focus(seat: ?*c.struct_wlr_seat) callconv(.c) void;
extern fn toggle_overview(arg: *const Arg) callconv(.c) c_int;
extern fn get_mon_curtag(m: *const Monitor) callconv(.c) u32;

extern fn wl_list_insert(list: [*c]WlList, elm: [*c]WlList) callconv(.c) void;
extern fn wl_list_remove(elm: [*c]WlList) callconv(.c) void;

fn clientOpt(p: [*c]Client) ?*Client {
    return if (p == null) null else @ptrCast(p);
}

fn monitorOpt(p: [*c]Monitor) ?*Monitor {
    return if (p == null) null else @ptrCast(p);
}

fn containerOf(comptime T: type, comptime link_field: []const u8, link: [*c]WlList) *T {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(T, link_field));
}

fn listHead(head: *WlList) [*c]WlList {
    return @ptrCast(head);
}

fn zeroArg() Arg {
    return std.mem.zeroes(Arg);
}

// ---------------------------------------------------------------------------
// directional focus
// ---------------------------------------------------------------------------

export fn focus_direction(arg: *const Arg) callconv(.c) i32 {
    const selected = monitorOpt(c.server.selected_monitor) orelse return 0;

    var target = clientOpt(direction_select(arg));
    if (selected.isoverview == 0)
        target = clientOpt(get_focused_stack_client(target, clientOpt(arg.tc)));
    if (target) |cl| {
        client_focus(cl, 1);
        if (c.config.warpcursor != 0)
            pointer_warp_to_client(cl);
    } else {
        if (!is_special_active(selected)) {
            if (c.config.focus_cross_tag != 0) {
                if (arg.i == c.LEFT or arg.i == c.UP) {
                    var a = zeroArg();
                    _ = view_shift_tag_have_client(&a, -1);
                }
                if (arg.i == c.RIGHT or arg.i == c.DOWN) {
                    var a = zeroArg();
                    _ = view_shift_tag_have_client(&a, 1);
                }
            } else if (c.config.focus_cross_monitor != 0) {
                _ = focus_monitor(arg);
            }
        }
    }
    return 0;
}

export fn focus_window_or_workspace(arg: *const Arg) callconv(.c) i32 {
    const selected = monitorOpt(c.server.selected_monitor) orelse return 0;
    if (selected.isoverview != 0)
        return 0;

    var target = clientOpt(direction_select(arg));
    if (selected.isoverview == 0)
        target = clientOpt(get_focused_stack_client(target, clientOpt(arg.tc)));
    if (target != null and target.?.mon == @as([*c]Monitor, @ptrCast(selected))) {
        client_focus(target, 1);
        if (c.config.warpcursor != 0)
            pointer_warp_to_client(target.?);
        return 0;
    }

    if (!is_special_active(selected)) {
        const dir = arg.i;
        if (dir == c.LEFT or dir == c.UP) {
            var a = zeroArg();
            if (!view_shift_tag_have_client(&a, -1))
                _ = view_shift_tag(&a, -1);
        } else if (dir == c.RIGHT or dir == c.DOWN) {
            var a = zeroArg();
            if (!view_shift_tag_have_client(&a, 1))
                _ = view_shift_tag(&a, 1);
        }
    }
    return 0;
}

// ---------------------------------------------------------------------------
// client groups
// ---------------------------------------------------------------------------

export fn client_group_join(join_in: ?*Client, replace_in: ?*Client) callconv(.c) void {
    const join = join_in orelse return;
    const replace = replace_in orelse return;
    const join_mon = monitorOpt(join.mon) orelse return;
    const replace_mon = monitorOpt(replace.mon) orelse return;

    if (join == replace)
        return;
    if (join_mon.isoverview != 0)
        return;

    if (client_is_group_member(join)) {
        var a = zeroArg();
        a.tc = @ptrCast(join);
        _ = group_leave(&a);
    }

    var oldmon: ?*Monitor = null;
    if (join.mon != replace.mon) {
        oldmon = join_mon;
        join.mon = replace.mon;
    }

    if (!client_is_group_member(replace))
        replace.is_group_focus = true;

    join.group_next = @ptrCast(replace);

    if (replace.group_prev != null)
        replace.group_prev.*.group_next = @ptrCast(join);

    join.group_prev = replace.group_prev;
    replace.group_prev = @ptrCast(join);

    client_focus_group_member(join);
    client_sync_tiled_hint(join);
    arrange(monitorOpt(join.mon) orelse replace_mon, false, false);

    if (oldmon) |om|
        arrange(om, false, false);
}

export fn group_join(arg: *const Arg) callconv(.c) i32 {
    const selected = monitorOpt(c.server.selected_monitor) orelse return 0;
    const join = clientOpt(arg.tc) orelse clientOpt(selected.sel) orelse return 0;
    const join_mon = monitorOpt(join.mon) orelse return 0;
    if (join_mon.isoverview != 0)
        return 0;

    client_group_join(join, clientOpt(direction_select(arg)));
    return 0;
}

export fn client_group_leave(tc_in: ?*Client) callconv(.c) bool {
    const tc = tc_in orelse return false;
    const tc_mon = monitorOpt(tc.mon) orelse return false;
    if (!tc.is_group_focus)
        return false;
    if (!client_is_group_member(tc))
        return false;
    if (tc_mon.isoverview != 0)
        return false;

    const was_visible = tc.tag_visible;
    const rc = clientOpt(tc.group_next) orelse clientOpt(tc.group_prev) orelse return false;

    client_focus_group_member(rc);
    client_group_detach(tc);

    tc.is_group_focus = false;
    tc.mon = @ptrCast(rc.mon);
    client_unpark(tc, rc);
    wl_list_remove(&tc.flink);
    wl_list_insert(rc.flink.next, &tc.flink);

    tc.tag_visible = was_visible;
    client_update_visibility(tc);

    if (!client_is_group_member(rc))
        rc.is_group_focus = false;

    return true;
}

export fn group_leave(arg: *const Arg) callconv(.c) i32 {
    const selected = monitorOpt(c.server.selected_monitor) orelse return 0;
    const tc = clientOpt(arg.tc) orelse clientOpt(selected.sel) orelse return 0;
    if (client_group_leave(tc))
        thresholdArrange(tc);
    return 0;
}

fn thresholdArrange(tc: *Client) void {
    if (monitorOpt(tc.mon)) |m|
        arrange(m, false, false);
}

// ---------------------------------------------------------------------------
// focus history / monitors / stacks
// ---------------------------------------------------------------------------

export fn focus_last(arg: *const Arg) callconv(.c) i32 {
    _ = arg;
    var target: ?*Client = null;
    var begin = false;

    var pos = c.server.focus_stack.next;
    const head = listHead(&c.server.focus_stack);
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "flink", pos);
        const surface = client_surface(cl);
        if (cl.iskilling != 0 or cl.isminimized != 0 or cl.isunglobal != 0 or
            surface == null or surface.?.mapped == false or
            client_is_unmanaged(cl) != 0 or client_is_x11_popup(cl) != 0)
            continue;

        const selected = monitorOpt(c.server.selected_monitor);
        if (selected != null and selected.?.sel == null) {
            target = cl;
            break;
        }

        if (selected != null and cl == clientOpt(selected.?.sel) and !begin) {
            begin = true;
            continue;
        }
        if (begin) {
            target = cl;
            break;
        }
    }

    const tc = target orelse return 0;
    const surface = client_surface(tc) orelse return 0;
    if (!surface.mapped)
        return 0;

    if (@as(i32, @bitCast(tc.tags)) > 0) {
        client_focus(tc, 1);
        const target_tag = get_tags_first_tag(tc.tags);
        var a = zeroArg();
        a.ui = target_tag;
        client_switch_view(&a, true);
    }
    return 0;
}

export fn toggle_trackpad_enable(arg: *const Arg) callconv(.c) i32 {
    _ = arg;
    c.config.disable_trackpad = if (c.config.disable_trackpad != 0) 0 else 1;
    return 0;
}

export fn focus_monitor(arg: *const Arg) callconv(.c) i32 {
    var tm: ?*Monitor = null;
    if (arg.i == c.MON_NEXT or arg.i == c.MON_PREV) {
        tm = monitor_from_cycle(arg.i);
    } else if (arg.i != c.UNDIR) {
        tm = monitor_from_direction(@intCast(arg.i));
    } else if (arg.v != null) {
        var pos = c.server.monitors.next;
        const head = listHead(&c.server.monitors);
        while (pos != head) : (pos = pos.*.next) {
            const m = containerOf(Monitor, "link", pos);
            if (m.wlr_output.*.enabled == false)
                continue;
            if (match_monitor_spec(arg.v, m)) {
                tm = m;
                break;
            }
        }
    } else {
        return 0;
    }

    const target_mon = tm orelse return 0;
    const selected_before = monitorOpt(c.server.selected_monitor);
    if (target_mon.wlr_output.*.enabled == false)
        return 0;
    if (selected_before != null and target_mon == selected_before.?)
        return 0;

    set_selected_monitor(target_mon);
    if (c.config.warpcursor != 0)
        pointer_warp_to_monitor(c.server.selected_monitor);

    const selected = monitorOpt(c.server.selected_monitor) orelse return 0;
    const cl = clientOpt(arg.tc) orelse client_focus_top(selected);
    if (cl == null) {
        selected.sel = null;
        wlr_seat_pointer_notify_clear_focus(c.server.seat);
        wlr_seat_keyboard_notify_clear_focus(c.server.seat);
        client_focus(null, 0);
    } else {
        client_focus(cl, 1);
    }
    return 0;
}

export fn focus_stack(arg: *const Arg) callconv(.c) i32 {
    const sel = clientOpt(arg.tc) orelse client_focus_top(c.server.selected_monitor) orelse return 0;
    const tc = get_next_stack_client(sel, arg.i != c.NEXT) orelse return 0;

    client_focus(tc, 1);
    if (c.config.warpcursor != 0)
        pointer_warp_to_client(tc);
    return 0;
}

export fn over_circle(arg: *const Arg) callconv(.c) i32 {
    const selected = monitorOpt(c.server.selected_monitor) orelse return 0;
    if (c.server.grab_client != null)
        return 0;

    const sel = clientOpt(arg.tc) orelse clientOpt(selected.sel);
    const next = arg.i == c.OVERCIRCLE_NEXT or arg.i == c.OVERCIRCLE_CURRENT_NEXT;
    const current = arg.i == c.OVERCIRCLE_CURRENT_NEXT or arg.i == c.OVERCIRCLE_CURRENT_PREV;

    if (selected.isoverview != 0 and selected.is_jump_mode == 0 and
        selected.ov_normal_mode == 0 and sel != null)
    {
        selected.ov_tab_layout = 1;
        const tc = get_next_stack_client(sel, !next) orelse return 0;
        client_focus(tc, 1);
        arrange(selected, true, false);
        return 0;
    }

    selected.ov_tab_layout = 1;
    var a = zeroArg();
    a.tc = arg.tc;
    a.i = @intFromBool(current);
    _ = toggle_overview(&a);
    if (selected.isoverview == 0)
        selected.ov_tab_layout = 0;
    return 0;
}

export fn group_focus(arg: *const Arg) callconv(.c) i32 {
    const selected = monitorOpt(c.server.selected_monitor);
    var target_opt = clientOpt(arg.tc);
    if (target_opt == null) {
        if (selected) |m|
            target_opt = clientOpt(m.sel);
    }
    const cl = target_opt orelse return 0;
    if (cl.mon == null)
        return 0;

    if (!client_is_group_member(cl))
        return 0;

    const m = monitorOpt(cl.mon).?;
    if (m.isoverview != 0)
        return 0;

    const tc = if (arg.i == c.NEXT)
        clientOpt(cl.group_next)
    else
        clientOpt(cl.group_prev);
    const target = tc orelse return 0;

    client_focus_group_member(target);
    arrange(monitorOpt(target.mon) orelse m, false, false);
    return 0;
}

export fn inc_nmaster(arg: *const Arg) callconv(.c) i32 {
    const selected = monitorOpt(c.server.selected_monitor) orelse return 0;
    const tag = get_mon_curtag(selected);
    const current = selected.pertag.*.nmasters[@intCast(tag)];
    selected.pertag.*.nmasters[@intCast(tag)] = @max(current + arg.i, 0);
    arrange(selected, false, false);
    return 0;
}

export fn focus_by_id(arg: *const Arg) callconv(.c) i32 {
    if (c.server.selected_monitor == null or arg.tc == null)
        return 0;
    client_active(clientOpt(arg.tc));
    return 0;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/bind_focus_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_surface: c.struct_wlr_surface;
extern var stub_surface_null: bool;
extern var stub_direction_client: ?*Client;
extern var stub_stack_client: ?*Client;
extern var stub_next_client: ?*Client;
extern var stub_focus_top_client: ?*Client;
extern var stub_group_member: bool;
extern var stub_nonmember_client: ?*Client;
extern var stub_special_active: bool;
extern var stub_have_client_result: bool;
extern var stub_cycle_monitor: ?*Monitor;
extern var stub_direction_monitor: ?*Monitor;
extern var stub_focus_calls: c_int;
extern var stub_focus_client: ?*Client;
extern var stub_warp_client_calls: c_int;
extern var stub_warp_monitor_calls: c_int;
extern var stub_have_calls: c_int;
extern var stub_shift_calls: c_int;
extern var stub_shift_dir: i32;
extern var stub_selected_calls: c_int;
extern var stub_switch_view_calls: c_int;
extern var stub_switch_view_ui: u32;
extern var stub_arrange_calls: c_int;
extern var stub_focus_group_calls: c_int;
extern var stub_focus_group_client: ?*Client;
extern var stub_sync_hint_calls: c_int;
extern var stub_detach_calls: c_int;
extern var stub_unpark_calls: c_int;
extern var stub_update_vis_calls: c_int;
extern var stub_active_calls: c_int;
extern var stub_clear_pointer_calls: c_int;
extern var stub_clear_keyboard_calls: c_int;
extern var stub_overview_calls: c_int;
extern var stub_overview_i: i32;

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
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    listInit(&c.server.clients);
    listInit(&c.server.monitors);
    listInit(&c.server.focus_stack);
    stub_surface = std.mem.zeroes(c.struct_wlr_surface);
    stub_surface.mapped = true;
    stub_surface_null = false;
    stub_direction_client = null;
    stub_stack_client = null;
    stub_next_client = null;
    stub_focus_top_client = null;
    stub_group_member = false;
    stub_nonmember_client = null;
    stub_special_active = false;
    stub_have_client_result = false;
    stub_cycle_monitor = null;
    stub_direction_monitor = null;
    stub_focus_calls = 0;
    stub_focus_client = null;
    stub_warp_client_calls = 0;
    stub_warp_monitor_calls = 0;
    stub_have_calls = 0;
    stub_shift_calls = 0;
    stub_shift_dir = 0;
    stub_selected_calls = 0;
    stub_switch_view_calls = 0;
    stub_switch_view_ui = 0;
    stub_arrange_calls = 0;
    stub_focus_group_calls = 0;
    stub_focus_group_client = null;
    stub_sync_hint_calls = 0;
    stub_detach_calls = 0;
    stub_unpark_calls = 0;
    stub_update_vis_calls = 0;
    stub_active_calls = 0;
    stub_clear_pointer_calls = 0;
    stub_clear_keyboard_calls = 0;
    stub_overview_calls = 0;
    stub_overview_i = 0;
}

fn baseMonitor(m: *Monitor, p: *c.Pertag, out: *c.struct_wlr_output) void {
    m.* = std.mem.zeroes(Monitor);
    p.* = std.mem.zeroes(c.Pertag);
    out.* = std.mem.zeroes(c.struct_wlr_output);
    out.enabled = true;
    m.pertag = p;
    m.wlr_output = @ptrCast(out);
    m.w = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
}

fn addClient(cl: *Client, m: *Monitor, tags: u32) void {
    cl.* = std.mem.zeroes(Client);
    cl.mon = @ptrCast(m);
    cl.tags = tags;
}

test "focus_direction focuses the stack client or shifts views" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);
    c.server.selected_monitor = &m;
    stub_direction_client = &a;
    stub_stack_client = &b;
    c.config.warpcursor = 1;

    var arg = std.mem.zeroes(Arg);
    arg.i = c.RIGHT;
    _ = focus_direction(&arg);
    try testing.expect(stub_focus_client == &b);
    try testing.expectEqual(@as(c_int, 1), stub_warp_client_calls);

    stub_direction_client = null;
    stub_stack_client = null;
    c.config.warpcursor = 0;
    c.config.focus_cross_tag = 1;
    _ = focus_direction(&arg);
    try testing.expectEqual(@as(c_int, 1), stub_have_calls);
    try testing.expectEqual(@as(i32, 1), stub_shift_dir);
    // focus_direction only probes whether the neighbouring view has clients
    try testing.expectEqual(@as(c_int, 0), stub_shift_calls);

    stub_special_active = true;
    _ = focus_direction(&arg);
    try testing.expectEqual(@as(c_int, 1), stub_have_calls);
}

test "focus_window_or_workspace prefers clients on the selected monitor" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    var a: Client = undefined;
    addClient(&a, &m, 1);
    c.server.selected_monitor = &m;
    stub_direction_client = &a;
    stub_stack_client = &a;

    var arg = std.mem.zeroes(Arg);
    arg.i = c.LEFT;
    _ = focus_window_or_workspace(&arg);
    try testing.expect(stub_focus_client == &a);
    try testing.expectEqual(@as(c_int, 0), stub_shift_calls);

    stub_direction_client = null;
    stub_stack_client = null;
    _ = focus_window_or_workspace(&arg);
    try testing.expectEqual(@as(c_int, 1), stub_shift_calls);
    try testing.expectEqual(@as(i32, -1), stub_shift_dir);
}

test "client_group_join links members and rearranges both monitors" {
    resetWorld();
    var p1: c.Pertag = undefined;
    var p2: c.Pertag = undefined;
    var o1: c.struct_wlr_output = undefined;
    var o2: c.struct_wlr_output = undefined;
    var m1: Monitor = undefined;
    var m2: Monitor = undefined;
    baseMonitor(&m1, &p1, &o1);
    baseMonitor(&m2, &p2, &o2);
    var join: Client = undefined;
    var replace: Client = undefined;
    addClient(&join, &m1, 1);
    addClient(&replace, &m2, 1);

    client_group_join(&join, &replace);

    try testing.expect(join.mon == @as([*c]Monitor, @ptrCast(&m2)));
    try testing.expect(join.group_next == @as([*c]Client, @ptrCast(&replace)));
    try testing.expect(replace.group_prev == @as([*c]Client, @ptrCast(&join)));
    try testing.expect(replace.is_group_focus);
    try testing.expect(stub_focus_group_client == &join);
    try testing.expectEqual(@as(c_int, 1), stub_sync_hint_calls);
    try testing.expectEqual(@as(c_int, 2), stub_arrange_calls);
}

test "client_group_leave re-inserts behind the next member" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    var tc: Client = undefined;
    var rc: Client = undefined;
    addClient(&tc, &m, 1);
    addClient(&rc, &m, 1);
    tc.is_group_focus = true;
    tc.group_next = @ptrCast(&rc);
    tc.tag_visible = true;

    listInsert(&c.server.focus_stack, &rc.flink);
    listInsert(&c.server.focus_stack, &tc.flink);
    stub_group_member = true;
    stub_nonmember_client = &rc;

    try testing.expect(client_group_leave(&tc));
    try testing.expectEqual(@as(c_int, 1), stub_detach_calls);
    try testing.expectEqual(@as(c_int, 1), stub_unpark_calls);
    try testing.expectEqual(@as(c_int, 1), stub_update_vis_calls);
    try testing.expect(!tc.is_group_focus);
    try testing.expect(!rc.is_group_focus);
    try testing.expect(tc.flink.next == @as([*c]WlList, @ptrCast(&rc.flink)));
    try testing.expect(rc.flink.prev == @as([*c]WlList, @ptrCast(&tc.flink)));
}

test "focus_last picks the next mapped client on the focus stack" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 2);
    m.sel = &a;
    c.server.selected_monitor = &m;

    listInsert(&c.server.focus_stack, &b.flink);
    listInsert(&c.server.focus_stack, &a.flink);

    _ = focus_last(&std.mem.zeroes(Arg));
    try testing.expect(stub_focus_client == &b);
    try testing.expectEqual(@as(u32, 2), stub_switch_view_ui);

    stub_focus_calls = 0;
    b.isminimized = 1;
    _ = focus_last(&std.mem.zeroes(Arg));
    try testing.expectEqual(@as(c_int, 0), stub_focus_calls);
}

test "focus_monitor selects and clears focus when empty" {
    resetWorld();
    var p1: c.Pertag = undefined;
    var p2: c.Pertag = undefined;
    var o1: c.struct_wlr_output = undefined;
    var o2: c.struct_wlr_output = undefined;
    var m1: Monitor = undefined;
    var m2: Monitor = undefined;
    baseMonitor(&m1, &p1, &o1);
    baseMonitor(&m2, &p2, &o2);
    c.server.selected_monitor = &m1;
    c.server.seat = null;
    stub_direction_monitor = &m2;
    var a: Client = undefined;
    addClient(&a, &m2, 1);
    stub_focus_top_client = &a;
    c.config.warpcursor = 1;

    var arg = std.mem.zeroes(Arg);
    arg.i = c.RIGHT;
    _ = focus_monitor(&arg);
    try testing.expectEqual(@as(c_int, 1), stub_selected_calls);
    try testing.expectEqual(@as(c_int, 1), stub_warp_monitor_calls);
    try testing.expect(stub_focus_client == &a);

    c.server.selected_monitor = &m1;
    stub_focus_top_client = null;
    stub_focus_calls = 0;
    _ = focus_monitor(&arg);
    try testing.expectEqual(@as(c_int, 1), stub_clear_pointer_calls);
    try testing.expectEqual(@as(c_int, 1), stub_clear_keyboard_calls);
    try testing.expect(stub_focus_client == null);
}

test "focus_stack and group_focus walk the next stack/group member" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);
    c.server.selected_monitor = &m;
    stub_next_client = &b;
    c.config.warpcursor = 1;

    var arg = std.mem.zeroes(Arg);
    arg.tc = @ptrCast(&a);
    arg.i = c.NEXT;
    _ = focus_stack(&arg);
    try testing.expect(stub_focus_client == &b);
    try testing.expectEqual(@as(c_int, 1), stub_warp_client_calls);

    a.group_next = @ptrCast(&b);
    stub_group_member = true;
    stub_next_client = null;
    _ = group_focus(&arg);
    try testing.expect(stub_focus_group_client == &b);
}

test "over_circle cycles in overview and toggles otherwise" {
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
    m.isoverview = 1;
    stub_next_client = &b;

    var arg = std.mem.zeroes(Arg);
    arg.i = c.OVERCIRCLE_NEXT;
    _ = over_circle(&arg);
    try testing.expectEqual(@as(i8, 1), m.ov_tab_layout);
    try testing.expect(stub_focus_client == &b);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);

    m.isoverview = 0;
    _ = over_circle(&arg);
    try testing.expectEqual(@as(c_int, 1), stub_overview_calls);
    try testing.expectEqual(@as(i32, 0), stub_overview_i);
    try testing.expectEqual(@as(i8, 0), m.ov_tab_layout);
}

test "inc_nmaster clamps and focus_by_id activates" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    c.server.selected_monitor = &m;
    p.nmasters[0] = 2;

    var arg = std.mem.zeroes(Arg);
    arg.i = -5;
    _ = inc_nmaster(&arg);
    try testing.expectEqual(@as(i32, 0), p.nmasters[0]);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);

    var cl: Client = undefined;
    addClient(&cl, &m, 1);
    arg.tc = @ptrCast(&cl);
    _ = focus_by_id(&arg);
    try testing.expectEqual(@as(c_int, 1), stub_active_calls);

    arg.tc = null;
    _ = focus_by_id(&arg);
    try testing.expectEqual(@as(c_int, 1), stub_active_calls);
}
