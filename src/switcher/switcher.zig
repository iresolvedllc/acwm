//! Port of switcher/switcher.c (Phase 5, switcher slice 1, slice 82).

const std = @import("std");
const c = @import("cc");
const build_options = @import("build_options");

const Client = c.Client;
const Monitor = c.Monitor;
const Tile = c.struct_switcher_tile;
const Entry = c.struct_switcher_surface;
const State = c.struct_switcher_state;
const Box = c.struct_wlr_box;
const FBox = c.struct_wlr_fbox;

const SW_PAD = 6;
const SW_GAP = 14;
const SW_MARGIN = 28;
const SW_PANEL_FRAC: f32 = 0.8;
const SW_TILE_FRAC: f32 = 0.25;
const SW_ASPECT_MIN: f32 = 9.0 / 16.0;
const SW_ASPECT_MAX: f32 = 12.0 / 5.0;

extern fn client_get_clip(cl: [*c]Client, clip: *Box) callconv(.c) void;
extern fn client_surface(cl: [*c]Client) callconv(.c) [*c]c.struct_wlr_surface;
extern fn client_is_unmanaged(cl: [*c]Client) callconv(.c) i32;
extern fn client_is_x11_popup(cl: [*c]Client) callconv(.c) i32;
extern fn client_is_x11(cl: [*c]Client) callconv(.c) i32;
extern fn client_send_frame_done(cl: [*c]Client, now: *const c.struct_timespec) callconv(.c) void;
extern fn client_focus(cl: [*c]Client, lift: i32) callconv(.c) void;
extern fn client_view_on_monitor(arg: [*c]const c.Arg, animate: bool, m: [*c]Monitor, from_rule: bool) callconv(.c) void;
extern fn get_tags_first_tag(tags: u32) callconv(.c) u32;
extern fn wlr_scene_tree_create(parent: [*c]c.struct_wlr_scene_tree) callconv(.c) [*c]c.struct_wlr_scene_tree;
extern fn wlr_scene_rect_create(parent: [*c]c.struct_wlr_scene_tree, width: c_int, height: c_int, color: [*c]const f32) callconv(.c) [*c]c.struct_wlr_scene_rect;
extern fn wlr_scene_rect_set_size(rect: [*c]c.struct_wlr_scene_rect, width: c_int, height: c_int) callconv(.c) void;
extern fn wlr_scene_rect_set_color(rect: [*c]c.struct_wlr_scene_rect, color: [*c]const f32) callconv(.c) void;
extern fn wlr_scene_buffer_create(parent: [*c]c.struct_wlr_scene_tree, buffer: ?*c.struct_wlr_buffer) callconv(.c) [*c]c.struct_wlr_scene_buffer;
extern fn wlr_scene_buffer_set_filter_mode(buffer: [*c]c.struct_wlr_scene_buffer, mode: c.enum_wlr_scale_filter_mode) callconv(.c) void;
extern fn wlr_scene_buffer_set_source_box(buffer: [*c]c.struct_wlr_scene_buffer, box: [*c]const FBox) callconv(.c) void;
extern fn wlr_scene_buffer_set_dest_size(buffer: [*c]c.struct_wlr_scene_buffer, width: c_int, height: c_int) callconv(.c) void;
extern fn wlr_scene_buffer_set_transform(buffer: [*c]c.struct_wlr_scene_buffer, transform: c.enum_wl_output_transform) callconv(.c) void;
extern fn wlr_scene_buffer_set_opacity(buffer: [*c]c.struct_wlr_scene_buffer, opacity: f32) callconv(.c) void;
extern fn wlr_scene_buffer_set_transfer_function(buffer: [*c]c.struct_wlr_scene_buffer, tf: c.enum_wlr_color_transfer_function) callconv(.c) void;
extern fn wlr_scene_buffer_set_primaries(buffer: [*c]c.struct_wlr_scene_buffer, primaries: c.enum_wlr_color_named_primaries) callconv(.c) void;
extern fn wlr_scene_buffer_set_color_encoding(buffer: [*c]c.struct_wlr_scene_buffer, encoding: c.enum_wlr_color_encoding) callconv(.c) void;
extern fn wlr_scene_buffer_set_color_range(buffer: [*c]c.struct_wlr_scene_buffer, range: c.enum_wlr_color_range) callconv(.c) void;
extern fn wlr_scene_buffer_set_buffer(buffer: [*c]c.struct_wlr_scene_buffer, buffer: ?*c.struct_wlr_buffer) callconv(.c) void;
extern fn wlr_scene_buffer_set_buffer_with_options(buffer: [*c]c.struct_wlr_scene_buffer, buf: [*c]c.struct_wlr_buffer, options: [*c]const c.struct_wlr_scene_buffer_set_buffer_options) callconv(.c) void;
extern fn wlr_scene_node_set_position(node: [*c]c.struct_wlr_scene_node, x: i32, y: i32) callconv(.c) void;
extern fn wlr_scene_node_destroy(node: [*c]c.struct_wlr_scene_node) callconv(.c) void;
extern fn wlr_scene_node_coords(node: [*c]c.struct_wlr_scene_node, x: *i32, y: *i32) callconv(.c) bool;
extern fn wlr_surface_for_each_surface(surface: [*c]c.struct_wlr_surface, iterator: *const fn ([*c]c.struct_wlr_surface, i32, i32, ?*anyopaque) callconv(.c) void, data: ?*anyopaque) callconv(.c) void;
extern fn wlr_surface_get_buffer_source_box(surface: [*c]c.struct_wlr_surface, box: *FBox) callconv(.c) void;
extern fn wlr_surface_send_frame_done(surface: [*c]c.struct_wlr_surface, when: *const c.struct_timespec) callconv(.c) void;
extern fn wlr_alpha_modifier_v1_get_surface_state(surface: [*c]c.struct_wlr_surface) callconv(.c) ?*const c.struct_wlr_alpha_modifier_surface_v1_state;
extern fn wlr_surface_get_image_description_v1_data(surface: [*c]c.struct_wlr_surface) callconv(.c) ?*const c.struct_wlr_image_description_v1_data;
extern fn wlr_color_manager_v1_transfer_function_to_wlr(tf: c.enum_wp_color_manager_v1_transfer_function) callconv(.c) c.enum_wlr_color_transfer_function;
extern fn wlr_color_manager_v1_primaries_to_wlr(primaries: c.enum_wp_color_manager_v1_primaries) callconv(.c) c.enum_wlr_color_named_primaries;
extern fn wlr_color_representation_v1_get_surface_state(surface: [*c]c.struct_wlr_surface) callconv(.c) ?*const c.struct_wlr_color_representation_v1_surface_state;
extern fn wlr_color_representation_v1_color_encoding_to_wlr(coefficients: c.enum_wp_color_manager_v1_primaries) callconv(.c) c.enum_wlr_color_encoding;
extern fn wlr_color_representation_v1_color_range_to_wlr(range: c.enum_wp_color_manager_v1_primaries) callconv(.c) c.enum_wlr_color_range;
extern fn wlr_linux_drm_syncobj_v1_get_surface_state(surface: [*c]c.struct_wlr_surface) callconv(.c) ?*c.struct_wlr_linux_drm_syncobj_surface_v1_state;
extern fn wlr_linux_drm_syncobj_v1_state_add_release_point(state: *c.struct_wlr_linux_drm_syncobj_surface_v1_state, timeline: ?*c.struct_wlr_drm_syncobj_timeline, point: u64, loop: ?*c.struct_wl_event_loop) callconv(.c) bool;
extern fn wlr_presentation_surface_scanned_out_on_output(surface: [*c]c.struct_wlr_surface, output: [*c]c.struct_wlr_output) callconv(.c) void;
extern fn wlr_presentation_surface_textured_on_output(surface: [*c]c.struct_wlr_surface, output: [*c]c.struct_wlr_output) callconv(.c) void;
extern fn wlr_box_contains_point(box: *const Box, x: f64, y: f64) callconv(.c) bool;
extern fn clock_gettime(clock: c.clockid_t, tp: *c.struct_timespec) callconv(.c) c_int;

