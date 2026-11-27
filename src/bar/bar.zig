//! Port of bar/bar.c (Phase 5, bar slice 1, slice 79).

const std = @import("std");
const c = @import("cc");

const Bar = c.struct_AcwmBar;
const Monitor = c.Monitor;
const BarButton = c.struct_BarButton;
const JumpLabel = c.struct_AcwmJumpLabel;
const Client = c.Client;

extern fn tray_init(loop: ?*c.struct_wl_event_loop) callconv(.c) void;
extern fn tray_cleanup() callconv(.c) void;
extern fn tray_reload() callconv(.c) void;
extern fn tray_sync_bar(bar: [*c]Bar) callconv(.c) void;
extern fn tray_detach_bar(bar: [*c]Bar) callconv(.c) void;
extern fn tray_click(item: ?*anyopaque, button: u32) callconv(.c) void;
extern fn bind_to_view(arg: [*c]const c.Arg) callconv(.c) i32;
extern fn arrange_layers(m: [*c]Monitor) callconv(.c) void;
extern fn get_monitor_active_tagset(m: [*c]const Monitor) callconv(.c) u32;
extern fn is_special_active(m: [*c]const Monitor) callconv(.c) bool;
extern fn special_has_clients(m: [*c]const Monitor) callconv(.c) bool;
extern fn get_tag_status(tag: u32, m: [*c]Monitor) callconv(.c) u32;
extern fn acwm_jump_label_node_create(parent: [*c]c.struct_wlr_scene_tree, data: c.DecorateDrawData) callconv(.c) [*c]JumpLabel;
extern fn acwm_jump_label_node_destroy(label: [*c]JumpLabel) callconv(.c) void;
extern fn acwm_jump_label_node_update(label: [*c]JumpLabel, text: [*c]const u8, scale: f32) callconv(.c) void;
extern fn acwm_jump_label_node_set_focus(label: [*c]JumpLabel, focused: bool) callconv(.c) void;
extern fn acwm_jump_label_node_set_background(label: [*c]JumpLabel, r: f32, g: f32, b: f32, a: f32) callconv(.c) void;
extern fn acwm_scene_node_set(node: [*c]c.struct_wlr_scene_node, type: u32, owner: ?*anyopaque) callconv(.c) bool;
extern fn acwm_scene_node_at(node: [*c]c.struct_wlr_scene_node, x: f64, y: f64, nx: ?*f64, ny: ?*f64) callconv(.c) [*c]c.struct_wlr_scene_node;
extern fn acwm_scene_node_find(node: [*c]c.struct_wlr_scene_node) callconv(.c) [*c]c.AcwmSceneNode;
extern fn wlr_scene_tree_create(parent: [*c]c.struct_wlr_scene_tree) callconv(.c) [*c]c.struct_wlr_scene_tree;
extern fn wlr_scene_rect_create(parent: [*c]c.struct_wlr_scene_tree, width: c_int, height: c_int, color: [*c]const f32) callconv(.c) [*c]c.struct_wlr_scene_rect;
extern fn wlr_scene_rect_set_size(rect: [*c]c.struct_wlr_scene_rect, width: c_int, height: c_int) callconv(.c) void;
extern fn wlr_scene_rect_set_corner_radii(rect: [*c]c.struct_wlr_scene_rect, radii: c.struct_fx_corner_radii) callconv(.c) void;
extern fn corner_radii_all(radius: c_int) callconv(.c) c.struct_fx_corner_radii;
extern fn wlr_scene_node_set_enabled(node: [*c]c.struct_wlr_scene_node, enabled: bool) callconv(.c) void;
extern fn wlr_scene_node_set_position(node: [*c]c.struct_wlr_scene_node, x: c_int, y: c_int) callconv(.c) void;
extern fn wlr_scene_node_destroy(node: [*c]c.struct_wlr_scene_node) callconv(.c) void;
extern fn wl_event_loop_add_timer(loop: [*c]c.struct_wl_event_loop, func: ?*const fn (?*anyopaque) callconv(.c) c_int, data: ?*anyopaque) callconv(.c) ?*c.struct_wl_event_source;
extern fn wl_event_source_timer_update(source: ?*c.struct_wl_event_source, ms: c_int) callconv(.c) c_int;
extern fn wl_event_source_remove(source: ?*c.struct_wl_event_source) callconv(.c) c_int;
extern fn time(t: ?*c.time_t) callconv(.c) c.time_t;
extern fn localtime_r(t: *const c.time_t, out: *c.struct_tm) callconv(.c) ?*c.struct_tm;
extern fn strftime(buf: [*c]u8, max: usize, fmt: [*c]const u8, tm: *const c.struct_tm) callconv(.c) usize;
extern fn strstr(haystack: [*c]const u8, needle: [*c]const u8) callconv(.c) [*c]u8;
extern fn snprintf(buf: [*c]u8, len: usize, fmt: [*c]const u8, ...) callconv(.c) c_int;
extern fn opendir(path: [*c]const u8) callconv(.c) ?*c.DIR;
extern fn readdir(dir: ?*c.DIR) callconv(.c) [*c]c.struct_dirent;
extern fn closedir(dir: ?*c.DIR) callconv(.c) c_int;
extern fn fopen(path: [*c]const u8, mode: [*c]const u8) callconv(.c) ?*c.FILE;
extern fn fgets(buf: [*c]u8, len: c_int, file: ?*c.FILE) callconv(.c) [*c]u8;
extern fn fclose(file: ?*c.FILE) callconv(.c) c_int;
extern fn atoi(str: [*c]const u8) callconv(.c) c_int;
extern fn strcspn(str: [*c]const u8, reject: [*c]const u8) callconv(.c) usize;
extern fn strncmp(a: [*c]const u8, b: [*c]const u8, n: usize) callconv(.c) c_int;

