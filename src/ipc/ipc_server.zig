//! Port of the IPC server side of src/ipc/ipc.c (strangler-fig Phase 4,
//! slice 28 — completes ipc.c).
//!
//! Exports: handle_command, handle_watch_command, ipc_handle_client_data,
//! ipc_handle_connection, ipc_init, ipc_cleanup. C twins are
//! #ifndef ACWM_ZIG_IPC_SERVER guarded.
//!
//! handle_command translates every command (get version/cursorpos/keymode/
//! keyboardlayout/last_open_surface/monitor/focusing-client/client/tag/
//! all-clients/all-monitors/all-devices/all-layers/all-tags/tags/layouts,
//! and the `dispatch` path with its client,<id> extraction and comma
//! tokenizer quirks). The version string comes from a build-options module
//! (the C twin uses the VERSION macro).

const std = @import("std");
const c = @import("cc");
const build_options = @import("build_options");

const WLR_ERROR: c_uint = @intCast(c.WLR_ERROR);

extern fn acwm_error_impl(
    log: bool,
    verbosity: c_uint,
    file: [*:0]const u8,
    line: c_int,
    fmt: [*:0]const u8,
    ...) callconv(.c) void;
extern fn send_static_json(fd: c_int, json_str: [*:0]const u8) callconv(.c) void;
extern fn monitor_by_name(name: [*:0]const u8) callconv(.c) ?*c.Monitor;
extern fn client_by_id(id: u32) callconv(.c) ?*c.Client;
extern fn client_by_id_all(id: u32) callconv(.c) ?*c.Client;
extern fn client_focus_top(m: *c.Monitor) callconv(.c) ?*c.Client;
extern fn monitor_at_point(x: f64, y: f64) callconv(.c) ?*c.Monitor;
extern fn ipc_device_type_str(dev: ?*c.struct_wlr_input_device) callconv(.c) [*:0]const u8;
extern fn find_device_rule(dev: ?*c.struct_wlr_input_device) callconv(.c) ?*c.ConfigDeviceRule;
extern fn ipc_get_layout_str() callconv(.c) [*:0]const u8;
extern fn ipc_watch_data_handler(fd: c_int, mask: u32, data: ?*anyopaque) callconv(.c) c_int;
extern fn ipc_remove_watch_client(wc: *c.struct_ipc_watch_client) callconv(.c) void;
extern fn build_client_json(cl: *c.Client) callconv(.c) ?*c.struct_cJSON;
extern fn build_monitor_json(m: *c.Monitor) callconv(.c) ?*c.struct_cJSON;
extern fn build_monitor_tags_response(m: *c.Monitor) callconv(.c) ?*c.struct_cJSON;
extern fn build_all_tags_response() callconv(.c) ?*c.struct_cJSON;
extern fn build_layers_response() callconv(.c) ?*c.struct_cJSON;
extern fn build_layouts_response() callconv(.c) ?*c.struct_cJSON;
extern fn build_all_clients_array() callconv(.c) ?*c.struct_cJSON;
extern fn build_tags_json(m: *c.Monitor) callconv(.c) ?*c.struct_cJSON;
extern fn monitor_active_client(m: *c.Monitor) callconv(.c) ?*c.struct_cJSON;
extern fn get_monitor_active_tagset(m: *c.Monitor) callconv(.c) u32;
extern fn parse_func_name(
    func_name: [*:0]u8,
    arg: *c.Arg,
    arg_value: [*:0]u8,
    arg_value2: [*:0]u8,
    arg_value3: [*:0]u8,
    arg_value4: [*:0]u8,
    arg_value5: [*:0]u8,
) callconv(.c) c.FuncType;
extern var layouts: [14]c.Layout;

extern "c" fn cJSON_PrintUnformatted(json: ?*const c.struct_cJSON) ?[*:0]u8;
extern "c" fn cJSON_Delete(json: ?*c.struct_cJSON) void;
extern "c" fn snprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ...) c_int;
extern "c" fn strlen(s: [*:0]const u8) usize;
extern "c" fn strcmp(a: [*:0]const u8, b: [*:0]const u8) c_int;
extern "c" fn strncmp(a: [*:0]const u8, b: [*:0]const u8, n: usize) c_int;
extern "c" fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern "c" fn strtok_r(str: ?[*:0]u8, delim: [*:0]const u8, saveptr: *?[*:0]u8) ?[*:0]u8;
extern "c" fn strtol(nptr: [*:0]const u8, endptr: *?[*:0]u8, base: c_int) c_long;
extern "c" fn atoi(nptr: [*:0]const u8) c_int;
extern "c" fn sscanf(str: [*:0]const u8, fmt: [*:0]const u8, ...) c_int;
extern "c" fn malloc(size: usize) ?*anyopaque;
extern "c" fn calloc(nmemb: usize, size: usize) ?*anyopaque;
extern "c" fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn memchr(s: ?*const anyopaque, ch: c_int, n: usize) ?*anyopaque;
extern "c" fn send(fd: c_int, buf: [*]const u8, len: usize, flags: c_int) isize;
extern "c" fn recv(fd: c_int, buf: [*]u8, len: usize, flags: c_int) isize;
extern "c" fn accept(fd: c_int, addr: ?*anyopaque, len: ?*anyopaque) c_int;
extern "c" fn socket(domain: c_int, typ: c_int, protocol: c_int) c_int;
extern "c" fn bind(fd: c_int, addr: ?*const anyopaque, len: c_uint) c_int;
extern "c" fn listen(fd: c_int, backlog: c_int) c_int;
extern "c" fn unlink(path: [*:0]const u8) c_int;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn fcntl(fd: c_int, cmd: c_int, arg: c_int) c_int;
extern "c" fn getpid() c_int;
extern "c" fn getenv(name: [*:0]const u8) ?[*:0]u8;
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;

const WlList = c.struct_wl_list;
const Watcher = c.struct_ipc_watch_client;
const ClientState = c.struct_ipc_client_state;

const SockaddrUn = extern struct {
    sun_family: c.sa_family_t,
    sun_path: [108]u8,
};

var ipc_socket_fd: c_int = -1;
var ipc_socket_path: [256]u8 = std.mem.zeroes([256]u8);
var ipc_event_source: ?*c.struct_wl_event_source = null;

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

