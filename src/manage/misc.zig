//! Port of the protocol/utility remainder of src/manage/misc.c
//! (Phase 5, manage slice 3, slice 50). The built-in idle cluster lives in
//! idle.zig; this module owns process/layout helpers, hit-testing,
//! xdg-decoration, session lock, image-capture, idle-inhibitor and
//! selection handling.

const std = @import("std");
const c = @import("cc");

const Client = c.Client;
const Monitor = c.Monitor;
const LayerSurface = c.LayerSurface;
const AcwmSceneNode = c.AcwmSceneNode;

extern fn client_focus(cl: ?*Client, lift: i32) callconv(.c) void;
extern fn client_focus_top(m: [*c]Monitor) callconv(.c) [*c]Client;
extern fn client_surface(cl: [*c]Client) callconv(.c) [*c]c.struct_wlr_surface;
extern fn client_notify_enter(s: [*c]c.struct_wlr_surface, kb: [*c]c.struct_wlr_keyboard) callconv(.c) void;
extern fn toplevel_from_wlr_surface(s: [*c]c.struct_wlr_surface, pc: [*c][*c]Client, pl: [*c][*c]LayerSurface) callconv(.c) i32;
extern fn reset_exclusive_layers_focus(m: [*c]Monitor) callconv(.c) void;
extern fn pointer_process_motion(time: u32, device: [*c]c.struct_wlr_input_device, dx: f64, dy: f64, dx_unaccel: f64, dy_unaccel: f64) callconv(.c) void;
extern fn arrange(m: [*c]Monitor, want_animation: bool, from_view: bool) callconv(.c) void;
extern fn bar_update_lock() callconv(.c) void;
extern fn rearm_idle_check() callconv(.c) void;
extern fn monitor_at_point(x: f64, y: f64) callconv(.c) [*c]Monitor;
extern fn wlr_idle_notifier_v1_set_inhibited(notifier: ?*c.struct_wlr_idle_notifier_v1, inhibited: bool) callconv(.c) void;

fn containerOf(comptime T: type, comptime field: []const u8, listener: [*c]c.struct_wl_listener) *T {
    return @ptrFromInt(@intFromPtr(listener) - @offsetOf(T, field));
}

fn ownerCast(comptime T: type, p: ?*anyopaque) [*c]T {
    return if (p) |q| @ptrCast(@alignCast(q)) else null;
}

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

fn listInsert(head: *c.struct_wl_list, link: *c.struct_wl_list) void {
    link.next = head.next;
    link.prev = head;
    head.next.*.prev = link;
    head.next = link;
}

// ---------------------------------------------------------------------------
// process and layout helpers
// ---------------------------------------------------------------------------

export fn get_parent_process(p: c.pid_t) callconv(.c) c.pid_t {
    if (p <= 0)
        return 0;

    var path_buf: [64]u8 = undefined;
    const path = std.fmt.bufPrintSentinel(&path_buf, "/proc/{d}/stat", .{@as(u32, @intCast(p))}, 0) catch return 0;

    const file = c.fopen(path.ptr, "r") orelse return 0;
    defer _ = c.fclose(file);

    var v: c_uint = 0;
    if (c.fscanf(file, "%*u %*s %*c %u", &v) != 1)
        return 0;
    return @intCast(v);
}

export fn is_descendant_process(p: c.pid_t, child: c.pid_t) callconv(.c) i32 {
    var cur = child;
    while (p != cur and cur != 0)
        cur = get_parent_process(cur);
    return @intCast(cur);
}

const LayoutMapping = struct { full: []const u8, abbr: []const u8 };

const layout_mappings = [_]LayoutMapping{
    .{ .full = "English (US)", .abbr = "us" },
    .{ .full = "English (UK)", .abbr = "gb" },
    .{ .full = "Russian", .abbr = "ru" },
    .{ .full = "German", .abbr = "de" },
    .{ .full = "French", .abbr = "fr" },
    .{ .full = "Spanish", .abbr = "es" },
    .{ .full = "Italian", .abbr = "it" },
    .{ .full = "Japanese", .abbr = "jp" },
    .{ .full = "Chinese", .abbr = "cn" },
    .{ .full = "Korean", .abbr = "kr" },
    .{ .full = "Arabic", .abbr = "ar" },
    .{ .full = "Hebrew", .abbr = "il" },
    .{ .full = "Greek", .abbr = "gr" },
    .{ .full = "Turkish", .abbr = "tr" },
    .{ .full = "Portuguese", .abbr = "pt" },
    .{ .full = "Portuguese (Brazil)", .abbr = "br" },
    .{ .full = "Swedish", .abbr = "se" },
    .{ .full = "Norwegian", .abbr = "no" },
    .{ .full = "Danish", .abbr = "dk" },
    .{ .full = "Finnish", .abbr = "fi" },
    .{ .full = "Polish", .abbr = "pl" },
    .{ .full = "Czech", .abbr = "cz" },
    .{ .full = "Hungarian", .abbr = "hu" },
    .{ .full = "Ukrainian", .abbr = "ua" },
    .{ .full = "Belarusian", .abbr = "by" },
    .{ .full = "Bulgarian", .abbr = "bg" },
    .{ .full = "Croatian", .abbr = "hr" },
    .{ .full = "Romanian", .abbr = "ro" },
    .{ .full = "Serbian", .abbr = "rs" },
    .{ .full = "Slovak", .abbr = "sk" },
    .{ .full = "Slovenian", .abbr = "si" },
    .{ .full = "Estonian", .abbr = "ee" },
    .{ .full = "Latvian", .abbr = "lv" },
    .{ .full = "Lithuanian", .abbr = "lt" },
    .{ .full = "Dutch", .abbr = "nl" },
    .{ .full = "Flemish", .abbr = "be" },
    .{ .full = "Swiss German", .abbr = "ch" },
    .{ .full = "French (Canada)", .abbr = "ca" },
    .{ .full = "French (Switzerland)", .abbr = "ch-fr" },
    .{ .full = "Icelandic", .abbr = "is" },
    .{ .full = "Maltese", .abbr = "mt" },
    .{ .full = "Irish", .abbr = "ie" },
    .{ .full = "Albanian", .abbr = "al" },
    .{ .full = "Macedonian", .abbr = "mk" },
    .{ .full = "Bosnian", .abbr = "ba" },
    .{ .full = "Montenegrin", .abbr = "me" },
    .{ .full = "Dvorak", .abbr = "dv" },
    .{ .full = "Colemak", .abbr = "cm" },
    .{ .full = "Workman", .abbr = "wm" },
    .{ .full = "Norman", .abbr = "nm" },
    .{ .full = "QGMLWY", .abbr = "qg" },
    .{ .full = "AZERTY", .abbr = "az" },
    .{ .full = "QWERTZ", .abbr = "qz" },
    .{ .full = "BÉPO (French ergonomic)", .abbr = "bepo" },
    .{ .full = "Neo", .abbr = "neo" },
    .{ .full = "Turkish F", .abbr = "trf" },
    .{ .full = "Tibetan", .abbr = "bo" },
    .{ .full = "Thai", .abbr = "th" },
    .{ .full = "Vietnamese", .abbr = "vn" },
    .{ .full = "Lao", .abbr = "la" },
    .{ .full = "Khmer", .abbr = "kh" },
    .{ .full = "Hindi", .abbr = "in" },
    .{ .full = "Persian", .abbr = "ir" },
    .{ .full = "Urdu", .abbr = "pk" },
    .{ .full = "Bangla", .abbr = "bd" },
    .{ .full = "Sinhala", .abbr = "lk" },
    .{ .full = "Nepali", .abbr = "np" },
    .{ .full = "Tamil", .abbr = "ta" },
    .{ .full = "Telugu", .abbr = "te" },
    .{ .full = "Kannada", .abbr = "kn" },
    .{ .full = "Malayalam", .abbr = "ml" },
};

