#!/usr/bin/env bash
# Fills the Steam build templates from the environment and uploads the exported builds with
# steamcmd (16 section 3). Nothing secret is stored: the account comes from the environment.
#
# Usage: tools/steam/upload.sh [--dry-run]
#
# Environment (all required except where marked):
#   STEAM_APP_ID        your app id from Steamworks (a positive integer)
#   STEAM_DEPOT_WIN     the Windows depot id
#   STEAM_DEPOT_LINUX   the Linux depot id
#   STEAM_USER          the Steam build account name (not needed with --dry-run)
#   STEAM_PASSWORD      optional; leave unset to use steamcmd's cached login or to be asked
#   STEAM_DESCRIPTION   optional build note, default "NOCLIP <version>"
#   STEAM_BUILD_DIR     optional, default <repo>/build (holds windows/ and linux/ from export.sh)
#   STEAMCMD            optional, default "steamcmd"
#
# --dry-run fills and checks the VDF files under <build dir>/steam/ and stops before steamcmd.
# The build is uploaded to Steam but never set live: you choose the branch in Steamworks.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$ROOT/tools/steam"

DRY=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY=1 ;;
  *) echo "upload.sh: unknown argument (only --dry-run is accepted)" >&2; exit 2 ;;
esac

fail() { echo "upload.sh: $*" >&2; exit 2; }

# An id is real only if it is a positive integer. Unset, empty, a {PLACEHOLDER}, text such as
# REPLACE_ME or YOUR_ID, zero, and Valve's public test app 480 are all refused.
check_id() {
  local name="$1" value="${!1:-}"
  [[ -n "$value" ]] || fail "$name is not set (see tools/steam/README.md)"
  [[ "$value" =~ ^[1-9][0-9]*$ ]] || fail "$name is a placeholder, not a numeric id"
  [[ "$value" != "480" ]] || fail "$name is 480, Valve's test app, not yours"
}
check_id STEAM_APP_ID
check_id STEAM_DEPOT_WIN
check_id STEAM_DEPOT_LINUX
[[ "$STEAM_DEPOT_WIN" != "$STEAM_DEPOT_LINUX" ]] || fail "the Windows and Linux depot ids are the same"
[[ "$STEAM_DEPOT_WIN" != "$STEAM_APP_ID" && "$STEAM_DEPOT_LINUX" != "$STEAM_APP_ID" ]] \
  || fail "a depot id equals the app id; depots have their own ids"
if [[ $DRY -eq 0 ]]; then
  [[ -n "${STEAM_USER:-}" ]] || fail "STEAM_USER is not set"
fi

VERSION="$(sed -n 's/^const VERSION[^"]*"\([^"]*\)".*/\1/p' "$ROOT/game/src/core/version.gd" | head -n1)"
[[ -n "$VERSION" ]] || fail "cannot read VERSION from game/src/core/version.gd"
BUILD_DIR="${STEAM_BUILD_DIR:-$ROOT/build}"
BUILD_DIR="${BUILD_DIR%/}"
# A VDF string cannot hold quotes or backslashes; keep the note plain.
DESCRIPTION="${STEAM_DESCRIPTION:-NOCLIP $VERSION}"
DESCRIPTION="${DESCRIPTION//[\"\\]/}"

[[ -f "$BUILD_DIR/windows/NOCLIP.exe" && -f "$BUILD_DIR/windows/NOCLIP.pck" ]] \
  || fail "no Windows build in $BUILD_DIR/windows (run tools/ci/export.sh $VERSION)"
[[ -f "$BUILD_DIR/linux/NOCLIP.x86_64" && -f "$BUILD_DIR/linux/NOCLIP.pck" ]] \
  || fail "no Linux build in $BUILD_DIR/linux (run tools/ci/export.sh $VERSION)"
[[ -x "$BUILD_DIR/linux/NOCLIP.x86_64" ]] \
  || fail "NOCLIP.x86_64 has no executable bit; upload from the machine that exported it"

OUT="$BUILD_DIR/steam"
mkdir -p "$OUT"
fill() {
  local text
  text="$(<"$1")"
  text="${text//\{APP_ID\}/$STEAM_APP_ID}"
  text="${text//\{DEPOT_WIN\}/$STEAM_DEPOT_WIN}"
  text="${text//\{DEPOT_LINUX\}/$STEAM_DEPOT_LINUX}"
  text="${text//\{BUILD_DIR\}/$BUILD_DIR}"
  text="${text//\{DESCRIPTION\}/$DESCRIPTION}"
  printf '%s\n' "$text" > "$2"
}
fill "$HERE/app_build.vdf.template" "$OUT/app_build.vdf"
fill "$HERE/depot_build_windows.vdf.template" "$OUT/depot_build_windows.vdf"
fill "$HERE/depot_build_linux.vdf.template" "$OUT/depot_build_linux.vdf"
python3 -I "$HERE/check_vdf.py" --generated "$OUT/app_build.vdf" "$OUT/depot_build_windows.vdf" "$OUT/depot_build_linux.vdf"

if [[ $DRY -eq 1 ]]; then
  echo "upload.sh: dry run ok; VDF files are in $OUT, steamcmd was not run"
  exit 0
fi

STEAMCMD="${STEAMCMD:-steamcmd}"
command -v "$STEAMCMD" >/dev/null || fail "steamcmd not found (set STEAMCMD or install it, see tools/steam/README.md)"
LOGIN=(+login "$STEAM_USER")
if [[ -n "${STEAM_PASSWORD:-}" ]]; then
  LOGIN+=("$STEAM_PASSWORD")
fi

echo "upload.sh: uploading NOCLIP $VERSION to app $STEAM_APP_ID (depots $STEAM_DEPOT_WIN, $STEAM_DEPOT_LINUX) as the account in STEAM_USER"
# Everything steamcmd prints passes through a filter that blanks the password and the account
# name, in case it echoes either. The command line is never printed.
set +e
"$STEAMCMD" "${LOGIN[@]}" +run_app_build "$OUT/app_build.vdf" +quit 2>&1 \
  | awk 'function mask(line, word, repl,   out, i) {
           if (word == "") return line
           out = ""
           while ((i = index(line, word)) > 0) {
             out = out substr(line, 1, i - 1) repl
             line = substr(line, i + length(word))
           }
           return out line
         }
         BEGIN { u = ENVIRON["STEAM_USER"]; p = ENVIRON["STEAM_PASSWORD"] }
         { print mask(mask($0, p, "********"), u, "<account>") }'
CODE=${PIPESTATUS[0]}
set -e
[[ $CODE -eq 0 ]] || fail "steamcmd exited with $CODE"
echo "upload.sh: done. Set the build live from the Steamworks Builds page."
