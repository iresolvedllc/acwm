/* Test-only stubs for manage/layer.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/animation/layer.h"
#include "acwm/bar/bar.h"
#include "acwm/common/scene_node.h"
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/ext-protocol/text-input.h"
#include "acwm/input/pointer.h"
#include "acwm/ipc/ipc.h"
#include "acwm/layout/arrange.h"
#include "acwm/manage/client.h"
#include "acwm/manage/layer.h"
#include "acwm/manage/monitor.h"
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <wlr/types/wlr_output.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/types/wlr_seat.h>
#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/util/box.h>

Config config = {0};
struct AcwmServer server = {0};

void *ecalloc(size_t nmemb, size_t size) { return calloc(nmemb, size); }

int stub_list_insert_calls = 0;
int stub_list_remove_calls = 0;
struct wl_listener *stub_last_listener = NULL;
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
	stub_last_listener = (struct wl_listener *)((char *)elm -
		offsetof(struct wl_listener, link));
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

/* scene nodes */
int stub_enable_calls = 0;
int stub_enabled_value = -1;
int stub_position_calls = 0;
int32_t stub_pos_x = 0, stub_pos_y = 0;
int stub_reparent_calls = 0;
int stub_destroy_calls = 0;
int stub_raise_calls = 0;
int stub_lower_calls = 0;
int stub_coords_calls = 0;
int32_t stub_coords_x = 0, stub_coords_y = 0;
int stub_for_each_calls = 0;
int stub_invoke_for_each = 0;
struct wlr_scene_surface *stub_scene_surface_result = NULL;
struct wlr_scene_buffer stub_for_each_buffer;
int stub_configure_calls = 0;
struct wlr_box stub_usable_area;
struct wlr_box stub_full_area;

void wlr_scene_node_set_enabled(struct wlr_scene_node *node, bool enabled) {
	node->enabled = enabled;
	stub_enable_calls++;
	stub_enabled_value = enabled ? 1 : 0;
}
void wlr_scene_node_set_position(struct wlr_scene_node *node, int32_t x,
								 int32_t y) {
	node->x = x;
	node->y = y;
	stub_position_calls++;
	stub_pos_x = x;
	stub_pos_y = y;
}
void wlr_scene_node_reparent(struct wlr_scene_node *node,
							 struct wlr_scene_tree *parent) {
	node->parent = parent;
	stub_reparent_calls++;
}
void wlr_scene_node_destroy(struct wlr_scene_node *node) {
	(void)node;
	stub_destroy_calls++;
}
void wlr_scene_node_raise_to_top(struct wlr_scene_node *node) {
	(void)node;
	stub_raise_calls++;
}
void wlr_scene_node_lower_to_bottom(struct wlr_scene_node *node) {
	(void)node;
	stub_lower_calls++;
}
bool wlr_scene_node_coords(struct wlr_scene_node *node, int *lx, int *ly) {
	(void)node;
	stub_coords_calls++;
	if (lx)
		*lx = stub_coords_x;
	if (ly)
		*ly = stub_coords_y;
	return true;
}
void wlr_scene_node_for_each_buffer(struct wlr_scene_node *node,
									wlr_scene_buffer_iterator_func_t iterator,
									void *user_data) {
	(void)node;
	stub_for_each_calls++;
	if (stub_invoke_for_each && iterator)
		iterator(&stub_for_each_buffer, 0, 0, user_data);
}
struct wlr_scene_surface *wlr_scene_surface_try_from_buffer(
	struct wlr_scene_buffer *buffer) {
	(void)buffer;
	return stub_scene_surface_result;
}

int stub_scene_node_set_calls = 0;
AcwmSceneNode *acwm_scene_node_set(struct wlr_scene_node *node, uint32_t type,
								   void *owner) {
	node->data = owner;
	stub_scene_node_set_calls++;
	return NULL;
}

/* scene creation pools */
struct wlr_scene_tree stub_layer_trees[8];
struct wlr_scene_layer_surface_v1 stub_scene_layers[8];
int stub_scene_layer_next = 0;
int stub_scene_layer_create_calls = 0;
struct wlr_scene_tree stub_plain_trees[8];
int stub_plain_tree_next = 0;
int stub_tree_create_calls = 0;
struct wlr_scene_tree stub_xdg_trees[8];
int stub_xdg_tree_next = 0;
int stub_xdg_surface_create_calls = 0;
struct wlr_scene_rect stub_rects[8];
int stub_rect_next = 0;
int stub_rect_create_calls = 0;
float stub_rect_color[4];
struct wlr_scene_shadow stub_shadows[8];
int stub_shadow_next = 0;
int stub_shadow_create_calls = 0;
int stub_shadow_corner = 0;
float stub_shadow_blur = 0;
float stub_shadow_color[4];
struct wlr_scene_blur stub_blurs[8];
int stub_blur_next = 0;
int stub_blur_create_calls = 0;

