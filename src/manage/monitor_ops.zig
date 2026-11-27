//! Port of the output layout-change / output-manager / frame / VRR cluster
//! in src/manage/monitor.c (Phase 5, manage slice 8, slice 56).

const std = @import("std");
const c = @import("cc");
const build_options = @import("build_options");

const Monitor = c.Monitor;
const Client = c.Client;
const LayerSurface = c.LayerSurface;
const Box = c.struct_wlr_box;
const OutputConfig = c.struct_wlr_output_configuration_v1;
const ConfigHead = c.struct_wlr_output_configuration_head_v1;

extern fn monitor_close(m: [*c]Monitor) callconv(.c) void;
extern fn set_selected_monitor(m: [*c]Monitor) callconv(.c) void;
extern fn special_update_dim(m: ?*Monitor) callconv(.c) void;
extern fn arrange_layers(m: *Monitor) callconv(.c) void;
extern fn arrange(m: [*c]Monitor, want_animation: bool, from_view: bool) callconv(.c) void;
extern fn resize(cl: [*c]Client, geo: Box, opts: c.ResizeOpts) callconv(.c) void;
extern fn client_focus(cl: ?*Client, lift: i32) callconv(.c) void;
extern fn client_focus_top(m: [*c]Monitor) callconv(.c) [*c]Client;
extern fn client_notify_enter(s: [*c]c.struct_wlr_surface, kb: [*c]c.struct_wlr_keyboard) callconv(.c) void;
extern fn client_activate_surface(s: [*c]c.struct_wlr_surface, activate: bool) callconv(.c) void;
extern fn client_change_mon(cl: [*c]Client, m: [*c]Monitor) callconv(.c) void;
extern fn reset_foreign_tolevel(cl: [*c]Client, oldmon: [*c]Monitor, newmon: [*c]Monitor) callconv(.c) void;
extern fn set_size_per(m: [*c]Monitor, cl: [*c]Client, reset_proportion: bool) callconv(.c) void;
extern fn xdg_output_update_all() callconv(.c) void;
extern fn xwayland_primary_update() callconv(.c) void;
extern fn xwayland_apply_scale(cl: [*c]Client) callconv(.c) void;
extern fn enable_adaptive_sync(m: *Monitor, state: *c.struct_wlr_output_state) callconv(.c) void;
extern fn disable_adaptive_sync(m: *Monitor, state: *c.struct_wlr_output_state) callconv(.c) void;
extern fn acwm_output_commit(m: *Monitor) callconv(.c) bool;
extern fn acwm_scene_output_commit(scene_output: *c.struct_wlr_scene_output, state: *c.struct_wlr_output_state) callconv(.c) bool;
extern fn monitor_check_skip_frame_timeout(m: *Monitor) callconv(.c) void;
extern fn monitor_stop_skip_frame_timer(m: *Monitor) callconv(.c) void;
extern fn layer_draw_frame(l: *LayerSurface) callconv(.c) bool;
extern fn layer_draw_fadeout_frame(l: *LayerSurface) callconv(.c) bool;
extern fn client_draw_frame(cl: [*c]Client) callconv(.c) bool;
extern fn client_draw_fadeout_frame(cl: [*c]Client) callconv(.c) bool;
extern fn client_is_rendered_on_mon(cl: [*c]Client, m: [*c]Monitor) callconv(.c) bool;
extern fn request_fresh_all_monitors() callconv(.c) void;

fn monitorOpt(p: [*c]Monitor) ?*Monitor {
    return if (p == null) null else @ptrCast(p);
}

fn containerOf(comptime T: type, comptime field: []const u8, link: anytype) *T {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(T, field));
}

fn clientFromLink(link: [*c]c.struct_wl_list) *Client {
    return containerOf(Client, "link", link);
}

fn monitorFromLink(link: [*c]c.struct_wl_list) *Monitor {
    return containerOf(Monitor, "link", link);
}

fn layerFromFadeoutLink(link: [*c]c.struct_wl_list) *LayerSurface {
    return containerOf(LayerSurface, "fadeout_link", link);
}

fn clientFromFadeoutLink(link: [*c]c.struct_wl_list) *Client {
    return containerOf(Client, "fadeout_link", link);
}

fn VISIBLEON(cl: *const Client, m: *const Monitor) bool {
    if (cl.mon != @as([*c]Monitor, @ptrCast(@constCast(m))))
        return false;
    if (cl.isminimized != 0)
        return false;
    return (cl.tags & m.tagset[m.seltags]) != 0 or cl.isglobal != 0 or cl.isunglobal != 0;
}

fn resizeInteract(cl: *Client, geo: Box, interact: i32) void {
    var opts = std.mem.zeroes(c.ResizeOpts);
    opts.interact = interact != 0;
    resize(cl, geo, opts);
}

fn clientSurface(cl: *Client) [*c]c.struct_wlr_surface {
    return c.client_surface(cl);
}

