#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="BetterNBB"
VERSION="1.0.0"
BUNDLE_ID="com.joowon.betternbb"

OUTPUT_DIR="/Users/joowon/Projects/App Outputs"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
MODULE_CACHE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/betternbb-module-cache.XXXXXX")"
trap 'rm -rf "$MODULE_CACHE_DIR"' EXIT

rm -rf "$APP_DIR" "$OUTPUT_DIR/$APP_NAME-$VERSION-macOS.zip" "$OUTPUT_DIR/ModuleCache"
mkdir -p "$MACOS_DIR" "$MODULE_CACHE_DIR"

swiftc "$ROOT_DIR/BetterNBB.swift" \
  -o "$MACOS_DIR/$APP_NAME" \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -framework AppKit \
  -framework Foundation

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"

echo "Built $APP_DIR"