fn writeAbbr(abbr: [*c]u8, s: []const u8) void {
    std.mem.copyForwards(u8, abbr[0..s.len], s);
    abbr[s.len] = 0;
}

export fn get_layout_abbr(abbr: [*c]u8, full_name: [*c]const u8) callconv(.c) void {
    if (abbr == null)
        return;
    abbr[0] = 0;
    if (full_name == null)
        return;

    const name = std.mem.span(@as([*:0]const u8, @ptrCast(full_name)));

    for (layout_mappings) |m| {
        if (std.mem.eql(u8, name, m.full)) {
            writeAbbr(abbr, m.abbr);
            return;
        }
    }

    const open = std.mem.lastIndexOfScalar(u8, name, '(');
    const close = std.mem.lastIndexOfScalar(u8, name, ')');
    if (open != null and close != null and close.? > open.?) {
        const inner = name[open.? + 1 .. close.?];
        if (inner.len > 0 and inner.len <= 4) {
            for (inner, 0..) |ch, j|
                abbr[j] = std.ascii.toLower(ch);
            abbr[inner.len] = 0;
            return;
        }
    }

    var j: usize = 0;
    var i: usize = 0;
    while (i < name.len and j < 3) : (i += 1) {
        if (std.ascii.isAlphabetic(name[i])) {
            abbr[j] = std.ascii.toLower(name[i]);
            j += 1;
        }
    }
    abbr[j] = 0;
    if (j >= 2)
        return;

    if (j == 1) {
        abbr[1] = if (name.len > 1 and name[1] != 0) std.ascii.toLower(name[1]) else 0;
        abbr[2] = 0;
    } else {
        writeAbbr(abbr, "xx");
    }
}

// ---------------------------------------------------------------------------
// hit testing
// ---------------------------------------------------------------------------

export fn client_at_point(x: f64, y: f64) callconv(.c) ?*Client {
    var pos = c.server.clients.next;
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = @as(*Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(Client, "link")));
        const m = monitorOpt(cl.mon);
        if (m != null and VISIBLEON(cl, m.?) and
            @as(f64, @floatFromInt(cl.animation.current.x)) <= x and
            @as(f64, @floatFromInt(cl.animation.current.y)) <= y and
            @as(f64, @floatFromInt(cl.animation.current.x + cl.animation.current.width)) >= x and
            @as(f64, @floatFromInt(cl.animation.current.y + cl.animation.current.height)) >= y)
            return cl;
    }
    return null;
}

export fn layer_ignores_focus(l_in: [*c]LayerSurface) callconv(.c) bool {
    if (l_in == null)
        return true;
    const l = @as(*LayerSurface, @ptrCast(l_in));
    if (l.layer_surface == null)
        return true;
    const s = l.layer_surface.*.surface;
    if (s == null)
        return true;
    if (c.pixman_region32_not_empty(&s.*.input_region) == 0)
        return true;
    return l.layer_surface.*.current.keyboard_interactive == 0;
}

fn nodeTypeIs(node: *const c.struct_wlr_scene_node, t: c_int) bool {
    return node.type == @as(c.enum_wlr_scene_node_type, @intCast(t));
}

export fn node_at_point(x: f64, y: f64, psurface: [*c][*c]c.struct_wlr_surface, pc: [*c][*c]Client, pl: [*c][*c]LayerSurface, bar: [*c][*c]c.AcwmBarDecoration, nx: [*c]f64, ny: [*c]f64) callconv(.c) void {
    var node: [*c]c.struct_wlr_scene_node = null;
    var surface: [*c]c.struct_wlr_surface = null;
    var c_hit: [*c]Client = null;
    var l_hit: [*c]LayerSurface = null;
    var bar_deco: [*c]c.AcwmBarDecoration = null;

    if (psurface != null) psurface[0] = null;
    if (pc != null) pc[0] = null;
    if (pl != null) pl[0] = null;
    if (bar != null) bar[0] = null;

    var layer: c_int = c.NUM_LAYERS - 1;
    while (layer >= 0) : (layer -= 1) {
        if (layer == c.LyrFadeOut)
            continue;

        const idx: usize = @intCast(layer);
        const wrap = c.server.layers_wrap[idx];
        if (wrap == null)
            continue;
        node = c.acwm_scene_node_at(&wrap.*.node, x, y, nx, ny);
        if (node == null)
            continue;

        const data = c.acwm_scene_node_find(node);
        const cm = monitor_at_point(x, y);
        if (cm != null and cm.*.special_dim_rect != null and
            cm.*.special_dim_rect.*.node.enabled and
            @intFromPtr(node) == @intFromPtr(&cm.*.special_dim_rect.*.node))
        {
            c_hit = null;
            l_hit = null;
            surface = null;
            bar_deco = null;
            break;
        }

        if (nodeTypeIs(node, c.WLR_SCENE_NODE_BUFFER)) {
            const scene_buffer = c.wlr_scene_buffer_from_node(node);
            if (scene_buffer != null) {
                const scene_surface = c.wlr_scene_surface_try_from_buffer(scene_buffer);
                if (scene_surface != null)
                    surface = scene_surface.*.surface;
            }
        }

        if (layer == c.LyrIMPopup) {
            c_hit = null;
            l_hit = null;
        } else if (data != null) {
            const dt = data.*.type;
            if (dt == @as(u32, @intCast(c.LayerShell))) {
                l_hit = ownerCast(LayerSurface, data.*.owner);
            } else if (dt == @as(u32, @intCast(c.GroupBar)) or dt == @as(u32, @intCast(c.TabBar))) {
                bar_deco = ownerCast(c.AcwmBarDecoration, data.*.owner);
            } else if (dt == @as(u32, @intCast(c.XDGShell)) or dt == @as(u32, @intCast(c.X11))) {
                c_hit = ownerCast(Client, data.*.owner);
            }
        }

        if (nodeTypeIs(node, c.WLR_SCENE_NODE_RECT)) {
            if (c_hit != null and (c_hit.*.type == c.XDGShell or c_hit.*.type == c.X11))
                surface = client_surface(c_hit);
            if (l_hit != null and l_hit.*.type == @as(u32, @intCast(c.LayerShell)))
                surface = l_hit.*.layer_surface.*.surface;
        }

        break;
    }

    if (psurface != null) psurface[0] = surface;
    if (pc != null) pc[0] = c_hit;
    if (pl != null) pl[0] = l_hit;
    if (bar != null) bar[0] = bar_deco;

    const selected = monitorOpt(c.server.selected_monitor);
    if (selected != null and selected.?.isoverview != 0) {
        const ovc = client_at_point(x, y);
        if (ovc != null and (l_hit == null or layer_ignores_focus(l_hit))) {
            if (pc != null) pc[0] = ovc;
            if (psurface != null) psurface[0] = if (ovc) |o| client_surface(@ptrCast(o)) else null;
            if (pl != null) pl[0] = null;
            if (bar != null) bar[0] = null;
        }
    }
}

// ---------------------------------------------------------------------------
// idle inhibitors (protocol side; the timer lives in idle.zig)
// ---------------------------------------------------------------------------

export fn check_idle_inhibitor(exclude: [*c]c.struct_wlr_surface) callconv(.c) void {
    if (c.server.idle_inhibit_manager == null)
        return;

    var inhibited: c_int = 0;
    const manager = @as(*c.struct_wlr_idle_inhibit_manager_v1, @ptrCast(c.server.idle_inhibit_manager));
    const head: [*c]c.struct_wl_list = @ptrCast(&manager.inhibitors);
    var pos = manager.inhibitors.next;
    while (pos != head) : (pos = pos.*.next) {
        const inhibitor = @as(*c.struct_wlr_idle_inhibitor_v1, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.struct_wlr_idle_inhibitor_v1, "link")));
        const surface = c.wlr_surface_get_root_surface(inhibitor.surface);
        if (exclude == surface)
            continue;

        var cl_ptr: [*c]Client = null;
        _ = toplevel_from_wlr_surface(inhibitor.surface, &cl_ptr, null);
        const cl = clientOpt(cl_ptr);

        if (c.config.idleinhibit_ignore_visible != 0) {
            inhibited = 1;
            break;
        }

        const tree: [*c]c.struct_wlr_scene_tree = if (surface.*.data) |d| @ptrCast(@alignCast(d)) else null;
        if (tree == null or (tree.*.node.enabled and (cl == null or !cl.?.animation.tagouting))) {
            inhibited = 1;
            break;
        }
    }

    if (c.server.idle_notifier != null)
        wlr_idle_notifier_v1_set_inhibited(c.server.idle_notifier, inhibited != 0);
    c.server.idle_inhibited = inhibited != 0;
    rearm_idle_check();
}

