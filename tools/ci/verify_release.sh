#!/usr/bin/env bash
# Verifies the output of tools/ci/export.sh against 16 (run by checkpoint.sh after the export):
#   - build/NOCLIP-<version>-{windows,linux}.zip exist, each holding exactly one folder
#     NOCLIP-<version>-<platform>/ with the binary, NOCLIP.pck, README.txt, LICENSES.txt,
#     SHA256SUMS.txt (no console wrapper, no stray files)
#   - every checksum matches: the inner SHA256SUMS.txt and build/NOCLIP-<version>-SHA256SUMS.txt
#   - README.txt carries the required lines (controls, user:// paths per OS, the AI
#     disclosure, the license notice, the checksum how-to); LICENSES.txt carries the Godot
#     license, the AI line and the font's OFL
#   - the Linux binary has the executable bit; the Windows exe is a GUI-subsystem PE
#   - release exclusions (16 §2): the PCKs hold no tests, no scenes/debug, no bench scene
#   - the PCK and the exe are the ones in build/<platform>/ (byte-identical to the zip's)
# Usage: tools/ci/verify_release.sh [build dir]   (default build/)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD="${1:-$ROOT/build}"
fail() { echo "verify_release.sh: FAIL: $*" >&2; exit 1; }

VERSION="$(sed -n 's/^const VERSION := "\([^"]*\)".*/\1/p' "$ROOT/game/src/core/version.gd")"
[[ -n "$VERSION" ]] || fail "no VERSION in version.gd"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

AI_LINE="an AI (Claude, Anthropic)"
FORBIDDEN_IN_PCK='res://tests/|res://scenes/debug/|scenes/ui/menu_gallery'

check_platform() {  # $1 platform, $2 binary name
  local platform="$1" binary="$2"
  local name="NOCLIP-$VERSION-$platform" zip="$BUILD/NOCLIP-$VERSION-$platform.zip"
  [[ -f "$zip" ]] || fail "missing $zip"
  mkdir -p "$WORK/$platform"
  unzip -q "$zip" -d "$WORK/$platform"
  local top
  top="$(ls "$WORK/$platform")"
  [[ "$top" == "$name" ]] || fail "$zip: top level is '$top', expected one folder '$name'"
  local dir="$WORK/$platform/$name"
  local got want
  got="$(cd "$dir" && ls -A | sort | tr '\n' ' ')"
  want="$(printf '%s\n' "$binary" NOCLIP.pck README.txt LICENSES.txt SHA256SUMS.txt | sort | tr '\n' ' ')"
  [[ "$got" == "$want" ]] || fail "$name contents: [$got] expected [$want]"
  (cd "$dir" && sha256sum --quiet -c SHA256SUMS.txt) || fail "$name: inner SHA256SUMS.txt does not match"
  cmp -s "$dir/$binary" "$BUILD/$platform/$binary" || fail "$name: $binary differs from build/$platform/$binary"
  cmp -s "$dir/NOCLIP.pck" "$BUILD/$platform/NOCLIP.pck" || fail "$name: NOCLIP.pck differs from build/$platform/"

  local readme="$dir/README.txt" licenses="$dir/LICENSES.txt"
  for needle in "NOCLIP $VERSION" "$binary" "NOCLIP.pck" "CONTROLS" "Move" "Noclip" "Interact" \
      "SETTINGS AND SAVE FILES" 'APPDATA%\NOCLIP' '.local/share/NOCLIP' "MADE BY AN AI" "$AI_LINE" \
      "SHA256SUMS.txt" "LICENSES.txt" "MIT license" "SIL Open Font License" "controllers are not supported"; do
    grep -qF -- "$needle" "$readme" || fail "$name README.txt lacks: $needle"
  done
  grep -q '{VERSION}\|{PLATFORM}' "$readme" && fail "$name README.txt has an unfilled placeholder"
  for needle in "$AI_LINE" "Godot" "MIT License" "SIL OPEN FONT LICENSE" "JetBrains Mono"; do
    grep -qiF -- "$needle" "$licenses" || fail "$name LICENSES.txt lacks: $needle"
  done
  if [[ "$platform" == "windows" ]]; then
    grep -q $'\r$' "$readme" || fail "$name README.txt is not CRLF"
  fi

  if [[ "$platform" == "linux" ]]; then
    [[ -x "$dir/$binary" ]] || fail "$name: $binary lost its executable bit in the zip"
  else
    local off sub
    off=$(od -An -tu4 -j60 -N4 "$dir/$binary" | tr -d ' ')
    sub=$(od -An -tu2 -j$((off + 92)) -N2 "$dir/$binary" | tr -d ' ')
    [[ "$sub" == "2" ]] || fail "$binary PE subsystem $sub (expected 2, GUI: no console window)"
    [[ "$(head -c2 "$dir/$binary")" == "MZ" ]] || fail "$binary is not a PE file"
  fi

  # 16 §2: nothing of tests/ or the benches in the shipped PCK. The PCK directory stores
  # resource paths in clear text; the gdc/scn exports live under .godot/exported with the
  # source name in the file name.
  if strings -n 6 "$dir/NOCLIP.pck" | grep -E "$FORBIDDEN_IN_PCK" | head -n 5 | grep -q .; then
    strings -n 6 "$dir/NOCLIP.pck" | grep -E "$FORBIDDEN_IN_PCK" | head -n 5 >&2
    fail "$name: NOCLIP.pck holds files the release must exclude"
  fi
  echo "verify_release.sh: $name ok ($(stat -c %s "$zip") bytes zip, $(stat -c %s "$dir/$binary") exe, $(stat -c %s "$dir/NOCLIP.pck") pck)"
}

check_platform windows NOCLIP.exe
check_platform linux NOCLIP.x86_64

SUMS="$BUILD/NOCLIP-$VERSION-SHA256SUMS.txt"
[[ -f "$SUMS" ]] || fail "missing $SUMS"
[[ "$(wc -l <"$SUMS")" == "2" ]] || fail "$SUMS should list the two zips"
(cd "$BUILD" && sha256sum --quiet -c "$SUMS") || fail "zip checksums do not match $SUMS"
# The debug-only features are gated at run time, not by file: DebugOverlay is only created
# when OS.is_debug_build() (main.gd), and smoke.sh asserts the release binary says so.
echo "verify_release.sh: OK (NOCLIP $VERSION)"
