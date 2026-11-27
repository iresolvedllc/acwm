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

## Phase 4 — Leaf ports to Zig (unit-tested) ✅ complete

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
- [x] `draw/text-node.c` → `src/draw/text-node.zig` (cairo/pango text
      surfaces wrapped in a wlr_buffer implementation, font-description
      cache, scene-rect decoration with premultiplied colors and scenefx
      corner radii/clipped borders, jump labels, bar decorations with
      ellipsized text, focus-dependent colors, centered text, close-button
      rendering/hit-testing, and config application. C twin guarded with
      ACWM_ZIG_TEXT_NODE; 4 tests against a stub scene graph with real
      cairo/pango)
- [x] `dispatch/bind.c` (2,746) — fully ported in seven slices:
  - [x] tag/view/action cluster → `src/dispatch/bind_tagview.zig`: tag,
        tag_monitor (cycle/direction/spec monitor moves with float-geometry
        rescaling), tag_silent (tag0 handling + fullscreen clearing),
        tag_to_left/right carousel, special-workspace toggles and window
        moves to/from tag0, scratchpad and named-scratchpad toggles,
        fake-fullscreen/floating/fullscreen/global/gaps/group-bar/
        maximize/overlay/render-border toggles, toggle_tag (all-tags
        semantics) and toggle_view (size reset + printstatus). C twins
        guarded with ACWM_ZIG_BIND_TAGVIEW; 9 recorded-side-effect tests
  - [x] focus/group cluster → `src/dispatch/bind_focus.zig`:
        directional focus with cross-tag/cross-monitor fallbacks,
        focus-window-or-workspace, client group join/leave (linking,
        monitor moves, focus-stack reinsertion), focus_last history walk,
        trackpad toggle, focus_monitor (cycle/direction/spec + clear focus),
        focus_stack, over_circle overview cycling, group_focus,
        inc_nmaster and focus_by_id. C twins guarded with
        ACWM_ZIG_BIND_FOCUS; 9 tests
  - [x] layout/gap/proportion/window actions → `src/dispatch/bind_layout.zig`:
        all seven gap adjusters, set_master_factor with broadcast, kill_client
        (force/normal), move_resize bar-node resolution, move_window and
        resize_window for floating/tiled clients, restore_minimized
        (scratchpad eviction, minimized restore, tag/monitor reset), quit,
        set_layout by name, set_key_mode and the scroller set_proportion /
        switch_proportion_preset actions. C twins guarded with
        ACWM_ZIG_BIND_LAYOUT; 8 tests
  - [x] smart-move/center/spawn/layout-cycle → `src/dispatch/bind_move.zig`:
        smart_move_window and smart_resize_window (edge/neighbour snapping
        with monitor clamps), center_window for floating and scroller heads,
        spawn_shell/spawn (activation token, setsid, wordexp/execvp) and
        spawn_on_empty, plus switch_layout table/circle cycling.
        switch_keyboard_layout stays C for the keyboard slice; C twins
        guarded with ACWM_ZIG_BIND_MOVE; 6 tests
  - [x] view shifting/zoom/options → `src/dispatch/bind_view.zig`:
        view_shift_tag and the have-client variant (carousel wrap + tag
        gathering extent), view_to_left/right, view_insert (direct switch or
        tag shifting), the four have-client wrappers, view/tag cross-monitor
        routing, combo_view, zoom (promotes the visible tiled candidate),
        setoption (parse + override + reset) and minimize_window. C twins
        guarded with ACWM_ZIG_BIND_VIEW; 8 tests
  - [x] monitor/scroller/dwindle/reload tail → `src/dispatch/bind_tail.zig`:
        monitor enable/disable/toggle/sleep/wakeup/sleep-toggle (output state
        + only_sleep + layout reflow), scroller_apply_stack (axis guards,
        same-stack neighbour moves, cross-stack tail appends, UNDIR stack
        inserts), scroller_stack dispatch, toggle_all_floating with focus
        raising, dwindle split direction helpers (toggle/horizontal/vertical,
        current-parent flip) and load_config_file. C twins guarded with
        ACWM_ZIG_BIND_TAIL; 7 tests
  - [x] keyboard layout + overview → `src/dispatch/bind_overview.zig`:
        switch_keyboard_layout (layout cycle/explicit index, modifier
        notification, standalone-keyboard filtering and seat sync), overview
        enter/leave (visible-client counting, only-current mode, tagset
        backup/restore, cursor/pointer reset, animation flags, tab-layout
        arrange, tagset fixing and status refresh), fix_mon_tagset_from_overview,
        toggle/enter/leave guards and toggle_jump. C twins guarded with
        ACWM_ZIG_BIND_OVERVIEW; 6 tests. bind.c has no unported functions left.

