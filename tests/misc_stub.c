/* Test-only stubs for manage/misc.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/bar/bar.h"
#include "acwm/common/scene_node.h"
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/input/pointer.h"
#include "acwm/layout/arrange.h"
#include "acwm/manage/client.h"
#include "acwm/manage/layer.h"
#include "acwm/manage/misc.h"
#include "acwm/manage/monitor.h"
#include <pixman.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <wlr/render/wlr_renderer.h>
#include <wlr/types/wlr_data_device.h>
#include <wlr/types/wlr_drm_lease_v1.h>
#include <wlr/types/wlr_ext_image_capture_source_v1.h>
#include <wlr/types/wlr_ext_image_copy_capture_v1.h>
#include <wlr/types/wlr_idle_notify_v1.h>
#include <wlr/types/wlr_primary_selection.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/types/wlr_seat.h>
#include <wlr/types/wlr_session_lock_v1.h>
#include <wlr/types/wlr_xdg_decoration_v1.h>

Config config = {0};
struct AcwmServer server = {0};

void *ecalloc(size_t nmemb, size_t size) { return calloc(nmemb, size); }

/* list plumbing: avoid needing initialised wl_signals in fixtures */
int stub_list_insert_calls = 0;
int stub_list_remove_calls = 0;
struct wl_listener *stub_last_listener = NULL;
struct wl_listener *stub_client_listener = NULL;
struct wl_listener *stub_added_destroy_listener = NULL;
int stub_emit_calls = 0;
int stub_region_empty = 0;

void wl_list_insert(struct wl_list *list, struct wl_list *elm) {
	(void)list;
	elm->next = elm;
	elm->prev = elm;
	stub_list_insert_calls++;
	stub_last_listener = (struct wl_listener *)((char *)elm -
		offsetof(struct wl_listener, link));
}
void wl_list_remove(struct wl_list *elm) {
	elm->next = elm;
	elm->prev = elm;
	stub_list_remove_calls++;
}
void wl_signal_emit_mutable(struct wl_signal *signal, void *data) {
	(void)signal;
	(void)data;
	stub_emit_calls++;
}

/* hit testing */
struct wlr_scene_node *stub_scene_node_at = NULL;
AcwmSceneNode *stub_scene_data = NULL;
Monitor *stub_monitor_at = NULL;
double stub_nx = 0, stub_ny = 0;

struct wlr_scene_node *acwm_scene_node_at(struct wlr_scene_node *node, double x,
										  double y, double *nx, double *ny) {
	(void)node;
	(void)x;
	(void)y;
	if (nx)
		*nx = stub_nx;
	if (ny)
		*ny = stub_ny;
	return stub_scene_node_at;
}
AcwmSceneNode *acwm_scene_node_find(struct wlr_scene_node *node) {
	(void)node;
	return stub_scene_data;
}
Monitor *monitor_at_point(double x, double y) {
	(void)x;
	(void)y;
	return stub_monitor_at;
}
pixman_bool_t pixman_region32_not_empty(const pixman_region32_t *region) {
	(void)region;
	return !stub_region_empty;
}

/* client helpers */
int stub_client_focus_calls = 0;
Client *stub_last_focus = NULL;
int32_t stub_last_lift = -1;
Client *stub_top_client = NULL;
int stub_client_notify_calls = 0;
struct wlr_surface *stub_notify_surface = NULL;
struct wlr_surface *stub_client_surface = NULL;
Client *stub_toplevel_client = NULL;
int stub_reset_exclusive_calls = 0;
int stub_pointer_motion_calls = 0;
int stub_arrange_calls = 0;
int stub_bar_update_lock_calls = 0;
int stub_rearm_calls = 0;

