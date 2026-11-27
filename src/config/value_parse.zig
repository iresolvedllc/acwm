//! Port of src/config/value_parse.c (strangler-fig Phase 4).
//!
//! Exports the same C symbols as the C twin (which is removed from the
//! compositor build); option_defs.c and friends call these unchanged.
//!
//! Enum values mirror include/acwm/{config/parse.h,config/preset.h,
//! dispatch/bind.h,common/server.h}. Keep them in sync when bumping upstream.
//!
//! Tests live at the bottom; they need the C stub in
//! src/config/value_parse_test_stub.c (variadic log functions cannot be
//! defined in Zig).

const std = @import("std");
const Io = std.Io;

// ---------------------------------------------------------------------------
// C interop
// ---------------------------------------------------------------------------

const WLR_ERROR: c_uint = 1;
const WLR_INFO: c_uint = 2;

extern fn acwm_error_impl(log: bool, verbosity: c_uint, file: [*:0]const u8, line: c_int, fmt: [*:0]const u8, ...) callconv(.c) void;
extern fn acwm_error_untagged(verbosity: c_uint, fmt: [*:0]const u8, ...) callconv(.c) void;
/// C-side shim (src/manage/misc.c): returns server.tagmask.
extern fn acwm_current_tagmask() callconv(.c) c_uint;

extern "c" fn strtol(nptr: [*:0]const u8, endptr: ?*?[*:0]u8, base: c_int) c_long;
extern "c" fn strtod(nptr: [*:0]const u8, endptr: *?[*:0]u8) f64;
extern "c" fn strtok(?[*:0]u8, delim: [*:0]const u8) ?[*:0]u8;
extern "c" fn strtok_r(?[*:0]u8, delim: [*:0]const u8, saveptr: *?[*:0]u8) ?[*:0]u8;
extern "c" fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern "c" fn free(ptr: ?*anyopaque) void;

const c_strdup = strdup;

// ---------------------------------------------------------------------------
// Constants (mirror the C headers)
// ---------------------------------------------------------------------------

const NUM_TYPE_MINUS: u32 = 0; // enum { NUM_TYPE_MINUS, NUM_TYPE_PLUS, NUM_TYPE_DEFAULT };
const NUM_TYPE_PLUS: u32 = 1;
const NUM_TYPE_DEFAULT: u32 = 2;

const ANIM_TYPE_UNSET: i32 = -1; // enum { ANIM_TYPE_UNSET = -1, ANIM_TYPE_NONE, ... };
const ANIM_TYPE_NONE: i32 = 0;
const ANIM_TYPE_FADE: i32 = 1;
const ANIM_TYPE_SLIDE: i32 = 2;
const ANIM_TYPE_ZOOM: i32 = 3;
const ANIM_TYPE_UNKNOWN: i32 = 4;

const PREV: i32 = 0; // enum { PREV, NEXT };
const NEXT: i32 = 1;
const OVERCIRCLE_PREV: i32 = PREV; // OVERCIRCLE_PREV = PREV, ...
const OVERCIRCLE_NEXT: i32 = NEXT;
const OVERCIRCLE_CURRENT_PREV: i32 = 2;
const OVERCIRCLE_CURRENT_NEXT: i32 = 3;

const MON_PREV: i32 = -1; // enum { MON_PREV = -1, MON_NEXT = -2 };
const MON_NEXT: i32 = -2;

const FORCE: i32 = 0; // enum { FORCE, UNFORCE };
const UNFORCE: i32 = 1;

const UNFOLD: i32 = 0; // enum { UNFOLD, FOLD, INVALIDFOLD };
const FOLD: i32 = 1;
const INVALIDFOLD: i32 = 2;

const UP: i32 = 0; // enum { UP, DOWN, LEFT, RIGHT, UNDIR, ALLDIR };
const DOWN: i32 = 1;
const LEFT: i32 = 2;
const RIGHT: i32 = 3;
const UNDIR: i32 = 4;
const ALLDIR: i32 = 5;

const TAG0_MASK: u32 = @as(u32, 1) << 31; // #define TAG0_MASK (1U << 31)
const tag_num_MAX: usize = 31; // preset.h