Exit criteria for Phase 4: `option_defs` + parsers + layout math in Zig with
tests; compositor still builds green under `zig build` and meson/nix.
**Met** — all leaf modules (config, IPC, layout, draw, dispatch) are ported
with C twins behind per-slice guards, 168 build steps and 115 test steps
green.

## Phase 5 — Core port (full parity)

- [x] Core binding strategy: keep the existing C wlroots/scenefx stack via
      the `cc` translate-c module instead of pinning a zig-wlroots fork.
      Zig owns the compositor logic while protocol/type bindings stay
      authoritative C headers; this preserves parity and avoids maintaining a
      second wlroots binding layer.
- [x] Common layer slice 1 → `src/common/util.zig`: ecalloc, wayland-string
      UTF-8-safe copy, nonblocking fd helper, PCRE2 matching (suffixed
      `_8` symbols), list append/swap/safe-reinsert, monotonic millisecond
      helpers and string joins. `die`/`string_printf` and the log backend
      stay C (C-variadic functions cannot be defined in Zig). C twins
      guarded with ACWM_ZIG_UTIL; 7 tests
- [x] Common layer slice 2 → `src/common/scene_node.zig`: payload
      allocation/replacement with destroy-listener cleanup, ancestor lookup,
      ignore-hit flags and the pointer hit-test walker (reverse child order,
      subtree pruning, rect clipped-region rejection, buffer input callbacks,
      rotation-aware sizes and node-local coordinates). C twin guarded with
      ACWM_ZIG_SCENE_NODE; 5 tests against a fake scene graph
- [x] Common/draw slice 3 → `src/draw/dim-node.zig`: the dim overlay's 1x1
      cairo surface wrapped in a wlr_buffer, color-change rebuilds, corner
      radii, box clamping/positioning, enabled state and teardown. C twin
      guarded with ACWM_ZIG_DIM_NODE; 3 tests with real cairo
- [x] Animation slice → `src/animation/common.zig` (cubic curves with
      per-type control points, 256 baked-point tables and binary search,
      snapshot-metadata destruction, per-monitor frame requests) and
      `src/animation/tag.zig` (tag-in direction/origin, arrange-visible
      scratchpad/tag0/tag-switch paths, tag-out pending geometry and
      arrange-hidden slide-out/tagout resets). Scene snapshot helpers remain
      C; guards are ACWM_ZIG_ANIMATION_COMMON / ACWM_ZIG_ANIMATION_TAG;
      7 tests
- [x] `manage/tab.c` → `src/manage/tab.zig`: layout-mode gating
      (monocle/deck tab modes), tab-chain head/focus/leave, monitor sync
      (kept-member filtering and chain rebuild), detach/replace relinking,
      input-penetration propagation across the chain, bar-node lifecycle
      (create/lower/title/config/destroy), raise/reparent helpers and the
      side-by-side strip layout with offsets and focus flags. C twin guarded
      with ACWM_ZIG_TAB; 7 tests
- [x] Built-in idle handling from `manage/misc.c` → `src/manage/idle.zig`:
      keep-idle-inhibit polling (focus/override and fullscreen config),
      activity notification with resume command, idle-check timer
      re-arming, inhibited/active-session handling and one-shot idle
      command. C region guarded with ACWM_ZIG_IDLE; 4 tests