export fn handle_output_layout_change(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    _ = data;
    const output_config = c.wlr_output_configuration_v1_create();

    // First remove disabled monitors from the layout.
    var pos = c.server.monitors.next;
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.monitors);
    while (pos != head) : (pos = pos.*.next) {
        const m = monitorFromLink(pos);
        if (m.wlr_output.*.enabled)
            continue;
        const config_head = c.wlr_output_configuration_head_v1_create(output_config, m.wlr_output);
        config_head.*.state.enabled = false;

        if (m.only_sleep != 0)
            continue;

        c.wlr_output_layout_remove(c.server.output_layout, m.wlr_output);
        monitor_close(m);
        m.m = std.mem.zeroes(Box);
        m.w = std.mem.zeroes(Box);
    }

    // Insert outputs that need to be in the layout.
    pos = c.server.monitors.next;
    while (pos != head) : (pos = pos.*.next) {
        const m = monitorFromLink(pos);
        if (m.wlr_output.*.enabled and
            c.wlr_output_layout_get(c.server.output_layout, m.wlr_output) == null)
            _ = c.wlr_output_layout_add_auto(c.server.output_layout, m.wlr_output);
    }

    c.wlr_output_layout_get_box(c.server.output_layout, null, &c.server.scene_geometry);
    if (c.server.root_bg != null) {
        c.wlr_scene_node_set_position(&c.server.root_bg.*.node, c.server.scene_geometry.x, c.server.scene_geometry.y);
        c.wlr_scene_rect_set_size(c.server.root_bg, c.server.scene_geometry.width, c.server.scene_geometry.height);
    }
    if (c.server.locked_bg != null) {
        c.wlr_scene_node_set_position(&c.server.locked_bg.*.node, c.server.scene_geometry.x, c.server.scene_geometry.y);
        c.wlr_scene_rect_set_size(c.server.locked_bg, c.server.scene_geometry.width, c.server.scene_geometry.height);
    }

    pos = c.server.monitors.next;
    while (pos != head) : (pos = pos.*.next) {
        const m = monitorFromLink(pos);
        if (!m.wlr_output.*.enabled)
            continue;
        const config_head = c.wlr_output_configuration_head_v1_create(output_config, m.wlr_output);

        const oldx = m.m.x;
        const oldy = m.m.y;
        c.wlr_output_layout_get_box(c.server.output_layout, m.wlr_output, &m.m);
        m.w = m.m;
        const offset_x = m.m.x - oldx;
        const offset_y = m.m.y - oldy;

        var cpos = c.server.clients.next;
        const chead: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
        while (cpos != chead) : (cpos = cpos.*.next) {
            const cl = clientFromLink(cpos);
            const surface = clientSurface(cl);

            if (build_options.xwayland and c.client_is_x11(cl) != 0 and cl.mon == @as([*c]Monitor, @ptrCast(m))) {
                xwayland_apply_scale(cl);
                if (surface != null and surface.*.mapped)
                    resizeInteract(cl, cl.geom, 0);
            }

                    if (cl.isfloating != 0 and cl.mon == @as([*c]Monitor, @ptrCast(m))) {
                cl.geom.x += offset_x;
                cl.geom.y += offset_y;
                cl.float_geom = cl.geom;
                if (VISIBLEON(cl, m))
                    resizeInteract(cl, cl.geom, 1);
            }

            if (cl.mon != null and cl.mon != @as([*c]Monitor, @ptrCast(m)) and
                surface != null and surface.*.mapped and
                std.mem.eql(u8, std.mem.sliceTo(&cl.oldmonname, 0), std.mem.span(@as([*:0]const u8, @ptrCast(m.wlr_output.*.name)))))
                client_change_mon(cl, m);
        }

        c.wlr_scene_output_set_position(m.scene_output, m.m.x, m.m.y);

        if (c.config.blur != 0 and m.blur != null) {
            c.wlr_scene_node_set_position(&m.blur.*.node, m.m.x, m.m.y);
            c.wlr_scene_optimized_blur_set_size(m.blur, m.m.width, m.m.height);
        }

        special_update_dim(m);

        if (m.lock_surface != null) {
            const lock_surface = @as(*c.struct_wlr_session_lock_surface_v1, @ptrCast(m.lock_surface));
            if (lock_surface.surface != null and lock_surface.surface.*.data != null) {
                const scene_tree = @as(*c.struct_wlr_scene_tree, @ptrCast(@alignCast(lock_surface.surface.*.data.?)));
                c.wlr_scene_node_set_position(&scene_tree.node, m.m.x, m.m.y);
            }
            _ = c.wlr_session_lock_surface_v1_configure(lock_surface, @intCast(m.m.width), @intCast(m.m.height));
        }

        arrange_layers(m);
        arrange(m, false, false);
        const top = client_focus_top(m);
        if (top != null and top.*.isfullscreen != 0)
            resizeInteract(top, m.m, 0);

        config_head.*.state.x = m.m.x;
        config_head.*.state.y = m.m.y;

        if (c.server.selected_monitor == null)
            set_selected_monitor(m);
    }

    if (c.server.selected_monitor != null and c.server.selected_monitor.*.wlr_output.*.enabled) {
        var cpos = c.server.clients.next;
        const chead: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
        while (cpos != chead) : (cpos = cpos.*.next) {
            const cl = clientFromLink(cpos);
            const surface = clientSurface(cl);
            if (cl.mon == null and surface != null and surface.*.mapped) {
                cl.mon = c.server.selected_monitor;
                reset_foreign_tolevel(cl, null, cl.mon);
            }
            if (cl.tags == 0 and cl.is_in_scratchpad == 0) {
                const sel = @as(*Monitor, @ptrCast(c.server.selected_monitor));
                cl.tags = sel.tagset[sel.seltags];
                set_size_per(sel, cl, false);
            }
        }
        client_focus(client_focus_top(c.server.selected_monitor), 1);
        if (c.server.selected_monitor.*.lock_surface != null) {
            const lock_surface_ptr = @as(*c.struct_wlr_session_lock_surface_v1, @ptrCast(c.server.selected_monitor.*.lock_surface));
            const lock_surface = lock_surface_ptr.surface;
            if (lock_surface != null) {
                client_notify_enter(lock_surface, c.wlr_seat_get_keyboard(c.server.seat));
                client_activate_surface(lock_surface, true);
            }
        }
    }

    if (c.server.cursor != null)
        c.wlr_cursor_move(c.server.cursor, null, 0, 0);

    c.wlr_output_manager_v1_set_configuration(c.server.output_manager, output_config);
    xdg_output_update_all();

    if (build_options.xwayland)
        xwayland_primary_update();
}

