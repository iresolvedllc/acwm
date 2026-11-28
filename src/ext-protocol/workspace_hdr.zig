//! Port of ext-protocol/ext-workspace.c and hdr.c
//! (Phase 5, ext-protocol slice 2, slice 76).

const std = @import("std");
const c = @import("cc");

const Monitor = c.Monitor;
const Workspace = c.struct_workspace;
const State = c.struct_wlr_output_state;

extern fn client_switch_view(arg: [*c]const c.Arg, animate: bool) callconv(.c) i32;
extern fn toggle_view(arg: [*c]const c.Arg) callconv(.c) i32;
extern fn toggle_overview(arg: [*c]const c.Arg) callconv(.c) i32;
extern fn get_tag_status(tag: u32, m: [*c]Monitor) callconv(.c) u32;
extern fn get_monitor_active_tagset(m: [*c]Monitor) callconv(.c) u32;
extern fn wlr_ext_workspace_manager_v1_create(display: [*c]c.struct_wl_display, version: u32) callconv(.c) [*c]c.struct_wlr_ext_workspace_manager_v1;
extern fn wlr_ext_workspace_handle_v1_create(manager: [*c]c.struct_wlr_ext_workspace_manager_v1, name: [*c]const u8, caps: u32) callconv(.c) [*c]c.struct_wlr_ext_workspace_handle_v1;
extern fn wlr_ext_workspace_handle_v1_destroy(handle: [*c]c.struct_wlr_ext_workspace_handle_v1) callconv(.c) void;
extern fn wlr_ext_workspace_handle_v1_set_group(handle: [*c]c.struct_wlr_ext_workspace_handle_v1, group: [*c]c.struct_wlr_ext_workspace_group_handle_v1) callconv(.c) void;
extern fn wlr_ext_workspace_handle_v1_set_name(handle: [*c]c.struct_wlr_ext_workspace_handle_v1, name: [*c]const u8) callconv(.c) void;
extern fn wlr_ext_workspace_handle_v1_set_hidden(handle: [*c]c.struct_wlr_ext_workspace_handle_v1, hidden: bool) callconv(.c) void;
extern fn wlr_ext_workspace_handle_v1_set_urgent(handle: [*c]c.struct_wlr_ext_workspace_handle_v1, urgent: bool) callconv(.c) void;
extern fn wlr_ext_workspace_handle_v1_set_active(handle: [*c]c.struct_wlr_ext_workspace_handle_v1, active: bool) callconv(.c) void;
extern fn wlr_output_state_set_render_format(state: *State, format: u32) callconv(.c) void;
extern fn wlr_output_test_state(output: [*c]c.struct_wlr_output, state: *State) callconv(.c) bool;
extern fn wlr_output_state_set_image_description(state: *State, desc: ?*const c.struct_wlr_output_image_description) callconv(.c) void;
extern fn wlr_output_schedule_frame(output: [*c]c.struct_wlr_output) callconv(.c) void;
extern fn wlr_output_effective_resolution(output: [*c]c.struct_wlr_output, width: *c_int, height: *c_int) callconv(.c) void;
extern fn wlr_output_state_finish(state: *State) callconv(.c) void;
extern fn wlr_output_state_init(state: *State) callconv(.c) void;
extern fn wlr_damage_ring_add_whole(ring: *c.struct_wlr_damage_ring) callconv(.c) void;
extern fn wlr_color_primaries_from_named(primaries: *c.struct_wlr_color_primaries, named: c.enum_wlr_color_named_primaries) callconv(.c) void;
extern fn acwm_scene_output_commit(scene_output: [*c]c.struct_wlr_scene_output, state: *State) callconv(.c) bool;

const formats_8bit = [_]u32{
    c.DRM_FORMAT_XRGB8888, c.DRM_FORMAT_XBGR8888, c.DRM_FORMAT_RGBX8888,
    c.DRM_FORMAT_BGRX8888, c.DRM_FORMAT_ARGB8888, c.DRM_FORMAT_ABGR8888,
    c.DRM_FORMAT_RGBA8888, c.DRM_FORMAT_BGRA8888, c.DRM_FORMAT_RGB888,
    c.DRM_FORMAT_BGR888,
};
const formats_10bit = [_]u32{
    c.DRM_FORMAT_XRGB2101010, c.DRM_FORMAT_XBGR2101010, c.DRM_FORMAT_RGBX1010102,
    c.DRM_FORMAT_BGRX1010102, c.DRM_FORMAT_ARGB2101010, c.DRM_FORMAT_ABGR2101010,
    c.DRM_FORMAT_RGBA1010102, c.DRM_FORMAT_BGRA1010102,
};

var workspaces: c.struct_wl_list = std.mem.zeroes(c.struct_wl_list);

fn listInit(head: *c.struct_wl_list) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

fn workspaceFromLink(link: [*c]c.struct_wl_list) *Workspace {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(Workspace, "link"));
}

export fn get_name_from_tag(tag: u32) callconv(.c) [*c]const u8 {
    if (tag == 0)
        return "overview";
    if (tag <= @as(u32, @intCast(c.config.tag_num)))
        return c.tags[tag - 1];
    return null;
}