- [x] Remaining `manage/misc.c` → `src/manage/misc.zig`: process ancestry
      and parent lookup, layout-name abbreviation table/fallback chain,
      client hit-testing, layer focus rules, layered `node_at_point` with
      overview and special-dim handling, idle-inhibitor bookkeeping,
      xdg-decoration negotiation, session-lock manager/surface lifecycle
      and focus restoration, foreign-toplevel capture requests and BGR shm
      format announcement, session tracking, DRM lease grant/reject and
      seat primary/clipboard selection policy (global filter). C file now
      guarded with ACWM_ZIG_MISC; 9 tests
- [x] `animation/layer.c` → `src/animation/layer.zig`: layer actual size,
      exclusive-zone consumption and bound-area walk, anchor/margin target
      geometry, nearest-edge slide direction, capture shields, shadows with
      intersection clipping, buffer scale/fadeout effects, open and close
      animation ticks (opacity, blur, zoom buffers, completion) and
      fadeout snapshot creation/pending-state/commit/frame gating. C twin
      guarded with ACWM_ZIG_ANIMATION_LAYER; 12 tests
- [x] `manage/layer.c` → `src/manage/layer.zig`: exclusive/non-exclusive
      arrangement and popup sync, layer focus with IME relay, exclusive
      focus reset, bar-strip reservations and stale-geometry refresh,
      blur-buffer iteration/wallpaper choice/background cache invalidation,
      map-time rules (shield/blur/animation/shadow), shield/shadow/blur
      scene creation, commit handling (initial configure, empty buffers,
      animated moves, layer reparenting/list moves, keyboard-interactivity
      reset, blur refresh), popup creation/commit/reposition/destroy with
      unconstraining, surface creation/output fallback, node teardown and
      unmap cleanup. C twin guarded with ACWM_ZIG_LAYER; 11 tests
- [x] Monitor query/tag layer from `manage/monitor.c` →
      `src/manage/monitor_query.zig`: special-view detection, current tag
      selection, live-special-client scan, active tagset fallback,
      directional/cyclic monitor selection, layout predicates, special top
      layer reparenting, dim-rect sync, tag status (urgent/occupied),
      first-tag number/mask resolution, point/nearest monitor lookup,
      monitor-spec matching (name/make/model/serial), device-rule monitor
      targeting, wallpaper-layer classification, selected-monitor setter
      and gap updates with special-view variants. C region guarded with
      ACWM_ZIG_MONITOR_QUERY; 9 tests
- [x] Monitor output commit/mode/ICC/rule cluster from `manage/monitor.c`
      → `src/manage/monitor_output.zig`: scene-output state commit with
      damage/state short-circuit, ICC attachment (suppressed by image
      descriptions), tearing negotiation with fallback and one retry,
      pending-state reset, direct pending commit, nearest-mode selection by
      size+refresh, adaptive-sync testing/flag handling, monitor rule
      matching (name/make/model/serial), ICC file validation/loading and
      path caching, and rule application (VRR/HDR/disable/luminance/force/
      scale/transform, internal/custom/headless modes). C region guarded
      with ACWM_ZIG_MONITOR_OUTPUT; 10 tests
- [x] Output lifecycle/skip-frame/renderer-loss cluster from
      `manage/monitor.c` → `src/manage/monitor_lifecycle.zig`: output
      destroy (bar/layers/ext-workspaces/lock surface/scene output/layout
      removal, blur/dim/timer/ICC/pending teardown), monitor close
      (overview exit, selection fallback to the next enabled output,
      client group moves, foreign-toplevel drop, old-name recording),
      nested-backend request-state mode/custom handling, wayland/headless
      output creation, output power-mode commits, skip-frame timer
      stop/callback/check and renderer-loss idle recreation. C regions
      guarded with ACWM_ZIG_MONITOR_LIFECYCLE; 7 tests
