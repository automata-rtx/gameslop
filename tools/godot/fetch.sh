#!/usr/bin/env bash
# Downloads the pinned Godot editor (Linux x86_64) into tools/godot/bin and,
# with --templates, the export templates into tools/godot/templates and the
# user template directory. Verifies SHA-512 sums from the release. (14 §1)
# Usage: tools/godot/fetch.sh [--templates]
# Prints: export GODOT_BIN=<path>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="$(tr -d '[:space:]' < "$HERE/VERSION")"          # e.g. 4.7.2-stable
NUM="${VERSION%-stable}"                                    # e.g. 4.7.2
BASE="https://github.com/godotengine/godot/releases/download/${VERSION}"
BIN_DIR="$HERE/bin"
TPL_DIR="$HERE/templates"
WANT_TEMPLATES=0
[[ "${1:-}" == "--templates" ]] && WANT_TEMPLATES=1

mkdir -p "$BIN_DIR"
SUMS="$BIN_DIR/SHA512-SUMS.txt"
[[ -s "$SUMS" ]] || curl -fsSL --retry 4 -o "$SUMS" "$BASE/SHA512-SUMS.txt"

fetch_verified() {  # $1 = file name, $2 = destination dir
  local name="$1" dest="$2"
  mkdir -p "$dest"
  if [[ ! -s "$dest/$name" ]] || ! (cd "$dest" && grep " ${name}\$" "$SUMS" | sha512sum -c --status -); then
    echo "fetch: downloading $name" >&2
    curl -fL --retry 4 --progress-bar -o "$dest/$name" "$BASE/$name"
    (cd "$dest" && grep " ${name}\$" "$SUMS" | sha512sum -c -) >&2 || { echo "fetch: checksum failed for $name" >&2; rm -f "$dest/$name"; exit 1; }
  fi
}

EDITOR_ZIP="Godot_v${VERSION}_linux.x86_64.zip"
if [[ ! -x "$BIN_DIR/godot" ]] || ! "$BIN_DIR/godot" --headless --version 2>/dev/null | grep -q "^${NUM}.stable"; then
  fetch_verified "$EDITOR_ZIP" "$BIN_DIR"
  (cd "$BIN_DIR" && unzip -o -q "$EDITOR_ZIP" && mv -f "Godot_v${VERSION}_linux.x86_64" godot && chmod +x godot && rm -f "$EDITOR_ZIP")
fi

if (( WANT_TEMPLATES )); then
  TPZ="Godot_v${VERSION}_export_templates.tpz"
  USER_TPL="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${NUM}.stable"
  if [[ ! -f "$USER_TPL/version.txt" ]]; then
    fetch_verified "$TPZ" "$TPL_DIR"
    (cd "$TPL_DIR" && rm -rf templates && unzip -o -q "$TPZ" && rm -f "$TPZ")
    mkdir -p "$USER_TPL"
    # Only the desktop templates are needed (16 §2); keep disk use small.
    for f in version.txt linux_release.x86_64 linux_debug.x86_64 windows_release_x86_64.exe windows_debug_x86_64.exe windows_release_x86_64_console.exe windows_debug_x86_64_console.exe; do
      [[ -f "$TPL_DIR/templates/$f" ]] && cp -f "$TPL_DIR/templates/$f" "$USER_TPL/"
    done
    rm -rf "$TPL_DIR/templates"
    echo "fetch: templates installed to $USER_TPL" >&2
  fi
fi

echo "export GODOT_BIN=$BIN_DIR/godot"
