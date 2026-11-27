//! Port of animation/client.c (Phase 5, animation slice 1, slice 87).

const std = @import("std");
const c = @import("cc");
const build_options = @import("build_options");

const Client = c.Client;
const Monitor = c.Monitor;

extern fn client_gesture_driven(c: [*c]const Client) callconv(.c) bool;
extern fn get_mon_curtag(m: [*c]const Monitor) callconv(.c) u32;
extern fn is_scroller_layout(m: [*c]Monitor) callconv(.c) bool;
extern fn overview_card_set_corner_radii(cl: [*c]Client, corners: c.struct_fx_corner_radii) callconv(.c) void;
extern fn wlr_scene_node_for_each_buffer(node: [*c]c.struct_wlr_scene_node, iterator: *const fn ([*c]c.struct_wlr_scene_buffer, i32, i32, ?*anyopaque) callconv(.c) void, user_data: ?*anyopaque) callconv(.c) void;

fn gez(val: i32) i32 {
    return if (val >= 0) val else 0;
}

fn openAnimationType(cl: *const Client) i32 {
    return if (cl.animation_type_open != c.ANIM_TYPE_UNSET)
        cl.animation_type_open
    else
        c.config.animation_type_open;
}

fn closeAnimationType(cl: *const Client) i32 {
    return if (cl.animation_type_close != c.ANIM_TYPE_UNSET)
        cl.animation_type_close
    else
        c.config.animation_type_close;
}

fn isScrollTiled(cl: *const Client) bool {
    return cl.isfloating == 0 and cl.isminimized == 0 and cl.iskilling == 0 and
        cl.isunglobal == 0;
}

export fn client_animations_enabled(cl: [*c]const Client) callconv(.c) bool {
    if (cl != null and cl.*.no_animation != 0)
        return false;
    if (c.config.animations != 0)
        return true;
    return client_gesture_driven(cl);
}

export fn client_is_ignore_output_clip(cl: [*c]Client) callconv(.c) bool {
    return cl == c.server.grab_client or
        (!isScrollTiled(cl) and !cl.*.animation.tagining and
            !cl.*.animation.tagouting);
}

export fn compute_edge_offsets(cl: [*c]Client) callconv(.c) c.struct_ivec2 {
    var offsets = std.mem.zeroes(c.struct_ivec2);
    if (client_is_ignore_output_clip(cl))
        return offsets;

    const cur = cl.*.animation.current;
    const mon = cl.*.mon;
    offsets.width = gez(cur.x + cur.width - mon.*.m.x - mon.*.m.width); // right
    offsets.height = gez(cur.y + cur.height - mon.*.m.y - mon.*.m.height); // bottom
    offsets.x = gez(mon.*.m.x - cur.x); // left
    offsets.y = gez(mon.*.m.y - cur.y); // top
    return offsets;
}

export fn client_actual_size(cl: [*c]Client, width: [*c]i32, height: [*c]i32) callconv(.c) void {
    width.* = cl.*.animation.current.width - 2 * @as(i32, @intCast(cl.*.bw));
    height.* = cl.*.animation.current.height - 2 * @as(i32, @intCast(cl.*.bw));
}

export fn set_rect_size(rect: [*c]c.struct_wlr_scene_rect, width: i32, height: i32) callconv(.c) void {
    c.wlr_scene_rect_set_size(rect, gez(width), gez(height));
}

export fn set_client_corner_location(cl: [*c]Client) callconv(.c) c.struct_fx_corner_radii {
    var current_corner_location = c.corner_radii_all(c.config.border_radius);

    if (client_is_ignore_output_clip(cl))
        return current_corner_location;

    const target_geom = if (client_animations_enabled(cl))
        cl.*.animation.current
    else
        cl.*.geom;
    const mon = cl.*.mon.*;
    if (target_geom.x + c.config.border_radius <= mon.m.x) {
        current_corner_location.top_left = 0;
        current_corner_location.bottom_left = 0;
    }
    if (target_geom.x + target_geom.width - c.config.border_radius >=
        mon.m.x + mon.m.width)
    {
        current_corner_location.top_right = 0;
        current_corner_location.bottom_right = 0;
    }
    if (target_geom.y + c.config.border_radius <= mon.m.y) {
        current_corner_location.top_left = 0;
        current_corner_location.top_right = 0;
    }
    if (target_geom.y + target_geom.height - c.config.border_radius >=
        mon.m.y + mon.m.height)
    {
        current_corner_location.bottom_left = 0;
        current_corner_location.bottom_right = 0;
    }
    return current_corner_location;
}