void client_focus(Client *c, int32_t lift) {
	stub_client_focus_calls++;
	stub_last_focus = c;
	stub_last_lift = lift;
}
Client *client_focus_top(Monitor *m) {
	(void)m;
	return stub_top_client;
}
struct wlr_surface *client_surface(Client *c) {
	(void)c;
	return stub_client_surface;
}
void client_notify_enter(struct wlr_surface *s, struct wlr_keyboard *kb) {
	(void)kb;
	stub_client_notify_calls++;
	stub_notify_surface = s;
}
int32_t toplevel_from_wlr_surface(struct wlr_surface *s, Client **pc,
								  LayerSurface **pl) {
	(void)s;
	if (pc)
		*pc = stub_toplevel_client;
	if (pl)
		*pl = NULL;
	return stub_toplevel_client != NULL;
}
void reset_exclusive_layers_focus(Monitor *m) {
	(void)m;
	stub_reset_exclusive_calls++;
}
void pointer_process_motion(uint32_t time, struct wlr_input_device *device,
							double dx, double dy, double dx_unaccel,
							double dy_unaccel) {
	(void)time;
	(void)device;
	(void)dx;
	(void)dy;
	(void)dx_unaccel;
	(void)dy_unaccel;
	stub_pointer_motion_calls++;
}
void arrange(Monitor *m, bool want_animation, bool from_view) {
	(void)m;
	(void)want_animation;
	(void)from_view;
	stub_arrange_calls++;
}
void bar_update_lock(void) { stub_bar_update_lock_calls++; }
void rearm_idle_check(void) { stub_rearm_calls++; }

/* idle inhibitors */
int stub_set_inhibited_calls = 0;
bool stub_last_inhibited = false;
struct wlr_surface *stub_root_surface = NULL;

void wlr_idle_notifier_v1_set_inhibited(struct wlr_idle_notifier_v1 *notifier,
										bool inhibited) {
	(void)notifier;
	stub_set_inhibited_calls++;
	stub_last_inhibited = inhibited;
}
struct wlr_surface *wlr_surface_get_root_surface(struct wlr_surface *surface) {
	return stub_root_surface ? stub_root_surface : surface;
}

/* scene nodes */
int stub_scene_enable_calls = 0;
int stub_scene_position_calls = 0;
int stub_scene_destroy_calls = 0;
int stub_scene_enabled_value = -1;
int32_t stub_scene_x = 0, stub_scene_y = 0;
struct wlr_scene_tree *stub_subtree_result = NULL;
struct wlr_scene_tree *stub_tree_create_result = NULL;
struct wlr_scene_buffer *stub_scene_buffer = NULL;
struct wlr_scene_surface *stub_scene_surface = NULL;

void wlr_scene_node_set_enabled(struct wlr_scene_node *node, bool enabled) {
	node->enabled = enabled;
	stub_scene_enable_calls++;
	stub_scene_enabled_value = enabled ? 1 : 0;
}
void wlr_scene_node_set_position(struct wlr_scene_node *node, int32_t x,
								 int32_t y) {
	node->x = x;
	node->y = y;
	stub_scene_position_calls++;
	stub_scene_x = x;
	stub_scene_y = y;
}
void wlr_scene_node_destroy(struct wlr_scene_node *node) {
	(void)node;
	stub_scene_destroy_calls++;
}
struct wlr_scene_tree *wlr_scene_tree_create(struct wlr_scene_tree *parent) {
	(void)parent;
	return stub_tree_create_result;
}
struct wlr_scene_tree *wlr_scene_subsurface_tree_create(
	struct wlr_scene_tree *parent, struct wlr_surface *surface) {
	(void)parent;
	(void)surface;
	return stub_subtree_result;
}
struct wlr_scene_buffer *wlr_scene_buffer_from_node(
	struct wlr_scene_node *node) {
	(void)node;
	return stub_scene_buffer;
}
struct wlr_scene_surface *wlr_scene_surface_try_from_buffer(
	struct wlr_scene_buffer *buffer) {
	(void)buffer;
	return stub_scene_surface;
}

/* session lock */
int stub_locked_sent = 0;
int stub_lock_destroyed = 0;
int stub_configure_calls = 0;
uint32_t stub_configure_w = 0, stub_configure_h = 0;
int stub_clear_focus_calls = 0;
struct wlr_keyboard stub_keyboard = {0};
struct wlr_surface *stub_focused_surface = NULL;

void wlr_session_lock_v1_send_locked(struct wlr_session_lock_v1 *lock) {
	(void)lock;
	stub_locked_sent++;
}
void wlr_session_lock_v1_destroy(struct wlr_session_lock_v1 *lock) {
	(void)lock;
	stub_lock_destroyed++;
}
uint32_t wlr_session_lock_surface_v1_configure(
	struct wlr_session_lock_surface_v1 *lock_surface, uint32_t width,
	uint32_t height) {
	(void)lock_surface;
	stub_configure_calls++;
	stub_configure_w = width;
	stub_configure_h = height;
	return 1;
}
void wlr_seat_keyboard_notify_clear_focus(struct wlr_seat *seat) {
	(void)seat;
	stub_clear_focus_calls++;
}
struct wlr_keyboard *wlr_seat_get_keyboard(struct wlr_seat *seat) {
	(void)seat;
	return &stub_keyboard;
}

