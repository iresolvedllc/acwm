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
extern var stub_rect_call_count: c_int;
extern var stub_rect_call_w: [16]c_int;
extern var stub_rect_call_h: [16]c_int;
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
    test_client.tags = 1;
    test_mon.tagset[0] = 1;
    test_mon.seltags = 0;
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
    stub_rect_call_count = 0;
    stub_rect_call_w = std.mem.zeroes([16]c_int);
    stub_rect_call_h = std.mem.zeroes([16]c_int);
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

// ---------------------------------------------------------------------------
// draw helpers (slice 88)
// ---------------------------------------------------------------------------

extern fn client_surface(cl: [*c]Client) callconv(.c) [*c]c.struct_wlr_surface;
extern fn check_hit_no_border(cl: [*c]Client) callconv(.c) bool;
extern fn client_wants_group_bar(cl: [*c]Client) callconv(.c) bool;
extern fn client_group_head(cl: [*c]Client) callconv(.c) [*c]Client;
extern fn client_check_tab_node_visible(cl: [*c]Client) callconv(.c) void;
extern fn client_update_visibility(cl: [*c]Client) callconv(.c) void;
extern fn get_client_tag_idx(cl: [*c]const Client) callconv(.c) u32;
extern fn dwindle_find_leaf(node: [*c]c.DwindleNode, cl: [*c]Client) callconv(.c) [*c]c.DwindleNode;
extern fn acwm_dim_node_set_enabled(node: [*c]c.AcwmDimNode, enabled: bool) callconv(.c) void;
extern fn acwm_dim_node_set_radius(node: [*c]c.AcwmDimNode, radius: i32) callconv(.c) void;
extern fn acwm_dim_node_set_box(node: [*c]c.AcwmDimNode, x: i32, y: i32, width: i32, height: i32) callconv(.c) void;
extern fn acwm_bar_decoration_set_size(node: [*c]c.AcwmBarDecoration, width: i32, height: i32) callconv(.c) void;

fn isTiled(cl: *const Client) bool {
    return cl.isfloating == 0 and cl.isminimized == 0 and cl.iskilling == 0 and
        cl.ismaximizescreen == 0 and cl.isfullscreen == 0 and cl.isunglobal == 0;
}

fn visibleOn(cl: *const Client, m: *const Monitor) bool {
    return cl.mon == m and cl.isminimized == 0 and
        ((cl.tags & m.tagset[@intCast(m.seltags)]) != 0 or
            cl.isglobal != 0 or cl.isunglobal != 0);
}

fn setRectSize(rect: [*c]c.struct_wlr_scene_rect, width: i32, height: i32) void {
    c.wlr_scene_rect_set_size(rect, gez(width), gez(height));
}

export fn client_draw_shadow(cl: [*c]Client, offsets: c.struct_ivec2) callconv(.c) void {
    _ = offsets;
    if (cl.*.iskilling != 0 or !client_surface(cl).*.mapped or cl.*.no_shadow != 0)
        return;

    if (c.config.shadows == 0 or cl.*.isfullscreen != 0 or
        (cl.*.isfloating == 0 and c.config.shadow_only_floating != 0))
    {
        if (cl.*.shadow.*.node.enabled)
            c.wlr_scene_node_set_enabled(&cl.*.shadow.*.node, false);
        return;
    } else {
        if (cl.*.scene_surface.*.node.enabled and !cl.*.shadow.*.node.enabled)
            c.wlr_scene_node_set_enabled(&cl.*.shadow.*.node, true);
    }

    const hit_no_border = check_hit_no_border(cl);
    const current_corner_location = if (cl.*.isfullscreen != 0 or
        (c.config.no_radius_when_single != 0 and cl.*.mon != null and
            cl.*.mon.*.visible_tiling_clients == 1))
        c.corner_radii_none()
    else
        set_client_corner_location(cl);

    const bw: i32 = @intCast(cl.*.bw);
    const bwoffset: i32 = if (bw != 0 and hit_no_border) bw else 0;

    var width: i32 = 0;
    var height: i32 = 0;
    client_actual_size(cl, &width, &height);

    const delta = @as(i32, @intCast(c.config.shadows_size)) + bw - bwoffset;

    var client_box = c.struct_wlr_box{
        .x = bwoffset,
        .y = bwoffset,
        .width = width + 2 * bw - 2 * bwoffset,
        .height = height + 2 * bw - 2 * bwoffset,
    };

    var shadow_box = c.struct_wlr_box{
        .x = c.config.shadows_position_x + bwoffset,
        .y = c.config.shadows_position_y + bwoffset,
        .width = width + 2 * delta,
        .height = height + 2 * delta,
    };

    var intersection_box: c.struct_wlr_box = undefined;
    _ = c.wlr_box_intersection(&intersection_box, &client_box, &shadow_box);
    intersection_box.x -= c.config.shadows_position_x + bwoffset;
    intersection_box.y -= c.config.shadows_position_y + bwoffset;

    var clipped_region = c.struct_clipped_region{
        .area = intersection_box,
        .corners = current_corner_location,
    };

    const cur = cl.*.animation.current;
    const absolute_shadow_box = c.struct_wlr_box{
        .x = shadow_box.x + cur.x,
        .y = shadow_box.y + cur.y,
        .width = shadow_box.width,
        .height = shadow_box.height,
    };

    var left: i32 = undefined;
    var right: i32 = undefined;
    var top: i32 = undefined;
    var bottom: i32 = undefined;
    if (client_is_ignore_output_clip(cl)) {
        left = 0;
        right = 0;
        top = 0;
        bottom = 0;
    } else {
        const mon = cl.*.mon.*;
        right = gez(absolute_shadow_box.x + absolute_shadow_box.width - mon.m.x - mon.m.width);
        bottom = gez(absolute_shadow_box.y + absolute_shadow_box.height - mon.m.y - mon.m.height);
        left = gez(mon.m.x - absolute_shadow_box.x);
        top = gez(mon.m.y - absolute_shadow_box.y);
    }

    left = @min(left, shadow_box.width);
    right = @min(right, shadow_box.width);
    top = @min(top, shadow_box.height);
    bottom = @min(bottom, shadow_box.height);

    c.wlr_scene_node_set_position(&cl.*.shadow.*.node, shadow_box.x + left, shadow_box.y + top);

    c.wlr_scene_shadow_set_size(cl.*.shadow, gez(shadow_box.width - left - right), gez(shadow_box.height - top - bottom));

    clipped_region.area.x = clipped_region.area.x - left;
    clipped_region.area.y = clipped_region.area.y - top;

    c.wlr_scene_shadow_set_clipped_region(cl.*.shadow, clipped_region);
}

export fn client_draw_group_bar(cl: [*c]Client, offsets: c.struct_ivec2) callconv(.c) void {
    if (cl == null or cl.*.group_bar == null)
        return;

    if (!client_wants_group_bar(cl)) {
        if (cl.*.group_bar.*.scene.*.node.enabled)
            c.wlr_scene_node_set_enabled(&cl.*.group_bar.*.scene.*.node, false);
        return;
    }

    // Owner hidden by tab: hide the whole strip, otherwise its nodes (they are
    // not children of the window) would float over the visible window.
    if (cl.*.is_tab_hidden) {
        var cur = client_group_head(cl);
        while (cur != null) : (cur = cur.*.group_next) {
            if (cur.*.group_bar != null)
                c.wlr_scene_node_set_enabled(&cur.*.group_bar.*.scene.*.node, false);
        }
        return;
    }

    var count: i32 = 0;
    var cur = client_group_head(cl);
    while (cur != null) : (cur = cur.*.group_next) {
        count += 1;
    }

    const group_bar_height: i32 = @intCast(c.config.group_bar_height);
    var tab_x = cl.*.animation.current.x;
    var tab_y = cl.*.animation.current.y - group_bar_height;
    var tw = cl.*.animation.current.width;
    var th = group_bar_height;

    const top_over = offsets.y;
    const bottom_over = offsets.height;
    const left_over = offsets.x;
    const right_over = offsets.width;

    if (top_over > 0) {
        tab_y = cl.*.mon.*.m.y;
        th = group_bar_height - top_over;
    }
    if (bottom_over > 0) {
        th = th - gez(bottom_over - cl.*.animation.current.height);
    }

    if (right_over > 0)
        tw = tw - right_over;
    if (left_over > 0) {
        tab_x = cl.*.mon.*.m.x;
        tw = tw - left_over;
    }

    if (tw <= 0 or th <= 0) {
        cur = client_group_head(cl);
        while (cur != null) : (cur = cur.*.group_next) {
            if (cur.*.group_bar != null)
                c.wlr_scene_node_set_enabled(&cur.*.group_bar.*.scene.*.node, false);
        }
        return;
    } else {
        client_check_tab_node_visible(cl);
    }

    const bar_w = @divTrunc(tw, count);
    const rem = @rem(tw, count);
    var x = tab_x;
    cur = client_group_head(cl);

    var i: i32 = 0;
    while (i < count and cur != null) : (i += 1) {
        const w = bar_w + (if (i < rem) @as(i32, 1) else 0);
        global_draw_group_bar(cur, x, tab_y, w, th);
        x += w;
        cur = cur.*.group_next;
    }
}

export fn client_draw_shield(cl: [*c]Client, clip_box: c.struct_ivec2) callconv(.c) void {
    var shield_x: i32 = 0;
    var shield_y: i32 = 0;
    var shield_width: i32 = 0;
    var shield_height: i32 = 0;

    if (c.server.active_capture_count <= 0 or cl.*.shield_when_capture == 0) {
        if (cl.*.shield.*.node.enabled) {
            c.wlr_scene_node_lower_to_bottom(&cl.*.shield.*.node);
            c.wlr_scene_node_set_position(&cl.*.shield.*.node, 0, 0);
            c.wlr_scene_rect_set_size(cl.*.shield, cl.*.animation.current.width, cl.*.animation.current.height);
            c.wlr_scene_node_set_enabled(&cl.*.shield.*.node, false);
        }
        return;
    }

    const bw: i32 = @intCast(cl.*.bw);
    if (client_is_ignore_output_clip(cl)) {
        shield_x = bw;
        shield_y = bw;
        shield_width = cl.*.animation.current.width - 2 * bw;
        shield_height = cl.*.animation.current.height - 2 * bw;
    } else {
        shield_x = clip_box.x + bw;
        shield_y = clip_box.y + bw;
        shield_width = cl.*.animation.current.width - 2 * bw - clip_box.width - clip_box.x;
        shield_height = cl.*.animation.current.height - 2 * bw - clip_box.height - clip_box.y;
    }

    if (shield_width <= 0 or shield_height <= 0) {
        c.wlr_scene_node_set_enabled(&cl.*.shield.*.node, false);
        return;
    }

    c.wlr_scene_node_raise_to_top(&cl.*.shield.*.node);
    c.wlr_scene_node_set_position(&cl.*.shield.*.node, shield_x, shield_y);
    c.wlr_scene_rect_set_size(cl.*.shield, shield_width, shield_height);
    c.wlr_scene_node_set_enabled(&cl.*.shield.*.node, true);
}

export fn client_draw_dim(cl: [*c]Client, clip_box: c.struct_ivec2) callconv(.c) void {
    if (cl == null or cl.*.dim_node == null)
        return;

    if (cl.*.isfullscreen != 0) {
        acwm_dim_node_set_enabled(cl.*.dim_node, false);
        return;
    }

    if (c.config.dim_enable == 0) {
        acwm_dim_node_set_enabled(cl.*.dim_node, false);
        return;
    }

    var dim_x: i32 = 0;
    var dim_y: i32 = 0;
    var dim_width: i32 = 0;
    var dim_height: i32 = 0;

    const bw: i32 = @intCast(cl.*.bw);
    if (client_is_ignore_output_clip(cl)) {
        dim_width = cl.*.animation.current.width - 2 * bw;
        dim_height = cl.*.animation.current.height - 2 * bw;
    } else {
        dim_x = clip_box.x;
        dim_y = clip_box.y;
        dim_width = cl.*.animation.current.width - 2 * bw - clip_box.width - clip_box.x;
        dim_height = cl.*.animation.current.height - 2 * bw - clip_box.height - clip_box.y;
    }

    if (dim_width <= 0 or dim_height <= 0) {
        acwm_dim_node_set_enabled(cl.*.dim_node, false);
        return;
    }

    var radius: i32 = 0;
    if (cl.*.isfullscreen == 0 and !(c.config.no_radius_when_single != 0 and cl.*.mon != null and
        cl.*.mon.*.visible_tiling_clients == 1))
        radius = c.config.border_radius;

    acwm_dim_node_set_radius(cl.*.dim_node, radius);
    acwm_dim_node_set_enabled(cl.*.dim_node, true);
    acwm_dim_node_set_box(cl.*.dim_node, dim_x, dim_y, dim_width, dim_height);
}

export fn client_draw_blur(cl: [*c]Client, clip_box: c.struct_ivec2) callconv(.c) void {
    if (cl.*.isfullscreen != 0) {
        if (cl.*.blur.*.node.enabled)
            c.wlr_scene_node_set_enabled(&cl.*.blur.*.node, false);
        return;
    }

    var blur_x: i32 = 0;
    var blur_y: i32 = 0;
    var blur_width: i32 = 0;
    var blur_height: i32 = 0;

    if (c.config.blur != 0 and cl.*.no_blur == 0) {
        const bw: i32 = @intCast(cl.*.bw);
        if (client_is_ignore_output_clip(cl)) {
            blur_x = bw;
            blur_y = bw;
            blur_width = cl.*.animation.current.width - 2 * bw;
            blur_height = cl.*.animation.current.height - 2 * bw;
        } else {
            blur_x = clip_box.x + bw;
            blur_y = clip_box.y + bw;
            blur_width = cl.*.animation.current.width - 2 * bw - clip_box.width - clip_box.x;
            blur_height = cl.*.animation.current.height - 2 * bw - clip_box.height - clip_box.y;
        }

        if (blur_width <= 0 or blur_height <= 0) {
            c.wlr_scene_node_set_enabled(&cl.*.blur.*.node, false);
            return;
        }

        c.wlr_scene_node_set_enabled(&cl.*.blur.*.node, true);
        c.wlr_scene_node_set_position(&cl.*.blur.*.node, blur_x, blur_y);
        c.wlr_scene_blur_set_size(cl.*.blur, blur_width, blur_height);
    } else {
        c.wlr_scene_node_set_enabled(&cl.*.blur.*.node, false);
    }
}

export fn global_draw_group_bar(cl: [*c]Client, x: i32, y: i32, width: i32, height: i32) callconv(.c) void {
    if (cl.*.group_bar == null)
        return;

    c.wlr_scene_node_set_position(&cl.*.group_bar.*.scene.*.node, x, y);
    acwm_bar_decoration_set_size(cl.*.group_bar, width, height);
}

