/* Test-only stubs for bind_view.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/config/parse.h"
#include "acwm/dispatch/bind.h"
#include "acwm/ipc/ipc.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"

Config config = {0};
struct AcwmServer server = {0};

uint32_t stub_tag_status[32];
int stub_switch_view_calls = 0;
uint32_t stub_switch_view_ui = 0;
int stub_focus_calls = 0;
Client *stub_focus_client = NULL;
Client *stub_focus_top = NULL;
int stub_set_size_calls = 0;
int stub_arrange_calls = 0;
int stub_printstatus_calls = 0;
bool stub_special_active = false;
int stub_shift_tags_calls = 0;
uint32_t stub_shift_tags_target = 0;
int stub_view_on_monitor_calls = 0;
int stub_focus_monitor_calls = 0;
int32_t stub_focus_monitor_i = 0;
int stub_tag_monitor_calls = 0;
int32_t stub_tag_monitor_i = 0;
int stub_tag_client_calls = 0;
bool stub_match_monitor = true;
int stub_parse_calls = 0;
char stub_parse_key[256];
char stub_parse_value[256];
int stub_override_calls = 0;
int stub_reset_option_calls = 0;
int stub_minimized_calls = 0;

uint32_t get_tags_first_tag_num(uint32_t tags) {
	uint32_t n = 0;
	for (uint32_t i = 0; i < 32; i++)
		if (tags & (1u << i)) {
			n = i + 1;
			break;
		}
	return n;
}
uint32_t get_tags_first_tag(uint32_t tags) {
	return tags & (~tags + 1);
}
uint32_t get_tag_status(uint32_t tag, Monitor *m) {
	(void)m;
	return tag < 32 ? stub_tag_status[tag] : 0;
}
void client_switch_view(const Arg *arg, bool animate) {
	(void)animate;
	stub_switch_view_calls++;
	stub_switch_view_ui = arg->ui;
}
void client_focus(Client *c, int32_t lift) {
	(void)lift;
	stub_focus_calls++;
	stub_focus_client = c;
}
Client *client_focus_top(Monitor *m) {
	(void)m;
	return stub_focus_top;
}
void set_size_per(Monitor *m, Client *c, bool reset) {
	(void)m;
	(void)c;
	(void)reset;
	stub_set_size_calls++;
}
void arrange(Monitor *m, bool want_animation, bool from_view) {
	(void)m;
	(void)want_animation;
	(void)from_view;
	stub_arrange_calls++;
}
void printstatus(enum ipc_watch_type type) {
	(void)type;
	stub_printstatus_calls++;
}
bool is_special_active(const Monitor *m) {
	(void)m;
	return stub_special_active;
}
void view_insert_shift_tags(Monitor *m, uint32_t target) {
	(void)m;
	stub_shift_tags_calls++;
	stub_shift_tags_target = target;
}
void client_view_on_monitor(const Arg *arg, bool animate, Monitor *m,
							bool changefocus) {
	(void)arg;
	(void)animate;
	(void)m;
	(void)changefocus;
	stub_view_on_monitor_calls++;
}
int32_t focus_monitor(const Arg *arg) {
	stub_focus_monitor_calls++;
	stub_focus_monitor_i = arg->i;
	return 0;
}
int32_t tag_monitor(const Arg *arg) {
	stub_tag_monitor_calls++;
	stub_tag_monitor_i = arg->i;
	return 0;
}
void tag_client(const Arg *arg, Client *c) {
	(void)arg;
	(void)c;
	stub_tag_client_calls++;
}
bool match_monitor_spec(char *spec, Monitor *m) {
	(void)spec;
	(void)m;
	return stub_match_monitor;
}
uint32_t get_mon_curtag(const Monitor *m) {
	(void)m;
	return 0;
}
bool parse_option(Config *config, char *key, char *value, int line_number) {
	(void)config;
	(void)line_number;
	stub_parse_calls++;
	snprintf(stub_parse_key, sizeof(stub_parse_key), "%s", key);
	snprintf(stub_parse_value, sizeof(stub_parse_value), "%s", value);
	return true;
}
void override_config(void) { stub_override_calls++; }
void reset_option(void) { stub_reset_option_calls++; }
void set_minimized(Client *c) {
	(void)c;
	stub_minimized_calls++;
}
