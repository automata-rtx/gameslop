#!/usr/bin/env bash
# Export smoke test (16 §3 step 3) for the Linux build made by tools/ci/export.sh.
# Runs the exported binary (not the editor) with a fresh user folder:
#   1. --headless -- --smoke         boots, generates depth 1, waits 2 s, must exit 0 within 20 s
#                                    and print "smoke: ok" (14 §9)
#   2. -- --seed 1 --depth 1 --stratum halls   direct level for ~5 s (--quit-after), exit 0
#   3. no arguments                  the normal boot to the title for ~3 s, exit 0
#   4. when Xvfb and Mesa lavapipe are installed: run 1 again with the Forward+ renderer
# Every run fails on script or resource-loading errors in its output (a file that the
# export filters dropped shows up here). Also checks the executable bit and that the
# user:// folder was created.
# The Windows build cannot run in a Linux container (no Wine); its smoke runs on Windows:
#   NOCLIP.exe --headless -- --smoke   (exit code 0; no console window opens).
# Usage: tools/ci/smoke.sh [build dir]   (default build/linux)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="${1:-$ROOT/build/linux}"
BIN="$DIR/NOCLIP.x86_64"
SMOKE_TIMEOUT_S=20
fail() { echo "smoke.sh: FAIL: $*" >&2; exit 1; }

[[ -f "$BIN" ]] || fail "no $BIN (run tools/ci/export.sh first)"
[[ -x "$BIN" ]] || fail "$BIN is not executable"
[[ -f "$DIR/NOCLIP.pck" ]] || fail "no NOCLIP.pck next to the binary"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# A fresh user:// (custom user dir: Godot puts it under $XDG_DATA_HOME/<custom_user_dir_name>).
export XDG_DATA_HOME="$WORK/data"
USER_DIR="$XDG_DATA_HOME/NOCLIP"
BAD='^(SCRIPT ERROR|Parse Error|ERROR: Failed to load|ERROR: Cannot open file|ERROR: Resource file not found|ERROR: No loader found|ERROR: Failed loading resource|ERROR: Can.t load)'

run() {  # $1 = label, $2 = timeout s, rest = the command (the binary and its args)
  local label="$1" limit="$2"; shift 2
  local log="$WORK/$label.log"
  local start end code
  start=$(date +%s)
  set +e
  timeout "$limit" "$@" >"$log" 2>&1
  code=$?
  set -e
  end=$(date +%s)
  if grep -qE "$BAD" "$log"; then
    grep -E -A2 "$BAD" "$log" >&2
    fail "$label: errors in the output"
  fi
  if (( code != 0 )); then
    tail -n 30 "$log" >&2
    (( code == 124 )) && fail "$label: did not quit within ${limit} s"
    fail "$label: exit code $code"
  fi
  echo "smoke.sh: $label ok ($((end - start)) s)"
  LAST_LOG="$log"
}

run smoke "$SMOKE_TIMEOUT_S" "$BIN" --headless -- --smoke
grep -q "^smoke: ok" "$LAST_LOG" || fail "smoke: no 'smoke: ok' line"
# --max-fps keeps --quit-after a time budget: 300 frames at 60 fps is about 5 s.
run direct-level 60 "$BIN" --headless --max-fps 60 --quit-after 300 -- --seed 1 --depth 1 --stratum halls
run title 60 "$BIN" --headless --max-fps 60 --quit-after 180
# With Xvfb and Mesa lavapipe present (as tools/ci/render.sh), also boot with the real
# Forward+ renderer on the CPU: proves the baked shaders and the Vulkan path load. Slow
# and says nothing about frame times; real GPUs still need the 16 §4 checklist.
ICD=/usr/share/vulkan/icd.d/lvp_icd.json
if [[ -f "$ICD" ]] && command -v xvfb-run >/dev/null; then
  run smoke-rendered 120 env VK_ICD_FILENAMES="$ICD" xvfb-run -a -s "-screen 0 1280x720x24" \
    "$BIN" --audio-driver Dummy --resolution 960x540 -- --smoke
  grep -q "^smoke: ok" "$LAST_LOG" || fail "smoke-rendered: no 'smoke: ok' line"
  grep -q "Forward+" "$LAST_LOG" || fail "smoke-rendered: the Forward+ renderer did not start"
else
  echo "smoke.sh: rendered smoke skipped (no Xvfb + lavapipe)"
fi

[[ -d "$USER_DIR" ]] || fail "user:// was not created at $USER_DIR"
[[ -n "$(find "$USER_DIR" -type f | head -n 1)" ]] || fail "user:// is empty"
echo "smoke.sh: user:// files:"
(cd "$USER_DIR" && find . -type f | sort | sed 's/^/  /')
echo "smoke.sh: Linux build OK ($BIN)"
