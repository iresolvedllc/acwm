/* Test-only stubs for manage/monitor_output.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/ext-protocol/tearing.h"
#include "acwm/manage/monitor.h"
#include <string.h>
#include <wlr/types/wlr_output.h>
#include <wlr/types/wlr_scene.h>

Config config = {0};
struct AcwmServer server = {0};

bool stub_tearing = false;
int stub_tearing_calls = 0;
bool check_tearing_frame_allow(Monitor *m) {
	(void)m;
	stub_tearing_calls++;
	return stub_tearing;
}

int32_t regex_match(const char *pattern_mb, const char *str_mb) {
	if (!pattern_mb || !str_mb)
		return 0;
	return strcmp(pattern_mb, str_mb) == 0 ? 1 : 0;
}

bool stub_needs_frame = false;
int stub_needs_frame_calls = 0;
bool wlr_scene_output_needs_frame(struct wlr_scene_output *scene_output) {
	(void)scene_output;
	stub_needs_frame_calls++;
	return stub_needs_frame;
}

bool stub_build_ok = true;
int stub_build_calls = 0;
struct wlr_color_transform *stub_opts_color_transform = NULL;
bool wlr_scene_output_build_state(struct wlr_scene_output *scene_output,
								  struct wlr_output_state *state,
								  const struct wlr_scene_output_state_options *options) {
	(void)scene_output;
	(void)state;
	stub_build_calls++;
	stub_opts_color_transform = options ? options->color_transform : NULL;
	return stub_build_ok;
}

bool stub_test_ok = true;
int stub_test_calls = 0;
bool wlr_output_test_state(struct wlr_output *output,
						   const struct wlr_output_state *state) {
	(void)output;
	(void)state;
	stub_test_calls++;
	return stub_test_ok;
}

bool stub_commit_results[4] = { true, true, true, true };
int stub_commit_index = 0;
int stub_commit_calls = 0;
bool stub_last_tearing_flip = false;
bool wlr_output_commit_state(struct wlr_output *output,
							 const struct wlr_output_state *state) {
	(void)output;
	stub_commit_calls++;
	stub_last_tearing_flip = state->tearing_page_flip;
	if (stub_commit_index >= 4)
		return true;
	return stub_commit_results[stub_commit_index++];
}

int stub_finish_calls = 0;
int stub_init_calls = 0;
void wlr_output_state_finish(struct wlr_output_state *state) {
	(void)state;
	stub_finish_calls++;
}
void wlr_output_state_init(struct wlr_output_state *state) {
	(void)state;
	stub_init_calls++;
}

int stub_adaptive_calls = 0;
bool stub_adaptive_value = false;
void wlr_output_state_set_adaptive_sync_enabled(struct wlr_output_state *state,
												bool enabled) {
	(void)state;
	stub_adaptive_calls++;
	stub_adaptive_value = enabled;
}
struct wlr_output_mode *stub_set_mode = NULL;
int stub_set_mode_calls = 0;
void wlr_output_state_set_mode(struct wlr_output_state *state,
							   struct wlr_output_mode *mode) {
	(void)state;
	stub_set_mode_calls++;
	stub_set_mode = mode;
}
int stub_custom_mode_calls = 0;
int32_t stub_custom_w = 0, stub_custom_h = 0, stub_custom_refresh = 0;
void wlr_output_state_set_custom_mode(struct wlr_output_state *state,
									  int32_t width, int32_t height,
									  int32_t refresh) {
	(void)state;
	stub_custom_mode_calls++;
	stub_custom_w = width;
	stub_custom_h = height;
	stub_custom_refresh = refresh;
}
int stub_enabled_calls = 0;
bool stub_enabled_value = true;
void wlr_output_state_set_enabled(struct wlr_output_state *state,
								  bool enabled) {
	(void)state;
	stub_enabled_calls++;
	stub_enabled_value = enabled;
}
int stub_scale_calls = 0;
float stub_scale_value = 0;
void wlr_output_state_set_scale(struct wlr_output_state *state, float scale) {
	(void)state;
	stub_scale_calls++;
	stub_scale_value = scale;
}
int stub_transform_calls = 0;
int stub_transform_value = 0;
void wlr_output_state_set_transform(struct wlr_output_state *state,
									enum wl_output_transform transform) {
	(void)state;
	stub_transform_calls++;
	stub_transform_value = (int)transform;
}

bool stub_headless = false;
bool wlr_output_is_headless(struct wlr_output *output) {
	(void)output;
	return stub_headless;
}

int stub_icc_init_calls = 0;
size_t stub_icc_size = 0;
unsigned char stub_icc_data[64];
struct wlr_color_transform *stub_transform_result = NULL;
struct wlr_color_transform *wlr_color_transform_init_linear_to_icc(
	const void *data, size_t size) {
	stub_icc_init_calls++;
	stub_icc_size = size;
	if (size <= sizeof(stub_icc_data))
		memcpy(stub_icc_data, data, size);
	return stub_transform_result;
}
int stub_unref_calls = 0;
void wlr_color_transform_unref(struct wlr_color_transform *tr) {
	(void)tr;
	stub_unref_calls++;
}