const BAR_GAP: i32 = 4;
const BAR_CORNER_RADIUS = true;

var bar_clock_source: ?*c.struct_wl_event_source = null;
var bar_status_source: ?*c.struct_wl_event_source = null;
var bar_print_status_listener: c.struct_wl_listener = std.mem.zeroes(c.struct_wl_listener);
var bar_clock_text: [96]u8 = std.mem.zeroes([96]u8);
var bar_battery_text: [64]u8 = std.mem.zeroes([64]u8);

fn barPlainDrawData(out: *c.DecorateDrawData) void {
    out.* = c.config.bardata;
    out.bg_color[3] = 0.0;
    out.border_width = 0;
}

fn barStatusLabelInit(slot: *[*c]JumpLabel, parent: [*c]c.struct_wlr_scene_tree) void {
    var plain: c.DecorateDrawData = undefined;
    barPlainDrawData(&plain);
    slot.* = acwm_jump_label_node_create(parent, plain);
    if (slot.* != null)
        acwm_jump_label_node_set_background(slot.*, 0, 0, 0, 0);
}

fn barLabelUpdate(label: [*c]JumpLabel, text: [*c]const u8, scale: f32) void {
    if (label == null)
        return;
    acwm_jump_label_node_update(label, text, if (scale > 0) scale else 1.0);
}

fn barLabelMove(label: [*c]JumpLabel, x: i32, y: i32) void {
    if (label == null or label.*.scene == null)
        return;
    c.wlr_scene_node_set_position(&label.*.scene.*.node, x, y);
}

fn barVisibleFor(m: [*c]Monitor) bool {
    if (c.server.session_locked != 0)
        return false;
    if (m.*.isoverview != 0)
        return true;
    const tagset = m.*.tagset[m.*.seltags];
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    var pos = c.server.clients.next;
    while (pos != head) : (pos = pos.*.next) {
        const cl = @as([*c]Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Client, "link")));
        if (cl.*.mon != m or cl.*.iskilling != 0 or cl.*.isminimized != 0)
            continue;
        if (cl.*.isfullscreen == 0)
            continue;
        if ((cl.*.tags & tagset) != 0 or cl.*.isglobal != 0)
            return false;
    }
    return true;
}

