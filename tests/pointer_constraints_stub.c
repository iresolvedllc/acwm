/* Test-only stubs for input/pointer_constraints.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/input/pointer.h"
#include "acwm/manage/client.h"
#include <stddef.h>
#include <string.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_cursor.h>
#include <wlr/types/wlr_pointer.h>
#include <wlr/types/wlr_seat.h>

Config config = {0};
struct AcwmServer server = {0};
struct LastCursor last_cursor;
bool pointer_locked_applied = false;

int stub_list_insert_calls = 0;
int stub_list_remove_calls = 0;
void wl_list_init(struct wl_list *l) { l->next = l; l->prev = l; }
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
int stub_tap_fingers = 0;
bool wlr_input_device_is_libinput(struct wlr_input_device *d) { (void)d; return stub_is_libinput; }
struct libinput_device *wlr_libinput_get_device_handle(struct wlr_input_device *d) { (void)d; return (struct libinput_device *)0x5000; }
int stub_seat_device_add_calls = 0;
void handle_input_device_destroy(struct wl_listener *l, void *d) { (void)l; (void)d; }
int stub_attach_calls = 0;
void wlr_cursor_attach_input_device(struct wlr_cursor *c, struct wlr_input_device *d) { (void)c; (void)d; stub_attach_calls++; }
int stub_warp_calls = 0;
double stub_warp_x = 0, stub_warp_y = 0;
bool wlr_cursor_warp(struct wlr_cursor *c, struct wlr_input_device *d, double x, double y) {
	(void)d; stub_warp_calls++; stub_warp_x = x; stub_warp_y = y;
	if (c) { c->x = x; c->y = y; }
	return true;
}
void wlr_cursor_warp_absolute(struct wlr_cursor *c, struct wlr_input_device *d, double x, double y) {
	(void)c; (void)d; (void)x; (void)y;
}
double stub_abs_lx = 0, stub_abs_ly = 0;
void wlr_cursor_absolute_to_layout_coords(struct wlr_cursor *c, struct wlr_input_device *d, double x, double y, double *lx, double *ly) {
	(void)c; (void)d; (void)x; (void)y; *lx = stub_abs_lx; *ly = stub_abs_ly;
}
int stub_set_xcursor_calls = 0;
const char *stub_xcursor_name = NULL;
void wlr_cursor_set_xcursor(struct wlr_cursor *c, struct wlr_xcursor_manager *m, const char *name) {
	(void)c; (void)m; stub_set_xcursor_calls++; stub_xcursor_name = name;
}
const char *wlr_cursor_shape_v1_name(enum wp_cursor_shape_device_v1_shape s) { (void)s; return "shape"; }
int stub_seat_warp_calls = 0;
void wlr_seat_pointer_warp(struct wlr_seat *s, double x, double y) { (void)s; (void)x; (void)y; stub_seat_warp_calls++; }
int stub_pointer_frame_calls = 0;
void wlr_seat_pointer_notify_frame(struct wlr_seat *s) { (void)s; stub_pointer_frame_calls++; }
int stub_axis_calls = 0;
double stub_axis_value = 0;
int32_t stub_axis_discrete = 0;
void wlr_seat_pointer_notify_axis(struct wlr_seat *s, uint32_t t, enum wl_pointer_axis o, double v, int32_t d, enum wl_pointer_axis_source src, enum wl_pointer_axis_relative_direction rel) {
	(void)s; (void)t; (void)o; (void)src; (void)rel;
	stub_axis_calls++; stub_axis_value = v; stub_axis_discrete = d;
}
int stub_button_calls = 0;
uint32_t wlr_seat_pointer_notify_button(struct wlr_seat *s, uint32_t t, uint32_t b, enum wl_pointer_button_state st) {
	(void)s; (void)t; (void)b; (void)st; stub_button_calls++; return 1;
}
bool stub_contains = true;
bool wlr_box_contains_point(const struct wlr_box *b, double x, double y) { (void)b; (void)x; (void)y; return stub_contains; }
void wlr_box_closest_point(const struct wlr_box *b, double x, double y, double *dx, double *dy) {
	(void)b; *dx = x; *dy = y;
}

int stub_motion_calls = 0;
void pointer_process_motion(uint32_t t, struct wlr_input_device *d, double dx, double dy, double ux, double uy) {
	(void)t; (void)d; (void)dx; (void)dy; (void)ux; (void)uy; stub_motion_calls++;
}
bool stub_press_handled = false;
bool pointer_process_button_press(struct wlr_pointer_button_event *e) { (void)e; return stub_press_handled; }
int stub_activity_calls = 0;
void pointer_cursor_activity(void) { stub_activity_calls++; }
int stub_notify_device_calls = 0;
void ipc_notify_device_event(struct wlr_input_device *d) { (void)d; stub_notify_device_calls++; }
bool stub_is_trackpad = false, stub_trackpad_disabled = false;
bool pointer_is_trackpad(struct wlr_pointer *p) { (void)p; return stub_is_trackpad; }
bool check_trackpad_disabled(struct wlr_pointer *p) { (void)p; return stub_trackpad_disabled; }
uint32_t stub_mods = 0;
uint32_t keyboard_hard_modifiers(void) { return stub_mods; }
int stub_cancel_release_calls = 0;
void keyboard_cancel_pending_release_bind(void) { stub_cancel_release_calls++; }
int stub_acwm_activity_calls = 0;
void acwm_notify_activity(struct wlr_seat *s) { (void)s; stub_acwm_activity_calls++; }
int stub_toggle_overview_calls = 0;
int32_t toggle_overview(const Arg *a) { (void)a; stub_toggle_overview_calls++; return 0; }

ConfigDeviceRule *stub_rule = NULL;
ConfigDeviceRule *find_device_rule(struct wlr_input_device *d) { (void)d; return stub_rule; }

int stub_natural = -1;
int stub_accel_profile_calls = 0;
uint32_t stub_accel_profile = 0;
double stub_accel_speed = 0;
int stub_tap_enabled = -1, stub_tap_drag = -1, stub_tap_lock = -1;
uint32_t stub_tap_map = 0;
int stub_dwt = -1, stub_left = -1, stub_middle = -1;
uint32_t stub_scroll_method = 0, stub_scroll_button = 0;
uint32_t stub_click_method = 0;
uint32_t stub_send_mode = 0;
uint32_t stub_scroll_methods = 1;
uint32_t stub_click_methods = 1;
uint32_t stub_send_modes = 1;
enum libinput_config_status libinput_device_config_scroll_set_natural_scroll_enabled(struct libinput_device *d, int e) { (void)d; stub_natural = e; return LIBINPUT_CONFIG_STATUS_SUCCESS; }
int libinput_device_config_accel_is_available(struct libinput_device *d) { (void)d; return 1; }
enum libinput_config_status libinput_device_config_accel_set_profile(struct libinput_device *d, enum libinput_config_accel_profile p) { (void)d; stub_accel_profile_calls++; stub_accel_profile = (uint32_t)p; return LIBINPUT_CONFIG_STATUS_SUCCESS; }
enum libinput_config_status libinput_device_config_accel_set_speed(struct libinput_device *d, double s) { (void)d; stub_accel_speed = s; return LIBINPUT_CONFIG_STATUS_SUCCESS; }
int libinput_device_config_tap_get_finger_count(struct libinput_device *d) { (void)d; return stub_tap_fingers; }
enum libinput_config_status libinput_device_config_tap_set_enabled(struct libinput_device *d, enum libinput_config_tap_state e) { (void)d; stub_tap_enabled = (int)e; return LIBINPUT_CONFIG_STATUS_SUCCESS; }
enum libinput_config_status libinput_device_config_tap_set_drag_enabled(struct libinput_device *d, enum libinput_config_drag_state e) { (void)d; stub_tap_drag = (int)e; return LIBINPUT_CONFIG_STATUS_SUCCESS; }
enum libinput_config_status libinput_device_config_tap_set_drag_lock_enabled(struct libinput_device *d, enum libinput_config_drag_lock_state e) { (void)d; stub_tap_lock = (int)e; return LIBINPUT_CONFIG_STATUS_SUCCESS; }
enum libinput_config_status libinput_device_config_tap_set_button_map(struct libinput_device *d, enum libinput_config_tap_button_map m) { (void)d; stub_tap_map = (uint32_t)m; return LIBINPUT_CONFIG_STATUS_SUCCESS; }
int libinput_device_config_dwt_is_available(struct libinput_device *d) { (void)d; return 1; }
enum libinput_config_status libinput_device_config_dwt_set_enabled(struct libinput_device *d, enum libinput_config_dwt_state e) { (void)d; stub_dwt = (int)e; return LIBINPUT_CONFIG_STATUS_SUCCESS; }
int libinput_device_config_left_handed_is_available(struct libinput_device *d) { (void)d; return 1; }
enum libinput_config_status libinput_device_config_left_handed_set(struct libinput_device *d, int e) { (void)d; stub_left = (int)e; return LIBINPUT_CONFIG_STATUS_SUCCESS; }
int libinput_device_config_middle_emulation_is_available(struct libinput_device *d) { (void)d; return 1; }
enum libinput_config_status libinput_device_config_middle_emulation_set_enabled(struct libinput_device *d, enum libinput_config_middle_emulation_state e) { (void)d; stub_middle = (int)e; return LIBINPUT_CONFIG_STATUS_SUCCESS; }
uint32_t libinput_device_config_scroll_get_methods(struct libinput_device *d) { (void)d; return stub_scroll_methods; }
enum libinput_config_status libinput_device_config_scroll_set_method(struct libinput_device *d, enum libinput_config_scroll_method m) { (void)d; stub_scroll_method = (uint32_t)m; return LIBINPUT_CONFIG_STATUS_SUCCESS; }
enum libinput_config_status libinput_device_config_scroll_set_button(struct libinput_device *d, uint32_t b) { (void)d; stub_scroll_button = b; return LIBINPUT_CONFIG_STATUS_SUCCESS; }
uint32_t libinput_device_config_click_get_methods(struct libinput_device *d) { (void)d; return stub_click_methods; }
enum libinput_config_status libinput_device_config_click_set_method(struct libinput_device *d, enum libinput_config_click_method m) { (void)d; stub_click_method = (uint32_t)m; return LIBINPUT_CONFIG_STATUS_SUCCESS; }
uint32_t libinput_device_config_send_events_get_modes(struct libinput_device *d) { (void)d; return stub_send_modes; }
enum libinput_config_status libinput_device_config_send_events_set_mode(struct libinput_device *d, enum libinput_config_send_events_mode m) { (void)d; stub_send_mode = (uint32_t)m; return LIBINPUT_CONFIG_STATUS_SUCCESS; }

int stub_keybinding_calls = 0;
int32_t stub_keybinding_func(const Arg *a) { (void)a; stub_keybinding_calls++; return 0; }
int stub_activated_calls = 0, stub_deactivated_calls = 0;
void wlr_pointer_constraint_v1_send_activated(struct wlr_pointer_constraint_v1 *c) { (void)c; stub_activated_calls++; }
void wlr_pointer_constraint_v1_send_deactivated(struct wlr_pointer_constraint_v1 *c) { (void)c; stub_deactivated_calls++; }
struct wlr_pointer_constraint_v1 *stub_for_surface = NULL;
struct wlr_pointer_constraint_v1 *wlr_pointer_constraints_v1_constraint_for_surface(
	struct wlr_pointer_constraints_v1 *pc, struct wlr_surface *s, struct wlr_seat *seat) {
	(void)pc; (void)s; (void)seat; return stub_for_surface;
}

Client *stub_focus_top = NULL;
Client *client_focus_top(Monitor *m) { (void)m; return stub_focus_top; }
int stub_focus_calls = 0;
void client_focus(Client *c, int32_t lift) { (void)c; (void)lift; stub_focus_calls++; }
struct wlr_surface stub_surface;
struct wlr_surface *stub_client_surface = &stub_surface;
struct wlr_surface *client_surface(Client *c) { (void)c; return stub_client_surface; }
int stub_is_x11 = 0;
int32_t client_is_x11(Client *c) { (void)c; return stub_is_x11; }
int32_t stub_toplevel_result = -1;
Client *stub_toplevel_client = NULL;
int32_t toplevel_from_wlr_surface(struct wlr_surface *s, Client **pc, LayerSurface **pl) {
	(void)s;
	if (pc) *pc = stub_toplevel_client;
	if (pl) *pl = NULL;
	return stub_toplevel_result;
}
void *ecalloc(size_t n, size_t s) { return calloc(n, s); }
