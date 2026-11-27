//! Port of the query/tag helpers in src/manage/monitor.c
//! (Phase 5, manage slice 5, slice 53).

const std = @import("std");
const c = @import("cc");

const Monitor = c.Monitor;

const TAG0_MASK: u32 = @as(u32, 1) << 31;

extern fn output_from_wlr_output(output: [*c]c.struct_wlr_output) callconv(.c) [*c]Monitor;
extern fn find_device_rule(device: [*c]c.struct_wlr_input_device) callconv(.c) [*c]c.ConfigDeviceRule;
extern fn regex_match(pattern_mb: [*c]const u8, str_mb: [*c]const u8) callconv(.c) i32;
extern fn arrange(m: [*c]Monitor, want_animation: bool, from_view: bool) callconv(.c) void;

fn monitorOpt(p: [*c]Monitor) ?*Monitor {
    return if (p == null) null else @ptrCast(p);
}

fn containerOf(comptime T: type, comptime field: []const u8, link: anytype) *T {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(T, field));
}

fn cString(p: [*c]const u8) ?[]const u8 {
    if (p == null)
        return null;
    return std.mem.span(@as([*:0]const u8, @ptrCast(p)));
}

fn tagBit(tag: u32) u32 {
    if (tag == 0 or tag > 32)
        return 0;
    return @as(u32, 1) << @intCast(tag - 1);
}

export fn is_special_active(m_in: ?*const Monitor) callconv(.c) bool {
    const m = m_in orelse return false;
    return m.isoverview == 0 and (m.tagset[m.seltags] & TAG0_MASK) != 0;
}

export fn get_mon_curtag(m_in: ?*const Monitor) callconv(.c) u32 {
    const m = m_in orelse return 0;
    if (m.pertag == null)
        return 0;
    if (is_special_active(m))
        return 0;
    return if (m.pertag.*.curtag != 0) m.pertag.*.curtag else 1;
}

export fn special_has_clients(m_in: ?*const Monitor) callconv(.c) bool {
    const m = m_in orelse return false;
    var pos = c.server.clients.next;
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(c.Client, "link", pos);
        if (cl.mon == @as([*c]Monitor, @ptrCast(@constCast(m))) and cl.iskilling == 0 and
            cl.isminimized == 0 and (cl.tags & TAG0_MASK) != 0)
            return true;
    }
    return false;
}

export fn get_monitor_active_tagset(m_in: ?*const Monitor) callconv(.c) u32 {
    const m = m_in orelse return 0;
    if (is_special_active(m) and m.pertag != null) {
        const prev_set = m.tagset[m.seltags ^ 1] & c.server.tagmask;
        if (prev_set != 0)
            return prev_set;
        return if (m.pertag.*.prevtag != 0) tagBit(m.pertag.*.prevtag) else 1;
    }
    return m.tagset[m.seltags];
}

export fn monitor_from_direction(dir: c.enum_wlr_direction) callconv(.c) [*c]Monitor {
    const selected = monitorOpt(c.server.selected_monitor) orelse return null;

    if (c.wlr_output_layout_get(c.server.output_layout, selected.wlr_output) == null)
        return selected;

    const dir_bits: u32 = @intCast(dir);
    const mask: u32 = @intCast(c.WLR_DIRECTION_LEFT | c.WLR_DIRECTION_RIGHT | c.WLR_DIRECTION_UP | c.WLR_DIRECTION_DOWN);

    var next = c.wlr_output_layout_adjacent_output(
        c.server.output_layout,
        @intCast(@as(u32, 1) << @intCast(dir_bits)),
        selected.wlr_output,
        @floatFromInt(selected.m.x),
        @floatFromInt(selected.m.y),
    );
    if (next != null and next.*.data != null)
        return @ptrCast(@alignCast(next.*.data.?));

    next = c.wlr_output_layout_farthest_output(
        c.server.output_layout,
        @intCast(dir_bits ^ mask),
        selected.wlr_output,
        @floatFromInt(selected.m.x),
        @floatFromInt(selected.m.y),
    );
    if (next != null and next.*.data != null)
        return @ptrCast(@alignCast(next.*.data.?));
    return selected;
}