fn barLayout(m: [*c]Monitor) void {
    const bar = m.*.bar;
    if (bar == null or bar.*.tree == null)
        return;
    const visible = barVisibleFor(m);
    if (bar.*.tree.*.node.enabled != visible)
        c.wlr_scene_node_set_enabled(&bar.*.tree.*.node, visible);
    if (!visible)
        return;

    var pad: i32 = @intCast(c.config.bardata.padding_x);
    if (pad <= 0) pad = 6;
    var width: i32 = m.*.m.width - 2 * @as(i32, @intCast(c.config.bar_lr_gap));
    const height: i32 = @intCast(c.config.bar_height);
    if (width < 0) width = 0;
    if (bar.*.bg != null)
        c.wlr_scene_rect_set_size(bar.*.bg, width, height);

    if (BAR_CORNER_RADIUS) {
        if (bar.*.bg != null) {
            var radius: i32 = @intCast(c.config.bar_corner_radius);
            radius = @min(radius, @divTrunc(@min(width, height), 2));
            if (radius < 0) radius = 0;
            c.wlr_scene_rect_set_corner_radii(bar.*.bg, c.corner_radii_all(radius));
        }
    }
    c.wlr_scene_node_set_position(&bar.*.tree.*.node,
        m.*.m.x + @as(i32, @intCast(c.config.bar_lr_gap)),
        m.*.m.y + @as(i32, @intCast(c.config.bar_top_gap)));

    var cx: i32 = pad;
    var i: i32 = 0;
    while (i < bar.*.tag_count) : (i += 1) {
        const label = bar.*.tags[@intCast(i)];
        if (label == null) continue;
        const y = @max(0, @divTrunc(height - label.*.logical_height, 2));
        barLabelMove(label, cx, y);
        cx += label.*.logical_width + BAR_GAP;
        if (cx < 0) cx = 0;
    }

    var rx: i32 = width - pad;
    if (rx < 0) rx = 0;
    i = bar.*.tray_icon_count - 1;
    while (i >= 0) : (i -= 1) {
        const node = bar.*.tray_icons[@intCast(i)].node;
        if (node == null) continue;
        rx -= @intCast(c.config.bar_tray_icon_size);
        if (rx < 0) rx = 0;
        c.wlr_scene_node_set_position(&node.*.node, rx,
            @max(0, @divTrunc(height - @as(i32, @intCast(c.config.bar_tray_icon_size)), 2)));
        rx -= BAR_GAP;
    }
    if (bar.*.battery != null) {
        rx -= bar.*.battery.*.logical_width;
        if (rx < 0) rx = 0;
        barLabelMove(bar.*.battery, rx, @max(0, @divTrunc(height - bar.*.battery.*.logical_height, 2)));
        rx -= BAR_GAP;
    }
    if (bar.*.clock != null) {
        rx -= bar.*.clock.*.logical_width;
        if (rx < 0) rx = 0;
        barLabelMove(bar.*.clock, rx, @max(0, @divTrunc(height - bar.*.clock.*.logical_height, 2)));
    }
}

export fn bar_strip_height() callconv(.c) i32 {
    if (c.config.bar_enable == 0)
        return 0;
    return @as(i32, @intCast(c.config.bar_top_gap)) + @as(i32, @intCast(c.config.bar_height));
}

fn barTagText(tag: i32, buf: [*c]u8, len: usize) void {
    _ = c.snprintf(buf, len, "%d", tag);
}

export fn bar_refresh_tags() callconv(.c) void {
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.monitors);
    var pos = c.server.monitors.next;
    while (pos != head) : (pos = pos.*.next) {
        const m = @as([*c]Monitor, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Monitor, "link")));
        const bar = m.*.bar;
        if (bar == null) continue;
        const scale: f32 = if (m.*.wlr_output.*.scale > 0) m.*.wlr_output.*.scale else 1.0;
        const active = get_monitor_active_tagset(m);
        const special_active = is_special_active(m);
        const special_used = special_active or special_has_clients(m);
        var text: [16]u8 = undefined;
        var i: i32 = 0;
        while (i < bar.*.tag_count) : (i += 1) {
            const label = bar.*.tags[@intCast(i)];
            if (label == null) continue;
            if (i < c.config.tag_num) {
                const tag_bit = @as(u32, 1) << @intCast(i);
                const is_active = (tag_bit & active) != 0;
                const status = get_tag_status(@intCast(i + 1), m);
                c.wlr_scene_node_set_enabled(&label.*.scene.*.node, true);
                barTagText(i + 1, &text, text.len);
                barLabelUpdate(label, &text, scale);
                acwm_jump_label_node_set_focus(label, is_active);
                if (status == 2) {
                    acwm_jump_label_node_set_background(label,
                        c.config.urgentcolor[0], c.config.urgentcolor[1],
                        c.config.urgentcolor[2], c.config.urgentcolor[3]);
                } else if (is_active) {
                    acwm_jump_label_node_set_background(label,
                        c.config.bardata.focus_bg_color[0], c.config.bardata.focus_bg_color[1],
                        c.config.bardata.focus_bg_color[2], c.config.bardata.focus_bg_color[3]);
                } else {
                    acwm_jump_label_node_set_background(label,
                        c.config.bardata.bg_color[0], c.config.bardata.bg_color[1],
                        c.config.bardata.bg_color[2], 0);
                }
            } else {
                c.wlr_scene_node_set_enabled(&label.*.scene.*.node, special_used);
                barLabelUpdate(label, "S", scale);
                acwm_jump_label_node_set_focus(label, special_active);
            }
        }
        barLayout(m);
    }
}

export fn bar_monitor_layout(m: [*c]Monitor) callconv(.c) void {
    barLayout(m);
}

