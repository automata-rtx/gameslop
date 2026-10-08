#!/usr/bin/env bash
# Release export (16 §3 step 2): import, render the icons, export both presets with the
# release templates into build/<platform>/, then zip each as build/NOCLIP-<version>-<platform>.zip
# (binary, PCK, README.txt, LICENSES.txt, SHA256SUMS.txt) and write
# build/NOCLIP-<version>-SHA256SUMS.txt for the zips. Exits non-zero on any failure.
# Usage: tools/ci/export.sh [--no-bake] [version]
#   The version comes from game/src/core/version.gd (the single source, 16 §1); a version
#   argument must match it.
#   Shader baker (16 §2) needs a rendering device: the export runs under Xvfb with Mesa
#   lavapipe when both are installed (as tools/ci/render.sh), else on the desktop session
#   when DISPLAY or WAYLAND_DISPLAY is set, else headless without baked shaders (warned).
#   --no-bake forces the headless export.
# Needs the export templates for the pinned Godot (tools/godot/fetch.sh --templates).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$ROOT/tools/godot/bin/godot}"
if [[ ! -x "$GODOT_BIN" ]]; then
  # In a git worktree the gitignored binary lives in the main checkout.
  MAIN="$(cd "$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)/.." && pwd)"
  GODOT_BIN="$MAIN/tools/godot/bin/godot"
fi
[[ -x "$GODOT_BIN" ]] || { echo "export.sh: no Godot at $GODOT_BIN; run tools/godot/fetch.sh" >&2; exit 2; }
for tool in zip sha256sum; do
  command -v "$tool" >/dev/null || { echo "export.sh: $tool is required" >&2; exit 2; }
done

NO_BAKE=0
ARGS=()
for a in "$@"; do
  case "$a" in
    --no-bake) NO_BAKE=1 ;;
    *) ARGS+=("$a") ;;
  esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

GAME="$ROOT/game"
BUILD="$ROOT/build"
fail() { echo "export.sh: $*" >&2; exit 1; }

