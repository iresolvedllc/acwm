//! Port of ext-protocol/xdg-output.c (Phase 5, ext-protocol slice 3, slice 77).

const std = @import("std");
const c = @import("cc");
const build_options = @import("build_options");

const Output = c.struct_AcwmXDGOutput;
const Res = c.struct_AcwmXDGOutputResource;
const Monitor = c.Monitor;

extern var zxdg_output_v1_interface: c.struct_wl_interface;
extern var zxdg_output_manager_v1_interface: c.struct_wl_interface;

extern fn wl_resource_get_client(resource: [*c]c.struct_wl_resource) callconv(.c) ?*c.struct_wl_client;
extern fn wl_resource_get_version(resource: [*c]c.struct_wl_resource) callconv(.c) u32;
extern fn wl_resource_get_user_data(resource: [*c]c.struct_wl_resource) callconv(.c) ?*anyopaque;
extern fn wl_resource_set_user_data(resource: [*c]c.struct_wl_resource, data: ?*anyopaque) callconv(.c) void;
extern fn wl_resource_set_implementation(resource: [*c]c.struct_wl_resource, implementation: ?*const anyopaque, data: ?*anyopaque, destroy: ?*const fn ([*c]c.struct_wl_resource) callconv(.c) void) callconv(.c) void;
extern fn wl_resource_create(client: ?*c.struct_wl_client, interface: [*c]const c.struct_wl_interface, version: c_int, id: u32) callconv(.c) [*c]c.struct_wl_resource;
extern fn wl_resource_destroy(resource: [*c]c.struct_wl_resource) callconv(.c) void;
extern fn wl_client_post_no_memory(client: ?*c.struct_wl_client) callconv(.c) void;
extern fn wl_global_create(display: ?*c.struct_wl_display, interface: [*c]const c.struct_wl_interface, version: c_int, data: ?*anyopaque, bind: *const fn (?*c.struct_wl_client, ?*anyopaque, u32, u32) callconv(.c) void) callconv(.c) ?*c.struct_wl_global;
extern fn wl_resource_for_each_helper() void;
extern fn wlr_output_from_resource(resource: [*c]c.struct_wl_resource) callconv(.c) [*c]c.struct_wlr_output;
extern fn wlr_output_transformed_resolution(output: [*c]c.struct_wlr_output, width: *c_int, height: *c_int) callconv(.c) void;
extern fn wlr_output_schedule_done(output: [*c]c.struct_wlr_output) callconv(.c) void;
extern fn wlr_output_layout_get(layout: [*c]c.struct_wlr_output_layout, output: [*c]c.struct_wlr_output) callconv(.c) [*c]c.struct_wlr_output_layout_output;
extern fn xwayland_screen_origin(x: *i32, y: *i32) callconv(.c) void;
// extern fn c.zxdg_output_v1_send_logical_position(resource: [*c]c.struct_wl_resource, x: i32, y: i32) callconv(.c) void;
// extern fn c.zxdg_output_v1_send_logical_size(resource: [*c]c.struct_wl_resource, width: i32, height: i32) callconv(.c) void;
// extern fn c.zxdg_output_v1_send_done(resource: [*c]c.struct_wl_resource) callconv(.c) void;
// extern fn c.zxdg_output_v1_send_name(resource: [*c]c.struct_wl_resource, name: [*c]const u8) callconv(.c) void;
// extern fn zxdg_output_v1_send_description(resource: [*c]c.struct_wl_resource, description: [*c]const u8) callconv(.c) void;
// extern fn wl_output_send_done(resource: [*c]c.struct_wl_resource) callconv(.c) void;

var xdg_output_global: ?*c.struct_wl_global = null;
var xdg_outputs: c.struct_wl_list = std.mem.zeroes(c.struct_wl_list);

fn listInit(head: *c.struct_wl_list) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

fn outputFromLink(link: [*c]c.struct_wl_list) *Output {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(Output, "link"));
}

