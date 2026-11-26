/* Test-only stubs for dwindle.zig.
 *
 * Provides config/server, the monitor/client lookups, layout side effects
 * (arrange, tile resize, drag/jump/swap helpers) and wl_list_swap. The tile
 * resize recorder also answers predict probes. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/layout/arrange.h"
#include "acwm/layout/dwindle.h"
#include "acwm/layout/layout.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"

#include <wlr/types/wlr_cursor.h>

Config config = {0};
struct AcwmServer server = {0};
struct wlr_cursor stub_cursor = {0};

Client *stub_focus_top = NULL;
Monitor *stub_direction_monitor = NULL;
bool stub_jump_result = true;

int stub_arrange_calls = 0;
int stub_tile_calls = 0;
struct wlr_box stub_tile_boxes[256];
Client *stub_tile_clients[256];
int stub_jump_calls = 0;
int stub_swap_props_calls = 0;
int stub_swap_monitors_calls = 0;
int stub_finish_calls = 0;

uint32_t get_mon_curtag(const Monitor *m) {
	(void)m;
	return 0;
}

Client *client_focus_top(Monitor *m) {
	(void)m;
	return stub_focus_top;
}

void client_tile_resize(Client *c, struct wlr_box geo, int32_t interact,
						const LayoutContext *ctx) {
	(void)interact;
	if (ctx && ctx->probe) {
		if (c == ctx->probe && ctx->out)
			*ctx->out = geo;
		return;
	}
	if (stub_tile_calls < 256) {
		stub_tile_boxes[stub_tile_calls] = geo;
		stub_tile_clients[stub_tile_calls] = c;
		stub_tile_calls++;
	}
}

bool client_jump_to_monitor(Client *c, Monitor *m, int32_t dir) {
	(void)c;
	(void)m;
	(void)dir;
	stub_jump_calls++;
	return stub_jump_result;
}

Monitor *monitor_from_direction(enum wlr_direction dir) {
	(void)dir;
	return stub_direction_monitor;
}

void client_swap_layout_properties(Client *c1, Client *c2) {
	(void)c1;
	(void)c2;
	stub_swap_props_calls++;
}

void client_swap_monitors_and_tags(Client *c1, Client *c2) {
	(void)c1;
	(void)c2;
	stub_swap_monitors_calls++;
}

void finish_exchange_arrange_and_focus(Client *c1, Client *c2, Monitor *m1,
									   Monitor *m2) {
	(void)c1;
	(void)c2;
	(void)m1;
	(void)m2;
	stub_finish_calls++;
}

void arrange(Monitor *m, bool want_animation, bool from_view) {
	(void)m;
	(void)want_animation;
	(void)from_view;
	stub_arrange_calls++;
}

void wl_list_swap(struct wl_list *l1, struct wl_list *l2) {
	if (l1 == l2)
		return;
	struct wl_list *tmp1_prev = l1->prev;
	struct wl_list *tmp2_prev = l2->prev;
	struct wl_list *tmp1_next = l1->next;
	struct wl_list *tmp2_next = l2->next;

	if (l1->next == l2) {
		l1->next = l2->next;
		l1->prev = l2;
		l2->next = l1;
		l2->prev = tmp1_prev;
		tmp1_prev->next = l2;
		tmp2_next->prev = l1;
	} else if (l2->next == l1) {
		l2->next = l1->next;
		l2->prev = l1;
		l1->next = l2;
		l1->prev = tmp2_prev;
		tmp2_prev->next = l1;
		tmp1_next->prev = l2;
	} else {
		l1->prev = tmp2_prev;
		l1->next = tmp2_next;
		l2->prev = tmp1_prev;
		l2->next = tmp1_next;
		tmp2_prev->next = l1;
		tmp2_next->prev = l1;
		tmp1_prev->next = l2;
		tmp1_next->prev = l2;
	}
}
