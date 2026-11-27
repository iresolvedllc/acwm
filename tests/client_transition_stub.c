/* Test-only stubs for manage/client_transition.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/animation/client.h"
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/ipc/ipc.h"
#include "acwm/layout/dwindle.h"
#include "acwm/layout/scroll.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"
#include "acwm/manage/tab.h"
#include <stddef.h>
#include <string.h>
#include <wlr/types/wlr_foreign_toplevel_management_v1.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/types/wlr_xdg_shell.h>

Config config = {0};
struct AcwmServer server = {0};

int stub_list_insert_calls = 0;
int stub_list_remove_calls = 0;
int stub_list_swap_calls = 0;
int stub_reinsert_next_calls = 0;
int stub_reinsert_prev_calls = 0;
void wl_list_init(struct wl_list *l) { l->next = l; l->prev = l; }
void wl_list_insert(struct wl_list *l, struct wl_list *e) {
	e->next = e; e->prev = e;
	if (l) { e->next = l->next; e->prev = l; l->next->prev = e; l->next = e; }
	stub_list_insert_calls++;
}
void wl_list_remove(struct wl_list *e) {
	if (e->prev && e->next) { e->prev->next = e->next; e->next->prev = e->prev; }
	e->next = e; e->prev = e; stub_list_remove_calls++;
}
int32_t wl_list_empty(const struct wl_list *l) { return l->next == l; }
void wl_list_swap(struct wl_list *a, struct wl_list *b) {
	struct wl_list t = *a; *a = *b; *b = t;
	stub_list_swap_calls++;
}
void wl_list_safe_reinsert_next(struct wl_list *l1, struct wl_list *l2) {
	(void)l1; (void)l2; stub_reinsert_next_calls++;
}
void wl_list_safe_reinsert_prev(struct wl_list *l1, struct wl_list *l2) {
	(void)l1; (void)l2; stub_reinsert_prev_calls++;
}

struct wlr_surface stub_surface;
struct wlr_surface *client_surface(Client *c) {
	(void)c; return &stub_surface;
}
int32_t stub_x11 = 0;
int32_t client_is_x11(Client *c) { (void)c; return stub_x11; }
int stub_set_fs_calls = 0;
int32_t stub_set_fs_value = -1;
void client_set_fullscreen(Client *c, int32_t f) {
	(void)c; stub_set_fs_calls++; stub_set_fs_value = f;
}
int stub_set_max_calls = 0;
bool stub_set_max_value = false;
void client_set_maximized(Client *c, bool m) {
	(void)c; stub_set_max_calls++; stub_set_max_value = m;
}
int stub_tiled_hint_calls = 0;
void client_sync_tiled_hint(Client *c) { (void)c; stub_tiled_hint_calls++; }
int stub_visibility_calls = 0;
void client_update_visibility(Client *c) { (void)c; stub_visibility_calls++; }
int stub_reparent_group_calls = 0;
void client_reparent_group(Client *c) { (void)c; stub_reparent_group_calls++; }
int stub_group_replace_calls = 0;
void client_group_replace(Client *o, Client *n) {
	(void)o; (void)n; stub_group_replace_calls++;
}
int stub_oldmonname_calls = 0;
void client_update_oldmonname_record(Client *c, Monitor *m) {
	(void)c; (void)m; stub_oldmonname_calls++;
}
bool stub_group_bar = false;
bool client_wants_group_bar(Client *c) { (void)c; return stub_group_bar; }
int stub_swap_props_calls = 0;
void client_swap_layout_properties(Client *a, Client *b) {
	(void)a; (void)b; stub_swap_props_calls++;
}
int stub_swap_mon_calls = 0;
void client_swap_monitors_and_tags(Client *a, Client *b) {
	(void)a; (void)b; stub_swap_mon_calls++;
}
int stub_finish_exchange_calls = 0;
void finish_exchange_arrange_and_focus(Client *a, Client *b, Monitor *m1,
									   Monitor *m2) {
	(void)a; (void)b; (void)m1; (void)m2; stub_finish_exchange_calls++;
}
int stub_exchange_scroller_calls = 0;
void exchange_two_scroller_clients(Client *a, Client *b) {
	(void)a; (void)b; stub_exchange_scroller_calls++;
}
int stub_exchange_dwindle_calls = 0;
void dwindle_swap_clients(Client *a, Client *b) {
	(void)a; (void)b; stub_exchange_dwindle_calls++;
}
int stub_dwindle_remove_calls = 0;
void dwindle_remove(DwindleNode **root, Client *c) {
	(void)root; (void)c; stub_dwindle_remove_calls++;
}
struct DwindleNode *stub_dwindle_leaf = NULL;
DwindleNode *dwindle_find_leaf(DwindleNode *n, Client *c) {
	(void)n; (void)c; return stub_dwindle_leaf;
}
int stub_sync_scroller_calls = 0;
void sync_scroller_state_to_clients(Monitor *m, uint32_t t) {
	(void)m; (void)t; stub_sync_scroller_calls++;
}
struct ScrollerStackNode *stub_scroller_node = NULL;
ScrollerStackNode *find_scroller_node(struct TagScrollerState *st, Client *c) {
	(void)st; (void)c; return stub_scroller_node;
}
int stub_scroller_remove_calls = 0;
void scroller_node_remove(struct TagScrollerState *st,
						  struct ScrollerStackNode *n) {
	(void)st; (void)n; stub_scroller_remove_calls++;
}
int stub_tab_detach_calls = 0;
void tab_detach_client(Client *c) { (void)c; stub_tab_detach_calls++; }
int stub_tab_replace_calls = 0;
void tab_replace_client(Client *o, Client *n) {
	(void)o; (void)n; stub_tab_replace_calls++;
}
int stub_show_hide_calls = 0;
void show_hide_client(Client *c) { (void)c; stub_show_hide_calls++; }
int stub_add_foreign_calls = 0;
void add_foreign_toplevel(Client *c) { (void)c; stub_add_foreign_calls++; }
int stub_overview_destroy_calls = 0;
void overview_destroy_card(Client *c) { (void)c; stub_overview_destroy_calls++; }
int stub_overview_backup_calls = 0;
void overview_backup_surface(Client *c) { (void)c; stub_overview_backup_calls++; }
int stub_reset_foreign_calls = 0;
void reset_foreign_tolevel(Client *c, Monitor *o, Monitor *n) {
	(void)c; (void)o; (void)n; stub_reset_foreign_calls++;
}
struct wlr_box stub_center_box;
bool stub_center_passthrough = false;
int stub_center_calls = 0;
struct wlr_box client_center_geometry(Client *c, Monitor *m,
									  struct wlr_box g, int32_t x, int32_t y) {
	(void)c; (void)m; (void)x; (void)y;
	stub_center_calls++;
	return stub_center_passthrough ? g : stub_center_box;
}
uint32_t stub_tag_idx = 0;
uint32_t get_client_tag_idx(const Client *c) { (void)c; return stub_tag_idx; }
uint32_t stub_first_tag = 1;
uint32_t get_tags_first_tag(uint32_t t) { (void)t; return stub_first_tag; }
bool stub_scroller_layout = false, stub_monocle_layout = false;
bool is_scroller_layout(Monitor *m) { (void)m; return stub_scroller_layout; }
bool is_monocle_layout(Monitor *m) { (void)m; return stub_monocle_layout; }
int stub_size_per_calls = 0;
void set_size_per(Monitor *m, Client *c, bool r) {
	(void)m; (void)c; (void)r; stub_size_per_calls++;
}
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
int stub_focus_calls = 0;
void client_focus(Client *c, int32_t l) { (void)c; (void)l; stub_focus_calls++; }
Client *stub_top_client = NULL;
Client *client_focus_top(Monitor *m) { (void)m; return stub_top_client; }
int stub_vrr_calls = 0, stub_idle_calls = 0;
void check_vrr_enable(Client *c) { (void)c; stub_vrr_calls++; }
void check_keep_idle_inhibit(Client *c) { (void)c; stub_idle_calls++; }
struct AcwmDimNode stub_dim;
struct AcwmDimNode *acwm_dim_node_create(struct wlr_scene_tree *p,
										 const float color[4]) {
	(void)p; (void)color; return &stub_dim;
}
int stub_dim_enable_calls = 0;
void acwm_dim_node_set_enabled(AcwmDimNode *n, bool e) {
	(void)n; (void)e; stub_dim_enable_calls++;
}
int stub_state_colors_calls = 0;
void client_set_state_colors(Client *c, const float b[4], const float d[4]) {
	(void)c; (void)b; (void)d; stub_state_colors_calls++;
}
float stub_border[4] = {1, 0, 0, 1};
float *get_border_color(Client *c) { (void)c; return stub_border; }
float stub_dimc[4] = {0, 0, 0, 0.5};
float *get_dim_color(Client *c) { (void)c; return stub_dimc; }
int stub_printstatus_calls = 0;
void printstatus(enum ipc_watch_type t) { (void)t; stub_printstatus_calls++; }
int stub_ft_full_calls = 0, stub_ft_max_calls = 0, stub_ft_min_calls = 0;
int stub_ft_activate_calls = 0;
void wlr_foreign_toplevel_handle_v1_set_fullscreen(
	struct wlr_foreign_toplevel_handle_v1 *h, bool v) {
	(void)h; (void)v; stub_ft_full_calls++;
}
void wlr_foreign_toplevel_handle_v1_set_maximized(
	struct wlr_foreign_toplevel_handle_v1 *h, bool v) {
	(void)h; (void)v; stub_ft_max_calls++;
}
void wlr_foreign_toplevel_handle_v1_set_minimized(
	struct wlr_foreign_toplevel_handle_v1 *h, bool v) {
	(void)h; (void)v; stub_ft_min_calls++;
}
void wlr_foreign_toplevel_handle_v1_set_activated(
	struct wlr_foreign_toplevel_handle_v1 *h, bool v) {
	(void)h; (void)v; stub_ft_activate_calls++;
}
void wlr_foreign_toplevel_handle_v1_output_leave(
	struct wlr_foreign_toplevel_handle_v1 *h, struct wlr_output *o) {
	(void)h; (void)o;
}
void wlr_foreign_toplevel_handle_v1_output_enter(
	struct wlr_foreign_toplevel_handle_v1 *h, struct wlr_output *o) {
	(void)h; (void)o;
}
void wlr_foreign_toplevel_handle_v1_destroy(
	struct wlr_foreign_toplevel_handle_v1 *h) { (void)h; }
int stub_node_enable_calls = 0;
void wlr_scene_node_set_enabled(struct wlr_scene_node *n, bool e) {
	(void)n; (void)e; stub_node_enable_calls++;
}
int stub_bar_focus_calls = 0;
void acwm_bar_decoration_set_focus(AcwmBarDecoration *b, bool f) {
	(void)b; (void)f; stub_bar_focus_calls++;
}