export fn monitor_from_cycle(dir: i32) callconv(.c) [*c]Monitor {
    const selected = monitorOpt(c.server.selected_monitor) orelse return null;
    var m: *Monitor = selected;
    const nmons = c.wl_list_length(&c.server.monitors);

    var i: i32 = 0;
    while (i < nmons) : (i += 1) {
        if (dir == c.MON_NEXT)
            m = containerOf(Monitor, "link", m.link.next)
        else
            m = containerOf(Monitor, "link", m.link.prev);
        if (m != selected and m.wlr_output != null and m.wlr_output.*.enabled)
            return m;
    }
    return null;
}

fn currentLayoutId(m: *Monitor) u32 {
    if (m.pertag == null)
        return 0;
    const idx: usize = @intCast(get_mon_curtag(m));
    const layout = m.pertag.*.ltidxs[idx];
    if (layout == null)
        return 0;
    return layout.*.id;
}

export fn is_scroller_layout(m: *Monitor) callconv(.c) bool {
    const id = currentLayoutId(m);
    return id == c.SCROLLER or id == c.VERTICAL_SCROLLER;
}

export fn is_monocle_layout(m: *Monitor) callconv(.c) bool {
    return currentLayoutId(m) == c.MONOCLE;
}

export fn is_centertile_layout(m: *Monitor) callconv(.c) bool {
    return currentLayoutId(m) == c.CENTER_TILE;
}

export fn special_sync_top_layer(special_active: bool) callconv(.c) void {
    const top = c.server.layers[@intCast(c.LyrTop)];
    if (top == null)
        return;
    const target = if (special_active)
        c.server.layers_wrap[@intCast(c.LyrSpecialTop)]
    else
        c.server.layers_wrap[@intCast(c.LyrTop)];
    c.wlr_scene_node_reparent(&top.*.node, target);
}

export fn special_update_dim(m_in: ?*Monitor) callconv(.c) void {
    const m = m_in orelse return;
    if (m.special_dim_rect == null)
        return;
    c.wlr_scene_rect_set_size(m.special_dim_rect, m.m.width, m.m.height);
    c.wlr_scene_node_set_position(&m.special_dim_rect.*.node, m.m.x, m.m.y);
    if (is_special_active(m)) {
        const color = [4]f32{ 0.0, 0.0, 0.0, c.config.special_dim };
        c.wlr_scene_rect_set_color(m.special_dim_rect, &color);
        c.wlr_scene_node_set_enabled(&m.special_dim_rect.*.node, true);
    } else {
        c.wlr_scene_node_set_enabled(&m.special_dim_rect.*.node, false);
    }
}

export fn get_tag_status(tag: u32, m: *Monitor) callconv(.c) u32 {
    const bit = tagBit(tag);
    if (bit == 0)
        return 0;
    var status: u32 = 0;
    var pos = c.server.clients.next;
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(c.Client, "link", pos);
        if (cl.mon == @as([*c]Monitor, @ptrCast(m)) and (cl.tags & bit & c.server.tagmask) != 0) {
            if (cl.isurgent != 0) {
                status = 2;
                break;
            }
            status = 1;
        }
    }
    return status;
}

export fn get_tags_first_tag_num(source_tags: u32) callconv(.c) u32 {
    if (source_tags == 0)
        return 0;
    if ((source_tags & TAG0_MASK) != 0)
        return 0;

    const tag_num: u32 = @intCast(c.config.tag_num);
    var i: u32 = 0;
    var tag: u32 = 0;
    while ((tag & 1) == 0 and source_tags != 0 and i < tag_num) : (i += 1)
        tag = source_tags >> @intCast(i);

    if (i == 1)
        return 1;
    if (i >= tag_num)
        return tag_num;
    return i;
}

export fn get_tags_first_tag(source_tags: u32) callconv(.c) u32 {
    if (source_tags == 0) {
        const selected = monitorOpt(c.server.selected_monitor);
        if (selected != null and is_special_active(selected.?))
            return TAG0_MASK;
        if (selected != null and selected.?.pertag != null) {
            const curtag = selected.?.pertag.*.curtag;
            return tagBit(if (curtag != 0) curtag else 1);
        }
        return 1;
    }

    if ((source_tags & TAG0_MASK) != 0)
        return TAG0_MASK;

    const tag_num: u32 = @intCast(c.config.tag_num);
    var i: u32 = 0;
    var tag: u32 = 0;
    while ((tag & 1) == 0 and source_tags != 0 and i < tag_num) : (i += 1)
        tag = source_tags >> @intCast(i);

    if (i == 1)
        return 1;
    if (i >= tag_num)
        return tagBit(tag_num);
    return tagBit(i);
}

