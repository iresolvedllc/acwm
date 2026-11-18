//! Port of src/config/error_store.c (strangler-fig Phase 4).
//!
//! Exports the same C symbols as the C twin (removed from the compositor
//! link). Where config errors are reported, this module mirrors them to a
//! per-user log file that error_nag.c reads back: the store directory is
//! $XDG_RUNTIME_DIR/acwm (else /tmp/acwm-<uid>), hardened against symlinks
//! (O_NOFOLLOW) and foreign/loose directory ownership.
//!
//! C types and libc declarations come from the translate-c module ("cc").
//! Tests live at the bottom; they manipulate the module-private state and
//! the process environment directly (test execution order is declaration
//! order, so the env-dependent tests are self-contained).

const std = @import("std");
const c = @import("cc");

const PATH_MAX = c.PATH_MAX;

// module state (C statics)
var store_path: [PATH_MAX:0]u8 = [_]u8{0} ** (PATH_MAX + 1);
var store_file: ?*c.FILE = null;
var store_active: bool = false;

// ---------------------------------------------------------------------------
// static helpers
// ---------------------------------------------------------------------------

/// Directory exists, is a real dir, owned by us; loose group/other bits are
/// tightened to 0700 (chmod result ignored, as in C).
fn storeDirOk(path: [*:0]const u8) bool {
    var st: c.struct_stat = undefined;
    if (c.lstat(path, &st) != 0)
        return false;
    if ((st.st_mode & c.S_IFMT) != c.S_IFDIR)
        return false;
    if (st.st_uid != c.getuid())
        return false;
    if ((st.st_mode & 0o077) != 0)
        _ = c.chmod(path, 0o700);
    return true;
}

fn storeDirPrepare(path: [*:0]const u8) bool {
    if (storeDirOk(path))
        return true;
    if (c.mkdir(path, 0o700) == 0)
        return true;
    return storeDirOk(path);
}

// ---------------------------------------------------------------------------
// exported functions (same symbols as the C twin)
// ---------------------------------------------------------------------------

export fn config_error_store_path() callconv(.c) [*:0]const u8 {
    if (store_path[0] == 0) {
        var dir: [PATH_MAX:0]u8 = [_]u8{0} ** (PATH_MAX + 1);

        const runtime = c.getenv("XDG_RUNTIME_DIR");
        if (runtime != null and runtime.?[0] == '/') {
            _ = c.snprintf(&dir, PATH_MAX, "%s/acwm", runtime.?);
            if (!storeDirPrepare(&dir))
                dir[0] = 0;
        }
        if (dir[0] == 0) {
            // (int)getuid() in C — bitcast keeps the wrap on absurd uids
            _ = c.snprintf(&dir, PATH_MAX, "/tmp/acwm-%d", @as(c_int, @bitCast(c.getuid())));
            if (!storeDirPrepare(&dir))
                dir[0] = 0;
        }
        if (dir[0] == 0)
            return @ptrCast(&store_path);
        _ = c.snprintf(&store_path, PATH_MAX, "%s/config-errors.log", &dir);
    }
    return @ptrCast(&store_path);
}

export fn config_error_store_begin() callconv(.c) void {
    config_error_store_end();

    const path = config_error_store_path();
    if (path[0] == 0)
        return;

    const fd = c.open(
        path,
        @as(c_int, c.O_WRONLY | c.O_CREAT | c.O_TRUNC | c.O_NOFOLLOW | c.O_CLOEXEC),
        @as(c_uint, 0o600),
    );
    if (fd < 0)
        return;
    store_file = c.fdopen(fd, "w");
    if (store_file == null) {
        _ = c.close(fd);
        return;
    }
    store_active = true;
}

export fn config_error_store_end() callconv(.c) void {
    if (store_file != null) {
        _ = c.fclose(store_file);
        store_file = null;
    }
    store_active = false;
}

export fn config_error_store_active() callconv(.c) bool {
    return store_active;
}

