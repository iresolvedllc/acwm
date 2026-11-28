//! Port of input/pointer.c, part 2: resize/drag, motion/focus, drag-and-drop,
//! cursor state and button routing (Phase 5, input slice 7, slice 74).

const std = @import("std");
const c = @import("cc");
const build_options = @import("build_options");

const Client = c.Client;
const Monitor = c.Monitor;
const LayerSurface = c.LayerSurface;
const Bar = c.AcwmBarDecoration;
const Box = c.struct_wlr_box;
const LastCursor = c.LastCursor;

export var last_cursor: LastCursor = std.mem.zeroes(LastCursor);
export var pointer_locked_applied: bool = false;

extern fn pointer_surface_scale(cl: [*c]Client) callconv(.c) f64;
extern fn pointer_client_warp_box(cl: [*c]Client) callconv(.c) Box;
extern fn pointer_locked_constraint_applies(cl: [*c]Client, constraint: [*c]c.struct_wlr_pointer_constraint_v1) callconv(.c) bool;
extern fn pointer_follow_constraint_hint(constraint: [*c]c.struct_wlr_pointer_constraint_v1, cl: [*c]Client) callconv(.c) void;
extern fn pointer_confine_rule_client() callconv(.c) [*c]Client;
extern fn pointer_constraint_surface_visible(constraint: [*c]c.struct_wlr_pointer_constraint_v1) callconv(.c) bool;
extern fn pointer_confine_client(out: [*c][*c]c.struct_wlr_pointer_constraint_v1) callconv(.c) [*c]Client;
extern fn toggle_hotarea(x: i32, y: i32) callconv(.c) void;
extern fn handle_drag_icon_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn pointer_constrain_cursor(constraint: [*c]c.struct_wlr_pointer_constraint_v1) callconv(.c) void;
extern fn pointer_warp_to_constraint_hint() callconv(.c) void;
extern fn client_is_unmanaged(cl: [*c]Client) callconv(.c) i32;
extern fn client_wants_focus(cl: [*c]Client) callconv(.c) i32;
extern fn client_surface(cl: [*c]Client) callconv(.c) [*c]c.struct_wlr_surface;
extern fn client_focus(cl: [*c]Client, lift: i32) callconv(.c) void;
extern fn client_set_floating(cl: [*c]Client, floating: i32) callconv(.c) void;
extern fn client_set_monitor(cl: [*c]Client, m: [*c]Monitor, set_tags: i32, focus: bool) callconv(.c) void;
extern fn client_update_oldmonname_record(cl: [*c]Client, m: [*c]Monitor) callconv(.c) void;
extern fn client_set_drop_area(cl: [*c]Client) callconv(.c) void;
extern fn client_group_active(cl: [*c]Client) callconv(.c) [*c]Client;
extern fn client_group_leave(cl: [*c]Client) callconv(.c) void;
extern fn client_group_join(cl: [*c]Client, target: [*c]Client) callconv(.c) void;
extern fn client_handle_decorate_click(bar: [*c]Bar) callconv(.c) void;
extern fn exit_scroller_stack(cl: [*c]Client) callconv(.c) void;
extern fn set_size_per(m: [*c]Monitor, cl: [*c]Client, stack: bool) callconv(.c) void;
extern fn resize(cl: [*c]Client, geo: Box, opts: c.ResizeOpts) callconv(.c) void;
extern fn resize_tile_client(cl: [*c]Client, interact: bool, dx: f64, dy: f64, time: u32) callconv(.c) void;
extern fn apply_window_snap(cl: [*c]Client) callconv(.c) void;
extern fn monitor_at_point(x: f64, y: f64) callconv(.c) [*c]Monitor;
extern fn set_selected_monitor(m: [*c]Monitor) callconv(.c) void;
extern fn drag_refresh_interval_ms(m: [*c]Monitor) callconv(.c) u32;
extern fn is_scroller_layout(m: [*c]Monitor) callconv(.c) bool;
extern fn get_client_tag_idx(cl: [*c]const Client) callconv(.c) u32;
extern fn scroller_drop_tile(cl: [*c]Client, target: [*c]Client, vertical: i32) callconv(.c) void;
extern fn dwindle_insert(root: [*c][*c]c.DwindleNode, cl: [*c]Client, target: [*c]Client, ratio: f32, before: bool, split_h: bool, simple: bool) callconv(.c) void;
extern fn arrange(m: [*c]Monitor, want_animation: bool, from_view: bool) callconv(.c) void;
extern fn layer_focus(l: [*c]LayerSurface) callconv(.c) void;
extern fn pending_kill_client(cl: [*c]Client) callconv(.c) void;
extern fn switcher_is_active() callconv(.c) bool;
extern fn switcher_close() callconv(.c) void;
extern fn switcher_commit_client(cl: [*c]Client) callconv(.c) void;
extern fn switcher_client_at(x: f64, y: f64) callconv(.c) [*c]Client;
extern fn bar_handle_button_press(x: f64, y: f64, button: u32) callconv(.c) bool;
extern fn acwm_bar_decoration_close_contains(bar: [*c]Bar, x: f64, y: f64) callconv(.c) bool;
extern fn acwm_bar_decoration_set_close_hover(bar: [*c]Bar, hover: bool) callconv(.c) void;
extern fn acwm_scene_node_get_ignore_hit(node: [*c]c.struct_wlr_scene_node) callconv(.c) bool;
extern fn acwm_scene_node_set_ignore_hit(node: [*c]c.struct_wlr_scene_node, ignore: bool) callconv(.c) void;
extern fn node_at_point(x: f64, y: f64, psurface: [*c][*c]c.struct_wlr_surface, pc: [*c][*c]Client, pl: [*c]?*anyopaque, bar: [*c][*c]Bar, nx: *f64, ny: *f64) callconv(.c) void;
extern fn toplevel_from_wlr_surface(s: [*c]c.struct_wlr_surface, pc: [*c][*c]Client, pl: [*c][*c]LayerSurface) callconv(.c) i32;
extern fn ipc_notify_device_event(dev: [*c]c.struct_wlr_input_device) callconv(.c) void;
extern fn acwm_notify_activity(seat: [*c]c.struct_wlr_seat) callconv(.c) void;
extern fn printstatus(t: c.enum_ipc_watch_type) callconv(.c) void;
extern fn trackpad_gesture_drag_active() callconv(.c) bool;
extern fn check_trackpad_disabled(pointer: [*c]c.struct_wlr_pointer) callconv(.c) bool;
extern fn keyboard_hard_modifiers() callconv(.c) u32;
extern fn keyboard_cancel_pending_release_bind() callconv(.c) void;
extern fn seat_device_add(device: [*c]c.struct_wlr_input_device) callconv(.c) void;
extern fn toggle_overview(arg: [*c]const c.Arg) callconv(.c) i32;
extern fn wlr_cursor_move(cursor: [*c]c.struct_wlr_cursor, device: [*c]c.struct_wlr_input_device, dx: f64, dy: f64) callconv(.c) void;
extern fn wlr_cursor_warp_closest(cursor: [*c]c.struct_wlr_cursor, device: [*c]c.struct_wlr_input_device, x: f64, y: f64) callconv(.c) void;
extern fn wlr_cursor_set_xcursor(cursor: [*c]c.struct_wlr_cursor, manager: [*c]c.struct_wlr_xcursor_manager, name: [*c]const u8) callconv(.c) void;
extern fn wlr_cursor_set_surface(cursor: [*c]c.struct_wlr_cursor, surface: [*c]c.struct_wlr_surface, hx: i32, hy: i32) callconv(.c) void;
extern fn wlr_cursor_unset_image(cursor: [*c]c.struct_wlr_cursor) callconv(.c) void;
extern fn wlr_cursor_shape_v1_name(shape: c.enum_wp_cursor_shape_device_v1_shape) callconv(.c) [*c]const u8;
extern fn wlr_cursor_map_input_to_output(cursor: [*c]c.struct_wlr_cursor, device: [*c]c.struct_wlr_input_device, output: [*c]c.struct_wlr_output) callconv(.c) void;
extern fn wlr_xcursor_get_resize_name(edges: c.enum_wlr_edges) callconv(.c) [*c]const u8;
extern fn wlr_seat_pointer_clear_focus(seat: [*c]c.struct_wlr_seat) callconv(.c) void;
extern fn wlr_seat_pointer_notify_clear_focus(seat: [*c]c.struct_wlr_seat) callconv(.c) void;
extern fn wlr_seat_pointer_notify_enter(seat: [*c]c.struct_wlr_seat, surface: [*c]c.struct_wlr_surface, sx: f64, sy: f64) callconv(.c) void;
extern fn wlr_seat_pointer_notify_motion(seat: [*c]c.struct_wlr_seat, time: u32, sx: f64, sy: f64) callconv(.c) void;
extern fn wlr_seat_validate_pointer_grab_serial(seat: [*c]c.struct_wlr_seat, origin: [*c]c.struct_wlr_surface, serial: u32) callconv(.c) bool;
extern fn wlr_seat_start_pointer_drag(seat: [*c]c.struct_wlr_seat, drag: [*c]c.struct_wlr_drag, serial: u32) callconv(.c) void;
extern fn wlr_data_source_destroy(source: [*c]c.struct_wlr_data_source) callconv(.c) void;
extern fn wlr_scene_drag_icon_create(parent: [*c]c.struct_wlr_scene_tree, icon: [*c]c.struct_wlr_drag_icon) callconv(.c) [*c]c.struct_wlr_scene_tree;
extern fn wlr_scene_node_set_position(node: [*c]c.struct_wlr_scene_node, x: i32, y: i32) callconv(.c) void;
extern fn wlr_relative_pointer_manager_v1_send_relative_motion(manager: [*c]c.struct_wlr_relative_pointer_manager_v1, seat: [*c]c.struct_wlr_seat, time_usec: u64, dx: f64, dy: f64, dx_unaccel: f64, dy_unaccel: f64) callconv(.c) void;
extern fn wlr_region_confine(region: *c.pixman_region32_t, x1: f64, y1: f64, x2: f64, y2: f64, x: *f64, y: *f64) callconv(.c) bool;
extern fn wl_event_source_timer_update(source: ?*c.struct_wl_event_source, ms: i32) callconv(.c) c_int;
extern fn clock_gettime(clock: c.clockid_t, tp: *c.struct_timespec) callconv(.c) c_int;

