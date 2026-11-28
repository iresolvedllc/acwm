//! Port of main.c orchestration: limits, signals, cleanup, activation env,
//! run loop and CLI (Phase 5, main slice 1, slice 83). setup() stays C for
//! the next slice.

const std = @import("std");
const c = @import("cc");
const build_options = @import("build_options");

const Server = c.AcwmServer;

extern fn quit(arg: [*c]const c.Arg) callconv(.c) i32;
extern fn die(fmt: [*c]const u8, ...) callconv(.c) void;
extern fn setup() callconv(.c) void;
extern fn parse_config() callconv(.c) bool;
extern fn set_env_display() callconv(.c) void;
extern fn run_exec() callconv(.c) void;
extern fn run_exec_once() callconv(.c) void;
extern fn fd_set_nonblock(fd: c_int) callconv(.c) c_int;
extern fn join_strings(strings: [*c][*c]u8, sep: [*c]const u8) callconv(.c) [*c]u8;
extern fn join_strings_with_suffix(strings: [*c][*c]u8, suffix: [*c]const u8, sep: [*c]const u8) callconv(.c) [*c]u8;
extern fn spawn(arg: [*c]const c.Arg) callconv(.c) i32;
extern fn spawn_shell(arg: [*c]const c.Arg) callconv(.c) i32;
extern fn printstatus(t: c.enum_ipc_watch_type) callconv(.c) void;
extern fn set_selected_monitor(m: [*c]c.Monitor) callconv(.c) void;
extern fn monitor_at_point(x: f64, y: f64) callconv(.c) [*c]c.Monitor;
extern fn pointer_cursor_activity() callconv(.c) void;
extern fn bar_cleanup() callconv(.c) void;
extern fn ipc_cleanup() callconv(.c) void;
extern fn config_watcher_destroy() callconv(.c) void;
extern fn config_error_nag_destroy() callconv(.c) void;
extern fn keyboard_group_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;
extern fn acwm_im_relay_finish(relay: [*c]c.struct_acwm_input_method_relay) callconv(.c) void;
extern fn acwm_text_global_finish() callconv(.c) void;
extern fn wl_display_add_socket_auto(display: ?*c.struct_wl_display) callconv(.c) [*c]const u8;
extern fn wl_display_run(display: ?*c.struct_wl_display) callconv(.c) void;
extern fn wl_display_destroy_clients(display: ?*c.struct_wl_display) callconv(.c) void;
extern fn wl_display_destroy(display: ?*c.struct_wl_display) callconv(.c) void;
extern fn wlr_backend_start(backend: [*c]c.struct_wlr_backend) callconv(.c) bool;
extern fn wlr_backend_destroy(backend: [*c]c.struct_wlr_backend) callconv(.c) void;
extern fn wlr_xcursor_manager_destroy(manager: [*c]c.struct_wlr_xcursor_manager) callconv(.c) void;
extern fn wlr_cursor_warp_closest(cursor: [*c]c.struct_wlr_cursor, device: [*c]c.struct_wlr_input_device, x: f64, y: f64) callconv(.c) void;
extern fn wlr_cursor_set_xcursor(cursor: [*c]c.struct_wlr_cursor, manager: [*c]c.struct_wlr_xcursor_manager, name: [*c]const u8) callconv(.c) void;
extern fn wlr_scene_node_destroy(node: [*c]c.struct_wlr_scene_node) callconv(.c) void;
extern fn wlr_xwayland_destroy(xwayland: [*c]c.struct_wlr_xwayland) callconv(.c) void;
extern fn setrlimit(resource: c_int, rlim: *const c.struct_rlimit) callconv(.c) c_int;
extern fn getrlimit(resource: c_int, rlim: *c.struct_rlimit) callconv(.c) c_int;
extern fn pthread_atfork(prepare: ?*const fn () callconv(.c) void, parent: ?*const fn () callconv(.c) void, child: ?*const fn () callconv(.c) void) callconv(.c) c_int;
extern fn sigemptyset(set: *c.sigset_t) callconv(.c) c_int;
extern fn sigprocmask(how: c_int, set: *const c.sigset_t, old: ?*c.sigset_t) callconv(.c) c_int;
extern fn sigaction(sig: c_int, act: *const c.struct_sigaction, old: ?*c.struct_sigaction) callconv(.c) c_int;
extern fn waitpid(pid: c.pid_t, status: ?*c_int, options: c_int) callconv(.c) c.pid_t;
extern fn kill(pid: c.pid_t, sig: c_int) callconv(.c) c_int;
extern fn pipe(fds: *[2]c_int) callconv(.c) c_int;
extern fn fork() callconv(.c) c.pid_t;
extern fn setsid() callconv(.c) c.pid_t;
extern fn dup2(old: c_int, new: c_int) callconv(.c) c_int;
extern fn close(fd: c_int) callconv(.c) c_int;
extern fn execl(path: [*c]const u8, arg0: [*c]const u8, ...) callconv(.c) c_int;
extern fn write(fd: c_int, buf: [*c]const anyopaque, count: usize) callconv(.c) isize;
extern fn getenv(name: [*c]const u8) callconv(.c) [*c]u8;
extern fn setenv(name: [*c]const u8, value: [*c]const u8, overwrite: c_int) callconv(.c) c_int;
extern fn printf(fmt: [*c]const u8, ...) callconv(.c) c_int;
extern fn getopt(argc: c_int, argv: [*c][*c]u8, optstring: [*c]const u8) callconv(.c) c_int;
extern var optarg: [*c]u8;
extern var optind: c_int;

