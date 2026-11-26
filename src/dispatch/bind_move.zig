//! Port of the smart-move/resize, center, spawn and layout-cycle functions
//! from src/dispatch/bind.c (strangler-fig Phase 4, dispatch slice 4,
//! slice 40).
//!
//! switch_keyboard_layout stays C for the keyboard slice.

const std = @import("std");
const c = @import("cc");

const Arg = c.Arg;
const Client = c.Client;
const Monitor = c.Monitor;
const Box = c.struct_wlr_box;
const Layout = c.Layout;
const WlList = c.struct_wl_list;

extern var layouts: [14]Layout;

extern fn get_mon_curtag(m: *const Monitor) callconv(.c) u32;
extern fn client_set_floating(cl: *Client, floating: i32) callconv(.c) void;
extern fn resize(cl: *Client, geo: Box, opts: c.ResizeOpts) callconv(.c) void;
extern fn client_center_geometry(cl: *Client, m: *Monitor, geom: Box, ox: i32, oy: i32) callconv(.c) Box;
extern fn is_scroller_layout(m: *Monitor) callconv(.c) bool;
extern fn scroll_get_stack_head_client(cl: ?*Client) callconv(.c) ?*Client;
extern fn arrange(m: *Monitor, want_animation: bool, from_view: bool) callconv(.c) void;
extern fn clear_fullscreen_and_maximized_state(m: *Monitor) callconv(.c) void;
extern fn printstatus(kind: c.enum_ipc_watch_type) callconv(.c) void;
extern fn client_switch_view(arg: *const Arg, animate: bool) callconv(.c) void;
extern fn xdg_activation_v1_export_token() callconv(.c) [*c]const u8;
extern fn acwm_error_impl(
    log: bool,
    verbosity: c_uint,
    file: [*:0]const u8,
    line: c_int,
    fmt: [*:0]const u8,
    ...) callconv(.c) void;

extern "c" fn fork() c.pid_t;
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn dup2(oldfd: c_int, newfd: c_int) c_int;
extern "c" fn setsid() c.pid_t;
extern "c" fn _exit(status: c_int) noreturn;
extern "c" fn strerror(errnum: c_int) [*:0]u8;
extern "c" fn __errno_location() *c_int;

const Wordexp = extern struct {
    we_wordc: usize,
    we_wordv: [*c][*c]u8,
    we_word_offs: usize,
};

extern "c" fn wordexp(words: [*:0]const u8, p: *Wordexp, flags: c_int) c_int;
extern "c" fn wordfree(p: *Wordexp) void;
extern "c" fn execvp(file: [*:0]const u8, argv: [*c]const [*c]u8) c_int;

const EXIT_FAILURE = 1;
const WLR_ERROR: c_uint = @intCast(c.WLR_ERROR);
const WLR_DEBUG: c_uint = @intCast(c.WLR_DEBUG);
const WLR_INFO: c_uint = @intCast(c.WLR_INFO);

fn clientOpt(p: [*c]Client) ?*Client {
    return if (p == null) null else @ptrCast(p);
}

fn monitorOpt(p: [*c]Monitor) ?*Monitor {
    return if (p == null) null else @ptrCast(p);
}

fn containerOf(comptime T: type, comptime link_field: []const u8, link: [*c]WlList) *T {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(T, link_field));
}

fn listHead(head: *WlList) [*c]WlList {
    return @ptrCast(head);
}

fn VISIBLEON(cl: *const Client, m: *const Monitor) bool {
    if (cl.mon != @as([*c]Monitor, @ptrCast(@constCast(m))))
        return false;
    if (cl.isminimized != 0)
        return false;
    return (cl.tags & m.tagset[m.seltags]) != 0 or cl.isglobal != 0 or cl.isunglobal != 0;
}

fn selectedClient(arg: *const Arg) ?*Client {
    if (clientOpt(arg.tc)) |cl|
        return cl;
    const m = monitorOpt(c.server.selected_monitor) orelse return null;
    return clientOpt(m.sel);
}

// ---------------------------------------------------------------------------
// smart move / resize
// ---------------------------------------------------------------------------

