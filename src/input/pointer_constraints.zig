//! Port of input/pointer.c, part 1: constraints, confine, axis/button,
//! pointer configuration and absolute motion (Phase 5, input slice 6, slice 73).

const std = @import("std");
const c = @import("cc");
const build_options = @import("build_options");

const Client = c.Client;
const Monitor = c.Monitor;
const LayerSurface = c.LayerSurface;
const InputDevice = c.InputDevice;
const PointerConstraint = c.PointerConstraint;
const LastCursor = c.LastCursor;
const Box = c.struct_wlr_box;
const Constraint = c.struct_wlr_pointer_constraint_v1;

extern fn client_is_x11(cl: [*c]Client) callconv(.c) i32;
extern fn client_surface(cl: [*c]Client) callconv(.c) [*c]c.struct_wlr_surface;
extern fn client_focus(cl: [*c]Client, lift: i32) callconv(.c) void;
extern fn client_focus_top(m: [*c]Monitor) callconv(.c) [*c]Client;
extern fn toplevel_from_wlr_surface(s: [*c]c.struct_wlr_surface, pc: [*c][*c]Client, pl: [*c][*c]LayerSurface) callconv(.c) i32;
extern fn pointer_process_motion(time: u32, device: [*c]c.struct_wlr_input_device, dx: f64, dy: f64, dx_unaccel: f64, dy_unaccel: f64) callconv(.c) void;
extern fn pointer_process_button_press(event: [*c]c.struct_wlr_pointer_button_event) callconv(.c) bool;
extern fn pointer_cursor_activity() callconv(.c) void;
extern fn pointer_is_trackpad(pointer: [*c]c.struct_wlr_pointer) callconv(.c) bool;
extern fn check_trackpad_disabled(pointer: [*c]c.struct_wlr_pointer) callconv(.c) bool;
extern fn keyboard_hard_modifiers() callconv(.c) u32;
extern fn keyboard_cancel_pending_release_bind() callconv(.c) void;
extern fn acwm_notify_activity(seat: [*c]c.struct_wlr_seat) callconv(.c) void;
extern fn ipc_notify_device_event(dev: [*c]c.struct_wlr_input_device) callconv(.c) void;
extern fn toggle_overview(arg: [*c]const c.Arg) callconv(.c) i32;
extern fn find_device_rule(device: [*c]c.struct_wlr_input_device) callconv(.c) [*c]c.ConfigDeviceRule;
extern fn wlr_input_device_is_libinput(device: [*c]c.struct_wlr_input_device) callconv(.c) bool;
extern fn wlr_libinput_get_device_handle(device: [*c]c.struct_wlr_input_device) callconv(.c) ?*c.struct_libinput_device;
extern fn handle_input_device_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn wlr_cursor_attach_input_device(cursor: [*c]c.struct_wlr_cursor, device: [*c]c.struct_wlr_input_device) callconv(.c) void;
extern fn wlr_cursor_warp(cursor: [*c]c.struct_wlr_cursor, device: [*c]c.struct_wlr_input_device, x: f64, y: f64) callconv(.c) bool;
extern fn wlr_cursor_warp_absolute(cursor: [*c]c.struct_wlr_cursor, device: [*c]c.struct_wlr_input_device, x: f64, y: f64) callconv(.c) void;
extern fn wlr_cursor_absolute_to_layout_coords(cursor: [*c]c.struct_wlr_cursor, device: [*c]c.struct_wlr_input_device, x: f64, y: f64, lx: *f64, ly: *f64) callconv(.c) void;
extern fn wlr_cursor_set_xcursor(cursor: [*c]c.struct_wlr_cursor, manager: [*c]c.struct_wlr_xcursor_manager, name: [*c]const u8) callconv(.c) void;
extern fn wlr_cursor_shape_v1_name(shape: c.enum_wp_cursor_shape_device_v1_shape) callconv(.c) [*c]const u8;
extern fn wlr_seat_pointer_warp(seat: [*c]c.struct_wlr_seat, x: f64, y: f64) callconv(.c) void;
extern fn wlr_seat_pointer_notify_frame(seat: [*c]c.struct_wlr_seat) callconv(.c) void;
extern fn wlr_seat_pointer_notify_axis(seat: [*c]c.struct_wlr_seat, time: u32, orientation: c.enum_wl_pointer_axis, value: f64, value_discrete: i32, source: c.enum_wl_pointer_axis_source, rel: c.enum_wl_pointer_axis_relative_direction) callconv(.c) void;
extern fn wlr_seat_pointer_notify_button(seat: [*c]c.struct_wlr_seat, time: u32, button: u32, state: c.enum_wl_pointer_button_state) callconv(.c) u32;
extern fn wlr_box_contains_point(box: *const Box, x: f64, y: f64) callconv(.c) bool;
extern fn wlr_box_closest_point(box: *const Box, x: f64, y: f64, dx: *f64, dy: *f64) callconv(.c) void;
extern fn pixman_region32_not_empty(region: *c.pixman_region32_t) callconv(.c) bool;
extern fn pixman_region32_empty(region: *c.pixman_region32_t) callconv(.c) bool;
extern fn pixman_region32_copy(dst: *c.pixman_region32_t, src: *c.pixman_region32_t) callconv(.c) void;
extern fn pixman_region32_intersect(dst: *c.pixman_region32_t, a: *c.pixman_region32_t, b: *c.pixman_region32_t) callconv(.c) bool;
extern fn pixman_region32_contains_point(region: *c.pixman_region32_t, x: i32, y: i32, box: ?*c.pixman_box32_t) callconv(.c) bool;
extern fn pixman_region32_rectangles(region: *c.pixman_region32_t, n: *c_int) callconv(.c) [*c]c.pixman_box32_t;
extern fn wlr_pointer_constraints_v1_constraint_for_surface(constraints: [*c]c.struct_wlr_pointer_constraints_v1, surface: [*c]c.struct_wlr_surface, seat: [*c]c.struct_wlr_seat) callconv(.c) [*c]Constraint;
extern fn wlr_pointer_constraint_v1_send_activated(constraint: [*c]Constraint) callconv(.c) void;
extern fn wlr_pointer_constraint_v1_send_deactivated(constraint: [*c]Constraint) callconv(.c) void;
extern fn libinput_device_config_scroll_set_natural_scroll_enabled(device: ?*c.struct_libinput_device, enabled: bool) callconv(.c) c_int;
extern fn libinput_device_config_accel_is_available(device: ?*c.struct_libinput_device) callconv(.c) bool;
extern fn libinput_device_config_accel_set_profile(device: ?*c.struct_libinput_device, profile: u32) callconv(.c) c_int;
extern fn libinput_device_config_accel_set_speed(device: ?*c.struct_libinput_device, speed: f64) callconv(.c) c_int;
extern fn libinput_device_config_tap_get_finger_count(device: ?*c.struct_libinput_device) callconv(.c) c_int;
extern fn libinput_device_config_tap_set_enabled(device: ?*c.struct_libinput_device, enabled: bool) callconv(.c) c_int;
extern fn libinput_device_config_tap_set_drag_enabled(device: ?*c.struct_libinput_device, enabled: bool) callconv(.c) c_int;
extern fn libinput_device_config_tap_set_drag_lock_enabled(device: ?*c.struct_libinput_device, enabled: bool) callconv(.c) c_int;
extern fn libinput_device_config_tap_set_button_map(device: ?*c.struct_libinput_device, map: u32) callconv(.c) c_int;
extern fn libinput_device_config_dwt_is_available(device: ?*c.struct_libinput_device) callconv(.c) bool;
extern fn libinput_device_config_dwt_set_enabled(device: ?*c.struct_libinput_device, enabled: bool) callconv(.c) c_int;
extern fn libinput_device_config_left_handed_is_available(device: ?*c.struct_libinput_device) callconv(.c) bool;
extern fn libinput_device_config_left_handed_set(device: ?*c.struct_libinput_device, left: bool) callconv(.c) c_int;
extern fn libinput_device_config_middle_emulation_is_available(device: ?*c.struct_libinput_device) callconv(.c) bool;
extern fn libinput_device_config_middle_emulation_set_enabled(device: ?*c.struct_libinput_device, enabled: bool) callconv(.c) c_int;
extern fn libinput_device_config_scroll_get_methods(device: ?*c.struct_libinput_device) callconv(.c) u32;
extern fn libinput_device_config_scroll_set_method(device: ?*c.struct_libinput_device, method: u32) callconv(.c) c_int;
extern fn libinput_device_config_scroll_set_button(device: ?*c.struct_libinput_device, button: u32) callconv(.c) c_int;
extern fn libinput_device_config_click_get_methods(device: ?*c.struct_libinput_device) callconv(.c) u32;
extern fn libinput_device_config_click_set_method(device: ?*c.struct_libinput_device, method: u32) callconv(.c) c_int;
extern fn libinput_device_config_send_events_get_modes(device: ?*c.struct_libinput_device) callconv(.c) u32;
extern fn libinput_device_config_send_events_set_mode(device: ?*c.struct_libinput_device, mode: u32) callconv(.c) c_int;

