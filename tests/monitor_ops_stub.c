/* Test-only stubs for manage/monitor_ops.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/animation/client.h"
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/layout/arrange.h"
#include "acwm/manage/client.h"
#include "acwm/manage/layer.h"
#include "acwm/manage/monitor.h"
#include "acwm/manage/xwayland_primary.h"
#include <stddef.h>
#include <string.h>
#include <wlr/types/wlr_output.h>
#include <wlr/types/wlr_output_layout.h>
#include <wlr/types/wlr_output_management_v1.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/types/wlr_seat.h>
#include <wlr/types/wlr_session_lock_v1.h>

Config config = {0};
struct AcwmServer server = {0};

int stub_list_remove_calls = 0;
void wl_list_remove(struct wl_list *elm) {
	if (elm->prev && elm->next) {
		elm->prev->next = elm->next;
		elm->next->prev = elm->prev;
	}
	elm->next = elm;
	elm->prev = elm;
	stub_list_remove_calls++;
}

int stub_monitor_close_calls = 0;
void monitor_close(Monitor *m) {
	(void)m;
	stub_monitor_close_calls++;
}
int stub_selected_calls = 0;
Monitor *stub_selected_value = NULL;
void set_selected_monitor(Monitor *m) {
	stub_selected_calls++;
	stub_selected_value = m;
	server.selected_monitor = m;
}
int stub_dim_calls = 0;
void special_update_dim(Monitor *m) {
	(void)m;
	stub_dim_calls++;
}
int stub_arrange_layers_calls = 0;
void arrange_layers(Monitor *m) {
	(void)m;
	stub_arrange_layers_calls++;
}
int stub_arrange_calls = 0;
void arrange(Monitor *m, bool want_animation, bool from_view) {
	(void)m;
	(void)want_animation;
	(void)from_view;
	stub_arrange_calls++;
}
int stub_resize_calls = 0;
struct wlr_box stub_resize_geo;
int32_t stub_resize_interact = -1;
void resize(Client *c, struct wlr_box geo, ResizeOpts opts) {
	(void)c;
	stub_resize_calls++;
	stub_resize_geo = geo;
	stub_resize_interact = opts.interact ? 1 : 0;
}
int stub_focus_calls = 0;
Client *stub_focus_client = NULL;
void client_focus(Client *c, int32_t lift) {
	(void)lift;
	stub_focus_calls++;
	stub_focus_client = c;
}
Client *stub_top_client = NULL;
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
int stub_activate_calls = 0;
void client_activate_surface(struct wlr_surface *s, int32_t activate) {
	(void)s;
	(void)activate;
	stub_activate_calls++;
}
int stub_change_mon_calls = 0;
void client_change_mon(Client *c, Monitor *m) {
	(void)c;
	(void)m;
	stub_change_mon_calls++;
}
int stub_reset_foreign_calls = 0;
void reset_foreign_tolevel(Client *c, Monitor *oldmon, Monitor *newmon) {
	(void)c;
	(void)oldmon;
	(void)newmon;
	stub_reset_foreign_calls++;
}
int stub_size_per_calls = 0;
void set_size_per(Monitor *m, Client *c, bool reset_proportion) {
	(void)m;
	(void)c;
	(void)reset_proportion;
	stub_size_per_calls++;
}
int stub_xdg_update_calls = 0;
void xdg_output_update_all(void) { stub_xdg_update_calls++; }
int stub_xwayland_primary_calls = 0;
void xwayland_primary_update(void) { stub_xwayland_primary_calls++; }
int stub_xwayland_scale_calls = 0;
void xwayland_apply_scale(Client *c) {
	(void)c;
	stub_xwayland_scale_calls++;
}

int stub_enable_async_calls = 0;
bool stub_enable_async_value = false;
int stub_disable_async_calls = 0;
void enable_adaptive_sync(Monitor *m, struct wlr_output_state *state) {
	(void)m;
	(void)state;
	stub_enable_async_calls++;
	stub_enable_async_value = true;
}
void disable_adaptive_sync(Monitor *m, struct wlr_output_state *state) {
	(void)m;
	(void)state;
	stub_disable_async_calls++;
	stub_enable_async_value = false;
}
int stub_acwm_commit_calls = 0;
bool acwm_output_commit(Monitor *m) {
	(void)m;
	stub_acwm_commit_calls++;
	return true;
}
int stub_scene_commit_calls = 0;
bool acwm_scene_output_commit(struct wlr_scene_output *scene_output,
							  struct wlr_output_state *state) {
	(void)scene_output;
	(void)state;
	stub_scene_commit_calls++;
	return true;
}
int stub_check_timeout_calls = 0;
void monitor_check_skip_frame_timeout(Monitor *m) {
	(void)m;
	stub_check_timeout_calls++;
}
int stub_stop_timer_calls = 0;
void monitor_stop_skip_frame_timer(Monitor *m) {
	(void)m;
	stub_stop_timer_calls++;
}
int stub_layer_draw_calls = 0;
bool stub_layer_draw_result = false;
bool layer_draw_frame(LayerSurface *l) {
	(void)l;
	stub_layer_draw_calls++;
	return stub_layer_draw_result;
}
int stub_layer_fade_calls = 0;
bool stub_layer_fade_result = false;
bool layer_draw_fadeout_frame(LayerSurface *l) {
	(void)l;
	stub_layer_fade_calls++;
	if (stub_layer_fade_result)
		free(l);
	return stub_layer_fade_result;
}
int stub_client_draw_calls = 0;
bool stub_client_draw_result = false;
bool client_draw_frame(Client *c) {
	(void)c;
	stub_client_draw_calls++;
	return stub_client_draw_result;
}
int stub_client_fade_calls = 0;
bool stub_client_fade_result = false;
bool client_draw_fadeout_frame(Client *c) {
	(void)c;
	stub_client_fade_calls++;
	return stub_client_fade_result;
}
struct wlr_surface *stub_client_surface_result = NULL;
struct wlr_surface *client_surface(Client *c) {
	(void)c;
	return stub_client_surface_result;
}
int stub_rendered_calls = 0;
bool stub_rendered_result = false;
int32_t client_is_rendered_on_mon(Client *c, Monitor *m) {
	(void)c;
	(void)m;
	stub_rendered_calls++;
	return stub_rendered_result;
}
int stub_fresh_calls = 0;
void request_fresh_all_monitors(void) { stub_fresh_calls++; }

/* output configuration */
struct wlr_output_configuration_v1 stub_config;
struct wlr_output_configuration_head_v1 stub_heads[8];
int stub_head_next = 0;
int stub_config_create_calls = 0;
int stub_head_create_calls = 0;
int stub_succeeded_calls = 0;
int stub_failed_calls = 0;
int stub_config_destroy_calls = 0;
int stub_manager_set_calls = 0;
struct wlr_output_configuration_v1 *wlr_output_configuration_v1_create(void) {
	stub_config_create_calls++;
	memset(&stub_config, 0, sizeof(stub_config));
	stub_config.heads.next = &stub_config.heads;
	stub_config.heads.prev = &stub_config.heads;
	return &stub_config;
}
struct wlr_output_configuration_head_v1 *wlr_output_configuration_head_v1_create(
	struct wlr_output_configuration_v1 *config, struct wlr_output *output) {
	(void)config;
	struct wlr_output_configuration_head_v1 *head =
		&stub_heads[stub_head_next++];
	memset(head, 0, sizeof(*head));
	head->state.output = output;
	stub_head_create_calls++;
	return head;
}
void wlr_output_configuration_v1_send_succeeded(
	struct wlr_output_configuration_v1 *config) {
	(void)config;
	stub_succeeded_calls++;
}
void wlr_output_configuration_v1_send_failed(
	struct wlr_output_configuration_v1 *config) {
	(void)config;
	stub_failed_calls++;
}
void wlr_output_configuration_v1_destroy(
	struct wlr_output_configuration_v1 *config) {
	(void)config;
	stub_config_destroy_calls++;
}
void wlr_output_manager_v1_set_configuration(
	struct wlr_output_manager_v1 *manager,
	struct wlr_output_configuration_v1 *config) {
	(void)manager;
	(void)config;
	stub_manager_set_calls++;
}

