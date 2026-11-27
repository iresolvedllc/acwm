//! Port of input/trackpad.c (Phase 5, input slice 4, slice 71).

const std = @import("std");
const c = @import("cc");

const Client = c.Client;
const Monitor = c.Monitor;
const Arg = c.Arg;
const GestureBinding = c.GestureBinding;
const FuncType = c.FuncType;

extern fn keyboard_hard_modifiers() callconv(.c) u32;
extern fn keyboard_cancel_pending_release_bind() callconv(.c) void;
extern fn pointer_begin_move_resize(gc: [*c]Client, mode: u32, x: f64, y: f64, arg: u32) callconv(.c) bool;
extern fn pointer_end_grab_client(follow_pointer: bool) callconv(.c) void;
extern fn pointer_process_motion(time: u32, device: [*c]c.struct_wlr_input_device, dx: f64, dy: f64, dx_unaccel: f64, dy_unaccel: f64) callconv(.c) void;
extern fn get_mon_curtag(m: [*c]const Monitor) callconv(.c) u32;
extern fn client_animation_set_progress(cl: [*c]Client, p: f64) callconv(.c) void;
extern fn client_animation_resume(cl: [*c]Client, remaining: f64) callconv(.c) void;
extern fn client_apply_clip(cl: [*c]Client, factor: f32) callconv(.c) void;
extern fn client_focus(cl: [*c]Client, lift: i32) callconv(.c) void;
extern fn request_fresh_all_monitors() callconv(.c) void;
extern fn arrange(m: [*c]Monitor, want_animation: bool, from_view: bool) callconv(.c) void;
extern fn wlr_input_device_is_libinput(device: [*c]c.struct_wlr_input_device) callconv(.c) bool;
extern fn wlr_libinput_get_device_handle(device: [*c]c.struct_wlr_input_device) callconv(.c) ?*c.struct_libinput_device;
extern fn libinput_device_config_tap_get_finger_count(device: [*c]c.struct_libinput_device) callconv(.c) c_int;
extern fn wlr_pointer_gestures_v1_send_swipe_begin(g: [*c]c.struct_wlr_pointer_gestures_v1, seat: [*c]c.struct_wlr_seat, time: u32, fingers: u32) callconv(.c) void;
extern fn wlr_pointer_gestures_v1_send_swipe_update(g: [*c]c.struct_wlr_pointer_gestures_v1, seat: [*c]c.struct_wlr_seat, time: u32, dx: f64, dy: f64) callconv(.c) void;
extern fn wlr_pointer_gestures_v1_send_swipe_end(g: [*c]c.struct_wlr_pointer_gestures_v1, seat: [*c]c.struct_wlr_seat, time: u32, cancelled: bool) callconv(.c) void;
extern fn wlr_pointer_gestures_v1_send_pinch_begin(g: [*c]c.struct_wlr_pointer_gestures_v1, seat: [*c]c.struct_wlr_seat, time: u32, fingers: u32) callconv(.c) void;
extern fn wlr_pointer_gestures_v1_send_pinch_update(g: [*c]c.struct_wlr_pointer_gestures_v1, seat: [*c]c.struct_wlr_seat, time: u32, dx: f64, dy: f64, scale: f64, rotation: f64) callconv(.c) void;
extern fn wlr_pointer_gestures_v1_send_pinch_end(g: [*c]c.struct_wlr_pointer_gestures_v1, seat: [*c]c.struct_wlr_seat, time: u32, cancelled: bool) callconv(.c) void;
extern fn wlr_pointer_gestures_v1_send_hold_begin(g: [*c]c.struct_wlr_pointer_gestures_v1, seat: [*c]c.struct_wlr_seat, time: u32, fingers: u32) callconv(.c) void;
extern fn wlr_pointer_gestures_v1_send_hold_end(g: [*c]c.struct_wlr_pointer_gestures_v1, seat: [*c]c.struct_wlr_seat, time: u32, cancelled: bool) callconv(.c) void;

extern fn view_to_left(arg: [*c]const Arg) callconv(.c) i32;
extern fn view_to_right(arg: [*c]const Arg) callconv(.c) i32;
extern fn view_to_left_have_client(arg: [*c]const Arg) callconv(.c) i32;
extern fn view_to_right_have_client(arg: [*c]const Arg) callconv(.c) i32;
extern fn viewprev_have_client(arg: [*c]const Arg) callconv(.c) i32;
extern fn viewnext_have_client(arg: [*c]const Arg) callconv(.c) i32;
extern fn toggle_overview(arg: [*c]const Arg) callconv(.c) i32;
extern fn enter_overview(arg: [*c]const Arg) callconv(.c) i32;
extern fn leave_overview(arg: [*c]const Arg) callconv(.c) i32;
extern fn focus_direction(arg: [*c]const Arg) callconv(.c) i32;
extern fn move_resize(arg: [*c]const Arg) callconv(.c) i32;

const SWIPE_LOCK_DISTANCE: f64 = 16;
const SWIPE_FLICK_MAX_MS: u32 = 200;

const SwipeDrive = struct {
    active: bool = false,
    consumed: bool = false,
    pan: bool = false,
    drag: bool = false,
    mon: [*c]Monitor = null,
    fingers: u32 = 0,
    start_sel: [*c]Client = null,
    horizontal: bool = false,
    base: f64 = 0,
    dir: f64 = 0,
    prev_axis: f64 = 0,
    avg_speed: f64 = 0,
    speed_points: u32 = 0,
    first_time: u32 = 0,
    last_time: u32 = 0,
    drag_prev_dx: f64 = 0,
    drag_prev_dy: f64 = 0,
    motion: u32 = 0,
    max_delta: f64 = 0,
    func: FuncType = null,
    arg: Arg = std.mem.zeroes(Arg),
};

var swipe_drive: SwipeDrive = .{};
var swipe_active: bool = false;
var swipe_locked: bool = false;
var swipe_horizontal: bool = false;

fn cleanMask(mask: u32) u32 {
    return mask & ~@as(u32, @intCast(c.WLR_MODIFIER_CAPS));
}

fn VISIBLEON(cl: [*c]const Client, m: [*c]const Monitor) bool {
    if (cl == null or m == null or cl.*.mon != m or cl.*.isminimized != 0)
        return false;
    return (cl.*.tags & m.*.tagset[m.*.seltags]) != 0 or cl.*.isglobal != 0 or cl.*.isunglobal != 0;
}

fn ISSCROLLTILED(cl: [*c]const Client) bool {
    return cl != null and cl.*.isfloating == 0 and cl.*.isminimized == 0 and
        cl.*.iskilling == 0 and cl.*.isunglobal == 0;
}

fn ISTILED(cl: [*c]const Client) bool {
    return cl != null and cl.*.isfloating == 0 and cl.*.isminimized == 0 and
        cl.*.iskilling == 0 and cl.*.ismaximizescreen == 0 and
        cl.*.isfullscreen == 0 and cl.*.isunglobal == 0;
}

export fn pointer_is_trackpad(pointer: [*c]c.struct_wlr_pointer) callconv(.c) bool {
    if (c.wlr_input_device_is_libinput(&pointer.*.base)) {
        const device = c.wlr_libinput_get_device_handle(&pointer.*.base);
        if (device != null and c.libinput_device_config_tap_get_finger_count(device) > 0)
            return true;
    }
    return false;
}

export fn check_trackpad_disabled(pointer: [*c]c.struct_wlr_pointer) callconv(.c) bool {
    if (c.config.disable_trackpad == 0)
        return false;
    return pointer_is_trackpad(pointer);
}

