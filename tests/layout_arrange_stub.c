/* Test-only stubs for the arrange hub.
 *
 * Provides config/server, every layout entry point (recorded, no geometry),
 * the arrange visibility/animation hooks, tag-rule hooks and special-view
 * predicates. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/ipc/ipc.h"
#include "acwm/layout/arrange.h"
#include "acwm/layout/layout.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"

Config config = {0};
struct AcwmServer server = {0};

int stub_curtag = 0;
int stub_set_size_calls = 0;
int stub_visible_calls = 0;
int stub_hidden_calls = 0;
int stub_sync_layer_calls = 0;
int stub_focus_calls = 0;
int stub_update_vis_calls = 0;
int stub_resetmax_calls = 0;
int stub_tab_sync_calls = 0;
int stub_special_sync_calls = 0;
bool stub_special_sync_arg = false;
int stub_pointer_calls = 0;
int stub_idle_calls = 0;
int stub_printstatus_calls = 0;
int stub_tag_defaults_calls = 0;
int stub_rule_matches_calls = 0;
int stub_rule_apply_calls = 0;
int stub_layout_calls = 0;
int stub_layout_gappoh = 0;
int stub_overview_calls = 0;
int stub_focus_top_calls = 0;
int stub_check_tab_visible_calls = 0;
int stub_update_scroller_calls = 0;

bool stub_special_active = false;
bool stub_special_has_clients = false;
bool stub_only_one_tag = false;
int stub_toggle_calls = 0;
Client *stub_focus_top = NULL;

uint32_t get_mon_curtag(const Monitor *m) {
	(void)m;
	return (uint32_t)stub_curtag;
}

void set_size_per(Monitor *m, Client *c, bool reset) {
	(void)m;
	(void)c;
	(void)reset;
	stub_set_size_calls++;
}

void update_scroller_state(Monitor *m) {
	(void)m;
	stub_update_scroller_calls++;
}

struct ScrollerStackNode *find_scroller_node(struct TagScrollerState *st,
											 Client *c) {
	(void)st;
	(void)c;
	return NULL;
}

void client_check_tab_node_visible(Client *c) {
	(void)c;
	stub_check_tab_visible_calls++;
}

void client_focus(Client *c, int32_t lift) {
	(void)c;
	(void)lift;
	stub_focus_calls++;
}

Client *client_focus_top(Monitor *m) {
	(void)m;
	stub_focus_top_calls++;
	return stub_focus_top;
}

bool client_only_in_one_tag(Client *c) {
	(void)c;
	return stub_only_one_tag;
}

void client_update_visibility(Client *c) {
	(void)c;
	stub_update_vis_calls++;
}

void client_sync_layer(Client *c) {
	(void)c;
	stub_sync_layer_calls++;
}

void reset_maximizescreen_size(Client *c) {
	(void)c;
	stub_resetmax_calls++;
}

void set_arrange_visible(Monitor *m, Client *c, bool want_animation) {
	(void)m;
	(void)c;
	(void)want_animation;
	stub_visible_calls++;
}

void set_arrange_hidden(Monitor *m, Client *c, bool want_animation) {
	(void)m;
	(void)c;
	(void)want_animation;
	stub_hidden_calls++;
}

void special_update_dim(Monitor *m) {
	(void)m;
}

bool is_special_active(const Monitor *m) {
	(void)m;
	return stub_special_active;
}

bool special_has_clients(const Monitor *m) {
	(void)m;
	return stub_special_has_clients;
}

void toggle_special_tag_mon(Monitor *m) {
	(void)m;
	stub_toggle_calls++;
}

void tab_sync_monitor(Monitor *m) {
	(void)m;
	stub_tab_sync_calls++;
}

void special_sync_top_layer(bool special_active) {
	stub_special_sync_calls++;
	stub_special_sync_arg = special_active;
}

void pointer_process_motion(uint32_t time, struct wlr_input_device *device,
							double dx, double dy, double dx_unaccel,
							double dy_unaccel) {
	(void)time;
	(void)device;
	(void)dx;
	(void)dy;
	(void)dx_unaccel;
	(void)dy_unaccel;
	stub_pointer_calls++;
}

void check_idle_inhibitor(struct wlr_surface *exclude) {
	(void)exclude;
	stub_idle_calls++;
}

void printstatus(enum ipc_watch_type type) {
	(void)type;
	stub_printstatus_calls++;
}

void tag_slot_set_defaults(Monitor *m, uint32_t tag) {
	(void)m;
	(void)tag;
	stub_tag_defaults_calls++;
}

bool tag_rule_matches_monitor(const ConfigTagRule *tr, Monitor *m) {
	(void)tr;
	(void)m;
	stub_rule_matches_calls++;
	return true;
}

void tag_rule_apply_to_slot(Monitor *m, const ConfigTagRule *tr, uint32_t tag) {
	(void)m;
	(void)tr;
	(void)tag;
	stub_rule_apply_calls++;
}

static void record_layout(Monitor *m) {
	stub_layout_calls++;
	stub_layout_gappoh = m->gappoh;
}

void tile(Monitor *m) { record_layout(m); }
void scroller(Monitor *m) { record_layout(m); }
void grid(Monitor *m) { record_layout(m); }
void monocle(Monitor *m) { record_layout(m); }
void deck(Monitor *m) { record_layout(m); }
void center_tile(Monitor *m) { record_layout(m); }
void right_tile(Monitor *m) { record_layout(m); }
void vertical_scroller(Monitor *m) { record_layout(m); }
void vertical_tile(Monitor *m) { record_layout(m); }
void vertical_grid(Monitor *m) { record_layout(m); }
void vertical_deck(Monitor *m) { record_layout(m); }
void dwindle(Monitor *m) { record_layout(m); }
void fair(Monitor *m) { record_layout(m); }
void vertical_fair(Monitor *m) { record_layout(m); }
void overview(Monitor *m) {
	(void)m;
	stub_overview_calls++;
}

bool tile_predict(Monitor *m, Client *c, struct wlr_box *out) { (void)m; (void)c; (void)out; return false; }
bool scroller_predict(Monitor *m, Client *c, struct wlr_box *out) { (void)m; (void)c; (void)out; return false; }
bool grid_predict(Monitor *m, Client *c, struct wlr_box *out) { (void)m; (void)c; (void)out; return false; }
bool monocle_predict(Monitor *m, Client *c, struct wlr_box *out) { (void)m; (void)c; (void)out; return false; }
bool deck_predict(Monitor *m, Client *c, struct wlr_box *out) { (void)m; (void)c; (void)out; return false; }
bool center_tile_predict(Monitor *m, Client *c, struct wlr_box *out) { (void)m; (void)c; (void)out; return false; }
bool right_tile_predict(Monitor *m, Client *c, struct wlr_box *out) { (void)m; (void)c; (void)out; return false; }
bool vertical_scroller_predict(Monitor *m, Client *c, struct wlr_box *out) { (void)m; (void)c; (void)out; return false; }
bool vertical_tile_predict(Monitor *m, Client *c, struct wlr_box *out) { (void)m; (void)c; (void)out; return false; }
bool vertical_grid_predict(Monitor *m, Client *c, struct wlr_box *out) { (void)m; (void)c; (void)out; return false; }
bool vertical_deck_predict(Monitor *m, Client *c, struct wlr_box *out) { (void)m; (void)c; (void)out; return false; }
bool dwindle_predict(Monitor *m, Client *c, struct wlr_box *out) { (void)m; (void)c; (void)out; return false; }
bool fair_predict(Monitor *m, Client *c, struct wlr_box *out) { (void)m; (void)c; (void)out; return false; }
bool vertical_fair_predict(Monitor *m, Client *c, struct wlr_box *out) { (void)m; (void)c; (void)out; return false; }