export fn is_horizontal_stack_layout(m: [*c]Monitor) callconv(.c) bool {
    const tag = get_mon_curtag(m);
    const id = m.*.pertag.*.ltidxs[tag].*.id;
    return id == c.TILE or id == c.DECK;
}

export fn is_horizontal_right_stack_layout(m: [*c]Monitor) callconv(.c) bool {
    const tag = get_mon_curtag(m);
    return m.*.pertag.*.ltidxs[tag].*.id == c.RIGHT_TILE;
}

export fn is_special_animation_rule(cl: [*c]Client) callconv(.c) i32 {
    if (is_scroller_layout(cl.*.mon) and cl.*.isfloating == 0) {
        return c.DOWN;
    } else if (cl.*.mon.*.visible_tiling_clients == 1 and cl.*.isfloating == 0) {
        return c.DOWN;
    } else if (cl.*.mon.*.visible_tiling_clients == 2 and cl.*.isfloating == 0 and
        c.config.new_is_master == 0 and is_horizontal_stack_layout(cl.*.mon))
    {
        return c.RIGHT;
    } else if (cl.*.isfloating == 0 and c.config.new_is_master != 0 and
        is_horizontal_stack_layout(cl.*.mon))
    {
        return c.LEFT;
    } else if (cl.*.mon.*.visible_tiling_clients == 2 and cl.*.isfloating == 0 and
        c.config.new_is_master == 0 and is_horizontal_right_stack_layout(cl.*.mon))
    {
        return c.LEFT;
    } else if (cl.*.isfloating == 0 and c.config.new_is_master != 0 and
        is_horizontal_right_stack_layout(cl.*.mon))
    {
        return c.RIGHT;
    } else {
        return c.UNDIR;
    }
}

export fn set_overview_enter_animation(cl: [*c]Client) callconv(.c) void {
    var start = cl.*.overview_backup_geom;
    if (start.width <= 0 or start.height <= 0)
        start = cl.*.animation.current;
    cl.*.animainit_geom = start;
}

