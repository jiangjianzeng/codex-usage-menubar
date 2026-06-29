#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.1.7}"
ARCH="${ARCH:-macos-arm64}"
APP="$ROOT/.build/release/CodexUsageBar.app"
DIST="$ROOT/.build/dist"
STAGE="$ROOT/.build/dmg-stage"
DMG="$DIST/codex-usage-menubar-v${VERSION}-${ARCH}.dmg"

if [[ ! -d "$APP" ]]; then
  "$ROOT/scripts/build-app.sh"
fi

rm -rf "$STAGE"
mkdir -p "$DIST" "$STAGE"

cp -R "$APP" "$STAGE/Codex Usage Menubar.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
  -volname "Codex Usage Menubar" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG" >/dev/null

shasum -a 256 "$DMG" > "$DMG.sha256"

echo "$DMG"
