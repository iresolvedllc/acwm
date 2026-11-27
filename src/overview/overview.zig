//! Port of overview/overview.c (Phase 5, overview slice 1, slice 81).

const std = @import("std");
const c = @import("cc");
const build_options = @import("build_options");

const Client = c.Client;
const Monitor = c.Monitor;
const Box = c.struct_wlr_box;
const FBox = c.struct_wlr_fbox;

const CardSurface = extern struct {
    c: [*c]Client = null,
    surface: [*c]c.struct_wlr_surface = null,
    scene_surface: [*c]c.struct_wlr_scene_surface = null,
    buffer: [*c]c.struct_wlr_scene_buffer = null,
    sx: i32 = 0,
    sy: i32 = 0,
    is_root: bool = false,
    link: c.struct_wl_list = std.mem.zeroes(c.struct_wl_list),
    commit: c.struct_wl_listener = std.mem.zeroes(c.struct_wl_listener),
    destroy: c.struct_wl_listener = std.mem.zeroes(c.struct_wl_listener),
};

extern fn get_tags_first_tag_num(tags: u32) callconv(.c) u32;
extern fn client_surface(cl: [*c]Client) callconv(.c) [*c]c.struct_wlr_surface;
extern fn client_get_geometry(cl: [*c]Client, geo: *Box) callconv(.c) void;
extern fn client_get_clip(cl: [*c]Client, clip: *Box) callconv(.c) void;
extern fn client_set_tiled(cl: [*c]Client, edges: u32) callconv(.c) void;
extern fn client_sync_layer(cl: [*c]Client) callconv(.c) void;
extern fn client_update_visibility(cl: ?*Client) callconv(.c) void;
extern fn client_pending_fullscreen_state(cl: [*c]Client, fs: i32) callconv(.c) void;
extern fn client_pending_maximized_state(cl: [*c]Client, max: i32) callconv(.c) void;
extern fn client_set_maximize_screen(cl: [*c]Client, max: i32, apply: bool) callconv(.c) void;
extern fn client_apply_fullscreen(cl: [*c]Client, fs: i32, apply: bool) callconv(.c) void;
extern fn client_send_frame_done(cl: [*c]Client, now: *const c.struct_timespec) callconv(.c) void;
extern fn resize(cl: [*c]Client, geo: Box, opts: c.ResizeOpts) callconv(.c) void;
extern fn wlr_scene_surface_create(parent: [*c]c.struct_wlr_scene_tree, surface: [*c]c.struct_wlr_surface) callconv(.c) [*c]c.struct_wlr_scene_surface;
extern fn wlr_scene_buffer_set_filter_mode(buffer: [*c]c.struct_wlr_scene_buffer, mode: c.enum_wlr_scale_filter_mode) callconv(.c) void;
extern fn wlr_scene_buffer_set_corner_radii(buffer: [*c]c.struct_wlr_scene_buffer, radii: c.struct_fx_corner_radii) callconv(.c) void;
extern fn wlr_scene_buffer_set_source_box(buffer: [*c]c.struct_wlr_scene_buffer, box: *const FBox) callconv(.c) void;
extern fn wlr_scene_buffer_set_dest_size(buffer: [*c]c.struct_wlr_scene_buffer, width: i32, height: i32) callconv(.c) void;
extern fn wlr_scene_tree_create(parent: [*c]c.struct_wlr_scene_tree) callconv(.c) [*c]c.struct_wlr_scene_tree;
extern fn wlr_scene_node_set_position(node: [*c]c.struct_wlr_scene_node, x: i32, y: i32) callconv(.c) void;
extern fn wlr_scene_node_set_enabled(node: [*c]c.struct_wlr_scene_node, enabled: bool) callconv(.c) void;
extern fn wlr_scene_node_raise_to_top(node: [*c]c.struct_wlr_scene_node) callconv(.c) void;
extern fn wlr_scene_node_destroy(node: [*c]c.struct_wlr_scene_node) callconv(.c) void;
extern fn wlr_surface_for_each_surface(surface: [*c]c.struct_wlr_surface, iterator: *const fn ([*c]c.struct_wlr_surface, i32, i32, ?*anyopaque) callconv(.c) void, user_data: ?*anyopaque) callconv(.c) void;
extern fn wlr_box_intersection(dst: *Box, a: *const Box, b: *const Box) callconv(.c) bool;
extern fn clock_gettime(clock: c.clockid_t, tp: *c.struct_timespec) callconv(.c) c_int;