int stub_layout_remove_calls = 0;
int stub_layout_add_calls = 0;
int stub_layout_add_auto_calls = 0;
int32_t stub_layout_add_x = 0, stub_layout_add_y = 0;
struct wlr_box stub_box_result;
bool stub_layout_has_output = false;
void wlr_output_layout_remove(struct wlr_output_layout *layout,
							  struct wlr_output *output) {
	(void)layout;
	(void)output;
	stub_layout_remove_calls++;
}
struct wlr_output_layout_output *wlr_output_layout_add_auto(
	struct wlr_output_layout *layout, struct wlr_output *output) {
	(void)layout;
	(void)output;
	stub_layout_add_auto_calls++;
	return NULL;
}
struct wlr_output_layout_output *wlr_output_layout_add(
	struct wlr_output_layout *layout, struct wlr_output *output, int32_t x,
	int32_t y) {
	(void)layout;
	(void)output;
	stub_layout_add_calls++;
	stub_layout_add_x = x;
	stub_layout_add_y = y;
	return NULL;
}
struct wlr_output_layout_output *wlr_output_layout_get(
	struct wlr_output_layout *layout, struct wlr_output *reference) {
	(void)layout;
	(void)reference;
	return stub_layout_has_output ? (struct wlr_output_layout_output *)0x1000
								  : NULL;
}
void wlr_output_layout_get_box(struct wlr_output_layout *layout,
							   struct wlr_output *reference,
							   struct wlr_box *dest_box) {
	(void)layout;
	(void)reference;
	*dest_box = stub_box_result;
}