/* xdg decoration */
int stub_set_mode_calls = 0;
int stub_last_mode = -1;
uint32_t wlr_xdg_toplevel_decoration_v1_set_mode(
	struct wlr_xdg_toplevel_decoration_v1 *decoration,
	enum wlr_xdg_toplevel_decoration_v1_mode mode) {
	(void)decoration;
	stub_set_mode_calls++;
	stub_last_mode = (int)mode;
	return 0;
}

/* drm leases */
int stub_grant_calls = 0;
int stub_reject_calls = 0;
struct wlr_drm_lease_v1 *stub_lease_result = NULL;
struct wlr_drm_lease_v1 *wlr_drm_lease_request_v1_grant(
	struct wlr_drm_lease_request_v1 *request) {
	(void)request;
	stub_grant_calls++;
	return stub_lease_result;
}
void wlr_drm_lease_request_v1_reject(
	struct wlr_drm_lease_request_v1 *request) {
	(void)request;
	stub_reject_calls++;
}

/* image capture */
int stub_capture_create_calls = 0;
int stub_accept_calls = 0;
struct wlr_ext_image_capture_source_v1 *stub_capture_source_result = NULL;
struct wlr_ext_image_capture_source_v1 *stub_last_accept_source = NULL;
struct wlr_output *stub_capture_output = NULL;
struct wlr_drm_format stub_format_entries[8];
struct wlr_drm_format_set stub_texture_formats = {0};
int stub_texture_formats_valid = 0;

struct wlr_ext_image_capture_source_v1 *
wlr_ext_image_capture_source_v1_create_with_scene_node(
	struct wlr_scene_node *node, struct wl_event_loop *event_loop,
	struct wlr_allocator *allocator, struct wlr_renderer *renderer) {
	(void)node;
	(void)event_loop;
	(void)allocator;
	(void)renderer;
	stub_capture_create_calls++;
	return stub_capture_source_result;
}
bool wlr_ext_foreign_toplevel_image_capture_source_manager_v1_request_accept(
	struct wlr_ext_foreign_toplevel_image_capture_source_manager_v1_request *
		request,
	struct wlr_ext_image_capture_source_v1 *source) {
	(void)request;
	stub_accept_calls++;
	stub_last_accept_source = source;
	return true;
}
struct wlr_output *wlr_output_try_from_ext_image_capture_source_v1(
	struct wlr_ext_image_capture_source_v1 *source) {
	(void)source;
	return stub_capture_output;
}
const struct wlr_drm_format_set *wlr_renderer_get_texture_formats(
	struct wlr_renderer *renderer, uint32_t buffer_caps) {
	(void)renderer;
	(void)buffer_caps;
	return stub_texture_formats_valid ? &stub_texture_formats : NULL;
}

/* seat selection */
int stub_primary_set_calls = 0;
struct wlr_primary_selection_source *stub_primary_source = NULL;
uint32_t stub_primary_serial = 0;
int stub_selection_calls = 0;
struct wlr_data_source *stub_selection_source = NULL;
uint32_t stub_selection_serial = 0;
uint32_t stub_next_serial = 42;
const struct wl_interface *stub_global_interface_result = NULL;

void wlr_seat_set_primary_selection(
	struct wlr_seat *seat, struct wlr_primary_selection_source *source,
	uint32_t serial) {
	(void)seat;
	stub_primary_set_calls++;
	stub_primary_source = source;
	stub_primary_serial = serial;
}
void wlr_seat_set_selection(struct wlr_seat *seat,
							struct wlr_data_source *source, uint32_t serial) {
	(void)seat;
	stub_selection_calls++;
	stub_selection_source = source;
	stub_selection_serial = serial;
}
uint32_t wl_display_next_serial(struct wl_display *display) {
	(void)display;
	return stub_next_serial;
}
const struct wl_interface *wl_global_get_interface(
	const struct wl_global *global) {
	(void)global;
	return stub_global_interface_result;
}
struct wl_listener *wl_client_get_destroy_listener(struct wl_client *client,
												   wl_notify_func_t notify) {
	(void)client;
	(void)notify;
	return stub_client_listener;
}
void wl_client_add_destroy_listener(struct wl_client *client,
									struct wl_listener *listener) {
	(void)client;
	stub_added_destroy_listener = listener;
}
