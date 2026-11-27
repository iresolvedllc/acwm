/* Test-only stubs for src/overview/overview.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/animation/client.h"
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"
#include <stddef.h>
#include <string.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_scene.h>

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

uint32_t get_tags_first_tag_num(uint32_t t) { (void)t; return 0; }
struct wlr_surface stub_surface;
struct wlr_surface *client_surface(Client *c) { (void)c; return &stub_surface; }
struct wlr_box stub_geom, stub_clip;
void client_get_geometry(Client *c, struct wlr_box *g) { (void)c; *g = stub_geom; }
void client_get_clip(Client *c, struct wlr_box *g) { (void)c; *g = stub_clip; }
int stub_tiled_calls = 0; uint32_t stub_tiled_edges = 0;
void client_set_tiled(Client *c, uint32_t e) { (void)c; stub_tiled_calls++; stub_tiled_edges = e; }
int stub_sync_calls = 0;
void client_sync_layer(Client *c) { (void)c; stub_sync_calls++; }
int stub_visibility_calls = 0;
void client_update_visibility(Client *c) { (void)c; stub_visibility_calls++; }
int stub_fs_pending_calls = 0, stub_max_pending_calls = 0;
void client_pending_fullscreen_state(Client *c, int32_t f) { (void)c; (void)f; stub_fs_pending_calls++; }
void client_pending_maximized_state(Client *c, int32_t m) { (void)c; (void)m; stub_max_pending_calls++; }
int stub_set_max_calls = 0, stub_apply_fs_calls = 0;
void client_set_maximize_screen(Client *c, int32_t m, bool a) { (void)c; (void)m; (void)a; stub_set_max_calls++; }
void client_apply_fullscreen(Client *c, int32_t f, bool a) { (void)c; (void)f; (void)a; stub_apply_fs_calls++; }
int stub_frame_done_calls = 0;
void client_send_frame_done(Client *c, const struct timespec *n) { (void)c; (void)n; stub_frame_done_calls++; }
int stub_resize_calls = 0; struct wlr_box stub_resize_geo;
void resize(Client *c, struct wlr_box g, ResizeOpts o) { (void)c; (void)o; stub_resize_calls++; stub_resize_geo = g; }
int32_t client_is_x11(Client *c) { (void)c; return 0; }

int stub_filter_calls = 0, stub_corner_calls = 0, stub_source_calls = 0, stub_dest_calls = 0;
void wlr_scene_buffer_set_filter_mode(struct wlr_scene_buffer *b, enum wlr_scale_filter_mode m) { (void)b; (void)m; stub_filter_calls++; }
void wlr_scene_buffer_set_corner_radii(struct wlr_scene_buffer *b, struct fx_corner_radii r) { (void)b; (void)r; stub_corner_calls++; }
struct wlr_fbox stub_source;
void wlr_scene_buffer_set_source_box(struct wlr_scene_buffer *b, const struct wlr_fbox *s) { (void)b; stub_source = *s; stub_source_calls++; }
int32_t stub_dest_w = 0, stub_dest_h = 0;
void wlr_scene_buffer_set_dest_size(struct wlr_scene_buffer *b, int32_t w, int32_t h) { (void)b; stub_dest_w = w; stub_dest_h = h; stub_dest_calls++; }
struct wlr_scene_tree stub_tree;
struct wlr_scene_tree *wlr_scene_tree_create(struct wlr_scene_tree *p) { (void)p; return calloc(1, sizeof(struct wlr_scene_tree)); }
struct wlr_scene_surface stub_scene_surface;
struct wlr_scene_surface *wlr_scene_surface_create(struct wlr_scene_tree *p, struct wlr_surface *s) {
	(void)p; (void)s;
	static struct wlr_scene_buffer buf;
	stub_scene_surface.buffer = &buf;
	return &stub_scene_surface;
}
int stub_pos_calls = 0; int32_t stub_pos_x = 0, stub_pos_y = 0;
void wlr_scene_node_set_position(struct wlr_scene_node *n, int32_t x, int32_t y) { (void)n; stub_pos_calls++; stub_pos_x = x; stub_pos_y = y; }
int stub_enable_calls = 0, stub_raise_calls = 0, stub_destroy_calls = 0;
void wlr_scene_node_set_enabled(struct wlr_scene_node *n, bool e) { n->enabled = e; stub_enable_calls++; }
void wlr_scene_node_raise_to_top(struct wlr_scene_node *n) { (void)n; stub_raise_calls++; }
void wlr_scene_node_destroy(struct wlr_scene_node *n) { (void)n; stub_destroy_calls++; }
int stub_for_each_calls = 0;
void wlr_surface_for_each_surface(struct wlr_surface *s, wlr_surface_iterator_func_t f, void *d) {
	(void)s; stub_for_each_calls++; if (f) f(&stub_surface, 1, 2, d);
}
bool stub_intersect = true; struct wlr_box stub_vis;
bool wlr_box_intersection(struct wlr_box *dst, const struct wlr_box *a, const struct wlr_box *b) {
	(void)a; (void)b; *dst = stub_vis; return stub_intersect;
}
int clock_gettime(clockid_t id, struct timespec *tp) { (void)id; tp->tv_sec = 1; tp->tv_nsec = 0; return 0; }
