#!/bin/zsh
# Builds SpaceName and assembles build/SpaceName.app.
# Usage: scripts/build_app.sh [debug|release]   (default: release)
set -euo pipefail

CONFIG="${1:-release}"
ROOT="${0:A:h:h}"
APP="$ROOT/build/SpaceName.app"

cd "$ROOT"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ "$CONFIG" == release ]]; then
    # Universal binary so the app runs on both Apple silicon and Intel Macs.
    BINS=()
    for ARCH in arm64 x86_64; do
        swift build -c release --triple "$ARCH-apple-macosx14.0"
        BINS+=("$(swift build -c release --triple "$ARCH-apple-macosx14.0" --show-bin-path)/SpaceName")
    done
    lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/SpaceName"
else
    # Debug: this Mac's architecture only, for speed.
    swift build -c "$CONFIG"
    cp "$(swift build -c "$CONFIG" --show-bin-path)/SpaceName" "$APP/Contents/MacOS/SpaceName"
fi
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Signing identity: $SIGN_IDENTITY, else a "SpaceName Dev" certificate if one exists,
# else ad-hoc. An ad-hoc signature changes on every rebuild, which makes macOS forget
# the Accessibility grant; a real (even self-signed) certificate keeps it across rebuilds.
IDENTITY="${SIGN_IDENTITY:-}"
# No -v: a self-signed certificate isn't system-trusted, but codesign can still use it.
if [[ -z "$IDENTITY" ]] && security find-identity -p codesigning | grep -q '"SpaceName Dev"'; then
    IDENTITY="SpaceName Dev"
fi
codesign --force --sign "${IDENTITY:--}" "$APP"
[[ -z "$IDENTITY" ]] && echo "Signed ad-hoc: Accessibility permission will not survive rebuilds (see README)."

echo "Built $APP"
