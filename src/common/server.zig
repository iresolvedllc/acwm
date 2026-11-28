//! Port of common/server.c static listener table (Phase 5, common data
//! slice 1, slice 92).

const std = @import("std");
const c = @import("cc");
const build_options = @import("build_options");

const Notify = *const fn ([*c]c.struct_wl_listener, ?*anyopaque) callconv(.c) void;

extern fn handle_print_status(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_cursor_axis(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_cursor_button(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_cursor_frame(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_cursor_motion(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_cursor_motion_absolute(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_renderer_lost(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_output_layout_change(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_new_idle_inhibitor(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_new_input_device(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_new_virtual_keyboard(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_new_virtual_pointer(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_new_pointer_constraint(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_new_output(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_new_xdg_toplevel(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_new_xdg_popup(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_new_xdg_decoration(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_new_layer_surface(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_output_manager_apply(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_output_manager_test(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_output_power_manager_set_mode(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_tearing_new_object(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_ext_commit(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_tablet_tool_axis(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_tablet_tool_button(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_tablet_tool_proximity(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_tablet_tool_tip(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_cursor_touch_down(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_cursor_touch_up(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_cursor_touch_cancel(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_cursor_touch_motion(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_cursor_touch_frame(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_ext_image_copy_capture_new_session(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_request_set_cursor(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_request_set_primary_selection(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_request_set_selection(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_request_set_cursor_shape(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_request_start_drag(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_start_drag(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_new_session_lock(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_drm_lease_request(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_keyboard_shortcuts_inhibit_new_inhibitor(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_last_cursor_surface_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_new_xwayland_surface(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_xwayland_ready(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;

export var server: c.AcwmServer = init: {
    var s = std.mem.zeroes(c.AcwmServer);
    s.child_pid = -1;
    s.enable_gaps = 1; // enables gaps, used by togglegaps
    s.allow_frame_scheduling = true;
    s.render_border = true;
    s.tagmask = (1 << 9) - 1; // default 9 tags; updated with config.tag_num

    s.key_mode = .{
        .mode = [_]u8{ 'd', 'e', 'f', 'a', 'u', 'l', 't' } ++ std.mem.zeroes([21]u8),
        .isdefault = true,
    };

    s.print_status_listener.notify = &handle_print_status;
    s.cursor_axis_listener.notify = &handle_cursor_axis;
    s.cursor_button_listener.notify = &handle_cursor_button;
    s.cursor_frame_listener.notify = &handle_cursor_frame;
    s.cursor_motion_listener.notify = &handle_cursor_motion;
    s.cursor_motion_absolute_listener.notify = &handle_cursor_motion_absolute;
    s.gpu_reset_listener.notify = &handle_renderer_lost;
    s.layout_change_listener.notify = &handle_output_layout_change;
    s.new_idle_inhibitor_listener.notify = &handle_new_idle_inhibitor;
    s.new_input_device_listener.notify = &handle_new_input_device;
    s.new_virtual_keyboard_listener.notify = &handle_new_virtual_keyboard;
    s.new_virtual_pointer_listener.notify = &handle_new_virtual_pointer;
    s.new_pointer_constraint_listener.notify = &handle_new_pointer_constraint;
    s.new_output_listener.notify = &handle_new_output;
    s.new_xdg_toplevel_listener.notify = &handle_new_xdg_toplevel;
    s.new_xdg_popup_listener.notify = &handle_new_xdg_popup;
    s.new_xdg_decoration_listener.notify = &handle_new_xdg_decoration;
    s.new_layer_surface_listener.notify = &handle_new_layer_surface;
    s.output_manager_apply_listener.notify = &handle_output_manager_apply;
    s.output_manager_test_listener.notify = &handle_output_manager_test;
    s.output_power_manager_set_mode_listener.notify = &handle_output_power_manager_set_mode;
    s.tearing_new_object_listener.notify = &handle_tearing_new_object;
    s.ext_workspace_commit_listener.notify = &handle_ext_commit;
    s.tablet_tool_axis_listener.notify = &handle_tablet_tool_axis;
    s.tablet_tool_button_listener.notify = &handle_tablet_tool_button;
    s.tablet_tool_proximity_listener.notify = &handle_tablet_tool_proximity;
    s.tablet_tool_tip_listener.notify = &handle_tablet_tool_tip;
    s.cursor_touch_down_listener.notify = &handle_cursor_touch_down;
    s.cursor_touch_up_listener.notify = &handle_cursor_touch_up;
    s.cursor_touch_cancel_listener.notify = &handle_cursor_touch_cancel;
    s.cursor_touch_motion_listener.notify = &handle_cursor_touch_motion;
    s.cursor_touch_frame_listener.notify = &handle_cursor_touch_frame;
    s.ext_image_copy_capture_manager_new_session_listener.notify = &handle_ext_image_copy_capture_new_session;
    s.request_cursor_listener.notify = &handle_request_set_cursor;
    s.request_set_psel_listener.notify = &handle_request_set_primary_selection;
    s.request_set_sel_listener.notify = &handle_request_set_selection;
    s.request_set_cursor_shape_listener.notify = &handle_request_set_cursor_shape;
    s.request_start_drag_listener.notify = &handle_request_start_drag;
    s.start_drag_listener.notify = &handle_start_drag;
    s.new_session_lock_listener.notify = &handle_new_session_lock;
    s.drm_lease_request_listener.notify = &handle_drm_lease_request;
    s.keyboard_shortcuts_inhibit_new_inhibitor_listener.notify = &handle_keyboard_shortcuts_inhibit_new_inhibitor;
    s.last_cursor_surface_destroy_listener.notify = &handle_last_cursor_surface_destroy;

    if (build_options.xwayland) {
        s.new_xwayland_surface_listener.notify = &handle_new_xwayland_surface;
        s.xwayland_ready_listener.notify = &handle_xwayland_ready;
    }

    break :init s;
};