fn VISIBLEON(cl: [*c]const Client, m: [*c]const Monitor) bool {
    if (cl == null or m == null or cl.*.mon != m or cl.*.isminimized != 0)
        return false;
    return (cl.*.tags & m.*.tagset[m.*.seltags]) != 0 or cl.*.isglobal != 0 or cl.*.isunglobal != 0;
}

fn ISTILED(cl: [*c]const Client) bool {
    return cl != null and cl.*.isfloating == 0 and cl.*.isminimized == 0 and cl.*.iskilling == 0 and
        cl.*.ismaximizescreen == 0 and cl.*.isfullscreen == 0 and cl.*.isunglobal == 0;
}

fn ISSCROLLTILED(cl: [*c]const Client) bool {
    return cl != null and cl.*.isfloating == 0 and cl.*.isminimized == 0 and
        cl.*.iskilling == 0 and cl.*.isunglobal == 0;
}

fn ISFULLSCREEN(cl: [*c]const Client) bool {
    return cl != null and cl.*.isfullscreen != 0;
}

fn INSIDEMON(cl: [*c]const Client) bool {
    if (cl == null or cl.*.mon == null)
        return false;
    const g = cl.*.geom;
    const m = cl.*.mon.*.m;
    return g.x + g.width > m.x and g.x < m.x + m.width and
        g.y + g.height > m.y and g.y < m.y + m.height;
}

fn cleanMask(mask: u32) u32 {
    return mask & ~@as(u32, @intCast(c.WLR_MODIFIER_CAPS));
}

fn clientResizeGrab(cl: [*c]Client) i32 {
    if (c.config.border_resize_size > 0)
        return c.config.border_resize_size;
    return @intCast(cl.*.bw);
}

fn tiledSharedEdges(cl: [*c]Client, cand: u32) u32 {
    const a = cl.*.geom;
    var shared: u32 = 0;
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    var pos = c.server.clients.next;
    while (pos != head) : (pos = pos.*.next) {
        const o = @as([*c]Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Client, "link")));
        if (o == cl or o.*.mon != cl.*.mon or !VISIBLEON(o, o.*.mon) or !ISTILED(o))
            continue;
        const b = o.*.geom;
        const voverlap = a.y < b.y + b.height and b.y < a.y + a.height;
        const hoverlap = a.x < b.x + b.width and b.x < a.x + a.width;
        if ((cand & c.WLR_EDGE_LEFT) != 0 and (shared & c.WLR_EDGE_LEFT) == 0 and voverlap and b.x + b.width <= a.x)
            shared |= c.WLR_EDGE_LEFT;
        if ((cand & c.WLR_EDGE_RIGHT) != 0 and (shared & c.WLR_EDGE_RIGHT) == 0 and voverlap and b.x >= a.x + a.width)
            shared |= c.WLR_EDGE_RIGHT;
        if ((cand & c.WLR_EDGE_TOP) != 0 and (shared & c.WLR_EDGE_TOP) == 0 and hoverlap and b.y + b.height <= a.y)
            shared |= c.WLR_EDGE_TOP;
        if ((cand & c.WLR_EDGE_BOTTOM) != 0 and (shared & c.WLR_EDGE_BOTTOM) == 0 and hoverlap and b.y >= a.y + a.height)
            shared |= c.WLR_EDGE_BOTTOM;
        if ((shared & cand) == cand)
            break;
    }
    return shared;
}

fn clientResizeEdgeAt(cl: [*c]Client, surface: [*c]c.struct_wlr_surface, x: f64, y: f64) u32 {
    if (cl == null or cl.*.scene == null or !cl.*.scene.*.node.enabled)
        return 0;
    if (client_is_unmanaged(cl) != 0 or ISFULLSCREEN(cl))
        return 0;
    if (surface != null and surface != client_surface(cl))
        return 0;
    if (cl.*.mon == null or cl.*.mon.*.isoverview != 0 or !VISIBLEON(cl, cl.*.mon))
        return 0;
    var t = clientResizeGrab(cl);
    if (t <= 0)
        return 0;
    const g = cl.*.geom;
    if (x < @as(f64, @floatFromInt(g.x)) or x >= @as(f64, @floatFromInt(g.x + g.width)) or
        y < @as(f64, @floatFromInt(g.y)) or y >= @as(f64, @floatFromInt(g.y + g.height)))
        return 0;
    t = @min(t, @divTrunc(g.width, 2));
    t = @min(t, @divTrunc(g.height, 2));
    var edge: u32 = 0;
    if (x < @as(f64, @floatFromInt(g.x + t))) edge |= c.WLR_EDGE_LEFT;
    if (x >= @as(f64, @floatFromInt(g.x + g.width - t))) edge |= c.WLR_EDGE_RIGHT;
    if (y < @as(f64, @floatFromInt(g.y + t))) edge |= c.WLR_EDGE_TOP;
    if (y >= @as(f64, @floatFromInt(g.y + g.height - t))) edge |= c.WLR_EDGE_BOTTOM;
    if (edge != 0 and cl.*.isfloating == 0) {
        if (!ISTILED(cl))
            return 0;
        edge = tiledSharedEdges(cl, edge);
    }
    return edge;
}

fn resizeCursorName(edge: u32, floating: bool) [*c]const u8 {
    if (floating)
        return c.wlr_xcursor_get_resize_name(@intCast(edge));
    return if ((edge & (c.WLR_EDGE_LEFT | c.WLR_EDGE_RIGHT)) != 0) "col-resize" else "row-resize";
}

fn pointerUpdateResizeCursor(cl: [*c]Client, surface: [*c]c.struct_wlr_surface) void {
    if (c.server.cursor_mode != c.CurNormal or c.server.session_locked != 0)
        return;
    var edge: u32 = 0;
    if (c.config.enable_border_resize != 0 and !c.server.cursor_hidden and
        c.server.seat.*.drag == null and cl != null)
        edge = clientResizeEdgeAt(cl, surface, c.server.cursor.*.x, c.server.cursor.*.y);
    const floating = edge != 0 and cl.*.isfloating != 0;
    const changed = edge != c.server.hover_resize_edge or floating != c.server.hover_resize_floating;
    const previous = c.server.hover_resize_edge;
    if (changed) {
        c.server.hover_resize_edge = edge;
        c.server.hover_resize_floating = floating;
    }
    if (c.server.cursor_hidden)
        return;
    if (edge != 0) {
        c.wlr_cursor_set_xcursor(c.server.cursor, c.server.cursor_manager, resizeCursorName(edge, floating));
    } else if (changed and previous != 0 and c.server.seat.*.drag == null) {
        c.wlr_seat_pointer_clear_focus(c.server.seat);
    }
}

export fn pointer_resize_floating_window(cl: [*c]Client, x: f64, y: f64) callconv(.c) void {
    const edge = c.server.resize_edge;
    const bw: i32 = @intCast(cl.*.bw);
    const min_w = 1 + 2 * bw;
    const min_h = 1 + 2 * bw;
    var cdx: i32 = 0;
    var cdy: i32 = 0;
    var box = cl.*.geom;

    if ((edge & (c.WLR_EDGE_LEFT | c.WLR_EDGE_RIGHT)) != 0) {
        cdx = @as(i32, @intFromFloat(@round(x))) - c.server.grab_offset_x;
        if ((edge & c.WLR_EDGE_RIGHT) != 0) {
            if (cl.*.geom.width + cdx < min_w)
                cdx = min_w - cl.*.geom.width;
            box.width = cl.*.geom.width + cdx;
        } else {
            if (cl.*.geom.width - cdx < min_w)
                cdx = cl.*.geom.width - min_w;
            box.x = cl.*.geom.x + cdx;
            box.width = cl.*.geom.width - cdx;
        }
    }
    if ((edge & (c.WLR_EDGE_TOP | c.WLR_EDGE_BOTTOM)) != 0) {
        cdy = @as(i32, @intFromFloat(@round(y))) - c.server.grab_offset_y;
        if ((edge & c.WLR_EDGE_BOTTOM) != 0) {
            if (cl.*.geom.height + cdy < min_h)
                cdy = min_h - cl.*.geom.height;
            box.height = cl.*.geom.height + cdy;
        } else {
            if (cl.*.geom.height - cdy < min_h)
                cdy = cl.*.geom.height - min_h;
            box.y = cl.*.geom.y + cdy;
            box.height = cl.*.geom.height - cdy;
        }
    }
    cl.*.float_geom = box;
    var opts = std.mem.zeroes(c.ResizeOpts);
    opts.interact = true;
    opts.drag_edge = edge;
    resize(cl, box, opts);
    c.server.grab_offset_x += cdx;
    c.server.grab_offset_y += cdy;
}

