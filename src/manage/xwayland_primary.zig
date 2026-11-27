//! Port of manage/xwayland_primary.c (Phase 5, manage slice, slice 85).

const std = @import("std");
const c = @import("cc");

const Monitor = c.Monitor;
const MAX_NAME = 64;
const CACHE_MAX = 16;

var conn: ?*c.xcb_connection_t = null;
var conn_source: ?*c.struct_wl_event_source = null;
var root: c.xcb_window_t = c.XCB_NONE;
var display_name: [MAX_NAME]u8 = std.mem.zeroes([MAX_NAME]u8);
var target_name: [MAX_NAME]u8 = std.mem.zeroes([MAX_NAME]u8);
var applied_name: [MAX_NAME]u8 = std.mem.zeroes([MAX_NAME]u8);
var cache_name: [CACHE_MAX][MAX_NAME]u8 = std.mem.zeroes([CACHE_MAX][MAX_NAME]u8);
var cache_output: [CACHE_MAX]c.xcb_randr_output_t = std.mem.zeroes([CACHE_MAX]c.xcb_randr_output_t);
var cache_len: i32 = 0;
var cache_valid: bool = false;
var resources_pending: bool = false;
var resources_cookie: c.xcb_randr_get_screen_resources_cookie_t = undefined;
var info_pending: bool = false;
var info_cookie: c.xcb_randr_get_output_info_cookie_t = undefined;
var outputs: [*c]c.xcb_randr_output_t = null;
var outputs_len: i32 = 0;
var outputs_idx: i32 = 0;
var cache_refresh_attempted: bool = false;

extern fn wl_event_loop_add_fd(loop: ?*c.struct_wl_event_loop, fd: c_int, mask: u32, func: ?*const fn (c_int, u32, ?*anyopaque) callconv(.c) c_int, data: ?*anyopaque) callconv(.c) ?*c.struct_wl_event_source;
extern fn wl_event_source_remove(source: ?*c.struct_wl_event_source) callconv(.c) c_int;
extern fn wl_display_get_event_loop(display: ?*c.struct_wl_display) callconv(.c) ?*c.struct_wl_event_loop;
extern fn xcb_connect(displayname: [*c]const u8, screenp: *c_int) callconv(.c) ?*c.xcb_connection_t;
extern fn xcb_disconnect(conn: ?*c.xcb_connection_t) callconv(.c) void;
extern fn xcb_connection_has_error(conn: ?*c.xcb_connection_t) callconv(.c) c_int;
extern fn xcb_get_setup(conn: ?*c.xcb_connection_t) callconv(.c) ?*c.xcb_setup_t;
extern fn xcb_setup_roots_iterator(setup: ?*c.xcb_setup_t) callconv(.c) c.xcb_screen_iterator_t;
extern fn xcb_screen_next(it: *c.xcb_screen_iterator_t) callconv(.c) void;
extern fn xcb_get_file_descriptor(conn: ?*c.xcb_connection_t) callconv(.c) c_int;
extern fn xcb_flush(conn: ?*c.xcb_connection_t) callconv(.c) c_int;
extern fn xcb_poll_for_event(conn: ?*c.xcb_connection_t) callconv(.c) ?*c.xcb_generic_event_t;
extern fn xcb_randr_get_screen_resources(conn: ?*c.xcb_connection_t, root: c.xcb_window_t) callconv(.c) c.xcb_randr_get_screen_resources_cookie_t;
extern fn xcb_randr_get_screen_resources_reply(conn: ?*c.xcb_connection_t, cookie: c.xcb_randr_get_screen_resources_cookie_t, err: ?*?*c.xcb_generic_error_t) callconv(.c) ?*c.xcb_randr_get_screen_resources_reply_t;
extern fn xcb_randr_get_screen_resources_outputs_length(reply: ?*c.xcb_randr_get_screen_resources_reply_t) callconv(.c) c_int;
extern fn xcb_randr_get_screen_resources_outputs(reply: ?*c.xcb_randr_get_screen_resources_reply_t) callconv(.c) [*c]c.xcb_randr_output_t;
extern fn xcb_randr_get_output_info(conn: ?*c.xcb_connection_t, output: c.xcb_randr_output_t, config_timestamp: c.xcb_timestamp_t) callconv(.c) c.xcb_randr_get_output_info_cookie_t;
extern fn xcb_randr_get_output_info_reply(conn: ?*c.xcb_connection_t, cookie: c.xcb_randr_get_output_info_cookie_t, err: ?*?*c.xcb_generic_error_t) callconv(.c) ?*c.xcb_randr_get_output_info_reply_t;
extern fn xcb_randr_get_output_info_name_length(reply: ?*c.xcb_randr_get_output_info_reply_t) callconv(.c) c_int;
extern fn xcb_randr_get_output_info_name(reply: ?*c.xcb_randr_get_output_info_reply_t) callconv(.c) [*c]u8;
extern fn xcb_randr_set_output_primary(conn: ?*c.xcb_connection_t, root: c.xcb_window_t, output: c.xcb_randr_output_t) callconv(.c) c.xcb_void_cookie_t;
extern fn xcb_randr_get_output_primary(conn: ?*c.xcb_connection_t, root: c.xcb_window_t) callconv(.c) c.xcb_randr_get_output_primary_cookie_t;
extern fn xcb_randr_get_output_primary_reply(conn: ?*c.xcb_connection_t, cookie: c.xcb_randr_get_output_primary_cookie_t, err: ?*?*c.xcb_generic_error_t) callconv(.c) ?*c.xcb_randr_get_output_primary_reply_t;
extern fn monitor_matches_rule(m: [*c]Monitor, rule: [*c]const c.ConfigMonitorRule) callconv(.c) bool;

