/* Test-only stubs for the reapply.zig tests.
 *
 * Includes the real project headers so all stubbed wlr/acwm signatures are
 * compiler-checked, provides the config/server/layouts data symbols and the
 * controllable hooks used by the pure-logic tests. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/ipc/ipc.h"
#include "acwm/layout/layout.h"
#include <libinput.h>
#include <wlr/types/wlr_output.h>

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

Config config = {0};
struct AcwmServer server = {0};
Layout layouts[14] = {0};

int stub_spawn_calls = 0;
char stub_spawn_arg[256] = {0};
int stub_configure_pointer_calls = 0;
int stub_client_property_calls = 0;
int stub_arrange_calls = 0;
int stub_parse_config_calls = 0;
int stub_reset_option_calls = 0;
int stub_update_seat_calls = 0;
int stub_primary_selection_calls = 0;
int stub_bar_reload_calls = 0;
int stub_printstatus_calls = 0;
int stub_watcher_update_calls = 0;
int stub_idle_rearm_calls = 0;
int stub_sync_workspaces_calls = 0;
int stub_regex_result = 1;
int stub_monitor_matches = 1;
int stub_apply_rule_calls = 0;
int stub_commit_result = 1;
int stub_device_rule_present = 0;
int stub_rule_has_keyboard = 0;
int stub_standalone_created = 0;

int32_t spawn_shell(const Arg *arg) {
	stub_spawn_calls++;
	if (arg && arg->v)
		snprintf(stub_spawn_arg, sizeof(stub_spawn_arg), "%s", arg->v);
	return 0;
}

void client_set_group_config(Client *c) { (void)c; stub_client_property_calls++; }
void client_apply_tab_bar_config(Client *c) { (void)c; }
void configure_pointer(struct wlr_input_device *d, struct libinput_device *dev) {
	(void)d;
	(void)dev;
	stub_configure_pointer_calls++;
}
void init_baked_points(void) {}
void pointer_cursor_activity(void) {}
void reset_keyboard_layout(void) {}
void arrange(Monitor *m, bool want_animation, bool from_view) {
	(void)m;
	(void)want_animation;
	(void)from_view;
	stub_arrange_calls++;
}

bool monitor_matches_rule(Monitor *m, const ConfigMonitorRule *rule) {
	(void)m;
	(void)rule;
	return stub_monitor_matches != 0;
}
bool apply_rule_to_state(Monitor *m, const ConfigMonitorRule *rule,
						 struct wlr_output_state *state) {
	(void)m;
	(void)rule;
	(void)state;
	stub_apply_rule_calls++;
	return true;
}
bool acwm_scene_output_commit(struct wlr_scene_output *so,
							  struct wlr_output_state *state) {
	(void)so;
	(void)state;
	return stub_commit_result != 0;
}
void output_state_setup_hdr(Monitor *m, bool silent,
							struct wlr_output_state *state) {
	(void)m;
	(void)silent;
	(void)state;
}
void output_enable_hdr(Monitor *m, struct wlr_output_state *state, bool enabled,
					   bool force) {
	(void)m;
	(void)state;
	(void)enabled;
	(void)force;
}
void handle_output_layout_change(struct wl_listener *listener, void *data) {
	(void)listener;
	(void)data;
}
ConfigDeviceRule *find_device_rule(struct wlr_input_device *device) {
	(void)device;
	if (!stub_device_rule_present)
		return NULL;
	static ConfigDeviceRule rule;
	return &rule;
}
bool device_rule_has_keyboard_settings(ConfigDeviceRule *rule) {
	(void)rule;
	return stub_rule_has_keyboard != 0;
}
void create_standalone_keyboard(InputDevice *input_dev,
								struct wlr_keyboard *keyboard,
								ConfigDeviceRule *rule) {
	(void)input_dev;
	(void)keyboard;
	(void)rule;
	stub_standalone_created++;
}
void standalone_keyboard_apply_config(KeyboardGroup *group,
									  ConfigDeviceRule *rule) {
	(void)group;
	(void)rule;
}
void handle_standalone_keyboard_destroy(struct wl_listener *listener,
										void *data) {
	(void)listener;
	(void)data;
}
void update_seat_capabilities(void) { stub_update_seat_calls++; }
void apply_primary_selection(void) { stub_primary_selection_calls++; }
void bar_config_reload(void) { stub_bar_reload_calls++; }
void printstatus(enum ipc_watch_type type) {
	(void)type;
	stub_printstatus_calls++;
}
void config_watcher_update(void) { stub_watcher_update_calls++; }
void rearm_idle_check(void) { stub_idle_rearm_calls++; }
int32_t regex_match(const char *pattern_mb, const char *str_mb) {
	(void)pattern_mb;
	(void)str_mb;
	return stub_regex_result;
}
void sync_workspaces_to_tag_num(Monitor *m) {
	(void)m;
	stub_sync_workspaces_calls++;
}
int32_t pointer_hide_cursor(void *data) {
	(void)data;
	return 0;
}
void config_error_nag_update(void) {}

bool parse_config(void) {
	stub_parse_config_calls++;
	return true;
}

/* wlroots/scenefx no-ops */
void wlr_scene_rect_set_color(struct wlr_scene_rect *rect, const float color[4]) {
	(void)rect;
	(void)color;
}
struct wlr_scene_optimized_blur *wlr_scene_optimized_blur_create(
	struct wlr_scene_tree *parent, int width, int height) {
	(void)parent;
	(void)width;
	(void)height;
	static struct wlr_scene_optimized_blur blur;
	return &blur;
}
void wlr_scene_node_destroy(struct wlr_scene_node *node) { (void)node; }
void wlr_scene_node_reparent(struct wlr_scene_node *node,
							 struct wlr_scene_tree *parent) {
	(void)node;
	(void)parent;
}
void wlr_scene_node_set_position(struct wlr_scene_node *node, int x, int y) {
	(void)node;
	(void)x;
	(void)y;
}
void wlr_scene_optimized_blur_set_size(struct wlr_scene_optimized_blur *blur,
									   int width, int height) {
	(void)blur;
	(void)width;
	(void)height;
}
void wlr_scene_set_blur_data(struct wlr_scene *scene, int num_passes,
							 int radius, float noise, float brightness,
							 float contrast, float saturation) {
	(void)scene;
	(void)num_passes;
	(void)radius;
	(void)noise;
	(void)brightness;
	(void)contrast;
	(void)saturation;
}
bool wlr_input_device_is_libinput(struct wlr_input_device *device) {
	(void)device;
	return true;
}
void wlr_output_state_set_enabled(struct wlr_output_state *state, bool enabled) {
	state->enabled = enabled;
}
struct wlr_output_layout_output *wlr_output_layout_add_auto(
	struct wlr_output_layout *layout, struct wlr_output *output) {
	(void)layout;
	(void)output;
	return NULL;
}
struct wlr_output_layout_output *wlr_output_layout_add(
	struct wlr_output_layout *layout, struct wlr_output *output, int x, int y) {
	(void)layout;
	(void)output;
	(void)x;
	(void)y;
	return NULL;
}
void wlr_damage_ring_add_whole(struct wlr_damage_ring *ring) { (void)ring; }
void wlr_output_schedule_frame(struct wlr_output *output) { (void)output; }
void wlr_output_effective_resolution(struct wlr_output *output, int *width,
									 int *height) {
	(void)output;
	if (width)
		*width = 1920;
	if (height)
		*height = 1080;
}
void wlr_cursor_unset_image(struct wlr_cursor *cursor) { (void)cursor; }
void wlr_cursor_set_surface(struct wlr_cursor *cursor,
							struct wlr_surface *surface, int32_t hotspot_x,
							int32_t hotspot_y) {
	(void)cursor;
	(void)surface;
	(void)hotspot_x;
	(void)hotspot_y;
}
void wlr_cursor_set_xcursor(struct wlr_cursor *cursor,
							struct wlr_xcursor_manager *manager, const char *name) {
	(void)cursor;
	(void)manager;
	(void)name;
}
void wlr_xcursor_manager_destroy(struct wlr_xcursor_manager *manager) {
	(void)manager;
}
struct wlr_xcursor_manager *wlr_xcursor_manager_create(const char *name,
													  uint32_t size) {
	(void)name;
	(void)size;
	return NULL;
}
void wlr_xcursor_manager_load(struct wlr_xcursor_manager *manager, float scale) {
	(void)manager;
	(void)scale;
}
struct wl_event_source *wl_event_loop_add_timer(struct wl_event_loop *loop,
												wl_event_loop_timer_func_t func,
												void *data) {
	(void)loop;
	(void)func;
	(void)data;
	return NULL;
}
struct wl_event_loop *wl_display_get_event_loop(struct wl_display *display) {
	(void)display;
	return NULL;
}
int wl_event_source_timer_update(struct wl_event_source *source, int ms) {
	(void)source;
	(void)ms;
	return 0;
}
int wl_event_source_remove(struct wl_event_source *source) {
	(void)source;
	return 0;
}
void wlr_keyboard_set_repeat_info(struct wlr_keyboard *kb, int32_t rate,
								  int32_t delay) {
	(void)kb;
	(void)rate;
	(void)delay;
}
bool wlr_keyboard_set_keymap(struct wlr_keyboard *kb,
							 struct xkb_keymap *keymap) {
	(void)kb;
	(void)keymap;
	return true;
}
void wlr_keyboard_notify_modifiers(struct wlr_keyboard *keyboard,
								   uint32_t mods_depressed,
								   uint32_t mods_latched,
								   uint32_t mods_locked,
								   uint32_t group) {
	(void)keyboard;
	(void)mods_depressed;
	(void)mods_latched;
	(void)mods_locked;
	(void)group;
}
bool wlr_keyboard_group_remove_keyboard(struct wlr_keyboard_group *group,
										struct wlr_keyboard *keyboard) {
	(void)group;
	(void)keyboard;
	return true;
}
bool wlr_keyboard_group_add_keyboard(struct wlr_keyboard_group *group,
									 struct wlr_keyboard *keyboard) {
	(void)group;
	(void)keyboard;
	return true;
}