export fn client_draw_split_border(cl: [*c]Client, hit_no_border: bool, offsets: c.struct_ivec2) callconv(.c) void {
    if (cl.*.iskilling != 0 or cl.*.mon == null or !client_surface(cl).*.mapped)
        return;

    const tag = get_client_tag_idx(cl);
    const layout = cl.*.mon.*.pertag.*.ltidxs[tag];

    if (hit_no_border or !isTiled(cl) or layout.*.id != c.DWINDLE or
        c.config.dwindle_manual_split == 0 or cl.*.isfullscreen != 0)
    {
        if (cl.*.splitindicator[0].*.node.enabled)
            c.wlr_scene_node_set_enabled(&cl.*.splitindicator[0].*.node, false);
        if (cl.*.splitindicator[1].*.node.enabled)
            c.wlr_scene_node_set_enabled(&cl.*.splitindicator[1].*.node, false);
        return;
    }

    const dnode = dwindle_find_leaf(cl.*.mon.*.pertag.*.dwindle_root[tag], cl);
    if (dnode == null) {
        c.wlr_scene_node_set_enabled(&cl.*.splitindicator[0].*.node, false);
        c.wlr_scene_node_set_enabled(&cl.*.splitindicator[1].*.node, false);
        return;
    }

    if (dnode.*.custom_leaf_split_h) {
        c.wlr_scene_node_set_enabled(&cl.*.splitindicator[0].*.node, false);
        c.wlr_scene_node_set_enabled(&cl.*.splitindicator[1].*.node, true);
    } else {
        c.wlr_scene_node_set_enabled(&cl.*.splitindicator[0].*.node, true);
        c.wlr_scene_node_set_enabled(&cl.*.splitindicator[1].*.node, false);
    }

    const fullgeom = cl.*.animation.current;
    const bw: i32 = @intCast(cl.*.bw);
    const left = offsets.x;
    const right = offsets.width;
    const top = offsets.y;
    const bottom = offsets.height;

    const border_down_width = gez(fullgeom.width - 2 * c.config.border_radius -
        gez((left + right) - c.config.border_radius));
    const border_down_height = gez(bw - bottom - gez(top + bw - fullgeom.height));

    const border_right_width = gez(bw - right - gez(left + bw - fullgeom.width));
    const border_right_height = gez(fullgeom.height - 2 * c.config.border_radius -
        gez((top + bottom) - c.config.border_radius));

    const border_down_x = gez(c.config.border_radius + gez(left - c.config.border_radius));
    const border_down_y = gez(fullgeom.height - bw) + gez(top + bw - fullgeom.height);

    const border_right_x = gez(fullgeom.width - bw) + gez(left + bw - fullgeom.width);
    const border_right_y = gez(c.config.border_radius + gez(top - c.config.border_radius));

    setRectSize(cl.*.splitindicator[0], border_down_width, border_down_height);
    setRectSize(cl.*.splitindicator[1], border_right_width, border_right_height);
    c.wlr_scene_node_set_position(&cl.*.splitindicator[0].*.node, border_down_x, border_down_y);
    c.wlr_scene_node_set_position(&cl.*.splitindicator[1].*.node, border_right_x, border_right_y);
}

export fn client_draw_border(cl: [*c]Client, offsets: c.struct_ivec2) callconv(.c) void {
    if (cl == null or cl.*.iskilling != 0 or !client_surface(cl).*.mapped)
        return;

    if (cl.*.isfullscreen != 0) {
        if (cl.*.border.*.node.enabled) {
            c.wlr_scene_node_set_enabled(&cl.*.splitindicator[0].*.node, false);
            c.wlr_scene_node_set_enabled(&cl.*.splitindicator[1].*.node, false);
            c.wlr_scene_node_set_enabled(&cl.*.border.*.node, false);
            c.wlr_scene_node_set_position(&cl.*.scene_surface.*.node, 0, 0);
        }
        return;
    } else {
        if (!cl.*.border.*.node.enabled)
            c.wlr_scene_node_set_enabled(&cl.*.border.*.node, true);
    }

    const hit_no_border = check_hit_no_border(cl);
    client_draw_split_border(cl, hit_no_border, offsets);

    const current_corner_location = if (cl.*.isfullscreen != 0 or
        (c.config.no_radius_when_single != 0 and cl.*.mon != null and
            cl.*.mon.*.visible_tiling_clients == 1))
        c.corner_radii_none()
    else
        set_client_corner_location(cl);

    const cur = cl.*.animation.current;
    const bw: i32 = @intCast(cl.*.bw);
    const left = offsets.x;
    const right = offsets.width;
    const top = offsets.y;
    const bottom = offsets.height;

    var inner_surface_width = gez(cur.width - 2 * bw);
    var inner_surface_height = gez(cur.height - 2 * bw);
    const inner_surface_x = gez(bw - left);
    const inner_surface_y = gez(bw - top);

    const rect_x = left;
    const rect_y = top;
    const rect_width = gez(cur.width - left - right);
    const rect_height = gez(cur.height - top - bottom);

    if (left > cl.*.bw)
        inner_surface_width = inner_surface_width - left + bw;
    if (top > cl.*.bw)
        inner_surface_height = inner_surface_height - top + bw;
    if (right > 0)
        inner_surface_width = @min(cur.width, inner_surface_width + right);
    if (bottom > 0)
        inner_surface_height = @min(cur.height, inner_surface_height + bottom);

    const clipped_region = c.struct_clipped_region{
        .area = .{
            .x = inner_surface_x,
            .y = inner_surface_y,
            .width = inner_surface_width,
            .height = inner_surface_height,
        },
        .corners = current_corner_location,
    };

    c.wlr_scene_node_set_position(&cl.*.scene_surface.*.node, @intCast(cl.*.bw), @intCast(cl.*.bw));
    c.wlr_scene_rect_set_size(cl.*.border, rect_width, rect_height);
    c.wlr_scene_node_set_position(&cl.*.border.*.node, rect_x, rect_y);
    c.wlr_scene_rect_set_corner_radii(cl.*.border, current_corner_location);
    c.wlr_scene_rect_set_clipped_region(cl.*.border, clipped_region);
}

export fn clip_to_hide(cl: [*c]Client, clip_box: [*c]c.struct_wlr_box, offsets: c.struct_ivec2) callconv(.c) c.struct_ivec2 {
    var offset = std.mem.zeroes(c.struct_ivec2);

    if (!isScrollTiled(cl) and !cl.*.animation.tagining and !cl.*.animation.tagouted and
        !cl.*.animation.tagouting)
        return offset;

    const bw: i32 = @intCast(cl.*.bw);
    const left = offsets.x;
    const right = offsets.width;
    const top = offsets.y;
    const bottom = offsets.height;

    if (left > 0) {
        offset.x = gez(left - bw);
        clip_box.*.x += offset.x;
        clip_box.*.width -= offset.x;
    } else if (right > 0) {
        offset.width = gez(right - bw);
        clip_box.*.width -= offset.width;
    }

    if (top > 0) {
        offset.y = gez(top - bw);
        clip_box.*.y += offset.y;
        clip_box.*.height -= offset.y;
    } else if (bottom > 0) {
        offset.height = gez(bottom - bw);
        clip_box.*.height -= offset.height;
    }

    if ((clip_box.*.width + bw <= 0 or clip_box.*.height + bw <= 0) and
        (isScrollTiled(cl) or cl.*.animation.tagouting or cl.*.animation.tagining))
    {
        cl.*.is_clip_to_hide = true;
        client_update_visibility(cl);
    } else if (cl.*.is_clip_to_hide and
        (visibleOn(cl, cl.*.mon) or client_gesture_driven(cl)))
    {
        cl.*.is_clip_to_hide = false;
        client_update_visibility(cl);
    }

    return offset;
}

// ---------------------------------------------------------------------------
// draw-helper tests (slice 88)
// ---------------------------------------------------------------------------

extern var stub_surface: [*c]c.struct_wlr_surface;
extern var stub_hit_no_border: c_int;
extern var stub_wants_group_bar: c_int;
extern var stub_group_head: [*c]Client;
extern var stub_tab_visible_calls: c_int;
extern var stub_visibility_calls: c_int;
extern var stub_client_tag: u32;
extern var stub_dnode: [*c]c.DwindleNode;
extern var stub_dim_enabled_calls: c_int;
extern var stub_dim_enabled_value: c_int;
extern var stub_dim_radius_calls: c_int;
extern var stub_dim_radius: c_int;
extern var stub_dim_box_calls: c_int;
extern var stub_dim_box: [4]c_int;
extern var stub_bar_size_calls: c_int;
extern var stub_bar_w: c_int;
extern var stub_bar_h: c_int;
extern var stub_node_enabled_calls: c_int;
extern var stub_node_enabled_value: c_int;
extern var stub_node_pos_calls: c_int;
extern var stub_pos_node: [24][*c]c.struct_wlr_scene_node;
extern var stub_pos_x: [24]i32;
extern var stub_pos_y: [24]i32;
extern var stub_lower_calls: c_int;
extern var stub_raise_calls: c_int;
extern var stub_shadow_size_calls: c_int;
extern var stub_shadow_w: c_int;
extern var stub_shadow_h: c_int;
extern var stub_shadow_clip_calls: c_int;
extern var stub_shadow_clip: c.struct_clipped_region;
extern var stub_rect_corner_calls: c_int;
extern var stub_rect_corners: c.struct_fx_corner_radii;
extern var stub_rect_clip_calls: c_int;
extern var stub_rect_clip: c.struct_clipped_region;
extern var stub_blur_size_calls: c_int;
extern var stub_blur_w: c_int;
extern var stub_blur_h: c_int;

var test_draw_surface: c.struct_wlr_surface = undefined;
var test_shadow: c.struct_wlr_scene_shadow = undefined;
var test_shield: c.struct_wlr_scene_rect = undefined;
var test_border: c.struct_wlr_scene_rect = undefined;
var test_split: [2]c.struct_wlr_scene_rect = undefined;
var test_dim: c.AcwmDimNode = undefined;
var test_group_bar: c.AcwmBarDecoration = undefined;
var test_group_scene: [2]c.struct_wlr_scene_tree = undefined;
var test_group_next: Client = undefined;
var test_dnode: c.DwindleNode = undefined;
var test_draw_layout: c.Layout = undefined;

fn resetDrawWorld() void {
    resetWorld();
    test_draw_surface = std.mem.zeroes(c.struct_wlr_surface);
    test_draw_surface.mapped = true;
    test_shadow = std.mem.zeroes(c.struct_wlr_scene_shadow);
    test_shield = std.mem.zeroes(c.struct_wlr_scene_rect);
    test_border = std.mem.zeroes(c.struct_wlr_scene_rect);
    test_split = std.mem.zeroes([2]c.struct_wlr_scene_rect);
    test_dim = std.mem.zeroes(c.AcwmDimNode);
    test_group_bar = std.mem.zeroes(c.AcwmBarDecoration);
    test_group_scene = std.mem.zeroes([2]c.struct_wlr_scene_tree);
    test_group_next = std.mem.zeroes(Client);
    test_dnode = std.mem.zeroes(c.DwindleNode);
    test_draw_layout = std.mem.zeroes(c.Layout);

    test_client.shadow = &test_shadow;
    test_client.shield = &test_shield;
    test_client.border = &test_border;
    test_client.splitindicator[0] = &test_split[0];
    test_client.splitindicator[1] = &test_split[1];
    test_client.dim_node = &test_dim;
    test_client.group_bar = &test_group_bar;
    test_group_bar.scene = &test_group_scene[0];
    test_client.scene_surface = &test_scene_surface_node;
    test_client.animation.current = .{ .x = 0, .y = 0, .width = 100, .height = 80 };
    test_mon.m = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
    test_mon.w = test_mon.m;
    test_pertag.ltidxs[0] = &test_draw_layout;

    stub_surface = &test_draw_surface;
    stub_hit_no_border = 0;
    stub_wants_group_bar = 1;
    stub_group_head = null;
    stub_tab_visible_calls = 0;
    stub_visibility_calls = 0;
    stub_client_tag = 0;
    stub_dnode = &test_dnode;
    stub_dim_enabled_calls = 0;
    stub_dim_enabled_value = -1;
    stub_dim_radius_calls = 0;
    stub_dim_radius = -1;
    stub_dim_box_calls = 0;
    stub_dim_box = std.mem.zeroes([4]c_int);
    stub_bar_size_calls = 0;
    stub_bar_w = 0;
    stub_bar_h = 0;
    stub_node_enabled_calls = 0;
    stub_node_enabled_value = -1;
    stub_node_pos_calls = 0;
    stub_pos_node = std.mem.zeroes([24][*c]c.struct_wlr_scene_node);
    stub_pos_x = std.mem.zeroes([24]i32);
    stub_pos_y = std.mem.zeroes([24]i32);
    stub_lower_calls = 0;
    stub_raise_calls = 0;
    stub_shadow_size_calls = 0;
    stub_shadow_w = 0;
    stub_shadow_h = 0;
    stub_shadow_clip_calls = 0;
    stub_shadow_clip = std.mem.zeroes(c.struct_clipped_region);
    stub_rect_w = -1;
    stub_rect_h = -1;
    stub_rect_call_count = 0;
    stub_rect_call_w = std.mem.zeroes([16]c_int);
    stub_rect_call_h = std.mem.zeroes([16]c_int);
    stub_rect_corner_calls = 0;
    stub_rect_corners = std.mem.zeroes(c.struct_fx_corner_radii);
    stub_rect_clip_calls = 0;
    stub_rect_clip = std.mem.zeroes(c.struct_clipped_region);
    stub_blur_size_calls = 0;
    stub_blur_w = 0;
    stub_blur_h = 0;
}

test "shadow draw enables, sizes and clips around the monitor" {
    resetDrawWorld();
    c.config.shadows = 1;
    c.config.shadows_size = 10;
    c.config.shadows_position_x = 0;
    c.config.shadows_position_y = 0;
    test_scene_surface_node.node.enabled = true;
    const offsets = std.mem.zeroes(c.struct_ivec2);
    client_draw_shadow(&test_client, offsets);
    try testing.expect(test_shadow.node.enabled);
    try testing.expectEqual(@as(c_int, 120), stub_shadow_w);
    try testing.expectEqual(@as(c_int, 100), stub_shadow_h);
    try testing.expectEqual(@as(c_int, 1), stub_shadow_clip_calls);
    try testing.expectEqual(@as(i32, 100), stub_shadow_clip.area.width);

    c.config.shadows = 0;
    client_draw_shadow(&test_client, offsets);
    try testing.expect(!test_shadow.node.enabled);
}

test "group bar splits the strip and hides with the tab" {
    resetDrawWorld();
    c.config.group_bar_height = 20;
    const offsets = std.mem.zeroes(c.struct_ivec2);
    client_draw_group_bar(&test_client, offsets);
    try testing.expectEqual(@as(c_int, 1), stub_bar_size_calls);
    try testing.expectEqual(@as(c_int, 100), stub_bar_w);
    try testing.expectEqual(@as(c_int, 20), stub_bar_h);
    try testing.expectEqual(@as(i32, -20), stub_pos_y[0]);

    const second = &test_group_next;
    second.mon = &test_mon;
    second.group_bar = &test_group_bar;
    test_group_bar.scene = &test_group_scene[1];
    test_client.group_next = second;
    client_draw_group_bar(&test_client, offsets);
    try testing.expectEqual(@as(c_int, 3), stub_bar_size_calls);
    try testing.expectEqual(@as(c_int, 50), stub_bar_w);

    stub_wants_group_bar = 0;
    client_draw_group_bar(&test_client, offsets);
    try testing.expect(!test_group_scene[0].node.enabled);
}

test "shield follows capture state and clip box" {
    resetDrawWorld();
    c.server.active_capture_count = 1;
    test_client.shield_when_capture = 1;
    const clip = std.mem.zeroes(c.struct_ivec2);
    client_draw_shield(&test_client, clip);
    try testing.expect(test_shield.node.enabled);
    try testing.expectEqual(@as(c_int, 1), stub_raise_calls);
    try testing.expectEqual(@as(c_int, 96), stub_rect_w);

    const too_big = c.struct_ivec2{ .x = 90, .y = 70, .width = 20, .height = 20 };
    client_draw_shield(&test_client, too_big);
    try testing.expect(!test_shield.node.enabled);
    try testing.expectEqual(@as(c_int, 0), stub_lower_calls);

    c.server.active_capture_count = 0;
    test_shield.node.enabled = true;
    client_draw_shield(&test_client, clip);
    try testing.expectEqual(@as(c_int, 1), stub_lower_calls);
}

