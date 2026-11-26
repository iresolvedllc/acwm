//! Port of the IPC watch/notification layer from src/ipc/ipc.c
//! (strangler-fig Phase 4, slice 27).
//!
//! Exports (same symbols; C twins #ifndef ACWM_ZIG_IPC_WATCH guarded):
//!   ipc_notify_json_to_fd, ipc_notify_device_event, ipc_remove_watch_client,
//!   ipc_watch_data_handler, ipc_notify_client, ipc_notify_tags,
//!   ipc_notify_all_tags, ipc_notify_monitor,
//!   ipc_notify_last_surface_ws_name, ipc_notify_focusing_client,
//!   ipc_notify_all_monitors, ipc_notify_all_clients, ipc_notify_keymode,
//!   ipc_notify_kb_layout, printstatus, handle_print_status
//!
//! The watch list (`ipc_watch_clients`) and `ipc_device_watch_count` stay
//! owned by ipc.c (handle_watch_command inserts, ipc_cleanup iterates) and
//! are now extern symbols so both sides share them. Payloads are built once
//! per notification and reused for every matching watcher; a failed send
//! removes that watcher, exactly like C. printstatus emits the server
//! print-status signal with a manual wl_list walk (wl_signal_emit is a
//! header inline).
//!
//! Tests live at the bottom and need tests/ipc_watch_stub.c (socketpair
//! based round trips against real cJSON).

const std = @import("std");
const c = @import("cc");

const WLR_ERROR: c_uint = @intCast(c.WLR_ERROR);

extern fn acwm_error_impl(
    log: bool,
    verbosity: c_uint,
    file: [*:0]const u8,
    line: c_int,
    fmt: [*:0]const u8,
    ...) callconv(.c) void;
extern fn build_client_json(cl: *c.Client) callconv(.c) ?*c.struct_cJSON;
extern fn build_monitor_json(m: *c.Monitor) callconv(.c) ?*c.struct_cJSON;
extern fn build_monitor_tags_response(m: *c.Monitor) callconv(.c) ?*c.struct_cJSON;
extern fn build_all_tags_response() callconv(.c) ?*c.struct_cJSON;
extern fn build_all_clients_array() callconv(.c) ?*c.struct_cJSON;
extern fn ipc_device_type_str(dev: ?*c.struct_wlr_input_device) callconv(.c) [*:0]const u8;
extern fn ipc_get_layout_str() callconv(.c) [*:0]const u8;
extern fn acwm_ext_workspace_printstatus(m: *c.Monitor) callconv(.c) void;
extern var layouts: [14]c.Layout;

extern "c" fn cJSON_PrintUnformatted(json: ?*const c.struct_cJSON) ?[*:0]u8;
extern "c" fn cJSON_Delete(json: ?*c.struct_cJSON) void;
extern "c" fn send(fd: c_int, buf: [*]const u8, len: usize, flags: c_int) isize;
extern "c" fn recv(fd: c_int, buf: [*]u8, len: usize, flags: c_int) isize;
extern "c" fn malloc(size: usize) ?*anyopaque;
extern "c" fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn snprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ...) c_int;
extern "c" fn strlen(s: [*:0]const u8) usize;
extern "c" fn strcmp(a: [*:0]const u8, b: [*:0]const u8) c_int;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn __errno_location() *c_int;

const Watcher = c.struct_ipc_watch_client;
const WlList = c.struct_wl_list;

fn containerOf(comptime T: type, comptime link_field: []const u8, link: [*c]WlList) *T {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(T, link_field));
}

fn listHead(head: *WlList) [*c]WlList {
    return @ptrCast(head);
}

fn listInit(head: *WlList) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

fn listRemove(link: *WlList) void {
    const prev = link.prev;
    const next = link.next;
    prev.*.next = next;
    next.*.prev = prev;
}

/// Renders the payload once: JSON + trailing newline, C-allocated.
const Payload = struct { ptr: [*:0]u8, len: usize };

fn printJSON(json: ?*c.struct_cJSON) ?Payload {
    const raw = cJSON_PrintUnformatted(json) orelse return null;
    const len = strlen(raw);
    const raw_msg = malloc(len + 2) orelse {
        free(@ptrCast(raw));
        return null;
    };
    const msg: [*:0]u8 = @ptrCast(raw_msg);
    _ = snprintf(msg, len + 2, "%s\n", raw);
    free(@ptrCast(raw));
    return .{ .ptr = msg, .len = len + 1 };
}