export fn handle_output_manager_apply(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    output_manager_apply_or_test(@as(*OutputConfig, @ptrCast(@alignCast(data.?))), 0);
}

export fn handle_output_manager_test(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    output_manager_apply_or_test(@as(*OutputConfig, @ptrCast(@alignCast(data.?))), 1);
}

export fn output_manager_apply_or_test(config: *OutputConfig, test_only: i32) callconv(.c) void {
    var ok = true;
    const head: [*c]c.struct_wl_list = @ptrCast(&config.heads);
    var pos = config.heads.next;
    while (pos != head) : (pos = pos.*.next) {
        const config_head = containerOf(ConfigHead, "link", pos);
        const output = config_head.state.output;
        if (output == null or output.*.data == null)
            continue;
        const m = @as(*Monitor, @ptrCast(@alignCast(output.*.data.?)));

        m.only_sleep = 0;

        var state: c.struct_wlr_output_state = std.mem.zeroes(c.struct_wlr_output_state);
        c.wlr_output_state_set_enabled(&state, config_head.state.enabled);
        if (config_head.state.enabled) {
            if (config_head.state.mode != null)
                c.wlr_output_state_set_mode(&state, config_head.state.mode)
            else
                c.wlr_output_state_set_custom_mode(
                    &state,
                    config_head.state.custom_mode.width,
                    config_head.state.custom_mode.height,
                    config_head.state.custom_mode.refresh,
                );

            c.wlr_output_state_set_transform(&state, config_head.state.transform);
            c.wlr_output_state_set_scale(&state, config_head.state.scale);

            if (config_head.state.adaptive_sync_enabled)
                enable_adaptive_sync(m, &state)
            else
                disable_adaptive_sync(m, &state);
        }

        ok = ok and if (test_only != 0)
            c.wlr_output_test_state(output, &state)
        else
            c.wlr_output_commit_state(output, &state);

        if (test_only == 0 and output.*.enabled and
            (m.m.x != config_head.state.x or m.m.y != config_head.state.y))
            _ = c.wlr_output_layout_add(c.server.output_layout, output, config_head.state.x, config_head.state.y);

        c.wlr_output_state_finish(&state);
    }

    if (ok)
        c.wlr_output_configuration_v1_send_succeeded(config)
    else
        c.wlr_output_configuration_v1_send_failed(config);
    c.wlr_output_configuration_v1_destroy(config);

    handle_output_layout_change(null, null);
}

