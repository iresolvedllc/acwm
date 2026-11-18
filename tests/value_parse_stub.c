/* Test-only stubs for the value_parse.zig tests.
 *
 * The ported code calls variadic C logging functions (acwm_error_impl /
 * acwm_error_untagged), which cannot be defined in Zig, and the tagmask
 * accessor. The unit tests link this file to stand in for the real
 * definitions that live in the compositor. */
#include <stdbool.h>
#include <stdint.h>

unsigned acwm_test_tagmask = 0;

void acwm_error_impl(bool log, unsigned verbosity, const char *file, int line,
					 const char *fmt, ...) {
	(void)log;
	(void)verbosity;
	(void)file;
	(void)line;
	(void)fmt;
}

void acwm_error_untagged(unsigned verbosity, const char *fmt, ...) {
	(void)verbosity;
	(void)fmt;
}

unsigned acwm_current_tagmask(void) {
	return acwm_test_tagmask;
}
