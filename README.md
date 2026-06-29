# 萧何输入法

简单的小鹤音形输入法。支持多个平台。

## Layout

- `crates/xnheime-core`: shared Rust input engine crate.
- `data/flypy`: vendored 小鹤音形 Rime 码表快照。
- `platform/macos`: macOS Swift frontend.
- `flake.nix`: development shell and Xcode build/install app entry points.

## Dictionary data

This repository vendors a minimal snapshot from `cubercsl/rime-flypy` instead
of using a git submodule or Nix flake input. That keeps the dictionary available
to plain Cargo/Xcode builds without requiring network access during normal
builds.

The snapshot source is recorded in `data/flypy/SOURCE`. Refresh it with:

```sh
python3 scripts/update_flypy.py
```

The Rust core reads the enabled import tables from the vendored snapshot at compile
time and embeds them into the static library.

## macOS smoke test

### Xcode build

The repository does not store a `DEVELOPMENT_TEAM`. The Nix build commands
read the first local `Apple Development` certificate and use its Team ID by
default. To override that choice, set:

```sh
export XNHEIME_DEVELOPMENT_TEAM=YOURTEAMID
```

For a reproducible command-line Xcode build:

```sh
nix run .#macos-build
```

or run the helper script directly:

```sh
python3 scripts/macos.py build
```

or run Xcode directly:

```sh
xcodebuild \
  -project platform/macos/Xnheime.xcodeproj \
  -scheme Xnheime \
  -configuration Release \
  -derivedDataPath target/xcode-derived \
  -destination 'platform=macOS,arch=arm64' \
  DEVELOPMENT_TEAM=YOURTEAMID \
  build
```

Install the Xcode-built app system-wide:

```sh
nix run .#macos-install-system
```

or:

```sh
python3 scripts/macos.py install-system
```

The install command builds in a temporary DerivedData directory, copies the app
to `/Library/Input Methods`, removes transient app bundles, and restarts
`TextInputMenuAgent`. It refuses to install an ad-hoc signed app because macOS
can show those in Settings while refusing to switch to them.

After installing, log out and back in, or restart the text input menu agent:

```sh
killall TextInputMenuAgent
```

Then enable `萧何输入法` in macOS Keyboard input source settings.