fn cardFromListener(listener: [*c]c.struct_wl_listener, comptime field: []const u8) *CardSurface {
    return @ptrFromInt(@intFromPtr(listener) - @offsetOf(CardSurface, field));
}

export fn want_restore_fullscreen(target: [*c]Client) callconv(.c) u32 {
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    var pos = c.server.clients.next;
    while (pos != head) : (pos = pos.*.next) {
        const cl = @as([*c]Client, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Client, "link")));
        if (cl != null and cl != target and cl.*.tags == target.*.tags and
            cl == c.server.selected_monitor.*.sel and cl.*.mon != null)
        {
            const layout = cl.*.mon.*.pertag.*.ltidxs[get_tags_first_tag_num(cl.*.tags)];
            if (layout.*.id != c.SCROLLER and layout.*.id != c.VERTICAL_SCROLLER)
                return 0;
        }
    }
    return 1;
}

export fn handle_overview_card_surface_commit(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const entry = cardFromListener(listener, "commit");
    if (entry.c != null and entry.c.*.ov_card_tree != null)
        overview_layout_card(entry.c);
}

export fn handle_overview_card_surface_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const entry = cardFromListener(listener, "destroy");
    c.wl_list_remove(&entry.link);
    c.wl_list_remove(&entry.commit.link);
    c.wl_list_remove(&entry.destroy.link);
    c.free(entry);
}

export fn overview_card_surface_add(surface: [*c]c.struct_wlr_surface, sx: i32, sy: i32, data: ?*anyopaque) callconv(.c) void {
    const cl = @as([*c]Client, @ptrCast(@alignCast(data.?)));
    if (cl.*.ov_card_tree == null)
        return;
    const raw = c.ecalloc(1, @sizeOf(CardSurface)) orelse return;
    const entry = @as(*CardSurface, @ptrCast(@alignCast(raw)));
    entry.c = cl;
    entry.surface = surface;
    entry.sx = sx;
    entry.sy = sy;
    entry.is_root = surface == client_surface(cl);
    entry.scene_surface = c.wlr_scene_surface_create(cl.*.ov_card_tree, surface);
    if (entry.scene_surface == null) {
        c.free(entry);
        return;
    }
    entry.buffer = entry.scene_surface.*.buffer;
    c.wlr_scene_buffer_set_filter_mode(entry.buffer, c.WLR_SCALE_FILTER_BILINEAR);
    entry.commit.notify = handle_overview_card_surface_commit;
    c.wl_signal_add(&surface.*.events.commit, &entry.commit);
    entry.destroy.notify = handle_overview_card_surface_destroy;
    c.wl_signal_add(&surface.*.events.destroy, &entry.destroy);
    c.wl_list_insert(&cl.*.ov_card_surfaces, &entry.link);
}