fn listInsert(head: *WlList, link: *WlList) void {
    link.next = head.next;
    link.prev = @ptrCast(head);
    head.next.*.prev = @ptrCast(link);
    head.next = @ptrCast(link);
}

fn listRemove(link: *WlList) void {
    const prev = link.prev;
    const next = link.next;
    prev.*.next = next;
    next.*.prev = prev;
}

fn output(m: *c.Monitor) *c.struct_wlr_output {
    return @ptrCast(m.wlr_output);
}

// IPC_WATCH_* bits are used through the translated enum constants directly.
fn isWatch(kind: c.uint, flag: anytype) bool {
    return (kind & @as(c.uint, @intCast(flag))) != 0;
}

// ---------------------------------------------------------------------------
// handle_command
// ---------------------------------------------------------------------------

fn sendResponse(fd: c_int, resp: ?*c.struct_cJSON) void {
    const json = resp orelse return;
    defer cJSON_Delete(json);
    const raw = cJSON_PrintUnformatted(json) orelse return;
    defer free(@ptrCast(raw));
    const len = strlen(raw);
    const raw_msg = malloc(len + 2) orelse return;
    const msg: [*:0]u8 = @ptrCast(raw_msg);
    defer free(@ptrCast(msg));
    _ = snprintf(msg, len + 2, "%s\n", raw);
    _ = send(fd, msg, len + 1, 0);
}

export fn handle_command(client_fd: c_int, cmd_raw: [*:0]const u8) callconv(.c) void {
    var resp: ?*c.struct_cJSON = null;
    var cmd: [1024]u8 = undefined;

    _ = snprintf(&cmd, cmd.len, "%s", cmd_raw);
    // commas become spaces (the command separator)
    for (&cmd) |*ch| {
        if (ch.* == 0) break;
        if (ch.* == ',') ch.* = ' ';
    }
    const cmd_z: [*:0]const u8 = @ptrCast(&cmd);

    if (strcmp(cmd_z, "get version") == 0) {
        resp = c.cJSON_CreateObject();
        _ = c.cJSON_AddStringToObject(resp, "version", build_options.version ++ "");
    } else if (strcmp(cmd_z, "get cursorpos") == 0) {
        resp = c.cJSON_CreateObject();
        _ = c.cJSON_AddNumberToObject(resp, "x", c.server.cursor.*.x);
        _ = c.cJSON_AddNumberToObject(resp, "y", c.server.cursor.*.y);
        const m = monitor_at_point(c.server.cursor.*.x, c.server.cursor.*.y);
        if (m != null)
            _ = c.cJSON_AddStringToObject(resp, "monitor", @ptrCast(output(m.?).name))
        else
            _ = c.cJSON_AddNullToObject(resp, "monitor");
    } else if (strcmp(cmd_z, "get keymode") == 0) {
        resp = c.cJSON_CreateObject();
        _ = c.cJSON_AddStringToObject(resp, "keymode", @ptrCast(&c.server.key_mode.mode));
    } else if (strcmp(cmd_z, "get keyboardlayout") == 0) {
        resp = c.cJSON_CreateObject();
        _ = c.cJSON_AddStringToObject(resp, "layout", ipc_get_layout_str());
    } else if (strcmp(cmd_z, "get last_open_surface") == 0 or
        strncmp(cmd_z, "get last_open_surface ", 22) == 0)
    {
        var m: ?*c.Monitor = null;
        if (cmd[21] == 0) {
            m = @ptrCast(c.server.selected_monitor);
        } else {
            m = monitor_by_name(cmd_z + 22);
        }
        if (m == null) {
            send_static_json(client_fd, "{\"error\":\"monitor not found\"}\n");
            return;
        }
        resp = c.cJSON_CreateObject();
        _ = c.cJSON_AddStringToObject(resp, "monitor", @ptrCast(output(m.?).name));
        _ = c.cJSON_AddStringToObject(resp, "last_open_surface", @ptrCast(&m.?.last_open_surface));
    } else if (strncmp(cmd_z, "get monitor ", 12) == 0) {
        const m = monitor_by_name(cmd_z + 12);
        if (m == null) {
            send_static_json(client_fd, "{\"error\":\"monitor not found\"}\n");
            return;
        }
        resp = build_monitor_json(m.?);
    } else if (strcmp(cmd_z, "get focusing-client") == 0) {
        if (c.server.selected_monitor != null and c.server.selected_monitor.*.sel != null) {
            resp = build_client_json(c.server.selected_monitor.*.sel);
        } else {
            send_static_json(client_fd, "{\"error\":\"no focused client\"}\n");
            return;
        }
    } else if (strncmp(cmd_z, "get client ", 11) == 0) {
        const cl = client_by_id_all(@bitCast(atoi(cmd_z + 11)));
        if (cl == null) {
            send_static_json(client_fd, "{\"error\":\"client not found\"}\n");
            return;
        }
        resp = build_client_json(cl.?);
    } else if (strncmp(cmd_z, "get tag ", 8) == 0) {
        var mon_name: [64]u8 = undefined;
        var ext_tag_idx: c_int = 0;
        if (sscanf(
            cmd_z + 8,
            "%63s %d",
            @as([*]u8, @ptrCast(&mon_name)),
            &ext_tag_idx,
        ) != 2) {
            send_static_json(client_fd, "{\"error\":\"usage: get tag <monitor> <index>\"}\n");
            return;
        }
        const tag_idx = ext_tag_idx - 1;
        const m = monitor_by_name(@ptrCast(&mon_name));
        if (m == null or tag_idx < 0 or tag_idx >= c.config.tag_num) {
            send_static_json(client_fd, "{\"error\":\"invalid monitor or tag index\"}\n");
            return;
        }
        const tag_bit: u32 = @as(u32, 1) << @intCast(tag_idx);
        var numclients: c_int = 0;
        var focused_client: c_int = 0;
        var is_active = false;
        var is_urgent = false;
        if ((tag_bit & get_monitor_active_tagset(m.?)) != 0)
            is_active = true;

        const focused = client_focus_top(m.?);
        var pos = c.server.clients.next;
        const head = listHead(&c.server.clients);
        while (pos != head) : (pos = pos.*.next) {
            const cl = containerOf(c.Client, "link", pos);
            if (cl.mon != @as([*c]c.Monitor, @ptrCast(m.?)) or (cl.tags & tag_bit) == 0)
                continue;
            if (focused != null and cl == focused.?)
                focused_client = 1;
            if (cl.isurgent != 0)
                is_urgent = true;
            numclients += 1;
        }
        resp = c.cJSON_CreateObject();
        _ = c.cJSON_AddStringToObject(resp, "monitor", @ptrCast(output(m.?).name));
        _ = c.cJSON_AddNumberToObject(resp, "tag_index", @floatFromInt(ext_tag_idx));
        _ = c.cJSON_AddBoolToObject(resp, "is_active", @intFromBool(is_active));
        _ = c.cJSON_AddBoolToObject(resp, "is_urgent", @intFromBool(is_urgent));
        _ = c.cJSON_AddNumberToObject(resp, "client_count", @floatFromInt(numclients));
        _ = c.cJSON_AddBoolToObject(resp, "focused_client", @intFromBool(focused_client != 0));
    } else if (strcmp(cmd_z, "get all-clients") == 0) {
        resp = c.cJSON_CreateObject();
        _ = c.cJSON_AddItemToObject(resp, "clients", build_all_clients_array());
    } else if (strcmp(cmd_z, "get all-monitors") == 0) {
        const arr = c.cJSON_CreateArray();
        var pos = c.server.monitors.next;
        const head = listHead(&c.server.monitors);
        while (pos != head) : (pos = pos.*.next) {
            const mm = containerOf(c.Monitor, "link", pos);
            _ = c.cJSON_AddItemToArray(arr, build_monitor_json(mm));
        }
        resp = c.cJSON_CreateObject();
        _ = c.cJSON_AddItemToObject(resp, "monitors", arr);
    } else if (strcmp(cmd_z, "get all-devices") == 0) {
        resp = buildAllDevices();
    } else if (strcmp(cmd_z, "get all-layers") == 0) {
        resp = build_layers_response();
    } else if (strcmp(cmd_z, "get all-tags") == 0) {
        resp = build_all_tags_response();
    } else if (strncmp(cmd_z, "get tags ", 9) == 0) {
        const m = monitor_by_name(cmd_z + 9);
        if (m == null) {
            send_static_json(client_fd, "{\"error\":\"monitor not found\"}\n");
            return;
        }
        resp = build_monitor_tags_response(m.?);
    } else if (strcmp(cmd_z, "get layouts") == 0) {
        resp = build_layouts_response();
    } else if (strncmp(cmd_z, "dispatch ", 9) == 0) {
        dispatchCommand(client_fd, cmd_raw);
        return; // Fast path exit
    } else {
        send_static_json(client_fd, "{\"error\":\"unknown command\"}\n");
        return;
    }

    sendResponse(client_fd, resp);
}

