#!/bin/sh

set -eu

DEVELOPER_DIR="${XNHEIME_DEVELOPER_DIR:?XNHEIME_DEVELOPER_DIR is required}" \
    exec /usr/bin/xcrun --sdk "${APPLE_SDK:?APPLE_SDK is required}" clang "$@"
