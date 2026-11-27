/* Test-only stubs for ipc_server.zig tests.
 *
 * Complements tests/ipc_watch_stub.c (which owns the data symbols and the
 * builder helpers) with the lookups, socket helpers and dispatcher stubs the
 * command layer calls. cJSON, sockets and the real builders stay real. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/ipc/ipc.h"
#include "acwm/manage/monitor.h"
#include "acwm/manage/client.h"

#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <wayland-server-core.h>

int stub_static_json_calls = 0;
char stub_last_static_json[512] = {0};
Client *stub_focus_top = NULL;
Monitor *stub_monitor_at_point = NULL;

int stub_parse_calls = 0;
int stub_parse_enabled = 0;
char stub_tokens[6][128] = {{0}};
Arg *stub_parse_arg = NULL;

int stub_dispatch_calls = 0;
Client *stub_dispatch_client = NULL;

int32_t focus_by_id(const Arg *arg) {
	(void)arg;
	return 0;
}

static int32_t stub_dispatch_impl(const Arg *arg) {
	stub_dispatch_calls++;
	stub_dispatch_client = arg ? arg->tc : NULL;
	return 0;
}

void send_static_json(int fd, const char *json_str) {
	stub_static_json_calls++;
	snprintf(stub_last_static_json, sizeof(stub_last_static_json), "%s",
			 json_str);
	ssize_t msg_len = (ssize_t)strlen(json_str);
	ssize_t n = send(fd, json_str, msg_len, 0);
	(void)n;
}

Monitor *monitor_by_name(const char *name) {
	if (!name)
		return NULL;
	Monitor *m;
	wl_list_for_each(m, &server.monitors, link) {
		if (strcmp(m->wlr_output->name, name) == 0)
			return m;
	}
	return NULL;
}

Client *client_by_id(uint32_t id) {
	Client *c;
	wl_list_for_each(c, &server.clients, link) {
		if (c->id == id)
			return c;
	}
	return NULL;
}

Client *client_by_id_all(uint32_t id) {
	return client_by_id(id);
}

Client *client_focus_top(Monitor *m) {
	(void)m;
	return stub_focus_top;
}

Monitor *monitor_at_point(double x, double y) {
	(void)x;
	(void)y;
	return stub_monitor_at_point;
}

ConfigDeviceRule *find_device_rule(struct wlr_input_device *dev) {
	(void)dev;
	return NULL;
}

FuncType parse_func_name(char *func_name, Arg *arg, char *arg_value,
						 char *arg_value2, char *arg_value3, char *arg_value4,
						 char *arg_value5) {
	stub_parse_calls++;
	const char *src[6] = {func_name, arg_value, arg_value2,
						  arg_value3, arg_value4, arg_value5};
	for (int i = 0; i < 6; i++) {
		if (src[i])
			snprintf(stub_tokens[i], sizeof(stub_tokens[i]), "%s", src[i]);
		else
			stub_tokens[i][0] = '\0';
	}
	stub_parse_arg = arg;
	return stub_parse_enabled ? stub_dispatch_impl : NULL;
}

struct wl_event_source *wl_event_loop_add_fd(struct wl_event_loop *loop,
											 int fd, uint32_t mask,
											 wl_event_loop_fd_func_t func,
											 void *data) {
	(void)loop;
	(void)fd;
	(void)mask;
	(void)func;
	(void)data;
	return (struct wl_event_source *)1;
}