fn watcherType(wc: *Watcher) c.uint {
    return @intCast(wc.type);
}

// ---------------------------------------------------------------------------
// watch plumbing
// ---------------------------------------------------------------------------

export fn ipc_notify_json_to_fd(fd: c_int, json: ?*c.struct_cJSON) callconv(.c) void {
    const payload = printJSON(json) orelse return;
    defer free(@ptrCast(payload.ptr));

    if (send(fd, payload.ptr, payload.len, 0) < 0) {
        var pos = c.ipc_watch_clients.next;
        const head = listHead(&c.ipc_watch_clients);
        while (pos != head) : (pos = pos.*.next) {
            const wc = containerOf(Watcher, "link", pos);
            if (wc.fd == fd) {
                ipc_remove_watch_client(wc);
                break;
            }
        }
    }
}

export fn ipc_notify_device_event(dev: ?*c.struct_wlr_input_device) callconv(.c) void {
    if (dev == null or c.ipc_device_watch_count == 0)
        return;

    const json = c.cJSON_CreateObject();
    _ = c.cJSON_AddStringToObject(json, "name", if (dev.?.name != null) @ptrCast(dev.?.name) else "");
    _ = c.cJSON_AddStringToObject(json, "type", ipc_device_type_str(dev));

    var pos = c.ipc_watch_clients.next;
    const head = listHead(&c.ipc_watch_clients);
    while (pos != head) {
        const next = pos.*.next; // removal-safe
        const wc = containerOf(Watcher, "link", pos);
        if (watcherType(wc) == c.IPC_WATCH_DEVICE)
            ipc_notify_json_to_fd(wc.fd, json);
        pos = next;
    }
    cJSON_Delete(json);
}

export fn ipc_remove_watch_client(wc: *Watcher) callconv(.c) void {
    if (watcherType(wc) == c.IPC_WATCH_DEVICE)
        c.ipc_device_watch_count -= 1;
    listRemove(&wc.link);
    _ = c.wl_event_source_remove(wc.source);
    _ = close(wc.fd);
    free(@ptrCast(wc));
}

export fn ipc_watch_data_handler(fd: c_int, mask: u32, data: ?*anyopaque) callconv(.c) c_int {
    const wc: *Watcher = @ptrCast(@alignCast(data.?));
    if ((mask & (c.WL_EVENT_HANGUP | c.WL_EVENT_ERROR)) != 0) {
        ipc_remove_watch_client(wc);
        return 0;
    }
    if ((mask & c.WL_EVENT_READABLE) != 0) {
        var buf: [64]u8 = undefined;
        const n = recv(fd, &buf, buf.len, 0);
        const err = __errno_location().*;
        if (n == 0 or (n < 0 and err != c.EAGAIN and err != c.EWOULDBLOCK))
            ipc_remove_watch_client(wc);
    }
    return 0;
}

// ---------------------------------------------------------------------------
// notifiers
// ---------------------------------------------------------------------------

fn notifyByTypeFallback() void {
    acwm_error_impl(true, WLR_ERROR, @src().file, @src().line, "IPC: out of memory");
}

export fn ipc_notify_client(cl: *c.Client) callconv(.c) void {
    var payload: ?Payload = null;
    var pos = c.ipc_watch_clients.next;
    const head = listHead(&c.ipc_watch_clients);
    while (pos != head) {
        const next = pos.*.next;
        const wc = containerOf(Watcher, "link", pos);
        if (watcherType(wc) == c.IPC_WATCH_CLIENT and wc.target.client.id == cl.id) {
            if (payload == null) {
                const json = build_client_json(cl) orelse return;
                payload = printJSON(json) orelse {
                    cJSON_Delete(json);
                    return;
                };
                cJSON_Delete(json);
            }
            if (send(wc.fd, payload.?.ptr, payload.?.len, 0) < 0)
                ipc_remove_watch_client(wc);
        }
        pos = next;
    }
    if (payload) |p| free(@ptrCast(p.ptr));
}

