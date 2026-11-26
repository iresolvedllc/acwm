//! Port of src/config/watcher.c (strangler-fig Phase 4, slice 25).
//!
//! Exports the same three C symbols; the C twin is filtered from the
//! compositor link. Auto-reload watching with a 150 ms debounce:
//!   - files from config_get_file_paths() are tracked by path with
//!     dev/ino/size/mtime snapshots (refresh_file_state detects create,
//!     delete, replace and content changes)
//!   - the Linux backend uses inotify (IN_NONBLOCK|IN_CLOEXEC) with one
//!     watch per parent directory, matching events against tracked paths;
//!     IN_Q_OVERFLOW forces a check, IN_IGNORED is ignored
//!   - the timer callback re-stats every tracked file and calls
//!     reload_config() when anything changed
//!
//! The BSD kqueue branch from the C twin is intentionally not carried over:
//! acwm's session features are Linux-only (systemd/greetd/PAM), and the
//! no-backend fallback below still disables watching cleanly. Behavior on
//! Linux is identical to the C.
//!
//! Tests live at the bottom and need tests/watcher_stub.c.

const std = @import("std");
const c = @import("cc");

const WLR_ERROR: c_uint = @intCast(c.WLR_ERROR);
const DEBOUNCE_MS: c_int = 150;

extern fn acwm_error_impl(
    log: bool,
    verbosity: c_uint,
    file: [*:0]const u8,
    line: c_int,
    fmt: [*:0]const u8,
    ...) callconv(.c) void;
extern fn config_get_file_paths(count: ?*c_int) callconv(.c) [*c][*c]u8;
extern fn reload_config(arg: ?*const c.Arg) callconv(.c) i32;

extern "c" fn stat(path: [*:0]const u8, buf: *c.struct_stat) c_int;
extern "c" fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque;
extern "c" fn malloc(size: usize) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern "c" fn strcmp(a: [*:0]const u8, b: [*:0]const u8) c_int;
extern "c" fn strlen(s: [*:0]const u8) usize;
extern "c" fn memcpy(dest: [*]u8, src: [*]const u8, n: usize) [*]u8;
extern "c" fn snprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ...) c_int;
extern "c" fn read(fd: c_int, buf: [*]u8, n: usize) isize;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn inotify_init1(flags: c_int) c_int;
extern "c" fn inotify_add_watch(fd: c_int, path: [*:0]const u8, mask: u32) c_int;
extern "c" fn inotify_rm_watch(fd: c_int, wd: c_int) c_int;

const WatchedFile = struct {
    path: ?[*:0]u8 = null,
    fd: c_int = -1,
    seen: bool = false,
    exists: bool = false,
    dev: c.dev_t = 0,
    ino: c.ino_t = 0,
    size: c.off_t = 0,
    mtime: c.struct_timespec = std.mem.zeroes(c.struct_timespec),
};

const DirWatch = struct {
    wd: c_int,
    dir: ?[*:0]u8,
};

var watch_timer: ?*c.struct_wl_event_source = null;
var watched_files: ?[*]WatchedFile = null;
var watched_files_count: c_int = 0;
var watcher_active = false;

var inotify_fd: c_int = -1;
var inotify_source: ?*c.struct_wl_event_source = null;
var dir_watches: ?[*]DirWatch = null;
var dir_watches_count: c_int = 0;

const WATCH_EVENTS: u32 = c.IN_CREATE | c.IN_CLOSE_WRITE | c.IN_ATTRIB |
    c.IN_MOVED_FROM | c.IN_MOVED_TO | c.IN_DELETE | c.IN_MODIFY |
    c.IN_DELETE_SELF | c.IN_MOVE_SELF;

// ---------------------------------------------------------------------------
// tracking
// ---------------------------------------------------------------------------

fn scheduleCheck() void {
    if (watcher_active and watch_timer != null)
        _ = c.wl_event_source_timer_update(watch_timer, DEBOUNCE_MS);
}

fn refreshFileState(file: *WatchedFile) bool {
    var st: c.struct_stat = undefined;
    const exists = stat(file.path.?, &st) == 0;
    var changed = false;

    if (file.seen) {
        if (file.exists != exists) {
            changed = true;
        } else if (exists) {
            changed = file.dev != st.st_dev or file.ino != st.st_ino or
                file.size != st.st_size or
                file.mtime.tv_sec != st.st_mtim.tv_sec or
                file.mtime.tv_nsec != st.st_mtim.tv_nsec;
        }
    }

    file.seen = true;
    file.exists = exists;
    if (exists) {
        file.dev = st.st_dev;
        file.ino = st.st_ino;
        file.size = st.st_size;
        file.mtime = st.st_mtim;
    }
    return changed;
}

