/* Test-only stubs for the cleanup.zig tests: server global and the
 * keymap teardown. The module itself owns nothing else externally. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"

Config config = {0};
struct AcwmServer server = {0};

int stub_cleanup_keymap_calls = 0;

void cleanup_config_keymap(void) {
	stub_cleanup_keymap_calls++;
}
