/* Test-only stubs for manage/client_state.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <xcb/xcb_icccm.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/xwayland.h>

Config config = {0};
struct AcwmServer server = {0};

struct wlr_box stub_x11_geo;
int stub_x11_geo_calls = 0;
void client_get_x11_geometry(Client *c, struct wlr_box *xgeo) {
	(void)c;
	stub_x11_geo_calls++;
	*xgeo = stub_x11_geo;
}
uint32_t stub_tag_idx = 0;
uint32_t get_client_tag_idx(const Client *c) {
	(void)c;
	return stub_tag_idx;
}
bool stub_monocle_layout = false;
bool is_monocle_layout(Monitor *m) {
	(void)m;
	return stub_monocle_layout;
}

int stub_source_box_calls = 0;
struct wlr_fbox stub_source_box;
int stub_filter_calls = 0;
int stub_filter_mode = -1;
int stub_dest_calls = 0;
int32_t stub_dest_w = 0, stub_dest_h = 0;
int stub_node_pos_calls = 0;
int32_t stub_node_pos_x = 0, stub_node_pos_y = 0;

void wlr_scene_buffer_set_source_box(struct wlr_scene_buffer *buffer,
									 const struct wlr_fbox *box) {
	(void)buffer;
	stub_source_box_calls++;
	stub_source_box = *box;
}
double stub_source_x(void) { return stub_source_box.x; }
double stub_source_y(void) { return stub_source_box.y; }
double stub_source_width(void) { return stub_source_box.width; }
double stub_source_height(void) { return stub_source_box.height; }
void wlr_scene_buffer_set_filter_mode(struct wlr_scene_buffer *buffer,
									  enum wlr_scale_filter_mode filter_mode) {
	(void)buffer;
	stub_filter_calls++;
	stub_filter_mode = (int)filter_mode;
}
void wlr_scene_buffer_set_dest_size(struct wlr_scene_buffer *buffer, int width,
									int height) {
	(void)buffer;
	stub_dest_calls++;
	stub_dest_w = width;
	stub_dest_h = height;
}
void wlr_scene_node_set_position(struct wlr_scene_node *node, int32_t x,
								 int32_t y) {
	node->x = x;
	node->y = y;
	stub_node_pos_calls++;
	stub_node_pos_x = x;
	stub_node_pos_y = y;
}

int stub_x11_configure_calls = 0;
int16_t stub_x11_configure_x = 0, stub_x11_configure_y = 0;
uint16_t stub_x11_configure_w = 0, stub_x11_configure_h = 0;
void wlr_xwayland_surface_configure(struct wlr_xwayland_surface *surface,
									int16_t x, int16_t y, uint16_t width,
									uint16_t height) {
	(void)surface;
	stub_x11_configure_calls++;
	stub_x11_configure_x = x;
	stub_x11_configure_y = y;
	stub_x11_configure_w = width;
	stub_x11_configure_h = height;
}
int stub_x11_minimize_calls = 0;
bool stub_x11_minimize_value = false;
void wlr_xwayland_surface_set_minimized(struct wlr_xwayland_surface *surface,
										bool minimized) {
	(void)surface;
	stub_x11_minimize_calls++;
	stub_x11_minimize_value = minimized;
}
int stub_x11_maximize_calls = 0;
bool stub_x11_maximize_vert = false;
bool stub_x11_maximize_horz = false;
void wlr_xwayland_surface_set_maximized(struct wlr_xwayland_surface *surface,
										bool maximized_vert,
										bool maximized_horz) {
	(void)surface;
	stub_x11_maximize_calls++;
	stub_x11_maximize_vert = maximized_vert;
	stub_x11_maximize_horz = maximized_horz;
}

int stub_xdg_set_size_calls = 0;
int32_t stub_xdg_set_size_w = 0, stub_xdg_set_size_h = 0;
uint32_t stub_xdg_set_size_result = 7;
uint32_t wlr_xdg_toplevel_set_size(struct wlr_xdg_toplevel *toplevel,
								   int32_t width, int32_t height) {
	(void)toplevel;
	stub_xdg_set_size_calls++;
	stub_xdg_set_size_w = width;
	stub_xdg_set_size_h = height;
	return stub_xdg_set_size_result;
}
int stub_xdg_maximize_calls = 0;
bool stub_xdg_maximize_value = false;
uint32_t wlr_xdg_toplevel_set_maximized(struct wlr_xdg_toplevel *toplevel,
										bool maximized) {
	(void)toplevel;
	stub_xdg_maximize_calls++;
	stub_xdg_maximize_value = maximized;
	return 1;
}
int stub_xdg_tiled_calls = 0;
uint32_t stub_xdg_tiled_edges = 0;
uint32_t wlr_xdg_toplevel_set_tiled(struct wlr_xdg_toplevel *toplevel,
									uint32_t edges) {
	(void)toplevel;
	stub_xdg_tiled_calls++;
	stub_xdg_tiled_edges = edges;
	return 1;
}
int stub_resource_version = 5;
int wl_resource_get_version(const struct wl_resource *resource) {
	(void)resource;
	return stub_resource_version;
}

bool stub_or_wants_focus = false;
bool wlr_xwayland_surface_override_redirect_wants_focus(
	const struct wlr_xwayland_surface *surface) {
	(void)surface;
	return stub_or_wants_focus;
}
int stub_input_model = 1;
enum wlr_xwayland_icccm_input_model wlr_xwayland_surface_icccm_input_model(
	const struct wlr_xwayland_surface *surface) {
	(void)surface;
	return (enum wlr_xwayland_icccm_input_model)stub_input_model;
}
int32_t client_is_unmanaged(Client *c) {
	return c->type == X11 && c->surface.xwayland &&
				   c->surface.xwayland->override_redirect
			   ? 1
			   : 0;
}
int stub_window_type = -1;
bool wlr_xwayland_surface_has_window_type(
	const struct wlr_xwayland_surface *surface,
	enum wlr_xwayland_net_wm_window_type type) {
	(void)surface;
	return (int)type == stub_window_type;
}
