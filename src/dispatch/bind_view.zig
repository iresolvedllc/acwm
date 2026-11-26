//! Port of the view-shifting / zoom / option cluster of src/dispatch/bind.c
//! (strangler-fig Phase 4, dispatch slice 5, slice 41).

const std = @import("std");
const c = @import("cc");

const Arg = c.Arg;
const Client = c.Client;
const Monitor = c.Monitor;
const Layout = c.Layout;
const WlList = c.struct_wl_list;

extern fn get_tags_first_tag_num(tags: u32) callconv(.c) u32;
extern fn get_tags_first_tag(tags: u32) callconv(.c) u32;
extern fn get_tag_status(tag: u32, m: ?*Monitor) callconv(.c) u32;
extern fn client_switch_view(arg: *const Arg, animate: bool) callconv(.c) void;
extern fn client_focus(cl: ?*Client, lift: i32) callconv(.c) void;
extern fn client_focus_top(m: ?*Monitor) callconv(.c) ?*Client;
extern fn set_size_per(m: *Monitor, cl: *Client, reset: bool) callconv(.c) void;
extern fn arrange(m: *Monitor, want_animation: bool, from_view: bool) callconv(.c) void;
extern fn printstatus(kind: c.enum_ipc_watch_type) callconv(.c) void;
extern fn is_special_active(m: ?*const Monitor) callconv(.c) bool;
extern fn view_insert_shift_tags(m: *Monitor, target: u32) callconv(.c) void;
extern fn client_view_on_monitor(arg: *const Arg, animate: bool, m: ?*Monitor, changefocus: bool) callconv(.c) void;
extern fn focus_monitor(arg: *const Arg) callconv(.c) c_int;
extern fn tag_monitor(arg: *const Arg) callconv(.c) c_int;
extern fn tag_client(arg: *const Arg, cl: ?*Client) callconv(.c) void;
extern fn match_monitor_spec(spec: [*c]const u8, m: *Monitor) callconv(.c) bool;
extern fn get_mon_curtag(m: *const Monitor) callconv(.c) u32;
extern fn parse_option(config: *c.Config, key: [*:0]const u8, value: [*:0]const u8, line: c_int) callconv(.c) bool;
extern fn override_config() callconv(.c) void;
extern fn reset_option() callconv(.c) void;
extern fn set_minimized(cl: *Client) callconv(.c) void;

extern fn wl_list_remove(elm: [*c]WlList) callconv(.c) void;
extern fn wl_list_insert(list: [*c]WlList, elm: [*c]WlList) callconv(.c) void;

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

fn VISIBLEON(cl: *const Client, m: *const Monitor) bool {
    if (cl.mon != @as([*c]Monitor, @ptrCast(@constCast(m))))
        return false;
    if (cl.isminimized != 0)
        return false;
    return (cl.tags & m.tagset[m.seltags]) != 0 or cl.isglobal != 0 or cl.isunglobal != 0;
}

fn tag0Mask() u32 {
    return @bitCast(c.TAG0_MASK);
}

// ---------------------------------------------------------------------------
// view shifting
// ---------------------------------------------------------------------------

fn tagsLastTagNum(tags_in: u32) u32 {
    var last: u32 = 0;
    var i: u32 = 1;
    const tag_num: u32 = @intCast(c.config.tag_num);
    while (i <= tag_num) : (i += 1) {
        if ((tags_in & (@as(u32, 1) << @intCast(i - 1))) != 0)
            last = i;
    }
    return last;
}

fn tagGatherLastTagNum(m: *Monitor) u32 {
    var last: u32 = 0;
    var pos = c.server.clients.next;
    const head = listHead(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (cl.mon != @as([*c]Monitor, @ptrCast(m)) or cl.iskilling != 0 or
            (cl.tags & tag0Mask()) != 0)
            continue;
        const n = tagsLastTagNum(cl.tags & c.server.tagmask);
        if (n > last)
            last = n;
    }
    last += 1;
    const tag_num: u32 = @intCast(c.config.tag_num);
    if (last > tag_num)
        last = tag_num;
    return last;
}