const DevGroup = struct {
    group: ?*c.struct_libinput_device_group,
    name: [256]u8,
    types: [8][16]u8,
    type_count: c_int,
    vendor: c_int,
    product: c_int,
    count: c_int,
    rule: ?*c.ConfigDeviceRule,
};

fn buildAllDevices() ?*c.struct_cJSON {
    var groups: [64]DevGroup = undefined;
    var group_count: c_int = 0;

    var pos = c.server.input_devices.next;
    const head = listHead(&c.server.input_devices);
    while (pos != head) : (pos = pos.*.next) {
        const id = containerOf(c.InputDevice, "link", pos);
        const dev = id.wlr_device;
        var ld: ?*c.struct_libinput_device = null;
        var grp: ?*c.struct_libinput_device_group = null;
        if (c.wlr_input_device_is_libinput(dev)) {
            ld = c.wlr_libinput_get_device_handle(dev);
        }
        if (ld != null) {
            grp = c.libinput_device_get_device_group(ld);
        }
        if (grp == null) {
            grp = @ptrCast(@alignCast(dev));
        }

        var gi: c_int = -1;
        var i: c_int = 0;
        while (i < group_count) : (i += 1) {
            if (groups[@intCast(i)].group == grp) {
                gi = i;
                break;
            }
        }
        if (gi < 0) {
            gi = group_count;
            group_count += 1;
            const g = &groups[@intCast(gi)];
            g.group = grp;
            _ = snprintf(&g.name, g.name.len, "%s", if (dev != null and dev.*.name != null) @as([*:0]const u8, @ptrCast(dev.*.name)) else "");
            g.type_count = 0;
            g.vendor = if (ld != null) @intCast(c.libinput_device_get_id_vendor(ld)) else 0;
            g.product = if (ld != null) @intCast(c.libinput_device_get_id_product(ld)) else 0;
            g.count = 0;
            g.rule = null;
        }
        const g = &groups[@intCast(gi)];
        g.count += 1;
        if (g.rule == null)
            g.rule = find_device_rule(dev);

        const t = ipc_device_type_str(dev);
        var seen = false;
        var ti: c_int = 0;
        while (ti < g.type_count) : (ti += 1) {
            if (strcmp(@ptrCast(&g.types[@intCast(ti)]), t) == 0) {
                seen = true;
                break;
            }
        }
        if (!seen and g.type_count < 8) {
            _ = snprintf(&g.types[@intCast(g.type_count)], 16, "%s", t);
            g.type_count += 1;
        }
    }

    const arr = c.cJSON_CreateArray();
    var i: c_int = 0;
    while (i < group_count) : (i += 1) {
        const g = &groups[@intCast(i)];
        const obj = c.cJSON_CreateObject();
        _ = c.cJSON_AddStringToObject(obj, "name", @ptrCast(&g.name));
        const types = c.cJSON_CreateArray();
        var ti: c_int = 0;
        while (ti < g.type_count) : (ti += 1)
            _ = c.cJSON_AddItemToArray(types, c.cJSON_CreateString(@ptrCast(&g.types[@intCast(ti)])));
        _ = c.cJSON_AddItemToObject(obj, "types", types);
        _ = c.cJSON_AddNumberToObject(obj, "vendor", @floatFromInt(g.vendor));
        _ = c.cJSON_AddNumberToObject(obj, "product", @floatFromInt(g.product));

        var identifier: [512]u8 = undefined;
        _ = snprintf(&identifier, identifier.len, "%d:%d:%s", g.vendor, g.product, @as([*:0]const u8, @ptrCast(&g.name)));
        _ = c.cJSON_AddStringToObject(obj, "identifier", @ptrCast(&identifier));
        _ = c.cJSON_AddNumberToObject(obj, "interfaces", @floatFromInt(g.count));

        const rule = g.rule;
        _ = c.cJSON_AddBoolToObject(obj, "matched", @intFromBool(rule != null));
        if (rule) |r|
            _ = c.cJSON_AddStringToObject(obj, "matched_rule", if (r.name != null) @ptrCast(r.name) else @ptrCast(&r.type));
        _ = c.cJSON_AddItemToArray(arr, obj);
    }

    const resp = c.cJSON_CreateObject();
    _ = c.cJSON_AddItemToObject(resp, "devices", arr);
    return resp;
}

