//! Port of the output commit / mode / adaptive-sync / ICC / monitor-rule
//! cluster in src/manage/monitor.c (Phase 5, manage slice 6, slice 54).

const std = @import("std");
const c = @import("cc");

const Monitor = c.Monitor;
const OutputState = c.struct_wlr_output_state;
const SceneOutput = c.struct_wlr_scene_output;

extern fn check_tearing_frame_allow(m: *Monitor) callconv(.c) bool;
extern fn wlr_output_is_headless(output: [*c]c.struct_wlr_output) callconv(.c) bool;
extern fn regex_match(pattern_mb: [*c]const u8, str_mb: [*c]const u8) callconv(.c) i32;

fn cString(p: [*c]const u8) ?[]const u8 {
    if (p == null)
        return null;
    return std.mem.span(@as([*:0]const u8, @ptrCast(p)));
}

fn strEqZ(p: [*c]const u8, s: []const u8) bool {
    const span = cString(p) orelse return false;
    return std.mem.eql(u8, span, s);
}

const STATE_BITS: u32 =
    @as(u32, @intCast(c.WLR_OUTPUT_STATE_MODE)) |
    @as(u32, @intCast(c.WLR_OUTPUT_STATE_SCALE)) |
    @as(u32, @intCast(c.WLR_OUTPUT_STATE_TRANSFORM)) |
    @as(u32, @intCast(c.WLR_OUTPUT_STATE_ENABLED)) |
    @as(u32, @intCast(c.WLR_OUTPUT_STATE_ADAPTIVE_SYNC_ENABLED)) |
    @as(u32, @intCast(c.WLR_OUTPUT_STATE_IMAGE_DESCRIPTION));

const IMG_DESC_BIT: u32 = @intCast(c.WLR_OUTPUT_STATE_IMAGE_DESCRIPTION);

export fn acwm_scene_output_commit(scene_output: *SceneOutput, state: *OutputState) callconv(.c) bool {
    const output = scene_output.output;
    if (output == null or output.*.data == null)
        return false;
    const m = @as(*Monitor, @ptrCast(@alignCast(output.*.data.?)));

    const frame_allow_tearing = check_tearing_frame_allow(m);

    const state_changed = (state.committed & STATE_BITS) != 0;
    if (!state_changed and !c.wlr_scene_output_needs_frame(scene_output))
        return true;

    const has_img_desc = (state.committed & IMG_DESC_BIT) != 0 or output.*.image_description != null;
    var opts = std.mem.zeroes(c.struct_wlr_scene_output_state_options);
    if (m.icc_transform != null and !has_img_desc)
        opts.color_transform = m.icc_transform;
    if (!c.wlr_scene_output_build_state(scene_output, state, &opts))
        return false;

    state.tearing_page_flip = frame_allow_tearing;

    if (state.tearing_page_flip) {
        if (!c.wlr_output_test_state(output, state))
            state.tearing_page_flip = false;
    }

    var committed = c.wlr_output_commit_state(output, state);
    if (!committed and state.tearing_page_flip) {
        state.tearing_page_flip = false;
        committed = c.wlr_output_commit_state(output, state);
    }

    if (committed) {
        if (@intFromPtr(state) == @intFromPtr(&m.pending)) {
            c.wlr_output_state_finish(&m.pending);
            c.wlr_output_state_init(&m.pending);
        }
    } else {
        return false;
    }

    return committed;
}

export fn acwm_output_commit(m: *Monitor) callconv(.c) bool {
    const committed = c.wlr_output_commit_state(m.wlr_output, &m.pending);
    if (committed) {
        c.wlr_output_state_finish(&m.pending);
        c.wlr_output_state_init(&m.pending);
    }
    return committed;
}

fn modeFromLink(link: [*c]c.struct_wl_list) *c.struct_wlr_output_mode {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(c.struct_wlr_output_mode, "link"));
}

export fn get_nearest_output_mode(output: [*c]c.struct_wlr_output, width: i32, height: i32, refresh: f32) callconv(.c) [*c]c.struct_wlr_output_mode {
    if (output == null)
        return null;
    var nearest: [*c]c.struct_wlr_output_mode = null;
    var min_diff: f32 = 99999.0;

    const head: [*c]c.struct_wl_list = @ptrCast(&output.*.modes);
    var pos = output.*.modes.next;
    while (pos != head) : (pos = pos.*.next) {
        const mode = modeFromLink(pos);
        if (mode.width == width and mode.height == height) {
            const mode_refresh = @as(f32, @floatFromInt(mode.refresh)) / 1000.0;
            const diff = @abs(mode_refresh - refresh);
            if (diff < min_diff) {
                min_diff = diff;
                nearest = mode;
            }
        }
    }
    return nearest;
}

