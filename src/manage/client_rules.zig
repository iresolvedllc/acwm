//! Port of the rule application and floating-snap helpers in
//! src/manage/client.c (Phase 5, client slice 4, slice 61).

const std = @import("std");
const c = @import("cc");

const Client = c.Client;
const Monitor = c.Monitor;
const Arg = c.Arg;
const Box = c.struct_wlr_box;

extern fn client_get_parent(cl: [*c]Client) callconv(.c) [*c]Client;
extern fn client_is_float_type(cl: [*c]Client) callconv(.c) i32;
extern fn client_is_x11(cl: [*c]Client) callconv(.c) i32;
extern fn client_update_geometry(cl: [*c]Client) callconv(.c) void;
extern fn client_get_appid(cl: [*c]Client) callconv(.c) [*c]const u8;
extern fn client_get_title(cl: [*c]Client) callconv(.c) [*c]const u8;
extern fn client_get_pid(cl: [*c]Client) callconv(.c) i32;
extern fn client_surface(cl: [*c]Client) callconv(.c) [*c]c.struct_wlr_surface;
extern fn is_window_rule_matches(r: *const c.ConfigWinRule, appid: [*c]const u8, title: [*c]const u8) callconv(.c) bool;
extern fn match_monitor_spec(spec: [*c]u8, m: *Monitor) callconv(.c) bool;
extern fn client_center_geometry(cl: [*c]Client, m: [*c]Monitor, geom: Box, offsetx: i32, offsety: i32) callconv(.c) Box;
extern fn client_set_size_bound(cl: [*c]Client) callconv(.c) void;
extern fn client_find_terminal(cl: [*c]Client) callconv(.c) [*c]Client;
extern fn client_replace(cl: [*c]Client, w: [*c]Client, is_group_change_member: bool, apply_rule: bool) callconv(.c) void;
extern fn client_set_monitor(cl: [*c]Client, m: [*c]Monitor, newtags: u32, focus: bool) callconv(.c) void;
extern fn client_reparent_group(cl: [*c]Client) callconv(.c) void;
extern fn client_view_on_monitor(arg: *const Arg, want_animation: bool, m: [*c]Monitor, from_rule: bool) callconv(.c) void;
extern fn client_apply_fullscreen(cl: [*c]Client, fullscreen: i32, rearrange: bool) callconv(.c) void;
extern fn client_set_fake_fullscreen(cl: [*c]Client, fakefullscreen: i32) callconv(.c) void;
extern fn clear_fullscreen_flag(cl: [*c]Client) callconv(.c) void;
extern fn apply_named_scratchpad(cl: [*c]Client) callconv(.c) void;
extern fn client_target_layer(cl: [*c]Client) callconv(.c) u32;
extern fn client_wants_fullscreen(cl: [*c]Client) callconv(.c) i32;
extern fn client_is_x11_popup(cl: [*c]Client) callconv(.c) i32;
extern fn client_should_ignore_focus(cl: [*c]Client) callconv(.c) i32;
extern fn is_special_active(m: ?*const Monitor) callconv(.c) bool;
extern fn get_tags_first_tag_num(tags: u32) callconv(.c) u32;
extern fn set_size_per(m: [*c]Monitor, cl: [*c]Client, reset_proportion: bool) callconv(.c) void;
extern fn arrange(m: [*c]Monitor, want_animation: bool, from_view: bool) callconv(.c) void;
extern fn resize(cl: [*c]Client, geo: Box, opts: c.ResizeOpts) callconv(.c) void;

const broken = "broken";

fn monitorOpt(p: [*c]Monitor) ?*Monitor {
    return if (p == null) null else @ptrCast(p);
}

fn clientOpt(p: [*c]Client) ?*Client {
    return if (p == null) null else @ptrCast(p);
}

fn VISIBLEON(cl: *const Client, m: *const Monitor) bool {
    if (cl.mon != @as([*c]Monitor, @ptrCast(@constCast(m))))
        return false;
    if (cl.isminimized != 0)
        return false;
    return (cl.tags & m.tagset[m.seltags]) != 0 or cl.isglobal != 0 or cl.isunglobal != 0;
}

fn ISFULLSCREEN(cl: *const Client) bool {
    return cl.isfullscreen != 0 or cl.ismaximizescreen != 0 or
        cl.overview_ismaximizescreenbak != 0 or cl.overview_isfullscreenbak != 0;
}

fn xdgInitialCommit(cl: *Client) bool {
    if (client_is_x11(cl) != 0)
        return false;
    if (cl.surface.xdg == null)
        return false;
    return cl.surface.xdg.*.initial_commit;
}

fn applyInt(cl: *Client, value: i32, comptime field: []const u8) void {
    if (value >= 0)
        @field(cl, field) = value;
}

fn applyFloat(cl: *Client, value: f32, comptime field: []const u8) void {
    if (value > 0.0)
        @field(cl, field) = value;
}