var original_nofile_rlimit: c.struct_rlimit = std.mem.zeroes(c.struct_rlimit);

fn restoreNofileLimit() callconv(.c) void {
    if (original_nofile_rlimit.rlim_cur == 0)
        return;
    if (c.setrlimit(c.RLIMIT_NOFILE, &original_nofile_rlimit) != 0)
        c.acwm_error_impl(true, c.WLR_ERROR, "src/main.c", 147, "Failed to restore max open files limit: setrlimit(NOFILE) failed");
}

fn increaseNofileLimit() void {
    if (c.getrlimit(c.RLIMIT_NOFILE, &original_nofile_rlimit) != 0) {
        c.acwm_error_impl(true, c.WLR_ERROR, "src/main.c", 154, "Failed to bump max open files limit: getrlimit(NOFILE) failed");
        return;
    }
    var new_rlimit = original_nofile_rlimit;
    new_rlimit.rlim_cur = new_rlimit.rlim_max;
    if (c.setrlimit(c.RLIMIT_NOFILE, &new_rlimit) != 0) {
        c.acwm_error_impl(true, c.WLR_ERROR, "src/main.c", 162, "Failed to bump max open files limit: setrlimit(NOFILE) failed");
        c.acwm_error_impl(true, c.WLR_INFO, "src/main.c", 164, "Running with %d max open files", @as(c_int, @intCast(original_nofile_rlimit.rlim_cur)));
        return;
    }
    _ = c.pthread_atfork(null, null, restoreNofileLimit);
}

export fn handle_signal(signo: i32) callconv(.c) void {
    if (signo == c.SIGCHLD) {
        while (waitpid(-1, null, c.WNOHANG) > 0) {}
    } else if (signo == c.SIGINT or signo == c.SIGTERM) {
        _ = quit(null);
    }
}

export fn restore_child_signals() callconv(.c) void {
    var set: c.sigset_t = undefined;
    _ = c.sigemptyset(&set);
    _ = c.sigprocmask(c.SIG_SETMASK, &set, null);
    var sa_dfl = std.mem.zeroes(c.struct_sigaction);
    sa_dfl.sa_flags = 0;
    sa_dfl.__sigaction_handler.sa_handler = c.SIG_DFL;
    _ = c.sigaction(c.SIGCHLD, &sa_dfl, null);
    _ = c.sigaction(c.SIGPIPE, &sa_dfl, null);
}

