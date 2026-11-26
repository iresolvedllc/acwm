/* Test-only stubs for animation/layer.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/animation/layer.h"
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/manage/layer.h"
#include "acwm/manage/monitor.h"
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/util/box.h>
#include <wlr/util/edges.h>

Config config = {0};
struct AcwmServer server = {0};

void *ecalloc(size_t nmemb, size_t size) { return calloc(nmemb, size); }

int stub_list_insert_calls = 0;
int stub_list_remove_calls = 0;
int stub_schedule_calls = 0;
void wl_list_insert(struct wl_list *list, struct wl_list *elm) {
	elm->next = list->next;
	elm->prev = list;
	list->next->prev = elm;
	list->next = elm;
	stub_list_insert_calls++;
}
void wl_list_remove(struct wl_list *elm) {
	elm->prev->next = elm->next;
	elm->next->prev = elm->prev;
	elm->next = elm;
	elm->prev = elm;
	stub_list_remove_calls++;
}
void wlr_output_schedule_frame(struct wlr_output *output) {
	(void)output;
	stub_schedule_calls++;
}

/* curve/time */
double stub_curve_factor = 1.0;
double stub_opacity_factor = 1.0;
uint32_t stub_now_ms = 1000;
uint32_t stub_get_now = 500;
double find_animation_curve_at(double t, int32_t type) {
	(void)t;
	if (type == OPAFADEIN || type == OPAFADEOUT)
		return stub_opacity_factor;
	return stub_curve_factor;
}
uint32_t timespec_to_ms(struct timespec *ts) {
	(void)ts;
	return stub_now_ms;
}
uint32_t get_now_in_ms(void) { return stub_get_now; }

/* scene node recorders */
int stub_enable_calls = 0;
int stub_enabled_value = -1;
int stub_position_calls = 0;
int32_t stub_pos_x = 0, stub_pos_y = 0;
int stub_raise_calls = 0;
int stub_lower_calls = 0;
int stub_destroy_calls = 0;
int stub_rect_size_calls = 0;
int32_t stub_rect_w = 0, stub_rect_h = 0;
int stub_shadow_size_calls = 0;
int32_t stub_shadow_w = 0, stub_shadow_h = 0;
int stub_shadow_clip_calls = 0;
struct clipped_region stub_shadow_clip;
int stub_blur_strength_calls = 0;
float stub_blur_strength = 0;
int stub_blur_alpha_calls = 0;
float stub_blur_alpha = 0;
int stub_blur_size_calls = 0;
int32_t stub_blur_w = 0, stub_blur_h = 0;
int stub_dest_size_calls = 0;
int32_t stub_dest_w = 0, stub_dest_h = 0;
int stub_for_each_calls = 0;
wlr_scene_buffer_iterator_func_t stub_for_each_iterator = NULL;
void *stub_for_each_data = NULL;
int stub_invoke_iterator = 0;
struct wlr_scene_buffer stub_iter_buffer;
struct wlr_scene_tree *stub_snapshot_result = NULL;
int stub_snapshot_calls = 0;
uint32_t stub_exclusive_edge = WLR_EDGE_NONE;
bool stub_blur_wallpaper = false;
int stub_opacity_calls = 0;
float stub_last_opacity = 0;

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
void wlr_scene_node_raise_to_top(struct wlr_scene_node *node) {
	(void)node;
	stub_raise_calls++;
}
void wlr_scene_node_lower_to_bottom(struct wlr_scene_node *node) {
	(void)node;
	stub_lower_calls++;
}
void wlr_scene_node_destroy(struct wlr_scene_node *node) {
	(void)node;
	stub_destroy_calls++;
}
void wlr_scene_node_for_each_buffer(struct wlr_scene_node *node,
									wlr_scene_buffer_iterator_func_t iterator,
									void *user_data) {
	(void)node;
	stub_for_each_calls++;
	stub_for_each_iterator = iterator;
	stub_for_each_data = user_data;
	if (stub_invoke_iterator && iterator)
		iterator(&stub_iter_buffer, 0, 0, user_data);
}
void wlr_scene_rect_set_size(struct wlr_scene_rect *rect, int width,
							 int height) {
	(void)rect;
	stub_rect_size_calls++;
	stub_rect_w = width;
	stub_rect_h = height;
}
void wlr_scene_shadow_set_size(struct wlr_scene_shadow *shadow, int width,
							   int height) {
	(void)shadow;
	stub_shadow_size_calls++;
	stub_shadow_w = width;
	stub_shadow_h = height;
}
void wlr_scene_shadow_set_clipped_region(
	struct wlr_scene_shadow *shadow, struct clipped_region clipped_region) {
	(void)shadow;
	stub_shadow_clip_calls++;
	stub_shadow_clip = clipped_region;
}
void wlr_scene_blur_set_strength(struct wlr_scene_blur *blur, float strength) {
	(void)blur;
	stub_blur_strength_calls++;
	stub_blur_strength = strength;
}
void wlr_scene_blur_set_alpha(struct wlr_scene_blur *blur, float alpha) {
	(void)blur;
	stub_blur_alpha_calls++;
	stub_blur_alpha = alpha;
}
void wlr_scene_blur_set_size(struct wlr_scene_blur *blur, int width,
							 int height) {
	(void)blur;
	stub_blur_size_calls++;
	stub_blur_w = width;
	stub_blur_h = height;
}
void wlr_scene_buffer_set_dest_size(struct wlr_scene_buffer *buffer, int width,
									int height) {
	(void)buffer;
	stub_dest_size_calls++;
	stub_dest_w = width;
	stub_dest_h = height;
}
struct wlr_scene_surface *stub_scene_surface_result = NULL;
struct wlr_scene_surface *wlr_scene_surface_try_from_buffer(
	struct wlr_scene_buffer *buffer) {
	(void)buffer;
	return stub_scene_surface_result;
}
struct wlr_scene_tree *wlr_scene_tree_snapshot(struct wlr_scene_node *node,
											   struct wlr_scene_tree *parent) {
	(void)node;
	(void)parent;
	stub_snapshot_calls++;
	return stub_snapshot_result;
}
uint32_t wlr_layer_surface_v1_get_exclusive_edge(
	struct wlr_layer_surface_v1 *surface) {
	(void)surface;
	return stub_exclusive_edge;
}
bool wlr_box_intersection(struct wlr_box *dest, const struct wlr_box *a,
						  const struct wlr_box *b) {
	int32_t x1 = a->x > b->x ? a->x : b->x;
	int32_t y1 = a->y > b->y ? a->y : b->y;
	int32_t x2 = (a->x + a->width) < (b->x + b->width)
					 ? (a->x + a->width)
					 : (b->x + b->width);
	int32_t y2 = (a->y + a->height) < (b->y + b->height)
					 ? (a->y + a->height)
					 : (b->y + b->height);
	if (x2 <= x1 || y2 <= y1) {
		memset(dest, 0, sizeof(*dest));
		return false;
	}
	dest->x = x1;
	dest->y = y1;
	dest->width = x2 - x1;
	dest->height = y2 - y1;
	return true;
}

/* builders/zones */
void scene_buffer_apply_opacity(struct wlr_scene_buffer *buffer, int32_t sx,
								int32_t sy, void *data) {
	(void)buffer;
	(void)sx;
	(void)sy;
	stub_opacity_calls++;
	stub_last_opacity = *(float *)data;
}
bool layer_blur_uses_wallpaper(LayerSurface *l) {
	(void)l;
	return stub_blur_wallpaper;
}
