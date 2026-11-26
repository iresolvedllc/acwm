//! Port of the IPC JSON builders from src/ipc/ipc.c (strangler-fig Phase 4,
//! slice 26).
//!
//! These functions are NOT filtered out of the C file (ipc.c still owns the
//! watch clients, command dispatcher and notifiers); instead the C twins are
//! #ifndef ACWM_ZIG_IPC_BUILDERS guarded, so the meson build keeps them while
//! the zig build links these Zig versions for every caller.
//!
//! Exports (same symbols):
//!   tags_mask_to_array, build_tags_json, monitor_active_tags,
//!   build_client_json, build_monitor_json, build_all_tags_entry,
//!   build_all_tags_response, build_monitor_tags_response,
//!   build_layouts_response, build_layers_response
//! Internal: layer_enum_str, client_output_name (build_all_clients_array is
//! only used by the command dispatcher and stays C for now).
//!
//! JSON is produced through the real cJSON library (translate-c module), and
//! the tests link libcjson and inspect the resulting trees.

const std = @import("std");
const c = @import("cc");

const TAG0_MASK: u32 = @intCast(c.TAG0_MASK);

extern fn get_monitor_active_tagset(m: *c.Monitor) callconv(.c) u32;
extern fn get_mon_curtag(m: *c.Monitor) callconv(.c) u32;
extern fn client_get_title(cl: *c.Client) callconv(.c) [*:0]const u8;
extern fn client_get_appid(cl: *c.Client) callconv(.c) [*:0]const u8;
extern fn client_is_group_member(cl: *const c.Client) callconv(.c) bool;
extern fn client_group_active(cl: *c.Client) callconv(.c) ?*c.Client;
extern fn ipc_get_layout_str() callconv(.c) [*:0]const u8;
extern var layouts: [14]c.Layout;

fn containerOf(comptime T: type, comptime link_field: []const u8, link: [*c]c.struct_wl_list) *T {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(T, link_field));
}

fn output(m: *c.Monitor) *c.struct_wlr_output {
    return @ptrCast(m.wlr_output);
}

fn addNum(obj: ?*c.struct_cJSON, comptime name: [:0]const u8, n: f64) void {
    _ = c.cJSON_AddNumberToObject(obj, name, n);
}

fn addInt(obj: ?*c.struct_cJSON, comptime name: [:0]const u8, n: i64) void {
    addNum(obj, name, @floatFromInt(n));
}

fn addBool(obj: ?*c.struct_cJSON, comptime name: [:0]const u8, b: bool) void {
    _ = c.cJSON_AddBoolToObject(obj, name, @intFromBool(b));
}

fn addStr(obj: ?*c.struct_cJSON, comptime name: [:0]const u8, s: ?[*:0]const u8) void {
    _ = c.cJSON_AddStringToObject(obj, name, s orelse "");
}

fn tagCount() usize {
    return @intCast(c.config.tag_num);
}

/// True/false for the C truthiness of an int32 field.
fn truthy(v: i32) bool {
    return v != 0;
}

fn visibleOn(cl: *c.Client, m: *c.Monitor) bool {
    return cl.mon == @as([*c]c.Monitor, @ptrCast(m)) and
        !truthy(cl.isminimized) and
        ((cl.tags & m.tagset[m.seltags]) != 0 or truthy(cl.isglobal) or truthy(cl.isunglobal));
}

// ---------------------------------------------------------------------------
// builders
// ---------------------------------------------------------------------------

export fn tags_mask_to_array(tag_mask: u32) callconv(.c) ?*c.struct_cJSON {
    const arr = c.cJSON_CreateArray();
    if ((tag_mask & TAG0_MASK) != 0)
        _ = c.cJSON_AddItemToArray(arr, c.cJSON_CreateNumber(0));
    var i: usize = 0;
    while (i < tagCount()) : (i += 1) {
        if ((tag_mask & (@as(u32, 1) << @intCast(i))) != 0)
            _ = c.cJSON_AddItemToArray(arr, c.cJSON_CreateNumber(@floatFromInt(i + 1)));
    }
    return arr;
}

