/* Test-only stubs for src/animation/client.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/animation/client.h"
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"
#include "acwm/overview/overview.h"
#include <stddef.h>
#include <string.h>

Config config = {0};
struct AcwmServer server = {0};

int stub_gesture = 0;
bool client_gesture_driven(const Client *c) { (void)c; return stub_gesture != 0; }

int stub_scroller = 0;
bool is_scroller_layout(Monitor *m) { (void)m; return stub_scroller != 0; }

uint32_t stub_tag = 0;
uint32_t get_mon_curtag(const Monitor *m) { (void)m; return stub_tag; }

int stub_card_radii_calls = 0;
struct fx_corner_radii stub_card_radii;
void overview_card_set_corner_radii(Client *c, struct fx_corner_radii corners) {
    (void)c;
    stub_card_radii_calls++;
    stub_card_radii = corners;
}

int stub_rect_w = -1, stub_rect_h = -1;
int stub_rect_call_count = 0;
int stub_rect_call_w[16], stub_rect_call_h[16];
void wlr_scene_rect_set_size(struct wlr_scene_rect *rect, int width, int height) {
    (void)rect;
    stub_rect_w = width;
    stub_rect_h = height;
    if (stub_rect_call_count < 16) {
        stub_rect_call_w[stub_rect_call_count] = width;
        stub_rect_call_h[stub_rect_call_count] = height;
    }
    stub_rect_call_count++;
}

int stub_dest_size_calls = 0, stub_dest_w = 0, stub_dest_h = 0;
void wlr_scene_buffer_set_dest_size(struct wlr_scene_buffer *buffer, int width, int height) {
    (void)buffer;
    stub_dest_size_calls++;
    stub_dest_w = width;
    stub_dest_h = height;
}

int stub_buffer_radii_calls = 0;
struct fx_corner_radii stub_buffer_radii;
void wlr_scene_buffer_set_corner_radii(struct wlr_scene_buffer *buffer, struct fx_corner_radii radii) {
    (void)buffer;
    stub_buffer_radii_calls++;
    stub_buffer_radii = radii;
}

int stub_blur_radii_calls = 0;
struct fx_corner_radii stub_blur_radii;
void wlr_scene_blur_set_corner_radii(struct wlr_scene_blur *blur, struct fx_corner_radii radii) {
    (void)blur;
    stub_blur_radii_calls++;
    stub_blur_radii = radii;
}

int stub_for_each_calls = 0, stub_iterate = 0;
struct wlr_scene_buffer *stub_scene_buffer = NULL;
void wlr_scene_node_for_each_buffer(struct wlr_scene_node *node,
                                    wlr_scene_buffer_iterator_func_t iterator,
                                    void *user_data) {
    (void)node;
    stub_for_each_calls++;
    if (stub_iterate)
        iterator(stub_scene_buffer, 0, 0, user_data);
}

struct wlr_scene_surface *stub_scene_surface = NULL;
struct wlr_scene_surface *wlr_scene_surface_try_from_buffer(struct wlr_scene_buffer *buffer) {
    (void)buffer;
    return stub_scene_surface;
}

struct wlr_subsurface *stub_subsurface = NULL;
struct wlr_subsurface *wlr_subsurface_try_from_wlr_surface(struct wlr_surface *surface) {
    (void)surface;
    return stub_subsurface;
}

struct wlr_xdg_popup *stub_popup = NULL;
struct wlr_xdg_popup *wlr_xdg_popup_try_from_wlr_surface(struct wlr_surface *surface) {
    (void)surface;
    return stub_popup;
}

struct wlr_xwayland_surface *stub_xwayland_surface = NULL;
struct wlr_xwayland_surface *wlr_xwayland_surface_try_from_wlr_surface(struct wlr_surface *surface) {
    (void)surface;
    return stub_xwayland_surface;
}

/* ---- animation draw helpers (slice 88) ---- */
struct wlr_surface *stub_surface = NULL;
struct wlr_surface *client_surface(Client *c) { (void)c; return stub_surface; }
int stub_hit_no_border = 0;
bool check_hit_no_border(Client *c) { (void)c; return stub_hit_no_border != 0; }
int stub_wants_group_bar = 0;
bool client_wants_group_bar(Client *c) { (void)c; return stub_wants_group_bar != 0; }
Client *stub_group_head = NULL;
Client *client_group_head(Client *c) { return stub_group_head != NULL ? stub_group_head : c; }
int stub_tab_visible_calls = 0;
void client_check_tab_node_visible(Client *c) { (void)c; stub_tab_visible_calls++; }
int stub_visibility_calls = 0;
void client_update_visibility(Client *c) { (void)c; stub_visibility_calls++; }
uint32_t stub_client_tag = 0;
uint32_t get_client_tag_idx(const Client *c) { (void)c; return stub_client_tag; }
DwindleNode *stub_dnode = NULL;
DwindleNode *dwindle_find_leaf(DwindleNode *node, Client *c) { (void)node; (void)c; return stub_dnode; }

