#!/bin/bash
# Checks the Home Screen widget's picture preparation (ios/DailyWidget/DailyPicture.swift) on an iOS
# simulator: builds tools/dev/widget_picture_check.swift with it for the simulator and runs it there.
#
#   tools/dev/widget_picture_check.sh <simulator udid> [picture.jpg]
#
# With a picture, the prepared widget images are written next to it as PNG files. The simulator must be
# booted. Nothing is installed and nothing is read from the network.
set -euo pipefail
udid=${1:?usage: widget_picture_check.sh <simulator udid> [picture.jpg]}
root=$(cd "$(dirname "$0")/../.." && pwd)
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
# Top-level code must live in main.swift when a module has more than one file.
cp "$root/tools/dev/widget_picture_check.swift" "$out/main.swift"
xcrun -sdk iphonesimulator swiftc -O -target arm64-apple-ios17.0-simulator \
  "$root/ios/DailyWidget/DailyPicture.swift" "$out/main.swift" \
  -o "$out/widget_picture_check"
xcrun simctl spawn "$udid" "$out/widget_picture_check" ${2:+"$2"}