# --- version (16 §1) -------------------------------------------------------------------
VERSION="$(sed -n 's/^const VERSION := "\([^"]*\)".*/\1/p' "$GAME/src/core/version.gd")"
[[ -n "$VERSION" ]] || fail "no VERSION in game/src/core/version.gd"
if [[ $# -ge 1 && "$1" != "$VERSION" ]]; then
  fail "asked for version $1 but game/src/core/version.gd says $VERSION"
fi
PROJECT_VERSION="$(sed -n 's/^config\/version="\([^"]*\)"/\1/p' "$GAME/project.godot")"
[[ "$PROJECT_VERSION" == "$VERSION" ]] || fail "project.godot config/version ($PROJECT_VERSION) != version.gd ($VERSION)"

# --- templates ---------------------------------------------------------------------------
ENGINE="$("$GODOT_BIN" --headless --version 2>/dev/null | head -n1)"   # 4.7.2.stable.official.<hash>
TPL_NAME="$(echo "$ENGINE" | cut -d. -f1-4)"                          # 4.7.2.stable
TPL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$TPL_NAME"
for t in windows_release_x86_64.exe linux_release.x86_64; do
  [[ -f "$TPL_DIR/$t" ]] || { echo "export.sh: missing template $TPL_DIR/$t; run tools/godot/fetch.sh --templates" >&2; exit 2; }
done

LOG_DIR="$BUILD/logs"
mkdir -p "$LOG_DIR"
run_step() {  # $1 = log name, rest = command; fails on a non-zero exit or script errors
  local name="$1"; shift
  local log="$LOG_DIR/$name.log"
  if ! "$@" >"$log" 2>&1; then
    tail -n 40 "$log" >&2
    fail "$name failed (log: $log)"
  fi
  if grep -qE "^(SCRIPT ERROR|Parse Error|ERROR: Failed to load script)" "$log"; then
    grep -E -A3 "^(SCRIPT ERROR|Parse Error|ERROR: Failed to load script)" "$log" >&2
    fail "$name reported script errors (log: $log)"
  fi
}
godot_step() {  # $1 = log name, rest = godot args (headless)
  local name="$1"; shift
  run_step "$name" "$GODOT_BIN" --headless --path "$GAME" "$@"
}

# How the export step runs (see the header): baking needs a rendering device.
ICD=/usr/share/vulkan/icd.d/lvp_icd.json
EXPORT_RUNNER=(env "$GODOT_BIN" --headless)
BAKE_NOTE="headless: shaders NOT baked (first-run shader stutter)"
if (( ! NO_BAKE )); then
  if [[ -f "$ICD" ]] && command -v xvfb-run >/dev/null; then
    EXPORT_RUNNER=(env "VK_ICD_FILENAMES=$ICD" xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT_BIN" --audio-driver Dummy)
    BAKE_NOTE="Xvfb + lavapipe: shaders baked"
  elif [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    EXPORT_RUNNER=(env "$GODOT_BIN")
    BAKE_NOTE="desktop session: shaders baked"
  fi
fi
if [[ "$BAKE_NOTE" == headless* ]]; then echo "export.sh: warning: no rendering device; $BAKE_NOTE" >&2; fi
# A windowed editor re-saves project.godot (dropping keys equal to the defaults) and may
# touch export_presets.cfg; the export must never edit the source tree, so restore both.
SNAP="$(mktemp -d)"
cp -p "$GAME/project.godot" "$GAME/export_presets.cfg" "$SNAP/"
restore_config() {
  cmp -s "$SNAP/project.godot" "$GAME/project.godot" || cp -p "$SNAP/project.godot" "$GAME/project.godot"
  cmp -s "$SNAP/export_presets.cfg" "$GAME/export_presets.cfg" || cp -p "$SNAP/export_presets.cfg" "$GAME/export_presets.cfg"
}
trap 'restore_config; rm -rf "$SNAP"' EXIT

# --- import and icons --------------------------------------------------------------------
# Import first so class_name types resolve; the first import of many new assets can crash
# the editor process (see test.sh), so retry.
imported=0
for attempt in 1 2 3; do
  if "$GODOT_BIN" --headless --path "$GAME" --import >"$LOG_DIR/import.log" 2>&1; then imported=1; break; fi
  echo "export.sh: import pass $attempt failed, retrying" >&2
done
(( imported )) || fail "import failed (log: $LOG_DIR/import.log)"
godot_step icons --script "$ROOT/tools/ci/icons.gd"
godot_step import-icons --import

# --- export ------------------------------------------------------------------------------
# platform id | preset name | binary name
PRESETS=(
  "windows|Windows x86_64|NOCLIP.exe"
  "linux|Linux x86_64|NOCLIP.x86_64"
)
godot_step licenses --script "$ROOT/tools/ci/licenses.gd" -- "$LOG_DIR/LICENSES.txt"
[[ -s "$LOG_DIR/LICENSES.txt" ]] || fail "LICENSES.txt is empty"

SUMS="$BUILD/NOCLIP-$VERSION-SHA256SUMS.txt"
rm -f "$SUMS"
for entry in "${PRESETS[@]}"; do
  IFS='|' read -r PLATFORM PRESET BINARY <<<"$entry"
  OUT="$BUILD/$PLATFORM"
  rm -rf "$OUT"
  mkdir -p "$OUT"
  echo "export.sh: exporting $PRESET -> build/$PLATFORM/$BINARY" >&2
  run_step "export-$PLATFORM" "${EXPORT_RUNNER[@]}" --path "$GAME" --export-release "$PRESET" "$OUT/$BINARY"
  restore_config
  if [[ "$BAKE_NOTE" != headless* ]] && ! grep -q "baking_shaders" "$LOG_DIR/export-$PLATFORM.log"; then
    fail "$PRESET: the shader baker did not run (log: $LOG_DIR/export-$PLATFORM.log); use --no-bake to export without it"
  fi
  [[ -s "$OUT/$BINARY" ]] || fail "$PRESET produced no $BINARY"
  [[ -s "$OUT/NOCLIP.pck" ]] || fail "$PRESET produced no NOCLIP.pck (embed_pck must stay off, 16 §1)"
  if [[ "$PLATFORM" == "linux" ]]; then chmod +x "$OUT/$BINARY"; fi

  # The zip holds one folder named like the zip, so unpacking never spills files.
  NAME="NOCLIP-$VERSION-$PLATFORM"
  STAGE="$BUILD/stage/$NAME"
  rm -rf "$STAGE"
  mkdir -p "$STAGE"
  cp -p "$OUT/$BINARY" "$OUT/NOCLIP.pck" "$STAGE/"
  sed -e "s/{VERSION}/$VERSION/g" -e "s/{PLATFORM}/$PRESET/g" "$ROOT/tools/ci/README.txt.in" >"$STAGE/README.txt"
  cp "$LOG_DIR/LICENSES.txt" "$STAGE/LICENSES.txt"
  (cd "$STAGE" && sha256sum "$BINARY" NOCLIP.pck README.txt LICENSES.txt >SHA256SUMS.txt)
  ZIP="$BUILD/$NAME.zip"
  rm -f "$ZIP"
  (cd "$BUILD/stage" && zip -q -r -X "$ZIP" "$NAME") || fail "zip failed for $NAME"
  (cd "$BUILD" && sha256sum "$NAME.zip" >>"$SUMS")
done
rm -rf "$BUILD/stage"

echo "export.sh: NOCLIP $VERSION ($BAKE_NOTE)" >&2
for entry in "${PRESETS[@]}"; do
  IFS='|' read -r PLATFORM PRESET BINARY <<<"$entry"
  printf '  %-34s %10s bytes\n' "build/$PLATFORM/$BINARY" "$(stat -c %s "$BUILD/$PLATFORM/$BINARY")" >&2
  printf '  %-34s %10s bytes\n' "build/$PLATFORM/NOCLIP.pck" "$(stat -c %s "$BUILD/$PLATFORM/NOCLIP.pck")" >&2
  printf '  %-34s %10s bytes\n' "build/NOCLIP-$VERSION-$PLATFORM.zip" "$(stat -c %s "$BUILD/NOCLIP-$VERSION-$PLATFORM.zip")" >&2
done
cat "$SUMS"
