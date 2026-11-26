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
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/inotify.h>
#include <sys/stat.h>
#include <libinput.h>
#include <sys/socket.h>
#include <unistd.h>
#include <wayland-server-core.h>
#include <wlr/backend/libinput.h>
#include <wlr/interfaces/wlr_buffer.h>
#include <wlr/interfaces/wlr_keyboard.h>
#include <wlr/types/wlr_cursor.h>
#include <wlr/types/wlr_ext_foreign_toplevel_list_v1.h>
#include <wlr/types/wlr_layer_shell_v1.h>
#include <wlr/types/wlr_keyboard.h>
#include <wlr/types/wlr_keyboard_group.h>
#include <wlr/types/wlr_xcursor_manager.h>
#include <wlr/util/log.h>

#include "acwm/config/parse.h"
#include "acwm/config/internal.h"
#include "acwm/config/preset.h"
#include "acwm/common/input-event-codes.h"
#include "acwm/common/util.h"
#include "acwm/common/server.h"
#include "acwm/input/device.h"
#include "acwm/input/keyboard.h"
#include "acwm/input/pointer.h"
#include "acwm/layout/layout.h"
#include "acwm/ipc/ipc.h"
#include "acwm/animation/client.h"
#include "acwm/manage/client.h"
#include "acwm/manage/layer.h"
#include "acwm/manage/monitor.h"
#include "acwm/switcher/switcher.h"

#endif
