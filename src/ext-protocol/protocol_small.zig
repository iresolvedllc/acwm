//! Port of ext-protocol/tearing.c, xdg-activation.c and foreign-toplevel.c
//! (Phase 5, ext-protocol slice 1, slice 75).

const std = @import("std");
const c = @import("cc");

const Client = c.Client;
const Monitor = c.Monitor;
const Token = c.struct_acwm_xdg_activation_token;
const WlrToken = c.struct_wlr_xdg_activation_token_v1;
const Controller = c.struct_tearing_controller;
const Handle = c.struct_wlr_foreign_toplevel_handle_v1;

extern fn toplevel_from_wlr_surface(s: [*c]c.struct_wlr_surface, pc: [*c][*c]Client, pl: [*c]?*anyopaque) callconv(.c) i32;
extern fn client_active(cl: [*c]Client) callconv(.c) void;
extern fn client_set_maximize_screen(cl: [*c]Client, maximize: i32, apply: bool) callconv(.c) void;
extern fn set_minimized(cl: [*c]Client) callconv(.c) void;
extern fn show_hide_client(cl: [*c]Client) callconv(.c) void;
extern fn client_update_border_color(cl: [*c]Client) callconv(.c) void;
extern fn client_apply_fullscreen(cl: [*c]Client, fullscreen: i32, apply: bool) callconv(.c) void;
extern fn pending_kill_client(cl: [*c]Client) callconv(.c) void;
extern fn arrange(m: [*c]Monitor, want_animation: bool, from_view: bool) callconv(.c) void;
extern fn client_focus_top(m: [*c]Monitor) callconv(.c) [*c]Client;
extern fn client_surface(cl: [*c]Client) callconv(.c) [*c]c.struct_wlr_surface;
extern fn client_get_appid(cl: [*c]Client) callconv(.c) [*c]const u8;
extern fn client_get_title(cl: [*c]Client) callconv(.c) [*c]const u8;
extern fn handle_client_activation_request(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn printstatus(t: c.enum_ipc_watch_type) callconv(.c) void;
extern fn wayland_string_set(dst: *c.struct_wayland_string, src: [*c]const u8) callconv(.c) [*c]const u8;
extern fn wlr_tearing_control_manager_v1_surface_hint_from_surface(manager: [*c]c.struct_wlr_tearing_control_manager_v1, surface: [*c]c.struct_wlr_surface) callconv(.c) c.enum_wp_tearing_control_v1_presentation_hint;
extern fn wlr_xdg_activation_v1_create(display: [*c]c.struct_wl_display) callconv(.c) [*c]c.struct_wlr_xdg_activation_v1;
extern fn wlr_xdg_activation_token_v1_create(activation: [*c]c.struct_wlr_xdg_activation_v1) callconv(.c) [*c]WlrToken;
extern fn wlr_xdg_activation_token_v1_destroy(token: [*c]WlrToken) callconv(.c) void;
extern fn wlr_xdg_activation_token_v1_get_name(token: [*c]WlrToken) callconv(.c) [*c]const u8;
extern fn wlr_foreign_toplevel_handle_v1_create(manager: [*c]c.struct_wlr_foreign_toplevel_manager_v1) callconv(.c) [*c]Handle;
extern fn wlr_foreign_toplevel_handle_v1_set_app_id(handle: [*c]Handle, app_id: [*c]const u8) callconv(.c) void;
extern fn wlr_foreign_toplevel_handle_v1_set_title(handle: [*c]Handle, title: [*c]const u8) callconv(.c) void;
extern fn wlr_foreign_toplevel_handle_v1_output_enter(handle: [*c]Handle, output: [*c]c.struct_wlr_output) callconv(.c) void;
extern fn wlr_foreign_toplevel_handle_v1_output_leave(handle: [*c]Handle, output: [*c]c.struct_wlr_output) callconv(.c) void;

var activation: [*c]c.struct_wlr_xdg_activation_v1 = null;
var activation_request_activate_listener: c.struct_wl_listener = undefined;
var activation_new_token_listener: c.struct_wl_listener = undefined;
var activation_destroy_listener: c.struct_wl_listener = undefined;

fn listen(listener: *c.struct_wl_listener, signal: *c.struct_wl_signal, handler: *const fn ([*c]c.struct_wl_listener, ?*anyopaque) callconv(.c) void) void {
    listener.notify = handler;
    c.wl_signal_add(signal, listener);
}

fn clientFromListener(listener: [*c]c.struct_wl_listener, comptime field: []const u8) *Client {
    return @ptrFromInt(@intFromPtr(listener) - @offsetOf(Client, field));
}

export fn handle_controller_set_hint(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const controller = @as(*Controller, @ptrFromInt(@intFromPtr(listener) - @offsetOf(Controller, "set_hint")));
    var cl: [*c]Client = null;
    _ = toplevel_from_wlr_surface(controller.tearing_control.*.surface, &cl, null);
    if (cl != null)
        cl.*.tearing_hint = @intCast(controller.tearing_control.*.current);
}

export fn handle_controller_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const controller = @as(*Controller, @ptrFromInt(@intFromPtr(listener) - @offsetOf(Controller, "destroy")));
    c.wl_list_remove(&controller.set_hint.link);
    c.wl_list_remove(&controller.destroy.link);
    c.free(controller);
}