export fn goto_workspace(target: [*c]Workspace) callconv(.c) void {
    if (target.*.tag == 0) {
        var arg = std.mem.zeroes(c.Arg);
        _ = toggle_overview(&arg);
        return;
    }
    var arg = std.mem.zeroes(c.Arg);
    arg.ui = @as(u32, 1) << @intCast(target.*.tag - 1);
    _ = client_switch_view(&arg, true);
}

export fn toggle_workspace(target: [*c]Workspace) callconv(.c) void {
    if (target.*.tag == 0) {
        var arg = std.mem.zeroes(c.Arg);
        arg.i = -1;
        _ = toggle_view(&arg);
        return;
    }
    var arg = std.mem.zeroes(c.Arg);
    arg.ui = @as(u32, 1) << @intCast(target.*.tag - 1);
    _ = toggle_view(&arg);
}

export fn remove_workspace_by_tag(tag: u32, m: [*c]Monitor) callconv(.c) void {
    const head: [*c]c.struct_wl_list = @ptrCast(&workspaces);
    var pos = workspaces.next;
    while (pos != head) {
        const next = pos.*.next;
        const w = workspaceFromLink(pos);
        if (w.tag == tag and w.m == m) {
            destroy_workspace(w);
            return;
        }
        pos = next;
    }
}

export fn destroy_workspace(workspace: [*c]Workspace) callconv(.c) void {
    c.wlr_ext_workspace_handle_v1_destroy(workspace.*.ext_workspace);
    c.wl_list_remove(&workspace.*.link);
    c.free(workspace);
}

export fn cleanup_workspaces_by_monitor(m: [*c]Monitor) callconv(.c) void {
    const head: [*c]c.struct_wl_list = @ptrCast(&workspaces);
    var pos = workspaces.next;
    while (pos != head) {
        const next = pos.*.next;
        const w = workspaceFromLink(pos);
        if (w.m == m)
            destroy_workspace(w);
        pos = next;
    }
}

export fn add_workspace_by_tag(tag: i32, m: [*c]Monitor) callconv(.c) void {
    const name = get_name_from_tag(@intCast(tag));
    const raw = c.ecalloc(1, @sizeOf(Workspace)) orelse return;
    const w = @as(*Workspace, @ptrCast(@alignCast(raw)));
    c.wl_list_append(&workspaces, &w.link);
    w.tag = @intCast(tag);
    w.m = m;
    w.ext_workspace = c.wlr_ext_workspace_handle_v1_create(c.server.ext_workspace_manager, name, c.EXT_WORKSPACE_HANDLE_V1_WORKSPACE_CAPABILITIES_ACTIVATE | c.EXT_WORKSPACE_HANDLE_V1_WORKSPACE_CAPABILITIES_DEACTIVATE);
    w.ext_workspace.*.data = w;
    c.wlr_ext_workspace_handle_v1_set_group(w.ext_workspace, m.*.ext_group);
    c.wlr_ext_workspace_handle_v1_set_name(w.ext_workspace, name);
}

export fn refresh_monitors_workspaces_status(m: [*c]Monitor) callconv(.c) void {
    if (m == null or m.*.wlr_output == null or !m.*.wlr_output.*.enabled or m.*.iscleanuping)
        return;
    if (m.*.isoverview != 0) {
        add_workspace_by_tag(0, m);
        var i: i32 = 1;
        while (i <= c.config.tag_num) : (i += 1)
            remove_workspace_by_tag(@intCast(i), m);
    } else {
        remove_workspace_by_tag(0, m);
        var i: i32 = 1;
        while (i <= c.config.tag_num) : (i += 1)
            add_workspace_by_tag(i, m);
    }
    acwm_ext_workspace_printstatus(m);
}

export fn workspaces_init() callconv(.c) void {
    c.server.ext_workspace_manager = c.wlr_ext_workspace_manager_v1_create(c.server.display, 1);
    listInit(&workspaces);
    c.wl_signal_add(&c.server.ext_workspace_manager.*.events.commit, &c.server.ext_workspace_commit_listener);
}

export fn handle_ext_commit(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event = @as(*c.struct_wlr_ext_workspace_v1_commit_event, @ptrCast(@alignCast(data.?)));
    const head: [*c]c.struct_wl_list = @ptrCast(event.*.requests);
    var pos = event.*.requests.*.next;
    while (pos != head) : (pos = pos.*.next) {
        const request = @as([*c]c.struct_wlr_ext_workspace_v1_request, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.struct_wlr_ext_workspace_v1_request, "link")));
        switch (request.*.type) {
            c.WLR_EXT_WORKSPACE_V1_REQUEST_ACTIVATE => {
                if (request.*.unnamed_0.activate.workspace == null) continue;
                var workspace: [*c]Workspace = null;
                const whead: [*c]c.struct_wl_list = @ptrCast(&workspaces);
                var wpos = workspaces.next;
                while (wpos != whead) : (wpos = wpos.*.next) {
                    const w = workspaceFromLink(wpos);
                    if (w.ext_workspace == request.*.unnamed_0.activate.workspace) {
                        workspace = w;
                        break;
                    }
                }
                if (workspace == null or workspace.*.m.*.isoverview != 0) continue;
                goto_workspace(workspace);
                c.acwm_error_impl(true, c.WLR_INFO, "src/ext-protocol/ext-workspace.c", 187, "ext activating workspace %d", workspace.*.tag);
            },
            c.WLR_EXT_WORKSPACE_V1_REQUEST_DEACTIVATE => {
                if (request.*.unnamed_0.deactivate.workspace == null) continue;
                var workspace: [*c]Workspace = null;
                const whead: [*c]c.struct_wl_list = @ptrCast(&workspaces);
                var wpos = workspaces.next;
                while (wpos != whead) : (wpos = wpos.*.next) {
                    const w = workspaceFromLink(wpos);
                    if (w.ext_workspace == request.*.unnamed_0.deactivate.workspace) {
                        workspace = w;
                        break;
                    }
                }
                if (workspace == null or workspace.*.m.*.isoverview != 0) continue;
                toggle_workspace(workspace);
                c.acwm_error_impl(true, c.WLR_INFO, "src/ext-protocol/ext-workspace.c", 209, "ext deactivating workspace %d", workspace.*.tag);
            },
            else => {},
        }
    }
}