export fn monitor_at_point(x: f64, y: f64) callconv(.c) [*c]Monitor {
    const o = c.wlr_output_layout_output_at(c.server.output_layout, x, y);
    if (o == null or o.*.data == null)
        return null;
    return @ptrCast(@alignCast(o.*.data.?));
}

export fn get_monitor_nearest_to(lx: i32, ly: i32) callconv(.c) [*c]Monitor {
    var closest_x: f64 = 0;
    var closest_y: f64 = 0;
    c.wlr_output_layout_closest_point(
        c.server.output_layout,
        null,
        @floatFromInt(lx),
        @floatFromInt(ly),
        &closest_x,
        &closest_y,
    );
    const o = c.wlr_output_layout_output_at(c.server.output_layout, closest_x, closest_y);
    if (o == null)
        return null;
    return output_from_wlr_output(o);
}

fn specRegex(pattern: []const u8, str: [*c]const u8) bool {
    if (str == null)
        return false;
    var buf: [512]u8 = undefined;
    if (pattern.len >= buf.len)
        return false;
    std.mem.copyForwards(u8, buf[0..pattern.len], pattern);
    buf[pattern.len] = 0;
    return regex_match(&buf, str) != 0;
}

export fn match_monitor_spec(spec_in: [*c]u8, m: *Monitor) callconv(.c) bool {
    if (spec_in == null or m.wlr_output == null)
        return false;
    const spec = std.mem.span(@as([*:0]const u8, @ptrCast(spec_in)));
    const output = m.wlr_output;

    if (std.mem.indexOfScalar(u8, spec, ':') == null)
        return specRegex(spec, output.*.name);

    var name_rule: ?[]const u8 = null;
    var make_rule: ?[]const u8 = null;
    var model_rule: ?[]const u8 = null;
    var serial_rule: ?[]const u8 = null;

    var it = std.mem.splitSequence(u8, spec, "&&");
    while (it.next()) |token| {
        const colon = std.mem.indexOfScalar(u8, token, ':') orelse continue;
        const key = token[0..colon];
        const value = token[colon + 1 ..];
        if (std.mem.eql(u8, key, "name"))
            name_rule = value
        else if (std.mem.eql(u8, key, "make"))
            make_rule = value
        else if (std.mem.eql(u8, key, "model"))
            model_rule = value
        else if (std.mem.eql(u8, key, "serial"))
            serial_rule = value;
    }

    var match = true;
    if (name_rule) |pattern| {
        if (!specRegex(pattern, output.*.name))
            match = false;
    }
    if (make_rule) |value| {
        const make = cString(output.*.make);
        if (make == null or !std.mem.eql(u8, make.?, value))
            match = false;
    }
    if (model_rule) |value| {
        const model = cString(output.*.model);
        if (model == null or !std.mem.eql(u8, model.?, value))
            match = false;
    }
    if (serial_rule) |value| {
        const serial = cString(output.*.serial);
        if (serial == null or !std.mem.eql(u8, serial.?, value))
            match = false;
    }
    return match;
}

export fn device_target_monitor(device: [*c]c.struct_wlr_input_device) callconv(.c) [*c]Monitor {
    const rule = find_device_rule(device);
    if (rule != null and rule.*.monitor[0] != 0) {
        var pos = c.server.monitors.next;
        const head: [*c]c.struct_wl_list = @ptrCast(&c.server.monitors);
        while (pos != head) : (pos = pos.*.next) {
            const m = containerOf(Monitor, "link", pos);
            if (match_monitor_spec(&rule.*.monitor[0], m))
                return m;
        }
    }
    return c.server.selected_monitor;
}

export fn blur_layer_on_wallpaper(layer: u32) callconv(.c) bool {
    return layer == @as(u32, @intCast(c.LyrBottom)) or
        layer == @as(u32, @intCast(c.LyrTile)) or
        layer == @as(u32, @intCast(c.LyrMaximize));
}

export fn set_selected_monitor(m: [*c]Monitor) callconv(.c) void {
    c.server.selected_monitor = m;
}