export fn enable_adaptive_sync(m: *Monitor, state: *OutputState) callconv(.c) void {
    c.wlr_output_state_set_adaptive_sync_enabled(state, true);
    if (!c.wlr_output_test_state(m.wlr_output, state)) {
        c.wlr_output_state_set_adaptive_sync_enabled(state, false);
    } else {
        m.is_vrr_enabling = true;
    }
}

export fn disable_adaptive_sync(m: *Monitor, state: *OutputState) callconv(.c) void {
    c.wlr_output_state_set_adaptive_sync_enabled(state, false);
    m.is_vrr_enabling = false;
}

export fn monitor_matches_rule(m: *Monitor, rule: *const c.ConfigMonitorRule) callconv(.c) bool {
    if (m.wlr_output == null)
        return false;
    const output = m.wlr_output;

    if (rule.name != null and regex_match(rule.name, output.*.name) == 0)
        return false;
    if (rule.make != null and !strEqZ(output.*.make, cString(rule.make).?))
        return false;
    if (rule.model != null and !strEqZ(output.*.model, cString(rule.model).?))
        return false;
    if (rule.serial != null and !strEqZ(output.*.serial, cString(rule.serial).?))
        return false;
    return true;
}

export fn monitor_load_icc_transform(path: [*c]const u8) callconv(.c) ?*c.struct_wlr_color_transform {
    if (path == null)
        return null;

    const fd = c.open(path, c.O_RDONLY | c.O_NOCTTY | c.O_CLOEXEC);
    if (fd == -1)
        return null;

    var info: c.struct_stat = undefined;
    if (c.fstat(fd, &info) == -1 or (info.st_mode & c.S_IFMT) != c.S_IFREG or info.st_size <= 0) {
        _ = c.close(fd);
        return null;
    }

    const size: usize = @intCast(info.st_size);
    const raw = c.malloc(size) orelse {
        _ = c.close(fd);
        return null;
    };
    const data = @as([*]u8, @ptrCast(raw));

    var nread: usize = 0;
    while (nread < size) {
        const r = c.read(fd, data + nread, size - nread);
        if (r <= 0) {
            c.free(raw);
            _ = c.close(fd);
            return null;
        }
        nread += @intCast(r);
    }
    _ = c.close(fd);

    const tr = c.wlr_color_transform_init_linear_to_icc(@ptrCast(data), size);
    c.free(raw);
    return tr;
}

export fn monitor_set_icc(m: *Monitor, path: [*c]const u8) callconv(.c) void {
    if (path == null or path[0] == 0) {
        c.wlr_color_transform_unref(m.icc_transform);
        m.icc_transform = null;
        m.icc_path[0] = 0;
        return;
    }
    if (m.icc_path[0] != 0 and strEqZ(&m.icc_path[0], cString(path).?))
        return;

    c.wlr_color_transform_unref(m.icc_transform);
    m.icc_transform = null;
    m.icc_path[0] = 0;

    const tr = monitor_load_icc_transform(path);
    if (tr == null)
        return;
    m.icc_transform = tr;
    const span = cString(path).?;
    const copy_len = @min(span.len, m.icc_path.len - 1);
    std.mem.copyForwards(u8, m.icc_path[0..copy_len], span[0..copy_len]);
    m.icc_path[copy_len] = 0;
}