extern var last_cursor: LastCursor;
extern var pointer_locked_applied: bool;
var pointer_hint_applied: bool = false;
var pointer_hint_x: f64 = 0;
var pointer_hint_y: f64 = 0;
var confine_pointer_last: [*c]Client = null;

fn VISIBLEON(cl: [*c]const Client, m: [*c]const Monitor) bool {
    if (cl == null or m == null or cl.*.mon != m or cl.*.isminimized != 0)
        return false;
    return (cl.*.tags & m.*.tagset[m.*.seltags]) != 0 or cl.*.isglobal != 0 or cl.*.isunglobal != 0;
}

export fn pointer_surface_scale(cl: [*c]Client) callconv(.c) f64 {
    if (build_options.xwayland and cl != null and client_is_x11(cl) != 0 and
        c.config.xwayland_ignore_scale != 0 and cl.*.xwayland_scale > 0)
        return cl.*.xwayland_scale;
    return 1.0;
}

fn pointerConstraintSyncRegion(constraint: [*c]Constraint) void {
    if (constraint == null)
        return;
    if (c.pixman_region32_not_empty(&constraint.*.current.region) != 0) {
        _ = c.pixman_region32_intersect(&constraint.*.region, &constraint.*.surface.*.input_region, &constraint.*.current.region);
    } else {
        _ = c.pixman_region32_copy(&constraint.*.region, &constraint.*.surface.*.input_region);
    }
}

fn pointerRegionClosestPoint(region: *c.pixman_region32_t, x: f64, y: f64, cx: *f64, cy: *f64) void {
    var nrects: c_int = 0;
    const rects = c.pixman_region32_rectangles(region, &nrects);
    var best_dist: f64 = 0;
    cx.* = x;
    cy.* = y;
    var i: c_int = 0;
    while (i < nrects) : (i += 1) {
        const r = rects[@intCast(i)];
        const px = @min(@max(x, @as(f64, @floatFromInt(r.x1))), @as(f64, @floatFromInt(r.x2 - 1)));
        const py = @min(@max(y, @as(f64, @floatFromInt(r.y1))), @as(f64, @floatFromInt(r.y2 - 1)));
        const dist = (px - x) * (px - x) + (py - y) * (py - y);
        if (i == 0 or dist < best_dist) {
            best_dist = dist;
            cx.* = px;
            cy.* = py;
        }
    }
}

export fn pointer_client_warp_box(cl: [*c]Client) callconv(.c) Box {
    var box = cl.*.animation.current;
    if (box.width <= 0 or box.height <= 0 or box.x < cl.*.geom.x or box.y < cl.*.geom.y or
        box.x + box.width > cl.*.geom.x + cl.*.geom.width or
        box.y + box.height > cl.*.geom.y + cl.*.geom.height)
        box = cl.*.geom;
    return box;
}

fn pointerConstraintHintPosition(constraint: [*c]Constraint, cl: [*c]Client, lx: *f64, ly: *f64) bool {
    if (cl == null or constraint == null or !constraint.*.current.cursor_hint.enabled)
        return false;
    const box = pointer_client_warp_box(cl);
    const scale = pointer_surface_scale(cl);
    var x = @as(f64, @floatFromInt(box.x)) + @as(f64, @floatFromInt(cl.*.bw)) + constraint.*.current.cursor_hint.x / scale;
    var y = @as(f64, @floatFromInt(box.y)) + @as(f64, @floatFromInt(cl.*.bw)) + constraint.*.current.cursor_hint.y / scale;
    if (!c.wlr_box_contains_point(&cl.*.geom, x, y))
        return false;
    if (cl.*.mon != null)
        c.wlr_box_closest_point(&cl.*.mon.*.m, x, y, &x, &y);
    lx.* = x;
    ly.* = y;
    return true;
}

export fn pointer_locked_constraint_applies(cl: [*c]Client, constraint: [*c]Constraint) callconv(.c) bool {
    if (cl == null or c.pixman_region32_empty(&constraint.*.region) != 0)
        return true;
    const scale = pointer_surface_scale(cl);
    const box = pointer_client_warp_box(cl);
    const sx = (c.server.cursor.*.x - @as(f64, @floatFromInt(box.x)) - @as(f64, @floatFromInt(cl.*.bw))) * scale;
    const sy = (c.server.cursor.*.y - @as(f64, @floatFromInt(box.y)) - @as(f64, @floatFromInt(cl.*.bw))) * scale;
    return c.pixman_region32_contains_point(&constraint.*.region, @intFromFloat(@floor(sx)), @intFromFloat(@floor(sy)), null) != 0;
}

export fn pointer_follow_constraint_hint(constraint: [*c]Constraint, cl: [*c]Client) callconv(.c) void {
    var lx: f64 = 0;
    var ly: f64 = 0;
    if (!pointerConstraintHintPosition(constraint, cl, &lx, &ly))
        return;
    if (pointer_hint_applied and pointer_hint_x == lx and pointer_hint_y == ly)
        return;
    pointer_hint_applied = true;
    pointer_hint_x = lx;
    pointer_hint_y = ly;
    _ = c.wlr_cursor_warp(c.server.cursor, null, lx, ly);
    c.wlr_seat_pointer_warp(constraint.*.seat, constraint.*.current.cursor_hint.x, constraint.*.current.cursor_hint.y);
}

fn pointerCursorOutsideClient(cl: [*c]Client) bool {
    const box = pointer_client_warp_box(cl);
    return c.server.cursor.*.x < @as(f64, @floatFromInt(box.x)) or
        c.server.cursor.*.y < @as(f64, @floatFromInt(box.y)) or
        c.server.cursor.*.x >= @as(f64, @floatFromInt(box.x + box.width)) or
        c.server.cursor.*.y >= @as(f64, @floatFromInt(box.y + box.height));
}

