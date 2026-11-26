/* Test-only stubs for arrange_resize.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/layout/arrange.h"
#include "acwm/layout/scroll.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"

#include <wlr/types/wlr_cursor.h>

Config config = {0};
struct AcwmServer server = {0};
struct wlr_cursor stub_cursor = {0};
struct TagScrollerState stub_scroller_state = {0};

int stub_curtag = 0;
int stub_client_tag = 0;
int stub_arrange_calls = 0;
int stub_dwindle_calls = 0;
int stub_dwindle_step_calls = 0;
int stub_last_dx = 0;
int stub_last_dy = 0;
int stub_sync_calls = 0;

uint32_t get_mon_curtag(const Monitor *m) {
	(void)m;
	return (uint32_t)stub_curtag;
}

uint32_t get_client_tag_idx(const Client *c) {
	(void)c;
	return (uint32_t)stub_client_tag;
}

void arrange(Monitor *m, bool want_animation, bool from_view) {
	(void)m;
	(void)want_animation;
	(void)from_view;
	stub_arrange_calls++;
}

void dwindle_resize_client(Monitor *m, Client *c) {
	(void)m;
	(void)c;
	stub_dwindle_calls++;
}

void dwindle_resize_client_step(Monitor *m, Client *c, int32_t dx, int32_t dy) {
	(void)m;
	(void)c;
	stub_dwindle_step_calls++;
	stub_last_dx = dx;
	stub_last_dy = dy;
}

struct ScrollerStackNode *find_scroller_node(struct TagScrollerState *st,
											 Client *c) {
	if (!st)
		return NULL;
	for (struct ScrollerStackNode *n = st->all_first; n; n = n->all_next)
		if (n->client == c)
			return n;
	return NULL;
}

void sync_scroller_state_to_clients(Monitor *m, uint32_t tag) {
	(void)m;
	(void)tag;
	stub_sync_calls++;
}

struct ScrollerStackNode *stub_node_new(struct TagScrollerState *st, Client *c,
										float prop, float stack_prop) {
	struct ScrollerStackNode *n = calloc(1, sizeof(*n));
	n->client = c;
	n->scroller_proportion = prop;
	n->scroller_stack_proportion = stack_prop;
	n->scroller_stack_weight = stack_prop;
	n->all_next = st->all_first;
	st->all_first = n;
	st->count++;
	return n;
}

void stub_node_link(struct ScrollerStackNode *a, struct ScrollerStackNode *b) {
	a->next_in_stack = b;
	b->prev_in_stack = a;
}
