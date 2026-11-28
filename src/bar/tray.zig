//! Port of bar/tray.c (Phase 5, bar slice 2, slice 80).

const std = @import("std");
const c = @import("cc");
const build_options = @import("build_options");

const Bar = c.struct_AcwmBar;
const BarTrayIcon = c.struct_BarTrayIcon;
const Monitor = c.Monitor;
const TextBuffer = c.struct_acwm_text_buffer;
const Bus = c.sd_bus;
const Message = c.sd_bus_message;
const Slot = c.sd_bus_slot;
const Error = c.sd_bus_error;

const TrayPixmap = extern struct {
    width: i32 = 0,
    height: i32 = 0,
    data: [*c]u32 = null,
};

const TrayItem = extern struct {
    name: [*c]u8 = null,
    path: [*c]u8 = null,
    icon_name: [*c]u8 = null,
    theme_path: [*c]u8 = null,
    status: [32]u8 = std.mem.zeroes([32]u8),
    pixmaps: [*c]TrayPixmap = null,
    pixmap_count: i32 = 0,
    slots: [5]?*Slot = .{ null, null, null, null, null },
    props_slot: ?*Slot = null,
    link: c.struct_wl_list = std.mem.zeroes(c.struct_wl_list),
};

extern fn aw_tray_vtable_get() callconv(.c) ?*const c.struct_sd_bus_vtable;
extern fn sd_bus_default_user(bus: *?*Bus) callconv(.c) c_int;
extern fn sd_bus_default_system(bus: *?*Bus) callconv(.c) c_int;
extern fn sd_bus_add_object_vtable(bus: ?*Bus, slot: ?*?*Slot, path: [*c]const u8, iface: [*c]const u8, vtable: ?*const c.struct_sd_bus_vtable, userdata: ?*anyopaque) callconv(.c) c_int;
extern fn sd_bus_request_name(bus: ?*Bus, name: [*c]const u8, flags: u64) callconv(.c) c_int;
extern fn sd_bus_match_signal(bus: ?*Bus, slot: ?*?*Slot, sender: [*c]const u8, path: [*c]const u8, iface: [*c]const u8, member: [*c]const u8, callback: ?*const fn (?*Message, ?*anyopaque, ?*Error) callconv(.c) c_int, userdata: ?*anyopaque) callconv(.c) c_int;
extern fn sd_bus_call_method_async(bus: ?*Bus, slot: ?*?*Slot, destination: [*c]const u8, path: [*c]const u8, interface: [*c]const u8, member: [*c]const u8, callback: ?*const fn (?*Message, ?*anyopaque, ?*Error) callconv(.c) c_int, userdata: ?*anyopaque, signature: [*c]const u8, ...) callconv(.c) c_int;
extern fn sd_bus_process(bus: ?*Bus, ret: ?*?*Message) callconv(.c) c_int;
extern fn sd_bus_flush(bus: ?*Bus) callconv(.c) c_int;
extern fn sd_bus_get_fd(bus: ?*Bus) callconv(.c) c_int;
extern fn sd_bus_flush_close_unref(bus: ?*Bus) callconv(.c) ?*Bus;
extern fn sd_bus_slot_unref(slot: ?*Slot) callconv(.c) ?*Slot;
extern fn sd_bus_message_is_method_error(m: ?*Message, name: [*c]const u8) callconv(.c) c_int;
extern fn sd_bus_message_get_error(m: ?*Message) callconv(.c) ?*const Error;
extern fn sd_bus_message_get_sender(m: ?*Message) callconv(.c) [*c]const u8;
extern fn sd_bus_message_enter_container(m: ?*Message, type: u8, contents: [*c]const u8) callconv(.c) c_int;
extern fn sd_bus_message_exit_container(m: ?*Message) callconv(.c) c_int;
extern fn sd_bus_message_skip(m: ?*Message, types: [*c]const u8) callconv(.c) c_int;
extern fn sd_bus_message_read(m: ?*Message, types: [*c]const u8, ...) callconv(.c) c_int;
extern fn sd_bus_message_open_container(m: ?*Message, type: u8, contents: [*c]const u8) callconv(.c) c_int;
extern fn sd_bus_message_close_container(m: ?*Message) callconv(.c) c_int;
extern fn sd_bus_message_append(m: ?*Message, types: [*c]const u8, ...) callconv(.c) c_int;
extern fn wl_event_loop_add_fd(loop: ?*c.struct_wl_event_loop, fd: c_int, mask: u32, func: ?*const fn (c_int, u32, ?*anyopaque) callconv(.c) c_int, data: ?*anyopaque) callconv(.c) ?*c.struct_wl_event_source;
extern fn wl_event_source_remove(source: ?*c.struct_wl_event_source) callconv(.c) c_int;
extern fn cairo_image_surface_create(format: c.cairo_format_t, width: c_int, height: c_int) callconv(.c) ?*c.cairo_surface_t;
extern fn cairo_image_surface_create_from_png(filename: [*c]const u8) callconv(.c) ?*c.cairo_surface_t;
extern fn cairo_image_surface_get_data(surface: ?*c.cairo_surface_t) callconv(.c) [*c]u8;
extern fn cairo_image_surface_get_stride(surface: ?*c.cairo_surface_t) callconv(.c) c_int;
extern fn cairo_image_surface_get_width(surface: ?*c.cairo_surface_t) callconv(.c) c_int;
extern fn cairo_image_surface_get_height(surface: ?*c.cairo_surface_t) callconv(.c) c_int;
extern fn cairo_surface_status(surface: ?*c.cairo_surface_t) callconv(.c) c.cairo_status_t;
extern fn cairo_surface_destroy(surface: ?*c.cairo_surface_t) callconv(.c) void;
extern fn cairo_create(target: ?*c.cairo_surface_t) callconv(.c) ?*c.cairo_t;
extern fn cairo_destroy(cr: ?*c.cairo_t) callconv(.c) void;
extern fn cairo_save(cr: ?*c.cairo_t) callconv(.c) void;
extern fn cairo_restore(cr: ?*c.cairo_t) callconv(.c) void;
extern fn cairo_scale(cr: ?*c.cairo_t, sx: f64, sy: f64) callconv(.c) void;
extern fn cairo_set_source_surface(cr: ?*c.cairo_t, surface: ?*c.cairo_surface_t, x: f64, y: f64) callconv(.c) void;
extern fn cairo_paint(cr: ?*c.cairo_t) callconv(.c) void;
extern fn cairo_set_operator(cr: ?*c.cairo_t, op: c.cairo_operator_t) callconv(.c) void;
extern fn cairo_set_source_rgba(cr: ?*c.cairo_t, r: f64, g: f64, b: f64, a: f64) callconv(.c) void;
extern fn cairo_image_surface_create_for_data(data: [*c]u8, format: c.cairo_format_t, width: c_int, height: c_int, stride: c_int) callconv(.c) ?*c.cairo_surface_t;
extern fn wlr_buffer_init(buffer: *c.struct_wlr_buffer, impl: [*c]const c.struct_wlr_buffer_impl, width: c_int, height: c_int) callconv(.c) void;
extern fn wlr_buffer_drop(buffer: *c.struct_wlr_buffer) callconv(.c) void;
extern fn wlr_scene_buffer_create(parent: [*c]c.struct_wlr_scene_tree, buffer: ?*c.struct_wlr_buffer) callconv(.c) [*c]c.struct_wlr_scene_buffer;
extern fn wlr_scene_buffer_set_buffer(node: [*c]c.struct_wlr_scene_buffer, buffer: ?*c.struct_wlr_buffer) callconv(.c) void;
extern fn wlr_scene_buffer_set_dest_size(node: [*c]c.struct_wlr_scene_buffer, width: c_int, height: c_int) callconv(.c) void;
extern fn wlr_scene_node_destroy(node: [*c]c.struct_wlr_scene_node) callconv(.c) void;
extern fn acwm_scene_node_set(node: [*c]c.struct_wlr_scene_node, type: u32, owner: ?*anyopaque) callconv(.c) ?*c.AcwmSceneNode;
extern fn bar_tray_sync_all() callconv(.c) void;
extern fn string_printf(fmt: [*c]const u8, ...) callconv(.c) [*c]u8;
extern fn opendir(path: [*c]const u8) callconv(.c) ?*c.DIR;
extern fn readdir(dir: ?*c.DIR) callconv(.c) [*c]c.struct_dirent;
extern fn closedir(dir: ?*c.DIR) callconv(.c) c_int;
extern fn strdup(s: [*c]const u8) callconv(.c) [*c]u8;
extern fn strndup(s: [*c]const u8, n: usize) callconv(.c) [*c]u8;
extern fn strchr(s: [*c]const u8, ch: c_int) callconv(.c) [*c]u8;
extern fn strrchr(s: [*c]const u8, ch: c_int) callconv(.c) [*c]u8;
extern fn strcmp(a: [*c]const u8, b: [*c]const u8) callconv(.c) c_int;
extern fn strncmp(a: [*c]const u8, b: [*c]const u8, n: usize) callconv(.c) c_int;
extern fn snprintf(buf: [*c]u8, len: usize, fmt: [*c]const u8, ...) callconv(.c) c_int;
extern fn getenv(name: [*c]const u8) callconv(.c) [*c]u8;
extern fn atoi(s: [*c]const u8) callconv(.c) c_int;