export fn handle_new_idle_inhibitor(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const inhibitor = @as(*c.struct_wlr_idle_inhibitor_v1, @ptrCast(@alignCast(data.?)));

    const l = c.ecalloc(1, @sizeOf(c.struct_wl_listener)) orelse return;
    const wl_listener = @as(*c.struct_wl_listener, @ptrCast(@alignCast(l)));
    wl_listener.notify = handle_idle_inhibitor_destroy;
    c.wl_signal_add(&inhibitor.events.destroy, wl_listener);

    check_idle_inhibitor(null);
}

export fn handle_idle_inhibitor_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    const root = c.wlr_surface_get_root_surface(@as([*c]c.struct_wlr_surface, @ptrCast(@alignCast(data.?))));
    check_idle_inhibitor(root);
    c.wl_list_remove(&listener.*.link);
    c.free(listener);
}

// ---------------------------------------------------------------------------
// xdg-decoration
// ---------------------------------------------------------------------------

export fn handle_xdg_decoration_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const cl = containerOf(Client, "destroy_decoration", listener);
    c.wl_list_remove(&cl.destroy_decoration.link);
    c.wl_list_remove(&cl.set_decoration_mode.link);
    cl.decoration = null;
}

export fn handle_xdg_decoration_mode_request(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    const cl = containerOf(Client, "set_decoration_mode", listener);
    const deco = @as(*c.struct_wlr_xdg_toplevel_decoration_v1, @ptrCast(@alignCast(data.?)));

    const xdg = cl.surface.xdg;
    if (xdg == null or !xdg.*.initialized)
        return;

    var requested = deco.requested_mode;
    if (cl.allow_csd == 0)
        requested = @intCast(c.WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE);
    if (cl.decoration != null)
        _ = c.wlr_xdg_toplevel_decoration_v1_set_mode(cl.decoration, requested);
}

export fn handle_new_xdg_decoration(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const deco = @as(*c.struct_wlr_xdg_toplevel_decoration_v1, @ptrCast(@alignCast(data.?)));
    const xdg_surface = deco.toplevel.*.base;
    const cl = @as(*Client, @ptrCast(@alignCast(xdg_surface.*.data.?)));
    cl.decoration = deco;

    c.wl_signal_add(&deco.events.request_mode, &cl.set_decoration_mode);
    cl.set_decoration_mode.notify = handle_xdg_decoration_mode_request;
    c.wl_signal_add(&deco.events.destroy, &cl.destroy_decoration);
    cl.destroy_decoration.notify = handle_xdg_decoration_destroy;

    handle_xdg_decoration_mode_request(&cl.set_decoration_mode, deco);
}

// ---------------------------------------------------------------------------
// session lock
// ---------------------------------------------------------------------------

const SessionLock = extern struct {
    scene: [*c]c.struct_wlr_scene_tree,
    lock: [*c]c.struct_wlr_session_lock_v1,
    new_surface: c.struct_wl_listener,
    unlock: c.struct_wl_listener,
    destroy: c.struct_wl_listener,
};

fn monitorFromLink(link: [*c]c.struct_wl_list) *Monitor {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(Monitor, "link"));
}

fn sessionLockFocusTarget() [*c]c.struct_wlr_surface {
    if (c.server.selected_monitor != null and c.server.selected_monitor.*.lock_surface != null)
        return c.server.selected_monitor.*.lock_surface.*.surface;

    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.monitors);
    var pos = c.server.monitors.next;
    while (pos != head) : (pos = pos.*.next) {
        const m = monitorFromLink(pos);
        if (m.wlr_output != null and m.wlr_output.*.enabled and m.lock_surface != null)
            return m.lock_surface.*.surface;
    }

    pos = c.server.monitors.next;
    while (pos != head) : (pos = pos.*.next) {
        const m = monitorFromLink(pos);
        if (m.lock_surface != null)
            return m.lock_surface.*.surface;
    }

    return null;
}

export fn session_lock_focus_restore() callconv(.c) void {
    if (c.server.session_locked == 0 or c.server.current_lock == null)
        return;

    const target = sessionLockFocusTarget();
    if (target == null or c.server.seat == null)
        return;
    if (c.server.seat.*.keyboard_state.focused_surface == target)
        return;

    client_notify_enter(target, c.wlr_seat_get_keyboard(c.server.seat));
}

export fn session_lock_focus_missing() callconv(.c) bool {
    if (c.server.session_locked == 0 or c.server.current_lock == null)
        return false;

    const target = sessionLockFocusTarget();
    if (target == null or c.server.seat == null)
        return false;
    return c.server.seat.*.keyboard_state.focused_surface != target;
}

export fn handle_session_lock_new_surface(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    const lock = containerOf(SessionLock, "new_surface", listener);
    const lock_surface = @as(*c.struct_wlr_session_lock_surface_v1, @ptrCast(@alignCast(data.?)));

    if (lock_surface.output == null or lock_surface.output.*.data == null or lock_surface.surface == null)
        return;
    const m = @as(*Monitor, @ptrCast(@alignCast(lock_surface.output.*.data.?)));

    const scene_tree = c.wlr_scene_subsurface_tree_create(lock.scene, lock_surface.surface);
    lock_surface.surface.*.data = @ptrCast(scene_tree);
    m.lock_surface = lock_surface;

    c.wlr_scene_node_set_position(&scene_tree.*.node, m.m.x, m.m.y);
    _ = c.wlr_session_lock_surface_v1_configure(lock_surface, @intCast(m.m.width), @intCast(m.m.height));

    c.wl_signal_add(&lock_surface.events.destroy, &m.destroy_lock_surface);
    m.destroy_lock_surface.notify = handle_session_lock_surface_destroy;

    session_lock_focus_restore();
}

export fn session_lock_cleanup(lock: *SessionLock, unlock: i32) callconv(.c) void {
    if (c.server.seat != null)
        c.wlr_seat_keyboard_notify_clear_focus(c.server.seat);

    c.server.session_locked = if (unlock != 0) 0 else 1;

    if (c.server.session_locked == 0) {
        if (c.server.locked_bg != null and c.server.locked_bg.*.node.enabled)
            c.wlr_scene_node_set_enabled(&c.server.locked_bg.*.node, false);

        client_focus(client_focus_top(c.server.selected_monitor), 1);
        pointer_process_motion(0, null, 0, 0, 0, 0);
        bar_update_lock();
    }

    c.wl_list_remove(&lock.new_surface.link);
    c.wl_list_remove(&lock.unlock.link);
    c.wl_list_remove(&lock.destroy.link);

    if (lock.scene != null)
        c.wlr_scene_node_destroy(&lock.scene.*.node);
    c.server.current_lock = null;
    c.free(lock);
}

export fn handle_session_lock_surface_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const m = containerOf(Monitor, "destroy_lock_surface", listener);
    const lock_surface = m.lock_surface;

    m.lock_surface = null;
    c.wl_list_remove(&m.destroy_lock_surface.link);
    if (lock_surface == null)
        return;

    const focused: [*c]c.struct_wlr_surface = if (c.server.seat != null) c.server.seat.*.keyboard_state.focused_surface else null;
    if (lock_surface.*.surface != focused) {
        if (c.server.exclusive_focus != null and c.server.session_locked == 0)
            reset_exclusive_layers_focus(m);
        return;
    }

    if (c.server.session_locked != 0)
        session_lock_focus_restore()
    else
        reset_exclusive_layers_focus(c.server.selected_monitor);
}

