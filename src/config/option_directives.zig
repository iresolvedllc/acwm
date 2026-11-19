//! Port of the session-directive branches from src/config/option_defs.c
//! (strangler-fig Phase 4, slice 17).
//!
//! Exports one C symbol: acwm_config_apply_directives_option(), called by
//! parse_option() ahead of its strcmp chain (guarded by
//! ACWM_ZIG_DIRECTIVES_OPTION, defined only in the Zig build). Covers the
//! env/var/exec/exec_once/source_optional/source directives, including the
//! C's prefix-match quirks (any key starting with "env" or "source" hits
//! those branches; "exec" is an exact match while "exec_once" is a prefix):
//!   - env: "type,value" split, ~/ -> $HOME expansion (every occurrence,
//!     only the tilde is replaced), calloc'd ConfigEnv appended to
//!     config->env; the "Invalid bind format" message is preserved from C
//!   - var: "name,value" split, name validated, stored in the config
//!     variable table (variable_expand twin)
//!   - exec / exec_once: strdup'd command arrays with counts
//!   - source_optional / source: parse_config_file(config, path, bool),
//!     return ignored (both always succeed), matching C
//!
//! Tests live at the bottom and need tests/option_directives_stub.c
//! (trim, error recorder, controllable variable/config-file hooks).

const std = @import("std");
const c = @import("cc");

const WLR_ERROR: c_uint = 1;

extern fn acwm_error_impl(
    log: bool,
    verbosity: c_uint,
    file: [*:0]const u8,
    line: c_int,
    fmt: [*:0]const u8,
    ...) callconv(.c) void;
extern fn trim_whitespace(str: ?[*:0]u8) callconv(.c) void;
/// variable_expand twin in the compositor link; stubbed in tests.
extern fn is_valid_var_name(name: ?[*:0]const u8) callconv(.c) bool;
extern fn set_config_var(name: [*:0]const u8, value: [*:0]const u8) callconv(.c) void;
/// load.c in the compositor link; stubbed in tests.
extern fn parse_config_file(config: *c.Config, file_path: [*:0]const u8, must_exist: bool) callconv(.c) bool;

extern "c" fn calloc(nmemb: usize, size: usize) ?*anyopaque;
extern "c" fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque;
extern "c" fn malloc(size: usize) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern "c" fn strlen(s: [*:0]const u8) usize;
extern "c" fn getenv(name: [*:0]const u8) ?[*:0]u8;
extern "c" fn strstr(haystack: [*:0]const u8, needle: [*:0]const u8) ?[*:0]u8;
extern "c" fn strchr(s: [*:0]const u8, ch: c_int) ?[*:0]u8;
extern "c" fn memcpy(dest: [*]u8, src: [*:0]const u8, n: usize) [*]u8;
extern "c" fn strcpy(dest: [*]u8, src: [*:0]const u8) [*]u8;
extern "c" fn sscanf(str: [*:0]const u8, fmt: [*:0]const u8, ...) c_int;

// ---------------------------------------------------------------------------
// env
// ---------------------------------------------------------------------------

