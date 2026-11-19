//! Port of the remaining option_defs.c functions (strangler-fig Phase 4,
//! slice 19): set_value_default, override_config, update_global_var and
//! apply_option_expanded.
//!
//! Exports the same C symbols as the C twins (all four removed from the
//! compositor link via the usual same-symbol rule — the C twins are deleted
//! from option_defs.c entirely because nothing else in that file needs
//! them; parse_option remains C for the meson build):
//!   - set_value_default: the startup defaults table (ints/floats/enums,
//!     RGBA arrays with hex/255 construction, strdup'd strings) applied to
//!     the global `Config config`
//!   - override_config: the post-parse clamp table in C order (CLAMP_INT in
//!     the int domain — including the two float fields C clamps with
//!     CLAMP_INT — and CLAMP_FLOAT, float-domain for f32 fields,
//!     double-domain for f64 fields), then update_global_var()
//!   - update_global_var: server.tagmask = (1 << tag_num) - 1 with x86
//!     shift-count masking (tag_num is clamped to 1..tag_num_MAX before)
//!   - apply_option_expanded: expand_config_variables -> parse_option ->
//!     free, with the expanded-or-original fallback
//!
//! Intentional divergence: NaN / out-of-i32-range floats reaching the
//! int-domain clamps saturate instead of C's UB cast.
//!
//! Tests live at the bottom and need tests/option_defaults_stub.c.

const std = @import("std");
const c = @import("cc");

extern "c" fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern "c" fn free(ptr: ?*anyopaque) void;
/// variable_expand twin in the compositor link; stubbed in tests.
extern fn expand_config_variables(value: [*:0]const u8) callconv(.c) ?[*:0]u8;
/// C parse_option in the compositor (and the meson) build; stubbed in tests.
extern fn parse_option(config: *c.Config, key: [*:0]u8, value: [*:0]u8, line_number: c_int) callconv(.c) bool;

fn hexF32(comptime byte: u8) f32 {
    return @as(f32, @floatFromInt(byte)) / 255.0;
}

fn enumI(comptime v: anytype) i64 {
    return @intCast(v);
}

// ---------------------------------------------------------------------------
// defaults
// ---------------------------------------------------------------------------

const Val = union(enum) {
    i: i64,
    f: f64,
    color: [4]f32,
    curve: [4]f64,
    str: [:0]const u8,
};

const Def = struct {
    field: [:0]const u8,
    nest: ?[:0]const u8 = null,
    val: Val,
};