fn resFromLink(link: [*c]c.struct_wl_list) *Res {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(Res, "link"));
}

var xdg_output_impl: c.struct_zxdg_output_v1_interface = .{ .destroy = handle_xdg_output_destroy };
var xdg_output_manager_impl: c.struct_zxdg_output_manager_v1_interface = .{
    .destroy = handle_xdg_output_manager_destroy,
    .get_xdg_output = handle_xdg_output_manager_get_output,
};

export fn xdg_output_resource_is_xwayland(resource: [*c]c.struct_wl_resource) callconv(.c) bool {
    if (build_options.xwayland and c.server.xwayland != null and c.server.xwayland.*.server != null and
        c.server.xwayland.*.server.*.client == c.wl_resource_get_client(resource))
        return true;
    return false;
}

export fn xdg_output_get_values(output: [*c]Output, lx: *i32, ly: *i32, lw: *i32, lh: *i32, px: *i32, py: *i32, pw: *i32, ph: *i32) callconv(.c) void {
    var x: i32 = 0;
    var y: i32 = 0;
    const m = @as(?*Monitor, @ptrCast(@alignCast(output.*.wlr_output.*.data)));
    if (m != null) {
        x = m.?.m.x;
        y = m.?.m.y;
    }
    const scale: f32 = if (output.*.wlr_output.*.scale > 0) output.*.wlr_output.*.scale else 1;
    var tw: c_int = 0;
    var th: c_int = 0;
    c.wlr_output_transformed_resolution(output.*.wlr_output, &tw, &th);
    const w: i32 = @intFromFloat(@round(@as(f32, @floatFromInt(tw)) / scale));
    const h: i32 = @intFromFloat(@round(@as(f32, @floatFromInt(th)) / scale));
    lx.* = x;
    ly.* = y;
    lw.* = w;
    lh.* = h;
    var ox: i32 = 0;
    var oy: i32 = 0;
    if (build_options.xwayland)
        xwayland_screen_origin(&ox, &oy);
    px.* = @intFromFloat(@round(@as(f32, @floatFromInt(x - ox)) * scale));
    py.* = @intFromFloat(@round(@as(f32, @floatFromInt(y - oy)) * scale));
    pw.* = tw;
    ph.* = th;
}

export fn xdg_output_send_details(output: [*c]Output, resource: [*c]c.struct_wl_resource) callconv(.c) void {
    var lx: i32 = 0;
    var ly: i32 = 0;
    var lw: i32 = 0;
    var lh: i32 = 0;
    var px: i32 = 0;
    var py: i32 = 0;
    var pw: i32 = 0;
    var ph: i32 = 0;
    xdg_output_get_values(output, &lx, &ly, &lw, &lh, &px, &py, &pw, &ph);
    var x: i32 = 0;
    var y: i32 = 0;
    var w: i32 = 0;
    var h: i32 = 0;
    if (xdg_output_resource_is_xwayland(resource)) {
        var ox: i32 = 0;
        var oy: i32 = 0;
        if (build_options.xwayland)
            xwayland_screen_origin(&ox, &oy);
        if (c.config.xwayland_ignore_scale != 0) {
            x = px; y = py; w = pw; h = ph;
        } else {
            x = lx - ox; y = ly - oy; w = lw; h = lh;
        }
    } else {
        x = lx; y = ly; w = lw; h = lh;
    }
    c.zxdg_output_v1_send_logical_position(resource, x, y);
    c.zxdg_output_v1_send_logical_size(resource, w, h);
    if (wl_resource_get_version(resource) < c.ACWM_XDG_OUTPUT_DONE_DEPRECATED_SINCE_VERSION)
        c.zxdg_output_v1_send_done(resource);
    output.*.last_lx = lx;
    output.*.last_ly = ly;
    output.*.last_lw = lw;
    output.*.last_lh = lh;
    output.*.sent = true;
    if (xdg_output_resource_is_xwayland(resource)) {
        output.*.last_px = px;
        output.*.last_py = py;
        output.*.last_pw = pw;
        output.*.last_ph = ph;
        output.*.xwl_sent = true;
    }
}

