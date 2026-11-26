/* Test-only stubs for the ipc_builders.zig tests.
 *
 * Provides the config/server/layouts data symbols and the acwm helper
 * functions the builders call. cJSON itself is the real library (linked). */
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

uint32_t stub_active_tagset = 0;
uint32_t stub_curtag = 0;
char stub_title[128] = "Title";
char stub_appid[128] = "app";
int stub_is_group_member = 0;
struct Client *stub_group_active = 0;
char stub_layout_str[32] = "us";

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
	return stub_is_group_member != 0;
}

Client *client_group_active(Client *c) {
	(void)c;
	return stub_group_active;
}

const char *ipc_get_layout_str(void) {
	return stub_layout_str;
}
