//! No-op tray API for builds without libsystemd (the tray and portal are
//! unavailable there). bar/bar.zig always links against these symbols.

const c = @import("cc");

const Bar = c.struct_AcwmBar;

export fn tray_init(loop: ?*c.struct_wl_event_loop) callconv(.c) void {
    _ = loop;
}

export fn tray_cleanup() callconv(.c) void {}

export fn tray_reload() callconv(.c) void {}

export fn tray_sync_bar(bar: [*c]Bar) callconv(.c) void {
    _ = bar;
}

export fn tray_detach_bar(bar: [*c]Bar) callconv(.c) void {
    _ = bar;
}

export fn tray_click(item: ?*anyopaque, button: u32) callconv(.c) void {
    _ = item;
    _ = button;
}
