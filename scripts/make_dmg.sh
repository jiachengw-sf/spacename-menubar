#!/bin/zsh
# Packages build/SpaceName.app into build/SpaceName-<version>.dmg: a disk image
# whose window shows the app next to an Applications shortcut to drag it onto.
# Usage: scripts/build_app.sh && scripts/make_dmg.sh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/build/SpaceName.app"
[[ -d "$APP" ]] || { echo "Build the app first: scripts/build_app.sh" >&2; exit 1; }

VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
DMG="$ROOT/build/SpaceName-$VERSION.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "SpaceName $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
echo "Built $DMG"
