#define WLR_USE_UNSTABLE 1
/* Test-only stubs for dim-node.zig. */
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <cairo.h>
#include <wlr/interfaces/wlr_buffer.h>
#include "acwm/draw/dim-node.h"

int stub_buffer_drops = 0;
int stub_scene_destroy = 0;
int stub_position_calls = 0;
int stub_enabled_calls = 0;
bool stub_enabled_value = true;
int stub_dest_calls = 0;
int stub_dest_w = 0;
int stub_dest_h = 0;
int stub_corner_calls = 0;
int stub_corner_radius = -1;

struct wlr_scene_buffer *wlr_scene_buffer_create(struct wlr_scene_tree *parent,
												 struct wlr_buffer *buffer) {
	(void)parent;
	struct wlr_scene_buffer *sb = calloc(1, sizeof(*sb));
	sb->buffer = buffer;
	return sb;
}
void wlr_scene_buffer_set_buffer(struct wlr_scene_buffer *buffer,
								 struct wlr_buffer *wlr_buffer) {
	buffer->buffer = wlr_buffer;
}
void wlr_scene_buffer_set_dest_size(struct wlr_scene_buffer *buffer,
									int32_t width, int32_t height) {
	(void)buffer;
	stub_dest_calls++;
	stub_dest_w = width;
	stub_dest_h = height;
}
void wlr_scene_buffer_set_corner_radii(struct wlr_scene_buffer *buffer,
									   struct fx_corner_radii radii) {
	(void)buffer;
	stub_corner_calls++;
	stub_corner_radius = radii.top_left;
}
void wlr_scene_node_set_position(struct wlr_scene_node *node, int32_t x,
								 int32_t y) {
	node->x = x;
	node->y = y;
	stub_position_calls++;
}
void wlr_scene_node_set_enabled(struct wlr_scene_node *node, bool enabled) {
	node->enabled = enabled;
	stub_enabled_calls++;
	stub_enabled_value = enabled;
}
void wlr_scene_node_destroy(struct wlr_scene_node *node) {
	(void)node;
	stub_scene_destroy++;
}
void wlr_buffer_init(struct wlr_buffer *buffer,
					 const struct wlr_buffer_impl *impl, int32_t width,
					 int32_t height) {
	buffer->impl = impl;
	buffer->width = width;
	buffer->height = height;
}
void wlr_buffer_drop(struct wlr_buffer *buffer) {
	stub_buffer_drops++;
	if (buffer && buffer->impl && buffer->impl->destroy)
		buffer->impl->destroy(buffer);
}
