/* Test-only stubs for manage/tab.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/draw/text-node.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"

Config config = {0};
struct AcwmServer server = {0};

struct wlr_scene_tree stub_bar_scenes[8];
AcwmBarDecoration stub_bars[8];
int stub_bar_next = 0;

int stub_visibility_calls = 0;
int stub_focus_calls = 0;
uint32_t stub_layer = 2;
int stub_arrange_calls = 0;
bool stub_group_bar = false;
int stub_reparent_calls = 0;
int stub_place_above_calls = 0;
int stub_raise_calls = 0;
int stub_lower_calls = 0;
int stub_enable_calls = 0;
int stub_enable_enabled = 0;
int stub_position_calls = 0;
int stub_ignore_hits = 0;
bool stub_last_ignore = false;
int stub_bar_update_calls = 0;
char stub_bar_title[128];
float stub_bar_scale = 0;
int stub_bar_apply_calls = 0;
int stub_bar_size_calls = 0;
int32_t stub_bar_w = 0, stub_bar_h = 0;
int stub_bar_focus_calls = 0;
bool stub_bar_focus = false;
int stub_bar_destroy_calls = 0;
int stub_draw_calls = 0;

Client *client_chain_head(Client *c, size_t prev_off) {
	while (*(Client **)((char *)c + prev_off))
		c = *(Client **)((char *)c + prev_off);
	return c;
}
void client_chain_unlink(Client *c, size_t prev_off, size_t next_off) {
	Client **prev = (Client **)((char *)c + prev_off);
	Client **next = (Client **)((char *)c + next_off);
	if (*prev)
		*(Client **)((char *)*prev + next_off) = *next;
	if (*next)
		*(Client **)((char *)*next + prev_off) = *prev;
	*prev = NULL;
	*next = NULL;
}
void client_update_visibility(Client *c) {
	(void)c;
	stub_visibility_calls++;
}
uint32_t client_target_layer(Client *c) {
	(void)c;
	return stub_layer;
}
void client_focus(Client *c, int32_t lift) {
	(void)c;
	(void)lift;
	stub_focus_calls++;
}
bool client_wants_group_bar(Client *c) {
	(void)c;
	return stub_group_bar;
}
const char *client_get_title(Client *c) {
	(void)c;
	return "title";
}
void arrange(Monitor *m, bool want_animation, bool from_view) {
	(void)m;
	(void)want_animation;
	(void)from_view;
	stub_arrange_calls++;
}
uint32_t get_mon_curtag(const Monitor *m) {
	(void)m;
	return 0;
}
void acwm_scene_node_set_ignore_hit(struct wlr_scene_node *node, bool ignore) {
	(void)node;
	stub_ignore_hits++;
	stub_last_ignore = ignore;
}
AcwmBarDecoration *acwm_bar_decoration_create(void *cdata, uint32_t type,
											  bool is_tab,
											  struct wlr_scene_tree *parent,
											  DecorateDrawData data,
											  int32_t width, int32_t height) {
	(void)cdata;
	(void)type;
	(void)is_tab;
	(void)parent;
	(void)data;
	(void)width;
	(void)height;
	if (stub_bar_next >= 8)
		return NULL;
	AcwmBarDecoration *bar = &stub_bars[stub_bar_next];
	memset(bar, 0, sizeof(*bar));
	bar->scene = &stub_bar_scenes[stub_bar_next];
	stub_bar_next++;
	return bar;
}
void acwm_bar_decoration_destroy(AcwmBarDecoration *node) {
	(void)node;
	stub_bar_destroy_calls++;
}
void acwm_bar_decoration_update(AcwmBarDecoration *node, const char *text,
								float scale) {
	(void)node;
	stub_bar_update_calls++;
	snprintf(stub_bar_title, sizeof(stub_bar_title), "%s", text ? text : "");
	stub_bar_scale = scale;
}
void acwm_bar_decoration_apply_config(AcwmBarDecoration *node,
									  const DecorateDrawData *data) {
	(void)node;
	(void)data;
	stub_bar_apply_calls++;
}
void acwm_bar_decoration_set_size(AcwmBarDecoration *node, int32_t width,
								  int32_t height) {
	(void)node;
	stub_bar_size_calls++;
	stub_bar_w = width;
	stub_bar_h = height;
}
void acwm_bar_decoration_set_focus(AcwmBarDecoration *node, bool focused) {
	(void)node;
	stub_bar_focus_calls++;
	stub_bar_focus = focused;
}

void wlr_scene_node_set_enabled(struct wlr_scene_node *node, bool enabled) {
	node->enabled = enabled;
	stub_enable_calls++;
	stub_enable_enabled = enabled ? 1 : 0;
}
void wlr_scene_node_reparent(struct wlr_scene_node *node,
							 struct wlr_scene_tree *parent) {
	node->parent = parent;
	stub_reparent_calls++;
}
void wlr_scene_node_place_above(struct wlr_scene_node *node,
								struct wlr_scene_node *sibling) {
	(void)node;
	(void)sibling;
	stub_place_above_calls++;
}
void wlr_scene_node_raise_to_top(struct wlr_scene_node *node) {
	(void)node;
	stub_raise_calls++;
}
void wlr_scene_node_lower_to_bottom(struct wlr_scene_node *node) {
	(void)node;
	stub_lower_calls++;
}
void wlr_scene_node_set_position(struct wlr_scene_node *node, int32_t x,
								 int32_t y) {
	node->x = x;
	node->y = y;
	stub_position_calls++;
	stub_draw_calls++;
}