export fn smart_move_window(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    const cl = selectedClient(arg) orelse return 0;
    if (cl.isfullscreen != 0)
        return 0;
    const clmon = monitorOpt(cl.mon) orelse return 0;
    if (cl.isfloating == 0)
        client_set_floating(cl, 1);

    var nx = cl.geom.x;
    var ny = cl.geom.y;
    const gappiv: i32 = @intCast(c.config.gappiv);
    const gappih: i32 = @intCast(c.config.gappih);
    const gappov = clmon.gappov;
    const gappoh = clmon.gappoh;

    switch (arg.i) {
        c.UP => {
            var tar: i32 = -99999;
            const top = cl.geom.y;
            ny -= @divTrunc(clmon.w.height, 4);

            var pos = c.server.clients.next;
            const head = listHead(&c.server.clients);
            while (pos != head) : (pos = pos.*.next) {
                const tc = containerOf(Client, "link", pos);
                if (!VISIBLEON(tc, m) or tc.isfloating == 0 or tc == cl)
                    continue;
                if (cl.geom.x + cl.geom.width < tc.geom.x or
                    cl.geom.x > tc.geom.x + tc.geom.width)
                    continue;
                const bottom = tc.geom.y + tc.geom.height + gappiv;
                if (top > bottom and ny < bottom)
                    tar = @max(tar, bottom);
            }
            ny = if (tar == -99999) ny else tar;
            ny = @max(ny, clmon.w.y + gappov);
        },
        c.DOWN => {
            var tar: i32 = 99999;
            const bottom = cl.geom.y + cl.geom.height;
            ny += @divTrunc(clmon.w.height, 4);

            var pos = c.server.clients.next;
            const head = listHead(&c.server.clients);
            while (pos != head) : (pos = pos.*.next) {
                const tc = containerOf(Client, "link", pos);
                if (!VISIBLEON(tc, m) or tc.isfloating == 0 or tc == cl)
                    continue;
                if (cl.geom.x + cl.geom.width < tc.geom.x or
                    cl.geom.x > tc.geom.x + tc.geom.width)
                    continue;
                const top = tc.geom.y - gappiv;
                if (bottom < top and (ny + cl.geom.height) > top)
                    tar = @min(tar, top - cl.geom.height);
            }
            ny = if (tar == 99999) ny else tar;
            ny = @min(ny, clmon.w.y + clmon.w.height - cl.geom.height - gappov);
        },
        c.LEFT => {
            var tar: i32 = -99999;
            const left = cl.geom.x;
            nx -= @divTrunc(clmon.w.width, 6);

            var pos = c.server.clients.next;
            const head = listHead(&c.server.clients);
            while (pos != head) : (pos = pos.*.next) {
                const tc = containerOf(Client, "link", pos);
                if (!VISIBLEON(tc, m) or tc.isfloating == 0 or tc == cl)
                    continue;
                if (cl.geom.y + cl.geom.height < tc.geom.y or
                    cl.geom.y > tc.geom.y + tc.geom.height)
                    continue;
                const right = tc.geom.x + tc.geom.width + gappih;
                if (left > right and nx < right)
                    tar = @max(tar, right);
            }
            nx = if (tar == -99999) nx else tar;
            nx = @max(nx, clmon.w.x + gappoh);
        },
        c.RIGHT => {
            var tar: i32 = 99999;
            const right = cl.geom.x + cl.geom.width;
            nx += @divTrunc(clmon.w.width, 6);

            var pos = c.server.clients.next;
            const head = listHead(&c.server.clients);
            while (pos != head) : (pos = pos.*.next) {
                const tc = containerOf(Client, "link", pos);
                if (!VISIBLEON(tc, m) or tc.isfloating == 0 or tc == cl)
                    continue;
                if (cl.geom.y + cl.geom.height < tc.geom.y or
                    cl.geom.y > tc.geom.y + tc.geom.height)
                    continue;
                const left = tc.geom.x - gappih;
                if (right < left and (nx + cl.geom.width) > left)
                    tar = @min(tar, left - cl.geom.width);
            }
            nx = if (tar == 99999) nx else tar;
            nx = @min(nx, clmon.w.x + clmon.w.width - cl.geom.width - gappoh);
        },
        else => {},
    }

    cl.float_geom = .{ .x = nx, .y = ny, .width = cl.geom.width, .height = cl.geom.height };
    cl.iscustomsize = 1;
    resize(cl, cl.float_geom, .{ .interact = true });
    return 0;
}

