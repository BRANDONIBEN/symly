#!/usr/bin/env bash
#
# Symly: Phase 0 spike
# ==================================
# Validates the ONE assumption the whole product rests on:
#
#   Avid Media Composer follows a repointed `Avid MediaFiles/MXF` symlink
#   transparently, through launch, import, project switch, relaunch, relink.
#
# If this passes on a real Avid drive, the app is worth building. If it fails,
# we learn that here for the price of 30 minutes instead of after writing an app.
#
# SAFETY: this script will NEVER delete your media:
#   * It only ever creates or removes SYMLINKS, never a real file or folder.
#   * Before removing the MXF location it verifies the location is a symlink.
#     If it is a real folder, it REFUSES and tells you to `adopt` it instead.
#   * Every command is a DRY RUN by default. Nothing changes until `--apply`.
#   * The only time real media moves is an explicit `adopt`, which is a
#     same-volume rename (instant, no bytes copied, nothing deleted), and it
#     refuses to run if it would cross volumes (which would copy).
#   * `teardown` only ever removes a sandbox THIS script created (marker file).
#
# It validates the real-Avid mechanism: import, switch, relaunch, relink.

set -euo pipefail

AMF="Avid MediaFiles"
PROJECTS_DIRNAME="Symly Media"
SANDBOX_MARKER=".mxf-spike-sandbox"

# ---- output ---------------------------------------------------------------
bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '\033[32m  ✓ %s\033[0m\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*"; }
plan() { printf '\033[35m  → %s\033[0m\n' "$*"; }   # magenta: the symlink color
die()  { printf '\033[31m  ✗ %s\033[0m\n' "$*" >&2; exit 1; }

# ---- helpers --------------------------------------------------------------
device_of()   { stat -f '%d' "$1" 2>/dev/null || echo "?"; }
mxf_path()    { printf '%s/%s/MXF' "$1" "$AMF"; }
project_mxf() { printf '%s/%s/%s/MXF' "$1" "$PROJECTS_DIRNAME" "$2"; }

# Refuse to ever act on an obviously protected path.
guard_path() {
  local p="$1"
  [ -n "$p" ] || die "empty path"
  case "$p" in
    / | /Volumes | /System* | /Users | /Library* | "$HOME")
      die "refusing to operate on a protected path: $p" ;;
  esac
}

describe_mxf() {
  local mxf; mxf="$(mxf_path "$1")"
  if [ -L "$mxf" ]; then printf 'symlink → %s' "$(readlink "$mxf")"
  elif [ -d "$mxf" ]; then printf 'REAL FOLDER (not yet adopted)'
  elif [ -e "$mxf" ]; then printf 'a file (unexpected)'
  else printf 'missing'; fi
}

# ---- commands -------------------------------------------------------------
cmd_setup() {
  local dir="${1:-$HOME/Desktop/mxf-spike-test}"
  bold "Setup sandbox: $dir"
  [ -e "$dir" ] && die "path already exists: $dir (pick another, or teardown first)"
  if [ "$APPLY" != "1" ]; then
    plan "would create a fake Avid layout (Avid MediaFiles/MXF) + ProjectA + ProjectB"
    info "re-run with --apply to create it"
    return
  fi
  mkdir -p "$dir"
  printf 'Symly spike sandbox, safe to delete.\n' > "$dir/$SANDBOX_MARKER"
  local p pm
  for p in ProjectA ProjectB; do
    pm="$(project_mxf "$dir" "$p")/1"
    mkdir -p "$pm"
    : > "$pm/msmMMOB.mdb"          # stand-ins for Avid's per-folder database pair
    : > "$pm/msmFMID.pmr"
    printf 'fake media for %s\n' "$p" > "$pm/${p}_clip01.mxf"
  done
  mkdir -p "$dir/$AMF"
  ln -s "$(project_mxf "$dir" ProjectA)" "$(mxf_path "$dir")"
  ok "sandbox created: MXF → ProjectA/MXF"
  info "try:  ./spike.sh status \"$dir\""
  info "      ./spike.sh link \"$dir\" ProjectB --apply"
}

cmd_status() {
  local dir="${1:?usage: spike.sh status DIR}"
  local mxf; mxf="$(mxf_path "$dir")"
  bold "Status: $dir"
  info "Avid MediaFiles/MXF: $(describe_mxf "$dir")"
  if [ -L "$mxf" ]; then
    if [ -e "$mxf" ]; then ok "symlink resolves (target exists)"
    else warn "symlink is DANGLING: target missing (drive unplugged?)"; fi
    info "resolved contents:"
    ( ls -1 "$mxf"/ 2>/dev/null | sed 's/^/        /' ) || true
  fi
  if [ -d "$dir/$PROJECTS_DIRNAME" ]; then
    info "projects available:"
    ( ls -1 "$dir/$PROJECTS_DIRNAME" 2>/dev/null | sed 's/^/        /' ) || true
  fi
}

