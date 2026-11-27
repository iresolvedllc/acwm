//! Port of input/device.c and input/switch.c
//! (Phase 5, input slice 1, slice 68).

const std = @import("std");
const c = @import("cc");

const InputDevice = c.InputDevice;
const Switch = c.Switch;

const SeatDevice = extern struct {
    link: c.struct_wl_list = std.mem.zeroes(c.struct_wl_list),
    device: [*c]c.struct_wlr_input_device = null,
    destroy: c.struct_wl_listener = std.mem.zeroes(c.struct_wl_listener),
};

extern fn keyboard_create(keyboard: [*c]c.struct_wlr_keyboard) callconv(.c) void;
extern fn pointer_create(pointer: [*c]c.struct_wlr_pointer) callconv(.c) void;
extern fn touch_create(touch: [*c]c.struct_wlr_touch) callconv(.c) void;
extern fn tablet_create(device: [*c]c.struct_wlr_input_device) callconv(.c) void;
extern fn tablet_pad_create(device: [*c]c.struct_wlr_input_device) callconv(.c) void;
extern fn ipc_notify_device_event(dev: [*c]c.struct_wlr_input_device) callconv(.c) void;

fn inputDeviceFromListener(listener: [*c]c.struct_wl_listener) *InputDevice {
    return @ptrFromInt(@intFromPtr(listener) - @offsetOf(InputDevice, "destroy_listener"));
}

fn seatDeviceFromListener(listener: [*c]c.struct_wl_listener) *SeatDevice {
    return @ptrFromInt(@intFromPtr(listener) - @offsetOf(SeatDevice, "destroy"));
}

fn seatDeviceFromLink(link: [*c]c.struct_wl_list) *SeatDevice {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(SeatDevice, "link"));
}

export fn handle_input_device_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const input_dev = inputDeviceFromListener(listener);

    if (input_dev.device_data != null) {
        switch (input_dev.wlr_device.*.type) {
            c.WLR_INPUT_DEVICE_SWITCH => {
                const sw = @as(*Switch, @ptrCast(@alignCast(input_dev.device_data)));
                c.wl_list_remove(&sw.toggle.link);
                c.free(sw);
            },
            else => {},
        }
        input_dev.device_data = null;
    }

    if (input_dev.wlr_device.*.type == c.WLR_INPUT_DEVICE_KEYBOARD)
        c.wl_list_remove(&input_dev.key_watch.link);
    c.wl_list_remove(&input_dev.link);
    c.wl_list_remove(&input_dev.destroy_listener.link);
    c.free(input_dev);
}

fn seatDeviceProvidesCapability(device: [*c]const c.struct_wlr_input_device, capability: u32) bool {
    switch (device.*.type) {
        c.WLR_INPUT_DEVICE_POINTER, c.WLR_INPUT_DEVICE_TABLET => {
            return capability == c.WL_SEAT_CAPABILITY_POINTER;
        },
        c.WLR_INPUT_DEVICE_TOUCH => {
            if (capability == c.WL_SEAT_CAPABILITY_TOUCH)
                return c.config.touch_enable != 0;
            return capability == c.WL_SEAT_CAPABILITY_POINTER and
                c.config.touch_enable != 0 and c.config.touch_enable_mouse_emulation != 0;
        },
        c.WLR_INPUT_DEVICE_KEYBOARD => {
            return capability == c.WL_SEAT_CAPABILITY_KEYBOARD;
        },
        else => return false,
    }
}

fn seatHasCapability(capability: u32) bool {
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.seat_devices);
    var pos = c.server.seat_devices.next;
    while (pos != head) : (pos = pos.*.next) {
        const seat_device = seatDeviceFromLink(pos);
        if (seatDeviceProvidesCapability(seat_device.device, capability))
            return true;
    }
    return false;
}

