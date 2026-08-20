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
        rustPlatform = pkgs.makeRustPlatform {
          cargo = rustToolchain;
          rustc = rustToolchain;
        };
        fcitx5Xnheime = rustPlatform.buildRustPackage {
          pname = "fcitx5-xnheime";
          version = "0.1.0";
          src = pkgs.lib.fileset.toSource {
            root = ./.;
            fileset = pkgs.lib.fileset.unions [
              ./Cargo.lock
              ./Cargo.toml
              ./crates
              ./data
              ./platform/fcitx5
            ];
          };

          cargoLock.lockFile = ./Cargo.lock;
          nativeBuildInputs = with pkgs; [
            cmake
            ninja
            pkg-config
          ];
          buildInputs = with pkgs; [
            fcitx5
            (lib.getDev fcitx5)
            gtk4
          ];

          configurePhase = ''
            runHook preConfigure
            cmake -S platform/fcitx5 -B build -G Ninja \
              -DCMAKE_BUILD_TYPE=Release \
              -DCMAKE_INSTALL_PREFIX="$out" \
              -DXNHEIME_CARGO_PROFILE=release
            runHook postConfigure
          '';
          buildPhase = ''
            runHook preBuild
            cmake --build build
            runHook postBuild
          '';
          checkPhase = ''
            runHook preCheck
            ctest --test-dir build --output-on-failure
            cargo test --offline \
              -p xnheime-core -p xnheime-cxx -p xnheime-dict-editor
            runHook postCheck
          '';
          installPhase = ''
            runHook preInstall
            cmake --install build
            runHook postInstall
          '';

          doCheck = true;
          strictDeps = true;
          meta = {
            description = "Xnheime input method addon for Fcitx 5";
            homepage = "https://github.com/uonr/xnheime";
            license = pkgs.lib.licenses.mit;
            platforms = pkgs.lib.platforms.linux;
          };
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
        packages = pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
          default = fcitx5Xnheime;
          fcitx5-xnheime = fcitx5Xnheime;
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            cmake
            git
            ninja
            pkg-config
            python3
            rustToolchain
          ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
            fcitx5
            (lib.getDev fcitx5)
            gtk4
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