export fn smart_resize_window(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    const cl = selectedClient(arg) orelse return 0;
    if (cl.isfullscreen != 0)
        return 0;
    if (cl.isfloating == 0)
        client_set_floating(cl, 1);

    const gappiv: i32 = @intCast(c.config.gappiv);
    const gappih: i32 = @intCast(c.config.gappih);
    const gappov: i32 = @intCast(c.config.gappov);
    const gappoh: i32 = @intCast(c.config.gappoh);

    var nw = cl.geom.width;
    var nh = cl.geom.height;

    switch (arg.i) {
        c.UP => {
            nh -= @divTrunc(m.w.height, 8);
            nh = @max(nh, @divTrunc(m.w.height, 10));
        },
        c.DOWN => {
            var tar: i32 = -99999;
            const bottom = cl.geom.y + cl.geom.height;
            nh += @divTrunc(m.w.height, 8);

            var pos = c.server.clients.next;
            const head = listHead(&c.server.clients);
            while (pos != head) : (pos = pos.*.next) {
                const tc = containerOf(Client, "link", pos);
                if (!VISIBLEON(tc, m) or tc.isfloating == 0 or tc == cl)
                    continue;
                if (cl.geom.x + cl.geom.width < tc.geom.x or
                    cl.geom.x > tc.geom.x + tc.geom.width)
                    continue;
                const top = tc.geom.y - gappiv;
                if (bottom < top and (nh + cl.geom.y) > top)
                    tar = @max(tar, top - cl.geom.y);
            }
            nh = if (tar == -99999) nh else tar;
            if (cl.geom.y + nh + gappov > m.w.y + m.w.height)
                nh = m.w.y + m.w.height - cl.geom.y - gappov;
        },
        c.LEFT => {
            nw -= @divTrunc(m.w.width, 16);
            nw = @max(nw, @divTrunc(m.w.width, 10));
        },
        c.RIGHT => {
            var tar: i32 = 99999;
            const right = cl.geom.x + cl.geom.width;
            nw += @divTrunc(m.w.width, 16);

            var pos = c.server.clients.next;
            const head = listHead(&c.server.clients);
            while (pos != head) : (pos = pos.*.next) {
                const tc = containerOf(Client, "link", pos);
                if (!VISIBLEON(tc, m) or tc.isfloating == 0 or tc == cl)
                    continue;
                if (cl.geom.y + cl.geom.height < tc.geom.y or
                    cl.geom.y > tc.geom.y + tc.geom.height)
                    continue;
                const left = tc.geom.x - gappih;
                if (right < left and (nw + cl.geom.x) > left)
                    tar = @min(tar, left - cl.geom.x);
            }
            nw = if (tar == 99999) nw else tar;
            if (cl.geom.x + nw + gappoh > m.w.x + m.w.width)
                nw = m.w.x + m.w.width - cl.geom.x - gappoh;
        },
        else => {},
    }

    cl.float_geom = .{ .x = cl.geom.x, .y = cl.geom.y, .width = nw, .height = nh };
    cl.iscustomsize = 1;
    resize(cl, cl.float_geom, .{ .interact = true });
    return 0;
}

export fn center_window(arg: *const Arg) callconv(.c) i32 {
    const cl = selectedClient(arg) orelse return 0;
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;

    if (cl.isfullscreen != 0 or cl.ismaximizescreen != 0)
        return 0;

    if (cl.isfloating != 0) {
        const clmon = monitorOpt(cl.mon) orelse return 0;
        cl.float_geom = client_center_geometry(cl, clmon, cl.geom, 0, 0);
        cl.iscustomsize = 1;
        resize(cl, cl.float_geom, .{ .interact = true });
        return 0;
    }

    if (!is_scroller_layout(m))
        return 0;

    const head = scroll_get_stack_head_client(cl) orelse return 0;
    const layout = m.pertag.*.ltidxs[@intCast(get_mon_curtag(m))];
    if (layout.*.id == c.SCROLLER) {
        head.geom.x = m.w.x + @divTrunc(m.w.width - head.geom.width, 2);
    } else {
        head.geom.y = m.w.y + @divTrunc(m.w.height - head.geom.height, 2);
    }

    arrange(m, false, false);
    return 0;
}