export fn update_seat_capabilities() callconv(.c) void {
    if (c.server.seat == null)
        return;

    var caps: u32 = 0;
    if (seatHasCapability(c.WL_SEAT_CAPABILITY_POINTER))
        caps |= c.WL_SEAT_CAPABILITY_POINTER;
    if (seatHasCapability(c.WL_SEAT_CAPABILITY_KEYBOARD))
        caps |= c.WL_SEAT_CAPABILITY_KEYBOARD;
    if (seatHasCapability(c.WL_SEAT_CAPABILITY_TOUCH))
        caps |= c.WL_SEAT_CAPABILITY_TOUCH;
    c.wlr_seat_set_capabilities(c.server.seat, caps);
}

fn handleSeatDeviceDestroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const seat_device = seatDeviceFromListener(listener);
    c.wl_list_remove(&seat_device.destroy.link);
    c.wl_list_remove(&seat_device.link);
    c.free(seat_device);
    update_seat_capabilities();
}

export fn seat_device_add(device: [*c]c.struct_wlr_input_device) callconv(.c) void {
    const raw = c.calloc(1, @sizeOf(SeatDevice)) orelse return;
    const seat_device = @as(*SeatDevice, @ptrCast(@alignCast(raw)));
    seat_device.device = device;
    seat_device.destroy.notify = handleSeatDeviceDestroy;
    c.wl_signal_add(&device.*.events.destroy, &seat_device.destroy);
    c.wl_list_insert(&c.server.seat_devices, &seat_device.link);
    update_seat_capabilities();
}

export fn handle_new_input_device(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const device = @as([*c]c.struct_wlr_input_device, @ptrCast(@alignCast(data.?)));

    switch (device.*.type) {
        c.WLR_INPUT_DEVICE_KEYBOARD => keyboard_create(c.wlr_keyboard_from_input_device(device)),
        c.WLR_INPUT_DEVICE_TABLET => tablet_create(device),
        c.WLR_INPUT_DEVICE_TABLET_PAD => tablet_pad_create(device),
        c.WLR_INPUT_DEVICE_POINTER => pointer_create(c.wlr_pointer_from_input_device(device)),
        c.WLR_INPUT_DEVICE_TOUCH => touch_create(c.wlr_touch_from_input_device(device)),
        c.WLR_INPUT_DEVICE_SWITCH => switch_create(c.wlr_switch_from_input_device(device)),
        else => {},
    }

    seat_device_add(device);
}