fn clearWatchedFiles() void {
    var i: usize = 0;
    while (i < @as(usize, @intCast(watched_files_count))) : (i += 1) {
        if (watched_files.?[i].fd >= 0)
            _ = close(watched_files.?[i].fd);
        free(@ptrCast(watched_files.?[i].path));
    }
    free(@ptrCast(watched_files));
    watched_files = null;
    watched_files_count = 0;
}

fn fileIsTracked(path: [*:0]const u8) bool {
    var i: usize = 0;
    while (i < @as(usize, @intCast(watched_files_count))) : (i += 1) {
        if (strcmp(watched_files.?[i].path.?, path) == 0)
            return true;
    }
    return false;
}

fn trackPath(path: [*:0]const u8) void {
    if (fileIsTracked(path))
        return;

    const next = realloc(
        @ptrCast(watched_files),
        (@as(usize, @intCast(watched_files_count)) + 1) * @sizeOf(WatchedFile),
    ) orelse return;
    watched_files = @ptrCast(@alignCast(next));

    const file = &watched_files.?[@intCast(watched_files_count)];
    file.path = strdup(path);
    if (file.path == null)
        return;

    file.fd = -1;
    file.seen = false;
    file.exists = false;
    _ = refreshFileState(file);
    watched_files_count += 1;
}

// ---------------------------------------------------------------------------
// inotify backend
// ---------------------------------------------------------------------------

fn pathDirname(path: [*:0]const u8) ?[*:0]u8 {
    const slash = std.mem.lastIndexOfScalar(u8, std.mem.span(path), '/') orelse
        return strdup(".");

    if (slash == 0)
        return strdup("/");

    const raw = malloc(slash + 1) orelse return null;
    const dir: [*:0]u8 = @ptrCast(raw);
    _ = memcpy(dir, path, slash);
    dir[slash] = 0;
    return dir;
}

fn clearDirWatches() void {
    var i: usize = 0;
    while (i < @as(usize, @intCast(dir_watches_count))) : (i += 1) {
        if (inotify_fd >= 0)
            _ = inotify_rm_watch(inotify_fd, dir_watches.?[i].wd);
        free(@ptrCast(dir_watches.?[i].dir));
    }
    free(@ptrCast(dir_watches));
    dir_watches = null;
    dir_watches_count = 0;
}

fn dirIsWatched(dir: [*:0]const u8) bool {
    var i: usize = 0;
    while (i < @as(usize, @intCast(dir_watches_count))) : (i += 1) {
        if (strcmp(dir_watches.?[i].dir.?, dir) == 0)
            return true;
    }
    return false;
}

fn addDirWatch(dir: [*:0]const u8) void {
    if (dirIsWatched(dir))
        return;

    const next = realloc(
        @ptrCast(dir_watches),
        (@as(usize, @intCast(dir_watches_count)) + 1) * @sizeOf(DirWatch),
    ) orelse return;
    dir_watches = @ptrCast(@alignCast(next));

    const wd = inotify_add_watch(inotify_fd, dir, WATCH_EVENTS);
    if (wd < 0)
        return;

    dir_watches.?[@intCast(dir_watches_count)].wd = wd;
    dir_watches.?[@intCast(dir_watches_count)].dir = strdup(dir);
    dir_watches_count += 1;
}

fn findDirWatch(wd: c_int) ?usize {
    var i: usize = 0;
    while (i < @as(usize, @intCast(dir_watches_count))) : (i += 1) {
        if (dir_watches.?[i].wd == wd)
            return i;
    }
    return null;
}

fn eventMatches(event: *const c.struct_inotify_event) bool {
    if ((event.mask & c.IN_Q_OVERFLOW) != 0)
        return true;
    if ((event.mask & c.IN_IGNORED) != 0)
        return false;
    if (event.len == 0)
        return (event.mask & (c.IN_DELETE_SELF | c.IN_MOVE_SELF)) != 0;

    const index = findDirWatch(@intCast(event.wd)) orelse return false;
    const dir = dir_watches.?[index].dir.?;
    const dir_len = strlen(dir);

    var path: [4096]u8 = undefined;
    const name: [*:0]const u8 = @ptrCast(event.name());
    if (dir_len > 0 and dir[dir_len - 1] == '/') {
        _ = snprintf(&path, path.len, "%s%s", dir, name);
    } else {
        _ = snprintf(&path, path.len, "%s/%s", dir, name);
    }

    var i: usize = 0;
    while (i < @as(usize, @intCast(watched_files_count))) : (i += 1) {
        if (strcmp(watched_files.?[i].path.?, @ptrCast(&path)) == 0)
            return true;
    }
    return false;
}

