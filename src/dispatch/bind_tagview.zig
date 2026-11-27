//! Port of the tag/view/action cluster of src/dispatch/bind.c
//! (strangler-fig Phase 4, dispatch slice 1, slice 37).
//!
//! Functions: tag, tag_monitor, tag_silent, tag_to_left/right, the special
//! workspace toggles, scratchpad toggles, fake-fullscreen/floating/
//! fullscreen/global/gaps/group-bar/maximize/overlay toggles and
//! toggle_tag/toggle_view. The C twins are guarded with
//! ACWM_ZIG_BIND_TAGVIEW.

const std = @import("std");
const c = @import("cc");

const Arg = c.Arg;
const Client = c.Client;
const Monitor = c.Monitor;
const Box = c.struct_wlr_box;
const WlList = c.struct_wl_list;

extern fn tag_client(arg: *const Arg, target_client: ?*Client) callconv(.c) void;
extern fn client_switch_view(arg: *const Arg, want_animation: bool) callconv(.c) void;
extern fn client_focus(cl: ?*Client, lift: i32) callconv(.c) void;
extern fn client_focus_top(m: ?*Monitor) callconv(.c) ?*Client;
extern fn monitor_from_cycle(dir: i32) callconv(.c) ?*Monitor;
extern fn monitor_from_direction(dir: c.enum_wlr_direction) callconv(.c) ?*Monitor;
extern fn match_monitor_spec(spec: [*c]const u8, m: *Monitor) callconv(.c) bool;
extern fn client_set_monitor(cl: *Client, m: *Monitor, newtags: u32, focus: bool) callconv(.c) void;
extern fn client_update_oldmonname_record(cl: *Client, m: *Monitor) callconv(.c) void;
extern fn reset_foreign_tolevel(cl: *Client, oldmon: ?*Monitor, newmon: ?*Monitor) callconv(.c) void;
extern fn set_selected_monitor(m: ?*Monitor) callconv(.c) void;
extern fn client_center_geometry(cl: *Client, m: *Monitor, geom: Box, offsetx: i32, offsety: i32) callconv(.c) Box;
extern fn get_tags_first_tag(tags: u32) callconv(.c) u32;
extern fn get_tags_first_tag_num(tags: u32) callconv(.c) u32;
extern fn resize(cl: *Client, geo: Box, opts: c.ResizeOpts) callconv(.c) void;
extern fn pointer_warp_to_monitor(m: ?*Monitor) callconv(.c) void;
extern fn arrange(m: *Monitor, want_animation: bool, from_view: bool) callconv(.c) void;
extern fn client_reparent_group(cl: *Client) callconv(.c) void;
extern fn clear_fullscreen_flag(cl: *Client) callconv(.c) void;
extern fn get_client_by_id_or_title(id: [*c]const u8, title: [*c]const u8) callconv(.c) ?*Client;
extern fn apply_named_scratchpad(cl: *Client) callconv(.c) void;
extern fn spawn_shell(arg: *const Arg) callconv(.c) c_int;
extern fn set_minimized(cl: *Client) callconv(.c) void;
extern fn switch_scratchpad_client_state(cl: *Client) callconv(.c) bool;
extern fn is_special_active(m: ?*const Monitor) callconv(.c) bool;
extern fn client_set_fake_fullscreen(cl: *Client, fake: i32) callconv(.c) void;
extern fn client_set_floating(cl: *Client, floating: i32) callconv(.c) void;
extern fn client_apply_fullscreen(cl: *Client, fullscreen: i32, rearrange: bool) callconv(.c) void;
extern fn client_set_maximize_screen(cl: *Client, maximize: i32, rearrange: bool) callconv(.c) void;
extern fn client_update_border_color(cl: *Client) callconv(.c) void;
extern fn set_size_per(m: *Monitor, cl: *Client, reset: bool) callconv(.c) void;
extern fn printstatus(kind: c.enum_ipc_watch_type) callconv(.c) void;

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

