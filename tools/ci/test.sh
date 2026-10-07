#!/usr/bin/env bash
# The merge gate (14 §8): import, then run every test headless. Extra args are passed
# to the runner, e.g. tools/ci/test.sh --filter levelgen
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$ROOT/tools/godot/bin/godot}"
if [[ ! -x "$GODOT_BIN" ]]; then
  # In a git worktree the gitignored binary lives in the main checkout.
  MAIN="$(cd "$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)/.." && pwd)"
  GODOT_BIN="$MAIN/tools/godot/bin/godot"
fi
[[ -x "$GODOT_BIN" ]] || { echo "test.sh: no Godot at $GODOT_BIN; run tools/godot/fetch.sh" >&2; exit 2; }
# Import refreshes the global class cache so class_name types resolve in --script mode.
# The first import of many new assets can crash the editor process (seen with 4.7.2 after a
# large WAV batch); a second pass finishes from the partial cache. Retry up to 3 times.
for attempt in 1 2 3; do
  if "$GODOT_BIN" --headless --path "$ROOT/game" --import >/dev/null 2>&1; then break; fi
  echo "test.sh: import pass $attempt failed, retrying" >&2
done
LOG="$(mktemp)"
set +e
"$GODOT_BIN" --headless --path "$ROOT/game" --script tests/run_tests.gd -- "$@" 2>&1 | tee "$LOG"
CODE=${PIPESTATUS[0]}
set -e
# Script errors that do not fail a test (parse errors in unrelated files) still fail the gate.
if grep -qE "^(SCRIPT ERROR|Parse Error|ERROR: Failed to load script)" "$LOG"; then
  echo "test.sh: engine reported script errors (see above)" >&2
  CODE=1
fi
rm -f "$LOG"
exit $CODE
