//! Port of the idle + session/general option group from
//! src/config/option_defs.c (strangler-fig Phase 4, slice 2).
//!
//! Exports one C symbol: acwm_config_apply_session_option(), called by
//! parse_option() ahead of its strcmp chain (guarded by
//! ACWM_ZIG_SESSION_OPTION, defined only in the Zig build). Covers the
//! contiguous chain block focus_on_activate .. warp_cursor — focus policy,
//! numlock, the idle trio (+ its command strings) and sloppy-focus/warp.
//! The window-rule key idle_inhibit_when_focus is NOT here (rule parser).
//!
//! Return contract identical to the bar group: 1 applied, -1 applied with an
//! invalid value (none today), 0 not ours. C parity notes:
//!   - focus_on_activate and numlockon are uint32_t fields assigned from
//!     atoi() — negative values wrap via @bitCast like the C conversion
//!   - idle_after goes through CLAMP_INT in the int32 domain (0..86400)
//!   - idle_command/resume_command strdup over the previous value
//!
//! Tests live at the bottom; no C stub is needed (libc + cc types only).

const std = @import("std");
const c = @import("cc");

extern "c" fn atoi(nptr: [*:0]const u8) c_int;
extern "c" fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern "c" fn free(ptr: ?*anyopaque) void;

// ---------------------------------------------------------------------------
// option table
// ---------------------------------------------------------------------------

const Kind = enum {
    /// atoi -> int32_t Config field, no clamp.
    int_raw,
    /// atoi -> uint32_t Config field; negative wraps like C (see header).
    uint_raw,
    /// CLAMP_INT(atoi, min, max) -> int32_t Config field.
    int_clamp,
    /// strdup over a Config char * (frees the old value first).
    string,
};

const Row = struct {
    key: [:0]const u8,
    kind: Kind,
    field: [:0]const u8,
    min: i32 = 0,
    max: i32 = 0,
};

/// The 9 keys of the focus_on_activate..warp_cursor block, in C order.
const rows = [_]Row{
    .{ .key = "focus_on_activate", .kind = .uint_raw, .field = "focus_on_activate" },
    .{ .key = "idle_inhibit_ignore_visible", .kind = .int_raw, .field = "idleinhibit_ignore_visible" },
    .{ .key = "idle_inhibit_when_fullscreen", .kind = .int_raw, .field = "idleinhibit_when_fullscreen" },
    .{ .key = "idle_after", .kind = .int_clamp, .field = "idle_after", .min = 0, .max = 86400 },
    .{ .key = "idle_command", .kind = .string, .field = "idle_command" },
    .{ .key = "resume_command", .kind = .string, .field = "resume_command" },
    .{ .key = "sloppy_focus", .kind = .int_raw, .field = "sloppyfocus" },
    .{ .key = "warp_cursor", .kind = .int_raw, .field = "warpcursor" },
    .{ .key = "numlock_on", .kind = .uint_raw, .field = "numlockon" },
};

// ---------------------------------------------------------------------------
// apply helpers
// ---------------------------------------------------------------------------

/// Replicates the CLAMP_INT macro: clamp in int32 domain.
fn clampInt(x: i32, comptime min: i32, comptime max: i32) i32 {
    return if (x < min) min else if (x > max) max else x;
}

fn setStringSlot(slot: anytype, value: [*:0]const u8) void {
    if (slot.* != null)
        free(@ptrCast(@constCast(slot.*)));
    slot.* = strdup(value);
}

fn applyRow(cfg: *c.Config, comptime row: Row, value: [*:0]const u8) c_int {
    switch (comptime row.kind) {
        .int_raw => {
            @field(cfg, row.field) = atoi(value);
            return 1;
        },
        .uint_raw => {
            @field(cfg, row.field) = @bitCast(atoi(value));
            return 1;
        },
        .int_clamp => {
            @field(cfg, row.field) = clampInt(atoi(value), row.min, row.max);
            return 1;
        },
        .string => {
            setStringSlot(&@field(cfg, row.field), value);
            return 1;
        },
    }
}

