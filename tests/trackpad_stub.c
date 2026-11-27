/* Test-only stubs for input/trackpad.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/animation/client.h"
#include "acwm/animation/common.h"
#include "acwm/common/log.h"
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/dispatch/bind.h"
#include "acwm/input/keyboard.h"
#include "acwm/input/pointer.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"
#include <stddef.h>
#include <string.h>
#include <wlr/backend/libinput.h>
#include <wlr/types/wlr_cursor.h>
#include <wlr/types/wlr_pointer.h>
#include <wlr/types/wlr_seat.h>

Config config = {0};
struct AcwmServer server = {0};

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
struct libinput_device *wlr_libinput_get_device_handle(struct wlr_input_device *d) {
	(void)d; return (struct libinput_device *)0x5000;
}
int libinput_device_config_tap_get_finger_count(struct libinput_device *d) { (void)d; return stub_tap_fingers; }

uint32_t stub_mods = 0;
uint32_t keyboard_hard_modifiers(void) { return stub_mods; }
int stub_cancel_release_calls = 0;
void keyboard_cancel_pending_release_bind(void) { stub_cancel_release_calls++; }

bool stub_begin_move_ok = true;
int stub_begin_move_calls = 0;
uint32_t stub_begin_move_mode = 0;
bool pointer_begin_move_resize(Client *gc, uint32_t mode, double x, double y, uint32_t a) {
	(void)gc; (void)x; (void)y; (void)a;
	stub_begin_move_calls++; stub_begin_move_mode = mode;
	if (stub_begin_move_ok)
		server.grab_client = gc;
	return stub_begin_move_ok;
}
int stub_end_grab_calls = 0;
void pointer_end_grab_client(bool follow_pointer) { (void)follow_pointer; stub_end_grab_calls++; }
int stub_motion_calls = 0;
double stub_motion_dx = 0, stub_motion_dy = 0;
void pointer_process_motion(uint32_t t, struct wlr_input_device *d, double dx, double dy, double ux, double uy) {
	(void)t; (void)d; (void)ux; (void)uy;
	stub_motion_calls++; stub_motion_dx = dx; stub_motion_dy = dy;
}

uint32_t stub_curtag = 0;
uint32_t get_mon_curtag(const Monitor *m) { (void)m; return stub_curtag; }
int stub_set_progress_calls = 0;
double stub_set_progress = 0;
void client_animation_set_progress(Client *c, double p) { (void)c; stub_set_progress_calls++; stub_set_progress = p; }
int stub_resume_calls = 0;
double stub_resume_remaining = 0;
void client_animation_resume(Client *c, double r) { (void)c; stub_resume_calls++; stub_resume_remaining = r; }
int stub_clip_calls = 0;
void client_apply_clip(Client *c, float f) { (void)c; (void)f; stub_clip_calls++; }
int stub_focus_calls = 0;
Client *stub_focus_arg = NULL;
void client_focus(Client *c, int32_t lift) { (void)lift; stub_focus_calls++; stub_focus_arg = c; }
int stub_fresh_calls = 0;
void request_fresh_all_monitors(void) { stub_fresh_calls++; }
int stub_arrange_calls = 0;
void arrange(Monitor *m, bool a, bool v) { (void)m; (void)a; (void)v; stub_arrange_calls++; }
int stub_scene_pos_calls = 0;
int32_t stub_scene_x = 0, stub_scene_y = 0;
void wlr_scene_node_set_position(struct wlr_scene_node *n, int32_t x, int32_t y) {
	(void)n;
	stub_scene_pos_calls++; stub_scene_x = x; stub_scene_y = y;
}

int stub_swipe_begin_calls = 0, stub_swipe_update_calls = 0, stub_swipe_end_calls = 0;
void wlr_pointer_gestures_v1_send_swipe_begin(struct wlr_pointer_gestures_v1 *g, struct wlr_seat *s, uint32_t t, uint32_t f) {
	(void)g; (void)s; (void)t; (void)f; stub_swipe_begin_calls++;
}
void wlr_pointer_gestures_v1_send_swipe_update(struct wlr_pointer_gestures_v1 *g, struct wlr_seat *s, uint32_t t, double dx, double dy) {
	(void)g; (void)s; (void)t; (void)dx; (void)dy; stub_swipe_update_calls++;
}
void wlr_pointer_gestures_v1_send_swipe_end(struct wlr_pointer_gestures_v1 *g, struct wlr_seat *s, uint32_t t, bool cn) {
	(void)g; (void)s; (void)t; (void)cn; stub_swipe_end_calls++;
}
int stub_pinch_begin_calls = 0, stub_pinch_update_calls = 0, stub_pinch_end_calls = 0;
void wlr_pointer_gestures_v1_send_pinch_begin(struct wlr_pointer_gestures_v1 *g, struct wlr_seat *s, uint32_t t, uint32_t f) {
	(void)g; (void)s; (void)t; (void)f; stub_pinch_begin_calls++;
}
void wlr_pointer_gestures_v1_send_pinch_update(struct wlr_pointer_gestures_v1 *g, struct wlr_seat *s, uint32_t t, double dx, double dy, double sc, double r) {
	(void)g; (void)s; (void)t; (void)dx; (void)dy; (void)sc; (void)r; stub_pinch_update_calls++;
}
void wlr_pointer_gestures_v1_send_pinch_end(struct wlr_pointer_gestures_v1 *g, struct wlr_seat *s, uint32_t t, bool cn) {
	(void)g; (void)s; (void)t; (void)cn; stub_pinch_end_calls++;
}
int stub_hold_begin_calls = 0, stub_hold_end_calls = 0;
void wlr_pointer_gestures_v1_send_hold_begin(struct wlr_pointer_gestures_v1 *g, struct wlr_seat *s, uint32_t t, uint32_t f) {
	(void)g; (void)s; (void)t; (void)f; stub_hold_begin_calls++;
}
void wlr_pointer_gestures_v1_send_hold_end(struct wlr_pointer_gestures_v1 *g, struct wlr_seat *s, uint32_t t, bool cn) {
	(void)g; (void)s; (void)t; (void)cn; stub_hold_end_calls++;
}

int stub_view_left_calls = 0, stub_view_right_calls = 0;
int stub_view_left_have_calls = 0, stub_view_right_have_calls = 0;
int stub_viewprev_calls = 0, stub_viewnext_calls = 0;
int stub_toggle_overview_calls = 0, stub_enter_overview_calls = 0, stub_leave_overview_calls = 0;
int stub_focus_direction_calls = 0;
int32_t stub_focus_direction_arg = 0;
int stub_move_resize_calls = 0;
int32_t view_to_left(const Arg *a) { (void)a; stub_view_left_calls++; return 0; }
int32_t view_to_right(const Arg *a) { (void)a; stub_view_right_calls++; return 0; }
int32_t view_to_left_have_client(const Arg *a) { (void)a; stub_view_left_have_calls++; return 0; }
int32_t view_to_right_have_client(const Arg *a) { (void)a; stub_view_right_have_calls++; return 0; }
int32_t viewprev_have_client(const Arg *a) { (void)a; stub_viewprev_calls++; return 0; }
int32_t viewnext_have_client(const Arg *a) { (void)a; stub_viewnext_calls++; return 0; }
int32_t toggle_overview(const Arg *a) { (void)a; stub_toggle_overview_calls++; return 0; }
int32_t enter_overview(const Arg *a) { (void)a; stub_enter_overview_calls++; return 0; }
int32_t leave_overview(const Arg *a) { (void)a; stub_leave_overview_calls++; return 0; }
int32_t focus_direction(const Arg *a) { stub_focus_direction_calls++; stub_focus_direction_arg = a->i; return 0; }
int32_t move_resize(const Arg *a) { (void)a; stub_move_resize_calls++; return 0; }

int stub_error_calls = 0;
void acwm_error_impl(bool log, enum wlr_log_importance v, const char *f, int l, const char *fmt, ...) {
	(void)log; (void)v; (void)f; (void)l; (void)fmt; stub_error_calls++;
}
