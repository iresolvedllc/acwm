/* Test-only stubs for the option_defaults.zig tests.
 *
 * Provides the global `Config config` (defined in option_defs.c in the
 * compositor), a controllable parse_option and expand_config_variables.
 * No logging is involved in this module. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

Config config = {0};
struct AcwmServer server = {0};

char stub_parse_key[128] = {0};
char stub_parse_value[256] = {0};
int stub_parse_calls = 0;
int stub_parse_ok = 1;

/* When NULL, expand_config_variables returns NULL (original value is used). */
char stub_expansion[256] = {0};
int stub_expansion_enabled = 0;

bool parse_option(Config *cfg, char *key, char *value, int line_number) {
	(void)cfg;
	(void)line_number;
	stub_parse_calls++;
	if (key)
		snprintf(stub_parse_key, sizeof(stub_parse_key), "%s", key);
	if (value)
		snprintf(stub_parse_value, sizeof(stub_parse_value), "%s", value);
	return stub_parse_ok != 0;
}

char *expand_config_variables(const char *value) {
	if (!stub_expansion_enabled)
		return NULL;
	(void)value;
	return strdup(stub_expansion);
}
