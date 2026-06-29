{
  description = "Xnheime input methods";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
        };
        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          targets = [
            "aarch64-apple-ios"
            "aarch64-apple-ios-sim"
          ];
        };
        macosToolPath = pkgs.lib.makeBinPath [
          rustToolchain
        ];
        macosBuild = pkgs.writeShellScript "xnheime-macos-build" ''
          set -euo pipefail
          export PATH="${macosToolPath}:$PATH"
          exec ${pkgs.python3}/bin/python3 scripts/macos.py build "$@"
        '';
        macosInstallSystem = pkgs.writeShellScript "xnheime-macos-install-system" ''
          set -euo pipefail
          export PATH="${macosToolPath}:$PATH"
          exec ${pkgs.python3}/bin/python3 scripts/macos.py install-system "$@"
        '';
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            git
            python3
            rustToolchain
          ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
            fcitx5
          ];

          shellHook = ''
            echo "xnheime dev shell"
            if [[ "$(uname -s)" == "Darwin" ]] && ! command -v xcrun >/dev/null; then
              echo "warning: macOS InputMethodKit builds need Xcode Command Line Tools (xcrun)."
            fi
          '';
        };

        apps = pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
          macos-build = {
            type = "app";
            program = "${macosBuild}";
          };

          macos-install-system = {
            type = "app";
            program = "${macosInstallSystem}";
          };
        };

        formatter = pkgs.nixpkgs-fmt;
      });
}
