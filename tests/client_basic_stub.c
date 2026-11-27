/* Test-only stubs for manage/client_basic.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/manage/client.h"
#include "acwm/manage/layer.h"
#include "acwm/manage/monitor.h"
#include <stddef.h>
#include <string.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_fractional_scale_v1.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/types/wlr_seat.h>
#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/xwayland.h>

Config config = {0};
struct AcwmServer server = {0};

uint32_t stub_first_tag = 0;
uint32_t get_tags_first_tag_num(uint32_t source_tags) {
	(void)source_tags;
	return stub_first_tag;
}

struct wlr_box stub_logical_box;
int stub_x11_to_logical_calls = 0;
float stub_x11_scale_arg = 0;
void xwayland_x11_to_logical(struct wlr_box *box, float scale) {
	stub_x11_to_logical_calls++;
	stub_x11_scale_arg = scale;
	*box = stub_logical_box;
}

struct wlr_surface *stub_root_result = NULL;
struct wlr_surface *wlr_surface_get_root_surface(struct wlr_surface *surface) {
	return stub_root_result ? stub_root_result : surface;
}

struct wlr_xwayland_surface *stub_xsurface_result = NULL;
struct wlr_xwayland_surface *wlr_xwayland_surface_try_from_wlr_surface(
	struct wlr_surface *surface) {
	(void)surface;
	return stub_xsurface_result;
}
struct wlr_layer_surface_v1 *stub_layer_result = NULL;
struct wlr_layer_surface_v1 *wlr_layer_surface_v1_try_from_wlr_surface(
	struct wlr_surface *surface) {
	(void)surface;
	return stub_layer_result;
}
struct wlr_xdg_surface *stub_xdg_result = NULL;
struct wlr_xdg_surface *stub_xdg_queue[4];
int stub_xdg_count = 0;
int stub_xdg_index = 0;
struct wlr_xdg_surface *wlr_xdg_surface_try_from_wlr_surface(
	struct wlr_surface *surface) {
	(void)surface;
	if (stub_xdg_index < stub_xdg_count)
		return stub_xdg_queue[stub_xdg_index++];
	return stub_xdg_result;
}
struct wlr_xdg_toplevel *stub_toplevel_result = NULL;
struct wlr_xdg_toplevel *wlr_xdg_toplevel_try_from_wlr_surface(
	struct wlr_surface *surface) {
	(void)surface;
	return stub_toplevel_result;
}

int stub_xwayland_minimize_calls = 0;
bool stub_xwayland_minimize_value = false;
int stub_xwayland_activate_calls = 0;
bool stub_xwayland_activate_value = false;
void wlr_xwayland_surface_set_minimized(struct wlr_xwayland_surface *surface,
										bool minimized) {
	(void)surface;
	stub_xwayland_minimize_calls++;
	stub_xwayland_minimize_value = minimized;
}
void wlr_xwayland_surface_activate(struct wlr_xwayland_surface *surface,
								   bool activated) {
	(void)surface;
	stub_xwayland_activate_calls++;
	stub_xwayland_activate_value = activated;
}
int stub_xwayland_close_calls = 0;
void wlr_xwayland_surface_close(struct wlr_xwayland_surface *surface) {
	(void)surface;
	stub_xwayland_close_calls++;
}
int stub_xwayland_fullscreen_calls = 0;
bool stub_xwayland_fullscreen_value = false;
void wlr_xwayland_surface_set_fullscreen(
	struct wlr_xwayland_surface *surface, bool fullscreen) {
	(void)surface;
	stub_xwayland_fullscreen_calls++;
	stub_xwayland_fullscreen_value = fullscreen;
}
int stub_window_type = -1;
bool wlr_xwayland_surface_has_window_type(
	const struct wlr_xwayland_surface *surface,
	enum wlr_xwayland_net_wm_window_type type) {
	(void)surface;
	return (int)type == stub_window_type;
}

int stub_activated_calls = 0;
bool stub_activated_value = false;
uint32_t wlr_xdg_toplevel_set_activated(struct wlr_xdg_toplevel *toplevel,
										bool activated) {
	(void)toplevel;
	stub_activated_calls++;
	stub_activated_value = activated;
	return 1;
}
int stub_send_close_calls = 0;
void wlr_xdg_toplevel_send_close(struct wlr_xdg_toplevel *toplevel) {
	(void)toplevel;
	stub_send_close_calls++;
}
int stub_xdg_fullscreen_calls = 0;
bool stub_xdg_fullscreen_value = false;
uint32_t wlr_xdg_toplevel_set_fullscreen(struct wlr_xdg_toplevel *toplevel,
										 bool fullscreen) {
	(void)toplevel;
	stub_xdg_fullscreen_calls++;
	stub_xdg_fullscreen_value = fullscreen;
	return 1;
}

pid_t stub_pid = 0;
int stub_credentials_calls = 0;
void wl_client_get_credentials(const struct wl_client *client, pid_t *pid,
							   uid_t *uid, gid_t *gid) {
	(void)client;
	(void)uid;
	(void)gid;
	stub_credentials_calls++;
	if (pid)
		*pid = stub_pid;
}

int stub_notify_enter_calls = 0;
struct wlr_surface *stub_notify_enter_surface = NULL;
int stub_notify_keycode_count = -1;
void wlr_seat_keyboard_notify_enter(struct wlr_seat *seat,
									struct wlr_surface *surface,
									const uint32_t *keycodes, size_t num_keycodes,
									const struct wlr_keyboard_modifiers *modifiers) {
	(void)seat;
	(void)keycodes;
	(void)modifiers;
	stub_notify_enter_calls++;
	stub_notify_enter_surface = surface;
	stub_notify_keycode_count = (int)num_keycodes;
}

bool stub_coords_ok = true;
int stub_coords_calls = 0;
bool wlr_scene_node_coords(struct wlr_scene_node *node, int *lx, int *ly) {
	(void)node;
	stub_coords_calls++;
	if (lx)
		*lx = 0;
	if (ly)
		*ly = 0;
	return stub_coords_ok;
}

int stub_rect_color_calls = 0;
float stub_rect_color[4];
void wlr_scene_rect_set_color(struct wlr_scene_rect *rect,
							  const float color[4]) {
	(void)rect;
	stub_rect_color_calls++;
	memcpy(stub_rect_color, color, sizeof(stub_rect_color));
}
int stub_dim_color_calls = 0;
float stub_dim_color[4];
void acwm_dim_node_set_color(AcwmDimNode *node, const float color[4]) {
	(void)node;
	stub_dim_color_calls++;
	memcpy(stub_dim_color, color, sizeof(stub_dim_color));
}

int stub_fractional_scale_calls = 0;
double stub_fractional_scale = 0;
void wlr_fractional_scale_v1_notify_scale(struct wlr_surface *surface,
										  double scale) {
	(void)surface;
	stub_fractional_scale_calls++;
	stub_fractional_scale = scale;
}
int stub_buffer_scale_calls = 0;
int32_t stub_buffer_scale = 0;
void wlr_surface_set_preferred_buffer_scale(struct wlr_surface *surface,
											int32_t scale) {
	(void)surface;
	stub_buffer_scale_calls++;
	stub_buffer_scale = scale;
}
