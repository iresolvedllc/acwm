//! Port of switch_keyboard_layout and the overview enter/leave/jump cluster
//! of src/dispatch/bind.c (strangler-fig Phase 4, dispatch slice 7,
//! slice 43 — completes bind.c).

const std = @import("std");
const c = @import("cc");

const Arg = c.Arg;
const Client = c.Client;
const Monitor = c.Monitor;
const WlList = c.struct_wl_list;

extern fn xkb_state_serialize_layout(state: ?*c.struct_xkb_state, components: c.enum_xkb_state_component) callconv(.c) c.xkb_layout_index_t;
extern fn xkb_keymap_num_layouts(keymap: ?*c.struct_xkb_keymap) callconv(.c) c.xkb_layout_index_t;
extern fn wlr_keyboard_notify_modifiers(keyboard: [*c]c.struct_wlr_keyboard, depressed: u32, latched: u32, locked: u32, group: c.xkb_layout_index_t) callconv(.c) void;
extern fn wlr_seat_set_keyboard(seat: ?*c.struct_wlr_seat, keyboard: [*c]c.struct_wlr_keyboard) callconv(.c) void;
extern fn wlr_seat_keyboard_notify_modifiers(seat: ?*c.struct_wlr_seat, modifiers: [*c]c.struct_wlr_keyboard_modifiers) callconv(.c) void;
extern fn wlr_seat_pointer_clear_focus(seat: ?*c.struct_wlr_seat) callconv(.c) void;
extern fn wlr_cursor_set_xcursor(cursor: [*c]c.struct_wlr_cursor, manager: [*c]c.struct_wlr_xcursor_manager, name: [*c]const u8) callconv(.c) void;
extern fn pointer_cursor_activity() callconv(.c) void;

extern fn get_tags_first_tag(tags: u32) callconv(.c) u32;
extern fn get_tags_first_tag_num(tags: u32) callconv(.c) u32;
extern fn client_switch_view(arg: *const Arg, animate: bool) callconv(.c) void;
extern fn client_focus(cl: ?*Client, lift: i32) callconv(.c) void;
extern fn client_is_unmanaged(cl: ?*Client) callconv(.c) c_int;
extern fn client_is_x11_popup(cl: ?*Client) callconv(.c) c_int;
extern fn client_surface(cl: ?*Client) callconv(.c) ?*c.struct_wlr_surface;
extern fn overview_backup(cl: *Client) callconv(.c) void;
extern fn overview_restore(cl: *Client, arg: *const Arg) callconv(.c) void;
extern fn refresh_monitors_workspaces_status(m: ?*Monitor) callconv(.c) void;
extern fn arrange(m: *Monitor, want_animation: bool, from_view: bool) callconv(.c) void;
extern fn begin_jump_mode(m: *Monitor) callconv(.c) void;
extern fn finish_jump_mode(m: *Monitor) callconv(.c) void;
extern fn printstatus(kind: c.enum_ipc_watch_type) callconv(.c) void;
extern fn acwm_error_impl(log: bool, verbosity: c_uint, file: [*:0]const u8, line: c_int, fmt: [*:0]const u8, ...) callconv(.c) void;

const WLR_ERROR: c_uint = @intCast(c.WLR_ERROR);
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

fn tag0Mask() u32 {
    return @bitCast(c.TAG0_MASK);
}

fn serviceMapped(cl: *Client) bool {
    const surface = client_surface(cl) orelse return false;
    return surface.mapped;
}

// ---------------------------------------------------------------------------
// keyboard layout
// ---------------------------------------------------------------------------

