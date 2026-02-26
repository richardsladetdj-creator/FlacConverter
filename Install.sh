#!/usr/bin/env bash
set -euo pipefail

APP_NAME="FlacConverter"
BUNDLE_ID="com.local.flacconverter"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$ROOT_DIR"

echo "== Build (Release) =="
swift build -c release

BIN_PATH=".build/release/$APP_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
  echo "ERROR: Expected binary at $BIN_PATH"
  exit 1
fi

APP_DIR="$ROOT_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"

echo "== Create app bundle =="
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

# Ad-hoc sign (helps Gatekeeper on many machines)
echo "== Codesign (ad-hoc) =="
codesign --force --deep --sign - "$APP_DIR" || true

echo "== Install to /Applications =="
DEST="/Applications/$APP_NAME.app"
rm -rf "$DEST"
cp -R "$APP_DIR" "$DEST"

echo "Installed: $DEST"
echo "Launching..."
open -a "$DEST"