test "dim and blur use clipped client boxes" {
    resetDrawWorld();
    c.config.dim_enable = 1;
    c.config.border_radius = 10;
    const clip = std.mem.zeroes(c.struct_ivec2);
    client_draw_dim(&test_client, clip);
    try testing.expectEqual(@as(c_int, 1), stub_dim_enabled_value);
    try testing.expectEqual(@as(c_int, 10), stub_dim_radius);
    try testing.expectEqual(@as(c_int, 96), stub_dim_box[2]);
    try testing.expectEqual(@as(c_int, 76), stub_dim_box[3]);

    c.config.blur = 1;
    client_draw_blur(&test_client, clip);
    try testing.expect(test_blur.node.enabled);
    try testing.expectEqual(@as(c_int, 96), stub_blur_w);
    try testing.expectEqual(@as(c_int, 76), stub_blur_h);

    test_client.isfullscreen = 1;
    client_draw_blur(&test_client, clip);
    try testing.expect(!test_blur.node.enabled);
    client_draw_dim(&test_client, clip);
    try testing.expectEqual(@as(c_int, 0), stub_dim_enabled_value);
}

test "split border shows the dwindle split indicator geometry" {
    resetDrawWorld();
    test_draw_layout.id = c.DWINDLE;
    c.config.dwindle_manual_split = 1;
    c.config.border_radius = 10;
    const offsets = std.mem.zeroes(c.struct_ivec2);
    client_draw_split_border(&test_client, false, offsets);
    try testing.expect(test_split[0].node.enabled);
    try testing.expect(!test_split[1].node.enabled);
    try testing.expectEqual(@as(c_int, 80), stub_rect_call_w[0]);
    try testing.expectEqual(@as(c_int, 2), stub_rect_call_h[0]);
    try testing.expectEqual(@as(c_int, 2), stub_rect_call_w[1]);
    try testing.expectEqual(@as(c_int, 60), stub_rect_call_h[1]);
    try testing.expectEqual(@as(i32, 10), stub_pos_x[0]);
    try testing.expectEqual(@as(i32, 78), stub_pos_y[0]);

    test_dnode.custom_leaf_split_h = true;
    client_draw_split_border(&test_client, false, offsets);
    try testing.expect(!test_split[0].node.enabled);
    try testing.expect(test_split[1].node.enabled);

    client_draw_split_border(&test_client, true, offsets);
    try testing.expect(!test_split[0].node.enabled);
    try testing.expect(!test_split[1].node.enabled);
}

test "border draw positions surface, border and clipped region" {
    resetDrawWorld();
    c.config.border_radius = 10;
    const offsets = std.mem.zeroes(c.struct_ivec2);
    client_draw_border(&test_client, offsets);
    try testing.expect(test_border.node.enabled);
    try testing.expectEqual(@as(c_int, 100), stub_rect_w);
    try testing.expectEqual(@as(c_int, 80), stub_rect_h);
    try testing.expectEqual(@as(c_int, 1), stub_rect_clip_calls);
    try testing.expectEqual(@as(i32, 2), stub_rect_clip.area.x);
    try testing.expectEqual(@as(i32, 96), stub_rect_clip.area.width);
    try testing.expectEqual(@as(c_int, 1), stub_rect_corner_calls);

    test_client.isfullscreen = 1;
    test_border.node.enabled = true;
    client_draw_border(&test_client, offsets);
    try testing.expect(!test_border.node.enabled);
    try testing.expectEqual(@as(i32, 0), stub_pos_x[@intCast(stub_node_pos_calls - 1)]);
}

test "clip to hide trims the clip box and toggles visibility" {
    resetDrawWorld();
    var clip = c.struct_wlr_box{ .x = 0, .y = 0, .width = 100, .height = 80 };
    var offsets = std.mem.zeroes(c.struct_ivec2);
    offsets.x = 10;
    const shifted = clip_to_hide(&test_client, &clip, offsets);
    try testing.expectEqual(@as(i32, 8), shifted.x);
    try testing.expectEqual(@as(i32, 8), clip.x);
    try testing.expectEqual(@as(i32, 92), clip.width);

    clip = .{ .x = 0, .y = 0, .width = 1, .height = 1 };
    offsets = std.mem.zeroes(c.struct_ivec2);
    offsets.x = 50;
    _ = clip_to_hide(&test_client, &clip, offsets);
    try testing.expect(test_client.is_clip_to_hide);
    try testing.expectEqual(@as(c_int, 1), stub_visibility_calls);

    test_client.is_clip_to_hide = true;
    clip = .{ .x = 0, .y = 0, .width = 100, .height = 80 };
    _ = clip_to_hide(&test_client, &clip, std.mem.zeroes(c.struct_ivec2));
    try testing.expect(!test_client.is_clip_to_hide);
    try testing.expectEqual(@as(c_int, 2), stub_visibility_calls);
}

// ---------------------------------------------------------------------------
// drop area, clip application and fadeout (slice 89)
// ---------------------------------------------------------------------------

extern fn client_draw_tabbar(cl: [*c]Client, offsets: c.struct_ivec2) callconv(.c) void;
extern fn client_get_clip(cl: [*c]Client, clip: [*c]c.struct_wlr_box) callconv(.c) void;
extern fn client_get_geometry(cl: [*c]Client, geom: [*c]c.struct_wlr_box) callconv(.c) void;
extern fn client_is_x11(cl: [*c]Client) callconv(.c) c_int;
extern fn client_update_xwayland_clip(cl: [*c]Client, clip: [*c]c.struct_wlr_box) callconv(.c) void;
extern fn client_update_xwayland_dest_size(cl: [*c]Client) callconv(.c) void;
extern fn client_is_unmanaged(cl: [*c]Client) callconv(.c) c_int;
extern fn client_set_border_color(cl: [*c]Client, color: [*c]const f32) callconv(.c) void;
extern fn overview_layout_card(cl: [*c]Client) callconv(.c) void;
extern fn overview_destroy_card(cl: [*c]Client) callconv(.c) void;
extern fn node_at_point(x: f64, y: f64, psurface: [*c][*c]c.struct_wlr_surface, pc: [*c][*c]Client, pl: [*c][*c]c.LayerSurface, bar: [*c][*c]c.AcwmBarDecoration, nx: [*c]f64, ny: [*c]f64) callconv(.c) void;
extern fn scene_buffer_apply_opacity(buffer: [*c]c.struct_wlr_scene_buffer, sx: i32, sy: i32, data: ?*anyopaque) callconv(.c) void;
extern fn find_animation_curve_at(t: f64, anim_type: i32) callconv(.c) f64;
extern fn timespec_to_ms(ts: [*c]c.struct_timespec) callconv(.c) u32;
extern fn get_now_in_ms() callconv(.c) u32;
extern fn request_fresh_all_monitors() callconv(.c) void;
extern fn ecalloc(nmemb: usize, size: usize) callconv(.c) ?*anyopaque;

fn wlListInit(list: *c.struct_wl_list) void {
    list.prev = @ptrCast(list);
    list.next = @ptrCast(list);
}

fn wlListInsert(list: *c.struct_wl_list, elm: *c.struct_wl_list) void {
    elm.next = list.next;
    elm.prev = @ptrCast(list);
    list.next.*.prev = elm;
    list.next = elm;
}

fn wlListRemove(elm: *c.struct_wl_list) void {
    const prev = elm.prev;
    const next = elm.next;
    prev.*.next = next;
    next.*.prev = prev;
}

export fn client_set_drop_area(cl: [*c]Client) callconv(.c) void {
    var first_draw = false;
    var drop_direction: i32 = c.UNDIR;

    if (cl == null or cl.*.mon == null)
        return;

    if (!cl.*.enable_drop_area_draw and !cl.*.droparea.*.node.enabled)
        return;

    if (!cl.*.enable_drop_area_draw and cl.*.droparea.*.node.enabled) {
        c.wlr_scene_node_lower_to_bottom(&cl.*.droparea.*.node);
        c.wlr_scene_node_set_enabled(&cl.*.droparea.*.node, false);
        return;
    } else if (cl.*.enable_drop_area_draw and !cl.*.droparea.*.node.enabled) {
        c.wlr_scene_node_raise_to_top(&cl.*.droparea.*.node);
        c.wlr_scene_node_set_enabled(&cl.*.droparea.*.node, true);
        first_draw = true;
    }

    const bw: i32 = @intCast(cl.*.bw);
    const client_width = cl.*.geom.width - 2 * bw;
    const client_height = cl.*.geom.height - 2 * bw;

    if (client_width <= 0 or client_height <= 0) {
        c.wlr_scene_node_set_enabled(&cl.*.droparea.*.node, false);
        return;
    }

    if (c.server.drop_to_group and c.server.drop_client == cl) {
        if (!first_draw and cl.*.drop_direction == c.UNDIR)
            return;
        cl.*.drop_direction = c.UNDIR;
        c.wlr_scene_node_set_position(&cl.*.droparea.*.node, bw, bw);
        c.wlr_scene_rect_set_size(cl.*.droparea, client_width, client_height);
        return;
    }

    const rel_x = c.server.cursor.*.x - @as(f64, @floatFromInt(cl.*.geom.x)) - @as(f64, @floatFromInt(bw));
    const rel_y = c.server.cursor.*.y - @as(f64, @floatFromInt(cl.*.geom.y)) - @as(f64, @floatFromInt(bw));

    var drop_box: c.struct_wlr_box = undefined;
    const cur_layout = cl.*.mon.*.pertag.*.ltidxs[get_client_tag_idx(cl)];
    const dwindle_familiar = cur_layout.*.id == c.DWINDLE and c.config.dwindle_drop_simple_split != 0;

    if (dwindle_familiar) {
        const split_h = cl.*.geom.width >= cl.*.geom.height;
        const ratio = c.config.dwindle_split_ratio;
        if (split_h) {
            if (rel_x < @as(f64, @floatFromInt(client_width)) * 0.5) {
                drop_direction = c.LEFT;
                drop_box.x = bw;
                drop_box.y = bw;
                drop_box.width = @intFromFloat(@as(f64, @floatFromInt(client_width)) * ratio);
                drop_box.height = client_height;
            } else {
                drop_direction = c.RIGHT;
                drop_box.x = bw + @as(i32, @intFromFloat(@as(f64, @floatFromInt(client_width)) * ratio));
                drop_box.y = bw;
                drop_box.width = client_width - @as(i32, @intFromFloat(@as(f64, @floatFromInt(client_width)) * ratio));
                drop_box.height = client_height;
            }
        } else {
            if (rel_y < @as(f64, @floatFromInt(client_height)) * 0.5) {
                drop_direction = c.UP;
                drop_box.x = bw;
                drop_box.y = bw;
                drop_box.width = client_width;
                drop_box.height = @intFromFloat(@as(f64, @floatFromInt(client_height)) * ratio);
            } else {
                drop_direction = c.DOWN;
                drop_box.x = bw;
                drop_box.y = bw + @as(i32, @intFromFloat(@as(f64, @floatFromInt(client_height)) * ratio));
                drop_box.width = client_width;
                drop_box.height = client_height - @as(i32, @intFromFloat(@as(f64, @floatFromInt(client_height)) * ratio));
            }
        }
    } else if (cur_layout.*.id == c.TILE or cur_layout.*.id == c.DECK or
        cur_layout.*.id == c.CENTER_TILE or cur_layout.*.id == c.RIGHT_TILE)
    {
        if (cl.*.ismaster) {
            if (cl.*.mon.*.visible_tiling_clients == 1) {
                if (rel_x < @as(f64, @floatFromInt(client_width)) * 0.5) {
                    drop_direction = c.LEFT;
                    drop_box.x = bw;
                    drop_box.y = bw;
                    drop_box.width = @divTrunc(client_width, 2);
                    drop_box.height = client_height;
                } else {
                    drop_direction = c.RIGHT;
                    drop_box.x = bw + @divTrunc(client_width, 2);
                    drop_box.y = bw;
                    drop_box.width = @divTrunc(client_width, 2);
                    drop_box.height = client_height;
                }
            } else {
                drop_box.x = bw;
                drop_box.y = bw;
                drop_box.width = client_width;
                drop_box.height = client_height;
                drop_direction = c.UNDIR;
            }
        } else {
            if (rel_y < @as(f64, @floatFromInt(client_height)) * 0.5) {
                drop_direction = c.UP;
                drop_box.x = bw;
                drop_box.y = bw;
                drop_box.width = client_width;
                drop_box.height = @divTrunc(client_height, 2);
            } else {
                drop_direction = c.DOWN;
                drop_box.x = bw;
                drop_box.y = bw + @divTrunc(client_height, 2);
                drop_box.width = client_width;
                drop_box.height = @divTrunc(client_height, 2);
            }
        }
    } else if (cur_layout.*.id == c.VERTICAL_TILE or cur_layout.*.id == c.VERTICAL_DECK) {
        if (cl.*.ismaster) {
            if (cl.*.mon.*.visible_tiling_clients == 1) {
                if (rel_y < @as(f64, @floatFromInt(client_height)) * 0.5) {
                    drop_direction = c.UP;
                    drop_box.x = bw;
                    drop_box.y = bw;
                    drop_box.width = client_width;
                    drop_box.height = @divTrunc(client_height, 2);
                } else {
                    drop_direction = c.DOWN;
                    drop_box.x = bw;
                    drop_box.y = bw + @divTrunc(client_height, 2);
                    drop_box.width = client_width;
                    drop_box.height = @divTrunc(client_height, 2);
                }
            } else {
                drop_box.x = bw;
                drop_box.y = bw;
                drop_box.width = client_width;
                drop_box.height = client_height;
                drop_direction = c.UNDIR;
            }
        } else {
            if (rel_x < @as(f64, @floatFromInt(client_width)) * 0.5) {
                drop_direction = c.LEFT;
                drop_box.x = bw;
                drop_box.y = bw;
                drop_box.width = @divTrunc(client_width, 2);
                drop_box.height = client_height;
            } else {
                drop_direction = c.RIGHT;
                drop_box.x = bw + @divTrunc(client_width, 2);
                drop_box.y = bw;
                drop_box.width = @divTrunc(client_width, 2);
                drop_box.height = client_height;
            }
        }
    } else {
        const dist_left = rel_x;
        const dist_right = @as(f64, @floatFromInt(client_width)) - rel_x;
        const dist_top = rel_y;
        const dist_bottom = @as(f64, @floatFromInt(client_height)) - rel_y;

        if (dist_left <= dist_right and dist_left <= dist_top and dist_left <= dist_bottom) {
            drop_direction = c.LEFT;
            drop_box.x = bw;
            drop_box.y = bw;
            drop_box.width = @divTrunc(client_width, 2);
            drop_box.height = client_height;
        } else if (dist_right <= dist_top and dist_right <= dist_bottom) {
            drop_direction = c.RIGHT;
            drop_box.x = bw + @divTrunc(client_width, 2);
            drop_box.y = bw;
            drop_box.width = @divTrunc(client_width, 2);
            drop_box.height = client_height;
        } else if (dist_top <= dist_bottom) {
            drop_direction = c.UP;
            drop_box.x = bw;
            drop_box.y = bw;
            drop_box.width = client_width;
            drop_box.height = @divTrunc(client_height, 2);
        } else {
            drop_direction = c.DOWN;
            drop_box.x = bw;
            drop_box.y = bw + @divTrunc(client_height, 2);
            drop_box.width = client_width;
            drop_box.height = @divTrunc(client_height, 2);
        }
    }

    if (!first_draw and cl.*.drop_direction == drop_direction)
        return;
    cl.*.drop_direction = drop_direction;

    c.wlr_scene_node_set_position(&cl.*.droparea.*.node, drop_box.x, drop_box.y);
    c.wlr_scene_rect_set_size(cl.*.droparea, drop_box.width, drop_box.height);
}