export fn view_shift_tag(arg: *const Arg, dir: i32) callconv(.c) bool {
    const m = monitorOpt(c.server.selected_monitor) orelse return false;
    if (m.isoverview != 0 or m.pertag.*.curtag == 0)
        return false;

    const cur = get_tags_first_tag_num(m.tagset[m.seltags]);
    const last: u32 = if (c.config.tag_gather != 0)
        tagGatherLastTagNum(m)
    else
        @intCast(c.config.tag_num);
    var target = m.tagset[m.seltags];
    var wrapped = false;

    if (dir < 0) {
        target >>= 1;
        if (target == 0) {
            if (c.config.tag_carousel == 0)
                return false;
            target = @as(u32, 1) << @intCast(last - 1);
            wrapped = true;
        }
    } else {
        target <<= 1;
        if (c.config.tag_carousel != 0 and cur >= last) {
            target = 1;
            wrapped = true;
        } else if ((target & c.server.tagmask) == 0) {
            return false;
        }
    }

    target &= c.server.tagmask;
    if (target == (m.tagset[m.seltags] & c.server.tagmask))
        return false;

    if (wrapped)
        m.carousel_anim_dir = if (dir < 0) -1 else 1;

    var a = std.mem.zeroes(Arg);
    a.ui = target;
    a.i = arg.i;
    client_switch_view(&a, true);
    m.carousel_anim_dir = 0;
    return true;
}

export fn view_shift_tag_have_client(arg: *const Arg, dir: i32) callconv(.c) bool {
    const m = monitorOpt(c.server.selected_monitor) orelse return false;
    if (m.isoverview != 0 or is_special_active(m))
        return false;

    const current = get_tags_first_tag_num(m.tagset[m.seltags]);
    var found = false;
    var wrapped = false;
    var n: u32 = 0;
    const tag_num: u32 = @intCast(c.config.tag_num);

    if (dir < 0) {
        var t: i64 = @as(i64, @intCast(current)) - 1;
        while (t >= 1) : (t -= 1) {
            if (get_tag_status(@intCast(t), m) != 0) {
                found = true;
                n = @intCast(t);
                break;
            }
        }
        if (!found and c.config.tag_carousel != 0) {
            var t2: u32 = tag_num;
            while (t2 > current) : (t2 -= 1) {
                if (get_tag_status(t2, m) != 0) {
                    found = true;
                    wrapped = true;
                    n = t2;
                    break;
                }
            }
        }
    } else {
        n = current + 1;
        while (n <= tag_num) : (n += 1) {
            if (get_tag_status(n, m) != 0) {
                found = true;
                break;
            }
        }
        if (!found and c.config.tag_carousel != 0) {
            var t2: u32 = 1;
            while (t2 < current) : (t2 += 1) {
                if (get_tag_status(t2, m) != 0) {
                    found = true;
                    wrapped = true;
                    n = t2;
                    break;
                }
            }
        }
    }

    if (found) {
        if (wrapped)
            m.carousel_anim_dir = if (dir < 0) -1 else 1;
        var a = std.mem.zeroes(Arg);
        a.ui = (@as(u32, 1) << @intCast(n - 1)) & c.server.tagmask;
        a.i = arg.i;
        client_switch_view(&a, true);
        m.carousel_anim_dir = 0;
        return true;
    }
    return false;
}

export fn view_to_left(arg: *const Arg) callconv(.c) i32 {
    _ = view_shift_tag(arg, -1);
    return 0;
}

export fn view_to_right(arg: *const Arg) callconv(.c) i32 {
    _ = view_shift_tag(arg, 1);
    return 0;
}

export fn view_insert(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    if (m.isoverview != 0)
        return 0;

    const curmask = m.tagset[m.seltags] & c.server.tagmask;
    if (curmask == 0 or (curmask & (curmask - 1)) != 0)
        return 0;
    const cur = get_tags_first_tag_num(curmask);
    if (cur == 0)
        return 0;

    const tag_num: u32 = @intCast(c.config.tag_num);
    var target: u32 = 0;
    if (arg.i == c.NEXT) {
        if (cur >= tag_num)
            return 0;
        target = cur + 1;
    } else if (cur == 1) {
        target = cur;
    } else if (get_tag_status(cur - 1, m) == 0) {
        target = cur - 1;
    } else {
        target = cur;
    }

    if (get_tag_status(target, m) == 0) {
        var a = std.mem.zeroes(Arg);
        a.ui = (@as(u32, 1) << @intCast(target - 1)) & c.server.tagmask;
        client_switch_view(&a, true);
        return 0;
    }

    if (target >= tag_num or get_tag_status(tag_num, m) != 0)
        return 0;

    view_insert_shift_tags(m, target);
    const gather_bak = c.config.tag_gather;
    c.config.tag_gather = 0;
    var a = std.mem.zeroes(Arg);
    a.ui = (@as(u32, 1) << @intCast(target - 1)) & c.server.tagmask;
    client_switch_view(&a, true);
    c.config.tag_gather = gather_bak;
    return 0;
}

