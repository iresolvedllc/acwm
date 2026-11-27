/* Test-only stubs for input/device.zig (device.c + switch.c). */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/input/device.h"
#include "acwm/input/switch.h"
#include <stddef.h>
#include <string.h>
#include <wlr/backend/libinput.h>
#include <wlr/types/wlr_input_device.h>
#include <wlr/types/wlr_keyboard.h>
#include <wlr/types/wlr_pointer.h>
#include <wlr/types/wlr_switch.h>
#include <wlr/types/wlr_tablet_pad.h>
#include <wlr/types/wlr_tablet_tool.h>
#include <wlr/types/wlr_touch.h>

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

struct wlr_keyboard stub_keyboard;
struct wlr_pointer stub_pointer;
struct wlr_touch stub_touch;
struct wlr_switch stub_switch;
struct wlr_keyboard *wlr_keyboard_from_input_device(struct wlr_input_device *d) {
	(void)d;
	return &stub_keyboard;
}
struct wlr_pointer *wlr_pointer_from_input_device(struct wlr_input_device *d) {
	(void)d;
	return &stub_pointer;
}
struct wlr_touch *wlr_touch_from_input_device(struct wlr_input_device *d) {
	(void)d;
	return &stub_touch;
}
struct wlr_switch *wlr_switch_from_input_device(struct wlr_input_device *d) {
	(void)d;
	return &stub_switch;
}

int stub_keyboard_create_calls = 0;
int stub_pointer_create_calls = 0;
int stub_touch_create_calls = 0;
int stub_tablet_create_calls = 0;
int stub_tablet_pad_create_calls = 0;
void keyboard_create(struct wlr_keyboard *k) { (void)k; stub_keyboard_create_calls++; }
void pointer_create(struct wlr_pointer *p) { (void)p; stub_pointer_create_calls++; }
void touch_create(struct wlr_touch *t) { (void)t; stub_touch_create_calls++; }
void tablet_create(struct wlr_input_device *d) { (void)d; stub_tablet_create_calls++; }
void tablet_pad_create(struct wlr_input_device *d) { (void)d; stub_tablet_pad_create_calls++; }

int stub_ipc_device_calls = 0;
void ipc_notify_device_event(struct wlr_input_device *d) {
	(void)d;
	stub_ipc_device_calls++;
}

int stub_seat_caps_calls = 0;
uint32_t stub_seat_caps = 0;
void wlr_seat_set_capabilities(struct wlr_seat *s, uint32_t caps) {
	(void)s;
	stub_seat_caps_calls++;
	stub_seat_caps = caps;
}

int stub_switch_func_calls = 0;
uint32_t stub_switch_func_ui = 0;
int32_t stub_switch_binding_func(const Arg *arg) {
	stub_switch_func_calls++;
	if (arg)
		stub_switch_func_ui = arg->ui;
	return 0;
}
