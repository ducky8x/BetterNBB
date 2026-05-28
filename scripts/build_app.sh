#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="BetterNBB"
VERSION="1.0.0"
BUNDLE_ID="com.joowon.betternbb"

OUTPUT_DIR="/Users/joowon/Projects/App Outputs"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
MODULE_CACHE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/betternbb-module-cache.XXXXXX")"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/betternbb-build.XXXXXX")"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/betternbb-app.XXXXXX")"
STAGING_APP_DIR="$STAGING_DIR/$APP_NAME.app"
CONTENTS_DIR="$STAGING_APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
MIN_MACOS="12.0"
trap 'rm -rf "$MODULE_CACHE_DIR" "$BUILD_DIR" "$STAGING_DIR"' EXIT

rm -rf "$OUTPUT_DIR/$APP_NAME-$VERSION-macOS.zip" "$OUTPUT_DIR/ModuleCache"
mkdir -p "$MACOS_DIR" "$MODULE_CACHE_DIR"

swiftc "$ROOT_DIR/BetterNBB.swift" \
  -o "$BUILD_DIR/$APP_NAME-arm64" \
  -target "arm64-apple-macos$MIN_MACOS" \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -framework AppKit \
  -framework Foundation

swiftc "$ROOT_DIR/BetterNBB.swift" \
  -o "$BUILD_DIR/$APP_NAME-x86_64" \
  -target "x86_64-apple-macos$MIN_MACOS" \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -framework AppKit \
  -framework Foundation

lipo -create \
  "$BUILD_DIR/$APP_NAME-arm64" \
  "$BUILD_DIR/$APP_NAME-x86_64" \
  -output "$MACOS_DIR/$APP_NAME"

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
  <string>$MIN_MACOS</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

find "$STAGING_APP_DIR" -name $'Icon\r' -delete
xattr -cr "$STAGING_APP_DIR"
codesign --force --deep --sign - "$STAGING_APP_DIR"

rm -rf "$APP_DIR"
mv "$STAGING_APP_DIR" "$APP_DIR"

echo "Built $APP_DIR"