fn removeAll() void {
    const s = &c.server;
    c.wl_list_remove(&s.ext_workspace_commit_listener.link);
    inline for (.{
        "print_status_listener",                             "cursor_axis_listener",                                "cursor_button_listener",
        "cursor_frame_listener",                             "cursor_motion_listener",                              "cursor_motion_absolute_listener",
        "cursor_touch_down_listener",                        "cursor_touch_up_listener",                            "cursor_touch_cancel_listener",
        "cursor_touch_motion_listener",                      "cursor_touch_frame_listener",                         "tablet_tool_proximity_listener",
        "tablet_tool_axis_listener",                         "tablet_tool_button_listener",                         "tablet_tool_tip_listener",
        "gpu_reset_listener",                                "new_idle_inhibitor_listener",                         "layout_change_listener",
        "new_input_device_listener",                         "new_virtual_keyboard_listener",                       "new_virtual_pointer_listener",
        "new_pointer_constraint_listener",                   "new_output_listener",                                 "new_xdg_toplevel_listener",
        "new_xdg_decoration_listener",                       "new_xdg_popup_listener",                              "new_layer_surface_listener",
        "output_manager_apply_listener",                     "output_manager_test_listener",                        "output_power_manager_set_mode_listener",
        "request_cursor_listener",                           "request_set_psel_listener",                           "request_set_sel_listener",
        "request_set_cursor_shape_listener",                 "request_start_drag_listener",                         "start_drag_listener",
        "new_session_lock_listener",                         "new_foreign_toplevel_capture_listener",               "tearing_new_object_listener",
        "keyboard_shortcuts_inhibit_new_inhibitor_listener", "ext_image_copy_capture_manager_new_session_listener",
    }) |field| c.wl_list_remove(&@field(s, field).link);
    if (s.drm_lease_manager != null)
        c.wl_list_remove(&s.drm_lease_request_listener.link);
    if (build_options.xwayland and s.xwayland != null) {
        c.wl_list_remove(&s.new_xwayland_surface_listener.link);
        c.wl_list_remove(&s.xwayland_ready_listener.link);
    }
}

export fn cleanup_listeners() callconv(.c) void {
    removeAll();
}

export fn cleanup() callconv(.c) void {
    c.server.allow_frame_scheduling = false;
    bar_cleanup();
    unset_activation_env();
    ipc_cleanup();
    config_watcher_destroy();
    config_error_nag_destroy();
    cleanup_listeners();
    if (build_options.xwayland and c.server.xwayland != null) {
        c.wlr_xwayland_destroy(c.server.xwayland);
        c.server.xwayland = null;
    }
    c.wl_display_destroy_clients(c.server.display);
    if (c.server.child_pid > 0) {
        _ = c.kill(-c.server.child_pid, c.SIGTERM);
        _ = waitpid(c.server.child_pid, null, 0);
    }
    c.wlr_xcursor_manager_destroy(c.server.cursor_manager);
    keyboard_group_destroy(&c.server.keyboard_group.*.destroy, null);
    acwm_im_relay_finish(c.server.input_method_relay);
    c.wlr_backend_destroy(c.server.backend);
    c.wl_display_destroy(c.server.display);
    c.wlr_scene_node_destroy(&c.server.scene.*.tree.node);
    acwm_text_global_finish();
}

export fn handle_quit_signal(signo: i32) callconv(.c) void {
    _ = signo;
    _ = quit(null);
}

var env_vars = [_][*c]u8{
    @constCast("DISPLAY"),                 @constCast("WAYLAND_DISPLAY"), @constCast("XDG_CURRENT_DESKTOP"),
    @constCast("XDG_SESSION_TYPE"),        @constCast("XCURSOR_THEME"),   @constCast("XCURSOR_SIZE"),
    @constCast("ACWM_INSTANCE_SIGNATURE"), null,
};

