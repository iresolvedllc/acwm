//! Port of the output lifecycle / skip-frame timer / renderer-loss cluster
//! in src/manage/monitor.c (Phase 5, manage slice 7, slice 55).

const std = @import("std");
const c = @import("cc");

const Monitor = c.Monitor;
const Allocator = @TypeOf(c.server.allocator);
const Client = c.Client;
const LayerSurface = c.LayerSurface;

extern fn wlr_ext_workspace_group_handle_v1_output_leave(group: ?*c.struct_wlr_ext_workspace_group_handle_v1, output: [*c]c.struct_wlr_output) callconv(.c) void;
extern fn wlr_ext_workspace_group_handle_v1_destroy(group: ?*c.struct_wlr_ext_workspace_group_handle_v1) callconv(.c) void;
extern fn wlr_foreign_toplevel_handle_v1_output_leave(handle: ?*c.struct_wlr_foreign_toplevel_handle_v1, output: [*c]c.struct_wlr_output) callconv(.c) void;
extern fn wlr_foreign_toplevel_handle_v1_destroy(handle: ?*c.struct_wlr_foreign_toplevel_handle_v1) callconv(.c) void;
extern fn bar_monitor_destroy(m: [*c]Monitor) callconv(.c) void;
extern fn cleanup_workspaces_by_monitor(m: [*c]Monitor) callconv(.c) void;
extern fn cleanup_monitor_dwindle(m: [*c]Monitor) callconv(.c) void;
extern fn cleanup_monitor_scroller(m: [*c]Monitor) callconv(.c) void;
extern fn handle_session_lock_surface_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn set_selected_monitor(m: [*c]Monitor) callconv(.c) void;
extern fn client_set_group_mon(cl: [*c]Client, m: [*c]Monitor) callconv(.c) void;
extern fn client_update_oldmonname_record(cl: [*c]Client, m: [*c]Monitor) callconv(.c) void;
extern fn client_focus(cl: ?*Client, lift: i32) callconv(.c) void;
extern fn client_focus_top(m: [*c]Monitor) callconv(.c) [*c]Client;
extern fn printstatus(t: c.enum_ipc_watch_type) callconv(.c) void;
extern fn handle_output_layout_change(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn wlr_backend_is_wl(backend: [*c]c.struct_wlr_backend) callconv(.c) bool;
extern fn wlr_backend_is_headless(backend: [*c]c.struct_wlr_backend) callconv(.c) bool;
extern fn wlr_wl_output_create(backend: [*c]c.struct_wlr_backend) callconv(.c) [*c]c.struct_wlr_output;
extern fn wlr_headless_add_output(backend: [*c]c.struct_wlr_backend, width: u32, height: u32) callconv(.c) [*c]c.struct_wlr_output;
extern fn fx_renderer_create(backend: [*c]c.struct_wlr_backend) callconv(.c) [*c]c.struct_wlr_renderer;
extern fn wlr_allocator_autocreate(backend: [*c]c.struct_wlr_backend, renderer: [*c]c.struct_wlr_renderer) callconv(.c) Allocator;
extern fn wlr_allocator_destroy(allocator: Allocator) callconv(.c) void;

fn containerOf(comptime T: type, comptime field: []const u8, link: anytype) *T {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(T, field));
}

fn monitorFromLink(link: [*c]c.struct_wl_list) *Monitor {
    return containerOf(Monitor, "link", link);
}

fn clientFromLink(link: [*c]c.struct_wl_list) *Client {
    return containerOf(Client, "link", link);
}

