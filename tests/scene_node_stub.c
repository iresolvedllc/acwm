/* Test-only stubs for scene_node.zig. */
#define WLR_USE_UNSTABLE 1
#include <stdbool.h>
#include "acwm/common/scene_node.h"
#include <scenefx/types/wlr_scene.h>

bool wlr_scene_node_coords(struct wlr_scene_node *node, int *lx, int *ly) {
	int x = 0, y = 0;
	struct wlr_scene_node *n = node;
	while (n) {
		x += n->x;
		y += n->y;
		n = n->parent ? &n->parent->node : NULL;
	}
	*lx = x;
	*ly = y;
	return node->enabled;
}

void wlr_output_transform_coords(enum wl_output_transform tr, int *x, int *y) {
	if (tr == WL_OUTPUT_TRANSFORM_90 || tr == WL_OUTPUT_TRANSFORM_270 ||
		tr == WL_OUTPUT_TRANSFORM_FLIPPED_90 ||
		tr == WL_OUTPUT_TRANSFORM_FLIPPED_270) {
		int tmp = *x;
		*x = *y;
		*y = tmp;
	}
}

bool wlr_box_contains_point(const struct wlr_box *box, double x, double y) {
	return x >= box->x && x < box->x + box->width && y >= box->y &&
		   y < box->y + box->height;
}

bool wlr_box_empty(const struct wlr_box *box) {
	return box->width <= 0 || box->height <= 0;
}