export fn trackpad_enabled() callconv(.c) bool {
    return c.config.disable_trackpad == 0;
}

fn fireGestureMotion(motion: u32, fingers: u32) bool {
    var handled = false;
    const mods = keyboard_hard_modifiers();

    var ji: i32 = 0;
    while (ji < c.config.gesture_bindings_count) : (ji += 1) {
        const g = &c.config.gesture_bindings[@intCast(ji)];
        const mode_matches = g.iscommonmode or
            (g.isdefaultmode and c.server.key_mode.isdefault) or
            c.strcmp(&c.server.key_mode.mode[0], &g.mode[0]) == 0;
        if (mode_matches and cleanMask(mods) == cleanMask(g.mod) and
            fingers == g.fingers_count and g.func != null and
            (g.motion == c.ALLDIR or motion == g.motion))
        {
            if (g.func.? == move_resize)
                continue;
            _ = g.func.?(&g.arg);
            handled = true;
        }
    }
    return handled;
}

fn swipeOppositeMotion(motion: u32) u32 {
    if (motion == c.SWIPE_LEFT)
        return c.SWIPE_RIGHT;
    if (motion == c.SWIPE_RIGHT)
        return c.SWIPE_LEFT;
    if (motion == c.SWIPE_UP)
        return c.SWIPE_DOWN;
    return c.SWIPE_UP;
}

export fn trackpad_gesture_drag_active() callconv(.c) bool {
    return swipe_active and swipe_drive.drag and swipe_drive.active;
}

fn viewOppositeFunc(func: FuncType) FuncType {
    if (func == view_to_left)
        return view_to_right;
    if (func == view_to_right)
        return view_to_left;
    if (func == view_to_left_have_client)
        return view_to_right_have_client;
    if (func == view_to_right_have_client)
        return view_to_left_have_client;
    if (func == viewprev_have_client)
        return viewnext_have_client;
    if (func == viewnext_have_client)
        return viewprev_have_client;
    return null;
}

fn swipeFuncIsView(func: FuncType) bool {
    return viewOppositeFunc(func) != null;
}

fn swipeFuncIsOverview(func: FuncType) bool {
    return func == toggle_overview or func == enter_overview or func == leave_overview;
}

fn swipeLayoutIsScroller(m: [*c]Monitor, vertical: ?*bool) bool {
    if (m == null or m.*.pertag == null)
        return false;
    const l = m.*.pertag.*.ltidxs[get_mon_curtag(m)];
    if (l == null)
        return false;
    if (l.*.id == c.VERTICAL_SCROLLER) {
        if (vertical) |v| v.* = true;
        return true;
    }
    if (l.*.id == c.SCROLLER) {
        if (vertical) |v| v.* = false;
        return true;
    }
    return false;
}

fn swipeFuncDrivable(func: FuncType, arg: *const Arg, motion: u32, m: [*c]Monitor) bool {
    if (func == move_resize)
        return true;
    if (swipeFuncIsView(func))
        return true;

    if (func == focus_direction) {
        var vertical = false;
        if (!swipeLayoutIsScroller(m, &vertical))
            return false;
        if (vertical)
            return arg.i == c.UP or arg.i == c.DOWN;
        return arg.i == c.LEFT or arg.i == c.RIGHT;
    }

    if (func == toggle_overview) {
        if (motion != c.SWIPE_UP and motion != c.SWIPE_DOWN)
            return false;
        return if (m.*.isoverview != 0) motion == c.SWIPE_DOWN else motion == c.SWIPE_UP;
    }

    if (func == enter_overview) {
        if (motion != c.SWIPE_UP and motion != c.SWIPE_DOWN)
            return false;
        return m.*.isoverview == 0;
    }

    if (func == leave_overview) {
        if (motion != c.SWIPE_UP and motion != c.SWIPE_DOWN)
            return false;
        return m.*.isoverview != 0;
    }

    return false;
}

fn swipeFindBinding(motion: u32, fingers: u32, out: ?*?*const GestureBinding) bool {
    const mods = keyboard_hard_modifiers();

    var ji: i32 = 0;
    while (ji < c.config.gesture_bindings_count) : (ji += 1) {
        const g = &c.config.gesture_bindings[@intCast(ji)];
        const mode_matches = g.iscommonmode or
            (g.isdefaultmode and c.server.key_mode.isdefault) or
            c.strcmp(&c.server.key_mode.mode[0], &g.mode[0]) == 0;
        if (mode_matches and cleanMask(mods) == cleanMask(g.mod) and
            fingers == g.fingers_count and g.func != null and
            (g.motion == c.ALLDIR or motion == g.motion))
        {
            if (out) |o| o.* = g;
            return true;
        }
    }
    return false;
}

fn swipeHasRunningTransition(m: [*c]Monitor) bool {
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    var pos = c.server.clients.next;
    while (pos != head) : (pos = pos.*.next) {
        const cl = @as([*c]Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Client, "link")));
        if (cl.*.mon != m or !cl.*.animation.running or !cl.*.need_output_flush)
            continue;
        if (cl.*.animation.action == c.TAG or cl.*.animation.action == c.MOVE or
            cl.*.animation.action == c.OVERVIEW or cl.*.animation.tagining or cl.*.animation.tagouting)
            return true;
    }
    return false;
}

fn swipeDriveLogState(m: [*c]Monitor, why: [*:0]const u8, sel_changed: bool, sel_before: [*c]Client) void {
    if (m == null)
        return;

    var visible: c_int = 0;
    var tiled: c_int = 0;
    var running: c_int = 0;
    var geometry: c_int = 0;

    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    var pos = c.server.clients.next;
    while (pos != head) : (pos = pos.*.next) {
        const cl = @as([*c]Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Client, "link")));
        if (cl.*.mon != m)
            continue;
        if (VISIBLEON(cl, m)) {
            visible += 1;
            if (ISTILED(cl))
                tiled += 1;
        }
        if (cl.*.animation.running and cl.*.need_output_flush) {
            running += 1;
            if (cl.*.animation.action == c.TAG or cl.*.animation.action == c.MOVE or
                cl.*.animation.action == c.OVERVIEW)
                geometry += 1;
        }
    }

    c.acwm_error_impl(true, c.WLR_DEBUG, "src/input/trackpad.c", 253,
        "swipe drive: %s (vis=%d tiled=%d run=%d geom=%d sel_changed=%d sel_before=%p sel_now=%p)\n",
        why, visible, tiled, running, geometry, @as(c_int, @intFromBool(sel_changed)),
        @as(?*anyopaque, @ptrCast(sel_before)), @as(?*anyopaque, @ptrCast(m.*.sel)));
}

fn swipeDriveFreeze(m: [*c]Monitor) void {
    c.server.gesture_drive_mon = m;
    c.server.gesture_drive_active = true;
}

fn swipeDriveUnfreeze() void {
    c.server.gesture_drive_active = false;
    c.server.gesture_drive_mon = null;
}

fn swipeDriveAxis() f64 {
    return if (swipe_horizontal) c.server.swipe_dx else c.server.swipe_dy;
}

fn swipeDriveApply(m: [*c]Monitor, p: f64) void {
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    var pos = c.server.clients.next;
    while (pos != head) : (pos = pos.*.next) {
        const cl = @as([*c]Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Client, "link")));
        if (cl.*.mon != m or !cl.*.animation.running or !cl.*.need_output_flush)
            continue;
        if (cl.*.animation.action != c.TAG and cl.*.animation.action != c.MOVE and
            cl.*.animation.action != c.OVERVIEW and !cl.*.animation.tagining and
            !cl.*.animation.tagouting)
            continue;
        client_animation_set_progress(cl, p);
    }
    request_fresh_all_monitors();
}

