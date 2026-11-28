//! Port of the curve/baked-point helpers and per-monitor frame request from
//! src/animation/common.c (Phase 5, animation slice 1, slice 47).
//! Scene snapshot helpers live in src/animation/snapshot.zig.

const std = @import("std");
const c = @import("cc");

const DVec2 = c.struct_dvec2;
const WlList = c.struct_wl_list;

extern fn wlr_output_schedule_frame(output: *c.struct_wlr_output) callconv(.c) void;
extern "c" fn calloc(nmemb: usize, size: usize) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;

fn containerOf(comptime T: type, comptime field: []const u8, link: [*c]WlList) *T {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(T, field));
}

fn curveFor(animation_type: i32) *const [4]f64 {
    const cfg = &c.config;
    return switch (animation_type) {
        c.MOVE => &cfg.animation_curve_move,
        c.OPEN => &cfg.animation_curve_open,
        c.TAG => &cfg.animation_curve_tag,
        c.CLOSE => &cfg.animation_curve_close,
        c.FOCUS => &cfg.animation_curve_focus,
        c.OPAFADEIN => &cfg.animation_curve_opafadein,
        c.OPAFADEOUT => &cfg.animation_curve_opafadeout,
        else => &cfg.animation_curve_move,
    };
}

export fn handle_snapshot_meta_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const meta: *c.SnapshotMetadata = @ptrFromInt(@intFromPtr(listener) - @offsetOf(c.SnapshotMetadata, "destroy"));
    c.wl_list_remove(&meta.destroy.link);
    free(@ptrCast(meta));
}

export fn calculate_animation_curve_at(t: f64, animation_type: i32) callconv(.c) DVec2 {
    const curve = curveFor(animation_type);
    const x = 3 * t * (1 - t) * (1 - t) * curve[0] +
        3 * t * t * (1 - t) * curve[2] + t * t * t;
    const y = 3 * t * (1 - t) * (1 - t) * curve[1] +
        3 * t * t * (1 - t) * curve[3] + t * t * t;
    return .{ .x = x, .y = y };
}

const BAKED_POINTS_COUNT = c.BAKED_POINTS_COUNT;

fn allocPoints() [*c]DVec2 {
    return @ptrCast(@alignCast(calloc(BAKED_POINTS_COUNT, @sizeOf(DVec2)) orelse return null));
}

export fn init_baked_points() callconv(.c) void {
    c.server.baked_points_move = allocPoints();
    c.server.baked_points_open = allocPoints();
    c.server.baked_points_tag = allocPoints();
    c.server.baked_points_close = allocPoints();
    c.server.baked_points_focus = allocPoints();
    c.server.baked_points_opafadein = allocPoints();
    c.server.baked_points_opafadeout = allocPoints();

    const denom: f64 = @floatFromInt(BAKED_POINTS_COUNT - 1);
    var i: c_int = 0;
    while (i < BAKED_POINTS_COUNT) : (i += 1) {
        const t = @as(f64, @floatFromInt(i)) / denom;
        c.server.baked_points_move[@intCast(i)] = calculate_animation_curve_at(t, c.MOVE);
    }
    i = 0;
    while (i < BAKED_POINTS_COUNT) : (i += 1) {
        const t = @as(f64, @floatFromInt(i)) / denom;
        c.server.baked_points_open[@intCast(i)] = calculate_animation_curve_at(t, c.OPEN);
    }
    i = 0;
    while (i < BAKED_POINTS_COUNT) : (i += 1) {
        const t = @as(f64, @floatFromInt(i)) / denom;
        c.server.baked_points_tag[@intCast(i)] = calculate_animation_curve_at(t, c.TAG);
    }
    i = 0;
    while (i < BAKED_POINTS_COUNT) : (i += 1) {
        const t = @as(f64, @floatFromInt(i)) / denom;
        c.server.baked_points_close[@intCast(i)] = calculate_animation_curve_at(t, c.CLOSE);
    }
    i = 0;
    while (i < BAKED_POINTS_COUNT) : (i += 1) {
        const t = @as(f64, @floatFromInt(i)) / denom;
        c.server.baked_points_focus[@intCast(i)] = calculate_animation_curve_at(t, c.FOCUS);
    }
    i = 0;
    while (i < BAKED_POINTS_COUNT) : (i += 1) {
        const t = @as(f64, @floatFromInt(i)) / denom;
        c.server.baked_points_opafadein[@intCast(i)] = calculate_animation_curve_at(t, c.OPAFADEIN);
    }
    i = 0;
    while (i < BAKED_POINTS_COUNT) : (i += 1) {
        const t = @as(f64, @floatFromInt(i)) / denom;
        c.server.baked_points_opafadeout[@intCast(i)] = calculate_animation_curve_at(t, c.OPAFADEOUT);
    }
}

fn bakedPointsFor(animation_type: i32) [*c]DVec2 {
    return switch (animation_type) {
        c.MOVE => c.server.baked_points_move,
        c.OPEN => c.server.baked_points_open,
        c.TAG => c.server.baked_points_tag,
        c.CLOSE => c.server.baked_points_close,
        c.FOCUS => c.server.baked_points_focus,
        c.OPAFADEIN => c.server.baked_points_opafadein,
        c.OPAFADEOUT => c.server.baked_points_opafadeout,
        else => c.server.baked_points_move,
    };
}

