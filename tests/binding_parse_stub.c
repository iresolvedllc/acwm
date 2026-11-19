/* Test-only stubs for the binding_parse.zig tests.
 *
 * Provides the config global, xkb rule fallbacks, controllable libxkbcommon
 * stand-ins (a tiny fake keymap: keycodes 1..stub_max_keycode with one
 * level, matching stub_scan_sym at stub_match_keycode), the value_parse
 * helpers, and no-op dispatch handlers for the 93-entry name table. */
#define WLR_USE_UNSTABLE 1
#include "acwm/config/parse.h"
#include "acwm/config/preset.h"

#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

Config config = {0};
const struct xkb_rule_names xkb_fallback_rules = {0};

char stub_last_error[1024] = {0};
int stub_error_count = 0;

/* xkb stand-ins */
struct xkb_keymap *stub_keymap = (struct xkb_keymap *)0x1;
xkb_keycode_t stub_min_keycode = 1;
xkb_keycode_t stub_max_keycode = 3;
xkb_level_index_t stub_levels = 1;
int stub_match_keycode = 2;
xkb_keysym_t stub_scan_sym = 0x61;
xkb_keysym_t stub_keysym_from_name = 0x61;
xkb_keysym_t stub_utf32_keysym = 0x61;
int stub_unref_calls = 0;

/* value_parse stand-ins */
int32_t stub_direction = 0;
int32_t stub_circle_direction = 0;
int32_t stub_overcircle_direction = 0;
int32_t stub_force = 0;
uint32_t stub_tag_mask = 0;
uint32_t stub_num_type = 0;
int32_t stub_monitor_arg = 0;

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

int32_t parse_direction(const char *str) { (void)str; return stub_direction; }
int32_t parse_circle_direction(const char *str) { (void)str; return stub_circle_direction; }
int32_t parse_overcircle_direction(const char *str) { (void)str; return stub_overcircle_direction; }
int32_t parse_force(const char *str) { (void)str; return stub_force; }
uint32_t parse_tag_mask(char *str) { (void)str; return stub_tag_mask; }
uint32_t parse_num_type(char *str) { (void)str; return stub_num_type; }
int32_t parse_monitor_arg(const char *str) { (void)str; return stub_monitor_arg; }

/* xkb */
struct xkb_context *xkb_context_new(enum xkb_context_flags flags) {
	(void)flags;
	return (struct xkb_context *)0x1;
}

void xkb_context_unref(struct xkb_context *context) { (void)context; }

struct xkb_keymap *xkb_keymap_new_from_names(struct xkb_context *context,
											 const struct xkb_rule_names *names,
											 enum xkb_keymap_compile_flags flags) {
	(void)context;
	(void)names;
	(void)flags;
	return stub_keymap;
}

void xkb_keymap_unref(struct xkb_keymap *keymap) {
	(void)keymap;
	stub_unref_calls++;
}

xkb_keycode_t xkb_keymap_min_keycode(struct xkb_keymap *keymap) {
	(void)keymap;
	return stub_min_keycode;
}

xkb_keycode_t xkb_keymap_max_keycode(struct xkb_keymap *keymap) {
	(void)keymap;
	return stub_max_keycode;
}

xkb_level_index_t xkb_keymap_num_levels_for_key(struct xkb_keymap *keymap,
												xkb_keycode_t key,
												xkb_layout_index_t layout) {
	(void)keymap;
	(void)key;
	(void)layout;
	return stub_levels;
}

int xkb_keymap_key_get_syms_by_level(struct xkb_keymap *keymap,
									 xkb_keycode_t key,
									 xkb_layout_index_t layout,
									 xkb_level_index_t level,
									 const xkb_keysym_t **syms_out) {
	(void)keymap;
	(void)layout;
	(void)level;
	static xkb_keysym_t syms[1];
	syms[0] = (key == (xkb_keycode_t)stub_match_keycode) ? stub_scan_sym : 0;
	*syms_out = syms;
	return 1;
}

