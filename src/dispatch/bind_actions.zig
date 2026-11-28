//! Port of the unguarded action callbacks in dispatch/bind.c
//! (Phase 5, bind cleanup slice, slice 97).

const std = @import("std");
const c = @import("cc");

const Arg = c.Arg;
const Client = c.Client;
const Monitor = c.Monitor;

extern fn client_switch_view(arg: [*c]const Arg, want_animation: bool) callconv(.c) void;
extern fn direction_select(arg: [*c]const Arg) callconv(.c) [*c]Client;
extern fn get_focused_stack_client(sc: [*c]Client, custom_focus_client: [*c]Client) callconv(.c) [*c]Client;
extern fn get_next_stack_client(cl: [*c]Client, reverse: bool) callconv(.c) [*c]Client;
extern fn client_exchange(c1: [*c]Client, c2: [*c]Client) callconv(.c) void;
extern fn client_jump_to_monitor(cl: [*c]Client, m: [*c]Monitor, dir: i32) callconv(.c) bool;
extern fn client_move_to_monitor(cl: [*c]Client, target: [*c]Client, dir: i32) callconv(.c) void;
extern fn dwindle_move_next_to(cl: [*c]Client, target: [*c]Client, ratio: f32, dir: i32) callconv(.c) void;
extern fn pointer_warp_to_client(cl: [*c]const Client) callconv(.c) void;
extern fn monitor_from_direction(dir: c.enum_wlr_direction) callconv(.c) [*c]Monitor;
extern fn is_special_active(m: [*c]const Monitor) callconv(.c) bool;
extern fn is_scroller_layout(m: [*c]Monitor) callconv(.c) bool;
extern fn setgaps(oh: i32, ov: i32, ih: i32, iv: i32) callconv(.c) void;
extern fn create_output(backend: [*c]c.struct_wlr_backend, data: ?*anyopaque) callconv(.c) void;
extern fn wlr_backend_is_multi(backend: [*c]c.struct_wlr_backend) callconv(.c) bool;
extern fn wlr_multi_for_each_backend(backend: [*c]c.struct_wlr_backend, callback: ?*const fn ([*c]c.struct_wlr_backend, ?*anyopaque) callconv(.c) void, data: ?*anyopaque) callconv(.c) void;
extern fn wlr_output_is_headless(output: [*c]c.struct_wlr_output) callconv(.c) bool;
extern fn wlr_output_destroy(output: [*c]c.struct_wlr_output) callconv(.c) void;
extern fn wlr_session_change_vt(session: [*c]c.struct_wlr_session, vt: c_uint) callconv(.c) bool;
extern fn nanosleep(req: *const c.struct_timespec, rem: ?*c.struct_timespec) callconv(.c) c_int;
extern fn acwm_error_impl(log: bool, verbosity: c.enum_wlr_log_importance, file: [*c]const u8, line: c_int, fmt: [*c]const u8, ...) callconv(.c) void;

fn clientFromLink(link: [*c]c.struct_wl_list) *Client {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(Client, "link"));
}

fn monitorFromLink(link: [*c]c.struct_wl_list) *Monitor {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(Monitor, "link"));
}

export fn bind_to_view(arg: [*c]const Arg) callconv(.c) i32 {
    if (c.server.selected_monitor == null)
        return 0;
    var target = arg.*.ui;
    const mon = c.server.selected_monitor;

    if (c.config.view_current_to_back != 0 and mon.*.pertag.*.curtag != 0 and
        (target & c.server.tagmask) == mon.*.tagset[@intCast(mon.*.seltags)])
    {
        if (mon.*.pertag.*.prevtag != 0) {
            target = @as(u32, 1) << @intCast(mon.*.pertag.*.prevtag - 1);
        } else {
            // prevtag==0: previous view was the special workspace, decide by
            // the other tagset.
            target = if ((mon.*.tagset[@intCast(mon.*.seltags ^ 1)] & c.TAG0_MASK) != 0)
                c.TAG0_MASK
            else
                0;
        }
    }

    if (c.config.view_current_to_back == 0 and
        (target & c.server.tagmask) == mon.*.tagset[@intCast(mon.*.seltags)])
        return 0;

    if (@as(i32, @bitCast(target)) == std.math.minInt(i32) and
        mon.*.pertag.*.curtag == 0)
    {
        if (c.config.view_current_to_back != 0 and mon.*.pertag.*.prevtag != 0)
            target = @as(u32, 1) << @intCast(mon.*.pertag.*.prevtag - 1)
        else
            target = 0;
    }

    // TAG0_MASK is INT_MIN too; handle it before the all-tags branch.
    if (target == c.TAG0_MASK) {
        var a = arg.*;
        a.ui = target;
        client_switch_view(&a, true);
        return 0;
    }

    var a = arg.*;
    if (target == 0 or @as(i32, @bitCast(target)) == std.math.minInt(i32)) {
        a.ui = ~@as(u32, 0) & c.server.tagmask;
        client_switch_view(&a, false);
    } else {
        a.ui = target;
        client_switch_view(&a, true);
    }
    return 0;
}

export fn change_vt(arg: [*c]const Arg) callconv(.c) i32 {
    var ts: c.struct_timespec = undefined;

    c.server.allow_frame_scheduling = false;

    if (c.server.selected_monitor != null) {
        c.server.chvt_backup_tag = c.server.selected_monitor.*.pertag.*.curtag;
        _ = c.strncpy(&c.server.chvt_backup_monitor_name,
            c.server.selected_monitor.*.wlr_output.*.name,
            c.server.chvt_backup_monitor_name.len - 1);
    }

    _ = wlr_session_change_vt(c.server.session, arg.*.ui);

    ts.tv_sec = 0;
    ts.tv_nsec = 100000000;
    _ = nanosleep(&ts, null);

    c.server.allow_frame_scheduling = true;
    return 1;
}

