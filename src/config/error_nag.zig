//! Port of src/config/error_nag.c (strangler-fig Phase 4, slice 20).
//!
//! Exports the same three C symbols (config_error_nag_init/update/destroy);
//! the C file is filtered from the compositor link. This is the config-error
//! nag launcher: it watches the error store written by error_store.c and
//! spawns `acwm-nag` inside a fresh wl_client, feeding the first lines of
//! the store through stdin and offering an "Edit" button whose command
//! points at the first offending file/line (with $EDITOR/$VISUAL detection
//! and vi/vim/nvim/hx/code-style line arguments).
//!
//! The C mechanics are preserved: WAYLAND_SOCKET handoff via socketpair with
//! FD_CLOEXEC on both ends (the child clears it), the poll-timer indirection
//! for the initial update, three non-empty lines piped plus an ellipsis
//! summary, and the exact execlp argument layouts for each combination of
//! output and edit command.
//!
//! Static helpers (ANSI stripping, shell quoting, first-target parsing, the
//! edit command builder) are unit-tested; the process/wayland plumbing is
//! exercised only by the stubs in tests/error_nag_stub.c.

const std = @import("std");
const c = @import("cc");

const PATH_MAX = c.PATH_MAX;

extern fn config_error_store_path() callconv(.c) [*:0]const u8;
extern fn string_printf(fmt: [*:0]const u8, ...) callconv(.c) ?[*:0]u8;

// libc
extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*c.FILE;
extern "c" fn fgets(buf: [*]u8, n: c_int, f: ?*c.FILE) ?[*:0]u8;
extern "c" fn fclose(f: ?*c.FILE) c_int;
extern "c" fn fgetc(f: ?*c.FILE) c_int;
extern "c" fn malloc(size: usize) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn memcpy(dest: [*]u8, src: [*]const u8, n: usize) [*]u8;
extern "c" fn strlen(s: [*:0]const u8) usize;
extern "c" fn strstr(h: [*:0]const u8, n: [*:0]const u8) ?[*:0]u8;
extern "c" fn strchr(s: [*:0]const u8, ch: c_int) ?[*:0]u8;
extern "c" fn strrchr(s: [*:0]const u8, ch: c_int) ?[*:0]u8;
extern "c" fn strcmp(a: [*:0]const u8, b: [*:0]const u8) c_int;
extern "c" fn atoi(s: [*:0]const u8) c_int;
extern "c" fn getenv(name: [*:0]const u8) ?[*:0]u8;
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn snprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ...) c_int;
extern "c" fn realpath(path: [*:0]const u8, resolved: [*]u8) ?[*:0]u8;
extern "c" fn write(fd: c_int, buf: [*]const u8, n: usize) isize;
extern "c" fn pipe(fds: *[2]c_int) c_int;
extern "c" fn socketpair(domain: c_int, typ: c_int, protocol: c_int, sv: *[2]c_int) c_int;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn dup2(oldfd: c_int, newfd: c_int) c_int;
extern "c" fn fcntl(fd: c_int, cmd: c_int, arg: c_int) c_int;
extern "c" fn fork() c_int;
extern "c" fn _exit(status: c_int) noreturn;
/// execlp is variadic in C; a fixed 15-slot declaration is ABI-compatible
/// and the trailing nulls stop the scan like the C call sites.
extern "c" fn execlp(
    path: [*:0]const u8,
    arg0: [*:0]const u8,
    a1: ?[*:0]const u8,
    a2: ?[*:0]const u8,
    a3: ?[*:0]const u8,
    a4: ?[*:0]const u8,
    a5: ?[*:0]const u8,
    a6: ?[*:0]const u8,
    a7: ?[*:0]const u8,
    a8: ?[*:0]const u8,
    a9: ?[*:0]const u8,
    a10: ?[*:0]const u8,
    a11: ?[*:0]const u8,
    a12: ?[*:0]const u8,
    a13: ?[*:0]const u8,
) c_int;

// libwayland (exported symbols)
extern "c" fn wl_client_create(display: ?*c.struct_wl_display, fd: c_int) ?*c.struct_wl_client;
extern "c" fn wl_client_destroy(client: ?*c.struct_wl_client) void;
extern "c" fn wl_client_add_destroy_listener(client: ?*c.struct_wl_client, listener: [*c]c.struct_wl_listener) void;
extern "c" fn wl_event_loop_add_timer(loop: ?*c.struct_wl_event_loop, func: ?*const fn (?*anyopaque) callconv(.c) c_int, data: ?*anyopaque) ?*c.struct_wl_event_source;
extern "c" fn wl_event_source_timer_update(source: ?*c.struct_wl_event_source, ms_delay: c_int) c_int;
extern "c" fn wl_event_source_remove(source: ?*c.struct_wl_event_source) c_int;