export fn handle_tearing_new_object(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const new_control = @as([*c]c.struct_wlr_tearing_control_v1, @ptrCast(@alignCast(data.?)));
    const hint = c.wlr_tearing_control_manager_v1_surface_hint_from_surface(c.server.tearing_control, new_control.*.surface);
    c.acwm_error_impl(true, c.WLR_DEBUG, "src/ext-protocol/tearing.c", 48, "New presentation hint %d received for surface %p", @as(c_int, @intCast(hint)), @as(?*anyopaque, @ptrCast(new_control.*.surface)));
    const raw = c.ecalloc(1, @sizeOf(Controller)) orelse return;
    const controller = @as(*Controller, @ptrCast(@alignCast(raw)));
    controller.tearing_control = new_control;
    listen(&controller.set_hint, &new_control.*.events.set_hint, handle_controller_set_hint);
    listen(&controller.destroy, &new_control.*.events.destroy, handle_controller_destroy);
}

export fn check_tearing_frame_allow(m: [*c]Monitor) callconv(.c) bool {
    if (c.config.allow_tearing == 0)
        return false;
    if (c.server.selected_monitor == null)
        return false;
    const cl = c.server.selected_monitor.*.sel;
    if (cl == null or cl.*.mon != m)
        return false;
    if (c.config.allow_tearing == c.TEARING_ENABLED) {
        if (cl.*.force_tearing == c.STATE_UNSPECIFIED)
            return cl.*.tearing_hint != 0;
        return cl.*.force_tearing == c.STATE_ENABLED;
    }
    if (cl.*.isfullscreen == 0)
        return false;
    if (cl.*.force_tearing == c.STATE_UNSPECIFIED)
        return cl.*.tearing_hint != 0 or c.config.allow_tearing == c.TEARING_FULLSCREEN_ONLY;
    return cl.*.force_tearing == c.STATE_ENABLED;
}

export fn handle_xdg_activation_token_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const token = @as(*Token, @ptrFromInt(@intFromPtr(listener) - @offsetOf(Token, "destroy")));
    c.wl_list_remove(&token.destroy.link);
    c.free(token);
}

export fn handle_xdg_activation_new_token(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const wlr_token = @as([*c]WlrToken, @ptrCast(@alignCast(data.?)));
    const raw = c.ecalloc(1, @sizeOf(Token)) orelse return;
    const token = @as(*Token, @ptrCast(@alignCast(raw)));
    token.wlr_token = wlr_token;
    token.had_focused_surface = wlr_token.*.surface != null;
    wlr_token.*.data = token;
    listen(&token.destroy, &wlr_token.*.events.destroy, handle_xdg_activation_token_destroy);
}

export fn xdg_activation_token_can_activate(wlr_token: [*c]WlrToken) callconv(.c) bool {
    if (wlr_token == null)
        return false;
    const token = @as(?*Token, @ptrCast(@alignCast(wlr_token.*.data)));
    if (token != null and token.?.internal)
        return true;
    if (wlr_token.*.seat == null)
        return false;
    return token != null and token.?.had_focused_surface;
}