fn pointerNodeEnabled(node: [*c]c.struct_wlr_scene_node) bool {
    var n = node;
    while (n != null) : (n = if (n.*.parent != null) &n.*.parent.*.node else null) {
        if (!n.*.enabled)
            return false;
    }
    return true;
}

fn pointerClientVisible(cl: [*c]Client) bool {
    return cl != null and cl.*.mon != null and cl.*.mon.*.isoverview == 0 and
        client_surface(cl).*.mapped and VISIBLEON(cl, cl.*.mon);
}

export fn pointer_confine_rule_client() callconv(.c) [*c]Client {
    var cl: [*c]Client = null;
    if (c.server.seat.*.keyboard_state.focused_surface != null)
        _ = toplevel_from_wlr_surface(c.server.seat.*.keyboard_state.focused_surface, &cl, null);
    if (cl == null and c.server.selected_monitor != null)
        cl = c.server.selected_monitor.*.sel;
    if (cl == null or cl.*.confine_pointer == 0 or client_surface(cl) == null or
        !client_surface(cl).*.mapped or cl.*.mon == null or cl.*.mon.*.isoverview != 0 or
        cl.*.isminimized != 0 or !VISIBLEON(cl, cl.*.mon) or cl.*.scene == null or
        !pointerNodeEnabled(&cl.*.scene.*.node))
        return null;
    return cl;
}

export fn pointer_check_confine_client() callconv(.c) void {
    const cl = pointer_confine_rule_client();
    if (cl != null and cl != confine_pointer_last and pointerCursorOutsideClient(cl)) {
        const box = pointer_client_warp_box(cl);
        _ = c.wlr_cursor_warp(c.server.cursor, null, @as(f64, @floatFromInt(box.x)) + @as(f64, @floatFromInt(box.width)) / 2.0, @as(f64, @floatFromInt(box.y)) + @as(f64, @floatFromInt(box.height)) / 2.0);
    }
    confine_pointer_last = cl;
}

export fn pointer_client_destroyed(cl: [*c]Client) callconv(.c) void {
    if (confine_pointer_last == cl)
        confine_pointer_last = null;
}

export fn pointer_constraint_surface_visible(constraint: [*c]Constraint) callconv(.c) bool {
    var cl: [*c]Client = null;
    var l: [*c]LayerSurface = null;
    _ = toplevel_from_wlr_surface(constraint.*.surface, &cl, &l);
    if (cl != null)
        return pointerClientVisible(cl);
    if (l != null and l.*.scene != null)
        return pointerNodeEnabled(&l.*.scene.*.node);
    return false;
}

fn pointerWarpIntoConstraint(constraint: [*c]Constraint, cl: [*c]Client) void {
    if (cl == null or cl.*.mon == null or cl.*.mon.*.isoverview != 0 or
        !pointer_constraint_surface_visible(constraint))
        return;

    var lx: f64 = 0;
    var ly: f64 = 0;
    if (pointerConstraintHintPosition(constraint, cl, &lx, &ly) and pointerCursorOutsideClient(cl)) {
        _ = c.wlr_cursor_warp(c.server.cursor, null, lx, ly);
        return;
    }

    const scale = pointer_surface_scale(cl);
    const region = &constraint.*.region;
    const box = pointer_client_warp_box(cl);
    const sx = (c.server.cursor.*.x - @as(f64, @floatFromInt(box.x)) - @as(f64, @floatFromInt(cl.*.bw))) * scale;
    const sy = (c.server.cursor.*.y - @as(f64, @floatFromInt(box.y)) - @as(f64, @floatFromInt(cl.*.bw))) * scale;
    if (c.pixman_region32_empty(region) != 0 or
        c.pixman_region32_contains_point(region, @intFromFloat(@floor(sx)), @intFromFloat(@floor(sy)), null) != 0)
        return;

    var cx: f64 = 0;
    var cy: f64 = 0;
    pointerRegionClosestPoint(region, sx, sy, &cx, &cy);
    _ = c.wlr_cursor_warp(c.server.cursor, null, @as(f64, @floatFromInt(box.x)) + @as(f64, @floatFromInt(cl.*.bw)) + cx / scale, @as(f64, @floatFromInt(box.y)) + @as(f64, @floatFromInt(cl.*.bw)) + cy / scale);
}

export fn pointer_confine_client(constraint_out: [*c][*c]Constraint) callconv(.c) [*c]Client {
    var constraint: [*c]Constraint = c.server.active_constraint;
    var cl: [*c]Client = null;

    if (constraint != null) {
        _ = toplevel_from_wlr_surface(constraint.*.surface, &cl, null);
        if (cl != null and pointer_constraint_surface_visible(constraint)) {
            constraint_out.* = constraint;
            return cl;
        }
        constraint_out.* = null;
        return null;
    }

    constraint_out.* = null;
    var fc: [*c]Client = null;
    var candidates = [_][*c]Client{ null, null };
    const kbd_focus = c.server.seat.*.keyboard_state.focused_surface;
    if (kbd_focus != null)
        _ = toplevel_from_wlr_surface(kbd_focus, &fc, null);
    candidates[0] = fc;
    candidates[1] = if (c.server.selected_monitor != null) c.server.selected_monitor.*.sel else null;

    var i: usize = 0;
    while (i < 2) : (i += 1) {
        const cc = candidates[i];
        if (cc == null or !pointerClientVisible(cc) or (i == 1 and cc == candidates[0]))
            continue;
        constraint = c.wlr_pointer_constraints_v1_constraint_for_surface(c.server.pointer_constraints, client_surface(cc), c.server.seat);
        if (constraint != null) {
            pointer_constrain_cursor(constraint);
            constraint_out.* = constraint;
            return cc;
        }
    }
    return null;
}

export fn toggle_hotarea(x_root: i32, y_root: i32) callconv(.c) void {
    var arg = std.mem.zeroes(c.Arg);
    if (c.server.selected_monitor == null)
        return;
    if (c.server.grab_client != null)
        return;

    const m = c.server.selected_monitor;
    if (c.config.hotarea_disable_on_fullscreen == 1) {
        const focused = m.*.sel;
        if (focused != null and focused.*.isfullscreen != 0 and VISIBLEON(focused, m)) {
            m.*.is_in_hotarea = 0;
            return;
        }
    }

    var hx: u32 = 0;
    var hy: u32 = 0;
    switch (c.config.hotarea_corner) {
        c.BOTTOM_RIGHT => {
            hx = @intCast(m.*.m.x + m.*.m.width - c.config.hotarea_size);
            hy = @intCast(m.*.m.y + m.*.m.height - c.config.hotarea_size);
        },
        c.TOP_LEFT => {
            hx = @intCast(m.*.m.x + c.config.hotarea_size);
            hy = @intCast(m.*.m.y + c.config.hotarea_size);
        },
        c.TOP_RIGHT => {
            hx = @intCast(m.*.m.x + m.*.m.width - c.config.hotarea_size);
            hy = @intCast(m.*.m.y + c.config.hotarea_size);
        },
        else => {
            hx = @intCast(m.*.m.x + c.config.hotarea_size);
            hy = @intCast(m.*.m.y + m.*.m.height - c.config.hotarea_size);
        },
    }

    var in_hotarea = false;
    switch (c.config.hotarea_corner) {
        c.BOTTOM_RIGHT => in_hotarea = y_root > hy and x_root > hx and
            x_root <= m.*.m.x + m.*.m.width and y_root <= m.*.m.y + m.*.m.height,
        c.TOP_LEFT => in_hotarea = y_root < hy and x_root < hx and
            x_root >= m.*.m.x and y_root >= m.*.m.y,
        c.TOP_RIGHT => in_hotarea = y_root < hy and x_root > hx and
            x_root <= m.*.m.x + m.*.m.width and y_root >= m.*.m.y,
        else => in_hotarea = y_root > hy and x_root < hx and
            x_root >= m.*.m.x and y_root <= m.*.m.y + m.*.m.height,
    }

    if (c.config.enable_hotarea == 1 and m.*.is_in_hotarea == 0 and in_hotarea) {
        m.*.ov_normal_mode = 1;
        _ = toggle_overview(&arg);
        m.*.is_in_hotarea = 1;
    } else if (c.config.enable_hotarea == 1 and m.*.is_in_hotarea == 1 and !in_hotarea) {
        m.*.is_in_hotarea = 0;
    }
}