const defaults = [_]Def{
    // animations
    .{ .field = "animations", .val = .{ .i = 1 } },
    .{ .field = "layer_animations", .val = .{ .i = 0 } },
    .{ .field = "animation_type_open", .val = .{ .i = enumI(c.ANIM_TYPE_UNSET) } },
    .{ .field = "animation_type_close", .val = .{ .i = enumI(c.ANIM_TYPE_UNSET) } },
    .{ .field = "layer_animation_type_open", .val = .{ .i = enumI(c.ANIM_TYPE_UNSET) } },
    .{ .field = "layer_animation_type_close", .val = .{ .i = enumI(c.ANIM_TYPE_UNSET) } },
    .{ .field = "animation_fade_in", .val = .{ .i = 1 } },
    .{ .field = "animation_fade_out", .val = .{ .i = 1 } },
    .{ .field = "tag_animation_direction", .val = .{ .i = enumI(c.HORIZONTAL) } },
    .{ .field = "zoom_initial_ratio", .val = .{ .f = 0.4 } },
    .{ .field = "zoom_end_ratio", .val = .{ .f = 0.8 } },
    .{ .field = "fadein_begin_opacity", .val = .{ .f = 0.5 } },
    .{ .field = "fadeout_begin_opacity", .val = .{ .f = 0.5 } },
    .{ .field = "animation_duration_move", .val = .{ .i = 500 } },
    .{ .field = "animation_duration_open", .val = .{ .i = 400 } },
    .{ .field = "animation_duration_tag", .val = .{ .i = 300 } },
    .{ .field = "animation_duration_close", .val = .{ .i = 300 } },
    .{ .field = "animation_duration_focus", .val = .{ .i = 0 } },
    // session/general
    .{ .field = "axis_bind_apply_timeout", .val = .{ .i = 100 } },
    .{ .field = "focus_on_activate", .val = .{ .i = 1 } },
    .{ .field = "new_is_master", .val = .{ .i = 1 } },
    .{ .field = "default_mfact", .val = .{ .f = 0.55 } },
    .{ .field = "default_nmaster", .val = .{ .i = 1 } },
    .{ .field = "tag_num", .val = .{ .i = 9 } },
    .{ .field = "tag_gather", .val = .{ .i = 0 } },
    .{ .field = "center_master_overspread", .val = .{ .i = 0 } },
    .{ .field = "center_when_single_stack", .val = .{ .i = 1 } },
    // dwindle
    .{ .field = "dwindle_vsplit", .val = .{ .i = 1 } },
    .{ .field = "dwindle_hsplit", .val = .{ .i = 1 } },
    .{ .field = "dwindle_preserve_split", .val = .{ .i = 0 } },
    .{ .field = "dwindle_smart_split", .val = .{ .i = 0 } },
    .{ .field = "dwindle_smart_resize", .val = .{ .i = 0 } },
    .{ .field = "dwindle_drop_simple_split", .val = .{ .i = 1 } },
    .{ .field = "dwindle_manual_split", .val = .{ .i = 0 } },
    .{ .field = "dwindle_split_ratio", .val = .{ .f = 0.5 } },
    // input/layout misc
    .{ .field = "log_level", .val = .{ .i = enumI(c.WLR_ERROR) } },
    .{ .field = "numlockon", .val = .{ .i = 0 } },
    .{ .field = "capslock", .val = .{ .i = 0 } },
    .{ .field = "hotarea_size", .val = .{ .i = 10 } },
    .{ .field = "hotarea_corner", .val = .{ .i = enumI(c.BOTTOM_LEFT) } },
    .{ .field = "enable_hotarea", .val = .{ .i = 0 } },
    .{ .field = "hotarea_disable_on_fullscreen", .val = .{ .i = 1 } },
    .{ .field = "smartgaps", .val = .{ .i = 0 } },
    .{ .field = "monocle_tab_mode", .val = .{ .i = 1 } },
    .{ .field = "deck_tab_mode", .val = .{ .i = 1 } },
    .{ .field = "sloppyfocus", .val = .{ .i = 1 } },
    // gaps
    .{ .field = "gappih", .val = .{ .i = 5 } },
    .{ .field = "gappiv", .val = .{ .i = 5 } },
    .{ .field = "gappoh", .val = .{ .i = 10 } },
    .{ .field = "gappov", .val = .{ .i = 10 } },
    .{ .field = "scratchpad_width_ratio", .val = .{ .f = 0.8 } },
    .{ .field = "scratchpad_height_ratio", .val = .{ .f = 0.9 } },
    .{ .field = "special_dim", .val = .{ .f = 0.5 } },
    .{ .field = "special_gappih", .val = .{ .i = 10 } },
    .{ .field = "special_gappiv", .val = .{ .i = 10 } },
    .{ .field = "special_gappoh", .val = .{ .i = 20 } },
    .{ .field = "special_gappov", .val = .{ .i = 20 } },
    // scroller/focus
    .{ .field = "scroller_structs", .val = .{ .i = 20 } },
    .{ .field = "scroller_default_proportion", .val = .{ .f = 0.9 } },
    .{ .field = "scroller_default_proportion_single", .val = .{ .f = 1.0 } },
    .{ .field = "scroller_ignore_proportion_single", .val = .{ .i = 1 } },
    .{ .field = "scroller_focus_center", .val = .{ .i = 0 } },
    .{ .field = "scroller_prefer_center", .val = .{ .i = 0 } },
    .{ .field = "scroller_prefer_overspread", .val = .{ .i = 1 } },
    .{ .field = "edge_scroller_pointer_focus", .val = .{ .i = 1 } },
    .{ .field = "edge_scroller_focus_allow_speed", .val = .{ .f = 0.0 } },
    .{ .field = "focus_cross_monitor", .val = .{ .i = 0 } },
    .{ .field = "focusdir_only_zone_overlap", .val = .{ .i = 1 } },
    .{ .field = "exchange_cross_monitor", .val = .{ .i = 0 } },
    .{ .field = "scratchpad_cross_monitor", .val = .{ .i = 0 } },
    .{ .field = "focus_cross_tag", .val = .{ .i = 0 } },
    .{ .field = "axis_scroll_factor", .val = .{ .f = 1.0 } },
    .{ .field = "trackpad_scroll_factor", .val = .{ .f = 1.0 } },
    .{ .field = "view_current_to_back", .val = .{ .i = 0 } },
    // misc
    .{ .field = "single_scratchpad", .val = .{ .i = 1 } },
    .{ .field = "xwayland_persistence", .val = .{ .i = 1 } },
    .{ .field = "xwayland_ignore_scale", .val = .{ .i = 0 } },
    .{ .field = "syncobj_enable", .val = .{ .i = 1 } },
    .{ .field = "tag_carousel", .val = .{ .i = 0 } },
    .{ .field = "allow_tearing", .val = .{ .i = enumI(c.TEARING_DISABLED) } },
    .{ .field = "hdr_depth", .val = .{ .i = enumI(c.ACWM_RENDER_BIT_DEPTH_10) } },
    .{ .field = "allow_shortcuts_inhibit", .val = .{ .i = enumI(c.SHORTCUTS_INHIBIT_ENABLE) } },
    .{ .field = "disable_middle_paste", .val = .{ .i = 0 } },
    .{ .field = "allow_lock_transparent", .val = .{ .i = 0 } },
    .{ .field = "auto_reload_config", .val = .{ .i = 1 } },
    .{ .field = "no_border_when_single", .val = .{ .i = 0 } },
    .{ .field = "no_radius_when_single", .val = .{ .i = 0 } },
    .{ .field = "monocle_no_border", .val = .{ .i = 0 } },
    .{ .field = "monocle_no_gap", .val = .{ .i = 0 } },
    .{ .field = "snap_distance", .val = .{ .i = 30 } },
    .{ .field = "drag_tile_to_tile", .val = .{ .i = 1 } },
    .{ .field = "drag_tile_small", .val = .{ .i = 1 } },
    .{ .field = "enable_floating_snap", .val = .{ .i = 0 } },
    .{ .field = "float_full_to_top", .val = .{ .i = 0 } },
    .{ .field = "swipe_min_threshold", .val = .{ .i = 1 } },
    .{ .field = "gesture_live", .val = .{ .i = 1 } },
    .{ .field = "gesture_swipe_distance", .val = .{ .i = 300 } },
    .{ .field = "gesture_swipe_cancel_ratio", .val = .{ .f = 0.5 } },
    .{ .field = "gesture_swipe_min_speed_to_force", .val = .{ .f = 10 } },
    .{ .field = "idleinhibit_ignore_visible", .val = .{ .i = 0 } },
    .{ .field = "idleinhibit_when_fullscreen", .val = .{ .i = 0 } },
    // borders / group bar
    .{ .field = "borderpx", .val = .{ .i = 4 } },
    .{ .field = "group_bar_height", .val = .{ .i = 33 } },
    .{ .field = "tab_bar_height", .val = .{ .i = 33 } },
    .{ .field = "always_show_group_bar", .val = .{ .i = 0 } },
    .{ .field = "group_bar_close_button_enable", .val = .{ .i = 1 } },
    .{ .field = "group_bar_button_size", .val = .{ .i = 16 } },
    .{ .field = "group_bar_button_margin", .val = .{ .i = 4 } },
    .{ .field = "group_bar_button_color", .val = .{ .color = .{ hexF32(0xad), hexF32(0x40), hexF32(0x1f), 1.0 } } },
    .{ .field = "overviewgappi", .val = .{ .i = 5 } },
    .{ .field = "overviewgappo", .val = .{ .i = 30 } },
    .{ .field = "overcircle_center_ratio", .val = .{ .f = 0.5 } },
    .{ .field = "cursor_hide_timeout", .val = .{ .i = 0 } },
    .{ .field = "cursor_hide_on_keypress", .val = .{ .i = 0 } },
    // cursor / drag
    .{ .field = "warpcursor", .val = .{ .i = 1 } },
    .{ .field = "drag_corner", .val = .{ .i = 3 } },
    .{ .field = "drag_warp_cursor", .val = .{ .i = 1 } },
    .{ .field = "enable_border_resize", .val = .{ .i = 1 } },
    .{ .field = "border_resize_size", .val = .{ .i = 10 } },
    // keyrepeat
    .{ .field = "repeat_rate", .val = .{ .i = 25 } },
    .{ .field = "repeat_delay", .val = .{ .i = 600 } },
    // touch / mouse / trackpad
    .{ .field = "disable_trackpad", .val = .{ .i = 0 } },
    .{ .field = "touch_enable", .val = .{ .i = 1 } },
    .{ .field = "touch_enable_mouse_emulation", .val = .{ .i = 0 } },
    .{ .field = "tap_to_click", .val = .{ .i = 1 } },
    .{ .field = "tap_and_drag", .val = .{ .i = 1 } },
    .{ .field = "drag_lock", .val = .{ .i = 1 } },
    .{ .field = "mouse_natural_scrolling", .val = .{ .i = 0 } },
    .{ .field = "cursor_size", .val = .{ .i = 24 } },
    .{ .field = "trackpad_natural_scrolling", .val = .{ .i = 0 } },
    .{ .field = "mouse_accel_profile", .val = .{ .i = enumI(c.LIBINPUT_CONFIG_ACCEL_PROFILE_ADAPTIVE) } },
    .{ .field = "mouse_accel_speed", .val = .{ .f = 0.0 } },
    .{ .field = "trackpad_accel_profile", .val = .{ .i = enumI(c.LIBINPUT_CONFIG_ACCEL_PROFILE_ADAPTIVE) } },
    .{ .field = "trackpad_accel_speed", .val = .{ .f = 0.0 } },
    .{ .field = "send_events_mode", .val = .{ .i = enumI(c.LIBINPUT_CONFIG_SEND_EVENTS_ENABLED) } },
    .{ .field = "button_map", .val = .{ .i = enumI(c.LIBINPUT_CONFIG_TAP_MAP_LRM) } },
    .{ .field = "mouse_left_handed", .val = .{ .i = 0 } },
    .{ .field = "mouse_middle_button_emulation", .val = .{ .i = 0 } },
    .{ .field = "mouse_scroll_method", .val = .{ .i = enumI(c.LIBINPUT_CONFIG_SCROLL_2FG) } },
    .{ .field = "mouse_scroll_button", .val = .{ .i = 274 } },
    .{ .field = "mouse_click_method", .val = .{ .i = enumI(c.LIBINPUT_CONFIG_CLICK_METHOD_BUTTON_AREAS) } },
    .{ .field = "mouse_send_events_mode", .val = .{ .i = enumI(c.LIBINPUT_CONFIG_SEND_EVENTS_ENABLED) } },
    .{ .field = "trackpad_left_handed", .val = .{ .i = 0 } },
    .{ .field = "trackpad_middle_button_emulation", .val = .{ .i = 0 } },
    .{ .field = "trackpad_disable_while_typing", .val = .{ .i = 1 } },
    .{ .field = "trackpad_scroll_method", .val = .{ .i = enumI(c.LIBINPUT_CONFIG_SCROLL_2FG) } },
    .{ .field = "trackpad_scroll_button", .val = .{ .i = 274 } },
    .{ .field = "trackpad_click_method", .val = .{ .i = enumI(c.LIBINPUT_CONFIG_CLICK_METHOD_BUTTON_AREAS) } },
    .{ .field = "trackpad_send_events_mode", .val = .{ .i = enumI(c.LIBINPUT_CONFIG_SEND_EVENTS_ENABLED) } },
    // blur / shadows
    .{ .field = "blur", .val = .{ .i = 0 } },
    .{ .field = "blur_layer", .val = .{ .i = 0 } },
    .{ .field = "blur_optimized", .val = .{ .i = 1 } },
    .{ .field = "border_radius", .val = .{ .i = 0 } },
    .{ .field = "num_passes", .nest = "blur_params", .val = .{ .i = 1 } },
    .{ .field = "radius", .nest = "blur_params", .val = .{ .f = 5.0 } },
    .{ .field = "noise", .nest = "blur_params", .val = .{ .f = 0.02 } },
    .{ .field = "brightness", .nest = "blur_params", .val = .{ .f = 0.9 } },
    .{ .field = "contrast", .nest = "blur_params", .val = .{ .f = 0.9 } },
    .{ .field = "saturation", .nest = "blur_params", .val = .{ .f = 1.2 } },
    .{ .field = "shadows", .val = .{ .i = 0 } },
    .{ .field = "shadow_only_floating", .val = .{ .i = 1 } },
    .{ .field = "layer_shadows", .val = .{ .i = 0 } },
    .{ .field = "shadows_size", .val = .{ .i = 10 } },
    .{ .field = "shadows_blur", .val = .{ .f = 15.0 } },
    .{ .field = "shadows_position_x", .val = .{ .i = 0 } },
    .{ .field = "shadows_position_y", .val = .{ .i = 0 } },
    .{ .field = "focused_opacity", .val = .{ .f = 1.0 } },
    .{ .field = "unfocused_opacity", .val = .{ .f = 1.0 } },
    .{ .field = "shadowscolor", .val = .{ .color = .{ 0.0, 0.0, 0.0, 1.0 } } },
    .{ .field = "dim_enable", .val = .{ .i = 0 } },
    .{ .field = "dim_focused_color", .val = .{ .color = .{ 0.0, 0.0, 0.0, 0.0 } } },
    .{ .field = "dim_unfocused_color", .val = .{ .color = .{ 0.0, 0.0, 0.0, hexF32(0x55) } } },
    // curves
    .{ .field = "animation_curve_move", .val = .{ .curve = .{ 0.46, 1.0, 0.29, 0.99 } } },
    .{ .field = "animation_curve_open", .val = .{ .curve = .{ 0.46, 1.0, 0.29, 0.99 } } },
    .{ .field = "animation_curve_tag", .val = .{ .curve = .{ 0.46, 1.0, 0.29, 0.99 } } },
    .{ .field = "animation_curve_close", .val = .{ .curve = .{ 0.46, 1.0, 0.29, 0.99 } } },
    .{ .field = "animation_curve_focus", .val = .{ .curve = .{ 0.46, 1.0, 0.29, 0.99 } } },
    .{ .field = "animation_curve_opafadein", .val = .{ .curve = .{ 0.46, 1.0, 0.29, 0.99 } } },
    .{ .field = "animation_curve_opafadeout", .val = .{ .curve = .{ 0.5, 0.5, 0.5, 0.5 } } },
    // group bar decoration
    .{ .field = "fg_color", .nest = "groupbardata", .val = .{ .color = .{ hexF32(0xc0), hexF32(0xca), hexF32(0xf5), 1.0 } } },
    .{ .field = "bg_color", .nest = "groupbardata", .val = .{ .color = .{ hexF32(0x1d), hexF32(0x20), hexF32(0x21), 1.0 } } },
    .{ .field = "focus_fg_color", .nest = "groupbardata", .val = .{ .color = .{ hexF32(0x9e), hexF32(0xce), hexF32(0x6a), 1.0 } } },
    .{ .field = "focus_bg_color", .nest = "groupbardata", .val = .{ .color = .{ hexF32(0x3c), hexF32(0x38), hexF32(0x36), 1.0 } } },
    .{ .field = "border_color", .nest = "groupbardata", .val = .{ .color = .{ hexF32(0x3b), hexF32(0x42), hexF32(0x61), 1.0 } } },
    .{ .field = "border_width", .nest = "groupbardata", .val = .{ .i = 4 } },
    .{ .field = "corner_radius", .nest = "groupbardata", .val = .{ .i = 5 } },
    .{ .field = "padding_x", .nest = "groupbardata", .val = .{ .i = 0 } },
    .{ .field = "padding_y", .nest = "groupbardata", .val = .{ .i = 0 } },
    // tab bar decoration
    .{ .field = "fg_color", .nest = "tabbardata", .val = .{ .color = .{ hexF32(0xc0), hexF32(0xca), hexF32(0xf5), 1.0 } } },
    .{ .field = "bg_color", .nest = "tabbardata", .val = .{ .color = .{ hexF32(0x1d), hexF32(0x20), hexF32(0x21), 1.0 } } },
    .{ .field = "focus_fg_color", .nest = "tabbardata", .val = .{ .color = .{ hexF32(0x7a), hexF32(0xa2), hexF32(0xf7), 1.0 } } },
    .{ .field = "focus_bg_color", .nest = "tabbardata", .val = .{ .color = .{ hexF32(0x3c), hexF32(0x38), hexF32(0x36), 1.0 } } },
    .{ .field = "border_color", .nest = "tabbardata", .val = .{ .color = .{ hexF32(0x3b), hexF32(0x42), hexF32(0x61), 1.0 } } },
    .{ .field = "border_width", .nest = "tabbardata", .val = .{ .i = 4 } },
    .{ .field = "corner_radius", .nest = "tabbardata", .val = .{ .i = 5 } },
    .{ .field = "padding_x", .nest = "tabbardata", .val = .{ .i = 0 } },
    .{ .field = "padding_y", .nest = "tabbardata", .val = .{ .i = 0 } },
    // jump label decoration
    .{ .field = "fg_color", .nest = "jumplabeldata", .val = .{ .color = .{ hexF32(0xc4), hexF32(0x93), hexF32(0x9d), 1.0 } } },
    .{ .field = "bg_color", .nest = "jumplabeldata", .val = .{ .color = .{ hexF32(0x32), hexF32(0x32), hexF32(0x32), 1.0 } } },
    .{ .field = "focus_fg_color", .nest = "jumplabeldata", .val = .{ .color = .{ hexF32(0xed), hexF32(0xa6), hexF32(0xb4), 1.0 } } },
    .{ .field = "focus_bg_color", .nest = "jumplabeldata", .val = .{ .color = .{ hexF32(0x4e), hexF32(0x45), hexF32(0x3c), 1.0 } } },
    .{ .field = "border_color", .nest = "jumplabeldata", .val = .{ .color = .{ hexF32(0x8b), hexF32(0xaa), hexF32(0x9b), 1.0 } } },
    .{ .field = "border_width", .nest = "jumplabeldata", .val = .{ .i = 4 } },
    .{ .field = "corner_radius", .nest = "jumplabeldata", .val = .{ .i = 5 } },
    .{ .field = "padding_x", .nest = "jumplabeldata", .val = .{ .i = 10 } },
    .{ .field = "padding_y", .nest = "jumplabeldata", .val = .{ .i = 10 } },
    // built-in bar
    .{ .field = "bar_enable", .val = .{ .i = 0 } },
    .{ .field = "bar_height", .val = .{ .i = 30 } },
    .{ .field = "bar_top_gap", .val = .{ .i = 6 } },
    .{ .field = "bar_lr_gap", .val = .{ .i = 6 } },
    .{ .field = "bar_corner_radius", .val = .{ .i = 10 } },
    .{ .field = "bar_battery_interval", .val = .{ .i = 300000 } },
    .{ .field = "bar_tray_icon_size", .val = .{ .i = 20 } },
    .{ .field = "bar_clock_format", .val = .{ .str = "%H:%M" } },
    .{ .field = "bar_bg_color", .val = .{ .color = .{ hexF32(0x1a), hexF32(0x1b), hexF32(0x26), 0.9 } } },
    .{ .field = "font_desc", .nest = "bardata", .val = .{ .str = "monospace Bold 13" } },
    .{ .field = "fg_color", .nest = "bardata", .val = .{ .color = .{ hexF32(0xc0), hexF32(0xca), hexF32(0xf5), 1.0 } } },
    .{ .field = "bg_color", .nest = "bardata", .val = .{ .color = .{ hexF32(0x1d), hexF32(0x20), hexF32(0x21), 1.0 } } },
    .{ .field = "focus_fg_color", .nest = "bardata", .val = .{ .color = .{ hexF32(0x1d), hexF32(0x20), hexF32(0x21), 1.0 } } },
    .{ .field = "focus_bg_color", .nest = "bardata", .val = .{ .color = .{ hexF32(0x7a), hexF32(0xa2), hexF32(0xf7), 1.0 } } },
    .{ .field = "border_color", .nest = "bardata", .val = .{ .color = .{ hexF32(0x3b), hexF32(0x42), hexF32(0x61), 1.0 } } },
    .{ .field = "border_width", .nest = "bardata", .val = .{ .i = 0 } },
    .{ .field = "corner_radius", .nest = "bardata", .val = .{ .i = 5 } },
    .{ .field = "padding_x", .nest = "bardata", .val = .{ .i = 6 } },
    .{ .field = "padding_y", .nest = "bardata", .val = .{ .i = 0 } },
    // window colors
    .{ .field = "rootcolor", .val = .{ .color = .{ hexF32(0x32), hexF32(0x32), hexF32(0x32), 1.0 } } },
    .{ .field = "bordercolor", .val = .{ .color = .{ hexF32(0x44), hexF32(0x44), hexF32(0x44), 1.0 } } },
    .{ .field = "dropcolor", .val = .{ .color = .{ hexF32(0xd5), hexF32(0x89), hexF32(0x9d), 0.5 } } },
    .{ .field = "splitcolor", .val = .{ .color = .{ hexF32(0xeb), hexF32(0x44), hexF32(0x1e), 1.0 } } },
    .{ .field = "focuscolor", .val = .{ .color = .{ hexF32(0xc6), hexF32(0x6b), hexF32(0x25), 1.0 } } },
    .{ .field = "maximizescreencolor", .val = .{ .color = .{ hexF32(0x89), hexF32(0xaa), hexF32(0x61), 1.0 } } },
    .{ .field = "urgentcolor", .val = .{ .color = .{ hexF32(0xad), hexF32(0x40), hexF32(0x1f), 1.0 } } },
    .{ .field = "scratchpadcolor", .val = .{ .color = .{ hexF32(0x51), hexF32(0x6c), hexF32(0x93), 1.0 } } },
    .{ .field = "globalcolor", .val = .{ .color = .{ hexF32(0xb1), hexF32(0x53), hexF32(0xa7), 1.0 } } },
    .{ .field = "overlaycolor", .val = .{ .color = .{ hexF32(0x14), hexF32(0xa5), hexF32(0x7c), 1.0 } } },
};