fn barClockRefresh(relayout: bool) void {
    var buf: [96]u8 = undefined;
    var now: c.time_t = c.time(null);
    var tmnow: c.struct_tm = undefined;
    _ = c.localtime_r(&now, &tmnow);
    const fmt: [*c]const u8 = if (c.config.bar_clock_format != null) c.config.bar_clock_format else "%H:%M";
    buf[0] = 0;
    _ = c.strftime(&buf, buf.len, fmt, &tmnow);
    if (buf[0] != 0 and c.strcmp(&bar_clock_text, &buf) != 0)
        _ = c.snprintf(&bar_clock_text, bar_clock_text.len, "%s", &buf);

    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.monitors);
    var pos = c.server.monitors.next;
    while (pos != head) : (pos = pos.*.next) {
        const m = @as([*c]Monitor, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Monitor, "link")));
        if (m.*.bar == null) continue;
        const scale: f32 = if (m.*.wlr_output.*.scale > 0) m.*.wlr_output.*.scale else 1.0;
        barLabelUpdate(m.*.bar.*.clock, &bar_clock_text, scale);
        if (relayout) barLayout(m);
    }
}

fn barClockTick(data: ?*anyopaque) callconv(.c) c_int {
    _ = data;
    barClockRefresh(true);
    var delay_ms: i32 = 0;
    if (c.config.bar_clock_format != null and c.strstr(c.config.bar_clock_format, "%S") != null) {
        delay_ms = 1000;
    } else {
        var now: c.time_t = c.time(null);
        var tmnow: c.struct_tm = undefined;
        _ = c.localtime_r(&now, &tmnow);
        delay_ms = (60 - tmnow.tm_sec) * 1000;
    }
    if (bar_clock_source != null)
        _ = c.wl_event_source_timer_update(bar_clock_source, delay_ms);
    return 0;
}

fn barReadFile(path: [*c]const u8, buf: [*c]u8, len: usize) bool {
    const fd = c.fopen(path, "r") orelse return false;
    const ok = c.fgets(buf, @intCast(len), fd) != null;
    _ = c.fclose(fd);
    if (!ok) return false;
    buf[c.strcspn(buf, "\n")] = 0;
    return true;
}

fn barBatteryRefresh(relayout: bool) void {
    const dir = c.opendir("/sys/class/power_supply");
    if (dir != null) {
        var total: i32 = 0;
        var count: i32 = 0;
        var count_ac: i32 = 0;
        var path: [320]u8 = undefined;
        var buf: [64]u8 = undefined;
        while (c.readdir(dir)) |ent| {
            if (c.strncmp(&ent.*.d_name, "BAT", 3) == 0) {
                _ = c.snprintf(&path, path.len, "/sys/class/power_supply/%s/capacity", &ent.*.d_name);
                if (barReadFile(&path, &buf, buf.len)) {
                    total += c.atoi(&buf);
                    count += 1;
                }
            } else if (c.strncmp(&ent.*.d_name, "AC", 2) == 0) {
                _ = c.snprintf(&path, path.len, "/sys/class/power_supply/%s/online", &ent.*.d_name);
                if (barReadFile(&path, &buf, buf.len) and c.atoi(&buf) == 1)
                    count_ac += 1;
            }
        }
        _ = c.closedir(dir);
        var text: [64]u8 = std.mem.zeroes([64]u8);
        if (count > 0 and count_ac > 0)
            _ = c.snprintf(&text, text.len, "+%d%%", if (count != 0) @divTrunc(total, count) else 0)
        else if (count > 0)
            _ = c.snprintf(&text, text.len, "%d%%", if (count != 0) @divTrunc(total, count) else 0)
        else if (count_ac > 0)
            _ = c.snprintf(&text, text.len, "AC");
        if (c.strcmp(&text, &bar_battery_text) != 0)
            _ = c.snprintf(&bar_battery_text, bar_battery_text.len, "%s", &text);
    }
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.monitors);
    var pos = c.server.monitors.next;
    while (pos != head) : (pos = pos.*.next) {
        const m = @as([*c]Monitor, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Monitor, "link")));
        if (m.*.bar == null) continue;
        const scale: f32 = if (m.*.wlr_output.*.scale > 0) m.*.wlr_output.*.scale else 1.0;
        barLabelUpdate(m.*.bar.*.battery, &bar_battery_text, scale);
        if (relayout) barLayout(m);
    }
}

fn barStatusTick(data: ?*anyopaque) callconv(.c) c_int {
    _ = data;
    barBatteryRefresh(true);
    tray_reload();
    if (bar_status_source != null and c.config.bar_battery_interval > 0)
        _ = c.wl_event_source_timer_update(bar_status_source, @intCast(c.config.bar_battery_interval));
    return 0;
}

