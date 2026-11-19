/* Test-only stubs for the option_directives.zig tests.
 *
 * is_valid_var_name/set_config_var (variable_expand twin) and
 * parse_config_file (load.c) are stubbed with controllable/recording
 * behavior; trim_whitespace trims spaces. acwm_error_impl is variadic and
 * cannot be defined in Zig, so it records the last message. */
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>

char stub_last_error[1024] = {0};
int stub_error_count = 0;

bool stub_var_name_valid = true;
char stub_var_name[128] = {0};
char stub_var_value[128] = {0};
int stub_var_calls = 0;

char stub_config_path[256] = {0};
int stub_config_must_exist = -1;
int stub_config_calls = 0;

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

bool is_valid_var_name(const char *name) {
	(void)name;
	return stub_var_name_valid;
}

void set_config_var(const char *name, const char *value) {
	stub_var_calls++;
	if (name)
		snprintf(stub_var_name, sizeof(stub_var_name), "%s", name);
	if (value)
		snprintf(stub_var_value, sizeof(stub_var_value), "%s", value);
}

bool parse_config_file(void *config, const char *file_path, bool must_exist) {
	(void)config;
	stub_config_calls++;
	stub_config_must_exist = must_exist ? 1 : 0;
	if (file_path)
		snprintf(stub_config_path, sizeof(stub_config_path), "%s", file_path);
	return true;
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
