//! Port of src/config/conflict_check.c (strangler-fig Phase 4).
//!
//! Exports the same C symbols as the C twin (removed from the compositor
//! link). Pure logic over binding tables: keybind conflicts are grouped via
//! qsort + adjacency (mode strings, common-mode wildcard, allowconflict
//! opt-out), while mouse/axis/switch/gesture go through the generic
//! callback-driven checker. Axis/gesture wildcard matching uses ALLDIR.
//!
//! C types come from the translate-c module ("cc"); the comparator and the
//! metadata callbacks stay C-ABI function pointers because qsort and
//! check_simple_binding_conflicts are C-facing. Intentional divergence from
//! C: allocator/callback-null failures return false instead of dereferencing
//! NULL (UB in the C twin).
//!
//! Tests live at the bottom and need tests/conflict_check_stub.c
//! (acwm_error_impl recorder + config_file_path_at table).

const std = @import("std");
const c = @import("cc");

const WLR_INFO: c_uint = 2;

const MOD_LOGO: u32 = @intCast(c.WLR_MODIFIER_LOGO);
const MOD_CTRL: u32 = @intCast(c.WLR_MODIFIER_CTRL);
const MOD_ALT: u32 = @intCast(c.WLR_MODIFIER_ALT);
const MOD_SHIFT: u32 = @intCast(c.WLR_MODIFIER_SHIFT);
const MOD_MOD3: u32 = @intCast(c.WLR_MODIFIER_MOD3);
const ALLDIR_C: u32 = @intCast(c.ALLDIR);

extern fn acwm_error_impl(log: bool, verbosity: c_uint, file: [*:0]const u8, line: c_int, fmt: [*:0]const u8, ...) callconv(.c) void;
/// Defined in load.c; NULL for out-of-range indices (passed to printf %s,
/// which renders "(null)" — same as the C twin).
extern fn config_file_path_at(index: c_int) callconv(.c) [*c]const u8;

extern "c" fn strcmp(a: [*:0]const u8, b: [*:0]const u8) c_int;

fn modePtr(b: *const [28]u8) [*:0]const u8 {
    // Bindings keep mode as a NUL-terminated char[28] (parser snprintf
    // "%.27s"); the C twin strcmp's the array directly.
    return @ptrCast(b);
}

fn reportConflict(
    comptime simple: bool,
    kind: ?[*:0]const u8,
    any_common: bool,
    mode_a: [*:0]const u8,
    file_a: [*c]const u8,
    line_a: c_int,
    file_b: [*c]const u8,
    line_b: c_int,
) void {
    if (simple) {
        acwm_error_impl(
            false,
            WLR_INFO,
            @src().file,
            @src().line,
            "%s conflict in keymode %s:\n  File \"%s\", line %d\n  File \"%s\", line %d\n",
            kind.?,
            if (any_common) @as([*:0]const u8, "common") else mode_a,
            file_a,
            line_a,
            file_b,
            line_b,
        );
    } else {
        acwm_error_impl(
            false,
            WLR_INFO,
            @src().file,
            @src().line,
            "Key binding conflict in keymode %s:\n  File \"%s\", line %d\n  File \"%s\", line %d\n",
            if (any_common) @as([*:0]const u8, "common") else mode_a,
            file_a,
            line_a,
            file_b,
            line_b,
        );
    }
}

fn fileFor(index: c_int) [*c]const u8 {
    return if (index >= 0) config_file_path_at(index) else "(built-in)";
}

// ---------------------------------------------------------------------------
// comparators / equality (C ABI: used by qsort and the generic checker)
// ---------------------------------------------------------------------------

export fn compare_keybind_by_key_only(a: ?*const anyopaque, b: ?*const anyopaque) callconv(.c) c_int {
    const ka: *const c.KeyBinding = @ptrCast(@alignCast(a.?));
    const kb: *const c.KeyBinding = @ptrCast(@alignCast(b.?));

    if (ka.mod != kb.mod)
        return if (ka.mod > kb.mod) 1 else -1;

    if (ka.keysymcode.type != kb.keysymcode.type)
        return if (ka.keysymcode.type > kb.keysymcode.type) 1 else -1;

    if (ka.keysymcode.type == c.KEY_TYPE_SYM) {
        if (ka.keysymcode.keysym != kb.keysymcode.keysym)
            return if (ka.keysymcode.keysym > kb.keysymcode.keysym) 1 else -1;
    } else {
        if (ka.keysymcode.keycode.keycode1 != kb.keysymcode.keycode.keycode1)
            return if (ka.keysymcode.keycode.keycode1 > kb.keysymcode.keycode.keycode1) 1 else -1;
    }
    return 0;
}

