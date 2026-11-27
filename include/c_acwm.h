/*
 * Translation unit for the Zig build-system translate-c step.
 *
 * Zig 0.17 removed @cImport; Zig sources that need C types (the Phase 4
 * config ports, which read/write the global `Config config`) import the
 * translate-c output of this header instead ("cc" module in build.zig).
 * Not used by C code.
 */
#ifndef __ACWM_C_TRANSLATION_UNIT_H__
#define __ACWM_C_TRANSLATION_UNIT_H__

/* wlroots exposes unstable APIs behind this guard; the compositor already
 * defines it project-wide via cflags. */
#define WLR_USE_UNSTABLE 1

/* libc surfaces needed by the ported config modules (error_store uses
 * stat/fcntl/unistd; others use stdlib/string). Kept here so the translated
 * declarations — including struct stat — stay authoritative. */
#include <cjson/cJSON.h>
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/inotify.h>
#include <sys/stat.h>
#include <sys/resource.h>
#include <libinput.h>
#include <sys/socket.h>
#ifdef HAVE_TRAY
#include <systemd/sd-bus.h>
#endif
#include <unistd.h>
#include <wayland-server-core.h>
#include <wlr/backend/libinput.h>
#include <wlr/backend/headless.h>
#include <wlr/backend/multi.h>
#include <wlr/backend/wayland.h>
#include <wlr/backend.h>
#include <wlr/interfaces/wlr_buffer.h>
#include <wlr/interfaces/wlr_keyboard.h>
#include <wlr/types/wlr_cursor.h>
#include <drm_fourcc.h>
#include <wlr/render/wlr_renderer.h>
#include <wlr/types/wlr_drm_lease_v1.h>
#include <wlr/types/wlr_ext_foreign_toplevel_list_v1.h>
#include <wlr/types/wlr_ext_workspace_v1.h>
#include <wlr/types/wlr_ext_image_capture_source_v1.h>
#include <wlr/types/wlr_ext_image_copy_capture_v1.h>
#include <wlr/types/wlr_idle_inhibit_v1.h>
#include <wlr/types/wlr_data_device.h>
#include <wlr/types/wlr_primary_selection.h>
#include <wlr/types/wlr_seat.h>
#include <wlr/types/wlr_session_lock_v1.h>
#include <wlr/types/wlr_xdg_decoration_v1.h>
#include <wlr/types/wlr_fractional_scale_v1.h>
#include <wlr/types/wlr_foreign_toplevel_management_v1.h>
#include <wlr/types/wlr_xdg_activation_v1.h>
#include <wlr/types/wlr_tearing_control_v1.h>
#include <wlr/types/wlr_pointer_constraints_v1.h>
#include <wlr/types/wlr_alpha_modifier_v1.h>
#include <wlr/types/wlr_color_management_v1.h>
#include <wlr/types/wlr_color_representation_v1.h>
#include <wlr/types/wlr_linux_drm_syncobj_v1.h>
#include <wlr/types/wlr_presentation_time.h>
#include <wlr/types/wlr_pointer_gestures_v1.h>
#include <wlr/types/wlr_relative_pointer_v1.h>
#include <wlr/types/wlr_virtual_pointer_v1.h>
#include <wlr/util/edges.h>
#include <wlr/util/region.h>
#include <wlr/xcursor.h>
#include <wlr/types/wlr_cursor_shape_v1.h>
#include <wlr/types/wlr_subcompositor.h>
#include <wlr/xwayland.h>
#include <xcb/xcb.h>
#include <xcb/randr.h>
#include <wlr/types/wlr_layer_shell_v1.h>
#include <wlr/types/wlr_output_power_management_v1.h>
#include <wlr/types/wlr_data_control_v1.h>
#include <wlr/types/wlr_drm.h>
#include <wlr/types/wlr_export_dmabuf_v1.h>
#include <wlr/types/wlr_ext_data_control_v1.h>
#include <wlr/types/wlr_fixes.h>
#include <wlr/types/wlr_gamma_control_v1.h>
#include <wlr/types/wlr_idle_notify_v1.h>
#include <wlr/types/wlr_input_method_v2.h>
#include <wlr/types/wlr_keyboard_shortcuts_inhibit_v1.h>
#include <wlr/types/wlr_output_layout.h>
#include <wlr/types/wlr_output_power_management_v1.h>
#include <wlr/types/wlr_presentation_time.h>
#include <wlr/types/wlr_primary_selection_v1.h>
#include <wlr/types/wlr_relative_pointer_v1.h>
#include <wlr/types/wlr_screencopy_v1.h>
#include <wlr/types/wlr_server_decoration.h>
#include <wlr/types/wlr_single_pixel_buffer_v1.h>
#include <wlr/types/wlr_viewporter.h>
#include <wlr/types/wlr_virtual_keyboard_v1.h>
#include <wlr/types/wlr_virtual_pointer_v1.h>
#include <wlr/types/wlr_xdg_foreign_registry.h>
#include <wlr/types/wlr_xdg_foreign_v1.h>
#include <wlr/types/wlr_xdg_foreign_v2.h>
#include <wlr/types/wlr_xdg_output_v1.h>
#include <wlr/types/wlr_xdg_decoration_v1.h>
#include <wlr/types/wlr_text_input_v3.h>
#include <wlr/render/allocator.h>
#include <scenefx/render/fx_renderer/fx_renderer.h>
#include <wlr/types/wlr_output_management_v1.h>
#include <wlr/types/wlr_keyboard.h>
#include <wlr/types/wlr_keyboard_group.h>
#include <wlr/types/wlr_keyboard_shortcuts_inhibit_v1.h>
#include <wlr/types/wlr_virtual_keyboard_v1.h>
#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/types/wlr_touch.h>
#include <wlr/types/wlr_switch.h>
#include <wlr/types/wlr_tablet_pad.h>
#include <wlr/types/wlr_tablet_tool.h>
#include <wlr/types/wlr_xcursor_manager.h>
#include <wlr/util/log.h>

#include "acwm/config/parse.h"
#include "acwm/config/internal.h"
#include "acwm/config/preset.h"
#include "acwm/config/watcher.h"
#include "acwm/config/error_nag.h"
#include "acwm/config/error_store.h"
#include "acwm/input/trackpad.h"
#include "acwm/animation/common.h"
#include "acwm/common/input-event-codes.h"
#include "acwm/common/log.h"
#include "acwm/common/util.h"
#include "acwm/common/scene_node.h"
#include "acwm/bar/bar.h"
#include "acwm/common/server.h"
#include "acwm/input/device.h"
#include "acwm/input/keyboard.h"
#include "acwm/ext-protocol/text-input.h"
#include "acwm/ext-protocol/tearing.h"
#include "acwm/ext-protocol/xdg-activation.h"
#include "acwm/ext-protocol/foreign-toplevel.h"
#include "acwm/ext-protocol/ext-workspace.h"
#include "acwm/ext-protocol/hdr.h"
#include "acwm/ext-protocol/xdg-output.h"
#include "acwm/input/pointer.h"
#include "acwm/input/switch.h"
#include "acwm/input/touch.h"
#include "acwm/input/tablet.h"
#include "acwm/layout/layout.h"
#include "acwm/ipc/ipc.h"
#include "acwm/animation/client.h"
#include "acwm/manage/client.h"
#include "acwm/manage/layer.h"
#include "acwm/manage/monitor.h"
#include "acwm/manage/misc.h"
#include "acwm/manage/xwayland_primary.h"
#include "acwm/switcher/switcher.h"

#endif