var switcher_state: State = std.mem.zeroes(State);
export const switcher_panel_color = [4]f32{ 0.09, 0.09, 0.11, 0.92 };

fn VISIBLEON(cl: [*c]const Client, m: [*c]const Monitor) bool {
    if (cl == null or m == null or cl.*.mon != m or cl.*.isminimized != 0)
        return false;
    return (cl.*.tags & m.*.tagset[m.*.seltags]) != 0 or cl.*.isglobal != 0 or cl.*.isunglobal != 0;
}

fn entryFromListener(listener: [*c]c.struct_wl_listener, comptime field: []const u8) *Entry {
    return @ptrFromInt(@intFromPtr(listener) - @offsetOf(Entry, field));
}

export fn switcher_content_size(cl: [*c]Client, w: *f32, h: *f32) callconv(.c) void {
    if (build_options.xwayland and client_is_x11(cl) != 0) {
        const s = client_surface(cl);
        w.* = @floatFromInt(s.*.current.width);
        h.* = @floatFromInt(s.*.current.height);
        return;
    }
    w.* = @floatFromInt(cl.*.surface.xdg.*.geometry.width);
    h.* = @floatFromInt(cl.*.surface.xdg.*.geometry.height);
}

export fn switcher_tile_layout(tile: [*c]Tile) callconv(.c) void {
    var clip = std.mem.zeroes(Box);
    client_get_clip(tile.*.c, &clip);
    var src_w: f32 = 0;
    var src_h: f32 = 0;
    switcher_content_size(tile.*.c, &src_w, &src_h);
    if (src_w <= 0 or src_h <= 0)
        return;
    const scale_x = @as(f32, @floatFromInt(tile.*.cw)) / src_w;
    const scale_y = @as(f32, @floatFromInt(switcher_state.tile_h)) / src_h;
    const head: [*c]c.struct_wl_list = @ptrCast(&tile.*.surfaces);
    var pos = tile.*.surfaces.next;
    while (pos != head) : (pos = pos.*.next) {
        const entry = @as(*Entry, @ptrFromInt(@intFromPtr(pos) - @offsetOf(Entry, "link")));
        const s = entry.surface;
        if (entry.is_root) {
            const ratio_x: f32 = if (s.*.current.width > 0)
                @as(f32, @floatFromInt(s.*.current.buffer_width)) / @as(f32, @floatFromInt(s.*.current.width))
            else
                1.0;
            const ratio_y: f32 = if (s.*.current.height > 0)
                @as(f32, @floatFromInt(s.*.current.buffer_height)) / @as(f32, @floatFromInt(s.*.current.height))
            else
                1.0;
            var src = FBox{
                .x = @as(f32, @floatFromInt(clip.x)) * ratio_x,
                .y = @as(f32, @floatFromInt(clip.y)) * ratio_y,
                .width = src_w * ratio_x,
                .height = src_h * ratio_y,
            };
            c.wlr_scene_buffer_set_source_box(entry.buffer, &src);
            c.wlr_scene_node_set_position(&entry.buffer.*.node, 0, 0);
            c.wlr_scene_buffer_set_dest_size(entry.buffer, tile.*.cw, switcher_state.tile_h);
        } else {
            c.wlr_scene_node_set_position(&entry.buffer.*.node, @intFromFloat((@as(f32, @floatFromInt(entry.sx)) - @as(f32, @floatFromInt(clip.x))) * scale_x), @intFromFloat((@as(f32, @floatFromInt(entry.sy)) - @as(f32, @floatFromInt(clip.y))) * scale_y));
            c.wlr_scene_buffer_set_dest_size(entry.buffer, @intFromFloat(@as(f32, @floatFromInt(s.*.current.width)) * scale_x), @intFromFloat(@as(f32, @floatFromInt(s.*.current.height)) * scale_y));
        }
    }
}