export fn view_to_left_have_client(arg: *const Arg) callconv(.c) i32 {
    _ = view_shift_tag_have_client(arg, -1);
    return 0;
}

export fn view_to_right_have_client(arg: *const Arg) callconv(.c) i32 {
    _ = view_shift_tag_have_client(arg, 1);
    return 0;
}

export fn viewprev_have_client(arg: *const Arg) callconv(.c) i32 {
    _ = view_shift_tag_have_client(arg, -1);
    return 0;
}

export fn viewnext_have_client(arg: *const Arg) callconv(.c) i32 {
    _ = view_shift_tag_have_client(arg, 1);
    return 0;
}

export fn view_cross_monitor(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    var a = std.mem.zeroes(Arg);
    a.v = arg.v;
    a.i = c.UNDIR;
    _ = focus_monitor(&a);
    client_view_on_monitor(arg, true, m, true);
    return 0;
}

export fn tag_cross_monitor(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    const cl = clientOpt(arg.tc) orelse clientOpt(m.sel) orelse return 0;

    if (match_monitor_spec(arg.v, m)) {
        tag_client(arg, cl);
        return 0;
    }

    var a = std.mem.zeroes(Arg);
    a.ui = arg.ui;
    a.i = c.UNDIR;
    a.v = arg.v;
    a.tc = @ptrCast(cl);
    _ = tag_monitor(&a);
    return 0;
}

export fn combo_view(arg: *const Arg) callconv(.c) i32 {
    const newtags = arg.ui & c.server.tagmask;
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    if (newtags == 0)
        return 0;

    if (c.server.tag_combo) {
        m.tagset[m.seltags] |= newtags;
        client_focus(client_focus_top(m), 1);
        arrange(m, false, false);
    } else {
        c.server.tag_combo = true;
        var a = std.mem.zeroes(Arg);
        a.ui = newtags;
        client_switch_view(&a, true);
    }

    printstatus(c.IPC_WATCH_ARRANGGE);
    return 0;
}

// ---------------------------------------------------------------------------
// zoom / options / minimize
// ---------------------------------------------------------------------------

export fn zoom(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    const selected = clientOpt(arg.tc) orelse client_focus_top(m) orelse return 0;
    const layout = m.pertag.*.ltidxs[@intCast(get_mon_curtag(m))];
    if (layout == null or layout.*.arrange == null or selected.isfloating != 0)
        return 0;

    var sel: ?*Client = selected;
    var candidate: ?*Client = null;
    var pos = c.server.clients.next;
    const head = listHead(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (VISIBLEON(cl, m) and cl.isfloating == 0) {
            if (sel == null or cl != sel.?) {
                candidate = cl;
                break;
            }
            sel = null;
        }
    }

    const target = sel orelse candidate orelse return 0;
    wl_list_remove(&target.link);
    wl_list_insert(&c.server.clients, &target.link);

    client_focus(target, 1);
    arrange(m, false, false);
    return 0;
}

export fn setoption(arg: *const Arg) callconv(.c) i32 {
    if (arg.v == null or arg.v2 == null)
        return 0;
    _ = parse_option(&c.config, @ptrCast(arg.v), @ptrCast(arg.v2), 0);
    override_config();
    reset_option();
    return 0;
}

