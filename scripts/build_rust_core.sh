#!/bin/sh

set -eu

find_cargo() {
    if [ -n "${CARGO:-}" ] && [ -x "$CARGO" ]; then
        printf '%s\n' "$CARGO"
        return
    fi

    if [ -x "${HOME}/.cargo/bin/cargo" ]; then
        printf '%s\n' "${HOME}/.cargo/bin/cargo"
        return
    fi

    if command -v cargo >/dev/null 2>&1; then
        command -v cargo
        return
    fi

    return 1
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
configuration="${1:-${CONFIGURATION:-Release}}"
output_dir="${RUST_OUTPUT_DIR:-$repo_root/target/xcode/$configuration}"
cargo_target_dir="${CARGO_TARGET_DIR:-$repo_root/target/cargo-xcode}"
deployment_target="${MACOSX_DEPLOYMENT_TARGET:-14.0}"

case "$configuration" in
    Debug)
        cargo_profile_dir=debug
        cargo_profile_args=
        ;;
    Release)
        cargo_profile_dir=release
        cargo_profile_args=--release
        ;;
    *)
        echo "error: unsupported Xcode configuration: $configuration" >&2
        exit 2
        ;;
esac

if ! cargo_bin="$(find_cargo)"; then
    echo "error: Cargo was not found." >&2
    echo "Install Rust with rustup, or set CARGO to the cargo executable." >&2
    exit 127
fi

swift_arch="${CURRENT_ARCH:-}"
if [ -z "$swift_arch" ] || [ "$swift_arch" = "undefined_arch" ]; then
    swift_arch="${NATIVE_ARCH_ACTUAL:-$(uname -m)}"
fi
swift_sdk="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"

mkdir -p "$output_dir"
cd "$repo_root"

# A caller such as scripts/macos.py may carry Xcode's C/Swift linker and SDK
# settings. They can break Cargo host tools and proc macros.
run_cargo() {
    if [ "${cargo_bin#/nix/store/}" != "$cargo_bin" ]; then
        if ! command -v nix >/dev/null 2>&1; then
            echo "error: the selected Cargo belongs to Nix, but nix is not available." >&2
            echo "Install Rust with rustup, or expose nix to this build phase." >&2
            exit 127
        fi
        set -- nix develop "$repo_root" --command cargo "$@"
    else
        set -- "$cargo_bin" "$@"
    fi

    env \
        -u AR \
        -u CC \
        -u CXX \
        -u DEVELOPER_DIR \
        -u DYLD_FRAMEWORK_PATH \
        -u DYLD_LIBRARY_PATH \
        -u LD \
        -u SDKROOT \
        CARGO_TARGET_DIR="$cargo_target_dir" \
        "$@"
}

run_cargo build $cargo_profile_args -p xnheime-uniffi

run_cargo run $cargo_profile_args \
    -p xnheime-uniffi \
    --features bindgen \
    --bin uniffi-bindgen \
    -- generate \
    --library "$cargo_target_dir/$cargo_profile_dir/libxnheime_uniffi.dylib" \
    --language swift \
    --no-format \
    --out-dir "$output_dir"

cp "$cargo_target_dir/$cargo_profile_dir/libxnheime_uniffi.a" "$output_dir/"

xcrun swiftc \
    -swift-version 6 \
    -target "$swift_arch-apple-macos$deployment_target" \
    -sdk "$swift_sdk" \
    -parse-as-library \
    -emit-library \
    -static \
    -emit-module \
    -module-name XnheimeCore \
    -import-objc-header "$output_dir/xnheime_uniffiFFI.h" \
    "$output_dir/xnheime_uniffi.swift" \
    -emit-module-path "$output_dir/XnheimeCore.swiftmodule" \
    -o "$output_dir/libXnheimeCore.a"