export fn handle_output_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const m = containerOf(Monitor, "destroy", listener);

    m.iscleanuping = true;
    bar_monitor_destroy(m);

    var i: usize = 0;
    while (i < m.layers.len) : (i += 1) {
        var pos = m.layers[i].next;
        const head: [*c]c.struct_wl_list = @ptrCast(&m.layers[i]);
        while (pos != head) {
            const next = pos.*.next;
            const l = containerOf(LayerSurface, "link", pos);
            c.wlr_layer_surface_v1_destroy(l.layer_surface);
            pos = next;
        }
    }

    if (m.ext_group != null) {
        wlr_ext_workspace_group_handle_v1_output_leave(m.ext_group, m.wlr_output);
        wlr_ext_workspace_group_handle_v1_destroy(m.ext_group);
    }
    cleanup_workspaces_by_monitor(m);

    c.wl_list_remove(&m.destroy.link);
    c.wl_list_remove(&m.frame.link);
    c.wl_list_remove(&m.link);
    c.wl_list_remove(&m.request_state.link);
    if (m.lock_surface != null)
        handle_session_lock_surface_destroy(&m.destroy_lock_surface, null);
    m.wlr_output.*.data = null;

    c.wlr_scene_output_destroy(m.scene_output);
    c.wlr_output_layout_remove(c.server.output_layout, m.wlr_output);

    monitor_close(m);
    if (m.blur != null) {
        c.wlr_scene_node_destroy(&m.blur.*.node);
        m.blur = null;
    }
    if (m.special_dim_rect != null) {
        c.wlr_scene_node_destroy(&m.special_dim_rect.*.node);
        m.special_dim_rect = null;
    }
    if (m.skip_frame_timeout != null) {
        monitor_stop_skip_frame_timer(m);
        _ = c.wl_event_source_remove(m.skip_frame_timeout);
        m.skip_frame_timeout = null;
    }
    m.wlr_output.*.data = null;

    cleanup_monitor_dwindle(m);
    cleanup_monitor_scroller(m);

    c.wlr_color_transform_unref(m.icc_transform);
    m.icc_transform = null;
    c.wlr_output_state_finish(&m.pending);
    c.free(m.pertag);
    c.free(m);
}

export fn monitor_close(m: *Monitor) callconv(.c) void {
    if (c.server.gesture_drive_mon != null and @intFromPtr(c.server.gesture_drive_mon) == @intFromPtr(m)) {
        c.server.gesture_drive_active = false;
        c.server.gesture_drive_mon = null;
    }

    if (m.isoverview != 0) {
        var arg = std.mem.zeroes(c.Arg);
        _ = c.toggle_overview(&arg);
    }

    const nmons = c.wl_list_length(&c.server.monitors);
    if (nmons == 0) {
        set_selected_monitor(null);
    } else if (c.server.selected_monitor != null and @intFromPtr(c.server.selected_monitor) == @intFromPtr(m)) {
        var next: [*c]Monitor = null;
        var pos = c.server.monitors.next;
        const head: [*c]c.struct_wl_list = @ptrCast(&c.server.monitors);
        while (pos != head) : (pos = pos.*.next) {
            const cand = monitorFromLink(pos);
            if (cand.wlr_output != null and cand.wlr_output.*.enabled) {
                next = cand;
                break;
            }
        }
        set_selected_monitor(next);
    }

    var pos = c.server.clients.next;
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = clientFromLink(pos);
        if (cl.mon != @as([*c]Monitor, @ptrCast(m)))
            continue;

        if (c.server.selected_monitor == null) {
            if (cl.foreign_toplevel != null) {
                wlr_foreign_toplevel_handle_v1_output_leave(cl.foreign_toplevel, cl.mon.*.wlr_output);
                wlr_foreign_toplevel_handle_v1_destroy(cl.foreign_toplevel);
                cl.foreign_toplevel = null;
            }
            client_set_group_mon(cl, null);
        } else {
            client_set_group_mon(cl, c.server.selected_monitor);
        }

        if (cl.oldmonname[0] == 0)
            client_update_oldmonname_record(cl, m);
    }

    if (c.server.selected_monitor != null) {
        client_focus(c.client_focus_top(c.server.selected_monitor), 1);
        printstatus(@intCast(c.IPC_WATCH_ARRANGGE));
    }
}

