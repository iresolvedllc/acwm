//! Native executable entry point; the compositor logic lives in
//! src/main_runtime.zig (exported as acwm_main).

const c = @import("cc");

extern fn acwm_main(argc: c_int, argv: [*c][*c]u8) callconv(.c) c_int;

export fn main(argc: c_int, argv: [*c][*c]u8) callconv(.c) c_int {
    return acwm_main(argc, argv);
}
