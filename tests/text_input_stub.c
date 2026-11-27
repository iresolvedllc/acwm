/* Test-only stubs for src/ext-protocol/text_input.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/ext-protocol/text-input.h"
#include "acwm/input/keyboard.h"
#include "acwm/manage/monitor.h"
#include <stddef.h>
#include <string.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_input_method_v2.h>
#include <wlr/types/wlr_text_input_v3.h>
#include <wlr/types/wlr_virtual_keyboard_v1.h>
#include <wlr/types/wlr_xdg_shell.h>

struct wlr_surface stub_surface;

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
struct wl_client *stub_client = (struct wl_client *)0x1000;
struct wl_client *wl_resource_get_client(struct wl_resource *r) { (void)r; return stub_client; }
struct wlr_virtual_keyboard_v1 stub_vk;
struct wlr_virtual_keyboard_v1 *stub_virtual_keyboard = NULL;
struct wlr_virtual_keyboard_v1 *wlr_input_device_get_virtual_keyboard(struct wlr_input_device *d) {
	(void)d; return stub_virtual_keyboard;
}
int stub_set_kb_calls = 0, stub_send_mods_calls = 0, stub_send_key_calls = 0;
void wlr_input_method_keyboard_grab_v2_set_keyboard(struct wlr_input_method_keyboard_grab_v2 *g, struct wlr_keyboard *k) { (void)g; (void)k; stub_set_kb_calls++; }
void wlr_input_method_keyboard_grab_v2_send_modifiers(struct wlr_input_method_keyboard_grab_v2 *g, struct wlr_keyboard_modifiers *m) { (void)g; (void)m; stub_send_mods_calls++; }
void wlr_input_method_keyboard_grab_v2_send_key(struct wlr_input_method_keyboard_grab_v2 *g, uint32_t t, uint32_t k, uint32_t s) { (void)g; (void)t; (void)k; (void)s; stub_send_key_calls++; }
int stub_activate_calls = 0, stub_deactivate_calls = 0, stub_im_done_calls = 0, stub_unavailable_calls = 0;
void wlr_input_method_v2_send_activate(struct wlr_input_method_v2 *m) { (void)m; stub_activate_calls++; }
void wlr_input_method_v2_send_deactivate(struct wlr_input_method_v2 *m) { (void)m; stub_deactivate_calls++; }
void wlr_input_method_v2_send_done(struct wlr_input_method_v2 *m) { (void)m; stub_im_done_calls++; }
void wlr_input_method_v2_send_unavailable(struct wlr_input_method_v2 *m) { (void)m; stub_unavailable_calls++; }
int stub_surrounding_calls = 0, stub_cause_calls = 0, stub_content_calls = 0;
void wlr_input_method_v2_send_surrounding_text(struct wlr_input_method_v2 *m, const char *t, uint32_t c, uint32_t a) { (void)m; (void)t; (void)c; (void)a; stub_surrounding_calls++; }
void wlr_input_method_v2_send_text_change_cause(struct wlr_input_method_v2 *m, uint32_t c) { (void)m; (void)c; stub_cause_calls++; }
void wlr_input_method_v2_send_content_type(struct wlr_input_method_v2 *m, uint32_t h, uint32_t p) { (void)m; (void)h; (void)p; stub_content_calls++; }
int stub_preedit_calls = 0, stub_commit_calls = 0, stub_delete_calls = 0, stub_ti_done_calls = 0, stub_leave_calls = 0, stub_enter_calls = 0;
void wlr_text_input_v3_send_preedit_string(struct wlr_text_input_v3 *i, const char *t, int32_t b, int32_t e) { (void)i; (void)t; (void)b; (void)e; stub_preedit_calls++; }
void wlr_text_input_v3_send_commit_string(struct wlr_text_input_v3 *i, const char *t) { (void)i; (void)t; stub_commit_calls++; }
void wlr_text_input_v3_send_delete_surrounding_text(struct wlr_text_input_v3 *i, uint32_t b, uint32_t a) { (void)i; (void)b; (void)a; stub_delete_calls++; }
void wlr_text_input_v3_send_done(struct wlr_text_input_v3 *i) { (void)i; stub_ti_done_calls++; }
void wlr_text_input_v3_send_leave(struct wlr_text_input_v3 *i) { i->focused_surface = NULL; stub_leave_calls++; }
void wlr_text_input_v3_send_enter(struct wlr_text_input_v3 *i, struct wlr_surface *s) { i->focused_surface = s; stub_enter_calls++; }
int stub_seat_mods_calls = 0;
void wlr_seat_keyboard_notify_modifiers(struct wlr_seat *s, const struct wlr_keyboard_modifiers *m) { (void)s; (void)m; stub_seat_mods_calls++; }
struct wlr_keyboard *stub_seat_kb = NULL;
struct wlr_keyboard *wlr_seat_get_keyboard(struct wlr_seat *s) { (void)s; return stub_seat_kb; }
struct wlr_xdg_surface *stub_xdg = NULL;
struct wlr_xdg_surface *wlr_xdg_surface_try_from_wlr_surface(struct wlr_surface *s) { (void)s; return stub_xdg; }
struct wlr_layer_surface_v1 *stub_layer = NULL;
struct wlr_layer_surface_v1 *wlr_layer_surface_v1_try_from_wlr_surface(struct wlr_surface *s) { (void)s; return stub_layer; }
int stub_coords_calls = 0; int32_t stub_coord_x = 0, stub_coord_y = 0;
bool wlr_scene_node_coords(struct wlr_scene_node *n, int32_t *x, int32_t *y) { (void)n; stub_coords_calls++; *x = stub_coord_x; *y = stub_coord_y; return true; }
int stub_pos_calls = 0; int32_t stub_pos_x = 0, stub_pos_y = 0;
void wlr_scene_node_set_position(struct wlr_scene_node *n, int32_t x, int32_t y) { (void)n; stub_pos_calls++; stub_pos_x = x; stub_pos_y = y; }
int stub_raise_calls = 0, stub_destroy_node_calls = 0;
void wlr_scene_node_raise_to_top(struct wlr_scene_node *n) { (void)n; stub_raise_calls++; }
void wlr_scene_node_destroy(struct wlr_scene_node *n) { (void)n; stub_destroy_node_calls++; }
struct wlr_scene_tree stub_tree;
struct wlr_scene_tree *wlr_scene_tree_create(struct wlr_scene_tree *p) { (void)p; return &stub_tree; }
struct wlr_scene_tree stub_subtree;
struct wlr_scene_tree *wlr_scene_subsurface_tree_create(struct wlr_scene_tree *p, struct wlr_surface *s) { (void)p; (void)s; return &stub_subtree; }
void wlr_output_layout_get_box(struct wlr_output_layout *l, struct wlr_output *o, struct wlr_box *b) { (void)l; (void)o; b->x = 0; b->y = 0; b->width = 1000; b->height = 800; }
void wlr_xdg_positioner_rules_get_geometry(const struct wlr_xdg_positioner_rules *r, struct wlr_box *b) { b->x = r->anchor_rect.x; b->y = r->anchor_rect.y + r->anchor_rect.height; b->width = r->size.width; b->height = r->size.height; }
void wlr_xdg_positioner_rules_unconstrain_box(const struct wlr_xdg_positioner_rules *r, const struct wlr_box *bounds, struct wlr_box *box) { (void)r; if (box->x + box->width > bounds->width) box->x = bounds->width - box->width; }
int stub_rect_calls = 0; struct wlr_box stub_rect;
void wlr_input_popup_surface_v2_send_text_input_rectangle(struct wlr_input_popup_surface_v2 *p, struct wlr_box *r) { (void)p; stub_rect_calls++; stub_rect = *r; }
struct Monitor *stub_nearest = NULL;
Monitor *get_monitor_nearest_to(int32_t x, int32_t y) { (void)x; (void)y; return stub_nearest; }
int stub_scene_set_calls = 0;
bool acwm_scene_node_set(struct wlr_scene_node *n, uint32_t t, void *o) { (void)n; (void)t; (void)o; stub_scene_set_calls++; return true; }