export fn xdg_output_logical_changed(output: [*c]Output) callconv(.c) bool {
    var lx: i32 = 0; var ly: i32 = 0; var lw: i32 = 0; var lh: i32 = 0;
    var px: i32 = 0; var py: i32 = 0; var pw: i32 = 0; var ph: i32 = 0;
    xdg_output_get_values(output, &lx, &ly, &lw, &lh, &px, &py, &pw, &ph);
    if (!output.*.sent)
        return false;
    return output.*.last_lx != lx or output.*.last_ly != ly or
        output.*.last_lw != lw or output.*.last_lh != lh;
}

export fn xdg_output_xwayland_changed(output: [*c]Output) callconv(.c) bool {
    var lx: i32 = 0; var ly: i32 = 0; var lw: i32 = 0; var lh: i32 = 0;
    var px: i32 = 0; var py: i32 = 0; var pw: i32 = 0; var ph: i32 = 0;
    xdg_output_get_values(output, &lx, &ly, &lw, &lh, &px, &py, &pw, &ph);
    const changed = output.*.last_px != px or output.*.last_py != py or
        output.*.last_pw != pw or output.*.last_ph != ph;
    output.*.last_px = px;
    output.*.last_py = py;
    output.*.last_pw = pw;
    output.*.last_ph = ph;
    return changed;
}

export fn xdg_output_update(output: [*c]Output) callconv(.c) void {
    const logical_changed = xdg_output_logical_changed(output);
    const head: [*c]c.struct_wl_list = @ptrCast(&output.*.resources);
    var pos = output.*.resources.next;
    while (pos != head) : (pos = pos.*.next) {
        const res = resFromLink(pos);
        if (!xdg_output_resource_is_xwayland(res.resource) and !logical_changed)
            continue;
        xdg_output_send_details(output, res.resource);
    }
}

export fn handle_xdg_output_resource_destroy(resource: [*c]c.struct_wl_resource) callconv(.c) void {
    const res = @as(?*Res, @ptrCast(@alignCast(wl_resource_get_user_data(resource))));
    if (res == null)
        return;
    c.wl_list_remove(&res.?.link);
    c.free(res.?);
}

export fn handle_xdg_output_destroy(client: ?*c.struct_wl_client, resource: [*c]c.struct_wl_resource) callconv(.c) void {
    _ = client;
    wl_resource_destroy(resource);
}

export fn handle_xdg_output_manager_destroy(client: ?*c.struct_wl_client, resource: [*c]c.struct_wl_resource) callconv(.c) void {
    _ = client;
    wl_resource_destroy(resource);
}

export fn handle_xdg_output_description(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const output = @as(*Output, @ptrFromInt(@intFromPtr(listener) - @offsetOf(Output, "unnamed_0")));
    const wlr_output = output.wlr_output;
    if (wlr_output.*.description == null)
        return;
    const head: [*c]c.struct_wl_list = @ptrCast(&output.resources);
    var pos = output.resources.next;
    while (pos != head) : (pos = pos.*.next) {
        const res = resFromLink(pos);
        if (wl_resource_get_version(res.resource) >= c.ACWM_XDG_OUTPUT_DESCRIPTION_MUTABLE_SINCE_VERSION)
            c.zxdg_output_v1_send_description(res.resource, wlr_output.*.description);
    }
}

export fn xdg_output_find(wlr_output: [*c]c.struct_wlr_output) callconv(.c) [*c]Output {
    const head: [*c]c.struct_wl_list = @ptrCast(&xdg_outputs);
    var pos = xdg_outputs.next;
    while (pos != head) : (pos = pos.*.next) {
        const output = outputFromLink(pos);
        if (output.wlr_output == wlr_output)
            return output;
    }
    return null;
}

fn handleXdgOutputLayoutOutputDestroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const output = @as(*Output, @ptrFromInt(@intFromPtr(listener) - @offsetOf(Output, "layout_output_destroy")));
    c.wl_list_remove(&output.layout_output_destroy.link);
    output.layout_output = null;
    xdg_output_destroy(output);
}

export fn xdg_output_create(wlr_output: [*c]c.struct_wlr_output) callconv(.c) [*c]Output {
    const raw = c.calloc(1, @sizeOf(Output)) orelse return null;
    const output = @as(*Output, @ptrCast(@alignCast(raw)));
    output.wlr_output = wlr_output;
    listInit(&output.resources);
    output.unnamed_0.description.notify = handle_xdg_output_description;
    c.wl_signal_add(&wlr_output.*.events.description, &output.unnamed_0.description);
    c.wl_list_insert(&xdg_outputs, &output.link);
    output.layout_output = c.wlr_output_layout_get(c.server.output_layout, wlr_output);
    if (output.layout_output != null) {
        output.layout_output_destroy.notify = handleXdgOutputLayoutOutputDestroy;
        c.wl_signal_add(&output.layout_output.*.events.destroy, &output.layout_output_destroy);
    }
    return output;
}

export fn xdg_output_destroy(output: [*c]Output) callconv(.c) void {
    const head: [*c]c.struct_wl_list = @ptrCast(&output.*.resources);
    var pos = output.*.resources.next;
    while (pos != head) {
        const next = pos.*.next;
        const res = resFromLink(pos);
        wl_resource_set_user_data(res.resource, null);
        c.wl_list_remove(&res.link);
        c.free(res);
        pos = next;
    }
    if (output.*.layout_output != null)
        c.wl_list_remove(&output.*.layout_output_destroy.link);
    c.wl_list_remove(&output.*.unnamed_0.description.link);
    c.wl_list_remove(&output.*.link);
    c.free(output);
}

export fn handle_xdg_output_manager_get_output(client: ?*c.struct_wl_client, manager_resource: [*c]c.struct_wl_resource, id: u32, output_resource: [*c]c.struct_wl_resource) callconv(.c) void {
    const wlr_output = c.wlr_output_from_resource(output_resource);
    const resource = wl_resource_create(client, &zxdg_output_v1_interface, @intCast(wl_resource_get_version(manager_resource)), id);
    if (resource == null) {
        wl_client_post_no_memory(client);
        return;
    }
    if (wlr_output == null) {
        wl_resource_set_implementation(resource, &xdg_output_impl, null, handle_xdg_output_resource_destroy);
        return;
    }
    var output = xdg_output_find(wlr_output);
    if (output == null)
        output = xdg_output_create(wlr_output);
    if (output == null) {
        wl_client_post_no_memory(client);
        wl_resource_destroy(resource);
        return;
    }
    const raw = c.calloc(1, @sizeOf(Res)) orelse {
        wl_client_post_no_memory(client);
        wl_resource_destroy(resource);
        return;
    };
    const res = @as(*Res, @ptrCast(@alignCast(raw)));
    res.resource = resource;
    c.wl_list_insert(&output.*.resources, &res.link);
    wl_resource_set_implementation(resource, &xdg_output_impl, res, handle_xdg_output_resource_destroy);
    const version = wl_resource_get_version(resource);
    if (version >= c.ZXDG_OUTPUT_V1_NAME_SINCE_VERSION and wlr_output.*.name != null)
        c.zxdg_output_v1_send_name(resource, wlr_output.*.name);
    if (version >= c.ZXDG_OUTPUT_V1_DESCRIPTION_SINCE_VERSION and wlr_output.*.description != null)
        c.zxdg_output_v1_send_description(resource, wlr_output.*.description);
    xdg_output_send_details(output, resource);
    if (wl_resource_get_version(output_resource) >= c.WL_OUTPUT_DONE_SINCE_VERSION and
        version >= c.ACWM_XDG_OUTPUT_DONE_DEPRECATED_SINCE_VERSION)
        c.wl_output_send_done(output_resource);
}

