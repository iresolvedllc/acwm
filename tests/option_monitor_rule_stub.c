/* Test-only stubs for the option_monitor_rule.zig tests.
 *
 * trim_whitespace is the value_parse twin in the compositor link (tested
 * there); this stand-in trims the same character class for space-padded
 * test inputs and counts calls. acwm_error_impl is variadic and cannot be
 * defined in Zig, so it records the last message. */
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>

char stub_last_error[1024] = {0};
int stub_error_count = 0;
int stub_trim_calls = 0;

static int is_space(char ch) {
	return ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';
}

void trim_whitespace(char *str) {
	stub_trim_calls++;
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
