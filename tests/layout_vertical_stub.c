/* Test-only stubs for vertical.zig layout tests.
 *
 * Provides the config/server globals plus the still-C helpers the layout
 * cores call: tag lookup, popup classification, visibility updates and
 * client_tile_resize. The resize stub records boxes (or, in predict mode,
 * answers the probe) so tests can assert the exact geometry. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/layout/layout.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"

Config config = {0};
struct AcwmServer server = {0};

int stub_curtag = 0;
uint32_t get_mon_curtag(const Monitor *m) {
	(void)m;
	return (uint32_t)stub_curtag;
}

int32_t stub_popup = 0;
int32_t client_is_x11_popup(Client *c) {
	(void)c;
	return stub_popup;
}

int stub_tile_calls = 0;
struct wlr_box stub_tile_boxes[128];
Client *stub_tile_clients[128];

void client_tile_resize(Client *c, struct wlr_box geo, int32_t interact,
						const LayoutContext *ctx) {
	(void)interact;
	if (ctx && ctx->probe) {
		if (c == ctx->probe && ctx->out)
			*ctx->out = geo;
		return;
	}
	if (stub_tile_calls < 128) {
		stub_tile_boxes[stub_tile_calls] = geo;
		stub_tile_clients[stub_tile_calls] = c;
		stub_tile_calls++;
	}
}

int stub_visibility_calls = 0;
void client_update_visibility(Client *c) {
	(void)c;
	stub_visibility_calls++;
}