export fn switch_keyboard_layout(arg: *const Arg) callconv(.c) i32 {
    const group = c.server.keyboard_group;
    if (group == null or group.*.wlr_group == null or c.server.seat == null) {
        acwm_error_impl(true, WLR_ERROR, @src().file, @src().line, "Invalid keyboard group or seat");
        return 0;
    }

    const keyboard = &group.*.wlr_group.*.keyboard;
    if (keyboard.keymap == null) {
        acwm_error_impl(true, WLR_ERROR, @src().file, @src().line, "Invalid keyboard or keymap");
        return 0;
    }

    const current = xkb_state_serialize_layout(keyboard.xkb_state, c.XKB_STATE_LAYOUT_EFFECTIVE);
    const num_layouts: i32 = @intCast(xkb_keymap_num_layouts(keyboard.keymap));
    if (num_layouts < 2) {
        acwm_error_impl(true, WLR_INFO, @src().file, @src().line, "Only one layout available");
        return 0;
    }

    var next: c.xkb_layout_index_t = 0;
    if (arg.i > 0 and arg.i <= num_layouts) {
        next = @intCast(arg.i - 1);
    } else {
        next = @intCast(@mod(@as(i32, @intCast(current)) + 1, num_layouts));
    }

    const depressed: u32 = keyboard.modifiers.depressed;
    const latched: u32 = keyboard.modifiers.latched;
    const locked_mods: u32 = keyboard.modifiers.locked;

    wlr_keyboard_notify_modifiers(keyboard, depressed, latched, locked_mods, next);
    wlr_seat_set_keyboard(c.server.seat, keyboard);
    wlr_seat_keyboard_notify_modifiers(c.server.seat, &keyboard.modifiers);

    var pos = c.server.input_devices.next;
    const head = listHead(&c.server.input_devices);
    while (pos != head) : (pos = pos.*.next) {
        const id = containerOf(c.InputDevice, "link", pos);
        if (id.wlr_device.*.type != c.WLR_INPUT_DEVICE_KEYBOARD or id.standalone)
            continue;

        const tkb: *c.struct_wlr_keyboard = @ptrCast(@alignCast(id.device_data));
        wlr_keyboard_notify_modifiers(tkb, depressed, latched, locked_mods, next);
        wlr_seat_set_keyboard(c.server.seat, tkb);
        wlr_seat_keyboard_notify_modifiers(c.server.seat, &tkb.modifiers);
    }

    printstatus(c.IPC_WATCH_KB_LAYOUT);
    return 0;
}

// ---------------------------------------------------------------------------
// overview
// ---------------------------------------------------------------------------

export fn fix_mon_tagset_from_overview(m: *Monitor) callconv(.c) void {
    if (m.tagset[m.seltags] == (m.ovbk_prev_tagset & c.server.tagmask)) {
        m.tagset[m.seltags ^ 1] = m.ovbk_current_tagset;
        m.pertag.*.prevtag = get_tags_first_tag_num(m.ovbk_current_tagset);
    } else {
        m.tagset[m.seltags ^ 1] = m.ovbk_prev_tagset;
        m.pertag.*.prevtag = get_tags_first_tag_num(m.ovbk_prev_tagset);
    }
}

fn overviewClientOnCurrentTags(cl: *Client, only_current: bool, current_tags: u32) bool {
    return !only_current or cl.isglobal != 0 or (cl.tags & current_tags) != 0;
}

