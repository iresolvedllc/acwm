/* Test-only stubs for input/pointer_input.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/animation/client.h"
#include "acwm/bar/bar.h"
#include "acwm/ipc/ipc.h"
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/input/pointer.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"
#include <stddef.h>
#include <string.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_cursor.h>
#include <wlr/types/wlr_pointer.h>
#include <wlr/types/wlr_seat.h>
#include <wlr/util/edges.h>

Config config = {0};
struct AcwmServer server = {0};
struct LastCursor last_cursor;
bool pointer_locked_applied = false;

void wl_list_init(struct wl_list *l) { l->next = l; l->prev = l; }
void wl_list_insert(struct wl_list *l, struct wl_list *e) {
	e->next = e; e->prev = e;
	if (l) { e->next = l->next; e->prev = l; l->next->prev = e; l->next = e; }
}
void wl_list_remove(struct wl_list *e) {
	if (e->prev && e->next) { e->prev->next = e->next; e->next->prev = e->prev; }
	e->next = e; e->prev = e;
}
int stub_reinsert_prev = 0, stub_reinsert_next = 0;
void wl_list_safe_reinsert_prev(struct wl_list *a, struct wl_list *b) { (void)a; (void)b; stub_reinsert_prev++; }
void wl_list_safe_reinsert_next(struct wl_list *a, struct wl_list *b) { (void)a; (void)b; stub_reinsert_next++; }

double pointer_surface_scale(Client *c) { (void)c; return 1.0; }
struct wlr_box pointer_client_warp_box(Client *c) { return c->geom; }
bool pointer_locked_constraint_applies(Client *c, struct wlr_pointer_constraint_v1 *k) { (void)c; (void)k; return true; }
void pointer_follow_constraint_hint(struct wlr_pointer_constraint_v1 *k, Client *c) { (void)k; (void)c; }
Client *pointer_confine_rule_client(void) { return NULL; }
bool pointer_constraint_surface_visible(struct wlr_pointer_constraint_v1 *k) { (void)k; return false; }
Client *pointer_confine_client(struct wlr_pointer_constraint_v1 **out) { (void)out; return NULL; }
void pointer_constrain_cursor(struct wlr_pointer_constraint_v1 *k) { (void)k; }
void pointer_warp_to_constraint_hint(void) {}

int stub_is_unmanaged = 0, stub_wants_focus = 0;
int32_t client_is_unmanaged(Client *c) { (void)c; return stub_is_unmanaged; }
int32_t client_wants_focus(Client *c) { (void)c; return stub_wants_focus; }
struct wlr_surface stub_surface;
struct wlr_surface *client_surface(Client *c) { (void)c; return &stub_surface; }
int stub_focus_calls = 0;
void client_focus(Client *c, int32_t lift) { (void)c; (void)lift; stub_focus_calls++; }
int stub_set_floating_calls = 0;
void client_set_floating(Client *c, int32_t f) { (void)c; (void)f; stub_set_floating_calls++; }
int stub_set_monitor_calls = 0;
Client *stub_set_monitor_client = NULL;
Monitor *stub_set_monitor_arg = NULL;
void client_set_monitor(Client *c, Monitor *m, uint32_t tags, bool focus) { (void)tags; (void)focus; stub_set_monitor_calls++; stub_set_monitor_client = c; stub_set_monitor_arg = m; }
int stub_oldmon_calls = 0;
void client_update_oldmonname_record(Client *c, Monitor *m) { (void)c; (void)m; stub_oldmon_calls++; }
int stub_drop_area_calls = 0;
void client_set_drop_area(Client *c) { (void)c; stub_drop_area_calls++; }
Client *client_group_active(Client *c) { return c; }
int stub_group_leave_calls = 0, stub_group_join_calls = 0;
bool client_group_leave(Client *c) { (void)c; stub_group_leave_calls++; return true; }
void client_group_join(Client *c, Client *t) { (void)c; (void)t; stub_group_join_calls++; }
int stub_decorate_click_calls = 0;
void client_handle_decorate_click(AcwmBarDecoration *b) { (void)b; stub_decorate_click_calls++; }
int stub_exit_stack_calls = 0;
void exit_scroller_stack(Client *c) { (void)c; stub_exit_stack_calls++; }
int stub_size_per_calls = 0;
void set_size_per(Monitor *m, Client *c, bool s) { (void)m; (void)c; (void)s; stub_size_per_calls++; }
int stub_resize_calls = 0;
struct wlr_box stub_resize_geo;
ResizeOpts stub_resize_opts;
void resize(Client *c, struct wlr_box g, ResizeOpts o) { (void)c; stub_resize_calls++; stub_resize_geo = g; stub_resize_opts = o; }
int stub_resize_tile_calls = 0;
void resize_tile_client(Client *c, bool i, double x, double y, uint32_t t) { (void)c; (void)i; (void)x; (void)y; (void)t; stub_resize_tile_calls++; }
int stub_snap_calls = 0;
void apply_window_snap(Client *c) { (void)c; stub_snap_calls++; }
Monitor *stub_monitor_at = NULL;
Monitor *monitor_at_point(double x, double y) { (void)x; (void)y; return stub_monitor_at; }
int stub_selected_calls = 0;
Monitor *stub_selected_arg = NULL;
void set_selected_monitor(Monitor *m) { stub_selected_calls++; stub_selected_arg = m; if (m) server.selected_monitor = m; }
uint32_t drag_refresh_interval_ms(Monitor *m) { (void)m; return 0; }
bool stub_scroller_layout = false;
bool is_scroller_layout(Monitor *m) { (void)m; return stub_scroller_layout; }
uint32_t get_client_tag_idx(const Client *c) { (void)c; return 0; }
int stub_drop_tile_calls = 0;
void scroller_drop_tile(Client *c, Client *t, int32_t v) { (void)c; (void)t; (void)v; stub_drop_tile_calls++; }
int stub_dwindle_calls = 0;
void dwindle_insert(DwindleNode **root, Client *c, Client *t, float r, bool b, bool h, bool s) {
	(void)root; (void)c; (void)t; (void)r; (void)b; (void)h; (void)s; stub_dwindle_calls++;
}
int stub_arrange_calls = 0;
void arrange(Monitor *m, bool a, bool v) { (void)m; (void)a; (void)v; stub_arrange_calls++; }
int stub_layer_focus_calls = 0;
void layer_focus(LayerSurface *l) { (void)l; stub_layer_focus_calls++; }
int stub_kill_calls = 0;
void pending_kill_client(Client *c) { (void)c; stub_kill_calls++; }
Client *switcher_client_at(double x, double y) { (void)x; (void)y; return NULL; }
bool switcher_is_active(void) { return false; }
void switcher_close(void) {}
void switcher_commit_client(Client *c) { (void)c; }
bool bar_handle_button_press(double x, double y, uint32_t b) { (void)x; (void)y; (void)b; return false; }
bool acwm_bar_decoration_close_contains(AcwmBarDecoration *b, double x, double y) { (void)b; (void)x; (void)y; return false; }
void acwm_bar_decoration_set_close_hover(AcwmBarDecoration *b, bool h) { (void)b; (void)h; }
bool acwm_scene_node_get_ignore_hit(struct wlr_scene_node *n) { (void)n; return false; }
void acwm_scene_node_set_ignore_hit(struct wlr_scene_node *n, bool i) { (void)n; (void)i; }
int stub_node_at_calls = 0;
struct wlr_surface *stub_node_surface = NULL;
Client *stub_node_client = NULL;
AcwmBarDecoration *stub_node_bar = NULL;
double stub_node_x = 0, stub_node_y = 0;
void node_at_point(double x, double y, struct wlr_surface **ps, Client **pc, LayerSurface **pl, AcwmBarDecoration **bar, double *nx, double *ny) {
	(void)x; (void)y; (void)pl;
	stub_node_at_calls++;
	if (ps) *ps = stub_node_surface;
	if (pc) *pc = stub_node_client;
	if (bar) *bar = stub_node_bar;
	if (nx) *nx = stub_node_x;
	if (ny) *ny = stub_node_y;
}
int32_t stub_toplevel_result = -1;
Client *stub_toplevel_client = NULL;
int32_t toplevel_from_wlr_surface(struct wlr_surface *s, Client **pc, LayerSurface **pl) {
	(void)s;
	if (pc) *pc = stub_toplevel_client;
	if (pl) *pl = NULL;
	return stub_toplevel_result;
}
int stub_ipc_calls = 0;
void ipc_notify_device_event(struct wlr_input_device *d) { (void)d; stub_ipc_calls++; }
int stub_activity_calls = 0;
void acwm_notify_activity(struct wlr_seat *s) { (void)s; stub_activity_calls++; }
int stub_printstatus_calls = 0;
void printstatus(enum ipc_watch_type t) { (void)t; stub_printstatus_calls++; }
bool stub_trackpad_drag = false;
bool trackpad_gesture_drag_active(void) { return stub_trackpad_drag; }
bool stub_trackpad_disabled = false;
bool check_trackpad_disabled(struct wlr_pointer *p) { (void)p; return stub_trackpad_disabled; }
uint32_t stub_mods = 0;
uint32_t keyboard_hard_modifiers(void) { return stub_mods; }
int stub_cancel_release_calls = 0;
void keyboard_cancel_pending_release_bind(void) { stub_cancel_release_calls++; }
int stub_seat_device_calls = 0;
void seat_device_add(struct wlr_input_device *d) { (void)d; stub_seat_device_calls++; }
int stub_toggle_hotarea_calls = 0;
void toggle_hotarea(int32_t x, int32_t y) { (void)x; (void)y; stub_toggle_hotarea_calls++; }
int stub_attach_calls = 0;
void wlr_cursor_attach_input_device(struct wlr_cursor *c, struct wlr_input_device *d) { (void)c; (void)d; stub_attach_calls++; }
int stub_toggle_overview_calls = 0;
int32_t toggle_overview(const Arg *a) { (void)a; stub_toggle_overview_calls++; return 0; }

int stub_move_calls = 0;
double stub_move_x = 0, stub_move_y = 0;
void wlr_cursor_move(struct wlr_cursor *c, struct wlr_input_device *d, double dx, double dy) {
	(void)c; (void)d; stub_move_calls++; stub_move_x = dx; stub_move_y = dy;
}
int stub_warp_closest_calls = 0;
double stub_warp_closest_x = 0, stub_warp_closest_y = 0;
void wlr_cursor_warp_closest(struct wlr_cursor *c, struct wlr_input_device *d, double x, double y) {
	(void)c; (void)d; stub_warp_closest_calls++; stub_warp_closest_x = x; stub_warp_closest_y = y;
}
int stub_xcursor_calls = 0;
const char *stub_xcursor_name = NULL;
void wlr_cursor_set_xcursor(struct wlr_cursor *c, struct wlr_xcursor_manager *m, const char *n) {
	(void)c; (void)m; stub_xcursor_calls++; stub_xcursor_name = n;
}
int stub_set_surface_calls = 0;
void wlr_cursor_set_surface(struct wlr_cursor *c, struct wlr_surface *s, int32_t x, int32_t y) {
	(void)c; (void)s; (void)x; (void)y; stub_set_surface_calls++;
}
int stub_unset_image_calls = 0;
void wlr_cursor_unset_image(struct wlr_cursor *c) { (void)c; stub_unset_image_calls++; }
const char *wlr_cursor_shape_v1_name(enum wp_cursor_shape_device_v1_shape s) { (void)s; return "shape"; }
int stub_map_input_calls = 0;
void wlr_cursor_map_input_to_output(struct wlr_cursor *c, struct wlr_input_device *d, struct wlr_output *o) {
	(void)c; (void)d; (void)o; stub_map_input_calls++;
}
const char *stub_resize_name = "resize";
const char *wlr_xcursor_get_resize_name(enum wlr_edges e) { (void)e; return stub_resize_name; }
int stub_clear_focus_calls = 0, stub_notify_clear_calls = 0;
void wlr_seat_pointer_clear_focus(struct wlr_seat *s) { (void)s; stub_clear_focus_calls++; }
void wlr_seat_pointer_notify_clear_focus(struct wlr_seat *s) { (void)s; stub_notify_clear_calls++; }
int stub_enter_calls = 0;
void wlr_seat_pointer_notify_enter(struct wlr_seat *s, struct wlr_surface *surf, double x, double y) {
	(void)s; (void)surf; (void)x; (void)y; stub_enter_calls++;
}
int stub_motion_calls = 0;
void wlr_seat_pointer_notify_motion(struct wlr_seat *s, uint32_t t, double x, double y) {
	(void)s; (void)t; (void)x; (void)y; stub_motion_calls++;
}
bool stub_validate_serial = true;
bool wlr_seat_validate_pointer_grab_serial(struct wlr_seat *s, struct wlr_surface *o, uint32_t serial) {
	(void)s; (void)o; (void)serial; return stub_validate_serial;
}
int stub_start_drag_calls = 0;
void wlr_seat_start_pointer_drag(struct wlr_seat *s, struct wlr_drag *d, uint32_t serial) {
	(void)s; (void)d; (void)serial; stub_start_drag_calls++;
}
int stub_source_destroy_calls = 0;
void wlr_data_source_destroy(struct wlr_data_source *s) { (void)s; stub_source_destroy_calls++; }
struct wlr_scene_tree *wlr_scene_drag_icon_create(struct wlr_scene_tree *p, struct wlr_drag_icon *i) {
	(void)p; (void)i; return (struct wlr_scene_tree *)0x7000;
}
int stub_node_pos_calls = 0;
void wlr_scene_node_set_position(struct wlr_scene_node *n, int32_t x, int32_t y) {
	(void)n; (void)x; (void)y; stub_node_pos_calls++;
}
int stub_rel_motion_calls = 0;
void wlr_relative_pointer_manager_v1_send_relative_motion(struct wlr_relative_pointer_manager_v1 *m, struct wlr_seat *s, uint64_t t, double dx, double dy, double ux, double uy) {
	(void)m; (void)s; (void)t; (void)dx; (void)dy; (void)ux; (void)uy; stub_rel_motion_calls++;
}
bool stub_confine_result = false;
bool wlr_region_confine(pixman_region32_t *r, double x1, double y1, double x2, double y2, double *x, double *y) {
	(void)r; (void)x1; (void)y1; (void)x2; (void)y2; (void)x; (void)y; return stub_confine_result;
}
int stub_timer_calls = 0;
int32_t stub_timer_ms = 0;
int wl_event_source_timer_update(struct wl_event_source *s, int32_t ms) { (void)s; stub_timer_calls++; stub_timer_ms = ms; return 0; }
int clock_gettime(clockid_t id, struct timespec *tp) { (void)id; tp->tv_sec = 1; tp->tv_nsec = 500000000; return 0; }
void *ecalloc(size_t n, size_t s) { return calloc(n, s); }
int stub_mouse_func_calls = 0;
int32_t stub_mouse_func(const Arg *a) { (void)a; stub_mouse_func_calls++; return 0; }
int stub_handle_icon_destroy = 0;
void handle_drag_icon_destroy(struct wl_listener *l, void *d) { (void)l; (void)d; stub_handle_icon_destroy++; }