export fn acwm_ext_workspace_printstatus(m: [*c]Monitor) callconv(.c) void {
    const head: [*c]c.struct_wl_list = @ptrCast(&workspaces);
    var pos = workspaces.next;
    while (pos != head) : (pos = pos.*.next) {
        const w = workspaceFromLink(pos);
        if (w.m != m) continue;
        const tag_status = get_tag_status(w.tag, m);
        if (tag_status == 2) {
            c.wlr_ext_workspace_handle_v1_set_hidden(w.ext_workspace, false);
            c.wlr_ext_workspace_handle_v1_set_urgent(w.ext_workspace, true);
        } else if (tag_status == 1) {
            c.wlr_ext_workspace_handle_v1_set_urgent(w.ext_workspace, false);
            c.wlr_ext_workspace_handle_v1_set_hidden(w.ext_workspace, false);
        } else {
            c.wlr_ext_workspace_handle_v1_set_urgent(w.ext_workspace, false);
            if (m.*.pertag.*.no_hide[w.tag] == 0)
                c.wlr_ext_workspace_handle_v1_set_hidden(w.ext_workspace, true)
            else
                c.wlr_ext_workspace_handle_v1_set_hidden(w.ext_workspace, false);
        }
        const active_tagset = get_monitor_active_tagset(m);
        const tag_active = w.tag > 0 and
            (active_tagset & (@as(u32, 1) << @intCast(w.tag - 1)) & c.server.tagmask) != 0;
        if (tag_active or m.*.isoverview != 0) {
            c.wlr_ext_workspace_handle_v1_set_hidden(w.ext_workspace, false);
            c.wlr_ext_workspace_handle_v1_set_active(w.ext_workspace, true);
        } else {
            c.wlr_ext_workspace_handle_v1_set_active(w.ext_workspace, false);
        }
    }
}

export fn sync_workspaces_to_tag_num(m: [*c]Monitor) callconv(.c) void {
    if (m == null or m.*.wlr_output == null or !m.*.wlr_output.*.enabled or m.*.iscleanuping)
        return;
    if (m.*.isoverview != 0) {
        var has_overview = false;
        const head: [*c]c.struct_wl_list = @ptrCast(&workspaces);
        var pos = workspaces.next;
        while (pos != head) {
            const next = pos.*.next;
            const w = workspaceFromLink(pos);
            if (w.m == m) {
                if (w.tag == 0) has_overview = true else destroy_workspace(w);
            }
            pos = next;
        }
        if (!has_overview)
            add_workspace_by_tag(0, m);
    } else {
        const head: [*c]c.struct_wl_list = @ptrCast(&workspaces);
        var pos = workspaces.next;
        while (pos != head) {
            const next = pos.*.next;
            const w = workspaceFromLink(pos);
            if (w.m == m and w.tag > @as(u32, @intCast(c.config.tag_num)))
                destroy_workspace(w);
            pos = next;
        }
        var i: i32 = 1;
        while (i <= c.config.tag_num) : (i += 1) {
            var exists = false;
            var wpos = workspaces.next;
            while (wpos != head) : (wpos = wpos.*.next) {
                const w = workspaceFromLink(wpos);
                if (w.m == m and w.tag == @as(u32, @intCast(i))) {
                    exists = true;
                    break;
                }
            }
            if (!exists) add_workspace_by_tag(i, m);
        }
    }
    acwm_ext_workspace_printstatus(m);
}

// ---------------------------------------------------------------------------
// HDR
// ---------------------------------------------------------------------------

export fn output_format_in_candidates(format: u32, candidates: [*c]u32, count: usize) callconv(.c) bool {
    var i: usize = 0;
    while (i < count) : (i += 1)
        if (candidates[i] == format)
            return true;
    return false;
}

export fn bit_depth_from_format(render_format: u32) callconv(.c) c.enum_render_bit_depth {
    if (output_format_in_candidates(render_format, @constCast(&formats_10bit), formats_10bit.len))
        return c.ACWM_RENDER_BIT_DEPTH_10;
    if (output_format_in_candidates(render_format, @constCast(&formats_8bit), formats_8bit.len))
        return c.ACWM_RENDER_BIT_DEPTH_8;
    return c.ACWM_RENDER_BIT_DEPTH_DEFAULT;
}

