//! Port of main.c setup() (Phase 5, main slice 2, slice 84).

const std = @import("std");
const c = @import("cc");
const build_options = @import("build_options");

extern fn handle_gpu_reset(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn set_xcursor_env() callconv(.c) void;
extern fn idle_keep_inhibit(data: ?*anyopaque) callconv(.c) c_int;
extern fn idle_check(data: ?*anyopaque) callconv(.c) c_int;
extern fn acwm_idle_init() callconv(.c) void;
extern fn update_seat_capabilities() callconv(.c) void;
extern fn keyboard_group_create() callconv(.c) [*c]c.KeyboardGroup;
extern fn acwm_im_relay_create() callconv(.c) [*c]c.struct_acwm_input_method_relay;
extern fn bar_init(loop: ?*c.struct_wl_event_loop) callconv(.c) void;
extern fn xdg_activation_init() callconv(.c) void;
extern fn xdg_output_init() callconv(.c) void;
extern fn workspaces_init() callconv(.c) void;
extern fn config_error_nag_init() callconv(.c) void;
extern fn handle_cursor_swipe_begin(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_cursor_swipe_update(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_cursor_swipe_end(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_cursor_pinch_begin(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_cursor_pinch_update(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_cursor_pinch_end(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_cursor_hold_begin(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn handle_cursor_hold_end(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn keyboard_sync_keymap(data: ?*anyopaque) callconv(.c) c_int;
extern fn handle_signal(signo: i32) callconv(.c) void;
extern fn restore_child_signals() callconv(.c) void;

var swipe_begin_listener: c.struct_wl_listener = std.mem.zeroes(c.struct_wl_listener);
var swipe_update_listener: c.struct_wl_listener = std.mem.zeroes(c.struct_wl_listener);
var swipe_end_listener: c.struct_wl_listener = std.mem.zeroes(c.struct_wl_listener);
var pinch_begin_listener: c.struct_wl_listener = std.mem.zeroes(c.struct_wl_listener);
var pinch_update_listener: c.struct_wl_listener = std.mem.zeroes(c.struct_wl_listener);
var pinch_end_listener: c.struct_wl_listener = std.mem.zeroes(c.struct_wl_listener);
var hold_begin_listener: c.struct_wl_listener = std.mem.zeroes(c.struct_wl_listener);
var hold_end_listener: c.struct_wl_listener = std.mem.zeroes(c.struct_wl_listener);

fn add(signal: *c.struct_wl_signal, listener: *c.struct_wl_listener) void {
    c.wl_signal_add(signal, listener);
}

fn addStatic(listener: *c.struct_wl_listener, signal: *c.struct_wl_signal, handler: *const fn ([*c]c.struct_wl_listener, ?*anyopaque) callconv(.c) void) void {
    listener.notify = handler;
    c.wl_signal_add(signal, listener);
}

export fn setup() callconv(.c) void {
    _ = c.setenv("XDG_CURRENT_DESKTOP", "acwm", 1);
    _ = c.setenv("_JAVA_AWT_WM_NONREPARENTING", "1", 1);
    _ = c.parse_config();
    if (c.server.cli_debug_log)
        c.config.log_level = c.WLR_DEBUG;
    c.init_baked_points();
    c.set_env_without_display();

    const sig = [_]c_int{ c.SIGCHLD, c.SIGINT, c.SIGTERM };
    var sa = std.mem.zeroes(c.struct_sigaction);
    sa.sa_flags = c.SA_RESTART;
    sa.__sigaction_handler.sa_handler = handle_signal;
    _ = c.sigemptyset(&sa.sa_mask);
    for (sig) |s| _ = c.sigaction(s, &sa, null);
    var sa_pipe = std.mem.zeroes(c.struct_sigaction);
    sa_pipe.sa_flags = 0;
    sa_pipe.__sigaction_handler.sa_handler = c.SIG_IGN;
    _ = c.sigemptyset(&sa_pipe.sa_mask);
    _ = c.sigaction(c.SIGPIPE, &sa_pipe, null);
    _ = c.pthread_atfork(null, null, restore_child_signals);
    c.wlr_log_init(@intCast(c.config.log_level), null);

    c.server.display = c.wl_display_create();
    c.wl_display_set_default_max_buffer_size(c.server.display, 1024 * 1024);
    c.wl_display_set_global_filter(c.server.display, c.acwm_global_filter, null);
    c.server.event_loop = c.wl_display_get_event_loop(c.server.display);
    c.ipc_init(c.server.event_loop);
    c.config_watcher_init(c.server.event_loop);
    c.server.tablet_manager = c.wlr_tablet_v2_create(c.server.display);

    c.server.backend = c.wlr_backend_autocreate(c.server.event_loop, &c.server.session);
    if (c.server.backend == null) c.die("couldn't create backend");
    c.server.headless_backend = c.wlr_headless_backend_create(c.server.event_loop);
    if (c.server.headless_backend == null) {
        c.acwm_error_impl(true, c.WLR_ERROR, "src/main.c", 528, "Failed to create secondary headless backend");
    } else {
        _ = c.wlr_multi_backend_add(c.server.backend, c.server.headless_backend);
    }

    c.server.scene = c.wlr_scene_create();
    c.server.root_bg = c.wlr_scene_rect_create(&c.server.scene.*.tree, 0, 0, &c.config.rootcolor);
    var i: usize = 0;
    while (i < c.NUM_LAYERS) : (i += 1) {
        c.server.layers_wrap[i] = c.wlr_scene_tree_create(&c.server.scene.*.tree);
        c.server.layers[i] = c.wlr_scene_tree_create(c.server.layers_wrap[i]);
    }
    c.server.drag_icon = c.wlr_scene_tree_create(&c.server.scene.*.tree);
    c.wlr_scene_node_place_below(&c.server.drag_icon.*.node, &c.server.layers_wrap[c.LyrBlock].*.node);

    c.server.renderer = c.fx_renderer_create(c.server.backend);
    if (c.server.renderer == null) c.die("couldn't create renderer");
    if (c.server.renderer.*.features.input_color_transform) {
        const render_intents = [_]c.enum_wp_color_manager_v1_render_intent{c.WP_COLOR_MANAGER_V1_RENDER_INTENT_PERCEPTUAL};
        var tf_len: usize = 0;
        const transfer_functions = c.wlr_color_manager_v1_transfer_function_list_from_renderer(c.server.renderer, &tf_len);
        var primaries_len: usize = 0;
        const primaries = c.wlr_color_manager_v1_primaries_list_from_renderer(c.server.renderer, &primaries_len);
        var options = std.mem.zeroes(c.struct_wlr_color_manager_v1_options);
        options.features.parametric = true;
        options.features.set_mastering_display_primaries = true;
        options.render_intents = &render_intents;
        options.render_intents_len = render_intents.len;
        options.transfer_functions = transfer_functions;
        options.transfer_functions_len = tf_len;
        options.primaries = primaries;
        options.primaries_len = primaries_len;
        const cm = c.wlr_color_manager_v1_create(c.server.display, 2, &options);
        c.free(transfer_functions);
        c.free(primaries);
        if (cm != null)
            c.wlr_scene_set_color_manager_v1(c.server.scene, cm)
        else
            c.acwm_error_impl(true, c.WLR_ERROR, "src/main.c", 585, "unable to create color manager");
    }
    _ = c.wlr_color_representation_manager_v1_create_with_renderer(c.server.display, 1, c.server.renderer);
    add(&c.server.renderer.*.events.lost, &c.server.gpu_reset_listener);
    _ = c.wlr_renderer_init_wl_shm(c.server.renderer, c.server.display);
    if (c.wlr_renderer_get_texture_formats(c.server.renderer, c.WLR_BUFFER_CAP_DMABUF) != null) {
        _ = c.wlr_drm_create(c.server.display, c.server.renderer);
        c.wlr_scene_set_linux_dmabuf_v1(c.server.scene, c.wlr_linux_dmabuf_v1_create_with_renderer(c.server.display, 4, c.server.renderer));
    }
    const drm_fd = c.wlr_renderer_get_drm_fd(c.server.renderer);
    if (c.config.syncobj_enable != 0 and drm_fd >= 0 and
        c.server.renderer.*.features.timeline and c.server.backend.*.features.timeline)
        _ = c.wlr_linux_drm_syncobj_manager_v1_create(c.server.display, 1, drm_fd);
    c.server.allocator = c.wlr_allocator_autocreate(c.server.backend, c.server.renderer);
    if (c.server.allocator == null) c.die("couldn't create allocator");

    c.server.compositor = c.wlr_compositor_create(c.server.display, 6, c.server.renderer);
    _ = c.wlr_export_dmabuf_manager_v1_create(c.server.display);
    _ = c.wlr_screencopy_manager_v1_create(c.server.display);
    _ = c.wlr_ext_output_image_capture_source_manager_v1_create(c.server.display, 1);
    _ = c.wlr_data_control_manager_v1_create(c.server.display);
    _ = c.wlr_data_device_manager_create(c.server.display);
    _ = c.wlr_primary_selection_v1_device_manager_create(c.server.display);
    _ = c.wlr_viewporter_create(c.server.display);
    _ = c.wlr_single_pixel_buffer_manager_v1_create(c.server.display);
    _ = c.wlr_fractional_scale_manager_v1_create(c.server.display, 1);
    _ = c.wlr_presentation_create(c.server.display, c.server.backend, 2);
    _ = c.wlr_subcompositor_create(c.server.display);
    _ = c.wlr_alpha_modifier_v1_create(c.server.display);
    _ = c.wlr_ext_data_control_manager_v1_create(c.server.display, 1);
    _ = c.wlr_fixes_create(c.server.display, 1);
    c.wl_signal_init(&c.server.print_status_signal);
    add(&c.server.print_status_signal, &c.server.print_status_listener);
    bar_init(c.server.event_loop);
    c.server.ext_image_copy_capture_manager = c.wlr_ext_image_copy_capture_manager_v1_create(c.server.display, 1);
    add(&c.server.ext_image_copy_capture_manager.*.events.new_session, &c.server.ext_image_copy_capture_manager_new_session_listener);
    xdg_activation_init();
    c.wlr_scene_set_gamma_control_manager_v1(c.server.scene, c.wlr_gamma_control_manager_v1_create(c.server.display));
    c.server.power_manager = c.wlr_output_power_manager_v1_create(c.server.display);
    add(&c.server.power_manager.*.events.set_mode, &c.server.output_power_manager_set_mode_listener);
    c.server.foreign_toplevel_list = c.wlr_ext_foreign_toplevel_list_v1_create(c.server.display, 1);
    c.server.ext_foreign_toplevel_image_capture_source_manager =
        c.wlr_ext_foreign_toplevel_image_capture_source_manager_v1_create(c.server.display, 1);
    add(&c.server.ext_foreign_toplevel_image_capture_source_manager.*.events.new_request, &c.server.new_foreign_toplevel_capture_listener);
    c.server.tearing_control = c.wlr_tearing_control_manager_v1_create(c.server.display, 1);
    add(&c.server.tearing_control.*.events.new_object, &c.server.tearing_new_object_listener);

    c.server.output_layout = c.wlr_output_layout_create(c.server.display);
    add(&c.server.output_layout.*.events.change, &c.server.layout_change_listener);
    xdg_output_init();
    c.wl_list_init(&c.server.monitors);
    add(&c.server.backend.*.events.new_output, &c.server.new_output_listener);
    c.server.scene_layout = c.wlr_scene_attach_output_layout(c.server.scene, c.server.output_layout);
    c.wl_list_init(&c.server.clients);
    c.wl_list_init(&c.server.focus_stack);
    c.wl_list_init(&c.server.fadeout_clients);
    c.wl_list_init(&c.server.fadeout_layers);
    c.server.idle_notifier = c.wlr_idle_notifier_v1_create(c.server.display);
    c.server.idle_inhibit_manager = c.wlr_idle_inhibit_v1_create(c.server.display);
    add(&c.server.idle_inhibit_manager.*.events.new_inhibitor, &c.server.new_idle_inhibitor_listener);
    c.server.keep_idle_inhibit_source = c.wl_event_loop_add_timer(c.wl_display_get_event_loop(c.server.display), idle_keep_inhibit, null);
    c.server.idle_check_source = c.wl_event_loop_add_timer(c.wl_display_get_event_loop(c.server.display), idle_check, null);
    acwm_idle_init();
    c.server.layer_shell = c.wlr_layer_shell_v1_create(c.server.display, 4);
    add(&c.server.layer_shell.*.events.new_surface, &c.server.new_layer_surface_listener);
    c.server.xdg_shell = c.wlr_xdg_shell_create(c.server.display, 6);
    add(&c.server.xdg_shell.*.events.new_toplevel, &c.server.new_xdg_toplevel_listener);
    add(&c.server.xdg_shell.*.events.new_popup, &c.server.new_xdg_popup_listener);
    c.server.session_lock_manager = c.wlr_session_lock_manager_v1_create(c.server.display);
    add(&c.server.session_lock_manager.*.events.new_lock, &c.server.new_session_lock_listener);
    var locked_color = [4]f32{ 0.1, 0.1, 0.1, 1.0 };
    c.server.locked_bg = c.wlr_scene_rect_create(c.server.layers[c.LyrBlock], c.server.scene_geometry.width, c.server.scene_geometry.height, &locked_color);
    c.wlr_scene_node_set_enabled(&c.server.locked_bg.*.node, false);
    c.wlr_server_decoration_manager_set_default_mode(c.wlr_server_decoration_manager_create(c.server.display), c.WLR_SERVER_DECORATION_MANAGER_MODE_SERVER);
    c.server.decoration_manager = c.wlr_xdg_decoration_manager_v1_create(c.server.display);
    add(&c.server.decoration_manager.*.events.new_toplevel_decoration, &c.server.new_xdg_decoration_listener);
    c.server.pointer_constraints = c.wlr_pointer_constraints_v1_create(c.server.display);
    add(&c.server.pointer_constraints.*.events.new_constraint, &c.server.new_pointer_constraint_listener);
    c.server.relative_pointer_manager = c.wlr_relative_pointer_manager_v1_create(c.server.display);
    c.server.cursor = c.wlr_cursor_create();
    c.wlr_cursor_attach_output_layout(c.server.cursor, c.server.output_layout);
    set_xcursor_env();
    c.server.cursor_manager = c.wlr_xcursor_manager_create(c.config.cursor_theme, c.config.cursor_size);
    add(&c.server.cursor.*.events.motion, &c.server.cursor_motion_listener);
    add(&c.server.cursor.*.events.motion_absolute, &c.server.cursor_motion_absolute_listener);
    add(&c.server.cursor.*.events.button, &c.server.cursor_button_listener);
    add(&c.server.cursor.*.events.axis, &c.server.cursor_axis_listener);
    add(&c.server.cursor.*.events.frame, &c.server.cursor_frame_listener);
    add(&c.server.cursor.*.events.tablet_tool_proximity, &c.server.tablet_tool_proximity_listener);
    add(&c.server.cursor.*.events.tablet_tool_axis, &c.server.tablet_tool_axis_listener);
    add(&c.server.cursor.*.events.tablet_tool_button, &c.server.tablet_tool_button_listener);
    add(&c.server.cursor.*.events.tablet_tool_tip, &c.server.tablet_tool_tip_listener);
    c.server.cursor_shape_manager = c.wlr_cursor_shape_manager_v1_create(c.server.display, 1);
    add(&c.server.cursor_shape_manager.*.events.request_set_shape, &c.server.request_set_cursor_shape_listener);
    c.server.hide_cursor_source = c.wl_event_loop_add_timer(c.wl_display_get_event_loop(c.server.display), c.pointer_hide_cursor, c.server.cursor);
    c.wl_list_init(&c.server.input_devices);
    c.wl_list_init(&c.server.seat_devices);
    c.wl_list_init(&c.server.standalone_keyboards);
    c.wl_list_init(&c.server.virtual_keyboards);
    c.wl_list_init(&c.server.tablets);
    c.wl_list_init(&c.server.tablet_pads);
    c.wl_list_init(&c.server.keyboard_shortcut_inhibitors);
    add(&c.server.backend.*.events.new_input, &c.server.new_input_device_listener);
    c.server.virtual_keyboard_manager = c.wlr_virtual_keyboard_manager_v1_create(c.server.display);
    add(&c.server.virtual_keyboard_manager.*.events.new_virtual_keyboard, &c.server.new_virtual_keyboard_listener);
    c.server.virtual_pointer_manager = c.wlr_virtual_pointer_manager_v1_create(c.server.display);
    add(&c.server.virtual_pointer_manager.*.events.new_virtual_pointer, &c.server.new_virtual_pointer_listener);
    c.server.pointer_gestures = c.wlr_pointer_gestures_v1_create(c.server.display);
    addStatic(&swipe_begin_listener, &c.server.cursor.*.events.swipe_begin, handle_cursor_swipe_begin);
    addStatic(&swipe_update_listener, &c.server.cursor.*.events.swipe_update, handle_cursor_swipe_update);
    addStatic(&swipe_end_listener, &c.server.cursor.*.events.swipe_end, handle_cursor_swipe_end);
    addStatic(&pinch_begin_listener, &c.server.cursor.*.events.pinch_begin, handle_cursor_pinch_begin);
    addStatic(&pinch_update_listener, &c.server.cursor.*.events.pinch_update, handle_cursor_pinch_update);
    addStatic(&pinch_end_listener, &c.server.cursor.*.events.pinch_end, handle_cursor_pinch_end);
    addStatic(&hold_begin_listener, &c.server.cursor.*.events.hold_begin, handle_cursor_hold_begin);
    addStatic(&hold_end_listener, &c.server.cursor.*.events.hold_end, handle_cursor_hold_end);
    c.wl_list_init(&c.server.touch_points);
    add(&c.server.cursor.*.events.touch_down, &c.server.cursor_touch_down_listener);
    add(&c.server.cursor.*.events.touch_up, &c.server.cursor_touch_up_listener);
    add(&c.server.cursor.*.events.touch_cancel, &c.server.cursor_touch_cancel_listener);
    add(&c.server.cursor.*.events.touch_motion, &c.server.cursor_touch_motion_listener);
    add(&c.server.cursor.*.events.touch_frame, &c.server.cursor_touch_frame_listener);
    c.server.seat = c.wlr_seat_create(c.server.display, "seat0");
    update_seat_capabilities();
    c.wl_list_init(&c.server.last_cursor_surface_destroy_listener.link);
    add(&c.server.seat.*.events.request_set_cursor, &c.server.request_cursor_listener);
    add(&c.server.seat.*.events.request_set_selection, &c.server.request_set_sel_listener);
    add(&c.server.seat.*.events.request_set_primary_selection, &c.server.request_set_psel_listener);
    add(&c.server.seat.*.events.request_start_drag, &c.server.request_start_drag_listener);
    add(&c.server.seat.*.events.start_drag, &c.server.start_drag_listener);
    c.server.keyboard_group = keyboard_group_create();
    c.server.last_active_keyboard = c.server.keyboard_group.*.keyboard;
    c.wl_list_init(&c.server.keyboard_group.*.destroy.link);
    c.server.keyboard_shortcuts_inhibit = c.wlr_keyboard_shortcuts_inhibit_v1_create(c.server.display);
    add(&c.server.keyboard_shortcuts_inhibit.*.events.new_inhibitor, &c.server.keyboard_shortcuts_inhibit_new_inhibitor_listener);
    c.server.output_manager = c.wlr_output_manager_v1_create(c.server.display);
    add(&c.server.output_manager.*.events.apply, &c.server.output_manager_apply_listener);
    add(&c.server.output_manager.*.events.@"test", &c.server.output_manager_test_listener);
    c.wlr_scene_set_blur_data(c.server.scene, c.config.blur_params.num_passes, @intFromFloat(c.config.blur_params.radius), c.config.blur_params.noise, c.config.blur_params.brightness, c.config.blur_params.contrast, c.config.blur_params.saturation);
    c.server.input_method_manager = c.wlr_input_method_manager_v2_create(c.server.display);
    c.server.text_input_manager = c.wlr_text_input_manager_v3_create(c.server.display);
    c.server.input_method_relay = acwm_im_relay_create();
    c.server.drm_lease_manager = c.wlr_drm_lease_v1_manager_create(c.server.display, c.server.backend);
    if (c.server.drm_lease_manager != null) {
        add(&c.server.drm_lease_manager.*.events.request, &c.server.drm_lease_request_listener);
    } else {
        c.acwm_error_impl(true, c.WLR_DEBUG, "src/main.c", 923, "Failed to create wlr_drm_lease_device_v1.");
        c.acwm_error_impl(true, c.WLR_INFO, "src/main.c", 924, "VR will not be available.");
    }
    c.server.foreign_toplevel_manager = c.wlr_foreign_toplevel_manager_v1_create(c.server.display);
    const foreign_registry = c.wlr_xdg_foreign_registry_create(c.server.display);
    _ = c.wlr_xdg_foreign_v1_create(c.server.display, foreign_registry);
    _ = c.wlr_xdg_foreign_v2_create(c.server.display, foreign_registry);
    workspaces_init();
    if (build_options.xwayland) {
        c.server.xwayland = c.wlr_xwayland_create(c.server.display, c.server.compositor, c.config.xwayland_persistence == 0);
        if (c.server.xwayland != null) {
            add(&c.server.xwayland.*.events.ready, &c.server.xwayland_ready_listener);
            add(&c.server.xwayland.*.events.new_surface, &c.server.new_xwayland_surface_listener);
            _ = c.setenv("DISPLAY", c.server.xwayland.*.display_name, 1);
        } else {
            c.acwm_error_impl(true, c.WLR_ERROR, "src/main.c", 948, "failed to setup XWayland X server, continuing without it\n");
        }
        c.server.sync_keymap = c.wl_event_loop_add_timer(c.wl_display_get_event_loop(c.server.display), keyboard_sync_keymap, null);
    }
    config_error_nag_init();
}