export fn minimize_window(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    if (m.isoverview != 0)
        return 0;

    const cl = clientOpt(arg.tc) orelse clientOpt(m.sel) orelse return 0;
    if (cl.isminimized == 0)
        set_minimized(cl);
    return 0;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/bind_view_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_tag_status: [32]u32;
extern var stub_switch_view_calls: c_int;
extern var stub_switch_view_ui: u32;
extern var stub_focus_calls: c_int;
extern var stub_focus_client: ?*Client;
extern var stub_focus_top: ?*Client;
extern var stub_set_size_calls: c_int;
extern var stub_arrange_calls: c_int;
extern var stub_printstatus_calls: c_int;
extern var stub_special_active: bool;
extern var stub_shift_tags_calls: c_int;
extern var stub_shift_tags_target: u32;
extern var stub_view_on_monitor_calls: c_int;
extern var stub_focus_monitor_calls: c_int;
extern var stub_focus_monitor_i: i32;
extern var stub_tag_monitor_calls: c_int;
extern var stub_tag_monitor_i: i32;
extern var stub_tag_client_calls: c_int;
extern var stub_match_monitor: bool;
extern var stub_parse_calls: c_int;
extern var stub_parse_key: [256]u8;
extern var stub_parse_value: [256]u8;
extern var stub_override_calls: c_int;
extern var stub_reset_option_calls: c_int;
extern var stub_minimized_calls: c_int;

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
    c.server.tagmask = 0x7fffffff;
    @memset(&stub_tag_status, 0);
    stub_switch_view_calls = 0;
    stub_switch_view_ui = 0;
    stub_focus_calls = 0;
    stub_focus_client = null;
    stub_focus_top = null;
    stub_set_size_calls = 0;
    stub_arrange_calls = 0;
    stub_printstatus_calls = 0;
    stub_special_active = false;
    stub_shift_tags_calls = 0;
    stub_shift_tags_target = 0;
    stub_view_on_monitor_calls = 0;
    stub_focus_monitor_calls = 0;
    stub_focus_monitor_i = 0;
    stub_tag_monitor_calls = 0;
    stub_tag_monitor_i = 0;
    stub_tag_client_calls = 0;
    stub_match_monitor = true;
    stub_parse_calls = 0;
    stub_override_calls = 0;
    stub_reset_option_calls = 0;
    stub_minimized_calls = 0;
}

fn baseMonitor(m: *Monitor, p: *c.Pertag, out: *c.struct_wlr_output) void {
    m.* = std.mem.zeroes(Monitor);
    p.* = std.mem.zeroes(c.Pertag);
    out.* = std.mem.zeroes(c.struct_wlr_output);
    out.enabled = true;
    m.pertag = p;
    m.wlr_output = @ptrCast(out);
    m.w = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
    m.tagset[0] = 1;
    m.seltags = 0;
    p.curtag = 1;
}

fn addClient(cl: *Client, m: *Monitor, tags: u32) void {
    cl.* = std.mem.zeroes(Client);
    cl.mon = @ptrCast(m);
    cl.tags = tags;
    listInsert(&c.server.clients, &cl.link);
}

test "view_shift_tag moves, wraps and honors tag gathering" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    c.server.selected_monitor = &m;
    c.config.tag_num = 9;
    c.config.tag_carousel = 1;

    var arg = std.mem.zeroes(Arg);
    try testing.expect(view_shift_tag(&arg, 1));
    try testing.expectEqual(@as(u32, 2), stub_switch_view_ui);

    m.tagset[0] = 1;
    try testing.expect(view_shift_tag(&arg, -1));
    try testing.expectEqual(@as(u32, 256), stub_switch_view_ui);
    try testing.expectEqual(@as(i8, 0), m.carousel_anim_dir);

    m.tagset[0] = 1;
    c.config.tag_carousel = 0;
    try testing.expect(!view_shift_tag(&arg, -1));

    c.config.tag_carousel = 1;
    c.config.tag_gather = 1;
    var cl: Client = undefined;
    addClient(&cl, &m, 4);
    m.tagset[0] = 8;
    try testing.expect(view_shift_tag(&arg, 1));
    try testing.expectEqual(@as(u32, 1), stub_switch_view_ui);
}

test "view_shift_tag_have_client finds the next populated tag" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    c.server.selected_monitor = &m;
    c.config.tag_num = 9;
    c.config.tag_carousel = 1;
    m.tagset[0] = 2;

    stub_tag_status[4] = 1;
    var arg = std.mem.zeroes(Arg);
    try testing.expect(view_shift_tag_have_client(&arg, 1));
    try testing.expectEqual(@as(u32, 8), stub_switch_view_ui);

    m.tagset[0] = 1 << 7;
    stub_tag_status[2] = 1;
    try testing.expect(view_shift_tag_have_client(&arg, 1));
    try testing.expectEqual(@as(u32, 2), stub_switch_view_ui);

    stub_special_active = true;
    try testing.expect(!view_shift_tag_have_client(&arg, 1));
}