fn drawDecorations(cl: [*c]Client, offsets: c.struct_ivec2, surface_clip_offset: c.struct_ivec2) void {
    client_draw_border(cl, offsets);
    client_draw_shadow(cl, offsets);
    client_draw_group_bar(cl, offsets);
    client_draw_tabbar(cl, offsets);
    client_draw_blur(cl, surface_clip_offset);
    client_draw_shield(cl, surface_clip_offset);
    client_draw_dim(cl, surface_clip_offset);
}

export fn client_apply_clip(cl: [*c]Client, factor: f32) callconv(.c) void {
    if (cl.*.iskilling != 0 or !client_surface(cl).*.mapped)
        return;

    // Overview card mode: content is shown by the independent card tree; update
    // the card position/scale here and redraw the decoration nodes to match the
    // card geometry.
    if (cl.*.ov_card_tree != null) {
        const offsets = compute_edge_offsets(cl);

        var card_w: i32 = 0;
        var card_h: i32 = 0;
        client_actual_size(cl, &card_w, &card_h);
        var clip_box = c.struct_wlr_box{ .x = 0, .y = 0, .width = card_w, .height = card_h };
        const surface_clip_offset = clip_to_hide(cl, &clip_box, offsets);

        drawDecorations(cl, offsets, surface_clip_offset);

        overview_layout_card(cl);
        overview_card_set_corner_radii(cl, set_client_corner_location(cl));
        return;
    }

    const offsets = compute_edge_offsets(cl);

    var clip_box: c.struct_wlr_box = undefined;
    var surface_clip_offset: c.struct_ivec2 = undefined;

    const current_corner_location = set_client_corner_location(cl);

    if (!client_animations_enabled(cl) and cl.*.overview_scene_surface == null) {
        cl.*.animation.running = false;
        cl.*.animation.tagining = false;
        cl.*.animation.tagouting = false;
        cl.*.need_output_flush = false;
        cl.*.animainit_geom = cl.*.geom;
        cl.*.current = cl.*.geom;
        cl.*.pending = cl.*.geom;
        cl.*.animation.current = cl.*.geom;

        client_get_clip(cl, &clip_box);
        surface_clip_offset = clip_to_hide(cl, &clip_box, offsets);

        drawDecorations(cl, offsets, surface_clip_offset);

        const should_render_client_surface = clip_box.width > 0 and clip_box.height > 0;
        cl.*.is_surface_hidden = !should_render_client_surface;
        client_update_visibility(cl);

        if (!should_render_client_surface)
            return;

        // X11 is clipped with source_box + dest_size (buffer physical size *
        // scale, clip logical size); wlr_scene clip would scale content by the
        // physical size.
        if (client_is_x11(cl) != 0)
            client_update_xwayland_clip(cl, &clip_box)
        else if (cl.*.overview_scene_surface == null)
            c.wlr_scene_subsurface_tree_set_clip(&cl.*.scene_surface.*.node, &clip_box);

        var buffer_data = std.mem.zeroes(c.BufferData);
        buffer_data.width_scale = 1.0;
        buffer_data.height_scale = 1.0;
        buffer_data.width = clip_box.width;
        buffer_data.height = clip_box.height;
        buffer_data.corner_location = current_corner_location;
        buffer_data.should_scale = true;
        buffer_set_effect(cl, buffer_data);
        return;
    }

    var width: i32 = 0;
    var height: i32 = 0;
    client_actual_size(cl, &width, &height);

    var geometry: c.struct_wlr_box = undefined;
    client_get_geometry(cl, &geometry);
    clip_box = .{ .x = geometry.x, .y = geometry.y, .width = width, .height = height };

    if (client_is_x11(cl) != 0) {
        clip_box.x = 0;
        clip_box.y = 0;
    }

    surface_clip_offset = clip_to_hide(cl, &clip_box, offsets);

    client_draw_border(cl, offsets);
    client_draw_shadow(cl, offsets);
    client_draw_group_bar(cl, offsets);
    client_draw_tabbar(cl, offsets);
    client_draw_shield(cl, surface_clip_offset);
    client_draw_dim(cl, surface_clip_offset);
    client_draw_blur(cl, surface_clip_offset);

    // During animation, sync the X11 root surface dest_size / clipping
    // (source_box + dest_size).
    if (client_is_x11(cl) != 0)
        client_update_xwayland_clip(cl, &clip_box)
    else
        client_update_xwayland_dest_size(cl);

    const should_render_client_surface = clip_box.width > 0 and clip_box.height > 0;
    cl.*.is_surface_hidden = !should_render_client_surface;
    client_update_visibility(cl);

    if (!should_render_client_surface)
        return;

    // X11 clipping is already done above by client_update_xwayland_clip with
    // source_box; wlr_scene clip would scale the buffer by its physical size
    // and cannot be used for X11.
    if (cl.*.overview_scene_surface == null and client_is_x11(cl) == 0)
        c.wlr_scene_subsurface_tree_set_clip(&cl.*.scene_surface.*.node, &clip_box);

    const actual_surface_width = geometry.width - surface_clip_offset.x - surface_clip_offset.width;
    const actual_surface_height = geometry.height - surface_clip_offset.y - surface_clip_offset.height;

    if (actual_surface_width <= 0 or actual_surface_height <= 0)
        return;

    var buffer_data = std.mem.zeroes(c.BufferData);
    buffer_data.should_scale = true;
    buffer_data.width = clip_box.width;
    buffer_data.height = clip_box.height;
    buffer_data.corner_location = current_corner_location;

    if (factor == 1.0 and cl.*.overview_scene_surface == null) {
        buffer_data.width_scale = 1.0;
        buffer_data.height_scale = 1.0;
    } else {
        buffer_data.width_scale = @as(f32, @floatFromInt(buffer_data.width)) /
            @as(f32, @floatFromInt(actual_surface_width));
        buffer_data.height_scale = @as(f32, @floatFromInt(buffer_data.height)) /
            @as(f32, @floatFromInt(actual_surface_height));
    }

    buffer_set_effect(cl, buffer_data);
}

export fn fadeout_client_animation_next_tick(cl: [*c]Client) callconv(.c) void {
    if (cl == null)
        return;

    var now: c.struct_timespec = undefined;
    _ = c.clock_gettime(c.CLOCK_MONOTONIC, &now);

    const passed_time: i32 = @bitCast(timespec_to_ms(&now) -% cl.*.animation.time_started);
    const animation_passed: f64 = if (cl.*.animation.duration != 0)
        @as(f64, @floatFromInt(passed_time)) / @as(f64, @floatFromInt(cl.*.animation.duration))
    else
        1.0;

    const anim_type = cl.*.animation.action;
    const factor = find_animation_curve_at(animation_passed, anim_type);

    const width: i32 = @intFromFloat(@as(f64, @floatFromInt(cl.*.animation.initial.width)) +
        @as(f64, @floatFromInt(cl.*.current.width - cl.*.animation.initial.width)) * factor);
    const height: i32 = @intFromFloat(@as(f64, @floatFromInt(cl.*.animation.initial.height)) +
        @as(f64, @floatFromInt(cl.*.current.height - cl.*.animation.initial.height)) * factor);
    const x: i32 = @intFromFloat(@as(f64, @floatFromInt(cl.*.animation.initial.x)) +
        @as(f64, @floatFromInt(cl.*.current.x - cl.*.animation.initial.x)) * factor);
    const y: i32 = @intFromFloat(@as(f64, @floatFromInt(cl.*.animation.initial.y)) +
        @as(f64, @floatFromInt(cl.*.current.y - cl.*.animation.initial.y)) * factor);

    c.wlr_scene_node_set_position(&cl.*.scene.*.node, x, y);

    cl.*.animation.current = .{ .x = x, .y = y, .width = width, .height = height };

    const opacity_eased_progress = find_animation_curve_at(animation_passed, c.OPAFADEOUT);
    const percent = c.config.fadeout_begin_opacity -
        opacity_eased_progress * c.config.fadeout_begin_opacity;
    var opacity = @max(percent, 0);

    if (c.config.animation_fade_out != 0 and cl.*.no_fade_out == 0)
        c.wlr_scene_node_for_each_buffer(&cl.*.scene.*.node, scene_buffer_apply_opacity, &opacity);

    if (closeAnimationType(cl) == c.ANIM_TYPE_ZOOM) {
        var buffer_data = std.mem.zeroes(c.BufferData);
        buffer_data.width = width;
        buffer_data.height = height;
        buffer_data.width_scale = @floatCast(animation_passed);
        buffer_data.height_scale = @floatCast(animation_passed);
        c.wlr_scene_node_for_each_buffer(&cl.*.scene.*.node, snap_scene_buffer_apply_effect, &buffer_data);
    }

    if (animation_passed >= 1.0) {
        wlListRemove(&cl.*.fadeout_link);
        c.wlr_scene_node_destroy(&cl.*.scene.*.node);
        c.free(cl);
    }
}

export fn client_animation_next_tick(cl: [*c]Client) callconv(.c) void {
    var now: c.struct_timespec = undefined;
    _ = c.clock_gettime(c.CLOCK_MONOTONIC, &now);

    const passed_time: i32 = @bitCast(timespec_to_ms(&now) -% cl.*.animation.time_started);
    const animation_passed: f64 = if (cl.*.animation.duration != 0)
        @as(f64, @floatFromInt(passed_time)) / @as(f64, @floatFromInt(cl.*.animation.duration))
    else
        1.0;

    const anim_type: i32 = if (cl.*.animation.action == c.NONE) c.MOVE else cl.*.animation.action;
    const factor = find_animation_curve_at(animation_passed, anim_type);

    const width: i32 = @intFromFloat(@as(f64, @floatFromInt(cl.*.animation.initial.width)) +
        @as(f64, @floatFromInt(cl.*.current.width - cl.*.animation.initial.width)) * factor);
    const height: i32 = @intFromFloat(@as(f64, @floatFromInt(cl.*.animation.initial.height)) +
        @as(f64, @floatFromInt(cl.*.current.height - cl.*.animation.initial.height)) * factor);
    const x: i32 = @intFromFloat(@as(f64, @floatFromInt(cl.*.animation.initial.x)) +
        @as(f64, @floatFromInt(cl.*.current.x - cl.*.animation.initial.x)) * factor);
    const y: i32 = @intFromFloat(@as(f64, @floatFromInt(cl.*.animation.initial.y)) +
        @as(f64, @floatFromInt(cl.*.current.y - cl.*.animation.initial.y)) * factor);

    c.wlr_scene_node_set_position(&cl.*.scene.*.node, x, y);
    cl.*.animation.current = .{ .x = x, .y = y, .width = width, .height = height };

    cl.*.is_pending_open_animation = false;
    client_apply_clip(cl, @floatCast(factor));

    if (animation_passed >= 1.0) {
        cl.*.animation.action = c.MOVE;
        cl.*.animation.tagining = false;
        cl.*.animation.running = false;
        cl.*.animation.overining = false;

        if (cl.*.animation.tagouting) {
            cl.*.animation.tagouting = false;
            client_update_visibility(cl);
            cl.*.animation.tagouted = true;
            cl.*.animation.current = cl.*.geom;
            client_apply_clip(cl, 1.0);
        } else {
            // Snap to the final box: an interpolated one can be a pixel off,
            // which leaves X11 content stretched (blurry).
            client_apply_finish_geometry(cl);
        }

        var pointer_c: [*c]Client = null;
        var sx: f64 = 0;
        var sy: f64 = 0;
        node_at_point(c.server.cursor.*.x, c.server.cursor.*.y, null, &pointer_c, null, null, &sx, &sy);
        const surface: [*c]c.struct_wlr_surface = if (pointer_c != null and pointer_c == cl)
            client_surface(pointer_c)
        else
            null;

        if (surface != null and c.server.selected_monitor != null and
            pointer_c == c.server.selected_monitor.*.sel and
            c.server.selected_monitor.*.isoverview == 0)
            c.wlr_seat_pointer_notify_enter(c.server.seat, surface, sx, sy);

        cl.*.need_output_flush = false;
    }
}

export fn init_fadeout_client(cl: [*c]Client) callconv(.c) void {
    if (cl.*.mon == null or client_is_unmanaged(cl) != 0)
        return;

    if (cl.*.scene == null)
        return;

    if (cl.*.shield_when_capture != 0 and c.server.active_capture_count > 0)
        return;

    if (closeAnimationType(cl) == c.ANIM_TYPE_NONE)
        return;

    const raw = ecalloc(1, @sizeOf(Client)) orelse return;
    const fadeout_client: *Client = @ptrCast(@alignCast(raw));
    fadeout_client.animation_type_open = c.ANIM_TYPE_UNSET;
    fadeout_client.animation_type_close = c.ANIM_TYPE_UNSET;

    cl.*.snapshot_temp_visible = true;
    client_update_visibility(cl);
    client_set_border_color(cl, &c.config.bordercolor);
    if (cl.*.ov_card_tree != null) {
        // Closing in overview: the fadeout snapshot is based on the
        // already-scaled card tree. Snapshotting accumulates node coordinates,
        // but card tree coordinates are relative to (bw,bw), so a direct
        // snapshot would land near the layer origin; temporarily move the card
        // tree to the card's absolute screen coordinates before snapshotting.
        const abs_x = cl.*.animation.current.x + @as(i32, @intCast(cl.*.bw));
        const abs_y = cl.*.animation.current.y + @as(i32, @intCast(cl.*.bw));
        c.wlr_scene_node_set_position(&cl.*.ov_card_tree.*.node, abs_x, abs_y);
        fadeout_client.scene = c.wlr_scene_tree_snapshot(&cl.*.ov_card_tree.*.node, c.server.layers[c.LyrFadeOut]);
        overview_destroy_card(cl);
        cl.*.overview_scene_surface = null;
    } else {
        fadeout_client.scene = c.wlr_scene_tree_snapshot(&cl.*.scene.*.node, c.server.layers[c.LyrFadeOut]);
    }
    cl.*.snapshot_temp_visible = false;
    client_update_visibility(cl);

    if (fadeout_client.scene == null) {
        c.free(fadeout_client);
        return;
    }

    fadeout_client.animation.duration = c.config.animation_duration_close;
    fadeout_client.geom = cl.*.animation.current;
    fadeout_client.current = cl.*.animation.current;
    fadeout_client.animainit_geom = cl.*.animation.current;
    fadeout_client.animation.initial = cl.*.animation.current;
    fadeout_client.mon = cl.*.mon;
    fadeout_client.animation_type_close = cl.*.animation_type_close;
    fadeout_client.animation.action = c.CLOSE;
    fadeout_client.bw = cl.*.bw;
    fadeout_client.no_fade_out = cl.*.no_fade_out;

    fadeout_client.animation.initial.x = 0;
    fadeout_client.animation.initial.y = 0;

    if (closeAnimationType(cl) == c.ANIM_TYPE_FADE) {
        fadeout_client.current.x = 0;
        fadeout_client.current.y = 0;
        fadeout_client.current.width = 0;
        fadeout_client.current.height = 0;
    } else if (closeAnimationType(cl) == c.ANIM_TYPE_SLIDE) {
        const mon = cl.*.mon.*;
        fadeout_client.current.y = if (cl.*.geom.y + @divTrunc(cl.*.geom.height, 2) >=
            mon.m.y + @divTrunc(mon.m.height, 2))
            mon.m.y + mon.m.height - cl.*.animation.current.y
        else
            mon.m.y - cl.*.geom.height - cl.*.animation.current.y;
        fadeout_client.current.x = 0;
    } else {
        fadeout_client.current.y = @intFromFloat((@as(f64, @floatFromInt(fadeout_client.geom.height)) -
            @as(f64, @floatFromInt(fadeout_client.geom.height)) * c.config.zoom_end_ratio) / 2);
        fadeout_client.current.x = @intFromFloat((@as(f64, @floatFromInt(fadeout_client.geom.width)) -
            @as(f64, @floatFromInt(fadeout_client.geom.width)) * c.config.zoom_end_ratio) / 2);
        fadeout_client.current.width = @intFromFloat(@as(f64, @floatFromInt(fadeout_client.geom.width)) * c.config.zoom_end_ratio);
        fadeout_client.current.height = @intFromFloat(@as(f64, @floatFromInt(fadeout_client.geom.height)) * c.config.zoom_end_ratio);
    }

    fadeout_client.animation.time_started = get_now_in_ms();
    c.wlr_scene_node_set_enabled(&fadeout_client.scene.*.node, true);
    wlListInsert(&c.server.fadeout_clients, &fadeout_client.fadeout_link);

    request_fresh_all_monitors();
}

