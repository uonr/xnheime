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
    command -v cargo
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
configuration="${1:-Debug}"
platform="${2:-simulator}"
cargo_target_dir="${CARGO_TARGET_DIR:-$repo_root/target/cargo-ios}"

case "$configuration" in
    Debug) cargo_profile_dir=debug; cargo_profile_args= ;;
    Release) cargo_profile_dir=release; cargo_profile_args=--release ;;
    *) echo "error: expected Debug or Release" >&2; exit 2 ;;
esac

case "$platform" in
    simulator)
        rust_target=aarch64-apple-ios-sim
        swift_target=arm64-apple-ios17.0-simulator
        sdk=iphonesimulator
        ;;
    device)
        rust_target=aarch64-apple-ios
        swift_target=arm64-apple-ios17.0
        sdk=iphoneos
        ;;
    *) echo "error: expected simulator or device" >&2; exit 2 ;;
esac

output_dir="${RUST_OUTPUT_DIR:-$repo_root/target/xcode/ios-$platform/$configuration}"
apple_developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
cargo_bin=$(find_cargo) || {
    echo "error: Cargo was not found; install Rust with rustup" >&2
    exit 127
}

run_cargo() {
    if [ "${cargo_bin#/nix/store/}" != "$cargo_bin" ]; then
        set -- nix develop "$repo_root" --command cargo "$@"
    else
        set -- "$cargo_bin" "$@"
    fi
    env -u AR -u CC -u CXX -u LD -u SDKROOT \
        APPLE_SDK="$sdk" \
        XNHEIME_DEVELOPER_DIR="$apple_developer_dir" \
        CARGO_TARGET_DIR="$cargo_target_dir" "$@"
}

mkdir -p "$output_dir"
cd "$repo_root"

DEVELOPER_DIR="$apple_developer_dir" \
CARGO_TARGET_AARCH64_APPLE_IOS_SIM_LINKER="$script_dir/apple_clang.sh" \
CARGO_TARGET_AARCH64_APPLE_IOS_LINKER="$script_dir/apple_clang.sh" \
    run_cargo build $cargo_profile_args -p xnheime-uniffi --target "$rust_target"

# Bindgen is a host tool. Generate bindings from the host dynamic library.
run_cargo build $cargo_profile_args -p xnheime-uniffi
run_cargo run $cargo_profile_args -p xnheime-uniffi --features bindgen \
    --bin uniffi-bindgen -- generate \
    --library "$cargo_target_dir/$cargo_profile_dir/libxnheime_uniffi.dylib" \
    --language swift --no-format --out-dir "$output_dir"

cp "$cargo_target_dir/$rust_target/$cargo_profile_dir/libxnheime_uniffi.a" "$output_dir/"

xcrun --sdk "$sdk" swiftc \
    -swift-version 6 \
    -target "$swift_target" \
    -sdk "$(xcrun --sdk "$sdk" --show-sdk-path)" \
    -parse-as-library -emit-library -static -emit-module \
    -module-name XnheimeCore \
    -import-objc-header "$output_dir/xnheime_uniffiFFI.h" \
    "$output_dir/xnheime_uniffi.swift" \
    -emit-module-path "$output_dir/XnheimeCore.swiftmodule" \
    -o "$output_dir/libXnheimeCore.a"

echo "iOS core artifacts: $output_dir"