fn clientBeginDragFloat(cl: [*c]Client) void {
    cl.*.drag_to_tile = true;
    exit_scroller_stack(cl);
    client_set_floating(cl, 1);
    cl.*.drag_tile_float_backup_geom = cl.*.float_geom;
    cl.*.old_stack_inner_per = 0.0;
    cl.*.old_master_inner_per = 0.0;
    set_size_per(cl.*.mon, cl, false);
}

export fn pointer_begin_move_resize(cl: [*c]Client, mode: u32, x: f64, y: f64, edge: u32) callconv(.c) bool {
    if (c.server.cursor_mode != c.CurNormal and c.server.cursor_mode != c.CurPressed)
        return false;
    if (cl == null or (mode != c.CurMove and mode != c.CurResize) or
        client_is_unmanaged(cl) != 0 or cl.*.isfullscreen != 0 or cl.*.ismaximizescreen != 0)
    {
        c.server.grab_client = null;
        return false;
    }
    c.server.grab_client = cl;
    c.server.grab_is_border_resize = edge != 0;

    if (cl.*.isfloating == 0 and mode == c.CurMove)
        clientBeginDragFloat(cl);

    if (cl.*.drag_to_tile and c.config.drag_tile_to_tile != 0 and c.config.drag_tile_small != 0) {
        cl.*.geom.x = @as(i32, @intFromFloat(@round(x))) - 150;
        cl.*.geom.y = @as(i32, @intFromFloat(@round(y))) - 150;
        cl.*.geom.width = 300;
        cl.*.geom.height = 300;
        var opts = std.mem.zeroes(c.ResizeOpts);
        opts.interact = true;
        resize(cl, cl.*.geom, opts);
    }

    c.server.cursor_mode = mode;
    switch (mode) {
        c.CurMove => {
            c.server.grab_offset_x = @intFromFloat(x - @as(f64, @floatFromInt(cl.*.geom.x)));
            c.server.grab_offset_y = @intFromFloat(y - @as(f64, @floatFromInt(cl.*.geom.y)));
            c.wlr_cursor_set_xcursor(c.server.cursor, c.server.cursor_manager, "grab");
        },
        c.CurResize => {
            if (cl.*.isfloating != 0) {
                var resize_edge = edge;
                if (resize_edge == 0) {
                    var corner = c.config.drag_corner;
                    if (corner == 4) {
                        const g = cl.*.geom;
                        corner = (if (x - @as(f64, @floatFromInt(g.x)) <
                            @as(f64, @floatFromInt(g.x + g.width)) - x) @as(i32, 0) else 1) +
                            (if (y - @as(f64, @floatFromInt(g.y)) <
                                @as(f64, @floatFromInt(g.y + g.height)) - y) @as(i32, 0) else 2);
                    }
                    resize_edge = if ((corner & 1) != 0) c.WLR_EDGE_RIGHT else c.WLR_EDGE_LEFT;
                    resize_edge |= if ((corner & 2) != 0) c.WLR_EDGE_BOTTOM else c.WLR_EDGE_TOP;
                }
                c.server.resize_edge = resize_edge;
                var grab_x: i32 = @intFromFloat(@round(x));
                var grab_y: i32 = @intFromFloat(@round(y));
                if (c.config.drag_warp_cursor != 0 and edge == 0) {
                    var warp_x = x;
                    var warp_y = y;
                    if ((resize_edge & (c.WLR_EDGE_LEFT | c.WLR_EDGE_RIGHT)) != 0) {
                        grab_x = if ((resize_edge & c.WLR_EDGE_RIGHT) != 0)
                            cl.*.geom.x + cl.*.geom.width else cl.*.geom.x;
                        warp_x = @floatFromInt(grab_x);
                    }
                    if ((resize_edge & (c.WLR_EDGE_TOP | c.WLR_EDGE_BOTTOM)) != 0) {
                        grab_y = if ((resize_edge & c.WLR_EDGE_BOTTOM) != 0)
                            cl.*.geom.y + cl.*.geom.height else cl.*.geom.y;
                        warp_y = @floatFromInt(grab_y);
                    }
                    c.wlr_cursor_warp_closest(c.server.cursor, null, warp_x, warp_y);
                }
                c.server.grab_offset_x = grab_x;
                c.server.grab_offset_y = grab_y;
                c.wlr_cursor_set_xcursor(c.server.cursor, c.server.cursor_manager, resizeCursorName(resize_edge, true));
            } else {
                c.wlr_cursor_set_xcursor(c.server.cursor, c.server.cursor_manager,
                    if (edge != 0) resizeCursorName(edge, false) else "grab");
            }
        },
        else => {},
    }
    c.server.grab_pointer_x = c.server.cursor.*.x;
    c.server.grab_pointer_y = c.server.cursor.*.y;
    return true;
}

export fn pointer_end_grab_client(follow_pointer: bool) callconv(.c) void {
    const gc = c.server.grab_client;
    if (gc == null or c.server.session_locked != 0 or c.server.cursor_mode == c.CurNormal or
        c.server.cursor_mode == c.CurPressed)
        return;
    const moved = c.server.cursor.*.x != c.server.grab_pointer_x or
        c.server.cursor.*.y != c.server.grab_pointer_y;
    const border_resize = c.server.grab_is_border_resize;
    c.server.grab_is_border_resize = false;
    c.server.cursor_mode = c.CurNormal;
    c.wlr_seat_pointer_clear_focus(c.server.seat);
    pointer_process_motion(0, null, 0, 0, 0, 0);
    if (gc == c.server.selected_monitor.*.sel)
        c.server.selected_monitor.*.sel = null;
    var target_mon = if (follow_pointer)
        monitor_at_point(c.server.cursor.*.x, c.server.cursor.*.y)
    else
        monitor_at_point(@floatFromInt(gc.*.geom.x + @divTrunc(gc.*.geom.width, 2)),
            @floatFromInt(gc.*.geom.y + @divTrunc(gc.*.geom.height, 2)));
    if (target_mon == null)
        target_mon = gc.*.mon;
    set_selected_monitor(target_mon);
    client_update_oldmonname_record(gc, c.server.selected_monitor);
    client_set_monitor(gc, c.server.selected_monitor, 0, true);
    if (!VISIBLEON(gc, c.server.selected_monitor))
        gc.*.tags = c.server.selected_monitor.*.tagset[c.server.selected_monitor.*.seltags];
    c.server.selected_monitor.*.prevsel = if (c.server.selected_monitor.*.sel != null and
        ISTILED(c.server.selected_monitor.*.sel)) c.server.selected_monitor.*.sel else null;
    c.server.selected_monitor.*.sel = gc;
    c.server.grab_client = null;
    c.server.start_drag_window = false;
    c.server.last_apply_drag_time = 0;
    if (gc.*.drag_to_tile and c.config.drag_tile_to_tile != 0) {
        pointer_place_drag_tile(gc);
        gc.*.float_geom = gc.*.drag_tile_float_backup_geom;
    } else if (!border_resize or moved) {
        apply_window_snap(gc);
    }
    gc.*.drag_to_tile = false;
    if (c.server.drop_client != null) {
        c.server.drop_client.*.enable_drop_area_draw = false;
        client_set_drop_area(c.server.drop_client);
        c.server.drop_client = null;
    }
}

fn groupBarTargetAt(x: f64, y: f64, ignore: [*c]Client) [*c]Client {
    var scene_hit = false;
    var bar_hit = false;
    if (ignore != null) {
        scene_hit = c.acwm_scene_node_get_ignore_hit(&ignore.*.scene.*.node);
        c.acwm_scene_node_set_ignore_hit(&ignore.*.scene.*.node, true);
        if (ignore.*.group_bar != null) {
            bar_hit = c.acwm_scene_node_get_ignore_hit(&ignore.*.group_bar.*.scene.*.node);
            c.acwm_scene_node_set_ignore_hit(&ignore.*.group_bar.*.scene.*.node, true);
        }
    }
    var bar: [*c]Bar = null;
    c.node_at_point(x, y, null, null, null, &bar, null, null);
    if (ignore != null) {
        c.acwm_scene_node_set_ignore_hit(&ignore.*.scene.*.node, scene_hit);
        if (ignore.*.group_bar != null)
            c.acwm_scene_node_set_ignore_hit(&ignore.*.group_bar.*.scene.*.node, bar_hit);
    }
    const owner: [*c]Client = if (bar != null and bar.*.node_data != null)
        @as([*c]Client, @ptrCast(@alignCast(bar.*.node_data)))
    else
        null;
    const target = client_group_active(owner);
    return if (target != ignore) target else null;
}