export fn monitor_active_tags(m: *c.Monitor) callconv(.c) ?*c.struct_cJSON {
    const arr = c.cJSON_CreateArray();
    if (truthy(m.isoverview)) {
        _ = c.cJSON_AddItemToArray(arr, c.cJSON_CreateNumber(0));
        return arr;
    }
    const tagset = get_monitor_active_tagset(m);
    var i: usize = 0;
    while (i < tagCount()) : (i += 1) {
        if ((tagset & (@as(u32, 1) << @intCast(i))) != 0)
            _ = c.cJSON_AddItemToArray(arr, c.cJSON_CreateNumber(@floatFromInt(i + 1)));
    }
    return arr;
}

export fn build_tags_json(m: *c.Monitor) callconv(.c) ?*c.struct_cJSON {
    const tags_array = c.cJSON_CreateArray();
    const active_tagset = get_monitor_active_tagset(m);

    var tag: usize = 1;
    while (tag <= tagCount()) : (tag += 1) {
        var numclients: i64 = 0;
        var is_active = false;
        var is_urgent = false;
        const tag_bit: u32 = @as(u32, 1) << @intCast(tag - 1);
        if ((tag_bit & active_tagset) != 0)
            is_active = true;

        var pos = c.server.clients.next;
        const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
        while (pos != head) : (pos = pos.*.next) {
            const cl = containerOf(c.Client, "link", pos);
            if (cl.mon != @as([*c]c.Monitor, @ptrCast(m)))
                continue;
            if ((cl.tags & tag_bit & c.server.tagmask) == 0)
                continue;
            if (truthy(cl.isurgent))
                is_urgent = true;
            numclients += 1;
        }

        const tag_obj = c.cJSON_CreateObject();
        addInt(tag_obj, "index", @intCast(tag));
        addBool(tag_obj, "is_active", is_active);
        addBool(tag_obj, "is_urgent", is_urgent);
        addStr(tag_obj, "layout", @ptrCast(m.pertag.*.ltidxs[tag].*.symbol));
        addInt(tag_obj, "client_count", numclients);
        _ = c.cJSON_AddItemToArray(tags_array, tag_obj);
    }
    return tags_array;
}

export fn monitor_active_client(m: *c.Monitor) callconv(.c) ?*c.struct_cJSON {
    const obj = c.cJSON_CreateObject();
    if (m.sel == null) {
        _ = c.cJSON_AddNullToObject(obj, "id");
        _ = c.cJSON_AddNullToObject(obj, "title");
        _ = c.cJSON_AddNullToObject(obj, "appid");
        return obj;
    }
    const cl = m.sel;
    addInt(obj, "id", cl.*.id);
    addStr(obj, "title", client_get_title(cl));
    addStr(obj, "appid", client_get_appid(cl));
    return obj;
}

export fn build_all_tags_entry(m: *c.Monitor) callconv(.c) ?*c.struct_cJSON {
    const entry = c.cJSON_CreateObject();
    addStr(entry, "monitor", @ptrCast(output(m).name));
    _ = c.cJSON_AddItemToObject(entry, "tags", build_tags_json(m));
    return entry;
}

export fn build_all_tags_response() callconv(.c) ?*c.struct_cJSON {
    const arr = c.cJSON_CreateArray();
    var pos = c.server.monitors.next;
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.monitors);
    while (pos != head) : (pos = pos.*.next) {
        const m = containerOf(c.Monitor, "link", pos);
        _ = c.cJSON_AddItemToArray(arr, build_all_tags_entry(m));
    }
    const resp = c.cJSON_CreateObject();
    _ = c.cJSON_AddItemToObject(resp, "all_tags", arr);
    return resp;
}

export fn build_monitor_tags_response(m: *c.Monitor) callconv(.c) ?*c.struct_cJSON {
    const resp = c.cJSON_CreateObject();
    addStr(resp, "monitor", @ptrCast(output(m).name));
    _ = c.cJSON_AddItemToObject(resp, "tags", build_tags_json(m));
    _ = c.cJSON_AddItemToObject(resp, "active_tags", monitor_active_tags(m));
    return resp;
}

export fn build_layouts_response() callconv(.c) ?*c.struct_cJSON {
    const arr = c.cJSON_CreateArray();
    var i: usize = 0;
    while (i < layouts.len) : (i += 1) {
        const entry = c.cJSON_CreateObject();
        addStr(entry, "symbol", @ptrCast(layouts[i].symbol));
        addStr(entry, "name", @ptrCast(layouts[i].name));
        _ = c.cJSON_AddItemToArray(arr, entry);
    }
    const resp = c.cJSON_CreateObject();
    _ = c.cJSON_AddItemToObject(resp, "layouts", arr);
    return resp;
}

