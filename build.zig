const std = @import("std");
const Io = std.Io;

const version = "0.1.0";

const common_cflags = [_][]const u8{
    "-U_FORTIFY_SOURCE",
    "-Wno-unused-function",
    "-Wno-unused-parameter",
    "-Wno-unused-result",
    "-DWLR_USE_UNSTABLE",
    "-D_POSIX_C_SOURCE=200809L",
};

/// Runs a program at configure time and returns trimmed stdout (null on error).
fn capture(b: *std.Build, argv: []const []const u8) ?[]const u8 {
    switch (b.runFallible(argv, .{ .stderr_behavior = .ignore })) {
        .success => |stdout| return std.mem.trim(u8, stdout, " \n\r\t"),
        else => return null,
    }
}

/// Creates a C-language executable with libc linked.
fn cExe(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    name: []const u8,
) *std.Build.Step.Compile {
    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    return b.addExecutable(.{ .name = name, .root_module = mod });
}

fn dupe(b: *std.Build, s: []const u8) []const u8 {
    return b.allocator.dupe(u8, s) catch "";
}

/// Applies pkg-config output (cflags + libs) to a C compile step.
fn applyPkgConfig(
    b: *std.Build,
    step: *std.Build.Step.Compile,
    pkgs: []const []const u8,
) void {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(b.allocator);
    argv.append(b.allocator, "pkg-config") catch return;
    argv.appendSlice(b.allocator, &.{ "--cflags", "--libs" }) catch return;
    for (pkgs) |p| argv.append(b.allocator, p) catch return;
    const out = capture(b, argv.items) orelse return;

    var it = std.mem.tokenizeAny(u8, out, " \n\r\t");
    while (it.next()) |tok| {
        if (std.mem.startsWith(u8, tok, "-I")) {
            const path = tok[2..];
            if (path.len > 0)
                step.root_module.addIncludePath(.{ .cwd_relative = dupe(b, path) });
        } else if (std.mem.startsWith(u8, tok, "-L")) {
            const path = tok[2..];
            if (path.len > 0)
                step.root_module.addLibraryPath(.{ .cwd_relative = dupe(b, path) });
        } else if (std.mem.startsWith(u8, tok, "-l")) {
            const lib = tok[2..];
            if (lib.len > 0)
                step.root_module.linkSystemLibrary(dupe(b, lib), .{ .use_pkg_config = .no });
        } else if (tok.len > 1 and tok[0] == '/' and
            (std.mem.endsWith(u8, tok, ".so") or std.mem.endsWith(u8, tok, ".a")))
        {
            // absolute library path (nix style): split into dir + lib name
            const idx = std.mem.lastIndexOfScalar(u8, tok, '/') orelse continue;
            const dir = tok[0..idx];
            var name = tok[idx + 1 ..];
            if (std.mem.startsWith(u8, name, "lib"))
                name = name[3..];
            if (std.mem.endsWith(u8, name, ".so"))
                name = name[0 .. name.len - 3];
            if (std.mem.endsWith(u8, name, ".a"))
                name = name[0 .. name.len - 2];
            step.root_module.addLibraryPath(.{ .cwd_relative = dupe(b, dir) });
            step.root_module.linkSystemLibrary(dupe(b, name), .{ .use_pkg_config = .no });
        }
    }
}

/// Runs pkg-config --cflags and returns the -I directories.
fn pkgIncludes(b: *std.Build, pkgs: []const []const u8) [][]const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(b.allocator);
    argv.append(b.allocator, "pkg-config") catch return &.{};
    argv.appendSlice(b.allocator, &.{"--cflags"}) catch return &.{};
    for (pkgs) |p| argv.append(b.allocator, p) catch return &.{};
    const out = capture(b, argv.items) orelse return &.{};

    var dirs: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeAny(u8, out, " \n\r\t");
    while (it.next()) |tok| {
        if (std.mem.startsWith(u8, tok, "-I") and tok.len > 2)
            dirs.append(b.allocator, dupe(b, tok[2..])) catch {};
    }
    return dirs.items;
}

fn hasPkg(b: *std.Build, name: []const u8) bool {
    return capture(b, &.{ "pkg-config", "--exists", name }) != null;
}

/// Builds per-executable C flags (common flags + extra defines).
fn cflags(b: *std.Build, extra: []const []const u8) []const []const u8 {
    var flags: std.ArrayList([]const u8) = .empty;
    for (common_cflags) |f| flags.append(b.allocator, f) catch {};
    for (extra) |f| flags.append(b.allocator, dupe(b, f)) catch {};
    return flags.items;
}

/// Protocol codegen: wayland-scanner at build step level.
const Protos = struct {
    b: *std.Build,
    gen_server: *std.Build.Step.WriteFile,
    gen_client: *std.Build.Step.WriteFile,
    server_headers: *std.StringHashMap(void),
    client_headers: *std.StringHashMap(void),

    /// Emits private-code .c + headers for one protocol xml.
    /// client_h_name overrides the generated client header file name
    /// (e.g. acwm-launch uses exe-prefixed names). Pass "" for the default.
    /// Returns the .c LazyPath to compile into the executable.
    fn gen(
        self: *const Protos,
        xml: []const u8,
        basename: []const u8,
        need_server: bool,
        need_client: bool,
        client_h_name: []const u8,
    ) std.Build.LazyPath {
        const b = self.b;
        const c_run = b.addSystemCommand(&.{ "wayland-scanner", "private-code" });
        c_run.addFileArg(.{ .cwd_relative = xml });
        const c_file = c_run.addOutputFileArg(b.fmt("{s}-protocol.c", .{basename}));

        if (need_server) {
            const h_run = b.addSystemCommand(&.{ "wayland-scanner", "server-header" });
            h_run.addFileArg(.{ .cwd_relative = xml });
            const h_file = h_run.addOutputFileArg(b.fmt("{s}-protocol.h", .{basename}));
            const dest = b.fmt("{s}-protocol.h", .{basename});
            if (!self.server_headers.contains(dest)) {
                _ = self.gen_server.addCopyFile(h_file, dest);
                self.server_headers.put(dest, {}) catch {};
            }
        }
        if (need_client) {
            const h_name = if (client_h_name.len > 0) client_h_name else b.fmt("{s}-client-protocol.h", .{basename});
            const h_run = b.addSystemCommand(&.{ "wayland-scanner", "client-header" });
            h_run.addFileArg(.{ .cwd_relative = xml });
            const h_file = h_run.addOutputFileArg(h_name);
            if (!self.client_headers.contains(h_name)) {
                _ = self.gen_client.addCopyFile(h_file, h_name);
                self.client_headers.put(h_name, {}) catch {};
            }
        }
        return c_file;
    }
};