fn barEnsureTimers() void {
    if (bar_clock_source == null)
        bar_clock_source = c.wl_event_loop_add_timer(c.server.event_loop, barClockTick, null);
    if (bar_status_source == null)
        bar_status_source = c.wl_event_loop_add_timer(c.server.event_loop, barStatusTick, null);
    if (bar_clock_source != null) _ = c.wl_event_source_timer_update(bar_clock_source, 1);
    if (bar_status_source != null) _ = c.wl_event_source_timer_update(bar_status_source, 1);
}

fn barStopTimers() void {
    if (bar_clock_source != null) _ = c.wl_event_source_timer_update(bar_clock_source, 0);
    if (bar_status_source != null) _ = c.wl_event_source_timer_update(bar_status_source, 0);
}

fn barDestroyInternal(bar: [*c]Bar) void {
    if (bar == null) return;
    tray_detach_bar(bar);
    if (bar.*.tags != null) {
        var i: i32 = 0;
        while (i < bar.*.tag_count) : (i += 1) {
            if (bar.*.tags[@intCast(i)] != null)
                acwm_jump_label_node_destroy(bar.*.tags[@intCast(i)]);
        }
        c.free(@ptrCast(bar.*.tags));
    }
    c.free(@ptrCast(bar.*.tag_btns));
    if (bar.*.battery != null) acwm_jump_label_node_destroy(bar.*.battery);
    if (bar.*.clock != null) acwm_jump_label_node_destroy(bar.*.clock);
    if (bar.*.tree != null) c.wlr_scene_node_destroy(&bar.*.tree.*.node);
    c.free(bar);
}

fn barCreate(m: [*c]Monitor) bool {
    const raw = c.calloc(1, @sizeOf(Bar)) orelse return false;
    const bar = @as(*Bar, @ptrCast(@alignCast(raw)));
    bar.mon = m;
    bar.tree = c.wlr_scene_tree_create(c.server.layers[c.LyrBar]);
    if (bar.tree == null) { barDestroyInternal(bar); return false; }
    bar.bg = c.wlr_scene_rect_create(bar.tree, 0, 0, &c.config.bar_bg_color);
    if (bar.bg == null) { barDestroyInternal(bar); return false; }
    bar.tag_count = c.config.tag_num + 1;
    bar.tags = @ptrCast(@alignCast(c.calloc(@intCast(bar.tag_count), @sizeOf([*c]JumpLabel))));
    bar.tag_btns = @ptrCast(@alignCast(c.calloc(@intCast(bar.tag_count), @sizeOf(BarButton))));
    if (bar.tags == null or bar.tag_btns == null) { barDestroyInternal(bar); return false; }
    var i: i32 = 0;
    while (i < bar.tag_count) : (i += 1) {
        var data: c.DecorateDrawData = undefined;
        barPlainDrawData(&data);
        bar.tags[@intCast(i)] = acwm_jump_label_node_create(bar.tree, data);
        if (bar.tags[@intCast(i)] == null) continue;
        bar.tag_btns[@intCast(i)].type = if (i < c.config.tag_num) c.BarNodeTypeTag else c.BarNodeTypeSpecial;
        bar.tag_btns[@intCast(i)].tag = if (i < c.config.tag_num) i + 1 else 0;
        bar.tag_btns[@intCast(i)].item = null;
        _ = acwm_scene_node_set(&bar.tags[@intCast(i)].*.scene.*.node,
            bar.tag_btns[@intCast(i)].type, &bar.tag_btns[@intCast(i)]);
    }
    barStatusLabelInit(&bar.battery, bar.tree);
    barStatusLabelInit(&bar.clock, bar.tree);
    tray_sync_bar(bar);
    m.*.bar = bar;
    return true;
}

export fn bar_monitor_create(m: [*c]Monitor) callconv(.c) void {
    if (c.config.bar_enable == 0 or m.*.bar != null or m.*.iscleanuping) return;
    if (barCreate(m)) {
        barEnsureTimers();
        tray_reload();
        barBatteryRefresh(true);
        barClockRefresh(true);
        bar_refresh_tags();
        barLayout(m);
    }
}

export fn bar_destroy_internal(bar: [*c]Bar) callconv(.c) void {
    barDestroyInternal(bar);
}

export fn bar_monitor_destroy(m: [*c]Monitor) callconv(.c) void {
    if (m == null or m.*.bar == null) return;
    const bar = m.*.bar;
    m.*.bar = null;
    barDestroyInternal(bar);
}