// ---------------------------------------------------------------------------
// ctype helpers (C locale semantics, ASCII)
// ---------------------------------------------------------------------------

fn isspaceChar(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == 0x0b or c == 0x0c or c == '\r';
}

fn isprintChar(c: u8) bool {
    return c >= 0x20 and c < 0x7f;
}

fn lowerChar(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + ('a' - 'A') else c;
}

// ---------------------------------------------------------------------------
// exported functions (same symbols as the C twin)
// ---------------------------------------------------------------------------

/// Helper function to trim whitespace from start and end of a string
export fn trim_whitespace(str: ?[*:0]u8) void {
    const s = str orelse return;
    if (s[0] == 0)
        return;

    var start: usize = 0;
    while (isspaceChar(s[start]))
        start += 1;

    var end: usize = std.mem.len(s) - 1;
    while (end > start and isspaceChar(s[end]))
        end -= 1;

    s[end + 1] = 0;

    if (start != 0) {
        if (end >= start) {
            const len = end - start + 1;
            std.mem.copyForwards(u8, s[0..len], s[start .. start + len]);
            s[len] = 0;
        } else {
            // the string was entirely whitespace: start walked past `end`
            s[0] = 0;
        }
    }
}

export fn strip_quotes(str: ?[*:0]u8) void {
    const s = str orelse return;
    const len = std.mem.len(s);
    if (len >= 2 and ((s[0] == '"' and s[len - 1] == '"') or
        (s[0] == '\'' and s[len - 1] == '\'')))
    {
        s[len - 1] = 0;
        std.mem.copyForwards(u8, s[0 .. len - 1], s[1..len]);
        trim_whitespace(s);
    }
}

/// remove comment, support double quote inside "#xxx" or '#xxx' not be
/// treated as comment
export fn remove_comment(str: ?[*:0]u8) void {
    const s = str orelse return;
    var quote: u8 = 0;
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {
        if (quote == 0) {
            if (s[i] == '\'' or s[i] == '"') {
                quote = s[i];
            } else if (s[i] == '#' and i > 0 and isspaceChar(s[i - 1])) {
                s[i] = 0;
                return;
            }
        } else if (s[i] == quote) {
            quote = 0;
        }
    }
}

export fn parse_double_array(
    input: [*:0]const u8,
    output: [*]f64,
    max_count: i32,
) callconv(.c) i32 {
    const dup = c_strdup(input) orelse return -1;
    defer free(dup);

    const out_slice = output[0..@intCast(max_count)];
    @memset(out_slice, 0);

    var count: i32 = 0;
    var token = strtok(dup, ",");
    while (token != null and count < max_count) : (token = strtok(null, ",")) {
        trim_whitespace(token);
        var endptr: ?[*:0]u8 = null;
        const val = strtod(token.?, &endptr);
        const ep = endptr.?;
        if (ep == token.? or ep[0] != 0) {
            acwm_error_impl(false, WLR_ERROR, "value_parse.zig", 0, "Invalid number in array: \x1b[1m\x1b[31m%s\x1b[0m\n", token.?);
            return -1;
        }
        if (val < 0.0) {
            acwm_error_impl(false, WLR_ERROR, "value_parse.zig", 0, "Invalid number in array (must be non-negative): \x1b[1m\x1b[31m%s\x1b[0m\n", token.?);
            return -1;
        }
        output[@intCast(count)] = val;
        count += 1;
    }
    return count;
}

/// Removes invisible characters from the string (including \r, \n, spaces).
/// Returns a pointer into the original buffer (same contract as C).
export fn sanitize_string(str: [*:0]u8) callconv(.c) [*:0]u8 {
    var i: usize = 0;
    while (str[i] != 0 and !isprintChar(str[i]))
        i += 1;
    var result = str + i;

    var end: usize = std.mem.len(result) - 1;
    while (end > 0 and !isprintChar(result[end]))
        end -= 1;
    result[end + 1] = 0;
    return result;
}

