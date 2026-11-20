/* Test-only stubs for the load.zig tests.
 *
 * Provides the server global, xkb fallbacks and controllable stand-ins for
 * everything load.c calls: the config parser hook, the lifecycle functions,
 * conflict checks, the error store/nag, TOML parsing, the xkb keymap
 * functions and the change_vt dispatch handler. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/config/preset.h"

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

struct AcwmServer server = {0};
const struct xkb_rule_names xkb_fallback_rules = {0};

char stub_last_error[1024] = {0};
int stub_error_count = 0;

int stub_free_config_calls = 0;
int stub_set_default_calls = 0;
int stub_override_calls = 0;
int stub_create_keymap_calls = 0;
int stub_store_begin_calls = 0;
int stub_store_end_calls = 0;
int stub_nag_update_calls = 0;
int stub_conflict_calls = 0;
int stub_conflict_result = 0;
int stub_toml_calls = 0;
int stub_toml_result = 1;

char stub_apply_key[128] = {0};
char stub_apply_value[256] = {0};
int stub_apply_calls = 0;
int stub_apply_result = 1;

char stub_report_path[256] = {0};
int stub_report_line = 0;
char stub_report_text[256] = {0};
int stub_report_calls = 0;

int stub_find_count = 0;
uint32_t stub_find_keycode = 7;

struct xkb_keymap *stub_keymap_new = (struct xkb_keymap *)0x1;
int stub_keymap_unref_calls = 0;
char stub_keysym_name[64] = "key";

static int is_space(char ch) {
	return ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';
}

void trim_whitespace(char *str) {
	if (!str)
		return;
	char *start = str;
	while (*start && is_space(*start))
		start++;
	if (start != str) {
		char *d = str;
		while (*start)
			*d++ = *start++;
		*d = '\0';
	}
	char *end = str;
	while (*end)
		end++;
	while (end > str && is_space(end[-1]))
		end--;
	*end = '\0';
}

void strip_quotes(char *str) {
	if (!str)
		return;
	size_t len = strlen(str);
	if (len >= 2 && (str[0] == '"' || str[0] == '\'') && str[len - 1] == str[0]) {
		memmove(str, str + 1, len - 2);
		str[len - 2] = '\0';
	}
}

void remove_comment(char *str) {
	if (!str)
		return;
	char *p = str;
	while (*p) {
		if (*p == '#') {
			*p = '\0';
			return;
		}
		p++;
	}
}

void report_config_line_error(const char *full_path, int line_number,
							  const char *line) {
	stub_report_calls++;
	if (full_path)
		snprintf(stub_report_path, sizeof(stub_report_path), "%s", full_path);
	stub_report_line = line_number;
	if (line)
		snprintf(stub_report_text, sizeof(stub_report_text), "%s", line);
}

bool apply_option_expanded(void *config, char *key, char *value,
						   int line_number) {
	(void)config;
	(void)line_number;
	stub_apply_calls++;
	if (key)
		snprintf(stub_apply_key, sizeof(stub_apply_key), "%s", key);
	if (value)
		snprintf(stub_apply_value, sizeof(stub_apply_value), "%s", value);
	return stub_apply_result != 0;
}

void free_config(void) { stub_free_config_calls++; }
void set_value_default(void) { stub_set_default_calls++; }
void override_config(void) { stub_override_calls++; }
void create_config_keymap(void) { stub_create_keymap_calls++; }

int32_t find_keycodes_for_keysym(struct xkb_keymap *keymap, xkb_keysym_t sym,
								 MultiKeycode *multi_kc) {
	(void)keymap;
	(void)sym;
	if (stub_find_count > 0) {
		multi_kc->keycode1 = stub_find_keycode;
		multi_kc->keycode2 = 0;
		multi_kc->keycode3 = 0;
	}
	return stub_find_count;
}

bool parse_toml_stream(void *config, FILE *file, const char *full_path) {
	(void)config;
	(void)file;
	(void)full_path;
	stub_toml_calls++;
	return stub_toml_result != 0;
}

bool check_key_binding_conflicts(Config *config) {
	(void)config;
	stub_conflict_calls++;
	return stub_conflict_result != 0;
}
bool check_mouse_binding_conflicts(Config *config) {
	(void)config;
	stub_conflict_calls++;
	return 0;
}
bool check_axis_binding_conflicts(Config *config) {
	(void)config;
	stub_conflict_calls++;
	return 0;
}
bool check_switch_binding_conflicts(Config *config) {
	(void)config;
	stub_conflict_calls++;
	return 0;
}
bool check_gesture_binding_conflicts(Config *config) {
	(void)config;
	stub_conflict_calls++;
	return 0;
}

void config_error_store_begin(void) { stub_store_begin_calls++; }
void config_error_store_end(void) { stub_store_end_calls++; }
void config_error_nag_update(void) { stub_nag_update_calls++; }

struct xkb_keymap *xkb_keymap_new_from_names(struct xkb_context *context,
											 const struct xkb_rule_names *names,
											 enum xkb_keymap_compile_flags flags) {
	(void)context;
	(void)names;
	(void)flags;
	return stub_keymap_new;
}

void xkb_keymap_unref(struct xkb_keymap *keymap) {
	(void)keymap;
	stub_keymap_unref_calls++;
}

int xkb_keysym_get_name(xkb_keysym_t keysym, char *buffer, size_t size) {
	(void)keysym;
	if (buffer && size > 0)
		snprintf(buffer, size, "%s", stub_keysym_name);
	return 0;
}

int32_t change_vt(const Arg *arg) {
	(void)arg;
	return 0;
}

void acwm_error_impl(bool log, unsigned verbosity, const char *file, int line,
					 const char *fmt, ...) {
	(void)log;
	(void)verbosity;
	(void)file;
	(void)line;
	va_list args;
	va_start(args, fmt);
	vsnprintf(stub_last_error, sizeof(stub_last_error), fmt, args);
	va_end(args);
	stub_error_count++;
}

void acwm_error_untagged(unsigned verbosity, const char *fmt, ...) {
	(void)verbosity;
	(void)fmt;
}
