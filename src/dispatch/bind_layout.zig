//! Port of the gap/layout/proportion/window-action cluster of
//! src/dispatch/bind.c (strangler-fig Phase 4, dispatch slice 3, slice 39).

const std = @import("std");
const c = @import("cc");

const Arg = c.Arg;
const Client = c.Client;
const Monitor = c.Monitor;
const Box = c.struct_wlr_box;
const Layout = c.Layout;
const Node = c.ScrollerStackNode;
const State = c.TagScrollerState;
const WlList = c.struct_wl_list;

extern var layouts: [14]Layout;

extern fn setgaps(oh: i32, ov: i32, ih: i32, iv: i32) callconv(.c) void;
extern fn get_mon_curtag(m: *const Monitor) callconv(.c) u32;
extern fn arrange(m: *Monitor, want_animation: bool, from_view: bool) callconv(.c) void;
extern fn printstatus(kind: c.enum_ipc_watch_type) callconv(.c) void;
extern fn clear_fullscreen_and_maximized_state(m: *Monitor) callconv(.c) void;
extern fn client_pending_force_kill(cl: *Client) callconv(.c) void;
extern fn pending_kill_client(cl: *Client) callconv(.c) void;
extern fn pointer_begin_move_resize(gc: *Client, mode: u32, x: f64, y: f64, edge: u32) callconv(.c) bool;
extern fn node_at_point(
    x: f64,
    y: f64,
    psurface: [*c]?*c.struct_wlr_surface,
    pc: [*c]?*Client,
    player: [*c]?*c.LayerSurface,
    pbar: [*c]?*c.AcwmBarDecoration,
    nx: [*c]f64,
    ny: [*c]f64,
) callconv(.c) void;
extern fn wl_display_terminate(display: ?*c.struct_wl_display) callconv(.c) void;
extern fn client_set_floating(cl: *Client, floating: i32) callconv(.c) void;
extern fn resize(cl: *Client, geo: Box, opts: c.ResizeOpts) callconv(.c) void;
extern fn resize_tile_client(gc: *Client, isdrag: bool, offsetx: i32, offsety: i32, time: u32) callconv(.c) void;
extern fn client_pending_minimized_state(cl: *Client, minimized: i32) callconv(.c) void;
extern fn client_update_border_color(cl: *Client) callconv(.c) void;
extern fn client_focus(cl: ?*Client, lift: i32) callconv(.c) void;
extern fn client_focus_top(m: ?*Monitor) callconv(.c) ?*Client;
extern fn pointer_warp_to_client(cl: *Client) callconv(.c) void;
extern fn is_scroller_layout(m: *Monitor) callconv(.c) bool;
extern fn scroll_get_stack_head_client(cl: ?*Client) callconv(.c) ?*Client;
extern fn find_scroller_node(st: ?*State, cl: ?*Client) callconv(.c) ?*Node;

fn clientOpt(p: [*c]Client) ?*Client {
    return if (p == null) null else @ptrCast(p);
}

fn monitorOpt(p: [*c]Monitor) ?*Monitor {
    return if (p == null) null else @ptrCast(p);
}

fn nodeOpt(p: [*c]Node) ?*Node {
    return if (p == null) null else @ptrCast(p);
}

fn stateOpt(p: [*c]State) ?*State {
    return if (p == null) null else @ptrCast(p);
}

fn containerOf(comptime T: type, comptime link_field: []const u8, link: [*c]WlList) *T {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(T, link_field));
}

fn listHead(head: *WlList) [*c]WlList {
    return @ptrCast(head);
}

fn ISTILED(cl: *const Client) bool {
    return cl.isfloating == 0 and cl.isminimized == 0 and cl.iskilling == 0 and
        cl.ismaximizescreen == 0 and cl.isfullscreen == 0 and cl.isunglobal == 0;
}

fn ISFAKETILED(cl: *const Client) bool {
    return cl.isfloating == 0 and cl.isminimized == 0 and
        cl.iskilling == 0 and cl.isunglobal == 0;
}

fn VISIBLEON(cl: *const Client, m: *const Monitor) bool {
    if (cl.mon != @as([*c]Monitor, @ptrCast(@constCast(m))))
        return false;
    if (cl.isminimized != 0)
        return false;
    return (cl.tags & m.tagset[m.seltags]) != 0 or cl.isglobal != 0 or cl.isunglobal != 0;
}