export fn apply_rule_to_state(m: *Monitor, rule: *const c.ConfigMonitorRule, state: *OutputState) callconv(.c) bool {
    var mode_set = false;
    m.vrr_global_enable = if (rule.vrr >= 0) rule.vrr != 0 else false;
    m.hdr_enable = if (rule.hdr >= 0) rule.hdr != 0 else false;
    m.prefer_disable = if (rule.disable >= 0) rule.disable != 0 else false;
    m.hdr_min_lum = rule.hdr_min_lum;
    m.hdr_max_lum = rule.hdr_max_lum;
    m.hdr_max_avg_lum = rule.hdr_max_avg_lum;
    m.hdr_force = if (rule.hdr_force >= 0) rule.hdr_force != 0 else false;
    monitor_set_icc(m, rule.icc);

    if (rule.width > 0 and rule.height > 0 and rule.refresh > 0) {
        var internal_mode: [*c]c.struct_wlr_output_mode = null;
        if (rule.custom == 0)
            internal_mode = get_nearest_output_mode(m.wlr_output, rule.width, rule.height, rule.refresh);
        if (internal_mode != null) {
            c.wlr_output_state_set_mode(state, internal_mode);
            mode_set = true;
        } else if (rule.custom != 0 or wlr_output_is_headless(m.wlr_output)) {
            const refresh_mhz: i32 = @intFromFloat(@round(rule.refresh * 1000.0));
            c.wlr_output_state_set_custom_mode(state, rule.width, rule.height, refresh_mhz);
            mode_set = true;
        }
    }

    if (m.vrr_global_enable)
        enable_adaptive_sync(m, state)
    else
        disable_adaptive_sync(m, state);

    c.wlr_output_state_set_enabled(state, !m.prefer_disable);
    c.wlr_output_state_set_scale(state, rule.scale);
    c.wlr_output_state_set_transform(state, @intCast(rule.rr));
    return mode_set;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/monitor_output_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_tearing: bool;
extern var stub_tearing_calls: c_int;
extern var stub_needs_frame: bool;
extern var stub_needs_frame_calls: c_int;
extern var stub_build_ok: bool;
extern var stub_build_calls: c_int;
extern var stub_opts_color_transform: ?*c.struct_wlr_color_transform;
extern var stub_test_ok: bool;
extern var stub_test_calls: c_int;
extern var stub_commit_results: [4]bool;
extern var stub_commit_index: c_int;
extern var stub_commit_calls: c_int;
extern var stub_last_tearing_flip: bool;
extern var stub_finish_calls: c_int;
extern var stub_init_calls: c_int;
extern var stub_adaptive_calls: c_int;
extern var stub_adaptive_value: bool;
extern var stub_set_mode: ?*c.struct_wlr_output_mode;
extern var stub_set_mode_calls: c_int;
extern var stub_custom_mode_calls: c_int;
extern var stub_custom_w: i32;
extern var stub_custom_h: i32;
extern var stub_custom_refresh: i32;
extern var stub_enabled_calls: c_int;
extern var stub_enabled_value: bool;
extern var stub_scale_calls: c_int;
extern var stub_scale_value: f32;
extern var stub_transform_calls: c_int;
extern var stub_transform_value: c_int;
extern var stub_headless: bool;
extern var stub_icc_init_calls: c_int;
extern var stub_icc_size: usize;
extern var stub_icc_data: [64]u8;
extern var stub_transform_result: ?*c.struct_wlr_color_transform;
extern var stub_unref_calls: c_int;

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

fn resetOutputWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    stub_tearing = false;
    stub_tearing_calls = 0;
    stub_needs_frame = false;
    stub_needs_frame_calls = 0;
    stub_build_ok = true;
    stub_build_calls = 0;
    stub_opts_color_transform = null;
    stub_test_ok = true;
    stub_test_calls = 0;
    stub_commit_results = .{ true, true, true, true };
    stub_commit_index = 0;
    stub_commit_calls = 0;
    stub_last_tearing_flip = false;
    stub_finish_calls = 0;
    stub_init_calls = 0;
    stub_adaptive_calls = 0;
    stub_adaptive_value = false;
    stub_set_mode = null;
    stub_set_mode_calls = 0;
    stub_custom_mode_calls = 0;
    stub_custom_w = 0;
    stub_custom_h = 0;
    stub_custom_refresh = 0;
    stub_enabled_calls = 0;
    stub_enabled_value = true;
    stub_scale_calls = 0;
    stub_scale_value = 0;
    stub_transform_calls = 0;
    stub_transform_value = 0;
    stub_headless = false;
    stub_icc_init_calls = 0;
    stub_icc_size = 0;
    stub_icc_data = std.mem.zeroes([64]u8);
    stub_transform_result = null;
    stub_unref_calls = 0;
}

fn baseOutput(m: *Monitor, out: *c.struct_wlr_output, scene_out: *c.struct_wlr_scene_output) void {
    m.* = std.mem.zeroes(Monitor);
    out.* = std.mem.zeroes(c.struct_wlr_output);
    scene_out.* = std.mem.zeroes(c.struct_wlr_scene_output);
    out.data = m;
    m.wlr_output = out;
    out.enabled = true;
    out.name = @ptrCast(@constCast("DP-1"));
    listInit(&out.modes);
    scene_out.output = out;
}