// ---------------------------------------------------------------------------
// state
// ---------------------------------------------------------------------------

var nag_client: ?*c.struct_wl_client = null;
var nag_client_destroy: c.struct_wl_listener = std.mem.zeroes(c.struct_wl_listener);
var nag_timer: ?*c.struct_wl_event_source = null;

/// wl_list_init is a static inline in wayland-util.h (no exported symbol).
fn wlListInit(list: *c.struct_wl_list) void {
    list.prev = @ptrCast(list);
    list.next = @ptrCast(list);
}

/// wl_list_remove, likewise inline in the header.
fn wlListRemove(link: *c.struct_wl_list) void {
    const prev = link.prev;
    const next = link.next;
    prev.*.next = next;
    next.*.prev = prev;
}

fn nagClientDestroyed(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    _ = data;
    wlListRemove(&nag_client_destroy.link);
    wlListInit(&nag_client_destroy.link);
    nag_client = null;
}

fn nagSetCloexec(fd: c_int) bool {
    const flags = fcntl(fd, c.F_GETFD, 0);
    if (flags < 0)
        return false;
    return fcntl(fd, c.F_SETFD, flags | c.FD_CLOEXEC) == 0;
}

/// Strips CSI escape sequences (ESC '[' ... final byte in 0x40..0x7e).
fn nagStripAnsi(src: [*:0]const u8, dst: [*]u8, dst_size: usize) void {
    var j: usize = 0;
    var i: usize = 0;
    while (src[i] != 0 and j + 1 < dst_size) {
        if (@as(u8, src[i]) == '\x1b' and src[i + 1] == '[') {
            var k = i + 2;
            while (src[k] != 0 and !(src[k] >= '@' and src[k] <= '~'))
                k += 1;
            if (src[k] == 0)
                break;
            i = k + 1;
            continue;
        }
        dst[j] = src[i];
        j += 1;
        i += 1;
    }
    dst[j] = 0;
}

fn nagKill() void {
    if (nag_client == null)
        return;
    // Tearing down the compositor-side client closes the connection, which
    // makes acwm-nag leave its main loop and exit on its own. The destroy
    // listener clears nag_client for us.
    wl_client_destroy(nag_client);
}

fn nagFirstTarget(path: [*]u8, path_size: usize, line_out: *c_int) bool {
    const file = fopen(config_error_store_path(), "r") orelse return false;

    var found = false;
    var raw: [1024]u8 = undefined;
    var line: [1024]u8 = undefined;
    while (fgets(&raw, raw.len, file) != null) {
        nagStripAnsi(@ptrCast(&raw), &line, line.len);
        var p = strstr(@ptrCast(&line), "[Index] ");
        if (p != null) {
            p = p.? + 8;
            while (p.?[0] == ' ' or p.?[0] == '\t')
                p = p.? + 1;
            var n = strlen(p.?);
            while (n > 0 and (p.?[n - 1] == '\n' or p.?[n - 1] == '\r' or p.?[n - 1] == ' ')) {
                n -= 1;
                p.?[n] = 0;
            }
            const colon = strrchr(p.?, ':');
            if (colon != null and colon.?[1] >= '0' and colon.?[1] <= '9') {
                line_out.* = atoi(colon.? + 1);
                colon.?[0] = 0;
            }
            _ = snprintf(path, path_size, "%s", p.?);
            found = true;
            break;
        }
        p = strstr(@ptrCast(&line), "File \"");
        if (p != null) {
            p = p.? + 6;
            const end = strchr(p.?, '"');
            if (end != null) {
                var n: usize = @intFromPtr(end.?) - @intFromPtr(p.?);
                if (n >= path_size)
                    n = path_size - 1;
                _ = memcpy(path, p.?, n);
                path[n] = 0;
                const lp = strstr(end.?, "line ");
                if (lp != null)
                    line_out.* = atoi(lp.? + 5);
                found = true;
                break;
            }
        }
    }
    _ = fclose(file);
    return found;
}

