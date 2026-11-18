self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.acwm;
in
{
  disabledModules = [ "programs/wayland/acwm.nix" ];

  options = {
    programs.acwm = {
      enable = lib.mkEnableOption "acwm, a wayland compositor based on dwl";
      addLoginEntry = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to add a login entry to the display manager for acwm. Only has effect if a display manager is configured (e.g. SDDM, GDM via `services.displayManager`).";
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.acwm;
        description = "The acwm package to use";
      };
      oo7 = {
        enable = lib.mkEnableOption ''
          oo7 Secret Service integration: a session keyring daemon
          (org.freedesktop.secrets), the secret portal backend and
          keyring unlock at login via `pam_oo7`.
        '';
        package = lib.mkOption {
          type = lib.types.package;
          default = self.packages.${pkgs.stdenv.hostPlatform.system}.oo7;
          defaultText = lib.literalExpression "self.packages.\${pkgs.stdenv.hostPlatform.system}.oo7";
          description = "The oo7 package providing oo7-daemon, the secret portal backend and oo7-cli.";
        };
        pamServices = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "sddm"
            "login"
          ];
          description = ''
            PAM services that unlock the user's keyring at login via the
            built-in `security.pam.services.<name>.oo7` wiring (which places
            `pam_oo7` after password entry in the auth stack).
          '';
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
    ] ++ lib.optional cfg.oo7.enable cfg.oo7.package;

    # Register oo7's systemd user units (daemon + secret portal) with the
    # user manager so dbus SystemdService activation resolves. The daemon
    # unit stays dormant until dbus activation requests it.
    systemd.packages = lib.optional cfg.oo7.enable cfg.oo7.package;

    xdg.portal = {
      enable = lib.mkDefault true;

      config = {
        acwm = {
          default = [
            "gtk"
          ];
          # except those
          "org.freedesktop.impl.portal.Secret" =
            lib.optionals cfg.oo7.enable [ "oo7" ]
            ++ lib.optionals (!cfg.oo7.enable) [ "gnome-keyring" ];
          "org.freedesktop.impl.portal.ScreenCast" = [ "wlr" ];
          # acwm-portal (screenshot) is part of the acwm package; wlr stays as
          # a fallback for packages built without libsystemd.
          "org.freedesktop.impl.portal.Screenshot" = [ "acwm" "wlr" ];

          # wlr does not have this interface
          "org.freedesktop.impl.portal.Inhibit" = [ ];
        };
      };
      extraPortals =
        with pkgs;
        [
          xdg-desktop-portal-wlr
          xdg-desktop-portal-gtk
        ]
        ++ lib.optional cfg.oo7.enable cfg.oo7.package;

      wlr.enable = lib.mkDefault true;

      configPackages = [ cfg.package ];
    };

    # Keyring unlock at login for the configured PAM services. Uses the
    # nixpkgs-maintained oo7 PAM rule placement (correct position after
    # password entry) — nixpkgs' `oo7-pam` must match our pinned oo7.
    security.pam.services = lib.listToAttrs (
      map (name: lib.nameValuePair name { oo7.enable = lib.mkDefault true; }) cfg.oo7.pamServices
    );

    security.polkit.enable = lib.mkDefault true;

    programs.xwayland.enable = lib.mkDefault true;

    services = {
      displayManager.sessionPackages = lib.mkIf cfg.addLoginEntry [ cfg.package ];

      graphical-desktop.enable = lib.mkDefault true;
    };
  };
}
