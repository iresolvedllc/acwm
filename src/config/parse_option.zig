//! Port of the option dispatcher in config/option_defs.c
//! (Phase 5, config cleanup slice, slice 98).

const c = @import("cc");

const Apply = *const fn (
    config: ?*c.Config,
    key: [*:0]const u8,
    value: [*:0]const u8,
    line_number: c_int,
) callconv(.c) c_int;

extern fn acwm_config_apply_bar_option(config: ?*c.Config, key: [*:0]const u8, value: [*:0]const u8, line_number: c_int) callconv(.c) c_int;
extern fn acwm_config_apply_session_option(config: ?*c.Config, key: [*:0]const u8, value: [*:0]const u8, line_number: c_int) callconv(.c) c_int;
extern fn acwm_config_apply_layout_option(config: ?*c.Config, key: [*:0]const u8, value: [*:0]const u8, line_number: c_int) callconv(.c) c_int;
extern fn acwm_config_apply_input_option(config: ?*c.Config, key: [*:0]const u8, value: [*:0]const u8, line_number: c_int) callconv(.c) c_int;
extern fn acwm_config_apply_visuals_option(config: ?*c.Config, key: [*:0]const u8, value: [*:0]const u8, line_number: c_int) callconv(.c) c_int;
extern fn acwm_config_apply_device_option(config: ?*c.Config, key: [*:0]const u8, value: [*:0]const u8, line_number: c_int) callconv(.c) c_int;
extern fn acwm_config_apply_animation_option(config: ?*c.Config, key: [*:0]const u8, value: [*:0]const u8, line_number: c_int) callconv(.c) c_int;
extern fn acwm_config_apply_scroller_option(config: ?*c.Config, key: [*:0]const u8, value: [*:0]const u8, line_number: c_int) callconv(.c) c_int;
extern fn acwm_config_apply_misc_option(config: ?*c.Config, key: [*:0]const u8, value: [*:0]const u8, line_number: c_int) callconv(.c) c_int;
extern fn acwm_config_apply_jumplabel_option(config: ?*c.Config, key: [*:0]const u8, value: [*:0]const u8, line_number: c_int) callconv(.c) c_int;
extern fn acwm_config_apply_gaps_option(config: ?*c.Config, key: [*:0]const u8, value: [*:0]const u8, line_number: c_int) callconv(.c) c_int;
extern fn acwm_config_apply_array_option(config: ?*c.Config, key: [*:0]const u8, value: [*:0]const u8, line_number: c_int) callconv(.c) c_int;
extern fn acwm_config_apply_monitor_rule(config: ?*c.Config, key: [*:0]const u8, value: [*:0]const u8, line_number: c_int) callconv(.c) c_int;
extern fn acwm_config_apply_rules_option(config: ?*c.Config, key: [*:0]const u8, value: [*:0]const u8, line_number: c_int) callconv(.c) c_int;
extern fn acwm_config_apply_window_rule(config: ?*c.Config, key: [*:0]const u8, value: [*:0]const u8, line_number: c_int) callconv(.c) c_int;
extern fn acwm_config_apply_device_rule(config: ?*c.Config, key: [*:0]const u8, value: [*:0]const u8, line_number: c_int) callconv(.c) c_int;
extern fn acwm_config_apply_directives_option(config: ?*c.Config, key: [*:0]const u8, value: [*:0]const u8, line_number: c_int) callconv(.c) c_int;
extern fn acwm_config_apply_bind_option(config: ?*c.Config, key: [*:0]const u8, value: [*:0]const u8, line_number: c_int) callconv(.c) c_int;
extern fn acwm_error_impl(log: bool, verbosity: c.enum_wlr_log_importance, file: [*c]const u8, line: c_int, fmt: [*c]const u8, ...) callconv(.c) void;

export fn parse_option(
    config: ?*c.Config,
    key: [*:0]u8,
    value: [*:0]u8,
    line_number: c_int,
) callconv(.c) bool {
    const groups = [_]Apply{
        acwm_config_apply_bar_option,
        acwm_config_apply_session_option,
        acwm_config_apply_layout_option,
        acwm_config_apply_input_option,
        acwm_config_apply_visuals_option,
        acwm_config_apply_device_option,
        acwm_config_apply_animation_option,
        acwm_config_apply_scroller_option,
        acwm_config_apply_misc_option,
        acwm_config_apply_jumplabel_option,
        acwm_config_apply_gaps_option,
        acwm_config_apply_array_option,
        acwm_config_apply_monitor_rule,
        acwm_config_apply_rules_option,
        acwm_config_apply_window_rule,
        acwm_config_apply_device_rule,
        acwm_config_apply_directives_option,
        acwm_config_apply_bind_option,
    };

    inline for (groups) |apply| {
        const result = apply(config, key, value, line_number);
        if (result != 0)
            return result > 0;
    }

    acwm_error_impl(false, c.WLR_ERROR, "src/config/option_defs.c", line_number,
        "Unknown keyword: \x1b[1m\x1b[31m%s\x1b[0m", key);
    return false;
}