export fn switcher_surface_finish(entry: [*c]Entry) callconv(.c) void {
    c.wl_list_remove(&entry.*.commit.link);
    c.wl_list_remove(&entry.*.destroy.link);
    c.wl_list_remove(&entry.*.output_sample.link);
    c.wl_list_remove(&entry.*.frame_done.link);
    c.wl_list_remove(&entry.*.link);
    c.free(entry);
}

export fn switcher_surface_update_buffer(entry: [*c]Entry) callconv(.c) void {
    const surface = entry.*.surface;
    const buffer = entry.*.buffer;
    var source = std.mem.zeroes(FBox);
    c.wlr_surface_get_buffer_source_box(surface, &source);
    c.wlr_scene_buffer_set_source_box(buffer, &source);
    c.wlr_scene_buffer_set_transform(buffer, surface.*.current.transform);
    const alpha = c.wlr_alpha_modifier_v1_get_surface_state(surface);
    c.wlr_scene_buffer_set_opacity(buffer, if (alpha != null) @as(f32, @floatCast(alpha.*.multiplier)) else 1.0);
    var tf: c.enum_wlr_color_transfer_function = c.WLR_COLOR_TRANSFER_FUNCTION_GAMMA22;
    var primaries: c.enum_wlr_color_named_primaries = c.WLR_COLOR_NAMED_PRIMARIES_SRGB;
    const image = c.wlr_surface_get_image_description_v1_data(surface);
    if (image != null) {
        tf = c.wlr_color_manager_v1_transfer_function_to_wlr(image.*.tf_named);
        primaries = c.wlr_color_manager_v1_primaries_to_wlr(image.*.primaries_named);
    }
    c.wlr_scene_buffer_set_transfer_function(buffer, tf);
    c.wlr_scene_buffer_set_primaries(buffer, primaries);
    var encoding: c.enum_wlr_color_encoding = c.WLR_COLOR_ENCODING_NONE;
    var range: c.enum_wlr_color_range = c.WLR_COLOR_RANGE_NONE;
    const representation = c.wlr_color_representation_v1_get_surface_state(surface);
    if (representation != null) {
        if (representation.*.coefficients != 0)
            encoding = c.wlr_color_representation_v1_color_encoding_to_wlr(@intCast(representation.*.coefficients));
        if (representation.*.range != 0)
            range = c.wlr_color_representation_v1_color_range_to_wlr(@intCast(representation.*.range));
    }
    c.wlr_scene_buffer_set_color_encoding(buffer, encoding);
    c.wlr_scene_buffer_set_color_range(buffer, range);
    if (surface.*.buffer == null or surface.*.current.width <= 0 or surface.*.current.height <= 0) {
        c.wlr_scene_buffer_set_buffer(buffer, null);
        return;
    }
    var options = std.mem.zeroes(c.struct_wlr_scene_buffer_set_buffer_options);
    options.damage = &surface.*.buffer_damage;
    const syncobj = c.wlr_linux_drm_syncobj_v1_get_surface_state(surface);
    if (syncobj != null) {
        options.wait_timeline = @ptrCast(syncobj.*.acquire_timeline);
        options.wait_point = syncobj.*.acquire_point;
    }
    c.wlr_scene_buffer_set_buffer_with_options(buffer, &surface.*.buffer.*.base, &options);
}

export fn handle_switcher_surface_commit(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const entry = entryFromListener(listener, "commit");
    switcher_surface_update_buffer(entry);
    switcher_tile_layout(entry.tile);
}

export fn handle_switcher_surface_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const entry = entryFromListener(listener, "destroy");
    const buffer = entry.buffer;
    switcher_surface_finish(entry);
    c.wlr_scene_node_destroy(&buffer.*.node);
}

