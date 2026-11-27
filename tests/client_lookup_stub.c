/* Test-only stubs for manage/client_lookup.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/layout/dwindle.h"
#include "acwm/layout/scroll.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"
#include <stddef.h>
#include <string.h>
#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/xwayland.h>

Config config = {0};
struct AcwmServer server = {0};

int32_t stub_descendant = 0;
int32_t is_descendant_process(pid_t p, pid_t c) {
	(void)p;
	(void)c;
	return stub_descendant;
}

struct wlr_surface *client_surface(Client *c) {
	if (!c)
		return NULL;
	if (c->type == X11 && c->surface.xwayland)
		return c->surface.xwayland->surface;
	if (c->surface.xdg)
		return c->surface.xdg->surface;
	return NULL;
}
const char *client_get_appid(Client *c) {
	if (!c || !c->surface.xdg || !c->surface.xdg->toplevel)
		return NULL;
	return c->surface.xdg->toplevel->app_id;
}
const char *client_get_title(Client *c) {
	if (!c || !c->surface.xdg || !c->surface.xdg->toplevel)
		return NULL;
	return c->surface.xdg->toplevel->title;
}
int32_t client_is_unmanaged(Client *c) {
	return c && c->type == X11 && c->surface.xwayland &&
				   c->surface.xwayland->override_redirect
			   ? 1
			   : 0;
}
bool stub_hit_no_border = false;
bool check_hit_no_border(Client *c) {
	(void)c;
	return stub_hit_no_border;
}
bool stub_scroller = false;
bool is_scroller_layout(Monitor *m) {
	(void)m;
	return stub_scroller;
}
struct Client *stub_scroll_head = NULL;
struct Client *stub_scroll_head_b = NULL;
struct Client *stub_scroll_client_b = NULL;
Client *scroll_get_stack_head_client(Client *c) {
	if (stub_scroll_client_b && c == stub_scroll_client_b && stub_scroll_head_b)
		return stub_scroll_head_b;
	return stub_scroll_head ? stub_scroll_head : c;
}
struct DwindleNode *stub_dwindle_sc = NULL;
struct DwindleNode *stub_dwindle_fc = NULL;
Client *stub_dwindle_sc_client = NULL;
Client *stub_dwindle_fc_client = NULL;
DwindleNode *dwindle_find_leaf(DwindleNode *node, Client *c) {
	(void)node;
	if (c == stub_dwindle_sc_client)
		return stub_dwindle_sc;
	if (c == stub_dwindle_fc_client)
		return stub_dwindle_fc;
	return NULL;
}
int32_t regex_match(const char *pattern_mb, const char *str_mb) {
	if (!pattern_mb || !str_mb)
		return 0;
	return strcmp(pattern_mb, str_mb) == 0 ? 1 : 0;
}
uint32_t stub_tag_idx = 0;
uint32_t get_client_tag_idx(const Client *c) {
	(void)c;
	return stub_tag_idx;
}