export fn xdg_output_manager_bind(client: ?*c.struct_wl_client, data: ?*anyopaque, version: u32, id: u32) callconv(.c) void {
    _ = data;
    const resource = wl_resource_create(client, &zxdg_output_manager_v1_interface, @intCast(version), id);
    if (resource == null) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(resource, &xdg_output_manager_impl, null, null);
}

export fn xdg_output_update_all() callconv(.c) void {
    const head: [*c]c.struct_wl_list = @ptrCast(&xdg_outputs);
    var pos = xdg_outputs.next;
    while (pos != head) {
        const next = pos.*.next;
        const output = outputFromLink(pos);
        const logical_changed = xdg_output_logical_changed(output);
        const xwayland_changed = xdg_output_xwayland_changed(output);
        xdg_output_update(output);
        if (logical_changed) {
            c.wlr_output_schedule_done(output.wlr_output);
        } else if (xwayland_changed) {
            const whead: [*c]c.struct_wl_list = @ptrCast(&output.wlr_output.*.resources);
            var wpos = output.wlr_output.*.resources.next;
            while (wpos != whead) : (wpos = wpos.*.next) {
                const wl_res = @as([*c]c.struct_wl_resource, @ptrFromInt(@intFromPtr(wpos) - @offsetOf(c.struct_wl_resource, "link")));
                if (wl_resource_get_version(wl_res) >= c.WL_OUTPUT_DONE_SINCE_VERSION and
                    xdg_output_resource_is_xwayland(wl_res))
                    c.wl_output_send_done(wl_res);
            }
        }
        pos = next;
    }
}

export fn xdg_output_init() callconv(.c) void {
    listInit(&xdg_outputs);
    xdg_output_global = wl_global_create(c.server.display, &zxdg_output_manager_v1_interface,
        c.ACWM_XDG_OUTPUT_MANAGER_VERSION, null, xdg_output_manager_bind);
    if (xdg_output_global == null)
        c.acwm_error_impl(true, c.WLR_ERROR, "src/ext-protocol/xdg-output.c", 377,
            "failed to create zxdg_output_manager_v1 global");
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/xdg_output_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_user_data: ?*anyopaque;
extern var stub_set_user_data_calls: c_int;
extern var stub_version: u32;
extern var stub_impl_calls: c_int;
extern var stub_resource: c.struct_wl_resource;
extern var stub_resource2: c.struct_wl_resource;
extern var stub_wl_output_resource: [*c]c.struct_wl_resource;
extern var stub_resource_destroy_calls: c_int;
extern var stub_no_memory_calls: c_int;
extern var stub_global: c.struct_wl_global;
extern var stub_wlr_output: [*c]c.struct_wlr_output;
extern var stub_transformed_w: c_int;
extern var stub_transformed_h: c_int;
extern var stub_schedule_done_calls: c_int;
extern var stub_layout_output: [*c]c.struct_wlr_output_layout_output;
extern var stub_ox: i32;
extern var stub_oy: i32;
extern var stub_pos_calls: c_int;
extern var stub_size_calls: c_int;
extern var stub_done_calls: c_int;
extern var stub_lx: i32;
extern var stub_ly: i32;
extern var stub_lw: i32;
extern var stub_lh: i32;
extern var stub_name_calls: c_int;
extern var stub_desc_calls: c_int;
extern var stub_output_done_calls: c_int;
extern var stub_error_calls: c_int;

fn listInitL(head: *c.struct_wl_list) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

fn resetXdgWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    listInit(&xdg_outputs);
    xdg_output_global = null;
    stub_user_data = null;
    stub_set_user_data_calls = 0;
    stub_version = 3;
    stub_impl_calls = 0;
    stub_resource = std.mem.zeroes(c.struct_wl_resource);
    stub_resource_destroy_calls = 0;
    stub_no_memory_calls = 0;
    stub_wlr_output = null;
    stub_transformed_w = 1920;
    stub_transformed_h = 1080;
    stub_schedule_done_calls = 0;
    stub_layout_output = null;
    stub_ox = 0;
    stub_oy = 0;
    stub_pos_calls = 0;
    stub_size_calls = 0;
    stub_done_calls = 0;
    stub_lx = 0;
    stub_ly = 0;
    stub_lw = 0;
    stub_lh = 0;
    stub_name_calls = 0;
    stub_desc_calls = 0;
    stub_output_done_calls = 0;
    stub_wl_output_resource = null;
    stub_error_calls = 0;
}