export fn same_key(a: ?*const c.KeyBinding, b: ?*const c.KeyBinding) callconv(.c) bool {
    return compare_keybind_by_key_only(a, b) == 0;
}

export fn same_mousebind_key(a: ?*const anyopaque, b: ?*const anyopaque) callconv(.c) bool {
    const ma: *const c.MouseBinding = @ptrCast(@alignCast(a.?));
    const mb: *const c.MouseBinding = @ptrCast(@alignCast(b.?));
    return ma.mod == mb.mod and ma.button == mb.button;
}

export fn same_axisbind_key(a: ?*const anyopaque, b: ?*const anyopaque) callconv(.c) bool {
    const aa: *const c.AxisBinding = @ptrCast(@alignCast(a.?));
    const ab: *const c.AxisBinding = @ptrCast(@alignCast(b.?));
    return aa.mod == ab.mod and
        (aa.dir == ALLDIR_C or ab.dir == ALLDIR_C or aa.dir == ab.dir);
}

export fn same_switchbind_key(a: ?*const anyopaque, b: ?*const anyopaque) callconv(.c) bool {
    const sa: *const c.SwitchBinding = @ptrCast(@alignCast(a.?));
    const sb: *const c.SwitchBinding = @ptrCast(@alignCast(b.?));
    return sa.fold == sb.fold;
}

export fn same_gesturebind_key(a: ?*const anyopaque, b: ?*const anyopaque) callconv(.c) bool {
    const ga: *const c.GestureBinding = @ptrCast(@alignCast(a.?));
    const gb: *const c.GestureBinding = @ptrCast(@alignCast(b.?));
    return ga.mod == gb.mod and ga.fingers_count == gb.fingers_count and
        (ga.motion == ALLDIR_C or gb.motion == ALLDIR_C or ga.motion == gb.motion);
}

// ---------------------------------------------------------------------------
// metadata extractors (same shape as BindingMetaFunc)
// ---------------------------------------------------------------------------

export fn get_mousebind_meta(elem: ?*const anyopaque, meta: [*c]c.BindingConflictMeta) callconv(.c) void {
    const b: *const c.MouseBinding = @ptrCast(@alignCast(elem.?));
    meta[0] = .{
        .mode = modePtr(&b.mode),
        .iscommonmode = b.iscommonmode,
        .file_index = b.file_index,
        .line_number = b.line_number,
    };
}

export fn get_axisbind_meta(elem: ?*const anyopaque, meta: [*c]c.BindingConflictMeta) callconv(.c) void {
    const b: *const c.AxisBinding = @ptrCast(@alignCast(elem.?));
    meta[0] = .{
        .mode = modePtr(&b.mode),
        .iscommonmode = b.iscommonmode,
        .file_index = b.file_index,
        .line_number = b.line_number,
    };
}

export fn get_switchbind_meta(elem: ?*const anyopaque, meta: [*c]c.BindingConflictMeta) callconv(.c) void {
    const b: *const c.SwitchBinding = @ptrCast(@alignCast(elem.?));
    meta[0] = .{
        .mode = modePtr(&b.mode),
        .iscommonmode = b.iscommonmode,
        .file_index = b.file_index,
        .line_number = b.line_number,
    };
}

export fn get_gesturebind_meta(elem: ?*const anyopaque, meta: [*c]c.BindingConflictMeta) callconv(.c) void {
    const b: *const c.GestureBinding = @ptrCast(@alignCast(elem.?));
    meta[0] = .{
        .mode = modePtr(&b.mode),
        .iscommonmode = b.iscommonmode,
        .file_index = b.file_index,
        .line_number = b.line_number,
    };
}

export fn check_mouse_binding_conflicts(config: *c.Config) callconv(.c) bool {
    return check_simple_binding_conflicts(
        @ptrCast(config.mouse_bindings),
        @intCast(config.mouse_bindings_count),
        @sizeOf(c.MouseBinding),
        same_mousebind_key,
        get_mousebind_meta,
        "mousebind",
    );
}