// ---------------------------------------------------------------------------
// clamps
// ---------------------------------------------------------------------------

const ClampKind = enum { int, float };

const Clamp = struct {
    field: [:0]const u8,
    nest: ?[:0]const u8 = null,
    kind: ClampKind,
    min: f64,
    max: f64,
};

const clamps = [_]Clamp{
    .{ .field = "animations", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "layer_animations", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "tag_animation_direction", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "animation_fade_in", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "animation_fade_out", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "zoom_initial_ratio", .kind = .float, .min = 0.1, .max = 1.0 },
    .{ .field = "zoom_end_ratio", .kind = .float, .min = 0.1, .max = 1.0 },
    .{ .field = "fadein_begin_opacity", .kind = .float, .min = 0.0, .max = 1.0 },
    .{ .field = "fadeout_begin_opacity", .kind = .float, .min = 0.0, .max = 1.0 },
    .{ .field = "animation_duration_move", .kind = .int, .min = 0, .max = 50000 },
    .{ .field = "animation_duration_open", .kind = .int, .min = 0, .max = 50000 },
    .{ .field = "animation_duration_tag", .kind = .int, .min = 0, .max = 50000 },
    .{ .field = "animation_duration_close", .kind = .int, .min = 0, .max = 50000 },
    .{ .field = "animation_duration_focus", .kind = .int, .min = 0, .max = 50000 },
    .{ .field = "scroller_default_proportion", .kind = .float, .min = 0.1, .max = 1.0 },
    .{ .field = "scroller_default_proportion_single", .kind = .float, .min = 0.1, .max = 1.0 },
    .{ .field = "scroller_ignore_proportion_single", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "scroller_focus_center", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "scroller_prefer_center", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "scroller_prefer_overspread", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "edge_scroller_pointer_focus", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "edge_scroller_focus_allow_speed", .kind = .float, .min = 0.0, .max = 1000.0 },
    .{ .field = "scroller_structs", .kind = .int, .min = 0, .max = 1000 },
    .{ .field = "default_mfact", .kind = .float, .min = 0.1, .max = 0.9 },
    .{ .field = "default_nmaster", .kind = .int, .min = 1, .max = 1000 },
    .{ .field = "tag_num", .kind = .int, .min = 1, .max = c.tag_num_MAX },
    .{ .field = "tag_gather", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "center_master_overspread", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "center_when_single_stack", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "new_is_master", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "dwindle_vsplit", .kind = .int, .min = 0, .max = 2 },
    .{ .field = "dwindle_hsplit", .kind = .int, .min = 0, .max = 2 },
    .{ .field = "dwindle_preserve_split", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "dwindle_smart_split", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "dwindle_smart_resize", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "dwindle_drop_simple_split", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "dwindle_manual_split", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "dwindle_split_ratio", .kind = .float, .min = 0.05, .max = 0.95 },
    .{ .field = "hotarea_size", .kind = .int, .min = 1, .max = 1000 },
    .{ .field = "hotarea_corner", .kind = .int, .min = 0, .max = 3 },
    .{ .field = "enable_hotarea", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "hotarea_disable_on_fullscreen", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "overviewgappi", .kind = .int, .min = 0, .max = 1000 },
    .{ .field = "overviewgappo", .kind = .int, .min = 0, .max = 1000 },
    .{ .field = "overcircle_center_ratio", .kind = .float, .min = 0.1, .max = 0.9 },
    .{ .field = "xwayland_persistence", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "xwayland_ignore_scale", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "syncobj_enable", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "drag_tile_to_tile", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "drag_tile_small", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "allow_tearing", .kind = .int, .min = 0, .max = 2 },
    .{ .field = "hdr_depth", .kind = .int, .min = 0, .max = 2 },
    .{ .field = "allow_shortcuts_inhibit", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "disable_middle_paste", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "allow_lock_transparent", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "auto_reload_config", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "axis_bind_apply_timeout", .kind = .int, .min = 0, .max = 1000 },
    .{ .field = "focus_on_activate", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "idleinhibit_ignore_visible", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "idleinhibit_when_fullscreen", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "sloppyfocus", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "warpcursor", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "drag_corner", .kind = .int, .min = 0, .max = 4 },
    .{ .field = "drag_warp_cursor", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "enable_border_resize", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "border_resize_size", .kind = .int, .min = 0, .max = 50 },
    .{ .field = "focus_cross_monitor", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "focusdir_only_zone_overlap", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "exchange_cross_monitor", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "scratchpad_cross_monitor", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "focus_cross_tag", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "view_current_to_back", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "enable_floating_snap", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "float_full_to_top", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "snap_distance", .kind = .int, .min = 0, .max = 99999 },
    .{ .field = "cursor_size", .kind = .int, .min = 4, .max = 512 },
    .{ .field = "no_border_when_single", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "no_radius_when_single", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "monocle_no_border", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "monocle_no_gap", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "cursor_hide_timeout", .kind = .int, .min = 0, .max = 36000 },
    .{ .field = "cursor_hide_on_keypress", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "single_scratchpad", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "repeat_rate", .kind = .int, .min = 1, .max = 1000 },
    .{ .field = "repeat_delay", .kind = .int, .min = 1, .max = 20000 },
    .{ .field = "numlockon", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "disable_trackpad", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "touch_enable", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "touch_enable_mouse_emulation", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "tap_to_click", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "tap_and_drag", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "drag_lock", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "trackpad_natural_scrolling", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "swipe_min_threshold", .kind = .int, .min = 1, .max = 1000 },
    .{ .field = "gesture_live", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "gesture_swipe_distance", .kind = .int, .min = 32, .max = 4096 },
    .{ .field = "gesture_swipe_cancel_ratio", .kind = .float, .min = 0.05, .max = 0.95 },
    .{ .field = "gesture_swipe_min_speed_to_force", .kind = .float, .min = 0.0, .max = std.math.inf(f64) },
    .{ .field = "mouse_natural_scrolling", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "mouse_accel_profile", .kind = .int, .min = 0, .max = 2 },
    .{ .field = "mouse_accel_speed", .kind = .float, .min = -1.0, .max = 1.0 },
    .{ .field = "trackpad_accel_profile", .kind = .int, .min = 0, .max = 2 },
    .{ .field = "trackpad_accel_speed", .kind = .float, .min = -1.0, .max = 1.0 },
    .{ .field = "send_events_mode", .kind = .int, .min = 0, .max = 2 },
    .{ .field = "button_map", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "mouse_left_handed", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "mouse_middle_button_emulation", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "mouse_scroll_method", .kind = .int, .min = 0, .max = 4 },
    .{ .field = "mouse_scroll_button", .kind = .int, .min = 272, .max = 279 },
    .{ .field = "mouse_click_method", .kind = .int, .min = 0, .max = 2 },
    .{ .field = "mouse_send_events_mode", .kind = .int, .min = 0, .max = 2 },
    .{ .field = "trackpad_left_handed", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "trackpad_middle_button_emulation", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "trackpad_disable_while_typing", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "trackpad_scroll_method", .kind = .int, .min = 0, .max = 4 },
    .{ .field = "trackpad_scroll_button", .kind = .int, .min = 272, .max = 279 },
    .{ .field = "trackpad_click_method", .kind = .int, .min = 0, .max = 2 },
    .{ .field = "trackpad_send_events_mode", .kind = .int, .min = 0, .max = 2 },
    .{ .field = "axis_scroll_factor", .kind = .float, .min = 0.1, .max = 10.0 },
    .{ .field = "trackpad_scroll_factor", .kind = .float, .min = 0.1, .max = 10.0 },
    .{ .field = "gappih", .kind = .int, .min = 0, .max = 1000 },
    .{ .field = "gappiv", .kind = .int, .min = 0, .max = 1000 },
    .{ .field = "gappoh", .kind = .int, .min = 0, .max = 1000 },
    .{ .field = "gappov", .kind = .int, .min = 0, .max = 1000 },
    .{ .field = "scratchpad_width_ratio", .kind = .float, .min = 0.1, .max = 1.0 },
    .{ .field = "scratchpad_height_ratio", .kind = .float, .min = 0.1, .max = 1.0 },
    .{ .field = "special_dim", .kind = .float, .min = 0.0, .max = 1.0 },
    .{ .field = "special_gappih", .kind = .int, .min = 0, .max = 1000 },
    .{ .field = "special_gappiv", .kind = .int, .min = 0, .max = 1000 },
    .{ .field = "special_gappoh", .kind = .int, .min = 0, .max = 1000 },
    .{ .field = "special_gappov", .kind = .int, .min = 0, .max = 1000 },
    .{ .field = "borderpx", .kind = .int, .min = 0, .max = 200 },
    .{ .field = "group_bar_height", .kind = .int, .min = 0, .max = 500 },
    .{ .field = "tab_bar_height", .kind = .int, .min = 0, .max = 500 },
    .{ .field = "always_show_group_bar", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "group_bar_close_button_enable", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "group_bar_button_size", .kind = .int, .min = 4, .max = 64 },
    .{ .field = "group_bar_button_margin", .kind = .int, .min = 0, .max = 50 },
    .{ .field = "smartgaps", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "blur", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "blur_layer", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "blur_optimized", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "border_radius", .kind = .int, .min = 0, .max = 100 },
    .{ .field = "num_passes", .nest = "blur_params", .kind = .int, .min = 0, .max = 10 },
    .{ .field = "radius", .nest = "blur_params", .kind = .int, .min = 0, .max = 100 },
    .{ .field = "noise", .nest = "blur_params", .kind = .float, .min = 0, .max = 1 },
    .{ .field = "brightness", .nest = "blur_params", .kind = .float, .min = 0, .max = 1 },
    .{ .field = "contrast", .nest = "blur_params", .kind = .float, .min = 0, .max = 1 },
    .{ .field = "saturation", .nest = "blur_params", .kind = .float, .min = 0, .max = 1 },
    .{ .field = "shadows", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "shadow_only_floating", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "layer_shadows", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "shadows_size", .kind = .int, .min = 0, .max = 100 },
    .{ .field = "shadows_blur", .kind = .int, .min = 0, .max = 100 },
    .{ .field = "shadows_position_x", .kind = .int, .min = -1000, .max = 1000 },
    .{ .field = "shadows_position_y", .kind = .int, .min = -1000, .max = 1000 },
    .{ .field = "focused_opacity", .kind = .float, .min = 0.0, .max = 1.0 },
    .{ .field = "unfocused_opacity", .kind = .float, .min = 0.0, .max = 1.0 },
    .{ .field = "dim_enable", .kind = .int, .min = 0, .max = 1 },
    .{ .field = "border_width", .nest = "groupbardata", .kind = .int, .min = 0, .max = 100 },
    .{ .field = "corner_radius", .nest = "groupbardata", .kind = .int, .min = 0, .max = 100 },
    .{ .field = "padding_x", .nest = "groupbardata", .kind = .int, .min = 0, .max = 100 },
    .{ .field = "padding_y", .nest = "groupbardata", .kind = .int, .min = 0, .max = 100 },
    .{ .field = "border_width", .nest = "tabbardata", .kind = .int, .min = 0, .max = 100 },
    .{ .field = "corner_radius", .nest = "tabbardata", .kind = .int, .min = 0, .max = 100 },
    .{ .field = "padding_x", .nest = "tabbardata", .kind = .int, .min = 0, .max = 100 },
    .{ .field = "padding_y", .nest = "tabbardata", .kind = .int, .min = 0, .max = 100 },
    .{ .field = "border_width", .nest = "jumplabeldata", .kind = .int, .min = 0, .max = 100 },
    .{ .field = "corner_radius", .nest = "jumplabeldata", .kind = .int, .min = 0, .max = 100 },
    .{ .field = "padding_x", .nest = "jumplabeldata", .kind = .int, .min = 0, .max = 100 },
    .{ .field = "padding_y", .nest = "jumplabeldata", .kind = .int, .min = 0, .max = 100 },
};

