//! Port of the built-in idle cluster in src/manage/misc.c
//! (Phase 5, manage slice 2, slice 49).

const std = @import("std");
const c = @import("cc");

const Client = c.Client;
const Monitor = c.Monitor;
const Arg = c.Arg;

extern fn wlr_idle_notifier_v1_notify_activity(notifier: ?*c.struct_wlr_idle_notifier_v1, seat: ?*c.struct_wlr_seat) callconv(.c) void;
extern fn wl_event_source_timer_update(source: ?*c.struct_wl_event_source, ms_delay: c_int) callconv(.c) c_int;
extern fn spawn_shell(arg: *const Arg) callconv(.c) c_int;

extern "c" fn clock_gettime(clk_id: c_int, tp: *c.struct_timespec) c_int;

fn monitorOpt(p: [*c]Monitor) ?*Monitor {
    return if (p == null) null else @ptrCast(p);
}

fn clientOpt(p: [*c]Client) ?*Client {
    return if (p == null) null else @ptrCast(p);
}

fn VISIBLEON(cl: *const Client, m: *const Monitor) bool {
    if (cl.mon != @as([*c]Monitor, @ptrCast(@constCast(m))))
        return false;
    if (cl.isminimized != 0)
        return false;
    return (cl.tags & m.tagset[m.seltags]) != 0 or cl.isglobal != 0 or cl.isunglobal != 0;
}

fn clientKeepIdleInhibit(cl: ?*Client) bool {
    const client = cl orelse return false;
    const m = monitorOpt(client.mon) orelse return false;

    if (client.idleinhibit_when_focus != 0)
        return true;

    if (c.config.idleinhibit_when_fullscreen != 0 and client.isfullscreen != 0 and
        VISIBLEON(client, m))
        return true;

    return false;
}

export fn check_keep_idle_inhibit(cl: ?*Client) callconv(.c) void {
    if (c.server.keep_idle_inhibit_source != null and clientKeepIdleInhibit(cl))
        _ = wl_event_source_timer_update(c.server.keep_idle_inhibit_source, 1000);
}

export fn idle_keep_inhibit(data: ?*anyopaque) callconv(.c) c_int {
    _ = data;
    if (c.server.idle_inhibit_manager == null) {
        _ = wl_event_source_timer_update(c.server.keep_idle_inhibit_source, 0);
        return 1;
    }

    if (c.server.session != null and !c.server.session.*.active) {
        _ = wl_event_source_timer_update(c.server.keep_idle_inhibit_source, 0);
        return 1;
    }

    const selected = monitorOpt(c.server.selected_monitor);
    if (selected == null or !clientKeepIdleInhibit(clientOpt(selected.?.sel))) {
        _ = wl_event_source_timer_update(c.server.keep_idle_inhibit_source, 0);
        return 1;
    }

    if (c.server.seat != null and c.server.idle_notifier != null) {
        wlr_idle_notifier_v1_notify_activity(c.server.idle_notifier, c.server.seat);
        _ = wl_event_source_timer_update(c.server.keep_idle_inhibit_source, 1000);
    }
    return 1;
}

fn idleNowMs() i64 {
    var ts: c.struct_timespec = undefined;
    _ = clock_gettime(c.CLOCK_MONOTONIC, &ts);
    return @as(i64, @intCast(ts.tv_sec)) * 1000 + @divTrunc(@as(i64, @intCast(ts.tv_nsec)), 1000000);
}

export fn acwm_idle_init() callconv(.c) void {
    c.server.last_activity_ms = idleNowMs();
    c.server.idle_triggered = false;
    rearm_idle_check();
}

export fn acwm_notify_activity(seat: ?*c.struct_wlr_seat) callconv(.c) void {
    const was_idle = c.server.idle_triggered;

    c.server.last_activity_ms = idleNowMs();
    c.server.idle_triggered = false;

    if (c.server.idle_notifier != null)
        wlr_idle_notifier_v1_notify_activity(c.server.idle_notifier, seat);

    if (was_idle and c.config.resume_command != null and c.config.resume_command[0] != 0) {
        var arg = std.mem.zeroes(Arg);
        arg.v = c.config.resume_command;
        _ = spawn_shell(&arg);
    }

    rearm_idle_check();
}

export fn rearm_idle_check() callconv(.c) void {
    if (c.server.idle_check_source == null)
        return;

    const idle_ms: i64 = @as(i64, c.config.idle_after) * 1000;
    if (idle_ms <= 0) {
        _ = wl_event_source_timer_update(c.server.idle_check_source, 0);
        return;
    }

    const remaining = idle_ms - (idleNowMs() - c.server.last_activity_ms);
    _ = wl_event_source_timer_update(c.server.idle_check_source, if (remaining > 0) @intCast(remaining) else 1);
}

export fn idle_check(data: ?*anyopaque) callconv(.c) c_int {
    _ = data;
    const idle_ms: i64 = @as(i64, c.config.idle_after) * 1000;
    if (idle_ms <= 0 or c.server.idle_triggered)
        return 1;

    if (c.server.idle_inhibited or (c.server.session != null and c.server.session.*.active)) {
        _ = wl_event_source_timer_update(c.server.idle_check_source, 1000);
        return 1;
    }

    if (idleNowMs() - c.server.last_activity_ms >= idle_ms) {
        c.server.idle_triggered = true;
        _ = wl_event_source_timer_update(c.server.idle_check_source, 0);
        if (c.config.idle_command != null and c.config.idle_command[0] != 0) {
            var arg = std.mem.zeroes(Arg);
            arg.v = c.config.idle_command;
            _ = spawn_shell(&arg);
        }
        return 1;
    }

    rearm_idle_check();
    return 1;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/idle_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_notify_calls: c_int;
extern var stub_timer_calls: c_int;
extern var stub_timer_delay: c_int;
extern var stub_spawn_calls: c_int;
extern var stub_spawn_cmd: [256]u8;

fn nowMs() i64 {
    return idleNowMs();
}

fn resetIdleWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    stub_notify_calls = 0;
    stub_timer_calls = 0;
    stub_timer_delay = -1;
    stub_spawn_calls = 0;
    stub_spawn_cmd = std.mem.zeroes([256]u8);
}