struct wlr_scene_layer_surface_v1 *wlr_scene_layer_surface_v1_create(
	struct wlr_scene_tree *parent, struct wlr_layer_surface_v1 *layer_surface) {
	(void)parent;
	(void)layer_surface;
	struct wlr_scene_layer_surface_v1 *s =
		&stub_scene_layers[stub_scene_layer_next];
	struct wlr_scene_tree *t = &stub_layer_trees[stub_scene_layer_next];
	stub_scene_layer_next++;
	memset(s, 0, sizeof(*s));
	memset(t, 0, sizeof(*t));
	s->tree = t;
	s->layer_surface = layer_surface;
	stub_scene_layer_create_calls++;
	return s;
}
void wlr_scene_layer_surface_v1_configure(
	struct wlr_scene_layer_surface_v1 *scene_layer, const struct wlr_box *full_area,
	struct wlr_box *usable_area) {
	(void)scene_layer;
	stub_configure_calls++;
	stub_full_area = *full_area;
	stub_usable_area = *usable_area;
}
struct wlr_scene_tree *wlr_scene_tree_create(struct wlr_scene_tree *parent) {
	(void)parent;
	struct wlr_scene_tree *t = &stub_plain_trees[stub_plain_tree_next++];
	memset(t, 0, sizeof(*t));
	stub_tree_create_calls++;
	return t;
}
struct wlr_scene_tree *wlr_scene_xdg_surface_create(
	struct wlr_scene_tree *parent, struct wlr_xdg_surface *xdg_surface) {
	(void)parent;
	(void)xdg_surface;
	struct wlr_scene_tree *t = &stub_xdg_trees[stub_xdg_tree_next++];
	memset(t, 0, sizeof(*t));
	stub_xdg_surface_create_calls++;
	return t;
}
struct wlr_scene_rect *wlr_scene_rect_create(struct wlr_scene_tree *parent,
											 int width, int height,
											 const float color[4]) {
	(void)parent;
	(void)width;
	(void)height;
	struct wlr_scene_rect *r = &stub_rects[stub_rect_next++];
	memset(r, 0, sizeof(*r));
	memcpy(stub_rect_color, color, sizeof(stub_rect_color));
	stub_rect_create_calls++;
	return r;
}
struct wlr_scene_shadow *wlr_scene_shadow_create(
	struct wlr_scene_tree *parent, int width, int height, int corner_radius,
	float blur_sigma, const float color[4]) {
	(void)parent;
	(void)width;
	(void)height;
	struct wlr_scene_shadow *s = &stub_shadows[stub_shadow_next++];
	memset(s, 0, sizeof(*s));
	stub_shadow_corner = corner_radius;
	stub_shadow_blur = blur_sigma;
	memcpy(stub_shadow_color, color, sizeof(stub_shadow_color));
	stub_shadow_create_calls++;
	return s;
}
struct wlr_scene_blur *wlr_scene_blur_create(struct wlr_scene_tree *parent,
											 int width, int height) {
	(void)parent;
	(void)width;
	(void)height;
	struct wlr_scene_blur *b = &stub_blurs[stub_blur_next++];
	memset(b, 0, sizeof(*b));
	stub_blur_create_calls++;
	return b;
}

int stub_mask_source_calls = 0;
int stub_blur_size_calls = 0;
int stub_blur_size_w = 0, stub_blur_size_h = 0;
int stub_bottom_layer_calls = 0;
bool stub_bottom_layer_value = false;
int stub_dirty_calls = 0;
void wlr_scene_blur_set_transparency_mask_source(
	struct wlr_scene_blur *blur, struct wlr_scene_buffer *source) {
	(void)blur;
	(void)source;
	stub_mask_source_calls++;
}
void wlr_scene_blur_set_size(struct wlr_scene_blur *blur, int width,
							 int height) {
	(void)blur;
	stub_blur_size_calls++;
	stub_blur_size_w = width;
	stub_blur_size_h = height;
}
void wlr_scene_blur_set_should_only_blur_bottom_layer(struct wlr_scene_blur *blur,
													  bool value) {
	(void)blur;
	stub_bottom_layer_calls++;
	stub_bottom_layer_value = value;
}
void wlr_scene_optimized_blur_mark_dirty(
	struct wlr_scene_optimized_blur *blur) {
	(void)blur;
	stub_dirty_calls++;
}