export fn handle_output_request_state(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    const m = containerOf(Monitor, "request_state", listener);
    const event = @as(*c.struct_wlr_output_event_request_state, @ptrCast(@alignCast(data.?)));
    if (event.state == null)
        return;

    if (event.state.*.committed == @as(u32, @intCast(c.WLR_OUTPUT_STATE_MODE))) {
        switch (@as(c_int, @intCast(event.state.*.mode_type))) {
            c.WLR_OUTPUT_STATE_MODE_FIXED => c.wlr_output_state_set_mode(&m.pending, event.state.*.mode),
            c.WLR_OUTPUT_STATE_MODE_CUSTOM => c.wlr_output_state_set_custom_mode(
                &m.pending,
                event.state.*.custom_mode.width,
                event.state.*.custom_mode.height,
                event.state.*.custom_mode.refresh,
            ),
            else => {},
        }
        handle_output_layout_change(null, null);
        c.wlr_output_schedule_frame(m.wlr_output);
        return;
    }

    _ = c.wlr_output_commit_state(m.wlr_output, event.state);
}

export fn create_output(b: [*c]c.struct_wlr_backend, data: ?*anyopaque) callconv(.c) void {
    const done = @as(*bool, @ptrCast(@alignCast(data.?)));
    if (done.*)
        return;

    if (wlr_backend_is_wl(b)) {
        _ = wlr_wl_output_create(b);
        done.* = true;
    } else if (wlr_backend_is_headless(b)) {
        _ = wlr_headless_add_output(b, 1920, 1080);
        done.* = true;
    }
    handle_output_layout_change(null, null);
}

export fn handle_output_power_manager_set_mode(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as(*c.struct_wlr_output_power_v1_set_mode_event, @ptrCast(@alignCast(data.?)));
    if (event.output == null or event.output.*.data == null)
        return;
    const m = @as(*Monitor, @ptrCast(@alignCast(event.output.*.data.?)));

    c.wlr_output_state_set_enabled(&m.pending, event.mode != 0);
    _ = c.acwm_output_commit(m);
    m.only_sleep = if (event.mode == 0) 1 else 0;
    handle_output_layout_change(null, null);
}

export fn monitor_stop_skip_frame_timer(m: *Monitor) callconv(.c) void {
    if (m.skip_frame_timeout != null)
        _ = c.wl_event_source_timer_update(m.skip_frame_timeout, 0);
    m.skiping_frame = false;
    m.resizing_count_pending = 0;
    m.resizing_count_current = 0;
}

export fn monitor_skip_frame_timeout_callback(data: ?*anyopaque) callconv(.c) c_int {
    const m = @as(*Monitor, @ptrCast(@alignCast(data.?)));

    var pos = c.server.clients.next;
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    while (pos != head) {
        const next = pos.*.next;
        const cl = clientFromLink(pos);
        cl.configure_serial = 0;
        pos = next;
    }

    monitor_stop_skip_frame_timer(m);
    c.wlr_output_schedule_frame(m.wlr_output);
    return 1;
}

export fn monitor_check_skip_frame_timeout(m: *Monitor) callconv(.c) void {
    if (m.skiping_frame and m.resizing_count_pending == m.resizing_count_current)
        return;

    if (m.skip_frame_timeout != null) {
        m.resizing_count_current = m.resizing_count_pending;
        m.skiping_frame = true;
        _ = c.wl_event_source_timer_update(m.skip_frame_timeout, 100);
    }
}

fn doRendererRecreate(data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const old_renderer = c.server.renderer;
    const old_allocator = c.server.allocator;

    c.server.recreate_renderer_source = null;

    const renderer = fx_renderer_create(c.server.backend);
    if (renderer == null)
        die();
    c.server.renderer = renderer;

    const allocator = wlr_allocator_autocreate(c.server.backend, c.server.renderer);
    if (allocator == null)
        die();
    c.server.allocator = allocator;

    c.wl_list_remove(&c.server.gpu_reset_listener.link);
    c.wl_signal_add(&c.server.renderer.*.events.lost, &c.server.gpu_reset_listener);

    c.wlr_compositor_set_renderer(c.server.compositor, c.server.renderer);

    var pos = c.server.monitors.next;
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.monitors);
    while (pos != head) : (pos = pos.*.next) {
        const m = monitorFromLink(pos);
        _ = c.wlr_output_init_render(m.wlr_output, c.server.allocator, c.server.renderer);
    }

    wlr_allocator_destroy(old_allocator);
    c.wlr_renderer_destroy(old_renderer);
}