export fn setgaps(oh: i32, ov: i32, ih: i32, iv: i32) callconv(.c) void {
    const selected = monitorOpt(c.server.selected_monitor) orelse return;
    if (selected.pertag != null and is_special_active(selected)) {
        selected.special_gappoh = @max(oh, 0);
        selected.special_gappov = @max(ov, 0);
        selected.special_gappih = @max(ih, 0);
        selected.special_gappiv = @max(iv, 0);
    } else {
        selected.gappoh = @max(oh, 0);
        selected.gappov = @max(ov, 0);
        selected.gappih = @max(ih, 0);
        selected.gappiv = @max(iv, 0);
    }
    arrange(c.server.selected_monitor, false, false);
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/monitor_query_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_regex_result: c_int;
extern var stub_regex_calls: c_int;
extern var stub_layout_output: c.struct_wlr_output_layout_output;
extern var stub_layout_has_output: bool;
extern var stub_adjacent_output: [*c]c.struct_wlr_output;
extern var stub_farthest_output: [*c]c.struct_wlr_output;
extern var stub_point_output: [*c]c.struct_wlr_output;
extern var stub_closest_x: f64;
extern var stub_closest_y: f64;
extern var stub_adjacent_dir: c_int;
extern var stub_farthest_dir: c_int;
extern var stub_output_monitor: [*c]Monitor;
extern var stub_device_rule: c.ConfigDeviceRule;
extern var stub_device_rule_valid: bool;
extern var stub_arrange_calls: c_int;
extern var stub_reparent_calls: c_int;
extern var stub_last_parent: [*c]c.struct_wlr_scene_tree;
extern var stub_enable_calls: c_int;
extern var stub_enabled_value: c_int;
extern var stub_position_calls: c_int;
extern var stub_pos_x: i32;
extern var stub_pos_y: i32;
extern var stub_rect_size_calls: c_int;
extern var stub_rect_w: i32;
extern var stub_rect_h: i32;
extern var stub_rect_color_calls: c_int;
extern var stub_rect_color: [4]f32;

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

fn resetMonitorWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    c.server.tagmask = 0xffffffff;
    listInit(&c.server.clients);
    listInit(&c.server.monitors);
    stub_regex_result = 0;
    stub_regex_calls = 0;
    stub_layout_output = std.mem.zeroes(c.struct_wlr_output_layout_output);
    stub_layout_has_output = true;
    stub_adjacent_output = null;
    stub_farthest_output = null;
    stub_point_output = null;
    stub_closest_x = 0;
    stub_closest_y = 0;
    stub_adjacent_dir = -1;
    stub_farthest_dir = -1;
    stub_output_monitor = null;
    stub_device_rule = std.mem.zeroes(c.ConfigDeviceRule);
    stub_device_rule_valid = false;
    stub_arrange_calls = 0;
    stub_reparent_calls = 0;
    stub_last_parent = null;
    stub_enable_calls = 0;
    stub_enabled_value = -1;
    stub_position_calls = 0;
    stub_pos_x = 0;
    stub_pos_y = 0;
    stub_rect_size_calls = 0;
    stub_rect_w = 0;
    stub_rect_h = 0;
    stub_rect_color_calls = 0;
    stub_rect_color = std.mem.zeroes([4]f32);
}

fn baseMonitor(m: *Monitor, p: *c.Pertag, out: *c.struct_wlr_output, curtag: u32) void {
    m.* = std.mem.zeroes(Monitor);
    p.* = std.mem.zeroes(c.Pertag);
    out.* = std.mem.zeroes(c.struct_wlr_output);
    m.pertag = p;
    m.wlr_output = out;
    p.curtag = curtag;
    out.enabled = true;
    m.m = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
}