export fn handle_switcher_surface_output_sample(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    const entry = entryFromListener(listener, "output_sample");
    const event = @as(*c.struct_wlr_scene_output_sample_event, @ptrCast(@alignCast(data.?)));
    if (entry.buffer.*.primary_output != event.*.output)
        return;
    const output = event.*.output.*.output;
    if (event.*.direct_scanout)
        c.wlr_presentation_surface_scanned_out_on_output(entry.surface, output)
    else
        c.wlr_presentation_surface_textured_on_output(entry.surface, output);
    const syncobj = c.wlr_linux_drm_syncobj_v1_get_surface_state(entry.surface);
    if (syncobj != null and event.*.release_timeline != null)
        _ = c.wlr_linux_drm_syncobj_v1_state_add_release_point(syncobj, event.*.release_timeline, event.*.release_point, output.*.event_loop);
}

export fn handle_switcher_surface_frame_done(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    const entry = entryFromListener(listener, "frame_done");
    const event = @as(*c.struct_wlr_scene_frame_done_event, @ptrCast(@alignCast(data.?)));
    if (entry.buffer.*.primary_output == event.*.output)
        c.wlr_surface_send_frame_done(entry.surface, &event.*.when);
}

export fn switcher_tile_add_surface(surface: [*c]c.struct_wlr_surface, sx: i32, sy: i32, data: ?*anyopaque) callconv(.c) void {
    const tile = @as([*c]Tile, @ptrCast(@alignCast(data.?)));
    const buffer = c.wlr_scene_buffer_create(tile.*.content, null);
    if (buffer == null) return;
    const raw = c.ecalloc(1, @sizeOf(Entry)) orelse return;
    const entry = @as(*Entry, @ptrCast(@alignCast(raw)));
    entry.tile = tile;
    entry.surface = surface;
    entry.buffer = buffer;
    entry.sx = sx;
    entry.sy = sy;
    entry.is_root = surface == client_surface(tile.*.c);
    c.wlr_scene_buffer_set_filter_mode(buffer, c.WLR_SCALE_FILTER_BILINEAR);
    switcher_surface_update_buffer(entry);
    entry.commit.notify = handle_switcher_surface_commit;
    c.wl_signal_add(&surface.*.events.commit, &entry.commit);
    entry.destroy.notify = handle_switcher_surface_destroy;
    c.wl_signal_add(&surface.*.events.destroy, &entry.destroy);
    entry.output_sample.notify = handle_switcher_surface_output_sample;
    c.wl_signal_add(&buffer.*.events.output_sample, &entry.output_sample);
    entry.frame_done.notify = handle_switcher_surface_frame_done;
    c.wl_signal_add(&buffer.*.events.frame_done, &entry.frame_done);
    c.wl_list_insert(&tile.*.surfaces, &entry.link);
}

export fn switcher_tile_create(tile: [*c]Tile, cl: [*c]Client) callconv(.c) void {
    tile.*.c = cl;
    c.wl_list_init(&tile.*.surfaces);
    var src_w: f32 = 0;
    var src_h: f32 = 0;
    switcher_content_size(cl, &src_w, &src_h);
    var aspect: f32 = if (src_w > 0 and src_h > 0) src_w / src_h else 1.0;
    aspect = @max(SW_ASPECT_MIN, @min(aspect, SW_ASPECT_MAX));
    tile.*.cw = @max(1, @as(i32, @intFromFloat(@as(f32, @floatFromInt(switcher_state.tile_h)) * aspect)));
    tile.*.tree = c.wlr_scene_tree_create(switcher_state.tree);
    tile.*.frame = c.wlr_scene_rect_create(tile.*.tree, 1, 1, &c.config.bordercolor);
    tile.*.content = c.wlr_scene_tree_create(tile.*.tree);
    c.wlr_scene_node_set_position(&tile.*.content.*.node, SW_PAD, SW_PAD);
    c.wlr_surface_for_each_surface(client_surface(cl), switcher_tile_add_surface, tile);
    switcher_tile_layout(tile);
}

export fn switcher_layout() callconv(.c) void {
    const frame_h = switcher_state.tile_h + 2 * SW_PAD;
    const maxrow_w = @max(1, @as(i32, @intFromFloat(@as(f32, @floatFromInt(switcher_state.mon.*.m.width)) * SW_PANEL_FRAC)) - 2 * SW_MARGIN);
    var nrows: i32 = 1;
    var row_w: i32 = 0;
    var content_w: i32 = 0;
    var i: i32 = 0;
    while (i < switcher_state.count) : (i += 1) {
        const tile = switcher_state.tiles[@intCast(i)];
        const fw = tile.*.cw + 2 * SW_PAD;
        if (row_w > 0 and row_w + SW_GAP + fw > maxrow_w) {
            nrows += 1;
            row_w = fw;
        } else {
            row_w = if (row_w == 0) fw else row_w + SW_GAP + fw;
        }
        tile.*.row = nrows - 1;
        content_w = @max(content_w, row_w);
    }
    const rowsw = @as([*c]i32, @ptrCast(@alignCast(c.ecalloc(@intCast(nrows), @sizeOf(i32)))));
    i = 0;
    while (i < switcher_state.count) : (i += 1) {
        const tile = switcher_state.tiles[@intCast(i)];
        const fw = tile.*.cw + 2 * SW_PAD;
        rowsw[@intCast(tile.*.row)] += if (rowsw[@intCast(tile.*.row)] == 0) fw else SW_GAP + fw;
    }
    const panel_w = content_w + 2 * SW_MARGIN;
    const panel_h = 2 * SW_MARGIN + nrows * frame_h + (nrows - 1) * SW_GAP;
    c.wlr_scene_node_set_position(&switcher_state.tree.*.node, switcher_state.mon.*.m.x + @divTrunc(switcher_state.mon.*.m.width - panel_w, 2), switcher_state.mon.*.m.y + @divTrunc(switcher_state.mon.*.m.height - panel_h, 2));
    c.wlr_scene_rect_set_size(switcher_state.bg, panel_w, panel_h);
    var row: i32 = -1;
    var x: i32 = 0;
    i = 0;
    while (i < switcher_state.count) : (i += 1) {
        const tile = switcher_state.tiles[@intCast(i)];
        if (tile.*.row != row) {
            row = tile.*.row;
            x = SW_MARGIN + @divTrunc(content_w - rowsw[@intCast(row)], 2);
        }
        c.wlr_scene_node_set_position(&tile.*.tree.*.node, x, SW_MARGIN + row * (frame_h + SW_GAP));
        c.wlr_scene_rect_set_size(tile.*.frame, tile.*.cw + 2 * SW_PAD, frame_h);
        x += tile.*.cw + 2 * SW_PAD + SW_GAP;
    }
    c.free(rowsw);
}