// ---------------------------------------------------------------------------
// spawn
// ---------------------------------------------------------------------------

export fn spawn_shell(arg: *const Arg) callconv(.c) i32 {
    if (arg.v == null)
        return 0;

    const token = xdg_activation_v1_export_token();
    if (fork() == 0) {
        if (token != null)
            _ = setenv("XDG_ACTIVATION_TOKEN", @ptrCast(token), 1);
        _ = dup2(c.STDERR_FILENO, c.STDOUT_FILENO);
        _ = setsid();

        _ = c.execlp("sh", "sh", "-c", arg.v, @as([*c]const u8, null));
        _ = c.execlp("bash", "bash", "-c", arg.v, @as([*c]const u8, null));

        acwm_error_impl(true, WLR_DEBUG, @src().file, @src().line, "acwm: failed to execute command '%s' with shell: %s\n", arg.v, strerror(__errno_location().*));
        _exit(EXIT_FAILURE);
    }
    return 0;
}

export fn spawn(arg: *const Arg) callconv(.c) i32 {
    if (arg.v == null)
        return 0;

    const token = xdg_activation_v1_export_token();
    if (fork() == 0) {
        if (token != null)
            _ = setenv("XDG_ACTIVATION_TOKEN", @ptrCast(token), 1);
        _ = dup2(c.STDERR_FILENO, c.STDOUT_FILENO);
        _ = setsid();

        var p: Wordexp = std.mem.zeroes(Wordexp);
        if (wordexp(@ptrCast(arg.v), &p, 0) != 0) {
            acwm_error_impl(true, WLR_DEBUG, @src().file, @src().line, "acwm: wordexp failed for '%s'\n", arg.v);
            _exit(EXIT_FAILURE);
        }

        _ = execvp(@ptrCast(p.we_wordv[0]), p.we_wordv);

        acwm_error_impl(true, WLR_DEBUG, @src().file, @src().line, "acwm: execvp '%s' failed: %s\n", p.we_wordv[0], strerror(__errno_location().*));
        wordfree(&p);
        _exit(EXIT_FAILURE);
    }
    return 0;
}

export fn spawn_on_empty(arg: *const Arg) callconv(.c) i32 {
    const selected = monitorOpt(c.server.selected_monitor);
    var is_empty = true;

    var pos = c.server.clients.next;
    const head = listHead(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if ((arg.ui & cl.tags) != 0 and cl.mon == @as([*c]Monitor, @ptrCast(selected orelse null))) {
            is_empty = false;
            break;
        }
    }

    client_switch_view(arg, true);
    if (is_empty)
        _ = spawn_shell(arg);
    return 0;
}

// ---------------------------------------------------------------------------
// layout cycling
// ---------------------------------------------------------------------------