/// Helper: checks whether a string starts with the given prefix
/// (case-insensitive).
export fn starts_with_ignore_case(str: [*:0]const u8, prefix: [*:0]const u8) callconv(.c) bool {
    var i: usize = 0;
    while (prefix[i] != 0) : (i += 1) {
        if (lowerChar(str[i]) != lowerChar(prefix[i]))
            return false;
    }
    return true;
}

export fn report_config_line_error(
    full_path: [*:0]const u8,
    line_number: c_int,
    line: [*:0]const u8,
) callconv(.c) void {
    acwm_error_untagged(WLR_INFO, "\x1b[1;31m╰─\x1b[1;33m[Index]\x1b[0m \x1b[1;36m%s\x1b[0m:\x1b[1;35m%d\x1b[0m\n   \x1b[1;36m╰─\x1b[0;33m%s\x1b[0m\n\n", full_path, line_number, line);
}

export fn convert_hex_to_rgba(color: [*]f32, hex: u32) callconv(.c) void {
    color[0] = @as(f32, @floatFromInt((hex >> 24) & 0xFF)) / 255.0;
    color[1] = @as(f32, @floatFromInt((hex >> 16) & 0xFF)) / 255.0;
    color[2] = @as(f32, @floatFromInt((hex >> 8) & 0xFF)) / 255.0;
    color[3] = @as(f32, @floatFromInt(hex & 0xFF)) / 255.0;
}

export fn parse_num_type(str: [*:0]u8) callconv(.c) u32 {
    return switch (str[0]) {
        '-' => NUM_TYPE_MINUS,
        '+' => NUM_TYPE_PLUS,
        else => NUM_TYPE_DEFAULT,
    };
}

export fn animation_type_from_string(value: ?[*:0]const u8) callconv(.c) i32 {
    const v = value orelse return ANIM_TYPE_UNSET;
    if (v[0] == 0)
        return ANIM_TYPE_UNSET;
    if (std.mem.eql(u8, std.mem.span(v), "none"))
        return ANIM_TYPE_NONE;
    if (std.mem.eql(u8, std.mem.span(v), "fade"))
        return ANIM_TYPE_FADE;
    if (std.mem.eql(u8, std.mem.span(v), "slide"))
        return ANIM_TYPE_SLIDE;
    if (std.mem.eql(u8, std.mem.span(v), "zoom"))
        return ANIM_TYPE_ZOOM;
    return ANIM_TYPE_UNKNOWN;
}

/// Lowercases at most buf.len - 1 chars (matching the C buffers' behavior).
fn lower_bounded(str: [*:0]const u8, buf: []u8) []const u8 {
    var i: usize = 0;
    while (str[i] != 0 and i < buf.len - 1) : (i += 1) {
        buf[i] = lowerChar(str[i]);
    }
    buf[i] = 0;
    return buf[0..i];
}

export fn parse_circle_direction(str: [*:0]const u8) callconv(.c) i32 {
    var buf: [10]u8 = undefined;
    const lowered = lower_bounded(str, &buf);
    return if (std.mem.eql(u8, lowered, "next")) NEXT else PREV;
}

export fn parse_overcircle_direction(str: [*:0]const u8) callconv(.c) i32 {
    var buf: [16]u8 = undefined;
    const lowered = lower_bounded(str, &buf);
    if (std.mem.eql(u8, lowered, "next"))
        return OVERCIRCLE_NEXT;
    if (std.mem.eql(u8, lowered, "current_next"))
        return OVERCIRCLE_CURRENT_NEXT;
    if (std.mem.eql(u8, lowered, "current_prev"))
        return OVERCIRCLE_CURRENT_PREV;
    return OVERCIRCLE_PREV;
}

export fn parse_direction(str: [*:0]const u8) callconv(.c) i32 {
    var buf: [10]u8 = undefined;
    const lowered = lower_bounded(str, &buf);
    if (std.mem.eql(u8, lowered, "up"))
        return UP;
    if (std.mem.eql(u8, lowered, "down"))
        return DOWN;
    if (std.mem.eql(u8, lowered, "left"))
        return LEFT;
    if (std.mem.eql(u8, lowered, "right"))
        return RIGHT;
    if (std.mem.eql(u8, lowered, "alldir"))
        return ALLDIR;
    return UNDIR;
}