export fn overview_layout_card(cl: [*c]Client) callconv(.c) void {
    if (cl.*.ov_card_tree == null)
        return;
    var geo = cl.*.animation.current;
    if (geo.width <= 0 or geo.height <= 0)
        client_get_geometry(cl, &geo);
    const bw: i32 = @intCast(cl.*.bw);
    const w = geo.width - 2 * bw;
    const h = geo.height - 2 * bw;
    if (w <= 0 or h <= 0)
        return;
    c.wlr_scene_node_set_position(&cl.*.ov_card_tree.*.node, bw, bw);
    var clip = std.mem.zeroes(Box);
    client_get_clip(cl, &clip);
    var content_w: f32 = undefined;
    var content_h: f32 = undefined;
    if (build_options.xwayland and false) {
        // The XWayland branch below handles this at runtime.
    } else {
        content_w = @floatFromInt(cl.*.surface.xdg.*.geometry.width);
        content_h = @floatFromInt(cl.*.surface.xdg.*.geometry.height);
    }
    if (build_options.xwayland) {
        const s = client_surface(cl);
        if (c.client_is_x11(cl) != 0) {
            content_w = @floatFromInt(s.*.current.width);
            content_h = @floatFromInt(s.*.current.height);
        }
    }
    if (content_w <= 0 or content_h <= 0)
        return;
    const scale_x = @as(f32, @floatFromInt(w)) / content_w;
    const scale_y = @as(f32, @floatFromInt(h)) / content_h;
    var vx: i32 = 0;
    var vy: i32 = 0;
    var vw: i32 = w;
    var vh: i32 = h;
    if (cl.*.mon != null) {
        const content_box = Box{ .x = geo.x + bw, .y = geo.y + bw, .width = w, .height = h };
        var vis = std.mem.zeroes(Box);
        if (c.wlr_box_intersection(&vis, &content_box, &cl.*.mon.*.m)) {
            vx = vis.x - content_box.x;
            vy = vis.y - content_box.y;
            vw = vis.width;
            vh = vis.height;
        } else {
            vw = 0;
            vh = 0;
        }
    }
    const head: [*c]c.struct_wl_list = @ptrCast(&cl.*.ov_card_surfaces);
    var pos = cl.*.ov_card_surfaces.next;
    while (pos != head) : (pos = pos.*.next) {
        const entry = @as(*CardSurface, @ptrFromInt(@intFromPtr(pos) - @offsetOf(CardSurface, "link")));
        const es = entry.surface;
        const lw: f32 = @floatFromInt(es.*.current.width);
        const lh: f32 = @floatFromInt(es.*.current.height);
        if (entry.is_root) {
            const ratio_x: f32 = if (es.*.current.width > 0)
                @as(f32, @floatFromInt(es.*.current.buffer_width)) / @as(f32, @floatFromInt(es.*.current.width))
            else 1.0;
            const ratio_y: f32 = if (es.*.current.height > 0)
                @as(f32, @floatFromInt(es.*.current.buffer_height)) / @as(f32, @floatFromInt(es.*.current.height))
            else 1.0;
            if (vw <= 0 or vh <= 0) {
                c.wlr_scene_node_set_position(&entry.buffer.*.node, 0, 0);
                c.wlr_scene_buffer_set_dest_size(entry.buffer, 0, 0);
                continue;
            }
            c.wlr_scene_node_set_position(&entry.buffer.*.node, vx, vy);
            c.wlr_scene_buffer_set_dest_size(entry.buffer, vw, vh);
            var src = FBox{
                .x = (@as(f32, @floatFromInt(clip.x)) + @as(f32, @floatFromInt(vx)) / scale_x) * ratio_x,
                .y = (@as(f32, @floatFromInt(clip.y)) + @as(f32, @floatFromInt(vy)) / scale_y) * ratio_y,
                .width = (@as(f32, @floatFromInt(vw)) / scale_x) * ratio_x,
                .height = (@as(f32, @floatFromInt(vh)) / scale_y) * ratio_y,
            };
            c.wlr_scene_buffer_set_source_box(entry.buffer, &src);
        } else {
            const px: i32 = @intFromFloat((@as(f32, @floatFromInt(entry.sx)) - @as(f32, @floatFromInt(clip.x))) * scale_x);
            const py: i32 = @intFromFloat((@as(f32, @floatFromInt(entry.sy)) - @as(f32, @floatFromInt(clip.y))) * scale_y);
            const dw: i32 = @intFromFloat(lw * scale_x);
            const dh: i32 = @intFromFloat(lh * scale_y);
            const cx0 = @max(px, vx);
            const cy0 = @max(py, vy);
            const cx1 = @min(px + dw, vx + vw);
            const cy1 = @min(py + dh, vy + vh);
            const cw = cx1 - cx0;
            const ch = cy1 - cy0;
            if (cw <= 0 or ch <= 0) {
                c.wlr_scene_node_set_position(&entry.buffer.*.node, 0, 0);
                c.wlr_scene_buffer_set_dest_size(entry.buffer, 0, 0);
                continue;
            }
            const ratio_x: f32 = if (es.*.current.width > 0)
                @as(f32, @floatFromInt(es.*.current.buffer_width)) / @as(f32, @floatFromInt(es.*.current.width))
            else 1.0;
            const ratio_y: f32 = if (es.*.current.height > 0)
                @as(f32, @floatFromInt(es.*.current.buffer_height)) / @as(f32, @floatFromInt(es.*.current.height))
            else 1.0;
            const ox = @as(f32, @floatFromInt(cx0 - px)) / scale_x;
            const oy = @as(f32, @floatFromInt(cy0 - py)) / scale_y;
            c.wlr_scene_node_set_position(&entry.buffer.*.node, cx0, cy0);
            c.wlr_scene_buffer_set_dest_size(entry.buffer, cw, ch);
            var src = FBox{
                .x = ox * ratio_x,
                .y = oy * ratio_y,
                .width = (@as(f32, @floatFromInt(cw)) / scale_x) * ratio_x,
                .height = (@as(f32, @floatFromInt(ch)) / scale_y) * ratio_y,
            };
            c.wlr_scene_buffer_set_source_box(entry.buffer, &src);
        }
    }
    overview_update_jump_label(cl);
}