/* xdg popups */
int stub_popup_unconstrain_calls = 0;
struct wlr_box stub_constraint_box;
struct wlr_xdg_popup *stub_popup_try_result = NULL;
int stub_popup_destroy_calls = 0;
struct wlr_xdg_popup *wlr_xdg_popup_try_from_wlr_surface(
	struct wlr_surface *surface) {
	(void)surface;
	return stub_popup_try_result;
}
void wlr_xdg_popup_unconstrain_from_box(
	struct wlr_xdg_popup *popup, const struct wlr_box *toplevel_space_box) {
	(void)popup;
	stub_popup_unconstrain_calls++;
	stub_constraint_box = *toplevel_space_box;
}
void wlr_xdg_popup_destroy(struct wlr_xdg_popup *popup) {
	(void)popup;
	stub_popup_destroy_calls++;
}
int stub_layer_destroy_calls = 0;
void wlr_layer_surface_v1_destroy(struct wlr_layer_surface_v1 *surface) {
	(void)surface;
	stub_layer_destroy_calls++;
}

bool wlr_box_equal(const struct wlr_box *a, const struct wlr_box *b) {
	return a->x == b->x && a->y == b->y && a->width == b->width &&
		a->height == b->height;
}

/* misc hooks */
int stub_regex_match = 0;
int stub_regex_calls = 0;
int32_t regex_match(const char *pattern_mb, const char *str_mb) {
	(void)pattern_mb;
	(void)str_mb;
	stub_regex_calls++;
	return stub_regex_match ? 1 : 0;
}
int stub_bar_strip = 0;
int32_t bar_strip_height(void) { return stub_bar_strip; }
int stub_bar_layout_calls = 0;
void bar_monitor_layout(Monitor *m) {
	(void)m;
	stub_bar_layout_calls++;
}
int stub_printstatus_calls = 0;
void printstatus(enum ipc_watch_type type) {
	(void)type;
	stub_printstatus_calls++;
}
int stub_client_focus_calls = 0;
Client *stub_last_focus = NULL;
int32_t stub_last_lift = -1;
Client *stub_top_client = NULL;
void client_focus(Client *c, int32_t lift) {
	stub_client_focus_calls++;
	stub_last_focus = c;
	stub_last_lift = lift;
}
Client *client_focus_top(Monitor *m) {
	(void)m;
	return stub_top_client;
}
int stub_notify_calls = 0;
struct wlr_surface *stub_notify_surface = NULL;
void client_notify_enter(struct wlr_surface *s, struct wlr_keyboard *kb) {
	(void)kb;
	stub_notify_calls++;
	stub_notify_surface = s;
}
struct wlr_keyboard stub_keyboard = {0};
struct wlr_keyboard *wlr_seat_get_keyboard(struct wlr_seat *seat) {
	(void)seat;
	return &stub_keyboard;
}
int stub_toplevel_kind = 1;
Client *stub_toplevel_client = NULL;
LayerSurface *stub_toplevel_layer = NULL;
int32_t toplevel_from_wlr_surface(struct wlr_surface *s, Client **pc,
								  LayerSurface **pl) {
	(void)s;
	if (pc)
		*pc = stub_toplevel_client;
	if (pl)
		*pl = stub_toplevel_layer;
	return stub_toplevel_kind;
}
int stub_relay_calls = 0;
void acwm_im_relay_set_focus(struct acwm_input_method_relay *relay,
							 struct wlr_surface *surface) {
	(void)relay;
	(void)surface;
	stub_relay_calls++;
}
int stub_scale_calls = 0;
float stub_scale = 0;
void client_set_scale(struct wlr_surface *s, float scale) {
	(void)s;
	stub_scale_calls++;
	stub_scale = scale;
}
int stub_pointer_calls = 0;
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
int stub_arrange_calls = 0;
void arrange(Monitor *m, bool want_animation, bool from_view) {
	(void)m;
	(void)want_animation;
	(void)from_view;
	stub_arrange_calls++;
}
int stub_blur_layer_calls = 0;
uint32_t stub_blur_layer = 0;
bool stub_blur_on_wallpaper = false;
bool blur_layer_on_wallpaper(uint32_t layer) {
	stub_blur_layer_calls++;
	stub_blur_layer = layer;
	return stub_blur_on_wallpaper;
}

/* animation layer hooks */
int stub_fadeout_calls = 0;
void init_fadeout_layers(LayerSurface *l) {
	(void)l;
	stub_fadeout_calls++;
}
int stub_pending_calls = 0;
void layer_set_pending_state(LayerSurface *l) {
	(void)l;
	stub_pending_calls++;
}
struct wlr_box stub_target_box;
int stub_target_calls = 0;
void get_layer_target_geometry(LayerSurface *l, struct wlr_box *target_box) {
	(void)l;
	stub_target_calls++;
	*target_box = stub_target_box;
}