int stub_dim_enabled_calls = 0, stub_dim_enabled_value = -1;
int stub_dim_radius_calls = 0, stub_dim_radius = -1;
int stub_dim_box_calls = 0, stub_dim_box[4];
void acwm_dim_node_set_enabled(AcwmDimNode *node, bool enabled) {
    (void)node; stub_dim_enabled_calls++; stub_dim_enabled_value = enabled ? 1 : 0;
}
void acwm_dim_node_set_radius(AcwmDimNode *node, int32_t radius) {
    (void)node; stub_dim_radius_calls++; stub_dim_radius = radius;
}
void acwm_dim_node_set_box(AcwmDimNode *node, int32_t x, int32_t y, int32_t width, int32_t height) {
    (void)node; stub_dim_box_calls++; stub_dim_box[0] = x; stub_dim_box[1] = y;
    stub_dim_box[2] = width; stub_dim_box[3] = height;
}
int stub_bar_size_calls = 0, stub_bar_w = 0, stub_bar_h = 0;
void acwm_bar_decoration_set_size(AcwmBarDecoration *node, int32_t width, int32_t height) {
    (void)node; stub_bar_size_calls++; stub_bar_w = width; stub_bar_h = height;
}

int stub_node_enabled_calls = 0, stub_node_enabled_value = -1;
struct wlr_scene_node *stub_node_enabled_ptr = NULL;
void wlr_scene_node_set_enabled(struct wlr_scene_node *node, bool enabled) {
    stub_node_enabled_calls++; stub_node_enabled_value = enabled ? 1 : 0; stub_node_enabled_ptr = node;
    if (node) node->enabled = enabled;
}
int stub_node_pos_calls = 0;
struct wlr_scene_node *stub_pos_node[24];
int32_t stub_pos_x[24], stub_pos_y[24];
void wlr_scene_node_set_position(struct wlr_scene_node *node, int x, int y) {
    if (stub_node_pos_calls < 24) {
        stub_pos_node[stub_node_pos_calls] = node;
        stub_pos_x[stub_node_pos_calls] = x;
        stub_pos_y[stub_node_pos_calls] = y;
    }
    stub_node_pos_calls++;
}
int stub_lower_calls = 0, stub_raise_calls = 0;
void wlr_scene_node_lower_to_bottom(struct wlr_scene_node *node) { (void)node; stub_lower_calls++; }
void wlr_scene_node_raise_to_top(struct wlr_scene_node *node) { (void)node; stub_raise_calls++; }

int stub_shadow_size_calls = 0, stub_shadow_w = 0, stub_shadow_h = 0;
void wlr_scene_shadow_set_size(struct wlr_scene_shadow *shadow, int width, int height) {
    (void)shadow; stub_shadow_size_calls++; stub_shadow_w = width; stub_shadow_h = height;
}
int stub_shadow_clip_calls = 0;
struct clipped_region stub_shadow_clip;
void wlr_scene_shadow_set_clipped_region(struct wlr_scene_shadow *shadow, struct clipped_region region) {
    (void)shadow; stub_shadow_clip_calls++; stub_shadow_clip = region;
}
int stub_rect_corner_calls = 0;
struct fx_corner_radii stub_rect_corners;
void wlr_scene_rect_set_corner_radii(struct wlr_scene_rect *rect, struct fx_corner_radii radii) {
    (void)rect; stub_rect_corner_calls++; stub_rect_corners = radii;
}
int stub_rect_clip_calls = 0;
struct clipped_region stub_rect_clip;
void wlr_scene_rect_set_clipped_region(struct wlr_scene_rect *rect, struct clipped_region region) {
    (void)rect; stub_rect_clip_calls++; stub_rect_clip = region;
}
int stub_blur_size_calls = 0, stub_blur_w = 0, stub_blur_h = 0;
void wlr_scene_blur_set_size(struct wlr_scene_blur *blur, int width, int height) {
    (void)blur; stub_blur_size_calls++; stub_blur_w = width; stub_blur_h = height;
}

bool wlr_box_intersection(struct wlr_box *dest, const struct wlr_box *box_a,
                          const struct wlr_box *box_b) {
    int x1 = box_a->x > box_b->x ? box_a->x : box_b->x;
    int y1 = box_a->y > box_b->y ? box_a->y : box_b->y;
    int x2 = box_a->x + box_a->width < box_b->x + box_b->width
                 ? box_a->x + box_a->width : box_b->x + box_b->width;
    int y2 = box_a->y + box_a->height < box_b->y + box_b->height
                 ? box_a->y + box_a->height : box_b->y + box_b->height;
    if (x2 <= x1 || y2 <= y1) {
        dest->x = dest->y = dest->width = dest->height = 0;
        return false;
    }
    dest->x = x1; dest->y = y1; dest->width = x2 - x1; dest->height = y2 - y1;
    return true;
}

