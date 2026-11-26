//! Port of the manual-resize/drag family from src/layout/arrange.c
//! (strangler-fig Phase 4, layout slice 6, slice 34).
//!
//! Covers drag_refresh_interval_ms, set_size_per, the inner weight
//! persistence helper, resize_tile_master_horizontal/vertical,
//! resize_tile_dwindle, resize_tile_grid_fair, resize_tile_scroller and the
//! resize_tile_client dispatcher. C twin guarded with
//! ACWM_ZIG_ARRANGE_RESIZE.
//!
//! Layout arithmetic keeps the C domains: drag deltas are computed in double
//! from the stored (double) ratios and narrowed to float, clamps use float,
//! and grid weights are float.

const std = @import("std");
const c = @import("cc");

const Client = c.Client;
const Monitor = c.Monitor;
const Box = c.struct_wlr_box;
const Node = c.ScrollerStackNode;
const State = c.TagScrollerState;
const WlList = c.struct_wl_list;
const Layout = c.Layout;

extern fn get_mon_curtag(m: *const Monitor) callconv(.c) u32;
extern fn get_client_tag_idx(cl: *const Client) callconv(.c) u32;
extern fn arrange(m: *Monitor, want_animation: bool, from_view: bool) callconv(.c) void;
extern fn dwindle_resize_client(m: *Monitor, cl: *Client) callconv(.c) void;
extern fn dwindle_resize_client_step(m: *Monitor, cl: *Client, dx: i32, dy: i32) callconv(.c) void;
extern fn find_scroller_node(st: ?*State, cl: ?*Client) callconv(.c) ?*Node;
extern fn sync_scroller_state_to_clients(m: *Monitor, tag: u32) callconv(.c) void;

fn containerOf(comptime T: type, comptime link_field: []const u8, link: [*c]WlList) *T {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(T, link_field));
}

fn listHead(head: *WlList) [*c]WlList {
    return @ptrCast(head);
}

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

fn layoutOpt(p: [*c]const Layout) ?*const Layout {
    return if (p == null) null else @ptrCast(p);
}

fn ISTILED(cl: ?*const Client) bool {
    const x = cl orelse return false;
    return x.isfloating == 0 and x.isminimized == 0 and x.iskilling == 0 and
        x.ismaximizescreen == 0 and x.isfullscreen == 0 and x.isunglobal == 0;
}

