/* Test-only stubs for the ipc_watch.zig tests.
 *
 * Provides the config/server/layouts data, the shared watch list symbols,
 * the helper functions the notifiers call, and the unported pieces
 * (build_all_clients_array, ipc_device_type_str, ext-workspace printstatus).
 * Sockets and cJSON are real. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/ipc/ipc.h"
#include "acwm/layout/layout.h"

#include <stdbool.h>
#include <stdint.h>

Config config = {0};
struct AcwmServer server = {0};
Layout layouts[14] = {0};

struct wl_list ipc_watch_clients;
int ipc_device_watch_count = 0;

uint32_t stub_active_tagset = 0;
uint32_t stub_curtag = 0;
char stub_title[128] = "Title";
char stub_appid[128] = "app";
char stub_layout_str[32] = "us";
int stub_workspace_printstatus_calls = 0;

uint32_t get_monitor_active_tagset(Monitor *m) {
	(void)m;
	return stub_active_tagset;
}

uint32_t get_mon_curtag(Monitor *m) {
	(void)m;
	return stub_curtag;
}

const char *client_get_title(Client *c) {
	(void)c;
	return stub_title;
}

const char *client_get_appid(Client *c) {
	(void)c;
	return stub_appid;
}

bool client_is_group_member(const Client *c) {
	(void)c;
	return false;
}

Client *client_group_active(Client *c) {
	(void)c;
	return NULL;
}

const char *ipc_get_layout_str(void) {
	return stub_layout_str;
}

const char *ipc_device_type_str(struct wlr_input_device *dev) {
	(void)dev;
	return "pointer";
}

cJSON *build_all_clients_array(void) {
	return cJSON_CreateArray();
}

void acwm_ext_workspace_printstatus(Monitor *m) {
	(void)m;
	stub_workspace_printstatus_calls++;
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
	(void)fmt;
}

void acwm_error_untagged(unsigned verbosity, const char *fmt, ...) {
	(void)verbosity;
	(void)fmt;
}