export fn switcher_apply_highlight() callconv(.c) void {
    var i: i32 = 0;
    while (i < switcher_state.count) : (i += 1)
        c.wlr_scene_rect_set_color(switcher_state.tiles[@intCast(i)].*.frame, if (i == switcher_state.index) &c.config.focuscolor else &c.config.bordercolor);
}

export fn switcher_close() callconv(.c) void {
    if (!switcher_is_active()) return;
    var i: i32 = 0;
    while (i < switcher_state.count) : (i += 1) {
        const head: [*c]c.struct_wl_list = @ptrCast(&switcher_state.tiles[@intCast(i)].*.surfaces);
        var pos = switcher_state.tiles[@intCast(i)].*.surfaces.next;
        while (pos != head) {
            const next = pos.*.next;
            switcher_surface_finish(@ptrFromInt(@intFromPtr(pos) - @offsetOf(Entry, "link")));
            pos = next;
        }
    }
    c.wlr_scene_node_destroy(&switcher_state.tree.*.node);
    i = 0;
    while (i < switcher_state.count) : (i += 1)
        c.free(switcher_state.tiles[@intCast(i)]);
    c.free(@ptrCast(switcher_state.tiles));
    switcher_state = std.mem.zeroes(State);
}

export fn switcher_remove_client(cl: [*c]Client) callconv(.c) void {
    if (!switcher_is_active()) return;
    var i: i32 = 0;
    while (i < switcher_state.count) : (i += 1)
        if (switcher_state.tiles[@intCast(i)].*.c == cl) break;
    if (i == switcher_state.count) return;
    const head: [*c]c.struct_wl_list = @ptrCast(&switcher_state.tiles[@intCast(i)].*.surfaces);
    var pos = switcher_state.tiles[@intCast(i)].*.surfaces.next;
    while (pos != head) {
        const next = pos.*.next;
        switcher_surface_finish(@ptrFromInt(@intFromPtr(pos) - @offsetOf(Entry, "link")));
        pos = next;
    }
    c.wlr_scene_node_destroy(&switcher_state.tiles[@intCast(i)].*.tree.*.node);
    c.free(switcher_state.tiles[@intCast(i)]);
    if (switcher_state.index > i) switcher_state.index -= 1;
    var j = i;
    while (j < switcher_state.count - 1) : (j += 1)
        switcher_state.tiles[@intCast(j)] = switcher_state.tiles[@intCast(j + 1)];
    switcher_state.count -= 1;
    if (switcher_state.count == 0) {
        switcher_close();
        return;
    }
    if (switcher_state.index >= switcher_state.count) switcher_state.index = switcher_state.count - 1;
    switcher_layout();
    switcher_apply_highlight();
}

fn switcherClientEligible(cl: [*c]Client) bool {
    return cl != null and cl.*.mon != null and cl.*.iskilling == 0 and cl.*.isminimized == 0 and
        cl.*.isunglobal == 0 and client_surface(cl) != null and client_surface(cl).*.mapped and
        client_is_unmanaged(cl) == 0 and client_is_x11_popup(cl) == 0;
}

export fn switcher_commit_client(tc: [*c]Client) callconv(.c) void {
    switcher_close();
    if (!switcherClientEligible(tc)) return;
    if (!VISIBLEON(tc, tc.*.mon)) {
        var arg = std.mem.zeroes(c.Arg);
        arg.ui = get_tags_first_tag(tc.*.tags);
        client_view_on_monitor(&arg, true, tc.*.mon, true);
    }
    client_focus(tc, 1);
}

export fn switcher_commit() callconv(.c) void {
    if (!switcher_is_active()) return;
    switcher_commit_client(switcher_state.tiles[@intCast(switcher_state.index)].*.c);
}