export fn ipc_notify_tags(m: *c.Monitor) callconv(.c) void {
    var payload: ?Payload = null;
    var pos = c.ipc_watch_clients.next;
    const head = listHead(&c.ipc_watch_clients);
    while (pos != head) {
        const next = pos.*.next;
        const wc = containerOf(Watcher, "link", pos);
        if (watcherType(wc) == c.IPC_WATCH_TAGS and
            strcmp(@ptrCast(&wc.target.tags.mon_name), @ptrCast(output(m).name)) == 0)
        {
            if (payload == null) {
                const json = build_monitor_tags_response(m) orelse return;
                payload = printJSON(json) orelse {
                    cJSON_Delete(json);
                    return;
                };
                cJSON_Delete(json);
            }
            if (send(wc.fd, payload.?.ptr, payload.?.len, 0) < 0)
                ipc_remove_watch_client(wc);
        }
        pos = next;
    }
    if (payload) |p| free(@ptrCast(p.ptr));
}

export fn ipc_notify_all_tags() callconv(.c) void {
    var payload: ?Payload = null;
    var pos = c.ipc_watch_clients.next;
    const head = listHead(&c.ipc_watch_clients);
    while (pos != head) {
        const next = pos.*.next;
        const wc = containerOf(Watcher, "link", pos);
        if (watcherType(wc) == c.IPC_WATCH_ALL_TAGS) {
            if (payload == null) {
                const json = build_all_tags_response() orelse return;
                payload = printJSON(json) orelse {
                    cJSON_Delete(json);
                    return;
                };
                cJSON_Delete(json);
            }
            if (send(wc.fd, payload.?.ptr, payload.?.len, 0) < 0)
                ipc_remove_watch_client(wc);
        }
        pos = next;
    }
    if (payload) |p| free(@ptrCast(p.ptr));
}

export fn ipc_notify_monitor(m: *c.Monitor) callconv(.c) void {
    var payload: ?Payload = null;
    var pos = c.ipc_watch_clients.next;
    const head = listHead(&c.ipc_watch_clients);
    while (pos != head) {
        const next = pos.*.next;
        const wc = containerOf(Watcher, "link", pos);
        if (watcherType(wc) == c.IPC_WATCH_MONITOR and
            strcmp(@ptrCast(&wc.target.monitor.name), @ptrCast(output(m).name)) == 0)
        {
            if (payload == null) {
                const json = build_monitor_json(m) orelse return;
                payload = printJSON(json) orelse {
                    cJSON_Delete(json);
                    return;
                };
                cJSON_Delete(json);
            }
            if (send(wc.fd, payload.?.ptr, payload.?.len, 0) < 0)
                ipc_remove_watch_client(wc);
        }
        pos = next;
    }
    if (payload) |p| free(@ptrCast(p.ptr));
}

export fn ipc_notify_last_surface_ws_name(m: *c.Monitor) callconv(.c) void {
    var payload: ?Payload = null;
    var pos = c.ipc_watch_clients.next;
    const head = listHead(&c.ipc_watch_clients);
    while (pos != head) {
        const next = pos.*.next;
        const wc = containerOf(Watcher, "link", pos);
        if (watcherType(wc) != c.IPC_WATCH_LAST_OPEN_SURFACE) {
            pos = next;
            continue;
        }

        var match = false;
        if (wc.target.monitor.name[0] == 0) {
            if (c.server.selected_monitor == @as([*c]c.Monitor, @ptrCast(m)))
                match = true;
        } else {
            if (strcmp(@ptrCast(&wc.target.monitor.name), @ptrCast(output(m).name)) == 0)
                match = true;
        }

        if (match) {
            if (payload == null) {
                const json = c.cJSON_CreateObject();
                _ = c.cJSON_AddStringToObject(json, "monitor", @ptrCast(output(m).name));
                _ = c.cJSON_AddStringToObject(json, "last_open_surface", @ptrCast(&m.last_open_surface));
                payload = printJSON(json) orelse {
                    cJSON_Delete(json);
                    return;
                };
                cJSON_Delete(json);
            }
            if (send(wc.fd, payload.?.ptr, payload.?.len, 0) < 0)
                ipc_remove_watch_client(wc);
        }
        pos = next;
    }
    if (payload) |p| free(@ptrCast(p.ptr));
}

