/* Test-only stubs for the option_bind.zig tests.
 *
 * Includes the real project headers so the callback signatures and struct
 * layouts match the compositor exactly. binding_parse.c's helpers
 * (parse_bind_flags/parse_key/parse_mod/parse_button/set_binding_keymode/
 * parse_func_name), load.c's config_current_file_index and the
 * value_parse twins are replaced with controllable stand-ins. */
#define WLR_USE_UNSTABLE 1
#include "acwm/config/parse.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

char stub_last_error[1024] = {0};
int stub_error_count = 0;

int stub_bind_calls = 0;
char stub_bind_key[64] = {0};
int stub_bind_sym = 0;

uint32_t stub_mod_return = 64;
uint32_t stub_button_return = 272;
int32_t stub_direction_return = 0;
int32_t stub_fold_return = 1;

int32_t stub_key_type = 1; /* KEY_TYPE_SYM */
uint32_t stub_key_keysym = 'q';
int stub_key_bindsym = -1;
char stub_key_input[64] = {0};

int stub_func_null = 0;
int stub_func_calls = 0;
char stub_func_name[128] = {0};
char stub_arg1[128] = {0};
char stub_arg2[128] = {0};

int stub_file_index = -1;

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

void parse_bind_flags(const char *str, KeyBinding *kb) {
	stub_bind_calls++;
	if (str)
		snprintf(stub_bind_key, sizeof(stub_bind_key), "%s", str);
	if (stub_bind_sym)
		kb->keysymcode.type = KEY_TYPE_SYM;
}

void set_binding_keymode(Config *config, char mode[28], bool *iscommonmode,
						 bool *isdefaultmode) {
	strcpy(mode, config->keymode);
	if (strcmp(mode, "common") == 0) {
		*iscommonmode = true;
		*isdefaultmode = false;
	} else if (strcmp(mode, "default") == 0) {
		*isdefaultmode = true;
		*iscommonmode = false;
	} else {
		*isdefaultmode = false;
		*iscommonmode = false;
	}
}

uint32_t parse_mod(const char *mod_str) {
	(void)mod_str;
	return stub_mod_return;
}

uint32_t parse_button(const char *str) {
	(void)str;
	return stub_button_return;
}

int32_t parse_direction(const char *str) {
	(void)str;
	return stub_direction_return;
}

int32_t parse_fold_state(const char *str) {
	(void)str;
	return stub_fold_return;
}

KeySymCode parse_key(const char *key_str, bool isbindsym) {
	if (key_str)
		snprintf(stub_key_input, sizeof(stub_key_input), "%s", key_str);
	stub_key_bindsym = isbindsym ? 1 : 0;
	KeySymCode code = {0};
	code.type = stub_key_type;
	code.keysym = stub_key_keysym;
	return code;
}

static int32_t dummy_func(const Arg *arg) {
	(void)arg;
	return 0;
}

FuncType parse_func_name(char *func_name, Arg *arg, char *arg_value,
						 char *arg_value2, char *arg_value3, char *arg_value4,
						 char *arg_value5) {
	(void)arg_value3;
	(void)arg_value4;
	(void)arg_value5;
	(void)arg;
	stub_func_calls++;
	if (func_name)
		snprintf(stub_func_name, sizeof(stub_func_name), "%s", func_name);
	if (arg_value)
		snprintf(stub_arg1, sizeof(stub_arg1), "%s", arg_value);
	if (arg_value2)
		snprintf(stub_arg2, sizeof(stub_arg2), "%s", arg_value2);
	if (stub_func_null)
		return NULL;
	return dummy_func;
}

int config_current_file_index(void) {
	return stub_file_index;
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
