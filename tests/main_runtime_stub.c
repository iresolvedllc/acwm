/* Test-only stubs for src/main_runtime.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/log.h"
#include "acwm/common/server.h"
#include "acwm/ipc/ipc.h"
#include <sys/resource.h>
#include "acwm/config/parse.h"
#include "acwm/manage/monitor.h"
#include <stddef.h>
#include <string.h>
#include <wayland-server-core.h>

Config config = {0};
struct AcwmServer server = {0};

int stub_list_remove_calls = 0;
void wl_list_remove(struct wl_list *e) { (void)e; stub_list_remove_calls++; }
int stub_quit_calls = 0;
int32_t quit(const Arg *a) { (void)a; stub_quit_calls++; return 0; }
int stub_die_calls = 0;
void die(const char *f, ...) { (void)f; stub_die_calls++; }
int stub_setup_calls = 0, stub_config_ok = 1;
void setup(void) { stub_setup_calls++; }
bool parse_config(void) { return stub_config_ok != 0; }
int stub_env_display_calls = 0, stub_run_exec_calls = 0, stub_run_exec_once_calls = 0;
void set_env_display(void) { stub_env_display_calls++; }
void run_exec(void) { stub_run_exec_calls++; }
void run_exec_once(void) { stub_run_exec_once_calls++; }
int stub_nonblock_calls = 0;
int32_t fd_set_nonblock(int32_t fd) { (void)fd; stub_nonblock_calls++; return 0; }
char *stub_join_result = NULL;
char *join_strings(char **strings, const char *sep) { (void)strings; (void)sep; return strdup("DISPLAY WAYLAND_DISPLAY"); }
char *join_strings_with_suffix(char **strings, const char *suffix, const char *sep) { (void)strings; (void)suffix; (void)sep; return strdup("DISPLAY= WAYLAND_DISPLAY="); }
int stub_spawn_calls = 0, stub_spawn_shell_calls = 0;
int32_t spawn(const Arg *a) { (void)a; stub_spawn_calls++; return 0; }
int32_t spawn_shell(const Arg *a) { (void)a; stub_spawn_shell_calls++; return 0; }
int stub_printstatus_calls = 0;
void printstatus(enum ipc_watch_type t) { (void)t; stub_printstatus_calls++; }
int stub_select_calls = 0;
void set_selected_monitor(Monitor *m) { (void)m; stub_select_calls++; }
Monitor *stub_monitor = NULL;
Monitor *monitor_at_point(double x, double y) { (void)x; (void)y; return stub_monitor; }
int stub_pointer_activity_calls = 0;
void pointer_cursor_activity(void) { stub_pointer_activity_calls++; }
int stub_bar_cleanup = 0, stub_ipc_cleanup = 0, stub_watch_destroy = 0, stub_nag_destroy = 0;
void bar_cleanup(void) { stub_bar_cleanup++; }
void ipc_cleanup(void) { stub_ipc_cleanup++; }
void config_watcher_destroy(void) { stub_watch_destroy++; }
void config_error_nag_destroy(void) { stub_nag_destroy++; }
int stub_keyboard_group_destroy = 0;
void keyboard_group_destroy(struct wl_listener *l, void *d) { (void)l; (void)d; stub_keyboard_group_destroy++; }
int stub_relay_finish = 0;
void acwm_im_relay_finish(struct acwm_input_method_relay *r) { (void)r; stub_relay_finish++; }
int stub_text_finish = 0;
void acwm_text_global_finish(void) { stub_text_finish++; }

char *stub_socket = "wayland-0";
const char *wl_display_add_socket_auto(struct wl_display *d) { (void)d; return stub_socket; }
int stub_display_run_calls = 0, stub_destroy_clients_calls = 0, stub_display_destroy_calls = 0;
void wl_display_run(struct wl_display *d) { (void)d; stub_display_run_calls++; }
void wl_display_destroy_clients(struct wl_display *d) { (void)d; stub_destroy_clients_calls++; }
void wl_display_destroy(struct wl_display *d) { (void)d; stub_display_destroy_calls++; }
int stub_backend_start_calls = 0, stub_backend_destroy_calls = 0;
bool wlr_backend_start(struct wlr_backend *b) { (void)b; stub_backend_start_calls++; return true; }
void wlr_backend_destroy(struct wlr_backend *b) { (void)b; stub_backend_destroy_calls++; }
int stub_xcursor_destroy = 0;
void wlr_xcursor_manager_destroy(struct wlr_xcursor_manager *m) { (void)m; stub_xcursor_destroy++; }
int stub_warp_calls = 0, stub_set_xcursor_calls = 0;
void wlr_cursor_warp_closest(struct wlr_cursor *c, struct wlr_input_device *d, double x, double y) { (void)c; (void)d; (void)x; (void)y; stub_warp_calls++; }
void wlr_cursor_set_xcursor(struct wlr_cursor *c, struct wlr_xcursor_manager *m, const char *n) { (void)c; (void)m; (void)n; stub_set_xcursor_calls++; }
int stub_scene_destroy = 0;
void wlr_scene_node_destroy(struct wlr_scene_node *n) { (void)n; stub_scene_destroy++; }
int stub_xwayland_destroy = 0;
void wlr_xwayland_destroy(struct wlr_xwayland *x) { (void)x; stub_xwayland_destroy++; }

int stub_getrlimit_calls = 0, stub_setrlimit_calls = 0;
int getrlimit(int resource, struct rlimit *r) { (void)resource; r->rlim_cur = 1024; r->rlim_max = 4096; stub_getrlimit_calls++; return 0; }
int setrlimit(int resource, const struct rlimit *r) { (void)resource; (void)r; stub_setrlimit_calls++; return 0; }
int stub_sigaction_calls = 0;
int sigaction(int sig, const struct sigaction *act, struct sigaction *old) { (void)sig; (void)act; (void)old; stub_sigaction_calls++; return 0; }
int stub_sigemptyset_calls = 0;
int sigemptyset(sigset_t *s) { (void)s; stub_sigemptyset_calls++; return 0; }
int stub_sigprocmask_calls = 0;
int sigprocmask(int how, const sigset_t *s, sigset_t *o) { (void)how; (void)s; (void)o; stub_sigprocmask_calls++; return 0; }
int stub_atfork_calls = 0;
int pthread_atfork(void (*p)(void), void (*pa)(void), void (*c)(void)) { (void)p; (void)pa; (void)c; stub_atfork_calls++; return 0; }
pid_t stub_waitpid_result = 0;
pid_t waitpid(pid_t p, int *s, int o) { (void)p; (void)s; (void)o; return stub_waitpid_result; }
int stub_kill_calls = 0;
int kill(pid_t p, int s) { (void)p; (void)s; stub_kill_calls++; return 0; }
int stub_pipe_calls = 0;
int pipe(int fds[2]) { fds[0] = 3; fds[1] = 4; stub_pipe_calls++; return 0; }
pid_t stub_fork_result = 5;
pid_t fork(void) { return stub_fork_result; }
pid_t setsid(void) { return 1; }
int stub_dup2_calls = 0, stub_close_calls = 0, stub_execl_calls = 0, stub_write_calls = 0;
int dup2(int a, int b) { (void)a; (void)b; stub_dup2_calls++; return 0; }
int close(int f) { (void)f; stub_close_calls++; return 0; }
int execl(const char *p, const char *a0, ...) { (void)p; (void)a0; stub_execl_calls++; return 0; }
ssize_t write(int f, const void *b, size_t n) { (void)f; (void)b; (void)n; stub_write_calls++; return 1; }
const char *stub_dbus = NULL;
char *getenv(const char *n) { (void)n; return (char *)stub_dbus; }
int stub_setenv_calls = 0;
int setenv(const char *n, const char *v, int o) { (void)n; (void)v; (void)o; stub_setenv_calls++; return 0; }
int stub_printf_calls = 0;
int printf(const char *f, ...) { (void)f; stub_printf_calls++; return 0; }
char *stub_optarg = NULL;
char *optarg = NULL;
int optind = 1;
int stub_getopt_calls = 0, stub_getopt_ret = -1;
int getopt(int argc, char **argv, const char *opts) { (void)argc; (void)argv; (void)opts; stub_getopt_calls++; int ret = stub_getopt_ret; stub_getopt_ret = -1; if (ret != -1) optarg = stub_optarg; return ret; }
int stub_exit_success = 0, stub_exit_failure = 1;
char *string_printf(const char *fmt, ...) { return strdup(fmt); }
int acwm_error_calls = 0;
void acwm_error_impl(bool log, enum wlr_log_importance v, const char *f, int l, const char *fmt, ...) { (void)log; (void)v; (void)f; (void)l; (void)fmt; acwm_error_calls++; }
#include <stdarg.h>