test "special state and current tag helpers" {
    resetMonitorWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    baseMonitor(&m, &p, &out, 5);

    m.tagset[0] = 1;
    m.seltags = 0;
    try testing.expect(!is_special_active(&m));
    try testing.expectEqual(@as(u32, 5), get_mon_curtag(&m));

    m.tagset[0] = TAG0_MASK;
    try testing.expect(is_special_active(&m));
    try testing.expectEqual(@as(u32, 0), get_mon_curtag(&m));
    m.isoverview = 1;
    try testing.expect(!is_special_active(&m));
    m.isoverview = 0;

    p.curtag = 0;
    m.tagset[0] = 1;
    try testing.expectEqual(@as(u32, 1), get_mon_curtag(&m));
    try testing.expectEqual(@as(u32, 0), get_mon_curtag(null));
    m.pertag = null;
    try testing.expectEqual(@as(u32, 0), get_mon_curtag(&m));
    m.pertag = &p;

    m.seltags = 0;
    m.tagset[0] = TAG0_MASK;
    m.tagset[1] = 0b101;
    try testing.expectEqual(@as(u32, 0b101), get_monitor_active_tagset(&m));
    m.tagset[1] = 0;
    p.prevtag = 3;
    try testing.expectEqual(@as(u32, 0b100), get_monitor_active_tagset(&m));
    p.prevtag = 0;
    try testing.expectEqual(@as(u32, 1), get_monitor_active_tagset(&m));

    var cl1: c.Client = std.mem.zeroes(c.Client);
    var cl2: c.Client = std.mem.zeroes(c.Client);
    var cl3: c.Client = std.mem.zeroes(c.Client);
    cl1.mon = &m;
    cl1.tags = TAG0_MASK;
    cl2.mon = &m;
    cl2.tags = TAG0_MASK;
    cl2.isminimized = 1;
    cl3.mon = &m;
    cl3.tags = 1;
    listInsert(&c.server.clients, &cl1.link);
    listInsert(&c.server.clients, &cl2.link);
    listInsert(&c.server.clients, &cl3.link);
    try testing.expect(special_has_clients(&m));
    cl1.iskilling = 1;
    try testing.expect(!special_has_clients(&m));
    try testing.expect(!special_has_clients(null));
}

test "monitor cycle and directional lookup" {
    resetMonitorWorld();
    var p: c.Pertag = undefined;
    var a: Monitor = undefined;
    var b: Monitor = undefined;
    var cc: Monitor = undefined;
    var oa: c.struct_wlr_output = undefined;
    var ob: c.struct_wlr_output = undefined;
    var oc: c.struct_wlr_output = undefined;
    baseMonitor(&a, &p, &oa, 1);
    baseMonitor(&b, &p, &ob, 1);
    baseMonitor(&cc, &p, &oc, 1);
    listInsert(&c.server.monitors, &a.link);
    listInsert(&c.server.monitors, &b.link);
    listInsert(&c.server.monitors, &cc.link);
    c.server.selected_monitor = &b;

    try testing.expect(monitor_from_cycle(c.MON_NEXT) == &a);
    try testing.expect(monitor_from_cycle(c.MON_PREV) == &cc);
    oa.enabled = false;
    try testing.expect(monitor_from_cycle(c.MON_NEXT) == &cc);
    oa.enabled = true;
    c.server.selected_monitor = null;
    try testing.expect(monitor_from_cycle(c.MON_NEXT) == null);

    c.server.selected_monitor = &b;
    var out_c: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    out_c.data = &cc;
    stub_adjacent_output = &out_c;
    try testing.expect(monitor_from_direction(c.WLR_DIRECTION_UP) == &cc);
    try testing.expectEqual(@as(c_int, 2), stub_adjacent_dir);
    try testing.expect(monitor_from_direction(c.WLR_DIRECTION_UP) == &cc);

    var out_a: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    out_a.data = &a;
    stub_adjacent_output = null;
    stub_farthest_output = &out_a;
    try testing.expect(monitor_from_direction(c.WLR_DIRECTION_UP) == &a);
    try testing.expectEqual(@as(c_int, 14), stub_farthest_dir);

    stub_farthest_output = null;
    try testing.expect(monitor_from_direction(c.WLR_DIRECTION_UP) == &b);
    stub_layout_has_output = false;
    try testing.expect(monitor_from_direction(c.WLR_DIRECTION_UP) == &b);
}

test "layout predicates follow the current tag layout" {
    resetMonitorWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    var layout: c.Layout = std.mem.zeroes(c.Layout);
    baseMonitor(&m, &p, &out, 1);
    p.ltidxs[1] = &layout;

    layout.id = @intCast(c.SCROLLER);
    try testing.expect(is_scroller_layout(&m));
    layout.id = @intCast(c.VERTICAL_SCROLLER);
    try testing.expect(is_scroller_layout(&m));
    try testing.expect(!is_monocle_layout(&m));
    layout.id = @intCast(c.MONOCLE);
    try testing.expect(is_monocle_layout(&m));
    try testing.expect(!is_scroller_layout(&m));
    layout.id = @intCast(c.CENTER_TILE);
    try testing.expect(is_centertile_layout(&m));
    layout.id = @intCast(c.DWINDLE);
    try testing.expect(!is_scroller_layout(&m));
    p.ltidxs[1] = null;
    try testing.expect(!is_monocle_layout(&m));
    m.pertag = null;
    try testing.expect(!is_scroller_layout(&m));
}