test "view_insert switches empty targets and shifts occupied neighbours" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    c.server.selected_monitor = &m;
    c.config.tag_num = 9;

    m.tagset[0] = 4; // tag 3
    var arg = std.mem.zeroes(Arg);
    arg.i = c.NEXT;
    _ = view_insert(&arg);
    try testing.expectEqual(@as(u32, 8), stub_switch_view_ui);

    m.tagset[0] = 2; // tag 2
    arg.i = 0;
    _ = view_insert(&arg);
    try testing.expectEqual(@as(u32, 1), stub_switch_view_ui);

    m.tagset[0] = 2;
    stub_tag_status[1] = 1;
    stub_tag_status[2] = 1;
    c.config.tag_gather = 1;
    _ = view_insert(&arg);
    try testing.expectEqual(@as(c_int, 1), stub_shift_tags_calls);
    try testing.expectEqual(@as(u32, 2), stub_shift_tags_target);
    try testing.expectEqual(@as(u32, 2), stub_switch_view_ui);
    try testing.expectEqual(@as(i32, 1), c.config.tag_gather);

    stub_tag_status[9] = 1;
    const switches = stub_switch_view_calls;
    _ = view_insert(&arg);
    try testing.expectEqual(switches, stub_switch_view_calls);
}

test "combo_view merges tags or starts a combo" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    c.server.selected_monitor = &m;

    var arg = std.mem.zeroes(Arg);
    arg.ui = 2;
    _ = combo_view(&arg);
    try testing.expect(c.server.tag_combo);
    try testing.expectEqual(@as(u32, 2), stub_switch_view_ui);

    _ = combo_view(&arg);
    try testing.expectEqual(@as(u32, 3), m.tagset[0]);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);
    try testing.expectEqual(@as(c_int, 2), stub_printstatus_calls);
}

test "zoom promotes the next visible tiled client to the front" {
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
    var layout: Layout = std.mem.zeroes(Layout);
    layout.arrange = dummyLayoutArrange;
    p.ltidxs[0] = @ptrCast(&layout);

    var arg = std.mem.zeroes(Arg);
    arg.tc = @ptrCast(&b);
    _ = zoom(&arg);

    try testing.expect(stub_focus_client == &a);
    try testing.expect(c.server.clients.next == @as([*c]WlList, @ptrCast(&a.link)));
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);
}

fn dummyLayoutArrange(m: [*c]Monitor) callconv(.c) void {
    _ = m;
}

test "setoption applies and resets parsed options" {
    resetWorld();
    var arg = std.mem.zeroes(Arg);
    arg.v = @ptrCast(@constCast("border_width"));
    arg.v2 = @ptrCast(@constCast("3"));
    _ = setoption(&arg);
    try testing.expectEqual(@as(c_int, 1), stub_parse_calls);
    try testing.expectEqualStrings("border_width", std.mem.span(@as([*:0]const u8, @ptrCast(&stub_parse_key))));
    try testing.expectEqualStrings("3", std.mem.span(@as([*:0]const u8, @ptrCast(&stub_parse_value))));
    try testing.expectEqual(@as(c_int, 1), stub_override_calls);
    try testing.expectEqual(@as(c_int, 1), stub_reset_option_calls);
}

test "minimize_window skips overview and already-minimized clients" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    var a: Client = undefined;
    addClient(&a, &m, 1);
    m.sel = &a;
    c.server.selected_monitor = &m;

    _ = minimize_window(&std.mem.zeroes(Arg));
    try testing.expectEqual(@as(c_int, 1), stub_minimized_calls);

    a.isminimized = 1;
    _ = minimize_window(&std.mem.zeroes(Arg));
    try testing.expectEqual(@as(c_int, 1), stub_minimized_calls);

    m.isoverview = 1;
    a.isminimized = 0;
    _ = minimize_window(&std.mem.zeroes(Arg));
    try testing.expectEqual(@as(c_int, 1), stub_minimized_calls);
}

test "cross-monitor view and tag actions route through the right helpers" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    var a: Client = undefined;
    addClient(&a, &m, 1);
    m.sel = &a;
    c.server.selected_monitor = &m;
    c.config.tag_num = 9;

    var arg = std.mem.zeroes(Arg);
    arg.v = @ptrCast(@constCast("DP-1"));
    _ = view_cross_monitor(&arg);
    try testing.expectEqual(@as(c_int, 1), stub_focus_monitor_calls);
    try testing.expectEqual(@as(i32, c.UNDIR), stub_focus_monitor_i);
    try testing.expectEqual(@as(c_int, 1), stub_view_on_monitor_calls);

    stub_match_monitor = true;
    _ = tag_cross_monitor(&arg);
    try testing.expectEqual(@as(c_int, 1), stub_tag_client_calls);

    stub_match_monitor = false;
    _ = tag_cross_monitor(&arg);
    try testing.expectEqual(@as(c_int, 1), stub_tag_monitor_calls);
    try testing.expectEqual(@as(i32, c.UNDIR), stub_tag_monitor_i);
}