export fn apply_rule_properties(cl: *Client, r: *const c.ConfigWinRule) callconv(.c) void {
    inline for (.{
        "isterm", "allow_csd", "force_fakemaximize", "force_tiled_state",
        "force_tearing", "no_swallow", "confine_pointer", "no_focus",
        "no_fade_in", "no_fade_out", "no_force_center", "isfloating",
        "isfullscreen", "isfakefullscreen", "no_border", "no_shadow",
        "no_radius", "no_animation", "isopensilent", "istagsilent",
        "isnamedscratchpad", "isglobal", "isoverlay", "shield_when_capture",
        "ignore_maximize", "ignore_minimize", "no_size_hint",
        "idleinhibit_when_focus", "vrr_only_fullscreen", "force_render",
        "activation_bypass", "isunglobal", "no_blur", "allow_shortcuts_inhibit",
        "animation_type_open", "animation_type_close",
    }) |field| {
        applyInt(cl, @field(r, field), field);
    }
    inline for (.{ "scroller_proportion", "scroller_proportion_single", "focused_opacity", "unfocused_opacity" }) |field| {
        applyFloat(cl, @field(r, field), field);
    }
}

export fn set_float_malposition(tc: *Client) callconv(.c) void {
    if (tc.mon == null)
        return;
    var x = tc.geom.x;
    var y = tc.geom.y;
    var xreverse: i32 = 1;
    var yreverse: i32 = 1;

    const offset = @min(@divTrunc(tc.mon.*.w.width, 20), @divTrunc(tc.mon.*.w.height, 20));

    var pos = c.server.clients.next;
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = @as(*Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(Client, "link")));
        if (cl.isfloating != 0 and cl != tc and VISIBLEON(cl, tc.mon) and
            @abs(x - cl.geom.x) < offset and @abs(y - cl.geom.y) < offset)
        {
            x = cl.geom.x + offset * xreverse;
            y = cl.geom.y + offset * yreverse;
            if (x < tc.mon.*.w.x) {
                x += offset;
                xreverse = 1;
            }
            if (y < tc.mon.*.w.y) {
                y += offset;
                yreverse = 1;
            }
            if (x + tc.geom.width > tc.mon.*.w.x + tc.mon.*.w.width) {
                x -= offset;
                xreverse = -1;
            }
            if (y + tc.geom.height > tc.mon.*.w.y + tc.mon.*.w.height) {
                y -= offset;
                yreverse = -1;
            }
        }
    }

    tc.float_geom.x = x;
    tc.geom.x = x;
    tc.float_geom.y = y;
    tc.geom.y = y;
}

export fn client_reset_mon_tags(cl: *Client, mon: [*c]Monitor, newtags: u32) callconv(.c) void {
    const m = monitorOpt(mon);
    if (newtags == 0 and m != null and m.?.isoverview == 0) {
        cl.tags = m.?.tagset[m.?.seltags];
    } else if (newtags == 0 and m != null and m.?.isoverview != 0) {
        cl.tags = m.?.ovbk_current_tagset;
    } else if (newtags != 0) {
        const masked = if ((newtags & (@as(u32, 1) << 31)) != 0)
            @as(u32, 1) << 31
        else
            newtags & c.server.tagmask;
        cl.tags = if (masked != 0) masked else if (m != null) m.?.tagset[m.?.seltags] else 0;
    } else if (m != null) {
        cl.tags = m.?.tagset[m.?.seltags];
    }
}

export fn check_match_tag_floating_rule(cl: *Client, mon: [*c]Monitor) callconv(.c) void {
    const m = monitorOpt(mon);
    if (cl.tags != 0 and cl.isfloating == 0 and m != null and cl.swallowing == null and
        m.?.pertag != null and
        m.?.pertag.*.open_as_floating[@intCast(get_tags_first_tag_num(cl.tags))] != 0)
        cl.isfloating = 1;
}

