#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_binary="${TMPDIR:-/tmp}/xnheime-keyboard-event-policy-tests"

xcrun swiftc \
    "$repository_root/platform/macos/Sources/KeyboardEventPolicy.swift" \
    "$repository_root/platform/macos/Tests/KeyboardEventPolicyTests.swift" \
    -o "$test_binary"
"$test_binary"