fn ISFAKETILED(cl: ?*const Client) bool {
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

fn f32i(v: i32) f32 {
    return @floatFromInt(v);
}

fn f64i(v: i32) f64 {
    return @floatFromInt(v);
}

fn clampF32(v: f32, lo: f32, hi: f32) f32 {
    return @min(@max(v, lo), hi);
}

// ---------------------------------------------------------------------------
// frame interval / size setup
// ---------------------------------------------------------------------------

export fn drag_refresh_interval_ms(m: ?*const Monitor) callconv(.c) u32 {
    var refresh_mhz: i32 = 0;
    if (m) |mon| {
        if (mon.wlr_output != null)
            refresh_mhz = mon.wlr_output.*.refresh;
    }
    if (refresh_mhz <= 0)
        refresh_mhz = 60000;

    const ms: i32 = @intFromFloat(1000.0 / (f64i(refresh_mhz) / 1000.0));
    return if (ms > 0) @intCast(ms) else 1;
}

export fn set_size_per(m_in: ?*Monitor, cl_in: ?*Client, reset_proportion: bool) callconv(.c) void {
    const m = m_in orelse return;
    const cl = cl_in orelse return;

    const tag = get_mon_curtag(m);
    const current_layout = layoutOpt(m.pertag.*.ltidxs[@intCast(tag)]);

    const keep_own = !reset_proportion and
        (cl.master_size_weight > 0.0 or cl.stack_size_weight > 0.0);

    cl.master_mfact_per = m.pertag.*.mfacts[@intCast(tag)];
    var pos = c.server.clients.next;
    const head = listHead(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const fc = containerOf(Client, "link", pos);
        if (fc == cl or !VISIBLEON(fc, m) or !ISTILED(fc) or
            fc.master_mfact_per <= 0.0)
            continue;
        if (current_layout != null and current_layout.?.id == c.CENTER_TILE and
            fc.isleftstack != cl.isleftstack)
            continue;
        cl.master_mfact_per = fc.master_mfact_per;
        break;
    }

    if (keep_own) {
        if (cl.iscustom_scroller_proportion == 0 and cl.scroller_proportion <= 0.0)
            cl.scroller_proportion = m.pertag.*.scroller_default_proportion[@intCast(tag)];
        if (cl.iscustom_scroller_proportion_single == 0 and cl.scroller_proportion_single <= 0.0)
            cl.scroller_proportion_single = m.pertag.*.scroller_default_proportion_single[@intCast(tag)];
        return;
    }

    var found = false;
    pos = c.server.clients.next;
    while (pos != head) : (pos = pos.*.next) {
        const fc = containerOf(Client, "link", pos);
        if (VISIBLEON(fc, m) and ISTILED(fc) and fc != cl) {
            if (current_layout != null and current_layout.?.id == c.CENTER_TILE and
                fc.isleftstack != cl.isleftstack)
                continue;
            cl.master_size_weight = fc.master_size_weight;
            cl.stack_size_weight = fc.stack_size_weight;
            found = true;
            break;
        }
    }

    if (!found or cl.master_size_weight <= 0.0 or cl.stack_size_weight <= 0.0) {
        cl.master_size_weight = 1.0;
        cl.stack_size_weight = 1.0;
    }

    cl.master_inner_per = cl.master_size_weight;
    cl.stack_inner_per = cl.stack_size_weight;

    if (cl.iscustom_scroller_proportion == 0)
        cl.scroller_proportion = m.pertag.*.scroller_default_proportion[@intCast(tag)];
    if (cl.iscustom_scroller_proportion_single == 0)
        cl.scroller_proportion_single = m.pertag.*.scroller_default_proportion_single[@intCast(tag)];
}

fn persistTileSizeWeights(m: *Monitor) void {
    var pos = c.server.clients.next;
    const head = listHead(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (!VISIBLEON(cl, m) or !ISFAKETILED(cl))
            continue;
        if (cl.ismaster)
            cl.master_size_weight = cl.master_inner_per
        else
            cl.stack_size_weight = cl.stack_inner_per;
    }
}

fn noteDragStart(cl: *Client) void {
    c.server.drag_begin_cursor_x = @as(i32, @intFromFloat(c.server.cursor.*.x));
    c.server.drag_begin_cursor_y = @as(i32, @intFromFloat(c.server.cursor.*.y));
    c.server.start_drag_window = true;
    cl.old_master_mfact_per = cl.master_mfact_per;
    cl.old_master_inner_per = cl.master_inner_per;
    cl.old_stack_inner_per = cl.stack_inner_per;
    cl.cursor_in_upper_half = c.server.cursor.*.y < f64i(cl.geom.y + @divTrunc(cl.geom.height, 2));
    cl.cursor_in_left_half = c.server.cursor.*.x < f64i(cl.geom.x + @divTrunc(cl.geom.width, 2));
    cl.drag_begin_geom = cl.geom;
}

fn noteKeyboardStart(cl: *Client) void {
    cl.old_master_mfact_per = cl.master_mfact_per;
    cl.old_master_inner_per = cl.master_inner_per;
    cl.old_stack_inner_per = cl.stack_inner_per;
    cl.drag_begin_geom = cl.geom;
    cl.cursor_in_upper_half = true;
    cl.cursor_in_left_half = false;
}

fn maybeArrange(m: *Monitor, isdrag: bool, time: u32) void {
    if (!isdrag) {
        arrange(m, false, false);
        return;
    }
    if (c.server.last_apply_drag_time == 0 or
        time -% @as(u32, @bitCast(c.server.last_apply_drag_time)) >= drag_refresh_interval_ms(m))
    {
        arrange(m, false, false);
        c.server.last_apply_drag_time = @intCast(time);
    }
}

// ---------------------------------------------------------------------------
// master horizontal
// ---------------------------------------------------------------------------

export fn resize_tile_master_horizontal(
    gc_in: ?*Client,
    isdrag: bool,
    offsetx_in: i32,
    offsety_in: i32,
    time: u32,
    layout_type: i32,
) callconv(.c) void {
    const gc = gc_in orelse return;
    const m = monitorOpt(gc.mon) orelse return;
    var offsetx = offsetx_in;
    var offsety = offsety_in;

    var next: ?*Client = null;
    var prev: ?*Client = null;
    var nextnext: ?*Client = null;
    var prevprev: ?*Client = null;

    var begin_find_nextnext = false;
    var node = gc.link.next;
    const head = listHead(&c.server.clients);
    while (node != head) : (node = node.*.next) {
        const tc = containerOf(Client, "link", node);
        if (begin_find_nextnext and VISIBLEON(tc, m) and ISTILED(tc)) {
            nextnext = tc;
            break;
        }
        if (!begin_find_nextnext and VISIBLEON(tc, m) and ISTILED(tc)) {
            next = tc;
            begin_find_nextnext = true;
            continue;
        }
    }

    var begin_find_prevprev = false;
    node = gc.link.prev;
    while (node != head) : (node = node.*.prev) {
        const tc = containerOf(Client, "link", node);
        if (begin_find_prevprev and VISIBLEON(tc, m) and ISTILED(tc)) {
            prevprev = tc;
            break;
        }
        if (!begin_find_prevprev and VISIBLEON(tc, m) and ISTILED(tc)) {
            prev = tc;
            begin_find_prevprev = true;
            continue;
        }
    }

    if (!c.server.start_drag_window and isdrag) {
        noteDragStart(gc);
        return;
    }

    if (isdrag) {
        offsetx = @as(i32, @intFromFloat(c.server.cursor.*.x)) - c.server.drag_begin_cursor_x;
        offsety = @as(i32, @intFromFloat(c.server.cursor.*.y)) - c.server.drag_begin_cursor_y;
    } else {
        noteKeyboardStart(gc);
    }

    var delta_x: f32 = undefined;
    var delta_y: f32 = undefined;
    if (gc.ismaster) {
        delta_x = @floatCast(f64i(offsetx) * gc.old_master_mfact_per / f64i(gc.drag_begin_geom.width));
        delta_y = @floatCast(f64i(offsety) * gc.old_master_inner_per / f64i(gc.drag_begin_geom.height));
    } else {
        delta_x = @floatCast(f64i(offsetx) * (1.0 - gc.old_master_mfact_per) / f64i(gc.drag_begin_geom.width));
        delta_y = @floatCast(f64i(offsety) * gc.old_stack_inner_per / f64i(gc.drag_begin_geom.height));
    }

    const moving_up = if (!isdrag) offsety < 0 else c.server.cursor.*.y < f64i(c.server.drag_begin_cursor_y);
    const moving_down = if (!isdrag) offsety > 0 else c.server.cursor.*.y > f64i(c.server.drag_begin_cursor_y);

    if (gc.ismaster and prev == null) {
        if (moving_up) delta_y = -@abs(delta_y) else delta_y = @abs(delta_y);
    } else if (gc.ismaster and next != null and !next.?.ismaster) {
        if (moving_up) delta_y = @abs(delta_y) else delta_y = -@abs(delta_y);
    } else if (!gc.ismaster and prev != null and prev.?.ismaster) {
        if (moving_up) delta_y = -@abs(delta_y) else delta_y = @abs(delta_y);
    } else if (!gc.ismaster and next == null) {
        if (moving_up) delta_y = @abs(delta_y) else delta_y = -@abs(delta_y);
    } else if (layout_type == c.CENTER_TILE and !gc.ismaster and nextnext == null) {
        if (moving_up) delta_y = @abs(delta_y) else delta_y = -@abs(delta_y);
    } else if (layout_type == c.CENTER_TILE and !gc.ismaster and prevprev != null and
        prevprev.?.ismaster)
    {
        if (moving_up) delta_y = -@abs(delta_y) else delta_y = @abs(delta_y);
    } else if ((gc.cursor_in_upper_half and moving_up) or
        (!gc.cursor_in_upper_half and moving_down))
    {
        delta_y = @abs(delta_y) * 2;
    } else {
        delta_y = -@abs(delta_y) * 2;
    }

    if (!gc.ismaster and gc.isleftstack and layout_type == c.CENTER_TILE)
        delta_x = delta_x * -1.0;
    if (gc.ismaster and layout_type == c.CENTER_TILE and gc.cursor_in_left_half)
        delta_x = delta_x * -1.0;
    if (gc.ismaster and layout_type == c.CENTER_TILE)
        delta_x = delta_x * 2;
    if (layout_type == c.RIGHT_TILE)
        delta_x = delta_x * -1.0;

    var new_master_mfact: f32 = @as(f32, @floatCast(gc.old_master_mfact_per)) + delta_x;
    var new_master_inner: f32 = @as(f32, @floatCast(gc.old_master_inner_per)) + delta_y;
    var new_stack_inner: f32 = @as(f32, @floatCast(gc.old_stack_inner_per)) + delta_y;

    new_master_mfact = clampF32(new_master_mfact, 0.1, 0.9);
    new_master_inner = clampF32(new_master_inner, 0.1, 0.9);
    new_stack_inner = clampF32(new_stack_inner, 0.1, 0.9);

    if (isdrag) {
        if (gc.ismaster) {
            const cur_other_sum: f32 = 1.0 - @as(f32, @floatCast(gc.master_inner_per));
            const new_other_sum: f32 = 1.0 - new_master_inner;
            if (cur_other_sum > 0.001) {
                const scale = new_other_sum / cur_other_sum;
                var tp = c.server.clients.next;
                while (tp != head) : (tp = tp.*.next) {
                    const tc = containerOf(Client, "link", tp);
                    if (VISIBLEON(tc, m) and ISTILED(tc) and tc.ismaster and tc != gc)
                        tc.master_inner_per *= @as(f64, scale);
                }
            }
        } else {
            if (layout_type == c.CENTER_TILE) {
                const cur_other_sum: f32 = 1.0 - @as(f32, @floatCast(gc.stack_inner_per));
                const new_other_sum: f32 = 1.0 - new_stack_inner;
                if (cur_other_sum > 0.001) {
                    const scale = new_other_sum / cur_other_sum;
                    var tp = c.server.clients.next;
                    while (tp != head) : (tp = tp.*.next) {
                        const tc = containerOf(Client, "link", tp);
                        if (VISIBLEON(tc, m) and ISTILED(tc) and !tc.ismaster and tc != gc and
                            tc.isleftstack == gc.isleftstack)
                            tc.stack_inner_per *= @as(f64, scale);
                    }
                }
            } else {
                const cur_other_sum: f32 = 1.0 - @as(f32, @floatCast(gc.stack_inner_per));
                const new_other_sum: f32 = 1.0 - new_stack_inner;
                if (cur_other_sum > 0.001) {
                    const scale = new_other_sum / cur_other_sum;
                    var tp = c.server.clients.next;
                    while (tp != head) : (tp = tp.*.next) {
                        const tc = containerOf(Client, "link", tp);
                        if (VISIBLEON(tc, m) and ISTILED(tc) and !tc.ismaster and tc != gc)
                            tc.stack_inner_per *= @as(f64, scale);
                    }
                }
            }
        }
    } else {
        var tp = c.server.clients.next;
        while (tp != head) : (tp = tp.*.next) {
            const tc = containerOf(Client, "link", tp);
            if (!VISIBLEON(tc, m) or !ISTILED(tc))
                continue;
            if (tc != gc) {
                if (!tc.ismaster and new_stack_inner != 1.0 and gc.old_stack_inner_per != 1.0 and
                    (layout_type != c.CENTER_TILE or
                        gc.isleftstack == tc.isleftstack))
                    tc.stack_inner_per = (1.0 - @as(f64, new_stack_inner)) /
                        (1.0 - gc.old_stack_inner_per) * tc.stack_inner_per;
                if (tc.ismaster and new_master_inner != 1.0 and gc.old_master_inner_per != 1.0)
                    tc.master_inner_per = (1.0 - @as(f64, new_master_inner)) /
                        (1.0 - gc.old_master_inner_per) * tc.master_inner_per;
            }
        }
    }

    gc.master_inner_per = new_master_inner;
    gc.stack_inner_per = new_stack_inner;

    var bp = c.server.clients.next;
    while (bp != head) : (bp = bp.*.next) {
        const tc = containerOf(Client, "link", bp);
        if (VISIBLEON(tc, m) and ISTILED(tc))
            tc.master_mfact_per = new_master_mfact;
    }

    persistTileSizeWeights(m);
    maybeArrange(m, isdrag, time);
}

// ---------------------------------------------------------------------------
// master vertical
// ---------------------------------------------------------------------------

export fn resize_tile_master_vertical(
    gc_in: ?*Client,
    isdrag: bool,
    offsetx_in: i32,
    offsety_in: i32,
    time: u32,
    layout_type: i32,
) callconv(.c) void {
    _ = layout_type;
    const gc = gc_in orelse return;
    const m = monitorOpt(gc.mon) orelse return;
    var offsetx = offsetx_in;
    var offsety = offsety_in;

    var next: ?*Client = null;
    var prev: ?*Client = null;

    var node = gc.link.next;
    const head = listHead(&c.server.clients);
    while (node != head) : (node = node.*.next) {
        const tc = containerOf(Client, "link", node);
        if (VISIBLEON(tc, m) and ISTILED(tc)) {
            next = tc;
            break;
        }
    }

    node = gc.link.prev;
    while (node != head) : (node = node.*.prev) {
        const tc = containerOf(Client, "link", node);
        if (VISIBLEON(tc, m) and ISTILED(tc)) {
            prev = tc;
            break;
        }
    }

    if (!c.server.start_drag_window and isdrag) {
        noteDragStart(gc);
        return;
    }

    if (isdrag) {
        offsetx = @as(i32, @intFromFloat(c.server.cursor.*.x)) - c.server.drag_begin_cursor_x;
        offsety = @as(i32, @intFromFloat(c.server.cursor.*.y)) - c.server.drag_begin_cursor_y;
    } else {
        noteKeyboardStart(gc);
    }

    var delta_x: f32 = undefined;
    var delta_y: f32 = undefined;
    if (gc.ismaster) {
        delta_x = @floatCast(f64i(offsetx) * gc.old_master_inner_per / f64i(gc.drag_begin_geom.width));
        delta_y = @floatCast(f64i(offsety) * gc.old_master_mfact_per / f64i(gc.drag_begin_geom.height));
    } else {
        delta_x = @floatCast(f64i(offsetx) * gc.old_stack_inner_per / f64i(gc.drag_begin_geom.width));
        delta_y = @floatCast(f64i(offsety) * (1.0 - gc.old_master_mfact_per) / f64i(gc.drag_begin_geom.height));
    }

    const moving_left = if (!isdrag) offsetx < 0 else c.server.cursor.*.x < f64i(c.server.drag_begin_cursor_x);
    const moving_right = if (!isdrag) offsetx > 0 else c.server.cursor.*.x > f64i(c.server.drag_begin_cursor_x);

    if (gc.ismaster and prev == null) {
        if (moving_left) delta_x = -@abs(delta_x) else delta_x = @abs(delta_x);
    } else if (gc.ismaster and next != null and !next.?.ismaster) {
        if (moving_left) delta_x = @abs(delta_x) else delta_x = -@abs(delta_x);
    } else if (!gc.ismaster and prev != null and prev.?.ismaster) {
        if (moving_left) delta_x = -@abs(delta_x) else delta_x = @abs(delta_x);
    } else if (!gc.ismaster and next == null) {
        if (moving_left) delta_x = @abs(delta_x) else delta_x = -@abs(delta_x);
    } else if ((gc.cursor_in_left_half and moving_left) or
        (!gc.cursor_in_left_half and moving_right))
    {
        delta_x = @abs(delta_x) * 2;
    } else {
        delta_x = -@abs(delta_x) * 2;
    }

    var new_master_mfact: f32 = @as(f32, @floatCast(gc.old_master_mfact_per)) + delta_y;
    var new_master_inner: f32 = @as(f32, @floatCast(gc.old_master_inner_per)) + delta_x;
    var new_stack_inner: f32 = @as(f32, @floatCast(gc.old_stack_inner_per)) + delta_x;

    new_master_mfact = clampF32(new_master_mfact, 0.1, 0.9);
    new_master_inner = clampF32(new_master_inner, 0.1, 0.9);
    new_stack_inner = clampF32(new_stack_inner, 0.1, 0.9);

    if (isdrag) {
        if (gc.ismaster) {
            const cur_other_sum: f32 = 1.0 - @as(f32, @floatCast(gc.master_inner_per));
            const new_other_sum: f32 = 1.0 - new_master_inner;
            if (cur_other_sum > 0.001) {
                const scale = new_other_sum / cur_other_sum;
                var tp = c.server.clients.next;
                while (tp != head) : (tp = tp.*.next) {
                    const tc = containerOf(Client, "link", tp);
                    if (VISIBLEON(tc, m) and ISTILED(tc) and tc.ismaster and tc != gc)
                        tc.master_inner_per *= @as(f64, scale);
                }
            }
        } else {
            const cur_other_sum: f32 = 1.0 - @as(f32, @floatCast(gc.stack_inner_per));
            const new_other_sum: f32 = 1.0 - new_stack_inner;
            if (cur_other_sum > 0.001) {
                const scale = new_other_sum / cur_other_sum;
                var tp = c.server.clients.next;
                while (tp != head) : (tp = tp.*.next) {
                    const tc = containerOf(Client, "link", tp);
                    if (VISIBLEON(tc, m) and ISTILED(tc) and !tc.ismaster and tc != gc)
                        tc.stack_inner_per *= @as(f64, scale);
                }
            }
        }
    } else {
        var tp = c.server.clients.next;
        while (tp != head) : (tp = tp.*.next) {
            const tc = containerOf(Client, "link", tp);
            if (!VISIBLEON(tc, m) or !ISTILED(tc))
                continue;
            if (tc != gc) {
                if (!tc.ismaster and new_stack_inner != 1.0 and gc.old_stack_inner_per != 1.0)
                    tc.stack_inner_per = (1.0 - @as(f64, new_stack_inner)) /
                        (1.0 - gc.old_stack_inner_per) * tc.stack_inner_per;
                if (tc.ismaster and new_master_inner != 1.0 and gc.old_master_inner_per != 1.0)
                    tc.master_inner_per = (1.0 - @as(f64, new_master_inner)) /
                        (1.0 - gc.old_master_inner_per) * tc.master_inner_per;
            }
        }
    }

    gc.master_inner_per = new_master_inner;
    gc.stack_inner_per = new_stack_inner;

    var bp = c.server.clients.next;
    while (bp != head) : (bp = bp.*.next) {
        const tc = containerOf(Client, "link", bp);
        if (VISIBLEON(tc, m) and ISTILED(tc))
            tc.master_mfact_per = new_master_mfact;
    }

    persistTileSizeWeights(m);
    maybeArrange(m, isdrag, time);
}

// ---------------------------------------------------------------------------
// dwindle
// ---------------------------------------------------------------------------

export fn resize_tile_dwindle(
    gc_in: ?*Client,
    isdrag: bool,
    offsetx: i32,
    offsety: i32,
    time: u32,
    isvertical: bool,
) callconv(.c) void {
    _ = isvertical;
    const gc = gc_in orelse return;
    const m = monitorOpt(gc.mon) orelse return;

    if (!isdrag) {
        dwindle_resize_client_step(m, gc, offsetx, offsety);
        return;
    }
    if (c.server.last_apply_drag_time == 0 or
        time -% @as(u32, @bitCast(c.server.last_apply_drag_time)) >= drag_refresh_interval_ms(m))
    {
        dwindle_resize_client(m, gc);
        c.server.last_apply_drag_time = @intCast(time);
    }
}

// ---------------------------------------------------------------------------
// grid / fair
// ---------------------------------------------------------------------------

export fn resize_tile_grid_fair(
    gc_in: ?*Client,
    isdrag: bool,
    offsetx_in: i32,
    offsety_in: i32,
    time: u32,
) callconv(.c) void {
    const gc = gc_in orelse return;
    if (gc.isfullscreen != 0 or gc.ismaximizescreen != 0)
        return;
    const m = monitorOpt(gc.mon) orelse return;
    if (m.isoverview != 0)
        return;
    if (m.visible_tiling_clients <= 1)
        return;

    const current_layout = layoutOpt(m.pertag.*.ltidxs[@intCast(get_mon_curtag(m))]);
    var offsetx = offsetx_in;
    var offsety = offsety_in;

    const head = listHead(&c.server.clients);

    if (!c.server.start_drag_window and isdrag) {
        c.server.drag_begin_cursor_x = @as(i32, @intFromFloat(c.server.cursor.*.x));
        c.server.drag_begin_cursor_y = @as(i32, @intFromFloat(c.server.cursor.*.y));
        c.server.start_drag_window = true;

        var tp = c.server.clients.next;
        while (tp != head) : (tp = tp.*.next) {
            const cl = containerOf(Client, "link", tp);
            cl.old_grid_col_per = if (cl.grid_col_per > 0.0) cl.grid_col_per else 1.0;
            cl.old_grid_row_per = if (cl.grid_row_per > 0.0) cl.grid_row_per else 1.0;
        }
        gc.old_grid_col_per = gc.grid_col_per;
        gc.old_grid_row_per = gc.grid_row_per;
        gc.cursor_in_left_half = c.server.cursor.*.x < f64i(gc.geom.x + @divTrunc(gc.geom.width, 2));
        gc.cursor_in_upper_half = c.server.cursor.*.y < f64i(gc.geom.y + @divTrunc(gc.geom.height, 2));
        gc.drag_begin_geom = gc.geom;
        return;
    }

    if (isdrag) {
        offsetx = @as(i32, @intFromFloat(c.server.cursor.*.x)) - c.server.drag_begin_cursor_x;
        offsety = @as(i32, @intFromFloat(c.server.cursor.*.y)) - c.server.drag_begin_cursor_y;
    } else {
        gc.drag_begin_geom = gc.geom;
        var tp = c.server.clients.next;
        while (tp != head) : (tp = tp.*.next) {
            const cl = containerOf(Client, "link", tp);
            cl.old_grid_col_per = if (cl.grid_col_per > 0.0) cl.grid_col_per else 1.0;
            cl.old_grid_row_per = if (cl.grid_row_per > 0.0) cl.grid_row_per else 1.0;
        }
        gc.cursor_in_upper_half = false;
        gc.cursor_in_left_half = false;
    }

    const delta_x: f32 = f32i(offsetx) * gc.old_grid_col_per / f32i(gc.drag_begin_geom.width);
    const delta_y: f32 = f32i(offsety) * gc.old_grid_row_per / f32i(gc.drag_begin_geom.height);

    var max_col: i32 = -1;
    var max_row: i32 = -1;
    var min_col: i32 = std.math.maxInt(i32);
    var min_row: i32 = std.math.maxInt(i32);
    var tp = c.server.clients.next;
    while (tp != head) : (tp = tp.*.next) {
        const cl = containerOf(Client, "link", tp);
        if (cl.mon != @as([*c]Monitor, @ptrCast(m)) or !VISIBLEON(cl, m) or !ISTILED(cl))
            continue;
        if (cl.grid_col_idx > max_col) max_col = cl.grid_col_idx;
        if (cl.grid_row_idx > max_row) max_row = cl.grid_row_idx;
        if (cl.grid_col_idx < min_col) min_col = cl.grid_col_idx;
        if (cl.grid_row_idx < min_row) min_row = cl.grid_row_idx;
    }

    var adj_c_idx: i32 = gc.grid_col_idx + 1;
    var adj_r_idx: i32 = gc.grid_row_idx + 1;
    var sign_x: f32 = 1.0;
    var sign_y: f32 = 1.0;

    if (gc.grid_col_idx == max_col) {
        adj_c_idx = gc.grid_col_idx - 1;
        sign_x = -1.0;
    }
    if (gc.grid_row_idx == max_row) {
        adj_r_idx = gc.grid_row_idx - 1;
        sign_y = -1.0;
    }
    if (gc.grid_col_idx == min_col) {
        adj_c_idx = gc.grid_col_idx + 1;
        sign_x = 1.0;
    }
    if (gc.grid_row_idx == min_row) {
        adj_r_idx = gc.grid_row_idx + 1;
        sign_y = 1.0;
    }

    const dx = delta_x * sign_x;
    const dy = delta_y * sign_y;

    const my_old_col = gc.old_grid_col_per;
    const my_old_row = gc.old_grid_row_per;
    var adj_old_col: f32 = -1.0;
    var adj_old_row: f32 = -1.0;

    tp = c.server.clients.next;
    while (tp != head) : (tp = tp.*.next) {
        const cl = containerOf(Client, "link", tp);
        if (cl.mon != @as([*c]Monitor, @ptrCast(m)) or !VISIBLEON(cl, m) or !ISTILED(cl))
            continue;
        if (cl.grid_col_idx == adj_c_idx and adj_old_col < 0)
            adj_old_col = cl.old_grid_col_per;
        if (cl.grid_row_idx == adj_r_idx and adj_old_row < 0)
            adj_old_row = cl.old_grid_row_per;
    }

    if (adj_old_col > 0.0) {
        var dx_clamped = dx;
        if (my_old_col + dx_clamped < 0.1)
            dx_clamped = 0.1 - my_old_col;
        if (adj_old_col - dx_clamped < 0.1)
            dx_clamped = adj_old_col - 0.1;

        var new_my_col = my_old_col + dx_clamped;
        var new_adj_col = adj_old_col - dx_clamped;

        if (current_layout != null and current_layout.?.id == c.VERTICAL_FAIR) {
            const n_tiling: i32 = @intCast(m.visible_tiling_clients);
            var l_rows: i32 = 0;
            while (l_rows <= n_tiling) : (l_rows += 1) {
                if (l_rows * l_rows >= n_tiling)
                    break;
            }
            const base_cols = @divTrunc(n_tiling, l_rows);
            if ((gc.grid_col_idx == base_cols - 1 and adj_c_idx == base_cols) or
                (gc.grid_col_idx == base_cols and adj_c_idx == base_cols - 1))
            {
                var p_col: f32 = if (gc.grid_col_idx == base_cols - 1)
                    (my_old_col + dx) / (my_old_col + adj_old_col)
                else
                    (adj_old_col - dx) / (my_old_col + adj_old_col);
                if (p_col < 0.01) p_col = 0.01;
                if (p_col > 0.99) p_col = 0.99;

                var new_r_var_per = p_col / (1.0 - p_col);
                if (new_r_var_per < 0.1) new_r_var_per = 0.1;
                if (new_r_var_per > 10.0) new_r_var_per = 10.0;

                if (gc.grid_col_idx == base_cols - 1) {
                    new_my_col = new_r_var_per;
                    new_adj_col = 1.0;
                } else {
                    new_my_col = 1.0;
                    new_adj_col = new_r_var_per;
                }
            }
        }

        var ap = c.server.clients.next;
        while (ap != head) : (ap = ap.*.next) {
            const cl = containerOf(Client, "link", ap);
            if (cl.mon != @as([*c]Monitor, @ptrCast(m)) or !VISIBLEON(cl, m) or !ISTILED(cl))
                continue;
            if (cl.grid_col_idx == gc.grid_col_idx)
                cl.grid_col_per = new_my_col;
            if (cl.grid_col_idx == adj_c_idx)
                cl.grid_col_per = new_adj_col;
        }

        ap = c.server.clients.next;
        while (ap != head) : (ap = ap.*.next) {
            const cl = containerOf(Client, "link", ap);
            if (cl.mon != @as([*c]Monitor, @ptrCast(m)) or !VISIBLEON(cl, m) or !ISTILED(cl))
                continue;
            if (cl.grid_row_idx == 0) {
                if (cl.grid_col_idx == gc.grid_col_idx)
                    cl.grid_col_per = new_my_col
                else if (cl.grid_col_idx == adj_c_idx)
                    cl.grid_col_per = new_adj_col;
            }
        }
    }

    if (adj_old_row > 0.0) {
        var dy_clamped = dy;
        if (my_old_row + dy_clamped < 0.1)
            dy_clamped = 0.1 - my_old_row;
        if (adj_old_row - dy_clamped < 0.1)
            dy_clamped = adj_old_row - 0.1;

        var new_my_row = my_old_row + dy_clamped;
        var new_adj_row = adj_old_row - dy_clamped;

        if (current_layout != null and current_layout.?.id == c.FAIR) {
            const n_tiling: i32 = @intCast(m.visible_tiling_clients);
            var l_cols: i32 = 0;
            while (l_cols <= n_tiling) : (l_cols += 1) {
                if (l_cols * l_cols >= n_tiling)
                    break;
            }
            const base_rows = @divTrunc(n_tiling, l_cols);
            if ((gc.grid_row_idx == base_rows - 1 and adj_r_idx == base_rows) or
                (gc.grid_row_idx == base_rows and adj_r_idx == base_rows - 1))
            {
                var p_row: f32 = if (gc.grid_row_idx == base_rows - 1)
                    (my_old_row + dy) / (my_old_row + adj_old_row)
                else
                    (adj_old_row - dy) / (my_old_row + adj_old_row);
                if (p_row < 0.01) p_row = 0.01;
                if (p_row > 0.99) p_row = 0.99;

                var new_r_var_per = p_row / (1.0 - p_row);
                if (new_r_var_per < 0.1) new_r_var_per = 0.1;
                if (new_r_var_per > 10.0) new_r_var_per = 10.0;

                if (gc.grid_row_idx == base_rows - 1) {
                    new_my_row = new_r_var_per;
                    new_adj_row = 1.0;
                } else {
                    new_my_row = 1.0;
                    new_adj_row = new_r_var_per;
                }
            }
        }

        var ap = c.server.clients.next;
        while (ap != head) : (ap = ap.*.next) {
            const cl = containerOf(Client, "link", ap);
            if (cl.mon != @as([*c]Monitor, @ptrCast(m)) or !VISIBLEON(cl, m) or !ISTILED(cl))
                continue;
            if (cl.grid_row_idx == gc.grid_row_idx)
                cl.grid_row_per = new_my_row;
            if (cl.grid_row_idx == adj_r_idx)
                cl.grid_row_per = new_adj_row;
        }

        ap = c.server.clients.next;
        while (ap != head) : (ap = ap.*.next) {
            const cl = containerOf(Client, "link", ap);
            if (cl.mon != @as([*c]Monitor, @ptrCast(m)) or !VISIBLEON(cl, m) or !ISTILED(cl))
                continue;
            if (cl.grid_col_idx == 0) {
                if (cl.grid_row_idx == gc.grid_row_idx)
                    cl.grid_row_per = new_my_row
                else if (cl.grid_row_idx == adj_r_idx)
                    cl.grid_row_per = new_adj_row;
            }
        }
    }

    maybeArrange(m, isdrag, time);
}

// ---------------------------------------------------------------------------
// scroller
// ---------------------------------------------------------------------------

export fn resize_tile_scroller(
    gc_in: ?*Client,
    isdrag: bool,
    offsetx_in: i32,
    offsety_in: i32,
    time: u32,
    isvertical: bool,
) callconv(.c) void {
    const gc = gc_in orelse return;
    if (gc.isfullscreen != 0 or gc.ismaximizescreen != 0)
        return;
    const m = monitorOpt(gc.mon) orelse return;
    if (m.isoverview != 0)
        return;

    const tag = get_client_tag_idx(gc);
    const st = stateOpt(m.pertag.*.scroller_state[@intCast(tag)]) orelse return;
    const curnode = find_scroller_node(st, gc) orelse return;

    var headnode = curnode;
    while (headnode.prev_in_stack != null)
        headnode = nodeOpt(headnode.prev_in_stack).?;

    const stack_head_client = clientOpt(headnode.client) orelse return;
    var offsetx = offsetx_in;
    var offsety = offsety_in;

    if (!c.server.start_drag_window and isdrag) {
        c.server.drag_begin_cursor_x = @as(i32, @intFromFloat(c.server.cursor.*.x));
        c.server.drag_begin_cursor_y = @as(i32, @intFromFloat(c.server.cursor.*.y));
        c.server.start_drag_window = true;

        stack_head_client.old_scroller_pproportion = @floatCast(headnode.scroller_proportion);
        gc.scroller_old_stack_proportion = curnode.scroller_stack_proportion;
        gc.cursor_in_left_half = c.server.cursor.*.x < f64i(gc.geom.x + @divTrunc(gc.geom.width, 2));
        gc.cursor_in_upper_half = c.server.cursor.*.y < f64i(gc.geom.y + @divTrunc(gc.geom.height, 2));
        gc.drag_begin_geom = gc.geom;
        return;
    }

    if (isdrag) {
        offsetx = @as(i32, @intFromFloat(c.server.cursor.*.x)) - c.server.drag_begin_cursor_x;
        offsety = @as(i32, @intFromFloat(c.server.cursor.*.y)) - c.server.drag_begin_cursor_y;
    } else {
        gc.old_master_mfact_per = gc.master_mfact_per;
        gc.old_master_inner_per = gc.master_inner_per;
        gc.old_stack_inner_per = gc.stack_inner_per;
        gc.drag_begin_geom = gc.geom;
        stack_head_client.old_scroller_pproportion = @floatCast(headnode.scroller_proportion);
        gc.scroller_old_stack_proportion = curnode.scroller_stack_proportion;
        gc.cursor_in_upper_half = false;
        gc.cursor_in_left_half = false;
    }

    var delta_x: f32 = undefined;
    var delta_y: f32 = undefined;
    if (isvertical) {
        delta_y = @floatCast(f64i(offsety) * stack_head_client.old_scroller_pproportion / f64i(gc.drag_begin_geom.height));
        delta_x = f32i(offsetx) * gc.scroller_old_stack_proportion / f32i(gc.drag_begin_geom.width);
    } else {
        delta_x = @floatCast(f64i(offsetx) * stack_head_client.old_scroller_pproportion / f64i(gc.drag_begin_geom.width));
        delta_y = f32i(offsety) * gc.scroller_old_stack_proportion / f32i(gc.drag_begin_geom.height);
    }

    const moving_up = if (!isdrag) offsety < 0 else c.server.cursor.*.y < f64i(c.server.drag_begin_cursor_y);
    const moving_down = if (!isdrag) offsety > 0 else c.server.cursor.*.y > f64i(c.server.drag_begin_cursor_y);
    const moving_left = if (!isdrag) offsetx < 0 else c.server.cursor.*.x < f64i(c.server.drag_begin_cursor_x);
    const moving_right = if (!isdrag) offsetx > 0 else c.server.cursor.*.x > f64i(c.server.drag_begin_cursor_x);

    if ((gc.cursor_in_upper_half and moving_up) or
        (!gc.cursor_in_upper_half and moving_down))
        delta_y = @abs(delta_y)
    else
        delta_y = -@abs(delta_y);

    if ((gc.cursor_in_left_half and moving_left) or
        (!gc.cursor_in_left_half and moving_right))
        delta_x = @abs(delta_x)
    else
        delta_x = -@abs(delta_x);

    if (isvertical) {
        if (curnode.next_in_stack == null and curnode.prev_in_stack != null and !isdrag)
            delta_x = delta_x * -1.0;
        if (curnode.next_in_stack == null and curnode.prev_in_stack != null and isdrag) {
            if (moving_right) delta_x = -@abs(delta_x) else delta_x = @abs(delta_x);
        }
        if (curnode.prev_in_stack == null and curnode.next_in_stack != null and isdrag) {
            if (moving_left) delta_x = -@abs(delta_x) else delta_x = @abs(delta_x);
        }
        if (isdrag) {
            if (moving_up) delta_y = -@abs(delta_y) else delta_y = @abs(delta_y);
        }
    } else {
        if (curnode.next_in_stack == null and curnode.prev_in_stack != null and !isdrag)
            delta_y = delta_y * -1.0;
        if (curnode.next_in_stack == null and curnode.prev_in_stack != null and isdrag) {
            if (moving_down) delta_y = -@abs(delta_y) else delta_y = @abs(delta_y);
        }
        if (curnode.prev_in_stack == null and curnode.next_in_stack != null and isdrag) {
            if (moving_up) delta_y = -@abs(delta_y) else delta_y = @abs(delta_y);
        }
        if (isdrag) {
            if (moving_left) delta_x = -@abs(delta_x) else delta_x = @abs(delta_x);
        }
    }

    var new_scroller: f32 = undefined;
    var new_stack: f32 = undefined;
    if (isvertical) {
        new_scroller = @floatCast(stack_head_client.old_scroller_pproportion + @as(f64, delta_y));
        new_stack = gc.scroller_old_stack_proportion + delta_x;
    } else {
        new_scroller = @floatCast(stack_head_client.old_scroller_pproportion + @as(f64, delta_x));
        new_stack = gc.scroller_old_stack_proportion + delta_y;
    }

    new_scroller = clampF32(new_scroller, 0.1, 1.0);
    new_stack = clampF32(new_stack, 0.1, 0.9);

    if (isdrag) {
        const current_other_sum: f32 = 1.0 - curnode.scroller_stack_proportion;
        const new_other_sum: f32 = 1.0 - new_stack;
        if (current_other_sum > 0.001) {
            const scale = new_other_sum / current_other_sum;
            var tn: ?*Node = headnode;
            while (tn) |node| : (tn = nodeOpt(node.next_in_stack)) {
                if (node != curnode)
                    node.scroller_stack_proportion *= scale;
            }
        }
    } else {
        if (gc.scroller_old_stack_proportion != 1.0) {
            var tn: ?*Node = headnode;
            while (tn) |node| : (tn = nodeOpt(node.next_in_stack)) {
                if (node != curnode)
                    node.scroller_stack_proportion = (1.0 - new_stack) /
                        (1.0 - gc.scroller_old_stack_proportion) *
                        node.scroller_stack_proportion;
            }
        }
    }

    curnode.scroller_stack_proportion = new_stack;

    if (m.visible_scroll_tiling_clients > 1 or c.config.scroller_ignore_proportion_single != 0)
        headnode.scroller_proportion = new_scroller;

    var sn: ?*Node = headnode;
    while (sn) |node| : (sn = nodeOpt(node.next_in_stack))
        node.scroller_stack_weight = node.scroller_stack_proportion;

    sync_scroller_state_to_clients(m, tag);
    maybeArrange(m, isdrag, time);
}

// ---------------------------------------------------------------------------
// dispatcher
// ---------------------------------------------------------------------------

export fn resize_tile_client(
    gc_in: ?*Client,
    isdrag: bool,
    offsetx: i32,
    offsety: i32,
    time: u32,
) callconv(.c) void {
    const gc = gc_in orelse return;
    if (gc.isfullscreen != 0 or gc.ismaximizescreen != 0)
        return;
    const m = monitorOpt(gc.mon) orelse return;
    if (m.isoverview != 0)
        return;

    const current_layout = layoutOpt(m.pertag.*.ltidxs[@intCast(get_client_tag_idx(gc))]) orelse return;
    const id = current_layout.id;

    if (id == c.TILE or id == c.DECK or id == c.CENTER_TILE or id == c.RIGHT_TILE) {
        resize_tile_master_horizontal(gc, isdrag, offsetx, offsety, time, @intCast(id));
    } else if (id == c.VERTICAL_TILE or id == c.VERTICAL_DECK) {
        resize_tile_master_vertical(gc, isdrag, offsetx, offsety, time, @intCast(id));
    } else if (id == c.SCROLLER) {
        resize_tile_scroller(gc, isdrag, offsetx, offsety, time, false);
    } else if (id == c.VERTICAL_SCROLLER) {
        resize_tile_scroller(gc, isdrag, offsetx, offsety, time, true);
    } else if (id == c.DWINDLE) {
        resize_tile_dwindle(gc, isdrag, offsetx, offsety, time, true);
    } else if (id == c.GRID or id == c.VERTICAL_GRID or id == c.FAIR or id == c.VERTICAL_FAIR) {
        resize_tile_grid_fair(gc, isdrag, offsetx, offsety, time);
    }
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/layout_resize_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_cursor: c.struct_wlr_cursor;
extern var stub_scroller_state: c.TagScrollerState;
extern var stub_curtag: c_int;
extern var stub_client_tag: c_int;
extern var stub_arrange_calls: c_int;
extern var stub_dwindle_calls: c_int;
extern var stub_dwindle_step_calls: c_int;
extern var stub_last_dx: c_int;
extern var stub_last_dy: c_int;
extern var stub_sync_calls: c_int;

extern fn stub_node_new(st: *c.TagScrollerState, cl: *c.Client, prop: f32, stack_prop: f32) ?*Node;
extern fn stub_node_link(a: *Node, b: *Node) void;

var test_layout: c.Layout = undefined;

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
    c.server.start_drag_window = false;
    c.server.last_apply_drag_time = 0;
    c.server.cursor = @ptrCast(&stub_cursor);
    stub_cursor.x = 0;
    stub_cursor.y = 0;
    stub_curtag = 0;
    stub_client_tag = 0;
    stub_arrange_calls = 0;
    stub_dwindle_calls = 0;
    stub_dwindle_step_calls = 0;
    stub_last_dx = 0;
    stub_last_dy = 0;
    stub_sync_calls = 0;
    stub_scroller_state = std.mem.zeroes(c.TagScrollerState);
    test_layout = std.mem.zeroes(c.Layout);
}

fn baseMonitor(m: *Monitor, p: *c.Pertag) void {
    m.* = std.mem.zeroes(Monitor);
    p.* = std.mem.zeroes(c.Pertag);
    m.pertag = p;
    m.w = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
    m.m = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
    m.tagset[0] = 1;
    m.seltags = 0;
    p.nmasters[0] = 1;
    p.mfacts[0] = 0.6;
    test_layout.id = @intCast(c.TILE);
    p.ltidxs[0] = @ptrCast(&test_layout);
    p.config_ltidxs[0] = @ptrCast(&test_layout);
}

fn setLayout(m: *Monitor, id: c_int) void {
    test_layout.id = @intCast(id);
    m.pertag.*.ltidxs[0] = @ptrCast(&test_layout);
}

fn addClient(cl: *Client, m: *Monitor, tags: u32) void {
    cl.* = std.mem.zeroes(Client);
    cl.mon = @ptrCast(m);
    cl.tags = tags;
    listInsert(&c.server.clients, &cl.link);
}

fn approx(expected: f32, actual: f32) !void {
    try testing.expectApproxEqAbs(expected, actual, 0.0001);
}

fn approxD(expected: f64, actual: f64) !void {
    try testing.expectApproxEqAbs(expected, actual, 0.0001);
}

test "drag_refresh_interval_ms derives the frame interval from refresh" {
    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    var m: Monitor = std.mem.zeroes(Monitor);
    m.wlr_output = @ptrCast(&out);

    out.refresh = 144000;
    try testing.expectEqual(@as(u32, 6), drag_refresh_interval_ms(&m));
    out.refresh = 60000;
    try testing.expectEqual(@as(u32, 16), drag_refresh_interval_ms(&m));
    out.refresh = 0;
    try testing.expectEqual(@as(u32, 16), drag_refresh_interval_ms(&m));
    try testing.expectEqual(@as(u32, 16), drag_refresh_interval_ms(null));
}

test "set_size_per copies neighbour weights and fills scroller defaults" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    p.scroller_default_proportion[0] = 0.7;
    p.scroller_default_proportion_single[0] = 0.4;

    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);
    b.master_mfact_per = 0.55;
    b.master_size_weight = 2.0;
    b.stack_size_weight = 3.0;

    set_size_per(&m, &a, false);

    try approxD(0.55, a.master_mfact_per);
    try approxD(2.0, a.master_size_weight);
    try approxD(3.0, a.stack_size_weight);
    try approxD(2.0, a.master_inner_per);
    try approxD(3.0, a.stack_inner_per);
    try approx(0.7, a.scroller_proportion);
    try approx(0.4, a.scroller_proportion_single);

    // custom scroller proportions survive a reset; weights still refresh
    a.iscustom_scroller_proportion = 1;
    a.iscustom_scroller_proportion_single = 1;
    a.scroller_proportion = 0.9;
    a.scroller_proportion_single = 0.8;
    a.master_size_weight = 0.0;
    a.stack_size_weight = 0.0;
    set_size_per(&m, &a, true);
    try approxD(2.0, a.master_size_weight);
    try approxD(3.0, a.stack_size_weight);
    try approx(0.9, a.scroller_proportion);
    try approx(0.8, a.scroller_proportion_single);

    // lone client falls back to unit weights
    resetWorld();
    baseMonitor(&m, &p);
    var lone: Client = undefined;
    addClient(&lone, &m, 1);
    set_size_per(&m, &lone, false);
    try approxD(1.0, lone.master_size_weight);
    try approxD(1.0, lone.stack_size_weight);
}