fn ISFULLSCREEN(cl: *const Client) bool {
    return cl.isfullscreen != 0 or cl.ismaximizescreen != 0 or
        cl.overview_ismaximizescreenbak != 0 or cl.overview_isfullscreenbak != 0;
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

fn ISTILED(cl: ?*const Client) bool {
    const x = cl orelse return false;
    return x.isfloating == 0 and x.isminimized == 0 and x.iskilling == 0 and
        x.ismaximizescreen == 0 and x.isfullscreen == 0 and x.isunglobal == 0;
}

fn tag0Mask() u32 {
    return @bitCast(c.TAG0_MASK);
}

fn makeArgUI(ui: u32) Arg {
    var a = std.mem.zeroes(Arg);
    a.ui = ui;
    return a;
}

fn makeArgUIClient(ui: u32, cl: *Client) Arg {
    var a = std.mem.zeroes(Arg);
    a.ui = ui;
    a.tc = @ptrCast(cl);
    return a;
}

// ---------------------------------------------------------------------------
// tagging
// ---------------------------------------------------------------------------

export fn tag(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    const target = clientOpt(arg.tc) orelse clientOpt(m.sel);
    tag_client(arg, target);
    return 0;
}

export fn tag_silent(arg: *const Arg) callconv(.c) i32 {
    const selected = monitorOpt(c.server.selected_monitor);
    var target_opt = clientOpt(arg.tc);
    if (target_opt == null) {
        if (selected) |m|
            target_opt = clientOpt(m.sel);
    }
    const target = target_opt orelse return 0;

    const tag0 = tag0Mask();
    target.tags = if ((arg.ui & tag0) != 0) tag0 else (arg.ui & c.server.tagmask);
    client_reparent_group(target);

    var pos = c.server.clients.next;
    const head = listHead(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const fc = containerOf(Client, "link", pos);
        if (fc != target and (target.tags & fc.tags) != 0 and
            ISFULLSCREEN(fc) and target.isfloating == 0)
            clear_fullscreen_flag(fc);
    }

    client_focus(client_focus_top(c.server.selected_monitor), 1);
    const m = monitorOpt(target.mon) orelse return 0;
    arrange(m, false, false);
    return 0;
}

export fn tag_monitor(arg: *const Arg) callconv(.c) i32 {
    const selected = monitorOpt(c.server.selected_monitor) orelse return 0;
    const cl = clientOpt(arg.tc) orelse client_focus_top(selected) orelse return 0;
    const oldmon = monitorOpt(cl.mon) orelse return 0;

    var m: ?*Monitor = null;
    if (arg.i == c.MON_NEXT or arg.i == c.MON_PREV) {
        m = monitor_from_cycle(arg.i);
    } else if (arg.i != c.UNDIR) {
        m = monitor_from_direction(@intCast(arg.i));
    } else if (arg.v != null) {
        var pos = c.server.monitors.next;
        const head = listHead(&c.server.monitors);
        while (pos != head) : (pos = pos.*.next) {
            const cm = containerOf(Monitor, "link", pos);
            if (cm.wlr_output.*.enabled == false)
                continue;
            if (match_monitor_spec(arg.v, cm)) {
                m = cm;
                break;
            }
        }
    } else {
        return 0;
    }

    const target_mon = m orelse return 0;
    if (target_mon.wlr_output.*.enabled == false)
        return 0;

    const newtags: u32 = if (arg.ui != 0) arg.ui else if (arg.i2 != 0) cl.tags else 0;

    if (cl.mon == @as([*c]Monitor, @ptrCast(target_mon))) {
        var a = makeArgUI(newtags);
        client_switch_view(&a, true);
        return 0;
    }

    if (cl == oldmon.sel)
        oldmon.sel = null;

    client_set_monitor(cl, target_mon, newtags, true);
    client_update_oldmonname_record(cl, target_mon);
    reset_foreign_tolevel(cl, oldmon, monitorOpt(cl.mon));

    const newmon = monitorOpt(cl.mon) orelse return 0;
    cl.float_geom.width = @divTrunc(cl.float_geom.width * newmon.w.width, oldmon.w.width);
    cl.float_geom.height = @divTrunc(cl.float_geom.height * newmon.w.height, oldmon.w.height);
    set_selected_monitor(newmon);
    cl.float_geom = client_center_geometry(cl, newmon, cl.float_geom, 0, 0);

    if (cl.isfloating != 0) {
        cl.geom = cl.float_geom;
        const target = get_tags_first_tag(cl.tags);
        var a = makeArgUI(target);
        client_switch_view(&a, true);
        client_focus(cl, 1);
        resize(cl, cl.geom, .{ .interact = true });
    } else {
        set_selected_monitor(newmon);
        const target = get_tags_first_tag(cl.tags);
        var a = makeArgUI(target);
        client_switch_view(&a, true);
        client_focus(cl, 1);
        arrange(monitorOpt(c.server.selected_monitor) orelse newmon, false, false);
    }
    if (c.config.warpcursor != 0)
        pointer_warp_to_monitor(newmon);
    return 0;
}

export fn tag_to_left(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    const sel = clientOpt(arg.tc) orelse clientOpt(m.sel) orelse return 0;

    if (@popCount(m.tagset[m.seltags] & c.server.tagmask) == 1) {
        var target = m.tagset[m.seltags] >> 1;
        if (target == 0) {
            if (c.config.tag_carousel == 0)
                return 0;
            target = (@as(u32, 1) << @intCast(c.config.tag_num - 1)) & c.server.tagmask;
            m.carousel_anim_dir = -1;
        }
        const a = makeArgUIClient(target & c.server.tagmask, sel);
        _ = tag(&a);
        m.carousel_anim_dir = 0;
    }
    return 0;
}

export fn tag_to_right(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    const sel = clientOpt(arg.tc) orelse clientOpt(m.sel) orelse return 0;

    if (@popCount(m.tagset[m.seltags] & c.server.tagmask) == 1) {
        var target = m.tagset[m.seltags] << 1;
        if ((target & c.server.tagmask) == 0) {
            if (c.config.tag_carousel == 0)
                return 0;
            target = 1;
            m.carousel_anim_dir = 1;
        }
        const a = makeArgUIClient(target & c.server.tagmask, sel);
        _ = tag(&a);
        m.carousel_anim_dir = 0;
    }
    return 0;
}

// ---------------------------------------------------------------------------
// scratchpads
// ---------------------------------------------------------------------------

export fn toggle_named_scratchpad(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor);
    if (m != null and m.?.isoverview != 0)
        return 0;

    const target = get_client_by_id_or_title(arg.v, arg.v2) orelse {
        if (arg.v3 != null) {
            var spawn_arg = std.mem.zeroes(Arg);
            spawn_arg.v = arg.v3;
            _ = spawn_shell(&spawn_arg);
        }
        return 0;
    };

    target.isnamedscratchpad = 1;
    apply_named_scratchpad(target);
    return 0;
}