fn setOverview(arg: *const Arg, enter: bool) void {
    const m = monitorOpt(c.server.selected_monitor) orelse return;
    const sel = clientOpt(arg.tc) orelse clientOpt(m.sel);
    var target: u32 = 0;
    var visible_client_number: u32 = 0;
    const only_current = arg.i == 1;
    var current_tags: u32 = 0;

    m.isoverview = if (enter) 1 else 0;

    if (!enter) {
        m.ov_tab_layout = 0;
        if (m.is_jump_mode != 0)
            finish_jump_mode(m);
    }

    if (enter) {
        current_tags = m.tagset[m.seltags] & c.server.tagmask;
        var pos = c.server.clients.next;
        const head = listHead(&c.server.clients);
        while (pos != head) : (pos = pos.*.next) {
            const cl = containerOf(Client, "link", pos);
            if (cl.mon != @as([*c]Monitor, @ptrCast(m)))
                continue;
            if (client_is_unmanaged(cl) == 0 and client_is_x11_popup(cl) == 0 and
                cl.isminimized == 0 and cl.isunglobal == 0 and
                (cl.tags & tag0Mask()) == 0 and
                overviewClientOnCurrentTags(cl, only_current, current_tags))
                visible_client_number += 1;
        }
        if (visible_client_number > 0) {
            m.ovbk_current_tagset = m.tagset[m.seltags];
            m.ovbk_prev_tagset = m.tagset[m.seltags ^ 1];
            target = if (only_current) current_tags else (~@as(u32, 0) & c.server.tagmask);
        } else {
            m.isoverview = 0;
            m.ov_tab_layout = 0;
            return;
        }
    } else if (sel != null and (sel.?.tags & c.server.tagmask) != 0) {
        target = get_tags_first_tag(sel.?.tags);
    } else {
        target = if (m.ovbk_current_tagset != 0)
            (m.ovbk_current_tagset & c.server.tagmask)
        else if (m.pertag.*.prevtag != 0)
            (@as(u32, 1) << @intCast(m.pertag.*.prevtag - 1))
        else
            1;
        if (target == 0)
            target = 1;
    }

    if (enter) {
        wlr_seat_pointer_clear_focus(c.server.seat);

        if (c.server.cursor_hidden) {
            pointer_cursor_activity();
        } else {
            wlr_cursor_set_xcursor(c.server.cursor, c.server.cursor_manager, "default");
        }

        var pos = c.server.clients.next;
        const head = listHead(&c.server.clients);
        while (pos != head) : (pos = pos.*.next) {
            const cl = containerOf(Client, "link", pos);
            if (cl.mon != @as([*c]Monitor, @ptrCast(m)))
                continue;
            if (client_is_unmanaged(cl) != 0 or client_is_x11_popup(cl) != 0 or
                cl.isunglobal != 0 or cl.isminimized != 0 or
                (cl.tags & tag0Mask()) != 0 or !serviceMapped(cl) or
                !overviewClientOnCurrentTags(cl, only_current, current_tags))
                continue;
            cl.animation.overining = true;
            if (m.is_jump_mode == 0 and m.ov_normal_mode == 0)
                cl.animation.overview_enter_anim_set = true
            else
                cl.animation.overview_enter_anim_set = false;
            overview_backup(cl);
        }
    } else {
        m.ov_normal_mode = 0;
        m.tagset[m.seltags] = target;

        var pos = c.server.clients.next;
        const head = listHead(&c.server.clients);
        while (pos != head) : (pos = pos.*.next) {
            const cl = containerOf(Client, "link", pos);
            if (cl.mon == @as([*c]Monitor, @ptrCast(m)) and cl.iskilling == 0 and
                client_is_unmanaged(cl) == 0 and cl.isunglobal == 0 and
                cl.isminimized == 0 and client_is_x11_popup(cl) == 0 and
                serviceMapped(cl) and (cl.tags & tag0Mask()) == 0)
            {
                var a = std.mem.zeroes(Arg);
                a.ui = target;
                overview_restore(cl, &a);
            }
        }
    }

    var switch_arg = std.mem.zeroes(Arg);
    switch_arg.ui = target;
    client_switch_view(&switch_arg, false);

    if (enter and m.is_jump_mode == 0 and m.ov_normal_mode == 0) {
        var pos = c.server.clients.next;
        const head = listHead(&c.server.clients);
        while (pos != head) : (pos = pos.*.next) {
            const cl = containerOf(Client, "link", pos);
            if (cl.mon == @as([*c]Monitor, @ptrCast(m)) and
                client_is_unmanaged(cl) == 0 and client_is_x11_popup(cl) == 0 and
                (cl.tags & tag0Mask()) == 0)
                cl.animation.overview_enter_anim_set = false;
        }
        arrange(m, true, false);
    }

    fix_mon_tagset_from_overview(m);
    refresh_monitors_workspaces_status(m);

    if (!enter and sel != null and (sel.?.tags & target) != 0)
        client_focus(sel, 1);
}

export fn toggle_overview(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    if (c.server.grab_client != null)
        return 0;
    setOverview(arg, m.isoverview == 0);
    return 0;
}

