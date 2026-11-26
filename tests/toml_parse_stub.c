/* Test-only stubs for toml_parse.zig. Records parser callbacks. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/config/internal.h"

#include <stdbool.h>
#include <string.h>
#include <stdlib.h>

int stub_apply_calls = 0;
char stub_apply_keys[64][256];
char stub_apply_values[64][4096];
int stub_apply_lines[64];

int stub_parse_calls = 0;
char stub_parse_names[16][256];
char stub_parse_pairs[16][8192];
int stub_parse_lines[16];

int stub_report_calls = 0;
int stub_error_calls = 0;
int stub_expand_calls = 0;
char stub_expand_value[256];
char stub_fail_key[256];
int stub_fail_rule = 0;

bool apply_option_expanded(Config *config, char *key, char *value,
						   int line_number) {
	(void)config;
	int i = stub_apply_calls;
	if (i < 64) {
		snprintf(stub_apply_keys[i], sizeof(stub_apply_keys[i]), "%s", key);
		snprintf(stub_apply_values[i], sizeof(stub_apply_values[i]), "%s",
				 value);
		stub_apply_lines[i] = line_number;
	}
	stub_apply_calls++;
	if (stub_fail_key[0] && strcmp(stub_fail_key, key) == 0)
		return false;
	return true;
}

bool parse_option(Config *config, char *key, char *value, int line_number) {
	(void)config;
	int i = stub_parse_calls;
	if (i < 16) {
		snprintf(stub_parse_names[i], sizeof(stub_parse_names[i]), "%s", key);
		snprintf(stub_parse_pairs[i], sizeof(stub_parse_pairs[i]), "%s",
				 value);
		stub_parse_lines[i] = line_number;
	}
	stub_parse_calls++;
	return stub_fail_rule == 0;
}

char *expand_config_variables(const char *value) {
	(void)value;
	stub_expand_calls++;
	if (stub_expand_value[0])
		return strdup(stub_expand_value);
	return NULL;
}

void report_config_line_error(const char *full_path, int line_number,
							  const char *line) {
	(void)full_path;
	(void)line_number;
	(void)line;
	stub_report_calls++;
}

void acwm_error_impl(bool log, unsigned verbosity, const char *file, int line,
					 const char *fmt, ...) {
	(void)log;
	(void)verbosity;
	(void)file;
	(void)line;
	(void)fmt;
	stub_error_calls++;
}