export fn handle_cursor_axis(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as(*c.struct_wlr_pointer_axis_event, @ptrCast(@alignCast(data.?)));
    ipc_notify_device_event(&event.*.pointer.*.base);
    pointer_cursor_activity();
    acwm_notify_activity(c.server.seat);

    if (check_trackpad_disabled(event.*.pointer))
        return;

    const mods = keyboard_hard_modifiers();
    var adir: u32 = 0;
    if (event.*.orientation == c.WL_POINTER_AXIS_VERTICAL_SCROLL)
        adir = if (event.*.delta > 0) c.AxisDown else c.AxisUp
    else
        adir = if (event.*.delta > 0) c.AxisRight else c.AxisLeft;

    var ji: i32 = 0;
    while (ji < c.config.axis_bindings_count) : (ji += 1) {
        const a = &c.config.axis_bindings[@intCast(ji)];
        const mode_matches = a.iscommonmode or
            (a.isdefaultmode and c.server.key_mode.isdefault) or
            c.strcmp(&c.server.key_mode.mode[0], &a.mode[0]) == 0;
        if (mode_matches and cleanMask(mods) == cleanMask(a.mod) and
            (a.dir == c.ALLDIR or adir == a.dir) and a.func != null)
        {
            keyboard_cancel_pending_release_bind();
            const timed = @as(i64, @intCast(event.*.time_msec)) - c.server.axis_apply_time >
                @as(i64, @intCast(c.config.axis_bind_apply_timeout));
            if (timed or @as(f64, @floatFromInt(c.server.axis_apply_dir)) * event.*.delta < 0) {
                _ = a.func.?(&a.arg);
                c.server.axis_apply_time = @intCast(event.*.time_msec);
                c.server.axis_apply_dir = if (event.*.delta > 0) 1 else -1;
                return;
            } else {
                c.server.axis_apply_dir = if (event.*.delta > 0) 1 else -1;
                c.server.axis_apply_time = @intCast(event.*.time_msec);
                return;
            }
        }
    }

    const factor = if (pointer_is_trackpad(event.*.pointer)) c.config.trackpad_scroll_factor else c.config.axis_scroll_factor;
    c.wlr_seat_pointer_notify_axis(c.server.seat, event.*.time_msec, event.*.orientation, event.*.delta * factor, @intFromFloat(@round(@as(f64, @floatFromInt(event.*.delta_discrete)) * factor)), event.*.source, event.*.relative_direction);
}

fn cleanMask(mask: u32) u32 {
    return mask & ~@as(u32, @intCast(c.WLR_MODIFIER_CAPS));
}

export fn handle_cursor_button(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as([*c]c.struct_wlr_pointer_button_event, @ptrCast(@alignCast(data.?)));
    ipc_notify_device_event(&event.*.pointer.*.base);
    if (!pointer_process_button_press(event))
        _ = c.wlr_seat_pointer_notify_button(c.server.seat, event.*.time_msec, event.*.button, event.*.state);
}

export fn handle_last_cursor_surface_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    last_cursor.surface = null;
    c.wl_list_remove(&listener.*.link);
}

export fn handle_request_set_cursor_shape(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as(*c.struct_wlr_cursor_shape_manager_v1_request_set_shape_event, @ptrCast(@alignCast(data.?)));
    if (c.server.cursor_mode != c.CurNormal and c.server.cursor_mode != c.CurPressed)
        return;
    if (c.server.hover_resize_edge != 0)
        return;
    if (event.*.seat_client == c.server.seat.*.pointer_state.focused_client) {
        if (last_cursor.surface != null and c.server.last_cursor_surface_destroy_listener.link.prev != null)
            c.wl_list_remove(&c.server.last_cursor_surface_destroy_listener.link);
        last_cursor.shape = event.*.shape;
        last_cursor.surface = null;
        if (!c.server.cursor_hidden)
            c.wlr_cursor_set_xcursor(c.server.cursor, c.server.cursor_manager, c.wlr_cursor_shape_v1_name(event.*.shape));
    }
}

export fn pointer_set_accel(device: ?*c.struct_libinput_device, natural_scrolling: bool, mouse_accel_profile: u32, mouse_accel_speed: f64) callconv(.c) void {
    _ = c.libinput_device_config_scroll_set_natural_scroll_enabled(device, @intFromBool(natural_scrolling));
    if (mouse_accel_profile != 0 and c.libinput_device_config_accel_is_available(device) != 0) {
        _ = c.libinput_device_config_accel_set_profile(device, mouse_accel_profile);
        _ = c.libinput_device_config_accel_set_speed(device, mouse_accel_speed);
    } else {
        _ = c.libinput_device_config_accel_set_profile(device, 1);
        _ = c.libinput_device_config_accel_set_profile(device, 0);
        _ = c.libinput_device_config_accel_set_speed(device, 0);
    }
}

fn ruleI32(rule: [*c]c.ConfigDeviceRule, comptime field: []const u8, fallback: i32) i32 {
    if (rule != null and @field(rule.*, field) != -1)
        return @field(rule.*, field);
    return fallback;
}

fn ruleU32(rule: [*c]c.ConfigDeviceRule, comptime field: []const u8, fallback: u32) u32 {
    if (rule != null and @field(rule.*, field) != std.math.maxInt(u32))
        return @field(rule.*, field);
    return fallback;
}