export fn set_client_open_animation(cl: [*c]Client, geo: c.struct_wlr_box) callconv(.c) void {
    const anim_type = openAnimationType(cl);

    if (anim_type == c.ANIM_TYPE_NONE or cl.*.animation.duration == 0) {
        cl.*.animainit_geom = geo;
        return;
    } else if (anim_type == c.ANIM_TYPE_FADE) {
        cl.*.animainit_geom.width = geo.width;
        cl.*.animainit_geom.height = geo.height;
        cl.*.animainit_geom.x = geo.x;
        cl.*.animainit_geom.y = geo.y;
        return;
    } else if (anim_type == c.ANIM_TYPE_ZOOM) {
        cl.*.animainit_geom.width = @intFromFloat(@as(f32, @floatFromInt(geo.width)) * c.config.zoom_initial_ratio);
        cl.*.animainit_geom.height = @intFromFloat(@as(f32, @floatFromInt(geo.height)) * c.config.zoom_initial_ratio);
        cl.*.animainit_geom.x = geo.x + @divTrunc(geo.width - cl.*.animainit_geom.width, 2);
        cl.*.animainit_geom.y = geo.y + @divTrunc(geo.height - cl.*.animainit_geom.height, 2);
        return;
    } else {
        const special_direction = is_special_animation_rule(cl);
        const center_x = cl.*.geom.x + @divTrunc(cl.*.geom.width, 2);
        const center_y = cl.*.geom.y + @divTrunc(cl.*.geom.height, 2);
        var slide_direction: i32 = undefined;
        if (special_direction == c.UNDIR) {
            const mon_w = cl.*.mon.*.w;
            const horizontal: i32 = if (mon_w.x + mon_w.width - center_x < center_x - mon_w.x)
                c.RIGHT
            else
                c.LEFT;
            const horizontal_value: i32 = if (horizontal == c.LEFT)
                center_x - mon_w.x
            else
                mon_w.x + mon_w.width - center_x;
            const vertical: i32 = if (mon_w.y + mon_w.height - center_y < center_y - mon_w.y)
                c.DOWN
            else
                c.UP;
            const vertical_value: i32 = if (vertical == c.UP)
                center_y - mon_w.y
            else
                mon_w.y + mon_w.height - center_y;
            slide_direction = if (horizontal_value < vertical_value) horizontal else vertical;
        } else {
            slide_direction = special_direction;
        }
        cl.*.animainit_geom.width = cl.*.geom.width;
        cl.*.animainit_geom.height = cl.*.geom.height;
        const mon = cl.*.mon.*;
        switch (slide_direction) {
            c.UP => {
                cl.*.animainit_geom.x = cl.*.geom.x;
                cl.*.animainit_geom.y = mon.m.y - cl.*.geom.height;
            },
            c.DOWN => {
                cl.*.animainit_geom.x = cl.*.geom.x;
                cl.*.animainit_geom.y = cl.*.geom.y + mon.m.height - (cl.*.geom.y - mon.m.y);
            },
            c.LEFT => {
                cl.*.animainit_geom.x = mon.m.x - cl.*.geom.width;
                cl.*.animainit_geom.y = cl.*.geom.y;
            },
            c.RIGHT => {
                cl.*.animainit_geom.x = cl.*.geom.x + mon.m.width - (cl.*.geom.x - mon.m.x);
                cl.*.animainit_geom.y = cl.*.geom.y;
            },
            else => {
                cl.*.animainit_geom.x = cl.*.geom.x;
                cl.*.animainit_geom.y = 0 - cl.*.geom.height;
            },
        }
    }
}

export fn snap_scene_buffer_apply_effect(buffer: [*c]c.struct_wlr_scene_buffer, sx: i32, sy: i32, data: ?*anyopaque) callconv(.c) void {
    _ = sx;
    _ = sy;
    const buffer_data: *c.BufferData = @ptrCast(@alignCast(data));
    c.wlr_scene_buffer_set_dest_size(buffer, buffer_data.width, buffer_data.height);
}

export fn scene_buffer_apply_effect(buffer: [*c]c.struct_wlr_scene_buffer, sx: i32, sy: i32, data: ?*anyopaque) callconv(.c) void {
    _ = sx;
    _ = sy;
    const buffer_data: *c.BufferData = @ptrCast(@alignCast(data));

    if (buffer_data.should_scale and buffer_data.height_scale < 1 and
        buffer_data.width_scale < 1)
        buffer_data.should_scale = false;

    if (buffer_data.should_scale and buffer_data.height_scale == 1 and
        buffer_data.width_scale < 1)
        buffer_data.should_scale = false;

    if (buffer_data.should_scale and buffer_data.height_scale < 1 and
        buffer_data.width_scale == 1)
        buffer_data.should_scale = false;

    const scene_surface = c.wlr_scene_surface_try_from_buffer(buffer);
    if (scene_surface == null)
        return;

    const surface = scene_surface.*.surface;

    if (buffer_data.should_scale and
        (!build_options.xwayland or c.wlr_xwayland_surface_try_from_wlr_surface(surface) == null))
    {
        var surface_width = surface.*.current.width;
        var surface_height = surface.*.current.height;

        surface_width = if (buffer_data.width_scale < 1)
            surface_width
        else
            @intFromFloat(buffer_data.width_scale * @as(f32, @floatFromInt(surface_width)));
        surface_height = if (buffer_data.height_scale < 1)
            surface_height
        else
            @intFromFloat(buffer_data.height_scale * @as(f32, @floatFromInt(surface_height)));

        if (surface_width > buffer_data.width and
            c.wlr_subsurface_try_from_wlr_surface(surface) == null)
            surface_width = buffer_data.width;

        if (surface_height > buffer_data.height and
            c.wlr_subsurface_try_from_wlr_surface(surface) == null)
            surface_height = buffer_data.height;

        if (surface_width > buffer_data.width and
            c.wlr_subsurface_try_from_wlr_surface(surface) != null)
            return;

        if (surface_height > buffer_data.height and
            c.wlr_subsurface_try_from_wlr_surface(surface) != null)
            return;

        if (surface_height > 0 and surface_width > 0)
            c.wlr_scene_buffer_set_dest_size(buffer, surface_width, surface_height);
    }

    if (c.wlr_xdg_popup_try_from_wlr_surface(surface) != null)
        return;

    c.wlr_scene_buffer_set_corner_radii(buffer, buffer_data.corner_location);
}

