/* Test-only stubs for animation/common.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"

Config config = {0};
struct AcwmServer server = {0};

int stub_frame_calls = 0;

void wlr_output_schedule_frame(struct wlr_output *output) {
	(void)output;
	stub_frame_calls++;
}