export fn configure_pointer(wlr_device: [*c]c.struct_wlr_input_device, device: ?*c.struct_libinput_device) callconv(.c) void {
    const rule = find_device_rule(wlr_device);
    const is_trackpad = c.libinput_device_config_tap_get_finger_count(device) > 0;

    const tap_to_click = ruleI32(rule, "tap_to_click", c.config.tap_to_click);
    const tap_and_drag = ruleI32(rule, "tap_and_drag", c.config.tap_and_drag);
    const drag_lock = ruleI32(rule, "drag_lock", c.config.drag_lock);
    const button_map = ruleU32(rule, "button_map", c.config.button_map);
    const natural_scrolling = ruleI32(rule, "natural_scrolling", if (is_trackpad) c.config.trackpad_natural_scrolling else c.config.mouse_natural_scrolling);
    var accel_profile: u32 = undefined;
    if (rule != null and rule.*.accel_profile != -1)
        accel_profile = @intCast(rule.*.accel_profile)
    else
        accel_profile = if (is_trackpad) c.config.trackpad_accel_profile else c.config.mouse_accel_profile;
    var accel_speed: f64 = undefined;
    if (rule != null and !std.math.isNan(rule.*.accel_speed))
        accel_speed = rule.*.accel_speed
    else
        accel_speed = if (is_trackpad) c.config.trackpad_accel_speed else c.config.mouse_accel_speed;
    const disable_while_typing = ruleI32(rule, "disable_while_typing", c.config.trackpad_disable_while_typing);
    const left_handed = ruleI32(rule, "left_handed", if (is_trackpad) c.config.trackpad_left_handed else c.config.mouse_left_handed);
    const middle_button_emulation = ruleI32(rule, "middle_button_emulation", if (is_trackpad) c.config.trackpad_middle_button_emulation else c.config.mouse_middle_button_emulation);
    const scroll_method = ruleU32(rule, "scroll_method", if (is_trackpad) c.config.trackpad_scroll_method else c.config.mouse_scroll_method);
    const scroll_button = ruleU32(rule, "scroll_button", if (is_trackpad) c.config.trackpad_scroll_button else c.config.mouse_scroll_button);
    const click_method = ruleU32(rule, "click_method", if (is_trackpad) c.config.trackpad_click_method else c.config.mouse_click_method);
    const send_events_mode = ruleU32(rule, "send_events_mode", if (is_trackpad) c.config.trackpad_send_events_mode else c.config.mouse_send_events_mode);

    if (c.libinput_device_config_tap_get_finger_count(device) != 0) {
        _ = c.libinput_device_config_tap_set_enabled(device, @intCast(@intFromBool(tap_to_click != 0)));
        _ = c.libinput_device_config_tap_set_drag_enabled(device, @intCast(@intFromBool(tap_and_drag != 0)));
        _ = c.libinput_device_config_tap_set_drag_lock_enabled(device, @intCast(@intFromBool(drag_lock != 0)));
        _ = c.libinput_device_config_tap_set_button_map(device, button_map);
    }
    pointer_set_accel(device, natural_scrolling != 0, accel_profile, accel_speed);
    if (c.libinput_device_config_dwt_is_available(device) != 0)
        _ = c.libinput_device_config_dwt_set_enabled(device, @intCast(@intFromBool(disable_while_typing != 0)));
    if (c.libinput_device_config_left_handed_is_available(device) != 0)
        _ = c.libinput_device_config_left_handed_set(device, @intCast(@intFromBool(left_handed != 0)));
    if (c.libinput_device_config_middle_emulation_is_available(device) != 0)
        _ = c.libinput_device_config_middle_emulation_set_enabled(device, @intCast(@intFromBool(middle_button_emulation != 0)));
    const scroll_methods = c.libinput_device_config_scroll_get_methods(device);
    if (scroll_methods != c.LIBINPUT_CONFIG_SCROLL_NO_SCROLL)
        _ = c.libinput_device_config_scroll_set_method(device, scroll_method);
    if (scroll_methods == c.LIBINPUT_CONFIG_SCROLL_ON_BUTTON_DOWN)
        _ = c.libinput_device_config_scroll_set_button(device, scroll_button);
    if (c.libinput_device_config_click_get_methods(device) != c.LIBINPUT_CONFIG_CLICK_METHOD_NONE)
        _ = c.libinput_device_config_click_set_method(device, click_method);
    if (c.libinput_device_config_send_events_get_modes(device) != 0)
        _ = c.libinput_device_config_send_events_set_mode(device, send_events_mode);
}

export fn pointer_create(pointer: [*c]c.struct_wlr_pointer) callconv(.c) void {
    if (c.wlr_input_device_is_libinput(&pointer.*.base)) {
        const device = c.wlr_libinput_get_device_handle(&pointer.*.base);
        if (device != null) {
            configure_pointer(&pointer.*.base, device);
            const raw = c.calloc(1, @sizeOf(InputDevice)) orelse return;
            const input_dev = @as(*InputDevice, @ptrCast(@alignCast(raw)));
            input_dev.wlr_device = &pointer.*.base;
            input_dev.libinput_device = device;
            input_dev.destroy_listener.notify = handle_input_device_destroy;
            c.wl_signal_add(&pointer.*.base.events.destroy, &input_dev.destroy_listener);
            c.wl_list_insert(&c.server.input_devices, &input_dev.link);
        }
    }
    c.wlr_cursor_attach_input_device(c.server.cursor, &pointer.*.base);
}

export fn handle_pointer_constraint_commit(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const pc = @as(*PointerConstraint, @ptrFromInt(@intFromPtr(listener) - @offsetOf(PointerConstraint, "commit")));
    const constraint = pc.constraint;
    var cl: [*c]Client = null;
    if (c.server.active_constraint != constraint)
        return;
    pointerConstraintSyncRegion(constraint);
    _ = toplevel_from_wlr_surface(constraint.*.surface, &cl, null);
    pointerWarpIntoConstraint(constraint, cl);
    if (constraint.*.type == c.WLR_POINTER_CONSTRAINT_V1_LOCKED)
        pointer_follow_constraint_hint(constraint, cl);
}

export fn handle_new_pointer_constraint(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const constraint = @as([*c]Constraint, @ptrCast(@alignCast(data.?)));
    const raw = c.ecalloc(1, @sizeOf(PointerConstraint)) orelse return;
    const pc = @as(*PointerConstraint, @ptrCast(@alignCast(raw)));
    pc.constraint = constraint;
    pc.destroy.notify = handle_pointer_constraint_destroy;
    c.wl_signal_add(&constraint.*.events.destroy, &pc.destroy);
    pc.commit.notify = handle_pointer_constraint_commit;
    c.wl_signal_add(&constraint.*.surface.*.events.commit, &pc.commit);

    const pointer_match = c.server.seat.*.pointer_state.focused_surface == constraint.*.surface;
    var cl: [*c]Client = null;
    var cc: [*c]Client = null;
    var sel: [*c]Client = null;
    if (c.server.seat.*.keyboard_state.focused_surface != null)
        _ = toplevel_from_wlr_surface(c.server.seat.*.keyboard_state.focused_surface, &cl, null);
    sel = if (c.server.selected_monitor != null) c.server.selected_monitor.*.sel else null;
    _ = toplevel_from_wlr_surface(constraint.*.surface, &cc, null);
    if (pointer_match or (cc != null and (cc == cl or cc == sel)))
        pointer_constrain_cursor(constraint);
}

export fn pointer_constrain_cursor(constraint: [*c]Constraint) callconv(.c) void {
    if (c.server.active_constraint == constraint)
        return;
    pointer_locked_applied = false;
    pointer_hint_applied = false;

    if (c.server.active_constraint != null) {
        if (constraint == null)
            pointer_warp_to_constraint_hint();
        c.wlr_pointer_constraint_v1_send_deactivated(c.server.active_constraint);
    }
    c.server.active_constraint = constraint;
    if (constraint != null) {
        pointerConstraintSyncRegion(constraint);
        c.wlr_pointer_constraint_v1_send_activated(constraint);
        var cl: [*c]Client = null;
        _ = toplevel_from_wlr_surface(constraint.*.surface, &cl, null);
        pointerWarpIntoConstraint(constraint, cl);
    }
}

export fn handle_cursor_frame(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    _ = data;
    c.wlr_seat_pointer_notify_frame(c.server.seat);
}