export fn ipc_notify_focusing_client() callconv(.c) void {
    var payload: ?Payload = null;
    var pos = c.ipc_watch_clients.next;
    const head = listHead(&c.ipc_watch_clients);
    while (pos != head) {
        const next = pos.*.next;
        const wc = containerOf(Watcher, "link", pos);
        if (watcherType(wc) == c.IPC_WATCH_FOCUSING_CLIENT) {
            if (payload == null) {
                var json: ?*c.struct_cJSON = null;
                if (c.server.selected_monitor != null and c.server.selected_monitor.*.sel != null) {
                    json = build_client_json(c.server.selected_monitor.*.sel);
                } else {
                    const obj = c.cJSON_CreateObject();
                    _ = c.cJSON_AddNullToObject(obj, "id");
                    _ = c.cJSON_AddNullToObject(obj, "title");
                    _ = c.cJSON_AddNullToObject(obj, "appid");
                    json = obj;
                }
                payload = printJSON(json) orelse {
                    cJSON_Delete(json);
                    return;
                };
                cJSON_Delete(json);
            }
            if (send(wc.fd, payload.?.ptr, payload.?.len, 0) < 0)
                ipc_remove_watch_client(wc);
        }
        pos = next;
    }
    if (payload) |p| free(@ptrCast(p.ptr));
}

export fn ipc_notify_all_monitors() callconv(.c) void {
    var payload: ?Payload = null;
    var pos = c.ipc_watch_clients.next;
    const head = listHead(&c.ipc_watch_clients);
    while (pos != head) {
        const next = pos.*.next;
        const wc = containerOf(Watcher, "link", pos);
        if (watcherType(wc) == c.IPC_WATCH_ALL_MONITORS) {
            if (payload == null) {
                const arr = c.cJSON_CreateArray();
                var mpos = c.server.monitors.next;
                const mhead: [*c]WlList = @ptrCast(&c.server.monitors);
                while (mpos != mhead) : (mpos = mpos.*.next) {
                    const mm = containerOf(c.Monitor, "link", mpos);
                    _ = c.cJSON_AddItemToArray(arr, build_monitor_json(mm));
                }
                const json = c.cJSON_CreateObject();
                _ = c.cJSON_AddItemToObject(json, "monitors", arr);
                payload = printJSON(json) orelse {
                    cJSON_Delete(json);
                    return;
                };
                cJSON_Delete(json);
            }
            if (send(wc.fd, payload.?.ptr, payload.?.len, 0) < 0)
                ipc_remove_watch_client(wc);
        }
        pos = next;
    }
    if (payload) |p| free(@ptrCast(p.ptr));
}

export fn ipc_notify_all_clients() callconv(.c) void {
    var payload: ?Payload = null;
    var pos = c.ipc_watch_clients.next;
    const head = listHead(&c.ipc_watch_clients);
    while (pos != head) {
        const next = pos.*.next;
        const wc = containerOf(Watcher, "link", pos);
        if (watcherType(wc) == c.IPC_WATCH_ALL_CLIENTS) {
            if (payload == null) {
                const json = c.cJSON_CreateObject();
                _ = c.cJSON_AddItemToObject(json, "clients", build_all_clients_array());
                payload = printJSON(json) orelse {
                    cJSON_Delete(json);
                    return;
                };
                cJSON_Delete(json);
            }
            if (send(wc.fd, payload.?.ptr, payload.?.len, 0) < 0)
                ipc_remove_watch_client(wc);
        }
        pos = next;
    }
    if (payload) |p| free(@ptrCast(p.ptr));
}

export fn ipc_notify_keymode() callconv(.c) void {
    var payload: ?Payload = null;
    var pos = c.ipc_watch_clients.next;
    const head = listHead(&c.ipc_watch_clients);
    while (pos != head) {
        const next = pos.*.next;
        const wc = containerOf(Watcher, "link", pos);
        if (watcherType(wc) == c.IPC_WATCH_KEYMODE) {
            if (payload == null) {
                const json = c.cJSON_CreateObject();
                _ = c.cJSON_AddStringToObject(json, "keymode", @ptrCast(&c.server.key_mode.mode));
                payload = printJSON(json) orelse {
                    cJSON_Delete(json);
                    return;
                };
                cJSON_Delete(json);
            }
            if (send(wc.fd, payload.?.ptr, payload.?.len, 0) < 0)
                ipc_remove_watch_client(wc);
        }
        pos = next;
    }
    if (payload) |p| free(@ptrCast(p.ptr));
}