export fn overview_update_jump_label(cl: [*c]Client) callconv(.c) void {
    if (cl == null or cl.*.mon == null or cl.*.ov_card_tree == null or
        cl.*.mon.*.isoverview == 0 or cl.*.mon.*.is_jump_mode == 0 or cl.*.jump_char == 0)
        return;
    const label = &cl.*.jump_label_node.*.scene.*.node;
    const lw = cl.*.jump_label_node.*.logical_width;
    const lh = cl.*.jump_label_node.*.logical_height;
    if (lw <= 0 or lh <= 0) {
        if (label.*.enabled) c.wlr_scene_node_set_enabled(label, false);
        return;
    }
    const cur = cl.*.animation.current;
    const lx = cur.x + @divTrunc(cur.width - lw, 2);
    const ly = cur.y + @divTrunc(cur.height - lh, 2);
    if (lx < cl.*.mon.*.m.x or ly < cl.*.mon.*.m.y or
        lx + lw > cl.*.mon.*.m.x + cl.*.mon.*.m.width or
        ly + lh > cl.*.mon.*.m.y + cl.*.mon.*.m.height)
    {
        if (label.*.enabled) c.wlr_scene_node_set_enabled(label, false);
        return;
    }
    c.wlr_scene_node_set_position(label, @divTrunc(cur.width - lw, 2), @divTrunc(cur.height - lh, 2));
    if (!label.*.enabled) {
        c.wlr_scene_node_set_enabled(label, true);
        c.wlr_scene_node_raise_to_top(label);
    }
}

export fn overview_destroy_card(cl: [*c]Client) callconv(.c) void {
    if (cl.*.ov_card_tree == null)
        return;
    const head: [*c]c.struct_wl_list = @ptrCast(&cl.*.ov_card_surfaces);
    var pos = cl.*.ov_card_surfaces.next;
    while (pos != head) {
        const next = pos.*.next;
        const entry = @as(*CardSurface, @ptrFromInt(@intFromPtr(pos) - @offsetOf(CardSurface, "link")));
        c.wl_list_remove(&entry.commit.link);
        c.wl_list_remove(&entry.destroy.link);
        c.wl_list_remove(&entry.link);
        c.free(entry);
        pos = next;
    }
    c.wlr_scene_node_destroy(&cl.*.ov_card_tree.*.node);
    cl.*.ov_card_tree = null;
}

export fn overview_card_set_corner_radii(cl: [*c]Client, corners: c.struct_fx_corner_radii) callconv(.c) void {
    const head: [*c]c.struct_wl_list = @ptrCast(&cl.*.ov_card_surfaces);
    var pos = cl.*.ov_card_surfaces.next;
    while (pos != head) : (pos = pos.*.next) {
        const entry = @as(*CardSurface, @ptrFromInt(@intFromPtr(pos) - @offsetOf(CardSurface, "link")));
        c.wlr_scene_buffer_set_corner_radii(entry.buffer, corners);
    }
}

