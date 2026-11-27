/* Test-only stubs for src/bar/tray.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/bar/bar.h"
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/manage/monitor.h"
#include <cairo/cairo.h>
#include <drm_fourcc.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <systemd/sd-bus.h>
#include <wlr/types/wlr_buffer.h>
#include <wlr/types/wlr_scene.h>

Config config = {0};
struct AcwmServer server = {0};

void wl_list_init(struct wl_list *l) { l->next = l; l->prev = l; }
void wl_list_append(struct wl_list *l, struct wl_list *e) { e->prev = l->prev; e->next = l; l->prev->next = e; l->prev = e; }
void wl_list_remove(struct wl_list *e) { if (e->prev && e->next) { e->prev->next = e->next; e->next->prev = e->prev; } e->next = e; e->prev = e; }

sd_bus *stub_bus = (sd_bus *)0x8000;
int stub_default_user_calls = 0, stub_default_system_calls = 0;
int sd_bus_default_user(sd_bus **b) { stub_default_user_calls++; *b = stub_bus; return 0; }
int sd_bus_default_system(sd_bus **b) { stub_default_system_calls++; *b = stub_bus; return 0; }
int stub_vtable_calls = 0, stub_name_calls = 0, stub_match_calls = 0, stub_call_async_calls = 0;
int sd_bus_add_object_vtable(sd_bus *b, sd_bus_slot **s, const char *p, const char *i, const sd_bus_vtable *v, void *u) { (void)b; (void)s; (void)p; (void)i; (void)v; (void)u; stub_vtable_calls++; return 0; }
int sd_bus_request_name(sd_bus *b, const char *n, uint64_t f) { (void)b; (void)n; (void)f; stub_name_calls++; return 0; }
int sd_bus_match_signal(sd_bus *b, sd_bus_slot **s, const char *se, const char *p, const char *i, const char *m, sd_bus_message_handler_t cb, void *u) {
	(void)b; (void)s; (void)se; (void)p; (void)i; (void)m; (void)cb; (void)u; stub_match_calls++; return 0;
}
int sd_bus_call_method_async(sd_bus *b, sd_bus_slot **s, const char *d, const char *p, const char *i, const char *m, sd_bus_message_handler_t cb, void *u, const char *sig, ...) {
	(void)b; (void)s; (void)d; (void)p; (void)i; (void)m; (void)cb; (void)u; (void)sig; stub_call_async_calls++; return 0;
}
int sd_bus_process(sd_bus *b, sd_bus_message **m) { (void)b; if (m) *m = NULL; return 0; }
int sd_bus_flush(sd_bus *b) { (void)b; return 0; }
int sd_bus_get_fd(sd_bus *b) { (void)b; return 42; }
sd_bus *sd_bus_flush_close_unref(sd_bus *b) { (void)b; return NULL; }
sd_bus_slot *sd_bus_slot_unref(sd_bus_slot *s) { (void)s; return NULL; }
int stub_method_error = 0;
const sd_bus_error *stub_error = NULL;
int sd_bus_message_is_method_error(sd_bus_message *m, const char *n) { (void)m; (void)n; return stub_method_error; }
const sd_bus_error *sd_bus_message_get_error(sd_bus_message *m) { (void)m; return stub_error; }
const char *stub_sender = ":1.42";
const char *sd_bus_message_get_sender(sd_bus_message *m) { (void)m; return stub_sender; }
int sd_bus_message_enter_container(sd_bus_message *m, char t, const char *c) { (void)m; (void)t; (void)c; return 0; }
int sd_bus_message_exit_container(sd_bus_message *m) { (void)m; return 0; }
int sd_bus_message_skip(sd_bus_message *m, const char *t) { (void)m; (void)t; return 0; }
const char *stub_read_string = NULL;
int sd_bus_message_read(sd_bus_message *m, const char *types, ...) {
	(void)m;
	va_list ap; va_start(ap, types);
	if (strcmp(types, "s") == 0 && stub_read_string) {
		const char **out = va_arg(ap, const char **); *out = stub_read_string;
	}
	va_end(ap); return 1;
}
int sd_bus_message_open_container(sd_bus_message *m, char t, const char *c) { (void)m; (void)t; (void)c; return 0; }
int sd_bus_message_close_container(sd_bus_message *m) { (void)m; return 0; }
int sd_bus_message_append(sd_bus_message *m, const char *t, ...) { (void)m; (void)t; return 0; }

int stub_fd_add_calls = 0, stub_fd_remove_calls = 0;
struct wl_event_source *wl_event_loop_add_fd(struct wl_event_loop *l, int fd, uint32_t mask, wl_event_loop_fd_func_t f, void *d) {
	(void)l; (void)fd; (void)mask; (void)f; (void)d; stub_fd_add_calls++; return (struct wl_event_source *)0x9001;
}
int wl_event_source_remove(struct wl_event_source *s) { (void)s; stub_fd_remove_calls++; return 0; }

struct cairo_surface_t;
struct cairo_t;
static unsigned char stub_pixels[64 * 64 * 4];
int stub_cairo_create_calls = 0, stub_cairo_destroy_calls = 0, stub_surface_destroy_calls = 0;
cairo_surface_t *cairo_image_surface_create(cairo_format_t f, int w, int h) { (void)f; (void)w; (void)h; return (cairo_surface_t *)0x2000; }
cairo_surface_t *cairo_image_surface_create_from_png(const char *p) { (void)p; return NULL; }
unsigned char *cairo_image_surface_get_data(cairo_surface_t *s) { (void)s; return stub_pixels; }
int cairo_image_surface_get_stride(cairo_surface_t *s) { (void)s; return 64 * 4; }
int cairo_image_surface_get_width(cairo_surface_t *s) { (void)s; return 16; }
int cairo_image_surface_get_height(cairo_surface_t *s) { (void)s; return 16; }
cairo_status_t cairo_surface_status(cairo_surface_t *s) { (void)s; return CAIRO_STATUS_SUCCESS; }
void cairo_surface_destroy(cairo_surface_t *s) { (void)s; stub_surface_destroy_calls++; }
cairo_t *cairo_create(cairo_surface_t *s) { (void)s; stub_cairo_create_calls++; return (cairo_t *)0x3000; }
void cairo_destroy(cairo_t *c) { (void)c; stub_cairo_destroy_calls++; }
void cairo_save(cairo_t *c) { (void)c; }
void cairo_restore(cairo_t *c) { (void)c; }
void cairo_scale(cairo_t *c, double x, double y) { (void)c; (void)x; (void)y; }
void cairo_set_source_surface(cairo_t *c, cairo_surface_t *s, double x, double y) { (void)c; (void)s; (void)x; (void)y; }
void cairo_paint(cairo_t *c) { (void)c; }
void cairo_set_operator(cairo_t *c, cairo_operator_t o) { (void)c; (void)o; }
void cairo_set_source_rgba(cairo_t *c, double r, double g, double b, double a) { (void)c; (void)r; (void)g; (void)b; (void)a; }
cairo_surface_t *cairo_image_surface_create_for_data(unsigned char *d, cairo_format_t f, int w, int h, int s) { (void)d; (void)f; (void)w; (void)h; (void)s; return (cairo_surface_t *)0x2000; }

int stub_buffer_init_calls = 0, stub_buffer_drop_calls = 0;
void wlr_buffer_init(struct wlr_buffer *b, const struct wlr_buffer_impl *i, int w, int h) { (void)b; (void)i; (void)w; (void)h; stub_buffer_init_calls++; }
void wlr_buffer_drop(struct wlr_buffer *b) { (void)b; stub_buffer_drop_calls++; }
struct wlr_scene_buffer *stub_scene_buffer = NULL;
struct wlr_scene_buffer *wlr_scene_buffer_create(struct wlr_scene_tree *p, struct wlr_buffer *b) {
	(void)p; (void)b;
	struct wlr_scene_buffer *n = calloc(1, sizeof(*n)); stub_scene_buffer = n; return n;
}
int stub_set_buffer_calls = 0, stub_dest_calls = 0, stub_node_destroy_calls = 0, stub_scene_set_calls = 0;
void wlr_scene_buffer_set_buffer(struct wlr_scene_buffer *n, struct wlr_buffer *b) { (void)n; (void)b; stub_set_buffer_calls++; }
void wlr_scene_buffer_set_dest_size(struct wlr_scene_buffer *n, int w, int h) { (void)n; (void)w; (void)h; stub_dest_calls++; }
void wlr_scene_node_destroy(struct wlr_scene_node *n) { (void)n; stub_node_destroy_calls++; }
struct AcwmSceneNode *acwm_scene_node_set(struct wlr_scene_node *n, uint32_t t, void *o) { (void)n; (void)t; (void)o; stub_scene_set_calls++; return NULL; }
int stub_sync_all_calls = 0;
void bar_tray_sync_all(void) { stub_sync_all_calls++; }
char *string_printf(const char *fmt, ...) { return strdup(fmt); }