fn makeMode(width: i32, height: i32, refresh: i32) c.struct_wlr_output_mode {
    var mode = std.mem.zeroes(c.struct_wlr_output_mode);
    mode.width = width;
    mode.height = height;
    mode.refresh = refresh;
    return mode;
}

test "scene output commit short-circuits without damage" {
    resetOutputWorld();
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    var scene_out: c.struct_wlr_scene_output = undefined;
    baseOutput(&m, &out, &scene_out);
    var state: c.struct_wlr_output_state = std.mem.zeroes(c.struct_wlr_output_state);

    try testing.expect(acwm_scene_output_commit(&scene_out, &state));
    try testing.expectEqual(@as(c_int, 0), stub_build_calls);
    try testing.expectEqual(@as(c_int, 0), stub_commit_calls);

    stub_needs_frame = true;
    try testing.expect(acwm_scene_output_commit(&scene_out, &state));
    try testing.expectEqual(@as(c_int, 1), stub_build_calls);
    try testing.expectEqual(@as(c_int, 1), stub_commit_calls);
}

test "scene output commit attaches ICC and reinitialises pending" {
    resetOutputWorld();
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    var scene_out: c.struct_wlr_scene_output = undefined;
    baseOutput(&m, &out, &scene_out);
    const transform: *c.struct_wlr_color_transform = @ptrFromInt(0x1000);
    m.icc_transform = transform;
    m.pending.committed = @intCast(c.WLR_OUTPUT_STATE_SCALE);

    try testing.expect(acwm_scene_output_commit(&scene_out, &m.pending));
    try testing.expectEqual(transform, stub_opts_color_transform);
    try testing.expectEqual(@as(c_int, 1), stub_finish_calls);
    try testing.expectEqual(@as(c_int, 1), stub_init_calls);
    try testing.expect(!stub_last_tearing_flip);

    out.image_description = @ptrFromInt(0x2000);
    var state2: c.struct_wlr_output_state = std.mem.zeroes(c.struct_wlr_output_state);
    state2.committed = @intCast(c.WLR_OUTPUT_STATE_SCALE);
    try testing.expect(acwm_scene_output_commit(&scene_out, &state2));
    try testing.expect(stub_opts_color_transform == null);
}

test "scene output commit negotiates and retries tearing" {
    resetOutputWorld();
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    var scene_out: c.struct_wlr_scene_output = undefined;
    baseOutput(&m, &out, &scene_out);
    stub_tearing = true;
    var state: c.struct_wlr_output_state = std.mem.zeroes(c.struct_wlr_output_state);
    state.committed = @intCast(c.WLR_OUTPUT_STATE_SCALE);

    try testing.expect(acwm_scene_output_commit(&scene_out, &state));
    try testing.expectEqual(@as(c_int, 1), stub_test_calls);
    try testing.expect(stub_last_tearing_flip);

    stub_commit_index = 0;
    stub_test_ok = false;
    var state2: c.struct_wlr_output_state = std.mem.zeroes(c.struct_wlr_output_state);
    state2.committed = @intCast(c.WLR_OUTPUT_STATE_SCALE);
    try testing.expect(acwm_scene_output_commit(&scene_out, &state2));
    try testing.expect(!stub_last_tearing_flip);

    stub_test_ok = true;
    stub_commit_index = 0;
    stub_commit_results[0] = false;
    stub_commit_results[1] = true;
    var state3: c.struct_wlr_output_state = std.mem.zeroes(c.struct_wlr_output_state);
    state3.committed = @intCast(c.WLR_OUTPUT_STATE_SCALE);
    const before = stub_commit_calls;
    try testing.expect(acwm_scene_output_commit(&scene_out, &state3));
    try testing.expectEqual(before + 2, stub_commit_calls);
    try testing.expect(!state3.tearing_page_flip);
}

test "scene output commit failure skips resetting pending" {
    resetOutputWorld();
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    var scene_out: c.struct_wlr_scene_output = undefined;
    baseOutput(&m, &out, &scene_out);
    stub_commit_results[0] = false;
    var state: c.struct_wlr_output_state = std.mem.zeroes(c.struct_wlr_output_state);
    state.committed = @intCast(c.WLR_OUTPUT_STATE_SCALE);
    try testing.expect(!acwm_scene_output_commit(&scene_out, &state));
    try testing.expectEqual(@as(c_int, 0), stub_finish_calls);
}

