//! Port of src/config/variable_expand.c (strangler-fig Phase 4).
//!
//! Exports the same C symbols as the C twin (which is removed from the
//! compositor build). Reads/writes the global `Config config` through the
//! translate-c module ("cc"), so the C struct layout is authoritative —
//! no hand-maintained mirrors.
//!
//! Tests live at the bottom; they need the C stub in
//! tests/zig_port_stub.c (which defines a zeroed `Config config` plus the
//! variadic logging stubs).

const std = @import("std");
const c = @import("cc");

// ---------------------------------------------------------------------------
// libc + helpers
// ---------------------------------------------------------------------------

extern "c" fn malloc(size: usize) ?*anyopaque;
extern "c" fn calloc(nmemb: usize, size: usize) ?*anyopaque;
extern "c" fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern "c" fn strcmp(a: [*c]const u8, b: [*c]const u8) c_int;

fn isalphaChar(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z');
}

fn isalnumChar(ch: u8) bool {
    return isalphaChar(ch) or (ch >= '0' and ch <= '9');
}

// ---------------------------------------------------------------------------
// exported functions (same symbols as the C twin)
// ---------------------------------------------------------------------------

fn findConfigVar(name: [*:0]const u8) ?*c.ConfigVar {
    const vars = c.config.vars;
    if (vars == null)
        return null;
    var i: i32 = 0;
    while (i < c.config.vars_count) : (i += 1) {
        const v = vars[@intCast(i)];
        if (v != null and v.*.name != null and
            strcmp(v.*.name, @ptrCast(name)) == 0)
        {
            return v;
        }
    }
    return null;
}

export fn is_valid_var_name(name: ?[*:0]const u8) callconv(.c) bool {
    const s = name orelse return false;
    if (s[0] == 0)
        return false;
    if (!isalphaChar(s[0]) and s[0] != '_')
        return false;
    var i: usize = 1;
    while (s[i] != 0) : (i += 1) {
        if (!isalnumChar(s[i]) and s[i] != '_')
            return false;
    }
    return true;
}

export fn set_config_var(name: [*:0]const u8, value: [*:0]const u8) callconv(.c) void {
    if (findConfigVar(name)) |var_| {
        const dup = strdup(value) orelse return;
        if (var_.value != null)
            free(var_.value);
        var_.value = dup;
        return;
    }

    const new_var: ?*c.ConfigVar = @ptrCast(@alignCast(calloc(1, @sizeOf(c.ConfigVar))));
    const nv = new_var orelse return;
    nv.name = strdup(name);
    nv.value = strdup(value);
    if (nv.name == null or nv.value == null) {
        free(@ptrCast(nv.name));
        free(@ptrCast(nv.value));
        free(@ptrCast(nv));
        return;
    }

    const old = c.config.vars;
    const new_vars: ?[*]?*c.ConfigVar = @ptrCast(@alignCast(realloc(
        @ptrCast(old),
        @intCast(@as(usize, @intCast(c.config.vars_count + 1)) * @sizeOf(?*c.ConfigVar)),
    )));
    if (new_vars == null) {
        free(@ptrCast(nv.name));
        free(@ptrCast(nv.value));
        free(@ptrCast(nv));
        return;
    }
    c.config.vars = new_vars;
    c.config.vars[@intCast(c.config.vars_count)] = nv;
    c.config.vars_count += 1;
}

const GrowBuf = struct {
    buf: ?[*]u8 = null,
    cap: usize = 0,
    len: usize = 0,

    fn append(self: *GrowBuf, s: []const u8) bool {
        if (self.len + s.len + 1 > self.cap) {
            const new_cap = self.cap * 2 + s.len + 1;
            const new_buf = realloc(self.buf, new_cap);
            if (new_buf == null)
                return false;
            self.buf = @ptrCast(new_buf);
            self.cap = new_cap;
        }
        const base = self.buf.?[self.len..self.cap];
        @memcpy(base[0..s.len], s);
        self.len += s.len;
        self.buf.?[self.len] = 0;
        return true;
    }
};