export fn ipc_notify_kb_layout() callconv(.c) void {
    var payload: ?Payload = null;
    var pos = c.ipc_watch_clients.next;
    const head = listHead(&c.ipc_watch_clients);
    while (pos != head) {
        const next = pos.*.next;
        const wc = containerOf(Watcher, "link", pos);
        if (watcherType(wc) == c.IPC_WATCH_KB_LAYOUT) {
            if (payload == null) {
                const json = c.cJSON_CreateObject();
                _ = c.cJSON_AddStringToObject(json, "layout", ipc_get_layout_str());
                payload = printJSON(json) orelse {
                    cJSON_Delete(json);
                    return;
                };
                cJSON_Delete(json);
            }
            if (send(wc.fd, payload.?.ptr, payload.?.len, 0) < 0)
                ipc_remove_watch_client(wc);
        }
        pos = next;
    }
    if (payload) |p| free(@ptrCast(p.ptr));
}

// ---------------------------------------------------------------------------
// printstatus
// ---------------------------------------------------------------------------

fn signalEmit(signal: *c.struct_wl_signal, data: ?*anyopaque) void {
    var pos = signal.listener_list.next;
    const head: [*c]WlList = @ptrCast(&signal.listener_list);
    while (pos != head) {
        const next = pos.*.next; // listeners may unlink themselves
        const listener = containerOf(c.struct_wl_listener, "link", pos);
        if (listener.notify) |notify|
            notify(@ptrCast(listener), data);
        pos = next;
    }
}

export fn printstatus(kind: c.uint) callconv(.c) void {
    var value: c.uint = kind;
    signalEmit(&c.server.print_status_signal, &value);
}

export fn handle_print_status(listener: ?*c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const kind = @as(*const c.uint, @ptrCast(@alignCast(data.?))).*;

    if ((kind & c.IPC_WATCH_KEYMODE) != 0)
        ipc_notify_keymode();
    if ((kind & c.IPC_WATCH_KB_LAYOUT) != 0)
        ipc_notify_kb_layout();
    if ((kind & c.IPC_WATCH_FOCUSING_CLIENT) != 0)
        ipc_notify_focusing_client();
    if ((kind & c.IPC_WATCH_ALL_TAGS) != 0)
        ipc_notify_all_tags();
    if ((kind & c.IPC_WATCH_ALL_CLIENTS) != 0)
        ipc_notify_all_clients();
    if ((kind & (c.IPC_WATCH_ALL_MONITORS | c.IPC_WATCH_KEYMODE | c.IPC_WATCH_KB_LAYOUT |
        c.IPC_WATCH_FOCUSING_CLIENT | c.IPC_WATCH_TAGS)) != 0)
        ipc_notify_all_monitors();

    if ((kind & c.IPC_WATCH_CLIENT) != 0) {
        var pos = c.server.clients.next;
        const head: [*c]WlList = @ptrCast(&c.server.clients);
        while (pos != head) : (pos = pos.*.next) {
            const cl = containerOf(c.Client, "link", pos);
            if (cl.iskilling != 0)
                continue;
            ipc_notify_client(cl);
        }
    }

    var pos = c.server.monitors.next;
    const head: [*c]WlList = @ptrCast(&c.server.monitors);
    while (pos != head) : (pos = pos.*.next) {
        const m = containerOf(c.Monitor, "link", pos);
        if (output(m).*.enabled == false)
            continue;
        if ((kind & c.IPC_WATCH_MONITOR) != 0)
            ipc_notify_monitor(m);
        if ((kind & c.IPC_WATCH_TAGS) != 0)
            ipc_notify_tags(m);
        if ((kind & c.IPC_WATCH_LAST_OPEN_SURFACE) != 0)
            ipc_notify_last_surface_ws_name(m);
        acwm_ext_workspace_printstatus(m);
    }
}

fn output(m: *c.Monitor) *c.struct_wlr_output {
    return @ptrCast(m.wlr_output);
}

// ---------------------------------------------------------------------------
// tests (stub-backed: see tests/ipc_watch_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_active_tagset: u32;
extern var stub_curtag: u32;
extern var stub_title: [128]u8;
extern var stub_appid: [128]u8;
extern var stub_layout_str: [32]u8;
extern var stub_workspace_printstatus_calls: c_int;

extern "c" fn socketpair(domain: c_int, typ: c_int, protocol: c_int, sv: *[2]c_int) c_int;
extern "c" fn fcntl(fd: c_int, cmd: c_int, arg: c_int) c_int;
extern "c" fn read(fd: c_int, buf: [*]u8, n: usize) isize;

var name_buf: [4:0]u8 = "DP-1".*;