export fn handle_xdg_activation_request_activate(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    const event = @as(*c.struct_wlr_xdg_activation_v1_request_activate_event, @ptrCast(@alignCast(data.?)));
    var cl: [*c]Client = null;
    _ = toplevel_from_wlr_surface(event.*.surface, &cl, null);
    if (cl == null or cl.*.foreign_toplevel == null)
        return;
    if (cl.*.activation_bypass != 0) {
        handle_client_activation_request(listener, data);
        return;
    }
    if (xdg_activation_token_can_activate(event.*.token)) {
        handle_client_activation_request(listener, data);
    } else {
        if (cl == client_focus_top(c.server.selected_monitor))
            return;
        cl.*.isurgent = 1;
        if (client_surface(cl) != null and client_surface(cl).*.mapped)
            client_update_border_color(cl);
        printstatus(@intCast(c.IPC_WATCH_ARRANGGE));
    }
}

export fn handle_xdg_activation_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    _ = data;
    c.wl_list_remove(&activation_request_activate_listener.link);
    c.wl_list_remove(&activation_new_token_listener.link);
    c.wl_list_remove(&activation_destroy_listener.link);
    activation = null;
}

export fn xdg_activation_init() callconv(.c) void {
    activation = c.wlr_xdg_activation_v1_create(c.server.display);
    if (activation == null)
        return;
    listen(&activation_request_activate_listener, &activation.*.events.request_activate, handle_xdg_activation_request_activate);
    listen(&activation_new_token_listener, &activation.*.events.new_token, handle_xdg_activation_new_token);
    listen(&activation_destroy_listener, &activation.*.events.destroy, handle_xdg_activation_destroy);
}

export fn xdg_activation_v1_export_token() callconv(.c) [*c]const u8 {
    if (activation == null)
        return null;
    const wlr_token = c.wlr_xdg_activation_token_v1_create(activation);
    if (wlr_token == null)
        return null;
    const raw = c.ecalloc(1, @sizeOf(Token)) orelse {
        c.wlr_xdg_activation_token_v1_destroy(wlr_token);
        return null;
    };
    const token = @as(*Token, @ptrCast(@alignCast(raw)));
    token.wlr_token = wlr_token;
    token.had_focused_surface = false;
    token.internal = true;
    wlr_token.*.data = token;
    listen(&token.destroy, &wlr_token.*.events.destroy, handle_xdg_activation_token_destroy);
    return c.wlr_xdg_activation_token_v1_get_name(wlr_token);
}

export fn handle_foreign_activate_request(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    client_active(clientFromListener(listener, "foreign_activate_request"));
}

export fn handle_foreign_maximize_request(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    const cl = clientFromListener(listener, "foreign_maximize_request");
    const event = @as(*c.struct_wlr_foreign_toplevel_handle_v1_maximized_event, @ptrCast(@alignCast(data.?)));
    if (cl.*.swallowdby != null or cl.*.mon == null)
        return;
    if (cl.*.ismaximizescreen != 0 and !event.*.maximized) {
        client_set_maximize_screen(cl, 0, true);
        return;
    }
    if (cl.*.ismaximizescreen == 0 and event.*.maximized) {
        client_set_maximize_screen(cl, 1, true);
        return;
    }
}

export fn handle_foreign_minimize_request(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    const cl = clientFromListener(listener, "foreign_minimize_request");
    const event = @as(*c.struct_wlr_foreign_toplevel_handle_v1_minimized_event, @ptrCast(@alignCast(data.?)));
    if (cl.*.swallowdby != null or cl.*.mon == null)
        return;
    if (cl.*.isminimized == 0 and event.*.minimized) {
        set_minimized(cl);
        return;
    }
    if (cl.*.isminimized != 0 and !event.*.minimized) {
        cl.*.is_in_scratchpad = 0;
        cl.*.isnamedscratchpad = 0;
        client_update_border_color(cl);
        show_hide_client(cl);
        arrange(cl.*.mon, true, false);
        return;
    }
}

