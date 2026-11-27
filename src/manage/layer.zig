//! Port of src/manage/layer.c (Phase 5, manage slice 4, slice 52).
//! Layer-shell surface lifecycle, focus/exclusive handling, arrangement,
//! blur/shadow/shield setup, popup lifecycle and layer rules.

const std = @import("std");
const c = @import("cc");

const Client = c.Client;
const Monitor = c.Monitor;
const LayerSurface = c.LayerSurface;
const Popup = c.Popup;
const Box = c.struct_wlr_box;

extern fn arrange(m: [*c]Monitor, want_animation: bool, from_view: bool) callconv(.c) void;
extern fn client_focus(cl: ?*Client, lift: i32) callconv(.c) void;
extern fn client_focus_top(m: [*c]Monitor) callconv(.c) [*c]Client;
extern fn client_notify_enter(s: [*c]c.struct_wlr_surface, kb: [*c]c.struct_wlr_keyboard) callconv(.c) void;
extern fn client_set_scale(s: [*c]c.struct_wlr_surface, scale: f32) callconv(.c) void;
extern fn toplevel_from_wlr_surface(s: [*c]c.struct_wlr_surface, pc: [*c][*c]Client, pl: [*c][*c]LayerSurface) callconv(.c) i32;
extern fn pointer_process_motion(time: u32, device: [*c]c.struct_wlr_input_device, dx: f64, dy: f64, dx_unaccel: f64, dy_unaccel: f64) callconv(.c) void;
extern fn acwm_im_relay_set_focus(relay: ?*anyopaque, surface: [*c]c.struct_wlr_surface) callconv(.c) void;
extern fn bar_strip_height() callconv(.c) i32;
extern fn bar_monitor_layout(m: [*c]Monitor) callconv(.c) void;
extern fn printstatus(t: c.enum_ipc_watch_type) callconv(.c) void;
extern fn regex_match(pattern_mb: [*c]const u8, str_mb: [*c]const u8) callconv(.c) i32;
extern fn blur_layer_on_wallpaper(layer: u32) callconv(.c) bool;
extern fn init_fadeout_layers(l: *LayerSurface) callconv(.c) void;
extern fn layer_set_pending_state(l: *LayerSurface) callconv(.c) void;
extern fn get_layer_target_geometry(l: *LayerSurface, box: *Box) callconv(.c) void;

fn containerOf(comptime T: type, comptime field: []const u8, link: anytype) *T {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(T, field));
}

fn monitorOpt(p: [*c]Monitor) ?*Monitor {
    return if (p == null) null else @ptrCast(p);
}

fn surfaceOf(l: *LayerSurface) [*c]c.struct_wlr_surface {
    return l.layer_surface.*.surface;
}

fn layerKind(l: *const LayerSurface) c_int {
    return @intCast(l.layer_surface.*.current.layer);
}

fn isBottomLayer(kind: c_int) bool {
    return kind == c.ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM or kind == c.ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND;
}

fn configAnimations(l: *const LayerSurface) bool {
    return c.config.animations != 0 and c.config.layer_animations != 0 and l.no_animation == 0;
}

fn snapGeometry(l: *LayerSurface) void {
    l.animainit_geom = l.geom;
    l.animation.current = l.geom;
    l.current = l.geom;
    l.pending = l.geom;
}

const layermap = [4]c_int{ c.LyrBg, c.LyrBottom, c.LyrTop, c.LyrSpecialOverlay };

fn layerScene(l: *const LayerSurface) [*c]c.struct_wlr_scene_tree {
    return c.server.layers[@intCast(layermap[@intCast(layerKind(l))])];
}

export fn arrange_layer(m: *Monitor, list: *c.struct_wl_list, usable_area: *Box, exclusive: i32, full_area: *Box) callconv(.c) void {
    _ = m;
    const head: [*c]c.struct_wl_list = @ptrCast(list);
    var pos = list.next;
    while (pos != head) : (pos = pos.*.next) {
        const l = containerOf(LayerSurface, "link", pos);
        const layer_surface = l.layer_surface;

        if (exclusive != @as(i32, @intFromBool(layer_surface.*.current.exclusive_zone > 0)) or
            !layer_surface.*.initialized)
            continue;
        if (l.being_unmapped or l.scene_layer == null or l.scene == null or l.popups == null)
            continue;

        _ = c.wlr_scene_layer_surface_v1_configure(l.scene_layer, full_area, usable_area);
        c.wlr_scene_node_set_position(&l.popups.*.node, l.scene.*.node.x, l.scene.*.node.y);
    }
}

export fn layer_focus(l: *LayerSurface) callconv(.c) void {
    if (c.server.session_locked != 0)
        return;

    client_focus(null, 0);
    acwm_im_relay_set_focus(c.server.input_method_relay, surfaceOf(l));
    client_notify_enter(surfaceOf(l), c.wlr_seat_get_keyboard(c.server.seat));
}

export fn reset_exclusive_layers_focus(m_in: [*c]Monitor) callconv(.c) void {
    const m = monitorOpt(m_in) orelse return;
    var need_change = false;
    const layers_above_shell = [3]c_int{
        c.ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY,
        c.ZWLR_LAYER_SHELL_V1_LAYER_TOP,
        c.ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM,
    };

    for (layers_above_shell) |kind| {
        const head: [*c]c.struct_wl_list = @ptrCast(&m.layers[@intCast(kind)]);
        var pos = m.layers[@intCast(kind)].next;
        while (pos != head) : (pos = pos.*.next) {
            const l = containerOf(LayerSurface, "link", pos);
            const surface = surfaceOf(l);
            const focused = if (c.server.seat != null) c.server.seat.*.keyboard_state.focused_surface else null;

            if (c.server.exclusive_focus != null and
                @intFromPtr(l) == @intFromPtr(c.server.exclusive_focus.?))
            {
                const kbd = l.layer_surface.*.current.keyboard_interactive;
                if (@as(c_int, @intCast(kbd)) != c.ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_EXCLUSIVE) {
                    c.server.exclusive_focus = null;
                    need_change = true;
                }
            }

            if (surface == focused and l.being_unmapped)
                need_change = true;

            if (@as(c_int, @intCast(l.layer_surface.*.current.keyboard_interactive)) == c.ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE and
                surface == focused)
                need_change = true;

            if (c.server.session_locked != 0 or
                @as(c_int, @intCast(l.layer_surface.*.current.keyboard_interactive)) != c.ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_EXCLUSIVE or
                l.being_unmapped)
                continue;

            c.server.exclusive_focus = @ptrCast(l);
            need_change = false;
            if (surface != focused)
                layer_focus(l);
            return;
        }
    }

    if (need_change)
        client_focus(client_focus_top(c.server.selected_monitor), 1);
}

