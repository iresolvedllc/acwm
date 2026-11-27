/* Test-only stubs for manage/client_rules.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/animation/client.h"
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/xwayland.h>

Config config = {0};
struct AcwmServer server = {0};

bool stub_x11 = false;
int32_t client_is_x11(Client *c) {
	(void)c;
	return stub_x11;
}
int32_t stub_float_type = 0;
int32_t client_is_float_type(Client *c) {
	(void)c;
	return stub_float_type;
}
int stub_update_geometry_calls = 0;
void client_update_geometry(Client *c) {
	(void)c;
	stub_update_geometry_calls++;
}
struct wlr_surface *client_surface(Client *c) {
	if (!c)
		return NULL;
	if (stub_x11 && c->surface.xwayland)
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
int32_t stub_pid = 0;
int32_t client_get_pid(Client *c) {
	(void)c;
	return stub_pid;
}
Client *stub_parent = NULL;
Client *client_get_parent(Client *c) {
	(void)c;
	return stub_parent;
}
bool is_window_rule_matches(const ConfigWinRule *r, const char *appid,
							const char *title) {
	bool title_match = r->title && strcmp(r->title, title) == 0;
	bool id_match = r->id && strcmp(r->id, appid) == 0;
	return (title_match && !r->id) || (id_match && !r->title) ||
		   (id_match && title_match);
}
bool match_monitor_spec(char *spec, Monitor *m) {
	if (!spec || !m || !m->wlr_output || !m->wlr_output->name)
		return false;
	return strcmp(spec, m->wlr_output->name) == 0;
}
struct wlr_box stub_center_box;
int stub_center_calls = 0;
struct wlr_box client_center_geometry(Client *c, Monitor *tm,
									  struct wlr_box geom, int32_t offsetx,
									  int32_t offsety) {
	(void)c;
	(void)tm;
	(void)geom;
	(void)offsetx;
	(void)offsety;
	stub_center_calls++;
	return stub_center_box;
}
int stub_size_bound_calls = 0;
void client_set_size_bound(Client *c) {
	(void)c;
	stub_size_bound_calls++;
}
Client *stub_terminal = NULL;
Client *client_find_terminal(Client *w) {
	(void)w;
	return stub_terminal;
}
int stub_replace_calls = 0;
void client_replace(Client *c, Client *w, bool is_group_change_member,
					bool apply_rule) {
	(void)c;
	(void)w;
	(void)is_group_change_member;
	(void)apply_rule;
	stub_replace_calls++;
}
int stub_set_monitor_calls = 0;
Monitor *stub_set_monitor_m = NULL;
uint32_t stub_set_monitor_tags = 0;
bool stub_set_monitor_focus = false;
void client_set_monitor(Client *c, Monitor *m, uint32_t newtags, bool focus) {
	(void)c;
	stub_set_monitor_calls++;
	stub_set_monitor_m = m;
	stub_set_monitor_tags = newtags;
	stub_set_monitor_focus = focus;
}
int stub_reparent_group_calls = 0;
void client_reparent_group(Client *c) {
	(void)c;
	stub_reparent_group_calls++;
}
int stub_view_on_monitor_calls = 0;
uint32_t stub_view_tags = 0;
bool stub_view_from_rule = false;
void client_view_on_monitor(const Arg *arg, bool want_animation, Monitor *m,
							bool from_rule) {
	(void)want_animation;
	(void)m;
	stub_view_on_monitor_calls++;
	stub_view_tags = arg->ui;
	stub_view_from_rule = from_rule;
}
int stub_apply_fullscreen_calls = 0;
int32_t stub_apply_fullscreen_state = -1;
void client_apply_fullscreen(Client *c, int32_t fullscreen, bool rearrange) {
	(void)c;
	(void)rearrange;
	stub_apply_fullscreen_calls++;
	stub_apply_fullscreen_state = fullscreen;
}
int stub_fake_fullscreen_calls = 0;
void client_set_fake_fullscreen(Client *c, int32_t fakefullscreen) {
	(void)c;
	(void)fakefullscreen;
	stub_fake_fullscreen_calls++;
}
int stub_clear_fullscreen_calls = 0;
void clear_fullscreen_flag(Client *c) {
	(void)c;
	stub_clear_fullscreen_calls++;
}
int stub_named_scratchpad_calls = 0;
void apply_named_scratchpad(Client *c) {
	(void)c;
	stub_named_scratchpad_calls++;
}
uint32_t stub_target_layer = 5;
uint32_t client_target_layer(Client *c) {
	(void)c;
	return stub_target_layer;
}
int32_t stub_wants_fullscreen = 0;
int32_t client_wants_fullscreen(Client *c) {
	(void)c;
	return stub_wants_fullscreen;
}
bool stub_special = false;
bool is_special_active(const Monitor *m) {
	(void)m;
	return stub_special;
}
uint32_t get_tags_first_tag_num(uint32_t tags) {
	uint32_t i = 0;
	while (i < 32 && (tags & (1u << i)) == 0)
		i++;
	return i + 1;
}
int stub_size_per_calls = 0;
void set_size_per(Monitor *m, Client *c, bool reset_proportion) {
	(void)m;
	(void)c;
	(void)reset_proportion;
	stub_size_per_calls++;
}
int stub_arrange_calls = 0;
void arrange(Monitor *m, bool want_animation, bool from_view) {
	(void)m;
	(void)want_animation;
	(void)from_view;
	stub_arrange_calls++;
}
int stub_resize_calls = 0;
struct wlr_box stub_resize_geo;
void resize(Client *c, struct wlr_box geo, ResizeOpts opts) {
	(void)c;
	(void)opts;
	stub_resize_calls++;
	stub_resize_geo = geo;
}
int stub_reinsert_calls = 0;
void wl_list_safe_reinsert_prev(struct wl_list *l1, struct wl_list *l2) {
	(void)l1;
	(void)l2;
	stub_reinsert_calls++;
}
int stub_reparent_calls = 0;
struct wlr_scene_tree *stub_reparent_parent = NULL;
void wlr_scene_node_reparent(struct wlr_scene_node *node,
							 struct wlr_scene_tree *parent) {
	node->parent = parent;
	stub_reparent_calls++;
	stub_reparent_parent = parent;
}
int32_t stub_x11_popup = 0;
int32_t client_is_x11_popup(Client *c) {
	(void)c;
	return stub_x11_popup;
}
int32_t stub_ignore_focus = 0;
int32_t client_should_ignore_focus(Client *c) {
	(void)c;
	return stub_ignore_focus;
}