test "resize_tile_master_horizontal applies keyboard deltas" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    setLayout(&m, c.TILE);

    var gc: Client = undefined;
    addClient(&gc, &m, 1);
    gc.ismaster = true;
    gc.master_mfact_per = 0.5;
    gc.master_inner_per = 0.5;
    gc.stack_inner_per = 0.5;
    gc.geom = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };

    resize_tile_master_horizontal(&gc, false, 50, 0, 0, c.TILE);

    try approx(0.525, @floatCast(gc.master_mfact_per));
    try approx(0.5, @floatCast(gc.master_inner_per));
    try approx(0.5, @floatCast(gc.stack_inner_per));
    try approxD(0.5, gc.master_size_weight);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);
}

test "resize_tile_master_vertical applies keyboard deltas" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    setLayout(&m, c.VERTICAL_TILE);

    var gc: Client = undefined;
    addClient(&gc, &m, 1);
    gc.ismaster = true;
    gc.master_mfact_per = 0.5;
    gc.master_inner_per = 0.5;
    gc.stack_inner_per = 0.5;
    gc.geom = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };

    resize_tile_master_vertical(&gc, false, 50, 0, 0, c.VERTICAL_TILE);

    try approx(0.5, @floatCast(gc.master_mfact_per));
    try approx(0.525, @floatCast(gc.master_inner_per));
    try approx(0.525, @floatCast(gc.stack_inner_per));
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);
}

