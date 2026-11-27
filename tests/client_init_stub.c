/* Test-only stubs for manage/client_init.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/scene_node.h"
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/layout/arrange.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"
#include "acwm/overview/overview.h"
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/xwayland.h>

Config config = {0};
struct AcwmServer server = {0};

void *ecalloc(size_t nmemb, size_t size) { return calloc(nmemb, size); }

void handle_client_commit(struct wl_listener *listener, void *data) {
	(void)listener;
	(void)data;
}
void handle_client_map(struct wl_listener *listener, void *data) {
	(void)listener;
	(void)data;
}
void handle_client_unmap(struct wl_listener *listener, void *data) {
	(void)listener;
	(void)data;
}
void handle_client_destroy(struct wl_listener *listener, void *data) {
	(void)listener;
	(void)data;
}
void handle_client_request_fullscreen(struct wl_listener *listener,
									  void *data) {
	(void)listener;
	(void)data;
}
void handle_client_request_maximize(struct wl_listener *listener,
									void *data) {
	(void)listener;
	(void)data;
}
void handle_client_request_minimize(struct wl_listener *listener,
									void *data) {
	(void)listener;
	(void)data;
}
void handle_client_set_title(struct wl_listener *listener, void *data) {
	(void)listener;
	(void)data;
}
int stub_list_insert_calls = 0;
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
}

bool stub_unmanaged = false;
int32_t client_is_unmanaged(Client *c) {
	(void)c;
	return stub_unmanaged ? 1 : 0;
}
int stub_xwayland_scale_calls = 0;
void xwayland_apply_scale(Client *c) {
	(void)c;
	stub_xwayland_scale_calls++;
}
int stub_fix_coord_calls = 0;
void fix_xwayland_coordinate(struct wlr_box *box) {
	(void)box;
	stub_fix_coord_calls++;
}
int stub_logical_to_x11_calls = 0;
struct wlr_box stub_logical_x11;
void xwayland_logical_to_x11(struct wlr_box *box, float scale) {
	(void)scale;
	stub_logical_to_x11_calls++;
	*box = stub_logical_x11;
}
int stub_dest_size_calls = 0;
void client_update_xwayland_dest_size(Client *c) {
	(void)c;
	stub_dest_size_calls++;
}
int stub_set_geometry_listener_calls = 0;
void handle_xwayland_surface_set_geometry(struct wl_listener *listener,
										  void *data) {
	(void)listener;
	(void)data;
	stub_set_geometry_listener_calls++;
}
int stub_x11_commit_listener_calls = 0;
void handle_xwayland_surface_commit(struct wl_listener *listener, void *data) {
	(void)listener;
	(void)data;
	stub_x11_commit_listener_calls++;
}
int stub_focus_calls = 0;
void client_focus(Client *c, int32_t lift) {
	(void)c;
	(void)lift;
	stub_focus_calls++;
}
int32_t stub_wants_focus = 0;
int32_t client_wants_focus(Client *c) {
	(void)c;
	return stub_wants_focus;
}
struct wlr_surface *stub_surface = NULL;
struct wlr_surface *client_surface(Client *c) {
	(void)c;
	return stub_surface;
}
struct wlr_box stub_geom;
int stub_get_geometry_calls = 0;
void client_get_geometry(Client *c, struct wlr_box *geom) {
	(void)c;
	stub_get_geometry_calls++;
	*geom = stub_geom;
}
int stub_set_size_calls = 0;
uint32_t stub_set_size_w = 0, stub_set_size_h = 0;
uint32_t client_set_size(Client *c, uint32_t width, uint32_t height,
						 bool force_configure) {
	(void)c;
	(void)force_configure;
	stub_set_size_calls++;
	stub_set_size_w = width;
	stub_set_size_h = height;
	return 1;
}
uint32_t stub_reset_tags = 0;
int stub_reset_tags_calls = 0;
void client_reset_mon_tags(Client *c, Monitor *m, uint32_t newtags) {
	(void)m;
	(void)newtags;
	stub_reset_tags_calls++;
	c->tags = stub_reset_tags;
}
int stub_tag_float_calls = 0;
void check_match_tag_floating_rule(Client *c, Monitor *m) {
	(void)c;
	(void)m;
	stub_tag_float_calls++;
}
int32_t stub_wants_fullscreen = 0;
int32_t client_wants_fullscreen(Client *c) {
	(void)c;
	return stub_wants_fullscreen;
}
struct Client *stub_center_client = NULL;
Client *center_tiled_select(Monitor *m) {
	(void)m;
	return stub_center_client;
}
struct Client *stub_scroll_tail = NULL;
Client *scroll_get_stack_tail_client(Client *c) {
	(void)c;
	return stub_scroll_tail;
}
int stub_pre_calc_calls = 0;
void pre_calculate_before_arrange(Monitor *m, bool want_animation,
								  bool from_view, bool force) {
	(void)m;
	(void)want_animation;
	(void)from_view;
	(void)force;
	stub_pre_calc_calls++;
}
int stub_overview_destroy_calls = 0;
void overview_destroy_card(Client *c) {
	(void)c;
	stub_overview_destroy_calls++;
}
bool stub_scroller = false;
bool is_scroller_layout(Monitor *m) {
	(void)m;
	return stub_scroller;
}
uint32_t stub_curtag = 0;
uint32_t get_mon_curtag(const Monitor *m) {
	(void)m;
	return stub_curtag;
}

struct AcwmSceneNode *stub_scene_data = NULL;
AcwmSceneNode *acwm_scene_node_find(struct wlr_scene_node *node) {
	(void)node;
	return stub_scene_data;
}
struct wlr_scene_buffer *stub_buffer = NULL;
struct wlr_scene_buffer *wlr_scene_buffer_from_node(
	struct wlr_scene_node *node) {
	(void)node;
	return stub_buffer;
}
struct wlr_scene_surface *stub_scene_surface = NULL;
struct wlr_scene_surface *wlr_scene_surface_try_from_buffer(
	struct wlr_scene_buffer *buffer) {
	(void)buffer;
	return stub_scene_surface;
}
int stub_point_accepts_calls = 0;
double stub_point_tx = 0, stub_point_ty = 0;
bool stub_point_accepts_result = true;
bool wlr_surface_point_accepts_input(struct wlr_surface *surface, double sx,
									 double sy) {
	(void)surface;
	stub_point_accepts_calls++;
	stub_point_tx = sx;
	stub_point_ty = sy;
	return stub_point_accepts_result;
}
int stub_x11_configure_calls = 0;
void wlr_xwayland_surface_configure(struct wlr_xwayland_surface *surface,
									int16_t x, int16_t y, uint16_t width,
									uint16_t height) {
	(void)surface;
	(void)x;
	(void)y;
	(void)width;
	(void)height;
	stub_x11_configure_calls++;
}
int stub_scene_pos_calls = 0;
int stub_reparent_calls = 0;
void wlr_scene_node_set_position(struct wlr_scene_node *node, int32_t x,
								 int32_t y) {
	(void)node;
	(void)x;
	(void)y;
	stub_scene_pos_calls++;
}
void wlr_scene_node_reparent(struct wlr_scene_node *node,
							 struct wlr_scene_tree *parent) {
	node->parent = parent;
	stub_reparent_calls++;
}