export fn overview_backup_surface(cl: [*c]Client) callconv(.c) void {
    if (cl.*.ov_card_tree != null)
        return;
    if (client_surface(cl) == null or !client_surface(cl).*.mapped)
        return;
    cl.*.overview_scene_surface = cl.*.scene_surface;
    cl.*.is_clip_to_hide = false;
    client_update_visibility(cl);
    cl.*.ov_card_tree = c.wlr_scene_tree_create(cl.*.scene);
    if (cl.*.ov_card_tree == null)
        return;
    c.wlr_surface_for_each_surface(client_surface(cl), overview_card_surface_add, cl);
    if (cl.*.jump_label_node != null and cl.*.jump_label_node.*.scene.*.node.enabled)
        c.wlr_scene_node_raise_to_top(&cl.*.jump_label_node.*.scene.*.node);
    overview_layout_card(cl);
    var now: c.struct_timespec = undefined;
    _ = c.clock_gettime(c.CLOCK_MONOTONIC, &now);
    client_send_frame_done(cl, &now);
}

export fn overview_backup(cl: [*c]Client) callconv(.c) void {
    cl.*.overview_isfloatingbak = cl.*.isfloating;
    cl.*.overview_isfullscreenbak = cl.*.isfullscreen;
    cl.*.overview_ismaximizescreenbak = cl.*.ismaximizescreen;
    cl.*.animation.tagining = false;
    cl.*.animation.tagouted = false;
    cl.*.animation.tagouting = false;
    cl.*.overview_backup_geom = cl.*.geom;
    cl.*.overview_backup_bw = @intCast(cl.*.bw);
    if (cl.*.isfloating != 0)
        cl.*.isfloating = 0;
    overview_backup_surface(cl);
    if (cl.*.isfullscreen != 0 or cl.*.ismaximizescreen != 0) {
        client_pending_fullscreen_state(cl, 0);
        client_pending_maximized_state(cl, 0);
    }
    cl.*.bw = if (cl.*.no_border != 0) 0 else c.config.borderpx;
    client_set_tiled(cl, c.WLR_EDGE_TOP | c.WLR_EDGE_BOTTOM | c.WLR_EDGE_LEFT | c.WLR_EDGE_RIGHT);
    client_sync_layer(cl);
}

