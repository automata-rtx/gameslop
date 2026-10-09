# Release checklist

Copy of `docs/design/16_release_and_steam.md` §4, ticked per build.

| Check | Windows | Linux | Notes |
|---|---|---|---|
| Clean-machine launch | | | |
| First-run flow (title → depth 2 within 3 attempts) | | | |
| Settings persist; AZERTY key names | | | |
| Alt-tab mouse capture; mute when unfocused | | | |
| 10 levels, memory flat | | | |
| Tour matches visual targets | | | |
| Feedback Contract complete | | | |
| Death by each error and the win write meta.json | | | |
| Ending, credits, Endless | | | |
| Daily locks after one attempt | | | |
| Forbidden words grep clean | | | Automated by tests/unit/test_text_gate.gd; re-read the store page text by hand |

## M4.1 export pipeline (build 1.0.0, Linux container, Godot 4.7.2 release templates, Xvfb + lavapipe, shaders baked)

Evidence from `tools/ci/export.sh`, `tools/ci/verify_release.sh` and `tools/ci/smoke.sh` (build/ is not committed; rerun to reproduce).

| M4.1 check | Result | Evidence |
|---|---|---|
| Presets `Windows x86_64`, `Linux x86_64`; options per 16 §2 | ok | `game/export_presets.cfg`; `tests/unit/test_export_presets.gd` |
| Version single source | ok | `version.gd` = `project.godot` = 1.0.0; `export.sh` and the test fail on drift |
| Windows build, no console window, no wrapper | ok | `build/windows/NOCLIP.exe` 109,132,800 B + `NOCLIP.pck` 23,358,852 B; PE subsystem 2 (GUI); no console exe |
| Linux build, executable bit | ok | `build/linux/NOCLIP.x86_64` 73,519,416 B + `NOCLIP.pck` 15,832,704 B |
| Windows zip (one folder: exe, pck, README.txt (CRLF), LICENSES.txt, SHA256SUMS.txt) | ok | `build/NOCLIP-1.0.0-windows.zip` 57,214,916 B, sha256 `36f6318f3f0b667a9203881555b6385b57e3ca9e3aa87ad4b0c59fa13e7acc37` |
| Linux zip (same, exec bit kept) | ok | `build/NOCLIP-1.0.0-linux.zip` 40,813,411 B, sha256 `15398bef950ba641f068fcd3d555377af2173c462466fab645e8c4a0d6f66843` |
| Checksum files (inner per zip, outer `build/NOCLIP-1.0.0-SHA256SUMS.txt`) | ok | `sha256sum -c` passes for all (`verify_release.sh`) |
| README.txt required lines; LICENSES.txt (Godot MIT, components, JetBrains Mono OFL, AI line) | ok | `verify_release.sh` greps each line |
| Icons: `icon.png` 256 px, `icon.ico` 16/24/32/48/64/128/256 px, from `noclip.svg`, no imported art | ok | `tools/ci/icons.gd`; regenerates byte-identical (git clean after export) |
| Release PCK has no `tests/`, `scenes/debug/`, bench scenes | ok | `verify_release.sh` scans both PCKs (found and fixed `menu_gallery.tscn` shipping) |
| No F3 overlay in release | ok | exported binary prints `smoke: build=release overlay=no`; `smoke.sh` requires it |
| Linux smoke (headless, direct level, title, rendered Forward+ on lavapipe) | ok | `smoke.sh`: all runs pass, user:// files created |
| Windows smoke (`NOCLIP.exe --headless -- --smoke`, exit 0, no console window) | NOT RUN | needs a Windows machine |
| Clean-machine launch on real GPUs, frame times | NOT RUN | needs real hardware |
| `CREDITS.md` at the repo root (font license) | ok | `CREDITS.md`; `test_export_presets.gd` |
