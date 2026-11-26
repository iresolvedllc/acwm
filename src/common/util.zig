//! Port of the non-variadic helpers in src/common/util.c
//! (strangler-fig Phase 5, common slice 1, slice 44).
//!
//! Zig cannot define C-variadic functions, so die() and string_printf()
//! permanently remain C; the rest of util.c is exported here with the C
//! twins guarded by ACWM_ZIG_UTIL.

const std = @import("std");
const c = @import("cc");

const WlList = c.struct_wl_list;

extern fn die(fmt: [*:0]const u8, ...) callconv(.c) noreturn;

extern "c" fn calloc(nmemb: usize, size: usize) ?*anyopaque;
extern "c" fn malloc(size: usize) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn strlen(str: [*:0]const u8) usize;
extern "c" fn strcat(dest: [*:0]u8, src: [*:0]const u8) [*:0]u8;
extern "c" fn memcpy(dest: ?*anyopaque, src: ?*const anyopaque, n: usize) ?*anyopaque;
extern "c" fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
extern "c" fn perror(s: [*:0]const u8) void;
extern "c" fn clock_gettime(clk_id: c_int, tp: *c.struct_timespec) c_int;
extern "c" fn wl_list_insert(list: [*c]WlList, elm: [*c]WlList) void;
extern "c" fn wl_list_remove(elm: [*c]WlList) void;
extern "c" fn wl_list_init(list: [*c]WlList) void;

const PCRE2_CODE = opaque {};
extern "c" fn pcre2_compile_8(pattern: [*:0]const u8, length: usize, options: u32, errcode: *c_int, erroffset: *usize, ctx: ?*anyopaque) ?*PCRE2_CODE;
extern "c" fn pcre2_get_error_message_8(errcode: c_int, buf: [*]u8, buf_size: usize) c_int;
extern "c" fn pcre2_match_data_create_from_pattern_8(code: *PCRE2_CODE, ctx: ?*anyopaque) ?*anyopaque;
extern "c" fn pcre2_match_8(code: *PCRE2_CODE, subject: [*]const u8, length: usize, startoffset: usize, options: u32, match_data: ?*anyopaque, mctx: ?*anyopaque) c_int;
extern "c" fn pcre2_match_data_free_8(md: ?*anyopaque) void;
extern "c" fn pcre2_code_free_8(code: *PCRE2_CODE) void;

const PCRE2_ZERO_TERMINATED: usize = std.math.maxInt(usize);
const PCRE2_UTF: u32 = 0x00080000;
const WLR_ERROR: c_uint = @intCast(c.WLR_ERROR);

extern fn acwm_error_impl(
    log: bool,
    verbosity: c_uint,
    file: [*:0]const u8,
    line: c_int,
    fmt: [*:0]const u8,
    ...) callconv(.c) void;

fn span(p: [*:0]const u8) []const u8 {
    return std.mem.span(p);
}

export fn ecalloc(nmemb: usize, size: usize) callconv(.c) ?*anyopaque {
    return calloc(nmemb, size) orelse die("calloc:");
}

fn utf8Strcpy(dst: []u8, src: [*:0]const u8, size: usize) void {
    var len: usize = 0;
    while (len < size - 1 and src[len] != 0) : (len += 1) {}
    while (len > 0 and (src[len] & 0xc0) == 0x80)
        len -= 1;
    @memcpy(dst[0..len], src[0..len]);
    dst[len] = 0;
}

export fn wayland_string_set(dst: *c.struct_wayland_string, src: [*c]const u8) callconv(.c) [*:0]const u8 {
    const s: [*:0]const u8 = if (src != null) @ptrCast(src) else "";
    utf8Strcpy(&dst.data, s, dst.data.len);
    return @ptrCast(&dst.data);
}

export fn fd_set_nonblock(fd: i32) callconv(.c) i32 {
    const flags = fcntl(fd, c.F_GETFL);
    if (flags < 0) {
        perror("fcntl(F_GETFL):");
        return -1;
    }
    if (fcntl(fd, c.F_SETFL, flags | c.O_NONBLOCK) < 0) {
        perror("fcntl(F_SETFL):");
        return -1;
    }
    return 0;
}

export fn regex_match(pattern: [*c]const u8, str: [*c]const u8) callconv(.c) i32 {
    if (pattern == null or str == null)
        return 0;

    var errnum: c_int = 0;
    var erroffset: usize = 0;
    const re = pcre2_compile_8(@ptrCast(pattern), PCRE2_ZERO_TERMINATED, PCRE2_UTF, &errnum, &erroffset, null) orelse {
        var errbuf: [256]u8 = undefined;
        _ = pcre2_get_error_message_8(errnum, &errbuf, errbuf.len);
        acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "PCRE2 error: %s at offset %zu\n", @as([*:0]const u8, @ptrCast(&errbuf)), erroffset);
        return 0;
    };

    const match_data = pcre2_match_data_create_from_pattern_8(re, null);
    const subject: [*]const u8 = @ptrCast(str);
    const ret = pcre2_match_8(re, subject, strlen(@ptrCast(str)), 0, 0, match_data, null);

    pcre2_match_data_free_8(match_data);
    pcre2_code_free_8(re);
    return if (ret >= 0) 1 else 0;
}