export fn client_apply_rules(cl: *Client, rule_mon: [*c][*c]Monitor, rule_tags: [*c]u32) callconv(.c) void {
    var newtags: u32 = 0;
    const parent = clientOpt(client_get_parent(cl));
    var mon: ?*Monitor = if (parent != null and parent.?.mon != null)
        @ptrCast(parent.?.mon)
    else
        monitorOpt(c.server.selected_monitor);

    cl.isfloating = if (client_is_float_type(cl) != 0 or parent != null) 1 else 0;
    client_update_geometry(cl);

    const appid = blk: {
        const a = client_get_appid(cl);
        break :blk if (a != null) a else @as([*c]const u8, @ptrCast(broken.ptr));
    };
    const title = blk: {
        const t = client_get_title(cl);
        break :blk if (t != null) t else @as([*c]const u8, @ptrCast(broken.ptr));
    };

    var i: i32 = 0;
    while (i < c.config.window_rules_count) : (i += 1) {
        const idx: usize = @intCast(i);
        const r = @as(*c.ConfigWinRule, @ptrCast(&c.config.window_rules[idx]));

        if (!is_window_rule_matches(r, appid, title))
            continue;
        if (r.is_once != 0 and r.is_once_applied != 0)
            continue;
        if (r.is_once != 0 and (client_is_x11(cl) != 0 or !xdgInitialCommit(cl)))
            r.is_once_applied = 1;

        apply_rule_properties(cl, r);

        if (r.tags != 0) {
            newtags |= r.tags;
        } else if (parent != null) {
            newtags = parent.?.tags;
        }

        var pos = c.server.monitors.next;
        const head: [*c]c.struct_wl_list = @ptrCast(&c.server.monitors);
        while (pos != head) : (pos = pos.*.next) {
            const m = @as(*Monitor, @ptrFromInt(@intFromPtr(pos) - @offsetOf(Monitor, "link")));
            if (match_monitor_spec(r.monitor, m))
                mon = m;
        }

        if (cl.isnamedscratchpad != 0)
            cl.isfloating = 1;
        if (r.scroller_proportion > 0.0)
            cl.iscustom_scroller_proportion = 1;
        if (r.scroller_proportion_single > 0.0)
            cl.iscustom_scroller_proportion_single = 1;

        if (r.width > 1) {
            cl.float_geom.width = @intFromFloat(r.width);
        } else if (r.width > 0 and r.width <= 1 and mon != null) {
            cl.float_geom.width = @intFromFloat(@round(@as(f32, @floatFromInt(mon.?.m.width)) * r.width));
        }
        if (r.height > 1) {
            cl.float_geom.height = @intFromFloat(r.height);
        } else if (r.height > 0 and r.height <= 1 and mon != null) {
            cl.float_geom.height = @intFromFloat(@round(@as(f32, @floatFromInt(mon.?.m.height)) * r.height));
        }
        if (r.width > 0 or r.height > 0)
            cl.iscustomsize = 1;

        if (r.offsetx != 0 or r.offsety != 0) {
            cl.iscustompos = 1;
            const centered = client_center_geometry(cl, (if (mon) |mm| mm else null), cl.float_geom, r.offsetx, r.offsety);
            cl.float_geom = centered;
            cl.geom = centered;
        }
        if (cl.isfloating != 0) {
            cl.geom = if (cl.float_geom.width > 0 and cl.float_geom.height > 0) cl.float_geom else cl.geom;
            if (cl.no_size_hint == 0)
                client_set_size_bound(cl);
        }
    }

    if (newtags == 0 and parent != null and (parent.?.tags & (@as(u32, 1) << 31)) != 0) {
        newtags = @as(u32, 1) << 31;
    } else if (newtags == 0 and mon != null and is_special_active(mon.?)) {
        newtags = @as(u32, 1) << 31;
    }

    if (mon != null)
        set_size_per(mon.?, cl, false);

    if (cl.iscustompos == 0 and
        (client_is_x11(cl) == 0 or (cl.geom.x == 0 and cl.geom.y == 0)))
    {
        const pending_center = if (cl.iscustomsize != 0) cl.float_geom else cl.geom;
        const centered = client_center_geometry(cl, (if (mon) |mm| mm else null), pending_center, 0, 0);
        cl.float_geom = centered;
        cl.geom = centered;
    } else if (cl.iscustomsize == 0) {
        cl.float_geom = cl.geom;
    }

    const surface = client_surface(cl);
    if (surface == null or !surface.*.mapped) {
        if (rule_mon != null) rule_mon[0] = (if (mon) |mm| mm else null);
        if (rule_tags != null) rule_tags[0] = newtags;
        return;
    }

    cl.pid = client_get_pid(cl);
    if (cl.no_swallow == 0 and cl.isfloating == 0 and client_is_float_type(cl) == 0 and
        !xdgInitialCommit(cl))
    {
        const p = clientOpt(client_find_terminal(cl));
        if (p != null and p.?.isminimized == 0) {
            cl.swallowing = p.?;
            p.?.swallowdby = cl;
            mon = monitorOpt(p.?.mon);
            newtags = p.?.tags;
            client_replace(cl, p.?, false, true);
        }
    }

    const fullscreen_state_backup: i32 = if (cl.isfullscreen != 0 or client_wants_fullscreen(cl) != 0) 1 else 0;
    const should_focus = cl.isopensilent == 0 and
        !(client_is_x11_popup(cl) != 0 and client_should_ignore_focus(cl) != 0) and
        mon != null and
        (cl.istagsilent == 0 or newtags == 0 or
            (newtags & mon.?.tagset[mon.?.seltags]) != 0);

    if (!should_focus)
        c.wl_list_safe_reinsert_prev(&c.server.focus_stack, &cl.flink);

    client_set_monitor(cl, (if (mon) |mm| mm else null), newtags, should_focus);
    client_reparent_group(cl);

    if (cl.isfloating == 0) {
        cl.old_stack_inner_per = cl.stack_inner_per;
        cl.old_master_inner_per = cl.master_inner_per;
    }

    if (cl.mon != null and
        !(cl.mon == c.server.selected_monitor and
            (cl.tags & cl.mon.*.tagset[cl.mon.*.seltags]) != 0) and
        cl.isopensilent == 0 and cl.istagsilent == 0)
    {
        cl.animation.tag_from_rule = true;
        var arg = std.mem.zeroes(Arg);
        arg.ui = cl.tags;
        client_view_on_monitor(&arg, true, cl.mon, true);
    }

    client_apply_fullscreen(cl, fullscreen_state_backup, true);
    if (cl.isfakefullscreen != 0)
        client_set_fake_fullscreen(cl, 1);

    var pos = c.server.clients.next;
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const fc = @as(*Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(Client, "link")));
        if (fc != cl and (cl.tags & fc.tags) != 0 and cl.mon != null and
            VISIBLEON(fc, cl.mon) and ISFULLSCREEN(fc) and cl.isfloating == 0)
        {
            clear_fullscreen_flag(fc);
            arrange(cl.mon, false, false);
        }
    }

    if (cl.isfloating != 0 and cl.iscustompos == 0 and cl.isnamedscratchpad == 0) {
        c.wl_list_safe_reinsert_prev(&c.server.clients, &cl.link);
        set_float_malposition(cl);
    }

    if (cl.isnamedscratchpad != 0)
        apply_named_scratchpad(cl);

    if (cl.isoverlay != 0 and cl.scene != null)
        c.wlr_scene_node_reparent(&cl.scene.*.node, c.server.layers[@intCast(client_target_layer(cl))]);
}