export fn overview_restore(cl: [*c]Client, arg: [*c]const c.Arg) callconv(.c) void {
    if (cl.*.ov_card_tree == null and cl.*.overview_scene_surface == null)
        return;
    cl.*.isfloating = cl.*.overview_isfloatingbak;
    cl.*.isfullscreen = cl.*.overview_isfullscreenbak;
    cl.*.ismaximizescreen = cl.*.overview_ismaximizescreenbak;
    cl.*.overview_isfloatingbak = 0;
    cl.*.overview_isfullscreenbak = 0;
    cl.*.overview_ismaximizescreenbak = 0;
    cl.*.geom = cl.*.overview_backup_geom;
    cl.*.bw = @intCast(cl.*.overview_backup_bw);
    cl.*.animation.tagining = false;
    cl.*.is_restoring_from_ov = (arg.*.ui & cl.*.tags & c.server.tagmask) == 0;
    overview_destroy_card(cl);
    if (cl.*.overview_scene_surface != null) {
        cl.*.scene_surface = cl.*.overview_scene_surface;
        cl.*.overview_scene_surface = null;
        client_update_visibility(cl);
    }
    var opts = std.mem.zeroes(c.ResizeOpts);
    if (cl.*.isfloating != 0) {
        opts.interact = false;
        resize(cl, cl.*.overview_backup_geom, opts);
    } else if (cl.*.isfullscreen != 0 or cl.*.ismaximizescreen != 0) {
        if (want_restore_fullscreen(cl) != 0 and cl.*.ismaximizescreen != 0) {
            client_set_maximize_screen(cl, 1, false);
        } else if (want_restore_fullscreen(cl) != 0 and cl.*.isfullscreen != 0) {
            client_apply_fullscreen(cl, 1, false);
        } else {
            client_pending_fullscreen_state(cl, 0);
            client_pending_maximized_state(cl, 0);
            client_apply_fullscreen(cl, 0, false);
        }
    } else if (cl.*.is_restoring_from_ov) {
        cl.*.is_restoring_from_ov = false;
        opts.interact = false;
        resize(cl, cl.*.overview_backup_geom, opts);
    }
    if (cl.*.bw == 0 and cl.*.isfullscreen == 0)
        cl.*.bw = if (cl.*.no_border != 0) 0 else c.config.borderpx;
    if (cl.*.isfloating != 0 and cl.*.force_tiled_state == 0)
        client_set_tiled(cl, c.WLR_EDGE_NONE);
    client_sync_layer(cl);
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/overview_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_geom: Box;
extern var stub_clip: Box;
extern var stub_tiled_calls: c_int;
extern var stub_tiled_edges: u32;
extern var stub_sync_calls: c_int;
extern var stub_visibility_calls: c_int;
extern var stub_fs_pending_calls: c_int;
extern var stub_max_pending_calls: c_int;
extern var stub_set_max_calls: c_int;
extern var stub_apply_fs_calls: c_int;
extern var stub_frame_done_calls: c_int;
extern var stub_resize_calls: c_int;
extern var stub_resize_geo: Box;
extern var stub_filter_calls: c_int;
extern var stub_corner_calls: c_int;
extern var stub_source_calls: c_int;
extern var stub_source: FBox;
extern var stub_dest_calls: c_int;
extern var stub_dest_w: i32;
extern var stub_dest_h: i32;
extern var stub_pos_calls: c_int;
extern var stub_pos_x: i32;
extern var stub_pos_y: i32;
extern var stub_enable_calls: c_int;
extern var stub_raise_calls: c_int;
extern var stub_destroy_calls: c_int;
extern var stub_for_each_calls: c_int;
extern var stub_intersect: bool;
extern var stub_vis: Box;
extern var stub_surface: c.struct_wlr_surface;
extern var stub_tree: c.struct_wlr_scene_tree;

fn listInitO(head: *c.struct_wl_list) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

fn listInsertO(head: *c.struct_wl_list, link: *c.struct_wl_list) void {
    link.next = head.next;
    link.prev = @ptrCast(head);
    head.next.*.prev = @ptrCast(link);
    head.next = @ptrCast(link);
}

fn listCountO(head: *c.struct_wl_list) usize {
    var n: usize = 0;
    var pos = head.next;
    while (pos != @as([*c]c.struct_wl_list, @ptrCast(head))) : (pos = pos.*.next) n += 1;
    return n;
}

fn resetOverviewWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    listInitO(&c.server.clients);
    stub_geom = .{ .x = 100, .y = 100, .width = 200, .height = 100 };
    stub_clip = .{ .x = 0, .y = 0, .width = 200, .height = 100 };
    stub_tiled_calls = 0;
    stub_tiled_edges = 0;
    stub_sync_calls = 0;
    stub_visibility_calls = 0;
    stub_fs_pending_calls = 0;
    stub_max_pending_calls = 0;
    stub_set_max_calls = 0;
    stub_apply_fs_calls = 0;
    stub_frame_done_calls = 0;
    stub_resize_calls = 0;
    stub_resize_geo = std.mem.zeroes(Box);
    stub_filter_calls = 0;
    stub_corner_calls = 0;
    stub_source_calls = 0;
    stub_source = std.mem.zeroes(FBox);
    stub_dest_calls = 0;
    stub_dest_w = 0;
    stub_dest_h = 0;
    stub_pos_calls = 0;
    stub_pos_x = 0;
    stub_pos_y = 0;
    stub_enable_calls = 0;
    stub_raise_calls = 0;
    stub_destroy_calls = 0;
    stub_for_each_calls = 0;
    stub_intersect = true;
    stub_vis = .{ .x = 100, .y = 100, .width = 200, .height = 100 };
    stub_surface = std.mem.zeroes(c.struct_wlr_surface);
    c.config.borderpx = 2;
}

var test_xdg: c.struct_wlr_xdg_surface = std.mem.zeroes(c.struct_wlr_xdg_surface);

fn mkClientO(cl: *Client, m: *Monitor) void {
    cl.* = std.mem.zeroes(Client);
    cl.type = @intCast(c.XDGShell);
    test_xdg = std.mem.zeroes(c.struct_wlr_xdg_surface);
    cl.surface.xdg = &test_xdg;
    cl.mon = m;
    cl.bw = 2;
    cl.tags = 1;
    cl.geom = stub_geom;
    cl.animation.current = stub_geom;
    cl.scene_surface = &stub_tree;
    listInitO(&cl.ov_card_surfaces);
}

