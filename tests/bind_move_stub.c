/* Test-only stubs for bind_move.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/animation/client.h"
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/dispatch/bind.h"
#include "acwm/ipc/ipc.h"
#include "acwm/layout/layout.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"

#include <sys/types.h>
#include <unistd.h>

Config config = {0};
struct AcwmServer server = {0};

Layout layouts[14] = {
	{"T", NULL, NULL, "tile", 0},
	{"S", NULL, NULL, "scroller", 1},
	{"G", NULL, NULL, "grid", 2},
	{"M", NULL, NULL, "monocle", 3},
	{"K", NULL, NULL, "deck", 4},
	{"CT", NULL, NULL, "center_tile", 5},
	{"RT", NULL, NULL, "right_tile", 6},
	{"VS", NULL, NULL, "vertical_scroller", 7},
	{"VT", NULL, NULL, "vertical_tile", 8},
	{"VG", NULL, NULL, "vertical_grid", 9},
	{"VK", NULL, NULL, "vertical_deck", 10},
	{"DW", NULL, NULL, "dwindle", 11},
	{"F", NULL, NULL, "fair", 12},
	{"VF", NULL, NULL, "vertical_fair", 13},
};

char *stub_circle[4] = {"grid", "monocle", "tile", "deck"};
struct wlr_box stub_center_box = {11, 22, 333, 444};
Client *stub_head_client = NULL;
bool stub_is_scroller = false;
uint32_t stub_token_calls = 0;
int stub_fork_calls = 0;
int stub_floating_calls = 0;
int32_t stub_floating_arg = 0;
int stub_resize_calls = 0;
struct wlr_box stub_resize_box;
int stub_arrange_calls = 0;
int stub_clear_fs_calls = 0;
int stub_printstatus_calls = 0;
int stub_switch_view_calls = 0;
uint32_t stub_switch_view_ui = 0;

uint32_t get_mon_curtag(const Monitor *m) {
	(void)m;
	return 0;
}
void client_set_floating(Client *c, int32_t floating) {
	(void)c;
	stub_floating_calls++;
	stub_floating_arg = floating;
}
void resize(Client *c, struct wlr_box geo, ResizeOpts opts) {
	(void)c;
	(void)opts;
	stub_resize_calls++;
	stub_resize_box = geo;
}
struct wlr_box client_center_geometry(Client *c, Monitor *m, struct wlr_box geom,
									  int32_t ox, int32_t oy) {
	(void)c;
	(void)m;
	(void)geom;
	(void)ox;
	(void)oy;
	return stub_center_box;
}
bool is_scroller_layout(Monitor *m) {
	(void)m;
	return stub_is_scroller;
}
Client *scroll_get_stack_head_client(Client *c) {
	return stub_head_client ? stub_head_client : c;
}
void arrange(Monitor *m, bool want_animation, bool from_view) {
	(void)m;
	(void)want_animation;
	(void)from_view;
	stub_arrange_calls++;
}
void clear_fullscreen_and_maximized_state(Monitor *m) {
	(void)m;
	stub_clear_fs_calls++;
}
void printstatus(enum ipc_watch_type type) {
	(void)type;
	stub_printstatus_calls++;
}
void client_switch_view(const Arg *arg, bool animate) {
	(void)animate;
	stub_switch_view_calls++;
	stub_switch_view_ui = arg->ui;
}
const char *xdg_activation_v1_export_token(void) {
	stub_token_calls++;
	return NULL;
}
void acwm_error_impl(bool log, unsigned verbosity, const char *file, int line,
					 const char *fmt, ...) {
	(void)log;
	(void)verbosity;
	(void)file;
	(void)line;
	(void)fmt;
}
pid_t fork(void) {
	stub_fork_calls++;
	return 12345;
}
