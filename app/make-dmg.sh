#!/usr/bin/env bash
#
# Build the styled Symly DMG: app on the left, Applications on the right with an
# arrow between, a Read Me below, on the dark branded background.
#
#   ./make-dmg.sh                       # builds + opens an UNSIGNED preview DMG
#                                       # (fast layout check, no notarization)
#   ./make-dmg.sh <app-path> <out-dmg>  # used by build_release.sh
#
# Layout coords are kept in lockstep with dmg-assets/dmg-background.tiff.
set -euo pipefail
cd "$(dirname "$0")"

APP="${1:-}"
DMG="${2:-}"
PREVIEW=0
if [ -z "$APP" ]; then
  PREVIEW=1
  ./make-app.sh debug >/dev/null
  APP="dist/Symly.app"
fi
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
[ -n "$DMG" ] || DMG="dist/Symly-$VERSION-preview.dmg"

rm -f "$DMG"
SRC="$(mktemp -d)"
cp -R "$APP" "$SRC/Symly.app"
cat > "$SRC/Read Me.txt" <<EOF
Symly $VERSION

Drag Symly into the Applications folder, then open it.

Free and open source. Symly organizes Avid Media Composer's MXF media by project
through a single symlink, without ever copying, moving, or deleting your media.

Requires macOS 13 Ventura or later.

Help and docs:  https://getsymly.app
Source:         https://github.com/brandoniben/symly
Questions:      symly@brandoniben.com


PRIVACY

Symly runs entirely on your Mac and never opens a network connection, so nothing
you do in it leaves your computer. There is no account, no sign-in, no analytics,
no telemetry, and no update check. The only thing it remembers between launches
is which drive you last set up, kept in your local app preferences. It reads only
the drive you choose, and the only thing it ever writes is a single symlink.


TERMS

Symly is free, open source, and provided as-is and as-available, with no warranty
of any kind, express or implied, including any warranty of merchantability,
fitness for a particular purpose, or non-infringement, and no guarantee that it
will be uninterrupted, error-free, or safe for your particular setup. You use it
entirely at your own risk. To the fullest extent permitted by law, you agree that
Brandon Iben is not liable for any loss or damage of any kind, including lost,
moved, or corrupted media, lost work, or downtime, arising from your use of the
app or any of its tools. You are responsible for testing it on your own workflow
before relying on it, for keeping your own backups, and for how you use it.


BUILT WITH AI ASSISTANCE

Symly was designed and built by Brandon Iben with AI assistance, including
Anthropic's Claude through Claude Code. The judgment and the final calls are his,
and the engine is open source so you can read exactly what it does.


Not affiliated with, endorsed by, or sponsored by Avid Technology, Inc. Avid and
Media Composer are trademarks of Avid Technology, Inc. MXF is an open SMPTE
standard. Copyright (C) 2026 Brandon Iben. Apache License 2.0.
EOF

create-dmg \
  --volname "Symly $VERSION" \
  --background "dmg-assets/dmg-background.tiff" \
  --window-pos 200 120 \
  --window-size 660 420 \
  --icon-size 120 \
  --icon "Symly.app" 165 195 \
  --app-drop-link 495 195 \
  --icon "Read Me.txt" 330 312 \
  --hide-extension "Symly.app" \
  --no-internet-enable \
  "$DMG" "$SRC" || true
[ -f "$DMG" ] || { echo "create-dmg failed to produce $DMG" >&2; exit 1; }
rm -rf "$SRC"

if [ "$PREVIEW" = 1 ]; then
  echo "Preview DMG (unsigned, layout only): $DMG"
  open "$DMG"
fi
