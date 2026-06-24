#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}"
TOOLCHAIN="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr"
SDK="$(ls -d "$DEVELOPER_DIR"/Platforms/MacOSX.platform/Developer/SDKs/MacOSX*.sdk | sort -V | tail -1)"
BUILD="$ROOT/.build/manual"
APP="$ROOT/.build/release/CodexUsageBar.app"
MACOS="$APP/Contents/MacOS"
BINARY="$ROOT/.build/release/CodexUsageBar"

mkdir -p "$BUILD" "$MACOS" "$APP/Contents"

"$TOOLCHAIN/bin/swift-frontend" \
  -c \
  -parse-as-library \
  -module-name CodexUsageCore \
  -emit-module-path "$BUILD/CodexUsageCore.swiftmodule" \
  -sdk "$SDK" \
  -target arm64-apple-macosx14.0 \
  "$ROOT/Sources/CodexUsageCore/CodexUsageReader.swift" \
  -o "$BUILD/CodexUsageReader.o"

"$TOOLCHAIN/bin/swift-frontend" \
  -c \
  -module-name CodexUsageBar \
  -I "$BUILD" \
  -sdk "$SDK" \
  -target arm64-apple-macosx14.0 \
  "$ROOT/Sources/CodexUsageBar/main.swift" \
  -o "$BUILD/main.o"

"$TOOLCHAIN/bin/clang" \
  -target arm64-apple-macosx14.0 \
  -isysroot "$SDK" \
  "$BUILD/CodexUsageReader.o" \
  "$BUILD/main.o" \
  -L "$TOOLCHAIN/lib/swift/macosx" \
  -rpath /usr/lib/swift \
  -framework AppKit \
  -framework Foundation \
  -lswiftCore \
  -lswiftFoundation \
  -lswiftDispatch \
  -lswiftCoreFoundation \
  -o "$BINARY"

cp "$BINARY" "$MACOS/CodexUsageBar"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>CodexUsageBar</string>
  <key>CFBundleIdentifier</key>
  <string>local.codex-usage-bar</string>
  <key>CFBundleName</key>
  <string>CodexUsageBar</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --sign - "$APP" >/dev/null
/usr/bin/codesign --force --sign - "$BINARY" >/dev/null
/usr/bin/xattr -cr "$APP" 2>/dev/null || true
/usr/bin/xattr -c "$BINARY" 2>/dev/null || true

echo "$APP"
echo "$BINARY"
