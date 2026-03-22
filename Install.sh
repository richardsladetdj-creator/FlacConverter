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
RES_DIR="$CONTENTS/Resources"

echo "== Create app bundle =="
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"

echo "== Download yt-dlp =="
curl -fL "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos" \
  -o "$MACOS_DIR/yt-dlp"
chmod +x "$MACOS_DIR/yt-dlp"

echo "== Download ffmpeg + ffprobe =="
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
  ARCH_SLUG="arm64"
else
  ARCH_SLUG="amd64"
fi
RIEDL_BASE="https://ffmpeg.martin-riedl.de/redirect/latest/macos/${ARCH_SLUG}/snapshot"

for TOOL in ffmpeg ffprobe; do
  TOOL_ZIP=$(mktemp /tmp/${TOOL}_XXXXXX.zip)
  if curl -fL "${RIEDL_BASE}/${TOOL}.zip" -o "$TOOL_ZIP" 2>/dev/null; then
    unzip -o -j "$TOOL_ZIP" "$TOOL" -d "$MACOS_DIR" >/dev/null
    chmod +x "$MACOS_DIR/$TOOL"
    rm -f "$TOOL_ZIP"
    echo "Bundled $TOOL for $ARCH"
  else
    echo "WARN: Could not download $TOOL — TikTok audio extraction may not work"
    rm -f "$TOOL_ZIP"
  fi
done

# Copy icon if present
if [[ -f "$ROOT_DIR/icon.icns" ]]; then
  cp "$ROOT_DIR/icon.icns" "$RES_DIR/icon.icns"
else
  echo "WARN: icon.icns not found at $ROOT_DIR/icon.icns (app will use default icon)"
fi

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

  <key>CFBundleIconFile</key>
  <string>icon</string>

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
pkill -x "FlacConverter" 2>/dev/null || true
sleep 0.5
open "$DEST"