fn onInotifyEvent(fd: c_int, mask: u32, data: ?*anyopaque) callconv(.c) c_int {
    _ = mask;
    _ = data;

    var buffer: [4096]u8 align(@alignOf(c.struct_inotify_event)) = undefined;
    var pending = false;

    while (true) {
        const len = read(fd, &buffer, buffer.len);
        if (len < 0) {
            if (c.__errno_location().* == c.EINTR)
                continue;
            break;
        }
        if (len == 0)
            break;

        var offset: usize = 0;
        const total: usize = @intCast(len);
        while (offset + @sizeOf(c.struct_inotify_event) <= total) {
            const event: *const c.struct_inotify_event = @ptrCast(@alignCast(buffer[offset..].ptr));
            if (eventMatches(event))
                pending = true;
            offset += @sizeOf(c.struct_inotify_event) + event.len;
        }
    }

    if (pending)
        scheduleCheck();
    return 0;
}

fn backendInit(loop: *c.struct_wl_event_loop) bool {
    inotify_fd = inotify_init1(c.IN_NONBLOCK | c.IN_CLOEXEC);
    if (inotify_fd < 0)
        return false;

    inotify_source = c.wl_event_loop_add_fd(loop, inotify_fd, c.WL_EVENT_READABLE, onInotifyEvent, null);
    if (inotify_source == null) {
        _ = close(inotify_fd);
        inotify_fd = -1;
        return false;
    }
    return true;
}

fn backendDestroy() void {
    if (inotify_source != null) {
        _ = c.wl_event_source_remove(inotify_source);
        inotify_source = null;
    }
    clearDirWatches();
    if (inotify_fd >= 0) {
        _ = close(inotify_fd);
        inotify_fd = -1;
    }
}

fn backendSync() void {
    if (inotify_fd < 0)
        return;

    clearDirWatches();
    var i: usize = 0;
    while (i < @as(usize, @intCast(watched_files_count))) : (i += 1) {
        const dir = pathDirname(watched_files.?[i].path.?);
        if (dir != null) {
            addDirWatch(dir.?);
            free(@ptrCast(dir));
        }
    }
}

// ---------------------------------------------------------------------------
// timer + exported API
// ---------------------------------------------------------------------------

fn onWatchTimer(data: ?*anyopaque) callconv(.c) c_int {
    _ = data;
    var changed = false;
    var i: usize = 0;
    while (i < @as(usize, @intCast(watched_files_count))) : (i += 1) {
        if (refreshFileState(&watched_files.?[i]))
            changed = true;
    }

    if (changed)
        _ = reload_config(null);
    return 0;
}

export fn config_watcher_init(loop: ?*c.struct_wl_event_loop) callconv(.c) void {
    if (watch_timer != null)
        return;

    watch_timer = c.wl_event_loop_add_timer(loop, onWatchTimer, null);
    if (watch_timer == null) {
        acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "config auto reload disabled: no event loop timer available\n");
        return;
    }

    if (!backendInit(loop.?)) {
        acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "config auto reload disabled: no filesystem event backend available\n");
        return;
    }

    watcher_active = true;
    config_watcher_update();
}

export fn config_watcher_update() callconv(.c) void {
    clearWatchedFiles();

    if (!watcher_active or c.config.auto_reload_config == 0)
        return;

    var count: c_int = 0;
    const paths = config_get_file_paths(&count);
    var i: usize = 0;
    while (i < @as(usize, @intCast(count))) : (i += 1) {
        if (paths[i] != null)
            trackPath(@ptrCast(paths[i]));
    }

    backendSync();
}

export fn config_watcher_destroy() callconv(.c) void {
    backendDestroy();

    if (watch_timer != null) {
        _ = c.wl_event_source_remove(watch_timer);
        watch_timer = null;
    }

    watcher_active = false;
    clearWatchedFiles();
}

// ---------------------------------------------------------------------------
// tests (stub-backed: see tests/watcher_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_paths: [4]?[*:0]u8;
extern var stub_paths_count: c_int;
extern var stub_reload_calls: c_int;
extern var stub_error_count: c_int;

extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*c.FILE;
extern "c" fn fputs(s: [*:0]const u8, f: ?*c.FILE) c_int;
extern "c" fn fclose(f: ?*c.FILE) c_int;
extern "c" fn unlink(path: [*:0]const u8) c_int;

fn writeTemp(comptime path: [:0]const u8, content: []const u8) void {
    const file = fopen(path, "w").?;
    for (content) |ch| {
        const b = [2]u8{ ch, 0 };
        _ = fputs(@ptrCast(&b), file);
    }
    _ = fclose(file);
}