export fn apply_window_snap(cl: *Client) callconv(.c) void {
    if (cl.mon == null or client_surface(cl) == null or !client_surface(cl).*.mapped or cl.iskilling != 0)
        return;
    if (cl.isfloating == 0 or c.config.enable_floating_snap == 0)
        return;

    var snap_up: i64 = 99999;
    var snap_down: i64 = 99999;
    var snap_left: i64 = 99999;
    var snap_right: i64 = 99999;

    const cbw: u32 = if (!c.server.render_border or cl.fake_no_border) cl.bw else 0;
    const cx: u32 = @intCast(cl.geom.x + @as(i32, @intCast(cbw)));
    const cy: u32 = @intCast(cl.geom.y + @as(i32, @intCast(cbw)));
    const cw: u32 = @intCast(cl.geom.width - 2 * @as(i32, @intCast(cbw)));
    const ch: u32 = @intCast(cl.geom.height - 2 * @as(i32, @intCast(cbw)));

    var pos = c.server.clients.next;
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const tc = @as(*Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(Client, "link")));
        const ts = client_surface(tc);
        if (tc.isfloating != 0 and tc.iskilling == 0 and ts != null and ts.*.mapped and
            VISIBLEON(tc, cl.mon))
        {
            const tcbw: u32 = if (!c.server.render_border or tc.fake_no_border) tc.bw else 0;
            const tcx: u32 = @intCast(tc.geom.x + @as(i32, @intCast(tcbw)));
            const tcy: u32 = @intCast(tc.geom.y + @as(i32, @intCast(tcbw)));
            const tcw: u32 = @intCast(tc.geom.width - 2 * @as(i32, @intCast(tcbw)));
            const tch: u32 = @intCast(tc.geom.height - 2 * @as(i32, @intCast(tcbw)));

            const left_temp: i64 = @as(i64, cx) - tcx - tcw;
            const right_temp: i64 = @as(i64, tcx) - cx - cw;
            const up_temp: i64 = @as(i64, cy) - tcy - tch;
            const down_temp: i64 = @as(i64, tcy) - cy - ch;

            if (left_temp < snap_left and left_temp >= 0) snap_left = left_temp;
            if (right_temp < snap_right and right_temp >= 0) snap_right = right_temp;
            if (up_temp < snap_up and up_temp >= 0) snap_up = up_temp;
            if (down_temp < snap_down and down_temp >= 0) snap_down = down_temp;
        }
    }

    const m = @as(*Monitor, @ptrCast(cl.mon));
    const left_mon: i64 = @as(i64, cx) - m.m.x;
    const right_mon: i64 = @as(i64, m.m.x) + m.m.width - cx - cw;
    const up_mon: i64 = @as(i64, cy) - m.m.y;
    const down_mon: i64 = @as(i64, m.m.y) + m.m.height - cy - ch;

    if (up_mon >= 0 and up_mon < snap_up) snap_up = up_mon;
    if (down_mon >= 0 and down_mon < snap_down) snap_down = down_mon;
    if (left_mon >= 0 and left_mon < snap_left) snap_left = left_mon;
    if (right_mon >= 0 and right_mon < snap_right) snap_right = right_mon;

    const left_screen: i64 = @as(i64, cx) - m.w.x;
    const right_screen: i64 = @as(i64, m.w.x) + m.w.width - cx - cw;
    const up_screen: i64 = @as(i64, cy) - m.w.y;
    const down_screen: i64 = @as(i64, m.w.y) + m.w.height - cy - ch;

    if (up_screen >= 0 and up_screen < snap_up) snap_up = up_screen;
    if (down_screen >= 0 and down_screen < snap_down) snap_down = down_screen;
    if (left_screen >= 0 and left_screen < snap_left) snap_left = left_screen;
    if (right_screen >= 0 and right_screen < snap_right) snap_right = right_screen;

    const distance: i64 = c.config.snap_distance;
    if (snap_left < snap_right and snap_left < distance)
        cl.geom.x -= @intCast(snap_left);
    if (snap_right <= snap_left and snap_right < distance)
        cl.geom.x += @intCast(snap_right);
    if (snap_up < snap_down and snap_up < distance)
        cl.geom.y -= @intCast(snap_up);
    if (snap_down <= snap_up and snap_down < distance)
        cl.geom.y += @intCast(snap_down);

    cl.float_geom = cl.geom;
    var opts = std.mem.zeroes(c.ResizeOpts);
    opts.interact = false;
    resize(cl, cl.geom, opts);
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/client_rules_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_x11: bool;
extern var stub_float_type: i32;
extern var stub_update_geometry_calls: c_int;
extern var stub_pid: i32;
extern var stub_parent: [*c]Client;
extern var stub_center_box: Box;
extern var stub_center_calls: c_int;
extern var stub_size_bound_calls: c_int;
extern var stub_terminal: [*c]Client;
extern var stub_replace_calls: c_int;
extern var stub_set_monitor_calls: c_int;
extern var stub_set_monitor_m: [*c]Monitor;
extern var stub_set_monitor_tags: u32;
extern var stub_set_monitor_focus: bool;
extern var stub_reparent_group_calls: c_int;
extern var stub_view_on_monitor_calls: c_int;
extern var stub_view_tags: u32;
extern var stub_view_from_rule: bool;
extern var stub_apply_fullscreen_calls: c_int;
extern var stub_apply_fullscreen_state: i32;
extern var stub_fake_fullscreen_calls: c_int;
extern var stub_clear_fullscreen_calls: c_int;
extern var stub_named_scratchpad_calls: c_int;
extern var stub_target_layer: u32;
extern var stub_wants_fullscreen: i32;
extern var stub_special: bool;
extern var stub_size_per_calls: c_int;
extern var stub_arrange_calls: c_int;
extern var stub_resize_calls: c_int;
extern var stub_resize_geo: Box;
extern var stub_reinsert_calls: c_int;
extern var stub_reparent_calls: c_int;
extern var stub_reparent_parent: [*c]c.struct_wlr_scene_tree;
extern var stub_x11_popup: i32;
extern var stub_ignore_focus: i32;

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

