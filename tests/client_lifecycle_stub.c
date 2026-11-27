/* Test-only stubs for manage/client_lifecycle.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/animation/client.h"
#include "acwm/common/scene_node.h"
#include "acwm/common/server.h"
#include "acwm/common/util.h"
#include "acwm/ipc/ipc.h"
#include "acwm/config/parse.h"
#include "acwm/layout/scroll.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <wlr/types/wlr_ext_foreign_toplevel_list_v1.h>
#include <wlr/types/wlr_foreign_toplevel_management_v1.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/types/wlr_xdg_activation_v1.h>
#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/xwayland.h>

void *ecalloc(size_t nmemb, size_t size) { return calloc(nmemb, size); }

uint32_t get_client_tag_idx(const Client *c) { (void)c; return 0; }

Config config = {0};
struct AcwmServer server = {0};

int stub_list_insert_calls = 0;
int stub_list_remove_calls = 0;
void wl_list_init(struct wl_list *list) {
	list->next = list;
	list->prev = list;
}
void wl_list_insert(struct wl_list *list, struct wl_list *elm) {
	elm->next = elm;
	elm->prev = elm;
	if (list) {
		elm->next = list->next;
		elm->prev = list;
		list->next->prev = elm;
		list->next = elm;
	}
	stub_list_insert_calls++;
}
void wl_list_remove(struct wl_list *elm) {
	if (elm->prev && elm->next) {
		elm->prev->next = elm->next;
		elm->next->prev = elm->prev;
	}
	elm->next = elm;
	elm->prev = elm;
	stub_list_remove_calls++;
}
int32_t wl_list_empty(const struct wl_list *list) {
	return list->next == list;
}

int stub_generate_id_calls = 0;
uint32_t generate_client_id(void) {
	stub_generate_id_calls++;
	return 42;
}
int stub_init_xwayland_calls = 0;
void client_init_xwayland(Client *c) {
	(void)c;
	stub_init_xwayland_calls++;
}
bool stub_unmanaged = false;
bool client_init_unmanaged(Client *c) {
	(void)c;
	return stub_unmanaged;
}
int stub_apply_xwayland_calls = 0;
void client_apply_xwayland(Client *c) {
	(void)c;
	stub_apply_xwayland_calls++;
}
int stub_init_props_calls = 0;
void init_client_properties(Client *c) {
	(void)c;
	stub_init_props_calls++;
}
int stub_apply_rules_calls = 0;
void client_apply_rules(Client *c, Monitor **rule_mon, uint32_t *rule_tags) {
	(void)c;
	stub_apply_rules_calls++;
	if (rule_mon)
		*rule_mon = NULL;
	if (rule_tags)
		*rule_tags = 0;
}
int stub_insert_tiling_calls = 0;
void client_insert_tiling_order(Client *c) { (void)c; stub_insert_tiling_calls++; }
int stub_negotiate_calls = 0;
void client_negotiate_initial_size(Client *c, Monitor *m, uint32_t tags) {
	(void)c;
	(void)m;
	(void)tags;
	stub_negotiate_calls++;
}
int stub_set_monitor_calls = 0;
void client_set_monitor(Client *c, Monitor *m, uint32_t tags, bool focus) {
	(void)c;
	(void)m;
	(void)tags;
	(void)focus;
	stub_set_monitor_calls++;
}
int stub_scale_calls = 0;
void client_set_scale(struct wlr_surface *s, float scale) {
	(void)s;
	(void)scale;
	stub_scale_calls++;
}
int stub_set_tiled_calls = 0;
uint32_t stub_tiled_edges = 0;
void client_set_tiled(Client *c, uint32_t edges) {
	(void)c;
	stub_set_tiled_calls++;
	stub_tiled_edges = edges;
}
int stub_border_color_calls = 0;
void client_update_border_color(Client *c) {
	(void)c;
	stub_border_color_calls++;
}
int stub_group_bar_add = 0, stub_group_bar_remove = 0;
int stub_tab_bar_add = 0, stub_tab_bar_remove = 0;
void client_add_group_bar(Client *c) { (void)c; stub_group_bar_add++; }
void client_remove_group_bar(Client *c) { (void)c; stub_group_bar_remove++; }
void client_add_tab_bar(Client *c) { (void)c; stub_tab_bar_add++; }
void client_remove_tab_bar(Client *c) { (void)c; stub_tab_bar_remove++; }
int stub_group_title_calls = 0, stub_tab_title_calls = 0;
void client_update_group_bar_title(Client *c) { (void)c; stub_group_title_calls++; }
void client_update_tab_bar_title(Client *c) { (void)c; stub_tab_title_calls++; }
int stub_jump_add = 0, stub_jump_destroy = 0;
int stub_dim_add = 0, stub_dim_destroy = 0;
void client_add_jump_label_node(Client *c) { (void)c; stub_jump_add++; }
void client_add_dim_node(Client *c) { (void)c; stub_dim_add++; }
void acwm_jump_label_node_destroy(AcwmJumpLabel *n) { (void)n; stub_jump_destroy++; }
void acwm_dim_node_destroy(AcwmDimNode *n) { (void)n; stub_dim_destroy++; }
bool stub_parked = false;
bool client_is_parked(Client *c) { (void)c; return stub_parked; }
bool stub_group_member = false;
bool client_is_group_member(const Client *c) { (void)c; return stub_group_member; }
int stub_group_detach_calls = 0;
void client_group_detach(Client *c) { (void)c; stub_group_detach_calls++; }
int stub_replace_calls = 0;
void client_replace(Client *c, Client *w, bool g, bool a) {
	(void)c; (void)w; (void)g; (void)a; stub_replace_calls++;
}
int stub_maximize_screen_calls = 0;
void client_set_maximize_screen(Client *c, int32_t m, bool r) {
	(void)c; (void)m; (void)r; stub_maximize_screen_calls++;
}
int stub_fullscreen_calls = 0;
int32_t stub_fullscreen_value = -1;
void client_apply_fullscreen(Client *c, int32_t f, bool r) {
	(void)c; (void)r; stub_fullscreen_calls++; stub_fullscreen_value = f;
}
int stub_minimize_client_calls = 0;
int stub_unminimize_calls = 0;
int stub_set_minimized_calls = 0;
void set_minimized(Client *c) { (void)c; stub_minimize_client_calls++; }
void unminimize(Client *c) { (void)c; stub_unminimize_calls++; }
void client_set_minimized(Client *c, bool m) { (void)c; (void)m; stub_set_minimized_calls++; }
int stub_resize_calls = 0;
void resize(Client *c, struct wlr_box geo, ResizeOpts opts) {
	(void)c; (void)geo; (void)opts; stub_resize_calls++;
}
int stub_focus_calls = 0;
void client_focus(Client *c, int32_t lift) { (void)c; (void)lift; stub_focus_calls++; }
Client *stub_top_client = NULL;
Client *client_focus_top(Monitor *m) { (void)m; return stub_top_client; }
int stub_view_calls = 0;
void client_view_on_monitor(const Arg *arg, bool a, Monitor *m, bool r) {
	(void)arg; (void)a; (void)m; (void)r; stub_view_calls++;
}
struct wlr_surface *stub_surface = NULL;
struct wlr_surface *client_surface(Client *c) { (void)c; return stub_surface; }
struct wlr_box stub_geom;
void client_get_geometry(Client *c, struct wlr_box *g) { (void)c; *g = stub_geom; }
const char *stub_appid = "app";
const char *stub_title = "title";
const char *client_get_appid(Client *c) { (void)c; return stub_appid; }
const char *client_get_title(Client *c) { (void)c; return stub_title; }
int32_t stub_x11 = 0;
int32_t client_is_x11(Client *c) { (void)c; return stub_x11; }
int32_t stub_unmanaged_flag = 0;
int32_t client_is_unmanaged(Client *c) { (void)c; return stub_unmanaged_flag; }
int32_t stub_x11_popup = 0;
int32_t client_is_x11_popup(Client *c) { (void)c; return stub_x11_popup; }
int32_t stub_should_global = 0;
int32_t client_should_global(Client *c) { (void)c; return stub_should_global; }
int32_t stub_wants_fs = 0;
int32_t client_wants_fullscreen(Client *c) { (void)c; return stub_wants_fs; }
bool stub_request_max = false;
bool client_request_maximize(Client *c, void *d) { (void)c; (void)d; return stub_request_max; }
bool stub_request_min = false;
bool client_request_minimize(Client *c, void *d) { (void)c; (void)d; return stub_request_min; }
int stub_send_close_calls = 0;
void client_send_close(Client *c) { (void)c; stub_send_close_calls++; }
Client *stub_toplevel_client = NULL;
int32_t toplevel_from_wlr_surface(struct wlr_surface *s, Client **pc,
								  LayerSurface **pl) {
	(void)s; if (pc) *pc = stub_toplevel_client; if (pl) *pl = NULL;
	return stub_toplevel_client ? XDGShell : -1;
}
int stub_tab_detach_calls = 0;
void tab_detach_client(Client *c) { (void)c; stub_tab_detach_calls++; }
int stub_switcher_remove_calls = 0;
void switcher_remove_client(Client *c) { (void)c; stub_switcher_remove_calls++; }
struct ScrollerStackNode *stub_scroller_node = NULL;
ScrollerStackNode *find_scroller_node(struct TagScrollerState *st, Client *c) {
	(void)st; (void)c; return stub_scroller_node;
}
int stub_scroller_remove_calls = 0;
void scroller_remove_client(Client *c) { (void)c; stub_scroller_remove_calls++; }
int stub_dwindle_remove_calls = 0;
void dwindle_remove_client(Client *c) { (void)c; stub_dwindle_remove_calls++; }
int stub_drop_area_calls = 0;
void client_set_drop_area(Client *c) { (void)c; stub_drop_area_calls++; }
int stub_pointer_destroyed_calls = 0;
void pointer_client_destroyed(Client *c) { (void)c; stub_pointer_destroyed_calls++; }
int stub_pointer_motion_calls = 0;
void pointer_process_motion(uint32_t t, struct wlr_input_device *d, double a,
							double b, double c, double e) {
	(void)t; (void)d; (void)a; (void)b; (void)c; (void)e;
	stub_pointer_motion_calls++;
}
int stub_toggle_overview_calls = 0;
int32_t toggle_overview(const Arg *arg) { (void)arg; stub_toggle_overview_calls++; return 0; }
int stub_fadeout_calls = 0;
void init_fadeout_client(Client *c) { (void)c; stub_fadeout_calls++; }
int stub_backup_surface_calls = 0;
void overview_backup_surface(Client *c) { (void)c; stub_backup_surface_calls++; }
int stub_iter_buffers_calls = 0;
void iter_xdg_scene_buffers(struct wlr_scene_buffer *b, int32_t sx, int32_t sy,
							void *d) { (void)b; (void)sx; (void)sy; (void)d; stub_iter_buffers_calls++; }
const char *wayland_string_set(struct wayland_string *dst, const char *src) {
	(void)dst; return src ? src : "";
}
int stub_deco_request_calls = 0;
void handle_xdg_decoration_mode_request(struct wl_listener *l, void *d) {
	(void)l; (void)d; stub_deco_request_calls++;
}
int stub_xwayland_scale_calls = 0;
void xwayland_apply_scale(Client *c) { (void)c; stub_xwayland_scale_calls++; }
int stub_printstatus_calls = 0;
void printstatus(enum ipc_watch_type t) { (void)t; stub_printstatus_calls++; }

struct wlr_scene_tree stub_trees[16];
int stub_tree_next = 0;
struct wlr_scene_tree *wlr_scene_tree_create(struct wlr_scene_tree *p) {
	(void)p; struct wlr_scene_tree *t = &stub_trees[stub_tree_next++];
	memset(t, 0, sizeof(*t)); return t;
}
struct wlr_scene_tree *wlr_scene_xdg_surface_create(struct wlr_scene_tree *p,
													struct wlr_xdg_surface *x) {
	(void)p; (void)x; return wlr_scene_tree_create(NULL);
}
struct wlr_scene_tree *wlr_scene_subsurface_tree_create(
	struct wlr_scene_tree *p, struct wlr_surface *s) {
	(void)p; (void)s; return wlr_scene_tree_create(NULL);
}
struct wlr_scene stub_scene;
struct wlr_scene *wlr_scene_create(void) { return &stub_scene; }
struct wlr_scene_rect stub_rects[12];
int stub_rect_next = 0;
int stub_rect_calls = 0;
struct wlr_scene_rect *wlr_scene_rect_create(struct wlr_scene_tree *p, int w,
											 int h, const float color[4]) {
	(void)p; (void)w; (void)h; (void)color;
	stub_rect_calls++;
	return &stub_rects[stub_rect_next++];
}
struct wlr_scene_shadow stub_shadow;
int stub_shadow_calls = 0;
struct wlr_scene_shadow *wlr_scene_shadow_create(
	struct wlr_scene_tree *p, int w, int h, int cr, float bs,
	const float color[4]) {
	(void)p; (void)w; (void)h; (void)cr; (void)bs; (void)color;
	stub_shadow_calls++; return &stub_shadow;
}
struct wlr_scene_blur stub_blur;
struct wlr_scene_blur *wlr_scene_blur_create(struct wlr_scene_tree *p, int w,
											 int h) {
	(void)p; (void)w; (void)h; return &stub_blur;
}
struct wlr_scene_surface stub_scene_surface;
struct wlr_scene_surface *wlr_scene_surface_create(struct wlr_scene_tree *p,
												   struct wlr_surface *s) {
	(void)p; (void)s; return &stub_scene_surface;
}
int stub_node_enable_calls = 0;
int stub_node_pos_calls = 0;
int stub_node_destroy_calls = 0;
void wlr_scene_node_set_enabled(struct wlr_scene_node *n, bool e) {
	(void)n; (void)e; stub_node_enable_calls++;
}
void wlr_scene_node_set_position(struct wlr_scene_node *n, int32_t x, int32_t y) {
	(void)n; (void)x; (void)y; stub_node_pos_calls++;
}
void wlr_scene_node_lower_to_bottom(struct wlr_scene_node *n) { (void)n; }
void wlr_scene_node_destroy(struct wlr_scene_node *n) { (void)n; stub_node_destroy_calls++; }
void wlr_scene_rect_set_corner_radii(struct wlr_scene_rect *r,
									 struct fx_corner_radii c) { (void)r; (void)c; }
int stub_for_each_calls = 0;
void wlr_scene_node_for_each_buffer(struct wlr_scene_node *n,
									wlr_scene_buffer_iterator_func_t f,
									void *d) {
	(void)n; (void)f; (void)d; stub_for_each_calls++;
}
AcwmSceneNode *acwm_scene_node_set(struct wlr_scene_node *n, uint32_t t,
								   void *o) {
	(void)n; (void)t; (void)o; return NULL;
}
struct wlr_ext_foreign_toplevel_handle_v1 stub_ext_handle;
struct wlr_ext_foreign_toplevel_handle_v1 *
wlr_ext_foreign_toplevel_handle_v1_create(
	struct wlr_ext_foreign_toplevel_list_v1 *l,
	const struct wlr_ext_foreign_toplevel_handle_v1_state *s) {
	(void)l; (void)s; return &stub_ext_handle;
}
void wlr_ext_foreign_toplevel_handle_v1_destroy(
	struct wlr_ext_foreign_toplevel_handle_v1 *h) { (void)h; }
void wlr_ext_foreign_toplevel_handle_v1_update_state(
	struct wlr_ext_foreign_toplevel_handle_v1 *h,
	const struct wlr_ext_foreign_toplevel_handle_v1_state *s) {
	(void)h; (void)s;
}
int stub_ft_set_title_calls = 0;
void wlr_foreign_toplevel_handle_v1_set_title(
	struct wlr_foreign_toplevel_handle_v1 *h, const char *t) {
	(void)h; (void)t; stub_ft_set_title_calls++;
}
void wlr_foreign_toplevel_handle_v1_destroy(
	struct wlr_foreign_toplevel_handle_v1 *h) { (void)h; }
uint32_t stub_schedule_serial = 5;
uint32_t wlr_xdg_surface_schedule_configure(struct wlr_xdg_surface *x) {
	(void)x; return stub_schedule_serial;
}
int stub_wm_caps_calls = 0;
uint32_t stub_wm_caps = 0;
uint32_t wlr_xdg_toplevel_set_wm_capabilities(
	struct wlr_xdg_toplevel *t, uint32_t c) {
	(void)t; stub_wm_caps_calls++; stub_wm_caps = c; return 0;
}
int stub_bounds_calls = 0;
uint32_t wlr_xdg_toplevel_set_bounds(struct wlr_xdg_toplevel *t, int32_t w,
									 int32_t h) {
	(void)t; (void)w; (void)h; stub_bounds_calls++; return 0;
}