- [x] Output layout/manager/frame cluster from `manage/monitor.c` →
      `src/manage/monitor_ops.zig`: layout reconciliation (disabled-monitor
      removal with sleep exception, auto-insert, root/locked backgrounds,
      per-output geometry, floating offset and old-name restore, XWayland
      scale, scene-output/blur/dim/lock-surface sync, arrangement,
      fullscreen resize, selection), orphan client adoption and tag
      assignment, cursor reset, output-manager apply/test with commits,
      layout adds, success/failure replies and reconfiguration, per-frame
      layer/fadeout/client drawing, skip-frame commit suppression and VRR
      enable/disable policy. XWayland calls are gated by a build option.
      C regions guarded with ACWM_ZIG_MONITOR_OPS; 5 tests
- [x] `handle_new_output` from `manage/monitor.c` →
      `src/manage/monitor_new.zig`: renderer init and non-desktop DRM-lease
      offers, headless naming, monitor/state allocation and defaults,
      temporary rule state with first-match application, preferred/custom
      mode fallback, final state assembly (enabled/mode/scale/transform/
      adaptive sync), HDR setup, scene-output creation/build/commit with
      ICC, layout placement (auto/manual), scene-layout and monitor-list
      registration, pertag defaults, chvt tag restore, tag rules, optimized
      blur, dim rect, ext-workspace group and per-tag workspaces, initial
      layout/bar creation and frame/destroy/request-state listeners. C
      region guarded with ACWM_ZIG_MONITOR_NEW; 5 tests. monitor.c is now
      fully ported
- [x] Basic client helpers from `manage/client.c` →
      `src/manage/client_basic.zig`: role detection (X11/xdg), surface
      selection, toplevel/popup/layer surface resolution, activation,
      appid/pid/title with broken fallbacks, tag index, clip and geometry
      (including XWayland conversion), parent/children queries, float-type
      inference, rendered-on-monitor and unmanaged checks, keyboard enter,
      close/fullscreen requests, border/state colors and fractional scale
      notification. C region guarded with ACWM_ZIG_CLIENT_BASIC; 9 tests.
      Also fixed the translate-c unit to define XWAYLAND (and test C
      sources to compile with it), so Zig `Client` layouts now match the
      real C build's conditional fields
- [x] Client size/state and XWayland clipping from `manage/client.c` →
      `src/manage/client_state.zig`: device-aligned source-box clipping
      (rounding, overhang/nearest filtering, zoom-like and negative clips),
      dest-size restore/active-clip path, xdg/XWayland size configuration
      with hint clamping and duplicate-config suppression, minimize/
      maximize/tiled state, tiled-hint sync, focus/popup/global/overtop/
      unmanaged predicates, fullscreen/minimize/maximize requests, size
      bounds (logical/scaled) and border hit-testing. C region guarded with
      ACWM_ZIG_CLIENT_STATE; 9 tests
- [x] Client lookup/direction/stack helpers from `manage/client.c` →
      `src/manage/client_lookup.zig`: terminal lookup in the focus stack,
      id/title/swallow-target client search, centered geometry with
      offsets/clamps/borders, window-rule matching, nearest center-tiled
      selection, directional neighbor search (step fallback, overlap and
      cross-monitor rules, distance/center tie-breaks, stack filtering),
      direction selection guards, top-of-focus-stack lookup, cyclic
      next/previous client in the client list, border/dim color selection,
      single-bit/one-tag tests, same-stack layout logic (monocle, tiles,
      decks, scrollers, center-tile) and focus-memory stack selection with
      dwindle branch restrictions. C region guarded with
      ACWM_ZIG_CLIENT_LOOKUP; 11 tests
- [x] Client rules and floating snap from `manage/client.c` →
      `src/manage/client_rules.zig`: full window-rule property application
      (int sentinels, float thresholds, animation types), overlap-aware
      floating placement, monitor-tag reset (special/overview/masks),
      per-tag open-as-floating, pre-map rule application (tags, monitors,
      size fractions, offsets, custom flags, once rules, size bounds),
      parent-tag inheritance, monitor-spec targeting, mapped-path actions
      (swallow/terminal adoption, focus suppression, monitor assignment,
      fullscreen backup, tag-view animation, fullscreen-peer exit, named
      scratchpads, overlay reparenting, floating reinsertion/malposition)
      and floating edge/neighbour snapping with resize. C region guarded
      with ACWM_ZIG_CLIENT_RULES; 9 tests