fn appendTemp(comptime path: [:0]const u8, content: []const u8) void {
    const file = fopen(path, "a").?;
    for (content) |ch| {
        const b = [2]u8{ ch, 0 };
        _ = fputs(@ptrCast(&b), file);
    }
    _ = fclose(file);
}

test "pathDirname handles relative, root and nested paths" {
    const d1 = pathDirname("config.conf").?;
    defer free(@ptrCast(d1));
    try testing.expectEqualStrings(".", std.mem.span(@as([*:0]const u8, d1)));

    const d2 = pathDirname("/file.conf").?;
    defer free(@ptrCast(d2));
    try testing.expectEqualStrings("/", std.mem.span(@as([*:0]const u8, d2)));

    const d3 = pathDirname("/etc/acwm/config.conf").?;
    defer free(@ptrCast(d3));
    try testing.expectEqualStrings("/etc/acwm", std.mem.span(@as([*:0]const u8, d3)));
}

test "refreshFileState detects create, modify and delete" {
    var file: WatchedFile = .{};
    file.path = strdup("/tmp/opencode/acwm-watch-state.conf");
    defer free(@ptrCast(file.path));
    _ = unlink("/tmp/opencode/acwm-watch-state.conf");

    // first sight: seen=false -> no change reported, exists=false
    try testing.expect(!refreshFileState(&file));
    try testing.expect(!file.exists);

    writeTemp("/tmp/opencode/acwm-watch-state.conf", "a");
    defer _ = unlink("/tmp/opencode/acwm-watch-state.conf");
    try testing.expect(refreshFileState(&file)); // appeared
    try testing.expect(file.exists);

    try testing.expect(!refreshFileState(&file)); // unchanged

    appendTemp("/tmp/opencode/acwm-watch-state.conf", "b");
    try testing.expect(refreshFileState(&file)); // size/mtime change

    _ = unlink("/tmp/opencode/acwm-watch-state.conf");
    try testing.expect(refreshFileState(&file)); // disappeared
    try testing.expect(!file.exists);
}

test "trackPath deduplicates and snapshots state" {
    clearWatchedFiles();
    defer clearWatchedFiles();

    writeTemp("/tmp/opencode/acwm-watch-track.conf", "x");
    defer _ = unlink("/tmp/opencode/acwm-watch-track.conf");

    trackPath("/tmp/opencode/acwm-watch-track.conf");
    try testing.expectEqual(@as(c_int, 1), watched_files_count);
    try testing.expect(watched_files.?[0].seen);
    try testing.expect(watched_files.?[0].exists);

    trackPath("/tmp/opencode/acwm-watch-track.conf");
    try testing.expectEqual(@as(c_int, 1), watched_files_count);
}

test "watcher init, update, debounce callback and destroy" {
    resetWrapper();
    c.config.auto_reload_config = 1;

    writeTemp("/tmp/opencode/acwm-watch-live.conf", "one");
    defer _ = unlink("/tmp/opencode/acwm-watch-live.conf");
    stub_paths[0] = strdup("/tmp/opencode/acwm-watch-live.conf");
    stub_paths_count = 1;

    config_watcher_init(@ptrFromInt(@alignOf(usize)));
    try testing.expect(watcher_active);
    try testing.expect(inotify_fd >= 0);
    try testing.expectEqual(@as(c_int, 1), watched_files_count);

    // no change yet -> no reload
    _ = onWatchTimer(null);
    try testing.expectEqual(@as(c_int, 0), stub_reload_calls);

    // change -> reload once, then stable
    appendTemp("/tmp/opencode/acwm-watch-live.conf", "two");
    _ = onWatchTimer(null);
    try testing.expectEqual(@as(c_int, 1), stub_reload_calls);
    _ = onWatchTimer(null);
    try testing.expectEqual(@as(c_int, 1), stub_reload_calls);

    // auto reload disabled -> update drops all tracked files
    c.config.auto_reload_config = 0;
    config_watcher_update();
    try testing.expectEqual(@as(c_int, 0), watched_files_count);

    // enabled again -> tracks the path again
    c.config.auto_reload_config = 1;
    config_watcher_update();
    try testing.expectEqual(@as(c_int, 1), watched_files_count);

    config_watcher_destroy();
    try testing.expect(!watcher_active);
    try testing.expectEqual(@as(c_int, 0), watched_files_count);
    try testing.expect(inotify_fd < 0);

    free(@ptrCast(stub_paths[0]));
    stub_paths[0] = null;
    stub_paths_count = 0;
}

/// Resets module state so a test can initialise the watcher from scratch.
fn resetWrapper() void {
    if (watcher_active)
        config_watcher_destroy();
    watcher_active = false;
    watch_timer = null;
    stub_reload_calls = 0;
    stub_error_count = 0;
}