test "special top layer and dim rect follow view state" {
    resetMonitorWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    baseMonitor(&m, &p, &out, 1);
    var top: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var wrap_top: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var wrap_special: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    c.server.layers[@intCast(c.LyrTop)] = &top;
    c.server.layers_wrap[@intCast(c.LyrTop)] = &wrap_top;
    c.server.layers_wrap[@intCast(c.LyrSpecialTop)] = &wrap_special;

    special_sync_top_layer(true);
    try testing.expect(stub_last_parent == &wrap_special);
    special_sync_top_layer(false);
    try testing.expect(stub_last_parent == &wrap_top);

    var rect: c.struct_wlr_scene_rect = std.mem.zeroes(c.struct_wlr_scene_rect);
    m.special_dim_rect = &rect;
    m.tagset[0] = TAG0_MASK;
    m.seltags = 0;
    c.config.special_dim = 0.5;
    special_update_dim(&m);
    try testing.expectEqual(@as(i32, 1000), stub_rect_w);
    try testing.expectEqual(@as(i32, 800), stub_rect_h);
    try testing.expectEqual(@as(c_int, 1), stub_rect_color_calls);
    try testing.expectApproxEqAbs(@as(f32, 0.5), stub_rect_color[3], 1e-6);
    try testing.expectEqual(@as(c_int, 1), stub_enabled_value);

    m.tagset[0] = 1;
    special_update_dim(&m);
    try testing.expectEqual(@as(c_int, 0), stub_enabled_value);
    special_update_dim(null);
}

test "tag status and first-tag selection" {
    resetMonitorWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    baseMonitor(&m, &p, &out, 3);
    c.server.tagmask = 0xffffffff;
    c.config.tag_num = 5;

    var cl1: c.Client = std.mem.zeroes(c.Client);
    var cl2: c.Client = std.mem.zeroes(c.Client);
    cl1.mon = &m;
    cl1.tags = 0b10;
    cl2.mon = &m;
    cl2.tags = 0b100;
    cl2.isurgent = 1;
    listInsert(&c.server.clients, &cl1.link);
    listInsert(&c.server.clients, &cl2.link);

    try testing.expectEqual(@as(u32, 1), get_tag_status(2, &m));
    try testing.expectEqual(@as(u32, 2), get_tag_status(3, &m));
    try testing.expectEqual(@as(u32, 0), get_tag_status(4, &m));
    try testing.expectEqual(@as(u32, 0), get_tag_status(0, &m));

    try testing.expectEqual(@as(u32, 0), get_tags_first_tag_num(0));
    try testing.expectEqual(@as(u32, 0), get_tags_first_tag_num(TAG0_MASK));
    try testing.expectEqual(@as(u32, 1), get_tags_first_tag_num(1));
    try testing.expectEqual(@as(u32, 2), get_tags_first_tag_num(2));
    try testing.expectEqual(@as(u32, 3), get_tags_first_tag_num(0b100));
    try testing.expectEqual(@as(u32, 5), get_tags_first_tag_num(0b100000));

    c.server.selected_monitor = &m;
    m.tagset[0] = 1;
    try testing.expectEqual(@as(u32, 4), get_tags_first_tag(0));
    m.tagset[0] = TAG0_MASK;
    try testing.expectEqual(TAG0_MASK, get_tags_first_tag(0));
    c.server.selected_monitor = null;
    try testing.expectEqual(@as(u32, 1), get_tags_first_tag(0));

    try testing.expectEqual(@as(u32, 1), get_tags_first_tag(1));
    try testing.expectEqual(@as(u32, 2), get_tags_first_tag(0b10));
    try testing.expectEqual(TAG0_MASK, get_tags_first_tag(TAG0_MASK));
    try testing.expectEqual(@as(u32, 16), get_tags_first_tag(0b100000));
}