export fn pointer_warp_to_constraint_hint() callconv(.c) void {
    if (c.server.active_constraint == null)
        return;
    var cl: [*c]Client = null;
    _ = toplevel_from_wlr_surface(c.server.active_constraint.*.surface, &cl, null);
    var lx: f64 = 0;
    var ly: f64 = 0;
    if (pointerConstraintHintPosition(c.server.active_constraint, cl, &lx, &ly)) {
        _ = c.wlr_cursor_warp(c.server.cursor, null, lx, ly);
        c.wlr_seat_pointer_warp(c.server.active_constraint.*.seat, c.server.active_constraint.*.current.cursor_hint.x, c.server.active_constraint.*.current.cursor_hint.y);
    }
}

export fn handle_drag_icon_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    client_focus(client_focus_top(c.server.selected_monitor), 1);
    pointer_process_motion(0, null, 0, 0, 0, 0);
    c.wl_list_remove(&listener.*.link);
    c.free(listener);
}

export fn handle_pointer_constraint_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const pc = @as(*PointerConstraint, @ptrFromInt(@intFromPtr(listener) - @offsetOf(PointerConstraint, "destroy")));
    var cl: [*c]Client = null;
    _ = toplevel_from_wlr_surface(pc.constraint.*.surface, &cl, null);
    if (c.server.active_constraint == pc.constraint) {
        pointer_warp_to_constraint_hint();
        c.server.active_constraint = null;
        pointer_locked_applied = false;
        pointer_hint_applied = false;
    }
    c.wl_list_remove(&pc.destroy.link);
    c.wl_list_remove(&pc.commit.link);
    c.free(pc);
}

export fn handle_cursor_motion_absolute(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as(*c.struct_wlr_pointer_motion_absolute_event, @ptrCast(@alignCast(data.?)));
    ipc_notify_device_event(&event.*.pointer.*.base);
    if (check_trackpad_disabled(event.*.pointer))
        return;
    if (event.*.time_msec == 0)
        c.wlr_cursor_warp_absolute(c.server.cursor, &event.*.pointer.*.base, event.*.x, event.*.y);
    var lx: f64 = 0;
    var ly: f64 = 0;
    c.wlr_cursor_absolute_to_layout_coords(c.server.cursor, &event.*.pointer.*.base, event.*.x, event.*.y, &lx, &ly);
    const dx = lx - c.server.cursor.*.x;
    const dy = ly - c.server.cursor.*.y;
    pointer_process_motion(event.*.time_msec, &event.*.pointer.*.base, dx, dy, dx, dy);
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/pointer_constraints_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_list_insert_calls: c_int;
extern var stub_list_remove_calls: c_int;
extern var stub_is_libinput: bool;
extern var stub_tap_fingers: c_int;
extern var stub_attach_calls: c_int;
extern var stub_warp_calls: c_int;
extern var stub_warp_x: f64;
extern var stub_warp_y: f64;
extern var stub_set_xcursor_calls: c_int;
extern var stub_xcursor_name: [*c]const u8;
extern var stub_seat_warp_calls: c_int;
extern var stub_pointer_frame_calls: c_int;
extern var stub_axis_calls: c_int;
extern var stub_axis_value: f64;
extern var stub_axis_discrete: i32;
extern var stub_button_calls: c_int;
extern var stub_contains: bool;
extern var stub_motion_calls: c_int;
extern var stub_press_handled: bool;
extern var stub_activity_calls: c_int;
extern var stub_notify_device_calls: c_int;
extern var stub_is_trackpad: bool;
extern var stub_trackpad_disabled: bool;
extern var stub_mods: u32;
extern var stub_cancel_release_calls: c_int;
extern var stub_acwm_activity_calls: c_int;
extern var stub_toggle_overview_calls: c_int;
extern var stub_rule: [*c]c.ConfigDeviceRule;
extern var stub_natural: c_int;
extern var stub_accel_profile_calls: c_int;
extern var stub_accel_profile: u32;
extern var stub_accel_speed: f64;
extern var stub_tap_enabled: c_int;
extern var stub_tap_drag: c_int;
extern var stub_tap_lock: c_int;
extern var stub_tap_map: u32;
extern var stub_dwt: c_int;
extern var stub_left: c_int;
extern var stub_middle: c_int;
extern var stub_scroll_method: u32;
extern var stub_scroll_button: u32;
extern var stub_click_method: u32;
extern var stub_send_mode: u32;
extern var stub_scroll_methods: u32;
extern var stub_click_methods: u32;
extern var stub_send_modes: u32;
extern var stub_activated_calls: c_int;
extern var stub_deactivated_calls: c_int;
extern var stub_for_surface: [*c]Constraint;
extern var stub_abs_lx: f64;
extern var stub_abs_ly: f64;
extern var stub_keybinding_calls: c_int;
extern fn stub_keybinding_func(arg: [*c]const c.Arg) callconv(.c) i32;
extern var stub_surface: c.struct_wlr_surface;
extern var stub_client_surface: [*c]c.struct_wlr_surface;
extern var stub_is_x11: c_int;
extern var stub_toplevel_result: i32;
extern var stub_toplevel_client: [*c]Client;
extern var stub_focus_top: [*c]Client;
extern var stub_focus_calls: c_int;

var test_cursor: c.struct_wlr_cursor = undefined;
var test_seat: c.struct_wlr_seat = undefined;

fn listInit(head: *c.struct_wl_list) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

fn listCount(head: *c.struct_wl_list) usize {
    var n: usize = 0;
    var pos = head.next;
    while (pos != @as([*c]c.struct_wl_list, @ptrCast(head))) : (pos = pos.*.next)
        n += 1;
    return n;
}

fn resetPointerWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    listInit(&c.server.input_devices);
    listInit(&c.server.clients);
    test_cursor = std.mem.zeroes(c.struct_wlr_cursor);
    test_seat = std.mem.zeroes(c.struct_wlr_seat);
    c.server.cursor = &test_cursor;
    c.server.seat = &test_seat;
    c.server.cursor_manager = @ptrFromInt(0x9000);
    last_cursor = std.mem.zeroes(LastCursor);
    pointer_locked_applied = false;
    pointer_hint_applied = false;
    confine_pointer_last = null;
    stub_list_insert_calls = 0;
    stub_list_remove_calls = 0;
    stub_is_libinput = true;
    stub_tap_fingers = 0;
    stub_attach_calls = 0;
    stub_warp_calls = 0;
    stub_warp_x = 0;
    stub_warp_y = 0;
    stub_set_xcursor_calls = 0;
    stub_xcursor_name = null;
    stub_seat_warp_calls = 0;
    stub_pointer_frame_calls = 0;
    stub_axis_calls = 0;
    stub_axis_value = 0;
    stub_axis_discrete = 0;
    stub_button_calls = 0;
    stub_contains = true;
    stub_motion_calls = 0;
    stub_press_handled = false;
    stub_activity_calls = 0;
    stub_notify_device_calls = 0;
    stub_is_trackpad = false;
    stub_trackpad_disabled = false;
    stub_mods = 0;
    stub_cancel_release_calls = 0;
    stub_acwm_activity_calls = 0;
    stub_toggle_overview_calls = 0;
    stub_rule = null;
    stub_natural = -1;
    stub_accel_profile_calls = 0;
    stub_accel_profile = 0;
    stub_accel_speed = 0;
    stub_tap_enabled = -1;
    stub_tap_drag = -1;
    stub_tap_lock = -1;
    stub_tap_map = 0;
    stub_dwt = -1;
    stub_left = -1;
    stub_middle = -1;
    stub_scroll_method = 0;
    stub_scroll_button = 0;
    stub_click_method = 0;
    stub_send_mode = 0;
    stub_scroll_methods = 1;
    stub_click_methods = 1;
    stub_send_modes = 1;
    stub_activated_calls = 0;
    stub_deactivated_calls = 0;
    stub_for_surface = null;
    stub_surface = std.mem.zeroes(c.struct_wlr_surface);
    stub_client_surface = &stub_surface;
    stub_is_x11 = 0;
    stub_toplevel_result = -1;
    stub_toplevel_client = null;
    stub_focus_top = null;
    stub_focus_calls = 0;
}

