/* Test-only stubs for src/ext-protocol/workspace_hdr.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/log.h"
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/manage/monitor.h"
#include <scenefx/types/wlr_scene.h>
#include <stddef.h>
#include <string.h>
#include <wlr/types/wlr_ext_workspace_v1.h>
#include <wlr/types/wlr_output.h>

const char *tags[tag_num_MAX] = {0};

Config config = {0};
struct AcwmServer server = {0};

void wl_list_init(struct wl_list *l) { l->next = l; l->prev = l; }
void wl_list_append(struct wl_list *l, struct wl_list *e) {
	e->prev = l->prev; e->next = l;
	l->prev->next = e; l->prev = e;
}
void wl_list_remove(struct wl_list *e) {
	if (e->prev && e->next) { e->prev->next = e->next; e->next->prev = e->prev; }
	e->next = e; e->prev = e;
}
void *ecalloc(size_t n, size_t s) { return calloc(n, s); }

int stub_switch_calls = 0; uint32_t stub_switch_tags = 0;
int32_t client_switch_view(const Arg *a, bool animate) { (void)animate; stub_switch_calls++; stub_switch_tags = a->ui; return 0; }
int stub_toggle_view_calls = 0; uint32_t stub_toggle_view_tags = 0; int32_t stub_toggle_view_i = 0;
int32_t toggle_view(const Arg *a) { stub_toggle_view_calls++; stub_toggle_view_tags = a->ui; stub_toggle_view_i = a->i; return 0; }
int stub_overview_calls = 0;
int32_t toggle_overview(const Arg *a) { (void)a; stub_overview_calls++; return 0; }
uint32_t stub_tag_status = 0;
uint32_t get_tag_status(uint32_t tag, Monitor *m) { (void)tag; (void)m; return stub_tag_status; }
uint32_t stub_active_tagset = 0;
uint32_t get_monitor_active_tagset(const Monitor *m) { (void)m; return stub_active_tagset; }

struct wlr_ext_workspace_manager_v1 stub_manager;
struct wlr_ext_workspace_manager_v1 *wlr_ext_workspace_manager_v1_create(struct wl_display *d, uint32_t v) {
	(void)d; (void)v; return &stub_manager;
}
int stub_handle_create_calls = 0, stub_handle_destroy_calls = 0;
int stub_group_calls = 0, stub_name_calls = 0;
int stub_hidden_calls = 0, stub_urgent_calls = 0, stub_active_calls = 0;
int stub_last_hidden = -1, stub_last_urgent = -1, stub_last_active = -1;
struct wlr_ext_workspace_handle_v1 *wlr_ext_workspace_handle_v1_create(struct wlr_ext_workspace_manager_v1 *m, const char *name, uint32_t caps) {
	(void)m; (void)name; (void)caps; stub_handle_create_calls++;
	return calloc(1, sizeof(struct wlr_ext_workspace_handle_v1));
}
void wlr_ext_workspace_handle_v1_destroy(struct wlr_ext_workspace_handle_v1 *h) { stub_handle_destroy_calls++; free(h); }
void wlr_ext_workspace_handle_v1_set_group(struct wlr_ext_workspace_handle_v1 *h, struct wlr_ext_workspace_group_handle_v1 *g) { (void)h; (void)g; stub_group_calls++; }
void wlr_ext_workspace_handle_v1_set_name(struct wlr_ext_workspace_handle_v1 *h, const char *n) { (void)h; (void)n; stub_name_calls++; }
void wlr_ext_workspace_handle_v1_set_hidden(struct wlr_ext_workspace_handle_v1 *h, bool v) { (void)h; stub_hidden_calls++; stub_last_hidden = v; }
void wlr_ext_workspace_handle_v1_set_urgent(struct wlr_ext_workspace_handle_v1 *h, bool v) { (void)h; stub_urgent_calls++; stub_last_urgent = v; }
void wlr_ext_workspace_handle_v1_set_active(struct wlr_ext_workspace_handle_v1 *h, bool v) { (void)h; stub_active_calls++; stub_last_active = v; }

int stub_render_format_calls = 0;
void wlr_output_state_set_render_format(struct wlr_output_state *s, uint32_t f) { (void)s; (void)f; stub_render_format_calls++; }
bool stub_test_state = true;
bool wlr_output_test_state(struct wlr_output *o, const struct wlr_output_state *s) { (void)o; (void)s; return stub_test_state; }
int stub_image_desc_calls = 0; int stub_image_desc_null = 0;
struct wlr_output_image_description stub_last_desc;
bool wlr_output_state_set_image_description(struct wlr_output_state *s, const struct wlr_output_image_description *d) {
	(void)s; stub_image_desc_calls++;
	if (!d) { stub_image_desc_null = 1; } else { stub_image_desc_null = 0; stub_last_desc = *d; }
	return true;
}
int stub_schedule_calls = 0;
void wlr_output_schedule_frame(struct wlr_output *o) { (void)o; stub_schedule_calls++; }
void wlr_output_effective_resolution(struct wlr_output *o, int32_t *w, int32_t *h) { (void)o; *w = 1920; *h = 1080; }
int stub_state_finish_calls = 0, stub_state_init_calls = 0;
void wlr_output_state_finish(struct wlr_output_state *s) { (void)s; stub_state_finish_calls++; }
void wlr_output_state_init(struct wlr_output_state *s) { (void)s; stub_state_init_calls++; }
int stub_damage_calls = 0;
void wlr_damage_ring_add_whole(struct wlr_damage_ring *r) { (void)r; stub_damage_calls++; }
void wlr_color_primaries_from_named(struct wlr_color_primaries *p, enum wlr_color_named_primaries n) { (void)n; p->red.x = 1; }
bool stub_commit_ok = true;
int stub_commit_calls = 0;
bool acwm_scene_output_commit(struct wlr_scene_output *o, struct wlr_output_state *s) { (void)o; (void)s; stub_commit_calls++; return stub_commit_ok; }
int stub_error_calls = 0;
void acwm_error_impl(bool log, enum wlr_log_importance v, const char *f, int l, const char *fmt, ...) {
	(void)log; (void)v; (void)f; (void)l; (void)fmt; stub_error_calls++;
}