fn die() void {
    @panic("couldn't recreate renderer");
}

export fn handle_renderer_lost(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    _ = data;
    if (c.server.recreate_renderer_source != null)
        return;

    c.server.recreate_renderer_source = c.wl_event_loop_add_idle(c.server.event_loop, doRendererRecreate, null);
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/monitor_lifecycle_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_list_insert_calls: c_int;
extern var stub_list_remove_calls: c_int;
extern var stub_bar_destroy_calls: c_int;
extern var stub_workspace_cleanup_calls: c_int;
extern var stub_dwindle_cleanup_calls: c_int;
extern var stub_scroller_cleanup_calls: c_int;
extern var stub_ext_leave_calls: c_int;
extern var stub_ext_destroy_calls: c_int;
extern var stub_ft_leave_calls: c_int;
extern var stub_ft_destroy_calls: c_int;
extern var stub_set_group_calls: c_int;
extern var stub_last_group_mon: [*c]Monitor;
extern var stub_oldmonname_calls: c_int;
extern var stub_focus_calls: c_int;
extern var stub_focus_client: [*c]Client;
extern var stub_focus_lift: i32;
extern var stub_top_client: [*c]Client;
extern var stub_printstatus_calls: c_int;
extern var stub_selected_calls: c_int;
extern var stub_selected_value: [*c]Monitor;
extern var stub_layout_change_calls: c_int;
extern var stub_lock_surface_destroy_calls: c_int;
extern var stub_scene_output_destroy_calls: c_int;
extern var stub_layout_remove_calls: c_int;
extern var stub_layer_v1_destroy_calls: c_int;
extern var stub_state_enabled_calls: c_int;
extern var stub_state_enabled: bool;
extern var stub_state_mode_calls: c_int;
extern var stub_state_mode: [*c]c.struct_wlr_output_mode;
extern var stub_state_custom_calls: c_int;
extern var stub_state_custom_w: i32;
extern var stub_state_custom_h: i32;
extern var stub_state_custom_refresh: i32;
extern var stub_commit_result: bool;
extern var stub_commit_calls: c_int;
extern var stub_finish_calls: c_int;
extern var stub_unref_calls: c_int;
extern var stub_schedule_frame_calls: c_int;
extern var stub_timer_update_calls: c_int;
extern var stub_timer_delay: c_int;
extern var stub_timer_remove_calls: c_int;
extern var stub_is_wl: bool;
extern var stub_is_headless: bool;
extern var stub_wl_output_calls: c_int;
extern var stub_headless_output_calls: c_int;
extern var stub_toggle_overview_calls: c_int;
extern var stub_acwm_commit_calls: c_int;
extern var stub_acwm_commit_result: bool;
extern var stub_new_renderer: [*c]c.struct_wlr_renderer;
extern var stub_new_allocator: Allocator;
extern var stub_fx_create_calls: c_int;
extern var stub_alloc_create_calls: c_int;
extern var stub_alloc_destroy_calls: c_int;
extern var stub_renderer_destroy_calls: c_int;
extern var stub_compositor_renderer_calls: c_int;
extern var stub_output_init_render_calls: c_int;
extern var stub_idle_callback: ?*const fn (?*anyopaque) callconv(.c) void;
extern var stub_add_idle_calls: c_int;

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

fn resetLifecycleWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    listInit(&c.server.clients);
    listInit(&c.server.monitors);
    stub_list_insert_calls = 0;
    stub_list_remove_calls = 0;
    stub_bar_destroy_calls = 0;
    stub_workspace_cleanup_calls = 0;
    stub_dwindle_cleanup_calls = 0;
    stub_scroller_cleanup_calls = 0;
    stub_ext_leave_calls = 0;
    stub_ext_destroy_calls = 0;
    stub_ft_leave_calls = 0;
    stub_ft_destroy_calls = 0;
    stub_set_group_calls = 0;
    stub_last_group_mon = null;
    stub_oldmonname_calls = 0;
    stub_focus_calls = 0;
    stub_focus_client = null;
    stub_focus_lift = -1;
    stub_top_client = null;
    stub_printstatus_calls = 0;
    stub_selected_calls = 0;
    stub_selected_value = null;
    stub_layout_change_calls = 0;
    stub_lock_surface_destroy_calls = 0;
    stub_scene_output_destroy_calls = 0;
    stub_layout_remove_calls = 0;
    stub_layer_v1_destroy_calls = 0;
    stub_state_enabled_calls = 0;
    stub_state_enabled = false;
    stub_state_mode_calls = 0;
    stub_state_mode = null;
    stub_state_custom_calls = 0;
    stub_state_custom_w = 0;
    stub_state_custom_h = 0;
    stub_state_custom_refresh = 0;
    stub_commit_result = true;
    stub_commit_calls = 0;
    stub_finish_calls = 0;
    stub_unref_calls = 0;
    stub_schedule_frame_calls = 0;
    stub_timer_update_calls = 0;
    stub_timer_delay = -1;
    stub_timer_remove_calls = 0;
    stub_is_wl = false;
    stub_is_headless = false;
    stub_wl_output_calls = 0;
    stub_headless_output_calls = 0;
    stub_toggle_overview_calls = 0;
    stub_acwm_commit_calls = 0;
    stub_acwm_commit_result = true;
    stub_new_renderer = null;
    stub_new_allocator = null;
    stub_fx_create_calls = 0;
    stub_alloc_create_calls = 0;
    stub_alloc_destroy_calls = 0;
    stub_renderer_destroy_calls = 0;
    stub_compositor_renderer_calls = 0;
    stub_output_init_render_calls = 0;
    stub_idle_callback = null;
    stub_add_idle_calls = 0;
}