fn xwaylandServerRunning() bool {
    return c.server.xwayland != null and c.server.xwayland.*.server != null and
        c.server.xwayland.*.server.*.ready;
}

fn unwatch() void {
    if (conn_source != null) {
        _ = wl_event_source_remove(conn_source);
        conn_source = null;
    }
}

fn watch() void {
    if (conn == null or conn_source != null) return;
    conn_source = wl_event_loop_add_fd(wl_display_get_event_loop(c.server.display), xcb_get_file_descriptor(conn), c.WL_EVENT_READABLE, xwaylandPrimaryReady, null);
}

fn closeConn() void {
    unwatch();
    if (conn != null) {
        xcb_disconnect(conn);
        conn = null;
    }
    root = c.XCB_NONE;
    applied_name[0] = 0;
    resources_pending = false;
    info_pending = false;
    c.free(outputs);
    outputs = null;
    outputs_len = 0;
    outputs_idx = 0;
    cache_len = 0;
    cache_valid = false;
}

fn connect() bool {
    if (conn != null) return true;
    var screen_num: c_int = 0;
    conn = xcb_connect(&display_name, &screen_num);
    if (conn == null or xcb_connection_has_error(conn) != 0 or xcb_get_setup(conn) == null) {
        closeConn();
        return false;
    }
    var it = xcb_setup_roots_iterator(xcb_get_setup(conn));
    var i: i32 = 0;
    while (i < screen_num and it.rem != 0) : (i += 1) xcb_screen_next(&it);
    if (it.rem == 0) {
        closeConn();
        return false;
    }
    root = it.data.*.root;
    cache_valid = false;
    return true;
}

fn buildCache() void {
    c.free(outputs);
    outputs = null;
    outputs_len = 0;
    outputs_idx = 0;
    cache_len = 0;
    cache_valid = false;
    resources_pending = true;
    resources_cookie = xcb_randr_get_screen_resources(conn, root);
    _ = xcb_flush(conn);
}

fn apply() void {
    if (conn == null) return;
    if (target_name[0] == 0) {
        closeConn();
        return;
    }
    if (resources_pending or info_pending) return;
    if (!cache_valid) {
        buildCache();
        return;
    }
    var i: i32 = 0;
    while (i < cache_len) : (i += 1) {
        if (c.strncmp(&cache_name[@intCast(i)], &target_name, MAX_NAME) != 0) continue;
        _ = xcb_randr_set_output_primary(conn, root, cache_output[@intCast(i)]);
        _ = xcb_flush(conn);
        const reply = xcb_randr_get_output_primary_reply(conn, xcb_randr_get_output_primary(conn, root), null);
        c.free(reply);
        _ = c.strncpy(&applied_name, &target_name, MAX_NAME - 1);
        applied_name[MAX_NAME - 1] = 0;
        cache_refresh_attempted = false;
        closeConn();
        return;
    }
    if (!cache_refresh_attempted) {
        cache_refresh_attempted = true;
        cache_valid = false;
        buildCache();
        return;
    }
    applied_name[0] = 0;
    closeConn();
}

fn start() void {
    if (c.strncmp(&applied_name, &target_name, MAX_NAME) == 0) return;
    if (!xwaylandServerRunning()) {
        applied_name[0] = 0;
        cache_valid = false;
        return;
    }
    if (conn != null and xcb_connection_has_error(conn) != 0) closeConn();
    if (conn == null and !connect()) return;
    watch();
    apply();
}