- [x] Client geometry/init and tiling helpers from `manage/client.c` →
      `src/manage/client_init.zig`: geometry updates, tiling and floating
      size application with border/tab deductions, xdg toplevel
      configure/size negotiation, unmanaged X11 overlay setup, XWayland
      root-buffer tracking and commit listeners, scaled scene-buffer input
      hit-testing, property initialization and resize clamping. C region
      guarded with ACWM_ZIG_CLIENT_INIT; 9 tests
- [x] Client map/commit/unmap/destroy lifecycle from `manage/client.c` →
      `src/manage/client_lifecycle.zig`: scene setup, XWayland scene/scale
      init, map and unmap paths, destroy teardown, request handlers
      (fullscreen/minimize/maximize/title), tag visibility sync, focus
      stack bookkeeping and animation hooks. C region guarded with
      ACWM_ZIG_CLIENT_LIFECYCLE; 7 tests and shared tiling helpers exported
      from client_init
- [x] Client focus/view/tag visibility from `manage/client.c` →
      `src/manage/client_view.zig`: view/tag assignment, show/hide with
      animations and overview interaction, focus/raise/unfocus, monitor
      view dispatch, visibility reconciliation and tag-view calls. C region
      guarded with ACWM_ZIG_CLIENT_VIEW; 7 tests
- [x] Client floating/fullscreen/scratchpad transitions from
      `manage/client.c` → `src/manage/client_transition.zig`: floating
      enter/leave with mode clearing, centered/clamped geometry and peer
      fullscreen exit, fullscreen apply/restore, fake fullscreen,
      maximize-screen gaps/group-bar reservation and reset, minimize/
      unminimize with tag/scratchpad preservation, scroller-stack exit,
      pending state propagation to foreign toplevels, scratchpad show/
      switch/named handling, border/dim updates, exchange and park/unpark/
      replace. C region guarded with ACWM_ZIG_CLIENT_TRANSITION; 8 tests
- [x] Monitor moves, bounds, visibility and group/decorations from
      `manage/client.c` → `src/manage/client_group.zig`: direction-based
      monitor jump/move with scroller/tile insertion, old-name recording,
      bounds, layout/monitor/tag swaps, tile resize with bar reservations,
      client ids, gesture/visibility decisions, scene target layers, layer
      sync, group-bar lifecycle, group focus/chains/detach/replace,
      tab-node visibility, raise/reparent and decoration clicks, frame-done
      forwarding, force render and pending SIGKILL. C region guarded with
      ACWM_ZIG_CLIENT_GROUP; 7 tests
- [x] XWayland integration from `manage/client.c` →
      `src/manage/client_xwayland.zig`: monitor fallback and client/
      preferred scale, logical↔X11 conversion with scene origin, X11
      geometry for normal/fullscreen windows, coordinate fixing, configure
      routing (unmapped/unmanaged/floating/tiled), activation with
      minimize restore/urgency, hint urgency, new-surface listener
      registration, associate/dissociate, commit serial tracking,
      XWayland ready (seat, primary selection, cursor, keymap timer) and
      geometry updates. C region guarded with ACWM_ZIG_CLIENT_XWAYLAND;
      11 tests. `manage/client.c` is now fully ported; `-Dxwayland=false`
      also builds
- [ ] Server/event loop + output management in Zig
- [ ] `manage/monitor.c`, `manage/layer.c`, `manage/tab.c`,
      `manage/misc.c` (incl. the idle/shim helpers)
- [x] Input device dispatch and switches from `input/device.c` +
      `input/switch.c` → `src/input/device.zig`: input-device teardown with
      switch payload and keyboard-watch cleanup, seat-device tracking and
      capability recomputation (pointer/tablet, touch + mouse emulation,
      keyboard), new-device dispatch to keyboard/pointer/touch/tablet/pad/
      switch creators, libinput switch creation with destruction/toggle
      listeners, and switch-binding matching (common/default/mode, fold and
      callback dispatch). C regions guarded with ACWM_ZIG_INPUT_DEVICE;
      6 tests