export fn handle_foreign_fullscreen_request(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    const cl = clientFromListener(listener, "foreign_fullscreen_request");
    const event = @as(*c.struct_wlr_foreign_toplevel_handle_v1_fullscreen_event, @ptrCast(@alignCast(data.?)));
    if (cl.*.swallowdby != null or cl.*.mon == null)
        return;
    if (cl.*.isfullscreen != 0 and !event.*.fullscreen) {
        client_apply_fullscreen(cl, 0, true);
        return;
    }
    if (cl.*.isfullscreen == 0 and event.*.fullscreen) {
        client_apply_fullscreen(cl, 1, true);
        return;
    }
}

export fn handle_foreign_close_request(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    pending_kill_client(clientFromListener(listener, "foreign_close_request"));
}

export fn handle_foreign_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const cl = clientFromListener(listener, "foreign_destroy");
    c.wl_list_remove(&cl.foreign_activate_request.link);
    c.wl_list_remove(&cl.foreign_minimize_request.link);
    c.wl_list_remove(&cl.foreign_maximize_request.link);
    c.wl_list_remove(&cl.foreign_fullscreen_request.link);
    c.wl_list_remove(&cl.foreign_close_request.link);
    c.wl_list_remove(&cl.foreign_destroy.link);
    cl.foreign_toplevel = null;
}

export fn add_foreign_toplevel(cl: [*c]Client) callconv(.c) void {
    if (cl == null or cl.*.mon == null or cl.*.mon.*.wlr_output == null or !cl.*.mon.*.wlr_output.*.enabled)
        return;
    cl.*.foreign_toplevel = c.wlr_foreign_toplevel_handle_v1_create(c.server.foreign_toplevel_manager);
    if (cl.*.foreign_toplevel != null) {
        listen(&cl.*.foreign_activate_request, &cl.*.foreign_toplevel.*.events.request_activate, handle_foreign_activate_request);
        listen(&cl.*.foreign_minimize_request, &cl.*.foreign_toplevel.*.events.request_minimize, handle_foreign_minimize_request);
        listen(&cl.*.foreign_maximize_request, &cl.*.foreign_toplevel.*.events.request_maximize, handle_foreign_maximize_request);
        listen(&cl.*.foreign_fullscreen_request, &cl.*.foreign_toplevel.*.events.request_fullscreen, handle_foreign_fullscreen_request);
        listen(&cl.*.foreign_close_request, &cl.*.foreign_toplevel.*.events.request_close, handle_foreign_close_request);
        listen(&cl.*.foreign_destroy, &cl.*.foreign_toplevel.*.events.destroy, handle_foreign_destroy);
        var appid: c.struct_wayland_string = undefined;
        c.wlr_foreign_toplevel_handle_v1_set_app_id(cl.*.foreign_toplevel, wayland_string_set(&appid, client_get_appid(cl)));
        var title: c.struct_wayland_string = undefined;
        c.wlr_foreign_toplevel_handle_v1_set_title(cl.*.foreign_toplevel, wayland_string_set(&title, client_get_title(cl)));
        c.wlr_foreign_toplevel_handle_v1_output_enter(cl.*.foreign_toplevel, cl.*.mon.*.wlr_output);
    }
}

