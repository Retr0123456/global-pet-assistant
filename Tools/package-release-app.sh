#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
APP_PATH="$ROOT_DIR/.build/release/GlobalPetAssistant.app"
ZIP_PATH="$ROOT_DIR/.build/release/GlobalPetAssistant.zip"
EXECUTABLE="$BIN_DIR/GlobalPetAssistant"
RESOURCE_BUNDLE="$BIN_DIR/GlobalPetAssistant_GlobalPetAssistant.bundle"

rm -rf "$APP_PATH" "$ZIP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

cp "$EXECUTABLE" "$APP_PATH/Contents/MacOS/GlobalPetAssistant"

if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_PATH/Contents/Resources/GlobalPetAssistant_GlobalPetAssistant.bundle"
fi

cat > "$APP_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>GlobalPetAssistant</string>
  <key>CFBundleIdentifier</key>
  <string>com.ryanchen.GlobalPetAssistant</string>
  <key>CFBundleName</key>
  <string>Global Pet Assistant</string>
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
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "$APP_PATH"
echo "$ZIP_PATH"