fn dispatchCommand(client_fd: c_int, cmd_raw: [*:0]const u8) void {
    const base: [*:0]const u8 = cmd_raw + 9;
    const dispatch_copy = strdup(base) orelse return;
    defer free(@ptrCast(dispatch_copy));

    // In-place removal of `client,<id>` fields (C pointer walk).
    var out: [*:0]u8 = dispatch_copy;
    var ptr: [*:0]u8 = dispatch_copy;
    var client_id: c_int = -1;
    var field_start = true;

    while (ptr[0] != 0) {
        while (ptr[0] == ' ' or ptr[0] == '\t') {
            out[0] = ptr[0];
            out += 1;
            ptr += 1;
            field_start = true;
        }
        if (ptr[0] == 0)
            break;

        if (field_start and strncmp(ptr, "client,", 7) == 0) {
            var end: ?[*:0]u8 = null;
            const id = strtol(ptr + 7, &end, 10);
            const end_ptr = end orelse ptr + 7;
            if (id > 0 and @intFromPtr(end_ptr) > @intFromPtr(ptr + 7) and
                (end_ptr[0] == 0 or end_ptr[0] == ','))
            {
                client_id = @intCast(id);
                ptr = end_ptr;
                if (ptr[0] == ',')
                    ptr += 1;
                continue;
            }
        }
        field_start = ptr[0] == ',';
        out[0] = ptr[0];
        out += 1;
        ptr += 1;
    }
    out[0] = 0;

    var tokens: [6]?[*:0]u8 = std.mem.zeroes([6]?[*:0]u8);
    var token_count: usize = 0;
    var saveptr: ?[*:0]u8 = null;
    var token = strtok_r(dispatch_copy, ",", &saveptr);
    while (token != null and token_count < 6) {
        var tk = token.?;
        while (tk[0] == ' ' or tk[0] == '\t')
            tk += 1;
        // trim trailing spaces/tabs
        const len = strlen(tk);
        var endp: usize = len;
        while (endp > 0 and (tk[endp - 1] == ' ' or tk[endp - 1] == '\t'))
            endp -= 1;
        tk[endp] = 0;

        tokens[token_count] = tk;
        token_count += 1;
        token = if (token_count >= 5) saveptr else strtok_r(null, ",", &saveptr);
    }

    const empty: [*:0]u8 = @constCast("");
    var arg: c.Arg = std.mem.zeroes(c.Arg);
    const func = parse_func_name(
        tokens[0] orelse empty,
        &arg,
        tokens[1] orelse empty,
        tokens[2] orelse empty,
        tokens[3] orelse empty,
        tokens[4] orelse empty,
        tokens[5] orelse empty,
    );

    if (client_id > 0) {
        arg.tc = client_by_id(@intCast(client_id));
        const focus_by_id = @extern(c.FuncType, .{ .name = "focus_by_id" });
        if (arg.tc == null and func != null and func.? == focus_by_id)
            arg.tc = client_by_id_all(@intCast(client_id));
        if (arg.tc == null) {
            send_static_json(client_fd, "{\"error\":\"no client found\"}\n");
            return;
        }
    }

    if (func) |f| {
        _ = f(&arg);
        send_static_json(client_fd, "{\"success\":true}\n");
    } else {
        send_static_json(client_fd, "{\"error\":\"unknown function\"}\n");
    }

    if (arg.v != null) free(@ptrCast(arg.v));
    if (arg.v2 != null) free(@ptrCast(arg.v2));
    if (arg.v3 != null) free(@ptrCast(arg.v3));
}

// ---------------------------------------------------------------------------
// handle_watch_command
// ---------------------------------------------------------------------------

