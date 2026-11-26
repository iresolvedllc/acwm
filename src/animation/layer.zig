//! Port of src/animation/layer.c (Phase 5, animation slice 3, slice 51).
//! Layer-shell geometry (exclusive bounds, target geometry, slide
//! directions), shield/shadow painting and the open/close animation ticks.

const std = @import("std");
const c = @import("cc");

const LayerSurface = c.LayerSurface;
const Monitor = c.Monitor;
const Box = c.struct_wlr_box;
const BufferData = c.BufferData;

extern fn layer_blur_uses_wallpaper(l: ?*LayerSurface) callconv(.c) bool;
extern fn scene_buffer_apply_opacity(buffer: [*c]c.struct_wlr_scene_buffer, sx: i32, sy: i32, data: ?*anyopaque) callconv(.c) void;
extern fn wlr_output_schedule_frame(output: [*c]c.struct_wlr_output) callconv(.c) void;

fn containerOf(comptime T: type, comptime field: []const u8, link: [*c]c.struct_wl_list) *T {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(T, field));
}

fn monitorOpt(p: [*c]Monitor) ?*Monitor {
    return if (p == null) null else @ptrCast(p);
}

fn layerState(l: *const LayerSurface) *const c.struct_wlr_layer_surface_v1_state {
    return &l.layer_surface.*.current;
}

fn openAnimationType(l: *const LayerSurface) i32 {
    return if (l.animation_type_open != c.ANIM_TYPE_UNSET)
        l.animation_type_open
    else
        c.config.layer_animation_type_open;
}

fn closeAnimationType(l: *const LayerSurface) i32 {
    return if (l.animation_type_close != c.ANIM_TYPE_UNSET)
        l.animation_type_close
    else
        c.config.layer_animation_type_close;
}

fn lerpBox(start: Box, end: Box, factor: f64) Box {
    const fx = @as(f64, @floatFromInt(end.x - start.x)) * factor;
    const fy = @as(f64, @floatFromInt(end.y - start.y)) * factor;
    const fw = @as(f64, @floatFromInt(end.width - start.width)) * factor;
    const fh = @as(f64, @floatFromInt(end.height - start.height)) * factor;
    return .{
        .x = start.x + @as(i32, @intFromFloat(fx)),
        .y = start.y + @as(i32, @intFromFloat(fy)),
        .width = start.width + @as(i32, @intFromFloat(fw)),
        .height = start.height + @as(i32, @intFromFloat(fh)),
    };
}

fn nowMs() u32 {
    var ts: c.struct_timespec = undefined;
    _ = c.clock_gettime(c.CLOCK_MONOTONIC, &ts);
    return c.timespec_to_ms(&ts);
}

export fn layer_actual_size(l: *LayerSurface, width: [*c]i32, height: [*c]i32) callconv(.c) void {
    if (l.animation.running) {
        width[0] = l.animation.current.width;
        height[0] = l.animation.current.height;
    } else {
        width[0] = l.geom.width;
        height[0] = l.geom.height;
    }
}

fn layerConsumeExclusive(it: *LayerSurface, box: *Box) void {
    const state = layerState(it);
    if (state.exclusive_zone <= 0)
        return;

    const edge = c.wlr_layer_surface_v1_get_exclusive_edge(it.layer_surface);
    switch (@as(c_int, @intCast(edge))) {
        c.WLR_EDGE_TOP => {
            box.y += state.exclusive_zone + state.margin.top;
            box.height -= state.exclusive_zone + state.margin.top;
        },
        c.WLR_EDGE_BOTTOM => {
            box.height -= state.exclusive_zone + state.margin.bottom;
        },
        c.WLR_EDGE_LEFT => {
            box.x += state.exclusive_zone + state.margin.left;
            box.width -= state.exclusive_zone + state.margin.left;
        },
        c.WLR_EDGE_RIGHT => {
            box.width -= state.exclusive_zone + state.margin.right;
        },
        else => {},
    }

    if (box.width < 0)
        box.width = 0;
    if (box.height < 0)
        box.height = 0;
}

fn layerBoundArea(l: *LayerSurface) Box {
    const state = layerState(l);
    const mon = monitorOpt(l.mon) orelse return std.mem.zeroes(Box);

    if (state.exclusive_zone < 0)
        return mon.m;
    if (state.exclusive_zone == 0)
        return mon.w;

    var box = mon.m;
    var reached = false;
    var i: i32 = 3;
    while (i >= 0 and !reached) : (i -= 1) {
        const head: [*c]c.struct_wl_list = @ptrCast(&mon.layers[@intCast(i)]);
        var pos = mon.layers[@intCast(i)].next;
        while (pos != head) : (pos = pos.*.next) {
            const it = containerOf(LayerSurface, "link", pos);
            if (it == l) {
                reached = true;
                break;
            }
            if (it.being_unmapped or it.mapped == 0 or !it.layer_surface.*.initialized)
                continue;
            layerConsumeExclusive(it, &box);
        }
    }

    if (!reached)
        return mon.m;
    return box;
}

export fn get_layer_area_bound(l: *LayerSurface, bound: *Box) callconv(.c) void {
    bound.* = layerBoundArea(l);
}