/// C entry point (see file header for the contract).
export fn acwm_config_apply_session_option(
    config: ?*c.Config,
    key: [*:0]const u8,
    value: [*:0]const u8,
    line_number: c_int,
) callconv(.c) c_int {
    _ = line_number;
    const cfg = config orelse return 0;
    const k = std.mem.span(key);

    inline for (rows) |row| {
        if (std.mem.eql(u8, k, row.key))
            return applyRow(cfg, row, value);
    }
    return 0;
}

// ---------------------------------------------------------------------------
// tests (no stub needed)
// ---------------------------------------------------------------------------

const testing = std.testing;

fn apply(cfg: *c.Config, key: [:0]const u8, value: [:0]const u8) c_int {
    return acwm_config_apply_session_option(cfg, key, value, 3);
}

test "tri-state dispatch: session key, foreign keys, rule-only key" {
    var config: c.Config = std.mem.zeroes(c.Config);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "idle_after", "60"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "bar_enable", "1"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "repeat_rate", "25"));
    // window-rule key only — must not be captured here
    try testing.expectEqual(@as(c_int, 0), apply(&config, "idle_inhibit_when_focus", "1"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "idle_afterx", "1"));
}

test "int fields store atoi verbatim" {
    var config: c.Config = std.mem.zeroes(c.Config);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "idle_inhibit_ignore_visible", "1"));
    try testing.expectEqual(@as(i32, 1), config.idleinhibit_ignore_visible);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "idle_inhibit_when_fullscreen", "-1"));
    try testing.expectEqual(@as(i32, -1), config.idleinhibit_when_fullscreen);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "sloppy_focus", "2"));
    try testing.expectEqual(@as(i32, 2), config.sloppyfocus);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "warp_cursor", "1"));
    try testing.expectEqual(@as(i32, 1), config.warpcursor);
}

test "uint fields wrap negatives like the C implicit conversion" {
    var config: c.Config = std.mem.zeroes(c.Config);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "focus_on_activate", "1"));
    try testing.expectEqual(@as(u32, 1), config.focus_on_activate);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "focus_on_activate", "-1"));
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), config.focus_on_activate);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "numlock_on", "1"));
    try testing.expectEqual(@as(u32, 1), config.numlockon);
}

test "idle_after clamps to 0..86400" {
    var config: c.Config = std.mem.zeroes(c.Config);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "idle_after", "-5"));
    try testing.expectEqual(@as(i32, 0), config.idle_after);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "idle_after", "90000"));
    try testing.expectEqual(@as(i32, 86400), config.idle_after);
    try testing.expectEqual(@as(c_int, 1), apply(&config, "idle_after", "300"));
    try testing.expectEqual(@as(i32, 300), config.idle_after);
}

test "command strings free the old value and store the new" {
    var config: c.Config = std.mem.zeroes(c.Config);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "idle_command", "swayidle -w"));
    try testing.expectEqualStrings(
        "swayidle -w",
        std.mem.span(@as([*:0]const u8, @ptrCast(config.idle_command))),
    );
    // overwrite exercises the free-old path
    try testing.expectEqual(@as(c_int, 1), apply(&config, "idle_command", "hypridle"));
    try testing.expectEqualStrings(
        "hypridle",
        std.mem.span(@as([*:0]const u8, @ptrCast(config.idle_command))),
    );

    try testing.expectEqual(@as(c_int, 1), apply(&config, "resume_command", "acwm-msg dispatch resume"));
    try testing.expectEqualStrings(
        "acwm-msg dispatch resume",
        std.mem.span(@as([*:0]const u8, @ptrCast(config.resume_command))),
    );
}

test "every table row dispatches through the C entry" {
    var config: c.Config = std.mem.zeroes(c.Config);

    for (rows) |row| {
        const r = acwm_config_apply_session_option(&config, row.key, "5", 0);
        if (r != 1) {
            std.debug.print("row failed to dispatch: {s}\n", .{row.key});
            return error.RowFailedToDispatch;
        }
    }
    try testing.expectEqual(@as(usize, 9), rows.len);
}