fn fakeSource() ?*c.struct_wl_event_source {
    return @ptrFromInt(8);
}

test "idle init arms the timer and rearm respects idle_after" {
    resetIdleWorld();
    c.server.idle_check_source = fakeSource();
    c.config.idle_after = 10;

    acwm_idle_init();
    try testing.expect(!c.server.idle_triggered);
    try testing.expect(c.server.last_activity_ms > 0);
    try testing.expect(stub_timer_delay > 9000 and stub_timer_delay <= 10000);

    c.config.idle_after = 0;
    rearm_idle_check();
    try testing.expectEqual(@as(c_int, 0), stub_timer_delay);

    c.server.idle_check_source = null;
    const before = stub_timer_calls;
    rearm_idle_check();
    try testing.expectEqual(before, stub_timer_calls);
}

test "activity resets idle state and runs resume_command" {
    resetIdleWorld();
    c.server.idle_check_source = fakeSource();
    c.server.idle_notifier = @ptrFromInt(16);
    c.server.seat = @ptrFromInt(24);
    c.server.idle_triggered = true;
    c.server.last_activity_ms = nowMs() - 50000;
    c.config.idle_after = 5;
    c.config.resume_command = @ptrCast(@constCast(@as([*:0]const u8, "resume")));

    acwm_notify_activity(c.server.seat);
    try testing.expect(!c.server.idle_triggered);
    try testing.expectEqual(@as(c_int, 1), stub_notify_calls);
    try testing.expectEqual(@as(c_int, 1), stub_spawn_calls);
    try testing.expectEqualStrings("resume", std.mem.span(@as([*:0]const u8, @ptrCast(&stub_spawn_cmd))));
    try testing.expect(stub_timer_delay > 4000 and stub_timer_delay <= 5000);
}

test "keep-idle inhibit polls only while a keep client is focused" {
    resetIdleWorld();
    c.server.keep_idle_inhibit_source = fakeSource();
    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    var m: c.Monitor = std.mem.zeroes(c.Monitor);
    var cl: c.Client = std.mem.zeroes(c.Client);
    m.wlr_output = @ptrCast(&out);
    m.tagset[0] = 1;
    cl.mon = @ptrCast(&m);
    cl.tags = 1;
    cl.idleinhibit_when_focus = 1;
    m.sel = @ptrCast(&cl);
    c.server.selected_monitor = &m;

    _ = idle_keep_inhibit(null);
    try testing.expectEqual(@as(c_int, 0), stub_timer_delay);

    c.server.idle_inhibit_manager = @ptrFromInt(32);
    var session: c.struct_wlr_session = std.mem.zeroes(c.struct_wlr_session);
    session.active = false;
    c.server.session = &session;
    _ = idle_keep_inhibit(null);
    try testing.expectEqual(@as(c_int, 0), stub_timer_delay);

    session.active = true;
    _ = idle_keep_inhibit(null);
    try testing.expectEqual(@as(c_int, 0), stub_timer_delay);

    c.server.seat = @ptrFromInt(24);
    c.server.idle_notifier = @ptrFromInt(16);
    _ = idle_keep_inhibit(null);
    try testing.expectEqual(@as(c_int, 1), stub_notify_calls);
    try testing.expectEqual(@as(c_int, 1000), stub_timer_delay);

    c.config.idleinhibit_when_fullscreen = 1;
    cl.idleinhibit_when_focus = 0;
    cl.isfullscreen = 1;
    check_keep_idle_inhibit(&cl);
    try testing.expectEqual(@as(c_int, 1000), stub_timer_delay);
}

test "idle check triggers idle_command once" {
    resetIdleWorld();
    c.server.idle_check_source = fakeSource();
    c.config.idle_after = 10;

    c.server.idle_triggered = true;
    _ = idle_check(null);
    try testing.expectEqual(@as(c_int, 0), stub_timer_calls);

    c.server.idle_triggered = false;
    c.server.idle_inhibited = true;
    _ = idle_check(null);
    try testing.expectEqual(@as(c_int, 1000), stub_timer_delay);
    c.server.idle_inhibited = false;

    c.server.last_activity_ms = nowMs();
    c.config.idle_after = 0;
    _ = idle_check(null);
    try testing.expectEqual(@as(c_int, 0), stub_spawn_calls);

    c.config.idle_after = 10;
    c.config.idle_command = @ptrCast(@constCast(@as([*:0]const u8, "lock")));
    c.server.last_activity_ms = nowMs() - 20000;
    _ = idle_check(null);
    try testing.expect(c.server.idle_triggered);
    try testing.expectEqual(@as(c_int, 0), stub_timer_delay);
    try testing.expectEqual(@as(c_int, 1), stub_spawn_calls);
    try testing.expectEqualStrings("lock", std.mem.span(@as([*:0]const u8, @ptrCast(&stub_spawn_cmd))));

    c.server.idle_triggered = false;
    c.server.last_activity_ms = nowMs();
    _ = idle_check(null);
    try testing.expect(stub_timer_delay > 9000 and stub_timer_delay <= 10000);
}