fn resetWatchState() void {
    listInit(&c.ipc_watch_clients);
    c.ipc_device_watch_count = 0;
    c.server.clients = std.mem.zeroes(WlList);
    c.server.monitors = std.mem.zeroes(WlList);
    listInit(&c.server.clients);
    listInit(&c.server.monitors);
    c.server.selected_monitor = null;
    listInit(&c.server.print_status_signal.listener_list);
    c.config.tag_num = 2;
    c.server.tagmask = 0b11;
    stub_active_tagset = 0;
    stub_curtag = 0;
    @memcpy(stub_title[0..5], "Title");
    stub_title[5] = 0;
    @memcpy(stub_appid[0..3], "app");
    stub_appid[3] = 0;
    @memcpy(stub_layout_str[0..2], "us");
    stub_layout_str[2] = 0;
}

fn newWatcher(fd: c_int, kind: c.uint) *Watcher {
    const raw = malloc(@sizeOf(Watcher)) orelse unreachable;
    const wc: *Watcher = @ptrCast(@alignCast(raw));
    wc.* = std.mem.zeroes(Watcher);
    wc.fd = fd;
    wc.type = @intCast(kind);
    listInsert(&c.ipc_watch_clients, &wc.link);
    return wc;
}

fn listInsert(head: *WlList, link: *WlList) void {
    link.next = head.next;
    link.prev = @ptrCast(head);
    head.next.*.prev = @ptrCast(link);
    head.next = @ptrCast(link);
}

fn makePair() [2]c_int {
    var sv: [2]c_int = undefined;
    try_assert(socketpair(c.AF_UNIX, c.SOCK_STREAM, 0, &sv) == 0);
    _ = fcntl(sv[1], c.F_GETFL, 0);
    _ = fcntl(sv[1], c.F_SETFL, c.O_NONBLOCK);
    return sv;
}

fn try_assert(ok: bool) void {
    if (!ok)
        @panic("assertion failed");
}

var recv_buf: [4096]u8 = undefined;

fn recvMsg(fd: c_int) []const u8 {
    const n = read(fd, &recv_buf, recv_buf.len);
    if (n <= 0)
        return "";
    return recv_buf[0..@intCast(n)];
}

test "notify_json_to_fd appends a newline and sends" {
    resetWatchState();
    const sv = makePair();
    defer _ = close(sv[0]);
    defer _ = close(sv[1]);

    _ = newWatcher(sv[0], c.IPC_WATCH_MONITOR);
    const json = c.cJSON_CreateObject();
    _ = c.cJSON_AddNumberToObject(json, "n", 7);
    ipc_notify_json_to_fd(sv[0], json);
    cJSON_Delete(json);

    try testing.expectEqualStrings("{\"n\":7}\n", recvMsg(sv[1]));
}

test "notify_client matches watcher target ids only" {
    resetWatchState();
    const sv = makePair();
    defer _ = close(sv[0]);
    defer _ = close(sv[1]);
    const sv_other = makePair();
    defer _ = close(sv_other[0]);
    defer _ = close(sv_other[1]);

    const matching = newWatcher(sv[0], c.IPC_WATCH_CLIENT);
    matching.target.client.id = 5;
    const other = newWatcher(sv_other[0], c.IPC_WATCH_CLIENT);
    other.target.client.id = 6;

    var cl: c.Client = std.mem.zeroes(c.Client);
    cl.id = 5;
    ipc_notify_client(&cl);

    const msg = recvMsg(sv[1]);
    try testing.expect(std.mem.indexOf(u8, msg, "\"id\":5") != null);
    try testing.expectEqualStrings("", recvMsg(sv_other[1]));
}

test "notify_tags filters by monitor name" {
    resetWatchState();
    const sv = makePair();
    defer _ = close(sv[0]);
    defer _ = close(sv[1]);

    const wc = newWatcher(sv[0], c.IPC_WATCH_TAGS);
    @memcpy(wc.target.tags.mon_name[0..4], "DP-1");
    wc.target.tags.mon_name[4] = 0;

    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    out.name = @ptrCast(&name_buf);
    out.enabled = true;
    var pertag: c.Pertag = std.mem.zeroes(c.Pertag);
    pertag.ltidxs[0] = &layouts[0];
    pertag.ltidxs[1] = &layouts[0];
    pertag.ltidxs[2] = &layouts[0];
    var m: c.Monitor = std.mem.zeroes(c.Monitor);
    m.wlr_output = @ptrCast(&out);
    m.pertag = @ptrCast(&pertag);
    layouts[0].symbol = "T";
    layouts[0].name = "tile";

    ipc_notify_tags(&m);
    const msg = recvMsg(sv[1]);
    try testing.expect(std.mem.indexOf(u8, msg, "\"monitor\":\"DP-1\"") != null);
    try testing.expect(std.mem.indexOf(u8, msg, "\"tags\"") != null);
}