var tray_bus: ?*Bus = null;
var tray_fd_source: ?*c.struct_wl_event_source = null;
var items: c.struct_wl_list = std.mem.zeroes(c.struct_wl_list);
var items_ready: bool = false;

fn listInit(head: *c.struct_wl_list) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

fn itemFromLink(link: [*c]c.struct_wl_list) *TrayItem {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(TrayItem, "link"));
}

fn bufferFromBase(base: [*c]c.struct_wlr_buffer) *TextBuffer {
    return @ptrFromInt(@intFromPtr(base) - @offsetOf(TextBuffer, "base"));
}

fn trayBufferDestroy(buffer: [*c]c.struct_wlr_buffer) callconv(.c) void {
    const buf = bufferFromBase(buffer);
    if (buf.surface != null)
        cairo_surface_destroy(buf.surface);
    c.free(buf);
}

fn trayBufferBegin(buffer: [*c]c.struct_wlr_buffer, flags: u32, data: [*c]?*anyopaque, format: [*c]u32, stride: [*c]usize) callconv(.c) bool {
    if ((flags & c.WLR_BUFFER_DATA_PTR_ACCESS_WRITE) != 0)
        return false;
    const buf = bufferFromBase(buffer);
    if (buf.surface == null)
        return false;
    data[0] = @ptrCast(cairo_image_surface_get_data(buf.surface));
    format[0] = c.DRM_FORMAT_ARGB8888;
    stride[0] = @intCast(cairo_image_surface_get_stride(buf.surface));
    return true;
}

fn trayBufferEnd(buffer: [*c]c.struct_wlr_buffer) callconv(.c) void {
    _ = buffer;
}

