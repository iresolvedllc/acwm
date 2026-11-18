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

#include "acwm/config/parse.h"
#include "acwm/config/internal.h"

#endif
