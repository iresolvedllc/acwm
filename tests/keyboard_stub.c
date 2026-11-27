/* Test-only stubs for input/keyboard.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/log.h"
#include "acwm/common/server.h"
#include "acwm/common/util.h"
#include "acwm/config/parse.h"
#include "acwm/config/preset.h"
#include "acwm/ipc/ipc.h"
#include "acwm/ext-protocol/text-input.h"
#include "acwm/input/keyboard.h"
#include "acwm/manage/client.h"
#include "acwm/manage/misc.h"
#include "acwm/switcher/switcher.h"
#include <stdarg.h>
#include <stddef.h>
#include <string.h>
#include <wlr/types/wlr_keyboard.h>
#include <wlr/types/wlr_keyboard_group.h>
#include <wlr/types/wlr_keyboard_shortcuts_inhibit_v1.h>
#include <wlr/types/wlr_seat.h>
#include <wlr/types/wlr_virtual_keyboard_v1.h>
#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/xwayland.h>

void *ecalloc(size_t n, size_t s) { return calloc(n, s); }
void ipc_notify_device_event(struct wlr_input_device *d) { (void)d; }
const struct xkb_rule_names xkb_fallback_rules = {0};

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
struct libinput_device *stub_libinput_device = (struct libinput_device *)0x5000;
int stub_vendor = 0x1234, stub_product = 0x5678;
int stub_tap_fingers = 0;
bool wlr_input_device_is_libinput(struct wlr_input_device *d) { (void)d; return stub_is_libinput; }
struct libinput_device *wlr_libinput_get_device_handle(struct wlr_input_device *d) { (void)d; return stub_libinput_device; }
int libinput_device_get_id_vendor(struct libinput_device *d) { (void)d; return stub_vendor; }
int libinput_device_get_id_product(struct libinput_device *d) { (void)d; return stub_product; }
int libinput_device_config_tap_get_finger_count(struct libinput_device *d) { (void)d; return stub_tap_fingers; }

int stub_seat_device_add_calls = 0;
void seat_device_add(struct wlr_input_device *d) { (void)d; stub_seat_device_add_calls++; }
int stub_input_destroy_calls = 0;
void handle_input_device_destroy(struct wl_listener *l, void *d) { (void)l; (void)d; stub_input_destroy_calls++; }

int stub_set_keymap_calls = 0;
struct xkb_keymap *stub_set_keymap_arg = NULL;
bool wlr_keyboard_set_keymap(struct wlr_keyboard *kb, struct xkb_keymap *km) {
	(void)kb; stub_set_keymap_calls++; stub_set_keymap_arg = km;
	kb->keymap = km;
	return true;
}
int stub_notify_mods_calls = 0;
uint32_t stub_notify_mods_locked = 0;
void wlr_keyboard_notify_modifiers(struct wlr_keyboard *kb, uint32_t dep, uint32_t lat, uint32_t lock, uint32_t grp) {
	(void)kb; (void)dep; (void)lat; (void)grp;
	stub_notify_mods_calls++; stub_notify_mods_locked = lock;
}
int stub_repeat_info_calls = 0;
int stub_repeat_rate = 0, stub_repeat_delay = 0;
void wlr_keyboard_set_repeat_info(struct wlr_keyboard *kb, int32_t rate, int32_t delay) {
	(void)kb; stub_repeat_info_calls++; stub_repeat_rate = rate; stub_repeat_delay = delay;
}
struct wlr_keyboard *stub_group_keyboard = NULL;
struct wlr_keyboard *stub_standalone_keyboard = NULL;
uint32_t stub_group_mods = 0, stub_standalone_mods = 0;
uint32_t wlr_keyboard_get_modifiers(struct wlr_keyboard *kb) {
	if (kb == stub_group_keyboard) return stub_group_mods;
	if (kb == stub_standalone_keyboard) return stub_standalone_mods;
	return 0;
}
struct wlr_keyboard_group stub_wlr_group;
struct wlr_keyboard_group *wlr_keyboard_group_create(void) {
	memset(&stub_wlr_group, 0, sizeof(stub_wlr_group));
	return &stub_wlr_group;
}
int stub_group_add_calls = 0;
bool wlr_keyboard_group_add_keyboard(struct wlr_keyboard_group *g, struct wlr_keyboard *kb) {
	(void)g; (void)kb; stub_group_add_calls++; return true;
}
int stub_group_destroy_calls = 0;
void wlr_keyboard_group_destroy(struct wlr_keyboard_group *g) { (void)g; stub_group_destroy_calls++; }
struct wlr_keyboard *stub_seat_keyboard = NULL;
struct wlr_keyboard *wlr_seat_get_keyboard(struct wlr_seat *s) { (void)s; return stub_seat_keyboard; }
int stub_set_seat_keyboard_calls = 0;
struct wlr_keyboard *stub_set_seat_keyboard_arg = NULL;
void wlr_seat_set_keyboard(struct wlr_seat *s, struct wlr_keyboard *kb) {
	(void)s; stub_set_seat_keyboard_calls++; stub_set_seat_keyboard_arg = kb; stub_seat_keyboard = kb;
}
int stub_keyboard_enter_calls = 0;
struct wlr_surface *stub_keyboard_enter_surface = NULL;
void wlr_seat_keyboard_enter(struct wlr_seat *s, struct wlr_surface *surf, const uint32_t keys[], size_t n, const struct wlr_keyboard_modifiers *m) {
	(void)s; (void)keys; (void)n; (void)m;
	stub_keyboard_enter_calls++; stub_keyboard_enter_surface = surf;
}
int stub_send_key_calls = 0;
void wlr_seat_keyboard_send_key(struct wlr_seat *s, uint32_t t, uint32_t k, uint32_t st) {
	(void)s; (void)t; (void)k; (void)st; stub_send_key_calls++;
}
int stub_notify_key_calls = 0;
uint32_t stub_notify_key_code = 0, stub_notify_key_state = 0;
void wlr_seat_keyboard_notify_key(struct wlr_seat *s, uint32_t t, uint32_t k, uint32_t st) {
	(void)s; (void)t; stub_notify_key_calls++; stub_notify_key_code = k; stub_notify_key_state = st;
}
int stub_seat_notify_mods_calls = 0;
void wlr_seat_keyboard_notify_modifiers(struct wlr_seat *s, const struct wlr_keyboard_modifiers *m) {
	(void)s; (void)m; stub_seat_notify_mods_calls++;
}
struct wlr_xdg_surface *stub_xdg_surface = NULL;
struct wlr_xdg_surface *wlr_xdg_surface_try_from_wlr_surface(struct wlr_surface *s) { (void)s; return stub_xdg_surface; }
struct wlr_xwayland_surface *stub_xwayland_surface = NULL;
struct wlr_xwayland_surface *wlr_xwayland_surface_try_from_wlr_surface(struct wlr_surface *s) { (void)s; return stub_xwayland_surface; }
int stub_inhibitor_activate_calls = 0;
void wlr_keyboard_shortcuts_inhibitor_v1_activate(struct wlr_keyboard_shortcuts_inhibitor_v1 *i) { (void)i; stub_inhibitor_activate_calls++; }

int stub_timer_update_calls = 0;
int32_t stub_timer_ms = 0;
int wl_event_source_timer_update(struct wl_event_source *s, int32_t ms) {
	(void)s; stub_timer_update_calls++; stub_timer_ms = ms; return 0;
}
int stub_timer_remove_calls = 0;
int wl_event_source_remove(struct wl_event_source *s) { (void)s; stub_timer_remove_calls++; return 0; }
struct wl_event_source *wl_event_loop_add_timer(struct wl_event_loop *l, wl_event_loop_timer_func_t func, void *data) {
	(void)l; (void)func; (void)data; return (struct wl_event_source *)0x9999;
}

Client *stub_focus_top_client = NULL;
Client *client_focus_top(Monitor *m) { (void)m; return stub_focus_top_client; }
const char *stub_appid = "app", *stub_title = "title";
const char *client_get_appid(Client *c) { (void)c; return stub_appid; }
const char *client_get_title(Client *c) { (void)c; return stub_title; }
struct wlr_surface *stub_client_surface = (struct wlr_surface *)0x6000;
struct wlr_surface *client_surface(Client *c) { (void)c; return stub_client_surface; }
int stub_focus_calls = 0;
void client_focus(Client *c, int32_t lift) { (void)c; (void)lift; stub_focus_calls++; }
bool stub_regex_match = false;
int32_t regex_match(const char *p, const char *s) { (void)p; (void)s; return stub_regex_match; }
int32_t stub_toplevel_result = -1;
Client *stub_toplevel_client = NULL;
int32_t toplevel_from_wlr_surface(struct wlr_surface *s, Client **pc, LayerSurface **pl) {
	(void)s;
	if (pc) *pc = stub_toplevel_client;
	if (pl) *pl = NULL;
	return stub_toplevel_result;
}
int stub_activity_calls = 0;
void acwm_notify_activity(struct wlr_seat *s) { (void)s; stub_activity_calls++; }
int stub_hide_cursor_calls = 0;
int32_t pointer_hide_cursor(void *d) { (void)d; stub_hide_cursor_calls++; return 0; }
bool stub_session_missing = false;
int stub_session_restore_calls = 0;
bool session_lock_focus_missing(void) { return stub_session_missing; }
void session_lock_focus_restore(void) { stub_session_restore_calls++; }
bool stub_switcher_active = false;
int stub_switcher_close_calls = 0, stub_switcher_commit_calls = 0;
bool switcher_is_active(void) { return stub_switcher_active; }
void switcher_close(void) { stub_switcher_close_calls++; }
void switcher_commit(void) { stub_switcher_commit_calls++; }
int stub_toggle_overview_calls = 0, stub_toggle_jump_calls = 0;
Arg stub_overview_arg;
int32_t toggle_overview(const Arg *a) { stub_toggle_overview_calls++; if (a) stub_overview_arg = *a; return 0; }
int32_t toggle_jump(const Arg *a) { (void)a; stub_toggle_jump_calls++; return 0; }
int stub_printstatus_calls = 0;
void printstatus(enum ipc_watch_type t) { (void)t; stub_printstatus_calls++; }
bool stub_forward_key = false, stub_forward_mods = false;
bool acwm_im_keyboard_grab_forward_key(KeyboardGroup *g, struct wlr_keyboard_key_event *e) {
	(void)g; (void)e; return stub_forward_key;
}
bool acwm_im_keyboard_grab_forward_modifiers(KeyboardGroup *g) { (void)g; return stub_forward_mods; }

int stub_error_calls = 0;
void acwm_error_impl(bool log, enum wlr_log_importance v, const char *f, int l, const char *fmt, ...) {
	(void)log; (void)v; (void)f; (void)l; (void)fmt; stub_error_calls++;
}
int stub_die_calls = 0;
void die(const char *fmt, ...) { (void)fmt; stub_die_calls++; }

int stub_keybinding_calls = 0;
int32_t stub_keybinding_result = 0;
int32_t stub_keybinding_func(const Arg *a) { (void)a; stub_keybinding_calls++; return stub_keybinding_result; }