export fn buffer_set_effect(cl: [*c]Client, data: c.BufferData) callconv(.c) void {
    var effect = data;
    if (cl == null or cl.*.iskilling != 0)
        return;

    if (cl.*.animation.tagouting or cl.*.animation.tagouted or
        cl.*.animation.tagining)
        effect.should_scale = false;

    if (cl == c.server.grab_client)
        effect.should_scale = false;

    if (cl.*.isfullscreen != 0 or (c.config.no_radius_when_single != 0 and cl.*.mon != null and
        cl.*.mon.*.visible_tiling_clients == 1))
        effect.corner_location = c.corner_radii_none();

    if (c.config.blur != 0 and cl.*.no_blur == 0)
        c.wlr_scene_blur_set_corner_radii(cl.*.blur, effect.corner_location);

    // Overview cards get rounded corners directly.
    if (cl.*.ov_card_tree != null) {
        overview_card_set_corner_radii(cl, effect.corner_location);
        return;
    }

    wlr_scene_node_for_each_buffer(&cl.*.scene_surface.*.node, scene_buffer_apply_effect, &effect);
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/animation_client_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_gesture: c_int;
extern var stub_scroller: c_int;
extern var stub_card_radii_calls: c_int;
extern var stub_card_radii: c.struct_fx_corner_radii;
extern var stub_rect_w: c_int;
extern var stub_rect_h: c_int;
extern var stub_dest_size_calls: c_int;
extern var stub_dest_w: c_int;
extern var stub_dest_h: c_int;
extern var stub_buffer_radii_calls: c_int;
extern var stub_buffer_radii: c.struct_fx_corner_radii;
extern var stub_blur_radii_calls: c_int;
extern var stub_for_each_calls: c_int;
extern var stub_iterate: c_int;
extern var stub_scene_buffer: [*c]c.struct_wlr_scene_buffer;
extern var stub_scene_surface: [*c]c.struct_wlr_scene_surface;
extern var stub_subsurface: [*c]c.struct_wlr_subsurface;
extern var stub_popup: [*c]c.struct_wlr_xdg_popup;

var test_client: Client = undefined;
var test_mon: Monitor = undefined;
var test_pertag: c.Pertag = undefined;
var test_layouts: [4]c.Layout = undefined;
var test_surface: c.struct_wlr_surface = undefined;
var test_scene_surface: c.struct_wlr_scene_surface = undefined;
var test_rect: c.struct_wlr_scene_rect = undefined;
var test_blur: c.struct_wlr_scene_blur = undefined;
var test_scene_surface_node: c.struct_wlr_scene_tree = undefined;

fn resetWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    test_client = std.mem.zeroes(Client);
    test_mon = std.mem.zeroes(Monitor);
    test_pertag = std.mem.zeroes(c.Pertag);
    test_layouts = std.mem.zeroes([4]c.Layout);
    test_surface = std.mem.zeroes(c.struct_wlr_surface);
    test_scene_surface = std.mem.zeroes(c.struct_wlr_scene_surface);
    test_rect = std.mem.zeroes(c.struct_wlr_scene_rect);
    test_blur = std.mem.zeroes(c.struct_wlr_scene_blur);
    test_scene_surface_node = std.mem.zeroes(c.struct_wlr_scene_tree);
    test_mon.pertag = &test_pertag;
    test_pertag.ltidxs[0] = &test_layouts[0];
    test_client.mon = &test_mon;
    test_client.bw = 2;
    test_client.animation_type_open = c.ANIM_TYPE_UNSET;
    test_client.animation_type_close = c.ANIM_TYPE_UNSET;
    test_client.animation.current = .{ .x = 0, .y = 0, .width = 100, .height = 80 };
    test_client.animation.duration = 300;
    test_client.geom = test_client.animation.current;
    test_scene_surface.surface = &test_surface;
    test_client.scene_surface = &test_scene_surface_node;
    test_client.blur = &test_blur;
    stub_gesture = 0;
    stub_scroller = 0;
    stub_card_radii_calls = 0;
    stub_card_radii = std.mem.zeroes(c.struct_fx_corner_radii);
    stub_rect_w = -1;
    stub_rect_h = -1;
    stub_dest_size_calls = 0;
    stub_dest_w = 0;
    stub_dest_h = 0;
    stub_buffer_radii_calls = 0;
    stub_buffer_radii = std.mem.zeroes(c.struct_fx_corner_radii);
    stub_blur_radii_calls = 0;
    stub_for_each_calls = 0;
    stub_iterate = 0;
    stub_scene_buffer = @ptrFromInt(0x1000);
    stub_scene_surface = &test_scene_surface;
    stub_subsurface = null;
    stub_popup = null;
}

