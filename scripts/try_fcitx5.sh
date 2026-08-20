#!/bin/sh

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
build_dir="${XNHEIME_FCITX5_BUILD_DIR:-$repo_root/target/fcitx5}"
trial_root="${XNHEIME_FCITX5_TRIAL_ROOT:-$repo_root/target/fcitx5-trial-root}"
action="${1:-start}"

usage() {
    cat <<EOF
Usage: $0 [start|foreground|restore]

  start       Build, stage, and restart fcitx5 with the development addon.
  foreground  Build and run fcitx5 in the foreground for debugging.
  restore     Restart fcitx5 without the development addon.

Overrides:
  XNHEIME_FCITX5_BUILD_DIR  CMake build directory
  XNHEIME_FCITX5_TRIAL_ROOT Staging directory for the addon
EOF
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: required command was not found: $1" >&2
        exit 127
    fi
}

run_cmake() {
    if command -v cmake >/dev/null 2>&1 && command -v cargo >/dev/null 2>&1; then
        cmake "$@"
        return
    fi

    require_command nix
    nix develop "$repo_root" --command cmake "$@"
}

build_and_stage() {
    run_cmake \
        -S "$repo_root/platform/fcitx5" \
        -B "$build_dir" \
        -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DXNHEIME_CARGO_PROFILE=release \
        -DXNHEIME_DICTIONARY_EDITOR_COMMAND="$build_dir/cargo-target/release/xnheime-dict-editor"
    run_cmake --build "$build_dir"

    mkdir -p \
        "$trial_root/lib/fcitx5" \
        "$trial_root/share/fcitx5/addon" \
        "$trial_root/share/fcitx5/inputmethod"
    cp "$build_dir/xnheime.so" "$trial_root/lib/fcitx5/"
    cp "$build_dir/xnheime-addon.conf" \
        "$trial_root/share/fcitx5/addon/xnheime.conf"
    cp "$repo_root/platform/fcitx5/xnheime.conf" \
        "$trial_root/share/fcitx5/inputmethod/"
}

start_fcitx() {
    mode="$1"
    addon_dirs="$trial_root/lib/fcitx5"
    data_dirs="$trial_root/share/fcitx5"
    if [ -n "${FCITX_ADDON_DIRS:-}" ]; then
        addon_dirs="$addon_dirs:$FCITX_ADDON_DIRS"
    fi
    if [ -n "${FCITX_DATA_DIRS:-}" ]; then
        data_dirs="$data_dirs:$FCITX_DATA_DIRS"
    fi

    if [ "$mode" = foreground ]; then
        command -v fcitx5-remote >/dev/null 2>&1 && fcitx5-remote -e || true
        echo "Starting fcitx5 in the foreground; press Ctrl-C to stop." >&2
        FCITX_ADDON_DIRS="$addon_dirs" \
        FCITX_DATA_DIRS="$data_dirs" \
        FCITX_LOG_LEVEL="${FCITX_LOG_LEVEL:-debug}" \
            exec fcitx5
    fi

    FCITX_ADDON_DIRS="$addon_dirs" \
    FCITX_DATA_DIRS="$data_dirs" \
        fcitx5 -rd
    echo "Development addon started from: $trial_root"
    echo "Open fcitx5-configtool and add Xnheime / 萧何输入法."
    echo "Restore the normal daemon with: $0 restore"
}

case "$action" in
    start)
        require_command fcitx5
        build_and_stage
        start_fcitx start
        ;;
    foreground)
        require_command fcitx5
        build_and_stage
        start_fcitx foreground
        ;;
    restore)
        require_command fcitx5
        env -u FCITX_ADDON_DIRS -u FCITX_DATA_DIRS fcitx5 -rd
        echo "fcitx5 restarted without the development addon."
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