// ---------------------------------------------------------------------------
// drop/clip/fadeout tests (slice 89)
// ---------------------------------------------------------------------------

extern var stub_get_clip_calls: c_int;
extern var stub_clip: c.struct_wlr_box;
extern var stub_get_geometry_calls: c_int;
extern var stub_geometry: c.struct_wlr_box;
extern var stub_is_x11: c_int;
extern var stub_xwayland_clip_calls: c_int;
extern var stub_xwayland_clip: c.struct_wlr_box;
extern var stub_xwayland_dest_calls: c_int;
extern var stub_unmanaged: c_int;
extern var stub_border_color_calls: c_int;
extern var stub_border_color: [4]f32;
extern var stub_overview_layout_calls: c_int;
extern var stub_overview_destroy_calls: c_int;
extern var stub_tabbar_calls: c_int;
extern var stub_pointer_client: [*c]Client;
extern var stub_node_at_point_calls: c_int;
extern var stub_opacity_calls: c_int;
extern var stub_opacity: f64;
extern var stub_curve: f64;
extern var stub_now_ms: u32;
extern var stub_get_now_ms: u32;
extern var stub_fresh_monitors_calls: c_int;
extern var stub_surface_clip_calls: c_int;
extern var stub_surface_clip: c.struct_wlr_box;
extern var stub_tree_destroy_calls: c_int;
extern var stub_snapshot_calls: c_int;
extern var stub_snapshot_tree: [*c]c.struct_wlr_scene_tree;
extern var stub_pointer_enter_calls: c_int;

var test_cursor: c.struct_wlr_cursor = undefined;
var test_fadeout_tree: c.struct_wlr_scene_tree = undefined;
var test_layers: [c.NUM_LAYERS]?*c.struct_wlr_scene_tree = undefined;
var test_selected_mon: Monitor = undefined;
var test_seat: c.struct_wlr_seat = undefined;
var test_droparea: c.struct_wlr_scene_rect = undefined;
var test_drop_layout: c.Layout = undefined;

fn resetDropWorld() void {
    resetDrawWorld();
    test_cursor = std.mem.zeroes(c.struct_wlr_cursor);
    test_fadeout_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    test_layers = std.mem.zeroes([c.NUM_LAYERS]?*c.struct_wlr_scene_tree);
    test_layers[c.LyrFadeOut] = &test_fadeout_tree;
    test_selected_mon = std.mem.zeroes(Monitor);
    test_seat = std.mem.zeroes(c.struct_wlr_seat);
    test_droparea = std.mem.zeroes(c.struct_wlr_scene_rect);
    test_drop_layout = std.mem.zeroes(c.Layout);
    test_client.droparea = &test_droparea;
    test_client.scene = &test_fadeout_tree;
    test_client.geom = .{ .x = 10, .y = 20, .width = 100, .height = 80 };
    test_client.animation.current = .{ .x = 0, .y = 0, .width = 100, .height = 80 };
    test_pertag.ltidxs[0] = &test_drop_layout;
    c.server.cursor = &test_cursor;
    c.server.layers = test_layers;
    c.server.fadeout_clients = std.mem.zeroes(c.struct_wl_list);
    wlListInit(&c.server.fadeout_clients);
    c.server.selected_monitor = &test_selected_mon;
    c.server.seat = &test_seat;
    test_client.mon = &test_mon;
    test_client.overview_scene_surface = null;
    test_client.ov_card_tree = null;
    test_client.iskilling = 0;
    test_client.isfullscreen = 0;
    test_client.isfloating = 0;
    test_client.isunglobal = 0;
    test_client.is_clip_to_hide = false;
    test_client.enable_drop_area_draw = false;
    test_client.drop_direction = c.UNDIR;
    test_client.ismaster = false;
    test_client.animation.duration = 0;
    test_client.animation.time_started = 0;
    test_mon.visible_tiling_clients = 1;
    c.config.animation_type_close = c.ANIM_TYPE_NONE;
    stub_get_clip_calls = 0;
    stub_clip = .{ .x = 0, .y = 0, .width = 100, .height = 80 };
    stub_get_geometry_calls = 0;
    stub_geometry = .{ .x = 0, .y = 0, .width = 100, .height = 80 };
    stub_is_x11 = 0;
    stub_xwayland_clip_calls = 0;
    stub_xwayland_clip = std.mem.zeroes(c.struct_wlr_box);
    stub_xwayland_dest_calls = 0;
    stub_unmanaged = 0;
    stub_border_color_calls = 0;
    stub_border_color = std.mem.zeroes([4]f32);
    stub_overview_layout_calls = 0;
    stub_overview_destroy_calls = 0;
    stub_tabbar_calls = 0;
    stub_pointer_client = null;
    stub_node_at_point_calls = 0;
    stub_opacity_calls = 0;
    stub_opacity = 0;
    stub_curve = -1;
    stub_now_ms = 0;
    stub_get_now_ms = 1000;
    stub_fresh_monitors_calls = 0;
    stub_surface_clip_calls = 0;
    stub_surface_clip = std.mem.zeroes(c.struct_wlr_box);
    stub_tree_destroy_calls = 0;
    stub_snapshot_calls = 0;
    stub_snapshot_tree = &test_fadeout_tree;
    stub_pointer_enter_calls = 0;
}

fn fadeoutFromLink(link: [*c]c.struct_wl_list) *Client {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(Client, "fadeout_link"));
}

test "drop area hides on disable and raises on first draw" {
    resetDropWorld();
    test_droparea.node.enabled = true;
    client_set_drop_area(&test_client);
    try testing.expectEqual(@as(c_int, 1), stub_lower_calls);

    test_client.enable_drop_area_draw = true;
    client_set_drop_area(&test_client);
    try testing.expectEqual(@as(c_int, 1), stub_raise_calls);
    try testing.expect(test_droparea.node.enabled);
    try testing.expectEqual(@as(c_int, 96), stub_rect_w);
}

test "drop area picks halves in tiled layouts" {
    resetDropWorld();
    test_drop_layout.id = c.TILE;
    test_client.enable_drop_area_draw = true;
    test_droparea.node.enabled = true;
    test_client.ismaster = false;
    test_cursor.x = 30;
    test_cursor.y = 25;
    client_set_drop_area(&test_client);
    try testing.expectEqual(@as(i32, c.UP), test_client.drop_direction);
    try testing.expectEqual(@as(c_int, 96), stub_rect_w);
    try testing.expectEqual(@as(c_int, 38), stub_rect_h);

    test_client.ismaster = true;
    test_cursor.x = 70;
    test_cursor.y = 70;
    client_set_drop_area(&test_client);
    try testing.expectEqual(@as(i32, c.RIGHT), test_client.drop_direction);
    try testing.expectEqual(@as(c_int, 48), stub_rect_w);
    try testing.expectEqual(@as(c_int, 76), stub_rect_h);
}

test "drop area uses dwindle ratio and group drops" {
    resetDropWorld();
    test_drop_layout.id = c.DWINDLE;
    c.config.dwindle_drop_simple_split = 1;
    c.config.dwindle_split_ratio = 0.25;
    test_client.enable_drop_area_draw = true;
    test_droparea.node.enabled = true;
    test_cursor.x = 20;
    client_set_drop_area(&test_client);
    try testing.expectEqual(@as(i32, c.LEFT), test_client.drop_direction);
    try testing.expectEqual(@as(c_int, 24), stub_rect_w);
    try testing.expectEqual(@as(c_int, 76), stub_rect_h);

    c.server.drop_to_group = true;
    c.server.drop_client = &test_client;
    client_set_drop_area(&test_client);
    try testing.expectEqual(@as(i32, c.UNDIR), test_client.drop_direction);
    try testing.expectEqual(@as(c_int, 96), stub_rect_w);
}

test "clip overview path redraws cards and decorations" {
    resetDropWorld();
    test_client.ov_card_tree = @ptrFromInt(0x5000);
    test_client.animation.duration = 10;
    c.config.animations = 1;
    client_apply_clip(&test_client, 0.5);
    try testing.expectEqual(@as(c_int, 1), stub_overview_layout_calls);
    try testing.expectEqual(@as(c_int, 1), stub_tabbar_calls);
    try testing.expectEqual(@as(c_int, 1), stub_card_radii_calls);
    try testing.expectEqual(@as(c_int, 0), stub_get_clip_calls);
}

test "clip without animations snaps geometry and hides empty clips" {
    resetDropWorld();
    c.config.animations = 0;
    stub_gesture = 0;
    client_apply_clip(&test_client, 1.0);
    try testing.expectEqual(@as(c_int, 1), stub_get_clip_calls);
    try testing.expectEqual(@as(c_int, 1), stub_surface_clip_calls);
    try testing.expectEqual(@as(c_int, 1), stub_tabbar_calls);
    try testing.expect(!test_client.is_surface_hidden);
    try testing.expectEqual(test_client.geom.width, test_client.pending.width);

    stub_clip.width = 0;
    client_apply_clip(&test_client, 1.0);
    try testing.expect(test_client.is_surface_hidden);
}

test "clip during animation routes X11 and scales buffers" {
    resetDropWorld();
    c.config.animations = 1;
    test_client.animation.duration = 10;
    stub_is_x11 = 1;
    stub_iterate = 1;
    client_apply_clip(&test_client, 0.5);
    try testing.expectEqual(@as(c_int, 1), stub_xwayland_clip_calls);
    try testing.expectEqual(@as(c_int, 0), stub_surface_clip_calls);
    try testing.expectEqual(@as(c_int, 1), stub_for_each_calls);
    // Both scales are below 1, so the scene-buffer effect declines to resize.
    try testing.expectEqual(@as(c_int, 0), stub_dest_size_calls);
    try testing.expectEqual(@as(c_int, 1), stub_buffer_radii_calls);

    resetDropWorld();
    c.config.animations = 1;
    test_client.animation.duration = 10;
    client_apply_clip(&test_client, 1.0);
    try testing.expectEqual(@as(c_int, 1), stub_xwayland_dest_calls);
    try testing.expectEqual(@as(c_int, 1), stub_surface_clip_calls);
}

test "fadeout tick interpolates, fades and destroys at the end" {
    resetDropWorld();
    c.config.animation_fade_out = 1;
    c.config.fadeout_begin_opacity = 0.8;
    test_client.animation.duration = 100;
    test_client.animation.time_started = 0;
    test_client.animation.initial = .{ .x = 0, .y = 0, .width = 100, .height = 80 };
    test_client.current = .{ .x = 100, .y = 80, .width = 200, .height = 160 };
    stub_now_ms = 50;
    stub_iterate = 1;
    fadeout_client_animation_next_tick(&test_client);
    try testing.expectEqual(@as(i32, 150), test_client.animation.current.width);
    try testing.expectEqual(@as(i32, 50), test_client.animation.current.x);
    try testing.expectEqual(@as(c_int, 1), stub_opacity_calls);
    try testing.expect(stub_opacity > 0 and stub_opacity < 0.8);

    const heap = @as(*Client, @ptrCast(@alignCast(c.ecalloc(1, @sizeOf(Client)) orelse unreachable)));
    heap.* = std.mem.zeroes(Client);
    heap.scene = &test_fadeout_tree;
    heap.animation.duration = 100;
    heap.animation.time_started = 0;
    heap.fadeout_link = std.mem.zeroes(c.struct_wl_list);
    wlListInsert(&c.server.fadeout_clients, &heap.fadeout_link);
    stub_now_ms = 200;
    fadeout_client_animation_next_tick(heap);
    try testing.expectEqual(@as(c_int, 1), stub_tree_destroy_calls);
    try testing.expect(c.server.fadeout_clients.next == &c.server.fadeout_clients);
}

test "animation tick snaps to pending geometry and re-enters the pointer" {
    resetDropWorld();
    test_client.animation.duration = 100;
    test_client.animation.time_started = 0;
    test_client.animation.initial = .{ .x = 0, .y = 0, .width = 100, .height = 80 };
    test_client.current = .{ .x = 100, .y = 80, .width = 200, .height = 160 };
    test_client.geom = .{ .x = 40, .y = 50, .width = 300, .height = 200 };
    stub_now_ms = 200;
    stub_pointer_client = &test_client;
    test_selected_mon.sel = &test_client;
    test_selected_mon.isoverview = 0;
    stub_is_x11 = 0;
    client_animation_next_tick(&test_client);
    try testing.expectEqual(test_client.geom.width, test_client.pending.width);
    try testing.expectEqual(@as(i32, c.MOVE), test_client.animation.action);
    try testing.expect(!test_client.animation.running);
    try testing.expectEqual(@as(c_int, 1), stub_pointer_enter_calls);
    try testing.expect(!test_client.need_output_flush);
}

test "animation tick handles tag-out completion" {
    resetDropWorld();
    test_client.animation.duration = 100;
    test_client.animation.time_started = 0;
    test_client.animation.initial = .{ .x = 0, .y = 0, .width = 100, .height = 80 };
    test_client.current = test_client.animation.initial;
    test_client.geom = .{ .x = 5, .y = 6, .width = 70, .height = 60 };
    test_client.animation.tagouting = true;
    test_client.iskilling = 1;
    stub_now_ms = 200;
    client_animation_next_tick(&test_client);
    try testing.expect(test_client.animation.tagouted);
    try testing.expect(!test_client.animation.tagouting);
    try testing.expectEqual(@as(i32, 70), test_client.animation.current.width);
}

test "fadeout init guards and builds a zoom client" {
    resetDropWorld();
    c.config.animation_type_close = c.ANIM_TYPE_NONE;
    init_fadeout_client(&test_client);
    try testing.expect(c.server.fadeout_clients.next == &c.server.fadeout_clients);

    c.config.animation_type_close = c.ANIM_TYPE_ZOOM;
    c.config.zoom_end_ratio = 0.5;
    c.config.animation_duration_close = 300;
    test_client.animation.current = .{ .x = 10, .y = 20, .width = 100, .height = 80 };
    init_fadeout_client(&test_client);
    try testing.expect(c.server.fadeout_clients.next != &c.server.fadeout_clients);
    const fade = fadeoutFromLink(c.server.fadeout_clients.next);
    try testing.expectEqual(@as(u32, 300), fade.animation.duration);
    try testing.expectEqual(@as(i32, c.CLOSE), fade.animation.action);
    try testing.expectEqual(@as(i32, 100), fade.geom.width);
    try testing.expectEqual(@as(i32, 25), fade.current.x);
    try testing.expectEqual(@as(i32, 20), fade.current.y);
    try testing.expectEqual(@as(i32, 50), fade.current.width);
    try testing.expectEqual(@as(i32, 40), fade.current.height);
    try testing.expectEqual(@as(c_int, 1), stub_border_color_calls);
    try testing.expectEqual(@as(c_int, 1), stub_fresh_monitors_calls);
}

