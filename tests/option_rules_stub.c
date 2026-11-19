/* Test-only stubs for the option_rules.zig tests (tag_rule/layer_rule).
 *
 * trim_whitespace and animation_type_from_string are value_parse twins in
 * the compositor link (tested there); these stand-ins trim spaces and
 * return a controllable animation type. acwm_error_impl is variadic and
 * cannot be defined in Zig, so it records the last message. */
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

char stub_last_error[1024] = {0};
int stub_error_count = 0;
int32_t stub_anim_type_return = 0;
char stub_anim_type_value[128] = {0};

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

int32_t animation_type_from_string(const char *value) {
	if (value)
		snprintf(stub_anim_type_value, sizeof(stub_anim_type_value), "%s",
				 value);
	return stub_anim_type_return;
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