export fn pointer_process_motion(time: u32, device: [*c]c.struct_wlr_input_device, dx_in: f64, dy_in: f64, dx_unaccel: f64, dy_unaccel: f64) callconv(.c) void {
    var sx: f64 = 0;
    var sy: f64 = 0;
    var hover_client: [*c]Client = null;
    var w: [*c]Client = null;
    var l: [*c]LayerSurface = null;
    var bar: [*c]Bar = null;
    var surface: [*c]c.struct_wlr_surface = null;
    var ddx = dx_in;
    var ddy = dy_in;
    var should_lock = false;

    if (time != 0) {
        c.wlr_relative_pointer_manager_v1_send_relative_motion(c.server.relative_pointer_manager, c.server.seat,
            @as(u64, time) * 1000, ddx, ddy, dx_unaccel, dy_unaccel);

        if (c.server.cursor_mode != c.CurResize and c.server.cursor_mode != c.CurMove) {
            var constraint: [*c]c.struct_wlr_pointer_constraint_v1 = null;
            const cc = pointer_confine_client(&constraint);
            const active = c.server.active_constraint;
            if (active != null and active.*.type == c.WLR_POINTER_CONSTRAINT_V1_LOCKED and
                pointer_constraint_surface_visible(active) and
                (constraint != null or active.*.surface == c.server.seat.*.pointer_state.focused_surface))
            {
                if (pointer_locked_constraint_applies(cc, active)) {
                    pointer_follow_constraint_hint(active, cc);
                    pointer_locked_applied = true;
                    return;
                }
                if (pointer_locked_applied) {
                    pointer_locked_applied = false;
                    pointer_warp_to_constraint_hint();
                }
            }

            if (cc != null) {
                const scale = pointer_surface_scale(cc);
                const region = &constraint.*.region;
                const box = pointer_client_warp_box(cc);
                sx = (c.server.cursor.*.x - @as(f64, @floatFromInt(box.x)) - @as(f64, @floatFromInt(cc.*.bw))) * scale;
                sy = (c.server.cursor.*.y - @as(f64, @floatFromInt(box.y)) - @as(f64, @floatFromInt(cc.*.bw))) * scale;
                var sx_confined: f64 = 0;
                var sy_confined: f64 = 0;
                if (c.wlr_region_confine(region, sx, sy, sx + ddx * scale, sy + ddy * scale, &sx_confined, &sy_confined)) {
                    ddx = (sx_confined - sx) / scale;
                    ddy = (sy_confined - sy) / scale;
                } else {
                    ddx = 0;
                    ddy = 0;
                }
            }
        }

        const rule_client = pointer_confine_rule_client();
        if (c.server.active_constraint == null and rule_client != null) {
            const box = pointer_client_warp_box(rule_client);
            const margin = 5.0;
            const min_x = @as(f64, @floatFromInt(box.x)) + @as(f64, @floatFromInt(rule_client.*.bw)) + margin;
            const min_y = @as(f64, @floatFromInt(box.y)) + @as(f64, @floatFromInt(rule_client.*.bw)) + margin;
            var max_x = @as(f64, @floatFromInt(box.x + box.width)) - @as(f64, @floatFromInt(rule_client.*.bw)) - margin - 1;
            var max_y = @as(f64, @floatFromInt(box.y + box.height)) - @as(f64, @floatFromInt(rule_client.*.bw)) - margin - 1;
            if (max_x < min_x) max_x = min_x;
            if (max_y < min_y) max_y = min_y;
            ddx = @min(@max(c.server.cursor.*.x + ddx, min_x), max_x) - c.server.cursor.*.x;
            ddy = @min(@max(c.server.cursor.*.y + ddy, min_y), max_y) - c.server.cursor.*.y;
        }

        c.wlr_cursor_move(c.server.cursor, device, ddx, ddy);
        pointer_cursor_activity();
        acwm_notify_activity(c.server.seat);

        if (c.config.sloppyfocus != 0) {
            const oldmon = c.server.selected_monitor;
            set_selected_monitor(monitor_at_point(c.server.cursor.*.x, c.server.cursor.*.y));
            if (oldmon != c.server.selected_monitor)
                printstatus(@intCast(c.IPC_WATCH_MONITOR | c.IPC_WATCH_ALL_MONITORS));
        }
    }

    c.node_at_point(c.server.cursor.*.x, c.server.cursor.*.y, &surface, &hover_client, null, &bar, &sx, &sy);

    if (c.server.cursor_mode != c.CurMove and c.server.cursor_mode != c.CurResize) {
        var hover: [*c]Bar = null;
        if (bar != null) {
            const lx = c.server.cursor.*.x - @as(f64, @floatFromInt(bar.*.scene.*.node.x));
            const ly = c.server.cursor.*.y - @as(f64, @floatFromInt(bar.*.scene.*.node.y));
            if (acwm_bar_decoration_close_contains(bar, lx, ly))
                hover = bar;
        }
        if (c.server.group_bar_hover != hover) {
            if (c.server.group_bar_hover != null)
                acwm_bar_decoration_set_close_hover(c.server.group_bar_hover, false);
            if (hover != null)
                acwm_bar_decoration_set_close_hover(hover, true);
            c.server.group_bar_hover = hover;
        }
    }

    if (c.server.cursor_mode == c.CurPressed and c.server.seat.*.drag == null and
        surface != c.server.seat.*.pointer_state.focused_surface and
        toplevel_from_wlr_surface(c.server.seat.*.pointer_state.focused_surface, &w, &l) >= 0)
    {
        hover_client = w;
        surface = c.server.seat.*.pointer_state.focused_surface;
        sx = c.server.cursor.*.x - @as(f64, @floatFromInt(if (l != null) l.*.scene.*.node.x else w.*.geom.x));
        sy = c.server.cursor.*.y - @as(f64, @floatFromInt(if (l != null) l.*.scene.*.node.y else w.*.geom.y));
    }

    c.wlr_scene_node_set_position(&c.server.drag_icon.*.node,
        @intFromFloat(@round(c.server.cursor.*.x)), @intFromFloat(@round(c.server.cursor.*.y)));

    if (c.server.group_bar_drag_pending) {
        const gdx = c.server.cursor.*.x - c.server.group_bar_drag_x;
        const gdy = c.server.cursor.*.y - c.server.group_bar_drag_y;
        if (gdx * gdx + gdy * gdy >= 25.0) {
            const dc = c.server.group_bar_drag_client;
            c.server.group_bar_drag_pending = false;
            c.server.group_bar_drag_client = null;
            if (dc != null and dc.*.iskilling == 0) {
                if (client_group_active(dc) != null)
                    client_group_leave(dc);
                client_focus(dc, 1);
                _ = pointer_begin_move_resize(dc, c.CurMove, c.server.cursor.*.x, c.server.cursor.*.y, 0);
            }
        }
    }

    pointerUpdateResizeCursor(hover_client, surface);

    if (c.server.cursor_mode == c.CurMove) {
        c.server.grab_client.*.iscustomsize = 1;
        c.server.grab_client.*.float_geom = .{
            .x = @as(i32, @intFromFloat(@round(c.server.cursor.*.x))) - c.server.grab_offset_x,
            .y = @as(i32, @intFromFloat(@round(c.server.cursor.*.y))) - c.server.grab_offset_y,
            .width = c.server.grab_client.*.geom.width,
            .height = c.server.grab_client.*.geom.height,
        };
        var target: [*c]Client = null;
        if (c.server.grab_client.*.drag_to_tile)
            target = groupBarTargetAt(c.server.cursor.*.x, c.server.cursor.*.y, c.server.grab_client);
        c.server.drop_to_group = target != null;
        const closest_drop_client = if (c.config.drag_tile_to_tile != 0 and c.server.grab_client.*.drag_to_tile)
            (if (target != null) target else find_closest_tiled_client(c.server.grab_client))
        else
            target;
        if (closest_drop_client != null and c.server.drop_client != null and closest_drop_client != c.server.drop_client) {
            c.server.drop_client.*.enable_drop_area_draw = false;
            client_set_drop_area(c.server.drop_client);
            c.server.drop_client = closest_drop_client;
            c.server.drop_client.*.enable_drop_area_draw = true;
            client_set_drop_area(c.server.drop_client);
        } else if (closest_drop_client != null) {
            c.server.drop_client = closest_drop_client;
            c.server.drop_client.*.enable_drop_area_draw = true;
            client_set_drop_area(c.server.drop_client);
        } else if (c.server.drop_client != null) {
            c.server.drop_client.*.enable_drop_area_draw = false;
            client_set_drop_area(c.server.drop_client);
            c.server.drop_client = null;
        }
        var opts = std.mem.zeroes(c.ResizeOpts);
        opts.interact = true;
        resize(c.server.grab_client, c.server.grab_client.*.float_geom, opts);
        return;
    } else if (c.server.cursor_mode == c.CurResize) {
        if (c.server.grab_client.*.isfloating != 0) {
            c.server.grab_client.*.iscustomsize = 1;
            if (c.server.last_apply_drag_time == 0 or
                time - @as(u32, @intCast(c.server.last_apply_drag_time)) >= drag_refresh_interval_ms(c.server.grab_client.*.mon))
            {
                pointer_resize_floating_window(c.server.grab_client, c.server.cursor.*.x, c.server.cursor.*.y);
                c.server.last_apply_drag_time = @intCast(time);
            }
            return;
        } else {
            resize_tile_client(c.server.grab_client, true, 0, 0, time);
            return;
        }
    }

    if (surface == null and c.server.seat.*.drag == null and !c.server.cursor_hidden)
        c.wlr_cursor_set_xcursor(c.server.cursor, c.server.cursor_manager, "default");

    if (hover_client != null and hover_client.*.mon != null and !hover_client.*.animation.running and
        (INSIDEMON(hover_client) or !ISSCROLLTILED(hover_client)))
        c.server.scroller_focus_lock = 0;

    should_lock = false;
    var speed: f64 = 0;
    if (c.config.edge_scroller_pointer_focus != 0)
        speed = @sqrt(ddx * ddx + ddy * ddy);

    if (c.server.scroller_focus_lock == 0 or !(hover_client != null and hover_client.*.mon != null and !INSIDEMON(hover_client))) {
        if (hover_client != null and hover_client.*.mon != null and ISSCROLLTILED(hover_client) and is_scroller_layout(hover_client.*.mon) and !INSIDEMON(hover_client))
            should_lock = true;
        if (!((c.config.edge_scroller_pointer_focus == 0 or speed < c.config.edge_scroller_focus_allow_speed) and
            hover_client != null and hover_client.*.mon != null and ISSCROLLTILED(hover_client) and is_scroller_layout(hover_client.*.mon) and !INSIDEMON(hover_client)))
            pointer_focus(hover_client, surface, sx, sy, time);
        if (should_lock and hover_client != null and hover_client.*.mon != null and ISTILED(hover_client) and hover_client == hover_client.*.mon.*.sel)
            c.server.scroller_focus_lock = 1;
    }
}

