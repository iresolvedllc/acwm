# Secrets & Keyring

acwm integrates [oo7](https://github.com/linux-credentials/oo7) as the session
Secret Service provider. oo7 is a Rust implementation of the
[`org.freedesktop.secrets`](https://specifications.freedesktop.org/secret-service-spec/latest/)
D-Bus API — the interface that browsers, Git, SSH tools and `libsecret`-based
apps use to store passwords, tokens and cookies in an encrypted keyring.

The acwm flake ships a pinned oo7 package (`oo7-daemon`, the `oo7` secret
portal backend and `oo7-cli`) so the daemon, portal and CLI always come from
the same compatible source.

## What you get

| Piece | Role |
|---|---|
| `oo7-daemon` | Implements `org.freedesktop.secrets` on the session bus (replaces `gnome-keyring-daemon`) |
| `oo7` portal backend | Implements `org.freedesktop.impl.portal.Secret` for sandboxed/portal apps |
| `oo7-cli` | `secret-tool`-style CLI (`oo7-cli lookup/search/store/…`) |
| `pam_oo7` | Unlocks the keyring with your login password (via nixpkgs' `oo7-pam`) |

## NixOS

Enable it through the acwm module:

```nix
programs.acwm = {
  enable = true;
  oo7 = {
    enable = true;
    # pamServices defaults to [ "sddm" "login" ] — PAM services that unlock
    # the keyring at login using nixpkgs' built-in oo7 wiring.
    # pamServices = [ "sddm" "login" "sudo" ];
  };
};
```

This wires up:

- `oo7-daemon` + the secret portal backend as D-Bus-activatable user services
  (registered through `systemd.packages` / `xdg.portal.extraPortals`),
- the portal preference so the acwm desktop routes `Secret` to `oo7`,
- `security.pam.services.<name>.oo7.enable = true` for each service listed in
  `pamServices` (the nixpkgs-maintained rule placement, after password entry).

## Other distributions

1. Install oo7 (0.6.0 or newer) — from your distro if packaged, otherwise:

   ```bash
   git clone https://github.com/linux-credentials/oo7.git
   cd oo7
   cargo build --release -p oo7-daemon -p oo7-portal -p oo7-cli
   sudo install -Dm755 target/release/oo7-daemon target/release/oo7-portal target/release/oo7-cli \
     -t /usr/local/bin
   ```

2. Start the daemon in the session (D-Bus activation file ships with proper
   installs, or autostart it explicitly):

   ```
   exec_once=oo7-daemon
   ```

3. Point the Secret portal at oo7 in
   `~/.config/xdg-desktop-portal/acwm-portals.conf` (the default acwm
   `acwm-portals.conf` already contains this):

   ```ini
   [preferred]
   org.freedesktop.impl.portal.Secret=oo7;gnome-keyring;
   ```

4. Keyring unlock at login: install nixpkgs' `oo7-pam` (or build
   `cargo build --release -p oo7-pam` and install `libpam_oo7.so` as
   `pam_oo7.so` into `/lib/security`), then add to your display manager's PAM
   stack **after** the password module:

   ```
   auth  optional  pam_oo7.so
   ```

## CLI usage

```bash
oo7-cli store --label "My token" application://myapp my-secret
oo7-cli lookup application://myapp
oo7-cli search myapp
```

## Note: GNOME keyring coexistence

`acwm-portals.conf` falls back to `gnome-keyring` when oo7 is not installed.
If you replace gnome-keyring entirely, remove it from `extraPortals`/PAM so
only one `org.freedesktop.secrets` provider claims the bus.