export fn arrange_layers(m: *Monitor) callconv(.c) void {
    var usable_area = m.m;
    var full_area = m.m;

    if (m.wlr_output == null or !m.wlr_output.*.enabled)
        return;
    if (m.iscleanuping)
        return;

    const bar_strip = bar_strip_height();
    if (bar_strip > 0 and bar_strip < usable_area.height) {
        usable_area.y += bar_strip;
        usable_area.height -= bar_strip;
        full_area.y += bar_strip;
        full_area.height -= bar_strip;
    }
    bar_monitor_layout(m);

    var i: i32 = 3;
    while (i >= 0) : (i -= 1)
        arrange_layer(m, &m.layers[@intCast(i)], &usable_area, 1, &full_area);

    i = 3;
    while (i >= 0) : (i -= 1) {
        const head: [*c]c.struct_wl_list = @ptrCast(&m.layers[@intCast(i)]);
        var pos = m.layers[@intCast(i)].next;
        while (pos != head) : (pos = pos.*.next) {
            const l = containerOf(LayerSurface, "link", pos);
            if (l.mapped == 0 or l.being_unmapped)
                continue;
            if (l.layer_surface.*.current.exclusive_zone <= 0)
                continue;
            var b = l.geom;
            get_layer_target_geometry(l, &b);
            if (!c.wlr_box_equal(&b, &l.geom)) {
                l.geom = b;
                l.animainit_geom = b;
                l.animation.current = b;
                l.current = b;
                l.pending = b;
                l.animation.initial = b;
                l.need_output_flush = true;
                c.wlr_scene_node_set_position(&l.scene.*.node, b.x, b.y);
            }
        }
    }

    if (!c.wlr_box_equal(&usable_area, &m.w)) {
        m.w = usable_area;
        arrange(m, false, false);
    }

    i = 3;
    while (i >= 0) : (i -= 1)
        arrange_layer(m, &m.layers[@intCast(i)], &usable_area, 0, &full_area);
}

export fn iter_layer_scene_buffers(buffer: [*c]c.struct_wlr_scene_buffer, sx: i32, sy: i32, user_data: ?*anyopaque) callconv(.c) void {
    _ = sx;
    _ = sy;
    const scene_surface = c.wlr_scene_surface_try_from_buffer(buffer);
    if (scene_surface == null)
        return;

    const l = @as(*LayerSurface, @ptrCast(@alignCast(user_data.?)));
    c.wlr_scene_node_set_enabled(&l.blur.*.node, true);
    c.wlr_scene_blur_set_transparency_mask_source(l.blur, buffer);
    c.wlr_scene_blur_set_size(l.blur, l.geom.width, l.geom.height);
    c.wlr_scene_blur_set_should_only_blur_bottom_layer(l.blur, layer_blur_uses_wallpaper(l));
}

export fn layer_blur_uses_wallpaper(l_in: ?*LayerSurface) callconv(.c) bool {
    const l = l_in orelse return false;
    if (l.layer_surface == null)
        return false;
    return c.config.blur_optimized != 0 or
        blur_layer_on_wallpaper(@intCast(layermap[@intCast(layerKind(l))]));
}

export fn layer_flush_blur_background(l: *LayerSurface) callconv(.c) void {
    if (c.config.blur == 0)
        return;

    if (layerKind(l) == c.ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND) {
        if (l.mon != null and l.mon.*.blur != null)
            c.wlr_scene_optimized_blur_mark_dirty(l.mon.*.blur);
    }
}

export fn handle_layer_surface_map(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const l = containerOf(LayerSurface, "map", listener);
    const layer_surface = l.layer_surface;

    l.mapped = 1;
    if (l.mon == null)
        return;

    const namespace = if (layer_surface.*.namespace != null)
        std.mem.span(@as([*:0]const u8, @ptrCast(layer_surface.*.namespace)))
    else
        "";

    @memset(&l.mon.*.last_open_surface, 0);
    const copy_len = @min(namespace.len, l.mon.*.last_open_surface.len - 1);
    std.mem.copyForwards(u8, l.mon.*.last_open_surface[0..copy_len], namespace[0..copy_len]);

    get_layer_target_geometry(l, &l.geom);

    l.no_animation = 0;
    l.dirty = false;
    l.shield_when_capture = false;
    l.no_blur = 0;
    l.shadow = null;
    l.need_output_flush = true;
    l.animation_type_open = c.ANIM_TYPE_UNSET;
    l.animation_type_close = c.ANIM_TYPE_UNSET;

    var ji: i32 = 0;
    while (ji < c.config.layer_rules_count) : (ji += 1) {
        const idx: usize = @intCast(ji);
        const rule = &c.config.layer_rules[idx];
        if (regex_match(rule.layer_name, layer_surface.*.namespace) == 0)
            continue;
        if (rule.shield_when_capture >= 0) l.shield_when_capture = rule.shield_when_capture != 0;
        if (rule.no_blur >= 0) l.no_blur = rule.no_blur;
        if (rule.no_animation >= 0) l.no_animation = rule.no_animation;
        if (rule.no_shadow >= 0) l.no_shadow = rule.no_shadow;
        if (rule.animation_type_open >= 0) l.animation_type_open = rule.animation_type_open;
        if (rule.animation_type_close >= 0) l.animation_type_close = rule.animation_type_close;
    }

    const color = [4]f32{ 0, 0, 0, 255 };
    l.shield = c.wlr_scene_rect_create(l.scene, 0, 0, &color);
    if (l.shield != null) {
        c.wlr_scene_node_lower_to_bottom(&l.shield.*.node);
        c.wlr_scene_node_set_enabled(&l.shield.*.node, false);
    }

    const kind = layerKind(l);
    if (!isBottomLayer(kind)) {
        if (layer_surface.*.current.exclusive_zone == 0) {
            l.shadow = c.wlr_scene_shadow_create(l.scene, 0, 0, c.config.border_radius, c.config.shadows_blur, &c.config.shadowscolor);
            if (l.shadow != null) {
                c.wlr_scene_node_lower_to_bottom(&l.shadow.*.node);
                c.wlr_scene_node_set_enabled(&l.shadow.*.node, true);
            }
        }

        l.blur = c.wlr_scene_blur_create(l.scene, 0, 0);
        if (l.blur != null)
            c.wlr_scene_node_lower_to_bottom(&l.blur.*.node);
    }

    if (configAnimations(l)) {
        l.animation.duration = c.config.animation_duration_open;
        l.animation.action = c.OPEN;
        layer_set_pending_state(l);
    } else {
        snapGeometry(l);
    }

    arrange_layers(@ptrCast(l.mon));
    reset_exclusive_layers_focus(l.mon);
    printstatus(@intCast(c.IPC_WATCH_LAST_OPEN_SURFACE));
}

export fn handle_layer_surface_commit(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const l = containerOf(LayerSurface, "surface_commit", listener);
    const layer_surface = l.layer_surface;
    const scene_layer = layerScene(l);
    var box = l.geom;

    if (layer_surface.*.initial_commit) {
        if (l.mon == null or l.mon.*.wlr_output == null)
            return;
        client_set_scale(layer_surface.*.surface, l.mon.*.wlr_output.*.scale);

        const old_state = layer_surface.*.current;
        layer_surface.*.current = layer_surface.*.pending;
        arrange_layers(@ptrCast(l.mon));
        layer_surface.*.current = old_state;

        if (c.server.exclusive_focus == null and
            @as(c_int, @intCast(layer_surface.*.current.keyboard_interactive)) == c.ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_ON_DEMAND)
            layer_focus(l);
        return;
    }

    if (l.mapped != 0 and layer_surface.*.surface.*.buffer == null) {
        c.wlr_scene_node_set_enabled(&l.scene.*.node, false);
        return;
    } else {
        c.wlr_scene_node_set_enabled(&l.scene.*.node, true);
    }

    get_layer_target_geometry(l, &box);

    if (!c.wlr_box_equal(&box, &l.geom)) {
        l.geom = box;

        if (configAnimations(l) and l.mapped != 0 and !isBottomLayer(layerKind(l))) {
            l.animation.action = c.MOVE;
            l.animation.duration = c.config.animation_duration_move;
            l.need_output_flush = true;
            layer_set_pending_state(l);
        } else {
            snapGeometry(l);
            l.need_output_flush = true;
        }
    }

    if (c.config.blur != 0 and c.config.blur_layer != 0) {
        if (l.no_blur == 0 and !isBottomLayer(layerKind(l)) and l.blur != null)
            c.wlr_scene_node_for_each_buffer(&l.scene.*.node, iter_layer_scene_buffers, l);
    }

    layer_flush_blur_background(l);

    if (layer_surface.*.current.committed == 0 and
        l.mapped == @as(i32, @intFromBool(layer_surface.*.surface.*.mapped)))
        return;
    l.mapped = @intFromBool(layer_surface.*.surface.*.mapped);

    if ((layer_surface.*.current.committed & @as(u32, @intCast(c.WLR_LAYER_SURFACE_V1_STATE_LAYER))) != 0) {
        if (l.scene.*.node.parent != scene_layer) {
            c.wlr_scene_node_reparent(&l.scene.*.node, scene_layer);
            c.wl_list_remove(&l.link);
            c.wl_list_insert(&l.mon.*.layers[@intCast(layerKind(l))], &l.link);
            const popup_parent = if (layerKind(l) < c.ZWLR_LAYER_SHELL_V1_LAYER_TOP)
                c.server.layers[@intCast(c.LyrTop)]
            else
                scene_layer;
            c.wlr_scene_node_reparent(&l.popups.*.node, popup_parent);
        }
    }

    arrange_layers(@ptrCast(l.mon));

    if ((layer_surface.*.current.committed & @as(u32, @intCast(c.WLR_LAYER_SURFACE_V1_STATE_KEYBOARD_INTERACTIVITY))) != 0)
        reset_exclusive_layers_focus(l.mon);
}