fn mkBox(x: i32, y: i32, w: i32, h: i32) Box {
    return .{ .x = x, .y = y, .width = w, .height = h };
}

fn resetRulesWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    listInit(&c.server.clients);
    listInit(&c.server.monitors);
    listInit(&c.server.focus_stack);
    c.server.tagmask = 0xffffffff;
    c.server.render_border = true;
    c.config.snap_distance = 20;
    c.config.enable_floating_snap = 1;
    stub_x11 = false;
    stub_float_type = 0;
    stub_update_geometry_calls = 0;
    stub_pid = 0;
    stub_parent = null;
    stub_center_box = std.mem.zeroes(Box);
    stub_center_calls = 0;
    stub_size_bound_calls = 0;
    stub_terminal = null;
    stub_replace_calls = 0;
    stub_set_monitor_calls = 0;
    stub_set_monitor_m = null;
    stub_set_monitor_tags = 0;
    stub_set_monitor_focus = false;
    stub_reparent_group_calls = 0;
    stub_view_on_monitor_calls = 0;
    stub_view_tags = 0;
    stub_view_from_rule = false;
    stub_apply_fullscreen_calls = 0;
    stub_apply_fullscreen_state = -1;
    stub_fake_fullscreen_calls = 0;
    stub_clear_fullscreen_calls = 0;
    stub_named_scratchpad_calls = 0;
    stub_target_layer = 5;
    stub_wants_fullscreen = 0;
    stub_special = false;
    stub_size_per_calls = 0;
    stub_arrange_calls = 0;
    stub_resize_calls = 0;
    stub_resize_geo = std.mem.zeroes(Box);
    stub_reinsert_calls = 0;
    stub_reparent_calls = 0;
    stub_reparent_parent = null;
    stub_x11_popup = 0;
    stub_ignore_focus = 0;
    test_output_next = 0;
}

var test_outputs: [8]c.struct_wlr_output = undefined;
var test_output_next: usize = 0;

fn baseMonitor(m: *Monitor, p: *c.Pertag, name: [*c]const u8) void {
    m.* = std.mem.zeroes(Monitor);
    p.* = std.mem.zeroes(c.Pertag);
    m.pertag = p;
    m.w = mkBox(0, 0, 1000, 800);
    m.m = m.w;
    m.tagset[0] = 1;
    m.seltags = 0;
    const out = &test_outputs[test_output_next];
    test_output_next += 1;
    out.* = std.mem.zeroes(c.struct_wlr_output);
    out.name = @ptrCast(@constCast(name));
    m.wlr_output = out;
}

fn baseClient(cl: *Client, m: *Monitor, xdg: *c.struct_wlr_xdg_surface, toplevel: *c.struct_wlr_xdg_toplevel, surface: *c.struct_wlr_surface) void {
    cl.* = std.mem.zeroes(Client);
    xdg.* = std.mem.zeroes(c.struct_wlr_xdg_surface);
    toplevel.* = std.mem.zeroes(c.struct_wlr_xdg_toplevel);
    surface.* = std.mem.zeroes(c.struct_wlr_surface);
    cl.type = @intCast(c.XDGShell);
    cl.mon = m;
    cl.tags = 1;
    cl.surface.xdg = xdg;
    xdg.surface = surface;
    xdg.unnamed_0.toplevel = toplevel;
    toplevel.base = xdg;
}