fn SCRATCHPAD_SHOWN(cl: *const Client) bool {
    return cl.is_in_scratchpad != 0 and cl.isminimized == 0;
}

fn selectedClient(arg: *const Arg) ?*Client {
    if (clientOpt(arg.tc)) |cl|
        return cl;
    const m = monitorOpt(c.server.selected_monitor) orelse return null;
    return clientOpt(m.sel);
}

fn setStr(dst: []u8, src: [*:0]const u8, max: usize) void {
    const s = std.mem.span(src);
    const n = @min(@min(s.len, max), dst.len - 1);
    @memcpy(dst[0..n], s[0..n]);
    dst[n] = 0;
}

// ---------------------------------------------------------------------------
// gaps
// ---------------------------------------------------------------------------

export fn increase_gaps(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    setgaps(m.gappoh + arg.i, m.gappov + arg.i, m.gappih + arg.i, m.gappiv + arg.i);
    return 0;
}

export fn increase_inner_gap(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    setgaps(m.gappoh, m.gappov, m.gappih + arg.i, m.gappiv + arg.i);
    return 0;
}

export fn increase_outer_gap(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    setgaps(m.gappoh + arg.i, m.gappov + arg.i, m.gappih, m.gappiv);
    return 0;
}

export fn increase_inner_horizontal_gap(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    setgaps(m.gappoh, m.gappov, m.gappih + arg.i, m.gappiv);
    return 0;
}

export fn increase_inner_vertical_gap(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    setgaps(m.gappoh, m.gappov, m.gappih, m.gappiv + arg.i);
    return 0;
}

export fn increase_outer_horizontal_gap(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    setgaps(m.gappoh + arg.i, m.gappov, m.gappih, m.gappiv);
    return 0;
}

export fn increase_outer_vertical_gap(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    setgaps(m.gappoh, m.gappov + arg.i, m.gappih, m.gappiv);
    return 0;
}

export fn set_master_factor(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    const tag = get_mon_curtag(m);
    const layout = m.pertag.*.ltidxs[@intCast(tag)];
    if (layout == null or layout.*.arrange == null)
        return 0;

    const current = m.pertag.*.mfacts[@intCast(tag)];
    const f: f32 = if (arg.f < 1.0) arg.f + current else arg.f - 1.0;
    if (f < 0.1 or f > 0.9)
        return 0;

    m.pertag.*.mfacts[@intCast(tag)] = f;

    var pos = c.server.clients.next;
    const head = listHead(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (VISIBLEON(cl, m) and ISTILED(cl))
            cl.master_mfact_per = f;
    }
    arrange(m, false, false);
    return 0;
}

// ---------------------------------------------------------------------------
// window move / resize
// ---------------------------------------------------------------------------

export fn kill_client(arg: *const Arg) callconv(.c) i32 {
    const cl = selectedClient(arg);
    if (cl) |target| {
        if (arg.i == c.FORCE)
            client_pending_force_kill(target)
        else
            pending_kill_client(target);
    }
    return 0;
}

export fn move_resize(arg: *const Arg) callconv(.c) i32 {
    if (c.server.cursor_mode != c.CurNormal and c.server.cursor_mode != c.CurPressed)
        return 0;

    var cl: ?*Client = null;
    var bar: ?*c.AcwmBarDecoration = null;
    node_at_point(c.server.cursor.*.x, c.server.cursor.*.y, null, &cl, null, &bar, null, null);
    if (cl == null and bar != null and !bar.?.is_tab) {
        if (bar.?.node_data != null)
            cl = @ptrCast(@alignCast(bar.?.node_data));
    }
    _ = pointer_begin_move_resize(cl.?, arg.ui, c.server.cursor.*.x, c.server.cursor.*.y, 0);
    return 0;
}

