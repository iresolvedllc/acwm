//! Port of src/common/scene_node.c (Phase 5, common slice 2, slice 45).
//!
//! Scene-node payloads (type/owner/ignore-hit) plus the pointer hit-test
//! walker that prunes ignore-hit subtrees and mirrors wlroots' input
//! acceptance rules for rects and buffers.

const std = @import("std");
const c = @import("cc");

const SceneNode = c.struct_wlr_scene_node;
const SceneTree = c.struct_wlr_scene_tree;
const SceneRect = c.struct_wlr_scene_rect;
const SceneBuffer = c.struct_wlr_scene_buffer;
const Payload = c.AcwmSceneNode;
const Box = c.struct_wlr_box;
const WlList = c.struct_wl_list;

extern fn wlr_scene_node_coords(node: *SceneNode, lx: *c_int, ly: *c_int) callconv(.c) bool;
extern fn wlr_output_transform_coords(tr: c.enum_wl_output_transform, x: *c_int, y: *c_int) callconv(.c) void;
extern fn wlr_box_contains_point(box: *const Box, x: f64, y: f64) callconv(.c) bool;
extern fn wlr_box_empty(box: *const Box) callconv(.c) bool;

extern "c" fn calloc(nmemb: usize, size: usize) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;

fn containerOf(comptime T: type, comptime field: []const u8, ptr: *const anyopaque) *T {
    return @ptrFromInt(@intFromPtr(ptr) - @offsetOf(T, field));
}

fn nodeContainer(comptime T: type, node: *SceneNode) *T {
    return @ptrFromInt(@intFromPtr(node) - @offsetOf(T, "node"));
}

fn payloadOpt(p: ?*anyopaque) ?*Payload {
    return if (p == null) null else @ptrCast(@alignCast(p));
}

fn handleSceneNodeDestroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const payload: *Payload = @ptrFromInt(@intFromPtr(listener) - @offsetOf(Payload, "destroy"));
    c.wl_list_remove(&payload.destroy.link);
    free(@ptrCast(payload));
}

export fn acwm_scene_node_set(node: ?*SceneNode, node_type: u32, owner: ?*anyopaque) callconv(.c) ?*Payload {
    const nd = node orelse return null;

    if (payloadOpt(nd.data)) |old| {
        c.wl_list_remove(&old.destroy.link);
        free(@ptrCast(old));
    }

    const data: *Payload = @ptrCast(@alignCast(calloc(1, @sizeOf(Payload)) orelse return null));
    data.type = node_type;
    data.owner = owner;
    data.destroy.notify = handleSceneNodeDestroy;
    c.wl_signal_add(&nd.events.destroy, &data.destroy);
    nd.data = @ptrCast(data);
    return data;
}

export fn acwm_scene_node_find(node_in: ?*SceneNode) callconv(.c) ?*Payload {
    var node = node_in;
    while (node != null) : (node = if (node.?.parent != null) &node.?.parent.*.node else null) {
        if (payloadOpt(node.?.data)) |payload|
            return payload;
    }
    return null;
}

export fn acwm_scene_node_set_ignore_hit(node_in: ?*SceneNode, ignore_hit: bool) callconv(.c) void {
    const node = node_in orelse return;
    const payload = payloadOpt(node.data) orelse return;
    payload.ignore_hit = ignore_hit;
}

export fn acwm_scene_node_get_ignore_hit(node_in: ?*SceneNode) callconv(.c) bool {
    const node = node_in orelse return false;
    const payload = payloadOpt(node.data) orelse return false;
    return payload.ignore_hit;
}

fn sceneNodeSize(node: *SceneNode, width: *i32, height: *i32) void {
    width.* = 0;
    height.* = 0;

    switch (node.type) {
        c.WLR_SCENE_NODE_RECT => {
            const rect = nodeContainer(SceneRect, node);
            width.* = rect.width;
            height.* = rect.height;
        },
        c.WLR_SCENE_NODE_BUFFER => {
            const buffer = nodeContainer(SceneBuffer, node);
            if (buffer.dst_width > 0 and buffer.dst_height > 0) {
                width.* = buffer.dst_width;
                height.* = buffer.dst_height;
            } else {
                width.* = buffer.WLR_PRIVATE.buffer_width;
                height.* = buffer.WLR_PRIVATE.buffer_height;
                wlr_output_transform_coords(buffer.transform, width, height);
            }
        },
        else => {},
    }
}

fn sceneNodeAcceptsInput(node: *SceneNode, rx: *f64, ry: *f64) bool {
    switch (node.type) {
        c.WLR_SCENE_NODE_BUFFER => {
            const buffer = nodeContainer(SceneBuffer, node);
            if (buffer.point_accepts_input) |accepts|
                return accepts(buffer, rx, ry);
            return true;
        },
        c.WLR_SCENE_NODE_RECT => {
            const rect = nodeContainer(SceneRect, node);
            if (!rect.accepts_input)
                return false;
            if (!wlr_box_empty(&rect.clipped_region.area) and
                wlr_box_contains_point(&rect.clipped_region.area, rx.*, ry.*))
                return false;
            return true;
        },
        else => return false,
    }
}

