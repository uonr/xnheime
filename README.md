# 萧何输入法

简单的小鹤音形输入法。支持多个平台。

## Layout

- `crates/xnheime-core`: shared Rust input engine crate.
- `data/flypy`: vendored 小鹤音形 Rime 码表快照。
- `platform/macos`: macOS 14+ Swift frontend.
- `platform/ios`: iOS 17+ container app and custom keyboard extension.
- `flake.nix`: optional reproducible development shell and macOS command wrappers.

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

Install a full Xcode distribution and a Rust toolchain from
[rustup](https://rustup.rs/). Build the Rust/UniFFI artifacts before opening
Xcode:

```sh
scripts/build_rust_core.sh Debug
```

Then open `platform/macos/Xnheime.xcodeproj` and build normally. The Xcode
project only consumes the artifacts under `target/xcode/Debug`; it never runs
Cargo. Use `Release` instead of `Debug` when building the Release
configuration. Nix is not required.

The repository does not store a `DEVELOPMENT_TEAM`. The Nix build commands
read the first local `Apple Development` certificate and use its Team ID by
default. To override that choice, set:

```sh
export XNHEIME_DEVELOPMENT_TEAM=YOURTEAMID
```

For a command-line Xcode build without Nix:

```sh
python3 scripts/macos.py build
```

The equivalent direct `xcodebuild` invocation is:

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

Nix remains available as an optional pinned development environment:

```sh
nix develop
nix run .#macos-build
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

## iOS Simulator

Build the Rust/UniFFI artifacts independently of Xcode:

```sh
scripts/build_ios_core.sh Debug simulator
```

Then open `platform/ios/Xnheime.xcodeproj`, select an iPhone Simulator, and run
the `Xnheime` scheme. In the simulated device, add the keyboard under
Settings → General → Keyboard → Keyboards → Add New Keyboard, then use the test
field in the container app. The extension works without Full Access.

For a device archive, build the matching artifacts first:

```sh
scripts/build_ios_core.sh Release device
```

The Nix development shell includes both Apple Rust targets. With a native
rustup installation, install them once with:

```sh
rustup target add aarch64-apple-ios-sim aarch64-apple-ios
```