export fn handle_switch_toggle(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void {
    const sw = @as(*Switch, @ptrFromInt(@intFromPtr(listener) - @offsetOf(Switch, "toggle")));
    const event = @as(*c.struct_wlr_switch_toggle_event, @ptrCast(@alignCast(data.?)));

    ipc_notify_device_event(&sw.wlr_switch.*.base);

    var i: i32 = 0;
    while (i < c.config.switch_bindings_count) : (i += 1) {
        const s = &c.config.switch_bindings[@intCast(i)];
        const mode_matches = s.iscommonmode or
            (s.isdefaultmode and c.server.key_mode.isdefault) or
            c.strcmp(&c.server.key_mode.mode[0], &s.mode[0]) == 0;
        if (mode_matches and event.*.switch_state == s.fold and s.func != null) {
            _ = s.func.?(&s.arg);
            return;
        }
    }
}

export fn switch_create(switch_device: [*c]c.struct_wlr_switch) callconv(.c) void {
    if (!c.wlr_input_device_is_libinput(&switch_device.*.base))
        return;
    const device = c.wlr_libinput_get_device_handle(&switch_device.*.base);
    if (device == null)
        return;

    const raw_dev = c.calloc(1, @sizeOf(InputDevice)) orelse return;
    const input_dev = @as(*InputDevice, @ptrCast(@alignCast(raw_dev)));
    input_dev.wlr_device = &switch_device.*.base;
    input_dev.libinput_device = device;
    input_dev.device_data = null;

    input_dev.destroy_listener.notify = handle_input_device_destroy;
    c.wl_signal_add(&switch_device.*.base.events.destroy, &input_dev.destroy_listener);

    const raw_sw = c.calloc(1, @sizeOf(Switch)) orelse {
        c.free(input_dev);
        return;
    };
    const sw = @as(*Switch, @ptrCast(@alignCast(raw_sw)));
    sw.wlr_switch = switch_device;
    sw.toggle.notify = handle_switch_toggle;
    sw.input_dev = input_dev;

    input_dev.device_data = sw;
    c.wl_signal_add(&switch_device.*.events.toggle, &sw.toggle);
    c.wl_list_insert(&c.server.input_devices, &input_dev.link);
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/input_device_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_list_insert_calls: c_int;
extern var stub_list_remove_calls: c_int;
extern var stub_is_libinput: bool;
extern var stub_libinput_device: ?*c.struct_libinput_device;
extern var stub_keyboard_create_calls: c_int;
extern var stub_pointer_create_calls: c_int;
extern var stub_touch_create_calls: c_int;
extern var stub_tablet_create_calls: c_int;
extern var stub_tablet_pad_create_calls: c_int;
extern var stub_ipc_device_calls: c_int;
extern var stub_seat_caps_calls: c_int;
extern var stub_seat_caps: u32;
extern var stub_switch_func_calls: c_int;
extern var stub_switch_func_ui: u32;
extern fn stub_switch_binding_func(arg: [*c]const c.Arg) callconv(.c) i32;
extern var stub_keyboard: c.struct_wlr_keyboard;
extern var stub_pointer: c.struct_wlr_pointer;
extern var stub_touch: c.struct_wlr_touch;
extern var stub_switch: c.struct_wlr_switch;

fn listInit(head: *c.struct_wl_list) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

fn listIsEmpty(head: *c.struct_wl_list) bool {
    return head.next == @as([*c]c.struct_wl_list, @ptrCast(head));
}

fn resetDeviceWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    listInit(&c.server.input_devices);
    listInit(&c.server.seat_devices);
    c.server.seat = @ptrFromInt(0x1000);
    stub_list_insert_calls = 0;
    stub_list_remove_calls = 0;
    stub_is_libinput = false;
    stub_keyboard_create_calls = 0;
    stub_pointer_create_calls = 0;
    stub_touch_create_calls = 0;
    stub_tablet_create_calls = 0;
    stub_tablet_pad_create_calls = 0;
    stub_ipc_device_calls = 0;
    stub_seat_caps_calls = 0;
    stub_seat_caps = 0;
    stub_switch_func_calls = 0;
    stub_switch_func_ui = 0;
}

fn mkDevice(dev: *c.struct_wlr_input_device, t: c_uint) void {
    dev.* = std.mem.zeroes(c.struct_wlr_input_device);
    dev.type = t;
    listInit(&dev.events.destroy.listener_list);
}

fn seatDeviceCount() usize {
    var n: usize = 0;
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.seat_devices);
    var pos = c.server.seat_devices.next;
    while (pos != head) : (pos = pos.*.next)
        n += 1;
    return n;
}

fn firstInputDevice() ?*InputDevice {
    if (listIsEmpty(&c.server.input_devices))
        return null;
    return @ptrCast(@alignCast(c.server.input_devices.next));
}

