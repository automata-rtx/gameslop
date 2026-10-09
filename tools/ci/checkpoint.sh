#!/usr/bin/env bash
# Everything a checkpoint needs before tagging (15 §1 rule 2): the full test suite with
# 1,000 seeds per stratum and wall-clock budgets enforced, the level validator, the headless
# smoke, and from cp-06 the exports with their smoke. Run on a quiet machine (no other gates).
# Usage: tools/ci/checkpoint.sh [--no-export]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$ROOT/tools/godot/bin/godot}"
NOCLIP_FULL_TESTS=1 "$ROOT/tools/ci/test.sh"
# 03 §2, §6: the audio files match their recipes, and the mix rules hold (M3.3).
python3 "$ROOT/tools/audio/synth.py" --out "$ROOT/game/assets/audio" --verify | tail -n 5
python3 "$ROOT/tools/audio/measure.py" | tail -n 1
"$GODOT_BIN" --headless --path "$ROOT/game" -- --validate-levels 1000
"$GODOT_BIN" --headless --path "$ROOT/game" -- --smoke
if [[ "${1:-}" != "--no-export" ]]; then
  "$ROOT/tools/ci/export.sh"
  "$ROOT/tools/ci/verify_release.sh"
  "$ROOT/tools/ci/smoke.sh"
fi
echo "checkpoint.sh: all green"
