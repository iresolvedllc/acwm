/* Test-only stubs for manage/monitor_lifecycle.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/bar/bar.h"
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/ext-protocol/ext-workspace.h"
#include "acwm/ipc/ipc.h"
#include "acwm/manage/client.h"
#include "acwm/manage/layer.h"
#include "acwm/manage/monitor.h"
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <wlr/backend/headless.h>
#include <wlr/backend/wayland.h>
#include <wlr/render/allocator.h>
#include <wlr/render/wlr_renderer.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_foreign_toplevel_management_v1.h>
#include <wlr/types/wlr_output.h>
#include <wlr/types/wlr_output_layout.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/types/wlr_session_lock_v1.h>

Config config = {0};
struct AcwmServer server = {0};

void *ecalloc(size_t nmemb, size_t size) { return calloc(nmemb, size); }

int stub_list_insert_calls = 0;
int stub_list_remove_calls = 0;
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
	stub_list_remove_calls++;
}

int stub_bar_destroy_calls = 0;
void bar_monitor_destroy(Monitor *m) {
	(void)m;
	stub_bar_destroy_calls++;
}
int stub_workspace_cleanup_calls = 0;
void cleanup_workspaces_by_monitor(Monitor *m) {
	(void)m;
	stub_workspace_cleanup_calls++;
}
int stub_dwindle_cleanup_calls = 0;
void cleanup_monitor_dwindle(Monitor *m) {
	(void)m;
	stub_dwindle_cleanup_calls++;
}
int stub_scroller_cleanup_calls = 0;
void cleanup_monitor_scroller(Monitor *m) {
	(void)m;
	stub_scroller_cleanup_calls++;
}
int stub_ext_leave_calls = 0;
int stub_ext_destroy_calls = 0;
void wlr_ext_workspace_group_handle_v1_output_leave(
	struct wlr_ext_workspace_group_handle_v1 *group,
	struct wlr_output *output) {
	(void)group;
	(void)output;
	stub_ext_leave_calls++;
}
void wlr_ext_workspace_group_handle_v1_destroy(
	struct wlr_ext_workspace_group_handle_v1 *group) {
	(void)group;
	stub_ext_destroy_calls++;
}
int stub_ft_leave_calls = 0;
int stub_ft_destroy_calls = 0;
void wlr_foreign_toplevel_handle_v1_output_leave(
	struct wlr_foreign_toplevel_handle_v1 *handle, struct wlr_output *output) {
	(void)handle;
	(void)output;
	stub_ft_leave_calls++;
}
void wlr_foreign_toplevel_handle_v1_destroy(
	struct wlr_foreign_toplevel_handle_v1 *handle) {
	(void)handle;
	stub_ft_destroy_calls++;
}
int stub_set_group_calls = 0;
Monitor *stub_last_group_mon = NULL;
void client_set_group_mon(Client *c, Monitor *m) {
	(void)c;
	stub_set_group_calls++;
	stub_last_group_mon = m;
}
int stub_oldmonname_calls = 0;
void client_update_oldmonname_record(Client *c, Monitor *m) {
	(void)c;
	(void)m;
	stub_oldmonname_calls++;
}
int stub_focus_calls = 0;
Client *stub_focus_client = NULL;
int32_t stub_focus_lift = -1;
void client_focus(Client *c, int32_t lift) {
	stub_focus_calls++;
	stub_focus_client = c;
	stub_focus_lift = lift;
}
Client *stub_top_client = NULL;
Client *client_focus_top(Monitor *m) {
	(void)m;
	return stub_top_client;
}
int stub_printstatus_calls = 0;
void printstatus(enum ipc_watch_type type) {
	(void)type;
	stub_printstatus_calls++;
}
int stub_selected_calls = 0;
Monitor *stub_selected_value = NULL;
void set_selected_monitor(Monitor *m) {
	stub_selected_calls++;
	stub_selected_value = m;
	server.selected_monitor = m;
}
int stub_layout_change_calls = 0;
void handle_output_layout_change(struct wl_listener *listener, void *data) {
	(void)listener;
	(void)data;
	stub_layout_change_calls++;
}
int stub_lock_surface_destroy_calls = 0;
void handle_session_lock_surface_destroy(struct wl_listener *listener,
										 void *data) {
	(void)listener;
	(void)data;
	stub_lock_surface_destroy_calls++;
}

int stub_node_destroy_calls = 0;
void wlr_scene_node_destroy(struct wlr_scene_node *node) {
	(void)node;
	stub_node_destroy_calls++;
}
int stub_scene_output_destroy_calls = 0;
void wlr_scene_output_destroy(struct wlr_scene_output *scene_output) {
	(void)scene_output;
	stub_scene_output_destroy_calls++;
}
int stub_layout_remove_calls = 0;
void wlr_output_layout_remove(struct wlr_output_layout *layout,
							  struct wlr_output *output) {
	(void)layout;
	(void)output;
	stub_layout_remove_calls++;
}
int stub_layer_v1_destroy_calls = 0;
void wlr_layer_surface_v1_destroy(struct wlr_layer_surface_v1 *surface) {
	(void)surface;
	stub_layer_v1_destroy_calls++;
}
int stub_state_enabled_calls = 0;
bool stub_state_enabled = false;
void wlr_output_state_set_enabled(struct wlr_output_state *state, bool enabled) {
	(void)state;
	stub_state_enabled_calls++;
	stub_state_enabled = enabled;
}
int stub_state_mode_calls = 0;
struct wlr_output_mode *stub_state_mode = NULL;
void wlr_output_state_set_mode(struct wlr_output_state *state,
							   struct wlr_output_mode *mode) {
	(void)state;
	stub_state_mode_calls++;
	stub_state_mode = mode;
}
int stub_state_custom_calls = 0;
int32_t stub_state_custom_w = 0, stub_state_custom_h = 0,
		stub_state_custom_refresh = 0;
void wlr_output_state_set_custom_mode(struct wlr_output_state *state,
									  int32_t width, int32_t height,
									  int32_t refresh) {
	(void)state;
	stub_state_custom_calls++;
	stub_state_custom_w = width;
	stub_state_custom_h = height;
	stub_state_custom_refresh = refresh;
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
int stub_finish_calls = 0;
void wlr_output_state_finish(struct wlr_output_state *state) {
	(void)state;
	stub_finish_calls++;
}
int stub_unref_calls = 0;
void wlr_color_transform_unref(struct wlr_color_transform *tr) {
	(void)tr;
	stub_unref_calls++;
}
int stub_schedule_frame_calls = 0;
void wlr_output_schedule_frame(struct wlr_output *output) {
	(void)output;
	stub_schedule_frame_calls++;
}
int stub_timer_update_calls = 0;
int stub_timer_delay = -1;
int wl_event_source_timer_update(struct wl_event_source *source, int ms_delay) {
	(void)source;
	stub_timer_update_calls++;
	stub_timer_delay = ms_delay;
	return 0;
}
int stub_timer_remove_calls = 0;
int wl_event_source_remove(struct wl_event_source *source) {
	(void)source;
	stub_timer_remove_calls++;
	return 0;
}
bool stub_is_wl = false;
bool stub_is_headless = false;
bool wlr_backend_is_wl(struct wlr_backend *backend) {
	(void)backend;
	return stub_is_wl;
}
bool wlr_backend_is_headless(struct wlr_backend *backend) {
	(void)backend;
	return stub_is_headless;
}
int stub_wl_output_calls = 0;
struct wlr_output *wlr_wl_output_create(struct wlr_backend *backend) {
	(void)backend;
	stub_wl_output_calls++;
	return NULL;
}
int stub_headless_output_calls = 0;
struct wlr_output *wlr_headless_add_output(struct wlr_backend *backend,
										   uint32_t width, uint32_t height) {
	(void)backend;
	stub_headless_output_calls++;
	return NULL;
}
int stub_toggle_overview_calls = 0;
int32_t toggle_overview(const Arg *arg) {
	(void)arg;
	stub_toggle_overview_calls++;
	return 0;
}

/* renderer recreation */
int stub_acwm_commit_calls = 0;
bool stub_acwm_commit_result = true;
bool acwm_output_commit(Monitor *m) {
	(void)m;
	stub_acwm_commit_calls++;
	return stub_acwm_commit_result;
}
struct wlr_renderer *stub_new_renderer = NULL;
struct wlr_allocator *stub_new_allocator = NULL;
int stub_fx_create_calls = 0;
int stub_alloc_create_calls = 0;
struct wlr_renderer *fx_renderer_create(struct wlr_backend *backend) {
	(void)backend;
	stub_fx_create_calls++;
	return stub_new_renderer;
}
struct wlr_allocator *wlr_allocator_autocreate(struct wlr_backend *backend,
											   struct wlr_renderer *renderer) {
	(void)backend;
	(void)renderer;
	stub_alloc_create_calls++;
	return stub_new_allocator;
}
int stub_alloc_destroy_calls = 0;
void wlr_allocator_destroy(struct wlr_allocator *allocator) {
	(void)allocator;
	stub_alloc_destroy_calls++;
}
int stub_renderer_destroy_calls = 0;
void wlr_renderer_destroy(struct wlr_renderer *renderer) {
	(void)renderer;
	stub_renderer_destroy_calls++;
}
int stub_compositor_renderer_calls = 0;
void wlr_compositor_set_renderer(struct wlr_compositor *compositor,
								 struct wlr_renderer *renderer) {
	(void)compositor;
	(void)renderer;
	stub_compositor_renderer_calls++;
}
int stub_output_init_render_calls = 0;
bool wlr_output_init_render(struct wlr_output *output,
							struct wlr_allocator *allocator,
							struct wlr_renderer *renderer) {
	(void)output;
	(void)allocator;
	(void)renderer;
	stub_output_init_render_calls++;
	return true;
}
wl_event_loop_idle_func_t stub_idle_callback = NULL;
int stub_add_idle_calls = 0;
struct wl_event_source *wl_event_loop_add_idle(struct wl_event_loop *loop,
											   wl_event_loop_idle_func_t func,
											   void *data) {
	(void)loop;
	(void)data;
	stub_add_idle_calls++;
	stub_idle_callback = func;
	return (struct wl_event_source *)0x9000;
}