/* ---- drop area / clip / fadeout (slice 89) ---- */
int stub_get_clip_calls = 0;
struct wlr_box stub_clip = {0, 0, 100, 80};
void client_get_clip(Client *c, struct wlr_box *clip) {
    (void)c; stub_get_clip_calls++; *clip = stub_clip;
}
int stub_get_geometry_calls = 0;
struct wlr_box stub_geometry = {0, 0, 100, 80};
void client_get_geometry(Client *c, struct wlr_box *geom) {
    (void)c; stub_get_geometry_calls++; *geom = stub_geometry;
}
int stub_is_x11 = 0;
int32_t client_is_x11(Client *c) { (void)c; return stub_is_x11; }
int stub_xwayland_clip_calls = 0;
struct wlr_box stub_xwayland_clip;
void client_update_xwayland_clip(Client *c, struct wlr_box *clip) {
    (void)c; stub_xwayland_clip_calls++; stub_xwayland_clip = *clip;
}
int stub_xwayland_dest_calls = 0;
void client_update_xwayland_dest_size(Client *c) { (void)c; stub_xwayland_dest_calls++; }
int stub_unmanaged = 0;
int32_t client_is_unmanaged(Client *c) { (void)c; return stub_unmanaged; }
int stub_border_color_calls = 0;
float stub_border_color[4];
void client_set_border_color(Client *c, const float color[4]) {
    (void)c; stub_border_color_calls++;
    memcpy(stub_border_color, color, sizeof(stub_border_color));
}
int stub_finish_geometry_calls = 0;
void client_apply_finish_geometry(Client *c) { (void)c; stub_finish_geometry_calls++; }
int stub_overview_layout_calls = 0;
void overview_layout_card(Client *c) { (void)c; stub_overview_layout_calls++; }
int stub_overview_destroy_calls = 0;
void overview_destroy_card(Client *c) { (void)c; stub_overview_destroy_calls++; }
int stub_tabbar_calls = 0;
void client_draw_tabbar(Client *c, struct ivec2 offsets) {
    (void)c; (void)offsets; stub_tabbar_calls++;
}

Client *stub_pointer_client = NULL;
double stub_node_sx = 1, stub_node_sy = 2;
int stub_node_at_point_calls = 0;
void node_at_point(double x, double y, struct wlr_surface **psurface, Client **pc,
                   LayerSurface **pl, AcwmBarDecoration **bar, double *nx, double *ny) {
    (void)x; (void)y; (void)psurface; (void)pl; (void)bar;
    stub_node_at_point_calls++;
    if (pc) *pc = stub_pointer_client;
    if (nx) *nx = stub_node_sx;
    if (ny) *ny = stub_node_sy;
}
int stub_opacity_calls = 0;
double stub_opacity = 0;
void scene_buffer_apply_opacity(struct wlr_scene_buffer *buffer, int32_t sx, int32_t sy, void *data) {
    (void)buffer; (void)sx; (void)sy;
    stub_opacity_calls++;
    if (data) stub_opacity = *(double *)data;
}
double stub_curve = -1;
double find_animation_curve_at(double t, int32_t type) {
    (void)type;
    if (stub_curve >= 0) return stub_curve;
    return t >= 1.0 ? 1.0 : (t < 0.0 ? 0.0 : t);
}
uint32_t stub_now_ms = 0;
int stub_clock_calls = 0;
int clock_gettime(clockid_t clk, struct timespec *ts) {
    (void)clk;
    stub_clock_calls++;
    ts->tv_sec = (time_t)(stub_now_ms / 1000);
    ts->tv_nsec = (long)((stub_now_ms % 1000) * 1000000);
    return 0;
}
uint32_t timespec_to_ms(struct timespec *ts) {
    return (uint32_t)(ts->tv_sec * 1000 + ts->tv_nsec / 1000000);
}
uint32_t stub_get_now_ms = 1000;
uint32_t get_now_in_ms(void) { return stub_get_now_ms; }
int stub_fresh_monitors_calls = 0;
void request_fresh_all_monitors(void) { stub_fresh_monitors_calls++; }
void *ecalloc(size_t nmemb, size_t size) { return calloc(nmemb, size); }

int stub_surface_clip_calls = 0;
struct wlr_box stub_surface_clip;
void wlr_scene_subsurface_tree_set_clip(struct wlr_scene_node *node, const struct wlr_box *clip) {
    (void)node; stub_surface_clip_calls++; stub_surface_clip = *clip;
}
int stub_tree_destroy_calls = 0;
void wlr_scene_node_destroy(struct wlr_scene_node *node) { (void)node; stub_tree_destroy_calls++; }
int stub_snapshot_calls = 0;
struct wlr_scene_tree *stub_snapshot_tree = NULL;
struct wlr_scene_tree *wlr_scene_tree_snapshot(struct wlr_scene_node *node, struct wlr_scene_tree *parent) {
    (void)node; (void)parent; stub_snapshot_calls++;
    return stub_snapshot_tree;
}
int stub_pointer_enter_calls = 0;
void wlr_seat_pointer_notify_enter(struct wlr_seat *seat, struct wlr_surface *surface, double sx, double sy) {
    (void)seat; (void)surface; (void)sx; (void)sy;
    stub_pointer_enter_calls++;
}