fn mkClient(cl: *Client, m: *Monitor) void {
    cl.* = std.mem.zeroes(Client);
    cl.mon = m;
    cl.tags = 1;
    cl.geom = .{ .x = 100, .y = 100, .width = 300, .height = 200 };
    cl.bw = 2;
    stub_toplevel_client = cl;
}

fn mkConstraint(con: *Constraint, surface: [*c]c.struct_wlr_surface) void {
    con.* = std.mem.zeroes(Constraint);
    con.surface = surface;
    con.seat = c.server.seat;
    c.pixman_region32_init(&con.region);
    c.pixman_region32_init(&con.current.region);
}

test "surface scale and warp box fall back safely" {
    resetPointerWorld();
    var m: Monitor = std.mem.zeroes(Monitor);
    var cl: Client = std.mem.zeroes(Client);
    cl.geom = .{ .x = 100, .y = 100, .width = 300, .height = 200 };
    cl.animation.current = .{ .x = 0, .y = 0, .width = 10, .height = 10 };
    var box = pointer_client_warp_box(&cl);
    try testing.expectEqual(@as(i32, 100), box.x);
    cl.animation.current = .{ .x = 110, .y = 120, .width = 100, .height = 80 };
    box = pointer_client_warp_box(&cl);
    try testing.expectEqual(@as(i32, 110), box.x);

    cl.mon = &m;
    stub_is_x11 = 1;
    cl.xwayland_scale = 2;
    c.config.xwayland_ignore_scale = 1;
    try testing.expectApproxEqAbs(@as(f64, 2), pointer_surface_scale(&cl), 1e-6);
    c.config.xwayland_ignore_scale = 0;
    try testing.expectApproxEqAbs(@as(f64, 1), pointer_surface_scale(&cl), 1e-6);
}

test "constraint hint warps cursor and seat once" {
    resetPointerWorld();
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    var con: Constraint = undefined;
    mkConstraint(&con, &surface);
    var m: Monitor = std.mem.zeroes(Monitor);
    m.m = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
    var cl: Client = std.mem.zeroes(Client);
    cl.geom = .{ .x = 100, .y = 100, .width = 300, .height = 200 };
    cl.bw = 2;
    cl.mon = &m;
    con.current.cursor_hint.enabled = true;
    con.current.cursor_hint.x = 20;
    con.current.cursor_hint.y = 30;

    pointer_follow_constraint_hint(&con, &cl);
    try testing.expectEqual(@as(c_int, 1), stub_warp_calls);
    try testing.expectEqual(@as(f64, 122), stub_warp_x);
    try testing.expectEqual(@as(f64, 132), stub_warp_y);
    try testing.expectEqual(@as(c_int, 1), stub_seat_warp_calls);
    try testing.expectEqual(@as(f64, 122), test_cursor.x);

    pointer_follow_constraint_hint(&con, &cl);
    try testing.expectEqual(@as(c_int, 1), stub_warp_calls);

    stub_contains = false;
    con.current.cursor_hint.x = 40;
    pointer_follow_constraint_hint(&con, &cl);
    try testing.expectEqual(@as(c_int, 1), stub_warp_calls);
}

test "constraint sync and warp clamp into the region" {
    resetPointerWorld();
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    c.pixman_region32_init_rect(&surface.input_region, 0, 0, 100, 100);
    var con: Constraint = undefined;
    mkConstraint(&con, &surface);
    var m: Monitor = std.mem.zeroes(Monitor);
    m.m = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
    m.tagset[0] = 1;
    var cl: Client = std.mem.zeroes(Client);
    cl.geom = .{ .x = 100, .y = 100, .width = 100, .height = 100 };
    cl.bw = 0;
    cl.tags = 1;
    cl.mon = &m;
    cl.animation.current = cl.geom;
    c.server.active_constraint = &con;
    test_cursor.x = 150;
    test_cursor.y = 150;

    pointerConstraintSyncRegion(&con);
    try testing.expect(c.pixman_region32_empty(&con.region) == 0);
    try testing.expect(pointer_locked_constraint_applies(&cl, &con));
    try testing.expect(c.pixman_region32_contains_point(&con.region, 150, 150, null) == 0);

    stub_toplevel_client = &cl;
    stub_surface.mapped = true;
    c.server.active_constraint = null;
    pointer_constrain_cursor(&con);
    try testing.expectEqual(@as(c_int, 1), stub_activated_calls);

    test_cursor.x = 0;
    test_cursor.y = 0;
    try testing.expect(pointer_constraint_surface_visible(&con));
    try testing.expect(pointerCursorOutsideClient(&cl));
    pointerWarpIntoConstraint(&con, &cl);
    try testing.expect(stub_warp_calls >= 1);
}

test "confine warps outside clients and forgets destroyed ones" {
    resetPointerWorld();
    var m: Monitor = std.mem.zeroes(Monitor);
    m.tagset[0] = 1;
    var tree: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    tree.node.enabled = true;
    var cl: Client = std.mem.zeroes(Client);
    mkClient(&cl, &m);
    m.sel = &cl;
    cl.confine_pointer = 1;
    cl.scene = &tree;
    stub_toplevel_client = &cl;
    c.server.selected_monitor = &m;
    stub_surface.mapped = true;
    test_cursor.x = 0;
    test_cursor.y = 0;

    try testing.expect(pointer_confine_rule_client() == &cl);
    pointer_check_confine_client();
    try testing.expectEqual(@as(c_int, 1), stub_warp_calls);
    try testing.expectEqual(@as(f64, 250), stub_warp_x);
    pointer_check_confine_client();
    try testing.expectEqual(@as(c_int, 1), stub_warp_calls);

    pointer_client_destroyed(&cl);
    test_cursor.x = 0;
    test_cursor.y = 0;
    pointer_check_confine_client();
    try testing.expectEqual(@as(c_int, 2), stub_warp_calls);
}

test "axis bindings apply and otherwise scroll the client" {
    resetPointerWorld();
    var pointer: c.struct_wlr_pointer = std.mem.zeroes(c.struct_wlr_pointer);
    var event: c.struct_wlr_pointer_axis_event = std.mem.zeroes(c.struct_wlr_pointer_axis_event);
    event.pointer = &pointer;
    event.orientation = c.WL_POINTER_AXIS_VERTICAL_SCROLL;
    event.time_msec = 100;
    event.delta = 1;
    event.delta_discrete = 1;
    c.config.axis_scroll_factor = 2;
    c.config.trackpad_scroll_factor = 3;

    handle_cursor_axis(null, &event);
    try testing.expectEqual(@as(c_int, 1), stub_axis_calls);
    try testing.expectEqual(@as(f64, 2), stub_axis_value);
    try testing.expectEqual(@as(i32, 2), stub_axis_discrete);
    try testing.expectEqual(@as(c_int, 1), stub_activity_calls);

    stub_is_trackpad = true;
    handle_cursor_axis(null, &event);
    try testing.expectEqual(@as(f64, 3), stub_axis_value);

    var binding: c.AxisBinding = std.mem.zeroes(c.AxisBinding);
    binding.iscommonmode = true;
    binding.dir = c.AxisDown;
    binding.func = stub_keybinding_func;
    c.config.axis_bindings = &binding;
    c.config.axis_bindings_count = 1;
    const axis_calls = stub_axis_calls;
    handle_cursor_axis(null, &event);
    try testing.expectEqual(@as(c_int, 1), stub_keybinding_calls);
    try testing.expectEqual(axis_calls, stub_axis_calls);

    stub_trackpad_disabled = true;
    handle_cursor_axis(null, &event);
    try testing.expectEqual(@as(c_int, 1), stub_keybinding_calls);
}