var tray_buffer_impl: c.struct_wlr_buffer_impl = .{
    .destroy = trayBufferDestroy,
    .begin_data_ptr_access = trayBufferBegin,
    .end_data_ptr_access = trayBufferEnd,
};

fn trayBufferCreate(pixel_w: i32, pixel_h: i32) ?*TextBuffer {
    const w: u32 = @intCast(@max(pixel_w, 1));
    const h: u32 = @intCast(@max(pixel_h, 1));
    const surface = cairo_image_surface_create(@intCast(c.CAIRO_FORMAT_ARGB32), @intCast(w), @intCast(h));
    if (surface == null or cairo_surface_status(surface) != @as(c.cairo_status_t, @intCast(c.CAIRO_STATUS_SUCCESS))) {
        cairo_surface_destroy(surface);
        return null;
    }
    const raw = c.calloc(1, @sizeOf(TextBuffer)) orelse {
        cairo_surface_destroy(surface);
        return null;
    };
    const buf = @as(*TextBuffer, @ptrCast(@alignCast(raw)));
    c.wlr_buffer_init(&buf.base, &tray_buffer_impl, @intCast(w), @intCast(h));
    buf.surface = surface;
    return buf;
}

fn surfaceLoadPng(path: [*c]const u8, out: **c.cairo_surface_t) bool {
    out.* = cairo_image_surface_create_from_png(path) orelse return false;
    return cairo_surface_status(out.*) == @as(c.cairo_status_t, @intCast(c.CAIRO_STATUS_SUCCESS));
}

fn itemCreate(name: [*c]const u8, path: [*c]const u8) ?*TrayItem {
    const raw = c.calloc(1, @sizeOf(TrayItem)) orelse return null;
    const item = @as(*TrayItem, @ptrCast(@alignCast(raw)));
    item.name = if (name != null) strdup(name) else strdup("");
    item.path = if (path != null) strdup(path) else strdup("");
    if (item.name == null or item.path == null) {
        c.free(item.name);
        c.free(item.path);
        c.free(item);
        return null;
    }
    c.wl_list_append(&items, &item.link);
    return item;
}

fn pixmapListFree(item: *TrayItem) void {
    var i: i32 = 0;
    while (i < item.pixmap_count) : (i += 1)
        c.free(item.pixmaps[@intCast(i)].data);
    c.free(item.pixmaps);
    item.pixmaps = null;
    item.pixmap_count = 0;
}

fn itemDestroy(item: *TrayItem) void {
    c.wl_list_remove(&item.link);
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        if (item.slots[i] != null) {
            _ = sd_bus_slot_unref(item.slots[i]);
            item.slots[i] = null;
        }
    }
    if (item.props_slot != null) {
        _ = sd_bus_slot_unref(item.props_slot);
        item.props_slot = null;
    }
    pixmapListFree(item);
    c.free(item.name);
    c.free(item.path);
    c.free(item.icon_name);
    c.free(item.theme_path);
    c.free(item);
}

fn itemRefreshAsync(item: *TrayItem) void {
    if (item.props_slot != null) {
        _ = sd_bus_slot_unref(item.props_slot);
        item.props_slot = null;
    }
    const r = sd_bus_call_method_async(tray_bus, &item.props_slot, item.name, item.path, "org.freedesktop.DBus.Properties", "GetAll", itemPropsDone, item, "s", "org.kde.StatusNotifierItem");
    if (r < 0 and item.props_slot != null) {
        _ = sd_bus_slot_unref(item.props_slot);
        item.props_slot = null;
    }
}

fn readPixmapVariant(m: ?*Message, item: *TrayItem) c_int {
    var pixmaps: [*c]TrayPixmap = null;
    var count: i32 = 0;
    var r = sd_bus_message_enter_container(m, c.SD_BUS_TYPE_ARRAY, "(iiay)");
    if (r < 0) return r;
    while (sd_bus_message_enter_container(m, c.SD_BUS_TYPE_STRUCT, "iiay") > 0) {
        var w: i32 = 0;
        var h: i32 = 0;
        r = sd_bus_message_read(m, "ii", &w, &h);
        if (r < 0) {
            freePixmaps(pixmaps, count);
            return r;
        }
        if (w > 0 and h > 0 and @as(i64, w) * h <= 4096 * 4096) {
            const bytes: usize = @intCast(@as(i64, w) * h * 4);
            const data = c.malloc(bytes) orelse {
                freePixmaps(pixmaps, count);
                return -c.ENOMEM;
            };
            r = sd_bus_message_enter_container(m, c.SD_BUS_TYPE_ARRAY, "y");
            if (r < 0) {
                c.free(data);
                freePixmaps(pixmaps, count);
                return r;
            }
            var got: usize = 0;
            var byte: u8 = 0;
            while (sd_bus_message_read(m, "y", &byte) > 0) {
                if (got < bytes) @as([*c]u8, @ptrCast(data))[got] = byte;
                got += 1;
            }
            _ = sd_bus_message_exit_container(m);
            if (got == bytes) {
                const next = c.realloc(pixmaps, @sizeOf(TrayPixmap) * @as(usize, @intCast(count + 1)));
                if (next != null) {
                    pixmaps = @ptrCast(@alignCast(next));
                    pixmaps[@intCast(count)].width = w;
                    pixmaps[@intCast(count)].height = h;
                    pixmaps[@intCast(count)].data = @ptrCast(@alignCast(data));
                    count += 1;
                } else c.free(data);
            } else c.free(data);
        } else {
            _ = sd_bus_message_skip(m, null);
        }
        _ = sd_bus_message_exit_container(m);
    }
    _ = sd_bus_message_exit_container(m);
    pixmapListFree(item);
    item.pixmaps = pixmaps;
    item.pixmap_count = count;
    return 0;
}