export fn enter_overview(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    if (c.server.grab_client != null or m.isoverview != 0)
        return 0;
    setOverview(arg, true);
    return 0;
}

export fn leave_overview(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    if (c.server.grab_client != null or m.isoverview == 0)
        return 0;
    setOverview(arg, false);
    return 0;
}

export fn toggle_jump(arg: *const Arg) callconv(.c) i32 {
    const m = monitorOpt(c.server.selected_monitor) orelse return 0;
    if (m.isoverview == 0) {
        begin_jump_mode(m);
        _ = toggle_overview(arg);
        return 0;
    }
    if (m.isoverview != 0)
        _ = toggle_overview(arg);
    return 0;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/bind_overview_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_surface: c.struct_wlr_surface;
extern var stub_unmapped_surface: c.struct_wlr_surface;
extern var stub_unmapped_client: ?*Client;
extern var stub_group: c.KeyboardGroup;
extern var stub_kbgroup: c.struct_wlr_keyboard_group;
extern var stub_tkb: c.struct_wlr_keyboard;
extern var stub_dev_kb: c.struct_wlr_input_device;
extern var stub_dev_ptr: c.struct_wlr_input_device;
extern var stub_id_kb: c.InputDevice;
extern var stub_id_standalone: c.InputDevice;
extern var stub_id_ptr: c.InputDevice;
extern var stub_current_layout: u32;
extern var stub_num_layouts: u32;
extern var stub_error_calls: c_int;
extern var stub_printstatus_calls: c_int;
extern var stub_notify_mod_calls: c_int;
extern var stub_notify_group: u32;
extern var stub_seat_set_calls: c_int;
extern var stub_seat_mod_calls: c_int;
extern var stub_switch_view_calls: c_int;
extern var stub_switch_view_ui: u32;
extern var stub_switch_view_anim: bool;
extern var stub_focus_calls: c_int;
extern var stub_focus_client: ?*Client;
extern var stub_is_unmanaged: bool;
extern var stub_is_popup: bool;
extern var stub_backup_calls: c_int;
extern var stub_backup_client: ?*Client;
extern var stub_restore_calls: c_int;
extern var stub_restore_client: ?*Client;
extern var stub_refresh_calls: c_int;
extern var stub_arrange_calls: c_int;
extern var stub_begin_jump_calls: c_int;
extern var stub_finish_jump_calls: c_int;
extern var stub_pointer_clear_calls: c_int;
extern var stub_cursor_activity_calls: c_int;
extern var stub_set_xcursor_calls: c_int;

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
    listInit(&c.server.input_devices);
    c.server.tagmask = 0x7fffffff;
    stub_surface = std.mem.zeroes(c.struct_wlr_surface);
    stub_surface.mapped = true;
    stub_unmapped_surface = std.mem.zeroes(c.struct_wlr_surface);
    stub_unmapped_surface.mapped = false;
    stub_unmapped_client = null;
    stub_group = std.mem.zeroes(c.KeyboardGroup);
    stub_kbgroup = std.mem.zeroes(c.struct_wlr_keyboard_group);
    stub_tkb = std.mem.zeroes(c.struct_wlr_keyboard);
    stub_dev_kb = std.mem.zeroes(c.struct_wlr_input_device);
    stub_dev_ptr = std.mem.zeroes(c.struct_wlr_input_device);
    stub_id_kb = std.mem.zeroes(c.InputDevice);
    stub_id_standalone = std.mem.zeroes(c.InputDevice);
    stub_id_ptr = std.mem.zeroes(c.InputDevice);
    stub_current_layout = 0;
    stub_num_layouts = 3;
    stub_error_calls = 0;
    stub_printstatus_calls = 0;
    stub_notify_mod_calls = 0;
    stub_notify_group = 99;
    stub_seat_set_calls = 0;
    stub_seat_mod_calls = 0;
    stub_switch_view_calls = 0;
    stub_switch_view_ui = 0;
    stub_switch_view_anim = true;
    stub_focus_calls = 0;
    stub_focus_client = null;
    stub_is_unmanaged = false;
    stub_is_popup = false;
    stub_backup_calls = 0;
    stub_backup_client = null;
    stub_restore_calls = 0;
    stub_restore_client = null;
    stub_refresh_calls = 0;
    stub_arrange_calls = 0;
    stub_begin_jump_calls = 0;
    stub_finish_jump_calls = 0;
    stub_pointer_clear_calls = 0;
    stub_cursor_activity_calls = 0;
    stub_set_xcursor_calls = 0;
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
}