export fn handle_output_frame(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const m = containerOf(Monitor, "frame", listener);
    var need_more_frames = false;
    var resizing_on_this_mon = false;

    if (c.server.session != null and !c.server.session.*.active)
        return;
    if (m.wlr_output == null or !m.wlr_output.*.enabled or !c.server.allow_frame_scheduling)
        return;

    var i: usize = 0;
    while (i < m.layers.len) : (i += 1) {
        const list_head: [*c]c.struct_wl_list = @ptrCast(&m.layers[i]);
        var pos = m.layers[i].next;
        while (pos != list_head) {
            const next = pos.*.next;
            const l = containerOf(LayerSurface, "link", pos);
            need_more_frames = layer_draw_frame(l) or need_more_frames;
            pos = next;
        }
    }

    var fpos = c.server.fadeout_clients.next;
    const fchead: [*c]c.struct_wl_list = @ptrCast(&c.server.fadeout_clients);
    while (fpos != fchead) {
        const next = fpos.*.next;
        const cl = clientFromFadeoutLink(fpos);
        need_more_frames = client_draw_fadeout_frame(cl) or need_more_frames;
        fpos = next;
    }

    var lpos = c.server.fadeout_layers.next;
    const flhead: [*c]c.struct_wl_list = @ptrCast(&c.server.fadeout_layers);
    while (lpos != flhead) {
        const next = lpos.*.next;
        const l = layerFromFadeoutLink(lpos);
        need_more_frames = layer_draw_fadeout_frame(l) or need_more_frames;
        lpos = next;
    }

    var cpos = c.server.clients.next;
    const chead: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    while (cpos != chead) : (cpos = cpos.*.next) {
        const cl = clientFromLink(cpos);
        need_more_frames = client_draw_frame(cl) or need_more_frames;

        if (cl.force_render == 0 and cl.configure_serial != 0 and
            client_is_rendered_on_mon(cl, m))
            resizing_on_this_mon = true;
    }

    var do_commit = true;
    if (c.config.animations == 0 and c.server.grab_client == null and
        !need_more_frames and resizing_on_this_mon)
    {
        monitor_check_skip_frame_timeout(m);
        do_commit = false;
    }

    if (do_commit) {
        if (m.skiping_frame)
            monitor_stop_skip_frame_timer(m);
        _ = acwm_scene_output_commit(m.scene_output, &m.pending);
    }

    var now: c.struct_timespec = undefined;
    _ = c.clock_gettime(c.CLOCK_MONOTONIC, &now);
    c.wlr_scene_output_send_frame_done(m.scene_output, &now);

    if (need_more_frames and c.server.allow_frame_scheduling)
        request_fresh_all_monitors();
}

