/* Test-only stubs for util.zig. */
#include <stdarg.h>
#include <stdbool.h>
#include <stdlib.h>

int stub_error_calls = 0;

void die(const char *fmt, ...) {
	(void)fmt;
	abort();
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