export fn toggle_scratchpad(arg: *const Arg) callconv(.c) i32 {
    _ = arg;
    const selected = monitorOpt(c.server.selected_monitor);
    if (selected != null and selected.?.isoverview != 0)
        return 0;

    var hit = false;
    var pos = c.server.clients.next;
    const head = listHead(&c.server.clients);
    while (pos != head) {
        const next = pos.*.next;
        const cl = containerOf(Client, "link", pos);
        if (c.config.scratchpad_cross_monitor == 0 and
            cl.mon != @as([*c]Monitor, @ptrCast(@constCast(selected orelse undefined))))
        {
            pos = next;
            continue;
        }

        if (c.config.single_scratchpad != 0 and cl.isnamedscratchpad != 0 and
            cl.isminimized == 0)
        {
            set_minimized(cl);
            pos = next;
            continue;
        }

        if (cl.isnamedscratchpad != 0) {
            pos = next;
            continue;
        }
        if (hit) {
            pos = next;
            continue;
        }

        hit = switch_scratchpad_client_state(cl);
        pos = next;
    }
    return 0;
}

// ---------------------------------------------------------------------------
// special workspace
// ---------------------------------------------------------------------------

export fn toggle_special_tag_mon(m_in: ?*Monitor) callconv(.c) void {
    const m = m_in orelse return;
    if (m.isoverview != 0)
        return;

    set_selected_monitor(m);
    if (is_special_active(m)) {
        const prev_set = m.tagset[m.seltags ^ 1] & c.server.tagmask;
        const target = if (prev_set != 0)
            prev_set
        else if (m.pertag.*.prevtag != 0)
            (@as(u32, 1) << @intCast(m.pertag.*.prevtag - 1))
        else
            1;
        var a = makeArgUI(target);
        client_switch_view(&a, true);
    } else {
        var a = makeArgUI(tag0Mask());
        client_switch_view(&a, true);
    }
}

