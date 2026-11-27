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
void wlr_scene_rect_set_size(struct wlr_scene_rect *rect, int width, int height) {
    (void)rect;
    stub_rect_w = width;
    stub_rect_h = height;
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