test "point and nearest monitor lookups" {
    resetMonitorWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    baseMonitor(&m, &p, &out, 1);
    var point_out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    point_out.data = &m;
    stub_point_output = &point_out;
    stub_layout_has_output = true;
    try testing.expect(monitor_at_point(10, 20) == &m);
    stub_point_output = null;
    try testing.expect(monitor_at_point(10, 20) == null);

    stub_point_output = &point_out;
    stub_layout_has_output = true;
    stub_closest_x = 7;
    stub_closest_y = 9;
    stub_output_monitor = &m;
    try testing.expect(get_monitor_nearest_to(100, 200) == &m);
    stub_layout_has_output = false;
    try testing.expect(get_monitor_nearest_to(100, 200) == null);
}

test "monitor spec matching by name and component rules" {
    resetMonitorWorld();
    var m: Monitor = std.mem.zeroes(Monitor);
    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    out.name = @ptrCast(@constCast("DP-1"));
    out.make = @ptrCast(@constCast("Acme"));
    out.model = @ptrCast(@constCast("Panel"));
    out.serial = @ptrCast(@constCast("1234"));
    m.wlr_output = &out;

    try testing.expect(!match_monitor_spec(null, &m));
    m.wlr_output = null;
    try testing.expect(!match_monitor_spec(@ptrCast(@constCast("DP-1")), &m));
    m.wlr_output = &out;

    try testing.expect(match_monitor_spec(@ptrCast(@constCast("DP-1")), &m));
    try testing.expect(!match_monitor_spec(@ptrCast(@constCast("HDMI-1")), &m));

    try testing.expect(match_monitor_spec(@ptrCast(@constCast("name:DP-1&&make:Acme&&model:Panel&&serial:1234")), &m));
    try testing.expect(!match_monitor_spec(@ptrCast(@constCast("make:Other")), &m));
    try testing.expect(!match_monitor_spec(@ptrCast(@constCast("model:Other")), &m));
    try testing.expect(!match_monitor_spec(@ptrCast(@constCast("serial:9999")), &m));
    try testing.expect(match_monitor_spec(@ptrCast(@constCast("unknown:value")), &m));

    out.make = null;
    try testing.expect(!match_monitor_spec(@ptrCast(@constCast("make:Acme")), &m));
}

test "device target monitor prefers rule matches" {
    resetMonitorWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    var other: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    var out2: c.struct_wlr_output = undefined;
    baseMonitor(&m, &p, &out, 1);
    baseMonitor(&other, &p, &out2, 1);
    out.name = @ptrCast(@constCast("DP-1"));
    out2.name = @ptrCast(@constCast("HDMI-1"));
    listInsert(&c.server.monitors, &m.link);
    listInsert(&c.server.monitors, &other.link);
    c.server.selected_monitor = &other;
    stub_device_rule_valid = true;
    @memset(&stub_device_rule.monitor, 0);
    std.mem.copyForwards(u8, stub_device_rule.monitor[0..4], "DP-1");
    try testing.expect(device_target_monitor(null) == &m);

    stub_device_rule.monitor[0] = 0;
    try testing.expect(device_target_monitor(null) == &other);
    stub_device_rule_valid = false;
    try testing.expect(device_target_monitor(null) == &other);
}

test "wallpaper layers, selection and gaps" {
    resetMonitorWorld();
    try testing.expect(blur_layer_on_wallpaper(@intCast(c.LyrBottom)));
    try testing.expect(blur_layer_on_wallpaper(@intCast(c.LyrTile)));
    try testing.expect(blur_layer_on_wallpaper(@intCast(c.LyrMaximize)));
    try testing.expect(!blur_layer_on_wallpaper(@intCast(c.LyrTop)));

    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    baseMonitor(&m, &p, &out, 1);
    set_selected_monitor(&m);
    try testing.expect(c.server.selected_monitor == &m);

    m.tagset[0] = 1;
    setgaps(10, -5, 3, 7);
    try testing.expectEqual(@as(i32, 10), m.gappoh);
    try testing.expectEqual(@as(i32, 0), m.gappov);
    try testing.expectEqual(@as(i32, 3), m.gappih);
    try testing.expectEqual(@as(i32, 7), m.gappiv);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);

    m.tagset[0] = TAG0_MASK;
    setgaps(1, 2, 3, 4);
    try testing.expectEqual(@as(i32, 1), m.special_gappoh);
    try testing.expectEqual(@as(i32, 4), m.special_gappiv);
    try testing.expectEqual(@as(i32, 3), m.gappih);

    c.server.selected_monitor = null;
    setgaps(9, 9, 9, 9);
    try testing.expectEqual(@as(c_int, 2), stub_arrange_calls);
}
