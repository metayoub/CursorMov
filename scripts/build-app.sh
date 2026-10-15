#!/usr/bin/env bash
# Builds CursorMov.app (universal: Apple silicon + Intel) into ./build.
set -euo pipefail

cd "$(dirname "$0")/.."
arch_flags=(--arch arm64 --arch x86_64)
swift build -c release "${arch_flags[@]}"

app="build/CursorMov.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$(swift build -c release "${arch_flags[@]}" --show-bin-path)/CursorMov" "$app/Contents/MacOS/CursorMov"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
# Ad-hoc by default. For local testing, set CODESIGN_IDENTITY to a certificate
# so macOS keeps the Accessibility permission across rebuilds.
codesign --force --sign "${CODESIGN_IDENTITY:--}" "$app"

echo "Built $(pwd)/$app"