export fn check_vrr_enable(cl: ?*Client) callconv(.c) void {
    const cm = if (cl) |client| monitorOpt(client.mon) else null;

    if (cl == null) {
        const sel = monitorOpt(c.server.selected_monitor) orelse return;
        if (!sel.iscleanuping and sel.is_vrr_enabling and !sel.vrr_global_enable) {
            disable_adaptive_sync(sel, &sel.pending);
            _ = acwm_output_commit(sel);
        }
        return;
    }

    const client = cl.?;
    const m = cm orelse monitorOpt(c.server.selected_monitor) orelse return;

    if (cm != null and VISIBLEON(client, cm.?) and client.vrr_only_fullscreen != 0 and
        client.isfullscreen != 0 and !cm.?.is_vrr_enabling)
    {
        enable_adaptive_sync(cm.?, &m.pending);
        _ = acwm_output_commit(m);
        return;
    }

    if (cm != null and !cm.?.is_vrr_enabling and cm.?.vrr_global_enable) {
        enable_adaptive_sync(cm.?, &m.pending);
        _ = acwm_output_commit(m);
    } else if (cm != null and cm.?.is_vrr_enabling and !cm.?.vrr_global_enable and
        (client.vrr_only_fullscreen == 0 or client.isfullscreen == 0))
    {
        disable_adaptive_sync(cm.?, &m.pending);
        _ = acwm_output_commit(m);
    }
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/monitor_ops_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_monitor_close_calls: c_int;
extern var stub_selected_calls: c_int;
extern var stub_selected_value: [*c]Monitor;
extern var stub_dim_calls: c_int;
extern var stub_arrange_layers_calls: c_int;
extern var stub_arrange_calls: c_int;
extern var stub_resize_calls: c_int;
extern var stub_resize_geo: Box;
extern var stub_resize_interact: i32;
extern var stub_focus_calls: c_int;
extern var stub_focus_client: [*c]Client;
extern var stub_top_client: [*c]Client;
extern var stub_notify_calls: c_int;
extern var stub_notify_surface: [*c]c.struct_wlr_surface;
extern var stub_activate_calls: c_int;
extern var stub_change_mon_calls: c_int;
extern var stub_reset_foreign_calls: c_int;
extern var stub_size_per_calls: c_int;
extern var stub_xdg_update_calls: c_int;
extern var stub_xwayland_primary_calls: c_int;
extern var stub_xwayland_scale_calls: c_int;
extern var stub_enable_async_calls: c_int;
extern var stub_enable_async_value: bool;
extern var stub_disable_async_calls: c_int;
extern var stub_acwm_commit_calls: c_int;
extern var stub_scene_commit_calls: c_int;
extern var stub_check_timeout_calls: c_int;
extern var stub_stop_timer_calls: c_int;
extern var stub_layer_draw_calls: c_int;
extern var stub_layer_draw_result: bool;
extern var stub_layer_fade_calls: c_int;
extern var stub_layer_fade_result: bool;
extern var stub_client_draw_calls: c_int;
extern var stub_client_draw_result: bool;
extern var stub_client_fade_calls: c_int;
extern var stub_client_fade_result: bool;
extern var stub_client_surface_result: [*c]c.struct_wlr_surface;
extern var stub_rendered_calls: c_int;
extern var stub_rendered_result: bool;
extern var stub_fresh_calls: c_int;
extern var stub_config_create_calls: c_int;
extern var stub_head_create_calls: c_int;
extern var stub_succeeded_calls: c_int;
extern var stub_failed_calls: c_int;
extern var stub_config_destroy_calls: c_int;
extern var stub_manager_set_calls: c_int;
extern var stub_layout_remove_calls: c_int;
extern var stub_layout_add_calls: c_int;
extern var stub_layout_add_auto_calls: c_int;
extern var stub_layout_add_x: i32;
extern var stub_layout_add_y: i32;
extern var stub_box_result: Box;
extern var stub_layout_has_output: bool;
extern var stub_scene_pos_calls: c_int;
extern var stub_scene_pos_x: i32;
extern var stub_scene_pos_y: i32;
extern var stub_rect_size_calls: c_int;
extern var stub_rect_size_w: i32;
extern var stub_rect_size_h: i32;
extern var stub_blur_size_calls: c_int;
extern var stub_blur_size_w: i32;
extern var stub_blur_size_h: i32;
extern var stub_scene_output_pos_calls: c_int;
extern var stub_frame_done_calls: c_int;
extern var stub_cursor_move_calls: c_int;
extern var stub_lock_configure_calls: c_int;
extern var stub_test_result: bool;
extern var stub_test_calls: c_int;
extern var stub_commit_result: bool;
extern var stub_commit_calls: c_int;
extern var stub_state_enabled_calls: c_int;
extern var stub_state_enabled: bool;
extern var stub_state_mode_calls: c_int;
extern var stub_state_custom_calls: c_int;
extern var stub_state_transform_calls: c_int;
extern var stub_state_scale_calls: c_int;
extern var stub_state_finish_calls: c_int;

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

fn mkBox(x: i32, y: i32, w: i32, h: i32) Box {
    return .{ .x = x, .y = y, .width = w, .height = h };
}

fn resetOpsWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    listInit(&c.server.clients);
    listInit(&c.server.monitors);
    listInit(&c.server.fadeout_clients);
    listInit(&c.server.fadeout_layers);
    stub_monitor_close_calls = 0;
    stub_selected_calls = 0;
    stub_selected_value = null;
    stub_dim_calls = 0;
    stub_arrange_layers_calls = 0;
    stub_arrange_calls = 0;
    stub_resize_calls = 0;
    stub_resize_geo = std.mem.zeroes(Box);
    stub_resize_interact = -1;
    stub_focus_calls = 0;
    stub_focus_client = null;
    stub_top_client = null;
    stub_notify_calls = 0;
    stub_notify_surface = null;
    stub_activate_calls = 0;
    stub_change_mon_calls = 0;
    stub_reset_foreign_calls = 0;
    stub_size_per_calls = 0;
    stub_xdg_update_calls = 0;
    stub_xwayland_primary_calls = 0;
    stub_xwayland_scale_calls = 0;
    stub_enable_async_calls = 0;
    stub_enable_async_value = false;
    stub_disable_async_calls = 0;
    stub_acwm_commit_calls = 0;
    stub_scene_commit_calls = 0;
    stub_check_timeout_calls = 0;
    stub_stop_timer_calls = 0;
    stub_layer_draw_calls = 0;
    stub_layer_draw_result = false;
    stub_layer_fade_calls = 0;
    stub_layer_fade_result = false;
    stub_client_draw_calls = 0;
    stub_client_draw_result = false;
    stub_client_fade_calls = 0;
    stub_client_fade_result = false;
    stub_client_surface_result = null;
    stub_rendered_calls = 0;
    stub_rendered_result = false;
    stub_fresh_calls = 0;
    stub_config_create_calls = 0;
    stub_head_create_calls = 0;
    stub_succeeded_calls = 0;
    stub_failed_calls = 0;
    stub_config_destroy_calls = 0;
    stub_manager_set_calls = 0;
    stub_layout_remove_calls = 0;
    stub_layout_add_calls = 0;
    stub_layout_add_auto_calls = 0;
    stub_layout_add_x = 0;
    stub_layout_add_y = 0;
    stub_box_result = std.mem.zeroes(Box);
    stub_layout_has_output = false;
    stub_scene_pos_calls = 0;
    stub_scene_pos_x = 0;
    stub_scene_pos_y = 0;
    stub_rect_size_calls = 0;
    stub_rect_size_w = 0;
    stub_rect_size_h = 0;
    stub_blur_size_calls = 0;
    stub_blur_size_w = 0;
    stub_blur_size_h = 0;
    stub_scene_output_pos_calls = 0;
    stub_frame_done_calls = 0;
    stub_cursor_move_calls = 0;
    stub_lock_configure_calls = 0;
    stub_test_result = true;
    stub_test_calls = 0;
    stub_commit_result = true;
    stub_commit_calls = 0;
    stub_state_enabled_calls = 0;
    stub_state_enabled = false;
    stub_state_mode_calls = 0;
    stub_state_custom_calls = 0;
    stub_state_transform_calls = 0;
    stub_state_scale_calls = 0;
    stub_state_finish_calls = 0;
}

