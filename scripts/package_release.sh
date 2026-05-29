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
STATE_DIR="${HOME}/Library/Application Support/BetterNBB"
STATE_FILE="$STATE_DIR/package_release.env"

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

prompt_editable_path() {
  local label="$1"
  local initial_value="$2"
  local answer

  if help read 2>/dev/null | grep -q -- '-i text'; then
    read -e -i "$initial_value" -r -p "$label: " answer
  elif help read 2>/dev/null | grep -q -- '-e'; then
    echo "Tip: Tab completion is enabled for this prompt." >&2
    read -e -r -p "$label [$initial_value]: " answer
    answer="${answer:-$initial_value}"
  else
    read -r -p "$label [$initial_value]: " answer
    answer="${answer:-$initial_value}"
  fi

  printf '%s\n' "$answer"
}

step() {
  local current="$1"
  local total="$2"
  local message="$3"
  printf '\n[%s/%s] %s\n' "$current" "$total" "$message"
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

resolve_source_swift_path() {
  local raw="$1"
  local path
  local search_dir
  local -a swift_files=()
  local choice

  path="$(expand_path "$raw")"

  # Relative paths are interpreted from ~/Projects for quicker typing.
  if [[ "$path" != /* ]]; then
    path="$HOME/Projects/$path"
  fi

  if [[ -f "$path" ]]; then
    printf '%s\n' "$path"
    return 0
  fi

  if [[ -d "$path" ]]; then
    search_dir="$path"
    while IFS= read -r file; do
      swift_files+=("$file")
    done < <(find "$search_dir" -maxdepth 3 -type f -name "*.swift" | sort)

    if [[ "${#swift_files[@]}" -eq 0 ]]; then
      echo "No .swift files found under: $search_dir" >&2
      return 1
    fi

    if [[ "${#swift_files[@]}" -eq 1 ]]; then
      echo "Using Swift file: ${swift_files[0]}" >&2
      printf '%s\n' "${swift_files[0]}"
      return 0
    fi

    echo "Multiple Swift files found under $search_dir:" >&2
    for i in "${!swift_files[@]}"; do
      printf '  %d) %s\n' "$((i + 1))" "${swift_files[$i]}" >&2
    done

    read -r -p "Choose Swift file [1-${#swift_files[@]}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#swift_files[@]} )); then
      printf '%s\n' "${swift_files[$((choice - 1))]}"
      return 0
    fi

    echo "Invalid selection." >&2
    return 1
  fi

  echo "Path does not exist: $path" >&2
  return 1
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
  if [[ "$slug" == "betternbb" ]]; then
    printf 'com.ducky8x.betternbb\n'
  else
    printf 'com.ducky8x.%s\n' "${slug:-app}"
  fi
}

load_state() {
  [[ -f "$STATE_FILE" ]] || return 0
  # shellcheck disable=SC1090
  source "$STATE_FILE"
}

save_state() {
  mkdir -p "$STATE_DIR"
  {
    printf 'LAST_SOURCE_SWIFT=%q\n' "$SOURCE_SWIFT"
    printf 'LAST_APP_NAME=%q\n' "$APP_NAME"
    printf 'LAST_OUTPUT_DIR=%q\n' "$OUTPUT_DIR"
    printf 'LAST_VERSION=%q\n' "$VERSION"
    printf 'LAST_BUNDLE_ID=%q\n' "$BUNDLE_ID"
  } > "$STATE_FILE"
}

echo "BetterNBB release packager"
echo

load_state

SOURCE_PATH_INITIAL="${SOURCE_SWIFT:-${HOME}/Projects/}"
SOURCE_SWIFT_INPUT="$(prompt_editable_path "Swift file path" "$SOURCE_PATH_INITIAL")"
SOURCE_SWIFT="$(resolve_source_swift_path "$SOURCE_SWIFT_INPUT")"
APP_NAME="$(sanitize_app_name "$(prompt "App name" "${APP_NAME:-${LAST_APP_NAME:-BetterNBB}}")")"
OUTPUT_DIR="$(expand_path "$(prompt "Destination folder" "${OUTPUT_DIR:-${LAST_OUTPUT_DIR:-/Users/joowon/Projects/App Outputs}}")")"
VERSION="$(prompt "Version" "${VERSION:-${LAST_VERSION:-1.0.0}}")"
BUNDLE_ID="$(prompt "Bundle identifier" "${BUNDLE_ID:-${LAST_BUNDLE_ID:-$(default_bundle_id "$APP_NAME")}}")"

if [[ -z "$APP_NAME" ]]; then
  echo "App name cannot be empty." >&2
  exit 1
fi

if [[ ! -f "$SOURCE_SWIFT" ]]; then
  echo "Swift source file not found: $SOURCE_SWIFT" >&2
  exit 1
fi

APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
DMG_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION-macOS.dmg"
SOURCE_INSTALLER_ZIP_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION-source-installer.zip"
MODULE_CACHE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/betternbb-module-cache.XXXXXX")"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/betternbb-build.XXXXXX")"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/betternbb-app.XXXXXX")"
DMG_STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/betternbb-dmg.XXXXXX")"
SOURCE_INSTALLER_STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/betternbb-source-installer.XXXXXX")"
SOURCE_INSTALLER_FOLDER="$SOURCE_INSTALLER_STAGING_DIR/$APP_NAME-Source-Installer"
STAGING_APP_DIR="$STAGING_DIR/$APP_NAME.app"
CONTENTS_DIR="$STAGING_APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
trap 'rm -rf "$MODULE_CACHE_DIR" "$BUILD_DIR" "$STAGING_DIR" "$DMG_STAGING_DIR" "$SOURCE_INSTALLER_STAGING_DIR"' EXIT

echo
echo "Packaging:"
echo "  Source:      $SOURCE_SWIFT"
echo "  App:         $APP_NAME.app"
echo "  Destination: $OUTPUT_DIR"
echo "  DMG:         $DMG_PATH"
echo "  Source ZIP:  $SOURCE_INSTALLER_ZIP_PATH"
echo "  Version:     $VERSION"
echo "  Bundle ID:   $BUNDLE_ID"
echo

step 1 8 "Preparing build folders..."
rm -rf "$DMG_PATH" "$SOURCE_INSTALLER_ZIP_PATH" "$OUTPUT_DIR/ModuleCache"
mkdir -p "$MACOS_DIR" "$MODULE_CACHE_DIR" "$OUTPUT_DIR"

step 2 8 "Compiling arm64 app binary..."
swiftc "$SOURCE_SWIFT" \
  -o "$BUILD_DIR/$APP_NAME-arm64" \
  -target "arm64-apple-macos$MIN_MACOS" \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -framework AppKit \
  -framework Foundation

step 3 8 "Compiling x86_64 app binary..."
swiftc "$SOURCE_SWIFT" \
  -o "$BUILD_DIR/$APP_NAME-x86_64" \
  -target "x86_64-apple-macos$MIN_MACOS" \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -framework AppKit \
  -framework Foundation

step 4 8 "Combining binaries into a universal app executable..."
lipo -create \
  "$BUILD_DIR/$APP_NAME-arm64" \
  "$BUILD_DIR/$APP_NAME-x86_64" \
  -output "$MACOS_DIR/$APP_NAME"

step 5 8 "Creating and verifying Contents/Info.plist..."
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

plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null
EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$CONTENTS_DIR/Info.plist")"
if [[ "$EXECUTABLE_NAME" != "$APP_NAME" ]]; then
  echo "Info.plist CFBundleExecutable is '$EXECUTABLE_NAME', expected '$APP_NAME'." >&2
  exit 1
fi

if [[ ! -x "$MACOS_DIR/$APP_NAME" ]]; then
  echo "App executable is missing or not executable: $MACOS_DIR/$APP_NAME" >&2
  exit 1
fi

step 6 8 "Signing and verifying the app bundle..."
find "$STAGING_APP_DIR" -name $'Icon\r' -delete
xattr -cr "$STAGING_APP_DIR"
codesign --force --deep --sign - "$STAGING_APP_DIR"
codesign --verify --deep --strict "$STAGING_APP_DIR"

rm -rf "$APP_DIR"
mv "$STAGING_APP_DIR" "$APP_DIR"

step 7 8 "Creating DMG..."
cp -R "$APP_DIR" "$DMG_STAGING_DIR/"
ln -s /Applications "$DMG_STAGING_DIR/Applications"
hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

step 8 8 "Creating source installer ZIP..."
mkdir -p "$SOURCE_INSTALLER_FOLDER"
cp "$SOURCE_SWIFT" "$SOURCE_INSTALLER_FOLDER/BetterNBB.swift"
cp "$ROOT_DIR/scripts/compilinstaller_doubleclicktoinstall.command" "$SOURCE_INSTALLER_FOLDER/compilinstaller_doubleclicktoinstall.command"
chmod +x "$SOURCE_INSTALLER_FOLDER/compilinstaller_doubleclicktoinstall.command"
(
  cd "$SOURCE_INSTALLER_STAGING_DIR"
  COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$APP_NAME-Source-Installer" "$SOURCE_INSTALLER_ZIP_PATH"
)

echo "Built $APP_DIR"
echo "Created $DMG_PATH"
echo "Created $SOURCE_INSTALLER_ZIP_PATH"

save_state
echo "Saved these defaults for next time: $STATE_FILE"