fn baseMonitor(m: *Monitor, out: *c.struct_wlr_output) void {
    m.* = std.mem.zeroes(Monitor);
    out.* = std.mem.zeroes(c.struct_wlr_output);
    m.wlr_output = out;
    out.data = m;
    out.enabled = true;
    var i: usize = 0;
    while (i < 4) : (i += 1)
        listInit(&m.layers[i]);
}

test "output destroy tears down layers, protocols and state" {
    resetLifecycleWorld();
    const m: *Monitor = @ptrCast(@alignCast(c.ecalloc(1, @sizeOf(Monitor)) orelse unreachable));
    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    baseMonitor(m, &out);
    out.data = m;
    var scene_out: c.struct_wlr_scene_output = std.mem.zeroes(c.struct_wlr_scene_output);
    scene_out.output = &out;
    m.scene_output = &scene_out;
    m.ext_group = @ptrFromInt(0x1000);
    m.pertag = @ptrCast(@alignCast(c.ecalloc(1, @sizeOf(c.Pertag)) orelse unreachable));
    listInsert(&c.server.monitors, &m.link);

    var ls: c.struct_wlr_layer_surface_v1 = std.mem.zeroes(c.struct_wlr_layer_surface_v1);
    const l: *LayerSurface = @ptrCast(@alignCast(c.ecalloc(1, @sizeOf(LayerSurface)) orelse unreachable));
    l.layer_surface = &ls;
    listInsert(&m.layers[0], &l.link);

    var blur: c.struct_wlr_scene_optimized_blur = std.mem.zeroes(c.struct_wlr_scene_optimized_blur);
    var dim: c.struct_wlr_scene_rect = std.mem.zeroes(c.struct_wlr_scene_rect);
    m.blur = &blur;
    m.special_dim_rect = &dim;
    m.skip_frame_timeout = @ptrFromInt(0x2000);
    m.lock_surface = @ptrFromInt(0x3000);
    m.icc_transform = @ptrFromInt(0x4000);

    handle_output_destroy(&m.destroy, null);
    try testing.expectEqual(@as(c_int, 1), stub_bar_destroy_calls);
    try testing.expectEqual(@as(c_int, 1), stub_layer_v1_destroy_calls);
    try testing.expectEqual(@as(c_int, 1), stub_ext_leave_calls);
    try testing.expectEqual(@as(c_int, 1), stub_ext_destroy_calls);
    try testing.expectEqual(@as(c_int, 1), stub_workspace_cleanup_calls);
    try testing.expectEqual(@as(c_int, 1), stub_lock_surface_destroy_calls);
    try testing.expectEqual(@as(c_int, 1), stub_scene_output_destroy_calls);
    try testing.expectEqual(@as(c_int, 1), stub_layout_remove_calls);
    try testing.expectEqual(@as(c_int, 1), stub_timer_update_calls);
    try testing.expectEqual(@as(c_int, 0), stub_timer_delay);
    try testing.expectEqual(@as(c_int, 1), stub_timer_remove_calls);
    try testing.expectEqual(@as(c_int, 1), stub_dwindle_cleanup_calls);
    try testing.expectEqual(@as(c_int, 1), stub_scroller_cleanup_calls);
    try testing.expectEqual(@as(c_int, 1), stub_unref_calls);
    try testing.expectEqual(@as(c_int, 1), stub_finish_calls);
    try testing.expectEqual(@as(c_int, 4), stub_list_remove_calls);
    try testing.expectEqual(@as(c_int, 1), stub_selected_calls);
    try testing.expect(stub_selected_value == null);
}

