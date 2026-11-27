/* Test-only stubs for input/tablet.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/log.h"
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/ipc/ipc.h"
#include "acwm/input/pointer.h"
#include "acwm/input/tablet.h"
#include "acwm/manage/client.h"
#include "acwm/manage/layer.h"
#include "acwm/manage/misc.h"
#include "acwm/manage/monitor.h"
#include <stddef.h>
#include <string.h>
#include <wlr/backend/libinput.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_cursor.h>
#include <wlr/types/wlr_seat.h>
#include <wlr/types/wlr_tablet_v2.h>

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

bool stub_is_libinput = true;
struct libinput_device *stub_libinput_device = (struct libinput_device *)0x5000;
struct libinput_device_group *stub_device_group = (struct libinput_device_group *)0x6000;
bool wlr_input_device_is_libinput(struct wlr_input_device *d) { (void)d; return stub_is_libinput; }
struct libinput_device *wlr_libinput_get_device_handle(struct wlr_input_device *d) { (void)d; return stub_libinput_device; }
struct libinput_device_group *libinput_device_get_device_group(struct libinput_device *d) { (void)d; return stub_device_group; }
uint32_t stub_send_modes = 0;
int stub_set_mode_calls = 0;
uint32_t stub_set_mode_value = 0;
uint32_t libinput_device_config_send_events_get_modes(struct libinput_device *d) { (void)d; return stub_send_modes; }
enum libinput_config_status libinput_device_config_send_events_set_mode(struct libinput_device *d, enum libinput_config_send_events_mode m) {
	(void)d; stub_set_mode_calls++; stub_set_mode_value = (uint32_t)m;
	return LIBINPUT_CONFIG_STATUS_SUCCESS;
}

struct wlr_tablet stub_wlr_tablet;
struct wlr_tablet_pad stub_wlr_pad;
struct wlr_tablet_tool stub_wlr_tool;
struct wlr_tablet_v2_tablet stub_tablet_v2 = { .wlr_tablet = &stub_wlr_tablet };
struct wlr_tablet_v2_tablet_pad stub_tablet_pad_v2 = { .wlr_pad = &stub_wlr_pad };
struct wlr_tablet_v2_tablet_tool stub_tool_v2 = { .wlr_tool = &stub_wlr_tool };
struct wlr_tablet_v2_tablet *stub_created_tablet = &stub_tablet_v2;
struct wlr_tablet_v2_tablet_pad *stub_created_pad = &stub_tablet_pad_v2;
struct wlr_tablet_v2_tablet_tool *stub_created_tool = &stub_tool_v2;
int stub_tablet_create_calls = 0;
int stub_pad_create_calls = 0;
int stub_tool_create_calls = 0;
struct wlr_tablet_v2_tablet *wlr_tablet_create(struct wlr_tablet_manager_v2 *m, struct wlr_seat *s, struct wlr_input_device *d) {
	(void)m; (void)s; (void)d; stub_tablet_create_calls++; return stub_created_tablet;
}
struct wlr_tablet_v2_tablet_pad *wlr_tablet_pad_create(struct wlr_tablet_manager_v2 *m, struct wlr_seat *s, struct wlr_input_device *d) {
	(void)m; (void)s; (void)d; stub_pad_create_calls++; return stub_created_pad;
}
struct wlr_tablet_v2_tablet_tool *wlr_tablet_tool_create(struct wlr_tablet_manager_v2 *m, struct wlr_seat *s, struct wlr_tablet_tool *t) {
	(void)m; (void)s; (void)t; stub_tool_create_calls++; return stub_created_tool;
}

int stub_attach_calls = 0;
void wlr_cursor_attach_input_device(struct wlr_cursor *c, struct wlr_input_device *d) { (void)c; (void)d; stub_attach_calls++; }
int stub_move_calls = 0;
double stub_move_dx = 0, stub_move_dy = 0;
void wlr_cursor_move(struct wlr_cursor *c, struct wlr_input_device *d, double dx, double dy) {
	(void)c; (void)d; stub_move_calls++; stub_move_dx = dx; stub_move_dy = dy;
}
int stub_warp_calls = 0;
double stub_warp_x = 0, stub_warp_y = 0;
void wlr_cursor_warp_absolute(struct wlr_cursor *c, struct wlr_input_device *d, double x, double y) {
	(void)c; (void)d; stub_warp_calls++; stub_warp_x = x; stub_warp_y = y;
}
int stub_set_surface_calls = 0;
struct wlr_surface *stub_set_surface = NULL;
int32_t stub_set_surface_hx = 0, stub_set_surface_hy = 0;
void wlr_cursor_set_surface(struct wlr_cursor *c, struct wlr_surface *s, int32_t hx, int32_t hy) {
	(void)c; stub_set_surface_calls++; stub_set_surface = s;
	stub_set_surface_hx = hx; stub_set_surface_hy = hy;
}
int stub_map_output_calls = 0;
void wlr_cursor_map_input_to_output(struct wlr_cursor *c, struct wlr_input_device *d, struct wlr_output *o) {
	(void)c; (void)d; (void)o; stub_map_output_calls++;
}

struct wl_client *stub_wl_client = (struct wl_client *)0x7000;
struct wlr_seat_client *stub_seat_client = (struct wlr_seat_client *)0x8000;
struct wl_client *wl_resource_get_client(struct wl_resource *r) { (void)r; return stub_wl_client; }
struct wlr_seat_client *wlr_seat_client_for_wl_client(struct wlr_seat *s, struct wl_client *c) {
	(void)s; (void)c; return stub_seat_client;
}

int stub_motion_calls = 0;
void pointer_process_motion(uint32_t t, struct wlr_input_device *d, double dx, double dy, double ux, double uy) {
	(void)t; (void)d; (void)dx; (void)dy; (void)ux; (void)uy; stub_motion_calls++;
}
bool stub_press_handled = false;
struct wlr_pointer_button_event stub_press_event;
bool pointer_process_button_press(struct wlr_pointer_button_event *e) {
	stub_press_event = *e; return stub_press_handled;
}
int stub_cursor_activity_calls = 0;
void pointer_cursor_activity(void) { stub_cursor_activity_calls++; }

struct Monitor *stub_monitor = NULL;
Monitor *monitor_at_point(double x, double y) { (void)x; (void)y; return stub_monitor; }
int stub_selected_calls = 0;
Monitor *stub_selected_monitor_arg = NULL;
void set_selected_monitor(Monitor *m) { stub_selected_calls++; stub_selected_monitor_arg = m; }
int stub_printstatus_calls = 0;
void printstatus(enum ipc_watch_type t) { (void)t; stub_printstatus_calls++; }

struct wlr_surface *stub_node_surface = NULL;
Client *stub_node_client = NULL;
double stub_node_x = 0, stub_node_y = 0;
void node_at_point(double x, double y, struct wlr_surface **ps, Client **pc, LayerSurface **pl, AcwmBarDecoration **bar, double *nx, double *ny) {
	(void)x; (void)y; (void)pl; (void)bar;
	if (ps) *ps = stub_node_surface;
	if (pc) *pc = stub_node_client;
	if (nx) *nx = stub_node_x;
	if (ny) *ny = stub_node_y;
}

int32_t stub_toplevel_result = -1;
Client *stub_toplevel_client = NULL;
LayerSurface *stub_toplevel_layer = NULL;
int32_t toplevel_from_wlr_surface(struct wlr_surface *s, Client **pc, LayerSurface **pl) {
	(void)s;
	if (pc) *pc = stub_toplevel_client;
	if (pl) *pl = stub_toplevel_layer;
	return stub_toplevel_result;
}
int stub_focus_calls = 0;
void client_focus(Client *c, int32_t lift) { (void)c; (void)lift; stub_focus_calls++; }
int32_t stub_unmanaged = 0, stub_is_x11 = 0;
int32_t client_is_unmanaged(Client *c) { (void)c; return stub_unmanaged; }
int32_t client_is_x11(Client *c) { (void)c; return stub_is_x11; }
bool stub_accepts_tablet = false;
bool wlr_surface_accepts_tablet_v2(struct wlr_surface *s, struct wlr_tablet_v2_tablet *t) {
	(void)s; (void)t; return stub_accepts_tablet;
}

ConfigDeviceRule *stub_rule = NULL;
ConfigDeviceRule *find_device_rule(struct wlr_input_device *d) { (void)d; return stub_rule; }
struct Monitor *stub_target_monitor = NULL;
Monitor *device_target_monitor(struct wlr_input_device *d) { (void)d; return stub_target_monitor; }
int stub_error_calls = 0;
void acwm_error_impl(bool log, enum wlr_log_importance v, const char *f, int l, const char *fmt, ...) {
	(void)log; (void)v; (void)f; (void)l; (void)fmt; stub_error_calls++;
}
int stub_activity_calls = 0;
void acwm_notify_activity(struct wlr_seat *s) { (void)s; stub_activity_calls++; }

int stub_prox_in_calls = 0, stub_prox_out_calls = 0;
void wlr_tablet_v2_tablet_tool_notify_proximity_in(struct wlr_tablet_v2_tablet_tool *t, struct wlr_tablet_v2_tablet *tab, struct wlr_surface *s) {
	(void)t; (void)tab; (void)s; stub_prox_in_calls++;
}
void wlr_tablet_v2_tablet_tool_notify_proximity_out(struct wlr_tablet_v2_tablet_tool *t) { (void)t; stub_prox_out_calls++; }
int stub_tool_motion_calls = 0;
double stub_tool_motion_x = 0, stub_tool_motion_y = 0;
void wlr_tablet_v2_tablet_tool_notify_motion(struct wlr_tablet_v2_tablet_tool *t, double x, double y) {
	(void)t; stub_tool_motion_calls++; stub_tool_motion_x = x; stub_tool_motion_y = y;
}
int stub_pressure_calls = 0; double stub_pressure = 0;
void wlr_tablet_v2_tablet_tool_notify_pressure(struct wlr_tablet_v2_tablet_tool *t, double p) { (void)t; stub_pressure_calls++; stub_pressure = p; }
int stub_distance_calls = 0; double stub_distance = 0;
void wlr_tablet_v2_tablet_tool_notify_distance(struct wlr_tablet_v2_tablet_tool *t, double d) { (void)t; stub_distance_calls++; stub_distance = d; }
int stub_tilt_calls = 0; double stub_tilt_x = 0, stub_tilt_y = 0;
void wlr_tablet_v2_tablet_tool_notify_tilt(struct wlr_tablet_v2_tablet_tool *t, double x, double y) { (void)t; stub_tilt_calls++; stub_tilt_x = x; stub_tilt_y = y; }
int stub_rotation_calls = 0; double stub_rotation = 0;
void wlr_tablet_v2_tablet_tool_notify_rotation(struct wlr_tablet_v2_tablet_tool *t, double d) { (void)t; stub_rotation_calls++; stub_rotation = d; }
int stub_slider_calls = 0; double stub_slider = 0;
void wlr_tablet_v2_tablet_tool_notify_slider(struct wlr_tablet_v2_tablet_tool *t, double p) { (void)t; stub_slider_calls++; stub_slider = p; }
int stub_wheel_calls = 0; double stub_wheel = 0;
void wlr_tablet_v2_tablet_tool_notify_wheel(struct wlr_tablet_v2_tablet_tool *t, double d, int32_t clicks) { (void)t; (void)clicks; stub_wheel_calls++; stub_wheel = d; }
int stub_tool_button_calls = 0; uint32_t stub_tool_button = 0;
void wlr_tablet_v2_tablet_tool_notify_button(struct wlr_tablet_v2_tablet_tool *t, uint32_t b, enum zwp_tablet_pad_v2_button_state s) {
	(void)t; (void)s; stub_tool_button_calls++; stub_tool_button = b;
}
int stub_down_calls = 0, stub_up_calls = 0;
void wlr_tablet_v2_tablet_tool_notify_down(struct wlr_tablet_v2_tablet_tool *t) { (void)t; stub_down_calls++; }
void wlr_tablet_v2_tablet_tool_notify_up(struct wlr_tablet_v2_tablet_tool *t) { (void)t; stub_up_calls++; }
int stub_pad_enter_calls = 0, stub_pad_leave_calls = 0;
uint32_t wlr_tablet_v2_tablet_pad_notify_enter(struct wlr_tablet_v2_tablet_pad *p, struct wlr_tablet_v2_tablet *t, struct wlr_surface *s) {
	(void)p; (void)t; (void)s; stub_pad_enter_calls++; return 1;
}
uint32_t wlr_tablet_v2_tablet_pad_notify_leave(struct wlr_tablet_v2_tablet_pad *p, struct wlr_surface *s) {
	(void)p; (void)s; stub_pad_leave_calls++; return 1;
}
int stub_grab_calls = 0;
void wlr_tablet_tool_v2_start_implicit_grab(struct wlr_tablet_v2_tablet_tool *t) { (void)t; stub_grab_calls++; }
int stub_seat_button_calls = 0;
uint32_t wlr_seat_pointer_notify_button(struct wlr_seat *s, uint32_t t, uint32_t b, enum wl_pointer_button_state st) {
	(void)s; (void)t; (void)b; (void)st; stub_seat_button_calls++; return 1;
}
