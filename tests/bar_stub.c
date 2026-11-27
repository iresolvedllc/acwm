/* Test-only stubs for src/bar/bar.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/bar/bar.h"
#include "acwm/common/log.h"
#include "acwm/common/scene_node.h"
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/draw/text-node.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"
#include <stddef.h>
#include <string.h>

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
int stub_tray_init_calls = 0, stub_tray_cleanup_calls = 0, stub_tray_reload_calls = 0, stub_tray_sync_calls = 0, stub_tray_detach_calls = 0, stub_tray_click_calls = 0;
void tray_init(struct wl_event_loop *l) { (void)l; stub_tray_init_calls++; }
void tray_cleanup(void) { stub_tray_cleanup_calls++; }
void tray_reload(void) { stub_tray_reload_calls++; }
void tray_sync_bar(struct AcwmBar *b) { (void)b; stub_tray_sync_calls++; }
void tray_detach_bar(struct AcwmBar *b) { (void)b; stub_tray_detach_calls++; }
void tray_click(struct AcwmTrayItem *i, uint32_t b) { (void)i; (void)b; stub_tray_click_calls++; }
int stub_bind_calls = 0; uint32_t stub_bind_tags = 0;
int32_t bind_to_view(const Arg *a) { stub_bind_calls++; stub_bind_tags = a->ui; return 0; }
int stub_arrange_layers_calls = 0;
void arrange_layers(Monitor *m) { (void)m; stub_arrange_layers_calls++; }
uint32_t stub_active_tagset = 0;
uint32_t get_monitor_active_tagset(const Monitor *m) { (void)m; return stub_active_tagset; }
bool stub_special_active = false, stub_special_has = false;
bool is_special_active(const Monitor *m) { (void)m; return stub_special_active; }
bool special_has_clients(const Monitor *m) { (void)m; return stub_special_has; }
uint32_t stub_tag_status = 0;
uint32_t get_tag_status(uint32_t t, Monitor *m) { (void)t; (void)m; return stub_tag_status; }

struct wlr_scene_tree stub_bar_parent;
struct wlr_scene_tree *wlr_scene_tree_create(struct wlr_scene_tree *p) { (void)p; return calloc(1, sizeof(struct wlr_scene_tree)); }
struct wlr_scene_rect *wlr_scene_rect_create(struct wlr_scene_tree *p, int32_t w, int32_t h, const float col[4]) {
	(void)p; (void)w; (void)h; (void)col;
	return calloc(1, sizeof(struct wlr_scene_rect));
}
int stub_rect_size_calls = 0; int32_t stub_rect_w = 0, stub_rect_h = 0;
void wlr_scene_rect_set_size(struct wlr_scene_rect *r, int32_t w, int32_t h) { (void)r; stub_rect_size_calls++; stub_rect_w = w; stub_rect_h = h; }
int stub_radius_calls = 0;
void wlr_scene_rect_set_corner_radii(struct wlr_scene_rect *r, struct fx_corner_radii rad) { (void)r; (void)rad; stub_radius_calls++; }
int stub_enable_calls = 0, stub_last_enabled = -1;
void wlr_scene_node_set_enabled(struct wlr_scene_node *n, bool e) { (void)n; stub_enable_calls++; stub_last_enabled = e; n->enabled = e; }
int stub_pos_calls = 0; int32_t stub_last_x = 0, stub_last_y = 0;
void wlr_scene_node_set_position(struct wlr_scene_node *n, int32_t x, int32_t y) { (void)n; stub_pos_calls++; stub_last_x = x; stub_last_y = y; }
int stub_node_destroy_calls = 0;
void wlr_scene_node_destroy(struct wlr_scene_node *n) { (void)n; stub_node_destroy_calls++; free(n); }
int stub_scene_set_calls = 0;
AcwmSceneNode *acwm_scene_node_set(struct wlr_scene_node *n, uint32_t t, void *o) { (void)n; (void)t; (void)o; stub_scene_set_calls++; return NULL; }
struct wlr_scene_node *stub_at_node = NULL;
struct wlr_scene_node *acwm_scene_node_at(struct wlr_scene_node *n, double x, double y, double *nx, double *ny) {
	(void)n; (void)x; (void)y; if (nx) *nx = 0; if (ny) *ny = 0; return stub_at_node;
}
struct AcwmSceneNode stub_scene_data;
struct AcwmSceneNode *stub_scene_find = NULL;
struct AcwmSceneNode *acwm_scene_node_find(struct wlr_scene_node *n) { (void)n; return stub_scene_find; }

struct wl_event_source *stub_last_timer_source = NULL;
int32_t stub_last_timer_ms = 0;
int stub_timer_add_calls = 0, stub_timer_update_calls = 0, stub_timer_remove_calls = 0;
struct wl_event_source *wl_event_loop_add_timer(struct wl_event_loop *l, wl_event_loop_timer_func_t f, void *d) {
	(void)l; (void)f; (void)d; stub_timer_add_calls++;
	return (struct wl_event_source *)0x9001;
}
int wl_event_source_timer_update(struct wl_event_source *s, int32_t ms) {
	stub_timer_update_calls++; stub_last_timer_source = s; stub_last_timer_ms = ms; return 0;
}
int wl_event_source_remove(struct wl_event_source *s) { (void)s; stub_timer_remove_calls++; return 0; }

struct AcwmJumpLabel stub_jump;
struct wlr_scene_tree stub_jump_scene;
int stub_jump_create_calls = 0, stub_jump_destroy_calls = 0, stub_jump_update_calls = 0, stub_jump_focus_calls = 0, stub_jump_bg_calls = 0;
AcwmJumpLabel *acwm_jump_label_node_create(struct wlr_scene_tree *p, DecorateDrawData d) {
	(void)p; (void)d; stub_jump_create_calls++;
	struct AcwmJumpLabel *j = calloc(1, sizeof(*j));
	j->scene = &stub_jump_scene;
	j->logical_width = 20; j->logical_height = 15;
	return j;
}
void acwm_jump_label_node_destroy(AcwmJumpLabel *j) { stub_jump_destroy_calls++; free(j); }
void acwm_jump_label_node_update(AcwmJumpLabel *j, const char *t, float s) { (void)j; (void)t; (void)s; stub_jump_update_calls++; }
void acwm_jump_label_node_set_focus(AcwmJumpLabel *j, bool f) { (void)j; (void)f; stub_jump_focus_calls++; }
void acwm_jump_label_node_set_background(AcwmJumpLabel *j, float r, float g, float b, float a) { (void)j; (void)r; (void)g; (void)b; (void)a; stub_jump_bg_calls++; }
