#!/usr/bin/env bash
# Runs Godot with a real Forward+ renderer on the CPU (Mesa lavapipe under Xvfb), so
# containers without a GPU can take screenshots. Slow (a few fps), but faithful enough
# for composition, palette, and shader checks; not for frame-time budgets.
# Usage: tools/ci/render.sh [godot args...]   e.g. tools/ci/render.sh --path game -- --tour build/tour
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$ROOT/tools/godot/bin/godot}"
if [[ ! -x "$GODOT_BIN" ]]; then
  MAIN="$(cd "$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)/.." && pwd)"
  GODOT_BIN="$MAIN/tools/godot/bin/godot"
fi
ICD=/usr/share/vulkan/icd.d/lvp_icd.json
if [[ ! -f "$ICD" ]]; then
  echo "render.sh: installing the Mesa software Vulkan driver" >&2
  (apt-get install -y -q mesa-vulkan-drivers || (apt-get update -q && apt-get install -y -q mesa-vulkan-drivers)) >/dev/null
fi
command -v xvfb-run >/dev/null || { echo "render.sh: xvfb-run missing (apt-get install xvfb)" >&2; exit 2; }
export VK_ICD_FILENAMES="$ICD"
exec xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT_BIN" --audio-driver Dummy "$@"