fn addClient(cl: *Client, m: *Monitor, tags: u32) void {
    cl.* = std.mem.zeroes(Client);
    cl.mon = @ptrCast(m);
    cl.tags = tags;
    listInsert(&c.server.clients, &cl.link);
}

test "switch_keyboard_layout cycles and syncs group devices" {
    resetWorld();
    c.server.keyboard_group = @ptrCast(&stub_group);
    c.server.seat = @ptrFromInt(16);
    stub_group.wlr_group = @ptrCast(&stub_kbgroup);
    stub_kbgroup.keyboard.keymap = @ptrFromInt(8);
    stub_kbgroup.keyboard.modifiers.depressed = 1;
    stub_kbgroup.keyboard.modifiers.latched = 2;
    stub_kbgroup.keyboard.modifiers.locked = 4;

    stub_dev_kb.type = c.WLR_INPUT_DEVICE_KEYBOARD;
    stub_id_kb.wlr_device = @ptrCast(&stub_dev_kb);
    stub_id_kb.device_data = @ptrCast(&stub_tkb);
    stub_id_kb.standalone = false;
    listInsert(&c.server.input_devices, &stub_id_kb.link);

    stub_dev_ptr.type = c.WLR_INPUT_DEVICE_POINTER;
    stub_id_ptr.wlr_device = @ptrCast(&stub_dev_ptr);
    listInsert(&c.server.input_devices, &stub_id_ptr.link);

    stub_dev_kb.type = c.WLR_INPUT_DEVICE_KEYBOARD;
    stub_id_standalone.wlr_device = @ptrCast(&stub_dev_kb);
    stub_id_standalone.device_data = @ptrCast(&stub_tkb);
    stub_id_standalone.standalone = true;
    listInsert(&c.server.input_devices, &stub_id_standalone.link);

    var arg = std.mem.zeroes(Arg);
    arg.i = 2;
    _ = switch_keyboard_layout(&arg);

    try testing.expectEqual(@as(c_int, 2), stub_notify_mod_calls); // group + one synced keyboard
    try testing.expectEqual(@as(u32, 1), stub_notify_group);
    try testing.expectEqual(@as(c_int, 2), stub_seat_set_calls);
    try testing.expectEqual(@as(c_int, 2), stub_seat_mod_calls);
    try testing.expectEqual(@as(c_int, 1), stub_printstatus_calls);

    stub_num_layouts = 1;
    stub_notify_mod_calls = 0;
    _ = switch_keyboard_layout(&arg);
    try testing.expectEqual(@as(c_int, 0), stub_notify_mod_calls);
    try testing.expectEqual(@as(c_int, 1), stub_error_calls);

    c.server.keyboard_group = null;
    _ = switch_keyboard_layout(&arg);
    try testing.expectEqual(@as(c_int, 2), stub_error_calls);
}

test "fix_mon_tagset_from_overview rebuilds the previous tagset" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    m.tagset[0] = 2;
    m.ovbk_prev_tagset = 2;
    m.ovbk_current_tagset = 8;

    fix_mon_tagset_from_overview(&m);
    try testing.expectEqual(@as(u32, 8), m.tagset[1]);
    try testing.expectEqual(@as(u32, 4), p.prevtag);

    m.tagset[0] = 1;
    m.ovbk_prev_tagset = 4;
    fix_mon_tagset_from_overview(&m);
    try testing.expectEqual(@as(u32, 4), m.tagset[1]);
    try testing.expectEqual(@as(u32, 3), p.prevtag);
}

