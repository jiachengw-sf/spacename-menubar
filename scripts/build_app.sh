#!/bin/zsh
# Builds SpaceName and assembles build/SpaceName.app.
# Usage: scripts/build_app.sh [debug|release]   (default: release)
set -euo pipefail

CONFIG="${1:-release}"
ROOT="${0:A:h:h}"
APP="$ROOT/build/SpaceName.app"

cd "$ROOT"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/SpaceName"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SpaceName"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

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