test "monitor close moves clients and picks the next enabled output" {
    resetLifecycleWorld();
    var p: c.Pertag = std.mem.zeroes(c.Pertag);
    var a: Monitor = undefined;
    var b: Monitor = undefined;
    var c_mon: Monitor = undefined;
    var oa: c.struct_wlr_output = undefined;
    var ob: c.struct_wlr_output = undefined;
    var oc: c.struct_wlr_output = undefined;
    baseMonitor(&a, &oa);
    baseMonitor(&b, &ob);
    baseMonitor(&c_mon, &oc);
    listInsert(&c.server.monitors, &a.link);
    listInsert(&c.server.monitors, &b.link);
    listInsert(&c.server.monitors, &c_mon.link);
    a.wlr_output.*.enabled = false;
    b.wlr_output.*.enabled = false;
    c_mon.wlr_output.*.enabled = true;
    b.pertag = &p;
    b.isoverview = 1;
    c.server.selected_monitor = &b;
    c.server.gesture_drive_mon = &b;
    c.server.gesture_drive_active = true;

    var cl1: c.Client = std.mem.zeroes(c.Client);
    var cl2: c.Client = std.mem.zeroes(c.Client);
    cl1.mon = &b;
    cl1.foreign_toplevel = @ptrFromInt(0x5000);
    cl2.mon = &b;
    cl2.oldmonname[0] = 'x';
    listInsert(&c.server.clients, &cl1.link);
    listInsert(&c.server.clients, &cl2.link);
    stub_top_client = &cl1;

    monitor_close(&b);
    try testing.expectEqual(@as(c_int, 1), stub_toggle_overview_calls);
    try testing.expectEqual(@as(c_int, 1), stub_selected_calls);
    try testing.expect(stub_selected_value == &c_mon);
    try testing.expect(c.server.selected_monitor == &c_mon);
    try testing.expectEqual(@as(c_int, 2), stub_set_group_calls);
    try testing.expect(stub_last_group_mon == &c_mon);
    try testing.expectEqual(@as(c_int, 1), stub_oldmonname_calls);
    try testing.expectEqual(@as(c_int, 1), stub_focus_calls);
    try testing.expect(stub_focus_client == &cl1);
    try testing.expectEqual(@as(i32, 1), stub_focus_lift);
    try testing.expectEqual(@as(c_int, 1), stub_printstatus_calls);
    try testing.expect(!c.server.gesture_drive_active);
    try testing.expect(c.server.gesture_drive_mon == null);

    // no monitors left and no selected monitor: drop foreign toplevels
    resetLifecycleWorld();
    var lone: Monitor = std.mem.zeroes(Monitor);
    var lone_out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    baseMonitor(&lone, &lone_out);
    c.server.selected_monitor = &lone;
    var cl3: c.Client = std.mem.zeroes(c.Client);
    cl3.mon = &lone;
    cl3.foreign_toplevel = @ptrFromInt(0x6000);
    listInsert(&c.server.clients, &cl3.link);
    monitor_close(&lone);
    try testing.expectEqual(@as(c_int, 1), stub_ft_leave_calls);
    try testing.expectEqual(@as(c_int, 1), stub_ft_destroy_calls);
    try testing.expect(cl3.foreign_toplevel == null);
    try testing.expectEqual(@as(c_int, 1), stub_set_group_calls);
    try testing.expect(stub_last_group_mon == null);
}