test "notify_all_monitors and keymode produce their wrappers" {
    resetWatchState();
    const sv = makePair();
    defer _ = close(sv[0]);
    defer _ = close(sv[1]);
    const sv2 = makePair();
    defer _ = close(sv2[0]);
    defer _ = close(sv2[1]);

    _ = newWatcher(sv[0], c.IPC_WATCH_ALL_MONITORS);
    _ = newWatcher(sv2[0], c.IPC_WATCH_KEYMODE);

    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    out.name = @ptrCast(&name_buf);
    out.enabled = true;
    var pertag: c.Pertag = std.mem.zeroes(c.Pertag);
    pertag.ltidxs[0] = &layouts[0];
    pertag.ltidxs[1] = &layouts[0];
    pertag.ltidxs[2] = &layouts[0];
    var m: c.Monitor = std.mem.zeroes(c.Monitor);
    m.wlr_output = @ptrCast(&out);
    m.pertag = @ptrCast(&pertag);
    listInsert(&c.server.monitors, &m.link);
    defer listInit(&c.server.monitors);

    ipc_notify_all_monitors();
    const msg = recvMsg(sv[1]);
    try testing.expect(std.mem.indexOf(u8, msg, "\"monitors\":[") != null);

    _ = snprintf(&c.server.key_mode.mode, c.server.key_mode.mode.len, "%s", "resize");
    ipc_notify_keymode();
    const msg2 = recvMsg(sv2[1]);
    try testing.expect(std.mem.indexOf(u8, msg2, "\"keymode\":\"resize\"") != null);
}

test "remove_watch_client updates the device count and unlinks" {
    resetWatchState();
    const sv = makePair();
    defer _ = close(sv[1]);
    const wc = newWatcher(sv[0], c.IPC_WATCH_DEVICE);
    c.ipc_device_watch_count = 1;

    ipc_remove_watch_client(wc);
    try testing.expectEqual(@as(c_int, 0), c.ipc_device_watch_count);
    try testing.expect(c.ipc_watch_clients.next == @as([*c]WlList, @ptrCast(&c.ipc_watch_clients)));
}

test "watch data handler removes hanging-up clients" {
    resetWatchState();
    const sv = makePair();
    defer _ = close(sv[1]);
    const wc = newWatcher(sv[0], c.IPC_WATCH_MONITOR);

    _ = ipc_watch_data_handler(sv[0], c.WL_EVENT_HANGUP, wc);
    try testing.expect(c.ipc_watch_clients.next == @as([*c]WlList, @ptrCast(&c.ipc_watch_clients)));
}

var emitted_kind: c.uint = 0;
var listener_fired = false;

fn recordingListener(listener: ?*c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    listener_fired = true;
    emitted_kind = @as(*c.uint, @ptrCast(@alignCast(data.?))).*;
}

test "printstatus emits the signal; handle_print_status dispatches" {
    resetWatchState();
    listener_fired = false;
    var listener: c.struct_wl_listener = std.mem.zeroes(c.struct_wl_listener);
    listener.notify = recordingListener;
    const signal = &c.server.print_status_signal;
    listInsert(&signal.listener_list, &listener.link);
    defer listRemove(&listener.link);

    printstatus(c.IPC_WATCH_KEYMODE);
    try testing.expect(listener_fired);
    try testing.expectEqual(@as(c.uint, c.IPC_WATCH_KEYMODE), emitted_kind);

    // direct dispatch: a keymode watcher receives the payload
    const sv = makePair();
    defer _ = close(sv[0]);
    defer _ = close(sv[1]);
    _ = newWatcher(sv[0], c.IPC_WATCH_KEYMODE);
    _ = snprintf(&c.server.key_mode.mode, c.server.key_mode.mode.len, "%s", "default");
    var kind: c.uint = c.IPC_WATCH_KEYMODE;
    handle_print_status(null, &kind);
    try testing.expect(std.mem.indexOf(u8, recvMsg(sv[1]), "\"keymode\":\"default\"") != null);
}
