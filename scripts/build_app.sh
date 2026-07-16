#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release

APP_DIR="$PWD/build/ScreenTranslator.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

rm -rf "$APP_DIR"
mkdir -p "$MACOS"

cp ".build/release/ScreenTranslator" "$MACOS/ScreenTranslator"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>ScreenTranslator</string>
  <key>CFBundleIdentifier</key>
  <string>local.screentranslator.app</string>
  <key>CFBundleName</key>
  <string>ScreenTranslator</string>
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
</dict>
</plist>
PLIST

echo "Built: $APP_DIR"