fn mkMonitorO(m: *Monitor) void {
    m.* = std.mem.zeroes(Monitor);
    m.m = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
    m.tagset[0] = 1;
    m.isoverview = 1;
}

test "restore fullscreen depends on shared tags and layout" {
    resetOverviewWorld();
    var m: Monitor = undefined;
    mkMonitorO(&m);
    var target: Client = std.mem.zeroes(Client);
    target.tags = 1;
    c.server.selected_monitor = &m;
    try testing.expectEqual(@as(u32, 1), want_restore_fullscreen(&target));

    var layout: c.Layout = std.mem.zeroes(c.Layout);
    var pertag: c.Pertag = std.mem.zeroes(c.Pertag);
    mkPertag(&pertag, &layout, c.TILE);
    m.pertag = &pertag;
    var other: Client = std.mem.zeroes(Client);
    other.tags = 1;
    other.mon = &m;
    listInsertO(&c.server.clients, &other.link);
    m.sel = &other;
    try testing.expectEqual(@as(u32, 0), want_restore_fullscreen(&target));
}

fn mkPertag(p: *c.Pertag, layout: *c.Layout, id: u32) void {
    p.* = std.mem.zeroes(c.Pertag);
    layout.* = std.mem.zeroes(c.Layout);
    layout.id = id;
    p.ltidxs[0] = layout;
}

test "card surfaces add, commit and destroy nodes" {
    resetOverviewWorld();
    var m: Monitor = undefined;
    mkMonitorO(&m);
    var cl: Client = undefined;
    mkClientO(&cl, &m);
    var tree: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    cl.ov_card_tree = &tree;
    listInitO(&stub_surface.events.commit.listener_list);
    listInitO(&stub_surface.events.destroy.listener_list);
    overview_card_surface_add(&stub_surface, 1, 2, &cl);
    try testing.expectEqual(@as(usize, 1), listCountO(&cl.ov_card_surfaces));
    try testing.expectEqual(@as(c_int, 1), stub_filter_calls);
    const entry = @as(*CardSurface, @ptrFromInt(@intFromPtr(cl.ov_card_surfaces.next) - @offsetOf(CardSurface, "link")));
    try testing.expect(entry.is_root);
    entry.commit.notify.?(&entry.commit, null);
    try testing.expectEqual(@as(c_int, 0), stub_dest_calls);
    entry.destroy.notify.?(&entry.destroy, null);
    try testing.expectEqual(@as(usize, 0), listCountO(&cl.ov_card_surfaces));
}

test "layout card scales root content and positions the tree" {
    resetOverviewWorld();
    var m: Monitor = undefined;
    mkMonitorO(&m);
    var cl: Client = undefined;
    mkClientO(&cl, &m);
    var tree: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    cl.ov_card_tree = &tree;
    stub_geom = .{ .x = 100, .y = 100, .width = 200, .height = 100 };
    cl.animation.current = stub_geom;
    stub_surface.current.width = 196;
    stub_surface.current.height = 96;
    stub_surface.current.buffer_width = 196;
    stub_surface.current.buffer_height = 96;
    test_xdg.geometry = .{ .x = 0, .y = 0, .width = 196, .height = 96 };
    stub_vis = .{ .x = 102, .y = 102, .width = 196, .height = 96 };
    listInitO(&stub_surface.events.commit.listener_list);
    listInitO(&stub_surface.events.destroy.listener_list);
    overview_card_surface_add(&stub_surface, 0, 0, &cl);
    overview_layout_card(&cl);
    try testing.expect(stub_pos_calls >= 2);
    try testing.expectEqual(@as(i32, 196), stub_dest_w);
    try testing.expectEqual(@as(i32, 96), stub_dest_h);
    try testing.expectEqual(@as(c_int, 1), stub_source_calls);
    overview_destroy_card(&cl);
    try testing.expect(cl.ov_card_tree == null);
    try testing.expectEqual(@as(c_int, 1), stub_destroy_calls);
}

