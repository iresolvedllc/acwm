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
