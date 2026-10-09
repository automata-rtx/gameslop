#!/usr/bin/env bash
# Checks the Steam tooling without Steam: the VDF parser, the templates, and upload.sh against
# a fake build folder and a fake steamcmd. Run by tests/unit/test_steam_tooling.gd.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UP="$HERE/upload.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAILS=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }

python3 -I "$HERE/check_vdf.py" --selftest >/dev/null && ok "parser selftest" || bad "parser selftest"
python3 -I "$HERE/check_vdf.py" --templates "$HERE/app_build.vdf.template" \
  "$HERE/depot_build_windows.vdf.template" "$HERE/depot_build_linux.vdf.template" >/dev/null \
  && ok "templates parse and carry their placeholders" || bad "templates"

mkdir -p "$T/b/windows" "$T/b/linux"
touch "$T/b/windows/NOCLIP.exe" "$T/b/windows/NOCLIP.pck" "$T/b/linux/NOCLIP.pck"
install -m 755 /dev/null "$T/b/linux/NOCLIP.x86_64"
cat > "$T/fakesteam" <<'EOS'
#!/bin/sh
# Echoes what a careless tool might: the account and the password.
echo "Logging in user $2 with password $3"
echo "args: $*" | sed 's/+login.*+run_app_build/+run_app_build/'
exit 0
EOS
chmod +x "$T/fakesteam"
GOOD=(STEAM_BUILD_DIR="$T/b" STEAM_APP_ID=1234560 STEAM_DEPOT_WIN=1234561 STEAM_DEPOT_LINUX=1234562)

refuses() { # name, env...
  local name="$1"; shift
  local out
  out="$(env -u STEAM_APP_ID -u STEAM_DEPOT_WIN -u STEAM_DEPOT_LINUX STEAM_BUILD_DIR="$T/b" "$@" "$UP" --dry-run 2>&1)"
  local code=$?
  if [[ $code -ne 0 && ! -e "$T/b/steam/app_build.vdf" ]]; then ok "refuses: $name"; else bad "refuses: $name (code $code)"; fi
}
refuses "nothing set"
refuses "template braces" STEAM_APP_ID='{APP_ID}' STEAM_DEPOT_WIN=2 STEAM_DEPOT_LINUX=3
refuses "text id" STEAM_APP_ID=REPLACE_ME STEAM_DEPOT_WIN=2 STEAM_DEPOT_LINUX=3
refuses "zero" STEAM_APP_ID=0 STEAM_DEPOT_WIN=2 STEAM_DEPOT_LINUX=3
refuses "test app 480" STEAM_APP_ID=480 STEAM_DEPOT_WIN=2 STEAM_DEPOT_LINUX=3
refuses "same depots" STEAM_APP_ID=1 STEAM_DEPOT_WIN=2 STEAM_DEPOT_LINUX=2
refuses "depot equals app" STEAM_APP_ID=2 STEAM_DEPOT_WIN=2 STEAM_DEPOT_LINUX=3

env "${GOOD[@]}" "$UP" --dry-run >/dev/null 2>&1 && ok "dry run with real-looking ids" || bad "dry run"
python3 -I "$HERE/check_vdf.py" --generated "$T/b/steam/app_build.vdf" "$T/b/steam/depot_build_windows.vdf" \
  "$T/b/steam/depot_build_linux.vdf" >/dev/null && ok "generated files parse, no placeholder left" || bad "generated files"
grep -q '"appid" "1234560"' "$T/b/steam/app_build.vdf" && ok "app id filled" || bad "app id filled"

OUT="$(env "${GOOD[@]}" STEAM_USER=bobthebuilder STEAM_PASSWORD=hunter2hunter2 STEAMCMD="$T/fakesteam" "$UP" 2>&1)"
CODE=$?
[[ $CODE -eq 0 ]] && ok "fake steamcmd upload runs" || bad "fake steamcmd upload (code $CODE)"
if grep -q "hunter2" <<<"$OUT" || grep -q "bobthebuilder" <<<"$OUT"; then bad "secrets leaked into the output"; else ok "password and account are masked"; fi

[[ $FAILS -eq 0 ]] && echo "steam selftest: ok" || { echo "steam selftest: $FAILS failed"; exit 1; }
