#!/usr/bin/env bash
#
# Symly: signed + notarized release build.
# ========================================
# Produces a Developer ID-signed, hardened-runtime, notarized, stapled DMG that
# installs with no Gatekeeper warning. Builds on make-app.sh.
#
# ONE-TIME PREREQS (you do these once, they need your Apple login):
#   1. Create a "Developer ID Application" certificate in your keychain:
#        Xcode > Settings > Accounts > (your team) > Manage Certificates >
#        + > "Developer ID Application".  (or developer.apple.com > Certificates)
#   2. Store notarization credentials as a keychain profile (one time):
#        xcrun notarytool store-credentials symly-notary \
#          --apple-id "you@example.com" --team-id "YOURTEAMID" \
#          --password "abcd-efgh-ijkl-mnop"     # an app-specific password from
#                                               # appleid.apple.com (NOT your login)
#
# THEN, each release:
#   SIGN_IDENTITY="Developer ID Application: Your Name (YOURTEAMID)" ./build_release.sh
#
# This script never sees or stores your password: notarytool reads the keychain
# profile you created above.

set -euo pipefail
cd "$(dirname "$0")"

NOTARY_PROFILE="${NOTARY_PROFILE:-symly-notary}"
APP="dist/Symly.app"
DMG="dist/Symly.dmg"

# --- preflight ---------------------------------------------------------------
if [ -z "${SIGN_IDENTITY:-}" ]; then
  echo "Set SIGN_IDENTITY to your Developer ID. Available identities:" >&2
  security find-identity -v -p codesigning | grep "Developer ID Application" >&2 || \
    echo "  (none found — create a 'Developer ID Application' cert first, see header)" >&2
  exit 1
fi

# --- build + bundle (release config) -----------------------------------------
echo "==> Building + bundling (release)"
./make-app.sh release

# --- code sign: Developer ID + hardened runtime + secure timestamp -----------
# The app needs no special entitlements: it is not sandboxed, uses no JIT, and
# only spawns Apple-signed system binaries (/bin/chmod, /bin/ls) which hardened
# runtime permits. If notarization ever flags an entitlement, add it here.
echo "==> Signing: $SIGN_IDENTITY"
codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

# --- package as a drag-to-install DMG ----------------------------------------
echo "==> Building DMG"
rm -f "$DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Symly" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

# --- notarize (waits for Apple; usually 1-5 min) -----------------------------
echo "==> Notarizing via profile '$NOTARY_PROFILE' (this waits for Apple)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

# --- staple + verify ---------------------------------------------------------
echo "==> Stapling + verifying"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature -vv "$DMG" || true

echo ""
echo "Done. Notarized, stapled DMG:  $DMG"
echo "Next: attach it to a GitHub Release and set DOWNLOAD_URL in the site repo."