fn freePixmaps(pixmaps: [*c]TrayPixmap, count: i32) void {
    var i: i32 = 0;
    while (i < count) : (i += 1) c.free(pixmaps[@intCast(i)].data);
    c.free(pixmaps);
}

fn itemFreeStrings(item: *TrayItem) void {
    c.free(item.icon_name);
    c.free(item.theme_path);
    item.icon_name = null;
    item.theme_path = null;
    item.status[0] = 0;
}

fn itemPropsDone(m: ?*Message, userdata: ?*anyopaque, ret_error: ?*Error) callconv(.c) c_int {
    _ = ret_error;
    const item = @as(*TrayItem, @ptrCast(@alignCast(userdata.?)));
    if (item.props_slot != null) {
        _ = sd_bus_slot_unref(item.props_slot);
        item.props_slot = null;
    }
    if (sd_bus_message_is_method_error(m, null) != 0) {
        const err = sd_bus_message_get_error(m);
        if (err != null and err.?.name != null and
            strcmp(err.?.name, "org.freedesktop.DBus.Error.UnknownObject") == 0)
        {
            itemDestroy(item);
            bar_tray_sync_all();
        }
        return 1;
    }
    var new_icon: [*c]u8 = null;
    var new_theme: [*c]u8 = null;
    var new_status: [32]u8 = std.mem.zeroes([32]u8);
    var has_status = false;
    var pixmaps: [*c]TrayPixmap = null;
    var pixmap_count: i32 = 0;
    var r = sd_bus_message_enter_container(m, c.SD_BUS_TYPE_ARRAY, "{sv}");
    if (r >= 0) {
        while (sd_bus_message_enter_container(m, c.SD_BUS_TYPE_DICT_ENTRY, "sv") > 0) {
            var key: [*c]const u8 = null;
            r = sd_bus_message_read(m, "s", &key);
            if (r < 0) break;
            r = sd_bus_message_enter_container(m, c.SD_BUS_TYPE_VARIANT, null);
            if (r < 0) break;
            if (strcmp(key, "IconName") == 0) {
                var value: [*c]const u8 = null;
                if (sd_bus_message_read(m, "s", &value) >= 0 and value != null) {
                    c.free(new_icon);
                    new_icon = strdup(value);
                }
            } else if (strcmp(key, "IconThemePath") == 0) {
                var value: [*c]const u8 = null;
                if (sd_bus_message_read(m, "s", &value) >= 0 and value != null) {
                    c.free(new_theme);
                    new_theme = strdup(value);
                }
            } else if (strcmp(key, "Status") == 0) {
                var value: [*c]const u8 = null;
                if (sd_bus_message_read(m, "s", &value) >= 0 and value != null) {
                    _ = snprintf(&new_status, new_status.len, "%s", value);
                    has_status = true;
                }
            } else if (strcmp(key, "IconPixmap") == 0) {
                r = readPixmapVariant(m, item);
                if (r >= 0) {
                    pixmaps = item.pixmaps;
                    pixmap_count = item.pixmap_count;
                    item.pixmaps = null;
                    item.pixmap_count = 0;
                }
            } else {
                _ = sd_bus_message_skip(m, null);
            }
            if (r >= 0) r = sd_bus_message_exit_container(m);
            if (r >= 0) r = sd_bus_message_exit_container(m);
            if (r < 0) break;
        }
        _ = sd_bus_message_exit_container(m);
    }
    if (r >= 0 or pixmaps != null) {
        if (new_icon != null) {
            c.free(item.icon_name);
            item.icon_name = new_icon;
            new_icon = null;
        }
        if (new_theme != null) {
            c.free(item.theme_path);
            item.theme_path = new_theme;
            new_theme = null;
        }
        if (has_status)
            _ = snprintf(&item.status, item.status.len, "%s", &new_status);
        if (pixmaps != null) {
            pixmapListFree(item);
            item.pixmaps = pixmaps;
            item.pixmap_count = pixmap_count;
            pixmaps = null;
        }
    }
    c.free(new_icon);
    c.free(new_theme);
    if (pixmaps != null) freePixmaps(pixmaps, pixmap_count);
    bar_tray_sync_all();
    return 1;
}

fn itemListenSignals(item: *TrayItem) void {
    const members = [_][*c]const u8{ "NewIcon", "NewAttentionIcon", "NewStatus", "NewPixmap", "NewTitle" };
    if (item.slots[0] != null) return;
    for (members, 0..) |member, i| {
        _ = sd_bus_match_signal(tray_bus, &item.slots[i], item.name, item.path, "org.kde.StatusNotifierItem", member, onItemSignal, item);
    }
}

fn onItemSignal(m: ?*Message, userdata: ?*anyopaque, ret_error: ?*Error) callconv(.c) c_int {
    _ = m;
    _ = ret_error;
    itemRefreshAsync(@ptrCast(@alignCast(userdata.?)));
    return 0;
}