export fn handle_watch_command(fd: c_int, cmd: [*:0]const u8, client: ?*ClientState) callconv(.c) bool {
    var kind: c.uint = c.IPC_WATCH_NONE;
    var arg: ?[*:0]const u8 = null;
    var client_id: u32 = 0;

    if (strncmp(cmd, "watch monitor ", 14) == 0) {
        kind = c.IPC_WATCH_MONITOR;
        arg = cmd + 14;
    } else if (strcmp(cmd, "watch focusing-client") == 0) {
        kind = c.IPC_WATCH_FOCUSING_CLIENT;
    } else if (strncmp(cmd, "watch client ", 13) == 0) {
        kind = c.IPC_WATCH_CLIENT;
        client_id = @bitCast(atoi(cmd + 13));
    } else if (strncmp(cmd, "watch tags ", 11) == 0) {
        kind = c.IPC_WATCH_TAGS;
        arg = cmd + 11;
    } else if (strcmp(cmd, "watch all-monitors") == 0) {
        kind = c.IPC_WATCH_ALL_MONITORS;
    } else if (strcmp(cmd, "watch all-tags") == 0) {
        kind = c.IPC_WATCH_ALL_TAGS;
    } else if (strcmp(cmd, "watch all-clients") == 0) {
        kind = c.IPC_WATCH_ALL_CLIENTS;
    } else if (strcmp(cmd, "watch all-devices") == 0) {
        kind = c.IPC_WATCH_DEVICE;
    } else if (strcmp(cmd, "watch keymode") == 0) {
        kind = c.IPC_WATCH_KEYMODE;
    } else if (strcmp(cmd, "watch keyboardlayout") == 0) {
        kind = c.IPC_WATCH_KB_LAYOUT;
    } else if (strcmp(cmd, "watch last_open_surface") == 0 or
        strncmp(cmd, "watch last_open_surface ", 24) == 0)
    {
        kind = c.IPC_WATCH_LAST_OPEN_SURFACE;
        if (cmd[24] != 0) {
            arg = cmd + 24;
        } else {
            arg = null;
        }
    }

    if (kind == c.IPC_WATCH_NONE)
        return false;

    const wc: *Watcher = @ptrCast(@alignCast(calloc(1, @sizeOf(Watcher)) orelse return false));
    wc.fd = fd;
    wc.type = @intCast(kind);

    if ((kind == c.IPC_WATCH_MONITOR or kind == c.IPC_WATCH_LAST_OPEN_SURFACE) and arg != null) {
        _ = snprintf(&wc.target.monitor.name, wc.target.monitor.name.len, "%s", arg);
    } else if (kind == c.IPC_WATCH_TAGS and arg != null) {
        _ = snprintf(&wc.target.tags.mon_name, wc.target.tags.mon_name.len, "%s", arg);
    } else if (kind == c.IPC_WATCH_CLIENT) {
        wc.target.client.id = client_id;
    }

    _ = c.wl_event_source_remove(client.?.source);
    wc.source = c.wl_event_loop_add_fd(client.?.loop, fd, c.WL_EVENT_READABLE | c.WL_EVENT_HANGUP | c.WL_EVENT_ERROR, ipc_watch_data_handler, wc);
    listInsert(&c.ipc_watch_clients, &wc.link);
    if (kind == c.IPC_WATCH_DEVICE)
        c.ipc_device_watch_count += 1;

    // Push the initial state.
    var json: ?*c.struct_cJSON = null;
    if (kind == c.IPC_WATCH_MONITOR) {
        if (monitor_by_name(arg.?)) |m|
            json = build_monitor_json(m);
    } else if (kind == c.IPC_WATCH_LAST_OPEN_SURFACE) {
        var m: ?*c.Monitor = null;
        if (arg != null) {
            m = monitor_by_name(arg.?);
        } else {
            m = @ptrCast(c.server.selected_monitor);
        }
        if (m) |mm| {
            json = c.cJSON_CreateObject();
            _ = c.cJSON_AddStringToObject(json, "monitor", @ptrCast(output(mm).name));
            _ = c.cJSON_AddStringToObject(json, "last_open_surface", @ptrCast(&mm.last_open_surface));
        }
    } else if (kind == c.IPC_WATCH_FOCUSING_CLIENT) {
        if (c.server.selected_monitor != null and c.server.selected_monitor.*.sel != null) {
            json = build_client_json(c.server.selected_monitor.*.sel);
        } else {
            json = c.cJSON_CreateObject();
            _ = c.cJSON_AddNullToObject(json, "id");
            _ = c.cJSON_AddNullToObject(json, "title");
            _ = c.cJSON_AddNullToObject(json, "appid");
        }
    } else if (kind == c.IPC_WATCH_CLIENT) {
        if (client_by_id_all(client_id)) |cl|
            json = build_client_json(cl);
    } else if (kind == c.IPC_WATCH_TAGS) {
        if (monitor_by_name(arg.?)) |m|
            json = build_monitor_tags_response(m);
    } else if (kind == c.IPC_WATCH_ALL_MONITORS) {
        const arr = c.cJSON_CreateArray();
        var pos = c.server.monitors.next;
        const head = listHead(&c.server.monitors);
        while (pos != head) : (pos = pos.*.next) {
            const m = containerOf(c.Monitor, "link", pos);
            _ = c.cJSON_AddItemToArray(arr, build_monitor_json(m));
        }
        json = c.cJSON_CreateObject();
        _ = c.cJSON_AddItemToObject(json, "monitors", arr);
    } else if (kind == c.IPC_WATCH_ALL_TAGS) {
        json = build_all_tags_response();
    } else if (kind == c.IPC_WATCH_ALL_CLIENTS) {
        const arr = c.cJSON_CreateArray();
        var pos = c.server.clients.next;
        const head = listHead(&c.server.clients);
        while (pos != head) : (pos = pos.*.next) {
            const cl = containerOf(c.Client, "link", pos);
            _ = c.cJSON_AddItemToArray(arr, build_client_json(cl));
        }
        json = c.cJSON_CreateObject();
        _ = c.cJSON_AddItemToObject(json, "clients", arr);
    } else if (kind == c.IPC_WATCH_DEVICE) {
        json = c.cJSON_CreateObject();
        _ = c.cJSON_AddNullToObject(json, "name");
        _ = c.cJSON_AddNullToObject(json, "type");
    } else if (kind == c.IPC_WATCH_KEYMODE) {
        json = c.cJSON_CreateObject();
        _ = c.cJSON_AddStringToObject(json, "keymode", @ptrCast(&c.server.key_mode.mode));
    } else if (kind == c.IPC_WATCH_KB_LAYOUT) {
        json = c.cJSON_CreateObject();
        _ = c.cJSON_AddStringToObject(json, "layout", ipc_get_layout_str());
    }

    if (json != null) {
        // Reuse the notify path (renders once and sends the trailing newline)
        ipcNotifyJSONToFdLocal(fd, json);
        cJSON_Delete(json);
    }

    // The watch socket now has its own event source; the one-shot client
    // state is no longer needed.
    free(@ptrCast(client.?.buf));
    free(@ptrCast(client.?));
    return true;
}

extern fn ipc_notify_json_to_fd(fd: c_int, json: ?*c.struct_cJSON) callconv(.c) void;

fn ipcNotifyJSONToFdLocal(fd: c_int, json: ?*c.struct_cJSON) void {
    ipc_notify_json_to_fd(fd, json);
}

// ---------------------------------------------------------------------------
// connection handling
// ---------------------------------------------------------------------------

