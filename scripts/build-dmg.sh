#!/usr/bin/env bash
# Builds an unsigned, drag-to-install DMG for a GitHub release into ./build.
set -euo pipefail

cd "$(dirname "$0")/.."
scripts/build-app.sh

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
dmg="build/CursorMov-$version.dmg"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

cp -R build/CursorMov.app "$staging/"
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
hdiutil create -volname "CursorMov $version" -srcfolder "$staging" -format UDZO -quiet "$dmg"

echo "Built $(pwd)/$dmg"