export fn move_window(arg: *const Arg) callconv(.c) i32 {
    const cl = selectedClient(arg) orelse return 0;
    if (cl.isfullscreen != 0)
        return 0;
    if (cl.isfloating == 0)
        client_set_floating(cl, 1);

    switch (arg.ui) {
        c.NUM_TYPE_MINUS => cl.geom.x -= arg.i,
        c.NUM_TYPE_PLUS => cl.geom.x += arg.i,
        else => cl.geom.x = arg.i,
    }

    switch (arg.ui2) {
        c.NUM_TYPE_MINUS => cl.geom.y -= arg.i2,
        c.NUM_TYPE_PLUS => cl.geom.y += arg.i2,
        else => cl.geom.y = arg.i2,
    }

    cl.iscustomsize = 1;
    cl.float_geom = cl.geom;
    resize(cl, cl.geom, .{ .interact = false });
    return 0;
}

export fn quit(arg: *const Arg) callconv(.c) i32 {
    _ = arg;
    wl_display_terminate(c.server.display);
    return 0;
}

export fn resize_window(arg: *const Arg) callconv(.c) i32 {
    const cl = selectedClient(arg) orelse return 0;
    var offsetx: i32 = 0;
    var offsety: i32 = 0;

    if (cl.isfullscreen != 0 or cl.ismaximizescreen != 0)
        return 0;

    const animations_backup = c.config.animations;
    if (cl.isfloating == 0)
        c.config.animations = 0;

    if (ISTILED(cl)) {
        offsetx = switch (arg.ui) {
            c.NUM_TYPE_MINUS => -arg.i,
            c.NUM_TYPE_PLUS => arg.i,
            else => arg.i,
        };
        offsety = switch (arg.ui2) {
            c.NUM_TYPE_MINUS => -arg.i2,
            c.NUM_TYPE_PLUS => arg.i2,
            else => arg.i2,
        };
        resize_tile_client(cl, false, offsetx, offsety, 0);
        c.config.animations = animations_backup;
        return 0;
    }

    switch (arg.ui) {
        c.NUM_TYPE_MINUS => cl.geom.width -= arg.i,
        c.NUM_TYPE_PLUS => cl.geom.width += arg.i,
        else => cl.geom.width = arg.i,
    }
    switch (arg.ui2) {
        c.NUM_TYPE_MINUS => cl.geom.height -= arg.i2,
        c.NUM_TYPE_PLUS => cl.geom.height += arg.i2,
        else => cl.geom.height = arg.i2,
    }

    cl.iscustomsize = 1;
    cl.float_geom = cl.geom;
    resize(cl, cl.geom, .{ .interact = false });
    c.config.animations = animations_backup;
    return 0;
}

export fn restore_minimized(arg: *const Arg) callconv(.c) i32 {
    _ = arg;
    const selected = monitorOpt(c.server.selected_monitor);
    if (selected != null and selected.?.isoverview != 0)
        return 0;

    var target: ?*Client = null;
    var focused: ?*Client = if (selected) |m| clientOpt(m.sel) else null;
    if (focused == null) {
        if (selected) |m|
            focused = client_focus_top(m);
    }

    if (focused != null and SCRATCHPAD_SHOWN(focused.?)) {
        target = focused;
    } else {
        var pos = c.server.clients.next;
        const head = listHead(&c.server.clients);
        while (pos != head) : (pos = pos.*.next) {
            const tc = containerOf(Client, "link", pos);
            const same_mon = selected != null and tc.mon == @as([*c]Monitor, @ptrCast(selected.?));
            if ((same_mon or c.config.scratchpad_cross_monitor != 0) and SCRATCHPAD_SHOWN(tc)) {
                target = tc;
                break;
            }
        }
    }

    if (target == null) {
        var pos = c.server.clients.next;
        const head = listHead(&c.server.clients);
        while (pos != head) : (pos = pos.*.next) {
            const cl = containerOf(Client, "link", pos);
            if (cl.isminimized != 0 and cl.isnamedscratchpad == 0) {
                target = cl;
                break;
            }
        }
    }

    const cl = target orelse return 0;
    cl.is_in_scratchpad = 0;
    cl.isnamedscratchpad = 0;
    client_pending_minimized_state(cl, 0);
    cl.iscustomsize = 0;

    if (focused != null and focused.? != cl and focused.?.tags != 0)
        cl.tags = focused.?.tags
    else if (selected) |m|
        cl.tags = m.tagset[m.seltags];
    cl.oldtags = cl.tags;
    if (selected) |m|
        cl.mon = @ptrCast(m);

    client_set_floating(cl, 0);
    client_update_border_color(cl);
    const m = monitorOpt(cl.mon) orelse return 0;
    arrange(m, false, false);
    client_focus(cl, 1);
    pointer_warp_to_client(cl);
    return 0;
}