export fn set_activation_env() callconv(.c) void {
    if (c.getenv("DBUS_SESSION_BUS_ADDRESS") == null) {
        c.acwm_error_impl(true, c.WLR_INFO, "src/main.c", 299, "Not updating dbus execution environment: DBUS_SESSION_BUS_ADDRESS not set");
        return;
    }
    c.acwm_error_impl(true, c.WLR_INFO, "src/main.c", 303, "Updating dbus execution environment");
    const env_keys = join_strings(@ptrCast(&env_vars), " ");
    const cmd1 = c.string_printf("dbus-update-activation-environment %s", env_keys);
    if (cmd1 == null) {
        c.acwm_error_impl(true, c.WLR_ERROR, "src/main.c", 311, "Failed to allocate command string");
        c.free(env_keys);
        return;
    }
    var arg = std.mem.zeroes(c.Arg);
    arg.v = cmd1;
    _ = spawn(&arg);
    c.free(cmd1);
    const cmd2 = c.string_printf("systemctl --user import-environment %s; systemctl --user --no-block start acwm-session.target", env_keys);
    if (cmd2 == null) {
        c.acwm_error_impl(true, c.WLR_ERROR, "src/main.c", 327, "Failed to allocate command string");
        c.free(env_keys);
        return;
    }
    arg.v = cmd2;
    _ = spawn_shell(&arg);
    c.free(cmd2);
    c.free(env_keys);
}

export fn unset_activation_env() callconv(.c) void {
    if (c.getenv("DBUS_SESSION_BUS_ADDRESS") == null) {
        c.acwm_error_impl(true, c.WLR_INFO, "src/main.c", 343, "Not clearing dbus execution environment: DBUS_SESSION_BUS_ADDRESS not set");
        return;
    }
    c.acwm_error_impl(true, c.WLR_INFO, "src/main.c", 347, "Clearing dbus execution environment");
    const env_keys = join_strings(@ptrCast(&env_vars), " ");
    const env_unset_keys = join_strings_with_suffix(@ptrCast(&env_vars), "=", " ");
    if (env_keys == null or env_unset_keys == null) {
        c.acwm_error_impl(true, c.WLR_ERROR, "src/main.c", 353, "Failed to allocate command string");
        c.free(env_keys);
        c.free(env_unset_keys);
        return;
    }
    var arg = std.mem.zeroes(c.Arg);
    const cmd0 = c.string_printf("systemctl --user --no-block stop graphical-session.target");
    if (cmd0 != null) {
        arg.v = cmd0;
        _ = spawn_shell(&arg);
        c.free(cmd0);
    }
    const cmd1 = c.string_printf("systemctl --user unset-environment %s", env_keys);
    if (cmd1 != null) {
        arg.v = cmd1;
        _ = spawn_shell(&arg);
        c.free(cmd1);
    }
    const cmd2 = c.string_printf("dbus-update-activation-environment %s", env_unset_keys);
    if (cmd2 != null) {
        arg.v = cmd2;
        _ = spawn_shell(&arg);
        c.free(cmd2);
    }
    c.free(env_keys);
    c.free(env_unset_keys);
}

export fn run(startup_cmd: [*c]u8, readiness_fd: c_int) callconv(.c) void {
    const socket = c.wl_display_add_socket_auto(c.server.display);
    if (socket == null)
        c.die("startup: display_add_socket_auto");
    _ = c.setenv("WAYLAND_DISPLAY", socket, 1);
    set_env_display();
    if (!c.wlr_backend_start(c.server.backend))
        c.die("startup: backend_start");
    if (startup_cmd != null) {
        var piperw: [2]c_int = undefined;
        if (c.pipe(&piperw) < 0)
            c.die("startup: pipe:");
        c.server.child_pid = c.fork();
        if (c.server.child_pid < 0)
            c.die("startup: fork:");
        if (c.server.child_pid == 0) {
            _ = c.setsid();
            _ = c.dup2(piperw[0], c.STDIN_FILENO);
            _ = c.close(piperw[0]);
            _ = c.close(piperw[1]);
            _ = c.execl("/bin/sh", "/bin/sh", "-c", startup_cmd, @as([*c]const u8, null));
            c.die("startup: execl:");
        }
        _ = c.dup2(piperw[1], c.STDOUT_FILENO);
        _ = c.close(piperw[1]);
        _ = c.close(piperw[0]);
    }
    if (fd_set_nonblock(c.STDOUT_FILENO) < 0)
        _ = c.close(c.STDOUT_FILENO);
    printstatus(c.IPC_WATCH_ARRANGGE);
    set_selected_monitor(monitor_at_point(c.server.cursor.*.x, c.server.cursor.*.y));
    c.wlr_cursor_warp_closest(c.server.cursor, null, c.server.cursor.*.x, c.server.cursor.*.y);
    c.wlr_cursor_set_xcursor(c.server.cursor, c.server.cursor_manager, "left_ptr");
    pointer_cursor_activity();
    set_activation_env();
    run_exec();
    run_exec_once();
    if (readiness_fd > 2) {
        _ = c.write(readiness_fd, "\n", 1);
        _ = c.close(readiness_fd);
    }
    c.wl_display_run(c.server.display);
}