test "animations enabled follows config, per-client opt-out and gestures" {
    resetWorld();
    try testing.expect(!client_animations_enabled(&test_client));
    stub_gesture = 1;
    try testing.expect(client_animations_enabled(&test_client));
    c.config.animations = 1;
    try testing.expect(client_animations_enabled(&test_client));
    test_client.no_animation = 1;
    try testing.expect(!client_animations_enabled(&test_client));
    try testing.expect(client_animations_enabled(null));
    c.config.animations = 0;
    try testing.expect(client_animations_enabled(null));
    stub_gesture = 0;
    try testing.expect(!client_animations_enabled(null));
}

test "output clip is ignored for grabs and non-scrolltag animations" {
    resetWorld();
    try testing.expect(!client_is_ignore_output_clip(&test_client));
    test_client.isfloating = 1;
    try testing.expect(client_is_ignore_output_clip(&test_client));
    test_client.animation.tagining = true;
    try testing.expect(!client_is_ignore_output_clip(&test_client));
    test_client.animation.tagining = false;
    c.server.grab_client = &test_client;
    try testing.expect(client_is_ignore_output_clip(&test_client));
}

test "edge offsets clip the window against the monitor box" {
    resetWorld();
    test_mon.m = .{ .x = 100, .y = 100, .width = 800, .height = 600 };
    test_client.animation.current = .{ .x = 90, .y = 80, .width = 100, .height = 100 };
    const offsets = compute_edge_offsets(&test_client);
    try testing.expectEqual(@as(i32, 10), offsets.x);
    try testing.expectEqual(@as(i32, 20), offsets.y);
    try testing.expectEqual(@as(i32, 0), offsets.width);
    try testing.expectEqual(@as(i32, 0), offsets.height);

    test_client.animation.current = .{ .x = 800, .y = 650, .width = 200, .height = 100 };
    const over = compute_edge_offsets(&test_client);
    try testing.expectEqual(@as(i32, 100), over.width);
    try testing.expectEqual(@as(i32, 50), over.height);
    try testing.expectEqual(@as(i32, 0), over.x);
}

test "actual size subtracts both borders" {
    resetWorld();
    var w: i32 = 0;
    var h: i32 = 0;
    client_actual_size(&test_client, &w, &h);
    try testing.expectEqual(@as(i32, 96), w);
    try testing.expectEqual(@as(i32, 76), h);
}

