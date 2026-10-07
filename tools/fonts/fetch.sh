#!/usr/bin/env bash
# Downloads the UI typeface (04 §2: JetBrains Mono, OFL, Regular and Bold only) from the
# official JetBrains GitHub release, verifies pinned SHA-256 sums, and places the static
# TTFs plus OFL.txt in game/assets/fonts/. The results are committed so builds never need
# the network; run this only to re-fetch or to bump the pinned version (update the sums).
# Usage: tools/fonts/fetch.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
DEST="$ROOT/game/assets/fonts"
VERSION="2.304"
URL="https://github.com/JetBrains/JetBrainsMono/releases/download/v${VERSION}/JetBrainsMono-${VERSION}.zip"
ZIP_SHA256="6f6376c6ed2960ea8a963cd7387ec9d76e3f629125bc33d1fdcd7eb7012f7bbf"

# name in archive | sha256 of the extracted file
FILES=(
  "fonts/ttf/JetBrainsMono-Regular.ttf|a0bf60ef0f83c5ed4d7a75d45838548b1f6873372dfac88f71804491898d138f"
  "fonts/ttf/JetBrainsMono-Bold.ttf|5590990c82e097397517f275f430af4546e1c45cff408bde4255dad142479dcb"
  "OFL.txt|30f0c136e3c88e422d0791acd97238870f9054a9729bc34cf2ff0d4ed8cac4ad"
)

all_present() {
  local entry path sum
  for entry in "${FILES[@]}"; do
    path="${entry%%|*}"; sum="${entry##*|}"
    [[ -f "$DEST/$(basename "$path")" ]] || return 1
    echo "$sum  $DEST/$(basename "$path")" | sha256sum -c --status - || return 1
  done
}

if all_present; then
  echo "fonts: JetBrains Mono ${VERSION} already present and verified in $DEST" >&2
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "fonts: downloading JetBrains Mono ${VERSION}" >&2
curl -fL --retry 4 --progress-bar -o "$TMP/jbm.zip" "$URL"
echo "$ZIP_SHA256  $TMP/jbm.zip" | sha256sum -c - >&2 || { echo "fonts: archive checksum failed" >&2; exit 1; }

mkdir -p "$TMP/x" "$DEST"
for entry in "${FILES[@]}"; do
  path="${entry%%|*}"; sum="${entry##*|}"
  unzip -q -j -o "$TMP/jbm.zip" "$path" -d "$TMP/x"
  name="$(basename "$path")"
  echo "$sum  $TMP/x/$name" | sha256sum -c - >&2 || { echo "fonts: checksum failed for $name" >&2; exit 1; }
  cp -f "$TMP/x/$name" "$DEST/$name"
done
echo "fonts: installed to $DEST" >&2