export fn acwm_main(argc: i32, argv: [*c][*c]u8) callconv(.c) i32 {
    var startup_cmd: [*c]u8 = null;
    var readiness_fd: i32 = 0;
    var check_config = false;
    while (true) {
        const opt = c.getopt(argc, argv, "s:c:r:hdvp");
        if (opt == -1) break;
        switch (opt) {
            's' => startup_cmd = c.optarg,
            'd' => c.server.cli_debug_log = true,
            'v' => {
                _ = c.printf("acwm " ++ build_options.version ++ "\n");
                return c.EXIT_SUCCESS;
            },
            'c' => _ = c.snprintf(&c.server.cli_config_path, c.server.cli_config_path.len, "%s", c.optarg),
            'p' => check_config = true,
            'r' => {
                readiness_fd = c.atoi(c.optarg);
                if (readiness_fd < 3) return usage();
            },
            else => return usage(),
        }
    }
    if (c.optind < argc) return usage();
    if (check_config)
        return if (parse_config()) c.EXIT_SUCCESS else c.EXIT_FAILURE;
    increaseNofileLimit();
    if (c.getenv("XDG_RUNTIME_DIR") == null)
        c.die("XDG_RUNTIME_DIR must be set");
    setup();
    run(startup_cmd, readiness_fd);
    cleanup();
    return c.EXIT_SUCCESS;
}