export fn output_set_render_format(m: [*c]Monitor, candidates: [*c]u32, count: usize, state: *State) callconv(.c) bool {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        var test_state = state.*;
        c.wlr_output_state_set_render_format(&test_state, candidates[i]);
        if (c.wlr_output_test_state(m.*.wlr_output, &test_state)) {
            c.wlr_output_state_set_render_format(state, candidates[i]);
            return true;
        }
    }
    c.acwm_error_impl(true, c.WLR_DEBUG, "src/ext-protocol/hdr.c", 31, "HDR: Failed to set render format");
    return false;
}

export fn output_supports_hdr(m: [*c]const Monitor, reason: [*c]?[*:0]const u8) callconv(.c) bool {
    const output = m.*.wlr_output;
    var r: ?[*:0]const u8 = null;
    if (!m.*.hdr_force and
        (output.*.supported_primaries & c.WLR_COLOR_NAMED_PRIMARIES_BT2020) == 0)
        r = "BT2020 primaries not supported"
    else if (!m.*.hdr_force and
        (output.*.supported_transfer_functions & c.WLR_COLOR_TRANSFER_FUNCTION_ST2084_PQ) == 0)
        r = "PQ transfer function not supported"
    else if (!c.server.renderer.*.features.output_color_transform)
        r = "renderer doesn't support output color transforms";
    if (reason != null) reason.* = r;
    return r == null;
}

export fn output_enable_hdr(m: [*c]Monitor, os: *State, enabled: bool, silent: bool) callconv(.c) void {
    if (!m.*.is_hdr_enabling and !enabled)
        return;
    if (!output_supports_hdr(m, null)) {
        m.*.is_hdr_enabling = false;
        return;
    }
    if (!enabled) {
        if (m.*.wlr_output.*.supported_primaries != 0 or m.*.wlr_output.*.supported_transfer_functions != 0) {
            if (!silent)
                c.acwm_error_impl(true, c.WLR_DEBUG, "src/ext-protocol/hdr.c", 80, "Disabling HDR on output %s", m.*.wlr_output.*.name);
            _ = c.wlr_output_state_set_image_description(os, null);
        }
        m.*.is_hdr_enabling = false;
        return;
    }
    if (!silent)
        c.acwm_error_impl(true, c.WLR_DEBUG, "src/ext-protocol/hdr.c", 89, "Enabling HDR on output %s", m.*.wlr_output.*.name);
    var desc = std.mem.zeroes(c.struct_wlr_output_image_description);
    desc.primaries = c.WLR_COLOR_NAMED_PRIMARIES_BT2020;
    desc.transfer_function = c.WLR_COLOR_TRANSFER_FUNCTION_ST2084_PQ;
    if (m.*.hdr_max_lum > 0) {
        c.wlr_color_primaries_from_named(&desc.mastering_display_primaries, c.WLR_COLOR_NAMED_PRIMARIES_BT2020);
        desc.mastering_luminance.min = m.*.hdr_min_lum;
        desc.mastering_luminance.max = m.*.hdr_max_lum;
        desc.max_cll = m.*.hdr_max_lum;
        desc.max_fall = m.*.hdr_max_avg_lum;
    }
    m.*.is_hdr_enabling = true;
    _ = c.wlr_output_state_set_image_description(os, &desc);
}

export fn output_state_setup_hdr(m: [*c]Monitor, silent: bool, state: *State) callconv(.c) void {
    const render_format = m.*.wlr_output.*.render_format;
    var unsupported_reason: ?[*:0]const u8 = null;
    const hdr_supported = output_supports_hdr(m, &unsupported_reason);
    var hdr_succeeded = false;
    if (!hdr_supported) {
        if (!silent)
            c.acwm_error_impl(true, c.WLR_INFO, "src/ext-protocol/hdr.c", 116, "HDR not supported on output %s: %s", m.*.wlr_output.*.name, unsupported_reason);
        return;
    }
    var depth = c.config.hdr_depth;
    if (depth == c.ACWM_RENDER_BIT_DEPTH_DEFAULT)
        depth = @intCast(bit_depth_from_format(render_format));
    if (depth == c.ACWM_RENDER_BIT_DEPTH_10 and bit_depth_from_format(render_format) == depth) {
        hdr_succeeded = true;
    } else if (depth == c.ACWM_RENDER_BIT_DEPTH_10) {
        hdr_succeeded = output_set_render_format(m, @constCast(&formats_10bit), formats_10bit.len, state);
        if (!hdr_succeeded) {
            if (!silent)
                c.acwm_error_impl(true, c.WLR_INFO, "src/ext-protocol/hdr.c", 130, "No 10 bit color formats supported, HDR disabled.");
            hdr_succeeded = output_set_render_format(m, @constCast(&formats_8bit), formats_8bit.len, state);
            if (!hdr_succeeded and !silent)
                c.acwm_error_impl(true, c.WLR_ERROR, "src/ext-protocol/hdr.c", 135, "No 8 bit color formats supported!");
        }
    } else {
        hdr_succeeded = output_set_render_format(m, @constCast(&formats_8bit), formats_8bit.len, state);
        if (!hdr_succeeded and !silent)
            c.acwm_error_impl(true, c.WLR_ERROR, "src/ext-protocol/hdr.c", 143, "No 8 bit color formats supported!");
    }
    output_enable_hdr(m, state, hdr_succeeded, silent);
}