export fn switcher_client_at(lx: f64, ly: f64) callconv(.c) [*c]Client {
    if (!switcher_is_active()) return null;
    var i: i32 = 0;
    while (i < switcher_state.count) : (i += 1) {
        const tile = switcher_state.tiles[@intCast(i)];
        var box = Box{ .x = 0, .y = 0, .width = tile.*.cw + 2 * SW_PAD, .height = switcher_state.tile_h + 2 * SW_PAD };
        if (!c.wlr_scene_node_coords(&tile.*.tree.*.node, &box.x, &box.y) or
            !c.wlr_box_contains_point(&box, lx, ly))
            continue;
        return tile.*.c;
    }
    return null;
}

export fn switcher_open(scope: i32, dir: i32) callconv(.c) void {
    const headm: [*c]c.struct_wl_list = @ptrCast(&c.server.monitors);
    var mpos = c.server.monitors.next;
    while (mpos != headm) : (mpos = mpos.*.next) {
        const m = @as([*c]Monitor, @ptrFromInt(@intFromPtr(mpos) - @offsetOf(c.Monitor, "link")));
        if (m.*.isoverview != 0) return;
    }
    switcher_state.mon = c.server.selected_monitor;
    switcher_state.scope = scope;
    var n: i32 = 0;
    const fhead: [*c]c.struct_wl_list = @ptrCast(&c.server.focus_stack);
    var pos = c.server.focus_stack.next;
    while (pos != fhead) : (pos = pos.*.next) {
        const cl = @as([*c]Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Client, "flink")));
        if (switcher_candidate(cl)) n += 1;
    }
    if (n == 0) return;
    const max_row_w = @as(i32, @intFromFloat(@as(f32, @floatFromInt(switcher_state.mon.*.m.width)) * SW_PANEL_FRAC)) - 2 * SW_MARGIN;
    const max_panel_h = @as(i32, @intFromFloat(@as(f32, @floatFromInt(switcher_state.mon.*.m.height)) * SW_PANEL_FRAC));
    switcher_state.tile_h = 1;
    var cols: i32 = 1;
    while (cols <= n) : (cols += 1) {
        const rows = @divTrunc(n + cols - 1, cols);
        const h_by_w = @as(i32, @intFromFloat(@as(f32, @floatFromInt(max_row_w - (cols - 1) * SW_GAP - 2 * cols * SW_PAD)) / (@as(f32, @floatFromInt(cols)) * SW_ASPECT_MAX)));
        const h_by_h = @divTrunc(max_panel_h - 2 * SW_MARGIN - (rows - 1) * SW_GAP, rows) - 2 * SW_PAD;
        const h = @min(@as(i32, @intFromFloat(@as(f32, @floatFromInt(switcher_state.mon.*.m.height)) * SW_TILE_FRAC)), @min(h_by_w, h_by_h));
        switcher_state.tile_h = @max(switcher_state.tile_h, h);
    }
    switcher_state.tree = c.wlr_scene_tree_create(c.server.layers[c.LyrSpecialOverlay]);
    switcher_state.bg = c.wlr_scene_rect_create(switcher_state.tree, 1, 1, &switcher_panel_color);
    switcher_state.tiles = @ptrCast(@alignCast(c.ecalloc(@intCast(n), @sizeOf([*c]Tile))));
    pos = c.server.focus_stack.next;
    while (pos != fhead) : (pos = pos.*.next) {
        const cl = @as([*c]Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Client, "flink")));
        if (!switcher_candidate(cl)) continue;
        const raw = c.ecalloc(1, @sizeOf(Tile)) orelse continue;
        const tile = @as([*c]Tile, @ptrCast(@alignCast(raw)));
        switcher_tile_create(tile, cl);
        switcher_state.tiles[@intCast(switcher_state.count)] = tile;
        switcher_state.count += 1;
    }
    if (switcher_state.count > 1)
        switcher_state.index = if (dir < 0) switcher_state.count - 1 else 1
    else
        switcher_state.index = 0;
    switcher_layout();
    switcher_apply_highlight();
    var now: c.struct_timespec = undefined;
    _ = c.clock_gettime(c.CLOCK_MONOTONIC, &now);
    var i: i32 = 0;
    while (i < switcher_state.count) : (i += 1)
        client_send_frame_done(switcher_state.tiles[@intCast(i)].*.c, &now);
}

export fn switcher_cycle(dir: i32) callconv(.c) void {
    switcher_state.index = @mod(switcher_state.index + dir + switcher_state.count, switcher_state.count);
    switcher_apply_highlight();
}

export fn switcher(arg: [*c]const c.Arg) callconv(.c) i32 {
    const dir: i32 = if (arg != null and arg.*.i == c.PREV) -1 else 1;
    const scope: i32 = if (arg != null) arg.*.i2 else c.SW_CURRENT_TAG;
    if (c.server.session_locked != 0 or c.server.selected_monitor == null or
        c.server.selected_monitor.*.is_jump_mode != 0)
        return 0;
    if (switcher_is_active()) {
        if (scope != switcher_state.scope) {
            switcher_close();
            switcher_open(scope, dir);
        } else switcher_cycle(dir);
    } else switcher_open(scope, dir);
    return 0;
}

export fn switcher_is_active() callconv(.c) bool {
    return switcher_state.tree != null;
}