fn swipeDrivePanTarget(m: [*c]Monitor, offset: f64, out: ?*[*c]Client) bool {
    if (m == null or m.*.sel == null)
        return false;

    const mon_cx = @as(f64, @floatFromInt(m.*.w.x)) + @as(f64, @floatFromInt(m.*.w.width)) / 2.0;
    const mon_cy = @as(f64, @floatFromInt(m.*.w.y)) + @as(f64, @floatFromInt(m.*.w.height)) / 2.0;
    var best: [*c]Client = null;
    var best_dist: f64 = 0;
    const horizontal = swipe_horizontal;

    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    var pos = c.server.clients.next;
    while (pos != head) : (pos = pos.*.next) {
        const cl = @as([*c]Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Client, "link")));
        if (cl.*.mon != m or !VISIBLEON(cl, m) or !ISSCROLLTILED(cl))
            continue;

        var cx = @as(f64, @floatFromInt(cl.*.geom.x)) + @as(f64, @floatFromInt(cl.*.geom.width)) / 2.0;
        var cy = @as(f64, @floatFromInt(cl.*.geom.y)) + @as(f64, @floatFromInt(cl.*.geom.height)) / 2.0;
        if (horizontal)
            cx += offset
        else
            cy += offset;

        const dx = cx - mon_cx;
        const dy = cy - mon_cy;
        const dist = dx * dx + dy * dy;
        if (best == null or dist < best_dist) {
            best = cl;
            best_dist = dist;
        }
    }

    if (out) |o| o.* = best;
    return best != null;
}

fn swipeDriveApplyPan(m: [*c]Monitor, offset: f64) void {
    const horizontal = swipe_horizontal;

    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    var pos = c.server.clients.next;
    while (pos != head) : (pos = pos.*.next) {
        const cl = @as([*c]Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Client, "link")));
        if (cl.*.mon != m or !VISIBLEON(cl, m) or !ISSCROLLTILED(cl))
            continue;

        var box = cl.*.geom;
        const delta: i32 = @intFromFloat(@round(offset));
        if (horizontal)
            box.x += delta
        else
            box.y += delta;

        c.wlr_scene_node_set_position(&cl.*.scene.*.node, box.x, box.y);
        cl.*.animation.current = box;
        cl.*.current = box;
        client_apply_clip(cl, 1.0);
    }
    request_fresh_all_monitors();
}

fn swipeDrivePanOffset(m: [*c]Monitor, raw: f64) f64 {
    var lo: f64 = 0;
    var hi: f64 = 0;
    var first = true;
    const horizontal = swipe_horizontal;
    const mon_center = (if (horizontal)
        @as(f64, @floatFromInt(m.*.w.width))
    else
        @as(f64, @floatFromInt(m.*.w.height))) / 2.0;

    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    var pos = c.server.clients.next;
    while (pos != head) : (pos = pos.*.next) {
        const cl = @as([*c]Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Client, "link")));
        if (cl.*.mon != m or !VISIBLEON(cl, m) or !ISSCROLLTILED(cl))
            continue;

        const center = if (horizontal)
            @as(f64, @floatFromInt(cl.*.geom.x)) + @as(f64, @floatFromInt(cl.*.geom.width)) / 2.0
        else
            @as(f64, @floatFromInt(cl.*.geom.y)) + @as(f64, @floatFromInt(cl.*.geom.height)) / 2.0;
        const center_rel = center - (if (horizontal)
            @as(f64, @floatFromInt(m.*.w.x))
        else
            @as(f64, @floatFromInt(m.*.w.y)));
        const o = mon_center - center_rel;
        if (first) {
            lo = o;
            hi = o;
            first = false;
        } else {
            if (o < lo) lo = o;
            if (o > hi) hi = o;
        }
    }

    if (first)
        return raw;
    if (raw < lo)
        return lo + (raw - lo) * 0.25;
    if (raw > hi)
        return hi + (raw - hi) * 0.25;
    return raw;
}

fn swipeDrivePanFlickTarget(m: [*c]Monitor, dir: f64, out_offset: ?*f64, out: ?*[*c]Client) bool {
    if (m == null or m.*.sel == null)
        return false;

    const horizontal = swipe_horizontal;
    const mon_origin = if (horizontal)
        @as(f64, @floatFromInt(m.*.w.x))
    else
        @as(f64, @floatFromInt(m.*.w.y));
    const mon_center = (if (horizontal)
        @as(f64, @floatFromInt(m.*.w.width))
    else
        @as(f64, @floatFromInt(m.*.w.height))) / 2.0;
    const sel_center = if (horizontal)
        @as(f64, @floatFromInt(m.*.sel.*.geom.x)) + @as(f64, @floatFromInt(m.*.sel.*.geom.width)) / 2.0
    else
        @as(f64, @floatFromInt(m.*.sel.*.geom.y)) + @as(f64, @floatFromInt(m.*.sel.*.geom.height)) / 2.0;
    const base_offset = mon_center - (sel_center - mon_origin);

    var best: [*c]Client = null;
    var best_delta: f64 = 0;
    var best_offset: f64 = 0;

    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    var pos = c.server.clients.next;
    while (pos != head) : (pos = pos.*.next) {
        const cl = @as([*c]Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Client, "link")));
        if (cl.*.mon != m or !VISIBLEON(cl, m) or !ISSCROLLTILED(cl) or cl == m.*.sel)
            continue;

        const center = if (horizontal)
            @as(f64, @floatFromInt(cl.*.geom.x)) + @as(f64, @floatFromInt(cl.*.geom.width)) / 2.0
        else
            @as(f64, @floatFromInt(cl.*.geom.y)) + @as(f64, @floatFromInt(cl.*.geom.height)) / 2.0;
        const offset = mon_center - (center - mon_origin);
        const delta = (offset - base_offset) * dir;
        if (delta <= 0)
            continue;
        if (best == null or delta < best_delta) {
            best = cl;
            best_delta = delta;
            best_offset = offset;
        }
    }

    if (best == null)
        return false;
    if (out_offset) |o| o.* = best_offset;
    if (out) |o| o.* = best;
    return true;
}

fn funcName(func: FuncType) [*:0]const u8 {
    if (func == toggle_overview) return "toggle_overview";
    if (func == enter_overview) return "enter_overview";
    if (func == leave_overview) return "leave_overview";
    if (func == focus_direction) return "focus_direction";
    return "view switch";
}