export fn togglehdr_output(target: [*c]Monitor, want: bool) callconv(.c) bool {
    if (target == null or target.*.wlr_output == null or !target.*.wlr_output.*.enabled or target.*.scene_output == null)
        return false;
    if (want == target.*.hdr_enable)
        return false;
    var reason: ?[*:0]const u8 = null;
    if (want and !output_supports_hdr(target, &reason)) {
        c.acwm_error_impl(true, c.WLR_INFO, "src/ext-protocol/hdr.c", 197, "togglehdr: HDR unavailable on %s: %s", target.*.wlr_output.*.name, if (reason) |r| r else @as([*:0]const u8, "unknown"));
        return false;
    }
    const prev_enable = target.*.hdr_enable;
    const prev_enabling = target.*.is_hdr_enabling;
    target.*.hdr_enable = want;
    if (want)
        output_state_setup_hdr(target, false, &target.*.pending)
    else
        output_enable_hdr(target, &target.*.pending, false, false);
    c.wlr_output_schedule_frame(target.*.wlr_output);
    c.wlr_damage_ring_add_whole(&target.*.scene_output.*.damage_ring);
    target.*.pending.allow_reconfiguration = true;
    if (!c.acwm_scene_output_commit(target.*.scene_output, &target.*.pending)) {
        c.acwm_error_impl(true, c.WLR_ERROR, "src/ext-protocol/hdr.c", 225, "togglehdr: commit failed on %s, reverting", target.*.wlr_output.*.name);
        target.*.hdr_enable = prev_enable;
        target.*.is_hdr_enabling = prev_enabling;
        c.wlr_output_state_finish(&target.*.pending);
        c.wlr_output_state_init(&target.*.pending);
        return false;
    }
    var w: c_int = 0;
    var h: c_int = 0;
    c.wlr_output_effective_resolution(target.*.wlr_output, &w, &h);
    target.*.m.width = w;
    target.*.m.height = h;
    return true;
}

export fn toggle_hdr(arg: [*c]const c.Arg) callconv(.c) i32 {
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.monitors);
    if (arg.*.v != null and c.strcmp(arg.*.v, "all") == 0) {
        var want = false;
        if (arg.*.i < 0) {
            var pos = c.server.monitors.next;
            while (pos != head) : (pos = pos.*.next) {
                const m = @as([*c]Monitor, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Monitor, "link")));
                if (m.*.wlr_output.*.enabled and m.*.hdr_enable) {
                    want = true;
                    break;
                }
            }
            want = !want;
        } else {
            want = arg.*.i != 0;
        }
        var pos = c.server.monitors.next;
        while (pos != head) : (pos = pos.*.next) {
            const m = @as([*c]Monitor, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Monitor, "link")));
            _ = togglehdr_output(m, want);
        }
        return 0;
    }
    var target: [*c]Monitor = null;
    if (arg.*.v != null and arg.*.v.* != 0) {
        var pos = c.server.monitors.next;
        while (pos != head) : (pos = pos.*.next) {
            const m = @as([*c]Monitor, @ptrFromInt(@intFromPtr(pos) - @offsetOf(c.Monitor, "link")));
            if (m.*.wlr_output.*.enabled and c.strcmp(m.*.wlr_output.*.name, arg.*.v) == 0) {
                target = m;
                break;
            }
        }
        if (target == null) {
            c.acwm_error_impl(true, c.WLR_ERROR, "src/ext-protocol/hdr.c", 259, "togglehdr: no enabled output named %s", arg.*.v);
            return 0;
        }
    } else {
        target = c.server.selected_monitor;
    }
    if (target == null)
        return 0;
    _ = togglehdr_output(target, if (arg.*.i < 0) !target.*.hdr_enable else arg.*.i != 0);
    return 0;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/workspace_hdr_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_switch_calls: c_int;
extern var stub_switch_tags: u32;
extern var stub_toggle_view_calls: c_int;
extern var stub_toggle_view_tags: u32;
extern var stub_toggle_view_i: i32;
extern var stub_overview_calls: c_int;
extern var stub_tag_status: u32;
extern var stub_active_tagset: u32;
extern var stub_handle_create_calls: c_int;
extern var stub_handle_destroy_calls: c_int;
extern var stub_group_calls: c_int;
extern var stub_name_calls: c_int;
extern var stub_hidden_calls: c_int;
extern var stub_urgent_calls: c_int;
extern var stub_active_calls: c_int;
extern var stub_last_hidden: c_int;
extern var stub_last_urgent: c_int;
extern var stub_last_active: c_int;
extern var stub_manager: c.struct_wlr_ext_workspace_manager_v1;
extern var stub_render_format_calls: c_int;
extern var stub_test_state: bool;
extern var stub_image_desc_calls: c_int;
extern var stub_image_desc_null: c_int;
extern var stub_last_desc: c.struct_wlr_output_image_description;
extern var stub_schedule_calls: c_int;
extern var stub_state_finish_calls: c_int;
extern var stub_state_init_calls: c_int;
extern var stub_damage_calls: c_int;
extern var stub_commit_ok: bool;
extern var stub_commit_calls: c_int;
extern var stub_error_calls: c_int;