export fn popup_unconstrain(popup: *Popup) callconv(.c) bool {
    const wlr_popup = popup.wlr_popup;
    if (wlr_popup == null or wlr_popup.*.parent == null)
        return false;

    const parent_node = wlr_popup.*.parent.*.data;
    if (parent_node == null)
        return false;

    var client_ptr: [*c]Client = null;
    var layer_ptr: [*c]LayerSurface = null;
    const kind = toplevel_from_wlr_surface(wlr_popup.*.base.*.surface, &client_ptr, &layer_ptr);
    const cl = if (client_ptr == null) null else @as(*Client, @ptrCast(client_ptr));
    const l = if (layer_ptr == null) null else @as(*LayerSurface, @ptrCast(layer_ptr));

    if ((kind == c.LayerShell and (l == null or l.?.mon == null)) or
        (kind != c.LayerShell and (cl == null or cl.?.mon == null)))
        return true;

    const usable = if (kind == c.LayerShell) l.?.mon.*.m else cl.?.mon.*.w;

    var lx: c_int = 0;
    var ly: c_int = 0;
    var constraint_box: Box = undefined;

    if (kind == c.LayerShell) {
        _ = c.wlr_scene_node_coords(&l.?.scene_layer.*.tree.*.node, &lx, &ly);
        constraint_box.x = usable.x - lx;
        constraint_box.y = usable.y - ly;
        constraint_box.width = usable.width;
        constraint_box.height = usable.height;
    } else {
        const xdg = cl.?.surface.xdg;
        constraint_box.x = usable.x - (cl.?.geom.x + @as(i32, @intCast(cl.?.bw)) - xdg.*.current.geometry.x);
        constraint_box.y = usable.y - (cl.?.geom.y + @as(i32, @intCast(cl.?.bw)) - xdg.*.current.geometry.y);
        constraint_box.width = usable.width;
        constraint_box.height = usable.height;
    }

    c.wlr_xdg_popup_unconstrain_from_box(wlr_popup, &constraint_box);
    return false;
}

export fn handle_popup_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const popup = containerOf(Popup, "destroy", listener);
    c.wl_list_remove(&popup.destroy.link);
    c.wl_list_remove(&popup.reposition.link);
    if (popup.commit.notify != null) {
        c.wl_list_remove(&popup.commit.link);
        popup.commit.notify = null;
    }
    c.free(popup);
}

export fn handle_popup_commit(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    const popup = containerOf(Popup, "commit", listener);
    const surface = @as([*c]c.struct_wlr_surface, @ptrCast(@alignCast(data.?)));
    const wlr_popup = c.wlr_xdg_popup_try_from_wlr_surface(surface);
    if (wlr_popup == null)
        return;
    if (!wlr_popup.*.base.*.initial_commit)
        return;

    var should_destroy = false;
    if (wlr_popup.*.parent == null or wlr_popup.*.parent.*.data == null) {
        should_destroy = true;
    } else {
        c.wlr_scene_node_raise_to_top(@as([*c]c.struct_wlr_scene_node, @ptrCast(@alignCast(wlr_popup.*.parent.*.data.?))));
        wlr_popup.*.base.*.surface.*.data = @ptrCast(c.wlr_scene_xdg_surface_create(@as([*c]c.struct_wlr_scene_tree, @ptrCast(@alignCast(wlr_popup.*.parent.*.data.?))), wlr_popup.*.base));
        popup.wlr_popup = wlr_popup;
        should_destroy = popup_unconstrain(popup);
    }

    c.wl_list_remove(&popup.commit.link);
    popup.commit.notify = null;

    if (should_destroy)
        c.wlr_xdg_popup_destroy(wlr_popup);
}

export fn handle_popup_reposition(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const popup = containerOf(Popup, "reposition", listener);
    _ = popup_unconstrain(popup);
}

export fn handle_new_xdg_popup(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const wlr_popup = @as(*c.struct_wlr_xdg_popup, @ptrCast(@alignCast(data.?)));

    const raw = c.calloc(1, @sizeOf(Popup)) orelse return;
    const popup = @as(*Popup, @ptrCast(@alignCast(raw)));
    popup.type = @intCast(c.XdgPopup);

    popup.destroy.notify = handle_popup_destroy;
    c.wl_signal_add(&wlr_popup.events.destroy, &popup.destroy);

    popup.commit.notify = handle_popup_commit;
    c.wl_signal_add(&wlr_popup.base.*.surface.*.events.commit, &popup.commit);

    popup.reposition.notify = handle_popup_reposition;
    c.wl_signal_add(&wlr_popup.events.reposition, &popup.reposition);
}

export fn handle_new_layer_surface(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const layer_surface = @as(*c.struct_wlr_layer_surface_v1, @ptrCast(@alignCast(data.?)));
    const surface = layer_surface.surface;
    const scene_layer = c.server.layers[@intCast(layermap[@intCast(layer_surface.pending.layer)])];

    if (layer_surface.output == null) {
        if (c.server.selected_monitor != null)
            layer_surface.output = c.server.selected_monitor.*.wlr_output;
        if (layer_surface.output == null) {
            c.wlr_layer_surface_v1_destroy(layer_surface);
            return;
        }
    }

    const raw = c.ecalloc(1, @sizeOf(LayerSurface)) orelse return;
    const l = @as(*LayerSurface, @ptrCast(@alignCast(raw)));
    layer_surface.data = @ptrCast(l);
    l.type = @intCast(c.LayerShell);
    l.animation_type_open = c.ANIM_TYPE_UNSET;
    l.animation_type_close = c.ANIM_TYPE_UNSET;

    l.map.notify = handle_layer_surface_map;
    c.wl_signal_add(&surface.*.events.map, &l.map);
    l.surface_commit.notify = handle_layer_surface_commit;
    c.wl_signal_add(&surface.*.events.commit, &l.surface_commit);
    l.unmap.notify = handle_layer_surface_unmap;
    c.wl_signal_add(&surface.*.events.unmap, &l.unmap);

    l.layer_surface = layer_surface;
    if (layer_surface.output.*.data == null)
        return;
    l.mon = @ptrCast(@alignCast(layer_surface.output.*.data.?));
    l.scene_layer = c.wlr_scene_layer_surface_v1_create(scene_layer, layer_surface);
    if (l.scene_layer == null)
        return;
    l.scene = l.scene_layer.*.tree;
    const popup_parent = if (layer_surface.current.layer < @as(c.enum_zwlr_layer_shell_v1_layer, @intCast(c.ZWLR_LAYER_SHELL_V1_LAYER_TOP)))
        c.server.layers[@intCast(c.LyrTop)]
    else
        scene_layer;
    l.popups = c.wlr_scene_tree_create(popup_parent);
    surface.*.data = @ptrCast(l.popups);
    _ = c.acwm_scene_node_set(&l.scene.*.node, @intCast(c.LayerShell), l);
    _ = c.acwm_scene_node_set(&l.popups.*.node, @intCast(c.LayerShell), l);

    l.destroy.notify = handle_layer_node_destroy;
    c.wl_signal_add(&l.scene.*.node.events.destroy, &l.destroy);

    c.wl_list_insert(&l.mon.*.layers[@intCast(layer_surface.pending.layer)], &l.link);
}