test "fadeout init applies fade and slide end states" {
    resetDropWorld();
    c.config.animation_type_close = c.ANIM_TYPE_FADE;
    c.config.animation_duration_close = 100;
    test_client.animation.current = .{ .x = 10, .y = 20, .width = 100, .height = 80 };
    init_fadeout_client(&test_client);
    var fade = fadeoutFromLink(c.server.fadeout_clients.next);
    try testing.expectEqual(@as(i32, 0), fade.current.width);
    try testing.expectEqual(@as(i32, 0), fade.current.height);

    resetDropWorld();
    c.config.animation_type_close = c.ANIM_TYPE_SLIDE;
    test_mon.m = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
    test_client.geom = .{ .x = 0, .y = 500, .width = 100, .height = 80 };
    test_client.animation.current = .{ .x = 0, .y = 600, .width = 100, .height = 80 };
    init_fadeout_client(&test_client);
    fade = fadeoutFromLink(c.server.fadeout_clients.next);
    try testing.expectEqual(@as(i32, 200), fade.current.y);
    try testing.expectEqual(@as(i32, 0), fade.current.x);
}

test "fadeout init snapshots overview cards and clears the card surface" {
    resetDropWorld();
    c.config.animation_type_close = c.ANIM_TYPE_FADE;
    test_client.ov_card_tree = &test_fadeout_tree;
    test_client.overview_scene_surface = @ptrFromInt(0x6000);
    test_client.animation.current = .{ .x = 30, .y = 40, .width = 100, .height = 80 };
    init_fadeout_client(&test_client);
    try testing.expectEqual(@as(c_int, 1), stub_overview_destroy_calls);
    try testing.expect(test_client.overview_scene_surface == null);
    try testing.expectEqual(@as(c_int, 1), stub_snapshot_calls);
    try testing.expectEqual(@as(i32, 32), stub_pos_x[0]);
    try testing.expectEqual(@as(i32, 42), stub_pos_y[0]);
}

// ---------------------------------------------------------------------------
// commit / resize (slice 90)
// ---------------------------------------------------------------------------

extern fn client_apply_bounds(cl: [*c]Client, bbox: [*c]c.struct_wlr_box) callconv(.c) void;
extern fn client_set_size_bound(cl: [*c]Client) callconv(.c) void;
extern fn client_set_size(cl: [*c]Client, width: u32, height: u32, force_configure: bool) callconv(.c) u32;
extern fn client_update_border_color(cl: [*c]Client) callconv(.c) void;
extern fn llround(x: f64) callconv(.c) c_longlong;

export fn client_apply_finish_geometry(cl: [*c]Client) callconv(.c) void {
    if (cl == null or cl.*.scene == null)
        return;

    c.wlr_scene_node_set_position(&cl.*.scene.*.node, cl.*.pending.x, cl.*.pending.y);
    cl.*.animation.current = cl.*.geom;
    cl.*.animainit_geom = cl.*.geom;
    cl.*.animation.initial = cl.*.geom;
    cl.*.pending = cl.*.geom;
    cl.*.current = cl.*.geom;
    client_apply_clip(cl, 1.0);
    cl.*.need_output_flush = false;
}

export fn client_animation_set_progress(cl: [*c]Client, progress: f64) callconv(.c) void {
    if (cl == null or cl.*.scene == null)
        return;

    var p = progress;
    if (p < 0.0) p = 0.0;
    if (p > 1.0) p = 1.0;

    const from = cl.*.animation.initial;
    const to = cl.*.current;

    const width: i32 = @intCast(llround(@as(f64, @floatFromInt(from.width)) +
        @as(f64, @floatFromInt(to.width - from.width)) * p));
    const height: i32 = @intCast(llround(@as(f64, @floatFromInt(from.height)) +
        @as(f64, @floatFromInt(to.height - from.height)) * p));
    const x: i32 = @intCast(llround(@as(f64, @floatFromInt(from.x)) +
        @as(f64, @floatFromInt(to.x - from.x)) * p));
    const y: i32 = @intCast(llround(@as(f64, @floatFromInt(from.y)) +
        @as(f64, @floatFromInt(to.y - from.y)) * p));

    c.wlr_scene_node_set_position(&cl.*.scene.*.node, x, y);
    cl.*.animation.current = .{ .x = x, .y = y, .width = width, .height = height };

    cl.*.is_pending_open_animation = false;
    client_apply_clip(cl, 1.0);
}

export fn client_animation_resume(cl: [*c]Client, remaining: f64) callconv(.c) void {
    if (cl == null or cl.*.scene == null)
        return;

    if (!cl.*.animation.running)
        return;

    if (c.config.animations == 0 or cl.*.animation.duration == 0 or remaining < 0.05) {
        client_animation_set_progress(cl, 1.0);
        cl.*.animation.action = c.MOVE;
        cl.*.animation.tagining = false;
        cl.*.animation.overining = false;
        cl.*.animation.running = false;
        if (cl.*.animation.tagouting) {
            cl.*.animation.tagouting = false;
            client_update_visibility(cl);
            cl.*.animation.tagouted = true;
            cl.*.animation.current = cl.*.geom;
        }
        cl.*.need_output_flush = false;
        return;
    }

    cl.*.animation.initial = cl.*.animation.current;
    cl.*.animation.time_started = get_now_in_ms();
    cl.*.animation.running = true;
    cl.*.need_output_flush = true;
    request_fresh_all_monitors();
}

export fn client_commit(cl: [*c]Client) callconv(.c) void {
    cl.*.current = cl.*.pending;

    if (cl.*.animation.should_animate) {
        if (!cl.*.animation.running)
            cl.*.animation.current = cl.*.animainit_geom;

        cl.*.animation.initial = cl.*.animainit_geom;
        cl.*.animation.time_started = get_now_in_ms();
        cl.*.animation.running = true;
        cl.*.animation.should_animate = false;
    } else {
        if (!cl.*.animation.running)
            cl.*.animation.current = cl.*.geom;
    }

    // When animation is disabled, set the surface position and size early
    // so pointer_process_motion focus does not hit the surface from the
    // previous frame.
    if (!client_animations_enabled(cl))
        client_apply_finish_geometry(cl);

    request_fresh_all_monitors();
}

export fn client_set_pending_state(cl: [*c]Client) callconv(.c) void {
    if (cl == null or cl.*.iskilling != 0)
        return;

    if (!client_animations_enabled(cl)) {
        cl.*.animation.should_animate = false;
    } else if (cl.*.animation.tagining) {
        cl.*.animation.should_animate = true;
    } else if (cl.*.animation.action == c.OVERVIEW and
        cl.*.animation.overview_enter_anim_set)
    {
        // Overview enter animation: force start after setting the zoom; not
        // forced during pre-arrangement to avoid jitter.
        cl.*.animation.should_animate = true;
    } else if (cl == c.server.grab_client or
        (!cl.*.is_pending_open_animation and
            c.wlr_box_equal(&cl.*.current, &cl.*.pending)))
    {
        cl.*.animation.should_animate = false;
    } else {
        cl.*.animation.should_animate = true;
    }

    if (openAnimationType(cl) == c.ANIM_TYPE_NONE and cl.*.animation.action == c.OPEN)
        cl.*.animation.duration = 0;

    if (c.server.start_drag_window) {
        cl.*.animation.should_animate = false;
        cl.*.animation.duration = 0;
    }

    if (cl.*.no_animation != 0) {
        cl.*.animation.should_animate = false;
        cl.*.animation.duration = 0;
    }

    client_commit(cl);
    cl.*.dirty = true;
}

export fn resize(cl: [*c]Client, geo: c.struct_wlr_box, opts: c.ResizeOpts) callconv(.c) void {
    if (cl == null or cl.*.mon == null or !client_surface(cl).*.mapped)
        return;

    cl.*.need_output_flush = true;
    cl.*.dirty = true;

    const bbox: [*c]c.struct_wlr_box = if (opts.interact or cl.*.isfloating != 0 or
        cl.*.isfullscreen != 0)
        &c.server.scene_geometry
    else
        &cl.*.mon.*.w;

    var clip: c.struct_wlr_box = undefined;

    const bw: i32 = @intCast(cl.*.bw);
    if (is_scroller_layout(cl.*.mon) and
        (cl.*.isfloating == 0 or cl == c.server.grab_client))
    {
        cl.*.geom = geo;
        cl.*.geom.width = @max(1 + 2 * bw, cl.*.geom.width);
        cl.*.geom.height = @max(1 + 2 * bw, cl.*.geom.height);
    } else {
        cl.*.geom = geo;
        client_apply_bounds(cl, bbox);
    }

    if (cl.*.no_size_hint == 0 and cl.*.ismaximizescreen == 0 and
        cl.*.isfullscreen == 0 and cl.*.isfloating != 0)
    {
        const anchor_right = cl.*.geom.x + cl.*.geom.width;
        const anchor_bottom = cl.*.geom.y + cl.*.geom.height;
        client_set_size_bound(cl);
        if (opts.drag_edge & c.WLR_EDGE_LEFT != 0)
            cl.*.geom.x = anchor_right - cl.*.geom.width;
        if (opts.drag_edge & c.WLR_EDGE_TOP != 0)
            cl.*.geom.y = anchor_bottom - cl.*.geom.height;
    }

    if (!cl.*.is_pending_open_animation)
        cl.*.animation.begin_fade_in = false;

    if (cl.*.animation.overining) {
        cl.*.animation.action = c.OVERVIEW;
        cl.*.animation.duration = c.config.animation_duration_tag;
    } else if (cl.*.animation.action == c.OPEN and !cl.*.animation.tagining and
        !cl.*.animation.tagouting and c.wlr_box_equal(&cl.*.geom, &cl.*.current))
    {
        // keep current action
    } else if (cl.*.animation.tagouting) {
        cl.*.animation.duration = c.config.animation_duration_tag;
        cl.*.animation.action = c.TAG;
    } else if (cl.*.animation.tagining) {
        cl.*.animation.duration = c.config.animation_duration_tag;
        cl.*.animation.action = c.TAG;
    } else if (cl.*.is_pending_open_animation) {
        cl.*.animation.duration = c.config.animation_duration_open;
        cl.*.animation.action = c.OPEN;
    } else {
        cl.*.animation.duration = c.config.animation_duration_move;
        cl.*.animation.action = c.MOVE;
    }

    if (cl.*.animation.tagouting) {
        cl.*.animainit_geom = cl.*.animation.current;
    } else if (cl.*.animation.tagining) {
        cl.*.animainit_geom.height = cl.*.animation.current.height;
        cl.*.animainit_geom.width = cl.*.animation.current.width;
    } else if (cl.*.is_pending_open_animation) {
        set_client_open_animation(cl, cl.*.geom);
    } else {
        cl.*.animainit_geom = cl.*.animation.current;
    }

    if (cl.*.no_border != 0 or cl.*.iskilling != 0)
        cl.*.bw = 0
    else if (cl.*.isfullscreen == 0)
        cl.*.bw = c.config.borderpx;

    const hit_no_border = check_hit_no_border(cl);
    if (hit_no_border) {
        cl.*.bw = 0;
        cl.*.fake_no_border = true;
    } else {
        cl.*.fake_no_border = false;
    }

    if (cl.*.mon.*.isoverview == 0) {
        const inner_width: u32 = @intCast(cl.*.geom.width - 2 * @as(i32, @intCast(cl.*.bw)));
        const inner_height: u32 = @intCast(cl.*.geom.height - 2 * @as(i32, @intCast(cl.*.bw)));
        cl.*.configure_serial = client_set_size(cl, inner_width, inner_height, opts.force_configure);
    }

    if (cl.*.configure_serial != 0)
        cl.*.mon.*.resizing_count_pending += 1;

    if (cl == c.server.grab_client) {
        const offsets = compute_edge_offsets(cl);

        cl.*.animation.running = false;
        cl.*.animation.tagining = false;
        cl.*.animation.tagouting = false;
        cl.*.need_output_flush = false;
        cl.*.animainit_geom = cl.*.geom;
        cl.*.current = cl.*.geom;
        cl.*.pending = cl.*.geom;
        cl.*.animation.current = cl.*.geom;
        c.wlr_scene_node_set_position(&cl.*.scene.*.node, cl.*.geom.x, cl.*.geom.y);

        client_draw_border(cl, offsets);
        client_get_clip(cl, &clip);
        client_draw_group_bar(cl, offsets);
        client_draw_tabbar(cl, offsets);
        client_draw_shadow(cl, offsets);

        const surface_clip_offset = clip_to_hide(cl, &clip, offsets);
        client_draw_shield(cl, surface_clip_offset);
        client_draw_dim(cl, surface_clip_offset);
        client_draw_blur(cl, surface_clip_offset);

        if (client_is_x11(cl) != 0)
            client_update_xwayland_clip(cl, &clip)
        else
            c.wlr_scene_subsurface_tree_set_clip(&cl.*.scene_surface.*.node, &clip);
        return;
    }

    if (!cl.*.animation.tagouting and cl.*.iskilling == 0)
        cl.*.pending = cl.*.geom;

    if (cl.*.swallowing != null and cl.*.animation.action == c.OPEN)
        cl.*.animainit_geom = cl.*.swallowing.*.animation.current;

    if (cl.*.swallowdby != null)
        cl.*.animainit_geom = cl.*.geom;

    if ((cl.*.isglobal != 0 or cl.*.isunglobal != 0) and cl.*.isfloating != 0 and
        cl.*.animation.action == c.TAG)
        cl.*.animainit_geom = cl.*.geom;

    if (cl.*.scratchpad_switching_mon and cl.*.isfloating != 0)
        cl.*.animainit_geom = cl.*.geom;

    if (!opts.skip_ov_enter_anim and cl.*.mon.*.isoverview != 0 and
        cl.*.animation.overining and !cl.*.animation.overview_enter_anim_set)
    {
        set_overview_enter_animation(cl);
        cl.*.animation.overining = false;
        cl.*.animation.overview_enter_anim_set = true;
    }

    client_set_pending_state(cl);
    client_update_border_color(cl);
}

// ---------------------------------------------------------------------------
// commit/resize tests (slice 90)
// ---------------------------------------------------------------------------

extern var stub_bounds_calls: c_int;
extern var stub_bounds: c.struct_wlr_box;
extern var stub_size_bound_calls: c_int;
extern var stub_set_size_calls: c_int;
extern var stub_set_size_w: u32;
extern var stub_set_size_h: u32;
extern var stub_set_size_force: c_int;
extern var stub_configure_serial: u32;
extern var stub_border_color_update_calls: c_int;

fn resetResizeWorld() void {
    resetDropWorld();
    c.config.borderpx = 2;
    c.config.animation_duration_move = 150;
    c.config.animation_duration_open = 200;
    c.config.animation_duration_tag = 250;
    test_client.scene = &test_fadeout_tree;
    test_client.current = .{ .x = 0, .y = 0, .width = 100, .height = 80 };
    test_client.pending = test_client.current;
    test_client.geom = test_client.current;
    test_client.animainit_geom = test_client.current;
    test_client.animation.current = test_client.current;
    test_client.animation.initial = test_client.current;
    test_client.animation.duration = 100;
    test_client.animation.time_started = 0;
    test_client.animation.running = false;
    test_client.animation.should_animate = false;
    test_client.animation.action = c.MOVE;
    test_client.animation.tagining = false;
    test_client.animation.tagouting = false;
    test_client.animation.tagouted = false;
    test_client.animation.overining = false;
    test_client.animation.overview_enter_anim_set = false;
    test_client.is_pending_open_animation = false;
    test_client.no_animation = 0;
    test_client.no_border = 0;
    test_client.no_size_hint = 0;
    test_client.isfloating = 0;
    test_client.isfullscreen = 0;
    test_client.ismaximizescreen = 0;
    test_client.iskilling = 0;
    test_client.isglobal = 0;
    test_client.isunglobal = 0;
    test_client.dirty = false;
    test_client.need_output_flush = false;
    test_client.configure_serial = 0;
    test_client.swallowing = null;
    test_client.swallowdby = null;
    test_client.scratchpad_switching_mon = false;
    test_client.ov_card_tree = null;
    test_client.overview_scene_surface = null;
    test_client.overview_backup_geom = .{ .x = 3, .y = 4, .width = 50, .height = 40 };
    test_mon.isoverview = 0;
    test_mon.resizing_count_pending = 0;
    c.server.grab_client = null;
    c.server.start_drag_window = false;
    stub_bounds_calls = 0;
    stub_bounds = std.mem.zeroes(c.struct_wlr_box);
    stub_size_bound_calls = 0;
    stub_set_size_calls = 0;
    stub_set_size_w = 0;
    stub_set_size_h = 0;
    stub_set_size_force = 0;
    stub_configure_serial = 0;
    stub_border_color_update_calls = 0;
    stub_curve = -1;
    stub_now_ms = 0;
    stub_get_now_ms = 1000;
    stub_surface_clip_calls = 0;
    stub_xwayland_clip_calls = 0;
    stub_is_x11 = 0;
    stub_iterate = 0;
    stub_gesture = 0;
}