// ---------------------------------------------------------------------------
// layout / keymode / proportions
// ---------------------------------------------------------------------------

export fn set_layout(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    if (arg.v == null)
        return 0;
    const name = std.mem.span(@as([*:0]const u8, @ptrCast(arg.v)));

    var i: usize = 0;
    while (i < layouts.len) : (i += 1) {
        const lname = std.mem.span(@as([*:0]const u8, @ptrCast(layouts[i].name)));
        if (std.mem.eql(u8, lname, name)) {
            m.pertag.*.ltidxs[@intCast(get_mon_curtag(m))] = &layouts[i];
            clear_fullscreen_and_maximized_state(m);
            arrange(m, false, false);
            printstatus(c.IPC_WATCH_ARRANGGE);
            return 0;
        }
    }
    return 0;
}

export fn set_key_mode(arg: *const Arg) callconv(.c) i32 {
    if (arg.v == null)
        return 0;
    setStr(&c.server.key_mode.mode, @ptrCast(arg.v), 27);
    c.server.key_mode.isdefault = std.mem.eql(u8, std.mem.sliceTo(&c.server.key_mode.mode, 0), "default");
    printstatus(c.IPC_WATCH_KEYMODE);
    return 1;
}

export fn set_proportion(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    if (m.isoverview != 0 or !is_scroller_layout(m))
        return 0;
    if (m.visible_tiling_clients == 1 and c.config.scroller_ignore_proportion_single == 0)
        return 0;

    const sel = clientOpt(arg.tc) orelse clientOpt(m.sel) orelse return 0;
    const head = scroll_get_stack_head_client(sel) orelse return 0;
    const hm = monitorOpt(head.mon) orelse return 0;
    const tag = get_mon_curtag(hm);

    const st = stateOpt(hm.pertag.*.scroller_state[@intCast(tag)]);
    const node = if (st) |s| find_scroller_node(s, head) else null;

    if (node) |n|
        n.scroller_proportion = arg.f;
    head.scroller_proportion = arg.f;

    const max_client_width = hm.w.width - 2 * c.config.scroller_structs - @as(i32, @intCast(c.config.gappih));
    head.geom.width = @intFromFloat(@as(f32, @floatFromInt(max_client_width)) * arg.f);
    arrange(hm, false, false);
    return 0;
}

export fn switch_proportion_preset(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    if (c.config.scroller_proportion_preset_count == 0)
        return 0;
    if (m.isoverview != 0 or !is_scroller_layout(m))
        return 0;
    if (m.visible_tiling_clients == 1 and c.config.scroller_ignore_proportion_single == 0)
        return 0;

    const sel = clientOpt(arg.tc) orelse clientOpt(m.sel) orelse return 0;
    if (sel.isfloating != 0)
        return 0;
    const head = scroll_get_stack_head_client(sel) orelse return 0;
    const hm = monitorOpt(head.mon) orelse return 0;
    const tag = get_mon_curtag(hm);
    const st = stateOpt(hm.pertag.*.scroller_state[@intCast(tag)]);
    const node = if (st) |s| find_scroller_node(s, head) else null;

    const current: f32 = if (node) |n| n.scroller_proportion else head.scroller_proportion;
    const count: usize = @intCast(c.config.scroller_proportion_preset_count);
    const presets = c.config.scroller_proportion_preset;

    var target: f32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (presets[i] == current) {
            if (arg.i == c.NEXT) {
                target = if (i == count - 1) presets[0] else presets[i + 1];
            } else {
                target = if (i == 0) presets[count - 1] else presets[i - 1];
            }
            break;
        }
    }
    if (target == 0.0)
        target = presets[0];

    if (node) |n|
        n.scroller_proportion = target;
    head.scroller_proportion = target;

    const max_client_width = hm.w.width - 2 * c.config.scroller_structs - @as(i32, @intCast(c.config.gappih));
    head.geom.width = @intFromFloat(@as(f32, @floatFromInt(max_client_width)) * target);
    arrange(hm, false, false);
    return 0;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/bind_layout_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_cursor: c.struct_wlr_cursor;
