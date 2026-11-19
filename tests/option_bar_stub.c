/* Test-only stubs for the option_bar.zig tests.
 *
 * The ported bar-group applier calls parse_color/convert_hex_to_rgba (their
 * real implementations live in the value_parse port and are tested there) and
 * the variadic logging functions, which cannot be defined in Zig. This file
 * provides controllable stand-ins plus recorders the tests can inspect. */
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

/* Controllable parse_color return; 0x11223344 is a valid sentinel default. */
int64_t stub_parse_color = 0x11223344;

/* Recorder for convert_hex_to_rgba. */
uint32_t stub_converted_hex = 0;
int stub_convert_calls = 0;

/* Recorder for the last acwm_error_impl message. */
char stub_last_error[512];
int stub_error_count = 0;

int64_t parse_color(const char *hex_str) {
	(void)hex_str;
	return stub_parse_color;
}

void convert_hex_to_rgba(float *color, uint32_t hex) {
	stub_converted_hex = hex;
	stub_convert_calls++;
	/* deterministic fill so tests can observe the destination write */
	color[0] = 0.25f;
	color[1] = 0.5f;
	color[2] = 0.75f;
	color[3] = 1.0f;
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