export fn handle_session_lock_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const lock = containerOf(SessionLock, "destroy", listener);
    session_lock_cleanup(lock, 0);
}

export fn handle_session_lock_unlock(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const lock = containerOf(SessionLock, "unlock", listener);
    session_lock_cleanup(lock, 1);
}

export fn handle_new_session_lock(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const session_lock = @as(*c.struct_wlr_session_lock_v1, @ptrCast(@alignCast(data.?)));

    if (c.config.allow_lock_transparent == 0 and c.server.locked_bg != null)
        c.wlr_scene_node_set_enabled(&c.server.locked_bg.*.node, true);

    if (c.server.current_lock != null) {
        c.wlr_session_lock_v1_destroy(session_lock);
        return;
    }

    const raw = c.ecalloc(1, @sizeOf(SessionLock)) orelse return;
    const lock = @as(*SessionLock, @ptrCast(@alignCast(raw)));
    session_lock.data = @ptrCast(lock);
    client_focus(null, 0);

    lock.scene = c.wlr_scene_tree_create(c.server.layers[@intCast(c.LyrBlock)]);
    bar_update_lock();
    c.server.current_lock = session_lock;
    lock.lock = session_lock;
    c.server.session_locked = 1;

    c.wl_signal_add(&session_lock.events.new_surface, &lock.new_surface);
    lock.new_surface.notify = handle_session_lock_new_surface;
    c.wl_signal_add(&session_lock.events.destroy, &lock.destroy);
    lock.destroy.notify = handle_session_lock_destroy;
    c.wl_signal_add(&session_lock.events.unlock, &lock.unlock);
    lock.unlock.notify = handle_session_lock_unlock;

    c.wlr_session_lock_v1_send_locked(session_lock);
}

// ---------------------------------------------------------------------------
// image capture
// ---------------------------------------------------------------------------

const CaptureSessionTracker = extern struct {
    session_destroy: c.struct_wl_listener,
    session: [*c]c.struct_wlr_ext_image_copy_capture_session_v1,
};

fn arrangeCaptureShields() void {
    var pos = c.server.clients.next;
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = @as(*Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(Client, "link")));
        if (cl.shield_when_capture != 0 and cl.iskilling == 0) {
            const m = monitorOpt(cl.mon);
            if (m != null and VISIBLEON(cl, m.?))
                arrange(cl.mon, false, false);
        }
    }
}

export fn handle_new_foreign_toplevel_capture_request(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const request = @as(*c.struct_wlr_ext_foreign_toplevel_image_capture_source_manager_v1_request, @ptrCast(@alignCast(data.?)));
    if (request.toplevel_handle == null or request.toplevel_handle.*.data == null)
        return;

    const cl = @as(*Client, @ptrCast(@alignCast(request.toplevel_handle.*.data.?)));
    if (cl.shield_when_capture != 0)
        return;

    if (cl.image_capture_source == null) {
        if (cl.image_capture_scene == null)
            return;
        cl.image_capture_source = c.wlr_ext_image_capture_source_v1_create_with_scene_node(
            &cl.image_capture_scene.*.tree.node,
            c.server.event_loop,
            c.server.allocator,
            c.server.renderer,
        );
        if (cl.image_capture_source == null)
            return;
    }

    _ = c.wlr_ext_foreign_toplevel_image_capture_source_manager_v1_request_accept(request, cl.image_capture_source);
}

export fn handle_session_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const tracker = containerOf(CaptureSessionTracker, "session_destroy", listener);
    c.server.active_capture_count -= 1;
    c.wl_list_remove(&tracker.session_destroy.link);
    arrangeCaptureShields();
    c.free(tracker);
}

fn captureSourceFormatSupported(renderer: [*c]c.struct_wlr_renderer, format: u32) bool {
    const formats = c.wlr_renderer_get_texture_formats(renderer, @intCast(c.WLR_BUFFER_CAP_DATA_PTR));
    if (formats == null)
        return false;
    var i: usize = 0;
    while (i < formats.*.len) : (i += 1) {
        if (formats.*.formats[i].format == format)
            return true;
    }
    return false;
}

fn captureSourceAddShmFormat(source: [*c]c.struct_wlr_ext_image_capture_source_v1, format: u32) bool {
    var i: usize = 0;
    while (i < source.*.shm_formats_len) : (i += 1) {
        if (source.*.shm_formats[i] == format)
            return false;
    }

    const new_len = source.*.shm_formats_len + 1;
    const raw = c.realloc(@ptrCast(source.*.shm_formats), new_len * @sizeOf(u32)) orelse return false;
    source.*.shm_formats = @as([*c]u32, @ptrCast(@alignCast(raw)));
    source.*.shm_formats[new_len - 1] = format;
    source.*.shm_formats_len = new_len;
    return true;
}

fn captureSessionAnnounceBgrShmFormats(session: [*c]c.struct_wlr_ext_image_copy_capture_session_v1) void {
    const source = session.*.source;
    if (source == null)
        return;

    const output = c.wlr_output_try_from_ext_image_capture_source_v1(source);
    var renderer = c.server.renderer;
    if (output != null and output.*.renderer != null)
        renderer = output.*.renderer;
    if (renderer == null)
        return;

    const bgr_formats = [_]u32{ c.DRM_FORMAT_XRGB8888, c.DRM_FORMAT_ARGB8888 };
    var updated = false;
    for (bgr_formats) |fmt| {
        if (!captureSourceFormatSupported(renderer, fmt))
            continue;
        if (captureSourceAddShmFormat(source, fmt))
            updated = true;
    }

    if (updated)
        c.wl_signal_emit_mutable(&source.*.events.constraints_update, null);
}

export fn handle_ext_image_copy_capture_new_session(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const capture_session = @as(*c.struct_wlr_ext_image_copy_capture_session_v1, @ptrCast(@alignCast(data.?)));

    captureSessionAnnounceBgrShmFormats(capture_session);

    const raw = c.ecalloc(1, @sizeOf(CaptureSessionTracker)) orelse return;
    const tracker = @as(*CaptureSessionTracker, @ptrCast(@alignCast(raw)));
    tracker.session = capture_session;
    tracker.session_destroy.notify = handle_session_destroy;
    c.wl_signal_add(&capture_session.events.destroy, &tracker.session_destroy);

    c.server.active_capture_count += 1;
    arrangeCaptureShields();
}

// ---------------------------------------------------------------------------
// seat selections
// ---------------------------------------------------------------------------

export fn handle_request_set_primary_selection(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as(*c.struct_wlr_seat_request_set_primary_selection_event, @ptrCast(@alignCast(data.?)));
    if (c.config.disable_middle_paste != 0)
        return;
    c.wlr_seat_set_primary_selection(c.server.seat, event.source, event.serial);
}

export fn apply_primary_selection() callconv(.c) void {
    if (c.config.disable_middle_paste == 0 or c.server.seat == null)
        return;
    const seat = c.server.seat;
    if (seat.*.primary_selection_source != null)
        c.wlr_seat_set_primary_selection(seat, null, c.wl_display_next_serial(c.server.display));
}

const PrimarySelectionPolicy = extern struct {
    destroy: c.struct_wl_listener,
    disable_middle_paste: bool,
};

export fn handle_primary_selection_policy_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const policy = containerOf(PrimarySelectionPolicy, "destroy", listener);
    c.wl_list_remove(&policy.destroy.link);
    c.free(policy);
}