// ---------------------------------------------------------------------------
// target helpers + assignment
// ---------------------------------------------------------------------------

fn Target(comptime nest: ?[:0]const u8, comptime field: [:0]const u8) type {
    if (nest) |n| {
        const Holder = @TypeOf(@field(@as(c.Config, undefined), n));
        return *@TypeOf(@field(@as(Holder, undefined), field));
    }
    return *@TypeOf(@field(@as(c.Config, undefined), field));
}

fn target(comptime nest: ?[:0]const u8, comptime field: [:0]const u8) Target(nest, field) {
    if (comptime nest) |n| {
        const holder = &@field(&c.config, n);
        return &@field(holder, field);
    }
    return &@field(&c.config, field);
}

fn setVal(dst: anytype, comptime v: Val) void {
    const T = @TypeOf(dst.*);
    switch (v) {
        .i => |x| {
            if (T == i32 or T == c_int) {
                dst.* = @intCast(x);
            } else if (T == u32 or T == c_uint) {
                dst.* = @truncate(@as(u64, @bitCast(x)));
            } else if (T == f32) {
                dst.* = @floatFromInt(x);
            } else if (T == f64) {
                dst.* = @floatFromInt(x);
            } else {
                @compileError("unsupported default int target: " ++ @typeName(T));
            }
        },
        .f => |x| {
            if (T == f32) {
                dst.* = @floatCast(x);
            } else if (T == f64) {
                dst.* = x;
            } else {
                @compileError("unsupported default float target: " ++ @typeName(T));
            }
        },
        .color => |arr| {
            if (T == [4]f32) {
                dst.* = arr;
            } else {
                @compileError("unsupported default color target: " ++ @typeName(T));
            }
        },
        .curve => |arr| {
            if (T == [4]f64) {
                dst.* = arr;
            } else {
                @compileError("unsupported default curve target: " ++ @typeName(T));
            }
        },
        .str => |s| {
            dst.* = strdup(s);
        },
    }
}