export fn bar_config_reload() callconv(.c) void {
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.monitors);
    var pos = c.server.monitors.next;
    while (pos != head) : (pos = pos.*.next) {
        const m = @as([*c]Monitor, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Monitor, "link")));
        bar_monitor_destroy(m);
    }
    pos = c.server.monitors.next;
    while (pos != head) : (pos = pos.*.next) {
        const m = @as([*c]Monitor, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Monitor, "link")));
        if (c.config.bar_enable != 0) bar_monitor_create(m);
        arrange_layers(m);
    }
    tray_reload();
    if (c.config.bar_enable == 0) {
        barStopTimers();
        tray_cleanup();
    }
}

export fn bar_update_lock() callconv(.c) void {
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.monitors);
    var pos = c.server.monitors.next;
    while (pos != head) : (pos = pos.*.next) {
        const m = @as([*c]Monitor, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Monitor, "link")));
        if (m.*.bar != null) barLayout(m);
    }
}

export fn bar_handle_button_press(x: f64, y: f64, button: u32) callconv(.c) bool {
    if (c.config.bar_enable == 0) return false;
    const node = acwm_scene_node_at(&c.server.layers_wrap[c.LyrBar].*.node, x, y, null, null);
    if (node == null) return false;
    const data = acwm_scene_node_find(node);
    if (data != null and data.*.owner != null) {
        const btn = @as(*BarButton, @ptrCast(@alignCast(data.*.owner)));
        switch (btn.*.type) {
            c.BarNodeTypeTag => {
                var arg = std.mem.zeroes(c.Arg);
                arg.ui = @as(u32, 1) << @intCast(btn.*.tag - 1);
                _ = bind_to_view(&arg);
                return true;
            },
            c.BarNodeTypeSpecial => {
                var arg = std.mem.zeroes(c.Arg);
                arg.ui = @as(u32, 1) << 31;
                _ = bind_to_view(&arg);
                return true;
            },
            c.BarNodeTypeTray => {
                tray_click(btn.*.item, button);
                return true;
            },
            else => {},
        }
    }
    return true;
}

fn barHandlePrintStatus(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const watch_type = @as(*c.enum_ipc_watch_type, @ptrCast(@alignCast(data.?))).*;
    const bits = c.IPC_WATCH_TAGS | c.IPC_WATCH_ALL_TAGS | c.IPC_WATCH_MONITOR |
        c.IPC_WATCH_CLIENT | c.IPC_WATCH_FOCUSING_CLIENT;
    if ((@as(c_int, @intCast(watch_type)) & bits) != 0)
        bar_refresh_tags();
}

export fn bar_init(loop: ?*c.struct_wl_event_loop) callconv(.c) void {
    tray_init(loop);
    bar_print_status_listener.notify = barHandlePrintStatus;
    c.wl_signal_add(&c.server.print_status_signal, &bar_print_status_listener);
}

export fn bar_tray_sync_all() callconv(.c) void {
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.monitors);
    var pos = c.server.monitors.next;
    while (pos != head) : (pos = pos.*.next) {
        const m = @as([*c]Monitor, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Monitor, "link")));
        if (m.*.bar == null) continue;
        tray_sync_bar(m.*.bar);
        barLayout(m);
    }
}

export fn bar_cleanup() callconv(.c) void {
    c.wl_list_remove(&bar_print_status_listener.link);
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.monitors);
    var pos = c.server.monitors.next;
    while (pos != head) {
        const next = pos.*.next;
        bar_monitor_destroy(@ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Monitor, "link")));
        pos = next;
    }
    if (bar_clock_source != null) { _ = c.wl_event_source_remove(bar_clock_source); bar_clock_source = null; }
    if (bar_status_source != null) { _ = c.wl_event_source_remove(bar_status_source); bar_status_source = null; }
    tray_cleanup();
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/bar_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_tray_init_calls: c_int;
extern var stub_tray_cleanup_calls: c_int;
extern var stub_tray_reload_calls: c_int;
extern var stub_tray_sync_calls: c_int;
extern var stub_tray_detach_calls: c_int;
extern var stub_tray_click_calls: c_int;
extern var stub_bind_calls: c_int;
extern var stub_bind_tags: u32;
extern var stub_arrange_layers_calls: c_int;
extern var stub_active_tagset: u32;
extern var stub_special_active: bool;
extern var stub_special_has: bool;
extern var stub_tag_status: u32;
extern var stub_rect_size_calls: c_int;
extern var stub_rect_w: i32;
extern var stub_rect_h: i32;
extern var stub_radius_calls: c_int;
extern var stub_enable_calls: c_int;
extern var stub_last_enabled: c_int;
extern var stub_pos_calls: c_int;
extern var stub_last_x: i32;
extern var stub_last_y: i32;
extern var stub_node_destroy_calls: c_int;
extern var stub_scene_set_calls: c_int;
extern var stub_at_node: [*c]c.struct_wlr_scene_node;
extern var stub_scene_data: c.AcwmSceneNode;
extern var stub_scene_find: [*c]c.AcwmSceneNode;
extern var stub_timer_add_calls: c_int;
extern var stub_timer_update_calls: c_int;
extern var stub_timer_remove_calls: c_int;
extern var stub_last_timer_ms: i32;
extern var stub_jump_create_calls: c_int;
extern var stub_jump_destroy_calls: c_int;
extern var stub_jump_update_calls: c_int;
extern var stub_jump_focus_calls: c_int;
extern var stub_jump_bg_calls: c_int;
extern var stub_bar_parent: c.struct_wlr_scene_tree;
extern var stub_jump_scene: c.struct_wlr_scene_tree;