export fn handle_cursor_motion(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as(*c.struct_wlr_pointer_motion_event, @ptrCast(@alignCast(data.?)));
    ipc_notify_device_event(&event.*.pointer.*.base);
    if (check_trackpad_disabled(event.*.pointer))
        return;
    pointer_process_motion(event.*.time_msec, &event.*.pointer.*.base, event.*.delta_x, event.*.delta_y,
        event.*.unaccel_dx, event.*.unaccel_dy);
    toggle_hotarea(@intFromFloat(c.server.cursor.*.x), @intFromFloat(c.server.cursor.*.y));
}

export fn pointer_focus(cl: [*c]Client, surface: [*c]c.struct_wlr_surface, sx_in: f64, sy_in: f64, time_in: u32) callconv(.c) void {
    var sx = sx_in;
    var sy = sy_in;
    var time = time_in;
    if (c.config.sloppyfocus != 0 and !c.server.start_drag_window and cl != null and time != 0 and
        cl.*.scene != null and cl.*.scene.*.node.enabled and
        (cl.*.mon == null or cl.*.mon.*.isoverview == 0) and !cl.*.animation.tagining and
        (surface != c.server.seat.*.pointer_state.focused_surface or
            (c.server.selected_monitor != null and c.server.selected_monitor.*.isoverview != 0 and
                c.server.selected_monitor.*.sel != cl)) and
        client_is_unmanaged(cl) == 0 and VISIBLEON(cl, cl.*.mon))
        client_focus(cl, 0);

    if (c.server.active_constraint != null and
        surface != c.server.seat.*.pointer_state.focused_surface and
        toplevel_from_wlr_surface(c.server.active_constraint.*.surface, null, null) == c.LayerShell)
        pointer_constrain_cursor(null);

    if (surface == null) {
        c.wlr_seat_pointer_notify_clear_focus(c.server.seat);
        return;
    }

    if (time == 0) {
        var now: c.struct_timespec = undefined;
        _ = c.clock_gettime(c.CLOCK_MONOTONIC, &now);
        time = @intCast(now.tv_sec * 1000 + @divTrunc(now.tv_nsec, 1000000));
    }

    const scale = pointer_surface_scale(cl);
    sx *= scale;
    sy *= scale;

    if (cl == null or cl.*.mon == null or cl.*.mon.*.isoverview == 0) {
        const old_focus = c.server.seat.*.pointer_state.focused_surface;
        c.wlr_seat_pointer_notify_enter(c.server.seat, surface, sx, sy);
        if (surface != old_focus) {
            const head: [*c]c.struct_wl_list = @ptrCast(&c.server.pointer_constraints.*.constraints);
            var pos = c.server.pointer_constraints.*.constraints.next;
            while (pos != head) : (pos = pos.*.next) {
                const constraint = @as([*c]c.struct_wlr_pointer_constraint_v1, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.struct_wlr_pointer_constraint_v1, "link")));
                if (constraint.*.surface == surface) {
                    pointer_constrain_cursor(constraint);
                    break;
                }
            }
        }
    }
    c.wlr_seat_pointer_notify_motion(c.server.seat, time, sx, sy);
}

export fn handle_request_start_drag(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as(*c.struct_wlr_seat_request_start_drag_event, @ptrCast(@alignCast(data.?)));
    if (c.wlr_seat_validate_pointer_grab_serial(c.server.seat, event.*.origin, event.*.serial))
        c.wlr_seat_start_pointer_drag(c.server.seat, event.*.drag, event.*.serial)
    else
        c.wlr_data_source_destroy(event.*.drag.*.source);
}

export fn handle_request_set_cursor(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as(*c.struct_wlr_seat_pointer_request_set_cursor_event, @ptrCast(@alignCast(data.?)));
    if (c.server.cursor_mode != c.CurNormal and c.server.cursor_mode != c.CurPressed)
        return;
    if (c.server.hover_resize_edge != 0)
        return;
    if (event.*.seat_client == c.server.seat.*.pointer_state.focused_client) {
        if (last_cursor.surface != null and c.server.last_cursor_surface_destroy_listener.link.prev != null)
            c.wl_list_remove(&c.server.last_cursor_surface_destroy_listener.link);
        last_cursor.shape = 0;
        last_cursor.surface = event.*.surface;
        last_cursor.hotspot_x = event.*.hotspot_x;
        last_cursor.hotspot_y = event.*.hotspot_y;
        if (event.*.surface != null)
            c.wl_signal_add(&event.*.surface.*.events.destroy, &c.server.last_cursor_surface_destroy_listener);
        if (!c.server.cursor_hidden)
            c.wlr_cursor_set_surface(c.server.cursor, event.*.surface, event.*.hotspot_x, event.*.hotspot_y);
    }
}

export fn handle_start_drag(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const drag = @as([*c]c.struct_wlr_drag, @ptrCast(@alignCast(data.?)));
    if (drag.*.icon == null)
        return;
    drag.*.icon.*.data = &c.wlr_scene_drag_icon_create(c.server.drag_icon, drag.*.icon).*.node;
    const icon_destroy = @as(*c.struct_wl_listener, @ptrCast(@alignCast(c.ecalloc(1, @sizeOf(c.struct_wl_listener)) orelse return)));
    icon_destroy.notify = handle_drag_icon_destroy;
    c.wl_signal_add(&drag.*.icon.*.events.destroy, icon_destroy);
}

export fn pointer_cursor_activity() callconv(.c) void {
    _ = wl_event_source_timer_update(c.server.hide_cursor_source, @intCast(c.config.cursor_hide_timeout * 1000));
    if (!c.server.cursor_hidden)
        return;
    c.server.cursor_hidden = false;
    if (last_cursor.shape != 0)
        c.wlr_cursor_set_xcursor(c.server.cursor, c.server.cursor_manager, c.wlr_cursor_shape_v1_name(last_cursor.shape))
    else if (last_cursor.surface != null)
        c.wlr_cursor_set_surface(c.server.cursor, last_cursor.surface, last_cursor.hotspot_x, last_cursor.hotspot_y);
}

export fn pointer_hide_cursor(data: ?*anyopaque) callconv(.c) i32 {
    _ = data;
    c.wlr_cursor_unset_image(c.server.cursor);
    c.server.cursor_hidden = true;
    return 1;
}

export fn pointer_warp_to_client(cl: [*c]const Client) callconv(.c) void {
    if (INSIDEMON(cl)) {
        c.wlr_cursor_warp_closest(c.server.cursor, null,
            @as(f64, @floatFromInt(cl.*.geom.x)) + @as(f64, @floatFromInt(cl.*.geom.width)) / 2.0,
            @as(f64, @floatFromInt(cl.*.geom.y)) + @as(f64, @floatFromInt(cl.*.geom.height)) / 2.0);
        pointer_process_motion(0, null, 0, 0, 0, 0);
    }
}

export fn pointer_warp_to_monitor(m: [*c]Monitor) callconv(.c) void {
    c.wlr_cursor_warp_closest(c.server.cursor, null,
        @as(f64, @floatFromInt(m.*.w.x)) + @as(f64, @floatFromInt(m.*.w.width)) / 2.0,
        @as(f64, @floatFromInt(m.*.w.y)) + @as(f64, @floatFromInt(m.*.w.height)) / 2.0);
    c.wlr_cursor_set_xcursor(c.server.cursor, c.server.cursor_manager, "default");
    pointer_cursor_activity();
}

export fn handle_new_virtual_pointer(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as(*c.struct_wlr_virtual_pointer_v1_new_pointer_event, @ptrCast(@alignCast(data.?)));
    const device = &event.*.new_pointer.*.pointer.base;
    seat_device_add(device);
    c.wlr_cursor_attach_input_device(c.server.cursor, device);
    if (event.*.suggested_output != null)
        c.wlr_cursor_map_input_to_output(c.server.cursor, device, event.*.suggested_output);
    pointer_cursor_activity();
}

