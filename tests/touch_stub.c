/* Test-only stubs for input/touch.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/log.h"
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/input/pointer.h"
#include "acwm/input/touch.h"
#include "acwm/ipc/ipc.h"
#include "acwm/manage/client.h"
#include "acwm/manage/misc.h"
#include "acwm/manage/monitor.h"
#include <stddef.h>
#include <string.h>
#include <wlr/backend/libinput.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_cursor.h>
#include <wlr/types/wlr_seat.h>
#include <wlr/types/wlr_touch.h>

void *ecalloc(size_t n, size_t s) { return calloc(n, s); }

Config config = {0};
struct AcwmServer server = {0};

int stub_list_insert_calls = 0;
int stub_list_remove_calls = 0;
int stub_list_init_calls = 0;
void wl_list_init(struct wl_list *l) { l->next = l; l->prev = l; stub_list_init_calls++; }
void wl_list_insert(struct wl_list *l, struct wl_list *e) {
	e->next = e; e->prev = e;
	if (l) { e->next = l->next; e->prev = l; l->next->prev = e; l->next = e; }
	stub_list_insert_calls++;
}
void wl_list_remove(struct wl_list *e) {
	if (e->prev && e->next) { e->prev->next = e->next; e->next->prev = e->prev; }
	e->next = e; e->prev = e;
	stub_list_remove_calls++;
}
int wl_list_length(const struct wl_list *l) {
	const struct wl_list *p = l->next; int n = 0;
	while (p != l) { p = p->next; n++; }
	return n;
}

struct Monitor *stub_target_monitor = NULL;
int stub_map_output_calls = 0;
struct wlr_output *stub_mapped_output = NULL;
void wlr_cursor_map_input_to_output(struct wlr_cursor *cur,
									struct wlr_input_device *dev,
									struct wlr_output *out) {
	(void)cur; (void)dev;
	stub_map_output_calls++;
	stub_mapped_output = out;
}
int stub_error_calls = 0;
void acwm_error_impl(bool log, enum wlr_log_importance verbosity,
					 const char *file, int line, const char *fmt, ...) {
	(void)log; (void)verbosity; (void)file; (void)line; (void)fmt;
	stub_error_calls++;
}
Monitor *device_target_monitor(struct wlr_input_device *d) {
	(void)d;
	return stub_target_monitor;
}

bool stub_is_libinput = false;
struct libinput_device *stub_libinput_device = (struct libinput_device *)0x5000;
bool wlr_input_device_is_libinput(struct wlr_input_device *d) {
	(void)d;
	return stub_is_libinput;
}
struct libinput_device *wlr_libinput_get_device_handle(struct wlr_input_device *d) {
	(void)d;
	return stub_libinput_device;
}
uint32_t stub_send_modes = 0;
int stub_set_mode_calls = 0;
uint32_t stub_set_mode_value = 0;
uint32_t libinput_device_config_send_events_get_modes(struct libinput_device *d) {
	(void)d;
	return stub_send_modes;
}
enum libinput_config_status
libinput_device_config_send_events_set_mode(struct libinput_device *d,
											enum libinput_config_send_events_mode m) {
	(void)d;
	stub_set_mode_calls++;
	stub_set_mode_value = (uint32_t)m;
	return LIBINPUT_CONFIG_STATUS_SUCCESS;
}

int stub_attach_calls = 0;
void wlr_cursor_attach_input_device(struct wlr_cursor *c,
									struct wlr_input_device *d) {
	(void)c; (void)d;
	stub_attach_calls++;
}

double stub_lx = 0, stub_ly = 0;
void wlr_cursor_absolute_to_layout_coords(struct wlr_cursor *c,
										  struct wlr_input_device *d,
										  double x, double y, double *lx,
										  double *ly) {
	(void)c; (void)d; (void)x; (void)y;
	*lx = stub_lx; *ly = stub_ly;
}
int stub_warp_calls = 0;
double stub_warp_x = 0, stub_warp_y = 0;
void wlr_cursor_warp_absolute(struct wlr_cursor *c,
							  struct wlr_input_device *d, double x, double y) {
	(void)c; (void)d;
	stub_warp_calls++;
	stub_warp_x = x;
	stub_warp_y = y;
}

struct wlr_surface *stub_node_surface = NULL;
Client *stub_node_client = NULL;
double stub_node_x = 0, stub_node_y = 0;
void node_at_point(double x, double y, struct wlr_surface **psurface,
				   Client **pc, LayerSurface **pl, AcwmBarDecoration **bar,
				   double *nx, double *ny) {
	(void)x; (void)y; (void)pl; (void)bar;
	if (psurface) *psurface = stub_node_surface;
	if (pc) *pc = stub_node_client;
	if (nx) *nx = stub_node_x;
	if (ny) *ny = stub_node_y;
}

int stub_motion_calls = 0;
double stub_motion_dx = 0, stub_motion_dy = 0;
uint32_t stub_motion_time = 0;
void pointer_process_motion(uint32_t time, struct wlr_input_device *dev,
							double dx, double dy, double ux, double uy) {
	(void)dev; (void)ux; (void)uy;
	stub_motion_calls++;
	stub_motion_dx = dx;
	stub_motion_dy = dy;
	stub_motion_time = time;
}
int stub_press_calls = 0;
bool stub_press_handled = false;
struct wlr_pointer_button_event stub_press_event;
bool pointer_process_button_press(struct wlr_pointer_button_event *ev) {
	stub_press_calls++;
	stub_press_event = *ev;
	return stub_press_handled;
}
int stub_button_calls = 0;
uint32_t stub_button = 0;
enum wl_pointer_button_state stub_button_state = 0;
uint32_t stub_button_time = 0;
uint32_t wlr_seat_pointer_notify_button(struct wlr_seat *s, uint32_t t,
										uint32_t b,
										enum wl_pointer_button_state st) {
	(void)s;
	stub_button_calls++;
	stub_button_time = t;
	stub_button = b;
	stub_button_state = st;
	return 1;
}
int stub_pointer_frame_calls = 0;
void wlr_seat_pointer_notify_frame(struct wlr_seat *s) {
	(void)s;
	stub_pointer_frame_calls++;
}
int stub_clear_focus_calls = 0;
void wlr_seat_pointer_notify_clear_focus(struct wlr_seat *s) {
	(void)s;
	stub_clear_focus_calls++;
}
int stub_hide_cursor_calls = 0;
int32_t pointer_hide_cursor(void *d) { (void)d; stub_hide_cursor_calls++; return 0; }

int stub_activity_calls = 0;
void acwm_notify_activity(struct wlr_seat *s) {
	(void)s;
	stub_activity_calls++;
}
int stub_ipc_device_calls = 0;
void ipc_notify_device_event(struct wlr_input_device *d) {
	(void)d;
	stub_ipc_device_calls++;
}

bool stub_accepts_touch = false;
bool wlr_surface_accepts_touch(struct wlr_surface *s, struct wlr_seat *seat) {
	(void)s; (void)seat;
	return stub_accepts_touch;
}
int32_t stub_toplevel_result = 0;
Client *stub_toplevel_client = NULL;
int32_t toplevel_from_wlr_surface(struct wlr_surface *s, Client **pc,
								  LayerSurface **pl) {
	(void)s; (void)pl;
	if (pc) *pc = stub_toplevel_client;
	return stub_toplevel_result;
}
int stub_is_x11 = 0;
int32_t client_is_x11(Client *c) { (void)c; return stub_is_x11; }

int stub_touch_down_calls = 0;
int32_t stub_down_id = -1;
double stub_down_sx = 0, stub_down_sy = 0;
uint32_t stub_down_time = 0;
uint32_t wlr_seat_touch_notify_down(struct wlr_seat *s,
									struct wlr_surface *surface,
									uint32_t t, int32_t id, double sx,
									double sy) {
	(void)s; (void)surface;
	stub_touch_down_calls++;
	stub_down_time = t;
	stub_down_id = id;
	stub_down_sx = sx;
	stub_down_sy = sy;
	return 1;
}
int stub_touch_motion_calls = 0;
int32_t stub_touch_motion_id = -1;
double stub_touch_motion_sx = 0, stub_touch_motion_sy = 0;
void wlr_seat_touch_notify_motion(struct wlr_seat *s, uint32_t t, int32_t id,
								  double sx, double sy) {
	(void)s; (void)t;
	stub_touch_motion_calls++;
	stub_touch_motion_id = id;
	stub_touch_motion_sx = sx;
	stub_touch_motion_sy = sy;
}
int stub_touch_up_calls = 0;
int32_t stub_touch_up_id = -1;
uint32_t wlr_seat_touch_notify_up(struct wlr_seat *s, uint32_t t, int32_t id) {
	(void)s; (void)t;
	stub_touch_up_calls++;
	stub_touch_up_id = id;
	return 1;
}
int stub_touch_cancel_calls = 0;
void wlr_seat_touch_notify_cancel(struct wlr_seat *s,
								  struct wlr_seat_client *c) {
	(void)s; (void)c;
	stub_touch_cancel_calls++;
}
int stub_touch_frame_calls = 0;
void wlr_seat_touch_notify_frame(struct wlr_seat *s) {
	(void)s;
	stub_touch_frame_calls++;
}
