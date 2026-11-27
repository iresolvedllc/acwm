/* Test-only stubs for the watcher.zig tests.
 *
 * Provides the config global, a controllable file-path table, a reload
 * counter and no-op wayland event-loop sources. The inotify calls come from
 * libc (the watcher really talks to the kernel in tests). */
#define WLR_USE_UNSTABLE 1
#include "acwm/config/parse.h"

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <wayland-server-core.h>

Config config = {0};

char *stub_paths[4] = {0};
int stub_paths_count = 0;
int stub_reload_calls = 0;
char stub_last_error[512] = {0};
int stub_error_count = 0;

char **config_get_file_paths(int *count) {
	if (count)
		*count = stub_paths_count;
	return stub_paths;
}

int32_t reload_config(const Arg *arg) {
	(void)arg;
	stub_reload_calls++;
	return 1;
}

struct wl_event_source *wl_event_loop_add_timer(struct wl_event_loop *loop,
												wl_event_loop_timer_func_t func,
												void *data) {
	(void)loop;
	(void)func;
	(void)data;
	return (struct wl_event_source *)0x1;
}

struct wl_event_source *wl_event_loop_add_fd(struct wl_event_loop *loop, int fd,
											 uint32_t mask,
											 wl_event_loop_fd_func_t func,
											 void *data) {
	(void)loop;
	(void)fd;
	(void)mask;
	(void)func;
	(void)data;
	return (struct wl_event_source *)0x1;
}

int wl_event_source_timer_update(struct wl_event_source *source, int ms) {
	(void)source;
	(void)ms;
	return 0;
}

int wl_event_source_remove(struct wl_event_source *source) {
	(void)source;
	return 0;
}

void acwm_error_impl(bool log, unsigned verbosity, const char *file, int line,
					 const char *fmt, ...) {
	(void)log;
	(void)verbosity;
	(void)file;
	(void)line;
	va_list args;
	va_start(args, fmt);
	vsnprintf(stub_last_error, sizeof(stub_last_error), fmt, args);
	va_end(args);
	stub_error_count++;
}

void acwm_error_untagged(unsigned verbosity, const char *fmt, ...) {
	(void)verbosity;
	(void)fmt;
}
