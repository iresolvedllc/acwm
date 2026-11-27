/* Test-only stubs for src/ext-protocol/xdg_output.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/ext-protocol/xdg-output.h"
#include "acwm/manage/monitor.h"
#include <stddef.h>
#include <string.h>
#include <wlr/types/wlr_output.h>
#include <wlr/types/wlr_output_layout.h>
#include <xdg-output-unstable-v1-protocol.h>

Config config = {0};
struct AcwmServer server = {0};

void wl_list_init(struct wl_list *l) { l->next = l; l->prev = l; }
void wl_list_insert(struct wl_list *l, struct wl_list *e) {
	e->next = e; e->prev = e;
	if (l) { e->next = l->next; e->prev = l; l->next->prev = e; l->next = e; }
}
void wl_list_remove(struct wl_list *e) {
	if (e->prev && e->next) { e->prev->next = e->next; e->next->prev = e->prev; }
	e->next = e; e->prev = e;
}

void *stub_user_data = NULL;
int stub_set_user_data_calls = 0;
void *wl_resource_get_user_data(struct wl_resource *r) { (void)r; return stub_user_data; }
void wl_resource_set_user_data(struct wl_resource *r, void *d) { (void)r; stub_user_data = d; stub_set_user_data_calls++; }
uint32_t stub_version = 3;
int wl_resource_get_version(const struct wl_resource *r) { (void)r; return (int)stub_version; }
int stub_impl_calls = 0;
void wl_resource_set_implementation(struct wl_resource *r, const void *impl, void *data, void (*destroy)(struct wl_resource *)) {
	(void)r; (void)impl; (void)destroy; stub_impl_calls++; stub_user_data = data;
}
struct wl_resource stub_resource;
struct wl_resource stub_resource2;
struct wl_resource *wl_resource_create(struct wl_client *c, const struct wl_interface *i, int v, uint32_t id) {
	(void)c; (void)i; (void)v; (void)id; return &stub_resource;
}
int stub_resource_destroy_calls = 0;
void wl_resource_destroy(struct wl_resource *r) { (void)r; stub_resource_destroy_calls++; }
int stub_no_memory_calls = 0;
void wl_client_post_no_memory(struct wl_client *c) { (void)c; stub_no_memory_calls++; }
struct wl_global *wl_global_create(struct wl_display *d, const struct wl_interface *i, int v, void *data, void (*bind)(struct wl_client *, void *, uint32_t, uint32_t)) {
	(void)d; (void)i; (void)v; (void)data; (void)bind; return (struct wl_global *)0x7000;
}
struct wl_resource *stub_wl_output_resource = NULL;
struct wlr_output *stub_wlr_output = NULL;
struct wlr_output *wlr_output_from_resource(struct wl_resource *r) { (void)r; return stub_wlr_output; }
int stub_transformed_w = 1920, stub_transformed_h = 1080;
void wlr_output_transformed_resolution(struct wlr_output *o, int32_t *w, int32_t *h) {
	(void)o; *w = stub_transformed_w; *h = stub_transformed_h;
}
int stub_schedule_done_calls = 0;
void wlr_output_schedule_done(struct wlr_output *o) { (void)o; stub_schedule_done_calls++; }
struct wlr_output_layout_output *stub_layout_output = NULL;
struct wlr_output_layout_output *wlr_output_layout_get(struct wlr_output_layout *l, struct wlr_output *o) {
	(void)l; (void)o; return stub_layout_output;
}
int32_t stub_ox = 0, stub_oy = 0;
void xwayland_screen_origin(int32_t *x, int32_t *y) { *x = stub_ox; *y = stub_oy; }

int stub_pos_calls = 0, stub_size_calls = 0, stub_done_calls = 0;
int32_t stub_lx = 0, stub_ly = 0, stub_lw = 0, stub_lh = 0;
int stub_name_calls = 0, stub_desc_calls = 0;
int stub_output_done_calls = 0;
#include <stdarg.h>
void wl_resource_post_event(struct wl_resource *r, uint32_t opcode, ...) {
	(void)r;
	va_list ap;
	va_start(ap, opcode);
	if (r == stub_wl_output_resource) { stub_output_done_calls++; va_end(ap); return; }
	if (opcode == ZXDG_OUTPUT_V1_LOGICAL_POSITION) {
		stub_pos_calls++; stub_lx = va_arg(ap, int32_t); stub_ly = va_arg(ap, int32_t);
	} else if (opcode == ZXDG_OUTPUT_V1_LOGICAL_SIZE) {
		stub_size_calls++; stub_lw = va_arg(ap, int32_t); stub_lh = va_arg(ap, int32_t);
	} else if (opcode == ZXDG_OUTPUT_V1_DONE) {
		stub_done_calls++;
	} else if (opcode == ZXDG_OUTPUT_V1_NAME) {
		stub_name_calls++;
	} else if (opcode == ZXDG_OUTPUT_V1_DESCRIPTION) {
		stub_desc_calls++;
	} else if (opcode == WL_OUTPUT_DONE) {
		stub_output_done_calls++;
	}
	va_end(ap);
}
int stub_error_calls = 0;
void acwm_error_impl(bool log, enum wlr_log_importance v, const char *f, int l, const char *fmt, ...) {
	(void)log; (void)v; (void)f; (void)l; (void)fmt; stub_error_calls++;
}
const struct wl_interface zxdg_output_v1_interface = {0};
const struct wl_interface zxdg_output_manager_v1_interface = {0};