test "seat capabilities reflect device types and touch config" {
    resetDeviceWorld();
    const Caps: u32 = @as(u32, c.WL_SEAT_CAPABILITY_POINTER) | @as(u32, c.WL_SEAT_CAPABILITY_KEYBOARD) | @as(u32, c.WL_SEAT_CAPABILITY_TOUCH);

    var pointer_dev: c.struct_wlr_input_device = undefined;
    mkDevice(&pointer_dev, c.WLR_INPUT_DEVICE_POINTER);
    seat_device_add(&pointer_dev);
    try testing.expectEqual(@as(u32, c.WL_SEAT_CAPABILITY_POINTER), stub_seat_caps);

    var tablet_dev: c.struct_wlr_input_device = undefined;
    mkDevice(&tablet_dev, c.WLR_INPUT_DEVICE_TABLET);
    seat_device_add(&tablet_dev);
    try testing.expectEqual(@as(u32, c.WL_SEAT_CAPABILITY_POINTER), stub_seat_caps);

    var keyboard_dev: c.struct_wlr_input_device = undefined;
    mkDevice(&keyboard_dev, c.WLR_INPUT_DEVICE_KEYBOARD);
    seat_device_add(&keyboard_dev);
    try testing.expectEqual(@as(u32, c.WL_SEAT_CAPABILITY_POINTER | c.WL_SEAT_CAPABILITY_KEYBOARD), stub_seat_caps);

    var switch_dev: c.struct_wlr_input_device = undefined;
    mkDevice(&switch_dev, c.WLR_INPUT_DEVICE_SWITCH);
    seat_device_add(&switch_dev);
    try testing.expectEqual(@as(u32, c.WL_SEAT_CAPABILITY_POINTER | c.WL_SEAT_CAPABILITY_KEYBOARD), stub_seat_caps);

    var touch_dev: c.struct_wlr_input_device = undefined;
    mkDevice(&touch_dev, c.WLR_INPUT_DEVICE_TOUCH);
    seat_device_add(&touch_dev);
    try testing.expectEqual(@as(u32, c.WL_SEAT_CAPABILITY_POINTER | c.WL_SEAT_CAPABILITY_KEYBOARD), stub_seat_caps);

    c.config.touch_enable = 1;
    update_seat_capabilities();
    try testing.expectEqual(@as(u32, c.WL_SEAT_CAPABILITY_POINTER | c.WL_SEAT_CAPABILITY_KEYBOARD | c.WL_SEAT_CAPABILITY_TOUCH), stub_seat_caps);

    c.config.touch_enable_mouse_emulation = 1;
    update_seat_capabilities();
    try testing.expectEqual(Caps, stub_seat_caps);
    try testing.expectEqual(@as(usize, 5), seatDeviceCount());

    c.server.seat = null;
    const calls = stub_seat_caps_calls;
    update_seat_capabilities();
    try testing.expectEqual(calls, stub_seat_caps_calls);
}

test "seat device destroy removes the device and updates capabilities" {
    resetDeviceWorld();
    var pointer_dev: c.struct_wlr_input_device = undefined;
    var keyboard_dev: c.struct_wlr_input_device = undefined;
    mkDevice(&pointer_dev, c.WLR_INPUT_DEVICE_POINTER);
    mkDevice(&keyboard_dev, c.WLR_INPUT_DEVICE_KEYBOARD);
    seat_device_add(&pointer_dev);
    seat_device_add(&keyboard_dev);
    try testing.expectEqual(@as(u32, c.WL_SEAT_CAPABILITY_POINTER | c.WL_SEAT_CAPABILITY_KEYBOARD), stub_seat_caps);

    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.seat_devices);
    var pos = c.server.seat_devices.next;
    var found: ?*SeatDevice = null;
    while (pos != head) : (pos = pos.*.next) {
        const sd = seatDeviceFromLink(pos);
        if (sd.device == &keyboard_dev)
            found = sd;
    }
    try testing.expect(found != null);
    const removes = stub_list_remove_calls;
    handleSeatDeviceDestroy(&found.?.destroy, null);
    try testing.expectEqual(removes + 2, stub_list_remove_calls);
    try testing.expectEqual(@as(u32, c.WL_SEAT_CAPABILITY_POINTER), stub_seat_caps);
    try testing.expectEqual(@as(usize, 1), seatDeviceCount());
}

fn allocInputDevice(dev: [*c]c.struct_wlr_input_device) *InputDevice {
    const raw = c.calloc(1, @sizeOf(InputDevice)) orelse unreachable;
    const idev = @as(*InputDevice, @ptrCast(@alignCast(raw)));
    idev.wlr_device = dev;
    listInit(&idev.destroy_listener.link);
    return idev;
}