fn baseMonitor(m: *Monitor, out: *c.struct_wlr_output, scene_out: *c.struct_wlr_scene_output) void {
    m.* = std.mem.zeroes(Monitor);
    out.* = std.mem.zeroes(c.struct_wlr_output);
    scene_out.* = std.mem.zeroes(c.struct_wlr_scene_output);
    m.wlr_output = out;
    m.scene_output = scene_out;
    out.data = m;
    out.enabled = true;
    out.name = @ptrCast(@constCast("DP-1"));
    scene_out.output = out;
    var i: usize = 0;
    while (i < 4) : (i += 1)
        listInit(&m.layers[i]);
}

test "layout change removes disabled monitors honouring sleep" {
    resetOpsWorld();
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    var scene_out: c.struct_wlr_scene_output = undefined;
    baseMonitor(&m, &out, &scene_out);
    out.enabled = false;
    m.m = mkBox(5, 6, 700, 500);
    m.w = m.m;
    listInsert(&c.server.monitors, &m.link);
    stub_box_result = mkBox(0, 0, 1000, 800);

    handle_output_layout_change(null, null);
    try testing.expectEqual(@as(c_int, 1), stub_config_create_calls);
    try testing.expectEqual(@as(c_int, 1), stub_head_create_calls);
    try testing.expectEqual(@as(c_int, 1), stub_layout_remove_calls);
    try testing.expectEqual(@as(c_int, 1), stub_monitor_close_calls);
    try testing.expectEqual(@as(i32, 0), m.m.width);
    try testing.expectEqual(@as(i32, 0), m.w.height);
    try testing.expectEqual(@as(c_int, 1), stub_manager_set_calls);
    try testing.expectEqual(@as(c_int, 1), stub_xdg_update_calls);
    try testing.expectEqual(@as(c_int, if (build_options.xwayland) 1 else 0), stub_xwayland_primary_calls);

    resetOpsWorld();
    baseMonitor(&m, &out, &scene_out);
    out.enabled = false;
    m.only_sleep = 1;
    listInsert(&c.server.monitors, &m.link);
    handle_output_layout_change(null, null);
    try testing.expectEqual(@as(c_int, 0), stub_layout_remove_calls);
    try testing.expectEqual(@as(c_int, 0), stub_monitor_close_calls);
    try testing.expectEqual(@as(c_int, 1), stub_head_create_calls);
}

test "layout change repositions clients, blur and lock surfaces" {
    resetOpsWorld();
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    var scene_out: c.struct_wlr_scene_output = undefined;
    baseMonitor(&m, &out, &scene_out);
    m.m = mkBox(0, 0, 100, 100);
    m.tagset[0] = 1;
    m.seltags = 0;
    listInsert(&c.server.monitors, &m.link);
    stub_box_result = mkBox(10, 20, 800, 600);
    stub_layout_has_output = true;

    var root_bg: c.struct_wlr_scene_rect = std.mem.zeroes(c.struct_wlr_scene_rect);
    var locked_bg: c.struct_wlr_scene_rect = std.mem.zeroes(c.struct_wlr_scene_rect);
    c.server.root_bg = &root_bg;
    c.server.locked_bg = &locked_bg;
    c.server.cursor = @ptrFromInt(0x8000);
    c.config.blur = 1;
    var blur: c.struct_wlr_scene_optimized_blur = std.mem.zeroes(c.struct_wlr_scene_optimized_blur);
    m.blur = &blur;

    var surface: c.struct_wlr_surface = std.mem.zeroes(c.struct_wlr_surface);
    surface.mapped = true;
    stub_client_surface_result = &surface;

    var floating: c.Client = std.mem.zeroes(c.Client);
    floating.mon = &m;
    floating.isfloating = 1;
    floating.tags = 1;
    floating.geom = mkBox(5, 5, 100, 100);
    listInsert(&c.server.clients, &floating.link);

    var restored: c.Client = std.mem.zeroes(c.Client);
    restored.mon = @ptrFromInt(0x7000);
    @memcpy(restored.oldmonname[0..4], "DP-1");
    listInsert(&c.server.clients, &restored.link);

    var orphan: c.Client = std.mem.zeroes(c.Client);
    orphan.tags = 0;
    listInsert(&c.server.clients, &orphan.link);

    var ls: c.struct_wlr_session_lock_surface_v1 = std.mem.zeroes(c.struct_wlr_session_lock_surface_v1);
    var ls_scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    ls.surface = &surface;
    surface.data = &ls_scene;
    m.lock_surface = &ls;

    handle_output_layout_change(null, null);
    try testing.expectEqual(@as(i32, 10), m.m.x);
    try testing.expectEqual(@as(i32, 20), m.m.y);
    try testing.expectEqual(@as(i32, 800), m.w.width);
    try testing.expectEqual(@as(i32, 15), floating.geom.x);
    try testing.expectEqual(@as(i32, 25), floating.geom.y);
    try testing.expectEqual(@as(c_int, 1), stub_resize_calls);
    try testing.expectEqual(@as(i32, 1), stub_resize_interact);
    try testing.expectEqual(@as(c_int, 1), stub_change_mon_calls);
    try testing.expectEqual(@as(c_int, 1), stub_scene_output_pos_calls);
    try testing.expectEqual(@as(c_int, 1), stub_blur_size_calls);
    try testing.expectEqual(@as(c_int, 800), stub_blur_size_w);
    try testing.expectEqual(@as(c_int, 1), stub_dim_calls);
    try testing.expectEqual(@as(c_int, 1), stub_lock_configure_calls);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_layers_calls);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);
    try testing.expectEqual(@as(c_int, 1), stub_selected_calls);
    try testing.expect(stub_selected_value == &m);
    try testing.expect(orphan.mon == &m);
    try testing.expectEqual(@as(c_int, 1), stub_reset_foreign_calls);
    try testing.expectEqual(@as(u32, 1), orphan.tags);
    try testing.expectEqual(@as(c_int, 2), stub_size_per_calls);
    try testing.expectEqual(@as(c_int, 1), stub_cursor_move_calls);
    try testing.expectEqual(@as(c_int, 1), stub_manager_set_calls);
    try testing.expectEqual(@as(c_int, 1), stub_xdg_update_calls);
    try testing.expectEqual(@as(c_int, if (build_options.xwayland) 1 else 0), stub_xwayland_primary_calls);
    try testing.expectEqual(@as(c_int, 1), stub_notify_calls);
    try testing.expectEqual(@as(c_int, 1), stub_activate_calls);
}