fn listInitL(head: *c.struct_wl_list) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

fn resetWorkspaceWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    listInit(&c.server.monitors);
    listInit(&workspaces);
    c.config.tag_num = 3;
    stub_switch_calls = 0;
    stub_switch_tags = 0;
    stub_toggle_view_calls = 0;
    stub_toggle_view_tags = 0;
    stub_toggle_view_i = 0;
    stub_overview_calls = 0;
    stub_tag_status = 0;
    stub_active_tagset = 0;
    stub_handle_create_calls = 0;
    stub_handle_destroy_calls = 0;
    stub_group_calls = 0;
    stub_name_calls = 0;
    stub_hidden_calls = 0;
    stub_urgent_calls = 0;
    stub_active_calls = 0;
    stub_last_hidden = -1;
    stub_last_urgent = -1;
    stub_last_active = -1;
    stub_manager = std.mem.zeroes(c.struct_wlr_ext_workspace_manager_v1);
    listInit(&stub_manager.events.commit.listener_list);
    stub_render_format_calls = 0;
    stub_test_state = true;
    stub_image_desc_calls = 0;
    stub_image_desc_null = 0;
    stub_schedule_calls = 0;
    stub_state_finish_calls = 0;
    stub_state_init_calls = 0;
    stub_damage_calls = 0;
    stub_commit_ok = true;
    stub_commit_calls = 0;
    stub_error_calls = 0;
}

fn findWorkspace(tag: u32, m: [*c]Monitor) ?*Workspace {
    const head: [*c]c.struct_wl_list = @ptrCast(&workspaces);
    var pos = workspaces.next;
    while (pos != head) : (pos = pos.*.next) {
        const w = workspaceFromLink(pos);
        if (w.tag == tag and w.m == m)
            return w;
    }
    return null;
}

test "workspace names and tag switches" {
    resetWorkspaceWorld();
    c.config.tag_num = 3;
    try testing.expectEqualStrings("overview", std.mem.span(get_name_from_tag(0)));
    c.tags[0] = "one";
    try testing.expectEqualStrings("one", std.mem.span(get_name_from_tag(1)));
    try testing.expect(get_name_from_tag(4) == null);

    var w: Workspace = std.mem.zeroes(Workspace);
    w.tag = 2;
    goto_workspace(&w);
    try testing.expectEqual(@as(u32, 2), stub_switch_tags);
    toggle_workspace(&w);
    try testing.expectEqual(@as(u32, 2), stub_toggle_view_tags);
    w.tag = 0;
    goto_workspace(&w);
    try testing.expectEqual(@as(c_int, 1), stub_overview_calls);
    toggle_workspace(&w);
    try testing.expectEqual(@as(i32, -1), stub_toggle_view_i);
}

test "workspace add, remove and cleanup by monitor" {
    resetWorkspaceWorld();
    var m: Monitor = std.mem.zeroes(Monitor);
    m.ext_group = @ptrFromInt(0x1000);
    add_workspace_by_tag(1, &m);
    add_workspace_by_tag(2, &m);
    try testing.expectEqual(@as(c_int, 2), stub_handle_create_calls);
    try testing.expectEqual(@as(c_int, 2), stub_group_calls);
    try testing.expectEqual(@as(c_int, 2), stub_name_calls);
    try testing.expect(findWorkspace(1, &m) != null);
    remove_workspace_by_tag(1, &m);
    try testing.expect(findWorkspace(1, &m) == null);
    try testing.expectEqual(@as(c_int, 1), stub_handle_destroy_calls);
    cleanup_workspaces_by_monitor(&m);
    try testing.expect(findWorkspace(2, &m) == null);
}

test "refresh switches overview and tag workspaces" {
    resetWorkspaceWorld();
    var m: Monitor = std.mem.zeroes(Monitor);
    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    out.enabled = true;
    m.wlr_output = &out;
    var pertag: c.Pertag = std.mem.zeroes(c.Pertag);
    m.pertag = &pertag;
    refresh_monitors_workspaces_status(&m);
    try testing.expect(findWorkspace(1, &m) != null);
    try testing.expect(findWorkspace(2, &m) != null);
    try testing.expect(findWorkspace(3, &m) != null);
    m.isoverview = 1;
    refresh_monitors_workspaces_status(&m);
    try testing.expect(findWorkspace(0, &m) != null);
    try testing.expect(findWorkspace(1, &m) == null);
    out.enabled = false;
    refresh_monitors_workspaces_status(&m);
}