/// Wraps a string in single quotes, replacing ' with '\'' (shell-safe).
fn nagShellQuote(s: [*:0]const u8) ?[*:0]u8 {
    var len: usize = 2;
    var i: usize = 0;
    while (s[i] != 0) : (i += 1)
        len += if (s[i] == '\'') 4 else 1;

    const raw = malloc(len + 1) orelse return null;
    const out: [*:0]u8 = @ptrCast(raw);
    var o: usize = 0;
    out[o] = '\'';
    o += 1;
    i = 0;
    while (s[i] != 0) : (i += 1) {
        if (s[i] == '\'') {
            _ = memcpy(out + o, "'\\''", 4);
            o += 4;
        } else {
            out[o] = s[i];
            o += 1;
        }
    }
    out[o] = '\'';
    o += 1;
    out[o] = 0;
    return out;
}

fn nagEditCommand() ?[*:0]u8 {
    var path: [PATH_MAX]u8 = std.mem.zeroes([PATH_MAX]u8);
    var line: c_int = 0;
    _ = nagFirstTarget(&path, path.len, &line);
    if (path[0] == 0)
        return null;

    if (path[0] != '/') {
        var resolved: [PATH_MAX]u8 = undefined;
        if (realpath(@ptrCast(&path), &resolved) != null)
            _ = snprintf(&path, path.len, "%s", @as([*:0]const u8, @ptrCast(&resolved)));
    }

    var editor: [*:0]const u8 = getenv("EDITOR") orelse "vi";
    if (editor[0] == 0)
        editor = getenv("VISUAL") orelse "vi";
    if (editor[0] == 0)
        editor = "vi";

    var name: [256]u8 = undefined;
    _ = snprintf(&name, name.len, "%s", editor);
    const slash = strrchr(@ptrCast(&name), '/');
    const base: [*:0]u8 = if (slash) |s| s + 1 else @ptrCast(&name);
    var stop: usize = 0;
    while (base[stop] != 0 and base[stop] != ' ')
        stop += 1;
    base[stop] = 0;

    const path_arg = nagShellQuote(@ptrCast(&path)) orelse return null;

    if (line <= 0) {
        const cmd = string_printf("%s %s", editor, path_arg);
        free(@ptrCast(path_arg));
        return cmd;
    }

    const with_line = string_printf("%s:%d", @as([*:0]const u8, @ptrCast(&path)), line);
    const line_arg: ?[*:0]u8 = if (with_line) |w| nagShellQuote(w) else null;
    free(@ptrCast(with_line));
    if (line_arg == null) {
        free(@ptrCast(path_arg));
        return null;
    }

    const plus = [_][*:0]const u8{ "vi", "vim", "nvim", "gvim", "emacs", "emacsclient", "nano" };
    const colon = [_][*:0]const u8{ "hx", "helix", "micro", "zed" };
    const code = [_][*:0]const u8{ "code", "codium" };

    var cmd: ?[*:0]u8 = null;
    for (plus) |n| {
        if (cmd == null and strcmp(base, n) == 0)
            cmd = string_printf("%s +%d %s", editor, line, path_arg);
    }
    if (cmd == null) {
        for (colon) |n| {
            if (cmd == null and strcmp(base, n) == 0)
                cmd = string_printf("%s %s", editor, line_arg.?);
        }
    }
    if (cmd == null) {
        for (code) |n| {
            if (cmd == null and strcmp(base, n) == 0)
                cmd = string_printf("%s -g %s", editor, line_arg.?);
        }
    }
    if (cmd == null)
        cmd = string_printf("%s %s", editor, path_arg);

    free(@ptrCast(path_arg));
    free(@ptrCast(line_arg));
    return cmd;
}

fn nagPipeText(fd: c_int) void {
    var buffer: [1024]u8 = undefined;
    var total: c_int = 0;

    var file = fopen(config_error_store_path(), "r") orelse return;
    while (fgets(&buffer, buffer.len, file) != null) {
        if (buffer[0] != '\n' and buffer[0] != 0)
            total += 1;
    }
    _ = fclose(file);

    var shown: c_int = 0;
    file = fopen(config_error_store_path(), "r") orelse return;
    while (shown < 3 and fgets(&buffer, buffer.len, file) != null) {
        if (buffer[0] == '\n')
            continue;
        const n = strlen(@ptrCast(&buffer));
        _ = write(fd, &buffer, n);
        if (buffer[n - 1] != '\n')
            _ = write(fd, "\n", 1);
        shown += 1;
    }
    _ = fclose(file);

    const hidden = total - shown;
    if (hidden > 0) {
        var summary: [80]u8 = undefined;
        const plural: [*:0]const u8 = if (hidden == 1) "" else "s";
        _ = snprintf(&summary, summary.len, "\xe2\x80\xa6 (+%d more line%s)\n", hidden, plural);
        _ = write(fd, &summary, strlen(@ptrCast(&summary)));
    }
}

