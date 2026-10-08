#!/usr/bin/env bash
# Export smoke test (16 §3 step 3) for the Linux build made by tools/ci/export.sh.
# Runs the exported binary (not the editor) with a fresh user folder:
#   1. --headless -- --smoke         boots, generates depth 1, waits 2 s, must exit 0 within 20 s
#                                    and print "smoke: ok" (14 §9)
#   2. -- --seed 1 --depth 1 --stratum halls   direct level for ~5 s (--quit-after), exit 0
#   3. no arguments                  the normal boot to the title for ~3 s, exit 0
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
# A fresh user:// (Godot puts it under $XDG_DATA_HOME/godot/app_userdata/<name>).
export XDG_DATA_HOME="$WORK/data"
USER_DIR="$XDG_DATA_HOME/godot/app_userdata/NOCLIP"
BAD='^(SCRIPT ERROR|Parse Error|ERROR: Failed to load|ERROR: Cannot open file|ERROR: Resource file not found|ERROR: No loader found|ERROR: Failed loading resource|ERROR: Can.t load)'

run() {  # $1 = label, $2 = timeout s, rest = binary args
  local label="$1" limit="$2"; shift 2
  local log="$WORK/$label.log"
  local start end code
  start=$(date +%s)
  set +e
  timeout "$limit" "$BIN" "$@" >"$log" 2>&1
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

run smoke "$SMOKE_TIMEOUT_S" --headless -- --smoke
grep -q "^smoke: ok" "$LAST_LOG" || fail "smoke: no 'smoke: ok' line"
# --max-fps keeps --quit-after a time budget: 300 frames at 60 fps is about 5 s.
run direct-level 60 --headless --max-fps 60 --quit-after 300 -- --seed 1 --depth 1 --stratum halls
run title 60 --headless --max-fps 60 --quit-after 180

[[ -d "$USER_DIR" ]] || fail "user:// was not created at $USER_DIR"
[[ -n "$(find "$USER_DIR" -type f | head -n 1)" ]] || fail "user:// is empty"
echo "smoke.sh: user:// files:"
(cd "$USER_DIR" && find . -type f | sort | sed 's/^/  /')
echo "smoke.sh: Linux build OK ($BIN)"