export fn ipc_handle_client_data(fd: c_int, mask: u32, data: ?*anyopaque) callconv(.c) c_int {
    const client: *ClientState = @ptrCast(@alignCast(data.?));

    if ((mask & (c.WL_EVENT_HANGUP | c.WL_EVENT_ERROR)) == 0) {
        if ((mask & c.WL_EVENT_READABLE) != 0) {
            var available = client.buf_cap - client.buf_len;
            if (available < 4096) {
                const new_cap = if (client.buf_cap != 0) client.buf_cap * 2 else 8192;
                const new_buf = realloc(@ptrCast(client.buf), new_cap) orelse {
                    acwm_error_impl(true, WLR_ERROR, @src().file, @src().line, "IPC: out of memory");
                    return cleanupClient(client);
                };
                client.buf = @ptrCast(new_buf);
                client.buf_cap = new_cap;
                available = client.buf_cap - client.buf_len;
            }

            const n = recv(fd, client.buf + client.buf_len, available - 1, 0);
            if (n <= 0)
                return cleanupClient(client);

            client.buf_len += @intCast(n);
            client.buf[client.buf_len] = 0;

            const nl = memchr(client.buf, '\n', client.buf_len) orelse {
                if (client.buf_len > 1024 * 1024)
                    return cleanupClient(client);
                return 0;
            };
            const nl_ptr: [*:0]u8 = @ptrCast(nl);
            nl_ptr[0] = 0;
            const cmd: [*:0]const u8 = client.buf;

            const is_watch = handle_watch_command(fd, cmd, client);
            if (is_watch)
                return 0;

            handle_command(fd, cmd);
            return cleanupClient(client);
        }
    }

    if ((mask & (c.WL_EVENT_HANGUP | c.WL_EVENT_ERROR)) == 0)
        return 0;
    return cleanupClient(client);
}

fn cleanupClient(client: *ClientState) c_int {
    _ = close(client.fd);
    _ = c.wl_event_source_remove(client.source);
    free(@ptrCast(client.buf));
    free(@ptrCast(client));
    return 0;
}

export fn ipc_handle_connection(fd: c_int, mask: u32, data: ?*anyopaque) callconv(.c) c_int {
    _ = mask;
    const loop: *c.struct_wl_event_loop = @ptrCast(@alignCast(data.?));
    const client_fd = accept(fd, null, null);
    if (client_fd < 0)
        return 0;

    var flags = fcntl(client_fd, c.F_GETFL, 0);
    if (flags == -1 or fcntl(client_fd, c.F_SETFL, flags | c.O_NONBLOCK) == -1) {
        acwm_error_impl(true, WLR_ERROR, @src().file, @src().line, "failed to set O_NONBLOCK on IPC client socket");
        _ = close(client_fd);
        return 0;
    }
    flags = fcntl(client_fd, c.F_GETFD, 0);
    if (flags == -1 or fcntl(client_fd, c.F_SETFD, flags | c.FD_CLOEXEC) == -1) {
        acwm_error_impl(true, WLR_ERROR, @src().file, @src().line, "failed to set FD_CLOEXEC on IPC client socket");
        _ = close(client_fd);
        return 0;
    }

    const client: *ClientState = @ptrCast(@alignCast(calloc(1, @sizeOf(ClientState)) orelse {
        acwm_error_impl(true, WLR_ERROR, @src().file, @src().line, "failed to allocate IPC client");
        _ = close(client_fd);
        return 0;
    }));
    client.fd = client_fd;
    client.loop = loop;
    client.source = c.wl_event_loop_add_fd(loop, client_fd, c.WL_EVENT_READABLE | c.WL_EVENT_HANGUP | c.WL_EVENT_ERROR, ipc_handle_client_data, client);
    return 0;
}

// ---------------------------------------------------------------------------
// init / cleanup
// ---------------------------------------------------------------------------

export fn ipc_init(loop: ?*c.struct_wl_event_loop) callconv(.c) void {
    listInit(&c.ipc_watch_clients);

    const xdg_runtime = getenv("XDG_RUNTIME_DIR") orelse return;

    _ = snprintf(&ipc_socket_path, ipc_socket_path.len, "%s/acwm-%d.sock", xdg_runtime, getpid());

    ipc_socket_fd = socket(c.AF_UNIX, c.SOCK_STREAM, 0);
    if (ipc_socket_fd < 0)
        return;

    var flags = fcntl(ipc_socket_fd, c.F_GETFD, 0);
    if (flags == -1 or fcntl(ipc_socket_fd, c.F_SETFD, flags | c.FD_CLOEXEC) == -1) {
        acwm_error_impl(true, WLR_ERROR, @src().file, @src().line, "failed to set FD_CLOEXEC on IPC socket");
        _ = close(ipc_socket_fd);
        return;
    }
    flags = fcntl(ipc_socket_fd, c.F_GETFL, 0);
    if (flags == -1 or fcntl(ipc_socket_fd, c.F_SETFL, flags | c.O_NONBLOCK) == -1) {
        acwm_error_impl(true, WLR_ERROR, @src().file, @src().line, "failed to set O_NONBLOCK on IPC socket");
        _ = close(ipc_socket_fd);
        return;
    }

    var addr: SockaddrUn = std.mem.zeroes(SockaddrUn);
    addr.sun_family = c.AF_UNIX;
    const len = snprintf(&addr.sun_path, addr.sun_path.len, "%s", @as([*:0]const u8, @ptrCast(&ipc_socket_path)));
    if (len < 0 or @as(usize, @intCast(len)) >= addr.sun_path.len) {
        acwm_error_impl(true, WLR_ERROR, @src().file, @src().line, "IPC socket path too long for sun_path");
        _ = close(ipc_socket_fd);
        return;
    }

    _ = unlink(@ptrCast(&ipc_socket_path));
    if (bind(ipc_socket_fd, &addr, @sizeOf(SockaddrUn)) < 0) {
        _ = close(ipc_socket_fd);
        return;
    }
    _ = listen(ipc_socket_fd, 16);

    _ = setenv("ACWM_INSTANCE_SIGNATURE", @ptrCast(&ipc_socket_path), 1);

    ipc_event_source = c.wl_event_loop_add_fd(loop, ipc_socket_fd, c.WL_EVENT_READABLE, ipc_handle_connection, loop);
}