xkb_layout_index_t xkb_keymap_num_layouts(struct xkb_keymap *keymap) {
	(void)keymap;
	return 1;
}

xkb_keysym_t xkb_utf32_to_keysym(uint32_t ucs) {
	(void)ucs;
	return stub_utf32_keysym;
}

xkb_keysym_t xkb_keysym_from_name(const char *name,
								  enum xkb_keysym_flags flags) {
	(void)name;
	(void)flags;
	return stub_keysym_from_name;
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

/* dispatch handlers (name table) */
int32_t bind_to_view(const Arg *arg) { (void)arg; return 0; }
int32_t center_window(const Arg *arg) { (void)arg; return 0; }
int32_t change_vt(const Arg *arg) { (void)arg; return 0; }
int32_t combo_view(const Arg *arg) { (void)arg; return 0; }
int32_t create_virtual_output(const Arg *arg) { (void)arg; return 0; }
int32_t destroy_all_virtual_output(const Arg *arg) { (void)arg; return 0; }
int32_t disable_monitor(const Arg *arg) { (void)arg; return 0; }
int32_t dwindle_split_horizontal(const Arg *arg) { (void)arg; return 0; }
int32_t dwindle_split_vertical(const Arg *arg) { (void)arg; return 0; }
int32_t dwindle_toggle_current_split(const Arg *arg) { (void)arg; return 0; }
int32_t dwindle_toggle_split_direction(const Arg *arg) { (void)arg; return 0; }
int32_t enable_monitor(const Arg *arg) { (void)arg; return 0; }
int32_t enter_overview(const Arg *arg) { (void)arg; return 0; }
int32_t exchange_client(const Arg *arg) { (void)arg; return 0; }
int32_t exchange_stack_client(const Arg *arg) { (void)arg; return 0; }
int32_t focus_by_id(const Arg *arg) { (void)arg; return 0; }
int32_t focus_direction(const Arg *arg) { (void)arg; return 0; }
int32_t focus_last(const Arg *arg) { (void)arg; return 0; }
int32_t focus_monitor(const Arg *arg) { (void)arg; return 0; }
int32_t focus_stack(const Arg *arg) { (void)arg; return 0; }
int32_t focus_window_or_workspace(const Arg *arg) { (void)arg; return 0; }
int32_t group_focus(const Arg *arg) { (void)arg; return 0; }
int32_t group_join(const Arg *arg) { (void)arg; return 0; }
int32_t group_leave(const Arg *arg) { (void)arg; return 0; }
int32_t inc_nmaster(const Arg *arg) { (void)arg; return 0; }
int32_t increase_gaps(const Arg *arg) { (void)arg; return 0; }
int32_t kill_client(const Arg *arg) { (void)arg; return 0; }
int32_t leave_overview(const Arg *arg) { (void)arg; return 0; }
int32_t load_config_file(const Arg *arg) { (void)arg; return 0; }
int32_t minimize_window(const Arg *arg) { (void)arg; return 0; }
int32_t move_client(const Arg *arg) { (void)arg; return 0; }
int32_t move_resize(const Arg *arg) { (void)arg; return 0; }
int32_t move_window(const Arg *arg) { (void)arg; return 0; }
int32_t over_circle(const Arg *arg) { (void)arg; return 0; }
int32_t quit(const Arg *arg) { (void)arg; return 0; }
int32_t reload_config(const Arg *arg) { (void)arg; return 0; }
int32_t resize_window(const Arg *arg) { (void)arg; return 0; }
int32_t restore_minimized(const Arg *arg) { (void)arg; return 0; }
int32_t scroller_stack(const Arg *arg) { (void)arg; return 0; }
int32_t set_key_mode(const Arg *arg) { (void)arg; return 0; }
int32_t set_layout(const Arg *arg) { (void)arg; return 0; }
int32_t set_master_factor(const Arg *arg) { (void)arg; return 0; }
int32_t set_proportion(const Arg *arg) { (void)arg; return 0; }
int32_t setoption(const Arg *arg) { (void)arg; return 0; }
int32_t sleep_monitor(const Arg *arg) { (void)arg; return 0; }
int32_t sleep_toggle_monitor(const Arg *arg) { (void)arg; return 0; }
int32_t smart_move_window(const Arg *arg) { (void)arg; return 0; }
int32_t smart_resize_window(const Arg *arg) { (void)arg; return 0; }
int32_t spawn(const Arg *arg) { (void)arg; return 0; }
int32_t spawn_on_empty(const Arg *arg) { (void)arg; return 0; }
int32_t spawn_shell(const Arg *arg) { (void)arg; return 0; }
int32_t switch_keyboard_layout(const Arg *arg) { (void)arg; return 0; }
int32_t switch_layout(const Arg *arg) { (void)arg; return 0; }
int32_t switch_proportion_preset(const Arg *arg) { (void)arg; return 0; }
int32_t switcher(const Arg *arg) { (void)arg; return 0; }
int32_t tag(const Arg *arg) { (void)arg; return 0; }
int32_t tag_cross_monitor(const Arg *arg) { (void)arg; return 0; }
int32_t tag_monitor(const Arg *arg) { (void)arg; return 0; }
int32_t tag_silent(const Arg *arg) { (void)arg; return 0; }
int32_t tag_special_silent(const Arg *arg) { (void)arg; return 0; }
int32_t tag_special_tag(const Arg *arg) { (void)arg; return 0; }
int32_t tag_to_left(const Arg *arg) { (void)arg; return 0; }
int32_t tag_to_right(const Arg *arg) { (void)arg; return 0; }
int32_t toggle_all_floating(const Arg *arg) { (void)arg; return 0; }
int32_t toggle_fake_fullscreen(const Arg *arg) { (void)arg; return 0; }
int32_t toggle_floating(const Arg *arg) { (void)arg; return 0; }
int32_t toggle_fullscreen(const Arg *arg) { (void)arg; return 0; }
int32_t toggle_gaps(const Arg *arg) { (void)arg; return 0; }
int32_t toggle_global(const Arg *arg) { (void)arg; return 0; }
int32_t toggle_group_bar(const Arg *arg) { (void)arg; return 0; }
int32_t toggle_hdr(const Arg *arg) { (void)arg; return 0; }
int32_t toggle_jump(const Arg *arg) { (void)arg; return 0; }
int32_t toggle_maximize_screen(const Arg *arg) { (void)arg; return 0; }
int32_t toggle_monitor(const Arg *arg) { (void)arg; return 0; }
int32_t toggle_named_scratchpad(const Arg *arg) { (void)arg; return 0; }
int32_t toggle_overlay(const Arg *arg) { (void)arg; return 0; }
int32_t toggle_overview(const Arg *arg) { (void)arg; return 0; }
int32_t toggle_render_border(const Arg *arg) { (void)arg; return 0; }
int32_t toggle_scratchpad(const Arg *arg) { (void)arg; return 0; }
int32_t toggle_special_tag(const Arg *arg) { (void)arg; return 0; }
int32_t toggle_tag(const Arg *arg) { (void)arg; return 0; }
int32_t toggle_trackpad_enable(const Arg *arg) { (void)arg; return 0; }
int32_t toggle_view(const Arg *arg) { (void)arg; return 0; }
int32_t view_cross_monitor(const Arg *arg) { (void)arg; return 0; }
int32_t view_insert(const Arg *arg) { (void)arg; return 0; }
int32_t view_to_left(const Arg *arg) { (void)arg; return 0; }
int32_t view_to_left_have_client(const Arg *arg) { (void)arg; return 0; }
int32_t view_to_right(const Arg *arg) { (void)arg; return 0; }
int32_t view_to_right_have_client(const Arg *arg) { (void)arg; return 0; }
int32_t viewnext_have_client(const Arg *arg) { (void)arg; return 0; }
int32_t viewprev_have_client(const Arg *arg) { (void)arg; return 0; }
int32_t wakeup_monitor(const Arg *arg) { (void)arg; return 0; }
int32_t zoom(const Arg *arg) { (void)arg; return 0; }
