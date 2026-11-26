/* Test-only stubs for bind_layout.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/animation/client.h"
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/dispatch/bind.h"
#include "acwm/ipc/ipc.h"
#include "acwm/layout/layout.h"
#include "acwm/layout/scroll.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"

#include <wlr/types/wlr_cursor.h>

Config config = {0};
struct AcwmServer server = {0};
struct wlr_cursor stub_cursor = {0};

static void stub_layout_fn(Monitor *m) { (void)m; }

Layout layouts[14] = {
	{"T", stub_layout_fn, NULL, "tile", 0},
	{"S", stub_layout_fn, NULL, "scroller", 1},
	{"G", stub_layout_fn, NULL, "grid", 2},
	{"M", stub_layout_fn, NULL, "monocle", 3},
	{"K", stub_layout_fn, NULL, "deck", 4},
	{"CT", stub_layout_fn, NULL, "center_tile", 5},
	{"RT", stub_layout_fn, NULL, "right_tile", 6},
	{"VS", stub_layout_fn, NULL, "vertical_scroller", 7},
	{"VT", stub_layout_fn, NULL, "vertical_tile", 8},
	{"VG", stub_layout_fn, NULL, "vertical_grid", 9},
	{"VK", stub_layout_fn, NULL, "vertical_deck", 10},
	{"DW", stub_layout_fn, NULL, "dwindle", 11},
	{"F", stub_layout_fn, NULL, "fair", 12},
	{"VF", stub_layout_fn, NULL, "vertical_fair", 13},
};

float stub_presets[4] = {0.4f, 0.6f, 0.8f, 0.0f};
struct ScrollerStackNode stub_node;
Client *stub_head_client = NULL;
Client *stub_node_client = NULL;
Client *stub_focus_top = NULL;
Client *stub_bar_client = NULL;
bool stub_is_scroller = false;
bool stub_node_found = false;
bool stub_bar_enabled = false;
AcwmBarDecoration stub_bar;

int stub_setgaps_calls = 0;
int32_t stub_gap_oh, stub_gap_ov, stub_gap_ih, stub_gap_iv;
int stub_arrange_calls = 0;
int stub_printstatus_calls = 0;
int stub_clear_fs_calls = 0;
int stub_force_kill_calls = 0;
int stub_kill_calls = 0;
int stub_move_resize_calls = 0;
Client *stub_move_resize_client = NULL;
uint32_t stub_move_resize_mode = 0;
int stub_display_term_calls = 0;
int stub_floating_calls = 0;
int32_t stub_floating_arg = 0;
int stub_resize_calls = 0;
int stub_resize_tile_calls = 0;
int32_t stub_resize_tile_dx = 0;
int32_t stub_resize_tile_dy = 0;
int stub_pending_min_calls = 0;
int32_t stub_pending_min_arg = -1;
int stub_border_color_calls = 0;
int stub_focus_calls = 0;
Client *stub_focus_client = NULL;
int stub_warp_calls = 0;

void setgaps(int32_t oh, int32_t ov, int32_t ih, int32_t iv) {
	stub_setgaps_calls++;
	stub_gap_oh = oh;
	stub_gap_ov = ov;
	stub_gap_ih = ih;
	stub_gap_iv = iv;
}
uint32_t get_mon_curtag(const Monitor *m) {
	(void)m;
	return 0;
}
void arrange(Monitor *m, bool want_animation, bool from_view) {
	(void)m;
	(void)want_animation;
	(void)from_view;
	stub_arrange_calls++;
}
void printstatus(enum ipc_watch_type type) {
	(void)type;
	stub_printstatus_calls++;
}
void clear_fullscreen_and_maximized_state(Monitor *m) {
	(void)m;
	stub_clear_fs_calls++;
}
void client_pending_force_kill(Client *c) {
	(void)c;
	stub_force_kill_calls++;
}
void pending_kill_client(Client *c) {
	(void)c;
	stub_kill_calls++;
}
bool pointer_begin_move_resize(Client *gc, uint32_t mode, double x, double y,
							   uint32_t edge) {
	(void)x;
	(void)y;
	(void)edge;
	stub_move_resize_calls++;
	stub_move_resize_client = gc;
	stub_move_resize_mode = mode;
	return true;
}
void node_at_point(double x, double y, struct wlr_surface **psurface,
				   Client **pc, LayerSurface **pl, AcwmBarDecoration **bar,
				   double *nx, double *ny) {
	(void)x;
	(void)y;
	(void)pl;
	(void)nx;
	(void)ny;
	if (psurface)
		*psurface = NULL;
	if (pc)
		*pc = stub_node_client;
	if (bar)
		*bar = stub_bar_enabled ? &stub_bar : NULL;
}
void wl_display_terminate(struct wl_display *display) {
	(void)display;
	stub_display_term_calls++;
}
void client_set_floating(Client *c, int32_t floating) {
	(void)c;
	stub_floating_calls++;
	stub_floating_arg = floating;
}
void resize(Client *c, struct wlr_box geo, ResizeOpts opts) {
	(void)c;
	(void)geo;
	(void)opts;
	stub_resize_calls++;
}
void resize_tile_client(Client *gc, bool isdrag, int32_t offsetx,
						int32_t offsety, uint32_t time) {
	(void)gc;
	(void)isdrag;
	(void)time;
	stub_resize_tile_calls++;
	stub_resize_tile_dx = offsetx;
	stub_resize_tile_dy = offsety;
}
void client_pending_minimized_state(Client *c, int32_t minimized) {
	(void)c;
	stub_pending_min_calls++;
	stub_pending_min_arg = minimized;
}
void client_update_border_color(Client *c) {
	(void)c;
	stub_border_color_calls++;
}
void client_focus(Client *c, int32_t lift) {
	(void)lift;
	stub_focus_calls++;
	stub_focus_client = c;
}
Client *client_focus_top(Monitor *m) {
	(void)m;
	return stub_focus_top;
}
void pointer_warp_to_client(Client *c) {
	(void)c;
	stub_warp_calls++;
}
bool is_scroller_layout(Monitor *m) {
	(void)m;
	return stub_is_scroller;
}
Client *scroll_get_stack_head_client(Client *c) {
	if (stub_head_client)
		return stub_head_client;
	return c;
}
struct ScrollerStackNode *find_scroller_node(struct TagScrollerState *st,
											 Client *c) {
	(void)st;
	(void)c;
	return stub_node_found ? &stub_node : NULL;
}