fn usage() i32 {
    _ = c.printf(
        "Usage: acwm [OPTIONS]\n\nOptions:\n  -v             Show acwm version\n  -d             Enable debug log\n  -c <file>      Use custom configuration file\n  -s <command>   Execute startup command\n  -r <fdnum>     When WM is ready, write '\\n' to the given file descriptor and close it. fdnum >= 3\n  -p             Check configuration file error\n",
    );
    return c.EXIT_SUCCESS;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/main_runtime_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_list_remove_calls: c_int;
extern var stub_quit_calls: c_int;
extern var stub_setup_calls: c_int;
extern var stub_config_ok: c_int;
extern var stub_env_display_calls: c_int;
extern var stub_run_exec_calls: c_int;
extern var stub_run_exec_once_calls: c_int;
extern var stub_nonblock_calls: c_int;
extern var stub_spawn_calls: c_int;
extern var stub_spawn_shell_calls: c_int;
extern var stub_printstatus_calls: c_int;
extern var stub_select_calls: c_int;
extern var stub_monitor: [*c]c.Monitor;
extern var stub_pointer_activity_calls: c_int;
extern var stub_bar_cleanup: c_int;
extern var stub_ipc_cleanup: c_int;
extern var stub_watch_destroy: c_int;
extern var stub_nag_destroy: c_int;
extern var stub_keyboard_group_destroy: c_int;
extern var stub_relay_finish: c_int;
extern var stub_text_finish: c_int;
extern var stub_display_run_calls: c_int;
extern var stub_destroy_clients_calls: c_int;
extern var stub_display_destroy_calls: c_int;
extern var stub_backend_start_calls: c_int;
extern var stub_backend_destroy_calls: c_int;
extern var stub_xcursor_destroy: c_int;
extern var stub_warp_calls: c_int;
extern var stub_set_xcursor_calls: c_int;
extern var stub_scene_destroy: c_int;
extern var stub_kill_calls: c_int;
extern var stub_pipe_calls: c_int;
extern var stub_fork_result: c.pid_t;
extern var stub_dup2_calls: c_int;
extern var stub_close_calls: c_int;
extern var stub_execl_calls: c_int;
extern var stub_write_calls: c_int;
extern var stub_dbus: [*c]const u8;
extern var stub_setenv_calls: c_int;
extern var stub_printf_calls: c_int;
extern var stub_getopt_ret: c_int;
extern var stub_optarg: [*c]u8;
extern var stub_getopt_calls: c_int;
extern var stub_exit_success: c_int;
extern var stub_exit_failure: c_int;
extern var stub_getrlimit_calls: c_int;
extern var stub_setrlimit_calls: c_int;
extern var stub_atfork_calls: c_int;
extern var stub_sigaction_calls: c_int;
extern var stub_waitpid_result: c.pid_t;
extern var acwm_error_calls: c_int;

var test_cursor: c.struct_wlr_cursor = std.mem.zeroes(c.struct_wlr_cursor);
var test_scene: c.struct_wlr_scene = std.mem.zeroes(c.struct_wlr_scene);
var test_group: c.KeyboardGroup = std.mem.zeroes(c.KeyboardGroup);
var test_relay: c.struct_acwm_input_method_relay = std.mem.zeroes(c.struct_acwm_input_method_relay);

fn resetMainWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    c.server.cursor = &test_cursor;
    c.server.scene = &test_scene;
    c.server.keyboard_group = &test_group;
    c.server.input_method_relay = &test_relay;
    c.server.child_pid = 0;
    original_nofile_rlimit = std.mem.zeroes(c.struct_rlimit);
    stub_list_remove_calls = 0;
    stub_quit_calls = 0;
    stub_setup_calls = 0;
    stub_config_ok = 1;
    stub_env_display_calls = 0;
    stub_run_exec_calls = 0;
    stub_run_exec_once_calls = 0;
    stub_nonblock_calls = 0;
    stub_spawn_calls = 0;
    stub_spawn_shell_calls = 0;
    stub_printstatus_calls = 0;
    stub_select_calls = 0;
    stub_monitor = null;
    stub_pointer_activity_calls = 0;
    stub_bar_cleanup = 0;
    stub_ipc_cleanup = 0;
    stub_watch_destroy = 0;
    stub_nag_destroy = 0;
    stub_keyboard_group_destroy = 0;
    stub_relay_finish = 0;
    stub_text_finish = 0;
    stub_display_run_calls = 0;
    stub_destroy_clients_calls = 0;
    stub_display_destroy_calls = 0;
    stub_backend_start_calls = 0;
    stub_backend_destroy_calls = 0;
    stub_xcursor_destroy = 0;
    stub_warp_calls = 0;
    stub_set_xcursor_calls = 0;
    stub_scene_destroy = 0;
    stub_kill_calls = 0;
    stub_pipe_calls = 0;
    stub_fork_result = 5;
    stub_dup2_calls = 0;
    stub_close_calls = 0;
    stub_execl_calls = 0;
    stub_write_calls = 0;
    stub_dbus = null;
    stub_setenv_calls = 0;
    stub_printf_calls = 0;
    stub_getopt_ret = -1;
    stub_getopt_calls = 0;
    stub_exit_success = 0;
    stub_exit_failure = 1;
    stub_getrlimit_calls = 0;
    stub_setrlimit_calls = 0;
    stub_atfork_calls = 0;
    stub_sigaction_calls = 0;
    stub_waitpid_result = 0;
    acwm_error_calls = 0;
}

test "signals map to quit and wait on children" {
    resetMainWorld();
    handle_signal(c.SIGINT);
    try testing.expectEqual(@as(c_int, 1), stub_quit_calls);
    handle_signal(c.SIGTERM);
    try testing.expectEqual(@as(c_int, 2), stub_quit_calls);
    handle_signal(c.SIGCHLD);
    try testing.expectEqual(@as(c_int, 2), stub_quit_calls);
    handle_quit_signal(1);
    try testing.expectEqual(@as(c_int, 3), stub_quit_calls);
}