test "workspace status sets hidden, urgent and active" {
    resetWorkspaceWorld();
    var m: Monitor = std.mem.zeroes(Monitor);
    var pertag: c.Pertag = std.mem.zeroes(c.Pertag);
    m.pertag = &pertag;
    m.tagset[0] = 1;
    add_workspace_by_tag(1, &m);
    add_workspace_by_tag(2, &m);
    stub_tag_status = 2;
    stub_active_tagset = 3;
    c.server.tagmask = 0xFFFFFFFF;
    acwm_ext_workspace_printstatus(&m);
    try testing.expectEqual(@as(c_int, 1), stub_last_urgent);
    stub_tag_status = 1;
    acwm_ext_workspace_printstatus(&m);
    try testing.expectEqual(@as(c_int, 0), stub_last_urgent);
    stub_tag_status = 0;
    pertag.no_hide[1] = 1;
    pertag.no_hide[2] = 1;
    acwm_ext_workspace_printstatus(&m);
    try testing.expectEqual(@as(c_int, 0), stub_last_hidden);
    try testing.expectEqual(@as(c_int, 1), stub_last_active);
}

test "workspace commit routes activate and deactivate" {
    resetWorkspaceWorld();
    var m: Monitor = std.mem.zeroes(Monitor);
    add_workspace_by_tag(2, &m);
    const w = findWorkspace(2, &m) orelse return error.TestUnexpectedResult;
    var request: c.struct_wlr_ext_workspace_v1_request = std.mem.zeroes(c.struct_wlr_ext_workspace_v1_request);
    request.type = c.WLR_EXT_WORKSPACE_V1_REQUEST_ACTIVATE;
    request.unnamed_0.activate.workspace = w.ext_workspace;
    var requests: c.struct_wl_list = std.mem.zeroes(c.struct_wl_list);
    listInit(&requests);
    requests.next = &request.link;
    requests.prev = &request.link;
    request.link.next = &requests;
    request.link.prev = &requests;
    var event: c.struct_wlr_ext_workspace_v1_commit_event = std.mem.zeroes(c.struct_wlr_ext_workspace_v1_commit_event);
    event.requests = &requests;
    handle_ext_commit(null, &event);
    try testing.expectEqual(@as(u32, 2), stub_switch_tags);

    request.type = c.WLR_EXT_WORKSPACE_V1_REQUEST_DEACTIVATE;
    request.unnamed_0.deactivate.workspace = w.ext_workspace;
    handle_ext_commit(null, &event);
    try testing.expectEqual(@as(u32, 2), stub_toggle_view_tags);
}

test "hdr format candidates and capability checks" {
    resetWorkspaceWorld();
    var formats = [_]u32{ c.DRM_FORMAT_XRGB8888, c.DRM_FORMAT_XRGB2101010 };
    try testing.expect(output_format_in_candidates(c.DRM_FORMAT_XRGB8888, &formats, 2));
    try testing.expect(!output_format_in_candidates(123, &formats, 2));
    try testing.expectEqual(@as(c_uint, @intCast(c.ACWM_RENDER_BIT_DEPTH_10)), bit_depth_from_format(c.DRM_FORMAT_XRGB2101010));
    try testing.expectEqual(@as(c_uint, @intCast(c.ACWM_RENDER_BIT_DEPTH_8)), bit_depth_from_format(c.DRM_FORMAT_XRGB8888));
    try testing.expectEqual(@as(c_uint, @intCast(c.ACWM_RENDER_BIT_DEPTH_DEFAULT)), bit_depth_from_format(123));

    var m: Monitor = std.mem.zeroes(Monitor);
    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    var renderer: c.struct_wlr_renderer = std.mem.zeroes(c.struct_wlr_renderer);
    m.wlr_output = &out;
    c.server.renderer = &renderer;
    out.supported_primaries = 0;
    var reason: ?[*:0]const u8 = null;
    try testing.expect(!output_supports_hdr(&m, &reason));
    try testing.expect(reason != null);
    out.supported_primaries = c.WLR_COLOR_NAMED_PRIMARIES_BT2020;
    out.supported_transfer_functions = c.WLR_COLOR_TRANSFER_FUNCTION_ST2084_PQ;
    try testing.expect(!output_supports_hdr(&m, &reason));
    renderer.features.output_color_transform = true;
    try testing.expect(output_supports_hdr(&m, &reason));
    m.hdr_force = true;
    out.supported_primaries = 0;
    try testing.expect(output_supports_hdr(&m, &reason));
}

test "hdr enable sets image description and metadata" {
    resetWorkspaceWorld();
    var m: Monitor = std.mem.zeroes(Monitor);
    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    var renderer: c.struct_wlr_renderer = std.mem.zeroes(c.struct_wlr_renderer);
    var state: c.struct_wlr_output_state = std.mem.zeroes(c.struct_wlr_output_state);
    m.wlr_output = &out;
    c.server.renderer = &renderer;
    out.supported_primaries = c.WLR_COLOR_NAMED_PRIMARIES_BT2020;
    out.supported_transfer_functions = c.WLR_COLOR_TRANSFER_FUNCTION_ST2084_PQ;
    renderer.features.output_color_transform = true;
    m.hdr_max_lum = 1000;
    m.hdr_min_lum = 1;
    m.hdr_max_avg_lum = 200;
    output_enable_hdr(&m, &state, true, true);
    try testing.expect(m.is_hdr_enabling);
    try testing.expectEqual(@as(c_int, 1), stub_image_desc_calls);
    try testing.expectEqual(@as(f64, 1000), stub_last_desc.mastering_luminance.max);
    try testing.expectEqual(@as(f64, 200), stub_last_desc.max_fall);

    m.is_hdr_enabling = true;
    output_enable_hdr(&m, &state, false, true);
    try testing.expect(!m.is_hdr_enabling);
    try testing.expectEqual(@as(c_int, 1), stub_image_desc_null);
}