fn xwaylandPrimaryReady(fd: c_int, mask: u32, data: ?*anyopaque) callconv(.c) c_int {
    _ = fd;
    _ = data;
    if (conn == null or (mask & (c.WL_EVENT_HANGUP | c.WL_EVENT_ERROR)) != 0) {
        closeConn();
        return 0;
    }
    while (xcb_poll_for_event(conn)) |event| c.free(event);
    if (resources_pending) {
        const resources = xcb_randr_get_screen_resources_reply(conn, resources_cookie, null);
        if (resources == null) {
            closeConn();
            return 0;
        }
        const len = xcb_randr_get_screen_resources_outputs_length(resources);
        outputs = @ptrCast(@alignCast(c.malloc(@sizeOf(c.xcb_randr_output_t) * @as(usize, @intCast(if (len > 0) len else 1)))));
        if (outputs != null and len > 0) {
            _ = c.memcpy(outputs, xcb_randr_get_screen_resources_outputs(resources), @sizeOf(c.xcb_randr_output_t) * @as(usize, @intCast(len)));
            outputs_len = len;
        }
        c.free(resources);
        resources_pending = false;
    } else if (info_pending) {
        const info = xcb_randr_get_output_info_reply(conn, info_cookie, null);
        if (info != null) {
            const len = xcb_randr_get_output_info_name_length(info);
            const name = xcb_randr_get_output_info_name(info);
            if (name != null and len > 0 and cache_len < CACHE_MAX) {
                const copy = @min(len, MAX_NAME - 1);
                _ = c.memcpy(&cache_name[@intCast(cache_len)], name, @intCast(copy));
                cache_name[@intCast(cache_len)][@intCast(copy)] = 0;
                cache_output[@intCast(cache_len)] = outputs[@intCast(outputs_idx)];
                cache_len += 1;
            }
            c.free(info);
        }
        info_pending = false;
        outputs_idx += 1;
    }
    if (resources_pending or info_pending) return 0;
    if (outputs_idx < outputs_len) {
        info_pending = true;
        info_cookie = xcb_randr_get_output_info(conn, outputs[@intCast(outputs_idx)], c.XCB_CURRENT_TIME);
        _ = xcb_flush(conn);
        return 0;
    }
    c.free(outputs);
    outputs = null;
    outputs_len = 0;
    outputs_idx = 0;
    cache_valid = true;
    apply();
    if (!resources_pending and !info_pending) unwatch();
    return 0;
}

fn ruleMonitor() [*c]Monitor {
    var first: [*c]Monitor = null;
    var by_rule: [*c]Monitor = null;
    var primary: [*c]Monitor = null;
    var best_rule: i32 = std.math.maxInt(i32);
    var primary_rule: i32 = std.math.maxInt(i32);
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.monitors);
    var pos = c.server.monitors.prev;
    while (pos != head) : (pos = pos.*.prev) {
        const m = @as([*c]Monitor, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Monitor, "link")));
        if (m.*.wlr_output == null or !m.*.wlr_output.*.enabled) continue;
        if (first == null) first = m;
        var i: i32 = 0;
        while (i < c.config.monitor_rules_count) : (i += 1) {
            if (monitor_matches_rule(m, &c.config.monitor_rules[@intCast(i)])) break;
        }
        if (i >= c.config.monitor_rules_count) continue;
        if (c.config.monitor_rules[@intCast(i)].primary != 0) {
            if (i < primary_rule) {
                primary_rule = i;
                primary = m;
            }
            continue;
        }
        if (i < best_rule) {
            best_rule = i;
            by_rule = m;
        }
    }
    if (primary != null) return primary;
    return if (by_rule != null) by_rule else first;
}

fn setMonitor(m: [*c]Monitor) void {
    const display = if (c.server.xwayland != null) c.server.xwayland.*.display_name else null;
    if (display == null or m == null or m.*.wlr_output == null or m.*.wlr_output.*.name == null) return;
    if (c.strncmp(&display_name, display, MAX_NAME) != 0) {
        closeConn();
        _ = c.strncpy(&display_name, display, MAX_NAME - 1);
        display_name[MAX_NAME - 1] = 0;
    }
    if (c.strncmp(&target_name, m.*.wlr_output.*.name, MAX_NAME) != 0)
        cache_refresh_attempted = false;
    _ = c.strncpy(&target_name, m.*.wlr_output.*.name, MAX_NAME - 1);
    target_name[MAX_NAME - 1] = 0;
    if (c.strncmp(&applied_name, &target_name, MAX_NAME) == 0) return;
    start();
}