fn sceneNodeContainsPoint(node: *SceneNode, px: f64, py: f64, lx: i32, ly: i32) bool {
    var width: i32 = 0;
    var height: i32 = 0;
    sceneNodeSize(node, &width, &height);

    const node_box = Box{ .x = lx, .y = ly, .width = width, .height = height };
    return wlr_box_contains_point(&node_box, px, py);
}

fn sceneNodeSearch(
    node: *SceneNode,
    px: f64,
    py: f64,
    lx: i32,
    ly: i32,
    result: **SceneNode,
    rx: *f64,
    ry: *f64,
) bool {
    if (!node.enabled)
        return false;

    if (payloadOpt(node.data)) |payload| {
        if (payload.ignore_hit)
            return false;
    }

    if (node.type == c.WLR_SCENE_NODE_TREE) {
        const tree = nodeContainer(SceneTree, node);
        var pos = tree.children.prev;
        const head: [*c]WlList = @ptrCast(&tree.children);
        while (pos != head) : (pos = pos.*.prev) {
            const child = containerOf(SceneNode, "link", pos);
            if (sceneNodeSearch(child, px, py, lx + child.x, ly + child.y, result, rx, ry))
                return true;
        }
        return false;
    }

    if (node.type != c.WLR_SCENE_NODE_BUFFER and node.type != c.WLR_SCENE_NODE_RECT)
        return false;

    if (!sceneNodeContainsPoint(node, px, py, lx, ly))
        return false;

    var local_x = px - @as(f64, @floatFromInt(lx));
    var local_y = py - @as(f64, @floatFromInt(ly));
    if (!sceneNodeAcceptsInput(node, &local_x, &local_y))
        return false;

    result.* = node;
    rx.* = local_x;
    ry.* = local_y;
    return true;
}

export fn acwm_scene_node_at(node_in: ?*SceneNode, lx: f64, ly: f64, nx: ?*f64, ny: ?*f64) callconv(.c) ?*SceneNode {
    const node = node_in orelse return null;
    var result: ?*SceneNode = null;
    var node_x: c_int = 0;
    var node_y: c_int = 0;
    var rx: f64 = 0;
    var ry: f64 = 0;

    _ = wlr_scene_node_coords(node, &node_x, &node_y);

    var result_ptr: *SceneNode = undefined;
    if (!sceneNodeSearch(node, lx, ly, node_x, node_y, &result_ptr, &rx, &ry))
        return null;
    result = result_ptr;

    if (nx) |out|
        out.* = rx;
    if (ny) |out|
        out.* = ry;
    return result;
}

// ---------------------------------------------------------------------------
// tests (stub scene graph: tests/scene_node_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

fn listInit(head: *WlList) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

fn listInsert(head: *WlList, link: *WlList) void {
    link.next = head.next;
    link.prev = @ptrCast(head);
    head.next.*.prev = @ptrCast(link);
    head.next = @ptrCast(link);
}

fn initTree(tree: *SceneTree) void {
    tree.* = std.mem.zeroes(SceneTree);
    tree.node.type = c.WLR_SCENE_NODE_TREE;
    tree.node.enabled = true;
    c.wl_signal_init(&tree.node.events.destroy);
    listInit(&tree.children);
}

fn addBuffer(buf: *SceneBuffer, parent: *SceneTree, x: i32, y: i32, w: i32, h: i32) void {
    buf.* = std.mem.zeroes(SceneBuffer);
    buf.node.type = c.WLR_SCENE_NODE_BUFFER;
    buf.node.enabled = true;
    buf.node.parent = @ptrCast(parent);
    buf.node.x = x;
    buf.node.y = y;
    buf.dst_width = w;
    buf.dst_height = h;
    buf.transform = c.WL_OUTPUT_TRANSFORM_NORMAL;
    c.wl_signal_init(&buf.node.events.destroy);
    listInsert(&parent.children, &buf.node.link);
}

fn addRect(rect: *SceneRect, parent: *SceneTree, x: i32, y: i32, w: i32, h: i32, accepts: bool) void {
    rect.* = std.mem.zeroes(SceneRect);
    rect.node.type = c.WLR_SCENE_NODE_RECT;
    rect.node.enabled = true;
    rect.node.parent = @ptrCast(parent);
    rect.node.x = x;
    rect.node.y = y;
    rect.width = w;
    rect.height = h;
    rect.accepts_input = accepts;
    c.wl_signal_init(&rect.node.events.destroy);
    listInsert(&parent.children, &rect.node.link);
}