test "input device destroy frees switch payloads and keyboard watchers" {
    resetDeviceWorld();
    var switch_dev: c.struct_wlr_input_device = undefined;
    mkDevice(&switch_dev, c.WLR_INPUT_DEVICE_SWITCH);
    const idev = allocInputDevice(&switch_dev);
    const raw_sw = c.calloc(1, @sizeOf(Switch)) orelse unreachable;
    const sw = @as(*Switch, @ptrCast(@alignCast(raw_sw)));
    sw.toggle.notify = handle_switch_toggle;
    listInit(&sw.toggle.link);
    idev.device_data = sw;
    handle_input_device_destroy(&idev.destroy_listener, null);
    try testing.expectEqual(@as(c_int, 3), stub_list_remove_calls);

    var keyboard_dev: c.struct_wlr_input_device = undefined;
    mkDevice(&keyboard_dev, c.WLR_INPUT_DEVICE_KEYBOARD);
    const kdev = allocInputDevice(&keyboard_dev);
    kdev.device_data = null;
    listInit(&kdev.key_watch.link);
    handle_input_device_destroy(&kdev.destroy_listener, null);
    try testing.expectEqual(@as(c_int, 6), stub_list_remove_calls);

    var pointer_dev: c.struct_wlr_input_device = undefined;
    mkDevice(&pointer_dev, c.WLR_INPUT_DEVICE_POINTER);
    const pdev = allocInputDevice(&pointer_dev);
    pdev.device_data = @ptrFromInt(0x2000);
    handle_input_device_destroy(&pdev.destroy_listener, null);
    try testing.expectEqual(@as(c_int, 8), stub_list_remove_calls);
}

test "new input device dispatches to each creator and the seat" {
    resetDeviceWorld();
    var keyboard_dev: c.struct_wlr_input_device = undefined;
    var pointer_dev: c.struct_wlr_input_device = undefined;
    var touch_dev: c.struct_wlr_input_device = undefined;
    var tablet_dev: c.struct_wlr_input_device = undefined;
    var pad_dev: c.struct_wlr_input_device = undefined;
    var switch_dev: c.struct_wlr_input_device = undefined;
    mkDevice(&keyboard_dev, c.WLR_INPUT_DEVICE_KEYBOARD);
    mkDevice(&pointer_dev, c.WLR_INPUT_DEVICE_POINTER);
    mkDevice(&touch_dev, c.WLR_INPUT_DEVICE_TOUCH);
    mkDevice(&tablet_dev, c.WLR_INPUT_DEVICE_TABLET);
    mkDevice(&pad_dev, c.WLR_INPUT_DEVICE_TABLET_PAD);
    mkDevice(&switch_dev, c.WLR_INPUT_DEVICE_SWITCH);

    handle_new_input_device(null, &keyboard_dev);
    handle_new_input_device(null, &pointer_dev);
    handle_new_input_device(null, &touch_dev);
    handle_new_input_device(null, &tablet_dev);
    handle_new_input_device(null, &pad_dev);
    handle_new_input_device(null, &switch_dev);

    try testing.expectEqual(@as(c_int, 1), stub_keyboard_create_calls);
    try testing.expectEqual(@as(c_int, 1), stub_pointer_create_calls);
    try testing.expectEqual(@as(c_int, 1), stub_touch_create_calls);
    try testing.expectEqual(@as(c_int, 1), stub_tablet_create_calls);
    try testing.expectEqual(@as(c_int, 1), stub_tablet_pad_create_calls);
    try testing.expectEqual(@as(usize, 6), seatDeviceCount());
    try testing.expectEqual(@as(usize, 0), blk: {
        var n: usize = 0;
        const head: [*c]c.struct_wl_list = @ptrCast(&c.server.input_devices);
        var pos = c.server.input_devices.next;
        while (pos != head) : (pos = pos.*.next)
            n += 1;
        break :blk n;
    });
}

