#!/usr/bin/env bash
#
# Render the MxfMark to a real AppIcon.icns (via the app's hidden
# --export-icon argument + iconutil). Run before make-app.sh when the mark
# changes. Writes Resources/AppIcon.icns.

set -euo pipefail
cd "$(dirname "$0")"

echo "Building (to export icon)..."
swift build -c debug >/dev/null
BIN="$(swift build -c debug --show-bin-path)/Symly"

ICONSET="/tmp/MXF.iconset"
rm -rf "$ICONSET"
"$BIN" --export-icon "$ICONSET"

if [ -z "$(ls -A "$ICONSET" 2>/dev/null)" ]; then
  echo "icon export produced no files; skipping" >&2
  exit 1
fi

mkdir -p Resources
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "wrote Resources/AppIcon.icns ($(du -h Resources/AppIcon.icns | cut -f1 | tr -d ' '))"