fn parseEnv(cfg: *c.Config, value: [*:0]u8) c_int {
    var env_type: [256]u8 = undefined;
    var env_value: [256]u8 = undefined;
    if (sscanf(
        value,
        "%255[^,],%255[^\n]",
        @as([*]u8, @ptrCast(&env_type)),
        @as([*]u8, @ptrCast(&env_value)),
    ) < 2) {
        // C reuses the bind message for env format errors.
        acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Invalid bind format: \x1b[1m\x1b[31m%s\x1b[0m\n", value);
        return -1;
    }
    const type_z: [*:0]u8 = @ptrCast(&env_type);
    const value_z: [*:0]u8 = @ptrCast(&env_value);
    trim_whitespace(type_z);
    trim_whitespace(value_z);

    const env: *c.ConfigEnv = @ptrCast(@alignCast(calloc(1, @sizeOf(c.ConfigEnv)) orelse return -1));

    const needle = "~/";
    if (strstr(value_z, needle) != null) {
        const home = getenv("HOME");
        if (home == null) {
            free(@ptrCast(env));
            acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "HOME environment variable not set.\n");
            return -1;
        }
        const rlen: usize = 1; // replace only ~
        const hlen = strlen(home.?);

        var len: usize = strlen(value_z) + 1;
        var probe = strstr(value_z, needle);
        while (probe != null) : (probe = strstr(probe.? + rlen, needle))
            len +%= hlen -% rlen; // wrapping like the C size_t arithmetic

        const buf = malloc(len) orelse {
            free(@ptrCast(env));
            acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Failed to allocate memory while expanding $HOME\n");
            return -1;
        };
        const dst_start: [*]u8 = @ptrCast(buf);
        var src: [*:0]u8 = value_z;
        var dst: [*]u8 = dst_start;
        while (strstr(src, needle)) |substr| {
            const n: usize = @intFromPtr(substr) - @intFromPtr(src);
            _ = memcpy(dst, src, n);
            dst += n;
            _ = memcpy(dst, home.?, hlen);
            dst += hlen;
            src = substr + rlen;
        }
        _ = strcpy(dst, src);
        env.value = @ptrCast(buf);
    } else {
        env.value = strdup(value_z);
    }

    env.type = strdup(type_z);

    const new_count = @as(usize, @intCast(cfg.env_count)) + 1;
    const raw = realloc(@ptrCast(cfg.env), new_count * @sizeOf(?*c.ConfigEnv)) orelse {
        free(@ptrCast(env.type));
        free(@ptrCast(env.value));
        free(@ptrCast(env));
        acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Failed to allocate memory for env\n");
        return -1;
    };
    cfg.env = @ptrCast(@alignCast(raw));
    cfg.env[@intCast(cfg.env_count)] = env;
    cfg.env_count += 1;
    return 1;
}

// ---------------------------------------------------------------------------
// var
// ---------------------------------------------------------------------------

fn parseVar(value: [*:0]u8) c_int {
    const comma = strchr(value, ',') orelse {
        acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Invalid variable format (expected \x1b[1mname,value\x1b[0m): \x1b[1m\x1b[31m%s\x1b[0m\n", value);
        return -1;
    };
    comma[0] = 0;
    const name = value;
    const var_value = comma + 1;
    trim_whitespace(name);
    trim_whitespace(var_value);

    if (!is_valid_var_name(name)) {
        acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Invalid variable name (allowed: [A-Za-z_][A-Za-z0-9_]*): \x1b[1m\x1b[31m%s\x1b[0m\n", name);
        return -1;
    }
    set_config_var(name, var_value);
    return 1;
}

// ---------------------------------------------------------------------------
// exec / exec_once
// ---------------------------------------------------------------------------

fn appendExec(
    cfg: *c.Config,
    comptime field: [:0]const u8,
    comptime count_field: [:0]const u8,
    value: [*:0]const u8,
    comptime alloc_msg: [:0]const u8,
    comptime dup_msg: [:0]const u8,
) c_int {
    const new_count = @as(usize, @intCast(@field(cfg, count_field))) + 1;
    const raw = realloc(@ptrCast(@field(cfg, field)), new_count * @sizeOf([*c]u8)) orelse {
        acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, alloc_msg.ptr);
        return -1;
    };
    @field(cfg, field) = @ptrCast(@alignCast(raw));

    const dup = strdup(value) orelse {
        acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, dup_msg.ptr);
        return -1;
    };
    @field(cfg, field)[@intCast(@field(cfg, count_field))] = dup;
    @field(cfg, count_field) += 1;
    return 1;
}

// ---------------------------------------------------------------------------
// C entry
// ---------------------------------------------------------------------------

/// C entry point (tri-state: 1 applied, -1 invalid value, 0 not ours).
export fn acwm_config_apply_directives_option(
    config: ?*c.Config,
    key: [*:0]const u8,
    value: [*:0]u8,
    line_number: c_int,
) callconv(.c) c_int {
    _ = line_number;
    const cfg = config orelse return 0;
    const k = std.mem.span(key);

    // Prefix matches replicate the C strncmp branches, including their order.
    if (std.mem.startsWith(u8, k, "env"))
        return parseEnv(cfg, value);
    if (std.mem.eql(u8, k, "var"))
        return parseVar(value);
    if (std.mem.eql(u8, k, "exec"))
        return appendExec(cfg, "exec", "exec_count", value, "Failed to allocate memory for exec\n", "Failed to duplicate exec string\n");
    if (std.mem.startsWith(u8, k, "exec_once"))
        return appendExec(cfg, "exec_once", "exec_once_count", value, "Failed to allocate memory for exec_once\n", "Failed to duplicate exec_once string\n");
    if (std.mem.startsWith(u8, k, "source_optional")) {
        _ = parse_config_file(cfg, value, false);
        return 1;
    }
    if (std.mem.startsWith(u8, k, "source")) {
        _ = parse_config_file(cfg, value, true);
        return 1;
    }
    return 0;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: see tests/option_directives_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_last_error: [1024]u8;
extern var stub_error_count: c_int;
extern var stub_var_name_valid: bool;
extern var stub_var_name: [128]u8;
extern var stub_var_value: [128]u8;
extern var stub_var_calls: c_int;
extern var stub_config_path: [256]u8;
extern var stub_config_must_exist: c_int;
extern var stub_config_calls: c_int;

extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;

fn resetStub() void {
    stub_error_count = 0;
    stub_last_error[0] = 0;
    stub_var_name_valid = true;
    stub_var_name[0] = 0;
    stub_var_value[0] = 0;
    stub_var_calls = 0;
    stub_config_path[0] = 0;
    stub_config_must_exist = -1;
    stub_config_calls = 0;
}

fn apply(cfg: *c.Config, comptime key: [:0]const u8, value: []const u8) c_int {
    var buf: [512:0]u8 = undefined;
    @memcpy(buf[0..value.len], value);
    buf[value.len] = 0;
    return acwm_config_apply_directives_option(cfg, key, &buf, 61);
}

fn lastError() []const u8 {
    return std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&stub_last_error)), 0);
}

fn envAt(cfg: *c.Config, i: usize) *c.ConfigEnv {
    return @ptrCast(cfg.env[i]);
}

fn spanC(ptr: [*c]const u8) []const u8 {
    return std.mem.span(@as([*:0]const u8, @ptrCast(ptr)));
}

test "tri-state dispatch: directives vs other groups" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "exec", "true"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "window_rule", "title:x"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "execx", "true")); // exact exec only
    try testing.expectEqual(@as(c_int, 0), apply(&config, "varx", "a,b"));
    try testing.expectEqual(@as(c_int, 0), apply(&config, "device_rule", "name:x"));
}

test "env: type/value split and append" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "env", "env,FOO=bar"));
    try testing.expectEqual(@as(i32, 1), config.env_count);
    try testing.expectEqualStrings("env", spanC(envAt(&config, 0).type));
    try testing.expectEqualStrings("FOO=bar", spanC(envAt(&config, 0).value));

    // prefix match: any key starting with "env"
    try testing.expectEqual(@as(c_int, 1), apply(&config, "environment", "XDG,X=1"));
    try testing.expectEqual(@as(i32, 2), config.env_count);
    try testing.expectEqualStrings("XDG", spanC(envAt(&config, 1).type));
}