fn primarySelectionPolicy(client: ?*c.struct_wl_client) ?*PrimarySelectionPolicy {
    const listener = c.wl_client_get_destroy_listener(client, handle_primary_selection_policy_destroy);
    if (listener != null)
        return containerOf(PrimarySelectionPolicy, "destroy", listener);

    const raw = c.ecalloc(1, @sizeOf(PrimarySelectionPolicy)) orelse return null;
    const policy = @as(*PrimarySelectionPolicy, @ptrCast(@alignCast(raw)));
    policy.disable_middle_paste = c.config.disable_middle_paste != 0;
    policy.destroy.notify = handle_primary_selection_policy_destroy;
    c.wl_client_add_destroy_listener(client, &policy.destroy);
    return policy;
}

export fn acwm_global_filter(client: ?*const c.struct_wl_client, global: ?*const c.struct_wl_global, data: ?*anyopaque) callconv(.c) bool {
    _ = data;
    if (client == null or global == null)
        return true;

    const interface = c.wl_global_get_interface(global);
    if (interface == null or interface.*.name == null)
        return true;

    const name = std.mem.span(@as([*:0]const u8, @ptrCast(interface.*.name)));
    if (std.mem.eql(u8, name, "zwp_primary_selection_device_manager_v1")) {
        const policy = primarySelectionPolicy(@constCast(client));
        return policy == null or !policy.?.disable_middle_paste;
    }
    return true;
}

export fn handle_request_set_selection(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as(*c.struct_wlr_seat_request_set_selection_event, @ptrCast(@alignCast(data.?)));
    c.wlr_seat_set_selection(c.server.seat, event.source, event.serial);
}

export fn acwm_current_tagmask() callconv(.c) u32 {
    return c.server.tagmask;
}

export fn handle_drm_lease_request(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const req = @as(*c.struct_wlr_drm_lease_request_v1, @ptrCast(@alignCast(data.?)));
    const lease = c.wlr_drm_lease_request_v1_grant(req);
    if (lease == null)
        c.wlr_drm_lease_request_v1_reject(req);
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/misc_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_list_insert_calls: c_int;
extern var stub_list_remove_calls: c_int;
extern var stub_last_listener: [*c]c.struct_wl_listener;
extern var stub_client_listener: [*c]c.struct_wl_listener;
extern var stub_added_destroy_listener: [*c]c.struct_wl_listener;
extern var stub_emit_calls: c_int;
extern var stub_region_empty: c_int;
extern var stub_scene_node_at: [*c]c.struct_wlr_scene_node;
extern var stub_scene_data: [*c]AcwmSceneNode;
extern var stub_monitor_at: [*c]Monitor;
extern var stub_client_focus_calls: c_int;
extern var stub_last_focus: [*c]Client;
extern var stub_last_lift: i32;
extern var stub_top_client: [*c]Client;
extern var stub_client_notify_calls: c_int;
extern var stub_notify_surface: [*c]c.struct_wlr_surface;
extern var stub_client_surface: [*c]c.struct_wlr_surface;
extern var stub_toplevel_client: [*c]Client;
extern var stub_reset_exclusive_calls: c_int;
extern var stub_pointer_motion_calls: c_int;
extern var stub_arrange_calls: c_int;
extern var stub_bar_update_lock_calls: c_int;
extern var stub_rearm_calls: c_int;
extern var stub_set_inhibited_calls: c_int;
extern var stub_last_inhibited: bool;
extern var stub_root_surface: [*c]c.struct_wlr_surface;
extern var stub_scene_enable_calls: c_int;
extern var stub_scene_position_calls: c_int;
extern var stub_scene_destroy_calls: c_int;
extern var stub_scene_enabled_value: c_int;
extern var stub_scene_x: i32;
extern var stub_scene_y: i32;
extern var stub_subtree_result: [*c]c.struct_wlr_scene_tree;
extern var stub_tree_create_result: [*c]c.struct_wlr_scene_tree;
extern var stub_scene_buffer: [*c]c.struct_wlr_scene_buffer;
extern var stub_scene_surface: [*c]c.struct_wlr_scene_surface;
extern var stub_locked_sent: c_int;
extern var stub_lock_destroyed: c_int;
extern var stub_configure_calls: c_int;
extern var stub_configure_w: u32;
extern var stub_configure_h: u32;
extern var stub_clear_focus_calls: c_int;
extern var stub_keyboard: c.struct_wlr_keyboard;
extern var stub_focused_surface: [*c]c.struct_wlr_surface;
extern var stub_set_mode_calls: c_int;
extern var stub_last_mode: c_int;
extern var stub_grant_calls: c_int;
extern var stub_reject_calls: c_int;
extern var stub_lease_result: [*c]c.struct_wlr_drm_lease_v1;
extern var stub_capture_create_calls: c_int;
extern var stub_accept_calls: c_int;
extern var stub_capture_source_result: [*c]c.struct_wlr_ext_image_capture_source_v1;
extern var stub_last_accept_source: [*c]c.struct_wlr_ext_image_capture_source_v1;
extern var stub_capture_output: [*c]c.struct_wlr_output;
extern var stub_format_entries: [8]c.struct_wlr_drm_format;
extern var stub_texture_formats: c.struct_wlr_drm_format_set;
extern var stub_texture_formats_valid: c_int;
extern var stub_primary_set_calls: c_int;
extern var stub_primary_source: [*c]c.struct_wlr_primary_selection_source;
extern var stub_primary_serial: u32;
extern var stub_selection_calls: c_int;
extern var stub_selection_source: [*c]c.struct_wlr_data_source;
extern var stub_selection_serial: u32;
extern var stub_next_serial: u32;
extern var stub_global_interface_result: [*c]const c.struct_wl_interface;

fn listInit(head: *c.struct_wl_list) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

fn resetMiscWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    listInit(&c.server.clients);
    listInit(&c.server.monitors);
    stub_list_insert_calls = 0;
    stub_list_remove_calls = 0;
    stub_last_listener = null;
    stub_client_listener = null;
    stub_added_destroy_listener = null;
    stub_emit_calls = 0;
    stub_region_empty = 0;
    stub_scene_node_at = null;
    stub_scene_data = null;
    stub_monitor_at = null;
    stub_client_focus_calls = 0;
    stub_last_focus = null;
    stub_last_lift = -1;
    stub_top_client = null;
    stub_client_notify_calls = 0;
    stub_notify_surface = null;
    stub_client_surface = null;
    stub_toplevel_client = null;
    stub_reset_exclusive_calls = 0;
    stub_pointer_motion_calls = 0;
    stub_arrange_calls = 0;
    stub_bar_update_lock_calls = 0;
    stub_rearm_calls = 0;
    stub_set_inhibited_calls = 0;
    stub_last_inhibited = false;
    stub_root_surface = null;
    stub_scene_enable_calls = 0;
    stub_scene_position_calls = 0;
    stub_scene_destroy_calls = 0;
    stub_scene_enabled_value = -1;
    stub_scene_x = 0;
    stub_scene_y = 0;
    stub_subtree_result = null;
    stub_tree_create_result = null;
    stub_scene_buffer = null;
    stub_scene_surface = null;
    stub_locked_sent = 0;
    stub_lock_destroyed = 0;
    stub_configure_calls = 0;
    stub_configure_w = 0;
    stub_configure_h = 0;
    stub_clear_focus_calls = 0;
    stub_focused_surface = null;
    stub_set_mode_calls = 0;
    stub_last_mode = -1;
    stub_grant_calls = 0;
    stub_reject_calls = 0;
    stub_lease_result = null;
    stub_capture_create_calls = 0;
    stub_accept_calls = 0;
    stub_capture_source_result = null;
    stub_last_accept_source = null;
    stub_capture_output = null;
    stub_texture_formats_valid = 0;
    stub_primary_set_calls = 0;
    stub_primary_source = null;
    stub_primary_serial = 0;
    stub_selection_calls = 0;
    stub_selection_source = null;
    stub_selection_serial = 0;
    stub_next_serial = 42;
    stub_global_interface_result = null;
}