fn pointAcceptsRewrite(buf: [*c]SceneBuffer, sx: [*c]f64, sy: [*c]f64) callconv(.c) bool {
    _ = buf;
    sx.* = 42;
    sy.* = 43;
    return true;
}

test "payload set/find/ignore and replacement" {
    var root: SceneTree = undefined;
    initTree(&root);

    const owner: *anyopaque = @ptrFromInt(0x1234);
    const p1 = acwm_scene_node_set(&root.node, 7, owner).?;
    try testing.expectEqual(@as(u32, 7), p1.type);
    try testing.expect(p1.owner == owner);
    try testing.expect(root.node.data == @as(?*anyopaque, @ptrCast(p1)));

    const p2 = acwm_scene_node_set(&root.node, 8, null).?;
    try testing.expect(root.node.data == @as(?*anyopaque, @ptrCast(p2)));
    try testing.expectEqual(@as(u32, 8), p2.type);

    acwm_scene_node_set_ignore_hit(&root.node, true);
    try testing.expect(acwm_scene_node_get_ignore_hit(&root.node));
    acwm_scene_node_set_ignore_hit(&root.node, false);
    try testing.expect(!acwm_scene_node_get_ignore_hit(&root.node));

    var buf: SceneBuffer = undefined;
    addBuffer(&buf, &root, 0, 0, 10, 10);
    try testing.expect(acwm_scene_node_find(&buf.node) == p2);
    acwm_scene_node_set_ignore_hit(&buf.node, true);
    try testing.expect(!acwm_scene_node_get_ignore_hit(&buf.node));

    try testing.expect(acwm_scene_node_set(null, 1, null) == null);
    try testing.expect(!acwm_scene_node_get_ignore_hit(null));
}

test "hit testing finds buffers with local coordinates" {
    var root: SceneTree = undefined;
    initTree(&root);
    var buf: SceneBuffer = undefined;
    addBuffer(&buf, &root, 10, 20, 100, 50);

    var nx: f64 = 0;
    var ny: f64 = 0;
    const hit = acwm_scene_node_at(&root.node, 15, 25, &nx, &ny);
    try testing.expect(hit == &buf.node);
    try testing.expectEqual(@as(f64, 5), nx);
    try testing.expectEqual(@as(f64, 5), ny);

    try testing.expect(acwm_scene_node_at(&root.node, 500, 500, null, null) == null);

    buf.node.enabled = false;
    try testing.expect(acwm_scene_node_at(&root.node, 15, 25, null, null) == null);

    buf.node.enabled = true;
    _ = acwm_scene_node_set(&buf.node, 1, null);
    acwm_scene_node_set_ignore_hit(&buf.node, true);
    try testing.expect(acwm_scene_node_at(&root.node, 15, 25, null, null) == null);
}

test "rect acceptance and clipped regions" {
    var root: SceneTree = undefined;
    initTree(&root);
    var rect: SceneRect = undefined;
    addRect(&rect, &root, 0, 0, 100, 100, true);

    try testing.expect(acwm_scene_node_at(&root.node, 50, 50, null, null) == &rect.node);

    rect.clipped_region.area = .{ .x = 0, .y = 0, .width = 10, .height = 10 };
    try testing.expect(acwm_scene_node_at(&root.node, 5, 5, null, null) == null);
    try testing.expect(acwm_scene_node_at(&root.node, 50, 50, null, null) == &rect.node);

    rect.clipped_region.area = std.mem.zeroes(Box);
    rect.accepts_input = false;
    try testing.expect(acwm_scene_node_at(&root.node, 50, 50, null, null) == null);
}

test "buffer input callbacks may rewrite local coordinates" {
    var root: SceneTree = undefined;
    initTree(&root);
    var buf: SceneBuffer = undefined;
    addBuffer(&buf, &root, 0, 0, 100, 100);
    buf.point_accepts_input = pointAcceptsRewrite;

    var nx: f64 = 0;
    var ny: f64 = 0;
    try testing.expect(acwm_scene_node_at(&root.node, 10, 10, &nx, &ny) == &buf.node);
    try testing.expectEqual(@as(f64, 42), nx);
    try testing.expectEqual(@as(f64, 43), ny);
}

test "nested tree offsets accumulate" {
    var root: SceneTree = undefined;
    var inner: SceneTree = undefined;
    initTree(&root);
    initTree(&inner);
    inner.node.parent = @ptrCast(&root);
    inner.node.x = 30;
    inner.node.y = 40;
    listInsert(&root.children, &inner.node.link);

    var buf: SceneBuffer = undefined;
    addBuffer(&buf, &inner, 5, 6, 20, 20);

    var nx: f64 = 0;
    var ny: f64 = 0;
    try testing.expect(acwm_scene_node_at(&root.node, 40, 50, &nx, &ny) == &buf.node);
    try testing.expectEqual(@as(f64, 5), nx);
    try testing.expectEqual(@as(f64, 4), ny);
}