export fn wl_list_append(list: *WlList, object: *WlList) callconv(.c) void {
    wl_list_insert(list.prev, object);
}

export fn get_now_in_ms() callconv(.c) u32 {
    var now: c.struct_timespec = undefined;
    _ = clock_gettime(c.CLOCK_MONOTONIC, &now);
    return timespec_to_ms(&now);
}

export fn timespec_to_ms(ts: *c.struct_timespec) callconv(.c) u32 {
    return @as(u32, @intCast(ts.tv_sec)) * 1000 +
        @as(u32, @intCast(@divTrunc(ts.tv_nsec, 1000000)));
}

fn joinStringsInner(arr: [*c][*c]u8, suffix: [*:0]const u8, sep: [*:0]const u8) ?[*:0]u8 {
    if (arr == null or arr[0] == null) {
        const empty: [*:0]u8 = @ptrCast(malloc(1) orelse return null);
        empty[0] = 0;
        return empty;
    }

    const sep_len = strlen(sep);
    const suffix_len = strlen(suffix);
    var total_len: usize = 0;
    var count: usize = 0;
    var i: usize = 0;
    while (arr[i] != null) : (i += 1) {
        total_len += strlen(@ptrCast(arr[i])) + suffix_len;
        count += 1;
    }
    if (count > 0)
        total_len += sep_len * (count - 1);

    const result: [*:0]u8 = @ptrCast(malloc(total_len + 1) orelse return null);
    result[0] = 0;
    i = 0;
    while (arr[i] != null) : (i += 1) {
        if (i > 0)
            _ = strcat(result, sep);
        _ = strcat(result, @ptrCast(arr[i]));
        if (suffix_len > 0)
            _ = strcat(result, suffix);
    }
    return result;
}

export fn join_strings(arr: [*c][*c]u8, sep: [*:0]const u8) callconv(.c) ?[*:0]u8 {
    return joinStringsInner(arr, "", sep);
}

export fn join_strings_with_suffix(arr: [*c][*c]u8, suffix: [*:0]const u8, sep: [*:0]const u8) callconv(.c) ?[*:0]u8 {
    return joinStringsInner(arr, suffix, sep);
}

export fn wl_list_swap(l1: *WlList, l2: *WlList) callconv(.c) void {
    const tmp1_prev: *WlList = @ptrCast(l1.prev);
    const tmp2_prev: *WlList = @ptrCast(l2.prev);
    const tmp1_next: *WlList = @ptrCast(l1.next);
    const tmp2_next: *WlList = @ptrCast(l2.next);

    if (l1.next == l2) {
        l1.next = l2.next;
        l1.prev = l2;
        l2.next = l1;
        l2.prev = tmp1_prev;
        tmp1_prev.next = l2;
        tmp2_next.prev = l1;
    } else if (l2.next == l1) {
        l2.next = l1.next;
        l2.prev = l1;
        l1.next = l2;
        l1.prev = tmp2_prev;
        tmp2_prev.next = l1;
        tmp1_next.prev = l2;
    } else {
        l2.next = tmp1_next;
        l2.prev = tmp1_prev;
        l1.next = tmp2_next;
        l1.prev = tmp2_prev;
        tmp1_prev.next = l2;
        tmp1_next.prev = l2;
        tmp2_prev.next = l1;
        tmp2_next.prev = l1;
    }
}

export fn wl_list_safe_reinsert_prev(l1: *WlList, l2: *WlList) callconv(.c) void {
    if (l1 == l2 or l1.prev == l2)
        return;
    wl_list_remove(l2);
    wl_list_init(l2);
    wl_list_insert(l1.prev, l2);
}

export fn wl_list_safe_reinsert_next(l1: *WlList, l2: *WlList) callconv(.c) void {
    if (l1 == l2 or l1.next == l2)
        return;
    wl_list_remove(l2);
    wl_list_init(l2);
    wl_list_insert(l1, l2);
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/util_stub.c; real pcre2/wayland)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_error_calls: c_int;

extern "c" fn pipe(fds: *[2]c_int) c_int;
extern "c" fn close(fd: c_int) c_int;

fn listInit(head: *WlList) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

fn listInsert(head: *WlList, link: *WlList) void {
    link.next = head.next;
    link.prev = @ptrCast(head);
    head.next.*.prev = @ptrCast(link);
    head.next = @ptrCast(link);
}

fn collect(head: *WlList, out: []*WlList) usize {
    var n: usize = 0;
    var pos = head.next;
    while (@intFromPtr(pos) != @intFromPtr(head) and n < out.len) : (pos = pos.*.next) {
        out[n] = @ptrCast(pos);
        n += 1;
    }
    return n;
}