test "env: invalid format keeps the C bind message" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, -1), apply(&config, "env", "no-comma-here"));
    try testing.expectEqual(@as(i32, 0), config.env_count);
    try testing.expect(std.mem.startsWith(u8, lastError(), "Invalid bind format: \x1b[1m\x1b[31mno-comma-here"));
}

test "env: ~/ expands to HOME on every occurrence (tilde only)" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();
    _ = setenv("HOME", "/home/tester", 1);

    try testing.expectEqual(@as(c_int, 1), apply(&config, "env", "PATH,~/bin:~/tools:$PATH"));
    try testing.expectEqualStrings("/home/tester/bin:/home/tester/tools:$PATH", spanC(envAt(&config, 0).value));

    // no tilde: value passes through untouched
    try testing.expectEqual(@as(c_int, 1), apply(&config, "env", "PLAIN,a/b/c"));
    try testing.expectEqualStrings("a/b/c", spanC(envAt(&config, 1).value));
}

test "env: missing HOME fails with the C message" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();
    _ = unsetenv("HOME");

    try testing.expectEqual(@as(c_int, -1), apply(&config, "env", "PATH,~/bin"));
    try testing.expectEqual(@as(i32, 0), config.env_count);
    try testing.expect(std.mem.eql(u8, lastError(), "HOME environment variable not set.\n"));

    _ = setenv("HOME", "/home/tester", 1); // restore for later tests
}

