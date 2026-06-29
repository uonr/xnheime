#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_temp=$(mktemp -d "${TMPDIR:-/tmp}/xnheime-uniffi-core.XXXXXX")
bindings_dir="$test_temp/bindings"
swift_module_dir="$test_temp/swift-module"
rust_library="$repository_root/target/debug/libxnheime_uniffi.dylib"

mkdir -p "$bindings_dir" "$swift_module_dir"

cd "$repository_root"
nix develop "$repository_root" --command cargo build -p xnheime-uniffi --features bindgen
nix develop "$repository_root" --command cargo run \
    -p xnheime-uniffi \
    --features bindgen \
    --bin uniffi-bindgen \
    -- generate \
    --library "$rust_library" \
    --language swift \
    --no-format \
    --out-dir "$bindings_dir"

CLANG_MODULE_CACHE_PATH="$test_temp/clang-cache" xcrun swiftc \
    -swift-version 6 \
    -parse-as-library \
    -emit-library \
    -emit-module \
    -module-name XnheimeCore \
    -import-objc-header "$bindings_dir/xnheime_uniffiFFI.h" \
    "$bindings_dir/xnheime_uniffi.swift" \
    -L "$repository_root/target/debug" \
    -lxnheime_uniffi \
    -Xlinker -rpath \
    -Xlinker "$repository_root/target/debug" \
    -emit-module-path "$swift_module_dir/XnheimeCore.swiftmodule" \
    -o "$swift_module_dir/libXnheimeCore.dylib"

CLANG_MODULE_CACHE_PATH="$test_temp/clang-cache" xcrun swiftc \
    -swift-version 6 \
    -default-isolation MainActor \
    -parse-as-library \
    "$repository_root/platform/macos/Tests/UniFFICoreTests.swift" \
    -I "$swift_module_dir" \
    -L "$swift_module_dir" \
    -lXnheimeCore \
    -Xlinker -rpath \
    -Xlinker "$swift_module_dir" \
    -o "$test_temp/UniFFICoreTests"

"$test_temp/UniFFICoreTests"
