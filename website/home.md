---
layout: home

hero:
  name: acwm
  text: A fast, practical Wayland compositor
  tagline: Built-in status bar, native secrets, its own greeter — and being ported to Zig.
  image:
    src: /acwm.png
    alt: acwm
  actions:
    - theme: brand
      text: Get started
      link: /docs/quick-start
    - theme: alt
      text: Configuration
      link: /docs/configuration/basics
    - theme: alt
      text: GitHub
      link: https://github.com/iresolvedllc/acwm

features:
  - title: Built-in status bar
    details: Tag buttons, clock, battery and an SNI system tray rendered in-process as scene nodes. No external bar needed.
  - title: Native screenshot portal
    details: acwm-portal answers org.freedesktop.impl.portal.Screenshot directly — no external portal backend.
  - title: Secrets built in
    details: Pinned oo7 integration — keyring daemon, secret portal and login unlock via PAM.
  - title: Its own greeter
    details: acwm-greeter + greetd. acwm is its own login compositor; no SDDM required.
  - title: Tags, not workspaces
    details: Each tag keeps an independent layout. Scroller, master-stack, monocle, dwindle, grid and more.
  - title: Being ported to Zig
    details: Module-by-module behind stable C-ABI boundaries, each with unit tests. Follow the roadmap.
---

## Quick look

```bash
# Nix
nix build github:iresolvedllc/acwm

# or from source (Zig 0.17)
git clone https://github.com/iresolvedllc/acwm.git
cd acwm
zig build
```

See [installation](/docs/installation) for dependencies and the source-build path,
or read the [introduction](/docs/) for the full feature tour.
