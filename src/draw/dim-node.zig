//! Port of src/draw/dim-node.c (Phase 5, draw slice, slice 46).
//!
//! A 1x1 cairo surface wrapped in a wlr_buffer, painted with the dim color
//! and stretched by the scene buffer dest size. C twin guarded with
//! ACWM_ZIG_DIM_NODE.

const std = @import("std");
const c = @import("cc");

const DimBuffer = c.struct_acwm_dim_buffer;
const DimNode = c.AcwmDimNode;
const SceneBuffer = c.struct_wlr_scene_buffer;

const DRM_FORMAT_ARGB8888: u32 = 0x34325241; // 'AR24'

extern "c" fn calloc(nmemb: usize, size: usize) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn memcmp(a: ?*const anyopaque, b: ?*const anyopaque, n: usize) c_int;

fn containerOf(comptime T: type, comptime field: []const u8, ptr: *const anyopaque) *T {
    return @ptrFromInt(@intFromPtr(ptr) - @offsetOf(T, field));
}

fn dimBufferDestroy(buffer: [*c]c.struct_wlr_buffer) callconv(.c) void {
    const buf = containerOf(DimBuffer, "base", buffer);
    if (buf.surface != null)
        c.cairo_surface_destroy(buf.surface);
    free(@ptrCast(buf));
}

fn dimBufferBeginDataPtrAccess(
    buffer: [*c]c.struct_wlr_buffer,
    flags: u32,
    data: [*c]?*anyopaque,
    format: [*c]u32,
    stride: [*c]usize,
) callconv(.c) bool {
    if ((flags & c.WLR_BUFFER_DATA_PTR_ACCESS_WRITE) != 0)
        return false;
    const buf = containerOf(DimBuffer, "base", buffer);
    if (buf.surface == null)
        return false;
    data[0] = @ptrCast(c.cairo_image_surface_get_data(buf.surface));
    format[0] = DRM_FORMAT_ARGB8888;
    stride[0] = @intCast(c.cairo_image_surface_get_stride(buf.surface));
    return true;
}

fn dimBufferEndDataPtrAccess(buffer: [*c]c.struct_wlr_buffer) callconv(.c) void {
    _ = buffer;
}

var dim_buffer_impl: c.struct_wlr_buffer_impl = .{
    .destroy = dimBufferDestroy,
    .begin_data_ptr_access = dimBufferBeginDataPtrAccess,
    .end_data_ptr_access = dimBufferEndDataPtrAccess,
};

fn dimNodeBuildPixel(node: *DimNode) void {
    const surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, 1, 1);
    if (c.cairo_surface_status(surface) != c.CAIRO_STATUS_SUCCESS) {
        c.cairo_surface_destroy(surface);
        return;
    }

    const cr = c.cairo_create(surface);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
    c.cairo_set_source_rgba(cr, node.color[0], node.color[1], node.color[2], node.color[3]);
    c.cairo_paint(cr);
    c.cairo_surface_flush(surface);
    c.cairo_destroy(cr);

    const buf: *DimBuffer = @ptrCast(@alignCast(calloc(1, @sizeOf(DimBuffer)) orelse {
        c.cairo_surface_destroy(surface);
        return;
    }));
    c.wlr_buffer_init(&buf.base, &dim_buffer_impl, 1, 1);
    buf.surface = surface;

    if (node.buffer != null)
        c.wlr_buffer_drop(&node.buffer.*.base);
    node.buffer = @ptrCast(buf);

    c.wlr_scene_buffer_set_buffer(node.scene_buffer, &buf.base);
}

fn dimNodePointAcceptsInput(buffer: [*c]SceneBuffer, sx: [*c]f64, sy: [*c]f64) callconv(.c) bool {
    _ = buffer;
    _ = sx;
    _ = sy;
    return false;
}

export fn acwm_dim_node_create(parent: ?*c.struct_wlr_scene_tree, color: [*c]const [4]f32) callconv(.c) ?*DimNode {
    const tree = parent orelse return null;

    const node: *DimNode = @ptrCast(@alignCast(calloc(1, @sizeOf(DimNode)) orelse return null));
    node.scene_buffer = c.wlr_scene_buffer_create(tree, null);
    if (node.scene_buffer == null) {
        free(@ptrCast(node));
        return null;
    }

    if (color != null)
        node.color = color.*
    else
        node.color = .{ 0.0, 0.0, 0.0, @as(f32, 0x55) / 255.0 };

    node.scene_buffer.*.point_accepts_input = dimNodePointAcceptsInput;

    dimNodeBuildPixel(node);
    c.wlr_scene_node_set_position(&node.scene_buffer.*.node, 0, 0);

    return node;
}

export fn acwm_dim_node_destroy(node_in: ?*DimNode) callconv(.c) void {
    const node = node_in orelse return;

    if (node.buffer != null) {
        c.wlr_buffer_drop(&node.buffer.*.base);
        node.buffer = null;
    }
    if (node.scene_buffer != null) {
        c.wlr_scene_node_destroy(&node.scene_buffer.*.node);
        node.scene_buffer = null;
    }

    free(@ptrCast(node));
}

export fn acwm_dim_node_set_color(node_in: ?*DimNode, color: [*c]const [4]f32) callconv(.c) void {
    const node = node_in orelse return;
    const new_color = color orelse return;

    const color_changed = node.buffer == null or
        memcmp(&node.color, new_color, @sizeOf([4]f32)) != 0;
    node.color = new_color.*;

    if (color_changed)
        dimNodeBuildPixel(node);
}

