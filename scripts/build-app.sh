#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}"
TOOLCHAIN="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr"
SDK="$(ls -d "$DEVELOPER_DIR"/Platforms/MacOSX.platform/Developer/SDKs/MacOSX*.sdk | sort -V | tail -1)"
BUILD="$ROOT/.build/manual"
APP="$ROOT/.build/release/CodexUsageBar.app"
MACOS="$APP/Contents/MacOS"
RESOURCES="$APP/Contents/Resources"
BINARY="$ROOT/.build/release/CodexUsageBar"
VERSION="${VERSION:-0.1.4}"
BUILD_NUMBER="${BUILD_NUMBER:-5}"
ICON_SVG="$ROOT/assets/app-icon.svg"
ICONSET="$BUILD/AppIcon.iconset"
ICON_PNG="$BUILD/AppIcon.png"
ICON_ICNS="$RESOURCES/AppIcon.icns"

mkdir -p "$BUILD" "$MACOS" "$RESOURCES" "$APP/Contents"

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
  -parse-as-library \
  -module-name CodexUsageBar \
  -I "$BUILD" \
  -sdk "$SDK" \
  -target arm64-apple-macosx14.0 \
  "$ROOT/Sources/CodexUsageBar/CodexUsageBar.swift" \
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

if [[ -f "$ICON_SVG" ]]; then
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"

  if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert -w 1024 -h 1024 "$ICON_SVG" -o "$ICON_PNG"
  else
    ICON_RENDER_DIR="$BUILD/icon-render"
    rm -rf "$ICON_RENDER_DIR"
    mkdir -p "$ICON_RENDER_DIR"
    /usr/bin/qlmanage -t -s 1024 -o "$ICON_RENDER_DIR" "$ICON_SVG" >/dev/null 2>&1
    ICON_RENDERED="$(find "$ICON_RENDER_DIR" -name '*.png' -print -quit)"
    cp "$ICON_RENDERED" "$ICON_PNG"
  fi

  for size in 16 32 128 256 512; do
    /usr/bin/sips -z "$size" "$size" "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    /usr/bin/sips -z "$((size * 2))" "$((size * 2))" "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  /usr/bin/iconutil -c icns "$ICONSET" -o "$ICON_ICNS"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Codex Usage Menubar</string>
  <key>CFBundleExecutable</key>
  <string>CodexUsageBar</string>
  <key>CFBundleIdentifier</key>
  <string>com.jiangjianzeng.codex-usage-menubar</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>CodexUsageBar</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --sign - "$BINARY" >/dev/null
/usr/bin/codesign --force --sign - "$MACOS/CodexUsageBar" >/dev/null
/usr/bin/codesign --force --sign - "$APP" >/dev/null
/usr/bin/xattr -cr "$APP" 2>/dev/null || true
/usr/bin/xattr -c "$BINARY" 2>/dev/null || true

echo "$APP"
echo "$BINARY"