test "enter_overview backs up visible clients and switches to all tags" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    var a: Client = undefined;
    addClient(&a, &m, 1);
    c.server.selected_monitor = &m;

    var arg = std.mem.zeroes(Arg);
    _ = enter_overview(&arg);

    try testing.expectEqual(@as(i32, 1), m.isoverview);
    try testing.expectEqual(@as(u32, c.server.tagmask), stub_switch_view_ui);
    try testing.expectEqual(@as(c_int, 1), stub_backup_calls);
    try testing.expect(stub_backup_client == &a);
    try testing.expect(a.animation.overining);
    // tab layout clears the flag again before arranging
    try testing.expect(!a.animation.overview_enter_anim_set);
    try testing.expectEqual(@as(c_int, 1), stub_arrange_calls);
    try testing.expectEqual(@as(c_int, 1), stub_refresh_calls);
    try testing.expectEqual(@as(c_int, 1), stub_pointer_clear_calls);
    try testing.expectEqual(@as(c_int, 1), stub_set_xcursor_calls);
    try testing.expect(!stub_switch_view_anim);
}

test "overview entry honors only-current and empty-client aborts" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 2);
    c.server.selected_monitor = &m;

    var arg = std.mem.zeroes(Arg);
    arg.i = 1;
    _ = enter_overview(&arg);
    try testing.expectEqual(@as(u32, 1), stub_switch_view_ui);
    try testing.expectEqual(@as(c_int, 1), stub_backup_calls);
    try testing.expect(stub_backup_client == &a);

    resetWorld();
    baseMonitor(&m, &p, &out);
    c.server.selected_monitor = &m;
    _ = enter_overview(&std.mem.zeroes(Arg));
    try testing.expectEqual(@as(i32, 0), m.isoverview);
    try testing.expectEqual(@as(c_int, 0), stub_switch_view_calls);
}

test "leave_overview restores clients and focuses the selection" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 2);
    addClient(&b, &m, 1);
    m.isoverview = 1;
    m.is_jump_mode = 1;
    c.server.selected_monitor = &m;

    var arg = std.mem.zeroes(Arg);
    arg.tc = @ptrCast(&a);
    _ = leave_overview(&arg);

    try testing.expectEqual(@as(i32, 0), m.isoverview);
    try testing.expectEqual(@as(u32, 2), m.tagset[0]);
    try testing.expectEqual(@as(u32, 2), stub_switch_view_ui);
    try testing.expectEqual(@as(c_int, 1), stub_finish_jump_calls);
    try testing.expectEqual(@as(c_int, 2), stub_restore_calls);
    try testing.expect(stub_focus_client == &a);
    try testing.expectEqual(@as(i32, 0), m.ov_normal_mode);
}

test "overview guards and jump toggling" {
    resetWorld();
    var p: c.Pertag = undefined;
    var out: c.struct_wlr_output = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p, &out);
    var a: Client = undefined;
    addClient(&a, &m, 1);
    c.server.selected_monitor = &m;

    var arg = std.mem.zeroes(Arg);
    c.server.grab_client = @ptrFromInt(8);
    _ = toggle_overview(&arg);
    try testing.expectEqual(@as(i32, 0), m.isoverview);

    c.server.grab_client = null;
    _ = enter_overview(&arg);
    try testing.expectEqual(@as(i32, 1), m.isoverview);
    _ = enter_overview(&arg);
    try testing.expectEqual(@as(c_int, 1), stub_switch_view_calls);
    _ = leave_overview(&arg);
    try testing.expectEqual(@as(i32, 0), m.isoverview);
    _ = leave_overview(&arg);
    try testing.expectEqual(@as(c_int, 2), stub_switch_view_calls);

    m.isoverview = 0;
    _ = toggle_jump(&arg);
    try testing.expectEqual(@as(c_int, 1), stub_begin_jump_calls);
    try testing.expectEqual(@as(i32, 1), m.isoverview);
    _ = toggle_jump(&arg);
    try testing.expectEqual(@as(i32, 0), m.isoverview);
    try testing.expectEqual(@as(c_int, 1), stub_begin_jump_calls);
}