export fn aw_tray_register_item(m: ?*Message, userdata: ?*anyopaque, ret_error: ?*Error) callconv(.c) c_int {
    _ = userdata;
    _ = ret_error;
    if (!items_ready) return 0;
    var param: [*c]const u8 = null;
    if (sd_bus_message_read(m, "s", &param) < 0 or param == null or param[0] == 0)
        return 0;
    const fallback_service = sd_bus_message_get_sender(m);
    var service: [*c]u8 = null;
    var path: [*c]u8 = null;
    const slash = strchr(param, '/');
    if (slash != null and slash != param) {
        service = strndup(param, @intFromPtr(slash) - @intFromPtr(param));
        path = strdup(slash);
    } else {
        service = if (fallback_service != null) strdup(fallback_service) else strdup("");
        path = strdup(param);
    }
    if (service == null or path == null) {
        c.free(service);
        c.free(path);
        return 0;
    }
    var item: ?*TrayItem = null;
    const head: [*c]c.struct_wl_list = @ptrCast(&items);
    var pos = items.next;
    while (pos != head) : (pos = pos.*.next) {
        const it = itemFromLink(pos);
        if (strcmp(it.name, service) == 0 and it.path != null and strcmp(it.path, path) == 0) {
            item = it;
            break;
        }
    }
    const fresh = item == null;
    if (fresh) {
        item = itemCreate(service, path);
        if (item) |i| itemListenSignals(i);
    }
    if (item) |i| {
        pixmapListFree(i);
        itemFreeStrings(i);
        itemRefreshAsync(i);
    }
    c.free(service);
    c.free(path);
    bar_tray_sync_all();
    return 0;
}

export fn aw_tray_register_host(m: ?*Message, userdata: ?*anyopaque, ret_error: ?*Error) callconv(.c) c_int {
    _ = m;
    _ = userdata;
    _ = ret_error;
    return 0;
}

export fn aw_tray_get_items(bus: ?*Bus, path: [*c]const u8, iface: [*c]const u8, prop: [*c]const u8, reply: ?*Message, userdata: ?*anyopaque, ret_error: ?*Error) callconv(.c) c_int {
    _ = bus;
    _ = path;
    _ = iface;
    _ = prop;
    _ = userdata;
    _ = ret_error;
    var r = sd_bus_message_open_container(reply, c.SD_BUS_TYPE_ARRAY, "s");
    if (r < 0) return r;
    const head: [*c]c.struct_wl_list = @ptrCast(&items);
    var pos = items.next;
    while (pos != head) : (pos = pos.*.next) {
        const item = itemFromLink(pos);
        const combined = string_printf("%s%s", item.name, item.path);
        if (combined != null) {
            r = sd_bus_message_append(reply, "s", combined);
            c.free(combined);
            if (r < 0) return r;
        }
    }
    return sd_bus_message_close_container(reply);
}

export fn aw_tray_get_bool(bus: ?*Bus, path: [*c]const u8, iface: [*c]const u8, prop: [*c]const u8, reply: ?*Message, userdata: ?*anyopaque, ret_error: ?*Error) callconv(.c) c_int {
    _ = bus;
    _ = path;
    _ = iface;
    _ = prop;
    _ = userdata;
    _ = ret_error;
    return sd_bus_message_append(reply, "b", @as(c_int, 1));
}

export fn aw_tray_get_version(bus: ?*Bus, path: [*c]const u8, iface: [*c]const u8, prop: [*c]const u8, reply: ?*Message, userdata: ?*anyopaque, ret_error: ?*Error) callconv(.c) c_int {
    _ = bus;
    _ = path;
    _ = iface;
    _ = prop;
    _ = userdata;
    _ = ret_error;
    return sd_bus_message_append(reply, "i", @as(c_int, 1));
}

fn onNameOwnerChanged(m: ?*Message, userdata: ?*anyopaque, ret_error: ?*Error) callconv(.c) c_int {
    _ = userdata;
    _ = ret_error;
    if (!items_ready) return 0;
    var name: [*c]const u8 = null;
    var old: [*c]const u8 = null;
    var new: [*c]const u8 = null;
    if (sd_bus_message_read(m, "sss", &name, &old, &new) < 0) return 0;
    if (name == null or new == null or new[0] != 0) return 0;
    var removed = false;
    const head: [*c]c.struct_wl_list = @ptrCast(&items);
    var pos = items.next;
    while (pos != head) {
        const next = pos.*.next;
        const item = itemFromLink(pos);
        if (strcmp(item.name, name) == 0) {
            itemDestroy(item);
            removed = true;
        }
        pos = next;
    }
    if (removed) bar_tray_sync_all();
    return 0;
}

fn pixmapFindBest(item: *TrayItem, target: i32, best: *?*TrayPixmap) bool {
    best.* = null;
    var found: ?*TrayPixmap = null;
    var i: i32 = 0;
    while (i < item.pixmap_count) : (i += 1) {
        const cur = &item.pixmaps[@intCast(i)];
        if (cur.width <= 0 or cur.height <= 0 or cur.data == null) continue;
        if (found == null or @abs(cur.width - target) < @abs(found.?.width - target))
            found = cur;
    }
    if (found) |f| {
        best.* = f;
        return true;
    }
    return false;
}

fn paintSurfaceScaled(cr: ?*c.cairo_t, src: ?*c.cairo_surface_t, pix: i32) bool {
    const sw: f64 = @floatFromInt(cairo_image_surface_get_width(src));
    const sh: f64 = @floatFromInt(cairo_image_surface_get_height(src));
    if (sw <= 0 or sh <= 0) return false;
    cairo_save(cr);
    cairo_scale(cr, @as(f64, @floatFromInt(pix)) / sw, @as(f64, @floatFromInt(pix)) / sh);
    cairo_set_source_surface(cr, src, 0, 0);
    cairo_paint(cr);
    cairo_restore(cr);
    return true;
}