test "rule properties apply ints and floats with sentinels" {
    resetRulesWorld();
    var cl: Client = std.mem.zeroes(Client);
    var r: c.ConfigWinRule = std.mem.zeroes(c.ConfigWinRule);
    r.isterm = 1;
    r.allow_csd = 1;
    r.force_tearing = -1;
    r.no_focus = 1;
    r.no_fade_in = 0;
    r.isfloating = 1;
    r.isunglobal = 1;
    r.no_blur = 1;
    r.animation_type_open = 3;
    r.scroller_proportion = 0.25;
    r.focused_opacity = 0.9;
    r.unfocused_opacity = -1.0;
    apply_rule_properties(&cl, &r);
    try testing.expectEqual(@as(i32, 1), cl.isterm);
    try testing.expectEqual(@as(i32, 1), cl.allow_csd);
    try testing.expectEqual(@as(i32, 0), cl.force_tearing);
    try testing.expectEqual(@as(i32, 1), cl.no_focus);
    try testing.expectEqual(@as(i32, 0), cl.no_fade_in);
    try testing.expectEqual(@as(i32, 1), cl.isunglobal);
    try testing.expectEqual(@as(i32, 1), cl.no_blur);
    try testing.expectEqual(@as(i32, 3), cl.animation_type_open);
    try testing.expectApproxEqAbs(@as(f32, 0.25), cl.scroller_proportion, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.9), cl.focused_opacity, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0), cl.unfocused_opacity, 1e-6);
}

test "floating clients are nudged away from overlaps" {
    resetRulesWorld();
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var m: Monitor = std.mem.zeroes(Monitor);
    baseMonitor(&m, &p, "DP-1");
    var tc: Client = std.mem.zeroes(Client);
    tc.mon = &m;
    tc.isfloating = 1;
    tc.tags = 1;
    tc.geom = mkBox(100, 100, 100, 100);

    var other: Client = std.mem.zeroes(Client);
    other.mon = &m;
    other.isfloating = 1;
    other.tags = 1;
    other.geom = mkBox(105, 105, 100, 100);
    listInsert(&c.server.clients, &other.link);

    set_float_malposition(&tc);
    try testing.expectEqual(@as(i32, 145), tc.geom.x);
    try testing.expectEqual(@as(i32, 145), tc.geom.y);

    tc.geom = mkBox(900, 700, 100, 100);
    other.geom = mkBox(905, 705, 100, 100);
    set_float_malposition(&tc);
    try testing.expectEqual(@as(i32, 905), tc.geom.x);
    try testing.expectEqual(@as(i32, 705), tc.geom.y);

    other.isfloating = 0;
    tc.geom = mkBox(100, 100, 100, 100);
    set_float_malposition(&tc);
    try testing.expectEqual(@as(i32, 100), tc.geom.x);

    var no_mon: Client = std.mem.zeroes(Client);
    set_float_malposition(&no_mon);
}

test "monitor tag reset handles special, overview and masks" {
    resetRulesWorld();
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var m: Monitor = std.mem.zeroes(Monitor);
    baseMonitor(&m, &p, "DP-1");
    m.tagset[0] = 0b101;
    var cl: Client = std.mem.zeroes(Client);

    client_reset_mon_tags(&cl, &m, 0);
    try testing.expectEqual(@as(u32, 0b101), cl.tags);
    m.isoverview = 1;
    m.ovbk_current_tagset = 0b10;
    client_reset_mon_tags(&cl, &m, 0);
    try testing.expectEqual(@as(u32, 0b10), cl.tags);
    m.isoverview = 0;

    cl.tags = 0;
    client_reset_mon_tags(&cl, &m, @as(u32, 1) << 31);
    try testing.expectEqual(@as(u32, 1) << 31, cl.tags);
    c.server.tagmask = 0xff;
    client_reset_mon_tags(&cl, &m, 0b100000000);
    try testing.expectEqual(@as(u32, 0b101), cl.tags);
    client_reset_mon_tags(&cl, &m, 0b1000);
    try testing.expectEqual(@as(u32, 0b1000), cl.tags);
}

test "per-tag open-as-floating promotes matching clients" {
    resetRulesWorld();
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var m: Monitor = std.mem.zeroes(Monitor);
    baseMonitor(&m, &p, "DP-1");
    p.open_as_floating[2] = 1;
    var cl: Client = std.mem.zeroes(Client);
    cl.mon = &m;
    cl.tags = 0b10;
    check_match_tag_floating_rule(&cl, &m);
    try testing.expectEqual(@as(i32, 1), cl.isfloating);

    cl.isfloating = 0;
    cl.tags = 0b100;
    check_match_tag_floating_rule(&cl, &m);
    try testing.expectEqual(@as(i32, 0), cl.isfloating);

    cl.tags = 0b10;
    cl.swallowing = &cl;
    check_match_tag_floating_rule(&cl, &m);
    try testing.expectEqual(@as(i32, 0), cl.isfloating);
}

