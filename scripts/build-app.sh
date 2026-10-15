#!/usr/bin/env bash
# Builds CursorMov.app into ./build.
set -euo pipefail

cd "$(dirname "$0")/.."
swift build -c release

app="build/CursorMov.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/CursorMov" "$app/Contents/MacOS/CursorMov"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"

echo "Built $(pwd)/$app"
