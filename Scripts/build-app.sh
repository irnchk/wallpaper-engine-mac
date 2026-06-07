#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/app"
APP_NAME="Wallpaper Engine Mac"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MACOS_DIR"

swift build --package-path "$ROOT_DIR" -c release
rm -rf "$BUILD_DIR/WallpaperEngineMac.app"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/.build/release/WallpaperEngineMac" "$MACOS_DIR/WallpaperEngineMac"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleExecutable</key>
  <string>WallpaperEngineMac</string>
  <key>CFBundleIdentifier</key>
  <string>local.wallpaper-engine-mac</string>
  <key>CFBundleName</key>
  <string>Wallpaper Engine Mac</string>
  <key>CFBundleDisplayName</key>
  <string>Wallpaper Engine Mac</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSScreenCaptureUsageDescription</key>
  <string>Wallpaper Engine Mac captures a tiny desktop stream so audio responsive wallpapers can react to system audio.</string>
  <key>NSAudioCaptureUsageDescription</key>
  <string>Wallpaper Engine Mac captures system audio levels to animate audio responsive wallpapers.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Wallpaper Engine Mac does not record the microphone, but macOS may show this permission alongside system audio capture.</string>
</dict>
</plist>
PLIST

SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Apple Development|Developer ID Application/ { print $2; exit }')"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="-"
fi

codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR" >/dev/null

echo "$APP_DIR"
