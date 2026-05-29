#!/usr/bin/env bash
set -euo pipefail

APP_NAME="BetterNBB"
BUNDLE_ID="com.ducky8x.betternbb"
VERSION="1.0.0"
MIN_MACOS="12.0"

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

SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
SOURCE_SWIFT="$SCRIPT_DIR/BetterNBB.swift"
INSTALL_DIR="/Applications"
APP_DIR="$INSTALL_DIR/$APP_NAME.app"
BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/betternbb-install.XXXXXX")"
APP_STAGING="$BUILD_ROOT/$APP_NAME.app"
CONTENTS_DIR="$APP_STAGING/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
MODULE_CACHE_DIR="$BUILD_ROOT/ModuleCache"

cleanup() {
  rm -rf "$BUILD_ROOT"
}
trap cleanup EXIT

step() {
  local current="$1"
  local total="$2"
  local message="$3"
  printf '\n[%s/%s] %s\n' "$current" "$total" "$message"
}

finish_and_close() {
  local exit_code="$1"

  if [[ "$exit_code" -eq 0 ]]; then
    osascript \
      -e 'on run argv' \
      -e '  delay 0.8' \
      -e '  set installerPath to item 1 of argv' \
      -e '  tell application "Finder"' \
      -e '    if exists POSIX file installerPath then delete POSIX file installerPath' \
      -e '  end tell' \
      -e '  tell application "Terminal" to close front window' \
      -e 'end run' \
      "$SCRIPT_PATH" >/dev/null 2>&1 &
  else
    echo
    echo "Install failed. Press any key to close this window."
    read -r -n 1 _ || true
  fi

  exit "$exit_code"
}

echo "BetterNBB source installer"
echo

if [[ ! -f "$SOURCE_SWIFT" ]]; then
  echo "Could not find $SOURCE_SWIFT"
  echo "Make sure this installer is in the same folder as BetterNBB.swift."
  finish_and_close 1
fi

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Swift compiler not found."
  echo "Install Apple's Command Line Tools, then run this installer again:"
  echo "  xcode-select --install"
  open "x-apple.systempreferences:com.apple.preferences.softwareupdate" >/dev/null 2>&1 || true
  finish_and_close 1
fi

if [[ -e "$APP_DIR" ]]; then
  step 1 7 "Removing the old installed app..."
  echo "$APP_DIR already exists. Replacing it..."
  rm -rf "$APP_DIR" 2>/dev/null || sudo rm -rf "$APP_DIR"
else
  step 1 7 "Checking for an existing installed app..."
fi

step 2 7 "Preparing build folders..."
mkdir -p "$MACOS_DIR" "$MODULE_CACHE_DIR"

step 3 7 "Building $APP_NAME..."
swiftc "$SOURCE_SWIFT" \
  -o "$MACOS_DIR/$APP_NAME" \
  -target "$(uname -m)-apple-macos$MIN_MACOS" \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -framework AppKit \
  -framework Foundation

step 4 7 "Creating and verifying Contents/Info.plist..."
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

echo "Created app Info.plist at $CONTENTS_DIR/Info.plist"
plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$CONTENTS_DIR/Info.plist")" != "$APP_NAME" ]]; then
  echo "Info.plist executable name is incorrect."
  finish_and_close 1
fi

if [[ ! -x "$MACOS_DIR/$APP_NAME" ]]; then
  echo "Built executable is missing or not executable."
  finish_and_close 1
fi

step 5 7 "Signing and verifying app bundle..."
codesign --force --deep --sign - "$APP_STAGING" >/dev/null
codesign --verify --deep --strict "$APP_STAGING" >/dev/null

step 6 7 "Installing to $APP_DIR..."
cp -R "$APP_STAGING" "$APP_DIR" 2>/dev/null || sudo cp -R "$APP_STAGING" "$APP_DIR"
xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true

if [[ ! -f "$APP_DIR/Contents/Info.plist" || ! -x "$APP_DIR/Contents/MacOS/$APP_NAME" ]]; then
  echo "Installed app is missing required bundle files."
  finish_and_close 1
fi

step 7 7 "Opening $APP_NAME..."
open "$APP_DIR"

echo
echo "Installed $APP_NAME. This installer will move itself to Trash."
finish_and_close 0