export fn find_animation_curve_at(t: f64, animation_type: i32) callconv(.c) f64 {
    var down: c_int = 0;
    var up: c_int = BAKED_POINTS_COUNT - 1;
    var middle: c_int = @divTrunc(up + down, 2);
    const points = bakedPointsFor(animation_type);

    while (up - down != 1) {
        if (points[@intCast(middle)].x <= t)
            down = middle
        else
            up = middle;
        middle = @divTrunc(up + down, 2);
    }
    return points[@intCast(up)].y;
}

export fn request_fresh_all_monitors() callconv(.c) void {
    var pos = c.server.monitors.next;
    const head: [*c]WlList = @ptrCast(&c.server.monitors);
    while (pos != head) : (pos = pos.*.next) {
        const m = containerOf(c.Monitor, "link", pos);
        if (m.wlr_output.*.enabled == false)
            continue;
        wlr_output_schedule_frame(m.wlr_output);
    }
}

// ---------------------------------------------------------------------------
// tests (stub scheduling: tests/animation_common_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_frame_calls: c_int;

fn linearizeCurves() void {
    const linear = [4]f64{ 0, 0, 1, 1 };
    c.config.animation_curve_move = linear;
    c.config.animation_curve_open = linear;
    c.config.animation_curve_tag = linear;
    c.config.animation_curve_close = linear;
    c.config.animation_curve_focus = linear;
    c.config.animation_curve_opafadein = linear;
    c.config.animation_curve_opafadeout = linear;
}

test "cubic curve evaluation and unknown-type fallback" {
    linearizeCurves();
    const p0 = calculate_animation_curve_at(0.0, c.MOVE);
    try testing.expectApproxEqAbs(@as(f64, 0), p0.x, 1e-9);
    try testing.expectApproxEqAbs(@as(f64, 0), p0.y, 1e-9);

    const mid = calculate_animation_curve_at(0.5, c.OPEN);
    try testing.expectApproxEqAbs(@as(f64, 0.5), mid.x, 1e-9);
    try testing.expectApproxEqAbs(@as(f64, 0.5), mid.y, 1e-9);

    const end = calculate_animation_curve_at(1.0, c.OPAFADEOUT);
    try testing.expectApproxEqAbs(@as(f64, 1), end.x, 1e-9);
    try testing.expectApproxEqAbs(@as(f64, 1), end.y, 1e-9);

    const unknown = calculate_animation_curve_at(0.25, 999);
    try testing.expectApproxEqAbs(@as(f64, 0.15625), unknown.x, 1e-9);
}

test "baked points initialize and binary-search" {
    linearizeCurves();
    init_baked_points();
    defer {
        free(@ptrCast(c.server.baked_points_move));
        free(@ptrCast(c.server.baked_points_open));
        free(@ptrCast(c.server.baked_points_tag));
        free(@ptrCast(c.server.baked_points_close));
        free(@ptrCast(c.server.baked_points_focus));
        free(@ptrCast(c.server.baked_points_opafadein));
        free(@ptrCast(c.server.baked_points_opafadeout));
        c.server.baked_points_move = null;
        c.server.baked_points_open = null;
        c.server.baked_points_tag = null;
        c.server.baked_points_close = null;
        c.server.baked_points_focus = null;
        c.server.baked_points_opafadein = null;
        c.server.baked_points_opafadeout = null;
    }

    try testing.expect(c.server.baked_points_move != null);
    try testing.expectApproxEqAbs(@as(f64, 0), c.server.baked_points_move[0].x, 1e-9);
    try testing.expectApproxEqAbs(@as(f64, 1), c.server.baked_points_move[c.BAKED_POINTS_COUNT - 1].x, 1e-9);

    const mid = find_animation_curve_at(0.5, c.MOVE);
    try testing.expectApproxEqAbs(@as(f64, 0.5), mid, 0.01);
    const unknown = find_animation_curve_at(0.25, 999);
    try testing.expect(unknown >= 0.2 and unknown <= 0.3);
}

test "request_fresh_all_monitors skips disabled outputs" {
    stub_frame_calls = 0;
    c.server.monitors.next = @ptrCast(&c.server.monitors);
    c.server.monitors.prev = @ptrCast(&c.server.monitors);

    var out1: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    var out2: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    out1.enabled = true;
    out2.enabled = false;

    var m1: c.Monitor = std.mem.zeroes(c.Monitor);
    var m2: c.Monitor = std.mem.zeroes(c.Monitor);
    m1.wlr_output = @ptrCast(&out1);
    m2.wlr_output = @ptrCast(&out2);
    c.wl_list_insert(&c.server.monitors, &m1.link);
    c.wl_list_insert(&c.server.monitors, &m2.link);

    request_fresh_all_monitors();
    try testing.expectEqual(@as(c_int, 1), stub_frame_calls);
}