fn listInitB(head: *c.struct_wl_list) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

fn listInsertB(head: *c.struct_wl_list, link: *c.struct_wl_list) void {
    link.next = head.next;
    link.prev = @ptrCast(head);
    head.next.*.prev = @ptrCast(link);
    head.next = @ptrCast(link);
}

fn resetBarWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    listInitB(&c.server.monitors);
    listInitB(&c.server.clients);
    listInitB(&c.server.print_status_signal.listener_list);
    bar_clock_source = null;
    bar_status_source = null;
    bar_clock_text = std.mem.zeroes([96]u8);
    bar_battery_text = std.mem.zeroes([64]u8);
    c.config.tag_num = 3;
    c.config.bar_enable = 1;
    c.config.bar_lr_gap = 10;
    c.config.bar_top_gap = 5;
    c.config.bar_height = 30;
    c.config.bar_tray_icon_size = 16;
    c.config.bardata.padding_x = 6;
    stub_tray_init_calls = 0;
    stub_tray_cleanup_calls = 0;
    stub_tray_reload_calls = 0;
    stub_tray_sync_calls = 0;
    stub_tray_detach_calls = 0;
    stub_tray_click_calls = 0;
    stub_bind_calls = 0;
    stub_bind_tags = 0;
    stub_arrange_layers_calls = 0;
    stub_active_tagset = 0;
    stub_special_active = false;
    stub_special_has = false;
    stub_tag_status = 0;
    stub_rect_size_calls = 0;
    stub_rect_w = 0;
    stub_rect_h = 0;
    stub_radius_calls = 0;
    stub_enable_calls = 0;
    stub_last_enabled = -1;
    stub_pos_calls = 0;
    stub_last_x = 0;
    stub_last_y = 0;
    stub_node_destroy_calls = 0;
    stub_scene_set_calls = 0;
    stub_at_node = null;
    stub_scene_find = null;
    stub_timer_add_calls = 0;
    stub_timer_update_calls = 0;
    stub_timer_remove_calls = 0;
    stub_last_timer_ms = 0;
    stub_jump_create_calls = 0;
    stub_jump_destroy_calls = 0;
    stub_jump_update_calls = 0;
    stub_jump_focus_calls = 0;
    stub_jump_bg_calls = 0;
}

var test_output: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);

fn mkMonitor(m: *Monitor) void {
    m.* = std.mem.zeroes(Monitor);
    test_output = std.mem.zeroes(c.struct_wlr_output);
    test_output.scale = 2;
    m.wlr_output = &test_output;
    m.m = .{ .x = 100, .y = 50, .width = 1000, .height = 800 };
    m.w = m.m;
    m.tagset[0] = 1;
}

test "strip height follows bar enable" {
    resetBarWorld();
    try testing.expectEqual(@as(i32, 35), bar_strip_height());
    c.config.bar_enable = 0;
    try testing.expectEqual(@as(i32, 0), bar_strip_height());
}

test "monitor create wires widgets and timers" {
    resetBarWorld();
    var m: Monitor = undefined;
    mkMonitor(&m);
    listInsertB(&c.server.monitors, &m.link);
    bar_monitor_create(&m);
    try testing.expect(m.bar != null);
    try testing.expectEqual(@as(c_int, 1), stub_tray_sync_calls);
    try testing.expectEqual(@as(c_int, 1), stub_tray_reload_calls);
    try testing.expect(stub_timer_add_calls >= 2);
    try testing.expect(stub_jump_create_calls >= 5);
    const bar = m.bar;
    try testing.expectEqual(@as(i32, 4), bar.*.tag_count);
    try testing.expectEqual(@as(c_int, 4), stub_scene_set_calls);
    try testing.expectEqual(@as(i32, 980), stub_rect_w);
    try testing.expectEqual(@as(i32, 30), stub_rect_h);
    try testing.expect(stub_pos_calls > 0);
    bar_monitor_destroy(&m);
    try testing.expect(m.bar == null);
    try testing.expectEqual(@as(c_int, 1), stub_tray_detach_calls);
}