- [x] Touch input from `input/touch.c` → `src/input/touch.zig`: monitor
      mapping, libinput send-events modes, cursor attachment, layout→surface
      coordinate conversion with per-point offsets, X11 touch scaling, touch
      protocol down/motion/up/cancel with surface-destroy tracking, pointer
      emulation (absolute motion, button press/release, emulated frames),
      global touch disable/finish-all and per-device IPC notifications. C
      region guarded with ACWM_ZIG_INPUT_TOUCH; 9 tests
- [x] Tablet input from `input/tablet.c` → `src/input/tablet.zig`: tablet
      and pad creation through tablet-v2 with libinput modes/cursor attach,
      sibling pad/tablet matching by libinput group, attach/destroy
      listener lifecycles, tool allocation and proximity handling,
      device-rule output mapping, cursor move vs absolute warp, sloppy
      focus, surface enter/leave with pad enter/leave, X11 coordinate
      scaling, axis notifications (pressure/distance/tilt/rotation/slider/
      wheel), buttons, tips with implicit grabs and seat fallback. C region
      guarded with ACWM_ZIG_INPUT_TABLET; 10 tests
- [x] Trackpad gestures from `input/trackpad.c` → `src/input/trackpad.zig`:
      trackpad detection via libinput tap fingers, global disable, swipe/
      pinch/hold forwarding to clients, gesture-binding matching with mode/
      modifier/finger/motion filters, live swipe drive state machine
      (lock threshold, dominant axis, speed averaging, transition progress,
      commit/revert/flick, opposite-action replay), scroller pan strip with
      rubber-banding, pan commit/flick targeting, drag-to-move-resize with
      window grab, and release-based swipe binding fallback. C region
      guarded with ACWM_ZIG_INPUT_TRACKPAD; 8 tests
- [x] Keyboard input from `input/keyboard.c` → `src/input/keyboard.zig`:
      device-rule matching by name/identifier/type (vendor:product, trackpad
      detection), rule keyboard-settings detection and self-contained keymap
      compilation, device creation into the shared group or standalone
      groups, repeat timer and keybinding replay, shortcut-inhibitor
      registration/removal, global window-rule key forwarding, physical
      modifier union, standalone/virtual keyboard lifecycle with seat
      restoration, keybinding matching (modes, mods, sym/code, press/
      release/pass/conflict), key handling (activity, cursor hide, mode-key
      overview/switcher, jump mode, bindings, repeat, global keys, seat
      forwarding), modifier forwarding/layout status, layout reset across
      grouped keyboards and virtual-keyboard setup. C region guarded with
      ACWM_ZIG_INPUT_KEYBOARD; 10 tests
- [x] Pointer constraints/configuration from `input/pointer.c` (part 1) →
      `src/input/pointer_constraints.zig`: surface-scale helpers, pointer
      warp boxes, constraint region sync/nearest-point clamping, hint
      warping, locked-constraint region tests, confine-rule tracking and
      warp/forget, constraint surface visibility, activation/deactivation
      and destroy/commit handlers, hot-area toggling, axis bindings with
      apply timeouts and scroll-factor forwarding, button dispatch, cursor
      shape requests, libinput acceleration/tap/DWT/left-handed/middle/
      scroll/click/send-events configuration with device-rule overrides,
      pointer device creation, frame handling and absolute motion. C region
      guarded with ACWM_ZIG_POINTER_CONSTRAINTS; 9 tests
- [x] Pointer motion/resize/drag/focus from `input/pointer.c` (part 2) →
      `src/input/pointer_input.zig`: resize-grab edges with tiled-neighbour
      filtering and cursor names, floating resize clamps, drag-float
      conversion, move/resize grab setup (corner selection, cursor warp,
      offsets), grab release with monitor transfer/tag retargeting/snap/
      drop-area cleanup, group-bar drag targets, relative/absolute pointer
      motion with constraint confinement and sloppy focus, resize-strip
      cursor ownership, drag-icon positioning, scroll-edge focus locking,
      pointer focus enter/motion/X11 scaling, pointer-grab drag start and
      cursor-surface requests, drag-icon creation, cursor activity/hide and
      remembered surface/shape restoration, client/monitor warps, virtual
      pointers, closest-tiled lookup, drag-to-tile placement across scroller/
      dwindle/right-tile/tiled layouts, and full button routing (switcher,
      bars, decorate clicks, overview clicks, mouse bindings, border
      resize, group drop and grab release). C region guarded with
      ACWM_ZIG_POINTER_INPUT; 8 tests. input/pointer.c is now fully ported
      and the input subsystem is complete