test "rules set size, tags and outputs before mapping" {
    resetRulesWorld();
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var m: Monitor = std.mem.zeroes(Monitor);
    baseMonitor(&m, &p, "DP-1");
    c.server.selected_monitor = &m;
    var xdg: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    var toplevel: c.struct_wlr_xdg_toplevel = std.mem.zeroes(c.struct_wlr_xdg_toplevel);
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    var cl: Client = undefined;
    baseClient(&cl, &m, &xdg, &toplevel, &surface);
    toplevel.app_id = @ptrCast(@constCast("app"));
    toplevel.title = @ptrCast(@constCast("title"));
    surface.mapped = false;

    var r: c.ConfigWinRule = std.mem.zeroes(c.ConfigWinRule);
    r.id = @ptrCast(@constCast("app"));
    r.tags = 0b10;
    r.width = 0.5;
    r.height = 200;
    r.is_once = 1;
    r.isfloating = 1;
    r.scroller_proportion = 0.3;
    c.config.window_rules = &r;
    c.config.window_rules_count = 1;
    stub_center_box = mkBox(400, 300, 500, 200);

    var rule_mon: [*c]Monitor = null;
    var rule_tags: c_uint = 0;
    client_apply_rules(&cl, &rule_mon, &rule_tags);
    try testing.expectEqual(@as(u32, 0b10), rule_tags);
    try testing.expect(rule_mon == &m);
    try testing.expectEqual(@as(i32, 1), cl.isfloating);
    try testing.expectEqual(@as(i32, 500), cl.float_geom.width);
    try testing.expectEqual(@as(i32, 200), cl.float_geom.height);
    try testing.expectEqual(@as(i32, 1), cl.iscustomsize);
    try testing.expectEqual(@as(i32, 1), cl.iscustom_scroller_proportion);
    try testing.expectEqual(@as(i32, 1), r.is_once_applied);
    try testing.expectEqual(@as(c_int, 1), stub_size_bound_calls);
    try testing.expectEqual(@as(c_int, 1), stub_size_per_calls);
    try testing.expectEqual(@as(i32, 400), cl.geom.x);

    client_apply_rules(&cl, &rule_mon, &rule_tags);
    try testing.expectEqual(@as(u32, 0), rule_tags);
    try testing.expectEqual(@as(c_int, 2), stub_update_geometry_calls);
}

test "rules use parent tags, monitor specs and offsets" {
    resetRulesWorld();
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var m: Monitor = std.mem.zeroes(Monitor);
    var m2: Monitor = std.mem.zeroes(Monitor);
    var p2: c.Pertag = std.mem.zeroes(c.Pertag);
    baseMonitor(&m, &p, "DP-1");
    baseMonitor(&m2, &p2, "HDMI-1");
    listInsert(&c.server.monitors, &m.link);
    listInsert(&c.server.monitors, &m2.link);
    c.server.selected_monitor = &m;

    var parent: Client = std.mem.zeroes(Client);
    parent.mon = &m;
    parent.tags = 0b100;
    stub_parent = &parent;

    var xdg: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    var toplevel: c.struct_wlr_xdg_toplevel = std.mem.zeroes(c.struct_wlr_xdg_toplevel);
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    var cl: Client = undefined;
    baseClient(&cl, &m, &xdg, &toplevel, &surface);
    toplevel.app_id = @ptrCast(@constCast("app"));
    toplevel.title = @ptrCast(@constCast("title"));
    surface.mapped = false;

    var r: c.ConfigWinRule = std.mem.zeroes(c.ConfigWinRule);
    r.id = @ptrCast(@constCast("app"));
    r.monitor = @ptrCast(@constCast("HDMI-1"));
    r.offsetx = 10;
    r.offsety = 20;
    c.config.window_rules = &r;
    c.config.window_rules_count = 1;
    stub_center_box = mkBox(50, 60, 300, 200);

    var rule_mon: [*c]Monitor = null;
    var rule_tags: c_uint = 0;
    client_apply_rules(&cl, &rule_mon, &rule_tags);
    try testing.expectEqual(@as(u32, 0b100), rule_tags);
    try testing.expect(rule_mon == &m2);
    try testing.expectEqual(@as(i32, 1), cl.iscustompos);
    try testing.expectEqual(@as(i32, 50), cl.geom.x);
    try testing.expectEqual(@as(c_int, 1), stub_center_calls);
}

test "mapped rule application handles swallow, focus and monitor" {
    resetRulesWorld();
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var m: Monitor = std.mem.zeroes(Monitor);
    baseMonitor(&m, &p, "DP-1");
    c.server.selected_monitor = &m;
    var xdg: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    var toplevel: c.struct_wlr_xdg_toplevel = std.mem.zeroes(c.struct_wlr_xdg_toplevel);
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    var cl: Client = undefined;
    baseClient(&cl, &m, &xdg, &toplevel, &surface);
    toplevel.app_id = @ptrCast(@constCast("app"));
    toplevel.title = @ptrCast(@constCast("title"));
    surface.mapped = true;
    xdg.initial_commit = false;

    var term_mon_p: c.Pertag = std.mem.zeroes(c.Pertag);
    var term_mon: Monitor = std.mem.zeroes(Monitor);
    baseMonitor(&term_mon, &term_mon_p, "DP-2");
    var term: Client = std.mem.zeroes(Client);
    term.mon = &term_mon;
    term.tags = 0b1000;
    stub_terminal = &term;
    stub_pid = 77;

    var r: c.ConfigWinRule = std.mem.zeroes(c.ConfigWinRule);
    r.id = @ptrCast(@constCast("app"));
    r.isopensilent = -1;
    c.config.window_rules = &r;
    c.config.window_rules_count = 1;
    stub_center_box = mkBox(100, 100, 200, 150);

    var rule_mon: [*c]Monitor = null;
    var rule_tags: c_uint = 0;
    client_apply_rules(&cl, &rule_mon, &rule_tags);
    try testing.expectEqual(@as(i32, 77), cl.pid);
    try testing.expect(cl.swallowing == &term);
    try testing.expect(term.swallowdby == &cl);
    try testing.expectEqual(@as(c_int, 1), stub_replace_calls);
    try testing.expectEqual(@as(u32, 0b1000), stub_set_monitor_tags);
    try testing.expect(stub_set_monitor_m == &term_mon);
    try testing.expect(stub_set_monitor_focus);
    try testing.expectEqual(@as(c_int, 1), stub_reparent_group_calls);
    try testing.expectEqual(@as(c_int, 1), stub_apply_fullscreen_calls);

    cl.isopensilent = 1;
    client_apply_rules(&cl, null, null);
    try testing.expect(!stub_set_monitor_focus);
    try testing.expect(stub_reinsert_calls > 0);
}

