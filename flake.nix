{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    # Pinned oo7 (Secret Service provider) for the session integration.
    # Must stay in lockstep with nixpkgs `oo7-pam` (see nix/oo7.nix).
    oo7 = {
      url = "github:linux-credentials/oo7/0.6.0";
      flake = false;
    };
  };

  outputs =
    {
      self,
      flake-parts,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.flake-parts.flakeModules.easyOverlay
      ];

      flake = {
        hmModules.acwm = import ./nix/hm-modules.nix self;
        nixosModules.acwm = import ./nix/nixos-modules.nix self;
      };

      perSystem =
        {
          config,
          pkgs,
          ...
        }:
        let
          inherit (pkgs) callPackage;
          acwm = callPackage ./nix {
            scenefx = pkgs.scenefx;
          };
          oo7 = callPackage ./nix/oo7.nix {
            src = inputs.oo7;
          };
        in
        {
          packages.default = acwm;
          overlayAttrs = {
            inherit (config.packages) acwm oo7;
          };
          packages = {
            inherit acwm oo7;
            hm-options-json = pkgs.callPackage (import ./nix/generate-options.nix self) {
              module = ./nix/hm-modules.nix;
              optionPrefix = "wayland.windowManager.acwm.";
            };
            nixos-options-json = pkgs.callPackage (import ./nix/generate-options.nix self) {
              module = ./nix/nixos-modules.nix;
              optionPrefix = "programs.acwm.";
            };
          };
          devShells.default = pkgs.mkShell {
            # Reuse the package's nativeBuildInputs/buildInputs (zig,
            # pkg-config, wayland-scanner, wlroots, scenefx, ...) so the shell
            # stays in sync with the build derivation.
            inputsFrom = [ acwm ];

            packages = with pkgs; [
              clang
              clang-tools
              ccache
              gdb
              git
              zig
            ];

            shellHook = ''
              echo "acwm dev shell"
              echo "  zig build              # full build (compositor + clients)"
              echo "  zig build test         # all Zig unit tests"
            '';
          };
          formatter = pkgs.nixfmt;
        };
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    };
}
