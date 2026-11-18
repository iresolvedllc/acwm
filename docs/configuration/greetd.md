---
title: greetd (Login Manager)
description: Use acwm as a greetd greeter compositor with acwm-greeter.
---

# greetd

[greetd](https://sr.ht/~kennylevinsen/greetd/) is a minimal login-manager
daemon that owns PAM, seats and VTs. acwm ships `acwm-greeter`, a tiny
layer-shell greeter client that talks to greetd and renders the
username/password UI — with **acwm itself as the greeter compositor**.

```
greetd → starts `acwm` (greeter session) → acwm starts `acwm-greeter`
       → you log in → greetd starts `acwm` (your session)
```

## Setup (generic distros)

1. Install `greetd` from your distribution.

2. Create a config for the greeter user's acwm instance, e.g.
   `/etc/acwm/greeter/config.conf`:

   ```ini
   # minimal greeter compositor config — no bar, no IPC socket
   exec_once=acwm-greeter
   ```

3. Configure greetd (`/etc/greetd/config.toml`):

   ```toml
   [terminal]
   vt = 1

   [default_session]
   # acwm is the greeter compositor; it starts acwm-greeter from the
   # config below
   command = "acwm -c /etc/acwm/greeter/config.conf"
   user = "greeter"

   [user_session]
   # the session greetd starts for the logged-in user
   command = "acwm"
   ```

   Make sure the `greeter` user can read the config files.

4. Enable/start greetd (e.g. `systemctl enable greetd`).

## NixOS

The acwm NixOS module wires the same setup through greetd:

```nix
programs.acwm = {
  enable = true;
  # optional: enable the greeter (uses the acwm package, creates a
  # minimal greeter config and a `greeter` session entry)
  greeter.enable = true;
};
```

See the [Nix module options](/docs/nix-options) for the full list. greetd
still needs `security.pam.services.greetd` — the module handles the PAM
wiring for keyring unlock through `programs.acwm.oo7.pamServices` (add
`"greetd"` to the list when using greetd instead of SDDM).

## Notes

- `acwm-greeter` requires `GREETD_SOCK`, which greetd sets for the greeter
  session — never start it outside a greetd session.
- Multi-session selection (listing `/usr/share/wayland-sessions`) is not
  implemented yet; the session command comes from greetd's
  `[user_session]` section.
- The greeter user's acwm runs like any other acwm instance, so you can
  theme the greeter backdrop (wallpaper, colors) via its config.