test "output manager apply and test drive commits and layout" {
    resetOpsWorld();
    var m1: Monitor = undefined;
    var m2: Monitor = undefined;
    var o1: c.struct_wlr_output = undefined;
    var o2: c.struct_wlr_output = undefined;
    var s1: c.struct_wlr_scene_output = undefined;
    var s2: c.struct_wlr_scene_output = undefined;
    baseMonitor(&m1, &o1, &s1);
    baseMonitor(&m2, &o2, &s2);
    m1.m = mkBox(0, 0, 100, 100);

    var config: c.struct_wlr_output_configuration_v1 = std.mem.zeroes(c.struct_wlr_output_configuration_v1);
    listInit(&config.heads);
    var h1: c.struct_wlr_output_configuration_head_v1 = std.mem.zeroes(c.struct_wlr_output_configuration_head_v1);
    var h2: c.struct_wlr_output_configuration_head_v1 = std.mem.zeroes(c.struct_wlr_output_configuration_head_v1);
    h1.state.output = &o1;
    h1.state.enabled = true;
    h1.state.scale = 1.5;
    h1.state.transform = @intCast(2);
    h1.state.custom_mode.width = 800;
    h1.state.custom_mode.height = 600;
    h1.state.custom_mode.refresh = 60000;
    h1.state.adaptive_sync_enabled = true;
    h1.state.x = 50;
    h1.state.y = 60;
    h2.state.output = &o2;
    h2.state.enabled = false;
    listInsert(&config.heads, &h1.link);
    listInsert(&config.heads, &h2.link);

    output_manager_apply_or_test(&config, 0);
    try testing.expectEqual(@as(c_int, 2), stub_state_enabled_calls);
    try testing.expectEqual(@as(c_int, 1), stub_state_custom_calls);
    try testing.expectEqual(@as(c_int, 1), stub_state_transform_calls);
    try testing.expectEqual(@as(c_int, 1), stub_state_scale_calls);
    try testing.expectEqual(@as(c_int, 1), stub_enable_async_calls);
    try testing.expectEqual(@as(c_int, 2), stub_commit_calls);
    try testing.expectEqual(@as(c_int, 0), stub_state_mode_calls);
    try testing.expectEqual(@as(c_int, 1), stub_layout_add_calls);
    try testing.expectEqual(@as(i32, 50), stub_layout_add_x);
    try testing.expectEqual(@as(c_int, 2), stub_state_finish_calls);
    try testing.expectEqual(@as(c_int, 1), stub_succeeded_calls);
    try testing.expectEqual(@as(c_int, 1), stub_config_destroy_calls);

    resetOpsWorld();
    baseMonitor(&m1, &o1, &s1);
    baseMonitor(&m2, &o2, &s2);
    listInit(&config.heads);
    listInsert(&config.heads, &h1.link);
    output_manager_apply_or_test(&config, 1);
    try testing.expectEqual(@as(c_int, 1), stub_test_calls);
    try testing.expectEqual(@as(c_int, 0), stub_commit_calls);
    try testing.expectEqual(@as(c_int, 0), stub_layout_add_calls);
    try testing.expectEqual(@as(c_int, 1), stub_succeeded_calls);

    stub_test_result = false;
    listInit(&config.heads);
    listInsert(&config.heads, &h1.link);
    output_manager_apply_or_test(&config, 1);
    try testing.expectEqual(@as(c_int, 1), stub_failed_calls);
}

