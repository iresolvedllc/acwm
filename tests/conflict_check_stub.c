/* Test-only stubs for the conflict_check.zig tests.
 *
 * The ported code calls the variadic logging function and
 * config_file_path_at (which lives in load.c in the compositor). This file
 * provides a recorder and a controllable path table. */
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>

/* Recorder for the last acwm_error_impl message. */
char stub_last_error[1024];
int stub_error_count = 0;

/* Controllable config file path table (index -> path). */
const char *stub_file_paths[4] = {0};
int stub_file_paths_count = 0;

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

const char *config_file_path_at(int index) {
	if (index < 0 || index >= stub_file_paths_count)
		return 0;
	return stub_file_paths[index];
}
