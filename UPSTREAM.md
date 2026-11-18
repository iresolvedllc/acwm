# Upstream lineage

acwm is a fork of [mangowc](https://github.com/mangowm/mango) ("mango" /
MangoWM, by DreamMaoMao) — a wlroots + scenefx based Wayland compositor built
on dwl.

## What this tree is based on

- Imported from upstream **tag `0.18.0`** (`a21b10fcbe6156b76ea96178d1941de5cb36137f`,
  2026-10-09), committed here as a single squashed "bootstrap" commit
  (tag `mangowc-base`).
- The working tree at import time was **not exactly the 0.18.0 tag**: it also
  contained upstream work that landed between 0.18.0 and 0.18.5 (the
  `master_size_weight` per-client layout rework and window-group-aware IPC are
  present, which do not exist in the 0.18.0 tag). The exact upstream commit the
  snapshot was cut from was not preserved by the squash. Upstream HEAD at the
  time of the fork was 0.18.5 (`5ba74a952ffd17033ecd5bea40e874fa875a56a2`).
- `meson.build` still carried `version : '0.18.0'` at import time.

## Fork-local additions at import time (never existed in upstream history)

- Built-in status bar: `src/bar/` (bar.c, tray.c), `include/mango/bar/bar.h`
  (~960 lines; tag buttons, clock, battery, SNI system tray over sd-bus) with
  ~40 `bar_*` config options. Upstream ships an *external* bar project
  ([mangobar](https://github.com/mangowm/mangobar)) instead.
- `mlaunch/` — standalone layer-shell application launcher (~2.5k lines),
  sibling of upstream's `mangonag`.
- Frame-based drag throttling (`drag_refresh_interval_ms` in layout/arrange.c),
  replacing upstream's config-based `drag_*_refresh_interval` options.
- Meson `tray` build option + `libsystemd` dependency for the SNI tray.
- Window-group-aware IPC extensions (client lookups across group members).
- Dev-shell rework in `flake.nix`.

## License

The imported code is GPL-3.0 (see `LICENSE`, restored from upstream). acwm
remains a derivative work of mangowc and stays GPL-3.0. The oo7 Secret Service
stack (planned session integration) is MIT and a separate project.

## Relationship to upstream going forward

- acwm has its own version numbering starting at 0.1.0.
- Upstream URL references in docs that point at mangowm.github.io / the
  upstream GitHub repo describe the upstream project and are kept as
  attribution, not as acwm's own docs.