fn box(x: i32, y: i32, w: i32, h: i32) c.struct_wlr_box {
    return .{ .x = x, .y = y, .width = w, .height = h };
}

fn cstr(buf: []u8) []const u8 {
    return std.mem.sliceTo(buf, 0);
}

fn view(cl: *Client, m: *Monitor) void {
    cl.mon = @ptrCast(m);
    cl.tags = 1;
    m.tagset[0] = 1;
    m.seltags = 0;
    cl.animation.current = box(0, 0, 100, 100);
}

test "parent process and layout abbreviations" {
    resetMiscWorld();
    const pid = c.getpid();
    try testing.expectEqual(c.getppid(), get_parent_process(pid));
    try testing.expectEqual(@as(c.pid_t, 0), get_parent_process(-1));
    try testing.expectEqual(c.getppid(), is_descendant_process(c.getppid(), pid));
    try testing.expectEqual(pid, is_descendant_process(pid, pid));
    try testing.expectEqual(@as(c.pid_t, 0), is_descendant_process(pid, 0));

    var buf: [16]u8 = undefined;
    get_layout_abbr(&buf, "English (US)");
    try testing.expectEqualStrings("us", cstr(&buf));
    get_layout_abbr(&buf, "BÉPO (French ergonomic)");
    try testing.expectEqualStrings("bepo", cstr(&buf));
    get_layout_abbr(&buf, "Custom (ABC)");
    try testing.expectEqualStrings("abc", cstr(&buf));
    get_layout_abbr(&buf, "Mango");
    try testing.expectEqualStrings("man", cstr(&buf));
    get_layout_abbr(&buf, "X");
    try testing.expectEqualStrings("x", cstr(&buf));
    get_layout_abbr(&buf, "7a");
    try testing.expectEqualStrings("aa", cstr(&buf));
    get_layout_abbr(&buf, "");
    try testing.expectEqualStrings("xx", cstr(&buf));
    get_layout_abbr(&buf, "English (US)");
    try testing.expectEqualStrings("us", cstr(&buf));
}

test "client_at_point and layer focus rules" {
    resetMiscWorld();
    var m: Monitor = std.mem.zeroes(Monitor);
    m.tagset[0] = 1;
    m.seltags = 0;
    var a: Client = std.mem.zeroes(Client);
    var b: Client = std.mem.zeroes(Client);
    view(&a, &m);
    view(&b, &m);
    b.animation.current = box(200, 200, 50, 50);
    listInsert(&c.server.clients, &a.link);
    listInsert(&c.server.clients, &b.link);

    try testing.expect(client_at_point(10, 10) == &a);
    try testing.expect(client_at_point(250, 250) == &b);
    try testing.expect(client_at_point(500, 500) == null);

    a.isminimized = 1;
    try testing.expect(client_at_point(10, 10) == null);
    a.isminimized = 0;
    a.tags = 2;
    try testing.expect(client_at_point(10, 10) == null);
    a.tags = 1;

    var surf: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    var ls: c.struct_wlr_layer_surface_v1 = std.mem.zeroes(c.struct_wlr_layer_surface_v1);
    var l: LayerSurface = std.mem.zeroes(LayerSurface);
    try testing.expect(layer_ignores_focus(null));
    try testing.expect(layer_ignores_focus(&l));
    l.layer_surface = &ls;
    try testing.expect(layer_ignores_focus(&l));
    ls.surface = &surf;
    stub_region_empty = 1;
    try testing.expect(layer_ignores_focus(&l));
    stub_region_empty = 0;
    ls.current.keyboard_interactive = 1;
    try testing.expect(!layer_ignores_focus(&l));
    ls.current.keyboard_interactive = 0;
    try testing.expect(layer_ignores_focus(&l));
}

test "node_at_point resolves clients, bars, layers and overview" {
    resetMiscWorld();
    var wrap: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var i: usize = 0;
    while (i < c.NUM_LAYERS) : (i += 1)
        c.server.layers_wrap[i] = &wrap;

    var node: c.struct_wlr_scene_node = std.mem.zeroes(c.struct_wlr_scene_node);
    node.type = @intCast(c.WLR_SCENE_NODE_BUFFER);
    var data: AcwmSceneNode = std.mem.zeroes(AcwmSceneNode);
    data.type = @intCast(c.XDGShell);
    var cl: Client = std.mem.zeroes(Client);
    cl.type = c.XDGShell;
    data.owner = @ptrCast(&cl);
    var surf: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    var sb: c.struct_wlr_scene_buffer = std.mem.zeroes(c.struct_wlr_scene_buffer);
    var ss: c.struct_wlr_scene_surface = std.mem.zeroes(c.struct_wlr_scene_surface);
    ss.surface = &surf;
    stub_scene_node_at = &node;
    stub_scene_data = &data;
    stub_scene_buffer = &sb;
    stub_scene_surface = &ss;

    var out_surface: [*c]c.struct_wlr_surface = null;
    var out_client: [*c]Client = null;
    var out_layer: [*c]LayerSurface = null;
    var out_bar: [*c]c.AcwmBarDecoration = null;
    node_at_point(1, 2, &out_surface, &out_client, &out_layer, &out_bar, null, null);
    try testing.expect(out_client == @as([*c]Client, @ptrCast(&cl)));
    try testing.expect(out_surface == &surf);
    try testing.expect(out_layer == null);
    try testing.expect(out_bar == null);

    var bar: c.AcwmBarDecoration = std.mem.zeroes(c.AcwmBarDecoration);
    data.type = @intCast(c.GroupBar);
    data.owner = @ptrCast(&bar);
    node_at_point(1, 2, &out_surface, &out_client, &out_layer, &out_bar, null, null);
    try testing.expect(out_bar == @as([*c]c.AcwmBarDecoration, @ptrCast(&bar)));
    try testing.expect(out_client == null);

    var layer: LayerSurface = std.mem.zeroes(LayerSurface);
    layer.type = @intCast(c.LayerShell);
    var ls: c.struct_wlr_layer_surface_v1 = std.mem.zeroes(c.struct_wlr_layer_surface_v1);
    ls.surface = &surf;
    layer.layer_surface = &ls;
    data.type = @intCast(c.LayerShell);
    data.owner = @ptrCast(&layer);
    node.type = @intCast(c.WLR_SCENE_NODE_RECT);
    node_at_point(1, 2, &out_surface, &out_client, &out_layer, &out_bar, null, null);
    try testing.expect(out_layer == @as([*c]LayerSurface, @ptrCast(&layer)));
    try testing.expect(out_surface == &surf);

    var rect: c.struct_wlr_scene_rect = std.mem.zeroes(c.struct_wlr_scene_rect);
    rect.node.enabled = true;
    var m: Monitor = std.mem.zeroes(Monitor);
    m.special_dim_rect = &rect;
    stub_monitor_at = &m;
    stub_scene_node_at = &rect.node;
    node_at_point(1, 2, &out_surface, &out_client, &out_layer, &out_bar, null, null);
    try testing.expect(out_surface == null);
    try testing.expect(out_client == null);
    try testing.expect(out_layer == null);
    try testing.expect(out_bar == null);

    resetMiscWorld();
    var m2: Monitor = std.mem.zeroes(Monitor);
    m2.tagset[0] = 1;
    m2.seltags = 0;
    var ov: Client = std.mem.zeroes(Client);
    view(&ov, &m2);
    ov.animation.current = box(0, 0, 100, 100);
    listInsert(&c.server.clients, &ov.link);
    c.server.selected_monitor = &m2;
    m2.isoverview = 1;
    stub_client_surface = &surf;
    node_at_point(10, 10, &out_surface, &out_client, &out_layer, &out_bar, null, null);
    try testing.expect(out_client == @as([*c]Client, @ptrCast(&ov)));
    try testing.expect(out_surface == &surf);
    try testing.expect(out_layer == null);
    try testing.expect(out_bar == null);
}