export fn check_axis_binding_conflicts(config: *c.Config) callconv(.c) bool {
    return check_simple_binding_conflicts(
        @ptrCast(config.axis_bindings),
        @intCast(config.axis_bindings_count),
        @sizeOf(c.AxisBinding),
        same_axisbind_key,
        get_axisbind_meta,
        "axisbind",
    );
}

export fn check_switch_binding_conflicts(config: *c.Config) callconv(.c) bool {
    return check_simple_binding_conflicts(
        @ptrCast(config.switch_bindings),
        @intCast(config.switch_bindings_count),
        @sizeOf(c.SwitchBinding),
        same_switchbind_key,
        get_switchbind_meta,
        "switchbind",
    );
}

export fn check_gesture_binding_conflicts(config: *c.Config) callconv(.c) bool {
    return check_simple_binding_conflicts(
        @ptrCast(config.gesture_bindings),
        @intCast(config.gesture_bindings_count),
        @sizeOf(c.GestureBinding),
        same_gesturebind_key,
        get_gesturebind_meta,
        "gesturebind",
    );
}

// ---------------------------------------------------------------------------
// generic checker
// ---------------------------------------------------------------------------

export fn check_simple_binding_conflicts(
    arr: ?*anyopaque,
    count: usize,
    elem_size: usize,
    same_key_fn: ?*const fn (?*const anyopaque, ?*const anyopaque) callconv(.c) bool,
    get_meta: c.BindingMetaFunc,
    kind: [*:0]const u8,
) callconv(.c) bool {
    var conflict_found = false;
    const base: [*]u8 = @ptrCast(arr orelse return false);
    const is_same = same_key_fn orelse return false;
    const meta_of = get_meta orelse return false;

    var i: usize = 0;
    while (i < count) : (i += 1) {
        var j: usize = i + 1;
        while (j < count) : (j += 1) {
            const ea = base + i * elem_size;
            const eb = base + j * elem_size;
            if (!is_same(ea, eb))
                continue;

            var ma: c.BindingConflictMeta = undefined;
            var mb: c.BindingConflictMeta = undefined;
            meta_of(ea, &ma);
            meta_of(eb, &mb);

            const same_mode = strcmp(@ptrCast(ma.mode), @ptrCast(mb.mode)) == 0;
            const any_common = ma.iscommonmode or mb.iscommonmode;
            if (same_mode or any_common) {
                conflict_found = true;
                reportConflict(
                    true,
                    kind,
                    any_common,
                    @ptrCast(ma.mode),
                    fileFor(ma.file_index),
                    ma.line_number,
                    fileFor(mb.file_index),
                    mb.line_number,
                );
            }
        }
    }
    return conflict_found;
}

// ---------------------------------------------------------------------------
// mod_to_string
// ---------------------------------------------------------------------------

var mod_buf: [128]u8 = undefined;

fn appendMod(buf: *[128]u8, len: *usize, s: []const u8) void {
    @memcpy(buf[len.* .. len.* + s.len], s);
    len.* += s.len;
    buf[len.*] = 0;
}

export fn mod_to_string(mod: u32) callconv(.c) [*:0]const u8 {
    var len: usize = 0;
    mod_buf[0] = 0;

    if (mod & MOD_LOGO != 0) appendMod(&mod_buf, &len, "Super+");
    if (mod & MOD_CTRL != 0) appendMod(&mod_buf, &len, "Ctrl+");
    if (mod & MOD_ALT != 0) appendMod(&mod_buf, &len, "Alt+");
    if (mod & MOD_SHIFT != 0) appendMod(&mod_buf, &len, "Shift+");
    if (mod & MOD_MOD3 != 0) appendMod(&mod_buf, &len, "Hyper+");

    if (len > 0)
        mod_buf[len - 1] = 0
    else {
        @memcpy(mod_buf[0..4], "None");
        mod_buf[4] = 0;
    }
    return @ptrCast(&mod_buf);
}

// ---------------------------------------------------------------------------
// key binding conflicts
// ---------------------------------------------------------------------------

