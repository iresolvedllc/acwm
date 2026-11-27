/* Test-only stubs for src/ext-protocol/protocol_small.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/log.h"
#include "acwm/common/server.h"
#include "acwm/common/util.h"
#include "acwm/ipc/ipc.h"
#include "acwm/config/parse.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"
#include <stddef.h>
#include <string.h>
#include <wlr/types/wlr_foreign_toplevel_management_v1.h>
#include <wlr/types/wlr_tearing_control_v1.h>
#include <wlr/types/wlr_xdg_activation_v1.h>

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
void *ecalloc(size_t n, size_t s) { return calloc(n, s); }

Client *stub_toplevel_client = NULL;
int32_t toplevel_from_wlr_surface(struct wlr_surface *s, Client **pc, LayerSurface **pl) {
	(void)s;
	if (pc) *pc = stub_toplevel_client;
	if (pl) *pl = NULL;
	return stub_toplevel_client ? 0 : -1;
}
int stub_active_calls = 0;
void client_active(Client *c) { (void)c; stub_active_calls++; }
int stub_max_calls = 0; int32_t stub_max_value = -1;
void client_set_maximize_screen(Client *c, int32_t m, bool a) { (void)c; (void)a; stub_max_calls++; stub_max_value = m; }
int stub_min_calls = 0;
void set_minimized(Client *c) { (void)c; stub_min_calls++; }
int stub_show_hide_calls = 0;
void show_hide_client(Client *c) { (void)c; stub_show_hide_calls++; }
int stub_border_calls = 0;
void client_update_border_color(Client *c) { (void)c; stub_border_calls++; }
int stub_full_calls = 0; int32_t stub_full_value = -1;
void client_apply_fullscreen(Client *c, int32_t f, bool a) { (void)c; (void)a; stub_full_calls++; stub_full_value = f; }
int stub_kill_calls = 0;
void pending_kill_client(Client *c) { (void)c; stub_kill_calls++; }
int stub_arrange_calls = 0;
void arrange(Monitor *m, bool a, bool v) { (void)m; (void)a; (void)v; stub_arrange_calls++; }
Client *stub_focus_top = NULL;
Client *client_focus_top(Monitor *m) { (void)m; return stub_focus_top; }
struct wlr_surface stub_surface;
struct wlr_surface *client_surface(Client *c) { (void)c; return &stub_surface; }
const char *client_get_appid(Client *c) { (void)c; return "app"; }
const char *client_get_title(Client *c) { (void)c; return "title"; }
int stub_activation_request_calls = 0;
void handle_client_activation_request(struct wl_listener *l, void *d) { (void)l; (void)d; stub_activation_request_calls++; }
int stub_printstatus_calls = 0;
void printstatus(enum ipc_watch_type t) { (void)t; stub_printstatus_calls++; }
const char *wayland_string_set(struct wayland_string *dst, const char *src) {
	snprintf(dst->data, sizeof(dst->data), "%s", src ? src : "");
	return dst->data;
}

enum wp_tearing_control_v1_presentation_hint stub_tearing_hint = WP_TEARING_CONTROL_V1_PRESENTATION_HINT_VSYNC;
enum wp_tearing_control_v1_presentation_hint wlr_tearing_control_manager_v1_surface_hint_from_surface(
	struct wlr_tearing_control_manager_v1 *m, struct wlr_surface *s) {
	(void)m; (void)s; return stub_tearing_hint;
}
int stub_error_calls = 0;
void acwm_error_impl(bool log, enum wlr_log_importance v, const char *f, int l, const char *fmt, ...) {
	(void)log; (void)v; (void)f; (void)l; (void)fmt; stub_error_calls++;
}

struct wlr_xdg_activation_v1 stub_activation;
struct wlr_xdg_activation_v1 *wlr_xdg_activation_v1_create(struct wl_display *d) { (void)d; return &stub_activation; }
struct wlr_xdg_activation_token_v1 stub_token;
struct wlr_xdg_activation_token_v1 *wlr_xdg_activation_token_v1_create(struct wlr_xdg_activation_v1 *a) {
	(void)a; memset(&stub_token, 0, sizeof(stub_token)); return &stub_token;
}
int stub_token_destroy_calls = 0;
void wlr_xdg_activation_token_v1_destroy(struct wlr_xdg_activation_token_v1 *t) { (void)t; stub_token_destroy_calls++; }
const char *wlr_xdg_activation_token_v1_get_name(struct wlr_xdg_activation_token_v1 *t) { (void)t; return "token-name"; }

struct wlr_foreign_toplevel_handle_v1 stub_handle;
struct wlr_foreign_toplevel_handle_v1 *stub_created_handle = &stub_handle;
struct wlr_foreign_toplevel_handle_v1 *wlr_foreign_toplevel_handle_v1_create(struct wlr_foreign_toplevel_manager_v1 *m) {
	(void)m; return stub_created_handle;
}
int stub_appid_calls = 0, stub_title_calls = 0, stub_enter_calls = 0, stub_leave_calls = 0;
void wlr_foreign_toplevel_handle_v1_set_app_id(struct wlr_foreign_toplevel_handle_v1 *h, const char *id) { (void)h; (void)id; stub_appid_calls++; }
void wlr_foreign_toplevel_handle_v1_set_title(struct wlr_foreign_toplevel_handle_v1 *h, const char *t) { (void)h; (void)t; stub_title_calls++; }
void wlr_foreign_toplevel_handle_v1_output_enter(struct wlr_foreign_toplevel_handle_v1 *h, struct wlr_output *o) { (void)h; (void)o; stub_enter_calls++; }
void wlr_foreign_toplevel_handle_v1_output_leave(struct wlr_foreign_toplevel_handle_v1 *h, struct wlr_output *o) { (void)h; (void)o; stub_leave_calls++; }