int stub_scene_pos_calls = 0;
int32_t stub_scene_pos_x = 0, stub_scene_pos_y = 0;
int stub_rect_size_calls = 0;
int32_t stub_rect_size_w = 0, stub_rect_size_h = 0;
int stub_blur_size_calls = 0;
int32_t stub_blur_size_w = 0, stub_blur_size_h = 0;
int stub_scene_output_pos_calls = 0;
int stub_frame_done_calls = 0;
int stub_cursor_move_calls = 0;
int stub_lock_configure_calls = 0;
void wlr_scene_node_set_position(struct wlr_scene_node *node, int32_t x,
								 int32_t y) {
	node->x = x;
	node->y = y;
	stub_scene_pos_calls++;
	stub_scene_pos_x = x;
	stub_scene_pos_y = y;
}
void wlr_scene_rect_set_size(struct wlr_scene_rect *rect, int width,
							 int height) {
	(void)rect;
	stub_rect_size_calls++;
	stub_rect_size_w = width;
	stub_rect_size_h = height;
}
void wlr_scene_optimized_blur_set_size(struct wlr_scene_optimized_blur *blur,
									   int width, int height) {
	(void)blur;
	stub_blur_size_calls++;
	stub_blur_size_w = width;
	stub_blur_size_h = height;
}
void wlr_scene_output_set_position(struct wlr_scene_output *scene_output,
								   int32_t x, int32_t y) {
	(void)scene_output;
	(void)x;
	(void)y;
	stub_scene_output_pos_calls++;
}
void wlr_scene_output_send_frame_done(struct wlr_scene_output *scene_output,
									  struct timespec *now) {
	(void)scene_output;
	(void)now;
	stub_frame_done_calls++;
}
void wlr_cursor_move(struct wlr_cursor *cursor, struct wlr_input_device *device,
					 double delta_x, double delta_y) {
	(void)cursor;
	(void)device;
	(void)delta_x;
	(void)delta_y;
	stub_cursor_move_calls++;
}
uint32_t wlr_session_lock_surface_v1_configure(
	struct wlr_session_lock_surface_v1 *surface, uint32_t width,
	uint32_t height) {
	(void)surface;
	(void)width;
	(void)height;
	stub_lock_configure_calls++;
	return 0;
}
struct wlr_keyboard *wlr_seat_get_keyboard(struct wlr_seat *seat) {
	(void)seat;
	return NULL;
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
int stub_state_enabled_calls = 0;
bool stub_state_enabled = false;
int stub_state_mode_calls = 0;
int stub_state_custom_calls = 0;
int stub_state_transform_calls = 0;
int stub_state_scale_calls = 0;
int stub_state_finish_calls = 0;
void wlr_output_state_set_enabled(struct wlr_output_state *state, bool enabled) {
	(void)state;
	stub_state_enabled_calls++;
	stub_state_enabled = enabled;
}
void wlr_output_state_set_mode(struct wlr_output_state *state,
							   struct wlr_output_mode *mode) {
	(void)state;
	(void)mode;
	stub_state_mode_calls++;
}
void wlr_output_state_set_custom_mode(struct wlr_output_state *state,
									  int32_t width, int32_t height,
									  int32_t refresh) {
	(void)state;
	(void)width;
	(void)height;
	(void)refresh;
	stub_state_custom_calls++;
}
void wlr_output_state_set_transform(struct wlr_output_state *state,
									enum wl_output_transform transform) {
	(void)state;
	(void)transform;
	stub_state_transform_calls++;
}
void wlr_output_state_set_scale(struct wlr_output_state *state, float scale) {
	(void)state;
	(void)scale;
	stub_state_scale_calls++;
}
void wlr_output_state_finish(struct wlr_output_state *state) {
	(void)state;
	stub_state_finish_calls++;
}
int32_t client_is_x11(Client *c) {
	(void)c;
	return 0;
}