test "buttons and cursor shape requests update the seat" {
    resetPointerWorld();
    var pointer: c.struct_wlr_pointer = std.mem.zeroes(c.struct_wlr_pointer);
    var event: c.struct_wlr_pointer_button_event = std.mem.zeroes(c.struct_wlr_pointer_button_event);
    event.pointer = &pointer;
    event.time_msec = 5;
    event.button = 0x110;
    handle_cursor_button(null, &event);
    try testing.expectEqual(@as(c_int, 1), stub_button_calls);

    stub_press_handled = true;
    handle_cursor_button(null, &event);
    try testing.expectEqual(@as(c_int, 1), stub_button_calls);

    var shape_event: c.struct_wlr_cursor_shape_manager_v1_request_set_shape_event = std.mem.zeroes(c.struct_wlr_cursor_shape_manager_v1_request_set_shape_event);
    test_seat.pointer_state.focused_client = @ptrFromInt(0x1000);
    shape_event.seat_client = test_seat.pointer_state.focused_client;
    c.server.cursor_mode = c.CurNormal;
    c.server.hover_resize_edge = 0;
    handle_request_set_cursor_shape(null, &shape_event);
    try testing.expectEqual(@as(c_int, 1), stub_set_xcursor_calls);
    try testing.expectEqual(@as(c_int, 2), stub_notify_device_calls);

    c.server.hover_resize_edge = 1;
    handle_request_set_cursor_shape(null, &shape_event);
    try testing.expectEqual(@as(c_int, 1), stub_set_xcursor_calls);
    c.server.cursor_hidden = true;
    c.server.hover_resize_edge = 0;
    handle_request_set_cursor_shape(null, &shape_event);
    try testing.expectEqual(@as(c_int, 1), stub_set_xcursor_calls);

    shape_event.seat_client = @ptrFromInt(0x2000);
    c.server.cursor_hidden = false;
    handle_request_set_cursor_shape(null, &shape_event);
    try testing.expectEqual(@as(c_int, 1), stub_set_xcursor_calls);
}

test "configure pointer applies rule overrides and create attaches" {
    resetPointerWorld();
    var dev: c.struct_wlr_input_device = std.mem.zeroes(c.struct_wlr_input_device);
    stub_tap_fingers = 2;
    stub_scroll_methods = c.LIBINPUT_CONFIG_SCROLL_ON_BUTTON_DOWN;
    stub_click_methods = 1;
    stub_send_modes = 1;

    var rule: c.ConfigDeviceRule = std.mem.zeroes(c.ConfigDeviceRule);
    rule.tap_to_click = 1;
    rule.tap_and_drag = 0;
    rule.drag_lock = 1;
    rule.button_map = 2;
    rule.natural_scrolling = 1;
    rule.accel_profile = 2;
    rule.accel_speed = 0.5;
    rule.disable_while_typing = 1;
    rule.left_handed = 0;
    rule.middle_button_emulation = 1;
    rule.scroll_method = 3;
    rule.scroll_button = 0x111;
    rule.click_method = 2;
    rule.send_events_mode = 4;
    stub_rule = &rule;
    configure_pointer(&dev, null);
    try testing.expectEqual(@as(c_int, 1), stub_natural);
    try testing.expectEqual(@as(u32, 2), stub_accel_profile);
    try testing.expectEqual(@as(f64, 0.5), stub_accel_speed);
    try testing.expectEqual(@as(c_int, 1), stub_tap_enabled);
    try testing.expectEqual(@as(c_int, 0), stub_tap_drag);
    try testing.expectEqual(@as(c_int, 1), stub_tap_lock);
    try testing.expectEqual(@as(u32, 2), stub_tap_map);
    try testing.expectEqual(@as(c_int, 1), stub_dwt);
    try testing.expectEqual(@as(c_int, 0), stub_left);
    try testing.expectEqual(@as(c_int, 1), stub_middle);
    try testing.expectEqual(@as(u32, 3), stub_scroll_method);
    try testing.expectEqual(@as(u32, 0x111), stub_scroll_button);
    try testing.expectEqual(@as(u32, 2), stub_click_method);
    try testing.expectEqual(@as(u32, 4), stub_send_mode);

    var pointer: c.struct_wlr_pointer = std.mem.zeroes(c.struct_wlr_pointer);
    listInit(&pointer.base.events.destroy.listener_list);
    pointer_create(&pointer);
    try testing.expectEqual(@as(c_int, 1), stub_attach_calls);
    try testing.expectEqual(@as(usize, 1), listCount(&c.server.input_devices));
}

test "new constraints activate and destroy cleanly" {
    resetPointerWorld();
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    listInit(&surface.events.commit.listener_list);
    var con: Constraint = undefined;
    mkConstraint(&con, &surface);
    listInit(&con.events.destroy.listener_list);
    test_seat.pointer_state.focused_surface = &surface;
    var cl: Client = std.mem.zeroes(Client);
    stub_toplevel_client = &cl;

    handle_new_pointer_constraint(null, &con);
    try testing.expectEqual(@as(c_int, 1), stub_activated_calls);
    try testing.expect(c.server.active_constraint == &con);

    const pc = @as(*PointerConstraint, @ptrFromInt(@intFromPtr(con.events.destroy.listener_list.next) - @offsetOf(PointerConstraint, "destroy")));
    handle_pointer_constraint_destroy(&pc.destroy, null);
    try testing.expect(c.server.active_constraint == null);
    try testing.expectEqual(@as(c_int, 0), stub_deactivated_calls);
}

test "absolute motion and hotarea route through the compositor" {
    resetPointerWorld();
    var pointer: c.struct_wlr_pointer = std.mem.zeroes(c.struct_wlr_pointer);
    var event: c.struct_wlr_pointer_motion_absolute_event = std.mem.zeroes(c.struct_wlr_pointer_motion_absolute_event);
    event.pointer = &pointer;
    event.x = 0.5;
    event.y = 0.5;
    event.time_msec = 0;
    test_cursor.x = 10;
    test_cursor.y = 20;
    stub_abs_lx = 100;
    stub_abs_ly = 200;
    handle_cursor_motion_absolute(null, &event);
    try testing.expectEqual(@as(c_int, 1), stub_motion_calls);
    try testing.expectEqual(@as(c_int, 1), stub_notify_device_calls);

    var m: Monitor = std.mem.zeroes(Monitor);
    m.m = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
    c.server.selected_monitor = &m;
    c.config.enable_hotarea = 1;
    c.config.hotarea_corner = c.BOTTOM_LEFT;
    c.config.hotarea_size = 10;
    toggle_hotarea(5, 795);
    try testing.expectEqual(@as(c_int, 1), stub_toggle_overview_calls);
    try testing.expectEqual(@as(i32, 1), m.is_in_hotarea);
    toggle_hotarea(5, 500);
    try testing.expectEqual(@as(i32, 0), m.is_in_hotarea);
}