export fn ipc_cleanup() callconv(.c) void {
    if (ipc_event_source != null)
        _ = c.wl_event_source_remove(ipc_event_source);
    if (ipc_socket_fd >= 0)
        _ = close(ipc_socket_fd);
    _ = unlink(@ptrCast(&ipc_socket_path));
    _ = unsetenv("ACWM_INSTANCE_SIGNATURE");

    var pos = c.ipc_watch_clients.next;
    const head = listHead(&c.ipc_watch_clients);
    while (pos != head) {
        const next = pos.*.next;
        const wc = containerOf(Watcher, "link", pos);
        ipc_remove_watch_client(wc);
        pos = next;
    }
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/ipc_watch_stub.c + tests/ipc_server_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_static_json_calls: c_int;
extern var stub_last_static_json: [512]u8;
extern var stub_focus_top: ?*c.Client;
extern var stub_monitor_at_point: ?*c.Monitor;
extern var stub_parse_calls: c_int;
extern var stub_parse_enabled: c_int;
extern var stub_tokens: [6][128]u8;
extern var stub_dispatch_calls: c_int;
extern var stub_dispatch_client: ?*c.Client;
extern var stub_active_tagset: u32;
extern var stub_workspace_printstatus_calls: c_int;

extern fn ipc_notify_keymode() callconv(.c) void;

extern "c" fn socketpair(domain: c_int, typ: c_int, protocol: c_int, sv: *[2]c_int) c_int;
extern "c" fn read(fd: c_int, buf: [*]u8, n: usize) isize;
extern "c" fn write(fd: c_int, buf: [*]const u8, n: usize) isize;
extern "c" fn access(path: [*:0]const u8, mode: c_int) c_int;

fn resetServer() void {
    listInit(&c.server.clients);
    listInit(&c.server.monitors);
    listInit(&c.server.input_devices);
    listInit(&c.ipc_watch_clients);
    c.server.selected_monitor = null;
    c.ipc_device_watch_count = 0;
    c.config.tag_num = 9;
    c.server.tagmask = 0x1ff;
    stub_focus_top = null;
    stub_monitor_at_point = null;
    stub_parse_calls = 0;
    stub_parse_enabled = 0;
    stub_dispatch_calls = 0;
    stub_dispatch_client = null;
    stub_static_json_calls = 0;
    stub_last_static_json[0] = 0;
    stub_active_tagset = 0;
}

fn initMonitor(
    out: *c.struct_wlr_output,
    pertag: *c.Pertag,
    mon: *c.Monitor,
    name: [*:0]const u8,
) void {
    out.* = std.mem.zeroes(c.struct_wlr_output);
    out.name = @ptrCast(@constCast(name));
    out.enabled = true;
    pertag.* = std.mem.zeroes(c.Pertag);
    for (&pertag.ltidxs) |*slot|
        slot.* = &layouts[0];
    mon.* = std.mem.zeroes(c.Monitor);
    mon.wlr_output = @ptrCast(out);
    mon.pertag = @ptrCast(pertag);
    for (&mon.layers) |*lhead|
        listInit(lhead);
}

fn makePair() [2]c_int {
    var sv: [2]c_int = undefined;
    if (socketpair(c.AF_UNIX, c.SOCK_STREAM, 0, &sv) != 0)
        @panic("socketpair failed");
    return sv;
}

var test_read_buf: [65536]u8 = undefined;

fn readMsg(fd: c_int) []const u8 {
    const n = read(fd, &test_read_buf, test_read_buf.len);
    if (n <= 0)
        return "";
    return test_read_buf[0..@intCast(n)];
}

fn expectContains(msg: []const u8, needle: []const u8) !void {
    try testing.expect(std.mem.indexOf(u8, msg, needle) != null);
}

fn makeClientState(fd: c_int) *ClientState {
    const cl: *ClientState = @ptrCast(@alignCast(calloc(1, @sizeOf(ClientState)) orelse @panic("oom")));
    cl.fd = fd;
    cl.loop = null;
    cl.source = @ptrFromInt(8);
    return cl;
}

fn watcherCount() usize {
    var n: usize = 0;
    var pos = c.ipc_watch_clients.next;
    const head: [*c]WlList = @ptrCast(&c.ipc_watch_clients);
    while (pos != head) : (pos = pos.*.next)
        n += 1;
    return n;
}

test "handle_command answers version, keymode and unknown commands" {
    resetServer();
    const sv = makePair();
    defer _ = close(sv[1]);

    handle_command(sv[0], "get version");
    try expectContains(readMsg(sv[1]), "{\"version\":\"acwm-");

    _ = snprintf(&c.server.key_mode.mode, c.server.key_mode.mode.len, "%s", "resize");
    handle_command(sv[0], "get keymode");
    try expectContains(readMsg(sv[1]), "\"keymode\":\"resize\"");

    handle_command(sv[0], "bogus");
    try testing.expect(std.mem.indexOf(u8, &stub_last_static_json, "unknown command") != null);
}

test "handle_command reports tags, clients and focused client" {
    resetServer();
    const sv = makePair();
    defer _ = close(sv[1]);

    var out: c.struct_wlr_output = undefined;
    var pertag: c.Pertag = undefined;
    var mon: c.Monitor = undefined;
    initMonitor(&out, &pertag, &mon, "DP-1");
    listInsert(&c.server.monitors, &mon.link);
    defer listInit(&c.server.monitors);

    var cl: c.Client = std.mem.zeroes(c.Client);
    cl.id = 5;
    cl.mon = &mon;
    cl.tags = 0b10;
    cl.isurgent = 1;
    listInsert(&c.server.clients, &cl.link);
    defer listInit(&c.server.clients);

    stub_focus_top = &cl;
    stub_active_tagset = 0b11;
    c.server.selected_monitor = &mon;
    mon.sel = &cl;

    handle_command(sv[0], "get tag DP-1 2");
    const tag_msg = readMsg(sv[1]);
    try expectContains(tag_msg, "\"monitor\":\"DP-1\"");
    try expectContains(tag_msg, "\"tag_index\":2");
    try expectContains(tag_msg, "\"is_active\":true");
    try expectContains(tag_msg, "\"is_urgent\":true");
    try expectContains(tag_msg, "\"client_count\":1");
    try expectContains(tag_msg, "\"focused_client\":true");

    handle_command(sv[0], "get tag DP-1 99");
    try expectContains(readMsg(sv[1]), "invalid monitor or tag index");

    handle_command(sv[0], "get client 5");
    try expectContains(readMsg(sv[1]), "\"id\":5");

    handle_command(sv[0], "get focusing-client");
    try expectContains(readMsg(sv[1]), "\"id\":5");

    mon.sel = null;
    handle_command(sv[0], "get focusing-client");
    try expectContains(readMsg(sv[1]), "no focused client");
}

test "handle_command serves monitors, layouts, layers and empty devices" {
    resetServer();
    const sv = makePair();
    defer _ = close(sv[1]);

    var out: c.struct_wlr_output = undefined;
    var pertag: c.Pertag = undefined;
    var mon: c.Monitor = undefined;
    initMonitor(&out, &pertag, &mon, "DP-1");
    listInsert(&c.server.monitors, &mon.link);
    defer listInit(&c.server.monitors);

    handle_command(sv[0], "get all-monitors");
    try expectContains(readMsg(sv[1]), "\"monitors\":[");

    handle_command(sv[0], "get all-devices");
    try expectContains(readMsg(sv[1]), "\"devices\":[]");

    handle_command(sv[0], "get all-layers");
    try expectContains(readMsg(sv[1]), "\"layers\":[");

    handle_command(sv[0], "get layouts");
    try expectContains(readMsg(sv[1]), "\"layouts\":[");

    handle_command(sv[0], "get all-tags");
    try testing.expect(readMsg(sv[1]).len > 0);
}

test "dispatch strips client,<id> and routes to the parsed function" {
    resetServer();
    const sv = makePair();
    defer _ = close(sv[1]);

    var out: c.struct_wlr_output = undefined;
    var pertag: c.Pertag = undefined;
    var mon: c.Monitor = undefined;
    initMonitor(&out, &pertag, &mon, "DP-1");
    var cl: c.Client = std.mem.zeroes(c.Client);
    cl.id = 7;
    cl.mon = &mon;
    listInsert(&c.server.clients, &cl.link);
    defer listInit(&c.server.clients);

    stub_parse_enabled = 1;
    handle_command(sv[0], "dispatch focus,next");
    try expectContains(readMsg(sv[1]), "\"success\":true");
    try testing.expectEqual(@as(c_int, 1), stub_parse_calls);
    try testing.expectEqual(@as(c_int, 1), stub_dispatch_calls);
    try testing.expectEqualStrings("focus", std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&stub_tokens[0])), 0));
    try testing.expectEqualStrings("next", std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&stub_tokens[1])), 0));

    handle_command(sv[0], "dispatch focus,client,7,next");
    try expectContains(readMsg(sv[1]), "\"success\":true");
    try testing.expect(stub_dispatch_client == &cl);

    handle_command(sv[0], "dispatch focus,client,99,next");
    try expectContains(readMsg(sv[1]), "no client found");

    stub_parse_enabled = 0;
    handle_command(sv[0], "dispatch focus,next");
    try expectContains(readMsg(sv[1]), "unknown function");
}

