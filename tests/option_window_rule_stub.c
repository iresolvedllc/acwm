/* Test-only stubs for the option_window_rule.zig tests.
 *
 * trim_whitespace, animation_type_from_string and parse_tag_mask are
 * value_parse twins; parse_mod/parse_key live in binding_parse.c. All are
 * stubbed here with controllable returns. acwm_error_impl is variadic and
 * cannot be defined in Zig, so it records the last message. */
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

/* Config-compatible KeySymCode shape (xkb_keysym_t, keycode union, type,
 * unresolved). Only type/keysym are consumed by the port. */
typedef struct {
	uint32_t keycode1;
	uint32_t keycode2;
	uint32_t keycode3;
} StubMultiKeycode;

typedef struct {
	uint32_t keysym;
	StubMultiKeycode keycode;
	int32_t type;
	bool unresolved;
} StubKeySymCode;

char stub_last_error[1024] = {0};
int stub_error_count = 0;
int32_t stub_anim_type_return = 0;
uint32_t stub_tag_mask_return = 0;
char stub_tag_mask_input[128] = {0};
uint32_t stub_mod_return = 0;
char stub_mod_input[128] = {0};
int32_t stub_key_type = 1; /* KEY_TYPE_SYM */
uint32_t stub_key_keysym = 'a';
char stub_key_input[128] = {0};

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
	(void)value;
	return stub_anim_type_return;
}

uint32_t parse_tag_mask(char *str) {
	if (str)
		snprintf(stub_tag_mask_input, sizeof(stub_tag_mask_input), "%s", str);
	return stub_tag_mask_return;
}

uint32_t parse_mod(const char *mod_str) {
	if (mod_str)
		snprintf(stub_mod_input, sizeof(stub_mod_input), "%s", mod_str);
	return stub_mod_return;
}

StubKeySymCode parse_key(const char *key_str, bool isbindsym) {
	(void)isbindsym;
	if (key_str)
		snprintf(stub_key_input, sizeof(stub_key_input), "%s", key_str);
	StubKeySymCode code = {0};
	code.type = stub_key_type;
	code.keysym = stub_key_keysym;
	return code;
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