export fn parse_monitor_arg(str: [*:0]const u8) callconv(.c) i32 {
    const dir = parse_direction(str);

    var buf: [10]u8 = undefined;
    const lowered = lower_bounded(str, &buf);
    if (std.mem.eql(u8, lowered, "next"))
        return MON_NEXT;
    if (std.mem.eql(u8, lowered, "prev"))
        return MON_PREV;
    return dir;
}

export fn parse_color(hex_str: [*:0]const u8) callconv(.c) i64 {
    var endptr: ?[*:0]u8 = null;
    const n = strtol(hex_str, &endptr, 16);
    if (endptr.?[0] != 0)
        return -1;
    return @intCast(n);
}

export fn parse_force(str: [*:0]const u8) callconv(.c) i32 {
    var buf: [10]u8 = undefined;
    const lowered = lower_bounded(str, &buf);
    if (std.mem.eql(u8, lowered, "unforce"))
        return UNFORCE;
    if (std.mem.eql(u8, lowered, "force"))
        return FORCE;
    return UNFORCE;
}

export fn parse_fold_state(str: [*:0]const u8) callconv(.c) i32 {
    var buf: [10]u8 = undefined;
    const lowered = lower_bounded(str, &buf);
    if (std.mem.eql(u8, lowered, "fold"))
        return FOLD;
    if (std.mem.eql(u8, lowered, "unfold"))
        return UNFOLD;
    return INVALIDFOLD;
}

/// atoi: strtol base 10, no error reporting.
fn atoi_c(s: [*:0]const u8) i32 {
    return @intCast(strtol(s, null, 10));
}

export fn parse_tag_mask(str: [*:0]u8) callconv(.c) u32 {
    var mask: u32 = 0;

    if (strdup(str)) |arg_copy| {
        defer free(arg_copy);
        var saveptr: ?[*:0]u8 = null;
        var token = strtok_r(arg_copy, "|", &saveptr);
        while (token != null) : (token = strtok_r(null, "|", &saveptr)) {
            trim_whitespace(token);
            const num = atoi_c(token.?);
            if (num == 0 and std.mem.eql(u8, std.mem.span(token.?), "0")) {
                mask |= TAG0_MASK;
            } else if (num > 0 and @as(usize, @intCast(num)) <= tag_num_MAX) {
                mask |= @as(u32, 1) << @intCast(num - 1);
            }
        }
    }

    // tag0 and normal tags are exclusive; keep tag0 when mixed
    const tagmask = acwm_current_tagmask();
    if ((mask & TAG0_MASK) != 0 and (mask & tagmask) != 0)
        mask = TAG0_MASK;

    if (mask != 0)
        return mask;
    return @bitCast(atoi_c(str));
}

// ---------------------------------------------------------------------------
// tests (stub-backed: see value_parse_test_stub.c)
// ---------------------------------------------------------------------------

extern var acwm_test_tagmask: c_uint;

const testing = std.testing;

fn cstr(s: []const u8) [:0]u8 {
    const b = testing.allocator.allocSentinel(u8, s.len, 0) catch unreachable;
    @memcpy(b[0..s.len], s);
    return b;
}

test "trim_whitespace" {
    const a = cstr("  hello world  ");
    defer testing.allocator.free(a);
    trim_whitespace(a);
    try testing.expectEqualStrings("hello world", std.mem.sliceTo(a, 0));
    try testing.expectEqual(@as(usize, 11), std.mem.sliceTo(a, 0).len);

    const b = cstr("     ");
    defer testing.allocator.free(b);
    trim_whitespace(b);
    try testing.expectEqual(@as(usize, 0), std.mem.sliceTo(b, 0).len);

    const c = cstr("");
    defer testing.allocator.free(c);
    trim_whitespace(c);
    try testing.expectEqual(@as(usize, 0), c.len);

    const d = cstr("node");
    defer testing.allocator.free(d);
    trim_whitespace(d);
    try testing.expectEqualStrings("node", d[0..4]);

    trim_whitespace(null); // no-op
}

