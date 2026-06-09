#!/usr/bin/env bash
#
# Throwaway mounted volumes to exercise the setup walkthrough without a real
# Avid drive. Creates two:
#   "MXF Fresh"    - empty, triggers the fresh-setup path
#   "MXF Existing" - has fake Avid media, triggers the adopt path
#
# Usage:  ./dev/test-volumes.sh        (create + mount)
#         ./dev/test-volumes.sh clean  (unmount + delete)

set -euo pipefail
DIR=/tmp/mxf-test-dmgs

if [ "${1:-up}" = "clean" ]; then
  for n in "MXF Fresh" "MXF Existing"; do
    hdiutil detach "/Volumes/$n" >/dev/null 2>&1 || true
  done
  rm -rf "$DIR"
  echo "test volumes removed"
  exit 0
fi

mkdir -p "$DIR"
make_vol() {
  local name="$1" img="$DIR/$2.dmg"
  hdiutil detach "/Volumes/$name" >/dev/null 2>&1 || true
  rm -f "$img"
  hdiutil create -size 200m -fs APFS -volname "$name" "$img" >/dev/null
  hdiutil attach "$img" >/dev/null
}

make_vol "MXF Fresh" fresh
make_vol "MXF Existing" existing

# Seed "MXF Existing" with real-looking Avid media so it triggers adoption.
EX="/Volumes/MXF Existing/Avid MediaFiles/MXF/1"
mkdir -p "$EX"
: > "$EX/msmMMOB.mdb"
: > "$EX/msmFMID.pmr"
printf 'pretend footage\n' > "$EX/A001_clip.mxf"

echo "Mounted test volumes:"
ls -d /Volumes/MXF* 2>/dev/null
echo "Remove later with:  ./dev/test-volumes.sh clean"