export fn handle_layer_node_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const l = containerOf(LayerSurface, "destroy", listener);

    c.wl_list_remove(&l.link);
    c.wl_list_remove(&l.destroy.link);
    c.wl_list_remove(&l.map.link);
    c.wl_list_remove(&l.unmap.link);
    c.wl_list_remove(&l.surface_commit.link);
    if (l.popups != null)
        c.wlr_scene_node_destroy(&l.popups.*.node);
    c.free(l);
}

export fn handle_layer_surface_unmap(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const l = containerOf(LayerSurface, "unmap", listener);

    l.mapped = 0;
    l.being_unmapped = true;

    init_fadeout_layers(l);
    c.wlr_scene_node_set_enabled(&l.scene.*.node, false);

    if (c.server.exclusive_focus != null and @intFromPtr(l) == @intFromPtr(c.server.exclusive_focus.?))
        c.server.exclusive_focus = null;

    if (l.layer_surface.*.output != null and l.layer_surface.*.output.*.data != null)
        l.mon = @ptrCast(@alignCast(l.layer_surface.*.output.*.data.?));
    if (l.mon != null)
        arrange_layers(@ptrCast(l.mon));
    reset_exclusive_layers_focus(l.mon);

    pointer_process_motion(0, null, 0, 0, 0, 0);
    layer_flush_blur_background(l);
    if (l.shadow != null) {
        c.wlr_scene_node_destroy(&l.shadow.*.node);
        l.shadow = null;
    }
    l.being_unmapped = false;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/manage_layer_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_list_insert_calls: c_int;
extern var stub_list_remove_calls: c_int;
extern var stub_last_listener: [*c]c.struct_wl_listener;
extern var stub_enable_calls: c_int;
extern var stub_enabled_value: c_int;
extern var stub_position_calls: c_int;
extern var stub_pos_x: i32;
extern var stub_pos_y: i32;
extern var stub_reparent_calls: c_int;
extern var stub_destroy_calls: c_int;
extern var stub_raise_calls: c_int;
extern var stub_lower_calls: c_int;
extern var stub_coords_calls: c_int;
extern var stub_coords_x: i32;
extern var stub_coords_y: i32;
extern var stub_for_each_calls: c_int;
extern var stub_scene_surface_result: [*c]c.struct_wlr_scene_surface;
extern var stub_configure_calls: c_int;
extern var stub_usable_area: Box;
extern var stub_full_area: Box;
extern var stub_scene_layer_create_calls: c_int;
extern var stub_scene_layer_next: c_int;
extern var stub_plain_tree_next: c_int;
extern var stub_xdg_tree_next: c_int;
extern var stub_rect_next: c_int;
extern var stub_shadow_next: c_int;
extern var stub_blur_next: c_int;
extern var stub_tree_create_calls: c_int;
extern var stub_xdg_surface_create_calls: c_int;
extern var stub_rect_create_calls: c_int;
extern var stub_shadow_create_calls: c_int;
extern var stub_blur_create_calls: c_int;
extern var stub_shadow_corner: c_int;
extern var stub_shadow_blur: f32;
extern var stub_mask_source_calls: c_int;
extern var stub_blur_size_calls: c_int;
extern var stub_blur_size_w: c_int;
extern var stub_blur_size_h: c_int;
extern var stub_bottom_layer_calls: c_int;
extern var stub_bottom_layer_value: bool;
extern var stub_dirty_calls: c_int;
extern var stub_popup_unconstrain_calls: c_int;
extern var stub_constraint_box: Box;
extern var stub_popup_try_result: [*c]c.struct_wlr_xdg_popup;
extern var stub_popup_destroy_calls: c_int;
extern var stub_layer_destroy_calls: c_int;
extern var stub_regex_match: c_int;
extern var stub_regex_calls: c_int;
extern var stub_bar_strip: c_int;
extern var stub_bar_layout_calls: c_int;
extern var stub_printstatus_calls: c_int;
extern var stub_client_focus_calls: c_int;
extern var stub_last_focus: [*c]Client;
extern var stub_last_lift: i32;
extern var stub_top_client: [*c]Client;
extern var stub_notify_calls: c_int;
extern var stub_notify_surface: [*c]c.struct_wlr_surface;
extern var stub_relay_calls: c_int;
extern var stub_scale_calls: c_int;
extern var stub_scale: f32;
extern var stub_pointer_calls: c_int;
extern var stub_arrange_calls: c_int;
extern var stub_blur_layer_calls: c_int;
extern var stub_blur_on_wallpaper: bool;
extern var stub_fadeout_calls: c_int;
extern var stub_pending_calls: c_int;
extern var stub_target_box: Box;
extern var stub_toplevel_kind: c_int;
extern var stub_toplevel_client: [*c]Client;
extern var stub_toplevel_layer: [*c]LayerSurface;

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

fn resetLayerWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    stub_list_insert_calls = 0;
    stub_list_remove_calls = 0;
    stub_last_listener = null;
    stub_enable_calls = 0;
    stub_enabled_value = -1;
    stub_position_calls = 0;
    stub_pos_x = 0;
    stub_pos_y = 0;
    stub_reparent_calls = 0;
    stub_destroy_calls = 0;
    stub_raise_calls = 0;
    stub_lower_calls = 0;
    stub_coords_calls = 0;
    stub_coords_x = 0;
    stub_coords_y = 0;
    stub_for_each_calls = 0;
    stub_scene_surface_result = null;
    stub_configure_calls = 0;
    stub_usable_area = std.mem.zeroes(Box);
    stub_full_area = std.mem.zeroes(Box);
    stub_scene_layer_next = 0;
    stub_scene_layer_create_calls = 0;
    stub_plain_tree_next = 0;
    stub_tree_create_calls = 0;
    stub_xdg_tree_next = 0;
    stub_xdg_surface_create_calls = 0;
    stub_rect_next = 0;
    stub_rect_create_calls = 0;
    stub_shadow_next = 0;
    stub_shadow_create_calls = 0;
    stub_shadow_corner = 0;
    stub_shadow_blur = 0;
    stub_blur_next = 0;
    stub_blur_create_calls = 0;
    stub_mask_source_calls = 0;
    stub_blur_size_calls = 0;
    stub_blur_size_w = 0;
    stub_blur_size_h = 0;
    stub_bottom_layer_calls = 0;
    stub_bottom_layer_value = false;
    stub_dirty_calls = 0;
    stub_popup_unconstrain_calls = 0;
    stub_constraint_box = std.mem.zeroes(Box);
    stub_popup_try_result = null;
    stub_popup_destroy_calls = 0;
    stub_layer_destroy_calls = 0;
    stub_regex_match = 0;
    stub_regex_calls = 0;
    stub_bar_strip = 0;
    stub_bar_layout_calls = 0;
    stub_printstatus_calls = 0;
    stub_client_focus_calls = 0;
    stub_last_focus = null;
    stub_last_lift = -1;
    stub_top_client = null;
    stub_notify_calls = 0;
    stub_notify_surface = null;
    stub_relay_calls = 0;
    stub_scale_calls = 0;
    stub_scale = 0;
    stub_pointer_calls = 0;
    stub_arrange_calls = 0;
    stub_blur_layer_calls = 0;
    stub_blur_on_wallpaper = false;
    stub_fadeout_calls = 0;
    stub_pending_calls = 0;
    stub_target_box = std.mem.zeroes(Box);
    stub_toplevel_kind = c.XDGShell;
    stub_toplevel_client = null;
    stub_toplevel_layer = null;
}

