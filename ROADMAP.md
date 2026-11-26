# acwm Roadmap

acwm is being ported from C to Zig. This document is the detailed plan and
living todo list. Upstream (mangowc) is treated as **provenance, not a
dependency**: no upstream-sync work is scheduled — acwm evolves
independently, and [`UPSTREAM.md`](UPSTREAM.md) exists only to document
license lineage and the fork-point snapshot.

State legend: `[x]` done · `[~]` in progress · `[ ]` planned

## Phase 0 — Groundwork ✅

- [x] Restore GPL-3.0 LICENSE (the port is a derivative work)
- [x] Record upstream lineage in `UPSTREAM.md` (snapshot window pinned to
      upstream work landing on/after 2026-10-31)
- [x] Tag the pristine import (`mangowc-base`) and the post-rename C era
      (`pre-zig-port`)

## Phase 1 — Identity: mango* → acwm* ✅

- [x] Project/binaries: `acwm`, `acwm-msg`, `acwm-nag`, `acwm-launch`
- [x] `include/mango/` → `include/acwm/`; internal prefixes
      `mango_/MANGO_/Mango` → `acwm_/ACWM_/Acwm`
- [x] Env: `ACWM_INSTANCE_SIGNATURE`, `ACWM_LAUNCH_*`
- [x] Runtime identity: `XDG_CURRENT_DESKTOP=acwm`, IPC socket
      `acwm-<pid>.sock`, config dir `/etc/acwm` + `~/.config/acwm`
- [x] Session assets: `acwm.desktop`, `acwm-session.target`,
      `acwm-portals.conf`
- [x] Nix modules: `programs.acwm`, `nixosModules.acwm`, `hmModules.acwm`
- [x] Own version numbering (starts at 0.1.0; upstream lineage recorded in
      `UPSTREAM.md`)
- [x] README rewritten as acwm's own (upstream minimized to attribution)

## Phase 2 — Session features (C era) ✅

- [x] **Built-in idle handling** — `idle_after` / `idle_command` /
      `resume_command`; activity funnels through one helper; honors session
      lock and idle-inhibit; hot-reload safe
- [x] **`acwm-portal`** — native screenshot portal backend
      (`org.freedesktop.impl.portal.Screenshot` v2): zwlr_screencopy
      capture, pointer-tracked output selection, sync `file://` responses;
      ships unit + dbus activation + `acwm.portal`
- [x] **`acwm-greeter`** — greetd client (full auth flow incl. auth_message
      handling, cancel, retry); `programs.acwm.greeter.*` wires greetd with
      acwm as the greeter compositor
- [x] **oo7 secrets** — pinned 0.6.0 package (daemon/portal/cli, lockstep
      with nixpkgs `oo7-pam`); `programs.acwm.oo7.{enable,package,pamServices}`;
      nixpkgs-maintained PAM wiring; secrets docs
- [x] Raw (non-Nix) session assets + docs for every feature above

## Phase 3 — Zig build system ✅

- [x] `build.zig` (Zig 0.17) compiles all six executables from the C tree
- [x] Wayland-scanner codegen as build steps; pkg-config discovery;
      xwayland/tray auto-detection
- [x] Full install parity: bins, systemd units, dbus activation, portal
      registration, configs, man pages
- [x] `build.zig.zon`; zig in the devshell
- [ ] *Deferred:* switch the nix derivation from meson to
      `zig build` (meson stays green meanwhile; switch when Phase 4 makes
      Zig sources mandatory)

## Phase 4 — Leaf ports to Zig (unit-tested) `[~] in progress`

Pattern for every slice: port the C file to Zig exporting the same C ABI
symbols, remove the C twin from the compositor link, add unit tests to
`zig build test`, verify the full build. C types come from the shared
translate-c module (`cc`, from `include/c_acwm.h`) — no hand-maintained
struct mirrors.

- [x] `value_parse.c` → `src/config/value_parse.zig` (18 helpers, 11 tests)
- [x] `variable_expand.c` → `src/config/variable_expand.zig` (translate-c
      pattern established; `cc` module)