export fn find_closest_tiled_client(cl: [*c]Client) callconv(.c) [*c]Client {
    var closest: [*c]Client = null;
    var min_dist: c_long = std.math.maxInt(c_long);
    const cursor_mon = monitor_at_point(c.server.cursor.*.x, c.server.cursor.*.y);
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    var pos = c.server.clients.next;
    while (pos != head) : (pos = pos.*.next) {
        const tc = @as([*c]Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Client, "link")));
        if (tc == cl or !ISTILED(tc) or !VISIBLEON(tc, cursor_mon))
            continue;
        if (c.server.cursor.*.x >= @as(f64, @floatFromInt(tc.*.geom.x)) and
            c.server.cursor.*.x < @as(f64, @floatFromInt(tc.*.geom.x + tc.*.geom.width)) and
            c.server.cursor.*.y >= @as(f64, @floatFromInt(tc.*.geom.y)) and
            c.server.cursor.*.y < @as(f64, @floatFromInt(tc.*.geom.y + tc.*.geom.height)))
            return tc;
        const dx: i32 = tc.*.geom.x + @divTrunc(tc.*.geom.width, 2) - @as(i32, @intFromFloat(c.server.cursor.*.x));
        const dy: i32 = tc.*.geom.y + @divTrunc(tc.*.geom.height, 2) - @as(i32, @intFromFloat(c.server.cursor.*.y));
        const dist: c_long = @as(c_long, dx) * dx + @as(c_long, dy) * dy;
        if (dist < min_dist) {
            min_dist = dist;
            closest = tc;
        }
    }
    return closest;
}

export fn pointer_place_drag_tile(cl: [*c]Client) callconv(.c) void {
    const closest = find_closest_tiled_client(cl);
    if (closest != null and closest.*.mon != null) {
        const layout = closest.*.mon.*.pertag.*.ltidxs[get_client_tag_idx(closest)];
        if (closest.*.drop_direction == c.UNDIR) {
            client_set_floating(cl, 0);
            c.wl_list_safe_reinsert_prev(&closest.*.link, &cl.*.link);
            arrange(closest.*.mon, false, false);
            return;
        }
        if (layout.*.id == c.SCROLLER) {
            scroller_drop_tile(cl, closest, 0);
            return;
        }
        if (layout.*.id == c.VERTICAL_SCROLLER) {
            scroller_drop_tile(cl, closest, 1);
            return;
        }
        if (layout.*.id == c.DWINDLE) {
            const tag = get_client_tag_idx(cl);
            const insert_before = closest.*.drop_direction == c.LEFT or closest.*.drop_direction == c.UP;
            const split_h = closest.*.drop_direction == c.LEFT or closest.*.drop_direction == c.RIGHT;
            dwindle_insert(&cl.*.mon.*.pertag.*.dwindle_root[tag], cl, closest,
                c.config.dwindle_split_ratio, insert_before, split_h, c.config.dwindle_drop_simple_split == 0);
            client_set_floating(cl, 0);
            return;
        }
        if (layout.*.id == c.RIGHT_TILE) {
            if (closest.*.drop_direction == c.LEFT)
                c.wl_list_safe_reinsert_next(&closest.*.link, &cl.*.link)
            else if (closest.*.drop_direction == c.RIGHT)
                c.wl_list_safe_reinsert_prev(&closest.*.link, &cl.*.link)
            else if (closest.*.drop_direction == c.UP)
                c.wl_list_safe_reinsert_prev(&closest.*.link, &cl.*.link)
            else
                c.wl_list_safe_reinsert_next(&closest.*.link, &cl.*.link);
            client_set_floating(cl, 0);
            return;
        }
        if (closest.*.drop_direction == c.LEFT or closest.*.drop_direction == c.UP)
            c.wl_list_safe_reinsert_prev(&closest.*.link, &cl.*.link)
        else
            c.wl_list_safe_reinsert_next(&closest.*.link, &cl.*.link);
    }
    client_set_floating(cl, 0);
}