export fn xwayland_primary_init() callconv(.c) void {
    const display = if (c.server.xwayland != null) c.server.xwayland.*.display_name else null;
    if (display == null) return;
    closeConn();
    _ = c.strncpy(&display_name, display, MAX_NAME - 1);
    display_name[MAX_NAME - 1] = 0;
    xwayland_primary_update();
}

export fn xwayland_primary_update() callconv(.c) void {
    cache_refresh_attempted = false;
    applied_name[0] = 0;
    cache_valid = false;
    const m = ruleMonitor();
    if (m != null) setMonitor(m) else target_name[0] = 0;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/xwayland_primary_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_conn: ?*anyopaque;
extern var stub_connect_calls: c_int;
extern var stub_disconnect_calls: c_int;
extern var stub_setup: ?*c.xcb_setup_t;
extern var stub_screen: ?*c.xcb_screen_t;
extern var stub_flush_calls: c_int;
extern var stub_get_resources_calls: c_int;
extern var stub_set_primary_calls: c_int;
extern var stub_set_primary_arg: c.xcb_randr_output_t;
extern var stub_watch_calls: c_int;
extern var stub_unwatch_calls: c_int;
extern var stub_rule_m1: [*c]Monitor;
extern var stub_m1_rule: c_int;
extern var stub_rule_m2: [*c]Monitor;
extern var stub_m2_rule: c_int;

var test_screen: c.xcb_screen_t = std.mem.zeroes(c.xcb_screen_t);
var test_output_a: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
var test_output_b: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
var test_mon_a: Monitor = std.mem.zeroes(Monitor);
var test_mon_b: Monitor = std.mem.zeroes(Monitor);
var test_xwayland: c.struct_wlr_xwayland = std.mem.zeroes(c.struct_wlr_xwayland);
var test_xserver: c.struct_wlr_xwayland_server = std.mem.zeroes(c.struct_wlr_xwayland_server);

var out_name_a = "eDP-1".*;
var out_name_b = "HDMI-A-1".*;
var test_display = ":0".*;

fn resetWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    conn = null;
    conn_source = null;
    root = c.XCB_NONE;
    display_name = std.mem.zeroes([MAX_NAME]u8);
    target_name = std.mem.zeroes([MAX_NAME]u8);
    applied_name = std.mem.zeroes([MAX_NAME]u8);
    cache_name = std.mem.zeroes([CACHE_MAX][MAX_NAME]u8);
    cache_output = std.mem.zeroes([CACHE_MAX]c.xcb_randr_output_t);
    cache_len = 0;
    cache_valid = false;
    resources_pending = false;
    info_pending = false;
    c.free(outputs);
    outputs = null;
    outputs_len = 0;
    outputs_idx = 0;
    cache_refresh_attempted = false;
    stub_conn = @ptrFromInt(0x1000);
    stub_setup = @ptrFromInt(0x2000);
    stub_screen = &test_screen;
    test_screen.root = 1;
    stub_connect_calls = 0;
    stub_disconnect_calls = 0;
    stub_flush_calls = 0;
    stub_get_resources_calls = 0;
    stub_set_primary_calls = 0;
    stub_set_primary_arg = 0;
    stub_watch_calls = 0;
    stub_unwatch_calls = 0;
    stub_rule_m1 = null;
    stub_m1_rule = -1;
    stub_rule_m2 = null;
    stub_m2_rule = -1;
    @memset(out_name_a[0..], 0);
    @memset(out_name_b[0..], 0);
    @memcpy(out_name_a[0..5], "eDP-1");
    @memcpy(out_name_b[0..8], "HDMI-A-1");
    test_output_a = std.mem.zeroes(c.struct_wlr_output);
    test_output_a.name = &out_name_a;
    test_output_a.enabled = true;
    test_output_b = std.mem.zeroes(c.struct_wlr_output);
    test_output_b.name = &out_name_b;
    test_output_b.enabled = true;
    test_mon_a = std.mem.zeroes(Monitor);
    test_mon_a.wlr_output = &test_output_a;
    test_mon_b = std.mem.zeroes(Monitor);
    test_mon_b.wlr_output = &test_output_b;
    test_xserver = std.mem.zeroes(c.struct_wlr_xwayland_server);
    test_xserver.ready = true;
    test_xwayland = std.mem.zeroes(c.struct_wlr_xwayland);
    test_xwayland.server = &test_xserver;
    test_xwayland.display_name = &test_display;
    c.wl_list_init(&c.server.monitors);
}