// zwlr_layer_shell_v1 layer values (protocol enum; not in the translate-c
// unit because the protocol header is generated).
const LAYER_BACKGROUND: u32 = 0;
const LAYER_BOTTOM: u32 = 1;
const LAYER_TOP: u32 = 2;
const LAYER_OVERLAY: u32 = 3;

fn layerEnumStr(layer: u32) [*:0]const u8 {
    return switch (layer) {
        LAYER_BACKGROUND => "background",
        LAYER_BOTTOM => "bottom",
        LAYER_TOP => "top",
        LAYER_OVERLAY => "overlay",
        else => "unknown",
    };
}

export fn build_layers_response() callconv(.c) ?*c.struct_cJSON {
    const arr = c.cJSON_CreateArray();
    var pos = c.server.monitors.next;
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.monitors);
    while (pos != head) : (pos = pos.*.next) {
        const m = containerOf(c.Monitor, "link", pos);
        var layer: usize = 0;
        while (layer < m.layers.len) : (layer += 1) {
            var lpos = m.layers[layer].next;
            const lhead: [*c]c.struct_wl_list = @ptrCast(&m.layers[layer]);
            while (lpos != lhead) : (lpos = lpos.*.next) {
                const l = containerOf(c.LayerSurface, "link", lpos);
                if (!truthy(l.mapped) or l.being_unmapped)
                    continue;
                const entry = c.cJSON_CreateObject();
                addStr(entry, "monitor", @ptrCast(output(m).name));
                addStr(entry, "layer", layerEnumStr(@intCast(layer)));
                const ns: ?[*:0]const u8 = if (l.layer_surface != null)
                    @ptrCast(l.layer_surface.*.namespace)
                else
                    null;
                addStr(entry, "name", ns);
                _ = c.cJSON_AddItemToArray(arr, entry);
            }
        }
    }
    const resp = c.cJSON_CreateObject();
    _ = c.cJSON_AddItemToObject(resp, "layers", arr);
    return resp;
}

fn clientOutputName(cl: *c.Client) [*:0]const u8 {
    if (cl.mon != null)
        return @ptrCast(output(@ptrCast(cl.mon)).name);
    const active = client_group_active(cl);
    if (active != null and active.?.mon != null)
        return @ptrCast(output(@ptrCast(active.?.mon)).name);
    return "";
}

export fn build_client_json(cl: *c.Client) callconv(.c) ?*c.struct_cJSON {
    const obj = c.cJSON_CreateObject();

    addInt(obj, "id", cl.id);
    addInt(obj, "pid", cl.pid);
    const ft_id: ?[*:0]const u8 = if (cl.ext_foreign_toplevel != null)
        @ptrCast(cl.ext_foreign_toplevel.*.identifier)
    else
        null;
    addStr(obj, "foreign_toplevel_id", ft_id);
    addStr(obj, "title", client_get_title(cl));
    addStr(obj, "appid", client_get_appid(cl));
    addStr(obj, "monitor", clientOutputName(cl));
    _ = c.cJSON_AddItemToObject(obj, "tags", tags_mask_to_array(cl.tags));
    addBool(obj, "is_xwayland", cl.type == @as(u32, c.X11));
    addBool(obj, "is_swallowing", cl.swallowing != null);
    addBool(obj, "is_swallowedby", cl.swallowdby != null);
    addBool(obj, "is_group", client_is_group_member(cl));
    addBool(obj, "is_group_focus", client_is_group_member(cl) and cl.is_group_focus);
    addBool(obj, "is_visible", cl.mon != null and visibleOn(cl, @ptrCast(cl.mon)));
    addBool(obj, "is_focused", cl.isfocusing);
    addBool(obj, "is_fullscreen", truthy(cl.isfullscreen));
    addBool(obj, "is_floating", truthy(cl.isfloating));
    addBool(obj, "is_maximized", truthy(cl.ismaximizescreen));
    addBool(obj, "is_global", truthy(cl.isglobal));
    addBool(obj, "is_unglobal", truthy(cl.isunglobal));
    addBool(obj, "is_overlay", truthy(cl.isoverlay));
    addBool(obj, "is_fakefullscreen", truthy(cl.isfakefullscreen));
    addBool(obj, "is_minimized", truthy(cl.isminimized));
    addBool(obj, "is_urgent", truthy(cl.isurgent));
    addBool(obj, "is_scratchpad", truthy(cl.is_in_scratchpad));
    addBool(obj, "is_namedscratchpad", truthy(cl.isnamedscratchpad));
    addInt(obj, "x", cl.geom.x);
    addInt(obj, "y", cl.geom.y);
    addInt(obj, "width", cl.geom.width);
    addInt(obj, "height", cl.geom.height);
    addNum(obj, "scroller_proportion", @floatCast(cl.scroller_proportion));
    return obj;
}