test "strip_quotes" {
    const a = cstr("\"quoted\"");
    defer testing.allocator.free(a);
    strip_quotes(a);
    try testing.expectEqualStrings("quoted", std.mem.sliceTo(a, 0));

    const b = cstr("'single'");
    defer testing.allocator.free(b);
    strip_quotes(b);
    try testing.expectEqualStrings("single", std.mem.sliceTo(b, 0));

    const c = cstr("unquoted");
    defer testing.allocator.free(c);
    strip_quotes(c);
    try testing.expectEqualStrings("unquoted", std.mem.sliceTo(c, 0));
}

test "remove_comment" {
    // note: C semantics keep the trailing space before the cut point
    const a = cstr("option=value # comment");
    defer testing.allocator.free(a);
    remove_comment(a);
    try testing.expectEqualStrings("option=value ", std.mem.sliceTo(a, 0));

    const b = cstr("key=\"a # b\" # tail");
    defer testing.allocator.free(b);
    remove_comment(b);
    try testing.expectEqualStrings("key=\"a # b\" ", std.mem.sliceTo(b, 0));

    const c = cstr("no-comment-here # x");
    defer testing.allocator.free(c);
    remove_comment(c);
    try testing.expectEqualStrings("no-comment-here ", std.mem.sliceTo(c, 0));

    const d = cstr("lead# nostrip");
    defer testing.allocator.free(d);
    remove_comment(d);
    try testing.expectEqualStrings("lead# nostrip", std.mem.sliceTo(d, 0));
}

test "starts_with_ignore_case" {
    const s = cstr("ZoomBlur");
    defer testing.allocator.free(s);
    const p1 = cstr("zoom");
    defer testing.allocator.free(p1);
    const p2 = cstr("fade");
    defer testing.allocator.free(p2);
    try testing.expect(starts_with_ignore_case(s, p1));
    try testing.expect(!starts_with_ignore_case(s, p2));
}

test "parse_color" {
    const a = cstr("ff00ff00");
    defer testing.allocator.free(a);
    try testing.expectEqual(@as(i64, 0xff00ff00), parse_color(a));
    const b = cstr("0xff");
    defer testing.allocator.free(b);
    try testing.expectEqual(@as(i64, 0xff), parse_color(b));
    const c = cstr("zzz");
    defer testing.allocator.free(c);
    try testing.expectEqual(@as(i64, -1), parse_color(c));
    const d = cstr("12x");
    defer testing.allocator.free(d);
    try testing.expectEqual(@as(i64, -1), parse_color(d));
}

test "parse_direction and monitor arg" {
    const up = cstr("UP");
    defer testing.allocator.free(up);
    try testing.expectEqual(UP, parse_direction(up));
    const all = cstr("AllDir");
    defer testing.allocator.free(all);
    try testing.expectEqual(ALLDIR, parse_direction(all));
    const junk = cstr("nonsense");
    defer testing.allocator.free(junk);
    try testing.expectEqual(UNDIR, parse_direction(junk));
    const next = cstr("Next");
    defer testing.allocator.free(next);
    try testing.expectEqual(MON_NEXT, parse_monitor_arg(next));
    const left = cstr("left");
    defer testing.allocator.free(left);
    try testing.expectEqual(LEFT, parse_monitor_arg(left));
}

test "parse_force and fold and num_type" {
    const f = cstr("Force");
    defer testing.allocator.free(f);
    try testing.expectEqual(FORCE, parse_force(f));
    const uf = cstr("whatever");
    defer testing.allocator.free(uf);
    try testing.expectEqual(UNFORCE, parse_force(uf));
    const fold = cstr("FOLD");
    defer testing.allocator.free(fold);
    try testing.expectEqual(FOLD, parse_fold_state(fold));
    const bad = cstr("x");
    defer testing.allocator.free(bad);
    try testing.expectEqual(INVALIDFOLD, parse_fold_state(bad));
    const plus = cstr("+5");
    defer testing.allocator.free(plus);
    try testing.expectEqual(NUM_TYPE_PLUS, parse_num_type(plus));
    const minus = cstr("-3");
    defer testing.allocator.free(minus);
    try testing.expectEqual(NUM_TYPE_MINUS, parse_num_type(minus));
    const plain = cstr("3");
    defer testing.allocator.free(plain);
    try testing.expectEqual(NUM_TYPE_DEFAULT, parse_num_type(plain));
}

