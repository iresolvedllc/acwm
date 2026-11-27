/* Test-only stubs for manage/client_view.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/animation/client.h"
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/ipc/ipc.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"
#include <stddef.h>
#include <string.h>
#include <wlr/types/wlr_foreign_toplevel_management_v1.h>
#include <wlr/types/wlr_pointer_constraints_v1.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/types/wlr_seat.h>
#include <wlr/types/wlr_subcompositor.h>
#include <wlr/types/wlr_xdg_shell.h>

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
	e->next = e; e->prev = e; stub_list_remove_calls++;
}

bool stub_wallpaper = false;
int stub_wallpaper_calls = 0;
bool blur_layer_on_wallpaper(uint32_t layer) {
	(void)layer; stub_wallpaper_calls++; return stub_wallpaper;
}
uint32_t stub_target_layer = 5;
uint32_t client_target_layer(Client *c) { (void)c; return stub_target_layer; }

int stub_blur_bottom_calls = 0;
bool stub_blur_bottom_value = false;
void wlr_scene_blur_set_should_only_blur_bottom_layer(
	struct wlr_scene_blur *b, bool v) {
	(void)b; stub_blur_bottom_calls++; stub_blur_bottom_value = v;
}
struct wlr_scene_surface *stub_scene_surface = NULL;
struct wlr_scene_surface *wlr_scene_surface_try_from_buffer(
	struct wlr_scene_buffer *b) { (void)b; return stub_scene_surface; }
struct wlr_subsurface *stub_subsurface = NULL;
struct wlr_subsurface *wlr_subsurface_try_from_wlr_surface(
	struct wlr_surface *s) { (void)s; return stub_subsurface; }
int stub_buffer_opacity_calls = 0;
float stub_buffer_opacity = -1;
void wlr_scene_buffer_set_opacity(struct wlr_scene_buffer *b, float o) {
	(void)b; stub_buffer_opacity_calls++; stub_buffer_opacity = o;
}
int stub_for_each_calls = 0;
void wlr_scene_node_for_each_buffer(struct wlr_scene_node *n,
									wlr_scene_buffer_iterator_func_t f,
									void *d) {
	(void)n; stub_for_each_calls++;
	struct wlr_scene_buffer buf = {0};
	if (f) f(&buf, 0, 0, d);
}

int stub_constrain_calls = 0;
void pointer_constrain_cursor(struct wlr_pointer_constraint_v1 *c) {
	(void)c; stub_constrain_calls++;
}
int stub_confine_check_calls = 0;
void pointer_check_confine_client(void) { stub_confine_check_calls++; }
int stub_pointer_motion_calls = 0;
void pointer_process_motion(uint32_t t, struct wlr_input_device *d, double a,
							double b, double cc, double e) {
	(void)t; (void)d; (void)a; (void)b; (void)cc; (void)e;
	stub_pointer_motion_calls++;
}
int stub_relay_calls = 0;
void acwm_im_relay_set_focus(struct acwm_input_method_relay *r,
							 struct wlr_surface *s) {
	(void)r; (void)s; stub_relay_calls++;
}
int stub_raise_group_calls = 0, stub_raise_tab_calls = 0;
void client_raise_group(Client *c) { (void)c; stub_raise_group_calls++; }
void client_raise_tab(Client *c) { (void)c; stub_raise_tab_calls++; }
int stub_unfocused_calls = 0, stub_focused_calls = 0;
void client_set_unfocused_opacity_animation(Client *c) {
	(void)c; stub_unfocused_calls++;
}
void client_set_focused_opacity_animation(Client *c) {
	(void)c; stub_focused_calls++;
}
int stub_tab_sync_calls = 0;
void tab_sync_focus(Client *c) { (void)c; stub_tab_sync_calls++; }
int stub_tab_visible_calls = 0;
void client_check_tab_node_visible(Client *c) {
	(void)c; stub_tab_visible_calls++;
}
int stub_idle_calls = 0, stub_vrr_calls = 0;
void check_keep_idle_inhibit(Client *c) { (void)c; stub_idle_calls++; }
void check_vrr_enable(Client *c) { (void)c; stub_vrr_calls++; }
int stub_clear_focus_calls = 0;
void wlr_seat_keyboard_notify_clear_focus(struct wlr_seat *s) {
	(void)s; stub_clear_focus_calls++;
}
int stub_activate_calls = 0;
int32_t stub_activate_value = -1;
void client_activate_surface(struct wlr_surface *s, int32_t a) {
	(void)s; stub_activate_calls++; stub_activate_value = a;
}
int stub_notify_calls = 0;
void client_notify_enter(struct wlr_surface *s, struct wlr_keyboard *k) {
	(void)s; (void)k; stub_notify_calls++;
}
struct wlr_keyboard stub_kb;
struct wlr_keyboard *wlr_seat_get_keyboard(struct wlr_seat *s) {
	(void)s; return &stub_kb;
}
int stub_set_selected_calls = 0;
Monitor *stub_selected_value = NULL;
void set_selected_monitor(Monitor *m) {
	stub_set_selected_calls++; stub_selected_value = m;
	server.selected_monitor = m;
}
int stub_arrange_calls = 0;
void arrange(Monitor *m, bool a, bool v) {
	(void)m; (void)a; (void)v; stub_arrange_calls++;
}
int stub_resize_calls = 0;
void resize(Client *c, struct wlr_box g, ResizeOpts o) {
	(void)c; (void)g; (void)o; stub_resize_calls++;
}
int stub_set_floating_calls = 0;
void client_set_floating(Client *c, int32_t f) {
	(void)c; (void)f; stub_set_floating_calls++;
}
int stub_apply_fs_calls = 0;
void client_apply_fullscreen(Client *c, int32_t f, bool r) {
	(void)c; (void)f; (void)r; stub_apply_fs_calls++;
}
int stub_pending_min_calls = 0;
void client_pending_minimized_state(Client *c, int32_t m) {
	(void)c; (void)m; stub_pending_min_calls++;
}
int stub_reparent_calls = 0;
void client_reparent_group(Client *c) { (void)c; stub_reparent_calls++; }
bool stub_group_swap = false;
bool client_group_swap_focus(Client *c) { (void)c; return stub_group_swap; }
int stub_border_color_calls = 0;
void client_update_border_color(Client *c) {
	(void)c; stub_border_color_calls++;
}
int stub_clear_fullscreen_calls = 0;
void clear_fullscreen_flag(Client *c) { (void)c; stub_clear_fullscreen_calls++; }
int stub_reset_foreign_calls = 0;
void reset_foreign_tolevel(Client *c, Monitor *o, Monitor *n) {
	(void)c; (void)o; (void)n; stub_reset_foreign_calls++;
}
int stub_reset_tags_calls = 0;
void client_reset_mon_tags(Client *c, Monitor *m, uint32_t t) {
	(void)m; (void)t; stub_reset_tags_calls++;
	c->tags = t ? (t & server.tagmask) : 1;
}
int stub_tag_float_calls = 0;
void check_match_tag_floating_rule(Client *c, Monitor *m) {
	(void)c; (void)m; stub_tag_float_calls++;
}
struct wlr_box stub_center_box;
int stub_center_calls = 0;
struct wlr_box client_center_geometry(Client *c, Monitor *m,
									  struct wlr_box g, int32_t x, int32_t y) {
	(void)c; (void)m; (void)g; (void)x; (void)y;
	stub_center_calls++; return stub_center_box;
}
uint32_t tag_remap_mask(uint32_t tags, const uint32_t *map) {
	uint32_t out = 0;
	for (uint32_t i = 0; i < 32; i++)
		if ((tags & (1u << i)) && i < 32 && map[i])
			out |= 1u << (map[i] - 1);
	return out;
}
int stub_gather_calls = 0;
uint32_t stub_gather_dst = 0, stub_gather_src = 0;
void tag_gather_move_pertag(Monitor *m, uint32_t dst, uint32_t src) {
	(void)m; stub_gather_calls++; stub_gather_dst = dst; stub_gather_src = src;
}
int stub_status = 0;
uint32_t get_tag_status(uint32_t tag, Monitor *m) {
	(void)tag; (void)m; return stub_status;
}
uint32_t get_tags_first_tag(uint32_t tags) {
	uint32_t i = 0; while (i < 32 && (tags & (1u << i)) == 0) i++;
	return i < 32 ? (1u << i) : 0;
}
uint32_t get_tags_first_tag_num(uint32_t tags) {
	uint32_t i = 0; while (i < 32 && (tags & (1u << i)) == 0) i++;
	return i + 1;
}
bool stub_scroller = false, stub_monocle = false;
bool is_scroller_layout(Monitor *m) { (void)m; return stub_scroller; }
bool is_monocle_layout(Monitor *m) { (void)m; return stub_monocle; }
int stub_set_size_per_calls = 0;
void set_size_per(Monitor *m, Client *c, bool r) {
	(void)m; (void)c; (void)r; stub_set_size_per_calls++;
}
int stub_printstatus_calls = 0;
void printstatus(enum ipc_watch_type t) {
	(void)t; stub_printstatus_calls++;
}
int32_t stub_unmanaged = 0, stub_x11_popup = 0, stub_ignore_focus = 0;
int32_t stub_wants_focus = 0;
int32_t client_is_unmanaged(Client *c) { (void)c; return stub_unmanaged; }
int32_t client_is_x11_popup(Client *c) { (void)c; return stub_x11_popup; }
int32_t client_should_ignore_focus(Client *c) {
	(void)c; return stub_ignore_focus;
}
int32_t client_wants_focus(Client *c) { (void)c; return stub_wants_focus; }
struct wlr_surface *stub_surface = NULL;
struct wlr_surface *client_surface(Client *c) { (void)c; return stub_surface; }
int32_t stub_toplevel_kind = -1;
Client *stub_toplevel_client = NULL;
LayerSurface *stub_toplevel_layer = NULL;
int32_t toplevel_from_wlr_surface(struct wlr_surface *s, Client **pc,
								  LayerSurface **pl) {
	(void)s;
	if (pc) *pc = stub_toplevel_client;
	if (pl) *pl = stub_toplevel_layer;
	return stub_toplevel_kind;
}
Client *stub_top_client = NULL;
Client *client_focus_top(Monitor *m) { (void)m; return stub_top_client; }
int stub_ft_activate_calls = 0;
bool stub_ft_activate_value = false;
void wlr_foreign_toplevel_handle_v1_set_activated(
	struct wlr_foreign_toplevel_handle_v1 *h, bool a) {
	(void)h; stub_ft_activate_calls++; stub_ft_activate_value = a;
}
bool client_is_parked(Client *c) { (void)c; return false; }