test "output request state applies modes or commits directly" {
    resetLifecycleWorld();
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    baseMonitor(&m, &out);
    var event: c.struct_wlr_output_event_request_state = std.mem.zeroes(c.struct_wlr_output_event_request_state);
    var state: c.struct_wlr_output_state = std.mem.zeroes(c.struct_wlr_output_state);
    var mode: c.struct_wlr_output_mode = std.mem.zeroes(c.struct_wlr_output_mode);
    event.output = &out;
    event.state = &state;

    state.committed = @intCast(c.WLR_OUTPUT_STATE_MODE);
    state.mode_type = @intCast(c.WLR_OUTPUT_STATE_MODE_FIXED);
    state.mode = &mode;
    handle_output_request_state(&m.request_state, &event);
    try testing.expectEqual(@as(c_int, 1), stub_state_mode_calls);
    try testing.expect(stub_state_mode == &mode);
    try testing.expectEqual(@as(c_int, 1), stub_layout_change_calls);
    try testing.expectEqual(@as(c_int, 1), stub_schedule_frame_calls);
    try testing.expectEqual(@as(c_int, 0), stub_commit_calls);

    state.mode_type = @intCast(c.WLR_OUTPUT_STATE_MODE_CUSTOM);
    state.custom_mode.width = 800;
    state.custom_mode.height = 600;
    state.custom_mode.refresh = 60000;
    handle_output_request_state(&m.request_state, &event);
    try testing.expectEqual(@as(c_int, 1), stub_state_custom_calls);
    try testing.expectEqual(@as(i32, 800), stub_state_custom_w);
    try testing.expectEqual(@as(i32, 60000), stub_state_custom_refresh);

    state.committed = @intCast(c.WLR_OUTPUT_STATE_SCALE);
    handle_output_request_state(&m.request_state, &event);
    try testing.expectEqual(@as(c_int, 1), stub_commit_calls);
}

test "create output handles wayland and headless backends once" {
    resetLifecycleWorld();
    var done = false;
    stub_is_wl = true;
    create_output(null, &done);
    try testing.expect(done);
    try testing.expectEqual(@as(c_int, 1), stub_wl_output_calls);
    try testing.expectEqual(@as(c_int, 1), stub_layout_change_calls);

    done = true;
    create_output(null, &done);
    try testing.expectEqual(@as(c_int, 1), stub_wl_output_calls);
    try testing.expectEqual(@as(c_int, 1), stub_layout_change_calls);

    done = false;
    stub_is_wl = false;
    stub_is_headless = true;
    create_output(null, &done);
    try testing.expect(done);
    try testing.expectEqual(@as(c_int, 1), stub_headless_output_calls);
    try testing.expectEqual(@as(c_int, 2), stub_layout_change_calls);
}

test "power manager updates pending state and sleep flag" {
    resetLifecycleWorld();
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    baseMonitor(&m, &out);
    var event: c.struct_wlr_output_power_v1_set_mode_event = std.mem.zeroes(c.struct_wlr_output_power_v1_set_mode_event);
    event.output = &out;

    event.mode = @intCast(1);
    handle_output_power_manager_set_mode(null, &event);
    try testing.expect(stub_state_enabled);
    try testing.expectEqual(@as(c_int, 1), stub_acwm_commit_calls);
    try testing.expectEqual(@as(i32, 0), m.only_sleep);
    try testing.expectEqual(@as(c_int, 1), stub_layout_change_calls);

    event.mode = @intCast(0);
    handle_output_power_manager_set_mode(null, &event);
    try testing.expect(!stub_state_enabled);
    try testing.expectEqual(@as(i32, 1), m.only_sleep);
    try testing.expectEqual(@as(c_int, 2), stub_layout_change_calls);
}