test "animation_type_from_string" {
    const none = cstr("none");
    defer testing.allocator.free(none);
    try testing.expectEqual(ANIM_TYPE_NONE, animation_type_from_string(none));
    const slide = cstr("slide");
    defer testing.allocator.free(slide);
    try testing.expectEqual(ANIM_TYPE_SLIDE, animation_type_from_string(slide));
    const empty = cstr("");
    defer testing.allocator.free(empty);
    try testing.expectEqual(ANIM_TYPE_UNSET, animation_type_from_string(empty));
    try testing.expectEqual(ANIM_TYPE_UNSET, animation_type_from_string(null));
    const junk = cstr("weird");
    defer testing.allocator.free(junk);
    try testing.expectEqual(ANIM_TYPE_UNKNOWN, animation_type_from_string(junk));
}

test "convert_hex_to_rgba" {
    var rgba: [4]f32 = undefined;
    convert_hex_to_rgba(&rgba, 0x11223344);
    try testing.expectApproxEqAbs(@as(f32, 0x11) / 255.0, rgba[0], 0.0001);
    try testing.expectApproxEqAbs(@as(f32, 0x22) / 255.0, rgba[1], 0.0001);
    try testing.expectApproxEqAbs(@as(f32, 0x33) / 255.0, rgba[2], 0.0001);
    try testing.expectApproxEqAbs(@as(f32, 0x44) / 255.0, rgba[3], 0.0001);
}

test "parse_tag_mask" {
    acwm_test_tagmask = ((@as(c_uint, 1)) << 8) - 1; // 8 tags configured

    const a = cstr("1|3");
    defer testing.allocator.free(a);
    try testing.expectEqual(@as(u32, 0b101), parse_tag_mask(a));
    const b = cstr("  5  | 8 ");
    defer testing.allocator.free(b);
    try testing.expectEqual(@as(u32, 0x80 | 0x10), parse_tag_mask(b));
    const zero = cstr("0");
    defer testing.allocator.free(zero);
    try testing.expectEqual(TAG0_MASK, parse_tag_mask(zero));
    const mixed = cstr("0|2");
    defer testing.allocator.free(mixed);
    try testing.expectEqual(TAG0_MASK, parse_tag_mask(mixed));
    const junk = cstr("");
    defer testing.allocator.free(junk);
    try testing.expectEqual(@as(u32, 0), parse_tag_mask(junk));
    // out-of-range tags are dropped
    const big = cstr("99|2");
    defer testing.allocator.free(big);
    try testing.expectEqual(@as(u32, 0b10), parse_tag_mask(big));
    // bare numeric fallback
    const num = cstr("4");
    defer testing.allocator.free(num);
    try testing.expectEqual(@as(u32, 0b1000), parse_tag_mask(num));
}

test "parse_circle and overcircle" {
    const next = cstr("NEXT");
    defer testing.allocator.free(next);
    try testing.expectEqual(NEXT, parse_circle_direction(next));
    const other = cstr("x");
    defer testing.allocator.free(other);
    try testing.expectEqual(PREV, parse_circle_direction(other));
    const cn = cstr("current_next");
    defer testing.allocator.free(cn);
    try testing.expectEqual(OVERCIRCLE_CURRENT_NEXT, parse_overcircle_direction(cn));
    const cp = cstr("CURRENT_PREV");
    defer testing.allocator.free(cp);
    try testing.expectEqual(OVERCIRCLE_CURRENT_PREV, parse_overcircle_direction(cp));
    const junk = cstr("zz");
    defer testing.allocator.free(junk);
    try testing.expectEqual(OVERCIRCLE_PREV, parse_overcircle_direction(junk));
}