test "direct output commit resets state on success only" {
    resetOutputWorld();
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    var scene_out: c.struct_wlr_scene_output = undefined;
    baseOutput(&m, &out, &scene_out);
    try testing.expect(acwm_output_commit(&m));
    try testing.expectEqual(@as(c_int, 1), stub_finish_calls);
    try testing.expectEqual(@as(c_int, 1), stub_init_calls);

    stub_commit_index = 0;
    stub_commit_results[0] = false;
    try testing.expect(!acwm_output_commit(&m));
    try testing.expectEqual(@as(c_int, 1), stub_finish_calls);
}

test "nearest output mode matches size and refresh" {
    resetOutputWorld();
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    var scene_out: c.struct_wlr_scene_output = undefined;
    baseOutput(&m, &out, &scene_out);

    var a = makeMode(1920, 1080, 60000);
    var b = makeMode(1920, 1080, 59940);
    var c_mode = makeMode(1280, 720, 60000);
    listInsert(&out.modes, &a.link);
    listInsert(&out.modes, &b.link);
    listInsert(&out.modes, &c_mode.link);

    const nearest = get_nearest_output_mode(&out, 1920, 1080, 59.95);
    try testing.expect(nearest == &b);
    try testing.expect(get_nearest_output_mode(&out, 1920, 1080, 144.0) == &a);
    try testing.expect(get_nearest_output_mode(&out, 800, 600, 60.0) == null);
    try testing.expect(get_nearest_output_mode(null, 1920, 1080, 60.0) == null);
}

test "adaptive sync toggles flags after testing" {
    resetOutputWorld();
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    var scene_out: c.struct_wlr_scene_output = undefined;
    baseOutput(&m, &out, &scene_out);
    var state: c.struct_wlr_output_state = std.mem.zeroes(c.struct_wlr_output_state);

    enable_adaptive_sync(&m, &state);
    try testing.expect(stub_adaptive_value);
    try testing.expect(m.is_vrr_enabling);

    stub_test_ok = false;
    m.is_vrr_enabling = false;
    enable_adaptive_sync(&m, &state);
    try testing.expect(!stub_adaptive_value);
    try testing.expect(!m.is_vrr_enabling);

    disable_adaptive_sync(&m, &state);
    try testing.expect(!stub_adaptive_value);
    try testing.expect(!m.is_vrr_enabling);
}

test "monitor rules match name, make, model and serial" {
    resetOutputWorld();
    var m: Monitor = std.mem.zeroes(Monitor);
    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    out.name = @ptrCast(@constCast("DP-1"));
    out.make = @ptrCast(@constCast("Acme"));
    out.model = @ptrCast(@constCast("Panel"));
    out.serial = @ptrCast(@constCast("1234"));
    m.wlr_output = &out;
    var rule: c.ConfigMonitorRule = std.mem.zeroes(c.ConfigMonitorRule);
    try testing.expect(monitor_matches_rule(&m, &rule));

    rule.name = @ptrCast(@constCast("DP-1"));
    try testing.expect(monitor_matches_rule(&m, &rule));
    rule.name = @ptrCast(@constCast("HDMI-1"));
    try testing.expect(!monitor_matches_rule(&m, &rule));
    rule.name = null;
    rule.make = @ptrCast(@constCast("Acme"));
    try testing.expect(monitor_matches_rule(&m, &rule));
    rule.make = @ptrCast(@constCast("Other"));
    try testing.expect(!monitor_matches_rule(&m, &rule));
    rule.make = null;
    rule.model = @ptrCast(@constCast("Panel"));
    try testing.expect(monitor_matches_rule(&m, &rule));
    rule.model = @ptrCast(@constCast("Other"));
    try testing.expect(!monitor_matches_rule(&m, &rule));
    rule.model = null;
    rule.serial = @ptrCast(@constCast("1234"));
    try testing.expect(monitor_matches_rule(&m, &rule));
    rule.serial = @ptrCast(@constCast("9999"));
    try testing.expect(!monitor_matches_rule(&m, &rule));
    out.make = null;
    rule.make = @ptrCast(@constCast("Acme"));
    try testing.expect(!monitor_matches_rule(&m, &rule));
}