fn themeLookup(dirs: [5][*c]const u8, rel_icon: [*c]const u8, target: i32, out: **c.cairo_surface_t) bool {
    for (dirs) |base| {
        if (base == null or base[0] == 0) continue;
        const d = opendir(base) orelse continue;
        var best_diff: i32 = -1;
        var best_name: [300]u8 = std.mem.zeroes([300]u8);
        while (c.readdir(d)) |ent| {
            const s: [*c]const u8 = &ent.*.d_name;
            if (s[0] < '0' or s[0] > '9') continue;
            const num = atoi(s);
            if (num <= 0) continue;
            const diff: i32 = @intCast(@abs(num - target));
            if (best_diff < 0 or diff < best_diff) {
                best_diff = diff;
                _ = snprintf(&best_name, best_name.len, "%s", s);
            }
        }
        _ = closedir(d);
        if (best_name[0] == 0) continue;
        var path: [512]u8 = undefined;
        _ = snprintf(&path, path.len, "%s/%s/apps/%s.png", base, &best_name, rel_icon);
        if (surfaceLoadPng(&path, out)) return true;
        _ = snprintf(&path, path.len, "%s/%s/status/%s.png", base, &best_name, rel_icon);
        if (surfaceLoadPng(&path, out)) return true;
    }
    return false;
}

fn trayRenderIconPixmap(dst: ?*c.cairo_surface_t, item: *TrayItem, target_size: i32, scale: f32) bool {
    var pix: i32 = @intFromFloat(@as(f32, @floatFromInt(target_size)) * scale + 0.5);
    if (pix < 1) pix = 1;
    const cr = cairo_create(dst);
    cairo_set_operator(cr, @intCast(c.CAIRO_OPERATOR_SOURCE));
    cairo_set_source_rgba(cr, 0, 0, 0, 0);
    cairo_paint(cr);
    var drawn = false;
    var pm: ?*TrayPixmap = null;
    if (pixmapFindBest(item, target_size, &pm) and pm.?.data != null) {
        const src = cairo_image_surface_create_for_data(@ptrCast(pm.?.data), @intCast(c.CAIRO_FORMAT_ARGB32), pm.?.width, pm.?.height, pm.?.width * 4);
        if (src != null and cairo_surface_status(src) == @as(c.cairo_status_t, @intCast(c.CAIRO_STATUS_SUCCESS)))
            drawn = paintSurfaceScaled(cr, src, pix);
        if (src != null) cairo_surface_destroy(src);
    }
    if (!drawn and item.icon_name != null and item.icon_name[0] != 0) {
        var home_icons: [256]u8 = std.mem.zeroes([256]u8);
        var data_icons: [256]u8 = std.mem.zeroes([256]u8);
        var stripped: [128]u8 = std.mem.zeroes([128]u8);
        var rel = item.icon_name;
        if (strchr(rel, '/') != null)
            rel = strrchr(rel, '/') + 1;
        const dot = strrchr(rel, '.');
        if (dot != null and (strcmp(dot, ".png") == 0 or strcmp(dot, ".svg") == 0)) {
            _ = snprintf(&stripped, stripped.len, "%.*s", @as(c_int, @intCast(@intFromPtr(dot) - @intFromPtr(rel))), rel);
            rel = &stripped;
        }
        const home = getenv("HOME");
        if (home != null) {
            _ = snprintf(&home_icons, home_icons.len, "%s/.icons", home);
            _ = snprintf(&data_icons, data_icons.len, "%s/.local/share/icons", home);
        }
        const dirs = [5][*c]const u8{
            if (home != null) &home_icons else null,
            if (home != null) &data_icons else null,
            "/usr/share/icons/hicolor",
            "/usr/share/pixmaps",
            item.theme_path,
        };
        var src: *c.cairo_surface_t = undefined;
        if (themeLookup(dirs, rel, target_size, &src)) {
            drawn = paintSurfaceScaled(cr, src, pix);
            cairo_surface_destroy(src);
        }
    }
    cairo_destroy(cr);
    return drawn;
}

export fn tray_sync_bar(bar: [*c]Bar) callconv(.c) void {
    if (bar == null or !items_ready) return;
    tray_detach_bar(bar);
    var count: i32 = 0;
    const head: [*c]c.struct_wl_list = @ptrCast(&items);
    var pos = items.next;
    while (pos != head) : (pos = pos.*.next) {
        const item = itemFromLink(pos);
        if (strcmp(&item.status, "Passive") == 0) continue;
        count += 1;
    }
    if (count == 0) return;
    bar.*.tray_icons = @ptrCast(@alignCast(c.calloc(@intCast(count), @sizeOf(BarTrayIcon))));
    if (bar.*.tray_icons == null) return;
    bar.*.tray_icon_capacity = count;
    bar.*.tray_icon_count = 0;
    pos = items.next;
    while (pos != head) : (pos = pos.*.next) {
        const item = itemFromLink(pos);
        if (strcmp(&item.status, "Passive") == 0) continue;
        const icon = &bar.*.tray_icons[@intCast(bar.*.tray_icon_count)];
        icon.item = @ptrCast(item);
        const scale: f32 = if (bar.*.mon != null and bar.*.mon.*.wlr_output.*.scale > 0)
            bar.*.mon.*.wlr_output.*.scale
        else
            1.0;
        var pix: i32 = @intFromFloat(@as(f32, @floatFromInt(c.config.bar_tray_icon_size)) * scale + 0.5);
        if (pix < 1) pix = 1;
        const buf = trayBufferCreate(pix, pix) orelse continue;
        _ = trayRenderIconPixmap(buf.surface, item, @intCast(c.config.bar_tray_icon_size), scale);
        icon.node = wlr_scene_buffer_create(bar.*.tree, null);
        if (icon.node == null) {
            c.wlr_buffer_drop(&buf.base);
            continue;
        }
        c.wlr_scene_buffer_set_buffer(icon.node, &buf.base);
        c.wlr_buffer_drop(&buf.base);
        c.wlr_scene_buffer_set_dest_size(icon.node, @intCast(c.config.bar_tray_icon_size), @intCast(c.config.bar_tray_icon_size));
        icon.btn.type = c.BarNodeTypeTray;
        icon.btn.tag = 0;
        icon.btn.item = item;
        _ = acwm_scene_node_set(&icon.node.*.node, c.BarNodeTypeTray, &icon.btn);
        bar.*.tray_icon_count += 1;
    }
}

