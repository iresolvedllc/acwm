/* Test-only stubs for the variable_expand.zig tests.
 *
 * Defines the global `Config config` the ported code reads/writes (the real
 * definition lives in the compositor). Zero-initialized; tests drive it via
 * set_config_var(). No variadic log stubs needed — variable_expand.zig does
 * not log. */
#define WLR_USE_UNSTABLE 1
#include "acwm/config/internal.h"

Config config = {0};
