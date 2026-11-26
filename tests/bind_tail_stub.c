/* Test-only stubs for bind_tail.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/dispatch/bind.h"
#include "acwm/layout/dwindle.h"
#include "acwm/layout/layout.h"
#include "acwm/layout/scroll.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"

Config config = {0};
struct AcwmServer server = {0};
struct TagScrollerState stub_state;
struct ScrollerStackNode stub_node_c;
struct ScrollerStackNode stub_node_t;
Client *stub_c_client = NULL;
Client *stub_t_client = NULL;
DwindleNode *stub_leaf = NULL;
Client *stub_direction_client = NULL;
bool stub_is_scroller = false;
bool stub_hit_noborder = false;
struct ivec2 stub_offsets = {1, 2};

int stub_enabled_calls = 0;
bool stub_enabled_arg = false;
int stub_commit_calls = 0;
int stub_layout_change_calls = 0;
int stub_match_calls = 0;
int stub_remove_calls = 0;
int stub_update_calls = 0;
int stub_insert_stack_calls = 0;
Client *stub_insert_stack_client = NULL;
Client *stub_insert_stack_target = NULL;
bool stub_insert_stack_before = true;
int stub_sync_calls = 0;
int stub_reinsert_prev_calls = 0;
int stub_reinsert_next_calls = 0;
int stub_set_size_calls = 0;
int stub_floating_calls = 0;
int32_t stub_floating_arg = 0;
int stub_raise_group_calls = 0;
int stub_raise_tab_calls = 0;
int stub_arrange_calls = 0;
int stub_draw_border_calls = 0;
int stub_reload_calls = 0;

bool acwm_output_commit(Monitor *m) {
	(void)m;
	stub_commit_calls++;
	return true;
}
void wlr_output_state_set_enabled(struct wlr_output_state *state, bool enabled) {
	(void)state;
	stub_enabled_calls++;
	stub_enabled_arg = enabled;
}
void handle_output_layout_change(struct wl_listener *listener, void *data) {
	(void)listener;
	(void)data;
	stub_layout_change_calls++;
}
bool match_monitor_spec(char *spec, Monitor *m) {
	(void)spec;
	(void)m;
	stub_match_calls++;
	return true;
}
bool is_scroller_layout(Monitor *m) {
	(void)m;
	return stub_is_scroller;
}
uint32_t get_client_tag_idx(const Client *c) {
	(void)c;
	return 0;
}
struct TagScrollerState *ensure_scroller_state(Monitor *m, uint32_t tag) {
	(void)m;
	(void)tag;
	return &stub_state;
}
struct ScrollerStackNode *find_scroller_node(struct TagScrollerState *st,
											 Client *c) {
	(void)st;
	if (c == stub_c_client)
		return &stub_node_c;
	if (c == stub_t_client)
		return &stub_node_t;
	return NULL;
}
void scroller_node_remove(struct TagScrollerState *st,
						  struct ScrollerStackNode *target) {
	(void)st;
	(void)target;
	stub_remove_calls++;
}
void update_scroller_state(Monitor *m) {
	(void)m;
	stub_update_calls++;
}
Client *scroll_get_stack_head_client(Client *c) {
	return c ? c : stub_c_client;
}
Client *scroll_get_stack_tail_client(Client *c) {
	return c ? c : stub_t_client;
}
void scroller_insert_stack(Client *c, Client *target, bool before) {
	stub_insert_stack_calls++;
	stub_insert_stack_client = c;
	stub_insert_stack_target = target;
	stub_insert_stack_before = before;
}
void sync_scroller_state_to_clients(Monitor *m, uint32_t tag) {
	(void)m;
	(void)tag;
	stub_sync_calls++;
}
void wl_list_safe_reinsert_prev(struct wl_list *l1, struct wl_list *l2) {
	(void)l1;
	(void)l2;
	stub_reinsert_prev_calls++;
}
void wl_list_safe_reinsert_next(struct wl_list *l1, struct wl_list *l2) {
	(void)l1;
	(void)l2;
	stub_reinsert_next_calls++;
}
Client *find_client_by_direction(Client *tc, const Arg *arg, bool findfloating) {
	(void)tc;
	(void)arg;
	(void)findfloating;
	return stub_direction_client;
}
void set_size_per(Monitor *m, Client *c, bool reset) {
	(void)m;
	(void)c;
	(void)reset;
	stub_set_size_calls++;
}
void client_set_floating(Client *c, int32_t floating) {
	(void)c;
	stub_floating_calls++;
	stub_floating_arg = floating;
}
void client_raise_group(Client *c) {
	(void)c;
	stub_raise_group_calls++;
}
void client_raise_tab(Client *c) {
	(void)c;
	stub_raise_tab_calls++;
}
void arrange(Monitor *m, bool want_animation, bool from_view) {
	(void)m;
	(void)want_animation;
	(void)from_view;
	stub_arrange_calls++;
}
DwindleNode *dwindle_find_leaf(DwindleNode *node, Client *c) {
	(void)node;
	(void)c;
	return stub_leaf;
}
bool check_hit_no_border(Client *c) {
	(void)c;
	return stub_hit_noborder;
}
struct ivec2 compute_edge_offsets(Client *c) {
	(void)c;
	return stub_offsets;
}
void client_draw_split_border(Client *c, bool hit_no_border,
							  struct ivec2 offsets) {
	(void)c;
	(void)hit_no_border;
	(void)offsets;
	stub_draw_border_calls++;
}
int32_t reload_config(const Arg *arg) {
	(void)arg;
	stub_reload_calls++;
	return 0;
}