fn swipeDriveBegin(fingers: u32) bool {
    const m = c.server.selected_monitor;
    if (m == null)
        return false;
    const sel_before = m.*.sel;

    const axis = swipeDriveAxis();
    const motion: u32 = if (swipe_horizontal)
        (if (axis < 0) c.SWIPE_LEFT else c.SWIPE_RIGHT)
    else
        (if (axis < 0) c.SWIPE_UP else c.SWIPE_DOWN);

    var binding: ?*const GestureBinding = null;
    if (!swipeFindBinding(motion, fingers, &binding) or
        !swipeFuncDrivable(binding.?.func, &binding.?.arg, motion, m))
        return false;

    const exec_func = binding.?.func.?;
    const exec_arg = binding.?.arg;

    const drag = exec_func == move_resize;
    if (c.config.gesture_live == 0 and !drag)
        return false;

    swipe_drive.consumed = true;
    swipe_drive.mon = m;
    swipe_drive.fingers = fingers;
    swipe_drive.horizontal = swipe_horizontal;
    swipe_drive.dir = if (axis < 0) -1.0 else 1.0;
    swipe_drive.base = axis - swipe_drive.dir * SWIPE_LOCK_DISTANCE;
    swipe_drive.motion = motion;
    swipe_drive.func = exec_func;
    swipe_drive.arg = exec_arg;
    swipe_drive.active = false;
    swipe_drive.pan = false;
    swipe_drive.drag = false;
    swipe_drive.start_sel = sel_before;

    if (drag) {
        const target = m.*.sel;
        if (!pointer_begin_move_resize(target, exec_arg.ui, c.server.cursor.*.x, c.server.cursor.*.y, 0)) {
            swipe_drive.consumed = false;
            swipeDriveLogState(m, "drag: no window to move", false, sel_before);
            return false;
        }
        swipe_drive.drag = true;
        swipe_drive.active = true;
        swipe_drive.drag_prev_dx = c.server.swipe_dx;
        swipe_drive.drag_prev_dy = c.server.swipe_dy;
        swipeDriveLogState(m, "dragging window", false, sel_before);
        return true;
    }

    if (exec_func == focus_direction) {
        swipe_drive.base = axis;
        swipe_drive.pan = true;
        swipe_drive.active = true;
        swipeDriveFreeze(m);
        swipeDriveApplyPan(m, 0.0);
        swipeDriveLogState(m, "panning scroller", false, sel_before);
        return true;
    }

    swipeDriveFreeze(m);
    _ = exec_func(&exec_arg);

    if (!swipeHasRunningTransition(m)) {
        swipeDriveUnfreeze();
        swipeDriveLogState(m, "fired but no transition", m.*.sel != sel_before, sel_before);
        c.acwm_error_impl(true, c.WLR_DEBUG, "src/input/trackpad.c", 532,
            "swipe drive: %s fired but produced no transition\n", funcName(binding.?.func));
        return true;
    }

    swipe_drive.active = true;
    swipeDriveApply(m, 0.0);
    swipeDriveLogState(m, "driving transition", m.*.sel != sel_before, sel_before);
    c.acwm_error_impl(true, c.WLR_DEBUG, "src/input/trackpad.c", 541,
        "swipe drive: driving transition, motion=%u fingers=%u\n",
        swipe_drive.motion, swipe_drive.fingers);
    return true;
}

fn swipeDriveFireOpposite() bool {
    if (swipe_drive.func == null)
        return false;

    if (swipeFuncIsView(swipe_drive.func)) {
        const opposite = viewOppositeFunc(swipe_drive.func);
        if (opposite == null)
            return false;
        _ = opposite.?(&swipe_drive.arg);
        swipe_drive.func = opposite;
    } else if (swipe_drive.func == focus_direction) {
        var a = swipe_drive.arg;
        if (swipe_drive.motion == c.SWIPE_LEFT)
            a.i = c.RIGHT
        else if (swipe_drive.motion == c.SWIPE_RIGHT)
            a.i = c.LEFT
        else if (swipe_drive.motion == c.SWIPE_UP)
            a.i = c.DOWN
        else
            a.i = c.UP;
        _ = focus_direction(&a);
        swipe_drive.arg = a;
    } else if (swipe_drive.func == toggle_overview) {
        _ = toggle_overview(&swipe_drive.arg);
    } else if (swipe_drive.func == enter_overview) {
        _ = leave_overview(&swipe_drive.arg);
        swipe_drive.func = leave_overview;
    } else if (swipe_drive.func == leave_overview) {
        _ = enter_overview(&swipe_drive.arg);
        swipe_drive.func = enter_overview;
    } else {
        return false;
    }

    swipe_drive.motion = swipeOppositeMotion(swipe_drive.motion);
    swipe_drive.dir = -swipe_drive.dir;
    return true;
}

fn swipeDriveApplyDrag(m: [*c]Monitor, time: u32) void {
    const distance = @as(f64, @floatFromInt(c.config.gesture_swipe_distance));
    if (c.server.grab_client == null or m == null or distance <= 0)
        return;

    const scale_x = @as(f64, @floatFromInt(m.*.w.width)) / distance;
    const scale_y = @as(f64, @floatFromInt(m.*.w.height)) / distance;

    const dx = (c.server.swipe_dx - swipe_drive.drag_prev_dx) * scale_x;
    const dy = (c.server.swipe_dy - swipe_drive.drag_prev_dy) * scale_y;
    swipe_drive.drag_prev_dx = c.server.swipe_dx;
    swipe_drive.drag_prev_dy = c.server.swipe_dy;

    if (dx == 0 and dy == 0)
        return;

    pointer_process_motion(time, null, dx, dy, dx, dy);
    request_fresh_all_monitors();
}

fn swipeDriveUpdate(fingers: u32, time: u32) bool {
    if (!swipe_active)
        return false;

    const adx = @abs(c.server.swipe_dx);
    const ady = @abs(c.server.swipe_dy);
    if (!swipe_locked) {
        if (adx < SWIPE_LOCK_DISTANCE and ady < SWIPE_LOCK_DISTANCE)
            return false;
        swipe_locked = true;
        swipe_horizontal = adx >= ady;
    }

    const axis = swipeDriveAxis();
    const step = @abs(axis - swipe_drive.prev_axis);
    swipe_drive.prev_axis = axis;
    if (swipe_drive.speed_points < 1000) {
        swipe_drive.avg_speed = (swipe_drive.avg_speed * @as(f64, @floatFromInt(swipe_drive.speed_points)) + step) /
            @as(f64, @floatFromInt(swipe_drive.speed_points + 1));
        if (swipe_drive.speed_points == 0)
            swipe_drive.first_time = time;
        swipe_drive.speed_points += 1;
        swipe_drive.last_time = time;
    }

    if (!swipe_drive.active) {
        if (swipe_drive.consumed)
            return true;
        return swipeDriveBegin(fingers);
    }

    const m = swipe_drive.mon;

    if (swipe_drive.drag) {
        swipeDriveApplyDrag(m, time);
        return true;
    }

    const distance = @as(f64, @floatFromInt(c.config.gesture_swipe_distance));
    const delta = (axis - swipe_drive.base) * swipe_drive.dir;
    var p = delta / distance;

    if (swipe_drive.pan) {
        const extent = if (swipe_horizontal)
            @as(f64, @floatFromInt(m.*.w.width))
        else
            @as(f64, @floatFromInt(m.*.w.height));
        const raw = ((axis - swipe_drive.base) / distance) * extent;
        const offset = swipeDrivePanOffset(m, raw);
        swipeDriveApplyPan(m, offset);
        return true;
    }

    if (p >= 1.0) {
        swipeDriveApply(m, 1.0);
        return true;
    }

    if (delta > swipe_drive.max_delta)
        swipe_drive.max_delta = delta;
    if (p < 0)
        p = 0;
    if (p > 1)
        p = 1;
    swipeDriveApply(m, p);
    return true;
}