fn fakeOutput(out: *c.struct_wlr_output, m: *Monitor) void {
    out.* = std.mem.zeroes(c.struct_wlr_output);
    out.data = @ptrCast(m);
    out.scale = 2;
    listInit(&out.events.description.listener_list);
}

test "xdg output values are rotation and scale aware" {
    resetXdgWorld();
    var m: Monitor = std.mem.zeroes(Monitor);
    m.m = .{ .x = 100, .y = 50, .width = 960, .height = 540 };
    var out: c.struct_wlr_output = undefined;
    fakeOutput(&out, &m);
    var output: Output = std.mem.zeroes(Output);
    output.wlr_output = &out;
    var lx: i32 = 0; var ly: i32 = 0; var lw: i32 = 0; var lh: i32 = 0;
    var px: i32 = 0; var py: i32 = 0; var pw: i32 = 0; var ph: i32 = 0;
    xdg_output_get_values(&output, &lx, &ly, &lw, &lh, &px, &py, &pw, &ph);
    try testing.expectEqual(@as(i32, 100), lx);
    try testing.expectEqual(@as(i32, 50), ly);
    try testing.expectEqual(@as(i32, 960), lw);
    try testing.expectEqual(@as(i32, 540), lh);
    try testing.expectEqual(@as(i32, 200), px);
    try testing.expectEqual(@as(i32, 100), py);
    try testing.expectEqual(@as(i32, 1920), pw);
    try testing.expectEqual(@as(i32, 1080), ph);
}

test "send details stores baselines and omits deprecated done" {
    resetXdgWorld();
    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    out.scale = 1;
    var output: Output = std.mem.zeroes(Output);
    output.wlr_output = &out;
    var res: Res = std.mem.zeroes(Res);
    res.resource = &stub_resource;
    xdg_output_send_details(&output, &stub_resource);
    try testing.expectEqual(@as(c_int, 1), stub_pos_calls);
    try testing.expectEqual(@as(c_int, 1), stub_size_calls);
    try testing.expectEqual(@as(c_int, 0), stub_done_calls);
    try testing.expect(output.sent);
    try testing.expectEqual(@as(i32, 1920), output.last_lw);

    stub_version = 2;
    xdg_output_send_details(&output, &stub_resource);
    try testing.expectEqual(@as(c_int, 1), stub_done_calls);
}

test "logical and xwayland change detection" {
    resetXdgWorld();
    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    out.scale = 1;
    var output: Output = std.mem.zeroes(Output);
    output.wlr_output = &out;
    try testing.expect(!xdg_output_logical_changed(&output));
    output.sent = true;
    output.last_lx = 0;
    output.last_ly = 0;
    output.last_lw = 100;
    output.last_lh = 100;
    try testing.expect(xdg_output_logical_changed(&output));
    output.last_lw = 1920;
    output.last_lh = 1080;
    try testing.expect(!xdg_output_logical_changed(&output));

    output.last_px = 99;
    try testing.expect(xdg_output_xwayland_changed(&output));
    try testing.expectEqual(@as(i32, 0), output.last_px);
    try testing.expect(!xdg_output_xwayland_changed(&output));
}