fn baseMonitor(m: *Monitor, out: *c.struct_wlr_output) void {
    m.* = std.mem.zeroes(Monitor);
    out.* = std.mem.zeroes(c.struct_wlr_output);
    m.m = mkBox(0, 0, 1000, 800);
    m.w = m.m;
    out.enabled = true;
    out.scale = 2.0;
    m.wlr_output = out;
    var i: usize = 0;
    while (i < 4) : (i += 1)
        listInit(&m.layers[i]);
}

fn baseLayer(l: *LayerSurface, m: *Monitor, scene: [*c]c.struct_wlr_scene_tree, ls: *c.struct_wlr_layer_surface_v1, kind: c_int) void {
    l.* = std.mem.zeroes(LayerSurface);
    ls.* = std.mem.zeroes(c.struct_wlr_layer_surface_v1);
    ls.initialized = true;
    ls.current.layer = @intCast(kind);
    ls.pending.layer = @intCast(kind);
    l.type = @intCast(c.LayerShell);
    l.mon = @ptrCast(m);
    l.scene = scene;
    l.layer_surface = ls;
    l.mapped = 1;
    l.geom = mkBox(0, 0, 100, 100);
    l.current = l.geom;
    l.pending = l.geom;
    l.animation.current = l.geom;
    l.animation_type_open = c.ANIM_TYPE_UNSET;
    l.animation_type_close = c.ANIM_TYPE_UNSET;
}