test "set_rect_size clamps negative sizes" {
    resetWorld();
    set_rect_size(&test_rect, -5, 12);
    try testing.expectEqual(@as(c_int, 0), stub_rect_w);
    try testing.expectEqual(@as(c_int, 12), stub_rect_h);
}

test "corner location rounds corners only where the window is inset" {
    resetWorld();
    c.config.border_radius = 10;
    test_mon.m = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
    test_client.geom = .{ .x = -20, .y = -20, .width = 1040, .height = 840 };
    test_client.animation.current = test_client.geom;
    test_client.animation.duration = 1;
    c.config.animations = 1;
    const corners = set_client_corner_location(&test_client);
    try testing.expectEqual(@as(i32, 0), corners.top_left);
}

test "stack layout detection follows the active layout id" {
    resetWorld();
    test_layouts[0].id = c.TILE;
    try testing.expect(is_horizontal_stack_layout(&test_mon));
    try testing.expect(!is_horizontal_right_stack_layout(&test_mon));
    test_layouts[0].id = c.DECK;
    try testing.expect(is_horizontal_stack_layout(&test_mon));
    test_layouts[0].id = c.RIGHT_TILE;
    try testing.expect(!is_horizontal_stack_layout(&test_mon));
    try testing.expect(is_horizontal_right_stack_layout(&test_mon));
}

test "special animation rule picks the slide direction" {
    resetWorld();
    stub_scroller = 1;
    try testing.expectEqual(c.DOWN, is_special_animation_rule(&test_client));
    stub_scroller = 0;
    test_mon.visible_tiling_clients = 1;
    try testing.expectEqual(c.DOWN, is_special_animation_rule(&test_client));
    test_mon.visible_tiling_clients = 2;
    test_layouts[0].id = c.TILE;
    try testing.expectEqual(c.RIGHT, is_special_animation_rule(&test_client));
    c.config.new_is_master = 1;
    try testing.expectEqual(c.LEFT, is_special_animation_rule(&test_client));
    test_layouts[0].id = c.RIGHT_TILE;
    try testing.expectEqual(c.RIGHT, is_special_animation_rule(&test_client));
    c.config.new_is_master = 0;
    try testing.expectEqual(c.LEFT, is_special_animation_rule(&test_client));
    test_client.isfloating = 1;
    try testing.expectEqual(c.UNDIR, is_special_animation_rule(&test_client));
}

test "overview enter uses the backup geometry when available" {
    resetWorld();
    test_client.overview_backup_geom = .{ .x = 1, .y = 2, .width = 30, .height = 40 };
    test_client.animation.current = .{ .x = 9, .y = 9, .width = 9, .height = 9 };
    set_overview_enter_animation(&test_client);
    try testing.expectEqual(@as(i32, 30), test_client.animainit_geom.width);
    test_client.overview_backup_geom.width = 0;
    set_overview_enter_animation(&test_client);
    try testing.expectEqual(@as(i32, 9), test_client.animainit_geom.width);
}

test "open animation handles none, fade and zoom" {
    resetWorld();
    const geo = c.struct_wlr_box{ .x = 10, .y = 20, .width = 100, .height = 50 };

    c.config.animation_type_open = c.ANIM_TYPE_NONE;
    set_client_open_animation(&test_client, geo);
    try testing.expectEqual(@as(i32, 100), test_client.animainit_geom.width);

    c.config.animation_type_open = c.ANIM_TYPE_FADE;
    set_client_open_animation(&test_client, geo);
    try testing.expectEqual(@as(i32, 10), test_client.animainit_geom.x);

    c.config.animation_type_open = c.ANIM_TYPE_ZOOM;
    c.config.zoom_initial_ratio = 0.5;
    set_client_open_animation(&test_client, geo);
    try testing.expectEqual(@as(i32, 50), test_client.animainit_geom.width);
    try testing.expectEqual(@as(i32, 25), test_client.animainit_geom.height);
    try testing.expectEqual(@as(i32, 35), test_client.animainit_geom.x);
    try testing.expectEqual(@as(i32, 32), test_client.animainit_geom.y);
}