fn execNag(out: ?[*:0]const u8, edit: ?[*:0]u8) noreturn {
    const nag: [*:0]const u8 = "acwm-nag";
    // execlp stops at the first NULL; the fixed declaration always passes
    // 13 slots so every combination terminates correctly.
    var args: [13]?[*:0]const u8 = std.mem.zeroes([13]?[*:0]const u8);
    var i: usize = 0;
    if (out != null) {
        args[i] = "-o";
        i += 1;
        args[i] = out;
        i += 1;
    }
    args[i] = "-t";
    i += 1;
    args[i] = "error";
    i += 1;
    args[i] = "-e";
    i += 1;
    args[i] = "top";
    i += 1;
    args[i] = "-l";
    i += 1;
    args[i] = "-s";
    i += 1;
    args[i] = "Close";
    i += 1;
    if (edit != null) {
        args[i] = "-b";
        i += 1;
        args[i] = edit;
        i += 1;
    }
    _ = execlp(nag, nag, args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9], args[10], args[11], args[12]);
    _exit(127);
}

fn nagSpawn() void {
    if (c.server.display == null)
        return;

    nagKill();

    const edit = nagEditCommand();
    defer if (edit) |e| free(@ptrCast(e));

    var pfd: [2]c_int = undefined;
    if (pipe(&pfd) != 0)
        return;

    var sockets: [2]c_int = undefined;
    if (socketpair(c.AF_UNIX, c.SOCK_STREAM, 0, &sockets) != 0) {
        _ = close(pfd[0]);
        _ = close(pfd[1]);
        return;
    }

    // Keep both ends close-on-exec; the child re-enables its end so
    // libwayland can pick it up from WAYLAND_SOCKET after the exec.
    if (!nagSetCloexec(sockets[0]) or !nagSetCloexec(sockets[1])) {
        _ = close(sockets[0]);
        _ = close(sockets[1]);
        _ = close(pfd[0]);
        _ = close(pfd[1]);
        return;
    }

    const client = wl_client_create(c.server.display, sockets[0]) orelse {
        _ = close(sockets[0]);
        _ = close(sockets[1]);
        _ = close(pfd[0]);
        _ = close(pfd[1]);
        return;
    };

    nag_client = client;
    nag_client_destroy.notify = nagClientDestroyed;
    wl_client_add_destroy_listener(client, &nag_client_destroy);

    const pid = fork();
    if (pid < 0) {
        wl_client_destroy(client);
        _ = close(sockets[1]);
        _ = close(pfd[0]);
        _ = close(pfd[1]);
        return;
    }
    if (pid == 0) {
        _ = close(sockets[0]);

        const flags = fcntl(sockets[1], c.F_GETFD, 0);
        if (flags >= 0)
            _ = fcntl(sockets[1], c.F_SETFD, flags & ~c.FD_CLOEXEC);

        var socket_str: [16]u8 = undefined;
        _ = snprintf(&socket_str, socket_str.len, "%d", sockets[1]);
        _ = setenv("WAYLAND_SOCKET", @ptrCast(&socket_str), 1);

        if (pfd[0] != c.STDIN_FILENO) {
            _ = dup2(pfd[0], c.STDIN_FILENO);
            _ = close(pfd[0]);
        }
        _ = close(pfd[1]);

        var out: ?[*:0]const u8 = null;
        if (c.server.selected_monitor != null) {
            const mon = c.server.selected_monitor;
            if (mon.*.wlr_output) |o| {
                out = @ptrCast(&o.*.name);
            }
        }

        execNag(out, edit);
    }

    _ = close(sockets[1]);
    _ = close(pfd[0]);
    nagPipeText(pfd[1]);
    _ = close(pfd[1]);
}

// ---------------------------------------------------------------------------
// exported functions (same symbols as the C twin)
// ---------------------------------------------------------------------------

export fn config_error_nag_update() callconv(.c) void {
    if (c.server.event_loop == null)
        return;

    var has_error = false;
    if (fopen(config_error_store_path(), "r")) |file| {
        if (fgetc(file) != c.EOF)
            has_error = true;
        _ = fclose(file);
    }

    nagKill();
    if (has_error)
        nagSpawn();
}