fn swipeDriveEnd() void {
    const m = swipe_drive.mon;

    if (swipe_drive.drag) {
        pointer_end_grab_client(false);
        swipe_drive.drag = false;
        swipe_drive.active = false;
        swipe_drive.consumed = false;
        swipe_drive.speed_points = 0;
        swipe_drive.avg_speed = 0;
        return;
    }

    if (swipe_drive.active and m != null) {
        if (swipe_drive.pan) {
            const axis = swipeDriveAxis();
            const distance = @as(f64, @floatFromInt(c.config.gesture_swipe_distance));
            const extent = if (swipe_horizontal)
                @as(f64, @floatFromInt(m.*.w.width))
            else
                @as(f64, @floatFromInt(m.*.w.height));
            const raw = ((axis - swipe_drive.base) / distance) * extent;
            var offset = swipeDrivePanOffset(m, raw);

            swipeDriveUnfreeze();

            var target: [*c]Client = null;
            _ = swipeDrivePanTarget(m, offset, &target);

            const dur = swipe_drive.last_time - swipe_drive.first_time;
            const speed_hit = swipe_drive.speed_points > 0 and
                swipe_drive.avg_speed >= c.config.gesture_swipe_min_speed_to_force;
            const quick_hit = swipe_drive.speed_points > 0 and dur <= SWIPE_FLICK_MAX_MS;

            if (target == swipe_drive.start_sel and (speed_hit or quick_hit)) {
                const dir: f64 = if (raw < 0) -1.0 else 1.0;
                var flick_offset = offset;
                if (swipeDrivePanFlickTarget(m, dir, &flick_offset, &target))
                    offset = flick_offset;
            }

            if (target != null and target != swipe_drive.start_sel) {
                c.acwm_error_impl(true, c.WLR_DEBUG, "src/input/trackpad.c", 640,
                    "swipe drive: pan commit, offset=%.0f target=%p\n",
                    offset, @as(?*anyopaque, @ptrCast(target)));

                const shift: i32 = @intFromFloat(@round(offset));
                if (shift != 0) {
                    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
                    var pos = c.server.clients.next;
                    while (pos != head) : (pos = pos.*.next) {
                        const cl = @as([*c]Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Client, "link")));
                        if (cl.*.mon != m or !VISIBLEON(cl, m) or !ISSCROLLTILED(cl))
                            continue;
                        if (swipe_horizontal)
                            cl.*.geom.x += shift
                        else
                            cl.*.geom.y += shift;
                    }
                }

                client_focus(target, 1);
                arrange(m, false, false);
            } else {
                c.acwm_error_impl(true, c.WLR_DEBUG, "src/input/trackpad.c", 664,
                    "swipe drive: pan revert, offset=%.0f\n", offset);
                arrange(m, false, false);
            }

            swipe_drive.active = false;
            swipe_drive.consumed = false;
            swipe_drive.speed_points = 0;
            swipe_drive.avg_speed = 0;
            return;
        }

        const axis = swipeDriveAxis();
        const distance = @as(f64, @floatFromInt(c.config.gesture_swipe_distance));
        const delta = (axis - swipe_drive.base) * swipe_drive.dir;
        var p = delta / distance;
        if (p < 0) p = 0;
        if (p > 1) p = 1;

        const dur = swipe_drive.last_time - swipe_drive.first_time;
        const flick = swipe_drive.speed_points > 0 and
            delta >= swipe_drive.max_delta - SWIPE_LOCK_DISTANCE and
            (swipe_drive.avg_speed >= c.config.gesture_swipe_min_speed_to_force or
                dur <= SWIPE_FLICK_MAX_MS);
        const commit = swipeFuncIsOverview(swipe_drive.func) or
            delta >= distance * c.config.gesture_swipe_cancel_ratio or flick;

        swipeDriveUnfreeze();

        if (commit) {
            c.acwm_error_impl(true, c.WLR_DEBUG, "src/input/trackpad.c", 692,
                "swipe drive: commit, p=%.2f speed=%.1f\n", p, swipe_drive.avg_speed);
            const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
            var pos = c.server.clients.next;
            while (pos != head) : (pos = pos.*.next) {
                const cl = @as([*c]Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Client, "link")));
                if (cl.*.mon != m or !cl.*.animation.running or !cl.*.need_output_flush)
                    continue;
                if (cl.*.animation.action != c.TAG and cl.*.animation.action != c.MOVE and
                    cl.*.animation.action != c.OVERVIEW and !cl.*.animation.tagining and
                    !cl.*.animation.tagouting)
                    continue;
                client_animation_resume(cl, 1.0 - p);
            }
            request_fresh_all_monitors();
            if (c.config.animations == 0)
                pointer_process_motion(0, null, 0, 0, 0, 0);
        } else {
            c.acwm_error_impl(true, c.WLR_DEBUG, "src/input/trackpad.c", 712,
                "swipe drive: revert, p=%.2f speed=%.1f\n", p, swipe_drive.avg_speed);
            _ = swipeDriveFireOpposite();
        }

        swipe_drive.active = false;
    }

    swipe_drive.consumed = false;
    swipe_drive.speed_points = 0;
    swipe_drive.avg_speed = 0;
}

export fn handle_cursor_swipe_begin(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as(*c.struct_wlr_pointer_swipe_begin_event, @ptrCast(@alignCast(data.?)));
    if (!trackpad_enabled())
        return;

    keyboard_cancel_pending_release_bind();
    swipeDriveUnfreeze();
    swipe_active = true;
    swipe_locked = false;
    swipe_horizontal = false;
    swipe_drive = .{};
    c.server.swipe_fingers = event.*.fingers;
    c.server.swipe_dx = 0;
    c.server.swipe_dy = 0;

    wlr_pointer_gestures_v1_send_swipe_begin(c.server.pointer_gestures, c.server.seat, event.*.time_msec, event.*.fingers);
}

export fn handle_cursor_swipe_update(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as(*c.struct_wlr_pointer_swipe_update_event, @ptrCast(@alignCast(data.?)));
    if (!trackpad_enabled())
        return;

    c.server.swipe_fingers = event.*.fingers;
    c.server.swipe_dx += event.*.dx;
    c.server.swipe_dy += event.*.dy;

    _ = swipeDriveUpdate(event.*.fingers, event.*.time_msec);

    wlr_pointer_gestures_v1_send_swipe_update(c.server.pointer_gestures, c.server.seat, event.*.time_msec, event.*.dx, event.*.dy);
}

export fn handle_cursor_swipe_end(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as(*c.struct_wlr_pointer_swipe_end_event, @ptrCast(@alignCast(data.?)));
    if (!trackpad_enabled())
        return;

    const consumed = swipe_drive.consumed;
    swipeDriveEnd();

    if (!consumed and !event.*.cancelled)
        _ = pointer_process_swipe_end(event);

    wlr_pointer_gestures_v1_send_swipe_end(c.server.pointer_gestures, c.server.seat, event.*.time_msec, event.*.cancelled);

    swipe_active = false;
    c.server.swipe_dx = 0;
    c.server.swipe_dy = 0;
}

export fn handle_cursor_pinch_begin(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as(*c.struct_wlr_pointer_pinch_begin_event, @ptrCast(@alignCast(data.?)));
    if (!trackpad_enabled())
        return;
    keyboard_cancel_pending_release_bind();
    wlr_pointer_gestures_v1_send_pinch_begin(c.server.pointer_gestures, c.server.seat, event.*.time_msec, event.*.fingers);
}

export fn handle_cursor_pinch_update(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as(*c.struct_wlr_pointer_pinch_update_event, @ptrCast(@alignCast(data.?)));
    if (!trackpad_enabled())
        return;
    wlr_pointer_gestures_v1_send_pinch_update(c.server.pointer_gestures, c.server.seat, event.*.time_msec, event.*.dx, event.*.dy, event.*.scale, event.*.rotation);
}

