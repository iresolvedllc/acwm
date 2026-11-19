/* Test-only stubs for the error_nag.zig tests.
 *
 * Provides the server global, the error-store path (controllable), a
 * variadic string_printf, and no-op libwayland entry points. The pure
 * helpers under test never reach the wayland/process plumbing. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"

#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-server-core.h>

struct AcwmServer server = {0};

char stub_store_path[4096] = "/tmp/opencode/acwm-error-nag-test-nonexistent.log";

const char *config_error_store_path(void) {
	return stub_store_path;
}

char *string_printf(const char *fmt, ...) {
	va_list args;
	va_start(args, fmt);
	char buf[1024];
	vsnprintf(buf, sizeof(buf), fmt, args);
	va_end(args);
	return strdup(buf);
}

struct wl_client *wl_client_create(struct wl_display *display, int fd) {
	(void)display;
	(void)fd;
	return NULL;
}

void wl_client_destroy(struct wl_client *client) {
	(void)client;
}

void wl_client_add_destroy_listener(struct wl_client *client,
									struct wl_listener *listener) {
	(void)client;
	(void)listener;
}

struct wl_event_source *wl_event_loop_add_timer(
	struct wl_event_loop *loop,
	wl_event_loop_timer_func_t func, void *data) {
	(void)loop;
	(void)func;
	(void)data;
	return NULL;
}

int wl_event_source_timer_update(struct wl_event_source *source, int ms_delay) {
	(void)source;
	(void)ms_delay;
	return 0;
}

int wl_event_source_remove(struct wl_event_source *source) {
	(void)source;
	return 0;
}