export fn build_monitor_json(m: *c.Monitor) callconv(.c) ?*c.struct_cJSON {
    const resp = c.cJSON_CreateObject();
    const out = output(m);
    const curtag = get_mon_curtag(m);
    const layout_idx = (@intFromPtr(m.pertag.*.ltidxs[curtag]) - @intFromPtr(&layouts[0])) / @sizeOf(c.Layout);

    addStr(resp, "name", @ptrCast(out.name));
    addBool(resp, "active", m == c.server.selected_monitor);
    addBool(resp, "is_hdr", m.is_hdr_enabling);
    addBool(resp, "is_vrr", m.is_vrr_enabling);
    addInt(resp, "x", m.m.x);
    addInt(resp, "y", m.m.y);
    addInt(resp, "width", m.m.width);
    addInt(resp, "height", m.m.height);
    addNum(resp, "scale", @floatCast(out.scale));
    addInt(resp, "layout_index", @intCast(layout_idx));
    addStr(resp, "layout_symbol", @ptrCast(m.pertag.*.ltidxs[curtag].*.symbol));
    addStr(resp, "last_open_surface", @ptrCast(&m.last_open_surface));
    _ = c.cJSON_AddItemToObject(resp, "tag_num", c.cJSON_CreateNumber(@floatFromInt(c.config.tag_num)));
    _ = c.cJSON_AddItemToObject(resp, "hide_clients", c.cJSON_CreateNumber(@floatFromInt(m.hide_clients)));
    _ = c.cJSON_AddItemToObject(resp, "tags", build_tags_json(m));
    _ = c.cJSON_AddItemToObject(resp, "active_tags", monitor_active_tags(m));
    _ = c.cJSON_AddItemToObject(resp, "active_client", monitor_active_client(m));
    _ = c.cJSON_AddItemToObject(resp, "keymode", c.cJSON_CreateString(@ptrCast(&c.server.key_mode.mode)));
    _ = c.cJSON_AddItemToObject(resp, "keyboardlayout", c.cJSON_CreateString(ipc_get_layout_str()));
    return resp;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: see tests/ipc_builders_stub.c; real libcjson)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_active_tagset: u32;
extern var stub_curtag: u32;
extern var stub_title: [128]u8;
extern var stub_appid: [128]u8;
extern var stub_is_group_member: c_int;
extern var stub_layout_str: [32]u8;

extern "c" fn cJSON_GetArraySize(array: ?*c.struct_cJSON) c_int;
extern "c" fn cJSON_GetArrayItem(array: ?*c.struct_cJSON, index: c_int) ?*c.struct_cJSON;
extern "c" fn cJSON_GetObjectItemCaseSensitive(obj: ?*c.struct_cJSON, key: [*:0]const u8) ?*c.struct_cJSON;
extern "c" fn cJSON_GetNumberValue(node: ?*const c.struct_cJSON) f64;
extern "c" fn cJSON_GetStringValue(node: ?*const c.struct_cJSON) ?[*:0]const u8;
extern "c" fn cJSON_IsTrue(node: ?*const c.struct_cJSON) c_int;
extern "c" fn cJSON_Delete(obj: ?*c.struct_cJSON) void;

fn item(obj: ?*c.struct_cJSON, comptime name: [:0]const u8) ?*c.struct_cJSON {
    return cJSON_GetObjectItemCaseSensitive(obj, name);
}

fn numOf(node: ?*c.struct_cJSON) f64 {
    return cJSON_GetNumberValue(node);
}

fn strOf(node: ?*c.struct_cJSON) []const u8 {
    const s = cJSON_GetStringValue(node) orelse return "";
    return std.mem.span(s);
}

fn isTrue(node: ?*c.struct_cJSON) bool {
    return cJSON_IsTrue(node) != 0;
}

fn arrLen(node: ?*c.struct_cJSON) usize {
    return @intCast(cJSON_GetArraySize(node));
}

