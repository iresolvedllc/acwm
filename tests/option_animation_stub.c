/* Test-only stubs for the option_animation.zig tests.
 *
 * animation_type_from_string and parse_double_array live in the value_parse
 * port in the compositor link; here they are controllable stand-ins (the
 * real implementations are tested by value_parse). acwm_error_impl is
 * variadic and cannot be defined in Zig, so it records the last message. */
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

int32_t stub_anim_type_return = 0;
char stub_anim_type_value[128] = {0};

int32_t stub_double_array_return = 4;
int stub_double_array_calls = 0;
char stub_double_array_input[128] = {0};

char stub_last_error[512] = {0};
int stub_error_count = 0;

int32_t animation_type_from_string(const char *value) {
	if (value)
		snprintf(stub_anim_type_value, sizeof(stub_anim_type_value), "%s",
				 value);
	return stub_anim_type_return;
}

int32_t parse_double_array(const char *input, double *output,
						   int32_t max_count) {
	stub_double_array_calls++;
	if (input)
		snprintf(stub_double_array_input, sizeof(stub_double_array_input),
				 "%s", input);
	static const double values[4] = {0.1, 0.2, 0.3, 0.4};
	int32_t n = stub_double_array_return;
	if (n > max_count)
		n = max_count;
	for (int32_t i = 0; i < n; i++)
		output[i] = values[i];
	return n;
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