export fn toggle_special_tag(arg: ?*const Arg) callconv(.c) i32 {
    var m = monitorOpt(c.server.selected_monitor);
    if (arg != null) {
        if (arg.?.tc != null) {
            if (clientOpt(arg.?.tc)) |cl| {
                if (cl.mon != null)
                    m = monitorOpt(cl.mon);
            }
        }
    }
    toggle_special_tag_mon(m);
    return 0;
}

fn tagSpecialTagInternal(arg: *const Arg, silent: bool) void {
    const selected = monitorOpt(c.server.selected_monitor) orelse return;
    const cl = clientOpt(arg.tc) orelse clientOpt(selected.sel) orelse return;
    const m = monitorOpt(cl.mon) orelse selected;

    if ((cl.tags & tag0Mask()) != 0) {
        const target: u32 = if (m.pertag.*.prevtag > 0)
            (@as(u32, 1) << @intCast(m.pertag.*.prevtag - 1))
        else if (m.pertag.*.curtag > 0)
            (@as(u32, 1) << @intCast(m.pertag.*.curtag - 1))
        else
            1;
        const a = makeArgUIClient(target, cl);
        if (silent)
            _ = tag_silent(&a)
        else
            _ = tag(&a);
    } else {
        const a = makeArgUIClient(tag0Mask(), cl);
        if (silent) {
            _ = tag_silent(&a);
        } else {
            _ = tag(&a);
            if (!is_special_active(m)) {
                var zero = std.mem.zeroes(Arg);
                _ = toggle_special_tag(&zero);
            }
        }
    }
}

export fn tag_special_tag(arg: *const Arg) callconv(.c) i32 {
    tagSpecialTagInternal(arg, false);
    return 0;
}

export fn tag_special_silent(arg: *const Arg) callconv(.c) i32 {
    tagSpecialTagInternal(arg, true);
    return 0;
}

// ---------------------------------------------------------------------------
// window-state toggles
// ---------------------------------------------------------------------------

export fn toggle_fake_fullscreen(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    const sel = clientOpt(arg.tc) orelse client_focus_top(m);
    if (sel) |cl|
        client_set_fake_fullscreen(cl, if (cl.isfakefullscreen != 0) 0 else 1);
    return 0;
}

export fn toggle_floating(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    if (c.server.grab_client != null)
        return 0;

    const sel = clientOpt(arg.tc) orelse client_focus_top(m) orelse return 0;
    if (m.isoverview != 0)
        return 0;

    const floating: i32 = if (sel.isfullscreen != 0 or sel.ismaximizescreen != 0)
        1
    else if (sel.isfloating != 0)
        0
    else
        1;
    client_set_floating(sel, floating);
    return 0;
}

export fn toggle_fullscreen(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    const sel = clientOpt(arg.tc) orelse client_focus_top(m) orelse return 0;

    sel.is_in_scratchpad = 0;
    sel.isnamedscratchpad = 0;

    client_apply_fullscreen(sel, if (sel.isfullscreen != 0) 0 else 1, true);
    return 0;
}

export fn toggle_global(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    const cl = clientOpt(arg.tc) orelse clientOpt(m.sel) orelse return 0;

    if (cl.is_in_scratchpad != 0) {
        cl.is_in_scratchpad = 0;
        cl.isnamedscratchpad = 0;
    }
    cl.isglobal = if (cl.isglobal != 0) 0 else 1;
    client_update_border_color(cl);
    return 0;
}