extern var stub_presets: [4]f32;
extern var stub_node: Node;
extern var stub_head_client: ?*Client;
extern var stub_node_client: ?*Client;
extern var stub_focus_top: ?*Client;
extern var stub_bar_client: ?*Client;
extern var stub_is_scroller: bool;
extern var stub_node_found: bool;
extern var stub_bar_enabled: bool;
extern var stub_bar: c.AcwmBarDecoration;
extern var stub_setgaps_calls: c_int;
extern var stub_gap_oh: i32;
extern var stub_gap_ov: i32;
extern var stub_gap_ih: i32;
extern var stub_gap_iv: i32;
extern var stub_arrange_calls: c_int;
extern var stub_printstatus_calls: c_int;
extern var stub_clear_fs_calls: c_int;
extern var stub_force_kill_calls: c_int;
extern var stub_kill_calls: c_int;
extern var stub_move_resize_calls: c_int;
extern var stub_move_resize_client: ?*Client;
extern var stub_move_resize_mode: u32;
extern var stub_display_term_calls: c_int;
extern var stub_floating_calls: c_int;
extern var stub_floating_arg: i32;
extern var stub_resize_calls: c_int;
extern var stub_resize_tile_calls: c_int;
extern var stub_resize_tile_dx: i32;
extern var stub_resize_tile_dy: i32;
extern var stub_pending_min_calls: c_int;
extern var stub_pending_min_arg: i32;
extern var stub_border_color_calls: c_int;
extern var stub_focus_calls: c_int;
extern var stub_focus_client: ?*Client;
extern var stub_warp_calls: c_int;

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
    stub_cursor = std.mem.zeroes(c.struct_wlr_cursor);
    c.server.cursor = @ptrCast(&stub_cursor);
    stub_node = std.mem.zeroes(Node);
    stub_head_client = null;
    stub_node_client = null;
    stub_focus_top = null;
    stub_is_scroller = false;
    stub_node_found = false;
    stub_bar_enabled = false;
    stub_bar = std.mem.zeroes(c.AcwmBarDecoration);
    stub_setgaps_calls = 0;
    stub_arrange_calls = 0;
    stub_printstatus_calls = 0;
    stub_clear_fs_calls = 0;
    stub_force_kill_calls = 0;
    stub_kill_calls = 0;
    stub_move_resize_calls = 0;
    stub_move_resize_client = null;
    stub_display_term_calls = 0;
    stub_floating_calls = 0;
    stub_floating_arg = 0;
    stub_resize_calls = 0;
    stub_resize_tile_calls = 0;
    stub_pending_min_calls = 0;
    stub_pending_min_arg = -1;
    stub_border_color_calls = 0;
    stub_focus_calls = 0;
    stub_focus_client = null;
    stub_warp_calls = 0;
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
    p.ltidxs[0] = @ptrCast(&layouts[0]);
}

fn addClient(cl: *Client, m: *Monitor, tags: u32) void {
    cl.* = std.mem.zeroes(Client);
    cl.mon = @ptrCast(m);
    cl.tags = tags;
    listInsert(&c.server.clients, &cl.link);
}

test "gap actions set the requested combination" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    m.gappoh = 10;
    m.gappov = 20;
    m.gappih = 6;
    m.gappiv = 4;
    c.server.selected_monitor = &m;

    var arg = std.mem.zeroes(Arg);
    arg.i = 2;
    _ = increase_gaps(&arg);
    try testing.expectEqual(@as(i32, 12), stub_gap_oh);
    try testing.expectEqual(@as(i32, 22), stub_gap_ov);
    try testing.expectEqual(@as(i32, 8), stub_gap_ih);
    try testing.expectEqual(@as(i32, 6), stub_gap_iv);

    _ = increase_inner_gap(&arg);
    try testing.expectEqual(@as(i32, 10), stub_gap_oh);
    try testing.expectEqual(@as(i32, 8), stub_gap_ih);
    try testing.expectEqual(@as(i32, 6), stub_gap_iv);

    _ = increase_outer_horizontal_gap(&arg);
    try testing.expectEqual(@as(i32, 12), stub_gap_oh);
    try testing.expectEqual(@as(i32, 20), stub_gap_ov);
    try testing.expectEqual(@as(i32, 6), stub_gap_ih);

    _ = increase_inner_vertical_gap(&arg);
    try testing.expectEqual(@as(i32, 6), stub_gap_iv);
}