export fn check_key_binding_conflicts(config: *c.Config) callconv(.c) bool {
    const n: usize = @intCast(config.key_bindings_count);
    if (n < 2)
        return false;

    // Copies user-defined bindings (line number > 0).
    const raw = c.malloc(n * @sizeOf(c.KeyBinding)) orelse return false;
    defer c.free(raw);
    const binds: [*]c.KeyBinding = @ptrCast(@alignCast(raw));

    var count: usize = 0;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (config.key_bindings[i].line_number > 0) {
            binds[count] = config.key_bindings[i];
            count += 1;
        }
    }
    if (count < 2)
        return false;

    // Sorts only by key so bindings with the same key are grouped together.
    c.qsort(binds, count, @sizeOf(c.KeyBinding), compare_keybind_by_key_only);

    var conflict_found = false;
    i = 0;
    while (i < count) {
        var j = i;
        // Finds all bindings with the same key (range [i, j)).
        while (j < count and same_key(&binds[i], &binds[j]))
            j += 1;

        var a: usize = i;
        while (a < j) : (a += 1) {
            var b: usize = a + 1;
            while (b < j) : (b += 1) {
                const same_mode = strcmp(modePtr(&binds[a].mode), modePtr(&binds[b].mode)) == 0;
                const any_common = binds[a].iscommonmode or binds[b].iscommonmode;
                const allow_conflict = binds[a].isallowconflict and binds[b].isallowconflict;

                if ((same_mode or any_common) and !allow_conflict) {
                    conflict_found = true;
                    reportConflict(
                        false,
                        null,
                        any_common,
                        modePtr(&binds[a].mode),
                        fileFor(binds[a].file_index),
                        binds[a].line_number,
                        fileFor(binds[b].file_index),
                        binds[b].line_number,
                    );
                }
            }
        }
        i = j; // Moves to the next key group.
    }
    return conflict_found;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: see tests/conflict_check_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_last_error: [1024]u8;
extern var stub_error_count: c_int;
extern var stub_file_paths: [4][*:0]const u8;
extern var stub_file_paths_count: c_int;

fn resetStub() void {
    stub_error_count = 0;
    stub_last_error[0] = 0;
    stub_file_paths_count = 0;
}

fn lastError() []const u8 {
    return std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&stub_last_error)), 0);
}

fn setMode(dst: *[28]u8, s: []const u8) void {
    @memset(dst, 0);
    @memcpy(dst[0..s.len], s);
}

fn keyBinding(mod: u32, sym: u32, mode: []const u8, line: c_int, common: bool, allow: bool) c.KeyBinding {
    var kb = c.KeyBinding{
        .mod = mod,
        .line_number = line,
        .iscommonmode = common,
        .isallowconflict = allow,
    };
    kb.keysymcode.type = c.KEY_TYPE_SYM;
    kb.keysymcode.keysym = sym;
    setMode(&kb.mode, mode);
    return kb;
}

test "keybind comparator orders by mod, type, then sym/code" {
    const a = c.KeyBinding{ .mod = 1, .keysymcode = .{ .type = c.KEY_TYPE_SYM, .keysym = 10 } };
    const b = c.KeyBinding{ .mod = 2, .keysymcode = .{ .type = c.KEY_TYPE_SYM, .keysym = 1 } };
    try testing.expect(compare_keybind_by_key_only(&a, &b) < 0);
    try testing.expect(compare_keybind_by_key_only(&b, &a) > 0);

    var c1 = c.KeyBinding{ .mod = 1, .keysymcode = .{ .type = c.KEY_TYPE_SYM, .keysym = 10 } };
    var c2 = c.KeyBinding{ .mod = 1, .keysymcode = .{ .type = c.KEY_TYPE_CODE, .keysym = 0 } };
    c2.keysymcode.keycode.keycode1 = 30;
    try testing.expect(compare_keybind_by_key_only(&c1, &c2) > 0); // SYM(1) > CODE(0)
    try testing.expect(compare_keybind_by_key_only(&c2, &c1) < 0);

    var s1 = c.KeyBinding{ .mod = 1, .keysymcode = .{ .type = c.KEY_TYPE_SYM, .keysym = 10 } };
    var s2 = c.KeyBinding{ .mod = 1, .keysymcode = .{ .type = c.KEY_TYPE_SYM, .keysym = 20 } };
    try testing.expect(compare_keybind_by_key_only(&s1, &s2) < 0);
    try testing.expect(compare_keybind_by_key_only(&s1, &s1) == 0);

    var k1 = c.KeyBinding{ .mod = 1, .keysymcode = .{ .type = c.KEY_TYPE_CODE } };
    k1.keysymcode.keycode.keycode1 = 30;
    var k2 = c.KeyBinding{ .mod = 1, .keysymcode = .{ .type = c.KEY_TYPE_CODE } };
    k2.keysymcode.keycode.keycode1 = 40;
    try testing.expect(compare_keybind_by_key_only(&k1, &k2) < 0);
    try testing.expect(same_key(&k1, &k1));
    try testing.expect(!same_key(&k1, &k2));
}

