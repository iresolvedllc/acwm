---
title: Installation
description: Install acwm on AerynOS, Arch, Fedora, Gentoo, Guix System, NixOS, PikaOS, or build from source.
---

## Package Installation

acwm can be installed by building from source or via the NixOS flake. Pre-built distribution packages are not available yet.

---

### Install from source or Nix

There are currently no distribution packages for acwm. Use one of the following methods:

- [Build from source](#building-from-source)
- [NixOS flake](#nixos)

---


### NixOS

The repository provides a Flake with a NixOS module.

1. **Add flake input**

   ```nix
   # flake.nix
   {
     inputs = {
       nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
       acwm = {
         url = "github:iresolvedllc/acwm";
         inputs.nixpkgs.follows = "nixpkgs";
       };
       # other inputs ...
     };
   }
   ```

2. **Import the NixOS module**

   **Option A — Import in `configuration.nix`:**

   ```nix
   # configuration.nix (or any other file that you import)
   {inputs, ...}: {
     imports = [
       inputs.acwm.nixosModules.acwm
       # .. other imports ...
     ];

     # ...
   }
   ```

   **Option B — Import directly in flake:**

   ```nix
   # flake.nix
   {
     # ...

     outputs = { self, nixpkgs, acwm, ...}@inputs: let
       inherit (nixpkgs) lib;
       # ...
     in {
       nixosConfigurations.YourHostName = lib.nixosSystem {
         modules = [
           acwm.nixosModules.acwm # or inputs.acwm.nixosModules.acwm
           # other imports ...
         ];
       };
     }
   }
   ```

3. **Enable the module**

   ```nix
   # configuration.nix (or any other file that you import)
   {
     programs.acwm.enable = true;
   }
   ```

4. **Start acwm on login**

   The following are common examples. Refer to the official NixOS documentation for full configuration options.

   **Option A — greetd:** Autologin on first start; login screen after logout.

   ```nix
   services.greetd = {
     enable = true;
     settings = {
       initial_session = {
         command = "acwm";
         user = "your-username"; # auto-login on first start, no password required
       };
       default_session = {
         command = "${pkgs.greetd.tuigreet}/bin/tuigreet --cmd acwm";
         user = "greeter";
       };
     };
   };
   ```

   **Option B — Display manager autologin:** Autologin via an existing display manager (e.g. SDDM, GDM). [`addLoginEntry`](/docs/nix-options#addloginentry) (default: `true`) automatically registers acwm as a session.

   ```nix
   services.displayManager = {
     defaultSession = "acwm"; # derived from acwm.desktop filename
     autoLogin = {
       enable = true;
       user = "your-username";
     };
   };
   ```

   **Option C — getty autologin:** No login screen, boots directly into acwm on TTY1.

   For bash/zsh:

   ```nix
   services.getty.autologinUser = "your-username";

   environment.loginShellInit = ''
     [ "$(tty)" = /dev/tty1 ] && exec acwm
   '';
   ```

   For fish:

   ```nix
   services.getty.autologinUser = "your-username";

   programs.fish.loginShellInit = ''
     if test (tty) = /dev/tty1
         exec acwm
     end
   '';
   ```

5. **All available options**

   See [Nix Module Options](/docs/nix-options) for the full list of NixOS and Home Manager options.

---

## Building from Source

If your distribution isn't listed above, or you want the latest unreleased changes, you can build acwm from source.

> **Info:** Ensure the following dependencies are installed before proceeding:
>
> - `wayland`
> - `wayland-protocols`
> - `libinput`
> - `libdrm`
> - `libxkbcommon`
> - `pixman`
> - `libdisplay-info`
> - `libliftoff`
> - `hwdata`
> - `seatd`
> - `pcre2`
> - `pango`
> - `cjson`
> - `pixman`
> - `xorg-xwayland`
> - `libxcb`

You will need to build `wlroots` and `scenefx` manually as well.

1. **Build wlroots**
   Clone and install the specific version required (check README for latest version).

   ```bash
   git clone -b 0.20.2 https://gitlab.freedesktop.org/wlroots/wlroots.git
   cd wlroots
   meson build -Dprefix=/usr
   sudo ninja -C build install
   ```

2. **Build scenefx**
   This library handles the visual effects.

   ```bash
   git clone -b 0.5 https://github.com/wlrfx/scenefx.git
   cd scenefx
   meson build -Dprefix=/usr
   sudo ninja -C build install
   ```

3. **Build acwm**
   Finally, compile the compositor itself.
   ```bash
   git clone https://github.com/iresolvedllc/acwm.git
   cd acwm
   sudo zig build --prefix=/usr -Doptimize=ReleaseFast
   ```