export fn pointer_process_button_press(event: [*c]c.struct_wlr_pointer_button_event) callconv(.c) bool {
    var c_: [*c]Client = null;
    var l: [*c]LayerSurface = null;
    var bar: [*c]Bar = null;
    var surface: [*c]c.struct_wlr_surface = null;
    const old_focus = c.server.seat.*.pointer_state.focused_surface;

    pointer_cursor_activity();
    acwm_notify_activity(c.server.seat);

    if (event.*.pointer != null and check_trackpad_disabled(event.*.pointer))
        return true;
    if (trackpad_gesture_drag_active())
        return true;
    keyboard_cancel_pending_release_bind();

    switch (event.*.state) {
        c.WL_POINTER_BUTTON_STATE_PRESSED => {
            c.server.cursor_mode = c.CurPressed;
            set_selected_monitor(monitor_at_point(c.server.cursor.*.x, c.server.cursor.*.y));
            if (c.server.session_locked != 0)
                return false;

            if (switcher_is_active() and (event.*.button == c.BTN_LEFT or event.*.button == c.BTN_RIGHT)) {
                const switcher_c = switcher_client_at(c.server.cursor.*.x, c.server.cursor.*.y);
                if (switcher_c == null)
                    switcher_close()
                else if (event.*.button == c.BTN_LEFT)
                    switcher_commit_client(switcher_c)
                else
                    pending_kill_client(switcher_c);
                c.wlr_seat_pointer_notify_clear_focus(c.server.seat);
                return true;
            }

            if (bar_handle_button_press(c.server.cursor.*.x, c.server.cursor.*.y, event.*.button))
                return true;

            c.node_at_point(c.server.cursor.*.x, c.server.cursor.*.y, &surface, null, null, &bar, null, null);
            if (toplevel_from_wlr_surface(surface, &c_, &l) >= 0) {
                if (c_ != null and c_.*.scene != null and c_.*.scene.*.node.enabled and
                    VISIBLEON(c_, c_.*.mon) and
                    (client_is_unmanaged(c_) == 0 or client_wants_focus(c_) != 0))
                    client_focus(c_, 1);
                if (surface != old_focus) {
                    c.wlr_seat_pointer_notify_clear_focus(c.server.seat);
                    pointer_process_motion(0, null, 0, 0, 0, 0);
                }
                if (l != null and c.server.exclusive_focus == null and
                    l.*.layer_surface.*.current.keyboard_interactive == c.ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_ON_DEMAND)
                    layer_focus(l);
            }

            if (c.server.selected_monitor != null and c.server.selected_monitor.*.isoverview != 0 and
                event.*.button == c.BTN_LEFT and c_ != null)
            {
                var arg = std.mem.zeroes(c.Arg);
                arg.tc = c_;
                _ = toggle_overview(&arg);
                return true;
            }
            if (c.server.selected_monitor != null and c.server.selected_monitor.*.isoverview != 0 and
                event.*.button == c.BTN_RIGHT and c_ != null)
            {
                pending_kill_client(c_);
                return true;
            }

            if (bar != null and !bar.*.is_tab and bar.*.node_data != null and event.*.button == c.BTN_LEFT) {
                const tc = @as([*c]Client, @ptrCast(@alignCast(bar.*.node_data)));
                const lx = c.server.cursor.*.x - @as(f64, @floatFromInt(bar.*.scene.*.node.x));
                const ly = c.server.cursor.*.y - @as(f64, @floatFromInt(bar.*.scene.*.node.y));
                if (acwm_bar_decoration_close_contains(bar, lx, ly)) {
                    pending_kill_client(tc);
                    return true;
                }
                client_handle_decorate_click(bar);
                if (tc.*.isfullscreen == 0 and tc.*.ismaximizescreen == 0 and client_is_unmanaged(tc) == 0) {
                    c.server.group_bar_drag_pending = true;
                    c.server.group_bar_drag_client = tc;
                    c.server.group_bar_drag_x = c.server.cursor.*.x;
                    c.server.group_bar_drag_y = c.server.cursor.*.y;
                }
                return true;
            }

            client_handle_decorate_click(bar);
            const mods = keyboard_hard_modifiers();
            var ji: i32 = 0;
            while (ji < c.config.mouse_bindings_count) : (ji += 1) {
                const m = &c.config.mouse_bindings[@intCast(ji)];
                const mode_matches = m.iscommonmode or
                    (m.isdefaultmode and c.server.key_mode.isdefault) or
                    c.strcmp(&c.server.key_mode.mode[0], &m.mode[0]) == 0;
                if (mode_matches and cleanMask(mods) == cleanMask(m.mod) and
                    event.*.button == m.button and m.func != null)
                {
                    _ = m.func.?(&m.arg);
                    return true;
                }
            }

            if (event.*.button == c.BTN_LEFT and c_ != null and bar == null and c.config.enable_border_resize != 0) {
                const edge = clientResizeEdgeAt(c_, surface, c.server.cursor.*.x, c.server.cursor.*.y);
                if (edge != 0 and pointer_begin_move_resize(c_, c.CurResize, c.server.cursor.*.x, c.server.cursor.*.y, edge))
                    return true;
            }
        },
        c.WL_POINTER_BUTTON_STATE_RELEASED => {
            c.server.group_bar_drag_pending = false;
            c.server.drop_to_group = false;
            c.server.group_bar_drag_client = null;
            if (c.server.cursor_mode == c.CurMove and c.server.grab_client != null and
                c.server.grab_client.*.drag_to_tile)
            {
                const jc = c.server.grab_client;
                const target = groupBarTargetAt(c.server.cursor.*.x, c.server.cursor.*.y, jc);
                if (target != null) {
                    c.server.grab_client = null;
                    c.server.cursor_mode = c.CurNormal;
                    c.server.start_drag_window = false;
                    c.server.last_apply_drag_time = 0;
                    jc.*.drag_to_tile = false;
                    if (c.server.drop_client != null) {
                        c.server.drop_client.*.enable_drop_area_draw = false;
                        client_set_drop_area(c.server.drop_client);
                        c.server.drop_client = null;
                    }
                    client_group_join(jc, target);
                    c.wlr_seat_pointer_clear_focus(c.server.seat);
                    return true;
                }
            }
            if (c.server.session_locked == 0 and c.server.cursor_mode != c.CurNormal and
                c.server.cursor_mode != c.CurPressed)
            {
                pointer_end_grab_client(true);
                return true;
            } else {
                c.server.cursor_mode = c.CurNormal;
            }
        },
        else => {},
    }
    return false;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/pointer_input_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_reinsert_prev: c_int;
extern var stub_reinsert_next: c_int;
extern var stub_is_unmanaged: c_int;
extern var stub_wants_focus: c_int;
extern var stub_surface: c.struct_wlr_surface;
extern var stub_focus_calls: c_int;
extern var stub_set_floating_calls: c_int;
extern var stub_set_monitor_calls: c_int;
extern var stub_set_monitor_client: [*c]Client;
extern var stub_set_monitor_arg: [*c]Monitor;
extern var stub_oldmon_calls: c_int;
extern var stub_drop_area_calls: c_int;
extern var stub_group_leave_calls: c_int;
extern var stub_group_join_calls: c_int;
extern var stub_decorate_click_calls: c_int;
extern var stub_exit_stack_calls: c_int;
extern var stub_size_per_calls: c_int;
extern var stub_resize_calls: c_int;
extern var stub_resize_geo: Box;
extern var stub_resize_opts: c.ResizeOpts;
extern var stub_resize_tile_calls: c_int;
extern var stub_snap_calls: c_int;
extern var stub_monitor_at: [*c]Monitor;
extern var stub_selected_calls: c_int;
extern var stub_selected_arg: [*c]Monitor;
extern var stub_scroller_layout: bool;
extern var stub_drop_tile_calls: c_int;
extern var stub_dwindle_calls: c_int;
extern var stub_arrange_calls: c_int;
extern var stub_layer_focus_calls: c_int;
extern var stub_kill_calls: c_int;
extern var stub_node_at_calls: c_int;
extern var stub_node_surface: [*c]c.struct_wlr_surface;
extern var stub_node_client: [*c]Client;
extern var stub_node_bar: [*c]Bar;
extern var stub_node_x: f64;
extern var stub_node_y: f64;
extern var stub_toplevel_result: i32;
extern var stub_toplevel_client: [*c]Client;
extern var stub_ipc_calls: c_int;
extern var stub_activity_calls: c_int;
extern var stub_printstatus_calls: c_int;
extern var stub_trackpad_drag: bool;
extern var stub_trackpad_disabled: bool;
extern var stub_mods: u32;
extern var stub_cancel_release_calls: c_int;
extern var stub_seat_device_calls: c_int;
extern var stub_toggle_overview_calls: c_int;
extern var stub_move_calls: c_int;
extern var stub_move_x: f64;
extern var stub_move_y: f64;
extern var stub_warp_closest_calls: c_int;
extern var stub_warp_closest_x: f64;
extern var stub_warp_closest_y: f64;
extern var stub_xcursor_calls: c_int;
extern var stub_xcursor_name: [*c]const u8;
extern var stub_set_surface_calls: c_int;
extern var stub_unset_image_calls: c_int;
extern var stub_map_input_calls: c_int;
extern var stub_resize_name: [*c]const u8;
extern var stub_clear_focus_calls: c_int;
extern var stub_notify_clear_calls: c_int;
extern var stub_enter_calls: c_int;
extern var stub_motion_calls: c_int;
extern var stub_validate_serial: bool;
extern var stub_start_drag_calls: c_int;
extern var stub_source_destroy_calls: c_int;
extern var stub_node_pos_calls: c_int;
extern var stub_rel_motion_calls: c_int;
extern var stub_confine_result: bool;
extern var stub_timer_calls: c_int;
extern var stub_timer_ms: i32;
extern var stub_handle_icon_destroy: c_int;

var test_cursor: c.struct_wlr_cursor = undefined;
var test_seat: c.struct_wlr_seat = undefined;
var test_drag_icon: c.struct_wlr_scene_tree = undefined;
var test_constraints: c.struct_wlr_pointer_constraints_v1 = undefined;

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

fn resetPointerInputWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    listInit(&c.server.clients);
    test_cursor = std.mem.zeroes(c.struct_wlr_cursor);
    test_seat = std.mem.zeroes(c.struct_wlr_seat);
    c.server.cursor = &test_cursor;
    c.server.seat = &test_seat;
    c.server.cursor_manager = @ptrFromInt(0x9000);
    test_drag_icon = std.mem.zeroes(c.struct_wlr_scene_tree);
    c.server.drag_icon = &test_drag_icon;
    test_constraints = std.mem.zeroes(c.struct_wlr_pointer_constraints_v1);
    listInit(&test_constraints.constraints);
    c.server.pointer_constraints = &test_constraints;
    last_cursor = std.mem.zeroes(LastCursor);
    pointer_locked_applied = false;
    stub_reinsert_prev = 0;
    stub_reinsert_next = 0;
    stub_is_unmanaged = 0;
    stub_wants_focus = 0;
    stub_surface = std.mem.zeroes(c.struct_wlr_surface);
    stub_focus_calls = 0;
    stub_set_floating_calls = 0;
    stub_set_monitor_calls = 0;
    stub_set_monitor_client = null;
    stub_set_monitor_arg = null;
    stub_oldmon_calls = 0;
    stub_drop_area_calls = 0;
    stub_group_leave_calls = 0;
    stub_group_join_calls = 0;
    stub_decorate_click_calls = 0;
    stub_exit_stack_calls = 0;
    stub_size_per_calls = 0;
    stub_resize_calls = 0;
    stub_resize_geo = std.mem.zeroes(Box);
    stub_resize_opts = std.mem.zeroes(c.ResizeOpts);
    stub_resize_tile_calls = 0;
    stub_snap_calls = 0;
    stub_monitor_at = null;
    stub_selected_calls = 0;
    stub_selected_arg = null;
    stub_scroller_layout = false;
    stub_drop_tile_calls = 0;
    stub_dwindle_calls = 0;
    stub_arrange_calls = 0;
    stub_layer_focus_calls = 0;
    stub_kill_calls = 0;
    stub_node_at_calls = 0;
    stub_node_surface = null;
    stub_node_client = null;
    stub_node_bar = null;
    stub_node_x = 0;
    stub_node_y = 0;
    stub_toplevel_result = -1;
    stub_toplevel_client = null;
    stub_ipc_calls = 0;
    stub_activity_calls = 0;
    stub_printstatus_calls = 0;
    stub_trackpad_drag = false;
    stub_trackpad_disabled = false;
    stub_mods = 0;
    stub_cancel_release_calls = 0;
    stub_seat_device_calls = 0;
    stub_toggle_overview_calls = 0;
    stub_move_calls = 0;
    stub_move_x = 0;
    stub_move_y = 0;
    stub_warp_closest_calls = 0;
    stub_warp_closest_x = 0;
    stub_warp_closest_y = 0;
    stub_xcursor_calls = 0;
    stub_xcursor_name = null;
    stub_set_surface_calls = 0;
    stub_unset_image_calls = 0;
    stub_map_input_calls = 0;
    stub_clear_focus_calls = 0;
    stub_notify_clear_calls = 0;
    stub_enter_calls = 0;
    stub_motion_calls = 0;
    stub_validate_serial = true;
    stub_start_drag_calls = 0;
    stub_source_destroy_calls = 0;
    stub_node_pos_calls = 0;
    stub_rel_motion_calls = 0;
    stub_confine_result = false;
    stub_timer_calls = 0;
    stub_timer_ms = 0;
    stub_handle_icon_destroy = 0;
}

fn mkClient(cl: *Client, m: *Monitor, x: i32, y: i32, w: i32, h: i32) void {
    cl.* = std.mem.zeroes(Client);
    cl.mon = m;
    cl.tags = 1;
    cl.geom = .{ .x = x, .y = y, .width = w, .height = h };
    cl.bw = 2;
}

test "resize floating clamps and applies edges" {
    resetPointerInputWorld();
    var cl: Client = std.mem.zeroes(Client);
    cl.geom = .{ .x = 100, .y = 100, .width = 300, .height = 200 };
    cl.bw = 2;
    c.server.resize_edge = c.WLR_EDGE_RIGHT | c.WLR_EDGE_BOTTOM;
    c.server.grab_offset_x = 100;
    c.server.grab_offset_y = 100;
    pointer_resize_floating_window(&cl, 150, 160);
    try testing.expectEqual(@as(i32, 350), stub_resize_geo.width);
    try testing.expectEqual(@as(i32, 260), stub_resize_geo.height);
    try testing.expectEqual(@as(i32, 350), cl.float_geom.width);
    try testing.expectEqual(@as(c_int, 1), stub_resize_calls);
    try testing.expectEqual(@as(i32, 150), c.server.grab_offset_x);

    c.server.resize_edge = c.WLR_EDGE_LEFT | c.WLR_EDGE_TOP;
    c.server.grab_offset_x = 100;
    c.server.grab_offset_y = 100;
    cl.geom = .{ .x = 100, .y = 100, .width = 300, .height = 200 };
    pointer_resize_floating_window(&cl, 0, 0);
    try testing.expectEqual(@as(i32, 0), stub_resize_geo.x);
    try testing.expectEqual(@as(i32, 400), stub_resize_geo.width);
}