fn truncToI32(x: f32) i32 {
    if (std.math.isNan(x))
        return std.math.minInt(i32);
    const clamped = @min(@max(x, -2147483648.0), 2147483647.0);
    return @intFromFloat(clamped);
}

fn clampI(v: i64, lo: i64, hi: i64) i64 {
    return if (v < lo) lo else if (v > hi) hi else v;
}

fn applyClamp(comptime row: Clamp) void {
    const dst = target(row.nest, row.field);
    const T = @TypeOf(dst.*);
    if (comptime row.kind == .int) {
        const lo: i64 = @intFromFloat(row.min);
        const hi: i64 = @intFromFloat(row.max);
        if (T == f32) {
            const cl = clampI(@as(i64, truncToI32(dst.*)), lo, hi);
            dst.* = @floatFromInt(cl);
        } else if (T == i32 or T == c_int) {
            dst.* = @intCast(clampI(@as(i64, dst.*), lo, hi));
        } else if (T == u32 or T == c_uint) {
            const cl = clampI(@as(i64, dst.*), lo, hi);
            dst.* = @truncate(@as(u64, @bitCast(cl)));
        } else {
            @compileError("unsupported int clamp target: " ++ @typeName(T));
        }
    } else {
        if (T == f32) {
            const lo: f32 = @floatCast(row.min);
            const hi: f32 = @floatCast(row.max);
            const v = dst.*;
            dst.* = if (v < lo) lo else if (v > hi) hi else v;
        } else if (T == f64) {
            const v = dst.*;
            dst.* = if (v < row.min) row.min else if (v > row.max) row.max else v;
        } else {
            @compileError("unsupported float clamp target: " ++ @typeName(T));
        }
    }
}

