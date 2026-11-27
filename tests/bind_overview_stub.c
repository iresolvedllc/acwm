/* Test-only stubs for bind_overview.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/dispatch/bind.h"
#include "acwm/input/device.h"
#include "acwm/input/keyboard.h"
#include "acwm/ipc/ipc.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_keyboard_group.h>

Config config = {0};
struct AcwmServer server = {0};
struct wlr_surface stub_surface = {0};
struct wlr_surface stub_unmapped_surface = {0};
Client *stub_unmapped_client = NULL;
KeyboardGroup stub_group;
struct wlr_keyboard_group stub_kbgroup;
struct wlr_keyboard stub_tkb;
struct wlr_input_device stub_dev_kb;
struct wlr_input_device stub_dev_ptr;
struct InputDevice stub_id_kb;
struct InputDevice stub_id_standalone;
struct InputDevice stub_id_ptr;

uint32_t stub_current_layout = 0;
uint32_t stub_num_layouts = 3;
int stub_error_calls = 0;
int stub_printstatus_calls = 0;
int stub_notify_mod_calls = 0;
uint32_t stub_notify_group = 99;
int stub_seat_set_calls = 0;
int stub_seat_mod_calls = 0;

int stub_switch_view_calls = 0;
uint32_t stub_switch_view_ui = 0;
bool stub_switch_view_anim = true;
int stub_focus_calls = 0;
Client *stub_focus_client = NULL;
int stub_unmanaged_calls = 0;
int stub_popup_calls = 0;
bool stub_is_unmanaged = false;
bool stub_is_popup = false;
int stub_backup_calls = 0;
Client *stub_backup_client = NULL;
int stub_restore_calls = 0;
Client *stub_restore_client = NULL;
int stub_refresh_calls = 0;
int stub_arrange_calls = 0;
int stub_begin_jump_calls = 0;
int stub_finish_jump_calls = 0;
int stub_pointer_clear_calls = 0;
int stub_cursor_activity_calls = 0;
int stub_set_xcursor_calls = 0;

uint32_t get_tags_first_tag(uint32_t tags) {
	return tags & (~tags + 1);
}
uint32_t get_tags_first_tag_num(uint32_t tags) {
	uint32_t n = 0;
	for (uint32_t i = 0; i < 32; i++)
		if (tags & (1u << i)) {
			n = i + 1;
			break;
		}
	return n;
}
void client_switch_view(const Arg *arg, bool animate) {
	stub_switch_view_calls++;
	stub_switch_view_ui = arg->ui;
	stub_switch_view_anim = animate;
}
void client_focus(Client *c, int32_t lift) {
	(void)lift;
	stub_focus_calls++;
	stub_focus_client = c;
}
int32_t client_is_unmanaged(Client *c) {
	(void)c;
	stub_unmanaged_calls++;
	return stub_is_unmanaged ? 1 : 0;
}
int32_t client_is_x11_popup(Client *c) {
	(void)c;
	stub_popup_calls++;
	return stub_is_popup ? 1 : 0;
}
struct wlr_surface *client_surface(Client *c) {
	if (c == stub_unmapped_client)
		return &stub_unmapped_surface;
	return &stub_surface;
}
void overview_backup(Client *c) {
	stub_backup_calls++;
	stub_backup_client = c;
}
void overview_restore(Client *c, const Arg *arg) {
	(void)arg;
	stub_restore_calls++;
	stub_restore_client = c;
}
void refresh_monitors_workspaces_status(Monitor *m) {
	(void)m;
	stub_refresh_calls++;
}
void arrange(Monitor *m, bool want_animation, bool from_view) {
	(void)m;
	(void)want_animation;
	(void)from_view;
	stub_arrange_calls++;
}
void begin_jump_mode(Monitor *m) {
	(void)m;
	stub_begin_jump_calls++;
}
void finish_jump_mode(Monitor *m) {
	(void)m;
	stub_finish_jump_calls++;
}
void printstatus(enum ipc_watch_type type) {
	(void)type;
	stub_printstatus_calls++;
}
void wlr_seat_pointer_clear_focus(struct wlr_seat *seat) {
	(void)seat;
	stub_pointer_clear_calls++;
}
void pointer_cursor_activity(void) {
	stub_cursor_activity_calls++;
}
void wlr_cursor_set_xcursor(struct wlr_cursor *cursor,
							struct wlr_xcursor_manager *manager,
							const char *name) {
	(void)cursor;
	(void)manager;
	(void)name;
	stub_set_xcursor_calls++;
}
xkb_layout_index_t xkb_state_serialize_layout(struct xkb_state *state,
											  enum xkb_state_component comp) {
	(void)state;
	(void)comp;
	return stub_current_layout;
}
xkb_layout_index_t xkb_keymap_num_layouts(struct xkb_keymap *keymap) {
	(void)keymap;
	return stub_num_layouts;
}
void wlr_keyboard_notify_modifiers(struct wlr_keyboard *keyboard,
								   uint32_t depressed, uint32_t latched,
								   uint32_t locked,
								   xkb_layout_index_t group) {
	(void)keyboard;
	(void)depressed;
	(void)latched;
	(void)locked;
	stub_notify_mod_calls++;
	stub_notify_group = group;
}
void wlr_seat_set_keyboard(struct wlr_seat *seat, struct wlr_keyboard *keyboard) {
	(void)seat;
	(void)keyboard;
	stub_seat_set_calls++;
}
void wlr_seat_keyboard_notify_modifiers(
	struct wlr_seat *seat, struct wlr_keyboard_modifiers *modifiers) {
	(void)seat;
	(void)modifiers;
	stub_seat_mod_calls++;
}
void acwm_error_impl(bool log, unsigned verbosity, const char *file, int line,
					 const char *fmt, ...) {
	(void)log;
	(void)verbosity;
	(void)file;
	(void)line;
	(void)fmt;
	stub_error_calls++;
}