test "mouse/switch equality" {
    const m1 = c.MouseBinding{ .mod = 64, .button = 272 };
    const m2 = c.MouseBinding{ .mod = 64, .button = 272 };
    const m3 = c.MouseBinding{ .mod = 64, .button = 273 };
    try testing.expect(same_mousebind_key(&m1, &m2));
    try testing.expect(!same_mousebind_key(&m1, &m3));

    const s1 = c.SwitchBinding{ .fold = 1 };
    const s2 = c.SwitchBinding{ .fold = 1 };
    const s3 = c.SwitchBinding{ .fold = 2 };
    try testing.expect(same_switchbind_key(&s1, &s2));
    try testing.expect(!same_switchbind_key(&s1, &s3));
}

test "axis/gesture ALLDIR wildcard matching" {
    const a1 = c.AxisBinding{ .mod = 64, .dir = @intCast(c.UP) };
    const a2 = c.AxisBinding{ .mod = 64, .dir = @intCast(c.DOWN) };
    const a3 = c.AxisBinding{ .mod = 64, .dir = ALLDIR_C };
    const a4 = c.AxisBinding{ .mod = 1, .dir = ALLDIR_C };
    try testing.expect(!same_axisbind_key(&a1, &a2));
    try testing.expect(same_axisbind_key(&a1, &a3));
    try testing.expect(same_axisbind_key(&a2, &a3));
    try testing.expect(!same_axisbind_key(&a1, &a4)); // mod still matters

    const g1 = c.GestureBinding{ .mod = 0, .fingers_count = 3, .motion = @intCast(c.LEFT) };
    const g2 = c.GestureBinding{ .mod = 0, .fingers_count = 3, .motion = @intCast(c.RIGHT) };
    const g3 = c.GestureBinding{ .mod = 0, .fingers_count = 3, .motion = ALLDIR_C };
    const g4 = c.GestureBinding{ .mod = 0, .fingers_count = 4, .motion = ALLDIR_C };
    try testing.expect(!same_gesturebind_key(&g1, &g2));
    try testing.expect(same_gesturebind_key(&g1, &g3));
    try testing.expect(!same_gesturebind_key(&g1, &g4));
}

test "mod_to_string formats modifier masks" {
    try testing.expectEqualStrings("None", std.mem.span(mod_to_string(0)));
    try testing.expectEqualStrings("Super", std.mem.span(mod_to_string(MOD_LOGO)));
    try testing.expectEqualStrings("Super+Ctrl+Alt+Shift+Hyper", std.mem.span(mod_to_string(
        MOD_LOGO | MOD_CTRL | MOD_ALT | MOD_SHIFT | MOD_MOD3,
    )));
    try testing.expectEqualStrings("Ctrl+Shift", std.mem.span(mod_to_string(MOD_CTRL | MOD_SHIFT)));
}

test "simple checker: same mode conflict with file/line report" {
    resetStub();
    var config: c.Config = std.mem.zeroes(c.Config);
    var m1 = c.MouseBinding{ .mod = 64, .button = 272, .file_index = -1 };
    setMode(&m1.mode, "default");
    var m2 = c.MouseBinding{ .mod = 64, .button = 272, .line_number = 12, .file_index = 0 };
    setMode(&m2.mode, "default");
    var arr = [_]c.MouseBinding{ m1, m2 };
    config.mouse_bindings = &arr;
    config.mouse_bindings_count = 2;

    stub_file_paths[0] = "/etc/acwm/config.conf";
    stub_file_paths_count = 1;
    try testing.expect(check_mouse_binding_conflicts(&config));
    try testing.expectEqual(@as(c_int, 1), stub_error_count);
    const msg = lastError();
    try testing.expect(std.mem.indexOf(u8, msg, "mousebind conflict in keymode default:") != null);
    try testing.expect(std.mem.indexOf(u8, msg, "(built-in)") != null);
    try testing.expect(std.mem.indexOf(u8, msg, "\"/etc/acwm/config.conf\", line 12") != null);
}