fn arrAt(node: ?*c.struct_cJSON, i: usize) ?*c.struct_cJSON {
    return cJSON_GetArrayItem(node, @intCast(i));
}

fn resetStub() void {
    stub_active_tagset = 0;
    stub_curtag = 0;
    stub_is_group_member = 0;
    @memcpy(stub_title[0..5], "Title");
    stub_title[5] = 0;
    @memcpy(stub_appid[0..3], "app");
    stub_appid[3] = 0;
    @memcpy(stub_layout_str[0..2], "us");
    stub_layout_str[2] = 0;
}

var name_buf: [4:0]u8 = "DP-1".*;

fn makeOutput() c.struct_wlr_output {
    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    out.name = @ptrCast(&name_buf);
    out.scale = 1.25;
    out.enabled = true;
    return out;
}

test "tags_mask_to_array includes tag 0 and set bits" {
    c.config.tag_num = 4;

    const plain = tags_mask_to_array(0b101);
    defer cJSON_Delete(plain);
    try testing.expectEqual(@as(usize, 2), arrLen(plain));
    try testing.expectEqual(@as(f64, 1), numOf(arrAt(plain, 0)));
    try testing.expectEqual(@as(f64, 3), numOf(arrAt(plain, 1)));

    const with_zero = tags_mask_to_array(TAG0_MASK | 0b10);
    defer cJSON_Delete(with_zero);
    try testing.expectEqual(@as(usize, 2), arrLen(with_zero));
    try testing.expectEqual(@as(f64, 0), numOf(arrAt(with_zero, 0)));
    try testing.expectEqual(@as(f64, 2), numOf(arrAt(with_zero, 1)));
}

test "monitor_active_tags: overview yields [0], otherwise the tagset" {
    c.config.tag_num = 3;
    var out = makeOutput();
    var m: c.Monitor = std.mem.zeroes(c.Monitor);
    m.wlr_output = @ptrCast(&out);

    resetStub();
    stub_active_tagset = 0b101;
    const tags = monitor_active_tags(&m);
    defer cJSON_Delete(tags);
    try testing.expectEqual(@as(usize, 2), arrLen(tags));
    try testing.expectEqual(@as(f64, 1), numOf(arrAt(tags, 0)));
    try testing.expectEqual(@as(f64, 3), numOf(arrAt(tags, 1)));

    m.isoverview = 1;
    const overview = monitor_active_tags(&m);
    defer cJSON_Delete(overview);
    try testing.expectEqual(@as(usize, 1), arrLen(overview));
    try testing.expectEqual(@as(f64, 0), numOf(arrAt(overview, 0)));
}

test "build_tags_json reports activity, urgency and client counts" {
    resetStub();
    c.config.tag_num = 2;
    c.server.tagmask = 0b11;
    layouts[0].symbol = "T";
    layouts[1].symbol = "M";
    c.server.clients = std.mem.zeroes(c.struct_wl_list);
    listInit(&c.server.clients);

    var out = makeOutput();
    var pertag: c.Pertag = std.mem.zeroes(c.Pertag);
    pertag.ltidxs[0] = &layouts[0];
    pertag.ltidxs[1] = &layouts[0];
    pertag.ltidxs[2] = &layouts[1];
    var m: c.Monitor = std.mem.zeroes(c.Monitor);
    m.wlr_output = @ptrCast(&out);
    m.pertag = @ptrCast(&pertag);
    stub_active_tagset = 0b1;

    var cl: c.Client = std.mem.zeroes(c.Client);
    cl.mon = @ptrCast(&m);
    cl.tags = 0b1;
    cl.isurgent = 1;
    listInsert(&c.server.clients, &cl.link);
    defer listInit(&c.server.clients);

    const tags = build_tags_json(&m);
    defer cJSON_Delete(tags);
    try testing.expectEqual(@as(usize, 2), arrLen(tags));

    const first = arrAt(tags, 0);
    try testing.expectEqual(@as(f64, 1), numOf(item(first, "index")));
    try testing.expect(isTrue(item(first, "is_active")));
    try testing.expect(isTrue(item(first, "is_urgent")));
    try testing.expectEqualStrings("T", strOf(item(first, "layout")));
    try testing.expectEqual(@as(f64, 1), numOf(item(first, "client_count")));

    const second = arrAt(tags, 1);
    try testing.expectEqual(@as(f64, 2), numOf(item(second, "index")));
    try testing.expect(!isTrue(item(second, "is_active")));
    try testing.expect(!isTrue(item(second, "is_urgent")));
    try testing.expectEqualStrings("M", strOf(item(second, "layout")));
    try testing.expectEqual(@as(f64, 0), numOf(item(second, "client_count")));
}