test "skip-frame timer resets counts and client serials" {
    resetLifecycleWorld();
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    baseMonitor(&m, &out);
    m.skip_frame_timeout = @ptrFromInt(0x1000);
    m.skiping_frame = true;
    m.resizing_count_pending = 4;
    m.resizing_count_current = 2;
    monitor_stop_skip_frame_timer(&m);
    try testing.expectEqual(@as(c_int, 0), stub_timer_delay);
    try testing.expect(!m.skiping_frame);
    try testing.expectEqual(@as(u32, 0), m.resizing_count_pending);

    var cl1: c.Client = std.mem.zeroes(c.Client);
    var cl2: c.Client = std.mem.zeroes(c.Client);
    cl1.configure_serial = 9;
    cl2.configure_serial = 7;
    listInsert(&c.server.clients, &cl1.link);
    listInsert(&c.server.clients, &cl2.link);
    m.skiping_frame = true;
    try testing.expectEqual(@as(c_int, 1), monitor_skip_frame_timeout_callback(&m));
    try testing.expectEqual(@as(u32, 0), cl1.configure_serial);
    try testing.expectEqual(@as(u32, 0), cl2.configure_serial);
    try testing.expectEqual(@as(c_int, 1), stub_schedule_frame_calls);

    m.skiping_frame = false;
    m.resizing_count_pending = 3;
    monitor_check_skip_frame_timeout(&m);
    try testing.expect(m.skiping_frame);
    try testing.expectEqual(@as(u32, 3), m.resizing_count_current);
    try testing.expectEqual(@as(c_int, 100), stub_timer_delay);
    const calls = stub_timer_update_calls;
    monitor_check_skip_frame_timeout(&m);
    try testing.expectEqual(calls, stub_timer_update_calls);
}

test "renderer loss schedules one recreation and rebuilds outputs" {
    resetLifecycleWorld();
    var old_renderer: c.struct_wlr_renderer = std.mem.zeroes(c.struct_wlr_renderer);
    var new_renderer: c.struct_wlr_renderer = std.mem.zeroes(c.struct_wlr_renderer);
    const old_alloc: Allocator = @ptrFromInt(0x4000);
    const new_alloc: Allocator = @ptrFromInt(0x5000);
    c.server.renderer = &old_renderer;
    c.server.allocator = old_alloc;
    c.server.backend = @ptrFromInt(0x1000);
    c.server.compositor = @ptrFromInt(0x2000);
    c.server.event_loop = @ptrFromInt(0x3000);
    c.server.gpu_reset_listener.link.next = &c.server.gpu_reset_listener.link;
    c.server.gpu_reset_listener.link.prev = &c.server.gpu_reset_listener.link;
    stub_new_renderer = &new_renderer;
    stub_new_allocator = new_alloc;

    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    baseMonitor(&m, &out);
    listInsert(&c.server.monitors, &m.link);

    handle_renderer_lost(null, null);
    try testing.expectEqual(@as(c_int, 1), stub_add_idle_calls);
    try testing.expect(c.server.recreate_renderer_source != null);
    handle_renderer_lost(null, null);
    try testing.expectEqual(@as(c_int, 1), stub_add_idle_calls);

    stub_idle_callback.?(null);
    try testing.expect(c.server.renderer == &new_renderer);
    try testing.expect(c.server.allocator == new_alloc);
    try testing.expectEqual(@as(c_int, 1), stub_fx_create_calls);
    try testing.expectEqual(@as(c_int, 1), stub_alloc_create_calls);
    try testing.expectEqual(@as(c_int, 1), stub_compositor_renderer_calls);
    try testing.expectEqual(@as(c_int, 1), stub_output_init_render_calls);
    try testing.expectEqual(@as(c_int, 1), stub_alloc_destroy_calls);
    try testing.expectEqual(@as(c_int, 1), stub_renderer_destroy_calls);
    try testing.expect(c.server.recreate_renderer_source == null);
}
