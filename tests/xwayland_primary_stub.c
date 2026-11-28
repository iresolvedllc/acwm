/* Test-only stubs for src/manage/xwayland_primary.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/manage/monitor.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <xcb/xcb.h>
#include <xcb/randr.h>
#include <wayland-server-core.h>

Config config = {0};
struct AcwmServer server = {0};

void *stub_conn = NULL;
int stub_connect_calls = 0, stub_disconnect_calls = 0;
const struct xcb_setup_t *stub_setup = NULL;
xcb_screen_t *stub_screen = NULL;
xcb_connection_t *xcb_connect(const char *name, int *screen) {
    (void)name;
    if (screen) *screen = 0;
    stub_connect_calls++;
    return (xcb_connection_t *)stub_conn;
}
void xcb_disconnect(xcb_connection_t *c) { (void)c; stub_disconnect_calls++; }
int xcb_connection_has_error(xcb_connection_t *c) { (void)c; return 0; }
const struct xcb_setup_t *xcb_get_setup(xcb_connection_t *c) { (void)c; return stub_setup; }
xcb_screen_iterator_t xcb_setup_roots_iterator(const struct xcb_setup_t *setup) {
    (void)setup;
    xcb_screen_iterator_t it;
    memset(&it, 0, sizeof(it));
    it.data = stub_screen;
    it.rem = stub_screen != NULL ? 1 : 0;
    return it;
}
void xcb_screen_next(xcb_screen_iterator_t *it) { (void)it; }
int xcb_get_file_descriptor(xcb_connection_t *c) { (void)c; return 7; }
int stub_flush_calls = 0;
int xcb_flush(xcb_connection_t *c) { (void)c; stub_flush_calls++; return 1; }
xcb_generic_event_t *xcb_poll_for_event(xcb_connection_t *c) { (void)c; return NULL; }

int stub_get_resources_calls = 0;
xcb_randr_get_screen_resources_cookie_t xcb_randr_get_screen_resources(xcb_connection_t *c, xcb_window_t root) {
    (void)c; (void)root;
    xcb_randr_get_screen_resources_cookie_t ck;
    memset(&ck, 0, sizeof(ck));
    stub_get_resources_calls++;
    return ck;
}
xcb_randr_get_screen_resources_reply_t *xcb_randr_get_screen_resources_reply(
    xcb_connection_t *c, xcb_randr_get_screen_resources_cookie_t ck, xcb_generic_error_t **err) {
    (void)c; (void)ck; if (err) *err = NULL;
    return NULL;
}
int xcb_randr_get_screen_resources_outputs_length(const xcb_randr_get_screen_resources_reply_t *r) { (void)r; return 0; }
xcb_randr_output_t *xcb_randr_get_screen_resources_outputs(const xcb_randr_get_screen_resources_reply_t *r) {
    (void)r; return NULL;
}
xcb_randr_get_output_info_cookie_t xcb_randr_get_output_info(xcb_connection_t *c, xcb_randr_output_t o, xcb_timestamp_t t) {
    (void)c; (void)o; (void)t;
    xcb_randr_get_output_info_cookie_t ck;
    memset(&ck, 0, sizeof(ck));
    return ck;
}
xcb_randr_get_output_info_reply_t *xcb_randr_get_output_info_reply(
    xcb_connection_t *c, xcb_randr_get_output_info_cookie_t ck, xcb_generic_error_t **err) {
    (void)c; (void)ck; if (err) *err = NULL;
    return NULL;
}
int xcb_randr_get_output_info_name_length(const xcb_randr_get_output_info_reply_t *r) { (void)r; return 0; }
uint8_t *xcb_randr_get_output_info_name(const xcb_randr_get_output_info_reply_t *r) { (void)r; return NULL; }

int stub_set_primary_calls = 0;
xcb_randr_output_t stub_set_primary_arg = 0;
xcb_void_cookie_t xcb_randr_set_output_primary(xcb_connection_t *c, xcb_window_t root, xcb_randr_output_t output) {
    (void)c; (void)root;
    stub_set_primary_calls++;
    stub_set_primary_arg = output;
    xcb_void_cookie_t ck;
    memset(&ck, 0, sizeof(ck));
    return ck;
}
xcb_randr_get_output_primary_cookie_t xcb_randr_get_output_primary(xcb_connection_t *c, xcb_window_t root) {
    (void)c; (void)root;
    xcb_randr_get_output_primary_cookie_t ck;
    memset(&ck, 0, sizeof(ck));
    return ck;
}
xcb_randr_get_output_primary_reply_t *xcb_randr_get_output_primary_reply(
    xcb_connection_t *c, xcb_randr_get_output_primary_cookie_t ck, xcb_generic_error_t **err) {
    (void)c; (void)ck; if (err) *err = NULL;
    return (xcb_randr_get_output_primary_reply_t *)malloc(sizeof(xcb_randr_get_output_primary_reply_t));
}

int stub_watch_calls = 0, stub_unwatch_calls = 0;
struct wl_event_source *stub_source = (struct wl_event_source *)0x2000;
struct wl_event_source *wl_event_loop_add_fd(struct wl_event_loop *loop, int fd, uint32_t mask,
                                             int (*func)(int, uint32_t, void *), void *data) {
    (void)loop; (void)fd; (void)mask; (void)func; (void)data;
    stub_watch_calls++;
    return stub_source;
}
int wl_event_source_remove(struct wl_event_source *source) { (void)source; stub_unwatch_calls++; return 0; }
struct wl_event_loop *wl_display_get_event_loop(struct wl_display *display) {
    (void)display;
    return (struct wl_event_loop *)0x3000;
}

Monitor *stub_rule_m1 = NULL;
int stub_m1_rule = -1;
Monitor *stub_rule_m2 = NULL;
int stub_m2_rule = -1;
bool monitor_matches_rule(Monitor *m, const ConfigMonitorRule *rule) {
    int idx = -1;
    if (m == stub_rule_m1) idx = stub_m1_rule;
    else if (m == stub_rule_m2) idx = stub_m2_rule;
    return idx >= 0 && rule == &config.monitor_rules[idx];
}