test "idle inhibitors respect visibility and exclusions" {
    resetMiscWorld();
    var manager: c.struct_wlr_idle_inhibit_manager_v1 = std.mem.zeroes(c.struct_wlr_idle_inhibit_manager_v1);
    listInit(&manager.inhibitors);
    c.server.idle_inhibit_manager = &manager;
    c.server.idle_notifier = @ptrFromInt(0x1000);

    var surf: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    var tree: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    tree.node.enabled = true;
    surf.data = @ptrCast(&tree);
    var inhibitor: c.struct_wlr_idle_inhibitor_v1 = std.mem.zeroes(c.struct_wlr_idle_inhibitor_v1);
    inhibitor.surface = &surf;
    listInsert(&manager.inhibitors, &inhibitor.link);

    var cl: Client = std.mem.zeroes(Client);
    stub_toplevel_client = &cl;

    check_idle_inhibitor(null);
    try testing.expect(stub_last_inhibited);
    try testing.expect(stub_set_inhibited_calls > 0);
    try testing.expect(stub_rearm_calls > 0);

    cl.animation.tagouting = true;
    check_idle_inhibitor(null);
    try testing.expect(!stub_last_inhibited);

    tree.node.enabled = false;
    check_idle_inhibitor(null);
    try testing.expect(!stub_last_inhibited);

    c.config.idleinhibit_ignore_visible = 1;
    check_idle_inhibitor(null);
    try testing.expect(stub_last_inhibited);

    c.config.idleinhibit_ignore_visible = 0;
    cl.animation.tagouting = false;
    tree.node.enabled = true;
    check_idle_inhibitor(&surf);
    try testing.expect(!stub_last_inhibited);

    handle_new_idle_inhibitor(null, &inhibitor);
    try testing.expect(stub_list_insert_calls > 0);
    try testing.expect(stub_last_inhibited);
}

test "xdg decoration mode negotiation" {
    resetMiscWorld();
    var cl: Client = std.mem.zeroes(Client);
    var xdg: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    var toplevel: c.struct_wlr_xdg_toplevel = std.mem.zeroes(c.struct_wlr_xdg_toplevel);
    var deco: c.struct_wlr_xdg_toplevel_decoration_v1 = std.mem.zeroes(c.struct_wlr_xdg_toplevel_decoration_v1);
    xdg.initialized = true;
    xdg.data = &cl;
    toplevel.base = &xdg;
    deco.toplevel = &toplevel;
    cl.surface.xdg = &xdg;
    cl.allow_csd = 0;
    deco.requested_mode = @intCast(1);

    handle_new_xdg_decoration(null, &deco);
    try testing.expect(cl.decoration == &deco);
    try testing.expectEqual(@as(c_int, 1), stub_set_mode_calls);
    try testing.expectEqual(c.WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE, stub_last_mode);
    try testing.expectEqual(@as(c_int, 2), stub_list_insert_calls);

    cl.allow_csd = 1;
    handle_xdg_decoration_mode_request(&cl.set_decoration_mode, &deco);
    try testing.expectEqual(@as(c_int, 2), stub_set_mode_calls);
    try testing.expectEqual(@as(c_int, 1), stub_last_mode);

    xdg.initialized = false;
    handle_xdg_decoration_mode_request(&cl.set_decoration_mode, &deco);
    try testing.expectEqual(@as(c_int, 2), stub_set_mode_calls);

    handle_xdg_decoration_destroy(&cl.destroy_decoration, null);
    try testing.expect(cl.decoration == null);
    try testing.expectEqual(@as(c_int, 2), stub_list_remove_calls);
}

test "session lock lifecycle and surface focus" {
    resetMiscWorld();
    var seat: c.struct_wlr_seat = std.mem.zeroes(c.struct_wlr_seat);
    c.server.seat = &seat;
    var block_tree: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    c.server.layers[@intCast(c.LyrBlock)] = &block_tree;
    stub_tree_create_result = &block_tree;
    var locked_bg: c.struct_wlr_scene_rect = std.mem.zeroes(c.struct_wlr_scene_rect);
    c.server.locked_bg = &locked_bg;
    var lock: c.struct_wlr_session_lock_v1 = std.mem.zeroes(c.struct_wlr_session_lock_v1);

    handle_new_session_lock(null, &lock);
    try testing.expectEqual(@as(i32, 1), c.server.session_locked);
    try testing.expect(c.server.current_lock == &lock);
    try testing.expect(locked_bg.node.enabled);
    try testing.expectEqual(@as(c_int, 1), stub_locked_sent);
    try testing.expectEqual(@as(c_int, 1), stub_client_focus_calls);
    try testing.expectEqual(@as(c_int, 1), stub_bar_update_lock_calls);
    try testing.expectEqual(@as(c_int, 3), stub_list_insert_calls);
    try testing.expect(lock.data != null);
    const wrapper: *SessionLock = @ptrCast(@alignCast(lock.data.?));

    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    var m: Monitor = std.mem.zeroes(Monitor);
    m.m = box(10, 20, 1000, 800);
    out.data = &m;
    out.enabled = true;
    listInsert(&c.server.monitors, &m.link);
    var surf: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    var ls: c.struct_wlr_session_lock_surface_v1 = std.mem.zeroes(c.struct_wlr_session_lock_surface_v1);
    ls.output = &out;
    ls.surface = &surf;
    var subtree: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    stub_subtree_result = &subtree;

    handle_session_lock_new_surface(&wrapper.new_surface, &ls);
    try testing.expect(m.lock_surface == &ls);
    try testing.expectEqual(@as(c_int, 1), stub_configure_calls);
    try testing.expectEqual(@as(u32, 1000), stub_configure_w);
    try testing.expectEqual(@as(u32, 800), stub_configure_h);
    try testing.expectEqual(@as(i32, 10), stub_scene_x);
    try testing.expectEqual(@as(i32, 20), stub_scene_y);
    try testing.expect(surf.data == @as(?*anyopaque, @ptrCast(&subtree)));
    try testing.expectEqual(@as(c_int, 1), stub_client_notify_calls);
    try testing.expect(stub_notify_surface == &surf);
    try testing.expect(session_lock_focus_missing());
    seat.keyboard_state.focused_surface = &surf;
    try testing.expect(!session_lock_focus_missing());

    handle_session_lock_surface_destroy(&m.destroy_lock_surface, null);
    try testing.expect(m.lock_surface == null);
    try testing.expectEqual(@as(c_int, 1), stub_list_remove_calls);

    handle_session_lock_unlock(&wrapper.unlock, null);
    try testing.expectEqual(@as(i32, 0), c.server.session_locked);
    try testing.expect(c.server.current_lock == null);
    try testing.expect(!locked_bg.node.enabled);
    try testing.expectEqual(@as(c_int, 2), stub_client_focus_calls);
    try testing.expectEqual(@as(i32, 1), stub_last_lift);
    try testing.expectEqual(@as(c_int, 1), stub_pointer_motion_calls);
    try testing.expectEqual(@as(c_int, 2), stub_bar_update_lock_calls);
    try testing.expectEqual(@as(c_int, 1), stub_scene_destroy_calls);
    try testing.expectEqual(@as(c_int, 4), stub_list_remove_calls);

    var lock2: c.struct_wlr_session_lock_v1 = std.mem.zeroes(c.struct_wlr_session_lock_v1);
    handle_new_session_lock(null, &lock2);
    const wrapper2: *SessionLock = @ptrCast(@alignCast(lock2.data.?));
    handle_session_lock_destroy(&wrapper2.destroy, null);
    try testing.expectEqual(@as(i32, 1), c.server.session_locked);
    try testing.expect(c.server.current_lock == null);
    try testing.expectEqual(@as(c_int, 2), stub_scene_destroy_calls);
    try testing.expectEqual(@as(c_int, 2), stub_clear_focus_calls);
    try testing.expectEqual(@as(c_int, 3), stub_client_focus_calls);
}

