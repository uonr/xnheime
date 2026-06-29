#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository_root"

configuration="${1:-Debug}"
device="${XNHEIME_IOS_TEST_DEVICE:-iPhone 17 Pro}"

"$repository_root/scripts/build_ios_core.sh" "$configuration" simulator

xcodebuild \
    -project platform/ios/Xnheime.xcodeproj \
    -scheme Xnheime \
    -configuration "$configuration" \
    -derivedDataPath target/ios-derived \
    -destination "platform=iOS Simulator,name=$device" \
    test