export fn acwm_dim_node_set_radius(node_in: ?*DimNode, radius_in: i32) callconv(.c) void {
    const node = node_in orelse return;
    var radius = radius_in;
    if (radius < 0)
        radius = 0;
    c.wlr_scene_buffer_set_corner_radii(node.scene_buffer, c.corner_radii_all(radius));
}

export fn acwm_dim_node_set_box(node_in: ?*DimNode, x: i32, y: i32, width_in: i32, height_in: i32) callconv(.c) void {
    const node = node_in orelse return;
    var width = width_in;
    var height = height_in;
    if (width < 0)
        width = 0;
    if (height < 0)
        height = 0;

    if (node.scene_buffer.*.node.x != x or node.scene_buffer.*.node.y != y)
        c.wlr_scene_node_set_position(&node.scene_buffer.*.node, x, y);

    c.wlr_scene_buffer_set_dest_size(node.scene_buffer, width, height);
}

export fn acwm_dim_node_set_enabled(node_in: ?*DimNode, enabled: bool) callconv(.c) void {
    const node = node_in orelse return;
    c.wlr_scene_node_set_enabled(&node.scene_buffer.*.node, enabled);
}

// ---------------------------------------------------------------------------
// tests (stub scene graph, real cairo: tests/dim_node_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_buffer_drops: c_int;
extern var stub_scene_destroy: c_int;
extern var stub_position_calls: c_int;
extern var stub_enabled_calls: c_int;
extern var stub_enabled_value: bool;
extern var stub_dest_calls: c_int;
extern var stub_dest_w: i32;
extern var stub_dest_h: i32;
extern var stub_corner_calls: c_int;
extern var stub_corner_radius: i32;

fn resetStub() void {
    stub_buffer_drops = 0;
    stub_scene_destroy = 0;
    stub_position_calls = 0;
    stub_enabled_calls = 0;
    stub_enabled_value = true;
    stub_dest_calls = 0;
    stub_dest_w = 0;
    stub_dest_h = 0;
    stub_corner_calls = 0;
    stub_corner_radius = -1;
}

fn fakeParent() *c.struct_wlr_scene_tree {
    return @ptrFromInt(8);
}

test "dim node creates a painted 1x1 buffer" {
    resetStub();
    const color = [4]f32{ 0.2, 0.4, 0.6, 0.5 };
    const node = acwm_dim_node_create(fakeParent(), &color).?;
    defer acwm_dim_node_destroy(node);

    try testing.expect(node.buffer != null);
    try testing.expectEqual(color[0], node.color[0]);
    try testing.expectEqual(color[3], node.color[3]);
    try testing.expectEqual(@as(c_int, 1), stub_position_calls);

    const accepts = node.scene_buffer.*.point_accepts_input.?;
    var sx: f64 = 0;
    var sy: f64 = 0;
    try testing.expect(!accepts(node.scene_buffer, &sx, &sy));

    const buf: *DimBuffer = @ptrCast(@alignCast(node.buffer));
    var data: ?*anyopaque = null;
    var format: u32 = 0;
    var stride: usize = 0;
    try testing.expect(dimBufferBeginDataPtrAccess(&buf.base, 0, &data, &format, &stride));
    try testing.expect(data != null);
    try testing.expectEqual(DRM_FORMAT_ARGB8888, format);
    try testing.expect(stride > 0);

    var wd: ?*anyopaque = null;
    var wf: u32 = 0;
    var ws: usize = 0;
    try testing.expect(!dimBufferBeginDataPtrAccess(&buf.base, c.WLR_BUFFER_DATA_PTR_ACCESS_WRITE, &wd, &wf, &ws));

    try testing.expect(acwm_dim_node_create(null, &color) == null);
}

test "dim node rebuilds only when the color changes" {
    resetStub();
    const color = [4]f32{ 0.1, 0.2, 0.3, 0.4 };
    const node = acwm_dim_node_create(fakeParent(), &color).?;
    defer acwm_dim_node_destroy(node);

    acwm_dim_node_set_color(node, &color);
    try testing.expectEqual(@as(c_int, 0), stub_buffer_drops);

    const next = [4]f32{ 1.0, 0.0, 0.0, 1.0 };
    acwm_dim_node_set_color(node, &next);
    try testing.expectEqual(@as(c_int, 1), stub_buffer_drops);
    try testing.expectEqual(@as(f32, 1.0), node.color[0]);
    try testing.expect(node.buffer != null);
}

test "dim node radius, box and enabled forwards to the scene" {
    resetStub();
    const color = [4]f32{ 0.0, 0.0, 0.0, 0.25 };
    const node = acwm_dim_node_create(fakeParent(), &color).?;
    defer acwm_dim_node_destroy(node);

    acwm_dim_node_set_radius(node, -5);
    try testing.expectEqual(@as(c_int, 1), stub_corner_calls);
    try testing.expectEqual(@as(i32, 0), stub_corner_radius);
    acwm_dim_node_set_radius(node, 12);
    try testing.expectEqual(@as(i32, 12), stub_corner_radius);

    acwm_dim_node_set_box(node, 10, 20, 300, -4);
    try testing.expectEqual(@as(c_int, 2), stub_position_calls);
    try testing.expectEqual(@as(i32, 300), stub_dest_w);
    try testing.expectEqual(@as(i32, 0), stub_dest_h);

    acwm_dim_node_set_box(node, 10, 20, 1, 2);
    try testing.expectEqual(@as(c_int, 2), stub_position_calls);

    acwm_dim_node_set_enabled(node, false);
    try testing.expectEqual(@as(c_int, 1), stub_enabled_calls);
    try testing.expect(!stub_enabled_value);
    try testing.expect(!node.scene_buffer.*.node.enabled);
}