test "capture requests and BGR shm formats" {
    resetMiscWorld();
    var client: Client = std.mem.zeroes(Client);
    var scene: c.struct_wlr_scene = std.mem.zeroes(c.struct_wlr_scene);
    client.image_capture_scene = &scene;
    var handle: c.struct_wlr_ext_foreign_toplevel_handle_v1 = std.mem.zeroes(c.struct_wlr_ext_foreign_toplevel_handle_v1);
    handle.data = &client;
    var request: c.struct_wlr_ext_foreign_toplevel_image_capture_source_manager_v1_request = std.mem.zeroes(c.struct_wlr_ext_foreign_toplevel_image_capture_source_manager_v1_request);
    request.toplevel_handle = &handle;
    var source: c.struct_wlr_ext_image_capture_source_v1 = std.mem.zeroes(c.struct_wlr_ext_image_capture_source_v1);
    stub_capture_source_result = &source;

    handle_new_foreign_toplevel_capture_request(null, &request);
    try testing.expectEqual(@as(c_int, 1), stub_capture_create_calls);
    try testing.expectEqual(@as(c_int, 1), stub_accept_calls);
    try testing.expect(stub_last_accept_source == &source);

    handle_new_foreign_toplevel_capture_request(null, &request);
    try testing.expectEqual(@as(c_int, 1), stub_capture_create_calls);
    try testing.expectEqual(@as(c_int, 2), stub_accept_calls);

    client.shield_when_capture = 1;
    handle_new_foreign_toplevel_capture_request(null, &request);
    try testing.expectEqual(@as(c_int, 2), stub_accept_calls);
    client.shield_when_capture = 0;

    var m: Monitor = std.mem.zeroes(Monitor);
    m.tagset[0] = 1;
    m.seltags = 0;
    var shielded: Client = std.mem.zeroes(Client);
    view(&shielded, &m);
    shielded.shield_when_capture = 1;
    listInsert(&c.server.clients, &shielded.link);

    stub_format_entries[0].format = c.DRM_FORMAT_XRGB8888;
    stub_format_entries[1].format = c.DRM_FORMAT_ARGB8888;
    stub_texture_formats.len = 2;
    stub_texture_formats.formats = &stub_format_entries;
    stub_texture_formats_valid = 1;
    c.server.renderer = @ptrFromInt(0x2000);

    var session: c.struct_wlr_ext_image_copy_capture_session_v1 = std.mem.zeroes(c.struct_wlr_ext_image_copy_capture_session_v1);
    session.source = &source;
    handle_ext_image_copy_capture_new_session(null, &session);
    try testing.expectEqual(@as(usize, 2), source.shm_formats_len);
    try testing.expectEqual(c.DRM_FORMAT_XRGB8888, source.shm_formats[0]);
    try testing.expectEqual(c.DRM_FORMAT_ARGB8888, source.shm_formats[1]);
    try testing.expectEqual(@as(c_int, 1), stub_emit_calls);
    try testing.expectEqual(@as(c_int, 1), c.server.active_capture_count);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);
    try testing.expect(stub_last_listener != null);

    const notify = stub_last_listener.*.notify.?;
    notify(stub_last_listener, null);
    try testing.expectEqual(@as(c_int, 0), c.server.active_capture_count);
    try testing.expectEqual(@as(c_int, 2), stub_arrange_calls);
    try testing.expectEqual(@as(c_int, 1), stub_list_remove_calls);

    stub_texture_formats_valid = 0;
    var source2: c.struct_wlr_ext_image_capture_source_v1 = std.mem.zeroes(c.struct_wlr_ext_image_capture_source_v1);
    var session2: c.struct_wlr_ext_image_copy_capture_session_v1 = std.mem.zeroes(c.struct_wlr_ext_image_copy_capture_session_v1);
    session2.source = &source2;
    handle_ext_image_copy_capture_new_session(null, &session2);
    try testing.expectEqual(@as(usize, 0), source2.shm_formats_len);
    try testing.expectEqual(@as(c_int, 1), stub_emit_calls);
}

test "primary selection policy, events and tagmask" {
    resetMiscWorld();
    var seat: c.struct_wlr_seat = std.mem.zeroes(c.struct_wlr_seat);
    c.server.seat = &seat;
    var event: c.struct_wlr_seat_request_set_primary_selection_event = std.mem.zeroes(c.struct_wlr_seat_request_set_primary_selection_event);
    event.source = @ptrFromInt(0x3000);
    event.serial = 7;

    c.config.disable_middle_paste = 1;
    handle_request_set_primary_selection(null, &event);
    try testing.expectEqual(@as(c_int, 0), stub_primary_set_calls);

    c.config.disable_middle_paste = 0;
    handle_request_set_primary_selection(null, &event);
    try testing.expectEqual(@as(c_int, 1), stub_primary_set_calls);
    try testing.expectEqual(@as(u32, 7), stub_primary_serial);

    seat.primary_selection_source = @ptrFromInt(0x3000);
    c.server.display = @ptrFromInt(0x4000);
    c.config.disable_middle_paste = 1;
    apply_primary_selection();
    try testing.expectEqual(@as(c_int, 2), stub_primary_set_calls);
    try testing.expect(stub_primary_source == null);
    try testing.expectEqual(@as(u32, 42), stub_primary_serial);

    var iface: c.struct_wl_interface = std.mem.zeroes(c.struct_wl_interface);
    iface.name = "zwp_primary_selection_device_manager_v1";
    stub_global_interface_result = &iface;
    const fake_client: *c.struct_wl_client = @ptrFromInt(0x5000);
    const fake_global: *c.struct_wl_global = @ptrFromInt(0x6000);
    try testing.expect(!acwm_global_filter(fake_client, fake_global, null));
    try testing.expect(stub_added_destroy_listener != null);
    const first_listener = stub_added_destroy_listener;
    stub_client_listener = first_listener;
    try testing.expect(!acwm_global_filter(fake_client, fake_global, null));
    try testing.expect(stub_added_destroy_listener == first_listener);

    // an existing policy keeps the config value captured at creation time
    c.config.disable_middle_paste = 0;
    try testing.expect(!acwm_global_filter(fake_client, fake_global, null));

    stub_client_listener = null;
    const fresh_client: *c.struct_wl_client = @ptrFromInt(0x5100);
    try testing.expect(acwm_global_filter(fresh_client, fake_global, null));

    iface.name = "wl_compositor";
    try testing.expect(acwm_global_filter(fake_client, fake_global, null));

    var selection: c.struct_wlr_seat_request_set_selection_event = std.mem.zeroes(c.struct_wlr_seat_request_set_selection_event);
    selection.source = @ptrFromInt(0x6000);
    selection.serial = 9;
    handle_request_set_selection(null, &selection);
    try testing.expectEqual(@as(c_int, 1), stub_selection_calls);
    try testing.expectEqual(@as(u32, 9), stub_selection_serial);

    c.server.tagmask = 0xabc;
    try testing.expectEqual(@as(u32, 0xabc), acwm_current_tagmask());
}

test "drm lease rejection and selection" {
    resetMiscWorld();
    var req: c.struct_wlr_drm_lease_request_v1 = std.mem.zeroes(c.struct_wlr_drm_lease_request_v1);
    handle_drm_lease_request(null, &req);
    try testing.expectEqual(@as(c_int, 1), stub_grant_calls);
    try testing.expectEqual(@as(c_int, 1), stub_reject_calls);

    var lease: c.struct_wlr_drm_lease_v1 = std.mem.zeroes(c.struct_wlr_drm_lease_v1);
    stub_lease_result = &lease;
    handle_drm_lease_request(null, &req);
    try testing.expectEqual(@as(c_int, 2), stub_grant_calls);
    try testing.expectEqual(@as(c_int, 1), stub_reject_calls);
}