export fn switcher_candidate(cl: [*c]Client) callconv(.c) bool {
    if (!switcherClientEligible(cl)) return false;
    if (switcher_state.scope == c.SW_CURRENT_TAG)
        return cl.*.mon == switcher_state.mon and VISIBLEON(cl, switcher_state.mon);
    if (switcher_state.scope == c.SW_ALL_TAG)
        return cl.*.mon == switcher_state.mon;
    return @as(i32, @intCast(cl.*.tags)) > 0;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/switcher_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_surface: c.struct_wlr_surface;
extern var stub_clip_calls: c_int;
extern var stub_clip: Box;
extern var stub_unmanaged: c_int;
extern var stub_x11popup: c_int;
extern var stub_frame_calls: c_int;
extern var stub_focus_calls: c_int;
extern var stub_view_calls: c_int;
extern var stub_rect_size_calls: c_int;
extern var stub_rect_color_calls: c_int;
extern var stub_filter_calls: c_int;
extern var stub_source_calls: c_int;
extern var stub_dest_calls: c_int;
extern var stub_setbuf_calls: c_int;
extern var stub_pos_calls: c_int;
extern var stub_node_destroy_calls: c_int;
extern var stub_coords_calls: c_int;
extern var stub_coord_x: i32;
extern var stub_coord_y: i32;
extern var stub_for_each_calls: c_int;
extern var stub_source_box: FBox;
extern var stub_contains: bool;

fn listInitS(head: *c.struct_wl_list) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

fn listInsertS(head: *c.struct_wl_list, link: *c.struct_wl_list) void {
    link.next = head.next;
    link.prev = @ptrCast(head);
    head.next.*.prev = @ptrCast(link);
    head.next = @ptrCast(link);
}

var test_xdg: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);

fn resetSwitcherWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    listInitS(&c.server.monitors);
    listInitS(&c.server.focus_stack);
    switcher_state = std.mem.zeroes(State);
    stub_clip = .{ .x = 0, .y = 0, .width = 200, .height = 100 };
    stub_clip_calls = 0;
    stub_unmanaged = 0;
    stub_x11popup = 0;
    stub_frame_calls = 0;
    stub_focus_calls = 0;
    stub_view_calls = 0;
    stub_rect_size_calls = 0;
    stub_rect_color_calls = 0;
    stub_filter_calls = 0;
    stub_source_calls = 0;
    stub_dest_calls = 0;
    stub_setbuf_calls = 0;
    stub_pos_calls = 0;
    stub_node_destroy_calls = 0;
    stub_coords_calls = 0;
    stub_coord_x = 0;
    stub_coord_y = 0;
    stub_for_each_calls = 0;
    stub_contains = true;
    stub_surface = std.mem.zeroes(c.struct_wlr_surface);
    stub_source_box = std.mem.zeroes(FBox);
    test_xdg = std.mem.zeroes(c.struct_wlr_xdg_surface);
    c.config.bordercolor = .{ 1, 0, 0, 1 };
    c.config.focuscolor = .{ 0, 1, 0, 1 };
}

fn mkClientS(cl: *Client, m: *Monitor, tags: u32) void {
    cl.* = std.mem.zeroes(Client);
    cl.mon = m;
    cl.tags = tags;
    cl.surface.xdg = &test_xdg;
    test_xdg.geometry = .{ .x = 0, .y = 0, .width = 200, .height = 100 };
    cl.animation.current = .{ .x = 0, .y = 0, .width = 200, .height = 100 };
    cl.geom = cl.animation.current;
}

fn mkMonitorS(m: *Monitor) void {
    m.* = std.mem.zeroes(Monitor);
    m.m = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
    m.tagset[0] = 1;
}

test "candidate scopes filter clients" {
    resetSwitcherWorld();
    var m: Monitor = undefined;
    mkMonitorS(&m);
    var cl: Client = undefined;
    mkClientS(&cl, &m, 1);
    stub_surface.mapped = true;
    switcher_state.mon = &m;
    switcher_state.scope = c.SW_CURRENT_TAG;
    try testing.expect(switcher_candidate(&cl));
    stub_unmanaged = 1;
    try testing.expect(!switcher_candidate(&cl));
    stub_unmanaged = 0;
    stub_x11popup = 1;
    try testing.expect(!switcher_candidate(&cl));
    stub_x11popup = 0;
    m.tagset[0] = 2;
    try testing.expect(!switcher_candidate(&cl));
    switcher_state.scope = c.SW_ALL_TAG;
    try testing.expect(switcher_candidate(&cl));
    try testing.expectEqual(@as(usize, 0), @as(usize, 0));
}

test "tile layout maps root and sub surfaces" {
    resetSwitcherWorld();
    var tile: Tile = std.mem.zeroes(Tile);
    listInitS(&tile.surfaces);
    var cl: Client = std.mem.zeroes(Client);
    cl.surface.xdg = &test_xdg;
    test_xdg.geometry = .{ .x = 0, .y = 0, .width = 400, .height = 200 };
    tile.c = &cl;
    tile.cw = 200;
    switcher_state.tile_h = 100;
    stub_surface.current.width = 400;
    stub_surface.current.height = 200;
    stub_surface.current.buffer_width = 400;
    stub_surface.current.buffer_height = 200;
    var root: Entry = std.mem.zeroes(Entry);
    root.tile = &tile;
    root.surface = &stub_surface;
    root.is_root = true;
    root.buffer = @ptrFromInt(0x1000);
    listInsertS(&tile.surfaces, &root.link);
    var sub: Entry = std.mem.zeroes(Entry);
    sub.tile = &tile;
    sub.surface = &stub_surface;
    sub.sx = 20;
    sub.sy = 10;
    sub.buffer = @ptrFromInt(0x2000);
    listInsertS(&tile.surfaces, &sub.link);
    switcher_tile_layout(&tile);
    try testing.expectEqual(@as(c_int, 1), stub_clip_calls);
    try testing.expectEqual(@as(c_int, 1), stub_source_calls);
    try testing.expectEqual(@as(c_int, 2), stub_dest_calls);
}