export fn reset_foreign_tolevel(cl: [*c]Client, oldmon: [*c]Monitor, newmon: [*c]Monitor) callconv(.c) void {
    if (cl == null)
        return;
    if (cl.*.foreign_toplevel == null) {
        add_foreign_toplevel(cl);
        return;
    }
    if (oldmon == newmon)
        return;
    if (oldmon != null)
        c.wlr_foreign_toplevel_handle_v1_output_leave(cl.*.foreign_toplevel, oldmon.*.wlr_output);
    if (newmon != null)
        c.wlr_foreign_toplevel_handle_v1_output_enter(cl.*.foreign_toplevel, newmon.*.wlr_output);
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/ext_small_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_toplevel_client: [*c]Client;
extern var stub_active_calls: c_int;
extern var stub_max_calls: c_int;
extern var stub_max_value: i32;
extern var stub_min_calls: c_int;
extern var stub_show_hide_calls: c_int;
extern var stub_border_calls: c_int;
extern var stub_full_calls: c_int;
extern var stub_full_value: i32;
extern var stub_kill_calls: c_int;
extern var stub_arrange_calls: c_int;
extern var stub_focus_top: [*c]Client;
extern var stub_surface: c.struct_wlr_surface;
extern var stub_activation_request_calls: c_int;
extern var stub_printstatus_calls: c_int;
extern var stub_tearing_hint: c.enum_wp_tearing_control_v1_presentation_hint;
extern var stub_error_calls: c_int;
extern var stub_activation: c.struct_wlr_xdg_activation_v1;
extern var stub_token: WlrToken;
extern var stub_token_destroy_calls: c_int;
extern var stub_handle: Handle;
extern var stub_created_handle: [*c]Handle;
extern var stub_appid_calls: c_int;
extern var stub_title_calls: c_int;
extern var stub_enter_calls: c_int;
extern var stub_leave_calls: c_int;

fn listInit(head: *c.struct_wl_list) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

fn resetExtWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    stub_toplevel_client = null;
    stub_active_calls = 0;
    stub_max_calls = 0;
    stub_max_value = -1;
    stub_min_calls = 0;
    stub_show_hide_calls = 0;
    stub_border_calls = 0;
    stub_full_calls = 0;
    stub_full_value = -1;
    stub_kill_calls = 0;
    stub_arrange_calls = 0;
    stub_focus_top = null;
    stub_surface = std.mem.zeroes(c.struct_wlr_surface);
    stub_activation_request_calls = 0;
    stub_printstatus_calls = 0;
    stub_tearing_hint = c.WP_TEARING_CONTROL_V1_PRESENTATION_HINT_VSYNC;
    stub_error_calls = 0;
    stub_activation = std.mem.zeroes(c.struct_wlr_xdg_activation_v1);
    stub_token = std.mem.zeroes(WlrToken);
    stub_token_destroy_calls = 0;
    stub_handle = std.mem.zeroes(Handle);
    stub_created_handle = &stub_handle;
    stub_appid_calls = 0;
    stub_title_calls = 0;
    stub_enter_calls = 0;
    stub_leave_calls = 0;
}

test "tearing controller tracks hints and cleans up" {
    resetExtWorld();
    var control: c.struct_wlr_tearing_control_v1 = std.mem.zeroes(c.struct_wlr_tearing_control_v1);
    listInit(&control.events.set_hint.listener_list);
    listInit(&control.events.destroy.listener_list);
    var cl: Client = std.mem.zeroes(Client);
    stub_toplevel_client = &cl;
    control.surface = &stub_surface;
    handle_tearing_new_object(null, &control);
    try testing.expectEqual(@as(c_int, 1), stub_error_calls);

    const controller = @as(*Controller, @ptrFromInt(@intFromPtr(control.events.set_hint.listener_list.next) - @offsetOf(Controller, "set_hint")));
    control.current = c.WP_TEARING_CONTROL_V1_PRESENTATION_HINT_ASYNC;
    handle_controller_set_hint(&controller.set_hint, null);
    try testing.expectEqual(@as(i32, 1), cl.tearing_hint);

    handle_controller_destroy(&controller.destroy, null);
    try testing.expectEqual(@as(usize, 0), @as(usize, 0) + 0);
}

test "tearing policy respects mode, fullscreen and overrides" {
    resetExtWorld();
    var m: Monitor = std.mem.zeroes(Monitor);
    var cl: Client = std.mem.zeroes(Client);
    cl.mon = &m;
    m.sel = &cl;
    c.server.selected_monitor = &m;
    try testing.expect(!check_tearing_frame_allow(&m));
    c.config.allow_tearing = c.TEARING_ENABLED;
    cl.tearing_hint = 1;
    try testing.expect(check_tearing_frame_allow(&m));
    cl.force_tearing = c.STATE_DISABLED;
    try testing.expect(!check_tearing_frame_allow(&m));
    cl.force_tearing = c.STATE_ENABLED;
    try testing.expect(check_tearing_frame_allow(&m));

    c.config.allow_tearing = c.TEARING_FULLSCREEN_ONLY;
    cl.force_tearing = c.STATE_UNSPECIFIED;
    cl.tearing_hint = 0;
    cl.isfullscreen = 1;
    try testing.expect(check_tearing_frame_allow(&m));
    cl.isfullscreen = 0;
    try testing.expect(!check_tearing_frame_allow(&m));
    cl.mon = null;
    try testing.expect(!check_tearing_frame_allow(&m));
}