test "refresh tags paints active, urgent and special states" {
    resetBarWorld();
    var m: Monitor = undefined;
    mkMonitor(&m);
    listInsertB(&c.server.monitors, &m.link);
    c.config.bar_enable = 1;
    bar_monitor_create(&m);
    stub_active_tagset = 0b101;
    stub_tag_status = 2;
    stub_special_active = true;
    stub_special_has = true;
    bar_refresh_tags();
    try testing.expect(stub_jump_update_calls > 0);
    try testing.expectEqual(@as(c_int, 1), stub_last_enabled);
    try testing.expect(stub_jump_focus_calls >= 4);
    try testing.expect(stub_jump_bg_calls >= 4);
}

test "visibility hides the bar for fullscreen and locks" {
    resetBarWorld();
    var m: Monitor = undefined;
    mkMonitor(&m);
    listInsertB(&c.server.monitors, &m.link);
    bar_monitor_create(&m);
    var cl: Client = std.mem.zeroes(Client);
    cl.mon = &m;
    cl.tags = 1;
    cl.isfullscreen = 1;
    listInsertB(&c.server.clients, &cl.link);
    bar_monitor_layout(&m);
    try testing.expectEqual(@as(c_int, 0), stub_last_enabled);
    c.server.session_locked = 1;
    bar_monitor_layout(&m);
    try testing.expectEqual(@as(c_int, 0), stub_last_enabled);
}

test "bar clicks route tags, special and tray buttons" {
    resetBarWorld();
    var wrap: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    c.server.layers_wrap[c.LyrBar] = &wrap;
    var node: c.struct_wlr_scene_node = std.mem.zeroes(c.struct_wlr_scene_node);
    stub_at_node = &node;
    stub_scene_find = &stub_scene_data;
    var btn: BarButton = std.mem.zeroes(BarButton);
    stub_scene_data.owner = &btn;
    btn.type = c.BarNodeTypeTag;
    btn.tag = 3;
    try testing.expect(bar_handle_button_press(1, 1, c.BTN_LEFT));
    try testing.expectEqual(@as(u32, 4), stub_bind_tags);
    btn.type = c.BarNodeTypeSpecial;
    try testing.expect(bar_handle_button_press(1, 1, c.BTN_LEFT));
    try testing.expectEqual(@as(u32, @as(u32, 1) << 31), stub_bind_tags);
    btn.type = c.BarNodeTypeTray;
    btn.item = @ptrFromInt(0x1000);
    try testing.expect(bar_handle_button_press(1, 1, c.BTN_RIGHT));
    try testing.expectEqual(@as(c_int, 1), stub_tray_click_calls);
    stub_scene_find = null;
    try testing.expect(bar_handle_button_press(1, 1, c.BTN_LEFT));
    c.config.bar_enable = 0;
    try testing.expect(!bar_handle_button_press(1, 1, c.BTN_LEFT));
}

test "config reload recreates bars and disables timers" {
    resetBarWorld();
    var m: Monitor = undefined;
    mkMonitor(&m);
    listInsertB(&c.server.monitors, &m.link);
    bar_monitor_create(&m);
    const before = stub_jump_create_calls;
    bar_config_reload();
    try testing.expect(m.bar != null);
    try testing.expect(stub_jump_create_calls > before);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_layers_calls);
    c.config.bar_enable = 0;
    bar_config_reload();
    try testing.expect(m.bar == null);
    try testing.expectEqual(@as(c_int, 1), stub_tray_cleanup_calls);
}

test "print-status listener refreshes tags and cleanup clears" {
    resetBarWorld();
    bar_init(null);
    var m: Monitor = undefined;
    mkMonitor(&m);
    listInsertB(&c.server.monitors, &m.link);
    bar_monitor_create(&m);
    var watch_type: c.enum_ipc_watch_type = @intCast(c.IPC_WATCH_TAGS);
    const before = stub_jump_update_calls;
    bar_print_status_listener.notify.?(&bar_print_status_listener, &watch_type);
    try testing.expect(stub_jump_update_calls > before);
    bar_cleanup();
    try testing.expectEqual(@as(c_int, 1), stub_tray_cleanup_calls);
    try testing.expectEqual(@as(c_int, 2), stub_timer_remove_calls);
}
