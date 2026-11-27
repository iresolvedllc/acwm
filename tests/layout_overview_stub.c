/* Test-only stubs for src/layout/overview.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"

#include <stddef.h>
#include <string.h>

Config config = {0};
struct AcwmServer server = {0};
const char default_jump_labels[] = "HJKLASDFGQWERTYUIOPZXCVBNM";

int stub_resize_calls = 0;
Client *stub_resize_client[16];
struct wlr_box stub_resize_box[16];
void client_tile_resize(Client *c, struct wlr_box geo, int32_t interact,
                        const LayoutContext *ctx) {
    (void)interact;
    (void)ctx;
    if (stub_resize_calls < 16) {
        stub_resize_client[stub_resize_calls] = c;
        stub_resize_box[stub_resize_calls] = geo;
    }
    stub_resize_calls++;
}

int32_t client_is_x11_popup(Client *c) { (void)c; return 0; }

int stub_keycode_calls = 0;
char stub_keycode_char[16];
MultiKeycode stub_keycode_value[16];
int32_t find_keycodes_for_char(char c_char, MultiKeycode *multi_kc) {
    if (stub_keycode_calls < 16) {
        stub_keycode_char[stub_keycode_calls] = c_char;
        stub_keycode_value[stub_keycode_calls] = *multi_kc;
    }
    stub_keycode_calls++;
    return 1;
}

int stub_label_update_calls = 0;
char stub_label_text[16][4];
float stub_label_scale[16];
void acwm_jump_label_node_update(AcwmJumpLabel *node, const char *text, float scale) {
    (void)node;
    if (stub_label_update_calls < 16) {
        strncpy(stub_label_text[stub_label_update_calls], text, 3);
        stub_label_text[stub_label_update_calls][3] = '\0';
        stub_label_scale[stub_label_update_calls] = scale;
    }
    stub_label_update_calls++;
}

int stub_overview_label_calls = 0;
Client *stub_overview_label_client[16];
void overview_update_jump_label(Client *c) {
    if (stub_overview_label_calls < 16)
        stub_overview_label_client[stub_overview_label_calls] = c;
    stub_overview_label_calls++;
}

void wlr_scene_node_set_enabled(struct wlr_scene_node *node, bool enabled) {
    node->enabled = enabled;
}