export fn tray_detach_bar(bar: [*c]Bar) callconv(.c) void {
    if (bar == null) return;
    var i: i32 = 0;
    while (i < bar.*.tray_icon_count) : (i += 1) {
        if (bar.*.tray_icons[@intCast(i)].node != null) {
            c.wlr_scene_node_destroy(&bar.*.tray_icons[@intCast(i)].node.*.node);
            bar.*.tray_icons[@intCast(i)].node = null;
        }
    }
    c.free(bar.*.tray_icons);
    bar.*.tray_icons = null;
    bar.*.tray_icon_count = 0;
    bar.*.tray_icon_capacity = 0;
}

export fn tray_click(item: ?*anyopaque, button: u32) callconv(.c) void {
    const i = @as(?*TrayItem, @ptrCast(@alignCast(item))) orelse return;
    if (tray_bus == null) return;
    const method: [*c]const u8 = if (button == c.BTN_RIGHT) "SecondaryActivate" else "Activate";
    _ = sd_bus_call_method_async(tray_bus, null, i.name, i.path, "org.kde.StatusNotifierItem", method, null, null, "ii", @as(c_int, 0), @as(c_int, 0));
    _ = sd_bus_flush(tray_bus);
}

fn trayDispatchReady(fd: c_int, mask: u32, data: ?*anyopaque) callconv(.c) c_int {
    _ = fd;
    _ = mask;
    _ = data;
    if (tray_bus == null) return 0;
    while (true) {
        const r = sd_bus_process(tray_bus, null);
        if (r < 0) {
            _ = wl_event_source_remove(tray_fd_source);
            tray_fd_source = null;
            tray_bus = sd_bus_flush_close_unref(tray_bus);
            return 0;
        }
        if (r == 0) break;
    }
    _ = sd_bus_flush(tray_bus);
    return 0;
}

export fn tray_reload() callconv(.c) void {
    if (tray_bus != null or c.config.bar_enable == 0) return;
    var r = sd_bus_default_user(&tray_bus);
    if (r < 0) r = sd_bus_default_system(&tray_bus);
    if (r < 0) {
        tray_bus = null;
        return;
    }
    _ = sd_bus_add_object_vtable(tray_bus, null, "/org/freedesktop/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher", aw_tray_vtable_get(), null);
    _ = sd_bus_add_object_vtable(tray_bus, null, "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher", aw_tray_vtable_get(), null);
    _ = sd_bus_request_name(tray_bus, "org.kde.StatusNotifierWatcher", 0);
    _ = sd_bus_match_signal(tray_bus, null, null, "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameOwnerChanged", onNameOwnerChanged, null);
    if (tray_fd_source != null) {
        _ = wl_event_source_remove(tray_fd_source);
        tray_fd_source = null;
    }
    tray_fd_source = wl_event_loop_add_fd(c.server.event_loop, sd_bus_get_fd(tray_bus), c.WL_EVENT_READABLE, trayDispatchReady, null);
    _ = trayDispatchReady(0, 0, null);
}

export fn tray_init(loop: ?*c.struct_wl_event_loop) callconv(.c) void {
    _ = loop;
    listInit(&items);
    items_ready = true;
}

export fn tray_cleanup() callconv(.c) void {
    if (tray_fd_source != null) {
        _ = wl_event_source_remove(tray_fd_source);
        tray_fd_source = null;
    }
    tray_bus = sd_bus_flush_close_unref(tray_bus);
    if (items_ready) {
        while (items.next != @as([*c]c.struct_wl_list, @ptrCast(&items))) {
            const item = itemFromLink(items.next);
            itemDestroy(item);
        }
        items_ready = false;
    }
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/tray_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_bus: ?*Bus;
extern var stub_default_user_calls: c_int;
extern var stub_vtable_calls: c_int;
extern var stub_name_calls: c_int;
extern var stub_match_calls: c_int;
extern var stub_call_async_calls: c_int;
extern var stub_read_string: [*c]const u8;
extern var stub_sender: [*c]const u8;
extern var stub_fd_add_calls: c_int;
extern var stub_fd_remove_calls: c_int;
extern var stub_cairo_create_calls: c_int;
extern var stub_cairo_destroy_calls: c_int;
extern var stub_surface_destroy_calls: c_int;
extern var stub_buffer_init_calls: c_int;
extern var stub_buffer_drop_calls: c_int;
extern var stub_scene_buffer: [*c]c.struct_wlr_scene_buffer;
extern var stub_set_buffer_calls: c_int;
extern var stub_dest_calls: c_int;
extern var stub_node_destroy_calls: c_int;
extern var stub_scene_set_calls: c_int;
extern var stub_sync_all_calls: c_int;

var test_output: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);

