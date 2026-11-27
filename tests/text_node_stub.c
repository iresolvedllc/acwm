/* Test-only stubs for text-node.zig.
 *
 * Provides a minimal scene graph and wlr_buffer lifecycle so tests can assert
 * geometry without a wlroots output/backend. Cairo/Pango stay real. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/scene_node.h"
#include "acwm/draw/text-node.h"
#include <wlr/interfaces/wlr_buffer.h>

#include <stdlib.h>
#include <string.h>

int stub_scene_node_set_calls = 0;
uint32_t stub_scene_node_set_type = 0;
void *stub_scene_node_set_data = NULL;

AcwmSceneNode *acwm_scene_node_set(struct wlr_scene_node *node, uint32_t type,
								   void *data) {
	(void)node;
	stub_scene_node_set_calls++;
	stub_scene_node_set_type = type;
	stub_scene_node_set_data = data;
	return NULL;
}

struct wlr_scene_tree *wlr_scene_tree_create(struct wlr_scene_tree *parent) {
	(void)parent;
	return calloc(1, sizeof(struct wlr_scene_tree));
}

struct wlr_scene_rect *wlr_scene_rect_create(struct wlr_scene_tree *parent,
											 int32_t width, int32_t height,
											 const float color[4]) {
	(void)parent;
	struct wlr_scene_rect *rect = calloc(1, sizeof(*rect));
	rect->width = width;
	rect->height = height;
	memcpy(rect->color, color, sizeof(rect->color));
	return rect;
}

struct wlr_scene_buffer *wlr_scene_buffer_create(struct wlr_scene_tree *parent,
												 struct wlr_buffer *buffer) {
	(void)parent;
	struct wlr_scene_buffer *sb = calloc(1, sizeof(*sb));
	sb->buffer = buffer;
	return sb;
}

void wlr_scene_node_destroy(struct wlr_scene_node *node) { (void)node; }
void wlr_scene_node_set_enabled(struct wlr_scene_node *node, bool enabled) {
	node->enabled = enabled;
}
void wlr_scene_node_set_position(struct wlr_scene_node *node, int32_t x,
								 int32_t y) {
	node->x = x;
	node->y = y;
}
void wlr_scene_node_place_above(struct wlr_scene_node *node,
								struct wlr_scene_node *sibling) {
	(void)node;
	(void)sibling;
}

void wlr_scene_rect_set_size(struct wlr_scene_rect *rect, int32_t width,
							 int32_t height) {
	rect->width = width;
	rect->height = height;
}
void wlr_scene_rect_set_color(struct wlr_scene_rect *rect,
							  const float color[4]) {
	memcpy(rect->color, color, sizeof(rect->color));
}
void wlr_scene_rect_set_corner_radii(struct wlr_scene_rect *rect,
									 struct fx_corner_radii radii) {
	rect->corners = radii;
}
void wlr_scene_rect_set_clipped_region(struct wlr_scene_rect *rect,
									   struct clipped_region region) {
	rect->clipped_region = region;
}
struct clipped_region clipped_region_get_default(void) {
	struct clipped_region region;
	memset(&region, 0, sizeof(region));
	return region;
}

void wlr_scene_buffer_set_buffer(struct wlr_scene_buffer *buffer,
								 struct wlr_buffer *wlr_buffer) {
	buffer->buffer = wlr_buffer;
}
void wlr_scene_buffer_set_dest_size(struct wlr_scene_buffer *buffer,
									int32_t width, int32_t height) {
	buffer->dst_width = width;
	buffer->dst_height = height;
}
void wlr_scene_buffer_set_source_box(struct wlr_scene_buffer *buffer,
									 const struct wlr_fbox *box) {
	if (box)
		buffer->src_box = *box;
}

void wlr_buffer_init(struct wlr_buffer *buffer,
					 const struct wlr_buffer_impl *impl, int32_t width,
					 int32_t height) {
	buffer->impl = impl;
	buffer->width = width;
	buffer->height = height;
}
void wlr_buffer_drop(struct wlr_buffer *buffer) {
	if (buffer && buffer->impl && buffer->impl->destroy)
		buffer->impl->destroy(buffer);
}