export fn switch_layout(arg: *const Arg) callconv(.c) i32 {
    _ = arg;
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    const tag = get_mon_curtag(m);
    const current = m.pertag.*.ltidxs[@intCast(tag)];
    const current_name = std.mem.span(@as([*:0]const u8, @ptrCast(current.*.name)));

    if (c.config.circle_layout_count != 0) {
        var target: ?[]const u8 = null;
        var jk: usize = 0;
        const count: usize = @intCast(c.config.circle_layout_count);
        while (jk < count) : (jk += 1) {
            const circle_name = std.mem.span(@as([*:0]const u8, @ptrCast(c.config.circle_layout[jk])));
            if (std.mem.eql(u8, circle_name, current_name)) {
                const next_name = if (jk == count - 1)
                    c.config.circle_layout[0]
                else
                    c.config.circle_layout[jk + 1];
                target = std.mem.span(@as([*:0]const u8, @ptrCast(next_name)));
                break;
            }
        }
        if (target == null)
            target = std.mem.span(@as([*:0]const u8, @ptrCast(c.config.circle_layout[0])));

        for (&layouts) |*layout| {
            const lname = std.mem.span(@as([*:0]const u8, @ptrCast(layout.name)));
            if (std.mem.eql(u8, lname, target.?)) {
                m.pertag.*.ltidxs[@intCast(tag)] = layout;
                break;
            }
        }
        clear_fullscreen_and_maximized_state(m);
        arrange(m, false, false);
        printstatus(c.IPC_WATCH_ARRANGGE);
        return 0;
    }

    var jk: usize = 0;
    while (jk < layouts.len) : (jk += 1) {
        const lname = std.mem.span(@as([*:0]const u8, @ptrCast(layouts[jk].name)));
        if (std.mem.eql(u8, lname, current_name)) {
            m.pertag.*.ltidxs[@intCast(tag)] = if (jk == layouts.len - 1)
                &layouts[0]
            else
                &layouts[jk + 1];
            clear_fullscreen_and_maximized_state(m);
            arrange(m, false, false);
            printstatus(c.IPC_WATCH_ARRANGGE);
            return 0;
        }
    }
    return 0;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/bind_move_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_circle: [4][*c]u8;
extern var stub_center_box: Box;
extern var stub_head_client: ?*Client;
extern var stub_is_scroller: bool;
extern var stub_token_calls: u32;
extern var stub_fork_calls: c_int;
extern var stub_floating_calls: c_int;
extern var stub_floating_arg: i32;
extern var stub_resize_calls: c_int;
extern var stub_resize_box: Box;
extern var stub_arrange_calls: c_int;
extern var stub_clear_fs_calls: c_int;
extern var stub_printstatus_calls: c_int;
extern var stub_switch_view_calls: c_int;
extern var stub_switch_view_ui: u32;

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

fn resetWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    listInit(&c.server.clients);
    listInit(&c.server.monitors);
    stub_head_client = null;
    stub_is_scroller = false;
    stub_token_calls = 0;
    stub_fork_calls = 0;
    stub_floating_calls = 0;
    stub_floating_arg = 0;
    stub_resize_calls = 0;
    stub_resize_box = std.mem.zeroes(Box);
    stub_arrange_calls = 0;
    stub_clear_fs_calls = 0;
    stub_printstatus_calls = 0;
    stub_switch_view_calls = 0;
    stub_switch_view_ui = 0;
}

fn baseMonitor(m: *Monitor, p: *c.Pertag, out: *c.struct_wlr_output) void {
    m.* = std.mem.zeroes(Monitor);
    p.* = std.mem.zeroes(c.Pertag);
    out.* = std.mem.zeroes(c.struct_wlr_output);
    out.enabled = true;
    m.pertag = p;
    m.wlr_output = @ptrCast(out);
    m.w = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
    m.tagset[0] = 1;
    m.seltags = 0;
    m.gappov = 10;
    m.gappoh = 10;
    p.ltidxs[0] = @ptrCast(&layouts[0]);
}

fn addClient(cl: *Client, m: *Monitor, tags: u32) void {
    cl.* = std.mem.zeroes(Client);
    cl.mon = @ptrCast(m);
    cl.tags = tags;
    listInsert(&c.server.clients, &cl.link);
}

