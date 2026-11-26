/* Test-only stubs for manage/idle.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"

Config config = {0};
struct AcwmServer server = {0};

int stub_notify_calls = 0;
int stub_timer_calls = 0;
int stub_timer_delay = -1;
int stub_spawn_calls = 0;
char stub_spawn_cmd[256];

void wlr_idle_notifier_v1_notify_activity(struct wlr_idle_notifier_v1 *notifier,
										  struct wlr_seat *seat) {
	(void)notifier;
	(void)seat;
	stub_notify_calls++;
}
int wl_event_source_timer_update(struct wl_event_source *source, int ms_delay) {
	(void)source;
	stub_timer_calls++;
	stub_timer_delay = ms_delay;
	return 0;
}
int32_t spawn_shell(const Arg *arg) {
	stub_spawn_calls++;
	snprintf(stub_spawn_cmd, sizeof(stub_spawn_cmd), "%s",
			 arg->v ? (char *)arg->v : "");
	return 0;
}
