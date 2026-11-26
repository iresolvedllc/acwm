/* Test-only stubs for scroll.zig.
 *
 * Provides config/server, monitor/client lookups and the layout side effects
 * the scroller state machine calls. client_tile_resize records the box and
 * mirrors real resize by updating c->geom, which later stack placements read.
 */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/layout/layout.h"
#include "acwm/layout/scroll.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"

Config config = {0};
struct AcwmServer server = {0};

int stub_curtag = 0;
int stub_client_tag = 0;
int stub_tile_calls = 0;
struct wlr_box stub_tile_boxes[512];
Client *stub_tile_clients[512];
int stub_floating_calls = 0;
int stub_fullscreen_calls = 0;
int stub_maximize_calls = 0;
int stub_arrange_calls = 0;
int stub_swap_props_calls = 0;
int stub_swap_monitors_calls = 0;
int stub_finish_calls = 0;
bool stub_group_bar = false;

uint32_t get_mon_curtag(const Monitor *m) {
	(void)m;
	return (uint32_t)stub_curtag;
}

uint32_t get_client_tag_idx(const Client *c) {
	(void)c;
	return (uint32_t)stub_client_tag;
}

void client_tile_resize(Client *c, struct wlr_box geo, int32_t interact,
						const LayoutContext *ctx) {
	(void)interact;
	if (ctx && ctx->probe) {
		if (c == ctx->probe && ctx->out)
			*ctx->out = geo;
		return;
	}
	if (stub_tile_calls < 512) {
		stub_tile_boxes[stub_tile_calls] = geo;
		stub_tile_clients[stub_tile_calls] = c;
		stub_tile_calls++;
	}
	c->geom = geo;
}

void client_set_floating(Client *c, int32_t floating) {
	(void)c;
	(void)floating;
	stub_floating_calls++;
}

void client_apply_fullscreen(Client *c, int32_t fullscreen, bool rearrange) {
	(void)c;
	(void)fullscreen;
	(void)rearrange;
	stub_fullscreen_calls++;
}

void client_set_maximize_screen(Client *c, int32_t max, bool rearrange) {
	(void)c;
	(void)max;
	(void)rearrange;
	stub_maximize_calls++;
}

bool client_wants_group_bar(Client *c) {
	(void)c;
	return stub_group_bar;
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

static void stub_list_init(struct wl_list *l) {
	l->prev = l;
	l->next = l;
}

static void stub_list_insert(struct wl_list *prev, struct wl_list *el) {
	el->prev = prev;
	el->next = prev->next;
	prev->next->prev = el;
	prev->next = el;
}

static void stub_list_remove(struct wl_list *el) {
	el->prev->next = el->next;
	el->next->prev = el->prev;
	el->next = NULL;
	el->prev = NULL;
}

void wl_list_safe_reinsert_prev(struct wl_list *l1, struct wl_list *l2) {
	if (!l1 || !l2 || l1 == l2 || l1->prev == l2)
		return;
	stub_list_remove(l2);
	stub_list_init(l2);
	stub_list_insert(l1->prev, l2);
}

void wl_list_safe_reinsert_next(struct wl_list *l1, struct wl_list *l2) {
	if (!l1 || !l2 || l1 == l2 || l1->next == l2)
		return;
	stub_list_remove(l2);
	stub_list_init(l2);
	stub_list_insert(l1, l2);
}