export fn config_error_store_record(message: ?[*:0]const u8) callconv(.c) void {
    if (!store_active or store_file == null or message == null)
        return;

    const len = c.strlen(message.?);
    const clean: ?[*:0]u8 = @ptrCast(c.malloc(len + 1));
    if (clean == null)
        return;
    _ = c.memcpy(@ptrCast(clean), @ptrCast(message), len + 1);

    var clean_len: usize = c.strlen(clean.?);
    while (clean_len > 0) {
        const ch = clean.?[clean_len - 1];
        if (ch != '\n' and ch != '\r' and ch != ' ' and ch != '\t')
            break;
        clean.?[clean_len - 1] = 0;
        clean_len -= 1;
    }

    if (clean_len > 0) {
        _ = c.fputs(@ptrCast(clean), store_file);
        const has_esc = c.strchr(@ptrCast(clean), '\x1b') != null;
        const has_reset = clean_len >= 4 and
            c.strcmp(@ptrCast(clean.? + clean_len - 4), "\x1b[0m") == 0;
        if (has_esc and !has_reset)
            _ = c.fputs("\x1b[0m", store_file);
        _ = c.fputc('\n', store_file);
        _ = c.fflush(store_file);
    }

    free(@ptrCast(clean));
}

// ---------------------------------------------------------------------------
// tests (same-module: reset the private state directly)
// ---------------------------------------------------------------------------

const testing = std.testing;

fn resetState() void {
    store_path = [_]u8{0} ** (PATH_MAX + 1);
    store_file = null;
    store_active = false;
}

fn tmpdirFor(comptime tag: []const u8) ![:0]u8 {
    var tmpl: [64]u8 = undefined;
    const used = std.fmt.bufPrintZ(
        &tmpl,
        "/tmp/opencode/acwm-store-" ++ tag ++ "-{d}-XXXXXX",
        .{c.getpid()},
    ) catch unreachable;
    const dir = c.mkdtemp(used.ptr) orelse return error.MkdtempFailed;
    return @constCast(std.mem.span(dir));
}

fn fileContents(path: [*:0]const u8, alloc: std.mem.Allocator) ![]u8 {
    const f = try std.fs.cwd().openFile(std.mem.span(path), .{});
    defer f.close();
    return f.readToEndAlloc(alloc, 1 << 20);
}

test "path falls back to /tmp/acwm-<uid> without XDG_RUNTIME_DIR" {
    resetState();
    _ = c.unsetenv("XDG_RUNTIME_DIR");

    const path = std.mem.span(config_error_store_path());
    try testing.expect(std.mem.startsWith(u8, path, "/tmp/acwm-"));
    try testing.expect(std.mem.endsWith(u8, path, "/config-errors.log"));
}

test "path prefers $XDG_RUNTIME_DIR/acwm and prepares it 0700" {
    resetState();
    const tmp = try tmpdirFor("xdg");
    _ = c.setenv("XDG_RUNTIME_DIR", tmp, 1);

    const path = std.mem.span(config_error_store_path());
    const want_dir = std.fmt.allocPrintZ(
        testing.allocator,
        "{s}/acwm/config-errors.log",
        .{tmp},
    ) catch unreachable;
    defer testing.allocator.free(want_dir);
    try testing.expectEqualStrings(want_dir, path);

    // the /acwm dir was created and is a private dir owned by us
    var st: c.struct_stat = undefined;
    const dir_z = std.fmt.allocPrintZ(
        testing.allocator,
        "{s}/acwm",
        .{tmp},
    ) catch unreachable;
    defer testing.allocator.free(dir_z);
    try testing.expectEqual(@as(c_int, 0), c.stat(@ptrCast(dir_z), &st));
    try testing.expect((st.st_mode & c.S_IFMT) == c.S_IFDIR);
    try testing.expectEqual(@as(u32, 0o700), st.st_mode & 0o777);
}

test "loose-permission dir is tightened to 0700" {
    resetState();
    const tmp = try tmpdirFor("loose");
    _ = c.setenv("XDG_RUNTIME_DIR", tmp, 1);

    const dir = std.fmt.allocPrintZ(
        testing.allocator,
        "{s}/acwm",
        .{tmp},
    ) catch unreachable;
    defer testing.allocator.free(dir);
    try testing.expectEqual(@as(c_int, 0), c.mkdir(@ptrCast(dir), 0o755));

    _ = config_error_store_path();
    var st: c.struct_stat = undefined;
    try testing.expectEqual(@as(c_int, 0), c.stat(@ptrCast(dir), &st));
    try testing.expectEqual(@as(u32, 0o700), st.st_mode & 0o777);
}