export fn create_virtual_output(arg: [*c]const Arg) callconv(.c) i32 {
    if (!wlr_backend_is_multi(c.server.backend)) {
        acwm_error_impl(true, c.WLR_ERROR, "src/dispatch/bind.c", 116, "Expected a multi backend");
        return 0;
    }

    if (arg.*.v != null) {
        const head: [*c]c.struct_wl_list = @ptrCast(&c.server.monitors);
        var pos = c.server.monitors.next;
        while (pos != head) : (pos = pos.*.next) {
            const m = monitorFromLink(pos);
            if (c.strcmp(m.wlr_output.*.name, arg.*.v) == 0) {
                acwm_error_impl(true, c.WLR_ERROR, "src/dispatch/bind.c", 125,
                    "Output '%s' already exists", arg.*.v);
                return 0;
            }
        }
    }

    var done = false;
    c.server.pending_headless_output_name = arg.*.v;
    wlr_multi_for_each_backend(c.server.backend, create_output, &done);
    c.server.pending_headless_output_name = null;

    if (!done) {
        acwm_error_impl(true, c.WLR_ERROR, "src/dispatch/bind.c", 137, "Failed to create virtual output");
        return 0;
    }

    if (arg.*.v != null) {
        acwm_error_impl(true, c.WLR_INFO, "src/dispatch/bind.c", 142,
            "Virtual output '%s' created", arg.*.v);
    } else {
        acwm_error_impl(true, c.WLR_INFO, "src/dispatch/bind.c", 144, "Virtual output created");
    }
    return 0;
}

export fn destroy_all_virtual_output(arg: [*c]const Arg) callconv(.c) i32 {
    _ = arg;
    if (!wlr_backend_is_multi(c.server.backend)) {
        acwm_error_impl(true, c.WLR_ERROR, "src/dispatch/bind.c", 152, "Expected a multi backend");
        return 0;
    }

    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.monitors);
    var pos = c.server.monitors.next;
    while (pos != head) {
        const next = pos.*.next;
        const m = monitorFromLink(pos);
        if (wlr_output_is_headless(m.wlr_output)) {
            wlr_output_destroy(m.wlr_output);
            acwm_error_impl(true, c.WLR_INFO, "src/dispatch/bind.c", 162, "Virtual output destroyed");
        }
        pos = next;
    }
    return 0;
}

export fn reset_gaps(arg: [*c]const Arg) callconv(.c) i32 {
    _ = arg;
    if (c.server.selected_monitor != null and is_special_active(c.server.selected_monitor)) {
        setgaps(@intCast(c.config.special_gappoh), @intCast(c.config.special_gappov),
            @intCast(c.config.special_gappih), @intCast(c.config.special_gappiv));
    } else {
        setgaps(@intCast(c.config.gappoh), @intCast(c.config.gappov),
            @intCast(c.config.gappih), @intCast(c.config.gappiv));
    }
    return 0;
}

export fn exchange_client(arg: [*c]const Arg) callconv(.c) i32 {
    if (c.server.selected_monitor == null)
        return 0;
    const cl = if (arg.*.tc != null) arg.*.tc else c.server.selected_monitor.*.sel;
    if (cl == null or cl.*.isfloating != 0)
        return 0;

    if ((cl.*.isfullscreen != 0 or cl.*.ismaximizescreen != 0) and
        !is_scroller_layout(cl.*.mon))
        return 0;

    var target = direction_select(arg);
    target = get_focused_stack_client(target, arg.*.tc);

    if (target == null)
        return 0;

    client_exchange(cl, target);
    return 0;
}

export fn move_client(arg: [*c]const Arg) callconv(.c) i32 {
    if (c.server.selected_monitor == null)
        return 0;

    const cl = if (arg.*.tc != null) arg.*.tc else c.server.selected_monitor.*.sel;
    if (cl == null or cl.*.mon == null or cl.*.isfloating != 0)
        return 0;

    if ((cl.*.isfullscreen != 0 or cl.*.ismaximizescreen != 0) and
        !is_scroller_layout(cl.*.mon))
        return 0;

    var target = direction_select(arg);

    if (target == null) {
        _ = client_jump_to_monitor(cl, monitor_from_direction(@intCast(arg.*.i)), arg.*.i);
    } else if (target.*.mon != cl.*.mon) {
        client_move_to_monitor(cl, target, arg.*.i);
    } else if (target.*.mon.*.pertag.*.ltidxs[c.get_mon_curtag(target.*.mon)].*.id == c.DWINDLE) {
        dwindle_move_next_to(cl, target, c.config.dwindle_split_ratio, arg.*.i);
    } else {
        target = get_focused_stack_client(target, cl);
        client_exchange(cl, target);
    }

    if (c.config.warpcursor != 0)
        pointer_warp_to_client(cl);
    return 0;
}

export fn exchange_stack_client(arg: [*c]const Arg) callconv(.c) i32 {
    if (c.server.selected_monitor == null)
        return 0;

    const cl = if (arg.*.tc != null) arg.*.tc else c.server.selected_monitor.*.sel;
    if (cl == null or cl.*.isfloating != 0 or cl.*.isfullscreen != 0 or
        cl.*.ismaximizescreen != 0)
        return 0;

    const target = if (arg.*.i == c.NEXT)
        get_next_stack_client(cl, false)
    else
        get_next_stack_client(cl, true);
    if (target != null)
        client_exchange(cl, target);
    return 0;
}