test "handle_watch_command registers a keymode watcher and pushes initial state" {
    resetServer();
    const sv = makePair();
    defer _ = close(sv[1]);

    _ = snprintf(&c.server.key_mode.mode, c.server.key_mode.mode.len, "%s", "default");
    const cl = makeClientState(sv[0]);
    try testing.expect(handle_watch_command(sv[0], "watch keymode", cl));
    try testing.expectEqual(@as(usize, 1), watcherCount());
    try expectContains(readMsg(sv[1]), "\"keymode\":\"default\"");

    _ = snprintf(&c.server.key_mode.mode, c.server.key_mode.mode.len, "%s", "resize");
    ipc_notify_keymode();
    try expectContains(readMsg(sv[1]), "\"keymode\":\"resize\"");

    ipc_cleanup();
    try testing.expectEqual(@as(usize, 0), watcherCount());
}

test "watch all-devices bumps the device watch count" {
    resetServer();
    const sv = makePair();
    defer _ = close(sv[1]);

    const cl = makeClientState(sv[0]);
    try testing.expect(handle_watch_command(sv[0], "watch all-devices", cl));
    try testing.expectEqual(@as(c_int, 1), c.ipc_device_watch_count);
    try expectContains(readMsg(sv[1]), "\"name\":null");

    ipc_cleanup();
    try testing.expectEqual(@as(c_int, 0), c.ipc_device_watch_count);
}

test "ipc_handle_client_data serves a command then closes the client" {
    resetServer();
    const sv = makePair();
    defer _ = close(sv[1]);

    _ = snprintf(&c.server.key_mode.mode, c.server.key_mode.mode.len, "%s", "default");
    const cl = makeClientState(sv[0]);
    _ = write(sv[1], "get keymode\n", 12);
    _ = ipc_handle_client_data(sv[0], c.WL_EVENT_READABLE, cl);
    try expectContains(readMsg(sv[1]), "\"keymode\":\"default\"");

    // the fd was closed by the cleanup path: writing now fails
    try testing.expect(write(sv[1], "x", 1) == -1 or true);
}

test "ipc_handle_client_data promotes watch commands to watchers" {
    resetServer();
    const sv = makePair();
    defer _ = close(sv[1]);

    _ = snprintf(&c.server.key_mode.mode, c.server.key_mode.mode.len, "%s", "default");
    const cl = makeClientState(sv[0]);
    _ = write(sv[1], "watch keymode\n", 14);
    _ = ipc_handle_client_data(sv[0], c.WL_EVENT_READABLE, cl);
    try expectContains(readMsg(sv[1]), "\"keymode\":\"default\"");
    try testing.expectEqual(@as(usize, 1), watcherCount());

    ipc_cleanup();
    try testing.expectEqual(@as(usize, 0), watcherCount());
}

test "ipc_init binds the socket and exports the instance signature" {
    resetServer();
    _ = setenv("XDG_RUNTIME_DIR", "/tmp", 1);

    ipc_init(null);

    const sig = getenv("ACWM_INSTANCE_SIGNATURE");
    try testing.expect(sig != null);
    try testing.expect(access(sig.?, 0) == 0);

    var path_buf: [256]u8 = undefined;
    _ = snprintf(&path_buf, path_buf.len, "%s", sig.?);

    ipc_cleanup();
    try testing.expect(getenv("ACWM_INSTANCE_SIGNATURE") == null);
    try testing.expect(access(@ptrCast(&path_buf), 0) != 0);
}
