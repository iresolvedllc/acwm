# oo7 — Secret Service provider (pinned fork-agnostic integration package).
#
# Packages the parts nixpkgs does not ship (oo7-daemon, portal registration is
# separate) from the pinned upstream tag, with all components built from the
# SAME source so the PAM<->daemon socket protocol and portal bus names always
# match. nixpkgs already provides `oo7-pam` (used by the built-in
# `security.pam.services.<name>.oo7` option) and `oo7` (client lib) at the same
# version — when bumping the pin here, check that nixpkgs `oo7-pam` matches.
{
  lib,
  rustPlatform,
  src,
  version ? "0.6.0",
}:

rustPlatform.buildRustPackage {
  pname = "oo7";
  inherit version;

  inherit src;
  cargoLock.lockFile = "${src}/Cargo.lock";

  # Only the session-side components; the client library and credential
  # helpers (cargo-credential, git-credential, python bindings) are nixpkgs'
  # job and stay out of this closure.
  cargoBuildFlags = [
    "-p"
    "oo7-daemon"
    "-p"
    "oo7-portal"
    "-p"
    "oo7-cli"
  ];

  # Tests need a running session bus / daemon.
  doCheck = false;

  postInstall = ''
    # --- systemd user units (upstream hardening preserved) ---
    substitute ${src}/server/data/oo7-daemon.service.in \
      $out/lib/systemd/user/oo7-daemon.service \
      --subst-var-by binary oo7-daemon \
      --subst-var-by libexecdir $out/bin

    substitute ${src}/portal/data/oo7-portal.service.in \
      $out/lib/systemd/user/oo7-portal.service \
      --subst-var-by dbus_name org.freedesktop.impl.portal.desktop.oo7 \
      --subst-var-by bin_name oo7-portal \
      --subst-var-by libexecdir $out/bin

    ln -s oo7-portal.service \
      $out/lib/systemd/user/dbus-org.freedesktop.impl.portal.desktop.oo7.service

    # --- dbus session activation files (as upstream installs them) ---
    substitute ${src}/server/data/org.freedesktop.secrets.service.in \
      $out/share/dbus-1/services/org.freedesktop.secrets.service \
      --subst-var-by dbus_known_name org.freedesktop.secrets

    substitute ${src}/portal/data/org.freedesktop.impl.portal.desktop.oo7.service.in \
      $out/share/dbus-1/services/org.freedesktop.impl.portal.desktop.oo7.service \
      --subst-var-by dbus_name org.freedesktop.impl.portal.desktop.oo7

    # --- portal registration ---
    substitute ${src}/portal/data/oo7-portal.portal.in \
      $out/share/xdg-desktop-portal/portals/oo7.portal \
      --subst-var-by dbus_name org.freedesktop.impl.portal.desktop.oo7

    substitute ${src}/portal/data/oo7-portal.desktop.in \
      $out/share/applications/oo7-portal.desktop \
      --subst-var-by bin_name oo7-portal \
      --subst-var-by libexecdir $out/bin
  '';

  meta = with lib; {
    description = "Secret Service provider: oo7-daemon (org.freedesktop.secrets), secret portal backend and CLI";
    homepage = "https://github.com/linux-credentials/oo7";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "oo7-cli";
  };
}
