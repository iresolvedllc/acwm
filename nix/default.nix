{
  lib,
  autoPatchelfHook,
  zig,
  libX11,
  libinput,
  libxcb,
  libdrm,
  libxkbcommon,
  gdk-pixbuf,
  pcre2,
  pango,
  cjson,
  pixman,
  pkg-config,
  stdenv,
  systemd,
  wayland,
  wayland-protocols,
  wayland-scanner,
  libxcb-wm,
  xwayland,
  scenefx,
  wlroots_0_20,
  libGL,
  enableXWayland ? true,
  debug ? false,
}:
stdenv.mkDerivation {
  pname = "acwm";
  version = "nightly";

  src = lib.cleanSourceWith {
    src = ../.;
    filter =
      path: type:
      let
        base = baseNameOf (toString path);
      in
      (lib.cleanSourceFilter path type) && base != "build" && base != "result"
      && base != "zig-out" && base != ".zig-cache";
    name = "source";
  };

  nativeBuildInputs = [
    zig
    pkg-config
    wayland-scanner
    autoPatchelfHook
  ];

  dontConfigure = true;
  dontInstall = true;

  buildPhase = ''
    runHook preBuild
    export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-global-cache
    export ZIG_LOCAL_CACHE_DIR=$TMPDIR/zig-local-cache
    zig build --prefix $out \
      -Doptimize=${if debug then "Debug" else "ReleaseFast"} \
      -Dxwayland=${if enableXWayland then "true" else "false"}
    runHook postBuild
  '';

  buildInputs = [
    libinput
    libxcb
    libxkbcommon
    pcre2
    pango
    cjson
    pixman
    wayland
    wayland-protocols
    wlroots_0_20
    scenefx
    libGL
    libdrm
    systemd # libsystemd → SNI tray for the built-in bar (HAVE_TRAY)
    gdk-pixbuf # acwm-launch client icon loading (.desktop Icon=)
  ]
  ++ lib.optionals enableXWayland [
    libX11
    libxcb-wm
    xwayland
  ];

  passthru = {
    providedSessions = [ "acwm" ];
  };

  meta = {
    mainProgram = "acwm";
    description = "Practical and Powerful wayland compositor (dwm but wayland)";
    homepage = "https://github.com/mangowm/acwm";
    license = lib.licenses.gpl3Plus;
    maintainers = [ ];
    platforms = lib.platforms.unix;
  };
}