test "smart_move_window snaps above/below/left/right neighbours" {
    var arg = std.mem.zeroes(Arg);

    {
        resetWorld();
        var p: c.Pertag = undefined;
        var out: c.struct_wlr_output = undefined;
        var m: Monitor = undefined;
        baseMonitor(&m, &p, &out);
        var a: Client = undefined;
        var ob: Client = undefined;
        addClient(&a, &m, 1);
        addClient(&ob, &m, 1);
        a.isfloating = 1;
        a.geom = .{ .x = 100, .y = 100, .width = 200, .height = 100 };
        ob.isfloating = 1;
        ob.geom = .{ .x = 100, .y = -50, .width = 200, .height = 100 };
        c.server.selected_monitor = &m;
        c.config.gappiv = 5;

        arg.i = c.UP;
        arg.tc = @ptrCast(&a);
        _ = smart_move_window(&arg);
        try testing.expectEqual(@as(i32, 55), a.float_geom.y);
        try testing.expectEqual(@as(c_int, 1), stub_resize_calls);
        try testing.expectEqual(@as(i32, 1), a.iscustomsize);
    }

    {
        resetWorld();
        var p: c.Pertag = undefined;
        var out: c.struct_wlr_output = undefined;
        var m: Monitor = undefined;
        baseMonitor(&m, &p, &out);
        var a: Client = undefined;
        var ob: Client = undefined;
        addClient(&a, &m, 1);
        addClient(&ob, &m, 1);
        a.isfloating = 1;
        a.geom = .{ .x = 100, .y = 100, .width = 200, .height = 100 };
        ob.isfloating = 1;
        ob.geom = .{ .x = 100, .y = 350, .width = 200, .height = 100 };
        c.server.selected_monitor = &m;
        c.config.gappiv = 5;

        arg.i = c.DOWN;
        arg.tc = @ptrCast(&a);
        _ = smart_move_window(&arg);
        try testing.expectEqual(@as(i32, 245), a.float_geom.y);
    }

    {
        resetWorld();
        var p: c.Pertag = undefined;
        var out: c.struct_wlr_output = undefined;
        var m: Monitor = undefined;
        baseMonitor(&m, &p, &out);
        var a: Client = undefined;
        var ob: Client = undefined;
        addClient(&a, &m, 1);
        addClient(&ob, &m, 1);
        a.isfloating = 1;
        a.geom = .{ .x = 100, .y = 100, .width = 200, .height = 100 };
        ob.isfloating = 1;
        ob.geom = .{ .x = -50, .y = 0, .width = 50, .height = 200 };
        c.server.selected_monitor = &m;
        c.config.gappih = 5;

        arg.i = c.LEFT;
        arg.tc = @ptrCast(&a);
        _ = smart_move_window(&arg);
        try testing.expectEqual(@as(i32, 10), a.float_geom.x);
    }

    {
        resetWorld();
        var p: c.Pertag = undefined;
        var out: c.struct_wlr_output = undefined;
        var m: Monitor = undefined;
        baseMonitor(&m, &p, &out);
        var a: Client = undefined;
        var ob: Client = undefined;
        addClient(&a, &m, 1);
        addClient(&ob, &m, 1);
        a.isfloating = 1;
        a.geom = .{ .x = 100, .y = 100, .width = 200, .height = 100 };
        ob.isfloating = 1;
        ob.geom = .{ .x = 400, .y = 100, .width = 100, .height = 100 };
        c.server.selected_monitor = &m;
        c.config.gappih = 5;

        arg.i = c.RIGHT;
        arg.tc = @ptrCast(&a);
        _ = smart_move_window(&arg);
        try testing.expectEqual(@as(i32, 195), a.float_geom.x);
    }
}

test "smart_resize_window snaps and clamps dimensions" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    var a: Client = undefined;
    addClient(&a, &m, 1);
    a.isfloating = 1;
    a.geom = .{ .x = 100, .y = 100, .width = 200, .height = 100 };
    c.server.selected_monitor = &m;
    c.config.gappiv = 5;
    c.config.gappih = 5;

    var arg = std.mem.zeroes(Arg);
    arg.tc = @ptrCast(&a);
    arg.i = c.UP;
    _ = smart_resize_window(&arg);
    try testing.expectEqual(@as(i32, 80), a.float_geom.height);

    a.geom = .{ .x = 100, .y = 100, .width = 200, .height = 100 };
    arg.i = c.LEFT;
    _ = smart_resize_window(&arg);
    try testing.expectEqual(@as(i32, 138), a.float_geom.width);

    var ob: Client = undefined;
    addClient(&ob, &m, 1);
    ob.isfloating = 1;
    ob.geom = .{ .x = 100, .y = 250, .width = 200, .height = 100 };
    a.geom = .{ .x = 100, .y = 100, .width = 200, .height = 100 };
    arg.i = c.DOWN;
    _ = smart_resize_window(&arg);
    try testing.expectEqual(@as(i32, 145), a.float_geom.height);

    ob.geom = .{ .x = 350, .y = 100, .width = 100, .height = 100 };
    a.geom = .{ .x = 100, .y = 100, .width = 200, .height = 100 };
    arg.i = c.RIGHT;
    _ = smart_resize_window(&arg);
    try testing.expectEqual(@as(i32, 245), a.float_geom.width);
}