cmd_link() {
  local dir="${1:?usage: spike.sh link DIR PROJECT [--apply]}"
  local proj="${2:?missing PROJECT name}"
  local mxf tgt; mxf="$(mxf_path "$dir")"; tgt="$(project_mxf "$dir" "$proj")"
  bold "Repoint MXF → $proj"
  [ -d "$tgt" ] || die "project target does not exist: $tgt"
  if [ -e "$mxf" ] && [ ! -L "$mxf" ]; then
    die "MXF is a REAL folder, not a symlink. Run 'adopt' first to move it safely into a project. (Refusing to touch real media.)"
  fi
  guard_path "$mxf"
  plan "current: $(describe_mxf "$dir")"
  plan "new:     symlink → $tgt"
  if [ "$APPLY" != "1" ]; then info "DRY RUN: re-run with --apply to make the change"; return; fi
  [ -L "$mxf" ] && rm "$mxf"        # only ever removes a verified symlink
  mkdir -p "$(dirname "$mxf")"
  ln -s "$tgt" "$mxf"
  ok "MXF now → $tgt"
}

cmd_adopt() {
  local dir="${1:?usage: spike.sh adopt DIR PROJECT [--apply]}"
  local proj="${2:?missing PROJECT name}"
  local mxf tgt; mxf="$(mxf_path "$dir")"; tgt="$(project_mxf "$dir" "$proj")"
  bold "Adopt existing real MXF → project $proj"
  [ -e "$mxf" ] || die "nothing at $mxf to adopt"
  [ -L "$mxf" ] && die "MXF is already a symlink, nothing to adopt"
  [ -d "$mxf" ] || die "MXF is not a folder"
  [ -e "$tgt" ] && die "destination already exists: $tgt"
  guard_path "$mxf"
  plan "move (rename, no copy):  $mxf"
  plan "                      →  $tgt"
  plan "then symlink:            MXF → $tgt"
  if [ "$(device_of "$mxf")" != "$(device_of "$dir")" ]; then
    die "source and destination are on different volumes: a move would COPY. Aborting to keep your media safe."
  fi
  if [ "$APPLY" != "1" ]; then info "DRY RUN: re-run with --apply"; return; fi
  mkdir -p "$(dirname "$tgt")"
  mv "$mxf" "$tgt"                  # same-volume rename: atomic, no copy, no delete
  ln -s "$tgt" "$mxf"
  ok "adopted: your media was moved (never copied or deleted); MXF → $tgt"
}

cmd_teardown() {
  local dir="${1:?usage: spike.sh teardown DIR [--apply]}"
  bold "Teardown sandbox: $dir"
  [ -f "$dir/$SANDBOX_MARKER" ] || die "no sandbox marker at $dir: refusing (teardown only removes sandboxes made by 'setup')"
  guard_path "$dir"
  plan "would remove the entire sandbox: $dir"
  if [ "$APPLY" != "1" ]; then info "DRY RUN: re-run with --apply"; return; fi
  rm -rf "$dir"
  ok "sandbox removed"
}

cmd_help() {
  cat <<'EOF'

Symly: Phase 0 spike

USAGE
  ./spike.sh <command> [args] [--apply]

  Every command is a DRY RUN until you add --apply. This script only ever
  creates or removes SYMLINKS. It never deletes or copies your real media; the
  only real-media operation is `adopt`, an instant same-volume rename.

COMMANDS
  setup [DIR]         Create a safe fake sandbox (default ~/Desktop/mxf-spike-test)
                      simulating Avid MediaFiles/MXF + ProjectA + ProjectB.
  status DIR          Show what Avid MediaFiles/MXF is and where it points.
  link DIR PROJECT    Repoint Avid MediaFiles/MXF → that project's MXF folder.
  adopt DIR PROJECT   Move a pre-existing REAL Avid MediaFiles/MXF into a project
                      (same-volume rename, no copy), then symlink it.
  teardown DIR        Remove a sandbox created by `setup` (marker-protected).
  help                This text.

REAL-AVID TEST
  Validates that Media Composer follows the repointed link through
  import / switch / relaunch / relink on real hardware.
EOF
}

# ---- dispatch -------------------------------------------------------------
APPLY=0
filtered=()
for a in "$@"; do
  if [ "$a" = "--apply" ]; then APPLY=1; else filtered+=("$a"); fi
done
set -- ${filtered[@]+"${filtered[@]}"}     # bash-3.2-safe expansion under set -u
cmd="${1:-help}"
if [ "$#" -gt 0 ]; then shift; fi

case "$cmd" in
  setup)    cmd_setup    "$@" ;;
  status)   cmd_status   "$@" ;;
  link)     cmd_link     "$@" ;;
  adopt)    cmd_adopt    "$@" ;;
  teardown) cmd_teardown "$@" ;;
  help|-h|--help) cmd_help ;;
  *) die "unknown command: $cmd  (try: ./spike.sh help)" ;;
esac