test "ecalloc returns zeroed memory" {
    const raw = ecalloc(4, 4) orelse return error.OutOfMemory;
    defer free(raw);
    const bytes: [*]u8 = @ptrCast(raw);
    for (0..16) |i|
        try testing.expectEqual(@as(u8, 0), bytes[i]);
}

test "wayland_string_set copies and avoids cutting UTF-8 sequences" {
    var dst: c.struct_wayland_string = std.mem.zeroes(c.struct_wayland_string);
    _ = wayland_string_set(&dst, "hello");
    try testing.expectEqualStrings("hello", std.mem.sliceTo(&dst.data, 0));

    _ = wayland_string_set(&dst, null);
    try testing.expectEqualStrings("", std.mem.sliceTo(&dst.data, 0));

    const N = @sizeOf(@TypeOf(dst.data));
    var src: [N + 2]u8 = undefined;
    @memset(src[0 .. N + 1], 'a');
    src[N - 2] = 0x80;
    src[N - 1] = 0x80;
    src[N] = 0;
    _ = wayland_string_set(&dst, @ptrCast(&src));

    const out_len = std.mem.len(@as([*:0]const u8, @ptrCast(&dst.data)));
    try testing.expect(out_len < N - 1);
    try testing.expect((dst.data[out_len - 1] & 0xc0) != 0x80);
    try testing.expectEqual(@as(u8, 0), dst.data[out_len]);
}

test "fd_set_nonblock enables O_NONBLOCK" {
    var fds: [2]c_int = undefined;
    try testing.expectEqual(@as(c_int, 0), pipe(&fds));
    defer _ = close(fds[0]);
    defer _ = close(fds[1]);

    try testing.expectEqual(@as(i32, 0), fd_set_nonblock(fds[0]));
    const flags = fcntl(fds[0], c.F_GETFL);
    try testing.expect((flags & c.O_NONBLOCK) != 0);
}

test "regex_match handles UTF-8 patterns and invalid input" {
    try testing.expectEqual(@as(i32, 1), regex_match("a.*b", "axxxb"));
    try testing.expectEqual(@as(i32, 0), regex_match("^abc$", "abcd"));
    try testing.expectEqual(@as(i32, 0), regex_match(null, "x"));
    try testing.expectEqual(@as(i32, 0), regex_match("a", null));

    stub_error_calls = 0;
    try testing.expectEqual(@as(i32, 0), regex_match("(", "x"));
    try testing.expectEqual(@as(c_int, 1), stub_error_calls);

    try testing.expectEqual(@as(i32, 1), regex_match("café", "café"));
}

test "list append/swap/safe-reinsert preserve order" {
    var head: WlList = undefined;
    var a: WlList = undefined;
    var b: WlList = undefined;
    var c_node: WlList = undefined;
    listInit(&head);

    wl_list_append(&head, &a);
    wl_list_append(&head, &b);
    wl_list_append(&head, &c_node);

    var order: [8]*WlList = undefined;
    try testing.expectEqual(@as(usize, 3), collect(&head, &order));
    try testing.expect(order[0] == &a and order[1] == &b and order[2] == &c_node);

    wl_list_swap(&a, &c_node);
    try testing.expectEqual(@as(usize, 3), collect(&head, &order));
    try testing.expect(order[0] == &c_node and order[1] == &b and order[2] == &a);

    wl_list_safe_reinsert_prev(&a, &b);
    try testing.expectEqual(@as(usize, 3), collect(&head, &order));
    try testing.expect(order[0] == &c_node and order[1] == &b and order[2] == &a);

    wl_list_safe_reinsert_prev(&b, &c_node);
    try testing.expectEqual(@as(usize, 3), collect(&head, &order));
    try testing.expect(order[0] == &c_node and order[1] == &b and order[2] == &a);
}

test "join_strings concatenates with separators and suffixes" {
    var arr: [4][*c]u8 = .{
        @ptrCast(@constCast("a")),
        @ptrCast(@constCast("b")),
        @ptrCast(@constCast("c")),
        null,
    };

    const joined = join_strings(&arr, ",") orelse return error.OutOfMemory;
    defer free(joined);
    try testing.expectEqualStrings("a,b,c", std.mem.span(joined));

    const suffixed = join_strings_with_suffix(&arr, "!", "|") orelse return error.OutOfMemory;
    defer free(suffixed);
    try testing.expectEqualStrings("a!|b!|c!", std.mem.span(suffixed));

    var empty: [1][*c]u8 = .{null};
    const none = join_strings(&empty, ",") orelse return error.OutOfMemory;
    defer free(none);
    try testing.expectEqualStrings("", std.mem.span(none));
}

test "timespec helpers convert to milliseconds" {
    var ts = std.mem.zeroes(c.struct_timespec);
    ts.tv_sec = 2;
    ts.tv_nsec = 500000000;
    try testing.expectEqual(@as(u32, 2500), timespec_to_ms(&ts));
    try testing.expect(get_now_in_ms() > 0);
}
