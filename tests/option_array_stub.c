/* Test-only stubs for the option_array.zig tests.
 *
 * sanitize_string lives in the value_parse port in the compositor link
 * (tested there); this stand-in trims surrounding spaces so the tests can
 * observe that circle_layout routes tokens through it. acwm_error_impl is
 * variadic and cannot be defined in Zig, so it records the last message.
 * strtok/sscanf/strdup/free come from libc for real. */
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>

char stub_last_error[1024] = {0};
int stub_error_count = 0;
int stub_sanitize_calls = 0;

char *sanitize_string(char *str) {
	stub_sanitize_calls++;
	if (!str)
		return str;
	while (*str == ' ')
		str++;
	char *end = str;
	while (*end)
		end++;
	while (end > str && end[-1] == ' ')
		end--;
	*end = '\0';
	return str;
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
