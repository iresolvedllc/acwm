/* Test-only stubs for manage/monitor_query.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/ext-protocol/text-input.h"
#include "acwm/layout/arrange.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"
#include <string.h>
#include <wlr/types/wlr_output.h>
#include <wlr/types/wlr_output_layout.h>
#include <wlr/types/wlr_scene.h>

Config config = {0};
struct AcwmServer server = {0};

int stub_regex_result = 0;
int stub_regex_calls = 0;
int32_t regex_match(const char *pattern_mb, const char *str_mb) {
	stub_regex_calls++;
	if (!pattern_mb || !str_mb)
		return 0;
	return strcmp(pattern_mb, str_mb) == 0;
}

struct wlr_output_layout_output stub_layout_output;
bool stub_layout_has_output = true;
struct wlr_output *stub_adjacent_output = NULL;
struct wlr_output *stub_farthest_output = NULL;
struct wlr_output *stub_point_output = NULL;
double stub_closest_x = 0, stub_closest_y = 0;
int stub_adjacent_dir = -1;
int stub_farthest_dir = -1;

struct wlr_output_layout_output *wlr_output_layout_get(
	struct wlr_output_layout *layout, struct wlr_output *reference) {
	(void)layout;
	(void)reference;
	return stub_layout_has_output ? &stub_layout_output : NULL;
}
struct wlr_output *wlr_output_layout_output_at(
	struct wlr_output_layout *layout, double lx, double ly) {
	(void)layout;
	(void)lx;
	(void)ly;
	return stub_layout_has_output ? stub_point_output : NULL;
}
struct wlr_output *wlr_output_layout_adjacent_output(
	struct wlr_output_layout *layout, enum wlr_direction direction,
	struct wlr_output *reference, double ref_lx, double ref_ly) {
	(void)layout;
	(void)reference;
	(void)ref_lx;
	(void)ref_ly;
	stub_adjacent_dir = (int)direction;
	return stub_adjacent_output;
}
struct wlr_output *wlr_output_layout_farthest_output(
	struct wlr_output_layout *layout, enum wlr_direction direction,
	struct wlr_output *reference, double ref_lx, double ref_ly) {
	(void)layout;
	(void)reference;
	(void)ref_lx;
	(void)ref_ly;
	stub_farthest_dir = (int)direction;
	return stub_farthest_output;
}
void wlr_output_layout_closest_point(struct wlr_output_layout *layout,
									 struct wlr_output *reference, double lx,
									 double ly, double *dest_lx,
									 double *dest_ly) {
	(void)layout;
	(void)reference;
	(void)lx;
	(void)ly;
	if (dest_lx)
		*dest_lx = stub_closest_x;
	if (dest_ly)
		*dest_ly = stub_closest_y;
}

Monitor *stub_output_monitor = NULL;
Monitor *output_from_wlr_output(struct wlr_output *wlr_output) {
	(void)wlr_output;
	return stub_output_monitor;
}

ConfigDeviceRule stub_device_rule;
bool stub_device_rule_valid = false;
ConfigDeviceRule *find_device_rule(struct wlr_input_device *device) {
	(void)device;
	return stub_device_rule_valid ? &stub_device_rule : NULL;
}

int stub_arrange_calls = 0;
void arrange(Monitor *m, bool want_animation, bool from_view) {
	(void)m;
	(void)want_animation;
	(void)from_view;
	stub_arrange_calls++;
}

int stub_reparent_calls = 0;
struct wlr_scene_tree *stub_last_parent = NULL;
int stub_enable_calls = 0;
int stub_enabled_value = -1;
int stub_position_calls = 0;
int32_t stub_pos_x = 0, stub_pos_y = 0;
int stub_rect_size_calls = 0;
int32_t stub_rect_w = 0, stub_rect_h = 0;
int stub_rect_color_calls = 0;
float stub_rect_color[4];

void wlr_scene_node_reparent(struct wlr_scene_node *node,
							 struct wlr_scene_tree *parent) {
	node->parent = parent;
	stub_reparent_calls++;
	stub_last_parent = parent;
}
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
void wlr_scene_rect_set_size(struct wlr_scene_rect *rect, int width,
							 int height) {
	(void)rect;
	stub_rect_size_calls++;
	stub_rect_w = width;
	stub_rect_h = height;
}
void wlr_scene_rect_set_color(struct wlr_scene_rect *rect, const float color[4]) {
	(void)rect;
	stub_rect_color_calls++;
	memcpy(stub_rect_color, color, sizeof(stub_rect_color));
}