test "begin/active/record/end round trip with trimming and reset repair" {
    resetState();
    const tmp = try tmpdirFor("roundtrip");
    _ = c.setenv("XDG_RUNTIME_DIR", tmp, 1);
    const path = config_error_store_path();

    try testing.expect(!config_error_store_active());
    config_error_store_begin();
    try testing.expect(config_error_store_active());

    // created file is 0600
    var st: c.struct_stat = undefined;
    try testing.expectEqual(@as(c_int, 0), c.stat(path, &st));
    try testing.expectEqual(@as(u32, 0o600), st.st_mode & 0o777);

    config_error_store_record("plain message\n"); // trailing \n trimmed
    config_error_store_record("   \n\r\t "); // whitespace-only: no line at all
    config_error_store_record("\x1b[1m\x1b[31minvalid\x1b[0m"); // ends with reset
    config_error_store_record("\x1b[1mbold\x1b[0m extra"); // esc without reset

    const got = try fileContents(path, testing.allocator);
    defer testing.allocator.free(got);
    try testing.expectEqualStrings(
        "plain message\n" ++
            "\x1b[1m\x1b[31minvalid\x1b[0m\n" ++
            "\x1b[1mbold\x1b[0m extra\x1b[0m\n",
        got,
    );

    config_error_store_end();
    try testing.expect(!config_error_store_active());
}

test "record outside an active store is a no-op" {
    resetState();
    config_error_store_record("before begin"); // must not create anything
    try testing.expect(!config_error_store_active());

    const tmp = try tmpdirFor("noop");
    _ = c.setenv("XDG_RUNTIME_DIR", tmp, 1);
    config_error_store_begin();
    config_error_store_end();
    config_error_store_record("after end");

    // no file was ever created
    const path = config_error_store_path();
    var st: c.struct_stat = undefined;
    try testing.expect(c.stat(path, &st) != 0);
}

test "re-begin truncates the previous store" {
    resetState();
    const tmp = try tmpdirFor("rebegin");
    _ = c.setenv("XDG_RUNTIME_DIR", tmp, 1);
    const path = config_error_store_path();

    config_error_store_begin();
    config_error_store_record("old entry");
    config_error_store_begin(); // end() + fresh O_TRUNC open
    config_error_store_record("new entry");
    config_error_store_end();

    const got = try fileContents(path, testing.allocator);
    defer testing.allocator.free(got);
    try testing.expectEqualStrings("new entry\n", got);
}

test "O_NOFOLLOW refuses a symlinked store file" {
    resetState();
    const tmp = try tmpdirFor("nofollow");
    _ = c.setenv("XDG_RUNTIME_DIR", tmp, 1);

    const dir = std.fmt.allocPrintZ(
        testing.allocator,
        "{s}/acwm",
        .{tmp},
    ) catch unreachable;
    defer testing.allocator.free(dir);
    try testing.expectEqual(@as(c_int, 0), c.mkdir(@ptrCast(dir), 0o700));

    // victim file + symlink in place of the store
    const victim = std.fmt.allocPrintZ(
        testing.allocator,
        "{s}/victim.txt",
        .{tmp},
    ) catch unreachable;
    defer testing.allocator.free(victim);
    const vf = std.fs.cwd().createFile(std.mem.span(victim), .{}) catch unreachable;
    vf.writeAll("untouched") catch unreachable;
    vf.close();

    const link = std.fmt.allocPrintZ(
        testing.allocator,
        "{s}/acwm/config-errors.log",
        .{tmp},
    ) catch unreachable;
    defer testing.allocator.free(link);
    try testing.expectEqual(@as(c_int, 0), c.symlink(@ptrCast(victim), @ptrCast(link)));

    config_error_store_begin();
    try testing.expect(!config_error_store_active()); // open(ELOOP) → no store

    // the victim file is intact
    const got = try fileContents(victim, testing.allocator);
    defer testing.allocator.free(got);
    try testing.expectEqualStrings("untouched", got);
    config_error_store_end();
}
