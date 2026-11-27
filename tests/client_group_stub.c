/* Test-only stubs for manage/client_group.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/animation/client.h"
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/draw/text-node.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"
#include <stddef.h>
#include <string.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/types/wlr_xdg_shell.h>

Config config = {0};
struct AcwmServer server = {0};

int stub_list_calls = 0;
void wl_list_init(struct wl_list *l) { l->next = l; l->prev = l; }
void wl_list_insert(struct wl_list *l, struct wl_list *e) {
	e->next = e; e->prev = e;
	if (l) { e->next = l->next; e->prev = l; l->next->prev = e; l->next = e; }
	stub_list_calls++;
}
void wl_list_remove(struct wl_list *e) {
	if (e->prev && e->next) { e->prev->next = e->next; e->next->prev = e->prev; }
	e->next = e; e->prev = e;
}
int32_t wl_list_empty(const struct wl_list *l) { return l->next == l; }
int stub_reinsert_prev = 0, stub_reinsert_next = 0;
void wl_list_safe_reinsert_prev(struct wl_list *a, struct wl_list *b) {
	(void)a; (void)b; stub_reinsert_prev++;
}
void wl_list_safe_reinsert_next(struct wl_list *a, struct wl_list *b) {
	(void)a; (void)b; stub_reinsert_next++;
}

uint32_t stub_tag_idx = 0, stub_curtag = 0;
uint32_t get_client_tag_idx(const Client *c) { (void)c; return stub_tag_idx; }
uint32_t get_mon_curtag(const Monitor *m) { (void)m; return stub_curtag; }
int stub_reset_tags = 0;
void client_reset_mon_tags(Client *c, Monitor *m, uint32_t t) {
	(void)m; (void)t; stub_reset_tags++; c->tags = 1;
}
int stub_change_mon_calls = 0;
void client_change_mon(Client *c, Monitor *m) {
	(void)c; (void)m; stub_change_mon_calls++;
}
int stub_focus_calls = 0;
void client_focus(Client *c, int32_t l) { (void)c; (void)l; stub_focus_calls++; }
int stub_replace_calls = 0;
void client_replace(Client *c, Client *w, bool g, bool a) {
	(void)c; (void)w; (void)g; (void)a; stub_replace_calls++;
}
int stub_blur_calls = 0;
void client_sync_blur_optimized(Client *c) { (void)c; stub_blur_calls++; }
int stub_reparent_tab_calls = 0;
void client_reparent_tab(Client *c) { (void)c; stub_reparent_tab_calls++; }
int stub_tab_pen_calls = 0, stub_tab_focus_calls = 0;
void tab_update_input_penetration(Client *c) { (void)c; stub_tab_pen_calls++; }
void tab_focus_member(Client *c) { (void)c; stub_tab_focus_calls++; }
int stub_selected_calls = 0;
void set_selected_monitor(Monitor *m) { (void)m; stub_selected_calls++; }
int stub_arrange_calls = 0;
void arrange(Monitor *m, bool a, bool v) {
	(void)m; (void)a; (void)v; stub_arrange_calls++;
}
int stub_resize_calls = 0;
struct wlr_box stub_resize_geo;
int32_t stub_resize_interact = -1;
void resize(Client *c, struct wlr_box g, ResizeOpts o) {
	(void)c; stub_resize_calls++; stub_resize_geo = g;
	stub_resize_interact = o.interact ? 1 : 0;
}
int stub_dwindle_move_calls = 0;
void dwindle_move_next_to(Client *c, Client *t, float r, int32_t d) {
	(void)c; (void)t; (void)r; (void)d; stub_dwindle_move_calls++;
}
int stub_scroller_insert_calls = 0;
void scroller_insert_stack(Client *c, Client *t, bool b) {
	(void)c; (void)t; (void)b; stub_scroller_insert_calls++;
}
Client *stub_scroll_head = NULL, *stub_scroll_tail = NULL;
Client *scroll_get_stack_head_client(Client *c) {
	(void)c; return stub_scroll_head;
}
Client *scroll_get_stack_tail_client(Client *c) {
	(void)c; return stub_scroll_tail;
}
bool stub_scroller = false, stub_special = false;
bool is_scroller_layout(Monitor *m) { (void)m; return stub_scroller; }
bool is_special_active(const Monitor *m) { (void)m; return stub_special; }
int stub_warp_calls = 0;
void pointer_warp_to_client(const Client *c) { (void)c; stub_warp_calls++; }
int stub_ignore_hits = 0;
bool stub_ignore_value = false;
void acwm_scene_node_set_ignore_hit(struct wlr_scene_node *n, bool i) {
	(void)n; stub_ignore_hits++; stub_ignore_value = i;
}

struct AcwmBarDecoration stub_bar;
struct wlr_scene_tree stub_bar_scene;
int stub_bar_create_calls = 0;
uint32_t stub_bar_type = 0;
bool stub_bar_is_tab = false;
AcwmBarDecoration *acwm_bar_decoration_create(void *cdata, uint32_t type,
											  bool is_tab,
											  struct wlr_scene_tree *parent,
											  DecorateDrawData data, int32_t w,
											  int32_t h) {
	(void)cdata; (void)parent; (void)data; (void)w; (void)h;
	stub_bar_create_calls++; stub_bar_type = type; stub_bar_is_tab = is_tab;
	memset(&stub_bar, 0, sizeof(stub_bar));
	stub_bar.scene = &stub_bar_scene;
	return &stub_bar;
}
int stub_bar_destroy_calls = 0;
void acwm_bar_decoration_destroy(AcwmBarDecoration *b) {
	(void)b; stub_bar_destroy_calls++;
}
int stub_bar_update_calls = 0;
float stub_bar_scale = 0;
void acwm_bar_decoration_update(AcwmBarDecoration *b, const char *t,
								float s) {
	(void)b; (void)t; stub_bar_update_calls++; stub_bar_scale = s;
}
int stub_bar_config_calls = 0;
void acwm_bar_decoration_apply_config(AcwmBarDecoration *b,
									  const DecorateDrawData *d) {
	(void)b; (void)d; stub_bar_config_calls++;
}
int stub_bar_focus_calls = 0;
bool stub_bar_focus_value = false;
void acwm_bar_decoration_set_focus(AcwmBarDecoration *b, bool f) {
	(void)b; stub_bar_focus_calls++; stub_bar_focus_value = f;
}
int stub_bar_close_color_calls = 0;
void acwm_bar_decoration_set_close_color(AcwmBarDecoration *b,
										 const float c[4]) {
	(void)b; (void)c; stub_bar_close_color_calls++;
}
int stub_bar_close_calls = 0;
bool stub_bar_close_show = false;
void acwm_bar_decoration_set_close(AcwmBarDecoration *b, bool s, int32_t z,
								   int32_t m) {
	(void)b; (void)z; (void)m; stub_bar_close_calls++; stub_bar_close_show = s;
}
struct AcwmJumpLabel stub_jump;
struct wlr_scene_tree stub_jump_scene;
int stub_jump_create_calls = 0;
AcwmJumpLabel *acwm_jump_label_node_create(struct wlr_scene_tree *p,
										   DecorateDrawData d) {
	(void)p; (void)d; stub_jump_create_calls++;
	memset(&stub_jump, 0, sizeof(stub_jump));
	stub_jump.scene = &stub_jump_scene;
	return &stub_jump;
}
int stub_jump_config_calls = 0;
void acwm_jump_label_node_apply_config(AcwmJumpLabel *n,
									   const DecorateDrawData *d) {
	(void)n; (void)d; stub_jump_config_calls++;
}
const char *client_get_title(Client *c) { (void)c; return "title"; }
struct wlr_surface *stub_group_surface = NULL;
struct wlr_surface *client_surface(Client *c) {
	(void)c;
	return stub_group_surface;
}
bool client_is_parked(Client *c) { return c && wl_list_empty(&c->link); }
int stub_node_enable_calls = 0;
int stub_node_raise_calls = 0, stub_node_lower_calls = 0;
int stub_node_reparent_calls = 0;
void wlr_scene_node_set_enabled(struct wlr_scene_node *n, bool e) {
	(void)n; (void)e; stub_node_enable_calls++;
}
void wlr_scene_node_raise_to_top(struct wlr_scene_node *n) {
	(void)n; stub_node_raise_calls++;
}
void wlr_scene_node_lower_to_bottom(struct wlr_scene_node *n) {
	(void)n; stub_node_lower_calls++;
}
void wlr_scene_node_reparent(struct wlr_scene_node *n,
							 struct wlr_scene_tree *p) {
	n->parent = p; stub_node_reparent_calls++;
}
int stub_rect_color_calls = 0;
void wlr_scene_rect_set_color(struct wlr_scene_rect *r, const float c[4]) {
	(void)r; (void)c; stub_rect_color_calls++;
}
int stub_kill_calls = 0;
int kill(pid_t p, int s) { (void)p; (void)s; stub_kill_calls++; return 0; }
int stub_frame_done_calls = 0;
void wlr_surface_send_frame_done(struct wlr_surface *s,
								 const struct timespec *t) {
	(void)s; (void)t; stub_frame_done_calls++;
}
int stub_for_each_surface_calls = 0;
void wlr_surface_for_each_surface(struct wlr_surface *s,
								  wlr_surface_iterator_func_t f, void *d) {
	(void)s; stub_for_each_surface_calls++;
	if (f) f(NULL, 0, 0, d);
}