test "panel layout rows and highlight" {
    resetSwitcherWorld();
    var m: Monitor = undefined;
    mkMonitorS(&m);
    switcher_state.mon = &m;
    switcher_state.tree = @ptrFromInt(0x1000);
    switcher_state.bg = @ptrFromInt(0x2000);
    switcher_state.tile_h = 100;
    var tiles: [3]*Tile = undefined;
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        tiles[i] = @as(*Tile, @ptrCast(@alignCast(c.calloc(1, @sizeOf(Tile)))));
        tiles[i].*.cw = 100;
        tiles[i].*.tree = @ptrFromInt(0x3000 + i * 0x100);
        tiles[i].*.frame = @ptrFromInt(0x4000 + i * 0x100);
    }
    switcher_state.tiles = @ptrCast(&tiles[0]);
    switcher_state.count = 3;
    switcher_state.index = 1;
    switcher_layout();
    try testing.expect(stub_pos_calls >= 4);
    try testing.expectEqual(@as(c_int, 4), stub_rect_size_calls);
    switcher_apply_highlight();
    try testing.expectEqual(@as(c_int, 3), stub_rect_color_calls);
}

test "open cycles commits and closes" {
    resetSwitcherWorld();
    var m: Monitor = undefined;
    mkMonitorS(&m);
    c.server.selected_monitor = &m;
    stub_surface.mapped = true;
    var cl1: Client = undefined;
    var cl2: Client = undefined;
    mkClientS(&cl1, &m, 1);
    mkClientS(&cl2, &m, 1);
    listInsertS(&c.server.focus_stack, &cl1.flink);
    listInsertS(&c.server.focus_stack, &cl2.flink);
    switcher_open(c.SW_CURRENT_TAG, 1);
    try testing.expect(switcher_is_active());
    try testing.expectEqual(@as(i32, 2), switcher_state.count);
    try testing.expectEqual(@as(i32, 1), switcher_state.index);
    try testing.expectEqual(@as(c_int, 2), stub_frame_calls);
    switcher_cycle(-1);
    try testing.expectEqual(@as(i32, 0), switcher_state.index);
    switcher_commit();
    try testing.expect(!switcher_is_active());
    try testing.expectEqual(@as(c_int, 1), stub_focus_calls);
}

test "remove client shrinks tiles and client_at resolves boxes" {
    resetSwitcherWorld();
    var m: Monitor = undefined;
    mkMonitorS(&m);
    c.server.selected_monitor = &m;
    stub_surface.mapped = true;
    var cl1: Client = undefined;
    var cl2: Client = undefined;
    mkClientS(&cl1, &m, 1);
    mkClientS(&cl2, &m, 1);
    listInsertS(&c.server.focus_stack, &cl1.flink);
    listInsertS(&c.server.focus_stack, &cl2.flink);
    switcher_open(c.SW_CURRENT_TAG, 1);
    switcher_state.index = 1;
    stub_coord_x = 10;
    stub_coord_y = 10;
    try testing.expect(switcher_client_at(15, 15) != null);
    stub_contains = false;
    try testing.expect(switcher_client_at(15, 15) == null);
    switcher_remove_client(&cl1);
    try testing.expectEqual(@as(i32, 1), switcher_state.count);
    try testing.expectEqual(@as(i32, 0), switcher_state.index);
    switcher_close();
    try testing.expect(!switcher_is_active());
}

test "surface add and update buffer wire scene nodes" {
    resetSwitcherWorld();
    var tile: Tile = std.mem.zeroes(Tile);
    listInitS(&tile.surfaces);
    tile.content = @ptrFromInt(0x1000);
    var cl: Client = std.mem.zeroes(Client);
    cl.surface.xdg = &test_xdg;
    tile.c = &cl;
    stub_surface.current.width = 10;
    stub_surface.current.height = 20;
    listInitS(&stub_surface.events.commit.listener_list);
    listInitS(&stub_surface.events.destroy.listener_list);
    switcher_tile_add_surface(&stub_surface, 0, 0, &tile);
    try testing.expectEqual(@as(c_int, 1), stub_filter_calls);
    try testing.expect(stub_source_calls >= 1);
    try testing.expect(stub_setbuf_calls >= 1);
    const entry = @as(*Entry, @ptrFromInt(@intFromPtr(tile.surfaces.next) - @offsetOf(Entry, "link")));
    stub_surface.buffer = null;
    switcher_surface_update_buffer(entry);
    try testing.expect(stub_setbuf_calls >= 2);
    entry.destroy.notify.?(&entry.destroy, null);
    try testing.expectEqual(@as(c_int, 1), stub_node_destroy_calls);
}