fn lastPosFor(node: [*c]c.struct_wlr_scene_node) [2]i32 {
    var i: c_int = stub_node_pos_calls - 1;
    while (i >= 0) : (i -= 1) {
        if (stub_pos_node[@intCast(i)] == node)
            return .{ stub_pos_x[@intCast(i)], stub_pos_y[@intCast(i)] };
    }
    return .{ -9999, -9999 };
}

test "finish geometry snaps every box and clears the flush flag" {
    resetResizeWorld();
    c.config.animations = 0;
    test_client.pending = .{ .x = 10, .y = 20, .width = 100, .height = 80 };
    test_client.geom = .{ .x = 5, .y = 6, .width = 70, .height = 60 };
    test_client.need_output_flush = true;
    client_apply_finish_geometry(&test_client);
    const scene_pos = lastPosFor(&test_fadeout_tree.node);
    try testing.expectEqual(@as(i32, 10), scene_pos[0]);
    try testing.expectEqual(@as(i32, 20), scene_pos[1]);
    try testing.expectEqual(@as(i32, 70), test_client.animation.current.width);
    try testing.expectEqual(@as(i32, 70), test_client.pending.width);
    try testing.expectEqual(@as(i32, 70), test_client.current.width);
    try testing.expect(!test_client.need_output_flush);
    try testing.expectEqual(@as(c_int, 1), stub_get_clip_calls);
}

test "set progress clamps and rounds interpolated boxes" {
    resetResizeWorld();
    c.config.animations = 1;
    test_client.animation.initial = .{ .x = 0, .y = 0, .width = 10, .height = 10 };
    test_client.current = .{ .x = 5, .y = 5, .width = 20, .height = 20 };
    client_animation_set_progress(&test_client, 0.5);
    try testing.expectEqual(@as(i32, 3), test_client.animation.current.x);
    try testing.expectEqual(@as(i32, 15), test_client.animation.current.width);
    client_animation_set_progress(&test_client, -1.0);
    try testing.expectEqual(@as(i32, 0), test_client.animation.current.x);
    try testing.expectEqual(@as(i32, 10), test_client.animation.current.width);
}

test "resume either restarts timing or snaps to the current box" {
    resetResizeWorld();
    client_animation_resume(&test_client, 0.5);
    try testing.expectEqual(@as(i32, 100), test_client.animation.initial.width);

    c.config.animations = 1;
    test_client.animation.running = true;
    test_client.animation.current = .{ .x = 7, .y = 8, .width = 30, .height = 20 };
    test_client.animation.initial = .{ .x = 0, .y = 0, .width = 1, .height = 1 };
    stub_get_now_ms = 333;
    client_animation_resume(&test_client, 0.5);
    try testing.expectEqual(@as(i32, 30), test_client.animation.initial.width);
    try testing.expectEqual(@as(u32, 333), test_client.animation.time_started);
    try testing.expect(test_client.need_output_flush);
    try testing.expectEqual(@as(c_int, 1), stub_fresh_monitors_calls);

    test_client.geom = .{ .x = 1, .y = 2, .width = 60, .height = 40 };
    test_client.animation.tagouting = true;
    client_animation_resume(&test_client, 0.01);
    try testing.expect(!test_client.animation.running);
    try testing.expect(test_client.animation.tagouted);
    try testing.expectEqual(@as(i32, 60), test_client.animation.current.width);
}

test "commit starts animations or snaps when disabled" {
    resetResizeWorld();
    test_client.animainit_geom = .{ .x = 1, .y = 2, .width = 30, .height = 40 };
    test_client.geom = .{ .x = 5, .y = 6, .width = 70, .height = 80 };
    test_client.pending = test_client.geom;
    test_client.animation.should_animate = true;
    c.config.animations = 1;
    stub_get_now_ms = 444;
    client_commit(&test_client);
    try testing.expectEqual(@as(i32, 30), test_client.animation.current.width);
    try testing.expectEqual(@as(i32, 30), test_client.animation.initial.width);
    try testing.expect(test_client.animation.running);
    try testing.expect(!test_client.animation.should_animate);
    try testing.expectEqual(@as(u32, 444), test_client.animation.time_started);

    resetResizeWorld();
    c.config.animations = 0;
    test_client.pending = .{ .x = 5, .y = 6, .width = 70, .height = 80 };
    test_client.current = .{ .x = 0, .y = 0, .width = 1, .height = 1 };
    test_client.geom = test_client.pending;
    client_commit(&test_client);
    try testing.expectEqual(@as(i32, 70), test_client.animation.current.width);
    try testing.expectEqual(@as(c_int, 1), stub_get_clip_calls);
}

test "pending state respects grab, drag, overview and equality" {
    resetResizeWorld();
    c.config.animations = 1;
    test_client.animation.tagining = true;
    client_set_pending_state(&test_client);
    try testing.expect(test_client.animation.running);

    resetResizeWorld();
    c.config.animations = 1;
    test_client.current = .{ .x = 1, .y = 2, .width = 3, .height = 4 };
    test_client.pending = test_client.current;
    client_set_pending_state(&test_client);
    try testing.expect(!test_client.animation.running);

    resetResizeWorld();
    c.config.animations = 1;
    test_client.animation.action = c.OVERVIEW;
    test_client.animation.overview_enter_anim_set = true;
    client_set_pending_state(&test_client);
    try testing.expect(test_client.animation.running);

    resetResizeWorld();
    c.config.animations = 1;
    c.server.start_drag_window = true;
    test_client.pending = .{ .x = 9, .y = 9, .width = 9, .height = 9 };
    client_set_pending_state(&test_client);
    try testing.expect(!test_client.animation.should_animate);
    try testing.expectEqual(@as(u32, 0), test_client.animation.duration);

    resetResizeWorld();
    c.config.animations = 1;
    test_client.no_animation = 1;
    client_set_pending_state(&test_client);
    try testing.expect(!test_client.animation.should_animate);
    try testing.expectEqual(@as(u32, 0), test_client.animation.duration);
}

test "resize applies bounds, border and pending state" {
    resetResizeWorld();
    c.config.animations = 0;
    test_client.isfloating = 1;
    stub_configure_serial = 5;
    const geo = c.struct_wlr_box{ .x = 10, .y = 20, .width = 100, .height = 80 };
    const opts = c.ResizeOpts{ .interact = true, .skip_ov_enter_anim = false, .force_configure = true, .drag_edge = 0 };
    resize(&test_client, geo, opts);
    try testing.expectEqual(@as(c_int, 1), stub_bounds_calls);
    try testing.expectEqual(@as(i32, 100), test_client.geom.width);
    try testing.expectEqual(@as(u32, 2), test_client.bw);
    try testing.expectEqual(@as(u32, 96), stub_set_size_w);
    try testing.expectEqual(@as(u32, 76), stub_set_size_h);
    try testing.expectEqual(@as(c_int, 1), stub_set_size_force);
    try testing.expectEqual(@as(u32, 5), test_client.configure_serial);
    try testing.expectEqual(@as(u32, 1), test_mon.resizing_count_pending);
    try testing.expectEqual(@as(i32, 100), test_client.pending.width);
    try testing.expectEqual(@as(i32, c.MOVE), test_client.animation.action);
    try testing.expectEqual(@as(u32, 150), test_client.animation.duration);
    try testing.expectEqual(@as(c_int, 1), stub_border_color_update_calls);
}

test "resize clamps scroller windows to the minimum size" {
    resetResizeWorld();
    stub_scroller = 1;
    test_client.isfloating = 0;
    test_client.bw = 2;
    const geo = c.struct_wlr_box{ .x = 0, .y = 0, .width = 1, .height = 2 };
    const opts = std.mem.zeroes(c.ResizeOpts);
    resize(&test_client, geo, opts);
    try testing.expectEqual(@as(i32, 5), test_client.geom.width);
    try testing.expectEqual(@as(i32, 5), test_client.geom.height);
    try testing.expectEqual(@as(c_int, 0), stub_bounds_calls);
}

test "resize grab path redraws and clips without pending state" {
    resetResizeWorld();
    c.server.grab_client = &test_client;
    test_client.isfloating = 1;
    stub_is_x11 = 1;
    test_client.pending = .{ .x = 1, .y = 1, .width = 1, .height = 1 };
    const geo = c.struct_wlr_box{ .x = 10, .y = 20, .width = 100, .height = 80 };
    const opts = std.mem.zeroes(c.ResizeOpts);
    resize(&test_client, geo, opts);
    const scene_pos = lastPosFor(&test_fadeout_tree.node);
    try testing.expectEqual(@as(i32, 10), scene_pos[0]);
    try testing.expectEqual(@as(i32, 20), scene_pos[1]);
    try testing.expectEqual(@as(c_int, 1), stub_get_clip_calls);
    try testing.expectEqual(@as(c_int, 1), stub_xwayland_clip_calls);
    try testing.expectEqual(@as(i32, 100), test_client.pending.width);
    try testing.expect(!test_client.animation.running);
    try testing.expectEqual(@as(c_int, 1), stub_tabbar_calls);
}

test "resize overview entry uses backup geometry and flags the animation" {
    resetResizeWorld();
    c.config.animations = 1;
    test_mon.isoverview = 1;
    test_client.animation.overining = true;
    test_client.overview_backup_geom = .{ .x = 3, .y = 4, .width = 50, .height = 40 };
    const geo = c.struct_wlr_box{ .x = 10, .y = 20, .width = 100, .height = 80 };
    const opts = std.mem.zeroes(c.ResizeOpts);
    resize(&test_client, geo, opts);
    try testing.expectEqual(@as(i32, 50), test_client.animainit_geom.width);
    try testing.expect(!test_client.animation.overining);
    try testing.expect(test_client.animation.overview_enter_anim_set);
    try testing.expectEqual(@as(i32, c.OVERVIEW), test_client.animation.action);
    try testing.expectEqual(@as(c_int, 0), stub_set_size_calls);
}

// ---------------------------------------------------------------------------
// focus animation + frame entry points (slice 91)
// ---------------------------------------------------------------------------

extern fn get_border_color(cl: [*c]Client) callconv(.c) [*c]f32;
extern fn get_dim_color(cl: [*c]Client) callconv(.c) [*c]f32;
extern fn client_set_opacity(cl: [*c]Client, opacity: f64) callconv(.c) void;
extern fn client_set_state_colors(cl: [*c]Client, border_color: [*c]const f32, dim_color: [*c]const f32) callconv(.c) void;
extern fn client_blur_uses_wallpaper(cl: [*c]Client) callconv(.c) bool;
extern fn client_force_render(cl: [*c]Client) callconv(.c) bool;

export fn client_draw_fadeout_frame(cl: [*c]Client) callconv(.c) bool {
    if (cl == null)
        return false;

    fadeout_client_animation_next_tick(cl);
    return true;
}

export fn client_start_focus_animation(cl: [*c]Client, focused: bool) callconv(.c) void {
    const border_color = get_border_color(cl);
    const dim_color = get_dim_color(cl);

    cl.*.opacity_animation.duration = c.config.animation_duration_focus;
    cl.*.opacity_animation.target_opacity = if (focused) cl.*.focused_opacity else cl.*.unfocused_opacity;
    @memcpy(cl.*.opacity_animation.target_border_color[0..4], border_color[0..4]);
    @memcpy(cl.*.opacity_animation.target_dim_color[0..4], dim_color[0..4]);
    cl.*.opacity_animation.initial_opacity = cl.*.opacity_animation.current_opacity;
    @memcpy(cl.*.opacity_animation.initial_border_color[0..4], cl.*.opacity_animation.current_border_color[0..4]);
    @memcpy(cl.*.opacity_animation.initial_dim_color[0..4], cl.*.opacity_animation.current_dim_color[0..4]);
    cl.*.opacity_animation.time_started = get_now_in_ms();
    cl.*.opacity_animation.running = true;
}

fn interpolateFocusAnimation(cl: [*c]Client, linear_progress: f64) void {
    const eased_progress = find_animation_curve_at(linear_progress, c.FOCUS);

    cl.*.opacity_animation.current_opacity = cl.*.opacity_animation.initial_opacity +
        (cl.*.opacity_animation.target_opacity - cl.*.opacity_animation.initial_opacity) *
            @as(f32, @floatCast(eased_progress));

    var i: usize = 0;
    while (i < 4) : (i += 1) {
        cl.*.opacity_animation.current_border_color[i] =
            cl.*.opacity_animation.initial_border_color[i] +
            (cl.*.opacity_animation.target_border_color[i] -
                cl.*.opacity_animation.initial_border_color[i]) * @as(f32, @floatCast(eased_progress));
        cl.*.opacity_animation.current_dim_color[i] =
            cl.*.opacity_animation.initial_dim_color[i] +
            (cl.*.opacity_animation.target_dim_color[i] -
                cl.*.opacity_animation.initial_dim_color[i]) * @as(f32, @floatCast(eased_progress));
    }
}

export fn client_step_focus_animation(cl: [*c]Client, linear_progress: f64) callconv(.c) bool {
    interpolateFocusAnimation(cl, linear_progress);

    client_set_opacity(cl, cl.*.opacity_animation.current_opacity);
    client_set_state_colors(cl, &cl.*.opacity_animation.current_border_color, &cl.*.opacity_animation.current_dim_color);

    cl.*.opacity_animation.running = linear_progress < 1.0;
    return cl.*.opacity_animation.running;
}

export fn client_set_unfocused_opacity_animation(cl: [*c]Client) callconv(.c) void {
    c.wlr_scene_node_raise_to_top(&cl.*.border.*.node);
    if (c.config.animations == 0) {
        client_update_border_color(cl);
        return;
    }

    client_start_focus_animation(cl, false);
}

export fn client_set_focused_opacity_animation(cl: [*c]Client) callconv(.c) void {
    c.wlr_scene_node_lower_to_bottom(&cl.*.border.*.node);

    if (c.config.animations == 0) {
        client_update_border_color(cl);
        return;
    }

    client_start_focus_animation(cl, true);
}