- [ ] `animation/` — scenefx 0.5 via C FFI (blur/shadow/animations)
- [ ] `draw/` remainder + `overview/` + `switcher/`
- [x] Built-in bar from `bar/bar.c` → `src/bar/bar.zig`: strip height,
      tag-button refresh with active/urgent/special palettes, monitor
      layout (bar background, corner radii, tag/tray/battery/clock
      placement), fullscreen/session-lock visibility, clock and battery
      timers/formatting, per-monitor create/destroy, config reload,
      lock updates, bar click routing (tag/special/tray/chrome),
      print-status listener, tray sync-all and cleanup. C region guarded
      with ACWM_ZIG_BAR; 7 tests. Bar/tray remaning: tray.c
- [ ] SNI tray from `bar/tray.c` (sd-bus FFI)
- [x] Small extension protocols from `ext-protocol/tearing.c`,
      `xdg-activation.c` and `foreign-toplevel.c` →
      `src/ext-protocol/protocol_small.zig`: tearing-controller hint
      tracking/lifecycle and the tearing frame policy matrix; trusted/
      focused xdg-activation tokens, token export for spawn, activation
      requests with bypass/authorised/urgent paths and full init/destroy
      wiring; foreign-toplevel handle creation with app-id/title/output,
      activate/maximize/minimize/fullscreen/close request routing,
      listener teardown and monitor output moves. C regions guarded with
      ACWM_ZIG_EXT_SMALL; 7 tests
- [x] ext-workspace and HDR from `ext-protocol/ext-workspace.c` and
      `hdr.c` → `src/ext-protocol/workspace_hdr.zig`: workspace names and
      tag switching, add/remove/destroy/cleanup by monitor, overview vs
      normal refresh, commit request activate/deactivate routing,
      hidden/urgent/active status with no-hide and tagmask awareness, tag
      count synchronisation; 8/10-bit format candidate selection, bit-depth
      detection, EDID/renderer HDR capability checks with force override,
      image-description enabling with mastering metadata, depth
      setup/fallback, per-output toggle with damage/commit/revert and
      resolution refresh, and all/named/selected monitor toggling. C
      regions guarded with ACWM_ZIG_EXT_WORKSPACE_HDR; 9 tests
- [x] xdg-output from `ext-protocol/xdg-output.c` →
      `src/ext-protocol/xdg_output.zig`: XWayland resource detection,
      rotation/scale-aware logical and physical values with output-layout
      offsets and XWayland origin, logical/physical send baselines,
      change detection, per-resource update, resource/description/destroy
      handling, output create/find/destroy with layout-output teardown,
      manager get-output wiring (names/descriptions/details/done), manager
      bind, all-output updates with wl_output.done scheduling and
      XWayland-only done, and manager global init. C region guarded with
      ACWM_ZIG_EXT_XDG_OUTPUT; 8 tests
- [x] text-input/input-method v2 from `ext-protocol/text-input.c` →
      `src/ext-protocol/text_input.zig`: monitor lookup/usability, virtual
      keyboard emulation detection, keyboard-grab forwarding for keys and
      modifiers, active text-input selection and input-method activate/
      deactivate, per-client focused-surface enter/leave, input-method
      commit forwarding (preedit/commit/delete/done), surrounding text/
      change-cause/content-type state, text-input enable/disable/commit/
      destroy handling, popup scene trees and cursor-rectangle positioning
      with positioner constraints, input-method/popup/text-input listener
      wiring, relay create/finish/focus and focused-surface teardown. C
      region guarded with ACWM_ZIG_EXT_TEXT_INPUT; 9 tests. The
      ext-protocol directory is now fully ported
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