/// Resolves the xml path for one compositor protocol by name.
fn serverProtoXml(b: *std.Build, wl_protocol_dir: []const u8, name: []const u8) []const u8 {
    if (std.mem.startsWith(u8, name, "wlr-"))
        return b.fmt("protocols/{s}.xml", .{name});
    if (std.mem.eql(u8, name, "xdg-shell"))
        return b.fmt("{s}/stable/xdg-shell/xdg-shell.xml", .{wl_protocol_dir});
    if (std.mem.eql(u8, name, "cursor-shape-v1"))
        return b.fmt("{s}/staging/cursor-shape/{s}.xml", .{ wl_protocol_dir, name });
    if (std.mem.startsWith(u8, name, "pointer-constraints"))
        return b.fmt("{s}/unstable/pointer-constraints/{s}.xml", .{ wl_protocol_dir, name });
    if (std.mem.startsWith(u8, name, "xdg-output"))
        return b.fmt("{s}/unstable/xdg-output/{s}.xml", .{ wl_protocol_dir, name });
    if (std.mem.eql(u8, name, "tablet-v2"))
        return b.fmt("{s}/stable/tablet/{s}.xml", .{ wl_protocol_dir, name });
    // staging dirs drop the trailing "-v1"; the xml file keeps it
    if (std.mem.endsWith(u8, name, "-v1"))
        return b.fmt("{s}/staging/{s}/{s}.xml", .{ wl_protocol_dir, name[0 .. name.len - 3], name });
    return b.fmt("{s}/staging/{s}/{s}.xml", .{ wl_protocol_dir, name, name });
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // version string: "0.1.0(<git hash>)" or "0.1.0(release)"
    const commit = capture(b, &.{ "git", "rev-parse", "--short", "HEAD" }) orelse "release";
    const version_define = b.fmt("\"acwm-{s}({s})\"", .{ version, commit });

    const wl_protocol_dir = capture(b, &.{ "pkg-config", "--variable=pkgdatadir", "wayland-protocols" }) orelse "";

    const io = b.graph.io;
    const root_dir = Io.Dir.cwd().openDir(io, ".", .{}) catch unreachable;

    const xwayland = b.option(bool, "xwayland", "Enable Xwayland support (auto)") orelse hasPkg(b, "xcb");
    const tray = b.option(bool, "tray", "Enable the SNI system tray / portal (libsystemd)") orelse hasPkg(b, "libsystemd");

    // Shared translate-c module ("cc"): Zig 0.17 removed @cImport, so the
    // config ports get C types (Config/ConfigVar, the `config` global) from
    // the translated headers instead.
    const c_header_files = b.addWriteFiles();
    const c_header = c_header_files.add("c_acwm_build.h", if (xwayland)
        "#define XWAYLAND 1\n#include \"c_acwm.h\"\n"
    else
        "#include \"c_acwm.h\"\n");
    const c_unit = b.addTranslateC(.{
        .root_source_file = c_header,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    c_unit.addIncludePath(b.path("."));
    c_unit.addIncludePath(b.path("include"));
    for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "libinput", "libcjson", "libdrm", "xcb", "xcb-icccm" })) |dir| {
        c_unit.addIncludePath(.{ .cwd_relative = dir });
    }
    const c_mod = c_unit.createModule();

    const server_protos = [_][]const u8{
        "xdg-shell",
        "pointer-constraints-unstable-v1",
        "xdg-output-unstable-v1",
        "cursor-shape-v1",
        "tablet-v2",
        "ext-image-copy-capture-v1",
        "ext-image-capture-source-v1",
        "ext-foreign-toplevel-list-v1",
        "ext-workspace-v1",
        "tearing-control-v1",
        "wlr-foreign-toplevel-management-unstable-v1",
        "wlr-layer-shell-unstable-v1",
        "wlr-output-power-management-unstable-v1",
    };

    var protos = Protos{
        .b = b,
        .gen_server = b.addWriteFiles(),
        .gen_client = b.addWriteFiles(),
        .server_headers = blk: {
            const m = b.allocator.create(std.StringHashMap(void)) catch unreachable;
            m.* = std.StringHashMap(void).init(b.allocator);
            break :blk m;
        },
        .client_headers = blk: {
            const m = b.allocator.create(std.StringHashMap(void)) catch unreachable;
            m.* = std.StringHashMap(void).init(b.allocator);
            break :blk m;
        },
    };
    c_unit.addIncludePath(protos.gen_server.getDirectory());

    // ------------------------------------------------------------------
    // acwm (the compositor)
    // ------------------------------------------------------------------
    const compositor = cExe(b, target, optimize, "acwm");
    compositor.root_module.addIncludePath(b.path("."));
    compositor.root_module.addIncludePath(b.path("include"));
    compositor.root_module.addCMacro("VERSION", version_define);
    compositor.root_module.addCMacro("SYSCONFDIR", "\"/etc\"");
    if (xwayland) compositor.root_module.addCMacro("XWAYLAND", "1");
    if (tray) compositor.root_module.addCMacro("HAVE_TRAY", "1");

    var src_files: std.ArrayList([]const u8) = .empty;
    {
        // same trick as the meson build: shell out to find(1) so new files
        // under src/ are picked up without editing this file
        const find_out = capture(b, &.{ "find", "src", "-name", "*.c" }) orelse "";
        var it = std.mem.tokenizeAny(u8, find_out, "\n");
        while (it.next()) |p| {
            if (p.len == 0)
                continue;
            // Phase 4 strangler boundary: src/config/value_parse.c is
            // replaced by its Zig twin (src/config/value_parse.zig), which
            // is attached as an object below. Same for
            // src/config/variable_expand.c.
            if (std.mem.eql(u8, p, "src/config/value_parse.c"))
                continue;
            if (std.mem.eql(u8, p, "src/config/variable_expand.c"))
                continue;
            if (std.mem.eql(u8, p, "src/config/error_store.c"))
                continue;
            if (std.mem.eql(u8, p, "src/config/conflict_check.c"))
                continue;
            if (std.mem.eql(u8, p, "src/config/error_nag.c"))
                continue;
            if (std.mem.eql(u8, p, "src/config/binding_parse.c"))
                continue;
            if (std.mem.eql(u8, p, "src/config/load.c"))
                continue;
            if (std.mem.eql(u8, p, "src/config/cleanup.c"))
                continue;
            if (std.mem.eql(u8, p, "src/config/reapply.c"))
                continue;
            if (std.mem.eql(u8, p, "src/config/watcher.c"))
                continue;
            src_files.append(b.allocator, dupe(b, p)) catch {};
        }
    }
    compositor.root_module.addCSourceFiles(.{ .root = b.path("."), .files = src_files.items, .flags = cflags(b, &.{ "-DACWM_ZIG_BAR_OPTION", "-DACWM_ZIG_SESSION_OPTION", "-DACWM_ZIG_LAYOUT_OPTION", "-DACWM_ZIG_INPUT_OPTION", "-DACWM_ZIG_VISUALS_OPTION", "-DACWM_ZIG_DEVICE_OPTION", "-DACWM_ZIG_ANIMATION_OPTION", "-DACWM_ZIG_SCROLLER_OPTION", "-DACWM_ZIG_MISC_OPTION", "-DACWM_ZIG_JUMLABEL_OPTION", "-DACWM_ZIG_GAPS_OPTION", "-DACWM_ZIG_ARRAY_OPTION", "-DACWM_ZIG_MONITOR_RULE", "-DACWM_ZIG_RULES_OPTION", "-DACWM_ZIG_WINDOW_RULE", "-DACWM_ZIG_DEVICE_RULE", "-DACWM_ZIG_DIRECTIVES_OPTION", "-DACWM_ZIG_BIND_OPTION", "-DACWM_ZIG_OPTION_DEFAULTS", "-DACWM_ZIG_IPC_BUILDERS", "-DACWM_ZIG_IPC_WATCH", "-DACWM_ZIG_IPC_SERVER", "-DACWM_ZIG_LAYOUT_VERTICAL", "-DACWM_ZIG_LAYOUT_DWINDLE", "-DACWM_ZIG_LAYOUT_HORIZONTAL", "-DACWM_ZIG_LAYOUT_SCROLL", "-DACWM_ZIG_ARRANGE_HUB", "-DACWM_ZIG_ARRANGE_RESIZE", "-DACWM_ZIG_TOML_PARSE", "-DACWM_ZIG_TEXT_NODE", "-DACWM_ZIG_BIND_TAGVIEW", "-DACWM_ZIG_BIND_FOCUS", "-DACWM_ZIG_BIND_LAYOUT", "-DACWM_ZIG_BIND_MOVE", "-DACWM_ZIG_BIND_VIEW", "-DACWM_ZIG_BIND_TAIL", "-DACWM_ZIG_BIND_OVERVIEW", "-DACWM_ZIG_UTIL", "-DACWM_ZIG_SCENE_NODE", "-DACWM_ZIG_DIM_NODE", "-DACWM_ZIG_ANIMATION_COMMON", "-DACWM_ZIG_ANIMATION_TAG", "-DACWM_ZIG_TAB", "-DACWM_ZIG_IDLE", "-DACWM_ZIG_MISC", "-DACWM_ZIG_ANIMATION_LAYER", "-DACWM_ZIG_LAYER", "-DACWM_ZIG_MONITOR_QUERY", "-DACWM_ZIG_MONITOR_OUTPUT", "-DACWM_ZIG_MONITOR_LIFECYCLE", "-DACWM_ZIG_MONITOR_OPS", "-DACWM_ZIG_MONITOR_NEW", "-DACWM_ZIG_CLIENT_BASIC", "-DACWM_ZIG_CLIENT_STATE", "-DACWM_ZIG_CLIENT_LOOKUP", "-DACWM_ZIG_CLIENT_RULES", "-DACWM_ZIG_CLIENT_INIT", "-DACWM_ZIG_CLIENT_LIFECYCLE", "-DACWM_ZIG_CLIENT_VIEW", "-DACWM_ZIG_CLIENT_TRANSITION" }) });

    // Zig twin of value_parse.c: exports the same C symbols, so the rest of
    // the C tree calls it unchanged.
    const vp_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/value_parse.zig"),
    });
    const vp_obj = b.addObject(.{ .name = "acwm-value-parse", .root_module = vp_mod });
    compositor.root_module.addObject(vp_obj);

    // Zig twin of variable_expand.c: reads/writes the C `config` global via
    // the translated headers ("cc").
    const ve_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/variable_expand.zig"),
    });
    ve_mod.addImport("cc", c_mod);
    const ve_obj = b.addObject(.{ .name = "acwm-variable-expand", .root_module = ve_mod });
    compositor.root_module.addObject(ve_obj);

    // Zig twin of the bar option group (option_defs.c slice 1): parse_option
    // calls it first under ACWM_ZIG_BAR_OPTION. parse_color/
    // convert_hex_to_rgba stay extern — they resolve to the value-parse
    // object in this link (importing that module here would duplicate its
    // exported symbols across objects).
    const ob_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/option_bar.zig"),
    });
    ob_mod.addImport("cc", c_mod);
    const ob_obj = b.addObject(.{ .name = "acwm-option-bar", .root_module = ob_mod });
    compositor.root_module.addObject(ob_obj);

    // Zig twin of error_store.c: the config-error log mirror (XDG runtime
    // dir, O_NOFOLLOW, 0600/0700 hardening). Pure libc + cc types.
    const es_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/error_store.zig"),
    });
    es_mod.addImport("cc", c_mod);
    const es_obj = b.addObject(.{ .name = "acwm-error-store", .root_module = es_mod });
    compositor.root_module.addObject(es_obj);

    // Zig twin of conflict_check.c: keybind/mousebind/axisbind/switchbind/
    // gesturebind conflict detection (pure logic; callbacks stay C ABI for
    // qsort and the generic checker).
    const cc_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/conflict_check.zig"),
    });
    cc_mod.addImport("cc", c_mod);
    const cc_obj = b.addObject(.{ .name = "acwm-conflict-check", .root_module = cc_mod });
    compositor.root_module.addObject(cc_obj);

    // Zig twin of the idle + session/general option group (option_defs.c
    // slice 2): parse_option calls it after the bar applier.
    const os_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/option_session.zig"),
    });
    os_mod.addImport("cc", c_mod);
    const os_obj = b.addObject(.{ .name = "acwm-option-session", .root_module = os_mod });
    compositor.root_module.addObject(os_obj);

    // Zig twin of the layout option group (option_defs.c slice 3).
    const ol_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/option_layout.zig"),
    });
    ol_mod.addImport("cc", c_mod);
    const ol_obj = b.addObject(.{ .name = "acwm-option-layout", .root_module = ol_mod });
    compositor.root_module.addObject(ol_obj);

    // Zig twin of the input/cursor/drag option group (option_defs.c slice 4).
    const oi_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/option_input.zig"),
    });
    oi_mod.addImport("cc", c_mod);
    const oi_obj = b.addObject(.{ .name = "acwm-option-input", .root_module = oi_mod });
    compositor.root_module.addObject(oi_obj);

    // Zig twin of the visuals option group (option_defs.c slice 5).
    const ov_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/option_visuals.zig"),
    });
    ov_mod.addImport("cc", c_mod);
    const ov_obj = b.addObject(.{ .name = "acwm-option-visuals", .root_module = ov_mod });
    compositor.root_module.addObject(ov_obj);

    // Zig twin of the device option group (option_defs.c slice 6).
    const od_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/option_device.zig"),
    });
    od_mod.addImport("cc", c_mod);
    const od_obj = b.addObject(.{ .name = "acwm-option-device", .root_module = od_mod });
    compositor.root_module.addObject(od_obj);

    // Zig twin of the animation option group (option_defs.c slice 7).
    const oa_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/option_animation.zig"),
    });
    oa_mod.addImport("cc", c_mod);
    const oa_obj = b.addObject(.{ .name = "acwm-option-animation", .root_module = oa_mod });
    compositor.root_module.addObject(oa_obj);

    // Zig twin of the scroller/focus option group (option_defs.c slice 8).
    const osc_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/option_scroller.zig"),
    });
    osc_mod.addImport("cc", c_mod);
    const osc_obj = b.addObject(.{ .name = "acwm-option-scroller", .root_module = osc_mod });
    compositor.root_module.addObject(osc_obj);

    // Zig twin of the early misc option group (option_defs.c slice 9).
    const om_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/option_misc.zig"),
    });
    om_mod.addImport("cc", c_mod);
    const om_obj = b.addObject(.{ .name = "acwm-option-misc", .root_module = om_mod });
    compositor.root_module.addObject(om_obj);

    // Zig twin of the jump-label decoration group (option_defs.c slice 10).
    const oj_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/option_jumplabel.zig"),
    });
    oj_mod.addImport("cc", c_mod);
    const oj_obj = b.addObject(.{ .name = "acwm-option-jumplabel", .root_module = oj_mod });
    compositor.root_module.addObject(oj_obj);

    // Zig twin of the gaps/scratchpad group (option_defs.c slice 11).
    const og_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/option_gaps.zig"),
    });
    og_mod.addImport("cc", c_mod);
    const og_obj = b.addObject(.{ .name = "acwm-option-gaps", .root_module = og_mod });
    compositor.root_module.addObject(og_obj);

    // Zig twin of the comma-list option parsers (option_defs.c slice 12):
    // scroller_proportion_preset + circle_layout, with the C memory
    // management and strtok/sscanf semantics preserved.
    const oarr_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/option_array.zig"),
    });
    oarr_mod.addImport("cc", c_mod);
    const oarr_obj = b.addObject(.{ .name = "acwm-option-array", .root_module = oarr_mod });
    compositor.root_module.addObject(oarr_obj);

    // Zig twin of the monitor_rule branch (option_defs.c slice 13).
    const omr_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/option_monitor_rule.zig"),
    });
    omr_mod.addImport("cc", c_mod);
    const omr_obj = b.addObject(.{ .name = "acwm-monitor-rule", .root_module = omr_mod });
    compositor.root_module.addObject(omr_obj);

    // Zig twin of the tag_rule/layer_rule branches (option_defs.c slice 14).
    const oru_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/option_rules.zig"),
    });
    oru_mod.addImport("cc", c_mod);
    const oru_obj = b.addObject(.{ .name = "acwm-rules", .root_module = oru_mod });
    compositor.root_module.addObject(oru_obj);

    // Zig twin of the window_rule/window_rule_once branch (slice 15).
    const owr_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/option_window_rule.zig"),
    });
    owr_mod.addImport("cc", c_mod);
    const owr_obj = b.addObject(.{ .name = "acwm-window-rule", .root_module = owr_mod });
    compositor.root_module.addObject(owr_obj);

    // Zig twin of the device_rule branch (option_defs.c slice 16).
    const odr_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/option_device_rule.zig"),
    });
    odr_mod.addImport("cc", c_mod);
    const odr_obj = b.addObject(.{ .name = "acwm-device-rule", .root_module = odr_mod });
    compositor.root_module.addObject(odr_obj);

    // Zig twin of the option_defs.c defaults/clamps tail (slice 19):
    // set_value_default/override_config/update_global_var/
    // apply_option_expanded. The C twins are #ifndef-guarded, so the meson
    // build keeps them and this build uses the Zig versions.
    const odf_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/option_defaults.zig"),
    });
    odf_mod.addImport("cc", c_mod);
    const odf_obj = b.addObject(.{ .name = "acwm-option-defaults", .root_module = odf_mod });
    compositor.root_module.addObject(odf_obj);

    // Zig twin of error_nag.c (slice 20): the config-error nag launcher
    // (wl_client + acwm-nag spawn with edit command).
    const en_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/error_nag.zig"),
    });
    en_mod.addImport("cc", c_mod);
    const en_obj = b.addObject(.{ .name = "acwm-error-nag", .root_module = en_mod });
    compositor.root_module.addObject(en_obj);

    // Zig twin of binding_parse.c (slice 21): keymap lifecycle, modifier/key/
    // button parsing and the 93-entry parse_func_name dispatch table.
    const bp_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/binding_parse.zig"),
    });
    bp_mod.addImport("cc", c_mod);
    const bp_obj = b.addObject(.{ .name = "acwm-binding-parse", .root_module = bp_mod });
    compositor.root_module.addObject(bp_obj);

    // Zig twin of load.c (slice 22): config file loading pipeline, path
    // resolution, keymap resolution and the CHVT default bindings.
    const ld_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/load.zig"),
    });
    ld_mod.addImport("cc", c_mod);
    const ld_obj = b.addObject(.{ .name = "acwm-load", .root_module = ld_mod });
    compositor.root_module.addObject(ld_obj);

    // Zig twin of cleanup.c (slice 23): config teardown.
    const cl_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/cleanup.zig"),
    });
    cl_mod.addImport("cc", c_mod);
    const cl_obj = b.addObject(.{ .name = "acwm-cleanup", .root_module = cl_mod });
    compositor.root_module.addObject(cl_obj);

    // Zig twin of reapply.c (slice 24): hot-reload reapply layer.
    const ra_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/reapply.zig"),
    });
    ra_mod.addImport("cc", c_mod);
    const ra_obj = b.addObject(.{ .name = "acwm-reapply", .root_module = ra_mod });
    compositor.root_module.addObject(ra_obj);

    // Zig twin of watcher.c (slice 25): inotify config auto-reload.
    const wt_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/watcher.zig"),
    });
    wt_mod.addImport("cc", c_mod);
    const wt_obj = b.addObject(.{ .name = "acwm-watcher", .root_module = wt_mod });
    compositor.root_module.addObject(wt_obj);

    // Zig twin of the IPC JSON builders (slice 26). ipc.c keeps everything
    // else; its builder twins are #ifndef ACWM_ZIG_IPC_BUILDERS guarded.
    const ib_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/ipc/ipc_builders.zig"),
    });
    ib_mod.addImport("cc", c_mod);
    const ib_obj = b.addObject(.{ .name = "acwm-ipc-builders", .root_module = ib_mod });
    compositor.root_module.addObject(ib_obj);

    // Zig twin of the IPC watch/notification layer (slice 27).
    const iw_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/ipc/ipc_watch.zig"),
    });
    iw_mod.addImport("cc", c_mod);
    const iw_obj = b.addObject(.{ .name = "acwm-ipc-watch", .root_module = iw_mod });
    compositor.root_module.addObject(iw_obj);

    // Zig twin of the IPC server side (slice 28): command dispatcher,
    // watch registration, connection handling, socket init/cleanup.
    const ipc_ver = b.addOptions();
    ipc_ver.addOption([]const u8, "version", b.fmt("acwm-{s}({s})", .{ version, commit }));
    const is_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/ipc/ipc_server.zig"),
    });
    is_mod.addImport("cc", c_mod);
    is_mod.addImport("build_options", ipc_ver.createModule());
    const is_obj = b.addObject(.{ .name = "acwm-ipc-server", .root_module = is_mod });
    compositor.root_module.addObject(is_obj);

    // Zig twin of the vertical layout family (slice 29).
    const lv_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/layout/vertical.zig"),
    });
    lv_mod.addImport("cc", c_mod);
    const lv_obj = b.addObject(.{ .name = "acwm-layout-vertical", .root_module = lv_mod });
    compositor.root_module.addObject(lv_obj);

    // Zig twin of the dwindle layout tree (slice 30).
    const dw_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/layout/dwindle.zig"),
    });
    dw_mod.addImport("cc", c_mod);
    const dw_obj = b.addObject(.{ .name = "acwm-layout-dwindle", .root_module = dw_mod });
    compositor.root_module.addObject(dw_obj);

    // Zig twin of the horizontal layout family (slice 31).
    const lh_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/layout/horizontal.zig"),
    });
    lh_mod.addImport("cc", c_mod);
    const lh_obj = b.addObject(.{ .name = "acwm-layout-horizontal", .root_module = lh_mod });
    compositor.root_module.addObject(lh_obj);

    // Zig twin of the scroller layout family (slice 32).
    const ls_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/layout/scroll.zig"),
    });
    ls_mod.addImport("cc", c_mod);
    const ls_obj = b.addObject(.{ .name = "acwm-layout-scroll", .root_module = ls_mod });
    compositor.root_module.addObject(ls_obj);

    // Zig twin of the arrange hub: layouts table, pre-arrange pass, tag
    // gathering and arrange() itself (slice 33).
    const ah_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/layout/arrange.zig"),
    });
    ah_mod.addImport("cc", c_mod);
    const ah_obj = b.addObject(.{ .name = "acwm-arrange-hub", .root_module = ah_mod });
    compositor.root_module.addObject(ah_obj);

    // Zig twin of the arrange resize/drag family (slice 34).
    const ar_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/layout/arrange_resize.zig"),
    });
    ar_mod.addImport("cc", c_mod);
    const ar_obj = b.addObject(.{ .name = "acwm-arrange-resize", .root_module = ar_mod });
    compositor.root_module.addObject(ar_obj);

    // Zig twin of the TOML subset parser (slice 35). Decision: hand-port,
    // no external TOML dependency.
    const tp_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/toml_parse.zig"),
    });
    tp_mod.addImport("cc", c_mod);
    const tp_obj = b.addObject(.{ .name = "acwm-toml-parse", .root_module = tp_mod });
    compositor.root_module.addObject(tp_obj);

    // Zig twin of the cairo/pango text nodes (slice 36).
    const tn_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/draw/text-node.zig"),
    });
    tn_mod.addImport("cc", c_mod);
    const tn_obj = b.addObject(.{ .name = "acwm-text-node", .root_module = tn_mod });
    compositor.root_module.addObject(tn_obj);

    // Zig twin of the bind tag/view/action cluster (slice 37).
    const bt_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/dispatch/bind_tagview.zig"),
    });
    bt_mod.addImport("cc", c_mod);
    const bt_obj = b.addObject(.{ .name = "acwm-bind-tagview", .root_module = bt_mod });
    compositor.root_module.addObject(bt_obj);

    // Zig twin of the bind focus/group cluster (slice 38).
    const bf_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/dispatch/bind_focus.zig"),
    });
    bf_mod.addImport("cc", c_mod);
    const bf_obj = b.addObject(.{ .name = "acwm-bind-focus", .root_module = bf_mod });
    compositor.root_module.addObject(bf_obj);

    // Zig twin of the bind layout/gap/proportion cluster (slice 39).
    const bl_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/dispatch/bind_layout.zig"),
    });
    bl_mod.addImport("cc", c_mod);
    const bl_obj = b.addObject(.{ .name = "acwm-bind-layout", .root_module = bl_mod });
    compositor.root_module.addObject(bl_obj);

    // Zig twin of the bind smart-move/spawn/layout-cycle cluster (slice 40).
    const bm_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/dispatch/bind_move.zig"),
    });
    bm_mod.addImport("cc", c_mod);
    const bm_obj = b.addObject(.{ .name = "acwm-bind-move", .root_module = bm_mod });
    compositor.root_module.addObject(bm_obj);

    // Zig twin of the bind view-shift/zoom/option cluster (slice 41).
    const bv_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/dispatch/bind_view.zig"),
    });
    bv_mod.addImport("cc", c_mod);
    const bv_obj = b.addObject(.{ .name = "acwm-bind-view", .root_module = bv_mod });
    compositor.root_module.addObject(bv_obj);

    // Zig twin of the bind tail cluster: monitors/scroller/dwindle/reload
    // (slice 42).
    const bt2_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/dispatch/bind_tail.zig"),
    });
    bt2_mod.addImport("cc", c_mod);
    const bt2_obj = b.addObject(.{ .name = "acwm-bind-tail", .root_module = bt2_mod });
    compositor.root_module.addObject(bt2_obj);

    // Zig twin of the bind overview/keyboard-layout cluster (slice 43,
    // completes bind.c).
    const bo_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/dispatch/bind_overview.zig"),
    });
    bo_mod.addImport("cc", c_mod);
    const bo_obj = b.addObject(.{ .name = "acwm-bind-overview", .root_module = bo_mod });
    compositor.root_module.addObject(bo_obj);

    // Zig twin of the common utility helpers (Phase 5, slice 44).
    const cu_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/common/util.zig"),
    });
    cu_mod.addImport("cc", c_mod);
    const cu_obj = b.addObject(.{ .name = "acwm-common-util", .root_module = cu_mod });
    compositor.root_module.addObject(cu_obj);

    // Zig twin of the scene-node payload/hit-test helpers (slice 45).
    const cs_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/common/scene_node.zig"),
    });
    cs_mod.addImport("cc", c_mod);
    const cs_obj = b.addObject(.{ .name = "acwm-scene-node", .root_module = cs_mod });
    compositor.root_module.addObject(cs_obj);

    // Zig twin of the dim node (slice 46).
    const dn_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/draw/dim-node.zig"),
    });
    dn_mod.addImport("cc", c_mod);
    const dn_obj = b.addObject(.{ .name = "acwm-dim-node", .root_module = dn_mod });
    compositor.root_module.addObject(dn_obj);

    // Zig twin of the animation curves (slice 47).
    const ac_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/animation/common.zig"),
    });
    ac_mod.addImport("cc", c_mod);
    const ac_obj = b.addObject(.{ .name = "acwm-animation-common", .root_module = ac_mod });
    compositor.root_module.addObject(ac_obj);

    // Zig twin of the tag animation state (slice 47).
    const at_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/animation/tag.zig"),
    });
    at_mod.addImport("cc", c_mod);
    const at_obj = b.addObject(.{ .name = "acwm-animation-tag", .root_module = at_mod });
    compositor.root_module.addObject(at_obj);

    // Zig twin of the tab chain/strip manager (slice 48).
    const tb_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/manage/tab.zig"),
    });
    tb_mod.addImport("cc", c_mod);
    const tb_obj = b.addObject(.{ .name = "acwm-manage-tab", .root_module = tb_mod });
    compositor.root_module.addObject(tb_obj);

    // Zig twin of the built-in idle handling (slice 49).
    const id_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/manage/idle.zig"),
    });
    id_mod.addImport("cc", c_mod);
    const id_obj = b.addObject(.{ .name = "acwm-manage-idle", .root_module = id_mod });
    compositor.root_module.addObject(id_obj);

    // Zig twin of the misc protocol/utility handlers (slice 50).
    const mi_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/manage/misc.zig"),
    });
    mi_mod.addImport("cc", c_mod);
    const mi_obj = b.addObject(.{ .name = "acwm-manage-misc", .root_module = mi_mod });
    compositor.root_module.addObject(mi_obj);

    // Zig twin of the layer animations (slice 51).
    const al_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/animation/layer.zig"),
    });
    al_mod.addImport("cc", c_mod);
    const al_obj = b.addObject(.{ .name = "acwm-animation-layer", .root_module = al_mod });
    compositor.root_module.addObject(al_obj);

    // Zig twin of layer-shell management (slice 52).
    const ly_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/manage/layer.zig"),
    });
    ly_mod.addImport("cc", c_mod);
    const ly_obj = b.addObject(.{ .name = "acwm-manage-layer", .root_module = ly_mod });
    compositor.root_module.addObject(ly_obj);

    // Zig twin of the monitor query/tag helpers (slice 53).
    const mq_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/manage/monitor_query.zig"),
    });
    mq_mod.addImport("cc", c_mod);
    const mq_obj = b.addObject(.{ .name = "acwm-monitor-query", .root_module = mq_mod });
    compositor.root_module.addObject(mq_obj);

    // Zig twin of output commit/ICC/rules (slice 54).
    const mo_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/manage/monitor_output.zig"),
    });
    mo_mod.addImport("cc", c_mod);
    const mo_obj = b.addObject(.{ .name = "acwm-monitor-output", .root_module = mo_mod });
    compositor.root_module.addObject(mo_obj);

    // Zig twin of the output lifecycle and renderer-loss handling (slice 55).
    const ml_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/manage/monitor_lifecycle.zig"),
    });
    ml_mod.addImport("cc", c_mod);
    const ml_obj = b.addObject(.{ .name = "acwm-monitor-lifecycle", .root_module = ml_mod });
    compositor.root_module.addObject(ml_obj);

    // Zig twin of the output layout/manager/frame handling (slice 56).
    const xw_opts = b.addOptions();
    xw_opts.addOption(bool, "xwayland", xwayland);
    const mops_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/manage/monitor_ops.zig"),
    });
    mops_mod.addImport("cc", c_mod);
    mops_mod.addImport("build_options", xw_opts.createModule());
    const mops_obj = b.addObject(.{ .name = "acwm-monitor-ops", .root_module = mops_mod });
    compositor.root_module.addObject(mops_obj);

    // Zig twin of output creation (slice 57).
    const mn_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/manage/monitor_new.zig"),
    });
    mn_mod.addImport("cc", c_mod);
    const mn_obj = b.addObject(.{ .name = "acwm-monitor-new", .root_module = mn_mod });
    compositor.root_module.addObject(mn_obj);

    // Zig twin of the basic client helpers (slice 58).
    const cb_opts = b.addOptions();
    cb_opts.addOption(bool, "xwayland", xwayland);
    const cb_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/manage/client_basic.zig"),
    });
    cb_mod.addImport("cc", c_mod);
    cb_mod.addImport("build_options", cb_opts.createModule());
    const cb_obj = b.addObject(.{ .name = "acwm-client-basic", .root_module = cb_mod });
    compositor.root_module.addObject(cb_obj);

    // Zig twin of client size/state and XWayland clipping (slice 59).
    const cst_opts = b.addOptions();
    cst_opts.addOption(bool, "xwayland", xwayland);
    const cst_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/manage/client_state.zig"),
    });
    cst_mod.addImport("cc", c_mod);
    cst_mod.addImport("build_options", cst_opts.createModule());
    const cst_obj = b.addObject(.{ .name = "acwm-client-state", .root_module = cst_mod });
    compositor.root_module.addObject(cst_obj);

    // Zig twin of client lookup/direction/stack helpers (slice 60).
    const clk_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/manage/client_lookup.zig"),
    });
    clk_mod.addImport("cc", c_mod);
    const clk_obj = b.addObject(.{ .name = "acwm-client-lookup", .root_module = clk_mod });
    compositor.root_module.addObject(clk_obj);

    // Zig twin of client rules and snapping (slice 61).
    const cru_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/manage/client_rules.zig"),
    });
    cru_mod.addImport("cc", c_mod);
    const cru_obj = b.addObject(.{ .name = "acwm-client-rules", .root_module = cru_mod });
    compositor.root_module.addObject(cru_obj);

    // Zig twin of client geometry/init (slice 62).
    const cin_opts = b.addOptions();
    cin_opts.addOption(bool, "xwayland", xwayland);
    const cin_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/manage/client_init.zig"),
    });
    cin_mod.addImport("cc", c_mod);
    cin_mod.addImport("build_options", cin_opts.createModule());
    const cin_obj = b.addObject(.{ .name = "acwm-client-init", .root_module = cin_mod });
    compositor.root_module.addObject(cin_obj);

    // Zig twin of client lifecycle/request handlers (slice 63).
    const cli_opts = b.addOptions();
    cli_opts.addOption(bool, "xwayland", xwayland);
    const cli_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/manage/client_lifecycle.zig"),
    });
    cli_mod.addImport("cc", c_mod);
    cli_mod.addImport("build_options", cli_opts.createModule());
    const cli_obj = b.addObject(.{ .name = "acwm-client-lifecycle", .root_module = cli_mod });
    compositor.root_module.addObject(cli_obj);

    // Zig twin of client focus/view/tag transitions (slice 64).
    const cvw_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/manage/client_view.zig"),
    });
    cvw_mod.addImport("cc", c_mod);
    const cvw_obj = b.addObject(.{ .name = "acwm-client-view", .root_module = cvw_mod });
    compositor.root_module.addObject(cvw_obj);

    // Zig twin of floating/fullscreen/scratchpad transitions (slice 65).
    const ctr_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/manage/client_transition.zig"),
    });
    ctr_mod.addImport("cc", c_mod);
    const ctr_obj = b.addObject(.{ .name = "acwm-client-transition", .root_module = ctr_mod });
    compositor.root_module.addObject(ctr_obj);

    // Zig twin of the env/var/exec/exec_once/source directives (slice 17).
    const odi_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/option_directives.zig"),
    });
    odi_mod.addImport("cc", c_mod);
    const odi_obj = b.addObject(.{ .name = "acwm-option-directives", .root_module = odi_mod });
    compositor.root_module.addObject(odi_obj);

    // Zig twin of key_mode + the bind branches (option_defs.c slice 18).
    const obi_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/config/option_bind.zig"),
    });
    obi_mod.addImport("cc", c_mod);
    const obi_obj = b.addObject(.{ .name = "acwm-option-bind", .root_module = obi_mod });
    compositor.root_module.addObject(obi_obj);

    for (server_protos) |name| {
        const xml = serverProtoXml(b, wl_protocol_dir, name);
        const c_file = protos.gen(xml, name, true, false, "");
        compositor.root_module.addCSourceFile(.{ .file = c_file, .flags = &.{} });
    }
    compositor.root_module.addIncludePath(protos.gen_server.getDirectory());

    applyPkgConfig(b, compositor, &.{ "wlroots-0.20", "scenefx-0.5", "wayland-server", "libinput", "xkbcommon", "wayland-client", "libpcre2-8", "pixman-1", "libcjson", "pangocairo", "libdrm" });
    compositor.root_module.linkSystemLibrary("m", .{});
    if (xwayland) applyPkgConfig(b, compositor, &.{ "xcb", "xcb-icccm", "xcb-randr" });
    if (tray) applyPkgConfig(b, compositor, &.{"libsystemd"});
    b.installArtifact(compositor);

    // ------------------------------------------------------------------
    // companions
    // ------------------------------------------------------------------
    const layer_xml = "protocols/wlr-layer-shell-unstable-v1.xml";
    const xdg_xml = b.fmt("{s}/stable/xdg-shell/xdg-shell.xml", .{wl_protocol_dir});
    const ftl_xml = "protocols/wlr-foreign-toplevel-management-unstable-v1.xml";
    const screencopy_xml = "protocols/wlr-screencopy-unstable-v1.xml";

    // acwm-msg — pure unix-socket client (links log/util for the shared code)
    const msg = cExe(b, target, optimize, "acwm-msg");
    msg.root_module.addIncludePath(b.path("."));
    msg.root_module.addIncludePath(b.path("include"));
    msg.root_module.addCMacro("VERSION", version_define);
    msg.root_module.addCSourceFiles(.{
        .root = b.path("."),
        .files = &.{ "acwm-msg/acwm-msg.c", "src/config/error_store.c", "src/common/log.c", "src/common/util.c" },
        .flags = cflags(b, &.{}),
    });
    applyPkgConfig(b, msg, &.{ "wlroots-0.20", "libpcre2-8", "wayland-client" });
    b.installArtifact(msg);

    // acwm-nag — layer-shell notification client
    const nag = cExe(b, target, optimize, "acwm-nag");
    nag.root_module.addIncludePath(b.path("."));
    nag.root_module.addIncludePath(b.path("include"));
    nag.root_module.addCSourceFiles(.{
        .root = b.path("."),
        .files = &.{"acwm-nag/acwm-nag.c"},
        .flags = cflags(b, &.{}),
    });
    {
        const c1 = protos.gen(layer_xml, "wlr-layer-shell-unstable-v1", false, true, "wlr-layer-shell-unstable-v1-client-protocol.h");
        nag.root_module.addCSourceFile(.{ .file = c1, .flags = &.{} });
        const c2 = protos.gen(xdg_xml, "xdg-shell", false, true, "");
        nag.root_module.addCSourceFile(.{ .file = c2, .flags = &.{} });
    }
    nag.root_module.addIncludePath(protos.gen_client.getDirectory());
    applyPkgConfig(b, nag, &.{ "wayland-client", "pangocairo" });
    b.installArtifact(nag);

    // acwm-launch — app launcher client
    const launch = cExe(b, target, optimize, "acwm-launch");
    launch.root_module.addIncludePath(b.path("."));
    launch.root_module.addIncludePath(b.path("include"));
    launch.root_module.addCSourceFiles(.{
        .root = b.path("."),
        .files = &.{"acwm-launch/acwm-launch.c"},
        .flags = cflags(b, &.{}),
    });
    {
        const c1 = protos.gen(layer_xml, "wlr-layer-shell-unstable-v1", false, true, "acwm-launch-layer-shell-client-protocol.h");
        launch.root_module.addCSourceFile(.{ .file = c1, .flags = &.{} });
        const c2 = protos.gen(xdg_xml, "xdg-shell", false, true, "acwm-launch-xdg-shell-client-protocol.h");
        launch.root_module.addCSourceFile(.{ .file = c2, .flags = &.{} });
        const c3 = protos.gen(ftl_xml, "wlr-foreign-toplevel-management-unstable-v1", false, true, "acwm-launch-foreign-toplevel-client-protocol.h");
        launch.root_module.addCSourceFile(.{ .file = c3, .flags = &.{} });
    }
    launch.root_module.addIncludePath(protos.gen_client.getDirectory());
    applyPkgConfig(b, launch, &.{ "wayland-client", "pangocairo", "cairo", "xkbcommon", "gdk-pixbuf-2.0" });
    b.installArtifact(launch);

    // acwm-portal — screenshot portal backend (requires libsystemd)
    if (tray) {
        const portal = cExe(b, target, optimize, "acwm-portal");
        portal.root_module.addIncludePath(b.path("."));
        portal.root_module.addIncludePath(b.path("include"));
        portal.root_module.addCMacro("_GNU_SOURCE", "1");
        portal.root_module.addCSourceFiles(.{
            .root = b.path("."),
            .files = &.{"acwm-portal/acwm-portal.c"},
            .flags = cflags(b, &.{}),
        });
        {
            const c = protos.gen(screencopy_xml, "wlr-screencopy-unstable-v1", false, true, "");
            portal.root_module.addCSourceFile(.{ .file = c, .flags = &.{} });
        }
        portal.root_module.addIncludePath(protos.gen_client.getDirectory());
        applyPkgConfig(b, portal, &.{ "wayland-client", "libcjson", "cairo", "libsystemd" });
        b.installArtifact(portal);

        // command (PATH-resolved) so no install-prefix substitution is
        // needed at configure time.
        const unit_in = root_dir.readFileAlloc(io, "assets/acwm-portal.service.in", b.allocator, Io.Limit.limited(1 << 16)) catch "";
        const unit_out = std.mem.replaceOwned(u8, b.allocator, unit_in, "@bindir@/", "") catch "";
        const unit_gen = b.addWriteFiles().add("lib/systemd/user/acwm-portal.service", unit_out);
        b.getInstallStep().dependOn(&b.addInstallFile(unit_gen, "lib/systemd/user/acwm-portal.service").step);

        const alias_out = unit_out;
        const alias_gen = b.addWriteFiles().add("lib/systemd/user/dbus-org.freedesktop.impl.portal.desktop.acwm.service", alias_out);
        b.getInstallStep().dependOn(&b.addInstallFile(alias_gen, "lib/systemd/user/dbus-org.freedesktop.impl.portal.desktop.acwm.service").step);

        b.installFile("assets/org.freedesktop.impl.portal.desktop.acwm.service", "share/dbus-1/services/org.freedesktop.impl.portal.desktop.acwm.service");
        b.installFile("assets/acwm.portal", "share/xdg-desktop-portal/portals/acwm.portal");
    }

    // acwm-greeter — greetd client
    const greeter = cExe(b, target, optimize, "acwm-greeter");
    greeter.root_module.addIncludePath(b.path("."));
    greeter.root_module.addIncludePath(b.path("include"));
    greeter.root_module.addCMacro("_GNU_SOURCE", "1");
    greeter.root_module.addCSourceFiles(.{
        .root = b.path("."),
        .files = &.{"acwm-greeter/acwm-greeter.c"},
        .flags = cflags(b, &.{}),
    });
    {
        const c1 = protos.gen(layer_xml, "wlr-layer-shell-unstable-v1", false, true, "wlr-layer-shell-unstable-v1-client-protocol.h");
        greeter.root_module.addCSourceFile(.{ .file = c1, .flags = &.{} });
        const c2 = protos.gen(xdg_xml, "xdg-shell", false, true, "");
        greeter.root_module.addCSourceFile(.{ .file = c2, .flags = &.{} });
    }
    greeter.root_module.addIncludePath(protos.gen_client.getDirectory());
    applyPkgConfig(b, greeter, &.{ "wayland-client", "libcjson", "cairo", "pangocairo", "xkbcommon" });
    b.installArtifact(greeter);

    // ------------------------------------------------------------------
    // man pages + data files
    // ------------------------------------------------------------------
    const wf_misc = b.addWriteFiles();
    const mans = [_][]const u8{ "acwm-portal", "acwm-msg", "acwm-nag", "acwm-launch", "acwm-greeter" };
    for (mans) |man| {
        const template = root_dir.readFileAlloc(
            io,
            b.fmt("{s}/{s}.1.in", .{ man, man }),
            b.allocator,
            Io.Limit.limited(1 << 16),
        ) catch continue;
        const out = std.mem.replaceOwned(u8, b.allocator, template, "@VERSION@", version) catch continue;
        const gen = wf_misc.add(b.fmt("share/man/man1/{s}.1", .{man}), out);
        b.getInstallStep().dependOn(&b.addInstallFile(gen, b.fmt("share/man/man1/{s}.1", .{man})).step);
    }

    b.installFile("assets/acwm.desktop", "share/wayland-sessions/acwm.desktop");
    b.installFile("assets/acwm-portals.conf", "share/xdg-desktop-portal/acwm-portals.conf");
    b.installFile("assets/config.conf", "etc/acwm/config.conf");
    b.installFile("assets/config.toml", "etc/acwm/config.toml");
    b.installFile("assets/acwm-session.target", "lib/systemd/user/acwm-session.target");

    // ------------------------------------------------------------------
    // test step — runs the Zig unit tests (stub-backed)
    // ------------------------------------------------------------------
    const test_step = b.step("test", "run zig tests");
    {
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/value_parse.zig"),
        });
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/value_parse_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/variable_expand.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/variable_expand_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/option_bar.zig"),
        });
        test_mod.addImport("cc", c_mod);
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/option_bar_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // option_bind: binding_parse.c helpers stubbed with real headers.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/option_bind.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/option_bind_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // client transitions: mode/scratchpad/replace stubs.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/manage/client_transition.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson", "xcb", "xcb-icccm" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/client_transition_stub.c"),
            .flags = if (xwayland) &.{ "-DXWAYLAND", "-I." } else &.{"-I."},
        });
        applyPkgConfig(b, unit_tests, &.{ "wayland-server", "xcb" });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // client focus/view: pointer/scene/tag stubs.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/manage/client_view.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson", "xcb", "xcb-icccm" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/client_view_stub.c"),
            .flags = if (xwayland) &.{ "-DXWAYLAND", "-I." } else &.{"-I."},
        });
        applyPkgConfig(b, unit_tests, &.{ "wayland-server", "xcb" });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // client lifecycle: scene/request side-effect stubs.
        const cli_test_opts = b.addOptions();
        cli_test_opts.addOption(bool, "xwayland", xwayland);
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/manage/client_lifecycle.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addImport("build_options", cli_test_opts.createModule());
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson", "xcb", "xcb-icccm" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/client_lifecycle_stub.c"),
            .flags = if (xwayland) &.{ "-DXWAYLAND", "-I." } else &.{"-I."},
        });
        applyPkgConfig(b, unit_tests, &.{ "wayland-server", "xcb" });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // client geometry/init: surface/scene/rule stubs.
        const cin_test_opts = b.addOptions();
        cin_test_opts.addOption(bool, "xwayland", xwayland);
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/manage/client_init.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addImport("build_options", cin_test_opts.createModule());
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson", "xcb", "xcb-icccm" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/client_init_stub.c"),
            .flags = if (xwayland) &.{ "-DXWAYLAND", "-I." } else &.{"-I."},
        });
        applyPkgConfig(b, unit_tests, &.{ "wayland-server", "xcb" });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // client rules/snap: rule/placement side-effect stubs.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/manage/client_rules.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson", "xcb", "xcb-icccm" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/client_rules_stub.c"),
            .flags = if (xwayland) &.{ "-DXWAYLAND", "-I." } else &.{"-I."},
        });
        applyPkgConfig(b, unit_tests, &.{ "wayland-server", "xcb" });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // client lookup/direction/stack: query/role stubs.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/manage/client_lookup.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson", "xcb", "xcb-icccm" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/client_lookup_stub.c"),
            .flags = if (xwayland) &.{ "-DXWAYLAND", "-I." } else &.{"-I."},
        });
        applyPkgConfig(b, unit_tests, &.{ "wayland-server", "xcb" });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // client size/state: scene/xwayland/role stubs.
        const cst_test_opts = b.addOptions();
        cst_test_opts.addOption(bool, "xwayland", xwayland);
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/manage/client_state.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addImport("build_options", cst_test_opts.createModule());
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson", "xcb", "xcb-icccm" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/client_state_stub.c"),
            .flags = if (xwayland) &.{ "-DXWAYLAND", "-I." } else &.{"-I."},
        });
        applyPkgConfig(b, unit_tests, &.{ "wayland-server", "xcb" });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // client basic helpers: surface/role/state stubs.
        const cb_test_opts = b.addOptions();
        cb_test_opts.addOption(bool, "xwayland", xwayland);
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/manage/client_basic.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addImport("build_options", cb_test_opts.createModule());
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson", "xcb", "xcb-icccm" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/client_basic_stub.c"),
            .flags = if (xwayland) &.{ "-DXWAYLAND", "-I." } else &.{"-I."},
        });
        applyPkgConfig(b, unit_tests, &.{ "wayland-server", "xcb" });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // monitor creation: output state/scene/config stubs.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/manage/monitor_new.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/monitor_new_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        applyPkgConfig(b, unit_tests, &.{"wayland-server"});
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // monitor layout/manager/frame: layout+config+drawing stubs.
        const xw_test_opts = b.addOptions();
        xw_test_opts.addOption(bool, "xwayland", xwayland);
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/manage/monitor_ops.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addImport("build_options", xw_test_opts.createModule());
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/monitor_ops_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        applyPkgConfig(b, unit_tests, &.{"wayland-server"});
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // monitor output lifecycle: teardown/frame/renderer stubs.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/manage/monitor_lifecycle.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/monitor_lifecycle_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        applyPkgConfig(b, unit_tests, &.{"wayland-server"});
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // monitor output commit/ICC/rules: output state side-effect stubs.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/manage/monitor_output.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/monitor_output_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        applyPkgConfig(b, unit_tests, &.{"wayland-server"});
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // monitor query/tag helpers: layout/scene side-effect stubs.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/manage/monitor_query.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/monitor_query_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        applyPkgConfig(b, unit_tests, &.{"wayland-server"});
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // layer-shell management: scene/popup/bar side-effect stubs.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/manage/layer.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/manage_layer_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        applyPkgConfig(b, unit_tests, &.{"wayland-server"});
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // layer animations: scene/curve/time side-effect stubs.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/animation/layer.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/animation_layer_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        applyPkgConfig(b, unit_tests, &.{"wayland-server"});
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // misc protocol/utility handlers: wlroots/scene side-effect stubs.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/manage/misc.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/misc_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        applyPkgConfig(b, unit_tests, &.{"wayland-server"});
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // built-in idle: timer/notifier/spawn recorders.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/manage/idle.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/idle_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // tab chain/strip manager: scene/bar side-effect stubs.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/manage/tab.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/tab_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // animation curves: real libc, frame scheduling stubbed.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/animation/common.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/animation_common_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        applyPkgConfig(b, unit_tests, &.{"wayland-server"});
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // tag animation state: side-effect stubs.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/animation/tag.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/animation_tag_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // dim node: real cairo, fake scene graph.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/draw/dim-node.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/dim_node_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        applyPkgConfig(b, unit_tests, &.{ "cairo", "pangocairo" });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // scene-node payloads and hit testing: fake scene graph.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/common/scene_node.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/scene_node_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        applyPkgConfig(b, unit_tests, &.{"wayland-server"});
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // common utilities: real pcre2/wayland list, logging stubbed.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/common/util.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/util_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        applyPkgConfig(b, unit_tests, &.{ "libpcre2-8", "wayland-server" });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // bind overview/keyboard-layout cluster.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/dispatch/bind_overview.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/bind_overview_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // bind tail cluster: monitors/scroller/dwindle/reload.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/dispatch/bind_tail.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/bind_tail_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        applyPkgConfig(b, unit_tests, &.{"wayland-server"});
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // bind view-shift/zoom/option cluster.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/dispatch/bind_view.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/bind_view_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        applyPkgConfig(b, unit_tests, &.{"wayland-server"});
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // bind smart-move/spawn/layout-cycle cluster.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/dispatch/bind_move.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/bind_move_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // bind layout/gap/proportion cluster: recorded stubs + layouts table.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/dispatch/bind_layout.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/bind_layout_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // bind focus/group cluster: recorded side-effect stubs.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/dispatch/bind_focus.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/bind_focus_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        applyPkgConfig(b, unit_tests, &.{"wayland-server"});
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // bind tag/view cluster: recorded side-effect stubs.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/dispatch/bind_tagview.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/bind_tagview_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // text nodes: real cairo/pango/wlroots/scenefx scene graph.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/draw/text-node.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/text_node_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        applyPkgConfig(b, unit_tests, &.{ "cairo", "pangocairo" });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // TOML parser: callback recorder stubs.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/toml_parse.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/toml_parse_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // arrange resize/drag family: counters + scroller state stubs.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/layout/arrange_resize.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/layout_resize_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // arrange hub: layout table + tag/pre-arrange passes, hooks stubbed.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/layout/arrange.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/layout_arrange_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // scroller layout family: state machine + layout recorders.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/layout/scroll.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/layout_scroll_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // horizontal layout family: geometry + resize recorder.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/layout/horizontal.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/layout_vertical_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // dwindle tree: pure tree ops + resize/arrange recorders.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/layout/dwindle.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/layout_dwindle_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // vertical layout family: pure geometry + resize recorder.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/layout/vertical.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/layout_vertical_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // ipc_server: real sockets/cJSON, builder + watch objects, stubs.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/ipc/ipc_server.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addImport("build_options", ipc_ver.createModule());
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/ipc_watch_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/ipc_server_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        unit_tests.root_module.addObject(ib_obj);
        unit_tests.root_module.addObject(iw_obj);
        applyPkgConfig(b, unit_tests, &.{ "libcjson", "wlroots-0.20", "libinput", "wayland-server", "pixman-1" });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // ipc_watch: sockets + real libcjson, helper stubs.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/ipc/ipc_watch.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/ipc_watch_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        unit_tests.root_module.addObject(ib_obj); // builder implementations
        applyPkgConfig(b, unit_tests, &.{"libcjson"});
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // ipc_builders: real libcjson + helper stubs.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/ipc/ipc_builders.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/ipc_builders_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        applyPkgConfig(b, unit_tests, &.{"libcjson"});
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // watcher: config/reload/path stubs, real inotify.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/watcher.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/watcher_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // reapply: acwm + wlr stubs and data symbols.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/reapply.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput", "libcjson", "libudev" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/reapply_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // cleanup: server + keymap teardown stubs.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/cleanup.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/cleanup_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // load: xkb/parser/lifecycle/conflict/nag stubs.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/load.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/load_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // binding_parse: xkb + dispatch + value_parse stubs.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/binding_parse.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/binding_parse_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // error_nag: server global + wayland/string_printf/store stubs.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/error_nag.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/error_nag_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // option_defaults: config global + parse_option/expand stubbed.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/option_defaults.zig"),
        });
        test_mod.addImport("cc", c_mod);
        test_mod.addIncludePath(b.path("."));
        test_mod.addIncludePath(b.path("include"));
        for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo", "wayland-server", "pixman-1", "libinput" })) |dir| {
            test_mod.addIncludePath(.{ .cwd_relative = dir });
        }
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/option_defaults_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // option_directives: var/config-file hooks stubbed (HOME is real).
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/option_directives.zig"),
        });
        test_mod.addImport("cc", c_mod);
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/option_directives_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // option_device_rule: trim + error recorder (monitor-rule stub).
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/option_device_rule.zig"),
        });
        test_mod.addImport("cc", c_mod);
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/option_monitor_rule_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // option_window_rule: trim/anim/tags/mod/key stubbed.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/option_window_rule.zig"),
        });
        test_mod.addImport("cc", c_mod);
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/option_window_rule_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // option_rules (tag/layer): trim + animation_type stubbed.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/option_rules.zig"),
        });
        test_mod.addImport("cc", c_mod);
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/option_rules_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // option_monitor_rule: trim_whitespace stubbed; error recorder.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/option_monitor_rule.zig"),
        });
        test_mod.addImport("cc", c_mod);
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/option_monitor_rule_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // option_array: sanitize_string is stubbed; strtok/sscanf are real.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/option_array.zig"),
        });
        test_mod.addImport("cc", c_mod);
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/option_array_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // option_jumplabel: colors need the parse_color/convert stub.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/option_jumplabel.zig"),
        });
        test_mod.addImport("cc", c_mod);
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/option_bar_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // option_gaps: no C stub needed (libc + cc types only).
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/option_gaps.zig"),
        });
        test_mod.addImport("cc", c_mod);
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // option_misc: no C stub needed (libc + cc types only).
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/option_misc.zig"),
        });
        test_mod.addImport("cc", c_mod);
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // option_scroller: no C stub needed (libc + cc types only).
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/option_scroller.zig"),
        });
        test_mod.addImport("cc", c_mod);
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // option_animation: curve/type parsers come from value_parse; stub
        // them plus the error recorder.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/option_animation.zig"),
        });
        test_mod.addImport("cc", c_mod);
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/option_animation_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // option_device: no C stub needed (libc + cc types only).
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/option_device.zig"),
        });
        test_mod.addImport("cc", c_mod);
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // option_visuals: colors need the parse_color/convert stub.
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/option_visuals.zig"),
        });
        test_mod.addImport("cc", c_mod);
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/option_bar_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // option_input: no C stub needed (libc + cc types only).
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/option_input.zig"),
        });
        test_mod.addImport("cc", c_mod);
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // option_layout: no C stub needed (libc + cc types only).
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/option_layout.zig"),
        });
        test_mod.addImport("cc", c_mod);
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // option_session: no C stub needed (libc + cc types only).
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/option_session.zig"),
        });
        test_mod.addImport("cc", c_mod);
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/conflict_check.zig"),
        });
        test_mod.addImport("cc", c_mod);
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        unit_tests.root_module.addCSourceFile(.{
            .file = b.path("tests/conflict_check_stub.c"),
            .flags = if (xwayland) &.{"-DXWAYLAND"} else &.{},
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
    {
        // error_store does its own tmpdir/env manipulation; no C stub is
        // needed (pure libc + cc types).
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/config/error_store.zig"),
        });
        test_mod.addImport("cc", c_mod);
        const unit_tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
}