export fn handle_cursor_pinch_end(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as(*c.struct_wlr_pointer_pinch_end_event, @ptrCast(@alignCast(data.?)));
    if (!trackpad_enabled())
        return;
    wlr_pointer_gestures_v1_send_pinch_end(c.server.pointer_gestures, c.server.seat, event.*.time_msec, event.*.cancelled);
}

export fn handle_cursor_hold_begin(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as(*c.struct_wlr_pointer_hold_begin_event, @ptrCast(@alignCast(data.?)));
    if (!trackpad_enabled())
        return;
    keyboard_cancel_pending_release_bind();
    wlr_pointer_gestures_v1_send_hold_begin(c.server.pointer_gestures, c.server.seat, event.*.time_msec, event.*.fingers);
}

export fn handle_cursor_hold_end(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as(*c.struct_wlr_pointer_hold_end_event, @ptrCast(@alignCast(data.?)));
    if (!trackpad_enabled())
        return;
    wlr_pointer_gestures_v1_send_hold_end(c.server.pointer_gestures, c.server.seat, event.*.time_msec, event.*.cancelled);
}

export fn pointer_process_swipe_end(event: [*c]c.struct_wlr_pointer_swipe_end_event) callconv(.c) i32 {
    if (event.*.cancelled)
        return 0;

    const adx: u32 = @intFromFloat(@round(@abs(c.server.swipe_dx)));
    const ady: u32 = @intFromFloat(@round(@abs(c.server.swipe_dy)));
    const threshold = c.config.swipe_min_threshold;
    if (@as(u64, adx) * adx + @as(u64, ady) * ady < @as(u64, threshold) * threshold)
        return 0;

    const motion: u32 = if (adx > ady)
        (if (c.server.swipe_dx < 0) c.SWIPE_LEFT else c.SWIPE_RIGHT)
    else
        (if (c.server.swipe_dy < 0) c.SWIPE_UP else c.SWIPE_DOWN);

    return if (fireGestureMotion(motion, c.server.swipe_fingers)) 1 else 0;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/trackpad_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_list_insert_calls: c_int;
extern var stub_is_libinput: bool;
extern var stub_tap_fingers: c_int;
extern var stub_mods: u32;
extern var stub_cancel_release_calls: c_int;
extern var stub_begin_move_ok: bool;
extern var stub_begin_move_calls: c_int;
extern var stub_begin_move_mode: u32;
extern var stub_end_grab_calls: c_int;
extern var stub_motion_calls: c_int;
extern var stub_motion_dx: f64;
extern var stub_motion_dy: f64;
extern var stub_set_progress_calls: c_int;
extern var stub_set_progress: f64;
extern var stub_resume_calls: c_int;
extern var stub_resume_remaining: f64;
extern var stub_clip_calls: c_int;
extern var stub_focus_calls: c_int;
extern var stub_focus_arg: [*c]Client;
extern var stub_fresh_calls: c_int;
extern var stub_arrange_calls: c_int;
extern var stub_scene_pos_calls: c_int;
extern var stub_scene_x: i32;
extern var stub_scene_y: i32;
extern var stub_swipe_begin_calls: c_int;
extern var stub_swipe_update_calls: c_int;
extern var stub_swipe_end_calls: c_int;
extern var stub_pinch_begin_calls: c_int;
extern var stub_pinch_update_calls: c_int;
extern var stub_pinch_end_calls: c_int;
extern var stub_hold_begin_calls: c_int;
extern var stub_hold_end_calls: c_int;
extern var stub_view_left_calls: c_int;
extern var stub_view_right_calls: c_int;
extern var stub_view_left_have_calls: c_int;
extern var stub_view_right_have_calls: c_int;
extern var stub_viewprev_calls: c_int;
extern var stub_viewnext_calls: c_int;
extern var stub_toggle_overview_calls: c_int;
extern var stub_enter_overview_calls: c_int;
extern var stub_leave_overview_calls: c_int;
extern var stub_focus_direction_calls: c_int;
extern var stub_focus_direction_arg: i32;
extern var stub_move_resize_calls: c_int;
extern var stub_error_calls: c_int;

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

var test_cursor: c.struct_wlr_cursor = undefined;

fn resetTrackpadWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    listInit(&c.server.clients);
    test_cursor = std.mem.zeroes(c.struct_wlr_cursor);
    c.server.cursor = &test_cursor;
    c.server.pointer_gestures = @ptrFromInt(0x9000);
    c.server.seat = @ptrFromInt(0x9100);
    swipe_drive = .{};
    swipe_active = false;
    swipe_locked = false;
    swipe_horizontal = false;
    stub_is_libinput = true;
    stub_tap_fingers = 0;
    stub_mods = 0;
    stub_cancel_release_calls = 0;
    stub_begin_move_ok = true;
    stub_begin_move_calls = 0;
    stub_begin_move_mode = 0;
    stub_end_grab_calls = 0;
    stub_motion_calls = 0;
    stub_motion_dx = 0;
    stub_motion_dy = 0;
    stub_set_progress_calls = 0;
    stub_set_progress = 0;
    stub_resume_calls = 0;
    stub_resume_remaining = 0;
    stub_clip_calls = 0;
    stub_focus_calls = 0;
    stub_focus_arg = null;
    stub_fresh_calls = 0;
    stub_arrange_calls = 0;
    stub_scene_pos_calls = 0;
    stub_scene_x = 0;
    stub_scene_y = 0;
    stub_swipe_begin_calls = 0;
    stub_swipe_update_calls = 0;
    stub_swipe_end_calls = 0;
    stub_pinch_begin_calls = 0;
    stub_pinch_update_calls = 0;
    stub_pinch_end_calls = 0;
    stub_hold_begin_calls = 0;
    stub_hold_end_calls = 0;
    stub_view_left_calls = 0;
    stub_view_right_calls = 0;
    stub_view_left_have_calls = 0;
    stub_view_right_have_calls = 0;
    stub_viewprev_calls = 0;
    stub_viewnext_calls = 0;
    stub_toggle_overview_calls = 0;
    stub_enter_overview_calls = 0;
    stub_leave_overview_calls = 0;
    stub_focus_direction_calls = 0;
    stub_focus_direction_arg = 0;
    stub_move_resize_calls = 0;
    stub_error_calls = 0;
}

fn mkMonitor(m: *Monitor, p: *c.Pertag, layout: *c.Layout) void {
    m.* = std.mem.zeroes(Monitor);
    p.* = std.mem.zeroes(c.Pertag);
    m.pertag = p;
    m.w = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
    m.m = m.w;
    m.tagset[0] = 1;
    m.seltags = 0;
    layout.* = std.mem.zeroes(c.Layout);
    p.ltidxs[0] = layout;
    c.server.selected_monitor = m;
}

fn mkClient(cl: *Client, m: *Monitor, x: i32, y: i32, w: i32, h: i32) void {
    cl.* = std.mem.zeroes(Client);
    cl.mon = m;
    cl.tags = 1;
    cl.geom = .{ .x = x, .y = y, .width = w, .height = h };
    cl.animation.running = true;
    cl.animation.action = c.TAG;
    cl.need_output_flush = true;
    listInsert(&c.server.clients, &cl.link);
}

var bindings: [1]c.GestureBinding = undefined;

fn setBinding(func: c.FuncType, motion: u32, fingers: u32) void {
    bindings[0] = std.mem.zeroes(c.GestureBinding);
    bindings[0].iscommonmode = true;
    bindings[0].fingers_count = fingers;
    bindings[0].motion = motion;
    bindings[0].func = func;
    c.config.gesture_bindings = &bindings[0];
    c.config.gesture_bindings_count = 1;
}

