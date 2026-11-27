/* Test-only stubs for manage/client_xwayland.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/animation/client.h"
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/ipc/ipc.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"
#include <stddef.h>
#include <string.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_cursor.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/types/wlr_xcursor_manager.h>
#include <wlr/xwayland.h>

Config config = {0};
struct AcwmServer server = {0};

int stub_set_scale_calls = 0;
float stub_set_scale_value = 0;
int stub_is_x11 = 0;
int stub_is_unmanaged = 0;
int stub_is_parked = 0;
struct wlr_surface stub_surface;
struct wlr_surface *stub_client_surface = &stub_surface;
int stub_update_dest_calls = 0;
int stub_focus_calls = 0;
Client *stub_focus_top_client = NULL;
int stub_view_calls = 0;
uint32_t stub_view_tags = 0;
int stub_border_calls = 0;
int stub_pending_min_calls = 0;
int stub_pending_min_value = -1;
int stub_resize_calls = 0;
struct wlr_box stub_resize_geo;
int stub_resize_force = -1;
int stub_arrange_calls = 0;
int stub_motion_calls = 0;
int stub_printstatus_calls = 0;
int stub_primary_init_calls = 0;
int stub_activate_calls = 0;
int stub_configure_calls = 0;
int32_t stub_conf_x, stub_conf_y, stub_conf_w, stub_conf_h;
int stub_signal_add_calls = 0;
int stub_list_remove_calls = 0;
int stub_set_position_calls = 0;
int32_t stub_pos_x = 0, stub_pos_y = 0;
int stub_scene_enabled_calls = 0;
int stub_urgency = 0;
int stub_seat_calls = 0;
int stub_cursor_calls = 0;
int32_t stub_cursor_hotspot_x = 0, stub_cursor_hotspot_y = 0;
int stub_timer_calls = 0;
int32_t stub_timer_ms = 0;
float stub_cursor_scale = 0;
int stub_transformed_calls = 0;
int32_t stub_transformed_w = 0, stub_transformed_h = 0;

void *ecalloc(size_t n, size_t s) { return calloc(n, s); }

void wl_list_remove(struct wl_list *l) {
	if (l) { l->next = l; l->prev = l; }
	stub_list_remove_calls++;
}

void client_set_scale(struct wlr_surface *s, float scale) {
	(void)s;
	stub_set_scale_calls++;
	stub_set_scale_value = scale;
}
void client_update_xwayland_dest_size(Client *c) {
	(void)c;
	stub_update_dest_calls++;
}
void client_focus(Client *c, int32_t lift) {
	(void)c; (void)lift;
	stub_focus_calls++;
}
Client *client_focus_top(Monitor *m) { (void)m; return stub_focus_top_client; }
void client_view_on_monitor(const Arg *arg, bool animate, Monitor *m,
							bool from_rule) {
	(void)animate; (void)m; (void)from_rule;
	stub_view_calls++;
	stub_view_tags = arg->ui;
}
void client_update_border_color(Client *c) {
	(void)c;
	stub_border_calls++;
}
void client_pending_minimized_state(Client *c, int32_t minimized) {
	(void)c;
	stub_pending_min_calls++;
	stub_pending_min_value = minimized;
}
void resize(Client *c, struct wlr_box geo, ResizeOpts opts) {
	(void)c;
	stub_resize_calls++;
	stub_resize_geo = geo;
	stub_resize_force = opts.force_configure ? 1 : 0;
}
void arrange(Monitor *m, bool animate, bool from_view) {
	(void)m; (void)animate; (void)from_view;
	stub_arrange_calls++;
}
void pointer_process_motion(uint32_t time, struct wlr_input_device *dev,
							double dx, double dy, double ux, double uy) {
	(void)time; (void)dev; (void)dx; (void)dy; (void)ux; (void)uy;
	stub_motion_calls++;
}
void printstatus(enum ipc_watch_type type) { (void)type; stub_printstatus_calls++; }
void xwayland_primary_init(void) { stub_primary_init_calls++; }

void handle_client_destroy(struct wl_listener *l, void *d) { (void)l; (void)d; }
void handle_client_request_fullscreen(struct wl_listener *l, void *d) { (void)l; (void)d; }
void handle_client_request_maximize(struct wl_listener *l, void *d) { (void)l; (void)d; }
void handle_client_request_minimize(struct wl_listener *l, void *d) { (void)l; (void)d; }
void handle_client_set_title(struct wl_listener *l, void *d) { (void)l; (void)d; }
void handle_client_map(struct wl_listener *l, void *d) { (void)l; (void)d; }
void handle_client_unmap(struct wl_listener *l, void *d) { (void)l; (void)d; }

void wlr_xwayland_surface_activate(struct wlr_xwayland_surface *s, bool a) {
	(void)s; (void)a; stub_activate_calls++;
}
void wlr_xwayland_surface_configure(struct wlr_xwayland_surface *s, int16_t x,
									int16_t y, uint16_t w, uint16_t h) {
	(void)s;
	stub_configure_calls++;
	stub_conf_x = x; stub_conf_y = y; stub_conf_w = w; stub_conf_h = h;
}
void wlr_xwayland_set_seat(struct wlr_xwayland *x, struct wlr_seat *s) {
	(void)x; (void)s; stub_seat_calls++;
}
void wlr_xwayland_set_cursor(struct wlr_xwayland *x, struct wlr_buffer *b,
							 int32_t hx, int32_t hy) {
	(void)x; (void)b;
	stub_cursor_calls++;
	stub_cursor_hotspot_x = hx;
	stub_cursor_hotspot_y = hy;
}
struct wlr_xcursor_image stub_xcursor_image;
struct wlr_xcursor_image *stub_xcursor_images[2] = { &stub_xcursor_image, NULL };
struct wlr_xcursor stub_xcursor = {
	.image_count = 1,
	.images = stub_xcursor_images,
};
struct wlr_xcursor *wlr_xcursor_manager_get_xcursor(struct wlr_xcursor_manager *m,
													const char *name,
													float scale) {
	(void)m; (void)name;
	stub_cursor_scale = scale;
	return &stub_xcursor;
}
struct wlr_buffer stub_xcursor_buffer;
struct wlr_buffer *wlr_xcursor_image_get_buffer(struct wlr_xcursor_image *i) {
	(void)i;
	return &stub_xcursor_buffer;
}
int wl_event_source_timer_update(struct wl_event_source *s, int32_t ms) {
	(void)s;
	stub_timer_calls++;
	stub_timer_ms = ms;
	return 0;
}
void wlr_output_transformed_resolution(struct wlr_output *o, int32_t *w,
									   int32_t *h) {
	(void)o;
	stub_transformed_calls++;
	*w = stub_transformed_w;
	*h = stub_transformed_h;
}
void wlr_scene_node_set_position(struct wlr_scene_node *n, int32_t x,
								 int32_t y) {
	(void)n;
	stub_set_position_calls++;
	stub_pos_x = x;
	stub_pos_y = y;
}
uint32_t xcb_icccm_wm_hints_get_urgency(xcb_icccm_wm_hints_t *hints) {
	(void)hints;
	return (uint32_t)stub_urgency;
}

struct wlr_surface *client_surface(Client *c) { (void)c; return stub_client_surface; }
int32_t client_is_x11(Client *c) { (void)c; return stub_is_x11; }
int32_t client_is_unmanaged(Client *c) { (void)c; return stub_is_unmanaged; }
bool client_is_parked(Client *c) { (void)c; return stub_is_parked != 0; }
