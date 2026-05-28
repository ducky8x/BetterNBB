#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
  SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
  LINK_TARGET="$(readlink "$SCRIPT_PATH")"
  if [[ "$LINK_TARGET" == /* ]]; then
    SCRIPT_PATH="$LINK_TARGET"
  else
    SCRIPT_PATH="$SCRIPT_DIR/$LINK_TARGET"
  fi
done

ROOT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")/.." && pwd)"
MIN_MACOS="12.0"

prompt() {
  local label="$1"
  local default_value="${2:-}"
  local answer

  if [[ -n "$default_value" ]]; then
    read -r -p "$label [$default_value]: " answer
    printf '%s\n' "${answer:-$default_value}"
  else
    read -r -p "$label: " answer
    printf '%s\n' "$answer"
  fi
}

expand_path() {
  local value="$1"

  if [[ "$value" == "~" ]]; then
    printf '%s\n' "$HOME"
  elif [[ "$value" == ~/* ]]; then
    printf '%s\n' "$HOME/${value#~/}"
  else
    printf '%s\n' "$value"
  fi
}

sanitize_app_name() {
  local value="$1"

  value="${value%.app}"
  value="${value//:/-}"
  printf '%s\n' "$value"
}

default_bundle_id() {
  local app_name="$1"
  local slug

  slug="$(printf '%s' "$app_name" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed -E 's/^-+|-+$//g')"
  printf 'com.joowon.%s\n' "${slug:-app}"
}

echo "BetterNBB release packager"
echo

SOURCE_SWIFT="$(expand_path "$(prompt "Swift file path" "${SOURCE_SWIFT:-$ROOT_DIR/BetterNBB.swift}")")"
APP_NAME="$(sanitize_app_name "$(prompt "App name" "${APP_NAME:-BetterNBB}")")"
OUTPUT_DIR="$(expand_path "$(prompt "Destination folder" "${OUTPUT_DIR:-/Users/joowon/Projects/App Outputs}")")"
VERSION="$(prompt "Version" "${VERSION:-1.0.0}")"
BUNDLE_ID="$(prompt "Bundle identifier" "${BUNDLE_ID:-$(default_bundle_id "$APP_NAME")}")"

if [[ -z "$APP_NAME" ]]; then
  echo "App name cannot be empty." >&2
  exit 1
fi

if [[ ! -f "$SOURCE_SWIFT" ]]; then
  echo "Swift source file not found: $SOURCE_SWIFT" >&2
  exit 1
fi

APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
ZIP_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION-macOS.zip"
DMG_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION-macOS.dmg"
MODULE_CACHE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/betternbb-module-cache.XXXXXX")"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/betternbb-build.XXXXXX")"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/betternbb-app.XXXXXX")"
DMG_STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/betternbb-dmg.XXXXXX")"
STAGING_APP_DIR="$STAGING_DIR/$APP_NAME.app"
CONTENTS_DIR="$STAGING_APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
trap 'rm -rf "$MODULE_CACHE_DIR" "$BUILD_DIR" "$STAGING_DIR" "$DMG_STAGING_DIR"' EXIT

echo
echo "Packaging:"
echo "  Source:      $SOURCE_SWIFT"
echo "  App:         $APP_NAME.app"
echo "  Destination: $OUTPUT_DIR"
echo "  Zip:         $ZIP_PATH"
echo "  DMG:         $DMG_PATH"
echo "  Version:     $VERSION"
echo "  Bundle ID:   $BUNDLE_ID"
echo

rm -rf "$ZIP_PATH" "$DMG_PATH" "$OUTPUT_DIR/ModuleCache"
mkdir -p "$MACOS_DIR" "$MODULE_CACHE_DIR" "$OUTPUT_DIR"

swiftc "$SOURCE_SWIFT" \
  -o "$BUILD_DIR/$APP_NAME-arm64" \
  -target "arm64-apple-macos$MIN_MACOS" \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -framework AppKit \
  -framework Foundation

swiftc "$SOURCE_SWIFT" \
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

(
  cd "$OUTPUT_DIR"
  COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$APP_NAME.app" "$ZIP_PATH"
)

cp -R "$APP_DIR" "$DMG_STAGING_DIR/"
ln -s /Applications "$DMG_STAGING_DIR/Applications"
hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Built $APP_DIR"
echo "Created $ZIP_PATH"
echo "Created $DMG_PATH"