test "arrange_layer configures matching layers and syncs popups" {
    resetLayerWorld();
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    baseMonitor(&m, &out);
    var scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var popups: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    scene.node.x = 5;
    scene.node.y = 6;
    var ls_a: c.struct_wlr_layer_surface_v1 = undefined;
    var a: LayerSurface = undefined;
    baseLayer(&a, &m, &scene, &ls_a, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    a.popups = &popups;
    var sl: c.struct_wlr_scene_layer_surface_v1 = std.mem.zeroes(c.struct_wlr_scene_layer_surface_v1);
    var lt: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    sl.tree = &lt;
    a.scene_layer = &sl;
    ls_a.current.exclusive_zone = 20;
    var ls_b: c.struct_wlr_layer_surface_v1 = undefined;
    var b: LayerSurface = undefined;
    baseLayer(&b, &m, &scene, &ls_b, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    b.popups = &popups;
    b.scene_layer = &sl;
    ls_b.current.exclusive_zone = 0;

    var list: c.struct_wl_list = undefined;
    listInit(&list);
    listInsert(&list, &a.link);
    listInsert(&list, &b.link);

    var usable = m.m;
    var full = m.m;
    arrange_layer(&m, &list, &usable, 1, &full);
    try testing.expectEqual(@as(c_int, 1), stub_configure_calls);
    try testing.expectEqual(@as(i32, 5), stub_pos_x);
    try testing.expectEqual(@as(i32, 6), stub_pos_y);

    arrange_layer(&m, &list, &usable, 0, &full);
    try testing.expectEqual(@as(c_int, 2), stub_configure_calls);

    ls_b.initialized = false;
    arrange_layer(&m, &list, &usable, 0, &full);
    try testing.expectEqual(@as(c_int, 2), stub_configure_calls);

    a.being_unmapped = true;
    arrange_layer(&m, &list, &usable, 1, &full);
    try testing.expectEqual(@as(c_int, 2), stub_configure_calls);
}

test "layer focus and exclusive reset honour locks and interactivity" {
    resetLayerWorld();
    var seat: c.struct_wlr_seat = std.mem.zeroes(c.struct_wlr_seat);
    c.server.seat = &seat;
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    var ls: c.struct_wlr_layer_surface_v1 = std.mem.zeroes(c.struct_wlr_layer_surface_v1);
    ls.surface = &surface;
    var l: LayerSurface = std.mem.zeroes(LayerSurface);
    l.layer_surface = &ls;

    c.server.session_locked = 1;
    layer_focus(&l);
    try testing.expectEqual(@as(c_int, 0), stub_client_focus_calls);

    c.server.session_locked = 0;
    layer_focus(&l);
    try testing.expectEqual(@as(c_int, 1), stub_client_focus_calls);
    try testing.expectEqual(@as(c_int, 1), stub_relay_calls);
    try testing.expectEqual(@as(c_int, 1), stub_notify_calls);

    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    baseMonitor(&m, &out);
    ls.current.keyboard_interactive = @intCast(c.ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_EXCLUSIVE);
    listInsert(&m.layers[@intCast(c.ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY)], &l.link);
    c.server.exclusive_focus = null;
    reset_exclusive_layers_focus(&m);
    try testing.expect(c.server.exclusive_focus != null);
    try testing.expectEqual(@intFromPtr(&l), @intFromPtr(c.server.exclusive_focus.?));
    try testing.expectEqual(@as(c_int, 2), stub_notify_calls);

    c.server.exclusive_focus = null;
    ls.current.keyboard_interactive = @intCast(c.ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE);
    seat.keyboard_state.focused_surface = &surface;
    reset_exclusive_layers_focus(&m);
    try testing.expect(c.server.exclusive_focus == null);

    l.mapped = 1;
    c.server.session_locked = 1;
    ls.current.keyboard_interactive = @intCast(c.ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_EXCLUSIVE);
    reset_exclusive_layers_focus(&m);
    try testing.expect(c.server.exclusive_focus == null);
}

test "arrange_layers reserves the bar strip and refreshes exclusive geometry" {
    resetLayerWorld();
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    baseMonitor(&m, &out);
    stub_bar_strip = 30;

    arrange_layers(&m);
    try testing.expectEqual(@as(i32, 30), m.w.y);
    try testing.expectEqual(@as(i32, 770), m.w.height);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);
    try testing.expectEqual(@as(c_int, 1), stub_bar_layout_calls);

    var scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var ls: c.struct_wlr_layer_surface_v1 = undefined;
    var l: LayerSurface = undefined;
    baseLayer(&l, &m, &scene, &ls, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    ls.current.exclusive_zone = 40;
    l.geom = mkBox(0, 0, 500, 500);
    stub_target_box = mkBox(0, 30, 1000, 770);
    var sl: c.struct_wlr_scene_layer_surface_v1 = std.mem.zeroes(c.struct_wlr_scene_layer_surface_v1);
    var lt: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    sl.tree = &lt;
    l.scene_layer = &sl;
    var popups: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    l.popups = &popups;
    listInsert(&m.layers[@intCast(c.ZWLR_LAYER_SHELL_V1_LAYER_TOP)], &l.link);

    arrange_layers(&m);
    try testing.expectEqual(@as(c_int, 1), stub_configure_calls);
    try testing.expectEqual(@as(i32, 30), l.geom.y);
    try testing.expectEqual(@as(i32, 770), l.geom.height);
    try testing.expectEqual(@as(i32, 30), stub_pos_y);
    try testing.expect(l.need_output_flush);

    var ls_b: c.struct_wlr_layer_surface_v1 = undefined;
    var b: LayerSurface = undefined;
    baseLayer(&b, &m, &scene, &ls_b, c.ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM);
    ls_b.current.exclusive_zone = 0;
    b.scene_layer = &sl;
    b.popups = &popups;
    listInsert(&m.layers[@intCast(c.ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM)], &b.link);
    arrange_layers(&m);
    try testing.expectEqual(@as(c_int, 3), stub_configure_calls);
}

test "blur iteration, wallpaper choice and background flush" {
    resetLayerWorld();
    var l: LayerSurface = std.mem.zeroes(LayerSurface);
    var ls: c.struct_wlr_layer_surface_v1 = std.mem.zeroes(c.struct_wlr_layer_surface_v1);
    var blur: c.struct_wlr_scene_blur = std.mem.zeroes(c.struct_wlr_scene_blur);
    l.layer_surface = &ls;
    l.blur = &blur;
    l.geom = mkBox(0, 0, 300, 40);
    ls.current.layer = @intCast(c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);

    iter_layer_scene_buffers(null, 0, 0, &l);
    try testing.expectEqual(@as(c_int, 0), stub_enable_calls);

    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    var ss: c.struct_wlr_scene_surface = std.mem.zeroes(c.struct_wlr_scene_surface);
    ss.surface = &surface;
    stub_scene_surface_result = &ss;
    var buffer: c.struct_wlr_scene_buffer = std.mem.zeroes(c.struct_wlr_scene_buffer);
    iter_layer_scene_buffers(&buffer, 0, 0, &l);
    try testing.expectEqual(@as(c_int, 1), stub_enable_calls);
    try testing.expectEqual(@as(c_int, 1), stub_mask_source_calls);
    try testing.expectEqual(@as(c_int, 300), stub_blur_size_w);
    try testing.expectEqual(@as(c_int, 40), stub_blur_size_h);
    try testing.expectEqual(@as(c_int, 1), stub_bottom_layer_calls);
    try testing.expect(!stub_bottom_layer_value);

    c.config.blur_optimized = 1;
    iter_layer_scene_buffers(&buffer, 0, 0, &l);
    try testing.expect(stub_bottom_layer_value);

    c.config.blur_optimized = 0;
    stub_blur_on_wallpaper = true;
    try testing.expect(layer_blur_uses_wallpaper(&l));
    stub_blur_on_wallpaper = false;
    try testing.expect(!layer_blur_uses_wallpaper(&l));
    try testing.expect(!layer_blur_uses_wallpaper(null));
    l.layer_surface = null;
    try testing.expect(!layer_blur_uses_wallpaper(&l));

    l.layer_surface = &ls;
    var m: Monitor = std.mem.zeroes(Monitor);
    var blur_bg: c.struct_wlr_scene_optimized_blur = std.mem.zeroes(c.struct_wlr_scene_optimized_blur);
    m.blur = &blur_bg;
    l.mon = &m;
    ls.current.layer = @intCast(c.ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND);
    layer_flush_blur_background(&l);
    try testing.expectEqual(@as(c_int, 0), stub_dirty_calls);
    c.config.blur = 1;
    layer_flush_blur_background(&l);
    try testing.expectEqual(@as(c_int, 1), stub_dirty_calls);
    ls.current.layer = @intCast(c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    layer_flush_blur_background(&l);
    try testing.expectEqual(@as(c_int, 1), stub_dirty_calls);
}

test "layer map applies rules and creates shield, shadow and blur" {
    resetLayerWorld();
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    baseMonitor(&m, &out);
    var scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var ls: c.struct_wlr_layer_surface_v1 = undefined;
    var l: LayerSurface = undefined;
    baseLayer(&l, &m, &scene, &ls, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    l.mapped = 0;
    ls.namespace = @ptrCast(@constCast("waybar"));
    ls.current.exclusive_zone = 0;
    stub_target_box = mkBox(10, 20, 300, 40);

    var rule: c.ConfigLayerRule = std.mem.zeroes(c.ConfigLayerRule);
    rule.layer_name = @ptrCast(@constCast(".*"));
    rule.shield_when_capture = 1;
    rule.no_blur = 1;
    rule.no_animation = 1;
    rule.no_shadow = 1;
    rule.animation_type_open = c.ANIM_TYPE_ZOOM;
    rule.animation_type_close = c.ANIM_TYPE_SLIDE;
    c.config.layer_rules = &rule;
    c.config.layer_rules_count = 1;
    stub_regex_match = 1;

    handle_layer_surface_map(&l.map, null);
    try testing.expectEqual(@as(i32, 1), l.mapped);
    try testing.expectEqualStrings("waybar", std.mem.sliceTo(&m.last_open_surface, 0));
    try testing.expectEqual(@as(i32, 10), l.geom.x);
    try testing.expectEqual(@as(i32, 40), l.geom.height);
    try testing.expect(l.shield_when_capture);
    try testing.expectEqual(@as(i32, 1), l.no_blur);
    try testing.expectEqual(@as(i32, 1), l.no_animation);
    try testing.expectEqual(@as(i32, 1), l.no_shadow);
    try testing.expectEqual(@as(i32, c.ANIM_TYPE_ZOOM), l.animation_type_open);
    try testing.expectEqual(@as(i32, c.ANIM_TYPE_SLIDE), l.animation_type_close);
    try testing.expect(l.shield != null);
    try testing.expect(l.shadow != null);
    try testing.expect(l.blur != null);
    try testing.expectEqual(@as(c_int, 1), stub_rect_create_calls);
    try testing.expectEqual(@as(c_int, 1), stub_shadow_create_calls);
    try testing.expectEqual(@as(c_int, 1), stub_blur_create_calls);
    try testing.expectEqual(@as(c_int, 3), stub_lower_calls);
    try testing.expectEqual(@as(c_int, 0), stub_pending_calls);
    try testing.expectEqual(@as(c_int, 1), stub_printstatus_calls);

    // bottom layers get no shadow or blur
    var l2: LayerSurface = undefined;
    baseLayer(&l2, &m, &scene, &ls, c.ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM);
    l2.mapped = 0;
    ls.current.exclusive_zone = 0;
    handle_layer_surface_map(&l2.map, null);
    try testing.expect(l2.shield != null);
    try testing.expect(l2.shadow == null);
    try testing.expect(l2.blur == null);

    // exclusive zones suppress shadows but keep blur
    var l3: LayerSurface = undefined;
    baseLayer(&l3, &m, &scene, &ls, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    l3.mapped = 0;
    ls.current.exclusive_zone = 40;
    handle_layer_surface_map(&l3.map, null);
    try testing.expect(l3.shadow == null);
    try testing.expect(l3.blur != null);

    // animation path defers geometry to the pending state
    resetLayerWorld();
    baseMonitor(&m, &out);
    var l4: LayerSurface = undefined;
    baseLayer(&l4, &m, &scene, &ls, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    l4.mapped = 0;
    ls.namespace = @ptrCast(@constCast("waybar"));
    c.config.animations = 1;
    c.config.layer_animations = 1;
    c.config.animation_duration_open = 250;
    handle_layer_surface_map(&l4.map, null);
    try testing.expectEqual(@as(c_int, 1), stub_pending_calls);
    try testing.expectEqual(@as(i32, c.OPEN), l4.animation.action);
    try testing.expectEqual(@as(u32, 250), l4.animation.duration);
}

test "layer commit handles initial commit, buffers, moves and layer changes" {
    resetLayerWorld();
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    baseMonitor(&m, &out);
    var seat: c.struct_wlr_seat = std.mem.zeroes(c.struct_wlr_seat);
    c.server.seat = &seat;
    var scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var popups: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var ls: c.struct_wlr_layer_surface_v1 = undefined;
    var l: LayerSurface = undefined;
    baseLayer(&l, &m, &scene, &ls, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    l.popups = &popups;
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    var buffer: c.struct_wlr_buffer = std.mem.zeroes(c.struct_wlr_buffer);
    ls.surface = &surface;
    var sl: c.struct_wlr_scene_layer_surface_v1 = std.mem.zeroes(c.struct_wlr_scene_layer_surface_v1);
    var lt: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    sl.tree = &lt;
    l.scene_layer = &sl;
    listInsert(&m.layers[@intCast(c.ZWLR_LAYER_SHELL_V1_LAYER_TOP)], &l.link);

    ls.initial_commit = true;
    ls.current.keyboard_interactive = @intCast(c.ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_ON_DEMAND);
    handle_layer_surface_commit(&l.surface_commit, null);
    try testing.expectEqual(@as(c_int, 1), stub_scale_calls);
    try testing.expectEqual(@as(f32, 2.0), stub_scale);
    try testing.expect(stub_configure_calls > 0);
    try testing.expectEqual(@as(c_int, 1), stub_notify_calls);

    var l2: LayerSurface = undefined;
    baseLayer(&l2, &m, &scene, &ls, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    ls.surface = &surface;
    ls.initial_commit = false;
    surface.buffer = null;
    l2.mapped = 1;
    handle_layer_surface_commit(&l2.surface_commit, null);
    try testing.expectEqual(@as(c_int, 0), stub_enabled_value);

    var l3: LayerSurface = undefined;
    baseLayer(&l3, &m, &scene, &ls, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    ls.surface = &surface;
    l3.mapped = 1;
    surface.buffer = @ptrCast(&buffer);
    surface.mapped = true;
    ls.current.exclusive_zone = 0;
    stub_target_box = mkBox(50, 60, 200, 100);
    c.config.animations = 1;
    c.config.layer_animations = 1;
    c.config.animation_duration_move = 180;
    handle_layer_surface_commit(&l3.surface_commit, null);
    try testing.expectEqual(@as(i32, c.MOVE), l3.animation.action);
    try testing.expectEqual(@as(u32, 180), l3.animation.duration);
    try testing.expectEqual(@as(c_int, 1), stub_pending_calls);
    try testing.expect(l3.need_output_flush);

    var l4: LayerSurface = undefined;
    baseLayer(&l4, &m, &scene, &ls, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    ls.surface = &surface;
    l4.mapped = 1;
    surface.buffer = @ptrCast(&buffer);
    surface.mapped = true;
    stub_target_box = l4.geom;
    const pending_before = stub_pending_calls;
    handle_layer_surface_commit(&l4.surface_commit, null);
    try testing.expectEqual(pending_before, stub_pending_calls);

    var l5: LayerSurface = undefined;
    baseLayer(&l5, &m, &scene, &ls, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    ls.surface = &surface;
    l5.mapped = 1;
    l5.popups = &popups;
    l5.scene.*.node.parent = null;
    surface.buffer = @ptrCast(&buffer);
    surface.mapped = true;
    ls.current.committed = @intCast(c.WLR_LAYER_SURFACE_V1_STATE_LAYER);
    var layer_tree: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    c.server.layers[@intCast(c.LyrTop)] = &layer_tree;
    stub_target_box = l5.geom;
    handle_layer_surface_commit(&l5.surface_commit, null);
    try testing.expectEqual(@as(c_int, 2), stub_reparent_calls);
    try testing.expect(l5.scene.*.node.parent == &layer_tree);
    try testing.expectEqual(@as(c_int, 1), stub_list_remove_calls);
    try testing.expectEqual(@as(c_int, 1), stub_list_insert_calls);

    var l6: LayerSurface = undefined;
    baseLayer(&l6, &m, &scene, &ls, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    ls.surface = &surface;
    l6.mapped = 1;
    surface.buffer = @ptrCast(&buffer);
    surface.mapped = true;
    ls.current.committed = @intCast(c.WLR_LAYER_SURFACE_V1_STATE_KEYBOARD_INTERACTIVITY);
    ls.current.keyboard_interactive = @intCast(c.ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_EXCLUSIVE);
    stub_target_box = l6.geom;
    c.server.exclusive_focus = null;
    handle_layer_surface_commit(&l6.surface_commit, null);
    try testing.expect(c.server.exclusive_focus != null);

    var l7: LayerSurface = undefined;
    baseLayer(&l7, &m, &scene, &ls, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    ls.surface = &surface;
    l7.mapped = 1;
    var blur: c.struct_wlr_scene_blur = std.mem.zeroes(c.struct_wlr_scene_blur);
    l7.blur = &blur;
    surface.buffer = @ptrCast(&buffer);
    surface.mapped = true;
    ls.current.committed = 0;
    stub_target_box = l7.geom;
    c.config.blur = 1;
    c.config.blur_layer = 1;
    handle_layer_surface_commit(&l7.surface_commit, null);
    try testing.expectEqual(@as(c_int, 1), stub_for_each_calls);
}

test "popup unconstrain uses layer and client offsets" {
    resetLayerWorld();
    var popup: Popup = std.mem.zeroes(Popup);
    try testing.expect(!popup_unconstrain(&popup));

    var wlr_popup: c.struct_wlr_xdg_popup = std.mem.zeroes(c.struct_wlr_xdg_popup);
    popup.wlr_popup = &wlr_popup;
    try testing.expect(!popup_unconstrain(&popup));

    var parent_surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    var parent_node: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    parent_surface.data = &parent_node;
    wlr_popup.parent = &parent_surface;
    var xdg: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    xdg.surface = &surface;
    wlr_popup.base = &xdg;

    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    baseMonitor(&m, &out);
    var ls: c.struct_wlr_layer_surface_v1 = std.mem.zeroes(c.struct_wlr_layer_surface_v1);
    var l: LayerSurface = std.mem.zeroes(LayerSurface);
    l.mon = &m;
    l.layer_surface = &ls;
    var scene_layer: c.struct_wlr_scene_layer_surface_v1 = std.mem.zeroes(c.struct_wlr_scene_layer_surface_v1);
    var tree: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    scene_layer.tree = &tree;
    l.scene_layer = &scene_layer;
    stub_toplevel_kind = c.LayerShell;
    stub_toplevel_layer = &l;
    stub_coords_x = 10;
    stub_coords_y = 20;
    try testing.expect(!popup_unconstrain(&popup));
    try testing.expectEqual(@as(c_int, 1), stub_popup_unconstrain_calls);
    try testing.expectEqual(@as(i32, -10), stub_constraint_box.x);
    try testing.expectEqual(@as(i32, -20), stub_constraint_box.y);
    try testing.expectEqual(@as(i32, 1000), stub_constraint_box.width);

    var client: Client = std.mem.zeroes(Client);
    client.mon = &m;
    client.geom = mkBox(100, 200, 10, 10);
    client.bw = 5;
    var cxdg: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    cxdg.current.geometry = mkBox(10, 20, 1, 1);
    client.surface.xdg = &cxdg;
    stub_toplevel_kind = c.XDGShell;
    stub_toplevel_client = &client;
    stub_toplevel_layer = null;
    m.w = mkBox(0, 0, 1000, 750);
    try testing.expect(!popup_unconstrain(&popup));
    try testing.expectEqual(@as(i32, -95), stub_constraint_box.x);
    try testing.expectEqual(@as(i32, -185), stub_constraint_box.y);
    try testing.expectEqual(@as(i32, 750), stub_constraint_box.height);

    l.mon = null;
    stub_toplevel_kind = c.LayerShell;
    stub_toplevel_layer = &l;
    try testing.expect(popup_unconstrain(&popup));
}

test "popup lifecycle installs listeners and destroys on bad parents" {
    resetLayerWorld();
    var base: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    base.surface = &surface;
    var wlr_popup: c.struct_wlr_xdg_popup = std.mem.zeroes(c.struct_wlr_xdg_popup);
    wlr_popup.base = &base;

    handle_new_xdg_popup(null, &wlr_popup);
    try testing.expectEqual(@as(c_int, 3), stub_list_insert_calls);
    const popup = containerOf(Popup, "reposition", stub_last_listener);
    try testing.expectEqual(@as(u32, @intCast(c.XdgPopup)), popup.type);

    stub_popup_try_result = &wlr_popup;
    base.initial_commit = false;
    if (popup.commit.notify) |f| f(&popup.commit, &surface);
    try testing.expect(popup.commit.notify != null);

    base.initial_commit = true;
    var parent_surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    var parent_node: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    parent_surface.data = &parent_node;
    wlr_popup.parent = &parent_surface;
    var m: Monitor = std.mem.zeroes(Monitor);
    m.w = mkBox(0, 0, 100, 100);
    var client: Client = std.mem.zeroes(Client);
    client.mon = &m;
    client.surface.xdg = &base;
    stub_toplevel_kind = c.XDGShell;
    stub_toplevel_client = &client;
    if (popup.commit.notify) |f| f(&popup.commit, &surface);
    try testing.expectEqual(@as(c_int, 1), stub_raise_calls);
    try testing.expectEqual(@as(c_int, 1), stub_xdg_surface_create_calls);
    try testing.expectEqual(@as(c_int, 1), stub_popup_unconstrain_calls);
    try testing.expect(popup.commit.notify == null);

    var wlr_popup2: c.struct_wlr_xdg_popup = std.mem.zeroes(c.struct_wlr_xdg_popup);
    var base2: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);
    base2.surface = &surface;
    wlr_popup2.base = &base2;
    handle_new_xdg_popup(null, &wlr_popup2);
    const popup2 = containerOf(Popup, "reposition", stub_last_listener);
    stub_popup_try_result = &wlr_popup2;
    base2.initial_commit = true;
    wlr_popup2.parent = null;
    if (popup2.commit.notify) |f| f(&popup2.commit, &surface);
    try testing.expectEqual(@as(c_int, 1), stub_popup_destroy_calls);
    try testing.expect(popup2.commit.notify == null);

    if (popup2.reposition.notify) |f| f(&popup2.reposition, null);
    try testing.expectEqual(@as(c_int, 1), stub_popup_unconstrain_calls);
    if (popup2.destroy.notify) |f| f(&popup2.destroy, null);
}

test "new layer surface wires scene nodes and lists" {
    resetLayerWorld();
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    baseMonitor(&m, &out);
    out.data = &m;
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    var ls: c.struct_wlr_layer_surface_v1 = std.mem.zeroes(c.struct_wlr_layer_surface_v1);
    ls.surface = &surface;
    ls.pending.layer = @intCast(c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    ls.current.layer = @intCast(c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    var top_tree: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    c.server.layers[@intCast(c.LyrTop)] = &top_tree;

    ls.output = &out;
    handle_new_layer_surface(null, &ls);
    try testing.expect(ls.output == &out);
    try testing.expect(ls.data != null);
    const l = @as(*LayerSurface, @ptrCast(@alignCast(ls.data.?)));
    try testing.expectEqual(@as(u32, @intCast(c.LayerShell)), l.type);
    try testing.expectEqual(@as(i32, c.ANIM_TYPE_UNSET), l.animation_type_open);
    try testing.expect(l.mon == &m);
    try testing.expect(l.scene_layer != null);
    try testing.expect(l.scene != null);
    try testing.expect(l.popups != null);
    try testing.expectEqual(@as(c_int, 1), stub_scene_layer_create_calls);
    try testing.expectEqual(@as(c_int, 1), stub_tree_create_calls);
    try testing.expectEqual(@as(c_int, 5), stub_list_insert_calls);

    var ls2: c.struct_wlr_layer_surface_v1 = std.mem.zeroes(c.struct_wlr_layer_surface_v1);
    ls2.surface = &surface;
    ls2.pending.layer = @intCast(c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    c.server.selected_monitor = &m;
    handle_new_layer_surface(null, &ls2);
    try testing.expect(ls2.output == &out);

    var ls3: c.struct_wlr_layer_surface_v1 = std.mem.zeroes(c.struct_wlr_layer_surface_v1);
    ls3.surface = &surface;
    ls3.pending.layer = @intCast(c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    c.server.selected_monitor = null;
    handle_new_layer_surface(null, &ls3);
    try testing.expectEqual(@as(c_int, 1), stub_layer_destroy_calls);
}

test "layer node destroy removes links and popups" {
    resetLayerWorld();
    var m: Monitor = std.mem.zeroes(Monitor);
    var i: usize = 0;
    while (i < 4) : (i += 1)
        listInit(&m.layers[i]);
    const l: *LayerSurface = @ptrCast(@alignCast(c.ecalloc(1, @sizeOf(LayerSurface)) orelse unreachable));
    l.mon = &m;
    var popups: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    l.popups = &popups;
    listInsert(&m.layers[2], &l.link);
    l.destroy.link.next = &l.destroy.link;
    l.destroy.link.prev = &l.destroy.link;
    l.map.link.next = &l.map.link;
    l.map.link.prev = &l.map.link;
    l.unmap.link.next = &l.unmap.link;
    l.unmap.link.prev = &l.unmap.link;
    l.surface_commit.link.next = &l.surface_commit.link;
    l.surface_commit.link.prev = &l.surface_commit.link;

    handle_layer_node_destroy(&l.destroy, null);
    try testing.expectEqual(@as(c_int, 5), stub_list_remove_calls);
    try testing.expectEqual(@as(c_int, 1), stub_destroy_calls);
}

test "layer unmap tears down focus, shadows and blur caches" {
    resetLayerWorld();
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    baseMonitor(&m, &out);
    out.data = &m;
    var scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var ls: c.struct_wlr_layer_surface_v1 = undefined;
    var l: LayerSurface = undefined;
    baseLayer(&l, &m, &scene, &ls, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    ls.output = &out;
    var shadow: c.struct_wlr_scene_shadow = std.mem.zeroes(c.struct_wlr_scene_shadow);
    l.shadow = &shadow;
    c.server.exclusive_focus = @ptrCast(&l);
    var blur_bg: c.struct_wlr_scene_optimized_blur = std.mem.zeroes(c.struct_wlr_scene_optimized_blur);
    m.blur = &blur_bg;
    c.config.blur = 1;
    ls.current.layer = @intCast(c.ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND);
    stub_bar_strip = 0;

    handle_layer_surface_unmap(&l.unmap, null);
    try testing.expectEqual(@as(i32, 0), l.mapped);
    try testing.expectEqual(@as(c_int, 1), stub_fadeout_calls);
    try testing.expectEqual(@as(c_int, 0), stub_enabled_value);
    try testing.expect(c.server.exclusive_focus == null);
    try testing.expectEqual(@as(c_int, 1), stub_pointer_calls);
    try testing.expectEqual(@as(c_int, 1), stub_dirty_calls);
    try testing.expectEqual(@as(c_int, 1), stub_destroy_calls);
    try testing.expect(l.shadow == null);
    try testing.expect(!l.being_unmapped);

    var l2: LayerSurface = undefined;
    baseLayer(&l2, &m, &scene, &ls, c.ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM);
    ls.output = &out;
    handle_layer_surface_unmap(&l2.unmap, null);
    try testing.expect(l2.shadow == null);
}