test "trackpad detection and global disable" {
    resetTrackpadWorld();
    var pointer: c.struct_wlr_pointer = std.mem.zeroes(c.struct_wlr_pointer);
    try testing.expect(!pointer_is_trackpad(&pointer));
    stub_tap_fingers = 2;
    try testing.expect(pointer_is_trackpad(&pointer));
    try testing.expect(trackpad_enabled());
    try testing.expect(!check_trackpad_disabled(&pointer));

    c.config.disable_trackpad = 1;
    try testing.expect(!trackpad_enabled());
    try testing.expect(check_trackpad_disabled(&pointer));
    var event: c.struct_wlr_pointer_swipe_begin_event = std.mem.zeroes(c.struct_wlr_pointer_swipe_begin_event);
    handle_cursor_swipe_begin(null, &event);
    try testing.expectEqual(@as(c_int, 0), stub_swipe_begin_calls);
    try testing.expect(!swipe_active);
}

test "pinch and hold gestures forward and cancel pending binds" {
    resetTrackpadWorld();
    var pinch_begin: c.struct_wlr_pointer_pinch_begin_event = std.mem.zeroes(c.struct_wlr_pointer_pinch_begin_event);
    pinch_begin.fingers = 3;
    handle_cursor_pinch_begin(null, &pinch_begin);
    var pinch_update: c.struct_wlr_pointer_pinch_update_event = std.mem.zeroes(c.struct_wlr_pointer_pinch_update_event);
    handle_cursor_pinch_update(null, &pinch_update);
    var pinch_end: c.struct_wlr_pointer_pinch_end_event = std.mem.zeroes(c.struct_wlr_pointer_pinch_end_event);
    pinch_end.cancelled = true;
    handle_cursor_pinch_end(null, &pinch_end);
    try testing.expectEqual(@as(c_int, 1), stub_pinch_begin_calls);
    try testing.expectEqual(@as(c_int, 1), stub_pinch_update_calls);
    try testing.expectEqual(@as(c_int, 1), stub_pinch_end_calls);
    try testing.expectEqual(@as(c_int, 1), stub_cancel_release_calls);

    var hold_begin: c.struct_wlr_pointer_hold_begin_event = std.mem.zeroes(c.struct_wlr_pointer_hold_begin_event);
    handle_cursor_hold_begin(null, &hold_begin);
    var hold_end: c.struct_wlr_pointer_hold_end_event = std.mem.zeroes(c.struct_wlr_pointer_hold_end_event);
    handle_cursor_hold_end(null, &hold_end);
    try testing.expectEqual(@as(c_int, 1), stub_hold_begin_calls);
    try testing.expectEqual(@as(c_int, 1), stub_hold_end_calls);
    try testing.expectEqual(@as(c_int, 2), stub_cancel_release_calls);

    c.config.disable_trackpad = 1;
    handle_cursor_pinch_begin(null, &pinch_begin);
    handle_cursor_hold_begin(null, &hold_begin);
    try testing.expectEqual(@as(c_int, 1), stub_pinch_begin_calls);
    try testing.expectEqual(@as(c_int, 1), stub_hold_begin_calls);
}

test "swipe end fires gesture bindings over the threshold" {
    resetTrackpadWorld();
    setBinding(view_to_left, c.ALLDIR, 3);
    var event: c.struct_wlr_pointer_swipe_end_event = std.mem.zeroes(c.struct_wlr_pointer_swipe_end_event);
    c.server.swipe_fingers = 3;
    c.config.swipe_min_threshold = 10;

    c.server.swipe_dx = -20;
    c.server.swipe_dy = 5;
    try testing.expectEqual(@as(i32, 1), pointer_process_swipe_end(&event));
    try testing.expectEqual(@as(c_int, 1), stub_view_left_calls);

    stub_view_left_calls = 0;
    c.server.swipe_dx = 2;
    c.server.swipe_dy = 1;
    try testing.expectEqual(@as(i32, 0), pointer_process_swipe_end(&event));
    try testing.expectEqual(@as(c_int, 0), stub_view_left_calls);

    c.server.swipe_dx = 0;
    c.server.swipe_dy = 30;
    try testing.expectEqual(@as(i32, 1), pointer_process_swipe_end(&event));
    event.cancelled = true;
    try testing.expectEqual(@as(i32, 0), pointer_process_swipe_end(&event));

    resetTrackpadWorld();
    setBinding(move_resize, c.ALLDIR, 3);
    c.server.swipe_fingers = 3;
    c.config.swipe_min_threshold = 10;
    c.server.swipe_dx = 50;
    try testing.expectEqual(@as(i32, 0), pointer_process_swipe_end(&event));
}

test "swipe drives a transition and commits on release" {
    resetTrackpadWorld();
    var p: c.Pertag = undefined;
    var layout: c.Layout = undefined;
    var m: Monitor = undefined;
    mkMonitor(&m, &p, &layout);
    var cl: Client = undefined;
    mkClient(&cl, &m, 0, 0, 100, 100);
    m.sel = &cl;
    setBinding(view_to_left, c.ALLDIR, 3);
    c.config.gesture_live = 1;
    c.config.gesture_swipe_distance = 100;
    c.config.gesture_swipe_cancel_ratio = 0.5;
    c.config.gesture_swipe_min_speed_to_force = 1000;
    c.config.animations = 1;

    var begin: c.struct_wlr_pointer_swipe_begin_event = std.mem.zeroes(c.struct_wlr_pointer_swipe_begin_event);
    begin.fingers = 3;
    handle_cursor_swipe_begin(null, &begin);
    try testing.expectEqual(@as(c_int, 1), stub_swipe_begin_calls);
    try testing.expect(swipe_active);

    var update: c.struct_wlr_pointer_swipe_update_event = std.mem.zeroes(c.struct_wlr_pointer_swipe_update_event);
    update.fingers = 3;
    update.dx = -20;
    update.time_msec = 1000;
    handle_cursor_swipe_update(null, &update);
    try testing.expectEqual(@as(c_int, 1), stub_view_left_calls);
    try testing.expect(c.server.gesture_drive_active);
    try testing.expect(swipe_drive.active);
    try testing.expectEqual(@as(c_int, 1), stub_set_progress_calls);
    try testing.expectEqual(@as(f64, 0), stub_set_progress);

    update.dx = -40;
    update.time_msec = 1100;
    handle_cursor_swipe_update(null, &update);
    try testing.expectApproxEqAbs(@as(f64, 0.56), stub_set_progress, 1e-6);

    var end: c.struct_wlr_pointer_swipe_end_event = std.mem.zeroes(c.struct_wlr_pointer_swipe_end_event);
    end.time_msec = 1200;
    handle_cursor_swipe_end(null, &end);
    try testing.expectEqual(@as(c_int, 1), stub_resume_calls);
    try testing.expectApproxEqAbs(@as(f64, 0.44), stub_resume_remaining, 1e-6);
    try testing.expect(!c.server.gesture_drive_active);
    try testing.expectEqual(@as(c_int, 1), stub_swipe_end_calls);
    try testing.expectEqual(@as(c_int, 0), stub_motion_calls);
}

