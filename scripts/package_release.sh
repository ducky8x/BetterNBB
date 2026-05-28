#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="BetterNBB"
VERSION="1.0.0"
OUTPUT_DIR="/Users/joowon/Projects/App Outputs"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
ZIP_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION-macOS.zip"

"$ROOT_DIR/scripts/build_app.sh"

rm -f "$ZIP_PATH"
(
  cd "$OUTPUT_DIR"
  ditto -c -k --keepParent "$APP_NAME.app" "$ZIP_PATH"
)

echo "Created $ZIP_PATH"