fn nagInitialCb(data: ?*anyopaque) callconv(.c) c_int {
    _ = data;
    if (nag_timer != null) {
        _ = wl_event_source_remove(nag_timer);
        nag_timer = null;
    }
    config_error_nag_update();
    return 0;
}

export fn config_error_nag_init() callconv(.c) void {
    if (c.server.event_loop == null)
        return;
    nag_timer = wl_event_loop_add_timer(c.server.event_loop, nagInitialCb, null);
    if (nag_timer != null)
        _ = wl_event_source_timer_update(nag_timer, 1);
}

export fn config_error_nag_destroy() callconv(.c) void {
    if (nag_timer != null) {
        _ = wl_event_source_remove(nag_timer);
        nag_timer = null;
    }
    nagKill();
}

// ---------------------------------------------------------------------------
// tests (stub-backed: see tests/error_nag_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_store_path: [4096]u8;

extern "c" fn fputs(s: [*:0]const u8, f: ?*c.FILE) c_int;
extern "c" fn read(fd: c_int, buf: [*]u8, n: usize) isize;
extern "c" fn unlink(path: [*:0]const u8) c_int;

fn setStorePath(comptime path: [:0]const u8) void {
    @memcpy(stub_store_path[0..path.len], path);
    stub_store_path[path.len] = 0;
}

fn writeStore(path: [:0]const u8, content: []const u8) void {
    const file = fopen(path, "w").?;
    for (content) |ch| {
        const b = [2]u8{ ch, 0 };
        _ = fputs(@ptrCast(&b), file);
    }
    _ = fclose(file);
}

test "strip ANSI removes CSI sequences and truncates at the end" {
    var out: [64]u8 = undefined;

    nagStripAnsi("plain", &out, out.len);
    try testing.expectEqualStrings("plain", std.mem.sliceTo(&out, 0));

    nagStripAnsi("\x1b[1m\x1b[31mred\x1b[0m text", &out, out.len);
    try testing.expectEqualStrings("red text", std.mem.sliceTo(&out, 0));

    // incomplete sequence: everything from ESC is dropped
    nagStripAnsi("ok\x1b[31", &out, out.len);
    try testing.expectEqualStrings("ok", std.mem.sliceTo(&out, 0));
}

test "shell quote wraps and escapes single quotes" {
    const q = nagShellQuote("plain/path").?;
    defer free(@ptrCast(q));
    try testing.expectEqualStrings("'plain/path'", std.mem.span(@as([*:0]const u8, q)));

    const q2 = nagShellQuote("it's").?;
    defer free(@ptrCast(q2));
    try testing.expectEqualStrings("'it'\\''s'", std.mem.span(@as([*:0]const u8, q2)));
}

test "first target: index form and file/line form" {
    const path = "/tmp/opencode/acwm-error-nag-index.log";
    setStorePath(path);
    writeStore(path, "noise line\n[Index] /etc/acwm/config.conf:42\ntrailer\n");
    defer _ = unlink(path);

    var out: [PATH_MAX]u8 = undefined;
    var line: c_int = 0;
    try testing.expect(nagFirstTarget(&out, out.len, &line));
    try testing.expectEqualStrings("/etc/acwm/config.conf", std.mem.sliceTo(&out, 0));
    try testing.expectEqual(@as(c_int, 42), line);

    setStorePath("/tmp/opencode/acwm-error-nag-file.log");
    writeStore("/tmp/opencode/acwm-error-nag-file.log", "  File \"/tmp/x.conf\", line 7\n");
    defer _ = unlink("/tmp/opencode/acwm-error-nag-file.log");
    line = 0;
    try testing.expect(nagFirstTarget(&out, out.len, &line));
    try testing.expectEqualStrings("/tmp/x.conf", std.mem.sliceTo(&out, 0));
    try testing.expectEqual(@as(c_int, 7), line);
}

test "first target: ANSI-colored index line" {
    const path = "/tmp/opencode/acwm-error-nag-ansi.log";
    setStorePath(path);
    writeStore(path, "\x1b[33m[Index] \x1b[0m/tmp/y.conf:9\n");
    defer _ = unlink(path);

    var out: [PATH_MAX]u8 = undefined;
    var line: c_int = 0;
    try testing.expect(nagFirstTarget(&out, out.len, &line));
    try testing.expectEqualStrings("/tmp/y.conf", std.mem.sliceTo(&out, 0));
    try testing.expectEqual(@as(c_int, 9), line);
}