test "set_master_factor broadcasts valid factors only" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    var a: Client = undefined;
    addClient(&a, &m, 1);
    c.server.selected_monitor = &m;
    p.mfacts[0] = 0.5;

    var arg = std.mem.zeroes(Arg);
    arg.f = 0.2;
    _ = set_master_factor(&arg);
    try testing.expectApproxEqAbs(@as(f32, 0.7), p.mfacts[0], 0.0001);
    try testing.expectApproxEqAbs(@as(f64, 0.7), a.master_mfact_per, 0.0001);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);

    arg.f = 3.0;
    _ = set_master_factor(&arg);
    try testing.expectApproxEqAbs(@as(f32, 0.7), p.mfacts[0], 0.0001);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);
}

test "kill_client picks force or normal termination" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    var a: Client = undefined;
    addClient(&a, &m, 1);
    c.server.selected_monitor = &m;

    var arg = std.mem.zeroes(Arg);
    arg.tc = @ptrCast(&a);
    arg.i = c.FORCE;
    _ = kill_client(&arg);
    try testing.expectEqual(@as(c_int, 1), stub_force_kill_calls);

    arg.i = 1;
    _ = kill_client(&arg);
    try testing.expectEqual(@as(c_int, 1), stub_kill_calls);

    m.sel = &a;
    arg.tc = null;
    _ = kill_client(&arg);
    try testing.expectEqual(@as(c_int, 2), stub_kill_calls);
}

test "move_resize resolves the client or the bar node data" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);
    c.server.cursor_mode = c.CurNormal;
    stub_cursor.x = 10;
    stub_cursor.y = 20;
    stub_node_client = &a;

    var arg = std.mem.zeroes(Arg);
    arg.ui = 3;
    _ = move_resize(&arg);
    try testing.expect(stub_move_resize_client == &a);
    try testing.expectEqual(@as(u32, 3), stub_move_resize_mode);

    stub_node_client = null;
    stub_bar_enabled = true;
    stub_bar.is_tab = false;
    stub_bar.node_data = @ptrCast(&b);
    _ = move_resize(&arg);
    try testing.expect(stub_move_resize_client == &b);
}

test "move_window and resize_window adjust floating geometry" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    var a: Client = undefined;
    addClient(&a, &m, 1);
    a.geom = .{ .x = 100, .y = 100, .width = 300, .height = 200 };
    c.server.selected_monitor = &m;

    var arg = std.mem.zeroes(Arg);
    arg.tc = @ptrCast(&a);
    arg.ui = c.NUM_TYPE_PLUS;
    arg.i = 10;
    arg.ui2 = c.NUM_TYPE_MINUS;
    arg.i2 = 5;
    _ = move_window(&arg);
    try testing.expectEqual(@as(i32, 110), a.geom.x);
    try testing.expectEqual(@as(i32, 95), a.geom.y);
    try testing.expectEqual(@as(c_int, 1), stub_floating_calls);
    try testing.expectEqual(@as(c_int, 1), stub_resize_calls);
    try testing.expectEqual(@as(i32, 1), a.iscustomsize);

    a.isfloating = 1;
    c.config.animations = 3;
    arg.ui = c.NUM_TYPE_PLUS;
    arg.i = 20;
    arg.ui2 = 0;
    arg.i2 = 50;
    _ = resize_window(&arg);
    try testing.expectEqual(@as(i32, 320), a.geom.width);
    try testing.expectEqual(@as(i32, 150), a.geom.height);
    try testing.expectEqual(@as(i32, 3), c.config.animations);

    a.isfloating = 0;
    _ = resize_window(&arg);
    try testing.expectEqual(@as(c_int, 1), stub_resize_tile_calls);
    try testing.expectEqual(@as(i32, 20), stub_resize_tile_dx);
    try testing.expectEqual(@as(i32, -50), stub_resize_tile_dy);
    try testing.expectEqual(@as(i32, 3), c.config.animations);
}

