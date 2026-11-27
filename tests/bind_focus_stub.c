/* Test-only stubs for bind_focus.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/dispatch/bind.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"
#include <wlr/types/wlr_compositor.h>

Config config = {0};
struct AcwmServer server = {0};
struct wlr_surface stub_surface = {0};
bool stub_surface_null = false;

Client *stub_direction_client = NULL;
Client *stub_stack_client = NULL;
Client *stub_next_client = NULL;
Client *stub_focus_top_client = NULL;
bool stub_group_member = false;
Client *stub_nonmember_client = NULL;
bool stub_special_active = false;
bool stub_have_client_result = false;
bool stub_view_shift_result = false;
Client *stub_cycle_monitor_client_unused = NULL;
Monitor *stub_cycle_monitor = NULL;
Monitor *stub_direction_monitor = NULL;

int stub_focus_calls = 0;
Client *stub_focus_client = NULL;
int stub_warp_client_calls = 0;
int stub_warp_monitor_calls = 0;
int stub_have_calls = 0;
int stub_shift_calls = 0;
int32_t stub_shift_dir = 0;
int stub_selected_calls = 0;
int stub_switch_view_calls = 0;
uint32_t stub_switch_view_ui = 0;
int stub_arrange_calls = 0;
int stub_focus_group_calls = 0;
Client *stub_focus_group_client = NULL;
int stub_sync_hint_calls = 0;
int stub_detach_calls = 0;
int stub_unpark_calls = 0;
int stub_update_vis_calls = 0;
int stub_active_calls = 0;
int stub_clear_pointer_calls = 0;
int stub_clear_keyboard_calls = 0;
int stub_overview_calls = 0;
int32_t stub_overview_i = 0;

Client *direction_select(const Arg *arg) {
	(void)arg;
	return stub_direction_client;
}
Client *get_focused_stack_client(Client *sc, Client *custom) {
	(void)custom;
	return stub_stack_client ? stub_stack_client : sc;
}
Client *get_next_stack_client(Client *c, bool reverse) {
	(void)c;
	(void)reverse;
	return stub_next_client;
}
void client_focus(Client *c, int32_t lift) {
	(void)lift;
	stub_focus_calls++;
	stub_focus_client = c;
}
Client *client_focus_top(Monitor *m) {
	(void)m;
	return stub_focus_top_client;
}
void client_active(Client *c) {
	(void)c;
	stub_active_calls++;
}
void pointer_warp_to_client(Client *c) {
	(void)c;
	stub_warp_client_calls++;
}
void pointer_warp_to_monitor(Monitor *m) {
	(void)m;
	stub_warp_monitor_calls++;
}
bool is_special_active(const Monitor *m) {
	(void)m;
	return stub_special_active;
}
bool view_shift_tag(const Arg *arg, int32_t dir) {
	(void)arg;
	stub_shift_calls++;
	stub_shift_dir = dir;
	return stub_view_shift_result;
}
bool view_shift_tag_have_client(const Arg *arg, int32_t dir) {
	(void)arg;
	stub_have_calls++;
	stub_shift_dir = dir;
	return stub_have_client_result;
}
void set_selected_monitor(Monitor *m) {
	stub_selected_calls++;
	server.selected_monitor = m;
}
Monitor *monitor_from_cycle(int32_t dir) {
	(void)dir;
	return stub_cycle_monitor;
}
Monitor *monitor_from_direction(enum wlr_direction dir) {
	(void)dir;
	return stub_direction_monitor;
}
bool match_monitor_spec(char *spec, Monitor *m) {
	(void)spec;
	(void)m;
	return true;
}
uint32_t get_tags_first_tag(uint32_t tags) {
	return tags & (~tags + 1);
}
void client_switch_view(const Arg *arg, bool animate) {
	(void)animate;
	stub_switch_view_calls++;
	stub_switch_view_ui = arg->ui;
}
void arrange(Monitor *m, bool want_animation, bool from_view) {
	(void)m;
	(void)want_animation;
	(void)from_view;
	stub_arrange_calls++;
}
bool client_is_group_member(const Client *c) {
	if (c == stub_nonmember_client)
		return false;
	return stub_group_member;
}
void client_focus_group_member(Client *c) {
	stub_focus_group_calls++;
	stub_focus_group_client = c;
}
void client_sync_tiled_hint(Client *c) {
	(void)c;
	stub_sync_hint_calls++;
}
void client_group_detach(Client *c) {
	(void)c;
	stub_detach_calls++;
}
void client_unpark(Client *c, Client *anchor) {
	(void)c;
	(void)anchor;
	stub_unpark_calls++;
}
void client_update_visibility(Client *c) {
	(void)c;
	stub_update_vis_calls++;
}
struct wlr_surface *client_surface(Client *c) {
	(void)c;
	if (stub_surface_null)
		return NULL;
	return &stub_surface;
}
int32_t client_is_unmanaged(Client *c) {
	(void)c;
	return 0;
}
int32_t client_is_x11_popup(Client *c) {
	(void)c;
	return 0;
}
void wlr_seat_pointer_notify_clear_focus(struct wlr_seat *seat) {
	(void)seat;
	stub_clear_pointer_calls++;
}
void wlr_seat_keyboard_notify_clear_focus(struct wlr_seat *seat) {
	(void)seat;
	stub_clear_keyboard_calls++;
}
int32_t toggle_overview(const Arg *arg) {
	stub_overview_calls++;
	stub_overview_i = arg->i;
	return 0;
}
uint32_t get_mon_curtag(const Monitor *m) {
	(void)m;
	return 0;
}
