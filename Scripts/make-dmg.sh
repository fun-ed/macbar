#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/macbar.app"
OUT="dist"
FINAL="$OUT/macbar-0.1.1-arm64.dmg"
mkdir -p "$OUT"
rm -f "$OUT"/*.dmg

if npx --yes create-dmg "$APP" "$OUT" --overwrite; then
    mv "$OUT/macbar 0.1.0.dmg" "$FINAL"
else
    echo "create-dmg failed, falling back to hdiutil" >&2
    rm -f "$OUT/macbar "*.dmg
    STAGING="$(mktemp -d)"
    cp -R "$APP" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"
    hdiutil create -volname macbar -srcfolder "$STAGING" -ov -format UDZO -quiet "$FINAL"
    rm -rf "$STAGING"
fi
echo "DMG ready: $FINAL"