test "build_client_json exposes identity, flags, geometry and tags" {
    resetStub();
    c.config.tag_num = 2;
    listInit(&c.server.clients);

    var out = makeOutput();
    var m: c.Monitor = std.mem.zeroes(c.Monitor);
    m.wlr_output = @ptrCast(&out);
    m.tagset[0] = 0b1;
    m.seltags = 0;

    var cl: c.Client = std.mem.zeroes(c.Client);
    cl.id = 7;
    cl.pid = 1234;
    cl.type = c.X11;
    cl.tags = 0b1;
    cl.mon = @ptrCast(&m);
    cl.isfocusing = true;
    cl.isfloating = 1;
    cl.geom = .{ .x = 10, .y = 20, .width = 800, .height = 600 };
    cl.scroller_proportion = 0.5;

    const obj = build_client_json(&cl);
    defer cJSON_Delete(obj);
    try testing.expectEqual(@as(f64, 7), numOf(item(obj, "id")));
    try testing.expectEqual(@as(f64, 1234), numOf(item(obj, "pid")));
    try testing.expectEqualStrings("Title", strOf(item(obj, "title")));
    try testing.expectEqualStrings("app", strOf(item(obj, "appid")));
    try testing.expectEqualStrings("DP-1", strOf(item(obj, "monitor")));
    try testing.expect(isTrue(item(obj, "is_xwayland")));
    try testing.expect(!isTrue(item(obj, "is_group")));
    try testing.expect(isTrue(item(obj, "is_visible")));
    try testing.expect(isTrue(item(obj, "is_focused")));
    try testing.expect(isTrue(item(obj, "is_floating")));
    try testing.expect(!isTrue(item(obj, "is_fullscreen")));
    try testing.expectEqual(@as(f64, 10), numOf(item(obj, "x")));
    try testing.expectEqual(@as(f64, 20), numOf(item(obj, "y")));
    try testing.expectEqual(@as(f64, 800), numOf(item(obj, "width")));
    try testing.expectEqual(@as(f64, 600), numOf(item(obj, "height")));
    try testing.expectEqual(@as(f64, 0.5), numOf(item(obj, "scroller_proportion")));

    const tags = item(obj, "tags");
    try testing.expectEqual(@as(usize, 1), arrLen(tags));
    try testing.expectEqual(@as(f64, 1), numOf(arrAt(tags, 0)));
}

test "build_monitor_json carries layout, tags and key state" {
    resetStub();
    c.config.tag_num = 2;
    c.server.tagmask = 0b11;
    listInit(&c.server.monitors);

    var out = makeOutput();
    var pertag: c.Pertag = std.mem.zeroes(c.Pertag);
    pertag.ltidxs[0] = &layouts[0];
    pertag.ltidxs[1] = &layouts[0];
    pertag.ltidxs[2] = &layouts[0];
    var m: c.Monitor = std.mem.zeroes(c.Monitor);
    m.wlr_output = @ptrCast(&out);
    m.pertag = @ptrCast(&pertag);
    m.m = .{ .x = 0, .y = 0, .width = 1920, .height = 1080 };
    m.hide_clients = 3;
    @memcpy(m.last_open_surface[0..4], "foot");
    layouts[0].symbol = "T";
    c.server.selected_monitor = @ptrCast(&m);
    _ = c.snprintf(&c.server.key_mode.mode, c.server.key_mode.mode.len, "%s", "default");

    const obj = build_monitor_json(&m);
    defer cJSON_Delete(obj);
    try testing.expectEqualStrings("DP-1", strOf(item(obj, "name")));
    try testing.expect(isTrue(item(obj, "active")));
    try testing.expectEqual(@as(f64, 1.25), numOf(item(obj, "scale")));
    try testing.expectEqual(@as(f64, 0), numOf(item(obj, "layout_index")));
    try testing.expectEqualStrings("T", strOf(item(obj, "layout_symbol")));
    try testing.expectEqualStrings("foot", strOf(item(obj, "last_open_surface")));
    try testing.expectEqual(@as(f64, 2), numOf(item(obj, "tag_num")));
    try testing.expectEqual(@as(f64, 3), numOf(item(obj, "hide_clients")));
    try testing.expectEqualStrings("default", strOf(item(obj, "keymode")));
    try testing.expectEqualStrings("us", strOf(item(obj, "keyboardlayout")));
    try testing.expectEqual(@as(usize, 2), arrLen(item(obj, "tags")));
    try testing.expectEqual(@as(usize, 0), arrLen(item(obj, "active_tags")));
    // no selected client -> nulls
    const sel = item(obj, "active_client");
    try testing.expectEqualStrings("", strOf(item(sel, "title")));
}