test "center_window centers floating clients and scroller heads" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    var a: Client = undefined;
    addClient(&a, &m, 1);
    c.server.selected_monitor = &m;
    a.isfloating = 1;
    a.geom = .{ .x = 1, .y = 2, .width = 10, .height = 20 };
    var arg = std.mem.zeroes(Arg);
    arg.tc = @ptrCast(&a);

    _ = center_window(&arg);
    try testing.expectEqual(@as(i32, 11), a.float_geom.x);
    try testing.expectEqual(@as(i32, 22), a.float_geom.y);
    try testing.expectEqual(@as(c_int, 1), stub_resize_calls);

    a.isfloating = 0;
    a.geom = .{ .x = 100, .y = 100, .width = 200, .height = 100 };
    stub_is_scroller = true;
    stub_head_client = &a;
    p.ltidxs[0] = @ptrCast(&layouts[1]);

    _ = center_window(&arg);
    try testing.expectEqual(@as(i32, 400), a.geom.x);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);

    p.ltidxs[0] = @ptrCast(&layouts[7]);
    _ = center_window(&arg);
    try testing.expectEqual(@as(i32, 350), a.geom.y);
}

test "spawn helpers only fork with a command" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    c.server.selected_monitor = &m;

    var arg = std.mem.zeroes(Arg);
    arg.v = @ptrCast(@constCast("true"));
    _ = spawn_shell(&arg);
    try testing.expectEqual(@as(c_int, 1), stub_fork_calls);
    try testing.expectEqual(@as(u32, 1), stub_token_calls);

    _ = spawn(&arg);
    try testing.expectEqual(@as(c_int, 2), stub_fork_calls);
    try testing.expectEqual(@as(u32, 2), stub_token_calls);

    arg.v = null;
    _ = spawn_shell(&arg);
    _ = spawn(&arg);
    try testing.expectEqual(@as(c_int, 2), stub_fork_calls);
}

test "spawn_on_empty switches view and spawns only on empty tags" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    c.server.selected_monitor = &m;

    var arg = std.mem.zeroes(Arg);
    arg.v = @ptrCast(@constCast("true"));
    arg.ui = 1;
    _ = spawn_on_empty(&arg);
    try testing.expectEqual(@as(c_int, 1), stub_switch_view_calls);
    try testing.expectEqual(@as(c_int, 1), stub_fork_calls);

    var a: Client = undefined;
    addClient(&a, &m, 1);
    _ = spawn_on_empty(&arg);
    try testing.expectEqual(@as(c_int, 2), stub_switch_view_calls);
    try testing.expectEqual(@as(c_int, 1), stub_fork_calls);
}

test "switch_layout cycles the table and circles configured layouts" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    c.server.selected_monitor = &m;

    var arg = std.mem.zeroes(Arg);
    _ = switch_layout(&arg);
    try testing.expect(p.ltidxs[0] == @as([*c]const Layout, @ptrCast(&layouts[1])));
    try testing.expectEqual(@as(c_int, 1), stub_clear_fs_calls);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);
    try testing.expectEqual(@as(c_int, 1), stub_printstatus_calls);

    p.ltidxs[0] = @ptrCast(&layouts[13]);
    _ = switch_layout(&arg);
    try testing.expect(p.ltidxs[0] == @as([*c]const Layout, @ptrCast(&layouts[0])));

    c.config.circle_layout_count = 2;
    c.config.circle_layout = @ptrCast(&stub_circle);
    p.ltidxs[0] = @ptrCast(&layouts[2]);
    _ = switch_layout(&arg);
    try testing.expect(p.ltidxs[0] == @as([*c]const Layout, @ptrCast(&layouts[3])));

    p.ltidxs[0] = @ptrCast(&layouts[8]);
    _ = switch_layout(&arg);
    try testing.expect(p.ltidxs[0] == @as([*c]const Layout, @ptrCast(&layouts[2])));
}
