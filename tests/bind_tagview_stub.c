/* Test-only stubs for bind_tagview.zig. */
#define WLR_USE_UNSTABLE 1
#include "acwm/common/server.h"
#include "acwm/animation/client.h"
#include "acwm/config/parse.h"
#include "acwm/dispatch/bind.h"
#include "acwm/ipc/ipc.h"
#include "acwm/manage/client.h"
#include "acwm/manage/monitor.h"

Config config = {0};
struct AcwmServer server = {0};

int stub_tag_client_calls = 0;
uint32_t stub_tag_client_ui = 0;
Client *stub_tag_client_target = NULL;
uint32_t stub_tag_client_target_tags = 0;

int stub_switch_view_calls = 0;
uint32_t stub_switch_view_ui = 0;
bool stub_switch_view_anim = false;

int stub_focus_calls = 0;
int stub_focus_top_calls = 0;
Client *stub_focus_top = NULL;
int stub_set_monitor_calls = 0;
Client *stub_set_monitor_client = NULL;
Monitor *stub_set_monitor_mon = NULL;
uint32_t stub_set_monitor_tags = 0;
int stub_update_oldmon_calls = 0;
int stub_reset_foreign_calls = 0;
int stub_selected_calls = 0;
Monitor *stub_selected_mon = NULL;
int stub_resize_calls = 0;
int stub_warp_calls = 0;
int stub_arrange_calls = 0;
int stub_reparent_calls = 0;
int stub_clear_fullscreen_calls = 0;
int stub_named_scratch_calls = 0;
int stub_spawn_calls = 0;
int stub_minimized_calls = 0;
int stub_switch_scratch_calls = 0;
bool stub_switch_scratch_result = false;
int stub_special_active_calls = 0;
bool stub_special_active = false;
int stub_fake_fullscreen_calls = 0;
int32_t stub_fake_fullscreen_arg = 0;
int stub_floating_calls = 0;
int32_t stub_floating_arg = 0;
int stub_fullscreen_calls = 0;
int32_t stub_fullscreen_arg = 0;
bool stub_fullscreen_rearrange = false;
int stub_maximize_calls = 0;
int32_t stub_maximize_arg = 0;
int stub_border_color_calls = 0;
int stub_set_size_calls = 0;
int stub_printstatus_calls = 0;
int stub_match_calls = 0;
Monitor *stub_cycle_monitor = NULL;
Monitor *stub_direction_monitor = NULL;
Client *stub_lookup_client = NULL;

void tag_client(const Arg *arg, Client *target) {
	stub_tag_client_calls++;
	stub_tag_client_ui = arg->ui;
	stub_tag_client_target = target;
	stub_tag_client_target_tags = target ? target->tags : 0;
}

void client_switch_view(const Arg *arg, bool want_animation) {
	stub_switch_view_calls++;
	stub_switch_view_ui = arg->ui;
	stub_switch_view_anim = want_animation;
}

void client_focus(Client *c, int32_t lift) {
	(void)c;
	(void)lift;
	stub_focus_calls++;
}

Client *client_focus_top(Monitor *m) {
	(void)m;
	stub_focus_top_calls++;
	return stub_focus_top;
}

Monitor *monitor_from_cycle(int32_t dir) {
	(void)dir;
	return stub_cycle_monitor;
}

Monitor *monitor_from_direction(enum wlr_direction dir) {
	(void)dir;
	return stub_direction_monitor;
}

bool match_monitor_spec(char *spec, Monitor *m) {
	(void)spec;
	(void)m;
	stub_match_calls++;
	return true;
}

void client_set_monitor(Client *c, Monitor *m, uint32_t newtags, bool focus) {
	(void)newtags;
	(void)focus;
	stub_set_monitor_calls++;
	stub_set_monitor_client = c;
	stub_set_monitor_mon = m;
	c->mon = m;
}

void client_update_oldmonname_record(Client *c, Monitor *m) {
	(void)c;
	(void)m;
	stub_update_oldmon_calls++;
}

void reset_foreign_tolevel(Client *c, Monitor *oldmon, Monitor *newmon) {
	(void)c;
	(void)oldmon;
	(void)newmon;
	stub_reset_foreign_calls++;
}

void set_selected_monitor(Monitor *m) {
	stub_selected_calls++;
	stub_selected_mon = m;
	server.selected_monitor = m;
}

struct wlr_box client_center_geometry(Client *c, Monitor *tm, struct wlr_box geom,
									  int32_t offsetx, int32_t offsety) {
	(void)c;
	(void)tm;
	(void)offsetx;
	(void)offsety;
	return geom;
}

uint32_t get_tags_first_tag(uint32_t tags) {
	return tags & (~tags + 1);
}

uint32_t get_tags_first_tag_num(uint32_t tags) {
	uint32_t num = 0;
	for (uint32_t i = 0; i < 32; i++)
		if (tags & (1u << i))
			num = i + 1;
	return num;
}

void resize(Client *c, struct wlr_box geo, ResizeOpts opts) {
	(void)c;
	(void)geo;
	(void)opts;
	stub_resize_calls++;
}

void pointer_warp_to_monitor(Monitor *m) {
	(void)m;
	stub_warp_calls++;
}

void arrange(Monitor *m, bool want_animation, bool from_view) {
	(void)m;
	(void)want_animation;
	(void)from_view;
	stub_arrange_calls++;
}

void client_reparent_group(Client *c) {
	(void)c;
	stub_reparent_calls++;
}

void clear_fullscreen_flag(Client *c) {
	(void)c;
	stub_clear_fullscreen_calls++;
}

Client *get_client_by_id_or_title(const char *id, const char *title) {
	(void)id;
	(void)title;
	return stub_lookup_client;
}

void apply_named_scratchpad(Client *c) {
	(void)c;
	stub_named_scratch_calls++;
}

int32_t spawn_shell(const Arg *arg) {
	(void)arg;
	stub_spawn_calls++;
	return 0;
}

void set_minimized(Client *c) {
	(void)c;
	stub_minimized_calls++;
}

bool switch_scratchpad_client_state(Client *c) {
	(void)c;
	stub_switch_scratch_calls++;
	return stub_switch_scratch_result;
}

bool is_special_active(const Monitor *m) {
	(void)m;
	stub_special_active_calls++;
	return stub_special_active;
}

void client_set_fake_fullscreen(Client *c, int32_t fake) {
	(void)c;
	stub_fake_fullscreen_calls++;
	stub_fake_fullscreen_arg = fake;
}

void client_set_floating(Client *c, int32_t floating) {
	(void)c;
	stub_floating_calls++;
	stub_floating_arg = floating;
}

void client_apply_fullscreen(Client *c, int32_t fullscreen, bool rearrange) {
	(void)c;
	stub_fullscreen_calls++;
	stub_fullscreen_arg = fullscreen;
	stub_fullscreen_rearrange = rearrange;
}

void client_set_maximize_screen(Client *c, int32_t maximize, bool rearrange) {
	(void)c;
	(void)rearrange;
	stub_maximize_calls++;
	stub_maximize_arg = maximize;
}

void client_update_border_color(Client *c) {
	(void)c;
	stub_border_color_calls++;
}

void set_size_per(Monitor *m, Client *c, bool reset) {
	(void)m;
	(void)c;
	(void)reset;
	stub_set_size_calls++;
}

void printstatus(enum ipc_watch_type type) {
	(void)type;
	stub_printstatus_calls++;
}