test "cleanup removes listeners and tears subsystems down" {
    resetMainWorld();
    c.server.drm_lease_manager = @ptrFromInt(0x1000);
    cleanup_listeners();
    try testing.expect(stub_list_remove_calls > 30);
    c.server.child_pid = 7;
    cleanup();
    try testing.expectEqual(@as(c_int, 1), stub_bar_cleanup);
    try testing.expectEqual(@as(c_int, 1), stub_ipc_cleanup);
    try testing.expectEqual(@as(c_int, 1), stub_watch_destroy);
    try testing.expectEqual(@as(c_int, 1), stub_nag_destroy);
    try testing.expectEqual(@as(c_int, 1), stub_keyboard_group_destroy);
    try testing.expectEqual(@as(c_int, 1), stub_relay_finish);
    try testing.expectEqual(@as(c_int, 1), stub_backend_destroy_calls);
    try testing.expectEqual(@as(c_int, 1), stub_destroy_clients_calls);
    try testing.expectEqual(@as(c_int, 1), stub_display_destroy_calls);
    try testing.expectEqual(@as(c_int, 1), stub_scene_destroy);
    try testing.expectEqual(@as(c_int, 1), stub_text_finish);
    try testing.expectEqual(@as(c_int, 1), stub_kill_calls);
}

test "activation environment commands respect dbus availability" {
    resetMainWorld();
    set_activation_env();
    try testing.expectEqual(@as(c_int, 0), stub_spawn_calls);
    stub_dbus = "unix:path=/run/user/1000/bus";
    set_activation_env();
    try testing.expectEqual(@as(c_int, 1), stub_spawn_calls);
    try testing.expectEqual(@as(c_int, 2), acwm_error_calls);
    unset_activation_env();
    try testing.expectEqual(@as(c_int, 4), stub_spawn_shell_calls);
}

test "run starts backend, selects monitor and enters the loop" {
    resetMainWorld();
    stub_monitor = @ptrFromInt(0x1000);
    test_cursor.x = 10;
    test_cursor.y = 20;
    run(null, -1);
    try testing.expectEqual(@as(c_int, 1), stub_env_display_calls);
    try testing.expectEqual(@as(c_int, 1), stub_backend_start_calls);
    try testing.expectEqual(@as(c_int, 1), stub_printstatus_calls);
    try testing.expectEqual(@as(c_int, 1), stub_select_calls);
    try testing.expectEqual(@as(c_int, 1), stub_warp_calls);
    try testing.expectEqual(@as(c_int, 1), stub_set_xcursor_calls);
    try testing.expectEqual(@as(c_int, 1), stub_pointer_activity_calls);
    try testing.expectEqual(@as(c_int, 1), stub_run_exec_calls);
    try testing.expectEqual(@as(c_int, 1), stub_run_exec_once_calls);
    try testing.expectEqual(@as(c_int, 1), stub_display_run_calls);
}

test "run spawns startup commands and readiness fd" {
    resetMainWorld();
    var cmd: [8]u8 = undefined;
    @memcpy(cmd[0..3], "cmd");
    cmd[3] = 0;
    run(&cmd, 4);
    try testing.expectEqual(@as(c_int, 1), stub_pipe_calls);
    try testing.expectEqual(@as(c_int, 1), stub_dup2_calls);
    try testing.expectEqual(@as(c_int, 1), stub_write_calls);
    try testing.expectEqual(@as(c_int, 1), stub_nonblock_calls);
    try testing.expectEqual(@as(c_int, 1), stub_display_run_calls);
}

test "main parses version and config-check options" {
    resetMainWorld();
    var argv = [_][*c]u8{ @constCast("acwm"), @constCast("-v"), null };
    stub_getopt_ret = 'v';
    try testing.expectEqual(stub_exit_success, acwm_main(2, &argv));
    try testing.expect(stub_printf_calls >= 1);

    resetMainWorld();
    stub_getopt_ret = 'p';
    try testing.expectEqual(stub_exit_success, acwm_main(1, &argv));
    try testing.expectEqual(@as(c_int, 0), stub_setup_calls);

    resetMainWorld();
    stub_getopt_ret = '?';
    try testing.expectEqual(stub_exit_success, acwm_main(1, &argv));
}