// ---------------------------------------------------------------------------
// exported functions (same symbols as the C twins)
// ---------------------------------------------------------------------------

export fn set_value_default() callconv(.c) void {
    inline for (defaults) |row| {
        setVal(target(row.nest, row.field), row.val);
    }
}

export fn update_global_var() callconv(.c) void {
    // (1 << tag_num) - 1; tag_num is clamped to 1..tag_num_MAX before this
    // runs. Truncate the shift count to 5 bits like x86 shift semantics.
    const n: u5 = @truncate(@as(u32, @bitCast(c.config.tag_num)));
    c.server.tagmask = @intCast((@as(u32, 1) << n) -% 1);
}

export fn override_config() callconv(.c) void {
    inline for (clamps) |row| {
        applyClamp(row);
    }
    update_global_var();
}

export fn apply_option_expanded(
    config: *c.Config,
    key: [*:0]u8,
    value: [*:0]u8,
    line_number: c_int,
) callconv(.c) bool {
    const expanded = expand_config_variables(value);
    const ok = parse_option(config, key, expanded orelse value, line_number);
    free(@ptrCast(expanded));
    return ok;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: see tests/option_defaults_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_parse_key: [128]u8;
extern var stub_parse_value: [256]u8;
extern var stub_parse_calls: c_int;
extern var stub_parse_ok: c_int;
extern var stub_expansion: [256]u8;
extern var stub_expansion_enabled: c_int;

fn cspan(p: [*]const u8) []const u8 {
    return std.mem.sliceTo(@as([*:0]const u8, @ptrCast(p)), 0);
}

test "set_value_default applies the defaults table" {
    c.config = std.mem.zeroes(c.Config);
    set_value_default();

    try testing.expect(c.config.animations == 1);
    try testing.expect(c.config.animation_type_open == -1);
    try testing.expect(c.config.tag_animation_direction == 1); // HORIZONTAL
    try testing.expect(c.config.tag_num == 9);
    try testing.expect(c.config.default_mfact == 0.55);
    try testing.expect(c.config.hotarea_corner == 2); // BOTTOM_LEFT
    try testing.expect(c.config.log_level == 1); // WLR_ERROR
    try testing.expect(c.config.hdr_depth == 2); // BIT_DEPTH_10
    try testing.expect(c.config.allow_tearing == 0);
    try testing.expect(c.config.gesture_swipe_min_speed_to_force == 10.0);
    try testing.expect(c.config.group_bar_height == 33);
    try testing.expect(c.config.repeat_rate == 25);
    try testing.expect(c.config.mouse_scroll_button == 274);
    try testing.expect(c.config.send_events_mode == c.LIBINPUT_CONFIG_SEND_EVENTS_ENABLED);
    try testing.expect(c.config.blur_params.radius == 5.0);
    try testing.expect(c.config.shadows_blur == 15.0);
    try testing.expect(c.config.animation_curve_opafadeout[0] == 0.5);
    try testing.expect(c.config.animation_curve_move[1] == 1.0);
    try testing.expect(c.config.rootcolor[0] == hexF32(0x32));
    try testing.expect(c.config.dim_unfocused_color[3] == hexF32(0x55));
    try testing.expect(c.config.group_bar_button_color[0] == hexF32(0xad));
    try testing.expect(c.config.jumplabeldata.padding_x == 10);
    try testing.expect(c.config.bardata.padding_x == 6);

    try testing.expectEqualStrings("%H:%M", cspan(c.config.bar_clock_format));
    try testing.expectEqualStrings("monospace Bold 13", cspan(c.config.bardata.font_desc));
}

test "override_config clamps in C order" {
    c.config = std.mem.zeroes(c.Config);

    c.config.tag_num = 100;
    c.config.default_mfact = 0.05;
    c.config.default_nmaster = 0;
    c.config.dwindle_vsplit = 5;
    c.config.blur_params.radius = 1000.0;
    c.config.shadows_blur = 1e9;
    c.config.shadows_position_x = -5000;
    c.config.gesture_swipe_cancel_ratio = 0.02;
    c.config.gesture_swipe_min_speed_to_force = -5.0;
    c.config.mouse_scroll_button = 100;
    c.config.cursor_size = 2;
    c.config.axis_scroll_factor = 0.01;
    c.config.cursor_hide_timeout = 99999;
    c.config.repeat_rate = 0;
    c.config.blur_params.noise = 5.0;
    c.config.groupbardata.padding_x = 500;
    c.config.enable_floating_snap = 7;

    override_config();

    try testing.expect(c.config.tag_num == 31);
    try testing.expect(c.config.default_mfact == 0.1);
    try testing.expect(c.config.default_nmaster == 1);
    try testing.expect(c.config.dwindle_vsplit == 2);
    try testing.expect(c.config.blur_params.radius == 100.0);
    try testing.expect(c.config.shadows_blur == 100.0);
    try testing.expect(c.config.shadows_position_x == -1000);
    try testing.expect(c.config.gesture_swipe_cancel_ratio == 0.05);
    try testing.expect(c.config.gesture_swipe_min_speed_to_force == 0.0);
    try testing.expect(c.config.mouse_scroll_button == 272);
    try testing.expect(c.config.cursor_size == 4);
    try testing.expect(c.config.axis_scroll_factor == 0.1);
    try testing.expect(c.config.cursor_hide_timeout == 36000);
    try testing.expect(c.config.repeat_rate == 1);
    try testing.expect(c.config.blur_params.noise == 1.0);
    try testing.expect(c.config.groupbardata.padding_x == 100);
    try testing.expect(c.config.enable_floating_snap == 1);
    // update_global_var ran at the end
    try testing.expect(c.server.tagmask == 0x7FFFFFFF);
}

test "override_config upper edges for floats and doubles" {
    c.config = std.mem.zeroes(c.Config);

    c.config.gesture_swipe_cancel_ratio = 0.99;
    c.config.mouse_accel_speed = 5.0;
    c.config.edge_scroller_focus_allow_speed = 5000.0;
    c.config.zoom_initial_ratio = 2.0;

    override_config();

    try testing.expect(c.config.gesture_swipe_cancel_ratio == 0.95);
    try testing.expect(c.config.mouse_accel_speed == 1.0);
    try testing.expect(c.config.edge_scroller_focus_allow_speed == 1000.0);
    try testing.expect(c.config.zoom_initial_ratio == 1.0);
}

test "update_global_var derives the tag mask" {
    c.config = std.mem.zeroes(c.Config);

    c.config.tag_num = 9;
    update_global_var();
    try testing.expect(c.server.tagmask == 511);

    c.config.tag_num = 31;
    update_global_var();
    try testing.expect(c.server.tagmask == 0x7FFFFFFF);

    c.config.tag_num = 0;
    update_global_var();
    try testing.expect(c.server.tagmask == 0);
}

test "apply_option_expanded falls back to the original value" {
    var cfg: c.Config = std.mem.zeroes(c.Config);
    stub_parse_calls = 0;
    stub_expansion_enabled = 0;
    stub_parse_ok = 1;

    var key: [1:0]u8 = .{0};
    var value: [5:0]u8 = undefined;
    @memcpy(value[0..5], "plain");
    value[5] = 0;
    try testing.expect(apply_option_expanded(&cfg, &key, &value, 3));
    try testing.expectEqual(@as(c_int, 1), stub_parse_calls);
    try testing.expectEqualStrings("plain", cspan(&stub_parse_value));
}

test "apply_option_expanded passes the expanded string and frees it" {
    var cfg: c.Config = std.mem.zeroes(c.Config);
    stub_parse_calls = 0;
    stub_expansion_enabled = 1;
    @memcpy(stub_expansion[0..9], "expanded!");
    stub_expansion[9] = 0;
    stub_parse_ok = 0;

    var key: [1:0]u8 = .{0};
    var value: [6:0]u8 = undefined;
    @memcpy(value[0..6], "${var}");
    value[6] = 0;
    try testing.expect(!apply_option_expanded(&cfg, &key, &value, 4));
    try testing.expectEqual(@as(c_int, 1), stub_parse_calls);
    try testing.expectEqualStrings("expanded!", cspan(&stub_parse_value));
}