export fn toggle_gaps(arg: *const Arg) callconv(.c) i32 {
    _ = arg;
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    c.server.enable_gaps = if (c.server.enable_gaps != 0) 0 else 1;
    arrange(m, false, false);
    return 0;
}

export fn toggle_group_bar(arg: *const Arg) callconv(.c) i32 {
    _ = arg;
    c.config.always_show_group_bar = if (c.config.always_show_group_bar != 0) 0 else 1;

    var pos = c.server.monitors.next;
    const head = listHead(&c.server.monitors);
    while (pos != head) : (pos = pos.*.next) {
        const m = containerOf(Monitor, "link", pos);
        if (m.wlr_output.*.enabled)
            arrange(m, false, false);
    }
    return 0;
}

export fn toggle_maximize_screen(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    const sel = clientOpt(arg.tc) orelse client_focus_top(m) orelse return 0;

    sel.is_in_scratchpad = 0;
    sel.isnamedscratchpad = 0;

    client_set_maximize_screen(sel, if (sel.ismaximizescreen != 0) 0 else 1, true);
    client_update_border_color(sel);
    return 0;
}

export fn toggle_overlay(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    const cl = clientOpt(arg.tc) orelse clientOpt(m.sel) orelse return 0;
    if (cl.mon == null or cl.isfullscreen != 0)
        return 0;

    cl.isoverlay = if (cl.isoverlay != 0) 0 else 1;
    client_reparent_group(cl);
    client_update_border_color(cl);
    return 0;
}

export fn toggle_render_border(arg: *const Arg) callconv(.c) i32 {
    _ = arg;
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    c.server.render_border = !c.server.render_border;
    arrange(m, false, false);
    return 0;
}

// ---------------------------------------------------------------------------
// tags / views
// ---------------------------------------------------------------------------

export fn toggle_tag(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    const sel = clientOpt(arg.tc) orelse client_focus_top(m) orelse return 0;
    if (sel.mon != null and sel.mon.*.isoverview != 0)
        return 0;
    if ((sel.tags & tag0Mask()) != 0)
        return 0;

    const all_tags = ~@as(u32, 0) & c.server.tagmask;
    var newtags: u32 = undefined;

    if (@as(i32, @bitCast(arg.ui)) == std.math.minInt(i32) and sel.tags != all_tags) {
        newtags = all_tags;
    } else if (@as(i32, @bitCast(arg.ui)) == std.math.minInt(i32) and sel.tags == all_tags) {
        const selmon = monitorOpt(sel.mon) orelse return 0;
        var tag_num = selmon.pertag.*.curtag;
        if (tag_num == 0)
            tag_num = get_tags_first_tag_num(selmon.tagset[selmon.seltags]);
        if (tag_num == 0)
            tag_num = 1;
        newtags = @as(u32, 1) << @intCast(tag_num - 1);
    } else {
        newtags = sel.tags ^ (arg.ui & c.server.tagmask);
    }

    if (newtags != 0) {
        sel.tags = newtags;
        client_reparent_group(sel);
        client_focus(client_focus_top(c.server.selected_monitor), 1);
        arrange(monitorOpt(c.server.selected_monitor) orelse m, false, false);
    }
    printstatus(c.IPC_WATCH_ARRANGGE);
    return 0;
}