test "hdr setup selects depth and falls back to 8 bit" {
    resetWorkspaceWorld();
    var m: Monitor = std.mem.zeroes(Monitor);
    var out: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    var renderer: c.struct_wlr_renderer = std.mem.zeroes(c.struct_wlr_renderer);
    var state: c.struct_wlr_output_state = std.mem.zeroes(c.struct_wlr_output_state);
    m.wlr_output = &out;
    c.server.renderer = &renderer;
    out.supported_primaries = c.WLR_COLOR_NAMED_PRIMARIES_BT2020;
    out.supported_transfer_functions = c.WLR_COLOR_TRANSFER_FUNCTION_ST2084_PQ;
    renderer.features.output_color_transform = true;
    c.config.hdr_depth = c.ACWM_RENDER_BIT_DEPTH_10;
    out.render_format = c.DRM_FORMAT_XRGB2101010;
    output_state_setup_hdr(&m, true, &state);
    try testing.expect(m.is_hdr_enabling);
    try testing.expectEqual(@as(c_int, 0), stub_render_format_calls);

    resetWorkspaceWorld();
    m = std.mem.zeroes(Monitor);
    out = std.mem.zeroes(c.struct_wlr_output);
    renderer = std.mem.zeroes(c.struct_wlr_renderer);
    state = std.mem.zeroes(c.struct_wlr_output_state);
    m.wlr_output = &out;
    c.server.renderer = &renderer;
    out.supported_primaries = c.WLR_COLOR_NAMED_PRIMARIES_BT2020;
    out.supported_transfer_functions = c.WLR_COLOR_TRANSFER_FUNCTION_ST2084_PQ;
    renderer.features.output_color_transform = true;
    c.config.hdr_depth = c.ACWM_RENDER_BIT_DEPTH_10;
    out.render_format = c.DRM_FORMAT_XRGB8888;
    stub_test_state = false;
    output_state_setup_hdr(&m, true, &state);
    try testing.expect(stub_render_format_calls >= 2);
    try testing.expect(stub_error_calls >= 1);
}

test "toggle hdr output and all-monitor toggle" {
    resetWorkspaceWorld();
    var m1: Monitor = std.mem.zeroes(Monitor);
    var m2: Monitor = std.mem.zeroes(Monitor);
    var out1: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    var out2: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    var scene1: c.struct_wlr_scene_output = std.mem.zeroes(c.struct_wlr_scene_output);
    var scene2: c.struct_wlr_scene_output = std.mem.zeroes(c.struct_wlr_scene_output);
    var renderer: c.struct_wlr_renderer = std.mem.zeroes(c.struct_wlr_renderer);
    out1.enabled = true;
    out2.enabled = true;
    out1.name = @constCast("eDP-1");
    out2.name = @constCast("HDMI-1");
    out1.supported_primaries = c.WLR_COLOR_NAMED_PRIMARIES_BT2020;
    out2.supported_primaries = c.WLR_COLOR_NAMED_PRIMARIES_BT2020;
    out1.supported_transfer_functions = c.WLR_COLOR_TRANSFER_FUNCTION_ST2084_PQ;
    out2.supported_transfer_functions = c.WLR_COLOR_TRANSFER_FUNCTION_ST2084_PQ;
    renderer.features.output_color_transform = true;
    m1.wlr_output = &out1;
    m2.wlr_output = &out2;
    m1.scene_output = &scene1;
    m2.scene_output = &scene2;
    c.server.renderer = &renderer;
    c.server.selected_monitor = &m1;
    listInsertList(&c.server.monitors, &m1.link);
    listInsertList(&c.server.monitors, &m2.link);

    try testing.expect(togglehdr_output(&m1, true));
    try testing.expect(m1.hdr_enable);
    try testing.expectEqual(@as(c_int, 1), stub_commit_calls);
    try testing.expectEqual(@as(i32, 1920), m1.m.width);
    try testing.expectEqual(@as(c_int, 1), stub_damage_calls);

    stub_commit_ok = false;
    try testing.expect(!togglehdr_output(&m2, true));
    try testing.expect(!m2.hdr_enable);
    try testing.expectEqual(@as(c_int, 1), stub_state_finish_calls);
    try testing.expectEqual(@as(c_int, 1), stub_state_init_calls);

    var arg: c.Arg = std.mem.zeroes(c.Arg);
    arg.v = @constCast("all");
    arg.i = -1;
    _ = toggle_hdr(&arg);
    try testing.expect(m1.hdr_enable);
    m1.hdr_enable = false;
    stub_commit_ok = true;
    arg.v = null;
    arg.i = -1;
    _ = toggle_hdr(&arg);
    try testing.expect(m1.hdr_enable);
}

fn listInsertList(head: *c.struct_wl_list, link: *c.struct_wl_list) void {
    link.next = head.next;
    link.prev = @ptrCast(head);
    head.next.*.prev = @ptrCast(link);
    head.next = @ptrCast(link);
}