test "var: split, validate, store" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "var", " my_var , some value "));
    try testing.expectEqual(@as(c_int, 1), stub_var_calls);
    try testing.expectEqualStrings("my_var", std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&stub_var_name)), 0));
    try testing.expectEqualStrings("some value", std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&stub_var_value)), 0));
}

test "var: invalid format and invalid name fail" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, -1), apply(&config, "var", "no_comma"));
    try testing.expect(std.mem.startsWith(u8, lastError(), "Invalid variable format (expected \x1b[1mname,value\x1b[0m): \x1b[1m\x1b[31mno_comma"));

    resetStub();
    stub_var_name_valid = false;
    try testing.expectEqual(@as(c_int, -1), apply(&config, "var", "2bad,value"));
    try testing.expect(std.mem.startsWith(u8, lastError(), "Invalid variable name (allowed: [A-Za-z_][A-Za-z0-9_]*): \x1b[1m\x1b[31m2bad"));
    try testing.expectEqual(@as(c_int, 0), stub_var_calls);
}

test "exec and exec_once append with prefix matching" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "exec", "foot"));
    try testing.expectEqual(@as(i32, 1), config.exec_count);
    try testing.expectEqualStrings("foot", spanC(config.exec[0]));

    try testing.expectEqual(@as(c_int, 1), apply(&config, "exec_once", "acwm-msg dispatch quit"));
    try testing.expectEqual(@as(i32, 1), config.exec_once_count);
    try testing.expectEqualStrings("acwm-msg dispatch quit", spanC(config.exec_once[0]));

    // "exec_once_extra" matches the exec_once prefix in C
    try testing.expectEqual(@as(c_int, 1), apply(&config, "exec_once_extra", "second"));
    try testing.expectEqual(@as(i32, 2), config.exec_once_count);
    try testing.expectEqualStrings("second", spanC(config.exec_once[1]));
}

test "source and source_optional call parse_config_file with the right flag" {
    var config: c.Config = std.mem.zeroes(c.Config);
    resetStub();

    try testing.expectEqual(@as(c_int, 1), apply(&config, "source", "~/.config/acwm/extra.conf"));
    try testing.expectEqual(@as(c_int, 1), stub_config_calls);
    try testing.expectEqual(@as(c_int, 1), stub_config_must_exist);
    try testing.expectEqualStrings("~/.config/acwm/extra.conf", std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&stub_config_path)), 0));

    resetStub();
    try testing.expectEqual(@as(c_int, 1), apply(&config, "source_optional", "/etc/acwm/optional.conf"));
    try testing.expectEqual(@as(c_int, 1), stub_config_calls);
    try testing.expectEqual(@as(c_int, 0), stub_config_must_exist);

    // prefix behavior: "source_extra" is a source with must_exist=true
    resetStub();
    try testing.expectEqual(@as(c_int, 1), apply(&config, "source_extra", "/tmp/x.conf"));
    try testing.expectEqual(@as(c_int, 1), stub_config_must_exist);
}