export fn toggle_view(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    if (m.isoverview != 0)
        return 0;

    const target: u32 = if (arg.ui == 0) (~@as(u32, 0) & c.server.tagmask) else arg.ui;
    const newtagset = m.tagset[m.seltags] ^ (target & c.server.tagmask);

    if (newtagset != 0) {
        m.tagset[m.seltags] = newtagset;
        client_focus(client_focus_top(m), 1);

        var pos = c.server.clients.next;
        const head = listHead(&c.server.clients);
        while (pos != head) : (pos = pos.*.next) {
            const cl = containerOf(Client, "link", pos);
            if (VISIBLEON(cl, m) and ISTILED(cl))
                set_size_per(m, cl, true);
        }
        arrange(m, false, false);
    }
    printstatus(c.IPC_WATCH_ARRANGGE);
    return 0;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/bind_tagview_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_tag_client_calls: c_int;
extern var stub_tag_client_ui: u32;
extern var stub_tag_client_target: ?*Client;
extern var stub_switch_view_calls: c_int;
extern var stub_switch_view_ui: u32;
extern var stub_switch_view_anim: bool;
extern var stub_focus_calls: c_int;
extern var stub_focus_top_calls: c_int;
extern var stub_focus_top: ?*Client;
extern var stub_set_monitor_calls: c_int;
extern var stub_set_monitor_mon: ?*Monitor;
extern var stub_update_oldmon_calls: c_int;
extern var stub_reset_foreign_calls: c_int;
extern var stub_selected_calls: c_int;
extern var stub_resize_calls: c_int;
extern var stub_warp_calls: c_int;
extern var stub_arrange_calls: c_int;
extern var stub_reparent_calls: c_int;
extern var stub_clear_fullscreen_calls: c_int;
extern var stub_named_scratch_calls: c_int;
extern var stub_spawn_calls: c_int;
extern var stub_minimized_calls: c_int;
extern var stub_switch_scratch_calls: c_int;
extern var stub_switch_scratch_result: bool;
extern var stub_special_active: bool;
extern var stub_fake_fullscreen_calls: c_int;
extern var stub_fake_fullscreen_arg: i32;
extern var stub_floating_calls: c_int;
extern var stub_floating_arg: i32;
extern var stub_fullscreen_calls: c_int;
extern var stub_fullscreen_arg: i32;
extern var stub_maximize_calls: c_int;
extern var stub_maximize_arg: i32;
extern var stub_border_color_calls: c_int;
extern var stub_set_size_calls: c_int;
extern var stub_printstatus_calls: c_int;
extern var stub_cycle_monitor: ?*Monitor;
extern var stub_direction_monitor: ?*Monitor;
extern var stub_lookup_client: ?*Client;

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
    stub_tag_client_calls = 0;
    stub_switch_view_calls = 0;
    stub_focus_calls = 0;
    stub_focus_top_calls = 0;
    stub_focus_top = null;
    stub_set_monitor_calls = 0;
    stub_update_oldmon_calls = 0;
    stub_reset_foreign_calls = 0;
    stub_selected_calls = 0;
    stub_resize_calls = 0;
    stub_warp_calls = 0;
    stub_arrange_calls = 0;
    stub_reparent_calls = 0;
    stub_clear_fullscreen_calls = 0;
    stub_named_scratch_calls = 0;
    stub_spawn_calls = 0;
    stub_minimized_calls = 0;
    stub_switch_scratch_calls = 0;
    stub_switch_scratch_result = false;
    stub_special_active = false;
    stub_fake_fullscreen_calls = 0;
    stub_floating_calls = 0;
    stub_fullscreen_calls = 0;
    stub_maximize_calls = 0;
    stub_border_color_calls = 0;
    stub_set_size_calls = 0;
    stub_printstatus_calls = 0;
    stub_cycle_monitor = null;
    stub_direction_monitor = null;
    stub_lookup_client = null;
}

fn baseMonitor(m: *Monitor, p: *c.Pertag, out: *c.struct_wlr_output) void {
    m.* = std.mem.zeroes(Monitor);
    p.* = std.mem.zeroes(c.Pertag);
    out.* = std.mem.zeroes(c.struct_wlr_output);
    out.enabled = true;
    m.pertag = p;
    m.wlr_output = @ptrCast(out);
    m.w = .{ .x = 0, .y = 0, .width = 500, .height = 400 };
    m.m = m.w;
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

test "tag dispatches the arg target or the selected client" {
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

    var arg = std.mem.zeroes(Arg);
    arg.ui = 4;
    _ = tag(&arg);
    try testing.expectEqual(@as(c_int, 1), stub_tag_client_calls);
    try testing.expectEqual(@as(u32, 4), stub_tag_client_ui);
    try testing.expect(stub_tag_client_target == &a);

    arg.tc = @ptrCast(&b);
    _ = tag(&arg);
    try testing.expect(stub_tag_client_target == &b);
}

test "tag_silent writes tags, reparents and clears conflicting fullscreen" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 2);
    b.isfullscreen = 1;
    c.server.selected_monitor = &m;

    var arg = std.mem.zeroes(Arg);
    arg.ui = 2;
    arg.tc = @ptrCast(&a);
    _ = tag_silent(&arg);

    try testing.expectEqual(@as(u32, 2), a.tags);
    try testing.expectEqual(@as(c_int, 1), stub_reparent_calls);
    try testing.expectEqual(@as(c_int, 1), stub_clear_fullscreen_calls);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);

    arg.ui = @bitCast(c.TAG0_MASK);
    _ = tag_silent(&arg);
    try testing.expectEqual(tag0Mask(), a.tags);
}