test "begin move creates a floating drag" {
    resetPointerInputWorld();
    var m: Monitor = std.mem.zeroes(Monitor);
    var cl: Client = std.mem.zeroes(Client);
    mkClient(&cl, &m, 100, 100, 300, 200);
    c.server.cursor_mode = c.CurNormal;
    test_cursor.x = 150;
    test_cursor.y = 160;
    try testing.expect(pointer_begin_move_resize(&cl, c.CurMove, 150, 160, 0));
    try testing.expect(cl.drag_to_tile);
    try testing.expectEqual(@as(c_int, 1), stub_set_floating_calls);
    try testing.expectEqual(@as(c_int, 1), stub_exit_stack_calls);
    try testing.expectEqual(@as(c_int, 1), stub_size_per_calls);
    try testing.expectEqual(@as(i32, 50), c.server.grab_offset_x);
    try testing.expectEqual(@as(i32, 60), c.server.grab_offset_y);
    try testing.expectEqualStrings("grab", std.mem.span(stub_xcursor_name));
    try testing.expect(c.server.grab_client == &cl);

    resetPointerInputWorld();
    var cl2: Client = std.mem.zeroes(Client);
    mkClient(&cl2, &m, 100, 100, 300, 200);
    cl2.ismaximizescreen = 1;
    try testing.expect(!pointer_begin_move_resize(&cl2, c.CurMove, 0, 0, 0));
    try testing.expect(c.server.grab_client == null);
}

test "begin resize computes corners and cursor names" {
    resetPointerInputWorld();
    var m: Monitor = std.mem.zeroes(Monitor);
    var cl: Client = std.mem.zeroes(Client);
    mkClient(&cl, &m, 100, 100, 300, 200);
    cl.isfloating = 1;
    c.server.cursor_mode = c.CurNormal;
    c.config.drag_corner = 4;
    c.config.drag_warp_cursor = 0;
    test_cursor.x = 390;
    test_cursor.y = 290;
    try testing.expect(pointer_begin_move_resize(&cl, c.CurResize, 390, 290, 0));
    try testing.expectEqual(@as(u32, c.WLR_EDGE_RIGHT | c.WLR_EDGE_BOTTOM), c.server.resize_edge);
    try testing.expectEqual(@as(i32, 390), c.server.grab_offset_x);
    try testing.expectEqualStrings("resize", std.mem.span(stub_xcursor_name));

    resetPointerInputWorld();
    mkClient(&cl, &m, 100, 100, 300, 200);
    c.server.cursor_mode = c.CurNormal;
    try testing.expect(pointer_begin_move_resize(&cl, c.CurResize, 110, 110, c.WLR_EDGE_LEFT));
    try testing.expectEqualStrings("col-resize", std.mem.span(stub_xcursor_name));
}

test "end grab moves the client to the target monitor" {
    resetPointerInputWorld();
    var m1: Monitor = std.mem.zeroes(Monitor);
    var m2: Monitor = std.mem.zeroes(Monitor);
    m2.tagset[0] = 2;
    var cl: Client = std.mem.zeroes(Client);
    mkClient(&cl, &m1, 100, 100, 300, 200);
    c.server.grab_client = &cl;
    c.server.cursor_mode = c.CurMove;
    c.server.grab_pointer_x = 100;
    c.server.grab_pointer_y = 100;
    c.server.selected_monitor = &m1;
    m1.sel = &cl;
    test_cursor.x = 500;
    test_cursor.y = 500;
    stub_monitor_at = &m2;
    pointer_end_grab_client(true);
    try testing.expectEqual(@as(c_int, 1), stub_selected_calls);
    try testing.expect(stub_selected_arg == &m2);
    try testing.expectEqual(@as(c_int, 1), stub_set_monitor_calls);
    try testing.expect(stub_set_monitor_arg == &m2);
    try testing.expectEqual(@as(c_int, 1), stub_snap_calls);
    try testing.expectEqual(@as(u32, 2), cl.tags);
    try testing.expect(m2.sel == &cl);
    try testing.expect(c.server.grab_client == null);
}

test "pointer focus enters, scales and clears surfaces" {
    resetPointerInputWorld();
    var m: Monitor = std.mem.zeroes(Monitor);
    m.tagset[0] = 1;
    var cl: Client = std.mem.zeroes(Client);
    mkClient(&cl, &m, 100, 100, 300, 200);
    var tree: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    tree.node.enabled = true;
    cl.scene = &tree;
    c.config.sloppyfocus = 1;
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    pointer_focus(&cl, &surface, 10, 20, 5);
    try testing.expectEqual(@as(c_int, 1), stub_focus_calls);
    try testing.expectEqual(@as(c_int, 1), stub_enter_calls);
    try testing.expectEqual(@as(c_int, 1), stub_motion_calls);

    pointer_focus(null, null, 0, 0, 5);
    try testing.expectEqual(@as(c_int, 1), stub_notify_clear_calls);

    cl.type = @intCast(c.X11);
    cl.xwayland_scale = 2;
    c.config.xwayland_ignore_scale = 1;
    if (build_options.xwayland) {
        pointer_focus(&cl, &surface, 10, 20, 0);
        try testing.expectEqual(@as(c_int, 2), stub_enter_calls);
    }
}

test "cursor activity, hide and warp helpers" {
    resetPointerInputWorld();
    c.config.cursor_hide_timeout = 3;
    pointer_cursor_activity();
    try testing.expectEqual(@as(c_int, 1), stub_timer_calls);
    try testing.expectEqual(@as(i32, 3000), stub_timer_ms);
    try testing.expectEqual(@as(i32, 1), pointer_hide_cursor(null));
    try testing.expectEqual(@as(c_int, 1), stub_unset_image_calls);
    try testing.expect(c.server.cursor_hidden);

    last_cursor.surface = &stub_surface;
    last_cursor.hotspot_x = 3;
    last_cursor.hotspot_y = 4;
    c.server.cursor_hidden = true;
    pointer_cursor_activity();
    try testing.expectEqual(@as(c_int, 1), stub_set_surface_calls);

    var m: Monitor = std.mem.zeroes(Monitor);
    m.w = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
    m.m = m.w;
    pointer_warp_to_monitor(&m);
    try testing.expectEqual(@as(c_int, 1), stub_warp_closest_calls);
    try testing.expectEqual(@as(f64, 500), stub_warp_closest_x);

    var cl: Client = std.mem.zeroes(Client);
    cl.mon = &m;
    cl.geom = .{ .x = 100, .y = 100, .width = 200, .height = 100 };
    pointer_warp_to_client(&cl);
    try testing.expectEqual(@as(c_int, 2), stub_warp_closest_calls);
}

test "find closest tiles and place dropped clients" {
    resetPointerInputWorld();
    var m: Monitor = std.mem.zeroes(Monitor);
    m.tagset[0] = 1;
    c.server.selected_monitor = &m;
    var a: Client = std.mem.zeroes(Client);
    var b: Client = std.mem.zeroes(Client);
    mkClient(&a, &m, 0, 0, 200, 200);
    mkClient(&b, &m, 300, 0, 200, 200);
    listInsert(&c.server.clients, &a.link);
    listInsert(&c.server.clients, &b.link);
    stub_monitor_at = &m;
    test_cursor.x = 10;
    test_cursor.y = 10;
    try testing.expect(find_closest_tiled_client(null) == &a);

    var layout: c.Layout = std.mem.zeroes(c.Layout);
    layout.id = c.TILE;
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    p.ltidxs[0] = &layout;
    m.pertag = &p;
    b.drop_direction = c.LEFT;
    pointer_place_drag_tile(&b);
    try testing.expectEqual(@as(c_int, 1), stub_reinsert_prev);
    try testing.expectEqual(@as(c_int, 1), stub_set_floating_calls);

    layout.id = c.SCROLLER;
    pointer_place_drag_tile(&b);
    try testing.expectEqual(@as(c_int, 1), stub_drop_tile_calls);
}

test "button bindings, overview clicks and release complete grabs" {
    resetPointerInputWorld();
    var m: Monitor = std.mem.zeroes(Monitor);
    c.server.selected_monitor = &m;
    var event: c.struct_wlr_pointer_button_event = std.mem.zeroes(c.struct_wlr_pointer_button_event);
    event.button = c.BTN_LEFT;
    event.state = c.WL_POINTER_BUTTON_STATE_PRESSED;
    var binding: c.MouseBinding = std.mem.zeroes(c.MouseBinding);
    binding.iscommonmode = true;
    binding.button = c.BTN_LEFT;
    binding.func = stub_mouse_func;
    c.config.mouse_bindings = &binding;
    c.config.mouse_bindings_count = 1;
    try testing.expect(pointer_process_button_press(&event));
    try testing.expectEqual(@as(c_int, 1), stub_mouse_func_calls);

    stub_mouse_func_calls = 0;
    m.isoverview = 1;
    var cl: Client = std.mem.zeroes(Client);
    cl.mon = &m;
    stub_node_client = &cl;
    stub_toplevel_client = &cl;
    stub_node_surface = &stub_surface;
    stub_toplevel_result = 0;
    try testing.expect(pointer_process_button_press(&event));
    try testing.expectEqual(@as(c_int, 1), stub_toggle_overview_calls);

    resetPointerInputWorld();
    c.server.cursor_mode = c.CurMove;
    var gc: Client = std.mem.zeroes(Client);
    c.server.grab_client = &gc;
    c.server.selected_monitor = &m;
    m.sel = &gc;
    event.state = c.WL_POINTER_BUTTON_STATE_RELEASED;
    try testing.expect(pointer_process_button_press(&event));
    try testing.expect(c.server.grab_client == null);
}

extern var stub_mouse_func_calls: c_int;
extern fn stub_mouse_func(arg: [*c]const c.Arg) callconv(.c) i32;