test "mapped rules clear peer fullscreen, scratchpads and overlays" {
    resetRulesWorld();
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var m: Monitor = std.mem.zeroes(Monitor);
    baseMonitor(&m, &p, "DP-1");
    c.server.selected_monitor = &m;
    m.tagset[0] = 1;
    var xdg: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    var toplevel: c.struct_wlr_xdg_toplevel = std.mem.zeroes(c.struct_wlr_xdg_toplevel);
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    var cl: Client = undefined;
    baseClient(&cl, &m, &xdg, &toplevel, &surface);
    toplevel.app_id = @ptrCast(@constCast("app"));
    toplevel.title = @ptrCast(@constCast("title"));
    surface.mapped = true;
    cl.tags = 1;
    xdg.initial_commit = true;

    var peer_xdg: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    var peer_top: c.struct_wlr_xdg_toplevel = std.mem.zeroes(c.struct_wlr_xdg_toplevel);
    var peer_surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    var peer: Client = undefined;
    baseClient(&peer, &m, &peer_xdg, &peer_top, &peer_surface);
    peer.isfullscreen = 1;
    peer.tags = 1;
    peer_surface.mapped = true;
    listInsert(&c.server.clients, &peer.link);

    var r: c.ConfigWinRule = std.mem.zeroes(c.ConfigWinRule);
    r.id = @ptrCast(@constCast("app"));
    r.isnamedscratchpad = 1;
    r.isoverlay = 1;
    c.config.window_rules = &r;
    c.config.window_rules_count = 1;
    stub_center_box = mkBox(100, 100, 200, 150);
    var scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    cl.scene = &scene;
    var layer_tree: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    c.server.layers[5] = &layer_tree;

    c.config.window_rules_count = 0;
    client_apply_rules(&cl, null, null);
    try testing.expectEqual(@as(c_int, 1), stub_clear_fullscreen_calls);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);

    c.config.window_rules_count = 1;
    client_apply_rules(&cl, null, null);
    try testing.expectEqual(@as(c_int, 1), stub_named_scratchpad_calls);
    try testing.expectEqual(@as(c_int, 1), stub_reparent_calls);
    try testing.expect(stub_reparent_parent == &layer_tree);
    try testing.expectEqual(@as(i32, 1), cl.isnamedscratchpad);
}

test "window snapping aligns to screen and neighbour edges" {
    resetRulesWorld();
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var m: Monitor = std.mem.zeroes(Monitor);
    baseMonitor(&m, &p, "DP-1");
    var xdg: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    var toplevel: c.struct_wlr_xdg_toplevel = std.mem.zeroes(c.struct_wlr_xdg_toplevel);
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    var cl: Client = undefined;
    baseClient(&cl, &m, &xdg, &toplevel, &surface);
    surface.mapped = true;
    cl.isfloating = 1;
    cl.geom = mkBox(890, 5, 100, 100);

    apply_window_snap(&cl);
    try testing.expectEqual(@as(i32, 900), cl.geom.x);
    try testing.expectEqual(@as(i32, 0), cl.geom.y);
    try testing.expectEqual(@as(c_int, 1), stub_resize_calls);
    try testing.expectEqual(@as(i32, 900), stub_resize_geo.x);

    var other_xdg: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    var other_top: c.struct_wlr_xdg_toplevel = std.mem.zeroes(c.struct_wlr_xdg_toplevel);
    var other_surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    var other: Client = undefined;
    baseClient(&other, &m, &other_xdg, &other_top, &other_surface);
    other_surface.mapped = true;
    other.isfloating = 1;
    other.tags = 1;
    other.geom = mkBox(200, 0, 100, 100);
    listInsert(&c.server.clients, &other.link);
    cl.geom = mkBox(310, 0, 100, 100);
    apply_window_snap(&cl);
    try testing.expectEqual(@as(i32, 300), cl.geom.x);

    c.config.snap_distance = 0;
    cl.geom = mkBox(890, 5, 100, 100);
    apply_window_snap(&cl);
    try testing.expectEqual(@as(i32, 890), cl.geom.x);

    cl.isfloating = 0;
    const calls = stub_resize_calls;
    apply_window_snap(&cl);
    try testing.expectEqual(calls, stub_resize_calls);
    cl.isfloating = 1;
    surface.mapped = false;
    apply_window_snap(&cl);
    try testing.expectEqual(calls, stub_resize_calls);
}