export fn get_layer_target_geometry(l: *LayerSurface, target_box: *Box) callconv(.c) void {
    if (l.mapped == 0)
        return;

    const state = layerState(l);
    const bounds = layerBoundArea(l);

    var box = Box{
        .width = @intCast(state.desired_width),
        .height = @intCast(state.desired_height),
    };

    const both_horiz: u32 = @intCast(c.ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT | c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
    if (box.width == 0) {
        box.x = bounds.x;
    } else if ((state.anchor & both_horiz) == both_horiz) {
        box.x = bounds.x + @divTrunc(bounds.width - box.width, 2);
    } else if ((state.anchor & @as(u32, @intCast(c.ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT))) != 0) {
        box.x = bounds.x;
    } else if ((state.anchor & @as(u32, @intCast(c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT))) != 0) {
        box.x = bounds.x + (bounds.width - box.width);
    } else {
        box.x = bounds.x + @divTrunc(bounds.width - box.width, 2);
    }

    const both_vert: u32 = @intCast(c.ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | c.ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM);
    if (box.height == 0) {
        box.y = bounds.y;
    } else if ((state.anchor & both_vert) == both_vert) {
        box.y = bounds.y + @divTrunc(bounds.height - box.height, 2);
    } else if ((state.anchor & @as(u32, @intCast(c.ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP))) != 0) {
        box.y = bounds.y;
    } else if ((state.anchor & @as(u32, @intCast(c.ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM))) != 0) {
        box.y = bounds.y + (bounds.height - box.height);
    } else {
        box.y = bounds.y + @divTrunc(bounds.height - box.height, 2);
    }

    if (box.width == 0) {
        box.x += state.margin.left;
        box.width = bounds.width - (state.margin.left + state.margin.right);
    } else {
        if ((state.anchor & @as(u32, @intCast(c.ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT))) != 0)
            box.x += state.margin.left
        else if ((state.anchor & @as(u32, @intCast(c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT))) != 0)
            box.x -= state.margin.right;
    }

    if (box.height == 0) {
        box.y += state.margin.top;
        box.height = bounds.height - (state.margin.top + state.margin.bottom);
    } else {
        if ((state.anchor & @as(u32, @intCast(c.ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP))) != 0)
            box.y += state.margin.top
        else if ((state.anchor & @as(u32, @intCast(c.ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM))) != 0)
            box.y -= state.margin.bottom;
    }

    target_box.* = box;
}

export fn set_layer_dir_animaiton(l: *LayerSurface, geo: *Box) callconv(.c) void {
    const mon = monitorOpt(l.mon) orelse return;

    var usable_area: Box = undefined;
    get_layer_area_bound(l, &usable_area);

    geo.width = l.geom.width;
    geo.height = l.geom.height;

    const center_x = l.geom.x + @divTrunc(l.geom.width, 2);
    const center_y = l.geom.y + @divTrunc(l.geom.height, 2);
    const horizontal: c_int = if (center_x > usable_area.x + @divTrunc(usable_area.width, 2)) c.RIGHT else c.LEFT;
    const horizontal_value = if (horizontal == c.LEFT)
        center_x - usable_area.x
    else
        usable_area.x + usable_area.width - center_x;
    const vertical: c_int = if (center_y > usable_area.y + @divTrunc(usable_area.height, 2)) c.DOWN else c.UP;
    const vertical_value = if (vertical == c.UP)
        center_y - mon.w.y
    else
        usable_area.y + usable_area.height - center_y;
    const slide_direction: c_int = if (horizontal_value < vertical_value) horizontal else vertical;

    switch (slide_direction) {
        c.UP => {
            geo.x = l.geom.x;
            geo.y = usable_area.y - l.geom.height;
        },
        c.DOWN => {
            geo.x = l.geom.x;
            geo.y = usable_area.y + usable_area.height;
        },
        c.LEFT => {
            geo.x = usable_area.x - l.geom.width;
            geo.y = l.geom.y;
        },
        c.RIGHT => {
            geo.x = usable_area.x + usable_area.width;
            geo.y = l.geom.y;
        },
        else => {
            geo.x = l.geom.x;
            geo.y = -l.geom.height;
        },
    }
}

export fn layer_draw_shield(l: *LayerSurface) callconv(.c) void {
    if (l.mapped == 0 or l.shield == null)
        return;

    if (c.server.active_capture_count > 0 and l.shield_when_capture) {
        var width: i32 = 0;
        var height: i32 = 0;
        layer_actual_size(l, &width, &height);

        if (width <= 0 or height <= 0) {
            c.wlr_scene_node_set_enabled(&l.shield.*.node, false);
            return;
        }

        c.wlr_scene_node_raise_to_top(&l.shield.*.node);
        c.wlr_scene_node_set_position(&l.shield.*.node, 0, 0);
        c.wlr_scene_rect_set_size(l.shield, width, height);
        c.wlr_scene_node_set_enabled(&l.shield.*.node, true);
    } else {
        if (l.shield.*.node.enabled) {
            c.wlr_scene_node_lower_to_bottom(&l.shield.*.node);
            c.wlr_scene_node_set_position(&l.shield.*.node, 0, 0);
            c.wlr_scene_node_set_enabled(&l.shield.*.node, false);
        }
    }
}

export fn layer_draw_shadow(l: *LayerSurface) callconv(.c) void {
    if (l.mapped == 0 or l.shadow == null)
        return;

    if (c.config.shadows == 0 or c.config.layer_shadows == 0 or l.no_shadow != 0) {
        c.wlr_scene_shadow_set_size(l.shadow, 0, 0);
        return;
    }

    var width: i32 = 0;
    var height: i32 = 0;
    layer_actual_size(l, &width, &height);

    const delta: i32 = @intCast(c.config.shadows_size);

    const layer_box = Box{ .x = 0, .y = 0, .width = width, .height = height };
    const shadow_box = Box{
        .x = c.config.shadows_position_x,
        .y = c.config.shadows_position_y,
        .width = width + 2 * delta,
        .height = height + 2 * delta,
    };

    var intersection_box: Box = undefined;
    _ = c.wlr_box_intersection(&intersection_box, &layer_box, &shadow_box);
    intersection_box.x -= c.config.shadows_position_x;
    intersection_box.y -= c.config.shadows_position_y;

    const clipped_region = c.struct_clipped_region{
        .area = intersection_box,
        .corners = c.corner_radii_all(c.config.border_radius),
    };

    c.wlr_scene_node_set_position(&l.shadow.*.node, shadow_box.x, shadow_box.y);
    c.wlr_scene_shadow_set_size(l.shadow, shadow_box.width, shadow_box.height);
    c.wlr_scene_shadow_set_clipped_region(l.shadow, clipped_region);
}

export fn layer_scene_buffer_apply_effect(buffer: [*c]c.struct_wlr_scene_buffer, sx: i32, sy: i32, data: ?*anyopaque) callconv(.c) void {
    _ = sx;
    _ = sy;
    const buffer_data = @as(*BufferData, @ptrCast(@alignCast(data.?)));

    const scene_surface = c.wlr_scene_surface_try_from_buffer(buffer);
    if (scene_surface == null)
        return;

    const surface = scene_surface.*.surface;
    const surface_width: i32 = @intFromFloat(@as(f64, @floatFromInt(surface.*.current.width)) * buffer_data.width_scale);
    const surface_height: i32 = @intFromFloat(@as(f64, @floatFromInt(surface.*.current.height)) * buffer_data.height_scale);

    if (surface_height > 0 and surface_width > 0)
        c.wlr_scene_buffer_set_dest_size(buffer, surface_width, surface_height);
}

export fn layer_fadeout_scene_buffer_apply_effect(buffer: [*c]c.struct_wlr_scene_buffer, sx: i32, sy: i32, data: ?*anyopaque) callconv(.c) void {
    _ = sx;
    _ = sy;
    const buffer_data = @as(*BufferData, @ptrCast(@alignCast(data.?)));
    c.wlr_scene_buffer_set_dest_size(buffer, buffer_data.width, buffer_data.height);
}

export fn fadeout_layer_animation_next_tick(l: *LayerSurface) callconv(.c) void {
    const passed_raw = nowMs() -% l.animation.time_started;
    const passed_time: i32 = @bitCast(passed_raw);
    const animation_passed: f64 = if (l.animation.duration != 0)
        @as(f64, @floatFromInt(passed_time)) / @as(f64, @floatFromInt(l.animation.duration))
    else
        1.0;

    const animation_type = l.animation.action;
    const factor = c.find_animation_curve_at(animation_passed, animation_type);
    const box = lerpBox(l.animation.initial, l.current, factor);

    c.wlr_scene_node_set_position(&l.scene.*.node, box.x, box.y);

    var buffer_data = std.mem.zeroes(BufferData);
    buffer_data.width = box.width;
    buffer_data.height = box.height;

    if (closeAnimationType(l) == c.ANIM_TYPE_ZOOM) {
        c.wlr_scene_node_for_each_buffer(&l.scene.*.node, layer_fadeout_scene_buffer_apply_effect, &buffer_data);
    }

    l.animation.current = box;

    const opacity_eased = c.find_animation_curve_at(animation_passed, c.OPAFADEOUT);
    const percent = @as(f64, c.config.fadeout_begin_opacity) - opacity_eased * @as(f64, c.config.fadeout_begin_opacity);
    var opacity: f32 = @max(@as(f32, @floatCast(percent)), 0.0);

    if (c.config.animation_fade_out != 0)
        c.wlr_scene_node_for_each_buffer(&l.scene.*.node, scene_buffer_apply_opacity, &opacity);

    if (animation_passed >= 1.0) {
        c.wl_list_remove(&l.fadeout_link);
        c.wlr_scene_node_destroy(&l.scene.*.node);
        c.free(l);
    }
}

export fn layer_animation_next_tick(l: *LayerSurface) callconv(.c) void {
    if (l.mapped == 0)
        return;

    const passed_raw = nowMs() -% l.animation.time_started;
    const passed_time: i32 = @bitCast(passed_raw);
    const animation_passed: f64 = if (l.animation.duration != 0)
        @as(f64, @floatFromInt(passed_time)) / @as(f64, @floatFromInt(l.animation.duration))
    else
        1.0;

    const animation_type = if (l.animation.action == c.NONE) c.MOVE else l.animation.action;
    const factor = c.find_animation_curve_at(animation_passed, animation_type);
    const box = lerpBox(l.animation.initial, l.current, factor);

    const opacity_eased = c.find_animation_curve_at(animation_passed, c.OPAFADEIN);
    var opacity: f32 = @min(
        @as(f32, @floatCast(@as(f64, c.config.fadein_begin_opacity) + opacity_eased * (1.0 - @as(f64, c.config.fadein_begin_opacity)))),
        1.0,
    );

    if (c.config.animation_fade_in != 0) {
        if (c.config.blur != 0 and l.no_blur == 0 and !layer_blur_uses_wallpaper(l) and l.blur != null) {
            c.wlr_scene_blur_set_strength(l.blur, opacity);
            c.wlr_scene_blur_set_alpha(l.blur, opacity);
        }
        c.wlr_scene_node_for_each_buffer(&l.scene.*.node, scene_buffer_apply_opacity, &opacity);
    }

    c.wlr_scene_node_set_position(&l.scene.*.node, box.x, box.y);

    var buffer_data = std.mem.zeroes(BufferData);
    if (factor == 1.0) {
        buffer_data.width_scale = 1.0;
        buffer_data.height_scale = 1.0;
    } else {
        buffer_data.width_scale = @as(f32, @floatFromInt(box.width)) / @as(f32, @floatFromInt(l.current.width));
        buffer_data.height_scale = @as(f32, @floatFromInt(box.height)) / @as(f32, @floatFromInt(l.current.height));
    }

    if (openAnimationType(l) == c.ANIM_TYPE_ZOOM) {
        c.wlr_scene_node_for_each_buffer(&l.scene.*.node, layer_scene_buffer_apply_effect, &buffer_data);
    }

    l.animation.current = box;

    if (c.config.blur != 0 and c.config.blur_layer != 0 and l.no_blur == 0 and l.blur != null)
        c.wlr_scene_blur_set_size(l.blur, l.animation.current.width, l.animation.current.height);

    if (animation_passed >= 1.0) {
        l.animation.running = false;
        l.need_output_flush = false;
        l.animation.action = c.MOVE;
    }
}

export fn init_fadeout_layers(l: *LayerSurface) callconv(.c) void {
    if (c.config.animations == 0 or c.config.layer_animations == 0 or l.no_animation != 0)
        return;
    if (l.mon == null or l.scene == null)
        return;
    if (l.shield_when_capture)
        return;
    if (closeAnimationType(l) == c.ANIM_TYPE_NONE)
        return;

    const layer_kind = l.layer_surface.*.current.layer;
    if (layer_kind == @as(c.enum_zwlr_layer_shell_v1_layer, @intCast(c.ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM)) or
        layer_kind == @as(c.enum_zwlr_layer_shell_v1_layer, @intCast(c.ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND)))
        return;

    const raw = c.ecalloc(1, @sizeOf(LayerSurface)) orelse return;
    const fadeout = @as(*LayerSurface, @ptrCast(@alignCast(raw)));

    var usable_area: Box = undefined;
    get_layer_area_bound(l, &usable_area);

    c.wlr_scene_node_set_enabled(&l.scene.*.node, true);
    fadeout.scene = c.wlr_scene_tree_snapshot(&l.scene.*.node, c.server.layers[@intCast(c.LyrFadeOut)]);
    c.wlr_scene_node_set_enabled(&l.scene.*.node, false);

    if (fadeout.scene == null) {
        c.free(fadeout);
        return;
    }

    fadeout.animation.duration = c.config.animation_duration_close;
    fadeout.geom = l.animation.current;
    fadeout.current = l.animation.current;
    fadeout.animainit_geom = l.animation.current;
    fadeout.animation.initial = l.animation.current;
    fadeout.mon = l.mon;
    fadeout.animation.action = c.CLOSE;
    fadeout.animation_type_close = l.animation_type_close;
    fadeout.animation_type_open = l.animation_type_open;

    fadeout.animation.initial.x = 0;
    fadeout.animation.initial.y = 0;

    if (closeAnimationType(l) == c.ANIM_TYPE_ZOOM) {
        fadeout.current.width = @intFromFloat(@as(f64, @floatFromInt(l.animation.current.width)) * c.config.zoom_end_ratio);
        fadeout.current.height = @intFromFloat(@as(f64, @floatFromInt(l.animation.current.height)) * c.config.zoom_end_ratio);
        fadeout.current.x = usable_area.x + @divTrunc(usable_area.width, 2) - @divTrunc(fadeout.current.width, 2);
        fadeout.current.y = usable_area.y + @divTrunc(usable_area.height, 2) - @divTrunc(fadeout.current.height, 2);
        fadeout.current.x = fadeout.current.x - l.animation.current.x;
        fadeout.current.y = fadeout.current.y - l.animation.current.y;
    } else if (closeAnimationType(l) == c.ANIM_TYPE_SLIDE) {
        set_layer_dir_animaiton(l, &fadeout.current);
        fadeout.current.x = fadeout.current.x - l.geom.x;
        fadeout.current.y = fadeout.current.y - l.geom.y;
        fadeout.current.width = fadeout.current.width - l.geom.width;
        fadeout.current.height = fadeout.current.height - l.geom.height;
    } else {
        fadeout.current.x = 0;
        fadeout.current.y = 0;
        fadeout.current.width = 0;
        fadeout.current.height = 0;
    }

    fadeout.animation.time_started = c.get_now_in_ms();

    c.wlr_scene_node_set_enabled(&fadeout.scene.*.node, true);
    c.wl_list_insert(&c.server.fadeout_layers, &fadeout.fadeout_link);

    if (l.mon != null)
        wlr_output_schedule_frame(l.mon.*.wlr_output);
}

export fn layer_set_pending_state(l: *LayerSurface) callconv(.c) void {
    if (l.mapped == 0)
        return;

    var usable_area: Box = undefined;
    get_layer_area_bound(l, &usable_area);

    l.pending = l.geom;

    if (l.animation.action == c.OPEN and !l.animation.running) {
        if (l.animation.duration == 0) {
            l.animainit_geom = l.geom;
        } else if (openAnimationType(l) == c.ANIM_TYPE_ZOOM) {
            l.animainit_geom.width = @intFromFloat(@as(f64, @floatFromInt(l.geom.width)) * c.config.zoom_initial_ratio);
            l.animainit_geom.height = @intFromFloat(@as(f64, @floatFromInt(l.geom.height)) * c.config.zoom_initial_ratio);
            l.animainit_geom.x = usable_area.x + @divTrunc(usable_area.width, 2) - @divTrunc(l.animainit_geom.width, 2);
            l.animainit_geom.y = usable_area.y + @divTrunc(usable_area.height, 2) - @divTrunc(l.animainit_geom.height, 2);
        } else if (openAnimationType(l) == c.ANIM_TYPE_SLIDE) {
            set_layer_dir_animaiton(l, &l.animainit_geom);
        } else {
            l.animainit_geom = l.geom;
        }
    } else {
        l.animainit_geom = l.animation.current;
    }

    const layer_kind = l.layer_surface.*.current.layer;
    if (c.config.animations == 0 or c.config.layer_animations == 0 or l.no_animation != 0 or
        layer_kind == @as(c.enum_zwlr_layer_shell_v1_layer, @intCast(c.ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND)) or
        layer_kind == @as(c.enum_zwlr_layer_shell_v1_layer, @intCast(c.ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM)))
    {
        l.animation.should_animate = false;
    } else {
        l.animation.should_animate = true;
    }

    if (openAnimationType(l) == c.ANIM_TYPE_NONE and l.animation.action == c.OPEN)
        l.animation.should_animate = false;

    layer_commit(l);
    l.dirty = true;
}

export fn layer_commit(l: *LayerSurface) callconv(.c) void {
    if (l.mapped == 0)
        return;

    l.current = l.pending;

    if (l.animation.should_animate) {
        if (!l.animation.running)
            l.animation.current = l.animainit_geom;

        l.animation.initial = l.animainit_geom;
        l.animation.time_started = c.get_now_in_ms();

        l.animation.running = true;
        l.animation.should_animate = false;
    }

    if (l.mon != null)
        wlr_output_schedule_frame(l.mon.*.wlr_output);
}

export fn layer_draw_frame(l: *LayerSurface) callconv(.c) bool {
    if (l.mapped == 0 or !l.need_output_flush)
        return false;

    const layer_kind = l.layer_surface.*.current.layer;
    if (layer_kind != @as(c.enum_zwlr_layer_shell_v1_layer, @intCast(c.ZWLR_LAYER_SHELL_V1_LAYER_TOP)) and
        layer_kind != @as(c.enum_zwlr_layer_shell_v1_layer, @intCast(c.ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY)))
        return false;

    if (c.config.animations != 0 and c.config.layer_animations != 0 and l.animation.running and l.no_animation == 0) {
        layer_animation_next_tick(l);
        layer_draw_shield(l);
        layer_draw_shadow(l);
    } else {
        layer_draw_shield(l);
        layer_draw_shadow(l);
        l.need_output_flush = false;
    }
    return true;
}

export fn layer_draw_fadeout_frame(l: *LayerSurface) callconv(.c) bool {
    fadeout_layer_animation_next_tick(l);
    return true;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/animation_layer_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_list_insert_calls: c_int;
extern var stub_list_remove_calls: c_int;
extern var stub_schedule_calls: c_int;
extern var stub_curve_factor: f64;
extern var stub_opacity_factor: f64;
extern var stub_now_ms: u32;
extern var stub_get_now: u32;
extern var stub_enable_calls: c_int;
extern var stub_enabled_value: c_int;
extern var stub_position_calls: c_int;
extern var stub_pos_x: i32;
extern var stub_pos_y: i32;
extern var stub_raise_calls: c_int;
extern var stub_lower_calls: c_int;
extern var stub_destroy_calls: c_int;
extern var stub_rect_size_calls: c_int;
extern var stub_rect_w: i32;
extern var stub_rect_h: i32;
extern var stub_shadow_size_calls: c_int;
extern var stub_shadow_w: i32;
extern var stub_shadow_h: i32;
extern var stub_shadow_clip_calls: c_int;
extern var stub_shadow_clip: c.struct_clipped_region;
extern var stub_blur_strength_calls: c_int;
extern var stub_blur_strength: f32;
extern var stub_blur_alpha_calls: c_int;
extern var stub_blur_alpha: f32;
extern var stub_blur_size_calls: c_int;
extern var stub_blur_w: i32;
extern var stub_blur_h: i32;
extern var stub_dest_size_calls: c_int;
extern var stub_dest_w: i32;
extern var stub_dest_h: i32;
extern var stub_for_each_calls: c_int;
extern var stub_invoke_iterator: c_int;
extern var stub_iter_buffer: c.struct_wlr_scene_buffer;
extern var stub_snapshot_result: [*c]c.struct_wlr_scene_tree;
extern var stub_snapshot_calls: c_int;
extern var stub_exclusive_edge: u32;
extern var stub_blur_wallpaper: bool;
extern var stub_opacity_calls: c_int;
extern var stub_last_opacity: f32;
extern var stub_scene_surface_result: [*c]c.struct_wlr_scene_surface;

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

fn resetAnimWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    listInit(&c.server.fadeout_layers);
    stub_list_insert_calls = 0;
    stub_list_remove_calls = 0;
    stub_schedule_calls = 0;
    stub_curve_factor = 1.0;
    stub_opacity_factor = 1.0;
    stub_now_ms = 1000;
    stub_get_now = 500;
    stub_enable_calls = 0;
    stub_enabled_value = -1;
    stub_position_calls = 0;
    stub_pos_x = 0;
    stub_pos_y = 0;
    stub_raise_calls = 0;
    stub_lower_calls = 0;
    stub_destroy_calls = 0;
    stub_rect_size_calls = 0;
    stub_rect_w = 0;
    stub_rect_h = 0;
    stub_shadow_size_calls = 0;
    stub_shadow_w = 0;
    stub_shadow_h = 0;
    stub_shadow_clip_calls = 0;
    stub_shadow_clip = std.mem.zeroes(c.struct_clipped_region);
    stub_blur_strength_calls = 0;
    stub_blur_strength = 0;
    stub_blur_alpha_calls = 0;
    stub_blur_alpha = 0;
    stub_blur_size_calls = 0;
    stub_blur_w = 0;
    stub_blur_h = 0;
    stub_dest_size_calls = 0;
    stub_dest_w = 0;
    stub_dest_h = 0;
    stub_for_each_calls = 0;
    stub_invoke_iterator = 0;
    stub_snapshot_result = null;
    stub_snapshot_calls = 0;
    stub_exclusive_edge = @intCast(c.WLR_EDGE_NONE);
    stub_blur_wallpaper = false;
    stub_opacity_calls = 0;
    stub_last_opacity = 0;
    stub_scene_surface_result = null;
}

fn baseMonitor(m: *Monitor, out: *c.struct_wlr_output) void {
    m.* = std.mem.zeroes(Monitor);
    out.* = std.mem.zeroes(c.struct_wlr_output);
    m.m = mkBox(0, 0, 1000, 800);
    m.w = m.m;
    out.enabled = true;
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
    l.mon = @ptrCast(m);
    l.scene = scene;
    l.layer_surface = ls;
    l.mapped = 1;
    l.geom = mkBox(0, 0, 100, 100);
    l.current = l.geom;
    l.pending = l.geom;
    l.animation.current = l.geom;
    l.animation.duration = 100;
    l.animation_type_open = c.ANIM_TYPE_UNSET;
    l.animation_type_close = c.ANIM_TYPE_UNSET;
}

test "layer actual size uses animation during motion" {
    resetAnimWorld();
    var l: LayerSurface = std.mem.zeroes(LayerSurface);
    l.geom = mkBox(10, 20, 30, 40);
    l.animation.current = mkBox(1, 2, 3, 4);
    var w: i32 = 0;
    var h: i32 = 0;
    layer_actual_size(&l, &w, &h);
    try testing.expectEqual(@as(i32, 30), w);
    try testing.expectEqual(@as(i32, 40), h);
    l.animation.running = true;
    layer_actual_size(&l, &w, &h);
    try testing.expectEqual(@as(i32, 3), w);
    try testing.expectEqual(@as(i32, 4), h);
}

test "layer target geometry honours anchors, margins and exclusive zones" {
    resetAnimWorld();
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    baseMonitor(&m, &out);
    var ls: c.struct_wlr_layer_surface_v1 = undefined;
    var l: LayerSurface = undefined;
    baseLayer(&l, &m, null, &ls, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);

    ls.current.exclusive_zone = 0;
    ls.current.desired_width = 0;
    ls.current.desired_height = 30;
    ls.current.anchor = @intCast(c.ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT | c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT | c.ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP);
    ls.current.margin.left = 10;
    ls.current.margin.right = 20;
    ls.current.margin.top = 5;
    var target: Box = undefined;
    get_layer_target_geometry(&l, &target);
    try testing.expectEqual(@as(i32, 10), target.x);
    try testing.expectEqual(@as(i32, 5), target.y);
    try testing.expectEqual(@as(i32, 970), target.width);
    try testing.expectEqual(@as(i32, 30), target.height);

    ls.current.anchor = 0;
    ls.current.desired_width = 200;
    ls.current.desired_height = 100;
    ls.current.margin = std.mem.zeroes(@TypeOf(ls.current.margin));
    get_layer_target_geometry(&l, &target);
    try testing.expectEqual(@as(i32, 400), target.x);
    try testing.expectEqual(@as(i32, 350), target.y);

    ls.current.anchor = @intCast(c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT | c.ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM);
    get_layer_target_geometry(&l, &target);
    try testing.expectEqual(@as(i32, 800), target.x);
    try testing.expectEqual(@as(i32, 700), target.y);

    ls.current.exclusive_zone = -1;
    ls.current.anchor = 0;
    get_layer_target_geometry(&l, &target);
    try testing.expectEqual(@as(i32, 400), target.x);
    try testing.expectEqual(@as(i32, 350), target.y);
}

test "layer bounds consume exclusive siblings" {
    resetAnimWorld();
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    baseMonitor(&m, &out);
    var first_ls: c.struct_wlr_layer_surface_v1 = undefined;
    var first: LayerSurface = undefined;
    baseLayer(&first, &m, null, &first_ls, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    first_ls.current.exclusive_zone = 40;
    first_ls.current.margin.top = 5;
    stub_exclusive_edge = @intCast(c.WLR_EDGE_TOP);

    var l_ls: c.struct_wlr_layer_surface_v1 = undefined;
    var l: LayerSurface = undefined;
    baseLayer(&l, &m, null, &l_ls, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    l_ls.current.exclusive_zone = 1;

    listInsert(&m.layers[2], &l.link);
    listInsert(&m.layers[2], &first.link);

    var bound: Box = undefined;
    get_layer_area_bound(&l, &bound);
    try testing.expectEqual(@as(i32, 0), bound.x);
    try testing.expectEqual(@as(i32, 45), bound.y);
    try testing.expectEqual(@as(i32, 1000), bound.width);
    try testing.expectEqual(@as(i32, 755), bound.height);

    l_ls.current.exclusive_zone = 0;
    get_layer_area_bound(&l, &bound);
    try testing.expectEqual(@as(i32, 0), bound.y);
    try testing.expectEqual(@as(i32, 800), bound.height);

    l_ls.current.exclusive_zone = -1;
    get_layer_area_bound(&l, &bound);
    try testing.expectEqual(@as(i32, 800), bound.height);

    l_ls.current.exclusive_zone = 1;
    first.being_unmapped = true;
    get_layer_area_bound(&l, &bound);
    try testing.expectEqual(@as(i32, 0), bound.y);

    first.being_unmapped = false;
    var ls2: c.struct_wlr_layer_surface_v1 = undefined;
    var l2: LayerSurface = undefined;
    baseLayer(&l2, &m, null, &ls2, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    ls2.current.exclusive_zone = 1;
    get_layer_area_bound(&l2, &bound);
    try testing.expectEqual(@as(i32, 0), bound.y);
    try testing.expectEqual(@as(i32, 800), bound.height);
}

test "slide animation picks the nearest edge" {
    resetAnimWorld();
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    baseMonitor(&m, &out);
    var ls: c.struct_wlr_layer_surface_v1 = undefined;
    var l: LayerSurface = undefined;
    baseLayer(&l, &m, null, &ls, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    ls.current.exclusive_zone = 0;

    l.geom = mkBox(0, 350, 100, 100);
    var geo: Box = undefined;
    set_layer_dir_animaiton(&l, &geo);
    try testing.expectEqual(@as(i32, -100), geo.x);
    try testing.expectEqual(@as(i32, 350), geo.y);

    l.geom = mkBox(900, 350, 100, 100);
    set_layer_dir_animaiton(&l, &geo);
    try testing.expectEqual(@as(i32, 1000), geo.x);
    try testing.expectEqual(@as(i32, 350), geo.y);

    l.geom = mkBox(450, 0, 100, 100);
    set_layer_dir_animaiton(&l, &geo);
    try testing.expectEqual(@as(i32, 450), geo.x);
    try testing.expectEqual(@as(i32, -100), geo.y);

    l.geom = mkBox(450, 700, 100, 100);
    set_layer_dir_animaiton(&l, &geo);
    try testing.expectEqual(@as(i32, 450), geo.x);
    try testing.expectEqual(@as(i32, 800), geo.y);
}

test "layer shield follows capture and size state" {
    resetAnimWorld();
    var l: LayerSurface = std.mem.zeroes(LayerSurface);
    var shield: c.struct_wlr_scene_rect = std.mem.zeroes(c.struct_wlr_scene_rect);
    l.mapped = 1;
    l.shield = &shield;
    l.geom = mkBox(0, 0, 100, 50);
    l.shield_when_capture = true;

    layer_draw_shield(&l);
    try testing.expectEqual(@as(c_int, 0), stub_enable_calls);

    c.server.active_capture_count = 1;
    layer_draw_shield(&l);
    try testing.expectEqual(@as(c_int, 1), stub_raise_calls);
    try testing.expectEqual(@as(c_int, 100), stub_rect_w);
    try testing.expectEqual(@as(c_int, 50), stub_rect_h);
    try testing.expectEqual(@as(c_int, 1), stub_enabled_value);

    l.geom.width = 0;
    layer_draw_shield(&l);
    try testing.expectEqual(@as(c_int, 0), stub_enabled_value);

    shield.node.enabled = true;
    c.server.active_capture_count = 0;
    layer_draw_shield(&l);
    try testing.expectEqual(@as(c_int, 1), stub_lower_calls);
    try testing.expectEqual(@as(c_int, 0), stub_enabled_value);
}

test "layer shadow shrinks to the layer intersection" {
    resetAnimWorld();
    var l: LayerSurface = std.mem.zeroes(LayerSurface);
    var shadow: c.struct_wlr_scene_shadow = std.mem.zeroes(c.struct_wlr_scene_shadow);
    l.mapped = 1;
    l.shadow = &shadow;
    l.geom = mkBox(0, 0, 100, 50);

    layer_draw_shadow(&l);
    try testing.expectEqual(@as(c_int, 0), stub_shadow_w);

    c.config.shadows = 1;
    c.config.layer_shadows = 0;
    layer_draw_shadow(&l);
    try testing.expectEqual(@as(c_int, 0), stub_shadow_w);

    c.config.layer_shadows = 1;
    c.config.shadows_size = 10;
    c.config.shadows_position_x = -5;
    c.config.shadows_position_y = -5;
    c.config.border_radius = 8;
    layer_draw_shadow(&l);
    try testing.expectEqual(@as(c_int, 120), stub_shadow_w);
    try testing.expectEqual(@as(c_int, 70), stub_shadow_h);
    try testing.expectEqual(@as(i32, -5), stub_pos_x);
    try testing.expectEqual(@as(i32, -5), stub_pos_y);
    try testing.expectEqual(@as(c_int, 1), stub_shadow_clip_calls);
    try testing.expectEqual(@as(i32, 5), stub_shadow_clip.area.x);
    try testing.expectEqual(@as(i32, 5), stub_shadow_clip.area.y);
    try testing.expectEqual(@as(i32, 100), stub_shadow_clip.area.width);
    try testing.expectEqual(@as(i32, 50), stub_shadow_clip.area.height);
    try testing.expectEqual(@as(u16, 8), stub_shadow_clip.corners.top_left);
    try testing.expectEqual(@as(u16, 8), stub_shadow_clip.corners.bottom_right);
}

test "layer buffer effects scale surfaces and fadeout sizes" {
    resetAnimWorld();
    var buffer: c.struct_wlr_scene_buffer = std.mem.zeroes(c.struct_wlr_scene_buffer);
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    var scene_surface: c.struct_wlr_scene_surface = std.mem.zeroes(c.struct_wlr_scene_surface);
    scene_surface.surface = &surface;
    surface.current.width = 200;
    surface.current.height = 100;
    stub_scene_surface_result = &scene_surface;

    var data = std.mem.zeroes(BufferData);
    data.width_scale = 0.5;
    data.height_scale = 0.25;
    layer_scene_buffer_apply_effect(&buffer, 0, 0, &data);
    try testing.expectEqual(@as(c_int, 100), stub_dest_w);
    try testing.expectEqual(@as(c_int, 25), stub_dest_h);

    stub_scene_surface_result = null;
    const before = stub_dest_size_calls;
    layer_scene_buffer_apply_effect(&buffer, 0, 0, &data);
    try testing.expectEqual(before, stub_dest_size_calls);

    data.width = 120;
    data.height = 60;
    layer_fadeout_scene_buffer_apply_effect(&buffer, 0, 0, &data);
    try testing.expectEqual(@as(c_int, 120), stub_dest_w);
    try testing.expectEqual(@as(c_int, 60), stub_dest_h);
}

test "open animation interpolates geometry, opacity and zoom" {
    resetAnimWorld();
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    baseMonitor(&m, &out);
    var ls: c.struct_wlr_layer_surface_v1 = undefined;
    var l: LayerSurface = undefined;
    baseLayer(&l, &m, null, &ls, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    var scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var blur: c.struct_wlr_scene_blur = std.mem.zeroes(c.struct_wlr_scene_blur);
    l.scene = &scene;
    l.blur = &blur;
    l.animation.duration = 100;
    l.animation.time_started = stub_now_ms - 50;
    l.animation.action = c.NONE;
    l.animation.initial = mkBox(0, 0, 100, 50);
    l.animation.current = mkBox(0, 0, 100, 50);
    l.current = mkBox(200, 100, 200, 100);
    l.need_output_flush = true;
    l.animation.running = true;
    stub_curve_factor = 0.5;
    stub_opacity_factor = 0.5;
    c.config.fadein_begin_opacity = 0.2;
    c.config.animation_fade_in = 1;
    c.config.blur = 1;
    c.config.blur_layer = 1;
    c.config.layer_animation_type_open = c.ANIM_TYPE_ZOOM;
    stub_invoke_iterator = 1;
    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    var scene_surface: c.struct_wlr_scene_surface = std.mem.zeroes(c.struct_wlr_scene_surface);
    scene_surface.surface = &surface;
    surface.current.width = 100;
    surface.current.height = 100;
    stub_scene_surface_result = &scene_surface;

    layer_animation_next_tick(&l);
    try testing.expectEqual(@as(i32, 100), stub_pos_x);
    try testing.expectEqual(@as(i32, 50), stub_pos_y);
    try testing.expectEqual(@as(i32, 150), l.animation.current.width);
    try testing.expectEqual(@as(i32, 75), l.animation.current.height);
    try testing.expectApproxEqAbs(@as(f32, 0.6), stub_last_opacity, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.6), stub_blur_strength, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.6), stub_blur_alpha, 1e-6);
    try testing.expectEqual(@as(i32, 150), stub_blur_w);
    try testing.expectEqual(@as(i32, 75), stub_blur_h);
    try testing.expectEqual(@as(c_int, 2), stub_for_each_calls);
    try testing.expectEqual(@as(c_int, 75), stub_dest_w);
    try testing.expectEqual(@as(c_int, 75), stub_dest_h);
    try testing.expect(l.animation.running);

    var l2: LayerSurface = std.mem.zeroes(LayerSurface);
    baseLayer(&l2, &m, &scene, &ls, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    l2.animation.duration = 100;
    l2.animation.time_started = stub_now_ms - 200;
    l2.animation.running = true;
    l2.need_output_flush = true;
    l2.animation.initial = mkBox(0, 0, 10, 10);
    l2.current = mkBox(10, 10, 10, 10);
    l2.animation.current = l2.animation.initial;
    c.config.layer_animation_type_open = c.ANIM_TYPE_NONE;
    stub_curve_factor = 1.0;
    layer_animation_next_tick(&l2);
    try testing.expect(!l2.animation.running);
    try testing.expect(!l2.need_output_flush);
    try testing.expectEqual(@as(i32, c.MOVE), l2.animation.action);
}

test "fadeout tick animates and destroys the snapshot" {
    resetAnimWorld();
    const l: *LayerSurface = @ptrCast(@alignCast(c.ecalloc(1, @sizeOf(LayerSurface)) orelse unreachable));
    var scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    l.scene = &scene;
    l.animation.duration = 100;
    l.animation.time_started = stub_now_ms - 50;
    l.animation.action = c.CLOSE;
    l.animation.initial = mkBox(0, 0, 160, 80);
    l.current = mkBox(80, 40, 240, 120);
    l.animation_type_close = c.ANIM_TYPE_ZOOM;
    stub_curve_factor = 0.5;
    stub_opacity_factor = 0.5;
    c.config.fadeout_begin_opacity = 0.8;
    c.config.animation_fade_out = 1;
    stub_invoke_iterator = 1;

    fadeout_layer_animation_next_tick(l);
    try testing.expectEqual(@as(i32, 40), stub_pos_x);
    try testing.expectEqual(@as(i32, 20), stub_pos_y);
    try testing.expectEqual(@as(i32, 200), l.animation.current.width);
    try testing.expectEqual(@as(i32, 100), l.animation.current.height);
    try testing.expectEqual(@as(i32, 200), stub_dest_w);
    try testing.expectEqual(@as(i32, 100), stub_dest_h);
    try testing.expectApproxEqAbs(@as(f32, 0.4), stub_last_opacity, 1e-6);
    try testing.expectEqual(@as(c_int, 2), stub_for_each_calls);

    const l2: *LayerSurface = @ptrCast(@alignCast(c.ecalloc(1, @sizeOf(LayerSurface)) orelse unreachable));
    l2.scene = &scene;
    l2.animation.duration = 100;
    l2.animation.time_started = stub_now_ms - 200;
    l2.animation.initial = mkBox(0, 0, 10, 10);
    l2.current = mkBox(10, 10, 10, 10);
    stub_curve_factor = 1.0;
    stub_invoke_iterator = 0;
    listInsert(&c.server.fadeout_layers, &l2.fadeout_link);
    fadeout_layer_animation_next_tick(l2);
    try testing.expectEqual(@as(c_int, 1), stub_list_remove_calls);
    try testing.expectEqual(@as(c_int, 1), stub_destroy_calls);
}

test "fadeout layers snapshot close animations with relative targets" {
    resetAnimWorld();
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    baseMonitor(&m, &out);
    var ls: c.struct_wlr_layer_surface_v1 = undefined;
    var l: LayerSurface = undefined;
    var scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var snap: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    baseLayer(&l, &m, &scene, &ls, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    l.animation.current = mkBox(100, 100, 200, 100);
    l.animation_type_close = c.ANIM_TYPE_ZOOM;
    c.config.animations = 1;
    c.config.layer_animations = 1;
    c.config.animation_duration_close = 300;
    c.config.zoom_end_ratio = 0.5;
    stub_snapshot_result = &snap;

    init_fadeout_layers(&l);
    try testing.expectEqual(@as(c_int, 1), stub_snapshot_calls);
    try testing.expectEqual(@as(c_int, 1), stub_list_insert_calls);
    try testing.expectEqual(@as(c_int, 1), stub_schedule_calls);
    try testing.expectEqual(@as(c_int, 3), stub_enable_calls);

    const fadeout = @as(*LayerSurface, @ptrFromInt(@intFromPtr(c.server.fadeout_layers.next) - @offsetOf(LayerSurface, "fadeout_link")));
    try testing.expectEqual(@as(u32, 300), fadeout.animation.duration);
    try testing.expectEqual(@as(i32, c.CLOSE), fadeout.animation.action);
    try testing.expectEqual(@as(i32, 100), fadeout.current.width);
    try testing.expectEqual(@as(i32, 50), fadeout.current.height);
    try testing.expectEqual(@as(i32, 350), fadeout.current.x);
    try testing.expectEqual(@as(i32, 275), fadeout.current.y);
    try testing.expectEqual(@as(i32, 0), fadeout.animation.initial.x);
    try testing.expectEqual(@as(i32, 100), fadeout.geom.x);

    listInit(&c.server.fadeout_layers);
    stub_list_insert_calls = 0;
    c.config.animations = 0;
    init_fadeout_layers(&l);
    try testing.expectEqual(@as(c_int, 0), stub_list_insert_calls);

    c.config.animations = 1;
    l.shield_when_capture = true;
    init_fadeout_layers(&l);
    try testing.expectEqual(@as(c_int, 0), stub_list_insert_calls);
    l.shield_when_capture = false;

    ls.current.layer = @intCast(c.ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM);
    init_fadeout_layers(&l);
    try testing.expectEqual(@as(c_int, 0), stub_list_insert_calls);
    ls.current.layer = @intCast(c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);

    stub_snapshot_result = null;
    init_fadeout_layers(&l);
    try testing.expectEqual(@as(c_int, 0), stub_list_insert_calls);

    var slide_scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var slide_snap: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var slide_l: LayerSurface = std.mem.zeroes(LayerSurface);
    var slide_ls: c.struct_wlr_layer_surface_v1 = std.mem.zeroes(c.struct_wlr_layer_surface_v1);
    slide_ls.initialized = true;
    slide_ls.current.layer = @intCast(c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    slide_ls.current.exclusive_zone = 0;
    slide_l.mon = &m;
    slide_l.scene = &slide_scene;
    slide_l.layer_surface = &slide_ls;
    slide_l.mapped = 1;
    slide_l.geom = mkBox(0, 350, 100, 100);
    slide_l.animation.current = mkBox(0, 350, 100, 100);
    slide_l.animation_type_close = c.ANIM_TYPE_SLIDE;
    stub_snapshot_result = &slide_snap;
    listInit(&c.server.fadeout_layers);
    stub_list_insert_calls = 0;
    init_fadeout_layers(&slide_l);
    try testing.expectEqual(@as(c_int, 1), stub_list_insert_calls);
    const slide_fade = @as(*LayerSurface, @ptrFromInt(@intFromPtr(c.server.fadeout_layers.next) - @offsetOf(LayerSurface, "fadeout_link")));
    try testing.expectEqual(@as(i32, -100), slide_fade.current.x);
    try testing.expectEqual(@as(i32, 0), slide_fade.current.y);
    try testing.expectEqual(@as(i32, 0), slide_fade.current.width);
    try testing.expectEqual(@as(i32, 0), slide_fade.current.height);
}

test "pending state branches and commit start the animation" {
    resetAnimWorld();
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    baseMonitor(&m, &out);
    var ls: c.struct_wlr_layer_surface_v1 = undefined;
    var l: LayerSurface = undefined;
    var scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    baseLayer(&l, &m, &scene, &ls, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    ls.current.exclusive_zone = 0;
    l.geom = mkBox(100, 100, 200, 100);
    l.pending = l.geom;
    l.current = l.geom;
    l.animation.current = l.geom;
    l.animation.action = c.OPEN;
    l.animation.duration = 100;
    c.config.animations = 1;
    c.config.layer_animations = 1;
    c.config.layer_animation_type_open = c.ANIM_TYPE_ZOOM;
    c.config.zoom_initial_ratio = 0.5;

    layer_set_pending_state(&l);
    try testing.expectEqual(@as(i32, 450), l.animainit_geom.x);
    try testing.expectEqual(@as(i32, 375), l.animainit_geom.y);
    try testing.expectEqual(@as(i32, 100), l.animainit_geom.width);
    try testing.expectEqual(@as(i32, 50), l.animainit_geom.height);
    try testing.expect(l.animation.running);
    try testing.expect(!l.animation.should_animate);
    try testing.expect(l.dirty);
    try testing.expectEqual(l.geom.width, l.current.width);
    try testing.expectEqual(@as(c_int, 1), stub_schedule_calls);

    var l2: LayerSurface = undefined;
    baseLayer(&l2, &m, &scene, &ls, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    l2.animation.action = c.OPEN;
    l2.animation.duration = 0;
    layer_set_pending_state(&l2);
    try testing.expectEqual(l2.geom.width, l2.animainit_geom.width);

    var l3: LayerSurface = undefined;
    baseLayer(&l3, &m, &scene, &ls, c.ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND);
    l3.animation.action = c.OPEN;
    layer_set_pending_state(&l3);
    try testing.expect(!l3.animation.should_animate);

    var l4: LayerSurface = undefined;
    baseLayer(&l4, &m, &scene, &ls, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    l4.animation.action = c.OPEN;
    c.config.layer_animation_type_open = c.ANIM_TYPE_NONE;
    layer_set_pending_state(&l4);
    try testing.expect(!l4.animation.should_animate);

    var l5: LayerSurface = undefined;
    baseLayer(&l5, &m, &scene, &ls, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    ls.current.exclusive_zone = 0;
    l5.geom = mkBox(0, 350, 100, 100);
    l5.animation.action = c.OPEN;
    c.config.layer_animation_type_open = c.ANIM_TYPE_SLIDE;
    layer_set_pending_state(&l5);
    try testing.expectEqual(@as(i32, -100), l5.animainit_geom.x);
    try testing.expectEqual(@as(i32, 350), l5.animainit_geom.y);
}

test "layer draw frame gates by layer kind and flush state" {
    resetAnimWorld();
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    baseMonitor(&m, &out);
    var ls: c.struct_wlr_layer_surface_v1 = undefined;
    var l: LayerSurface = undefined;
    var scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    baseLayer(&l, &m, &scene, &ls, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    l.need_output_flush = true;
    l.animation.running = true;
    l.animation.duration = 0;
    l.animation.initial = l.geom;
    l.animation.current = l.geom;
    c.config.animations = 1;
    c.config.layer_animations = 1;
    stub_curve_factor = 1.0;
    try testing.expect(layer_draw_frame(&l));
    try testing.expect(!l.need_output_flush);
    try testing.expect(!l.animation.running);

    var l2: LayerSurface = undefined;
    baseLayer(&l2, &m, &scene, &ls, c.ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM);
    l2.need_output_flush = true;
    try testing.expect(!layer_draw_frame(&l2));

    var l3: LayerSurface = undefined;
    baseLayer(&l3, &m, &scene, &ls, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    l3.need_output_flush = false;
    try testing.expect(!layer_draw_frame(&l3));

    var l4: LayerSurface = undefined;
    baseLayer(&l4, &m, &scene, &ls, c.ZWLR_LAYER_SHELL_V1_LAYER_TOP);
    l4.mapped = 0;
    try testing.expect(!layer_draw_frame(&l4));

    const l5: *LayerSurface = @ptrCast(@alignCast(c.ecalloc(1, @sizeOf(LayerSurface)) orelse unreachable));
    l5.scene = &scene;
    l5.animation.duration = 0;
    stub_curve_factor = 1.0;
    listInsert(&c.server.fadeout_layers, &l5.fadeout_link);
    try testing.expect(layer_draw_fadeout_frame(l5));
}