test "tag_to_left/right cycle carousel at the edges" {
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
    c.config.tag_carousel = 1;
    c.server.tagmask = 0x1ff;

    var arg = std.mem.zeroes(Arg);
    arg.tc = @ptrCast(&a);
    _ = tag_to_left(&arg);
    try testing.expectEqual(@as(u32, 256), stub_tag_client_ui);
    try testing.expectEqual(@as(i8, 0), m.carousel_anim_dir);

    m.tagset[0] = 2;
    _ = tag_to_left(&arg);
    try testing.expectEqual(@as(u32, 1), stub_tag_client_ui);

    m.tagset[0] = 256;
    _ = tag_to_right(&arg);
    try testing.expectEqual(@as(u32, 1), stub_tag_client_ui);

    m.tagset[0] = 1;
    _ = tag_to_right(&arg);
    try testing.expectEqual(@as(u32, 2), stub_tag_client_ui);
}

test "toggle_tag toggles bits and all-tags returns to the current tag" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    var a: Client = undefined;
    addClient(&a, &m, 1);
    c.server.selected_monitor = &m;
    stub_focus_top = &a;

    var arg = std.mem.zeroes(Arg);
    arg.ui = 2;
    _ = toggle_tag(&arg);

    try testing.expectEqual(@as(u32, 3), a.tags);
    try testing.expectEqual(@as(c_int, 1), stub_reparent_calls);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);
    try testing.expectEqual(@as(c_int, 1), stub_printstatus_calls);

    a.tags = c.server.tagmask;
    p.curtag = 2;
    arg.ui = @as(u32, @bitCast(@as(i32, std.math.minInt(i32))));
    _ = toggle_tag(&arg);
    try testing.expectEqual(@as(u32, 2), a.tags);

    a.tags = tag0Mask();
    const before = stub_arrange_calls;
    _ = toggle_tag(&arg);
    try testing.expectEqual(before, stub_arrange_calls);
}

test "toggle_view updates the tagset and resets visible tiled sizes" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    var a: Client = undefined;
    var f: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&f, &m, 1);
    f.isfloating = 1;
    c.server.selected_monitor = &m;

    var arg = std.mem.zeroes(Arg);
    arg.ui = 2;
    _ = toggle_view(&arg);

    try testing.expectEqual(@as(u32, 3), m.tagset[0]);
    try testing.expectEqual(@as(c_int, 1), stub_set_size_calls);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);
    try testing.expectEqual(@as(c_int, 1), stub_printstatus_calls);

    m.isoverview = 1;
    const before = stub_arrange_calls;
    _ = toggle_view(&arg);
    try testing.expectEqual(before, stub_arrange_calls);
}