test "switch create records libinput device and listeners" {
    resetDeviceWorld();
    var swdev: c.struct_wlr_switch = std.mem.zeroes(c.struct_wlr_switch);
    mkDevice(&swdev.base, c.WLR_INPUT_DEVICE_SWITCH);
    listInit(&swdev.events.toggle.listener_list);

    stub_is_libinput = false;
    switch_create(&swdev);
    try testing.expect(firstInputDevice() == null);
    try testing.expectEqual(@as(c_int, 0), stub_list_insert_calls);

    stub_is_libinput = true;
    switch_create(&swdev);
    const idev = firstInputDevice() orelse return error.TestUnexpectedResult;
    try testing.expect(idev.wlr_device == &swdev.base);
    try testing.expect(@intFromPtr(idev.libinput_device) == @intFromPtr(stub_libinput_device));
    try testing.expect(idev.destroy_listener.notify != null);
    try testing.expect(idev.device_data != null);
    const sw = @as(*Switch, @ptrCast(@alignCast(idev.device_data)));
    try testing.expect(sw.wlr_switch == &swdev);
    try testing.expect(sw.toggle.notify != null);
    try testing.expect(sw.input_dev == idev);
    try testing.expect(!listIsEmpty(&swdev.base.events.destroy.listener_list));
    try testing.expect(!listIsEmpty(&swdev.events.toggle.listener_list));
}

fn setMode(dst: []u8, src: []const u8) void {
    @memset(dst, 0);
    @memcpy(dst[0..src.len], src);
}

test "switch toggle runs the first matching binding" {
    resetDeviceWorld();
    var swdev: c.struct_wlr_switch = std.mem.zeroes(c.struct_wlr_switch);
    var sw: Switch = std.mem.zeroes(Switch);
    sw.wlr_switch = &swdev;
    var event: c.struct_wlr_switch_toggle_event = std.mem.zeroes(c.struct_wlr_switch_toggle_event);
    event.switch_state = @intCast(c.WLR_SWITCH_STATE_ON);

    var bindings: [3]c.SwitchBinding = std.mem.zeroes([3]c.SwitchBinding);
    bindings[0].fold = @intCast(c.WLR_SWITCH_STATE_ON);
    bindings[0].func = stub_switch_binding_func;
    bindings[0].arg.ui = 11;
    setMode(bindings[0].mode[0..], "gaming");
    bindings[1].fold = @intCast(c.WLR_SWITCH_STATE_ON);
    bindings[1].func = stub_switch_binding_func;
    bindings[1].arg.ui = 22;
    bindings[1].iscommonmode = true;
    bindings[2].fold = @intCast(c.WLR_SWITCH_STATE_ON);
    bindings[2].func = stub_switch_binding_func;
    bindings[2].arg.ui = 33;
    bindings[2].isdefaultmode = true;
    c.config.switch_bindings = &bindings[0];
    c.config.switch_bindings_count = 3;

    c.server.key_mode.isdefault = false;
    setMode(c.server.key_mode.mode[0..], "default");
    handle_switch_toggle(&sw.toggle, &event);
    try testing.expectEqual(@as(c_int, 1), stub_switch_func_calls);
    try testing.expectEqual(@as(u32, 22), stub_switch_func_ui);
    try testing.expectEqual(@as(c_int, 1), stub_ipc_device_calls);

    stub_switch_func_calls = 0;
    setMode(c.server.key_mode.mode[0..], "gaming");
    handle_switch_toggle(&sw.toggle, &event);
    try testing.expectEqual(@as(u32, 11), stub_switch_func_ui);

    stub_switch_func_calls = 0;
    bindings[1].iscommonmode = false;
    setMode(c.server.key_mode.mode[0..], "default");
    c.server.key_mode.isdefault = true;
    handle_switch_toggle(&sw.toggle, &event);
    try testing.expectEqual(@as(u32, 33), stub_switch_func_ui);

    stub_switch_func_calls = 0;
    event.switch_state = @intCast(c.WLR_SWITCH_STATE_OFF);
    handle_switch_toggle(&sw.toggle, &event);
    try testing.expectEqual(@as(c_int, 0), stub_switch_func_calls);
    try testing.expectEqual(@as(c_int, 4), stub_ipc_device_calls);
}
