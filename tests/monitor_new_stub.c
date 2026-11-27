/* Test-only stubs for manage/monitor_new.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/bar/bar.h"
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/ext-protocol/ext-workspace.h"
#include "acwm/ipc/ipc.h"
#include "acwm/layout/layout.h"
#include "acwm/manage/monitor.h"
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <wlr/types/wlr_drm_lease_v1.h>
#include <wlr/types/wlr_output.h>
#include <wlr/types/wlr_output_layout.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/types/wlr_ext_workspace_v1.h>

Config config = {0};
Layout layouts[14] = {0};
struct AcwmServer server = {0};

void *ecalloc(size_t nmemb, size_t size) { return calloc(nmemb, size); }

int stub_list_calls = 0;
void wl_list_init(struct wl_list *list) {
	list->next = list;
	list->prev = list;
	stub_list_calls++;
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
	stub_list_calls++;
}
void wl_list_remove(struct wl_list *elm) {
	if (elm->prev && elm->next) {
		elm->prev->next = elm->next;
		elm->next->prev = elm->prev;
	}
	elm->next = elm;
	elm->prev = elm;
}

bool stub_headless = false;
int stub_set_name_calls = 0;
const char *stub_last_name = NULL;
bool stub_init_render = true;
int stub_init_render_calls = 0;
int stub_lease_offer_calls = 0;
bool wlr_output_is_headless(struct wlr_output *output) {
	(void)output;
	return stub_headless;
}
void wlr_output_set_name(struct wlr_output *output, const char *name) {
	(void)output;
	stub_set_name_calls++;
	stub_last_name = name;
}
bool wlr_output_init_render(struct wlr_output *output,
							struct wlr_allocator *allocator,
							struct wlr_renderer *renderer) {
	(void)output;
	(void)allocator;
	(void)renderer;
	stub_init_render_calls++;
	return stub_init_render;
}
bool wlr_drm_lease_v1_manager_offer_output(
	struct wlr_drm_lease_v1_manager *manager, struct wlr_output *output) {
	(void)manager;
	(void)output;
	stub_lease_offer_calls++;
	return true;
}

struct wlr_output_mode stub_preferred_mode;
bool stub_has_preferred = false;
struct wlr_output_mode *wlr_output_preferred_mode(struct wlr_output *output) {
	(void)output;
	return stub_has_preferred ? &stub_preferred_mode : NULL;
}
bool stub_test_result = true;
int stub_test_calls = 0;
bool wlr_output_test_state(struct wlr_output *output,
						   const struct wlr_output_state *state) {
	(void)output;
	(void)state;
	stub_test_calls++;
	return stub_test_result;
}
bool stub_commit_result = true;
int stub_commit_calls = 0;
bool wlr_output_commit_state(struct wlr_output *output,
							 const struct wlr_output_state *state) {
	(void)output;
	(void)state;
	stub_commit_calls++;
	return stub_commit_result;
}

int stub_state_init_calls = 0;
int stub_state_finish_calls = 0;
int stub_state_enabled_calls = 0;
int stub_state_scale_calls = 0;
int stub_state_transform_calls = 0;
int stub_state_adaptive_calls = 0;
int stub_state_mode_calls = 0;
int stub_state_custom_calls = 0;
void wlr_output_state_init(struct wlr_output_state *state) {
	memset(state, 0, sizeof(*state));
	stub_state_init_calls++;
}
void wlr_output_state_finish(struct wlr_output_state *state) {
	(void)state;
	stub_state_finish_calls++;
}
void wlr_output_state_set_enabled(struct wlr_output_state *state, bool enabled) {
	state->committed |= WLR_OUTPUT_STATE_ENABLED;
	state->enabled = enabled;
	stub_state_enabled_calls++;
}
void wlr_output_state_set_scale(struct wlr_output_state *state, float scale) {
	state->committed |= WLR_OUTPUT_STATE_SCALE;
	state->scale = scale;
	stub_state_scale_calls++;
}
void wlr_output_state_set_transform(struct wlr_output_state *state,
									enum wl_output_transform transform) {
	state->committed |= WLR_OUTPUT_STATE_TRANSFORM;
	state->transform = transform;
	stub_state_transform_calls++;
}
void wlr_output_state_set_adaptive_sync_enabled(struct wlr_output_state *state,
												bool enabled) {
	state->committed |= WLR_OUTPUT_STATE_ADAPTIVE_SYNC_ENABLED;
	state->adaptive_sync_enabled = enabled;
	stub_state_adaptive_calls++;
}
void wlr_output_state_set_mode(struct wlr_output_state *state,
							   struct wlr_output_mode *mode) {
	state->committed |= WLR_OUTPUT_STATE_MODE;
	state->mode_type = WLR_OUTPUT_STATE_MODE_FIXED;
	state->mode = mode;
	stub_state_mode_calls++;
}
void wlr_output_state_set_custom_mode(struct wlr_output_state *state,
									  int32_t width, int32_t height,
									  int32_t refresh) {
	state->committed |= WLR_OUTPUT_STATE_MODE;
	state->mode_type = WLR_OUTPUT_STATE_MODE_CUSTOM;
	state->custom_mode.width = width;
	state->custom_mode.height = height;
	state->custom_mode.refresh = refresh;
	stub_state_custom_calls++;
}

struct wlr_scene_output stub_scene_output;
int stub_scene_output_create_calls = 0;
struct wlr_scene_output *wlr_scene_output_create(struct wlr_scene *scene,
												 struct wlr_output *output) {
	(void)scene;
	memset(&stub_scene_output, 0, sizeof(stub_scene_output));
	stub_scene_output.output = output;
	stub_scene_output_create_calls++;
	return &stub_scene_output;
}
int stub_build_calls = 0;
struct wlr_color_transform *stub_build_transform = NULL;
bool wlr_scene_output_build_state(struct wlr_scene_output *scene_output,
								  struct wlr_output_state *state,
								  const struct wlr_scene_output_state_options *options) {
	(void)scene_output;
	(void)state;
	stub_build_calls++;
	stub_build_transform = options ? options->color_transform : NULL;
	return true;
}
struct wlr_output_layout_output *stub_layout_output = NULL;
int stub_add_auto_calls = 0;
int stub_add_calls = 0;
int32_t stub_add_x = 0, stub_add_y = 0;
struct wlr_box stub_box_result;
struct wlr_output_layout_output *wlr_output_layout_add_auto(
	struct wlr_output_layout *layout, struct wlr_output *output) {
	(void)layout;
	(void)output;
	stub_add_auto_calls++;
	return stub_layout_output;
}
struct wlr_output_layout_output *wlr_output_layout_add(
	struct wlr_output_layout *layout, struct wlr_output *output, int32_t x,
	int32_t y) {
	(void)layout;
	(void)output;
	stub_add_calls++;
	stub_add_x = x;
	stub_add_y = y;
	return stub_layout_output;
}
void wlr_output_layout_get_box(struct wlr_output_layout *layout,
							   struct wlr_output *reference,
							   struct wlr_box *dest_box) {
	(void)layout;
	(void)reference;
	*dest_box = stub_box_result;
}
int stub_scene_layout_add_calls = 0;
void wlr_scene_output_layout_add_output(
	struct wlr_scene_output_layout *sol,
	struct wlr_output_layout_output *lo,
	struct wlr_scene_output *so) {
	(void)sol;
	(void)lo;
	(void)so;
	stub_scene_layout_add_calls++;
}

int stub_blur_create_calls = 0;
int stub_blur_size_calls = 0;
int32_t stub_blur_w = 0, stub_blur_h = 0;
int stub_scene_pos_calls = 0;
int32_t stub_scene_x = 0, stub_scene_y = 0;
int stub_reparent_calls = 0;
struct wlr_scene_optimized_blur stub_blur;
struct wlr_scene_optimized_blur *wlr_scene_optimized_blur_create(
	struct wlr_scene_tree *parent, int width, int height) {
	(void)parent;
	(void)width;
	(void)height;
	stub_blur_create_calls++;
	return &stub_blur;
}
void wlr_scene_optimized_blur_set_size(struct wlr_scene_optimized_blur *blur,
									   int width, int height) {
	(void)blur;
	stub_blur_size_calls++;
	stub_blur_w = width;
	stub_blur_h = height;
}
void wlr_scene_node_set_position(struct wlr_scene_node *node, int32_t x,
								 int32_t y) {
	node->x = x;
	node->y = y;
	stub_scene_pos_calls++;
	stub_scene_x = x;
	stub_scene_y = y;
}
void wlr_scene_node_reparent(struct wlr_scene_node *node,
							 struct wlr_scene_tree *parent) {
	node->parent = parent;
	stub_reparent_calls++;
}
struct wlr_scene_rect stub_dim_rect;
int stub_rect_create_calls = 0;
int32_t stub_rect_w = 0, stub_rect_h = 0;
float stub_rect_color[4];
struct wlr_scene_rect *wlr_scene_rect_create(struct wlr_scene_tree *parent,
											 int width, int height,
											 const float color[4]) {
	(void)parent;
	stub_rect_create_calls++;
	stub_rect_w = width;
	stub_rect_h = height;
	memcpy(stub_rect_color, color, sizeof(stub_rect_color));
	return &stub_dim_rect;
}

int stub_timer_add_calls = 0;
struct wl_event_loop *wl_display_get_event_loop(struct wl_display *display) {
	(void)display;
	return (struct wl_event_loop *)0x9000;
}
struct wl_event_source *wl_event_loop_add_timer(
	struct wl_event_loop *loop, wl_event_loop_timer_func_t func, void *data) {
	(void)loop;
	(void)func;
	(void)data;
	stub_timer_add_calls++;
	return (struct wl_event_source *)0xa000;
}
int monitor_skip_frame_timeout_callback(void *data) {
	(void)data;
	return 1;
}
void handle_output_frame(struct wl_listener *listener, void *data) {
	(void)listener;
	(void)data;
}
void handle_output_destroy(struct wl_listener *listener, void *data) {
	(void)listener;
	(void)data;
}
void handle_output_request_state(struct wl_listener *listener, void *data) {
	(void)listener;
	(void)data;
}

struct wlr_ext_workspace_group_handle_v1 stub_group;
int stub_group_create_calls = 0;
uint32_t stub_group_caps = 0;
int stub_group_enter_calls = 0;
struct wlr_ext_workspace_group_handle_v1 *
wlr_ext_workspace_group_handle_v1_create(
	struct wlr_ext_workspace_manager_v1 *manager, uint32_t caps) {
	(void)manager;
	stub_group_create_calls++;
	stub_group_caps = caps;
	return &stub_group;
}
void wlr_ext_workspace_group_handle_v1_output_enter(
	struct wlr_ext_workspace_group_handle_v1 *group,
	struct wlr_output *output) {
	(void)group;
	(void)output;
	stub_group_enter_calls++;
}

bool stub_rule_match = false;
bool stub_apply_result = false;
bool stub_apply_hdr = false;
struct wlr_color_transform *stub_apply_icc = NULL;
bool monitor_matches_rule(Monitor *m, const ConfigMonitorRule *rule) {
	(void)m;
	(void)rule;
	return stub_rule_match;
}
bool apply_rule_to_state(Monitor *m, const ConfigMonitorRule *rule,
						 struct wlr_output_state *state) {
	(void)rule;
	(void)state;
	if (stub_apply_hdr)
		m->hdr_enable = true;
	if (stub_apply_icc)
		m->icc_transform = stub_apply_icc;
	return stub_apply_result;
}
int stub_hdr_setup_calls = 0;
int stub_hdr_enable_calls = 0;
void output_state_setup_hdr(Monitor *m, bool silent,
							struct wlr_output_state *state) {
	(void)m;
	(void)silent;
	(void)state;
	stub_hdr_setup_calls++;
}
void output_enable_hdr(Monitor *m, struct wlr_output_state *state, bool enabled,
					   bool silent) {
	(void)m;
	(void)state;
	(void)enabled;
	(void)silent;
	stub_hdr_enable_calls++;
}
int stub_workspace_calls = 0;
int32_t stub_last_workspace_tag = 0;
void add_workspace_by_tag(int32_t tag, Monitor *m) {
	(void)m;
	stub_workspace_calls++;
	stub_last_workspace_tag = tag;
}
int stub_parse_tagrule_calls = 0;
void parse_tagrule(Monitor *m) {
	(void)m;
	stub_parse_tagrule_calls++;
}
int stub_layout_change_calls = 0;
void handle_output_layout_change(struct wl_listener *listener, void *data) {
	(void)listener;
	(void)data;
	stub_layout_change_calls++;
}
int stub_bar_create_calls = 0;
void bar_monitor_create(Monitor *m) {
	(void)m;
	stub_bar_create_calls++;
}
int stub_dim_calls = 0;
void special_update_dim(Monitor *m) {
	(void)m;
	stub_dim_calls++;
}
int stub_printstatus_calls = 0;
void printstatus(enum ipc_watch_type type) {
	(void)type;
	stub_printstatus_calls++;
}
int32_t regex_match(const char *pattern_mb, const char *str_mb) {
	if (!pattern_mb || !str_mb)
		return 0;
	return strcmp(pattern_mb, str_mb) == 0 ? 1 : 0;
}