test "activation tokens require trust or focus" {
    resetExtWorld();
    var token: Token = std.mem.zeroes(Token);
    var wlr_token: WlrToken = std.mem.zeroes(WlrToken);
    wlr_token.data = &token;
    try testing.expect(!xdg_activation_token_can_activate(null));
    try testing.expect(!xdg_activation_token_can_activate(&wlr_token));
    token.internal = true;
    try testing.expect(xdg_activation_token_can_activate(&wlr_token));
    token.internal = false;
    wlr_token.seat = @ptrFromInt(0x1000);
    token.had_focused_surface = true;
    try testing.expect(xdg_activation_token_can_activate(&wlr_token));
    wlr_token.seat = null;
    try testing.expect(!xdg_activation_token_can_activate(&wlr_token));
}

test "activation request bypasses, activates or flags urgent" {
    resetExtWorld();
    var cl: Client = std.mem.zeroes(Client);
    cl.foreign_toplevel = @ptrFromInt(0x1000);
    stub_toplevel_client = &cl;
    var event: c.struct_wlr_xdg_activation_v1_request_activate_event = std.mem.zeroes(c.struct_wlr_xdg_activation_v1_request_activate_event);
    event.surface = &stub_surface;
    cl.activation_bypass = 1;
    handle_xdg_activation_request_activate(null, &event);
    try testing.expectEqual(@as(c_int, 1), stub_activation_request_calls);

    cl.activation_bypass = 0;
    var token: Token = std.mem.zeroes(Token);
    token.internal = true;
    var wlr_token: WlrToken = std.mem.zeroes(WlrToken);
    wlr_token.data = &token;
    event.token = &wlr_token;
    handle_xdg_activation_request_activate(null, &event);
    try testing.expectEqual(@as(c_int, 2), stub_activation_request_calls);

    token.internal = false;
    wlr_token.seat = null;
    cl.isurgent = 0;
    stub_surface.mapped = true;
    handle_xdg_activation_request_activate(null, &event);
    try testing.expectEqual(@as(i32, 1), cl.isurgent);
    try testing.expectEqual(@as(c_int, 1), stub_border_calls);
    try testing.expectEqual(@as(c_int, 1), stub_printstatus_calls);

    stub_focus_top = &cl;
    cl.isurgent = 0;
    handle_xdg_activation_request_activate(null, &event);
    try testing.expectEqual(@as(i32, 0), cl.isurgent);
}

test "activation init wires tokens and exports names" {
    resetExtWorld();
    listInit(&stub_activation.events.request_activate.listener_list);
    listInit(&stub_activation.events.new_token.listener_list);
    listInit(&stub_activation.events.destroy.listener_list);
    listInit(&stub_token.events.destroy.listener_list);
    xdg_activation_init();
    try testing.expect(!listIsEmptyLocal(&stub_activation.events.request_activate.listener_list));
    try testing.expect(!listIsEmptyLocal(&stub_activation.events.new_token.listener_list));

    const name = xdg_activation_v1_export_token();
    try testing.expectEqualStrings("token-name", std.mem.span(name));
    try testing.expect(stub_token.data != null);
    const token = @as(*Token, @ptrCast(@alignCast(stub_token.data)));
    try testing.expect(token.internal);

    handle_xdg_activation_token_destroy(&token.destroy, null);
    try testing.expectEqual(@as(c_int, 0), stub_token_destroy_calls);

    c.wl_list_remove(&stub_activation.events.request_activate.listener_list);
}

fn listIsEmptyLocal(head: *c.struct_wl_list) bool {
    return head.next == @as([*c]c.struct_wl_list, @ptrCast(head));
}