test "window-state toggles forward the inverse state" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    var a: Client = undefined;
    addClient(&a, &m, 1);
    m.sel = &a;
    c.server.selected_monitor = &m;
    stub_focus_top = &a;

    a.isfullscreen = 1;
    _ = toggle_floating(&std.mem.zeroes(Arg));
    try testing.expectEqual(@as(c_int, 1), stub_floating_calls);
    try testing.expectEqual(@as(i32, 1), stub_floating_arg);

    a.isfullscreen = 0;
    a.isfloating = 1;
    _ = toggle_floating(&std.mem.zeroes(Arg));
    try testing.expectEqual(@as(i32, 0), stub_floating_arg);

    a.isfullscreen = 1;
    a.is_in_scratchpad = 1;
    a.isnamedscratchpad = 1;
    _ = toggle_fullscreen(&std.mem.zeroes(Arg));
    try testing.expectEqual(@as(i32, 0), stub_fullscreen_arg);
    try testing.expectEqual(@as(i32, 0), a.is_in_scratchpad);
    try testing.expectEqual(@as(i32, 0), a.isnamedscratchpad);

    _ = toggle_maximize_screen(&std.mem.zeroes(Arg));
    try testing.expectEqual(@as(i32, 1), stub_maximize_arg);
    try testing.expectEqual(@as(c_int, 1), stub_border_color_calls);

    _ = toggle_fake_fullscreen(&std.mem.zeroes(Arg));
    try testing.expectEqual(@as(i32, 1), stub_fake_fullscreen_arg);
}

test "special workspace toggles return to the previous tagset" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    m.tagset[0] = 1;
    m.tagset[1] = 4;
    p.prevtag = 3;
    c.server.selected_monitor = &m;

    stub_special_active = true;
    toggle_special_tag_mon(&m);
    try testing.expectEqual(@as(u32, 4), stub_switch_view_ui);
    try testing.expectEqual(@as(c_int, 1), stub_selected_calls);

    stub_special_active = false;
    toggle_special_tag_mon(&m);
    try testing.expectEqual(tag0Mask(), stub_switch_view_ui);

    var arg = std.mem.zeroes(Arg);
    var dummy = stub_dummy_client(&m);
    arg.tc = @ptrCast(&dummy);
    _ = toggle_special_tag(&arg);
}

fn stub_dummy_client(m: *Monitor) Client {
    var cl = std.mem.zeroes(Client);
    cl.mon = @ptrCast(m);
    return cl;
}

test "scratchpad toggles minimize named pads and hit unnamed pads once" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    var named: Client = undefined;
    var one: Client = undefined;
    var two: Client = undefined;
    addClient(&named, &m, 1);
    addClient(&one, &m, 1);
    addClient(&two, &m, 1);
    named.isnamedscratchpad = 1;
    c.server.selected_monitor = &m;
    c.config.single_scratchpad = 1;
    stub_switch_scratch_result = true;

    _ = toggle_scratchpad(&std.mem.zeroes(Arg));
    try testing.expectEqual(@as(c_int, 1), stub_minimized_calls);
    try testing.expectEqual(@as(c_int, 1), stub_switch_scratch_calls);

    var arg = std.mem.zeroes(Arg);
    arg.v = @ptrCast(@constCast("ghost"));
    arg.v2 = @ptrCast(@constCast("Ghost"));
    arg.v3 = @ptrCast(@constCast("kitty"));
    _ = toggle_named_scratchpad(&arg);
    try testing.expectEqual(@as(c_int, 1), stub_spawn_calls);
}

test "gaps, group bar and render border toggle and re-arrange" {
    resetWorld();
    var p1: c.Pertag = undefined;
    var p2: c.Pertag = undefined;
    var o1: c.struct_wlr_output = undefined;
    var o2: c.struct_wlr_output = undefined;
    var m1: Monitor = undefined;
    var m2: Monitor = undefined;
    baseMonitor(&m1, &p1, &o1);
    baseMonitor(&m2, &p2, &o2);
    listInsert(&c.server.monitors, &m1.link);
    listInsert(&c.server.monitors, &m2.link);
    c.server.selected_monitor = &m1;

    c.server.enable_gaps = 0;
    _ = toggle_gaps(&std.mem.zeroes(Arg));
    try testing.expectEqual(@as(i32, 1), c.server.enable_gaps);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);

    c.config.always_show_group_bar = 0;
    _ = toggle_group_bar(&std.mem.zeroes(Arg));
    try testing.expectEqual(@as(i32, 1), c.config.always_show_group_bar);
    try testing.expectEqual(@as(c_int, 3), stub_arrange_calls);

    c.server.render_border = false;
    _ = toggle_render_border(&std.mem.zeroes(Arg));
    try testing.expect(c.server.render_border);
}