test "restore_minimized evicts scratchpads or restores minimized clients" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    var scratch: Client = undefined;
    var focus: Client = undefined;
    var minimized: Client = undefined;
    addClient(&scratch, &m, 1);
    addClient(&focus, &m, 2);
    addClient(&minimized, &m, 4);
    minimized.isminimized = 1;
    scratch.is_in_scratchpad = 1;
    m.sel = &scratch;
    c.server.selected_monitor = &m;

    _ = restore_minimized(&std.mem.zeroes(Arg));
    try testing.expectEqual(@as(i32, 0), scratch.is_in_scratchpad);
    try testing.expectEqual(@as(i32, 0), stub_pending_min_arg);
    try testing.expectEqual(@as(c_int, 0), stub_floating_arg);
    try testing.expect(stub_focus_client == &scratch);
    try testing.expectEqual(@as(c_int, 1), stub_warp_calls);

    resetWorld();
    baseMonitor(&m, &p, &out);
    addClient(&minimized, &m, 4);
    addClient(&focus, &m, 8);
    minimized.isminimized = 1;
    m.sel = &focus;
    c.server.selected_monitor = &m;

    _ = restore_minimized(&std.mem.zeroes(Arg));
    try testing.expectEqual(@as(u32, 8), minimized.tags);
    try testing.expectEqual(@as(u32, 8), minimized.oldtags);
    try testing.expect(stub_focus_client == &minimized);
}

test "set_layout matches by name and set_key_mode updates the key mode" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    c.server.selected_monitor = &m;

    var arg = std.mem.zeroes(Arg);
    arg.v = @ptrCast(@constCast("grid"));
    _ = set_layout(&arg);
    try testing.expect(p.ltidxs[0] == @as([*c]const Layout, @ptrCast(&layouts[2])));
    try testing.expectEqual(@as(c_int, 1), stub_clear_fs_calls);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);
    try testing.expectEqual(@as(c_int, 1), stub_printstatus_calls);

    arg.v = @ptrCast(@constCast("nope"));
    _ = set_layout(&arg);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);

    arg.v = @ptrCast(@constCast("resize"));
    try testing.expectEqual(@as(i32, 1), set_key_mode(&arg));
    try testing.expectEqualStrings("resize", std.mem.sliceTo(&c.server.key_mode.mode, 0));
    try testing.expect(!c.server.key_mode.isdefault);

    arg.v = @ptrCast(@constCast("default"));
    _ = set_key_mode(&arg);
    try testing.expect(c.server.key_mode.isdefault);
    try testing.expectEqual(@as(c_int, 3), stub_printstatus_calls);
}

test "set_proportion and presets update the head node and geometry" {
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
    m.visible_tiling_clients = 2;
    c.server.selected_monitor = &m;
    c.config.scroller_structs = 10;
    c.config.gappih = 5;
    stub_is_scroller = true;
    stub_head_client = &b;
    stub_node_found = true;
    var st: c.TagScrollerState = std.mem.zeroes(c.TagScrollerState);
    m.pertag.*.scroller_state[0] = @ptrCast(&st);

    var arg = std.mem.zeroes(Arg);
    arg.f = 0.6;
    _ = set_proportion(&arg);
    try testing.expectApproxEqAbs(@as(f32, 0.6), stub_node.scroller_proportion, 0.0001);
    try testing.expectApproxEqAbs(@as(f32, 0.6), b.scroller_proportion, 0.0001);
    try testing.expectEqual(@as(i32, 585), b.geom.width);

    c.config.scroller_proportion_preset_count = 3;
    c.config.scroller_proportion_preset = &stub_presets;
    stub_node.scroller_proportion = 0.6;
    arg.i = c.NEXT;
    _ = switch_proportion_preset(&arg);
    try testing.expectApproxEqAbs(@as(f32, 0.8), stub_node.scroller_proportion, 0.0001);
    try testing.expectEqual(@as(i32, 780), b.geom.width);

    stub_node.scroller_proportion = 0.4;
    arg.i = 0;
    _ = switch_proportion_preset(&arg);
    try testing.expectApproxEqAbs(@as(f32, 0.8), stub_node.scroller_proportion, 0.0001);

    stub_node.scroller_proportion = 0.5;
    _ = switch_proportion_preset(&arg);
    try testing.expectApproxEqAbs(@as(f32, 0.4), stub_node.scroller_proportion, 0.0001);
}