test "swipe revert fires the opposite action" {
    resetTrackpadWorld();
    var p: c.Pertag = undefined;
    var layout: c.Layout = undefined;
    var m: Monitor = undefined;
    mkMonitor(&m, &p, &layout);
    var cl: Client = undefined;
    mkClient(&cl, &m, 0, 0, 100, 100);
    m.sel = &cl;
    setBinding(view_to_left, c.ALLDIR, 3);
    c.config.gesture_live = 1;
    c.config.gesture_swipe_distance = 100;
    c.config.gesture_swipe_cancel_ratio = 0.9;
    c.config.gesture_swipe_min_speed_to_force = 1000;

    var begin: c.struct_wlr_pointer_swipe_begin_event = std.mem.zeroes(c.struct_wlr_pointer_swipe_begin_event);
    begin.fingers = 3;
    handle_cursor_swipe_begin(null, &begin);
    var update: c.struct_wlr_pointer_swipe_update_event = std.mem.zeroes(c.struct_wlr_pointer_swipe_update_event);
    update.fingers = 3;
    update.dx = -20;
    update.time_msec = 0;
    handle_cursor_swipe_update(null, &update);
    update.dx = -10;
    update.time_msec = 1000;
    handle_cursor_swipe_update(null, &update);

    var end: c.struct_wlr_pointer_swipe_end_event = std.mem.zeroes(c.struct_wlr_pointer_swipe_end_event);
    handle_cursor_swipe_end(null, &end);
    try testing.expectEqual(@as(c_int, 1), stub_view_right_calls);
    try testing.expectEqual(@as(c_int, 0), stub_resume_calls);
    try testing.expect(!c.server.gesture_drive_active);
}

test "scroller pan moves windows and arranges on release" {
    resetTrackpadWorld();
    var p: c.Pertag = undefined;
    var layout: c.Layout = undefined;
    var m: Monitor = undefined;
    mkMonitor(&m, &p, &layout);
    layout.id = c.SCROLLER;
    var cl: Client = undefined;
    mkClient(&cl, &m, 0, 0, 100, 100);
    m.sel = &cl;
    var other: Client = undefined;
    mkClient(&other, &m, 200, 0, 100, 100);
    var scene1: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var scene2: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    cl.scene = &scene1;
    other.scene = &scene2;
    setBinding(focus_direction, c.ALLDIR, 3);
    bindings[0].arg.i = c.LEFT;
    c.config.gesture_live = 1;
    c.config.gesture_swipe_distance = 100;

    var begin: c.struct_wlr_pointer_swipe_begin_event = std.mem.zeroes(c.struct_wlr_pointer_swipe_begin_event);
    begin.fingers = 3;
    handle_cursor_swipe_begin(null, &begin);
    var update: c.struct_wlr_pointer_swipe_update_event = std.mem.zeroes(c.struct_wlr_pointer_swipe_update_event);
    update.fingers = 3;
    update.dx = -20;
    update.time_msec = 100;
    handle_cursor_swipe_update(null, &update);
    try testing.expect(swipe_drive.pan);
    try testing.expect(swipe_drive.active);
    try testing.expect(c.server.gesture_drive_active);
    try testing.expectEqual(@as(c_int, 2), stub_scene_pos_calls);

    update.dx = -40;
    update.time_msec = 200;
    handle_cursor_swipe_update(null, &update);
    try testing.expect(stub_scene_pos_calls >= 2);
    try testing.expect(stub_scene_x > 0);

    var end: c.struct_wlr_pointer_swipe_end_event = std.mem.zeroes(c.struct_wlr_pointer_swipe_end_event);
    handle_cursor_swipe_end(null, &end);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);
    try testing.expect(!c.server.gesture_drive_active);
    try testing.expect(!swipe_drive.active);
}

test "drag mode grabs and releases the client" {
    resetTrackpadWorld();
    var p: c.Pertag = undefined;
    var layout: c.Layout = undefined;
    var m: Monitor = undefined;
    mkMonitor(&m, &p, &layout);
    var cl: Client = undefined;
    mkClient(&cl, &m, 0, 0, 100, 100);
    m.sel = &cl;
    setBinding(move_resize, c.ALLDIR, 3);
    bindings[0].arg.ui = 7;
    c.config.gesture_live = 0;
    c.config.gesture_swipe_distance = 100;
    test_cursor.x = 10;
    test_cursor.y = 20;

    var begin: c.struct_wlr_pointer_swipe_begin_event = std.mem.zeroes(c.struct_wlr_pointer_swipe_begin_event);
    begin.fingers = 3;
    handle_cursor_swipe_begin(null, &begin);
    var update: c.struct_wlr_pointer_swipe_update_event = std.mem.zeroes(c.struct_wlr_pointer_swipe_update_event);
    update.fingers = 3;
    update.dx = -30;
    update.time_msec = 50;
    handle_cursor_swipe_update(null, &update);
    try testing.expectEqual(@as(c_int, 1), stub_begin_move_calls);
    try testing.expectEqual(@as(u32, 7), stub_begin_move_mode);
    try testing.expect(trackpad_gesture_drag_active());
    try testing.expect(swipe_drive.drag);

    update.dx = -10;
    update.time_msec = 60;
    handle_cursor_swipe_update(null, &update);
    try testing.expectEqual(@as(c_int, 1), stub_motion_calls);
    try testing.expectApproxEqAbs(@as(f64, -100), stub_motion_dx, 1e-6);

    var end: c.struct_wlr_pointer_swipe_end_event = std.mem.zeroes(c.struct_wlr_pointer_swipe_end_event);
    handle_cursor_swipe_end(null, &end);
    try testing.expectEqual(@as(c_int, 1), stub_end_grab_calls);
    try testing.expect(!trackpad_gesture_drag_active());

    resetTrackpadWorld();
    mkMonitor(&m, &p, &layout);
    mkClient(&cl, &m, 0, 0, 100, 100);
    m.sel = &cl;
    setBinding(move_resize, c.ALLDIR, 3);
    c.config.gesture_live = 0;
    c.config.gesture_swipe_distance = 100;
    stub_begin_move_ok = false;
    handle_cursor_swipe_begin(null, &begin);
    update.dx = -30;
    handle_cursor_swipe_update(null, &update);
    try testing.expect(!swipe_drive.drag);
    try testing.expect(!swipe_drive.consumed);
}

test "swipe lock waits for distance and picks the dominant axis" {
    resetTrackpadWorld();
    var p: c.Pertag = undefined;
    var layout: c.Layout = undefined;
    var m: Monitor = undefined;
    mkMonitor(&m, &p, &layout);
    var cl: Client = undefined;
    mkClient(&cl, &m, 0, 0, 100, 100);
    m.sel = &cl;
    setBinding(view_to_left, c.ALLDIR, 3);
    c.config.gesture_live = 1;
    c.config.gesture_swipe_distance = 100;

    var begin: c.struct_wlr_pointer_swipe_begin_event = std.mem.zeroes(c.struct_wlr_pointer_swipe_begin_event);
    handle_cursor_swipe_begin(null, &begin);
    var update: c.struct_wlr_pointer_swipe_update_event = std.mem.zeroes(c.struct_wlr_pointer_swipe_update_event);
    update.fingers = 3;
    update.dx = 5;
    update.dy = 8;
    handle_cursor_swipe_update(null, &update);
    try testing.expect(!swipe_locked);
    try testing.expectEqual(@as(c_int, 0), stub_view_left_calls);

    update.dy = 10;
    handle_cursor_swipe_update(null, &update);
    try testing.expect(swipe_locked);
    try testing.expect(!swipe_horizontal);
    try testing.expectEqual(@as(c_int, 1), stub_view_left_calls);
}