/// The caller owns the returned string (malloc'd, C free contract).
export fn expand_config_variables(value: [*:0]const u8) callconv(.c) ?[*:0]u8 {
    var g = GrowBuf{ .cap = std.mem.len(value) + 1 };
    g.buf = @ptrCast(malloc(g.cap));
    if (g.buf == null)
        return null;
    g.buf.?[0] = 0;

    var p: usize = 0;
    const v = std.mem.span(value);
    while (p < v.len) {
        var name_start: ?usize = null;
        var name_len: usize = 0;
        var next: usize = 0;

        if (v[p] == '$' and p + 1 < v.len and v[p + 1] == '{') {
            if (std.mem.indexOfScalarPos(u8, v, p + 2, '}')) |close| {
                name_start = p + 2;
                name_len = close - (p + 2);
                next = close + 1;
            }
        } else if (v[p] == '$' and p + 1 < v.len and
            (isalphaChar(v[p + 1]) or v[p + 1] == '_'))
        {
            var q = p + 1;
            while (q < v.len and (isalnumChar(v[q]) or v[q] == '_'))
                q += 1;
            name_start = p + 1;
            name_len = q - (p + 1);
            next = q;
        }

        if (name_start != null and name_len > 0 and name_len < 128) {
            var var_name: [128]u8 = undefined;
            @memcpy(var_name[0..name_len], v[name_start.?..][0..name_len]);
            var_name[name_len] = 0;
            const var_name_z: [*:0]const u8 = @ptrCast(&var_name);

            if (findConfigVar(var_name_z)) |var_| {
                const val = std.mem.span(@as([*:0]const u8, @ptrCast(var_.value)));
                if (!g.append(val))
                    return null;
                p = next;
                continue;
            }
            if (!g.append(v[p..next]))
                return null;
            p = next;
            continue;
        }

        if (!g.append(v[p .. p + 1]))
            return null;
        p += 1;
    }
    return @ptrCast(g.buf);
}

// ---------------------------------------------------------------------------
// tests (stub-backed: see tests/zig_port_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

fn cstr(s: []const u8) [:0]u8 {
    const b = testing.allocator.allocSentinel(u8, s.len, 0) catch unreachable;
    @memcpy(b[0..s.len], s);
    return b;
}

test "is_valid_var_name" {
    const good = cstr("my_var_2");
    defer testing.allocator.free(good);
    try testing.expect(is_valid_var_name(good));
    const underscore = cstr("_ok");
    defer testing.allocator.free(underscore);
    try testing.expect(is_valid_var_name(underscore));
    const digit_start = cstr("2bad");
    defer testing.allocator.free(digit_start);
    try testing.expect(!is_valid_var_name(digit_start));
    const empty = cstr("");
    defer testing.allocator.free(empty);
    try testing.expect(!is_valid_var_name(empty));
    try testing.expect(!is_valid_var_name(null));
    const dash = cstr("has-dash");
    defer testing.allocator.free(dash);
    try testing.expect(!is_valid_var_name(dash));
}

test "set and expand config variables" {
    const n1 = cstr("term");
    defer testing.allocator.free(n1);
    const v1 = cstr("foot");
    defer testing.allocator.free(v1);
    set_config_var(n1, v1);

    const n2 = cstr("nvidia");
    defer testing.allocator.free(n2);
    const v2 = cstr("env=NO");
    defer testing.allocator.free(v2);
    set_config_var(n2, v2);

    // re-set overwrites without growing
    const v1b = cstr("foot-client");
    defer testing.allocator.free(v1b);
    set_config_var(n1, v1b);

    const input = cstr("run ${term} and $nvidia !${missing}!$");
    defer testing.allocator.free(input);
    const out = expand_config_variables(input);
    try testing.expect(out != null);
    defer free(out);
    try testing.expectEqualStrings(
        "run foot-client and env=NO !${missing}!$",
        std.mem.span(out.?),
    );
}