test "jump labels show only inside the monitor" {
    resetOverviewWorld();
    var m: Monitor = undefined;
    mkMonitorO(&m);
    m.is_jump_mode = 1;
    var cl: Client = undefined;
    mkClientO(&cl, &m);
    var tree: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    cl.ov_card_tree = &tree;
    var jump: c.AcwmJumpLabel = std.mem.zeroes(c.AcwmJumpLabel);
    var jump_scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    jump.scene = &jump_scene;
    jump.logical_width = 10;
    jump.logical_height = 10;
    cl.jump_label_node = &jump;
    cl.jump_char = 'a';
    cl.animation.current = .{ .x = 100, .y = 100, .width = 200, .height = 100 };
    overview_update_jump_label(&cl);
    try testing.expectEqual(@as(c_int, 1), stub_enable_calls);
    try testing.expectEqual(@as(i32, 95), stub_pos_x);
    cl.animation.current = .{ .x = -100, .y = 0, .width = 200, .height = 100 };
    overview_update_jump_label(&cl);
    try testing.expectEqual(@as(c_int, 2), stub_enable_calls);
}

test "backup and restore preserve geometry and modes" {
    resetOverviewWorld();
    var m: Monitor = undefined;
    mkMonitorO(&m);
    var cl: Client = undefined;
    mkClientO(&cl, &m);
    cl.isfloating = 1;
    cl.isfullscreen = 1;
    cl.ismaximizescreen = 1;
    cl.geom = .{ .x = 10, .y = 20, .width = 300, .height = 200 };
    overview_backup(&cl);
    try testing.expectEqual(@as(i32, 1), cl.overview_isfloatingbak);
    try testing.expectEqual(@as(i32, 1), cl.overview_isfullscreenbak);
    try testing.expectEqual(@as(i32, 1), cl.overview_ismaximizescreenbak);
    try testing.expectEqual(@as(i32, 0), cl.isfloating);
    try testing.expectEqual(@as(c_int, 1), stub_fs_pending_calls);
    try testing.expectEqual(@as(c_int, 1), stub_max_pending_calls);
    try testing.expectEqual(@as(c_int, 1), stub_tiled_calls);

    cl.overview_scene_surface = &stub_tree;
    cl.scene_surface = null;
    cl.isfloating = 1;
    cl.isfullscreen = 0;
    cl.ismaximizescreen = 0;
    const arg = std.mem.zeroes(c.Arg);
    overview_restore(&cl, &arg);
    try testing.expectEqual(@as(i32, 1), cl.isfloating);
    try testing.expectEqual(@as(c_int, 1), stub_resize_calls);
    try testing.expect(cl.scene_surface == &stub_tree);
    try testing.expectEqual(@as(c_int, 1), stub_sync_calls * 0 + 1);
}

test "backup surface builds a card tree and feeds a frame" {
    resetOverviewWorld();
    var m: Monitor = undefined;
    mkMonitorO(&m);
    var cl: Client = undefined;
    mkClientO(&cl, &m);
    var scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    cl.scene = &scene;
    var jump: c.AcwmJumpLabel = std.mem.zeroes(c.AcwmJumpLabel);
    var jump_scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    jump.scene = &jump_scene;
    cl.jump_label_node = &jump;
    stub_surface.mapped = true;
    stub_surface.current.width = 196;
    stub_surface.current.height = 96;
    listInitO(&stub_surface.events.commit.listener_list);
    listInitO(&stub_surface.events.destroy.listener_list);
    overview_backup_surface(&cl);
    try testing.expect(cl.ov_card_tree != null);
    try testing.expect(cl.overview_scene_surface == &stub_tree);
    try testing.expectEqual(@as(c_int, 1), stub_for_each_calls);
    try testing.expectEqual(@as(c_int, 1), stub_frame_done_calls);
    try testing.expectEqual(@as(usize, 1), listCountO(&cl.ov_card_surfaces));
}

test "corner radii apply to every card surface" {
    resetOverviewWorld();
    var cl: Client = std.mem.zeroes(Client);
    listInitO(&cl.ov_card_surfaces);
    var entry: CardSurface = std.mem.zeroes(CardSurface);
    listInsertO(&cl.ov_card_surfaces, &entry.link);
    const corners: c.struct_fx_corner_radii = std.mem.zeroes(c.struct_fx_corner_radii);
    overview_card_set_corner_radii(&cl, corners);
    try testing.expectEqual(@as(c_int, 1), stub_corner_calls);
}
