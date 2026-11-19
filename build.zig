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
    const c_unit = b.addTranslateC(.{
        .root_source_file = b.path("include/c_acwm.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    c_unit.addIncludePath(b.path("."));
    c_unit.addIncludePath(b.path("include"));
    for (pkgIncludes(b, &.{ "wlroots-0.20", "scenefx-0.5", "xkbcommon", "pangocairo", "cairo" })) |dir| {
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
            src_files.append(b.allocator, dupe(b, p)) catch {};
        }
    }
    compositor.root_module.addCSourceFiles(.{ .root = b.path("."), .files = src_files.items, .flags = cflags(b, &.{ "-DACWM_ZIG_BAR_OPTION", "-DACWM_ZIG_SESSION_OPTION" }) });

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
            .flags = &.{},
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
            .flags = &.{},
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
            .flags = &.{},
        });
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
            .flags = &.{},
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
