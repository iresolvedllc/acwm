/* Test-only stubs for src/switcher/switcher.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"
#include "acwm/switcher/switcher.h"
#include <stddef.h>
#include <string.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/types/wlr_color_management_v1.h>
#include <wlr/types/wlr_color_representation_v1.h>

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

uint32_t get_tags_first_tag(uint32_t t) { (void)t; return 1; }
struct wlr_surface stub_surface;
struct wlr_surface *client_surface(Client *c) { (void)c; return &stub_surface; }
int stub_clip_calls = 0; struct wlr_box stub_clip;
void client_get_clip(Client *c, struct wlr_box *b) { (void)c; stub_clip_calls++; *b = stub_clip; }
int stub_unmanaged = 0, stub_x11popup = 0, stub_x11 = 0;
int32_t client_is_unmanaged(Client *c) { (void)c; return stub_unmanaged; }
int32_t client_is_x11_popup(Client *c) { (void)c; return stub_x11popup; }
int32_t client_is_x11(Client *c) { (void)c; return stub_x11; }
int stub_frame_calls = 0;
void client_send_frame_done(Client *c, const struct timespec *n) { (void)c; (void)n; stub_frame_calls++; }
int stub_focus_calls = 0;
void client_focus(Client *c, int32_t lift) { (void)c; (void)lift; stub_focus_calls++; }
int stub_view_calls = 0;
void client_view_on_monitor(const Arg *a, bool an, Monitor *m, bool fr) { (void)a; (void)an; (void)m; (void)fr; stub_view_calls++; }

struct wlr_scene_tree stub_tree[32]; int stub_tree_idx = 0;
struct wlr_scene_tree *wlr_scene_tree_create(struct wlr_scene_tree *p) { (void)p; return &stub_tree[stub_tree_idx++ % 32]; }
struct wlr_scene_rect stub_rect[32]; int stub_rect_idx = 0;
struct wlr_scene_rect *wlr_scene_rect_create(struct wlr_scene_tree *p, int32_t w, int32_t h, const float col[4]) {
	(void)p; (void)w; (void)h; (void)col; return &stub_rect[stub_rect_idx++ % 32];
}
int stub_rect_size_calls = 0, stub_rect_color_calls = 0;
void wlr_scene_rect_set_size(struct wlr_scene_rect *r, int32_t w, int32_t h) { (void)r; (void)w; (void)h; stub_rect_size_calls++; }
void wlr_scene_rect_set_color(struct wlr_scene_rect *r, const float c[4]) { (void)r; (void)c; stub_rect_color_calls++; }
struct wlr_scene_buffer stub_buffer[32]; int stub_buffer_idx = 0;
struct wlr_scene_buffer *wlr_scene_buffer_create(struct wlr_scene_tree *p, struct wlr_buffer *b) { (void)p; (void)b; return &stub_buffer[stub_buffer_idx++ % 32]; }
int stub_filter_calls = 0, stub_source_calls = 0, stub_dest_calls = 0, stub_transform_calls = 0, stub_opacity_calls = 0;
int stub_tf_calls = 0, stub_prim_calls = 0, stub_enc_calls = 0, stub_range_calls = 0, stub_setbuf_calls = 0;
void wlr_scene_buffer_set_filter_mode(struct wlr_scene_buffer *b, enum wlr_scale_filter_mode m) { (void)b; (void)m; stub_filter_calls++; }
void wlr_scene_buffer_set_source_box(struct wlr_scene_buffer *b, const struct wlr_fbox *f) { (void)b; (void)f; stub_source_calls++; }
void wlr_scene_buffer_set_dest_size(struct wlr_scene_buffer *b, int32_t w, int32_t h) { (void)b; (void)w; (void)h; stub_dest_calls++; }
void wlr_scene_buffer_set_transform(struct wlr_scene_buffer *b, enum wl_output_transform t) { (void)b; (void)t; stub_transform_calls++; }
void wlr_scene_buffer_set_opacity(struct wlr_scene_buffer *b, float o) { (void)b; (void)o; stub_opacity_calls++; }
void wlr_scene_buffer_set_transfer_function(struct wlr_scene_buffer *b, enum wlr_color_transfer_function t) { (void)b; (void)t; stub_tf_calls++; }
void wlr_scene_buffer_set_primaries(struct wlr_scene_buffer *b, enum wlr_color_named_primaries p) { (void)b; (void)p; stub_prim_calls++; }
void wlr_scene_buffer_set_color_encoding(struct wlr_scene_buffer *b, enum wlr_color_encoding e) { (void)b; (void)e; stub_enc_calls++; }
void wlr_scene_buffer_set_color_range(struct wlr_scene_buffer *b, enum wlr_color_range r) { (void)b; (void)r; stub_range_calls++; }
void wlr_scene_buffer_set_buffer(struct wlr_scene_buffer *b, struct wlr_buffer *buf) { (void)b; (void)buf; stub_setbuf_calls++; }
void wlr_scene_buffer_set_buffer_with_options(struct wlr_scene_buffer *b, struct wlr_buffer *buf, const struct wlr_scene_buffer_set_buffer_options *o) { (void)b; (void)buf; (void)o; stub_setbuf_calls++; }
int stub_pos_calls = 0;
void wlr_scene_node_set_position(struct wlr_scene_node *n, int32_t x, int32_t y) { (void)n; (void)x; (void)y; stub_pos_calls++; }
int stub_node_destroy_calls = 0;
void wlr_scene_node_destroy(struct wlr_scene_node *n) { (void)n; stub_node_destroy_calls++; }
int stub_coords_calls = 0; int32_t stub_coord_x = 0, stub_coord_y = 0;
bool wlr_scene_node_coords(struct wlr_scene_node *n, int32_t *x, int32_t *y) { (void)n; stub_coords_calls++; *x = stub_coord_x; *y = stub_coord_y; return true; }
int stub_for_each_calls = 0;
void wlr_surface_for_each_surface(struct wlr_surface *s, wlr_surface_iterator_func_t f, void *d) { (void)s; stub_for_each_calls++; if (f) f(&stub_surface, 0, 0, d); }
struct wlr_fbox stub_source_box;
void wlr_surface_get_buffer_source_box(struct wlr_surface *s, struct wlr_fbox *b) { (void)s; *b = stub_source_box; }
int stub_surface_frame_calls = 0;
void wlr_surface_send_frame_done(struct wlr_surface *s, const struct timespec *w) { (void)s; (void)w; stub_surface_frame_calls++; }
const struct wlr_alpha_modifier_surface_v1_state *wlr_alpha_modifier_v1_get_surface_state(struct wlr_surface *s) { (void)s; return NULL; }
const struct wlr_image_description_v1_data *wlr_surface_get_image_description_v1_data(struct wlr_surface *s) { (void)s; return NULL; }
enum wlr_color_transfer_function wlr_color_manager_v1_transfer_function_to_wlr(enum wp_color_manager_v1_transfer_function t) { (void)t; return WLR_COLOR_TRANSFER_FUNCTION_GAMMA22; }
enum wlr_color_named_primaries wlr_color_manager_v1_primaries_to_wlr(enum wp_color_manager_v1_primaries p) { (void)p; return WLR_COLOR_NAMED_PRIMARIES_SRGB; }
const struct wlr_color_representation_v1_surface_state *wlr_color_representation_v1_get_surface_state(struct wlr_surface *s) { (void)s; return NULL; }
enum wlr_color_encoding wlr_color_representation_v1_color_encoding_to_wlr(enum wp_color_representation_surface_v1_coefficients c) { (void)c; return WLR_COLOR_ENCODING_NONE; }
enum wlr_color_range wlr_color_representation_v1_color_range_to_wlr(enum wp_color_representation_surface_v1_range r) { (void)r; return WLR_COLOR_RANGE_NONE; }
struct wlr_linux_drm_syncobj_surface_v1_state *wlr_linux_drm_syncobj_v1_get_surface_state(struct wlr_surface *s) { (void)s; return NULL; }
bool wlr_linux_drm_syncobj_v1_state_add_release_point(struct wlr_linux_drm_syncobj_surface_v1_state *st, struct wlr_drm_syncobj_timeline *t, uint64_t p, struct wl_event_loop *l) { (void)st; (void)t; (void)p; (void)l; return true; }
void wlr_presentation_surface_scanned_out_on_output(struct wlr_surface *s, struct wlr_output *o) { (void)s; (void)o; }
void wlr_presentation_surface_textured_on_output(struct wlr_surface *s, struct wlr_output *o) { (void)s; (void)o; }
bool stub_contains = true;
bool wlr_box_contains_point(const struct wlr_box *b, double x, double y) { (void)b; (void)x; (void)y; return stub_contains; }
int clock_gettime(clockid_t id, struct timespec *tp) { (void)id; tp->tv_sec = 1; tp->tv_nsec = 0; return 0; }
