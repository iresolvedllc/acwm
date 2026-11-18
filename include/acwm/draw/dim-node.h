#ifndef ACWM_DRAW_DIM_NODE_H
#define ACWM_DRAW_DIM_NODE_H

#include <cairo.h>
#include <stdbool.h>
#include <stdint.h>
#include <wlr/types/wlr_buffer.h>

#if defined(__has_include) && __has_include(<scenefx/types/wlr_scene.h>)
#include <scenefx/types/wlr_scene.h>
#else
#include <wlr/types/wlr_scene.h>
#endif

struct acwm_dim_buffer {
	struct wlr_buffer base;
	cairo_surface_t *surface;
};

typedef struct AcwmDimNode {
	struct wlr_scene_buffer *scene_buffer;
	struct acwm_dim_buffer *buffer;
	float color[4];
} AcwmDimNode;

AcwmDimNode *acwm_dim_node_create(struct wlr_scene_tree *parent,
									const float color[4]);
void acwm_dim_node_destroy(AcwmDimNode *node);

void acwm_dim_node_set_color(AcwmDimNode *node, const float color[4]);
void acwm_dim_node_set_radius(AcwmDimNode *node, int32_t radius);
void acwm_dim_node_set_box(AcwmDimNode *node, int32_t x, int32_t y,
							int32_t width, int32_t height);
void acwm_dim_node_set_enabled(AcwmDimNode *node, bool enabled);

#endif