test "master drag captures the initial ratio and throttles arrange" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    setLayout(&m, c.TILE);

    var gc: Client = undefined;
    addClient(&gc, &m, 1);
    gc.ismaster = true;
    gc.master_mfact_per = 0.5;
    gc.master_inner_per = 0.5;
    gc.stack_inner_per = 0.5;
    gc.geom = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };

    stub_cursor.x = 100;
    stub_cursor.y = 100;
    resize_tile_master_horizontal(&gc, true, 0, 0, 0, c.TILE);
    try testing.expect(c.server.start_drag_window);
    try testing.expectEqual(@as(i32, 100), c.server.drag_begin_cursor_x);
    try approxD(0.5, gc.old_master_mfact_per);
    try testing.expectEqual(@as(c_int, 0), stub_arrange_calls);

    stub_cursor.x = 150;
    resize_tile_master_horizontal(&gc, true, 0, 0, 10, c.TILE);
    try approx(0.525, @floatCast(gc.master_mfact_per));
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);
    try testing.expectEqual(@as(i32, 10), c.server.last_apply_drag_time);
}

test "resize_tile_grid_fair adjusts both adjacent column weights" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    setLayout(&m, c.GRID);
    m.visible_tiling_clients = 2;

    var gc: Client = undefined;
    var other: Client = undefined;
    addClient(&gc, &m, 1);
    addClient(&other, &m, 1);
    gc.grid_col_idx = 0;
    gc.grid_row_idx = 0;
    gc.grid_col_per = 1.0;
    gc.grid_row_per = 1.0;
    gc.geom = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
    other.grid_col_idx = 1;
    other.grid_row_idx = 0;
    other.grid_col_per = 1.0;
    other.grid_row_per = 1.0;

    resize_tile_grid_fair(&gc, false, 100, 0, 0);

    try approx(1.1, gc.grid_col_per);
    try approx(0.9, other.grid_col_per);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);
}