test "ICC loading validates files and caches the path" {
    resetOutputWorld();
    const path = "/tmp/opencode/acwm_icc54.icc";
    const fd = c.open(path, c.O_WRONLY | c.O_CREAT | c.O_TRUNC, @as(c_uint, 0o644));
    try testing.expect(fd >= 0);
    const payload = "ICC!";
    _ = c.write(fd, payload.ptr, payload.len);
    _ = c.close(fd);

    const fake: *c.struct_wlr_color_transform = @ptrFromInt(0x1000);
    stub_transform_result = fake;
    const tr = monitor_load_icc_transform(@ptrCast(path));
    try testing.expect(tr == fake);
    try testing.expectEqual(@as(usize, 4), stub_icc_size);
    try testing.expectEqualStrings("ICC!", stub_icc_data[0..4]);

    try testing.expect(monitor_load_icc_transform(@ptrCast("/tmp/opencode/no-such-icc")) == null);
    try testing.expect(monitor_load_icc_transform(@ptrCast("/tmp/opencode")) == null);

    const empty_path = "/tmp/opencode/acwm_icc54_empty.icc";
    const efd = c.open(empty_path, c.O_WRONLY | c.O_CREAT | c.O_TRUNC, @as(c_uint, 0o644));
    try testing.expect(efd >= 0);
    _ = c.close(efd);
    try testing.expect(monitor_load_icc_transform(@ptrCast(empty_path)) == null);

    var m: Monitor = std.mem.zeroes(Monitor);
    monitor_set_icc(&m, @ptrCast(path));
    try testing.expect(m.icc_transform == fake);
    try testing.expectEqualStrings(path, std.mem.sliceTo(&m.icc_path, 0));
    const unref_before = stub_unref_calls;
    monitor_set_icc(&m, @ptrCast(path));
    try testing.expectEqual(unref_before, stub_unref_calls);
    monitor_set_icc(&m, null);
    try testing.expect(m.icc_transform == null);
    try testing.expectEqual(@as(u8, 0), m.icc_path[0]);
    try testing.expectEqual(unref_before + 1, stub_unref_calls);

    monitor_set_icc(&m, @ptrCast(path));
    monitor_set_icc(&m, @ptrCast("/tmp/opencode/no-such-icc"));
    try testing.expect(m.icc_transform == null);
    try testing.expectEqual(@as(u8, 0), m.icc_path[0]);
}

test "monitor rule application sets mode, VRR, HDR and scale" {
    resetOutputWorld();
    var m: Monitor = undefined;
    var out: c.struct_wlr_output = undefined;
    var scene_out: c.struct_wlr_scene_output = undefined;
    baseOutput(&m, &out, &scene_out);
    var mode = makeMode(1920, 1080, 60000);
    listInsert(&out.modes, &mode.link);
    var state: c.struct_wlr_output_state = std.mem.zeroes(c.struct_wlr_output_state);
    var rule: c.ConfigMonitorRule = std.mem.zeroes(c.ConfigMonitorRule);
    rule.vrr = 1;
    rule.hdr = 1;
    rule.disable = 1;
    rule.hdr_min_lum = 0.1;
    rule.hdr_max_lum = 1000;
    rule.hdr_max_avg_lum = 400;
    rule.hdr_force = 1;
    rule.width = 1920;
    rule.height = 1080;
    rule.refresh = 60.0;
    rule.scale = 1.5;
    rule.rr = 3;

    try testing.expect(apply_rule_to_state(&m, &rule, &state));
    try testing.expect(stub_set_mode == &mode);
    try testing.expect(m.vrr_global_enable);
    try testing.expect(m.hdr_enable);
    try testing.expect(m.prefer_disable);
    try testing.expect(m.hdr_force);
    try testing.expectApproxEqAbs(@as(f32, 0.1), m.hdr_min_lum, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 1000), m.hdr_max_lum, 1e-6);
    try testing.expect(stub_adaptive_value);
    try testing.expect(!stub_enabled_value);
    try testing.expectApproxEqAbs(@as(f32, 1.5), stub_scale_value, 1e-6);
    try testing.expectEqual(@as(c_int, 3), stub_transform_value);

    rule.custom = 1;
    rule.width = 800;
    rule.height = 600;
    rule.refresh = 59.94;
    try testing.expect(apply_rule_to_state(&m, &rule, &state));
    try testing.expectEqual(@as(i32, 800), stub_custom_w);
    try testing.expectEqual(@as(i32, 59940), stub_custom_refresh);

    stub_headless = true;
    rule.custom = 0;
    try testing.expect(apply_rule_to_state(&m, &rule, &state));

    rule.vrr = -1;
    rule.hdr = -1;
    rule.disable = -1;
    rule.hdr_force = -1;
    rule.width = 0;
    try testing.expect(!apply_rule_to_state(&m, &rule, &state));
    try testing.expect(!m.vrr_global_enable);
    try testing.expect(!m.hdr_enable);
    try testing.expect(!m.prefer_disable);
    try testing.expect(!m.hdr_force);
}