test "first target: missing store returns false" {
    setStorePath("/tmp/opencode/acwm-error-nag-missing.log");
    var out: [PATH_MAX]u8 = undefined;
    var line: c_int = 0;
    try testing.expect(!nagFirstTarget(&out, out.len, &line));
}

test "edit command picks the editor-line syntax by editor name" {
    const path = "/tmp/opencode/acwm-error-nag-edit.log";
    setStorePath(path);
    writeStore(path, "[Index] /etc/acwm/config.conf:42\n");
    defer _ = unlink(path);

    // vim: +line path
    _ = setenv("EDITOR", "vim", 1);
    _ = setenv("VISUAL", "", 1);
    const vim_cmd = nagEditCommand().?;
    defer free(@ptrCast(vim_cmd));
    try testing.expectEqualStrings(
        "vim +42 '/etc/acwm/config.conf'",
        std.mem.span(@as([*:0]const u8, vim_cmd)),
    );

    // hx: path:line
    _ = setenv("EDITOR", "hx", 1);
    const hx_cmd = nagEditCommand().?;
    defer free(@ptrCast(hx_cmd));
    try testing.expectEqualStrings("hx '/etc/acwm/config.conf:42'", std.mem.span(@as([*:0]const u8, hx_cmd)));

    // code: -g path:line
    _ = setenv("EDITOR", "code", 1);
    const code_cmd = nagEditCommand().?;
    defer free(@ptrCast(code_cmd));
    try testing.expectEqualStrings("code -g '/etc/acwm/config.conf:42'", std.mem.span(@as([*:0]const u8, code_cmd)));

    // unknown editor: plain path
    _ = setenv("EDITOR", "mined", 1);
    const mined_cmd = nagEditCommand().?;
    defer free(@ptrCast(mined_cmd));
    try testing.expectEqualStrings("mined '/etc/acwm/config.conf'", std.mem.span(@as([*:0]const u8, mined_cmd)));

    // editor path with a slash: basename rule applies
    _ = setenv("EDITOR", "/usr/bin/nano", 1);
    const nano_cmd = nagEditCommand().?;
    defer free(@ptrCast(nano_cmd));
    try testing.expectEqualStrings("/usr/bin/nano +42 '/etc/acwm/config.conf'", std.mem.span(@as([*:0]const u8, nano_cmd)));
}

test "edit command without a line number omits the line argument" {
    const path = "/tmp/opencode/acwm-error-nag-noline.log";
    setStorePath(path);
    writeStore(path, "File \"/etc/acwm/config.conf\", \n");
    defer _ = unlink(path);

    _ = setenv("EDITOR", "vim", 1);
    const cmd = nagEditCommand().?;
    defer free(@ptrCast(cmd));
    try testing.expectEqualStrings("vim '/etc/acwm/config.conf'", std.mem.span(@as([*:0]const u8, cmd)));
}

test "edit command returns null when the store has no target" {
    setStorePath("/tmp/opencode/acwm-error-nag-empty.log");
    writeStore("/tmp/opencode/acwm-error-nag-empty.log", "just noise\n");
    defer _ = unlink("/tmp/opencode/acwm-error-nag-empty.log");
    try testing.expect(nagEditCommand() == null);
}

test "pipe text sends up to three non-empty lines plus a summary" {
    const path = "/tmp/opencode/acwm-error-nag-pipe.log";
    setStorePath(path);
    writeStore(path, "one\n\ntwo\nthree\nfour\nfive\n");
    defer _ = unlink(path);

    var fds: [2]c_int = undefined;
    try testing.expectEqual(@as(c_int, 0), pipe(&fds));
    defer _ = close(fds[0]);
    nagPipeText(fds[1]);
    _ = close(fds[1]);

    var buf: [512]u8 = undefined;
    const n = read(fds[0], &buf, buf.len);
    try testing.expect(n > 0);
    try testing.expectEqualStrings(
        "one\ntwo\nthree\n\xe2\x80\xa6 (+2 more lines)\n",
        buf[0..@intCast(n)],
    );
}

test "update/init/destroy are safe without an event loop" {
    setStorePath("/tmp/opencode/acwm-error-nag-noloop.log");
    c.server.event_loop = null;
    c.server.display = null;

    config_error_nag_update();
    config_error_nag_init();
    config_error_nag_destroy();

    // with a loop pointer but an empty store: no spawn path is reached
    c.server.event_loop = @ptrFromInt(@alignOf(usize));
    config_error_nag_update();
    config_error_nag_destroy();
}
