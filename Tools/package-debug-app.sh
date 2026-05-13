#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SWIFT_BUILD_FLAGS="${SWIFT_BUILD_FLAGS:-}"

swift build ${SWIFT_BUILD_FLAGS}
swift build ${SWIFT_BUILD_FLAGS} --product petctl
swift build ${SWIFT_BUILD_FLAGS} --product global-pet-agent-bridge

BIN_DIR="$(swift build ${SWIFT_BUILD_FLAGS} --show-bin-path)"
APP_PATH="$ROOT_DIR/.build/GlobalPetAssistant.app"
EXECUTABLE="$BIN_DIR/GlobalPetAssistant"
RESOURCE_BUNDLE="$BIN_DIR/GlobalPetAssistant_GlobalPetAssistant.bundle"
APP_ICON="$ROOT_DIR/Assets/AppIcon/AppIcon.icns"
PETCTL_EXECUTABLE="$BIN_DIR/petctl"
AGENT_BRIDGE_EXECUTABLE="$BIN_DIR/global-pet-agent-bridge"

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources/bin" "$APP_PATH/Contents/Resources/Tools"

cp "$EXECUTABLE" "$APP_PATH/Contents/MacOS/GlobalPetAssistant"
cp "$PETCTL_EXECUTABLE" "$APP_PATH/Contents/Resources/bin/petctl"
cp "$AGENT_BRIDGE_EXECUTABLE" "$APP_PATH/Contents/Resources/bin/global-pet-agent-bridge"
cp "$ROOT_DIR/Tools/install-codex-hooks.sh" "$APP_PATH/Contents/Resources/Tools/install-codex-hooks.sh"
cp "$ROOT_DIR/Tools/verify-kitty-plugin.sh" "$APP_PATH/Contents/Resources/Tools/verify-kitty-plugin.sh"
mkdir -p "$APP_PATH/Contents/Resources/plugins"
cp -R "$ROOT_DIR/plugins/kitty" "$APP_PATH/Contents/Resources/plugins/kitty"

if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_PATH/Contents/Resources/GlobalPetAssistant_GlobalPetAssistant.bundle"
fi

if [[ -f "$APP_ICON" ]]; then
  cp "$APP_ICON" "$APP_PATH/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>GlobalPetAssistant</string>
  <key>CFBundleIdentifier</key>
  <string>io.github.globalpetassistant.GlobalPetAssistant</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>Global Pet Assistant</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.4.7</string>
  <key>CFBundleVersion</key>
  <string>16</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "$APP_PATH"