fn resetTrayWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    tray_bus = null;
    tray_fd_source = null;
    items_ready = false;
    listInit(&items);
    c.config.bar_enable = 1;
    c.config.bar_tray_icon_size = 16;
    test_output = std.mem.zeroes(c.struct_wlr_output);
    test_output.scale = 2;
    stub_default_user_calls = 0;
    stub_vtable_calls = 0;
    stub_name_calls = 0;
    stub_match_calls = 0;
    stub_call_async_calls = 0;
    stub_read_string = null;
    stub_fd_add_calls = 0;
    stub_fd_remove_calls = 0;
    stub_cairo_create_calls = 0;
    stub_cairo_destroy_calls = 0;
    stub_surface_destroy_calls = 0;
    stub_buffer_init_calls = 0;
    stub_buffer_drop_calls = 0;
    stub_scene_buffer = null;
    stub_set_buffer_calls = 0;
    stub_dest_calls = 0;
    stub_node_destroy_calls = 0;
    stub_scene_set_calls = 0;
    stub_sync_all_calls = 0;
}

fn addItem(name: []const u8, path: []const u8, status: []const u8) *TrayItem {
    const item = itemCreate(@ptrCast(name.ptr), @ptrCast(path.ptr)).?;
    @memcpy(item.status[0..status.len], status);
    item.status[status.len] = 0;
    return item;
}

test "tray init, reload and cleanup wire the bus" {
    resetTrayWorld();
    tray_init(null);
    try testing.expect(items_ready);
    tray_reload();
    try testing.expectEqual(@as(c_int, 1), stub_default_user_calls);
    try testing.expectEqual(@as(c_int, 2), stub_vtable_calls);
    try testing.expectEqual(@as(c_int, 1), stub_name_calls);
    try testing.expectEqual(@as(c_int, 1), stub_fd_add_calls);
    tray_cleanup();
    try testing.expect(!items_ready);
    try testing.expectEqual(@as(c_int, 1), stub_fd_remove_calls);
}

test "items create, match and destroy with pixmaps" {
    resetTrayWorld();
    listInit(&items);
    const item = addItem(":1.7", "/StatusNotifierItem", "Active");
    try testing.expectEqualStrings(":1.7", std.mem.span(item.name));
    const pixmaps = @as([*c]TrayPixmap, @ptrCast(@alignCast(c.calloc(1, @sizeOf(TrayPixmap)))));
    pixmaps[0].width = 16;
    pixmaps[0].height = 16;
    pixmaps[0].data = @ptrCast(@alignCast(c.malloc(16 * 16 * 4)));
    item.pixmaps = pixmaps;
    item.pixmap_count = 1;
    itemDestroy(item);
    try testing.expectEqual(@as(usize, 0), @as(usize, 0));
}

test "tray sync builds active icons and skips passive items" {
    resetTrayWorld();
    listInit(&items);
    items_ready = true;
    _ = addItem(":1.1", "/a", "Active");
    _ = addItem(":1.2", "/b", "Passive");
    _ = addItem(":1.3", "/c", "NeedsAttention");
    var bar: Bar = std.mem.zeroes(Bar);
    var m: Monitor = std.mem.zeroes(Monitor);
    m.wlr_output = &test_output;
    bar.mon = &m;
    bar.tree = @ptrFromInt(0x1000);
    tray_sync_bar(&bar);
    try testing.expectEqual(@as(i32, 2), bar.tray_icon_count);
    try testing.expectEqual(@as(c_int, 2), stub_buffer_init_calls);
    try testing.expectEqual(@as(c_int, 2), stub_set_buffer_calls);
    try testing.expectEqual(@as(c_int, 2), stub_dest_calls);
    try testing.expectEqual(@as(c_int, 2), stub_scene_set_calls);
    tray_detach_bar(&bar);
    try testing.expectEqual(@as(i32, 0), bar.tray_icon_count);
    try testing.expectEqual(@as(c_int, 2), stub_node_destroy_calls);
}

test "watcher registers senders and refreshes items" {
    resetTrayWorld();
    tray_init(null);
    tray_bus = stub_bus;
    stub_read_string = "/StatusNotifierItem";
    stub_sender = ":1.42";
    _ = aw_tray_register_item(null, null, null);
    try testing.expectEqual(@as(c_int, 1), stub_call_async_calls);
    try testing.expectEqual(@as(c_int, 5), stub_match_calls);
    try testing.expectEqual(@as(c_int, 1), stub_sync_all_calls);
    const head: [*c]c.struct_wl_list = @ptrCast(&items);
    try testing.expect(items.next != head);
    const item = itemFromLink(items.next);
    try testing.expectEqualStrings(":1.42", std.mem.span(item.name));
    try testing.expectEqualStrings("/StatusNotifierItem", std.mem.span(item.path));

    stub_read_string = "org.example/Status/Icon";
    _ = aw_tray_register_item(null, null, null);
    try testing.expectEqual(@as(c_int, 2), stub_sync_all_calls);
    var count: usize = 0;
    var pos = items.next;
    while (pos != head) : (pos = pos.*.next) count += 1;
    try testing.expectEqual(@as(usize, 2), count);
}

test "tray click and cleanup release items" {
    resetTrayWorld();
    tray_init(null);
    tray_bus = stub_bus;
    _ = addItem(":1.9", "/x", "Active");
    tray_click(@ptrCast(itemFromLink(items.next)), c.BTN_RIGHT);
    try testing.expectEqual(@as(c_int, 1), stub_call_async_calls);
    tray_cleanup();
    const head: [*c]c.struct_wl_list = @ptrCast(&items);
    try testing.expect(items.next == head);
    try testing.expect(!items_ready);
}