test "update resends xwayland always and logical only on change" {
    resetXdgWorld();
    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    out.scale = 1;
    var output: Output = std.mem.zeroes(Output);
    output.wlr_output = &out;
    listInit(&output.resources);
    const r1 = @as(*Res, @ptrCast(@alignCast(c.calloc(1, @sizeOf(Res)) orelse unreachable)));
    r1.resource = &stub_resource;
    c.wl_list_insert(&output.resources, &r1.link);
    output.sent = true;
    output.last_lx = 0;
    output.last_ly = 0;
    output.last_lw = 1920;
    output.last_lh = 1080;
    xdg_output_update(&output);
    try testing.expectEqual(@as(c_int, 0), stub_pos_calls);
    output.last_lw = 1;
    xdg_output_update(&output);
    try testing.expectEqual(@as(c_int, 1), stub_pos_calls);
    c.wl_list_remove(&r1.link);
    c.free(r1);
}

test "create, find, description and destroy manage resources" {
    resetXdgWorld();
    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    listInit(&out.events.description.listener_list);
    var m: Monitor = std.mem.zeroes(Monitor);
    out.data = @ptrCast(&m);
    out.name = @constCast("eDP-1");
    out.description = @constCast("panel");
    const output = xdg_output_create(&out);
    try testing.expect(output != null);
    try testing.expect(xdg_output_find(&out) == output);

    const res = @as(*Res, @ptrCast(@alignCast(c.calloc(1, @sizeOf(Res)) orelse unreachable)));
    res.resource = &stub_resource;
    c.wl_list_insert(&output.*.resources, &res.link);
    stub_version = 3;
    handle_xdg_output_description(&output.*.unnamed_0.description, null);
    try testing.expectEqual(@as(c_int, 1), stub_desc_calls);
    stub_version = 2;
    handle_xdg_output_description(&output.*.unnamed_0.description, null);
    try testing.expectEqual(@as(c_int, 1), stub_desc_calls);

    xdg_output_destroy(output);
    try testing.expect(xdg_output_find(&out) == null);
    try testing.expectEqual(@as(c_int, 1), stub_set_user_data_calls);
}

test "manager get_output wires resources and names" {
    resetXdgWorld();
    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    listInit(&out.events.description.listener_list);
    out.scale = 1;
    out.name = @constCast("eDP-1");
    out.description = @constCast("panel");
    out.resources = std.mem.zeroes(c.struct_wl_list);
    listInit(&out.resources);
    stub_wlr_output = &out;
    stub_version = 3;
    stub_wl_output_resource = &stub_resource2;
    handle_xdg_output_manager_get_output(null, &stub_resource, 7, &stub_resource2);
    try testing.expectEqual(@as(c_int, 1), stub_name_calls);
    try testing.expectEqual(@as(c_int, 1), stub_desc_calls);
    try testing.expectEqual(@as(c_int, 1), stub_pos_calls);
    try testing.expectEqual(@as(c_int, 1), stub_output_done_calls);
    try testing.expect(xdg_output_find(&out) != null);

    stub_wlr_output = null;
    const impl_before = stub_impl_calls;
    handle_xdg_output_manager_get_output(null, &stub_resource, 8, &stub_resource2);
    try testing.expectEqual(impl_before + 1, stub_impl_calls);
}

test "update all schedules done on logical changes" {
    resetXdgWorld();
    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    out.scale = 1;
    listInit(&out.events.description.listener_list);
    listInit(&out.resources);
    const output = xdg_output_create(&out);
    output.*.sent = true;
    output.*.last_lx = 0;
    output.*.last_ly = 0;
    output.*.last_lw = 1;
    output.*.last_lh = 1;
    xdg_output_update_all();
    try testing.expectEqual(@as(c_int, 1), stub_schedule_done_calls);
    xdg_output_destroy(output);
}

test "init creates the manager global" {
    resetXdgWorld();
    xdg_output_init();
    try testing.expect(xdg_output_global != null);
    try testing.expectEqual(@as(c_int, 0), stub_error_calls);
}