export fn client_apply_focus_opacity(cl: [*c]Client) callconv(.c) bool {
    if (c.config.blur != 0 and cl.*.no_blur == 0 and cl.*.blur_opacity != 1.0 and
        cl.*.animation.action != c.OPEN)
    {
        cl.*.blur_opacity = 1.0;
        c.wlr_scene_blur_set_strength(cl.*.blur, 1.0);
        c.wlr_scene_blur_set_alpha(cl.*.blur, 1.0);
    }

    const border_color = get_border_color(cl);
    if (cl.*.isfullscreen != 0) {
        cl.*.opacity_animation.running = false;
        client_set_opacity(cl, 1);
    } else if (cl.*.animation.running and cl.*.animation.action == c.OPEN) {
        var now: c.struct_timespec = undefined;
        _ = c.clock_gettime(c.CLOCK_MONOTONIC, &now);

        const passed_time: i32 = @bitCast(timespec_to_ms(&now) -% cl.*.animation.time_started);
        const linear_progress: f64 = if (cl.*.animation.duration != 0)
            @as(f64, @floatFromInt(passed_time)) / @as(f64, @floatFromInt(cl.*.animation.duration))
        else
            1.0;

        const opacity_eased_progress = find_animation_curve_at(linear_progress, c.OPAFADEIN);
        const percent: f32 = if (c.config.animation_fade_in != 0 and cl.*.no_fade_in == 0)
            @floatCast(opacity_eased_progress)
        else
            1.0;
        var opacity: f32 = if (c.server.selected_monitor != null and
            cl == c.server.selected_monitor.*.sel)
            cl.*.focused_opacity
        else
            cl.*.unfocused_opacity;
        var target_opacity = percent * (1.0 - c.config.fadein_begin_opacity) +
            c.config.fadein_begin_opacity;

        if (c.config.animations != 0 and cl.*.opacity_animation.running) {
            const focus_passed: i32 = @bitCast(timespec_to_ms(&now) -% cl.*.opacity_animation.time_started);
            const focus_progress: f64 = if (cl.*.opacity_animation.duration != 0)
                @as(f64, @floatFromInt(focus_passed)) / @as(f64, @floatFromInt(cl.*.opacity_animation.duration))
            else
                1.0;

            interpolateFocusAnimation(cl, focus_progress);
            opacity = cl.*.opacity_animation.current_opacity;
            if (focus_progress >= 1.0)
                cl.*.opacity_animation.running = false;
        } else {
            @memcpy(cl.*.opacity_animation.current_border_color[0..4], cl.*.opacity_animation.target_border_color[0..4]);
            @memcpy(cl.*.opacity_animation.current_dim_color[0..4], cl.*.opacity_animation.target_dim_color[0..4]);
        }

        if (target_opacity > opacity)
            target_opacity = opacity;

        cl.*.opacity_animation.current_opacity = target_opacity;
        client_set_opacity(cl, target_opacity);
        if (c.config.blur != 0 and cl.*.no_blur == 0 and !client_blur_uses_wallpaper(cl)) {
            const blur_val = @min(percent * (1.0 - c.config.fadein_begin_opacity) +
                c.config.fadein_begin_opacity, 1.0);
            cl.*.blur_opacity = blur_val;
            c.wlr_scene_blur_set_strength(cl.*.blur, blur_val);
            c.wlr_scene_blur_set_alpha(cl.*.blur, blur_val);
        }
        client_set_state_colors(cl, &cl.*.opacity_animation.current_border_color, &cl.*.opacity_animation.current_dim_color);
    } else if (c.config.animations != 0 and cl.*.opacity_animation.running) {
        var now: c.struct_timespec = undefined;
        _ = c.clock_gettime(c.CLOCK_MONOTONIC, &now);

        const passed_time: i32 = @bitCast(timespec_to_ms(&now) -% cl.*.opacity_animation.time_started);
        const linear_progress: f64 = if (cl.*.opacity_animation.duration != 0)
            @as(f64, @floatFromInt(passed_time)) / @as(f64, @floatFromInt(cl.*.opacity_animation.duration))
        else
            1.0;

        if (client_step_focus_animation(cl, linear_progress))
            return true;
    } else if (c.server.selected_monitor != null and cl == c.server.selected_monitor.*.sel) {
        cl.*.opacity_animation.running = false;
        cl.*.opacity_animation.current_opacity = cl.*.focused_opacity;
        @memcpy(cl.*.opacity_animation.current_border_color[0..4], border_color[0..4]);
        const dim_color = get_dim_color(cl);
        @memcpy(cl.*.opacity_animation.current_dim_color[0..4], dim_color[0..4]);
        client_set_opacity(cl, cl.*.focused_opacity);
    } else {
        cl.*.opacity_animation.running = false;
        cl.*.opacity_animation.current_opacity = cl.*.unfocused_opacity;
        @memcpy(cl.*.opacity_animation.current_border_color[0..4], border_color[0..4]);
        const dim_color = get_dim_color(cl);
        @memcpy(cl.*.opacity_animation.current_dim_color[0..4], dim_color[0..4]);
        client_set_opacity(cl, cl.*.unfocused_opacity);
    }

    return false;
}

export fn client_draw_frame(cl: [*c]Client) callconv(.c) bool {
    var need_next_tick = false;

    if (cl == null or !client_surface(cl).*.mapped)
        return false;

    // always render when scene is disabled
    if (cl.*.force_render != 0 and !cl.*.scene.*.node.enabled) {
        const force_render = client_force_render(cl);
        need_next_tick = force_render or need_next_tick;
    }

    if (c.server.gesture_drive_active and cl.*.mon == c.server.gesture_drive_mon and
        cl.*.animation.running and cl.*.need_output_flush)
        return client_apply_focus_opacity(cl);

    if (!cl.*.need_output_flush)
        return client_apply_focus_opacity(cl) or need_next_tick;

    if (c.config.animations != 0 and cl.*.animation.running) {
        need_next_tick = true;
        client_animation_next_tick(cl);
    } else {
        client_apply_finish_geometry(cl);
    }

    const need_fade_focus = client_apply_focus_opacity(cl);

    return need_next_tick or need_fade_focus;
}

// ---------------------------------------------------------------------------
// focus/frame tests (slice 91)
// ---------------------------------------------------------------------------

extern var stub_get_border_color: [4]f32;
extern var stub_get_dim_color: [4]f32;
extern var stub_set_opacity_calls: c_int;
extern var stub_set_opacity_value: f32;
extern var stub_state_colors_calls: c_int;
extern var stub_state_border: [4]f32;
extern var stub_state_dim: [4]f32;
extern var stub_blur_strength_calls: c_int;
extern var stub_blur_alpha_calls: c_int;
extern var stub_blur_strength: f32;
extern var stub_blur_alpha: f32;
extern var stub_blur_wallpaper: c_int;
extern var stub_force_render_result: c_int;
extern var stub_clock_calls: c_int;

fn resetFocusWorld() void {
    resetResizeWorld();
    test_client.border = &test_border;
    test_client.blur = &test_blur;
    test_client.scene.*.node.enabled = true;
    test_client.isfullscreen = 0;
    test_client.force_render = 0;
    test_client.need_output_flush = false;
    test_client.blur_opacity = 1.0;
    test_client.no_blur = 0;
    test_client.no_fade_in = 0;
    test_client.focused_opacity = 1.0;
    test_client.unfocused_opacity = 0.8;
    test_client.animation.action = c.MOVE;
    test_client.animation.running = false;
    test_client.opacity_animation = std.mem.zeroes(c.struct_acwm_opacity_animation);
    test_client.opacity_animation.current_opacity = 0.5;
    test_client.opacity_animation.current_border_color = .{ 0.01, 0.02, 0.03, 0.04 };
    test_client.opacity_animation.current_dim_color = .{ 0.05, 0.06, 0.07, 0.08 };
    c.config.animation_duration_focus = 120;
    c.config.fadein_begin_opacity = 0.2;
    c.config.animation_fade_in = 1;
    c.server.selected_monitor = null;
    c.server.gesture_drive_active = false;
    c.server.gesture_drive_mon = null;
    stub_get_border_color = .{ 0.1, 0.2, 0.3, 1.0 };
    stub_get_dim_color = .{ 0.4, 0.5, 0.6, 1.0 };
    stub_set_opacity_calls = 0;
    stub_set_opacity_value = -1;
    stub_state_colors_calls = 0;
    stub_state_border = std.mem.zeroes([4]f32);
    stub_state_dim = std.mem.zeroes([4]f32);
    stub_blur_strength_calls = 0;
    stub_blur_alpha_calls = 0;
    stub_blur_strength = -1;
    stub_blur_alpha = -1;
    stub_blur_wallpaper = 0;
    stub_force_render_result = 0;
    stub_lower_calls = 0;
    stub_raise_calls = 0;
    stub_border_color_update_calls = 0;
    stub_curve = -1;
    stub_now_ms = 0;
    stub_get_now_ms = 1000;
    stub_clock_calls = 0;
}

test "start focus animation captures targets and current colors" {
    resetFocusWorld();
    client_start_focus_animation(&test_client, false);
    try testing.expectEqual(@as(u32, 120), test_client.opacity_animation.duration);
    try testing.expectEqual(@as(f32, 0.8), test_client.opacity_animation.target_opacity);
    try testing.expectEqual(@as(f32, 0.5), test_client.opacity_animation.initial_opacity);
    try testing.expectEqual(@as(f32, 0.1), test_client.opacity_animation.target_border_color[0]);
    try testing.expectEqual(@as(f32, 0.01), test_client.opacity_animation.initial_border_color[0]);
    try testing.expectEqual(@as(u32, 1000), test_client.opacity_animation.time_started);
    try testing.expect(test_client.opacity_animation.running);
}

test "step focus animation interpolates opacity and colors" {
    resetFocusWorld();
    test_client.opacity_animation.initial_opacity = 0.0;
    test_client.opacity_animation.target_opacity = 1.0;
    test_client.opacity_animation.initial_border_color = .{ 0, 0, 0, 0 };
    test_client.opacity_animation.target_border_color = .{ 1, 1, 1, 1 };
    test_client.opacity_animation.initial_dim_color = .{ 0, 0, 0, 0 };
    test_client.opacity_animation.target_dim_color = .{ 1, 1, 1, 1 };
    const running = client_step_focus_animation(&test_client, 0.5);
    try testing.expect(running);
    try testing.expectEqual(@as(f32, 0.5), stub_set_opacity_value);
    try testing.expectEqual(@as(f32, 0.5), stub_state_border[0]);
    try testing.expectEqual(@as(f32, 0.5), stub_state_dim[0]);

    const still_running = client_step_focus_animation(&test_client, 1.0);
    try testing.expect(!still_running);
    try testing.expectEqual(@as(f32, 1.0), stub_set_opacity_value);
    try testing.expect(!test_client.opacity_animation.running);
}

test "focus setters raise/lower and honor disabled animations" {
    resetFocusWorld();
    c.config.animations = 0;
    client_set_unfocused_opacity_animation(&test_client);
    try testing.expectEqual(@as(c_int, 1), stub_raise_calls);
    try testing.expectEqual(@as(c_int, 1), stub_border_color_update_calls);
    try testing.expect(!test_client.opacity_animation.running);

    client_set_focused_opacity_animation(&test_client);
    try testing.expectEqual(@as(c_int, 1), stub_lower_calls);
    try testing.expect(!test_client.opacity_animation.running);

    c.config.animations = 1;
    client_set_focused_opacity_animation(&test_client);
    try testing.expect(test_client.opacity_animation.running);
    try testing.expectEqual(@as(f32, 1.0), test_client.opacity_animation.target_opacity);
    client_set_unfocused_opacity_animation(&test_client);
    try testing.expectEqual(@as(f32, 0.8), test_client.opacity_animation.target_opacity);
}

test "focus opacity handles fullscreen and blur reset" {
    resetFocusWorld();
    test_client.isfullscreen = 1;
    try testing.expect(!client_apply_focus_opacity(&test_client));
    try testing.expectEqual(@as(f32, 1.0), stub_set_opacity_value);
    try testing.expect(!test_client.opacity_animation.running);

    resetFocusWorld();
    c.config.blur = 1;
    test_client.blur_opacity = 0.5;
    test_client.animation.action = c.MOVE;
    _ = client_apply_focus_opacity(&test_client);
    try testing.expectEqual(@as(f32, 1.0), test_client.blur_opacity);
    try testing.expectEqual(@as(c_int, 1), stub_blur_strength_calls);
    try testing.expectEqual(@as(c_int, 1), stub_blur_alpha_calls);
    try testing.expectEqual(@as(f32, 1.0), stub_blur_strength);
}

test "focus opacity fades an opening window and blur" {
    resetFocusWorld();
    c.config.animations = 1;
    c.config.blur = 1;
    test_client.animation.action = c.OPEN;
    test_client.animation.running = true;
    test_client.animation.duration = 100;
    test_client.animation.time_started = 0;
    test_client.focused_opacity = 1.0;
    stub_now_ms = 50;
    _ = client_apply_focus_opacity(&test_client);
    try testing.expectEqual(@as(f32, 0.6), stub_set_opacity_value);
    try testing.expectEqual(@as(f32, 0.6), test_client.opacity_animation.current_opacity);
    try testing.expectEqual(@as(c_int, 1), stub_blur_strength_calls);
    try testing.expectEqual(@as(f32, 0.6), stub_blur_strength);
    try testing.expectEqual(@as(f32, 0.6), test_client.blur_opacity);
}

test "focus opacity steps a running focus animation" {
    resetFocusWorld();
    c.config.animations = 1;
    test_client.opacity_animation.running = true;
    test_client.opacity_animation.duration = 100;
    test_client.opacity_animation.time_started = 0;
    test_client.opacity_animation.initial_opacity = 0;
    test_client.opacity_animation.target_opacity = 1;
    stub_now_ms = 50;
    const need_more = client_apply_focus_opacity(&test_client);
    try testing.expect(need_more);
    try testing.expectEqual(@as(f32, 0.5), stub_set_opacity_value);
    try testing.expect(test_client.opacity_animation.running);
}

test "focus opacity settles on selected and unselected clients" {
    resetFocusWorld();
    c.server.selected_monitor = &test_selected_mon;
    test_selected_mon.sel = &test_client;
    _ = client_apply_focus_opacity(&test_client);
    try testing.expectEqual(@as(f32, 1.0), stub_set_opacity_value);
    try testing.expectEqual(@as(f32, 0.1), test_client.opacity_animation.current_border_color[0]);

    test_selected_mon.sel = null;
    _ = client_apply_focus_opacity(&test_client);
    try testing.expectEqual(@as(f32, 0.8), stub_set_opacity_value);
    try testing.expectEqual(@as(f32, 0.8), test_client.opacity_animation.current_opacity);
}

test "draw frame covers force render, gesture and tick paths" {
    resetFocusWorld();
    try testing.expect(!client_draw_frame(null));
    test_draw_surface.mapped = false;
    try testing.expect(!client_draw_frame(&test_client));
    test_draw_surface.mapped = true;

    test_client.force_render = 1;
    test_fadeout_tree.node.enabled = false;
    test_client.need_output_flush = false;
    stub_force_render_result = 1;
    try testing.expect(client_draw_frame(&test_client));

    resetFocusWorld();
    c.server.gesture_drive_active = true;
    c.server.gesture_drive_mon = &test_mon;
    test_client.animation.running = true;
    test_client.need_output_flush = true;
    c.server.selected_monitor = null;
    _ = client_draw_frame(&test_client);
    try testing.expectEqual(@as(c_int, 1), stub_set_opacity_calls);

    resetFocusWorld();
    c.config.animations = 1;
    test_client.animation.running = true;
    test_client.animation.duration = 100;
    test_client.animation.time_started = 0;
    test_client.animation.initial = test_client.animation.current;
    test_client.current = test_client.animation.current;
    test_client.geom = test_client.animation.current;
    test_client.need_output_flush = true;
    stub_now_ms = 50;
    try testing.expect(client_draw_frame(&test_client));
}

test "draw fadeout frame ticks and reports success" {
    resetFocusWorld();
    try testing.expect(!client_draw_fadeout_frame(null));
    test_client.scene = &test_fadeout_tree;
    test_client.animation.duration = 100;
    test_client.animation.time_started = 0;
    stub_now_ms = 50;
    _ = client_draw_fadeout_frame(&test_client);
    try testing.expectEqual(@as(c_int, 1), stub_clock_calls);
}