test "simple checker: different modes do not conflict unless common" {
    resetStub();
    var config: c.Config = std.mem.zeroes(c.Config);
    var m1 = c.MouseBinding{ .mod = 64, .button = 272 };
    setMode(&m1.mode, "default");
    var m2 = c.MouseBinding{ .mod = 64, .button = 272 };
    setMode(&m2.mode, "resize");
    var arr = [_]c.MouseBinding{ m1, m2 };
    config.mouse_bindings = &arr;
    config.mouse_bindings_count = 2;

    try testing.expect(!check_mouse_binding_conflicts(&config));
    try testing.expectEqual(@as(c_int, 0), stub_error_count);

    arr[1].iscommonmode = true;
    try testing.expect(check_mouse_binding_conflicts(&config));
    try testing.expect(std.mem.indexOf(u8, lastError(), "keymode common:") != null);
}

test "simple checker: single binding and gesture wrapper" {
    resetStub();
    var config: c.Config = std.mem.zeroes(c.Config);
    var g1 = c.GestureBinding{ .mod = 0, .fingers_count = 3, .motion = ALLDIR_C, .line_number = 3 };
    setMode(&g1.mode, "default");
    var arr = [_]c.GestureBinding{g1};
    config.gesture_bindings = &arr;
    config.gesture_bindings_count = 1;
    try testing.expect(!check_gesture_binding_conflicts(&config));

    config.gesture_bindings_count = 0;
    try testing.expect(!check_gesture_binding_conflicts(&config));
}

test "keybind conflicts: built-ins filtered, grouping works, allowconflict opt-out" {
    resetStub();
    var config: c.Config = std.mem.zeroes(c.Config);
    var arr = [_]c.KeyBinding{
        keyBinding(MOD_LOGO, 10, "default", 0, false, false), // built-in: ignored
        keyBinding(MOD_LOGO, 10, "default", 5, false, false),
        keyBinding(MOD_LOGO, 20, "default", 6, false, false), // different key
        keyBinding(MOD_LOGO, 10, "default", 7, false, false), // conflict with line 5
    };
    config.key_bindings = &arr;
    config.key_bindings_count = arr.len;

    stub_file_paths[0] = "/etc/acwm/config.conf";
    stub_file_paths_count = 1;
    try testing.expect(check_key_binding_conflicts(&config));
    try testing.expectEqual(@as(c_int, 1), stub_error_count);
    const msg = lastError();
    try testing.expect(std.mem.indexOf(u8, msg, "Key binding conflict in keymode default:") != null);
    try testing.expect(std.mem.indexOf(u8, msg, "line 5") != null);
    try testing.expect(std.mem.indexOf(u8, msg, "line 7") != null);

    // both allowconflict -> silent
    resetStub();
    arr[1].isallowconflict = true;
    arr[3].isallowconflict = true;
    try testing.expect(!check_key_binding_conflicts(&config));
    try testing.expectEqual(@as(c_int, 0), stub_error_count);

    // only one allowconflict -> still reported
    arr[3].isallowconflict = false;
    try testing.expect(check_key_binding_conflicts(&config));
}

test "keybind conflicts: mode strings and common mode" {
    resetStub();
    var config: c.Config = std.mem.zeroes(c.Config);
    var arr = [_]c.KeyBinding{
        keyBinding(MOD_CTRL, 40, "default", 2, false, false),
        keyBinding(MOD_CTRL, 40, "resize", 3, false, false),
    };
    config.key_bindings = &arr;
    config.key_bindings_count = arr.len;

    try testing.expect(!check_key_binding_conflicts(&config));
    try testing.expectEqual(@as(c_int, 0), stub_error_count);

    arr[1].iscommonmode = true;
    try testing.expect(check_key_binding_conflicts(&config));
    try testing.expect(std.mem.indexOf(u8, lastError(), "keymode common:") != null);
}

test "keybind conflicts: fewer than two user bindings short-circuit" {
    resetStub();
    var config: c.Config = std.mem.zeroes(c.Config);
    var arr = [_]c.KeyBinding{
        keyBinding(MOD_LOGO, 10, "default", 0, false, false),
        keyBinding(MOD_LOGO, 10, "default", 4, false, false),
    };
    config.key_bindings = &arr;
    config.key_bindings_count = arr.len;
    try testing.expect(!check_key_binding_conflicts(&config));
    try testing.expectEqual(@as(c_int, 0), stub_error_count);

    config.key_bindings_count = 1;
    try testing.expect(!check_key_binding_conflicts(&config));
}
