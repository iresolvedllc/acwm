/* Test-only stubs for animation/tag.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/animation/client.h"
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"

Config config = {0};
struct AcwmServer server = {0};

bool stub_animations_enabled = true;
int stub_update_vis_calls = 0;
int stub_resize_calls = 0;
struct wlr_box stub_resize_geom;
bool stub_resize_skip_ov = false;
bool stub_is_scroller = false;

bool client_animations_enabled(const Client *c) {
	(void)c;
	return stub_animations_enabled;
}
void client_update_visibility(Client *c) {
	(void)c;
	stub_update_vis_calls++;
}
void resize(Client *c, struct wlr_box geo, ResizeOpts opts) {
	(void)c;
	stub_resize_calls++;
	stub_resize_geom = geo;
	stub_resize_skip_ov = opts.skip_ov_enter_anim;
}
bool is_scroller_layout(Monitor *m) {
	(void)m;
	return stub_is_scroller;
}
bool wlr_box_equal(const struct wlr_box *a, const struct wlr_box *b) {
	return a->x == b->x && a->y == b->y && a->width == b->width &&
		   a->height == b->height;
}