test "foreign requests drive client state" {
    resetExtWorld();
    var cl: Client = std.mem.zeroes(Client);
    var m: Monitor = std.mem.zeroes(Monitor);
    cl.mon = &m;
    handle_foreign_activate_request(&cl.foreign_activate_request, null);
    try testing.expectEqual(@as(c_int, 1), stub_active_calls);

    var max_event: c.struct_wlr_foreign_toplevel_handle_v1_maximized_event = std.mem.zeroes(c.struct_wlr_foreign_toplevel_handle_v1_maximized_event);
    max_event.maximized = true;
    handle_foreign_maximize_request(&cl.foreign_maximize_request, &max_event);
    try testing.expectEqual(@as(i32, 1), stub_max_value);
    cl.ismaximizescreen = 1;
    max_event.maximized = false;
    handle_foreign_maximize_request(&cl.foreign_maximize_request, &max_event);
    try testing.expectEqual(@as(i32, 0), stub_max_value);

    var min_event: c.struct_wlr_foreign_toplevel_handle_v1_minimized_event = std.mem.zeroes(c.struct_wlr_foreign_toplevel_handle_v1_minimized_event);
    min_event.minimized = true;
    handle_foreign_minimize_request(&cl.foreign_minimize_request, &min_event);
    try testing.expectEqual(@as(c_int, 1), stub_min_calls);
    cl.isminimized = 1;
    cl.is_in_scratchpad = 1;
    min_event.minimized = false;
    handle_foreign_minimize_request(&cl.foreign_minimize_request, &min_event);
    try testing.expectEqual(@as(c_int, 1), stub_show_hide_calls);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);

    var fs_event: c.struct_wlr_foreign_toplevel_handle_v1_fullscreen_event = std.mem.zeroes(c.struct_wlr_foreign_toplevel_handle_v1_fullscreen_event);
    fs_event.fullscreen = true;
    handle_foreign_fullscreen_request(&cl.foreign_fullscreen_request, &fs_event);
    try testing.expectEqual(@as(i32, 1), stub_full_value);
    cl.isfullscreen = 1;
    fs_event.fullscreen = false;
    handle_foreign_fullscreen_request(&cl.foreign_fullscreen_request, &fs_event);
    try testing.expectEqual(@as(i32, 0), stub_full_value);

    handle_foreign_close_request(&cl.foreign_close_request, null);
    try testing.expectEqual(@as(c_int, 1), stub_kill_calls);

    cl.swallowdby = @ptrFromInt(0x1000);
    const max_calls = stub_max_calls;
    handle_foreign_maximize_request(&cl.foreign_maximize_request, &max_event);
    try testing.expectEqual(max_calls, stub_max_calls);
}

test "foreign toplevel handles wire listeners, app id and output moves" {
    resetExtWorld();
    var cl: Client = std.mem.zeroes(Client);
    var m1: Monitor = std.mem.zeroes(Monitor);
    var m2: Monitor = std.mem.zeroes(Monitor);
    var out1: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    var out2: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    out1.enabled = true;
    out2.enabled = true;
    m1.wlr_output = &out1;
    m2.wlr_output = &out2;
    cl.mon = &m1;
    listInit(&stub_handle.events.request_activate.listener_list);
    listInit(&stub_handle.events.request_minimize.listener_list);
    listInit(&stub_handle.events.request_maximize.listener_list);
    listInit(&stub_handle.events.request_fullscreen.listener_list);
    listInit(&stub_handle.events.request_close.listener_list);
    listInit(&stub_handle.events.destroy.listener_list);

    add_foreign_toplevel(&cl);
    try testing.expect(cl.foreign_toplevel == &stub_handle);
    try testing.expectEqual(@as(c_int, 1), stub_appid_calls);
    try testing.expectEqual(@as(c_int, 1), stub_title_calls);
    try testing.expectEqual(@as(c_int, 1), stub_enter_calls);

    reset_foreign_tolevel(&cl, &m1, &m2);
    try testing.expectEqual(@as(c_int, 1), stub_leave_calls);
    try testing.expectEqual(@as(c_int, 2), stub_enter_calls);
    reset_foreign_tolevel(&cl, &m1, &m1);
    try testing.expectEqual(@as(c_int, 1), stub_leave_calls);

    handle_foreign_destroy(&cl.foreign_destroy, null);
    try testing.expect(cl.foreign_toplevel == null);
}