- [x] `error_store.c` → `src/config/error_store.zig` (config-error log
      mirror: XDG runtime dir fallback, 0700/0600 hardening, O_NOFOLLOW,
      ANSI-reset repair; 7 tests)
- [~] `option_defs.c` (3,028 lines) — the whale. Slices, in order:
  - [x] bar option group (45 `bar_*`/`group_bar_*`/`tab_bar_*` keys →
        `src/config/option_bar.zig`: comptime row table, tri-state
        `acwm_config_apply_bar_option`, 10 tests with C-parity checks)
  - [x] idle + general/session options (9 keys: focus_on_activate,
        numlock_on, the idle trio + idle/resume commands, sloppy_focus,
        warp_cursor → `src/config/option_session.zig`, 5 tests)
  - [x] layout options (22 keys: master defaults, tag_num/gather, dwindle
        tuning, hotarea, overview gaps, overcircle ratio →
        `src/config/option_layout.zig`, 5 tests)
  - [x] input options (23 keys: jump labels, cursor hide + size/theme,
        axis-bind timeout, drag/border-resize, tab modes, keyrepeat,
        trackpad/touch toggles → `src/config/option_input.zig`, 5 tests)
  - [x] visuals options (33 keys: blur + nested scenefx blur_params,
        shadows, window opacity, the 14-key color block with legacy error
        names → `src/config/option_visuals.zig`, 6 tests)
  - [x] device options (21 keys: mouse/trackpad accel + double-precision
        speeds, left-handed/middle-emulation, click/scroll methods,
        send-events modes, button_map, scroll factors →
        `src/config/option_device.zig`, 4 tests)
  - [x] animation options (25 keys: enable flags, open/close types via
        animation_type_from_string, fades/direction, zoom + opacity floats,
        five durations, seven 4-double Bezier curves via parse_double_array
        → `src/config/option_animation.zig`, 5 tests)
  - [x] scroller/focus options (15 keys: structs/proportions, edge
        scroller, cross-monitor/tag focus policy →
        `src/config/option_scroller.zig`, 5 tests)
  - [x] early misc (30 keys: scratchpad persistence, xwayland, sync/tearing/
        hdr, shortcuts/lock, auto-reload, monocle flags, snap/drag/gesture
        tuning, five fixed-size xkb rule strings →
        `src/config/option_misc.zig`, 6 tests)
  - [x] jump-label decoration set (10 keys → `src/config/option_jumplabel.zig`,
        5 tests)
  - [x] gaps/scratchpad/special gaps + border_px (12 keys →
        `src/config/option_gaps.zig`, 5 tests)
  - [x] `scroller_proportion_preset` + `circle_layout` (array parsers →
        `src/config/option_array.zig`: comma counting, strtok/sscanf
        semantics, 0.1..1.0 clamping, sanitized strings, full
        free-on-failure parity; 6 tests)
  - [~] rule tails:
    - [x] `monitor_rule` (name/make/model/serial, rr, scale, x/y,
          width/height/refresh, vrr/hdr/lum/icc, custom/disable/primary;
          realloc'd rule array + 4 validation gates →
          `src/config/option_monitor_rule.zig`, 7 tests)
    - [x] tag_rule + layer_rule (tag: id/* wildcard, matchers, master/
          scroller knobs; layer: name defaulting to "default", animation
          types, capture/blur/shadow switches → `src/config/option_rules.zig`,
          6 tests)
    - [x] window_rule + window_rule_once (49 attributes: 34 int relays
          defaulting to -1, 6 floats, title/app_id/monitor strings,
          animation types, tag masks, global_key_binding with
          parse_mod/parse_key and hard-abort semantics →
          `src/config/option_window_rule.zig`, 7 tests)
    - [x] device_rule (25 attributes: match name/type with touchpad
          deprecation alias, keyboard repeat/kb_* strings, libinput params
          with -1/UINT32_MAX/NAN sentinels →
          `src/config/option_device_rule.zig`, 7 tests)
    - [x] env/var/exec/exec_once/source (env with ~/$HOME expansion across
          occurrences, var name validation, strdup'd exec arrays, recursive
          source/source_optional with C prefix-match quirks →
          `src/config/option_directives.zig`, 9 tests)
    - [x] key_mode + bind/binds/mousebind/axisbind/switchbind/gesturebind
          (8-field sscanf parsing, mode classification, bind-flag regex
          incl. its literal '|' quirk, silent-vs-logged failure split →
          `src/config/option_bind.zig`, 11 tests)
          → every parse_option key now routes through Zig in the zig build
          (the C chain remains only for the meson build and is inert here)
  - [x] defaults/clamps tail: `set_value_default` (full defaults table),
        `override_config` (~190 clamp rows, C order, double-domain for f64
        fields), `update_global_var` (tag mask) and `apply_option_expanded`
        (variable expansion wrapper) → `src/config/option_defaults.zig`,
        6 tests. Only `parse_option` itself remains C in option_defs.c
        (its chain inert under the zig build; kept for meson)
- [x] `error_nag.c` → `src/config/error_nag.zig` (config-error nag
      launcher: wl_client + acwm-nag spawn, WAYLAND_SOCKET handoff, first-3
      lines piped + ellipsis summary, $EDITOR/$VISUAL edit command with
      plus/colon/-g line syntax, ANSI stripping; 10 tests)
- [x] `conflict_check.c` → `src/config/conflict_check.zig` (keybind
      grouping via qsort, mouse/axis/switch/gesture generic checker, ALLDIR
      wildcards, allowconflict opt-out, mod_to_string; 10 tests)
- [x] `binding_parse.c` → `src/config/binding_parse.zig` (keymap
      lifecycle, bind flags, modifier/key/button/mouse-action parsing,
      comma-arg combination, 93-entry parse_func_name dispatch via
      comptime @extern; 11 tests)
- [x] `load.c` → `src/config/load.zig` (line/file parsing with 255-byte
      value cap, format detection, path resolution, file-path table with
      recursive index restore, xkb layout resolution, 12 CHVT defaults,
      full parse_config pipeline; 7 tests)
- [x] `reapply.c` → `src/config/reapply.zig` (hot-reload reapply: env/exec
      re-application, client borders, tag-rule rebuild with per-client
      mfacts, monitor-rule commit/HDR/position pass, blur scenes, cursor
      style + timers, keyboard grouping/repeat, master defaults, tag reset
      and the reload_config sequence; 12 tests)
- [x] `cleanup.c` → `src/config/cleanup.zig` (deep-free of every config
      allocation + animation baked-point caches, with null/count resets and
      idempotent re-entry; 3 tests)
- [x] `watcher.c` → `src/config/watcher.zig` (inotify auto-reload: path
      tracking with dev/ino/size/mtime snapshots, per-directory watches,
      event matching incl. IN_Q_OVERFLOW, 150 ms debounce timer, reload on
      change; Linux backend only — BSD kqueue branch dropped, session is
      Linux-only; 4 tests incl. a real-kernel inotify round trip)
- [x] `toml_parse.c` → `src/config/toml_parse.zig` — **decision: hand-port**
      (no external TOML dependency; the accepted syntax is project-specific
      and diagnostics/truncation must match). Covers comment stripping with
      quote awareness, scalar/escape handling, bool mapping, array iteration
      and comma-joining keys, env/var formatting, bind section headers with
      keymode+flag suffixes and all five bind prefixes, rule pair
      accumulation and flush through parse_option, global statements,
      multi-line statement completion, quoted keys and the error/report
      flow. C twin guarded with ACWM_ZIG_TOML_PARSE; 11 fixture tests
- [~] IPC (`ipc.c`, 1,400) — sliced:
  - [x] JSON builders (tags/client/monitor/layers/layouts + all-tags
        responses) → `src/ipc/ipc_builders.zig`; C twins guarded with
        ACWM_ZIG_IPC_BUILDERS (meson keeps them); real cJSON; 8 tests that
        parse the emitted JSON
  - [x] watch-client plumbing + notifiers (shared watch list as extern
        symbols, send/remove lifecycle, device events, all watch types incl.
        last-open-surface and focusing-client, printstatus signal emission +
        dispatch) → `src/ipc/ipc_watch.zig`, 7 tests with socketpair round
        trips
  - [x] command surface, watch registration, connections, socket lifecycle
        → `src/ipc/ipc_server.zig`; C twins guarded with ACWM_ZIG_IPC_SERVER.
        `handle_command` covers every get command (version, cursorpos,
        keymode, keyboardlayout, last_open_surface, monitor, focusing-client,
        client, tag, all-clients/monitors/devices/layers/tags, tags, layouts)
        and the dispatch fast path with its `client,<id>` extraction and
        six-token parse; `handle_watch_command` registers all 11 watch types,
        moves the fd to a new event source and pushes initial state;
        connection handling (nonblocking + CLOEXEC, line buffering, 1 MiB
        cap), socket init (FD_CLOEXEC/O_NONBLOCK, sun_path bounds,
        ACWM_INSTANCE_SIGNATURE) and cleanup. 9 tests: real socketpairs,
        command responses, tag/client fixtures, dispatch tokenizing, watch
        promotion, init/cleanup round trip
  - [x] **ipc.c fully ported** — no C twins left under ACWM_ZIG_IPC_SERVER
- [~] Layout math: `arrange.c`, `scroll.c`, `dwindle.c`, `vertical.c`,
      `horizontal.c` — pure geometry functions, heavy table tests
  - [x] `vertical.c` → `src/layout/vertical.zig` (vertical tile/deck/grid/
        fair cores + all four predict variants; C twins guarded with
        ACWM_ZIG_LAYOUT_VERTICAL; C arithmetic domains preserved — pertag
        mfacts are float, master ratios double, 0.65 grid width double,
        deck `round`, truncating int conversions; 9 tests against a
        resize-recording stub covering masters/stack, inner+outer gaps,
        smartgaps, proportional master widths, deck visibility updates,
        single/double/2x2 grids, fair remainder rows and predict probes)
  - [x] `dwindle.c` → `src/layout/dwindle.zig` (all 18 symbols: tree
        count/find/first/free, removal with the manual-split proportional
        rollback, assignment with auto/locked split direction and probe
        contexts, generic + config-driven insertion with smart-split cursor
        picking and 1/N manual ratios, sibling/block move, monitor swap,
        cursor drag resize with lock capture and smart-resize inversion,
        per-client removal across all monitor pertags, the layout core with
        stale-leaf cleanup and focus fallback, predict insert/remove, and
        monitor cleanup; 12 tests)
  - [x] `horizontal.c` → `src/layout/horizontal.zig` (tile, right_tile,
        center_tile with alternating left/right stacks and both single-stack
        modes, deck, monocle, grid with centered overflow columns, fair;
        plus all seven predict variants. C twins guarded with
        ACWM_ZIG_LAYOUT_HORIZONTAL; 12 tests against the shared resize
        recorder. Also fixed a parity bug in the already-ported vertical
        tile: C stores `w / available` with integer division before widening
        to double, now reproduced with a regression test)
  - [x] `scroll.c` → `src/layout/scroll.zig` (horizontal + vertical scroller
        layouts with their persistent per-tag stack state: node create/find/
        remove/clear, client sync, weight normalization, stack geometry,
        fullscreen/maximized adjustment and monitor clamping, the focused
        head/left/right or up/down arrangement with center/overspread modes,
        insert-before/after stack linking, drop tiling, head/tail lookups,
        visible-state reconciliation, same-stack and cross-stack swaps, and
        client exchange. C twins guarded with ACWM_ZIG_LAYOUT_SCROLL;
        12 tests driving the state machine and both layout cores)
  - [x] `arrange.c` hub → `src/layout/arrange.zig` (size-weight
        distribution for master/stack and centered stacks, the pre-arrange
        visibility pass with scroll-head counting, isleftstack side
        assignment and arrange show/hide hooks, tag remap/gather with pertag
        state moves and trailing-slot resets, the `layouts[]` table and
        overview layout descriptor, special-view empty handling, and
        `arrange()` with special-gap swapping, tab sync, overview dispatch,
        post-layout tag gathering and pointer/idle/printstatus hooks. C twin
        guarded with ACWM_ZIG_ARRANGE_HUB; 10 tests)
  - [x] `arrange.c` resize/drag family → `src/layout/arrange_resize.zig`
        (frame-interval helper, set_size_per neighbour/default weight copying,
        master horizontal/vertical drag with direction heuristics, global
        ratio scaling and keyboard stepping, dwindle step/drag dispatch,
        grid/fair column+row weight transfers including the asymmetric
        VERTICAL_FAIR/FAIR boundary corrections, scroller head/stack ratio
        drag with weight rescaling, and the layout-id dispatcher. C twin
        guarded with ACWM_ZIG_ARRANGE_RESIZE; arrange.c is now fully ported;
        9 tests)
- [ ] `draw/text-node.c` — pangocairo text shaping helpers
- [ ] `dispatch/bind.c` tables (2,746) — after config parsing is Zig

Exit criteria for Phase 4: `option_defs` + parsers + layout math in Zig with
tests; compositor still builds green under `zig build` and meson/nix.

## Phase 5 — Core port on zig-wlroots (full parity)

- [ ] Pin zig-wlroots 0.20.x + zig-wayland; write bindings for acwm-specific
      protocols (text-input v2/v3, parts of ext-*) and upstream them
- [ ] Server/event loop + output management in Zig
- [ ] `manage/client.c` (4,932 lines — the biggest single unit)
- [ ] `manage/monitor.c`, `manage/layer.c`, `manage/tab.c`,
      `manage/misc.c` (incl. the idle/shim helpers)
- [ ] Input: pointer (1,888), keyboard, touch, tablet, switch, device,
      trackpad
- [ ] `animation/` — scenefx 0.5 via C FFI (blur/shadow/animations)
- [ ] `draw/` remainder + `overview/` + `switcher/`
- [ ] Bar + SNI tray (sd-bus FFI) with the bar/tray scene-node architecture
- [ ] `acwm-portal` screencast (pipewire negotiation, ext-image-copy-capture)
- [ ] `acwm-lock` — built-in session lock UI (ext-session-lock-v1 already
      implemented server-side; add the unlock prompt + keyring state)
- [ ] Session picker in `acwm-greeter` (list `/usr/share/wayland-sessions`)
- [ ] Port the companion clients to zig-wayland (`acwm-msg`, `acwm-nag`,
      `acwm-launch`, `acwm-portal`, `acwm-greeter`)
- [ ] Delete remaining first-party C; wlroots/scenefx/pango/sd-bus stay as
      linked C libraries

## Phase 6 — Packaging, CI, docs

- [ ] Switch the nix derivation to `zig build`; delete meson
- [ ] CI: zig build + zig build test + nix build on the three usual systems
- [ ] awfixeros switch: flake input → acwm, `modules/acwm.nix`, gnome-keyring
      → oo7, drop `packages/mango` copy, pinned SDDM entry removed
- [ ] Publish docs (website build from `docs/`), tagged releases with
      changelogs
- [ ] AUR/homebrew-style packaging offers for other distros

## Phase 7 — Later / ideas

- [ ] `acwm-portal` screencast polish (window capture, cursor modes)
- [ ] Greeter: multi-session + user list, theming hooks
- [ ] Secret refs in config (`secret://…` resolution via the keyring)
- [ ] Bar module API for user widgets
- [ ] Revisit idle-shim C helpers once the server core is Zig

## Risks & principles

- **Test-first at the boundary** — every ported module carries unit tests;
  no port merges red.
- **Same-symbol exports** — callers never change during Phase 4; behavior
  differences are bugs (e.g. the all-whitespace `trim_whitespace` underflow
  the C version masked).
- **zig-wlroots is river-scoped** — expect binding gaps; budget for upstream
  PRs in Phase 5.
- **scenefx stays C** via FFI; its ABI is pinned at 0.5.
- **GPL-3.0 carries forward** — the port is a derivative work; the LICENSE
  file and `UPSTREAM.md` provenance stay in the tree.