test "build_layouts_response lists symbols and names" {
    layouts[0].symbol = "T";
    layouts[0].name = "tile";
    layouts[1].symbol = "M";
    layouts[1].name = "monocle";

    const resp = build_layouts_response();
    defer cJSON_Delete(resp);
    const arr = item(resp, "layouts");
    try testing.expectEqual(@as(usize, 14), arrLen(arr));
    try testing.expectEqualStrings("T", strOf(item(arrAt(arr, 0), "symbol")));
    try testing.expectEqualStrings("tile", strOf(item(arrAt(arr, 0), "name")));
    try testing.expectEqualStrings("M", strOf(item(arrAt(arr, 1), "symbol")));
    try testing.expectEqualStrings("monocle", strOf(item(arrAt(arr, 1), "name")));
}

test "build_layers_response only includes mapped layer surfaces" {
    listInit(&c.server.monitors);
    var out = makeOutput();
    var m: c.Monitor = std.mem.zeroes(c.Monitor);
    m.wlr_output = @ptrCast(&out);
    // list heads are self-referential: initialise them in place
    for (&m.layers) |*l| listInit(l);
    listInsert(&c.server.monitors, &m.link);
    defer listInit(&c.server.monitors);

    var surface: c.struct_wlr_layer_surface_v1 = std.mem.zeroes(c.struct_wlr_layer_surface_v1);
    var ns: [6:0]u8 = "waybar".*;
    surface.namespace = @ptrCast(&ns);

    var mapped: c.LayerSurface = std.mem.zeroes(c.LayerSurface);
    mapped.mapped = 1;
    mapped.layer_surface = @ptrCast(&surface);
    listInsert(&m.layers[2], &mapped.link); // top layer

    var hidden: c.LayerSurface = std.mem.zeroes(c.LayerSurface);
    hidden.mapped = 0;
    hidden.layer_surface = @ptrCast(&surface);
    listInsert(&m.layers[2], &hidden.link);

    const resp = build_layers_response();
    defer cJSON_Delete(resp);
    const arr = item(resp, "layers");
    try testing.expectEqual(@as(usize, 1), arrLen(arr));
    const entry = arrAt(arr, 0);
    try testing.expectEqualStrings("DP-1", strOf(item(entry, "monitor")));
    try testing.expectEqualStrings("top", strOf(item(entry, "layer")));
    try testing.expectEqualStrings("waybar", strOf(item(entry, "name")));
}

test "all-tags responses wrap the per-monitor entries" {
    resetStub();
    c.config.tag_num = 1;
    layouts[0].symbol = "T";
    listInit(&c.server.monitors);
    listInit(&c.server.clients);

    var out = makeOutput();
    var pertag: c.Pertag = std.mem.zeroes(c.Pertag);
    pertag.ltidxs[0] = &layouts[0];
    pertag.ltidxs[1] = &layouts[0];
    var m: c.Monitor = std.mem.zeroes(c.Monitor);
    m.wlr_output = @ptrCast(&out);
    m.pertag = @ptrCast(&pertag);
    listInsert(&c.server.monitors, &m.link);
    defer listInit(&c.server.monitors);

    const all = build_all_tags_response();
    defer cJSON_Delete(all);
    const arr = item(all, "all_tags");
    try testing.expectEqual(@as(usize, 1), arrLen(arr));
    const entry = arrAt(arr, 0);
    try testing.expectEqualStrings("DP-1", strOf(item(entry, "monitor")));
    try testing.expectEqual(@as(usize, 1), arrLen(item(entry, "tags")));

    const single = build_monitor_tags_response(&m);
    defer cJSON_Delete(single);
    try testing.expectEqualStrings("DP-1", strOf(item(single, "monitor")));
    try testing.expectEqual(@as(usize, 1), arrLen(item(single, "tags")));
    try testing.expectEqual(@as(usize, 0), arrLen(item(single, "active_tags")));
}

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