fn addMonitor(m: *Monitor) void {
    c.wl_list_insert(&c.server.monitors, &m.link);
}

fn targetSlice() []const u8 {
    return std.mem.sliceTo(&target_name, 0);
}

fn appliedSlice() []const u8 {
    return std.mem.sliceTo(&applied_name, 0);
}

test "update prefers a primary-flagged matching rule" {
    resetWorld();
    addMonitor(&test_mon_a);
    addMonitor(&test_mon_b);
    c.config.monitor_rules_count = 2;
    var rules = std.mem.zeroes([2]c.ConfigMonitorRule);
    rules[0].primary = 0;
    rules[1].primary = 1;
    c.config.monitor_rules = &rules;
    c.server.xwayland = &test_xwayland;
    stub_rule_m1 = &test_mon_a;
    stub_m1_rule = 0;
    stub_rule_m2 = &test_mon_b;
    stub_m2_rule = 1;
    xwayland_primary_update();
    try testing.expectEqualStrings("HDMI-A-1", targetSlice());
    try testing.expectEqual(@as(c_int, 1), stub_connect_calls);
    try testing.expectEqual(@as(c_int, 1), stub_get_resources_calls);
    try testing.expectEqual(@as(c_int, 1), stub_watch_calls);
}

test "update clears the target when no enabled output matches" {
    resetWorld();
    test_output_a.enabled = false;
    addMonitor(&test_mon_a);
    c.server.xwayland = &test_xwayland;
    stub_rule_m1 = &test_mon_a;
    stub_m1_rule = 0;
    c.config.monitor_rules_count = 1;
    var rules = std.mem.zeroes([1]c.ConfigMonitorRule);
    c.config.monitor_rules = &rules;
    xwayland_primary_update();
    try testing.expectEqual(@as(usize, 0), targetSlice().len);
    try testing.expectEqual(@as(c_int, 0), stub_connect_calls);
}

test "cached output is applied and the connection closed" {
    resetWorld();
    c.server.xwayland = &test_xwayland;
    @memcpy(display_name[0..3], ":0\x00");
    conn = @ptrFromInt(0x1000);
    @memcpy(cache_name[0][0..6], "eDP-1\x00");
    cache_output[0] = 42;
    cache_len = 1;
    cache_valid = true;
    setMonitor(&test_mon_a);
    try testing.expectEqual(@as(c_int, 1), stub_set_primary_calls);
    try testing.expectEqual(@as(c.xcb_randr_output_t, 42), stub_set_primary_arg);
    // close() clears applied_name after the copy, matching the C original.
    try testing.expectEqual(@as(usize, 0), appliedSlice().len);
    try testing.expectEqual(@as(i32, 0), cache_len);
    try testing.expect(conn == null);
    try testing.expectEqual(@as(c_int, 1), stub_disconnect_calls);
    try testing.expectEqualStrings(":0", std.mem.sliceTo(&display_name, 0));
}

test "unknown output refreshes the RandR cache" {
    resetWorld();
    c.server.xwayland = &test_xwayland;
    setMonitor(&test_mon_a);
    try testing.expectEqual(@as(c_int, 1), stub_get_resources_calls);
    try testing.expectEqual(@as(c_int, 0), stub_set_primary_calls);
    try testing.expect(conn != null);
    try testing.expect(resources_pending);
    try testing.expectEqualStrings("eDP-1", targetSlice());
}

test "init is a no-op without XWayland" {
    resetWorld();
    xwayland_primary_init();
    try testing.expectEqual(@as(c_int, 0), stub_connect_calls);
    try testing.expectEqual(@as(usize, 0), std.mem.sliceTo(&display_name, 0).len);
}

test "init copies the X display and targets the best monitor" {
    resetWorld();
    c.server.xwayland = &test_xwayland;
    addMonitor(&test_mon_a);
    stub_rule_m1 = &test_mon_a;
    stub_m1_rule = 0;
    c.config.monitor_rules_count = 1;
    var rules = std.mem.zeroes([1]c.ConfigMonitorRule);
    c.config.monitor_rules = &rules;
    xwayland_primary_init();
    try testing.expectEqualStrings(":0", std.mem.sliceTo(&display_name, 0));
    try testing.expectEqualStrings("eDP-1", targetSlice());
    try testing.expectEqual(@as(c_int, 1), stub_connect_calls);
}
