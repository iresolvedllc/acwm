# Upstream lineage

acwm is a fork of [mangowc](https://github.com/mangowm/mango) ("mango" /
MangoWM, by DreamMaoMao) — a wlroots + scenefx based Wayland compositor built
on dwl.

## What this tree is based on

- Imported from upstream **tag `0.18.0`** (`a21b10fcbe6156b76ea96178d1941de5cb36137f`,
  2026-10-09), committed here as a single squashed "bootstrap" commit
  (tag `mangowc-base`).
- The working tree at import time was **not exactly the 0.18.0 tag**. It
  provably contains upstream work landing on/after **2026-10-31**:
  - `master_size_weight` layout rework — upstream `72bd9c76` ("opt: redo size
    percent logic", 2026-10-10, after the 0.18.0 tag),
  - `drag_refresh_interval_ms` frame-rate drag dispatch — upstream `70f830b0`
    ("opt: Adapt the requests of resize dispatch to the screen frame rate",
    2026-10-31); upstream HEAD has since reworked this area,
  - window-group-aware IPC (`client_by_id_all`, `is_group_focus`) — present in
    upstream `src/ipc/ipc.c` at HEAD.
  The exact upstream commit the snapshot was cut from was not preserved by the
  squash. Upstream HEAD at the time of the fork was 0.18.5
  (`5ba74a952ffd17033ecd5bea40e874fa875a56a2`, 2026-11-16).
- `meson.build` carried `version : '0.18.0'` at import time even though
  upstream had already bumped to 0.18.1 by 2026-10-15 (`91e3f68`) — i.e. the
  version string was reset by whoever prepared the snapshot.

## Fork-local additions at import time (never existed in upstream history)

- Built-in status bar: `src/bar/` (bar.c, tray.c), `include/mango/bar/bar.h`
  (~960 lines; tag buttons, clock, battery, SNI system tray over sd-bus) with
  ~40 `bar_*` config options. Upstream ships an *external* bar project
  ([mangobar](https://github.com/mangowm/mangobar)) instead.
- `mlaunch/` — standalone layer-shell application launcher (~2.5k lines),
  sibling of upstream's `mangonag`.
- Meson `tray` build option + `libsystemd` dependency for the SNI tray
  (absent from upstream meson at HEAD).
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