test "output frame draws layers, fadeouts and clients" {
    resetOpsWorld();
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    var scene_out: c.struct_wlr_scene_output = undefined;
    baseMonitor(&m, &out, &scene_out);
    c.server.allow_frame_scheduling = true;

    var session: c.struct_wlr_session = std.mem.zeroes(c.struct_wlr_session);
    session.active = false;
    c.server.session = &session;
    handle_output_frame(&m.frame, null);
    try testing.expectEqual(@as(c_int, 0), stub_scene_commit_calls);
    session.active = true;

    var layer: LayerSurface = std.mem.zeroes(LayerSurface);
    listInsert(&m.layers[0], &layer.link);
    var fade_layer: LayerSurface = std.mem.zeroes(LayerSurface);
    listInsert(&c.server.fadeout_layers, &fade_layer.fadeout_link);
    var fade_client: c.Client = std.mem.zeroes(c.Client);
    listInsert(&c.server.fadeout_clients, &fade_client.fadeout_link);
    var client: c.Client = std.mem.zeroes(c.Client);
    listInsert(&c.server.clients, &client.link);
    stub_client_surface_result = null;

    handle_output_frame(&m.frame, null);
    try testing.expectEqual(@as(c_int, 1), stub_layer_draw_calls);
    try testing.expectEqual(@as(c_int, 1), stub_layer_fade_calls);
    try testing.expectEqual(@as(c_int, 1), stub_client_fade_calls);
    try testing.expectEqual(@as(c_int, 1), stub_client_draw_calls);
    try testing.expectEqual(@as(c_int, 1), stub_scene_commit_calls);
    try testing.expectEqual(@as(c_int, 1), stub_frame_done_calls);
    try testing.expectEqual(@as(c_int, 0), stub_fresh_calls);

    stub_layer_draw_result = true;
    handle_output_frame(&m.frame, null);
    try testing.expectEqual(@as(c_int, 1), stub_fresh_calls);

    stub_layer_draw_result = false;
    c.config.animations = 0;
    client.force_render = 0;
    client.configure_serial = 5;
    stub_rendered_result = true;
    const commits = stub_scene_commit_calls;
    handle_output_frame(&m.frame, null);
    try testing.expectEqual(@as(c_int, 1), stub_check_timeout_calls);
    try testing.expectEqual(commits, stub_scene_commit_calls);

    m.skiping_frame = true;
    stub_rendered_result = false;
    stub_client_draw_result = false;
    handle_output_frame(&m.frame, null);
    try testing.expectEqual(@as(c_int, 1), stub_stop_timer_calls);
    try testing.expectEqual(commits + 1, stub_scene_commit_calls);
}

test "VRR toggles follow fullscreen and global flags" {
    resetOpsWorld();
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    var scene_out: c.struct_wlr_scene_output = undefined;
    baseMonitor(&m, &out, &scene_out);
    m.is_vrr_enabling = true;
    m.vrr_global_enable = false;
    c.server.selected_monitor = &m;

    check_vrr_enable(null);
    try testing.expectEqual(@as(c_int, 1), stub_disable_async_calls);
    try testing.expectEqual(@as(c_int, 1), stub_acwm_commit_calls);

    c.server.selected_monitor = null;
    check_vrr_enable(null);
    try testing.expectEqual(@as(c_int, 1), stub_acwm_commit_calls);

    resetOpsWorld();
    baseMonitor(&m, &out, &scene_out);
    m.tagset[0] = 1;
    m.seltags = 0;
    var client: c.Client = std.mem.zeroes(c.Client);
    client.mon = &m;
    client.tags = 1;
    client.vrr_only_fullscreen = 1;
    client.isfullscreen = 1;
    check_vrr_enable(&client);
    try testing.expectEqual(@as(c_int, 1), stub_enable_async_calls);
    try testing.expectEqual(@as(c_int, 1), stub_acwm_commit_calls);

    resetOpsWorld();
    baseMonitor(&m, &out, &scene_out);
    m.vrr_global_enable = true;
    client.mon = &m;
    check_vrr_enable(&client);
    try testing.expectEqual(@as(c_int, 1), stub_enable_async_calls);

    resetOpsWorld();
    baseMonitor(&m, &out, &scene_out);
    m.is_vrr_enabling = true;
    m.vrr_global_enable = false;
    client.mon = &m;
    client.vrr_only_fullscreen = 1;
    client.isfullscreen = 0;
    check_vrr_enable(&client);
    try testing.expectEqual(@as(c_int, 1), stub_disable_async_calls);
    try testing.expectEqual(@as(c_int, 1), stub_acwm_commit_calls);
}
