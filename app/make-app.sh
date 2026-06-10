#!/usr/bin/env bash
#
# Wrap the built binary into a double-clickable "Symly.app".
# Usage: ./make-app.sh [debug|release]   (default: debug)
#
# This is the local-dev bundler. The signed + notarized release pipeline
# (Developer ID, hardened runtime, DMG, notarytool, stapler) builds on this.

set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-debug}"
APP="Symly"
DISPLAY_NAME="Symly"
BUNDLE_ID="com.brandoniben.symly"

echo "Building ($CONFIG)..."
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/$APP"
[ -f "$BIN" ] || { echo "binary not found at $BIN" >&2; exit 1; }

OUT="dist/$DISPLAY_NAME.app"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/$APP"

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSUIElement</key><false/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Brandon Iben. Apache License 2.0.</string>
</dict>
</plist>
PLIST

# Bundle the icon if it has been generated (see make-icon.sh).
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$OUT/Contents/Resources/AppIcon.icns"

# Ad-hoc sign so macOS treats it as a stable app identity for local runs.
codesign --force --sign - "$OUT" >/dev/null 2>&1 || true

echo "Built $OUT"
echo "Open it with:  open \"$(pwd)/$OUT\""