test "open animation slides from the nearest edge or special direction" {
    resetWorld();
    c.config.animation_type_open = c.ANIM_TYPE_SLIDE;
    test_mon.m = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
    test_mon.w = test_mon.m;
    test_client.geom = .{ .x = 100, .y = 100, .width = 200, .height = 100 };
    test_client.animation.current = test_client.geom;

    // Center distances: left 200, right 800, top 150, bottom 650 -> UP.
    set_client_open_animation(&test_client, test_client.geom);
    try testing.expectEqual(@as(i32, 100), test_client.animainit_geom.x);
    try testing.expectEqual(@as(i32, -100), test_client.animainit_geom.y);

    // A scroller layout forces DOWN.
    stub_scroller = 1;
    set_client_open_animation(&test_client, test_client.geom);
    try testing.expectEqual(@as(i32, 100), test_client.animainit_geom.x);
    try testing.expectEqual(@as(i32, 800), test_client.animainit_geom.y);
}

test "snap and scene buffer effects resize and round surfaces" {
    resetWorld();
    var data = std.mem.zeroes(c.BufferData);
    data.width = 120;
    data.height = 60;
    snap_scene_buffer_apply_effect(stub_scene_buffer, 0, 0, &data);
    try testing.expectEqual(@as(c_int, 1), stub_dest_size_calls);
    try testing.expectEqual(@as(c_int, 120), stub_dest_w);

    data = std.mem.zeroes(c.BufferData);
    data.should_scale = true;
    data.width_scale = 1.5;
    data.height_scale = 1.5;
    data.width = 200;
    data.height = 100;
    data.corner_location = c.corner_radii_all(7);
    test_surface.current.width = 100;
    test_surface.current.height = 50;
    scene_buffer_apply_effect(stub_scene_buffer, 0, 0, &data);
    try testing.expectEqual(@as(c_int, 150), stub_dest_w);
    try testing.expectEqual(@as(c_int, 75), stub_dest_h);
    try testing.expectEqual(@as(c_int, 1), stub_buffer_radii_calls);
    try testing.expectEqual(@as(i32, 7), stub_buffer_radii.top_left);
}

test "popups skip corner rounding and oversized subsurfaces bail out" {
    resetWorld();
    var data = std.mem.zeroes(c.BufferData);
    data.corner_location = c.corner_radii_all(5);
    test_surface.current.width = 50;
    test_surface.current.height = 50;
    stub_popup = @ptrFromInt(0x2000);
    scene_buffer_apply_effect(stub_scene_buffer, 0, 0, &data);
    try testing.expectEqual(@as(c_int, 0), stub_buffer_radii_calls);

    stub_popup = null;
    data.should_scale = true;
    data.width_scale = 2;
    data.height_scale = 2;
    data.width = 10;
    data.height = 10;
    stub_subsurface = @ptrFromInt(0x3000);
    scene_buffer_apply_effect(stub_scene_buffer, 0, 0, &data);
    try testing.expectEqual(@as(c_int, 0), stub_dest_size_calls);
    try testing.expectEqual(@as(c_int, 0), stub_buffer_radii_calls);
}

test "buffer effects route overview cards and blur corners" {
    resetWorld();
    c.config.blur = 1;
    var data = std.mem.zeroes(c.BufferData);
    data.corner_location = c.corner_radii_all(4);
    test_client.ov_card_tree = @ptrFromInt(0x4000);
    buffer_set_effect(&test_client, data);
    try testing.expectEqual(@as(c_int, 1), stub_card_radii_calls);
    try testing.expectEqual(@as(c_int, 1), stub_blur_radii_calls);
    try testing.expectEqual(@as(c_int, 0), stub_for_each_calls);

    resetWorld();
    test_client.animation.tagining = true;
    stub_iterate = 1;
    buffer_set_effect(&test_client, data);
    try testing.expectEqual(@as(c_int, 1), stub_for_each_calls);
    try testing.expectEqual(@as(c_int, 0), stub_dest_size_calls);
    try testing.expectEqual(@as(c_int, 1), stub_buffer_radii_calls);
}
