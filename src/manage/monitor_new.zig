//! Port of handle_new_output in src/manage/monitor.c
//! (Phase 5, manage slice 9, slice 57).

const std = @import("std");
const c = @import("cc");

const Monitor = c.Monitor;
const OutputState = c.struct_wlr_output_state;
const Box = c.struct_wlr_box;

const EXT_WORKSPACE_ENABLE_CAPS: u32 = 1 | 2;

extern fn wlr_output_is_headless(output: [*c]c.struct_wlr_output) callconv(.c) bool;
extern fn wlr_ext_workspace_group_handle_v1_create(manager: ?*c.struct_wlr_ext_workspace_manager_v1, caps: u32) callconv(.c) ?*c.struct_wlr_ext_workspace_group_handle_v1;
extern fn wlr_ext_workspace_group_handle_v1_output_enter(group: ?*c.struct_wlr_ext_workspace_group_handle_v1, output: [*c]c.struct_wlr_output) callconv(.c) void;
extern fn output_state_setup_hdr(m: *Monitor, silent: bool, state: *OutputState) callconv(.c) void;
extern fn output_enable_hdr(m: *Monitor, state: *OutputState, enabled: bool, silent: bool) callconv(.c) void;
extern fn add_workspace_by_tag(tag: i32, m: *Monitor) callconv(.c) void;
extern fn bar_monitor_create(m: *Monitor) callconv(.c) void;
extern fn handle_output_layout_change(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn special_update_dim(m: ?*Monitor) callconv(.c) void;
extern fn monitor_matches_rule(m: *Monitor, rule: *const c.ConfigMonitorRule) callconv(.c) bool;
extern fn apply_rule_to_state(m: *Monitor, rule: *const c.ConfigMonitorRule, state: *OutputState) callconv(.c) bool;
extern fn regex_match(pattern_mb: [*c]const u8, str_mb: [*c]const u8) callconv(.c) i32;
extern fn printstatus(t: c.enum_ipc_watch_type) callconv(.c) void;
extern fn monitor_skip_frame_timeout_callback(data: ?*anyopaque) callconv(.c) c_int;
extern fn handle_output_frame(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_output_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_output_request_state(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn wlr_output_init_render(output: [*c]c.struct_wlr_output, allocator: ?*c.struct_wlr_allocator_30, renderer: [*c]c.struct_wlr_renderer) callconv(.c) bool;

const ENABLED_BIT: u32 = @intCast(c.WLR_OUTPUT_STATE_ENABLED);
const MODE_BIT: u32 = @intCast(c.WLR_OUTPUT_STATE_MODE);
const SCALE_BIT: u32 = @intCast(c.WLR_OUTPUT_STATE_SCALE);
const TRANSFORM_BIT: u32 = @intCast(c.WLR_OUTPUT_STATE_TRANSFORM);
const ADAPTIVE_BIT: u32 = @intCast(c.WLR_OUTPUT_STATE_ADAPTIVE_SYNC_ENABLED);
const IMG_DESC_BIT: u32 = @intCast(c.WLR_OUTPUT_STATE_IMAGE_DESCRIPTION);

fn has(state: *const OutputState, bit: u32) bool {
    return (state.committed & bit) != 0;
}

export fn handle_new_output(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const output = @as(*c.struct_wlr_output, @ptrCast(@alignCast(data.?)));

    if (c.server.pending_headless_output_name != null and wlr_output_is_headless(output))
        c.wlr_output_set_name(output, c.server.pending_headless_output_name);

    const init_ok: bool = wlr_output_init_render(output, c.server.allocator, c.server.renderer);
    if (!init_ok)
        return;

    if (output.non_desktop) {
        if (c.server.drm_lease_manager != null)
            _ = c.wlr_drm_lease_v1_manager_offer_output(c.server.drm_lease_manager, output);
        return;
    }

    const loop = c.wl_display_get_event_loop(c.server.display);
    const raw = c.ecalloc(1, @sizeOf(Monitor)) orelse return;
    const m = @as(*Monitor, @ptrCast(@alignCast(raw)));
    output.data = @ptrCast(m);
    c.wlr_output_state_init(&m.pending);

    m.iscleanuping = false;
    m.skip_frame_timeout = c.wl_event_loop_add_timer(loop, monitor_skip_frame_timeout_callback, m);
    m.skiping_frame = false;
    m.resizing_count_pending = 0;
    m.resizing_count_current = 0;
    m.carousel_anim_dir = 0;
    m.vrr_global_enable = false;
    m.is_vrr_enabling = false;
    m.hdr_enable = false;
    m.prefer_disable = false;
    m.is_hdr_enabling = false;
    m.hdr_min_lum = 0.0;
    m.hdr_max_lum = 0.0;
    m.hdr_max_avg_lum = 0.0;
    m.hdr_force = false;

    m.wlr_output = output;
    output.data = @ptrCast(m);

    var i: usize = 0;
    while (i < m.layers.len) : (i += 1)
        c.wl_list_init(&m.layers[i]);

    m.gappih = @intCast(c.config.gappih);
    m.gappiv = @intCast(c.config.gappiv);
    m.gappoh = @intCast(c.config.gappoh);
    m.gappov = @intCast(c.config.gappov);
    m.special_gappih = @intCast(c.config.special_gappih);
    m.special_gappiv = @intCast(c.config.special_gappiv);
    m.special_gappoh = @intCast(c.config.special_gappoh);
    m.special_gappov = @intCast(c.config.special_gappov);
    m.isoverview = 0;
    m.sel = null;
    m.is_in_hotarea = 0;
    m.ov_normal_mode = 0;
    m.ov_tab_layout = 0;
    m.m.x = c.INT32_MAX;
    m.m.y = c.INT32_MAX;

    var pending: OutputState = std.mem.zeroes(OutputState);
    c.wlr_output_state_init(&pending);
    c.wlr_output_state_set_scale(&pending, 1.0);
    c.wlr_output_state_set_transform(&pending, 0);
    c.wlr_output_state_set_enabled(&pending, true);

    var custom_monitor_mode = false;
    var ji: i32 = 0;
    while (ji < c.config.monitor_rules_count) : (ji += 1) {
        const idx: usize = @intCast(ji);
        const rule: *const c.ConfigMonitorRule = @ptrCast(&c.config.monitor_rules[idx]);
        if (monitor_matches_rule(m, rule)) {
            m.m.x = rule.x;
            m.m.y = rule.y;
            if (apply_rule_to_state(m, rule, &pending))
                custom_monitor_mode = true;
            break;
        }
    }

    if (!custom_monitor_mode) {
        const preferred = c.wlr_output_preferred_mode(output);
        if (preferred != null) {
            c.wlr_output_state_set_mode(&pending, preferred);
        } else {
            var custom_test: OutputState = std.mem.zeroes(OutputState);
            c.wlr_output_state_init(&custom_test);
            c.wlr_output_state_set_custom_mode(&custom_test, 1920, 1080, 60000);
            if (c.wlr_output_test_state(output, &custom_test))
                c.wlr_output_state_set_custom_mode(&pending, 1920, 1080, 60000);
            c.wlr_output_state_finish(&custom_test);
        }
    }

    var state: OutputState = std.mem.zeroes(OutputState);
    c.wlr_output_state_init(&state);

    if (has(&pending, ENABLED_BIT))
        c.wlr_output_state_set_enabled(&state, pending.enabled);

    if (has(&pending, MODE_BIT)) {
        if (pending.mode_type == @as(c.enum_wlr_output_state_mode_type, @intCast(c.WLR_OUTPUT_STATE_MODE_FIXED)))
            c.wlr_output_state_set_mode(&state, pending.mode)
        else if (pending.mode_type == @as(c.enum_wlr_output_state_mode_type, @intCast(c.WLR_OUTPUT_STATE_MODE_CUSTOM)))
            c.wlr_output_state_set_custom_mode(&state, pending.custom_mode.width, pending.custom_mode.height, pending.custom_mode.refresh);
    } else {
        const pref = c.wlr_output_preferred_mode(output);
        if (pref != null)
            c.wlr_output_state_set_mode(&state, pref);
    }

    if (has(&pending, SCALE_BIT))
        c.wlr_output_state_set_scale(&state, pending.scale);
    if (has(&pending, TRANSFORM_BIT))
        c.wlr_output_state_set_transform(&state, pending.transform);
    if (has(&pending, ADAPTIVE_BIT))
        c.wlr_output_state_set_adaptive_sync_enabled(&state, pending.adaptive_sync_enabled);

    if (m.hdr_enable)
        output_state_setup_hdr(m, false, &state)
    else
        output_enable_hdr(m, &state, false, false);

    m.scene_output = c.wlr_scene_output_create(c.server.scene, output);

    const has_img_desc = has(&state, IMG_DESC_BIT) or output.image_description != null;
    var opts = std.mem.zeroes(c.struct_wlr_scene_output_state_options);
    opts.swapchain = null;
    opts.color_transform = null;
    if (m.icc_transform != null and !has_img_desc)
        opts.color_transform = m.icc_transform;

    _ = c.wlr_scene_output_build_state(m.scene_output, &state, &opts);
    _ = c.wlr_output_commit_state(output, &state);

    c.wlr_output_state_finish(&state);
    c.wlr_output_state_finish(&pending);

    var layout_output: [*c]c.struct_wlr_output_layout_output = null;
    if (m.m.x == c.INT32_MAX or m.m.y == c.INT32_MAX)
        layout_output = c.wlr_output_layout_add_auto(c.server.output_layout, output)
    else
        layout_output = c.wlr_output_layout_add(c.server.output_layout, output, m.m.x, m.m.y);

    c.wlr_scene_output_layout_add_output(c.server.scene_layout, layout_output, m.scene_output);

    c.wlr_output_layout_get_box(c.server.output_layout, output, &m.m);

    c.wl_list_insert(&c.server.monitors, &m.link);

    m.pertag = @ptrCast(@alignCast(c.ecalloc(1, @sizeOf(c.Pertag)) orelse return));
    var slot: usize = 0;
    while (slot < 32) : (slot += 1)
        m.pertag.*.scroller_state[slot] = null;

    if (c.server.chvt_backup_tag != 0 and
        regex_match(&c.server.chvt_backup_monitor_name[0], output.name) != 0)
    {
        const bit = @as(u32, 1) << @intCast(c.server.chvt_backup_tag - 1);
        m.tagset[0] = bit & c.server.tagmask;
        m.tagset[1] = m.tagset[0];
        m.pertag.*.curtag = c.server.chvt_backup_tag;
        m.pertag.*.prevtag = c.server.chvt_backup_tag;
        c.server.chvt_backup_tag = 0;
        @memset(&c.server.chvt_backup_monitor_name, 0);
    } else {
        m.tagset[0] = 1;
        m.tagset[1] = 1;
        m.pertag.*.curtag = 1;
        m.pertag.*.prevtag = 1;
    }

    const tag_num: usize = @intCast(c.config.tag_num);
    var ti: usize = 0;
    while (ti <= tag_num) : (ti += 1) {
        m.pertag.*.nmasters[ti] = @intCast(c.config.default_nmaster);
        m.pertag.*.mfacts[ti] = c.config.default_mfact;
        m.pertag.*.ltidxs[ti] = &c.layouts[0];
    }

    c.parse_tagrule(m);

    if (c.config.blur != 0) {
        m.blur = c.wlr_scene_optimized_blur_create(&c.server.scene.*.tree, 0, 0);
        if (m.blur != null) {
            c.wlr_scene_node_set_position(&m.blur.*.node, m.m.x, m.m.y);
            c.wlr_scene_node_reparent(&m.blur.*.node, c.server.layers[@intCast(c.LyrBlur)]);
            c.wlr_scene_optimized_blur_set_size(m.blur, m.m.width, m.m.height);
        }
    }

    const dim_color = [4]f32{ 0.0, 0.0, 0.0, c.config.special_dim };
    m.special_dim_rect = c.wlr_scene_rect_create(c.server.layers[@intCast(c.LyrSpecialDim)], m.m.width, m.m.height, &dim_color);
    special_update_dim(m);

    m.ext_group = wlr_ext_workspace_group_handle_v1_create(c.server.ext_workspace_manager, EXT_WORKSPACE_ENABLE_CAPS);
    if (m.ext_group != null)
        wlr_ext_workspace_group_handle_v1_output_enter(m.ext_group, m.wlr_output);

    var tag: i32 = 1;
    while (tag <= c.config.tag_num) : (tag += 1)
        add_workspace_by_tag(tag, m);

    handle_output_layout_change(null, null);
    bar_monitor_create(m);

    m.frame.notify = handle_output_frame;
    c.wl_signal_add(&output.events.frame, &m.frame);
    m.destroy.notify = handle_output_destroy;
    c.wl_signal_add(&output.events.destroy, &m.destroy);
    m.request_state.notify = handle_output_request_state;
    c.wl_signal_add(&output.events.request_state, &m.request_state);

    printstatus(@intCast(c.IPC_WATCH_ARRANGGE));
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/monitor_new_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_headless: bool;
extern var stub_set_name_calls: c_int;
extern var stub_last_name: [*c]const u8;
extern var stub_init_render: bool;
extern var stub_init_render_calls: c_int;
extern var stub_lease_offer_calls: c_int;
extern var stub_has_preferred: bool;
extern var stub_preferred_mode: c.struct_wlr_output_mode;
extern var stub_test_result: bool;
extern var stub_test_calls: c_int;
extern var stub_commit_result: bool;
extern var stub_commit_calls: c_int;
extern var stub_state_init_calls: c_int;
extern var stub_state_finish_calls: c_int;
extern var stub_state_enabled_calls: c_int;
extern var stub_state_scale_calls: c_int;
extern var stub_state_transform_calls: c_int;
extern var stub_state_adaptive_calls: c_int;
extern var stub_state_mode_calls: c_int;
extern var stub_state_custom_calls: c_int;
extern var stub_scene_output_create_calls: c_int;
extern var stub_build_calls: c_int;
extern var stub_build_transform: ?*c.struct_wlr_color_transform;
extern var stub_layout_output: [*c]c.struct_wlr_output_layout_output;
extern var stub_add_auto_calls: c_int;
extern var stub_add_calls: c_int;
extern var stub_add_x: i32;
extern var stub_add_y: i32;
extern var stub_box_result: Box;
extern var stub_scene_layout_add_calls: c_int;
extern var stub_blur_create_calls: c_int;
extern var stub_blur_size_calls: c_int;
extern var stub_blur_w: i32;
extern var stub_blur_h: i32;
extern var stub_scene_pos_calls: c_int;
extern var stub_scene_x: i32;
extern var stub_scene_y: i32;
extern var stub_reparent_calls: c_int;
extern var stub_rect_create_calls: c_int;
extern var stub_rect_w: i32;
extern var stub_rect_h: i32;
extern var stub_rect_color: [4]f32;
extern var stub_timer_add_calls: c_int;
extern var stub_group_create_calls: c_int;
extern var stub_group_caps: u32;
extern var stub_group_enter_calls: c_int;
extern var stub_rule_match: bool;
extern var stub_apply_result: bool;
extern var stub_apply_hdr: bool;
extern var stub_apply_icc: ?*c.struct_wlr_color_transform;
extern var stub_hdr_setup_calls: c_int;
extern var stub_hdr_enable_calls: c_int;
extern var stub_workspace_calls: c_int;
extern var stub_last_workspace_tag: i32;
extern var stub_parse_tagrule_calls: c_int;
extern var stub_layout_change_calls: c_int;
extern var stub_bar_create_calls: c_int;
extern var stub_dim_calls: c_int;
extern var stub_printstatus_calls: c_int;

fn listInit(head: *c.struct_wl_list) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

fn resetNewWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    listInit(&c.server.monitors);
    stub_headless = false;
    stub_set_name_calls = 0;
    stub_last_name = null;
    stub_init_render = true;
    stub_init_render_calls = 0;
    stub_lease_offer_calls = 0;
    stub_has_preferred = true;
    stub_preferred_mode = std.mem.zeroes(c.struct_wlr_output_mode);
    stub_preferred_mode.width = 2560;
    stub_preferred_mode.height = 1440;
    stub_preferred_mode.refresh = 60000;
    stub_test_result = true;
    stub_test_calls = 0;
    stub_commit_result = true;
    stub_commit_calls = 0;
    stub_state_init_calls = 0;
    stub_state_finish_calls = 0;
    stub_state_enabled_calls = 0;
    stub_state_scale_calls = 0;
    stub_state_transform_calls = 0;
    stub_state_adaptive_calls = 0;
    stub_state_mode_calls = 0;
    stub_state_custom_calls = 0;
    stub_scene_output_create_calls = 0;
    stub_build_calls = 0;
    stub_build_transform = null;
    stub_layout_output = @ptrFromInt(0x1000);
    stub_add_auto_calls = 0;
    stub_add_calls = 0;
    stub_add_x = 0;
    stub_add_y = 0;
    stub_box_result = .{ .x = 0, .y = 0, .width = 1920, .height = 1080 };
    stub_scene_layout_add_calls = 0;
    stub_blur_create_calls = 0;
    stub_blur_size_calls = 0;
    stub_blur_w = 0;
    stub_blur_h = 0;
    stub_scene_pos_calls = 0;
    stub_scene_x = 0;
    stub_scene_y = 0;
    stub_reparent_calls = 0;
    stub_rect_create_calls = 0;
    stub_rect_w = 0;
    stub_rect_h = 0;
    stub_rect_color = std.mem.zeroes([4]f32);
    stub_timer_add_calls = 0;
    stub_group_create_calls = 0;
    stub_group_caps = 0;
    stub_group_enter_calls = 0;
    stub_rule_match = false;
    stub_apply_result = false;
    stub_apply_hdr = false;
    stub_apply_icc = null;
    stub_hdr_setup_calls = 0;
    stub_hdr_enable_calls = 0;
    stub_workspace_calls = 0;
    stub_last_workspace_tag = 0;
    stub_parse_tagrule_calls = 0;
    stub_layout_change_calls = 0;
    stub_bar_create_calls = 0;
    stub_dim_calls = 0;
    stub_printstatus_calls = 0;

    c.config.tag_num = 3;
    c.config.default_nmaster = 1;
    c.config.default_mfact = 0.55;
    c.config.gappih = 2;
    c.config.gappiv = 3;
    c.config.gappoh = 4;
    c.config.gappov = 5;
    c.config.special_gappih = 6;
    c.config.special_gappiv = 7;
    c.config.special_gappoh = 8;
    c.config.special_gappov = 9;
    c.server.tagmask = 0xffffffff;
    c.server.display = @ptrFromInt(0x2000);
    c.server.scene = @ptrFromInt(0x3000);
    c.server.scene_layout = @ptrFromInt(0x4000);
    c.server.output_layout = @ptrFromInt(0x5000);
    c.server.ext_workspace_manager = @ptrFromInt(0x6000);
}

fn newOutput(out: *c.struct_wlr_output) void {
    out.* = std.mem.zeroes(c.struct_wlr_output);
    out.name = @ptrCast(@constCast("DP-1"));
    out.enabled = false;
}

test "new output honours render init, headless names and non-desktop leases" {
    resetNewWorld();
    var out: c.struct_wlr_output = undefined;
    newOutput(&out);
    c.server.drm_lease_manager = @ptrFromInt(0x7000);
    out.non_desktop = true;
    handle_new_output(null, &out);
    try testing.expectEqual(@as(c_int, 1), stub_lease_offer_calls);
    try testing.expect(out.data == null);

    resetNewWorld();
    newOutput(&out);
    c.server.drm_lease_manager = @ptrFromInt(0x7000);
    stub_init_render = false;
    handle_new_output(null, &out);
    try testing.expectEqual(@as(c_int, 0), stub_lease_offer_calls);
    try testing.expect(out.data == null);

    resetNewWorld();
    newOutput(&out);
    c.server.pending_headless_output_name = "HEADLESS-1";
    stub_headless = true;
    handle_new_output(null, &out);
    try testing.expectEqual(@as(c_int, 1), stub_set_name_calls);
    try testing.expectEqualStrings("HEADLESS-1", std.mem.span(@as([*:0]const u8, @ptrCast(stub_last_name))));

    resetNewWorld();
    newOutput(&out);
    out.non_desktop = true;
    handle_new_output(null, &out);
    try testing.expectEqual(@as(c_int, 0), stub_lease_offer_calls);
}

test "new output builds the monitor, state and scene wiring" {
    resetNewWorld();
    var out: c.struct_wlr_output = undefined;
    newOutput(&out);
    c.config.blur = 1;

    handle_new_output(null, &out);
    try testing.expectEqual(@as(c_int, 1), stub_init_render_calls);
    try testing.expectEqual(@as(c_int, 2), stub_state_mode_calls);
    try testing.expectEqual(@as(c_int, 1), stub_hdr_enable_calls);
    try testing.expectEqual(@as(c_int, 0), stub_hdr_setup_calls);
    try testing.expectEqual(@as(c_int, 1), stub_scene_output_create_calls);
    try testing.expectEqual(@as(c_int, 1), stub_build_calls);
    try testing.expectEqual(@as(c_int, 1), stub_commit_calls);
    try testing.expectEqual(@as(c_int, 1), stub_add_auto_calls);
    try testing.expectEqual(@as(c_int, 0), stub_add_calls);
    try testing.expectEqual(@as(c_int, 1), stub_scene_layout_add_calls);
    try testing.expectEqual(@as(c_int, 1), stub_timer_add_calls);
    try testing.expectEqual(@as(c_int, 1), stub_bar_create_calls);
    try testing.expectEqual(@as(c_int, 1), stub_layout_change_calls);
    try testing.expectEqual(@as(c_int, 1), stub_printstatus_calls);
    try testing.expectEqual(@as(c_int, 1), stub_blur_create_calls);
    try testing.expectEqual(@as(c_int, 1), stub_rect_create_calls);
    try testing.expectEqual(@as(c_int, 1), stub_dim_calls);
    try testing.expectEqual(@as(c_int, 1), stub_group_create_calls);
    try testing.expectEqual(@as(u32, 3), stub_group_caps);
    try testing.expectEqual(@as(c_int, 1), stub_group_enter_calls);
    try testing.expectEqual(@as(c_int, 3), stub_workspace_calls);
    try testing.expectEqual(@as(i32, 3), stub_last_workspace_tag);
    try testing.expectEqual(@as(c_int, 1), stub_parse_tagrule_calls);

    try testing.expect(out.data != null);
    const m = @as(*Monitor, @ptrCast(@alignCast(out.data.?)));
    try testing.expect(m.wlr_output == &out);
    try testing.expect(m.scene_output != null);
    try testing.expect(m.pertag != null);
    try testing.expectEqual(@as(u32, 1), m.tagset[0]);
    try testing.expectEqual(@as(u32, 1), m.tagset[1]);
    try testing.expectEqual(@as(u32, 1), m.pertag.*.curtag);
    try testing.expectEqual(@as(u32, 1), m.pertag.*.prevtag);
    try testing.expectEqual(@as(i32, 1), m.pertag.*.nmasters[0]);
    try testing.expectEqual(@as(i32, 1), m.pertag.*.nmasters[3]);
    try testing.expectApproxEqAbs(@as(f32, 0.55), m.pertag.*.mfacts[2], 1e-6);
    try testing.expect(m.pertag.*.ltidxs[0] == &c.layouts[0]);
    try testing.expectEqual(@as(i32, 0), m.m.x);
    try testing.expectEqual(@as(i32, 1920), m.m.width);
    try testing.expectEqual(@as(i32, 2), m.gappih);
    try testing.expectEqual(@as(i32, 9), m.special_gappov);
    try testing.expect(m.blur != null);
    try testing.expect(m.special_dim_rect != null);
    try testing.expect(m.ext_group != null);
    try testing.expect(m.frame.notify != null);
    try testing.expect(m.destroy.notify != null);
    try testing.expect(m.request_state.notify != null);
    try testing.expect(@intFromPtr(c.server.monitors.next) != @intFromPtr(&c.server.monitors));
}

test "new output applies the first matching monitor rule" {
    resetNewWorld();
    var out: c.struct_wlr_output = undefined;
    newOutput(&out);
    var rule: c.ConfigMonitorRule = std.mem.zeroes(c.ConfigMonitorRule);
    rule.x = 10;
    rule.y = 20;
    c.config.monitor_rules = &rule;
    c.config.monitor_rules_count = 1;
    stub_rule_match = true;
    stub_apply_result = true;
    stub_apply_hdr = true;
    const transform: *c.struct_wlr_color_transform = @ptrFromInt(0x8000);
    stub_apply_icc = transform;
    stub_box_result = .{ .x = 10, .y = 20, .width = 1920, .height = 1080 };
    c.server.scene = @ptrFromInt(0x3000);

    handle_new_output(null, &out);
    const m = @as(*Monitor, @ptrCast(@alignCast(out.data.?)));
    try testing.expectEqual(@as(i32, 10), m.m.x);
    try testing.expectEqual(@as(i32, 20), m.m.y);
    try testing.expectEqual(@as(c_int, 1), stub_state_mode_calls);
    try testing.expectEqual(@as(c_int, 1), stub_hdr_setup_calls);
    try testing.expectEqual(@as(c_int, 0), stub_hdr_enable_calls);
    try testing.expect(stub_build_transform == transform);
    try testing.expectEqual(@as(c_int, 0), stub_add_auto_calls);
    try testing.expectEqual(@as(c_int, 1), stub_add_calls);
    try testing.expectEqual(@as(i32, 10), stub_add_x);
    try testing.expectEqual(@as(i32, 20), stub_add_y);
}

test "new output falls back to preferred or custom modes" {
    resetNewWorld();
    var out: c.struct_wlr_output = undefined;
    newOutput(&out);
    stub_has_preferred = false;
    stub_test_result = true;
    handle_new_output(null, &out);
    try testing.expectEqual(@as(c_int, 1), stub_test_calls);
    try testing.expectEqual(@as(c_int, 3), stub_state_custom_calls);

    resetNewWorld();
    newOutput(&out);
    stub_has_preferred = false;
    stub_test_result = false;
    handle_new_output(null, &out);
    try testing.expectEqual(@as(c_int, 1), stub_state_custom_calls);
    try testing.expectEqual(@as(c_int, 1), stub_test_calls);
}

test "new output restores a chvt tag and skips blur when disabled" {
    resetNewWorld();
    var out: c.struct_wlr_output = undefined;
    newOutput(&out);
    c.server.chvt_backup_tag = 3;
    @memcpy(c.server.chvt_backup_monitor_name[0..4], "DP-1");
    c.config.tag_num = 2;
    handle_new_output(null, &out);
    const m = @as(*Monitor, @ptrCast(@alignCast(out.data.?)));
    try testing.expectEqual(@as(u32, 0b100), m.tagset[0]);
    try testing.expectEqual(@as(u32, 3), m.pertag.*.curtag);
    try testing.expectEqual(@as(u32, 0), c.server.chvt_backup_tag);
    try testing.expectEqual(@as(u8, 0), c.server.chvt_backup_monitor_name[0]);
    try testing.expectEqual(@as(c_int, 0), stub_blur_create_calls);
    try testing.expectEqual(@as(c_int, 1), stub_rect_create_calls);
}