test "resize_tile_client dispatches by layout id" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    setLayout(&m, c.DWINDLE);

    var gc: Client = undefined;
    addClient(&gc, &m, 1);
    gc.geom = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };

    resize_tile_client(&gc, false, 10, 20, 0);
    try testing.expectEqual(@as(c_int, 1), stub_dwindle_step_calls);
    try testing.expectEqual(@as(c_int, 10), stub_last_dx);
    try testing.expectEqual(@as(c_int, 20), stub_last_dy);
    try testing.expectEqual(@as(c_int, 0), stub_arrange_calls);

    resize_tile_client(&gc, true, 0, 0, 7);
    try testing.expectEqual(@as(c_int, 1), stub_dwindle_calls);
    try testing.expectEqual(@as(i32, 7), c.server.last_apply_drag_time);

    gc.isfullscreen = 1;
    resize_tile_client(&gc, false, 0, 0, 0);
    try testing.expectEqual(@as(c_int, 1), stub_dwindle_step_calls);
}

test "resize_tile_scroller keyboard adjusts stack and head proportions" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    setLayout(&m, c.SCROLLER);

    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);
    b.geom = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };

    m.pertag.*.scroller_state[0] = @ptrCast(&stub_scroller_state);
    const head = stub_node_new(&stub_scroller_state, &a, 0.5, 0.5).?;
    const curnode = stub_node_new(&stub_scroller_state, &b, 0.5, 0.5).?;
    stub_node_link(head, curnode);
    m.visible_scroll_tiling_clients = 2;

    resize_tile_scroller(&b, false, 100, 0, 0, false);

    try approx(0.55, head.scroller_proportion);
    try approx(0.5, curnode.scroller_stack_proportion);
    try approx(0.5, head.scroller_stack_weight);
    try approx(0.5, curnode.scroller_stack_weight);
    try testing.expectEqual(@as(c_int, 1), stub_sync_calls);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);
}

test "scroller drag captures state and applies cursor movement" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    setLayout(&m, c.SCROLLER);

    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);
    b.geom = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };

    m.pertag.*.scroller_state[0] = @ptrCast(&stub_scroller_state);
    const head = stub_node_new(&stub_scroller_state, &a, 0.5, 0.5).?;
    const curnode = stub_node_new(&stub_scroller_state, &b, 0.5, 0.5).?;
    stub_node_link(head, curnode);
    m.visible_scroll_tiling_clients = 2;

    stub_cursor.x = 100;
    stub_cursor.y = 100;
    resize_tile_scroller(&b, true, 0, 0, 0, false);
    try testing.expect(c.server.start_drag_window);
    try approxD(0.5, a.old_scroller_pproportion);
    try approx(0.5, b.scroller_old_stack_proportion);
    try testing.expectEqual(@as(c_int, 0), stub_arrange_calls);

    stub_cursor.x = 200;
    resize_tile_scroller(&b, true, 0, 0, 20, false);
    try approx(0.55, head.scroller_proportion);
    try approx(0.5, curnode.scroller_stack_proportion);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);
    try testing.expectEqual(@as(i32, 20), c.server.last_apply_drag_time);
}
