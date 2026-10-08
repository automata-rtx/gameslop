# 16 — Release and Steam

**Depends on:** `00_OVERVIEW.md`, `14_technical_architecture.md`
**Skills to read:** `godot-export-builds` (headless pipeline, Steam upload script), `godot-platform-desktop`

---

## 1. Targets

- **Windows x86_64** (`.exe` + `.pck`, embedded PCK off so patches are small), **Linux x86_64** (`.x86_64` + `.pck`). No macOS in v1.0 (no signing identity; add later if the user acquires one).
- Release templates only (`--export-release`). Debug builds are for the team (`--export-debug`, `debug` feature tag enables the overlay, telemetry, and bench scenes).
- Version: `game/src/core/version.gd` holds `VERSION = "1.0.0"`; the title shows it; `tools/ci/export.sh` tags builds `noclip-<version>-<platform>` under `build/`.

## 2. Export presets (`game/export_presets.cfg`)

- Windows: console wrapper off (`application/console_wrapper_icon` unused; `debug/export_console_wrapper = 0`), icon from `game/assets/icon.ico` (generated from `assets/ui/glyphs/noclip.svg` by `tools/ci/icons.py` at 16 to 256 px), product name NOCLIP, file description, copyright line with the year.
- Linux: icon `game/assets/icon.png`.
- Both: `texture_format/etc2_astc = false`, `bptc = true` (desktop), exclude `tests/**`, `scenes/debug/**` in release (filters), include `assets/audio/**`.
- Shader baker: on for desktop presets (shorter first-run stutter).
- Feature tags: `release` builds get no `debug` features; `OS.has_feature("debug")` gates all debug code.

## 3. Build pipeline (`tools/ci/`)

1. `test.sh`: import, then run the test suite (red stops).
2. `export.sh <version>`: import, export both presets, zip each with `README.txt` (controls summary, settings location `user://` path per OS, the AI disclosure, license notices), write SHA-256 sums.
3. `smoke.sh`: on a machine with a GPU, launch each build with `--smoke`; exit code 0 within 20 s; verify `user://` files were created; verify no console window on Windows (wrapper off) and that the Linux binary has the executable bit.
4. Steam: `tools/steam/app_build.vdf.template` and depot templates with placeholders `{APP_ID}`, `{DEPOT_WIN}`, `{DEPOT_LINUX}`, `{BUILD_DIR}`, `{DESCRIPTION}`; `tools/steam/upload.sh` fills them from env vars and runs `steamcmd +login <user> +run_app_build <vdf> +quit`. The human provides the app ID and credentials; nothing secret is committed.

## 4. Pre-release QA checklist (`docs/qa/release_checklist.md`, filled before each build)

- Clean-machine launch (no Godot installed), both platforms, 1080p and 1440p, windowed and fullscreen.
- First-run flow: boot, title, DESCEND, hints appear, reach depth 2 within three attempts.
- All settings persist across restart. Rebinding to AZERTY layout displays correct key names.
- Alt-tab mid-run: mouse released and recaptured correctly; "mute when unfocused" works.
- 10 consecutive levels with the debug memory counter flat.
- Every stratum from the tour matches the visual targets.
- Every row of the Feedback Contract ticked.
- Death by each error and the win both display the correct summary and write `meta.json`.
- The ending plays, credits scroll, Endless appears.
- Daily Descent locks after one attempt and shows the result.
- No text in the game uses the forbidden words (`01` §2): grep `strings.gd` and `data/notes`.

## 5. Store page facts (for the human to paste; the game must match these)

- **Title:** NOCLIP
- **Short description (≤ 300 chars):** A first-person horror roguelite about falling out of reality. Descend through generated liminal floors, pass through walls at the cost of how real you are, and learn the single rule of each thing hunting you. Made, start to finish, by an AI.
- **About:** three short paragraphs: the premise (`01` §1 in plain words), the loop (`00` §4), and the honesty line: "Every system, line of code, shader, sound, and word in NOCLIP was designed and built by an AI. A human chose the project, published it, and did nothing else. That is the experiment."
- **Features (bullets):** 6 generated strata; 5 errors each with one rule; noclip through walls and floors; Coherence renders the world; 36 notes; 14 unlocks and 4 loadouts; Daily Descent; Endless; full rebinding, FOV 70 to 110, sensitivity slider, accessibility options including sound captions.
- **Tags:** Horror, Roguelite, First-Person, Procedural Generation, Psychological Horror, Atmospheric, Singleplayer, Exploration, Liminal (if available), Indie.
- **Price suggestion:** USD 2.99 (the user's call).
- **Controller:** not supported (keyboard and mouse only; state it plainly).
- **System requirements:** Minimum: Windows 10 64-bit or Linux x86_64, 4-core CPU, 8 GB RAM, Vulkan 1.2 GPU with 2 GB VRAM (GTX 960 / RX 470 class), 500 MB disk. Recommended: GTX 1060 / RX 580, 16 GB RAM.
- **Screenshots:** eight from the tour: Halls corridor at 100 Coherence; Pools hall with water; Garage deck with a car and Still at distance; Offices with a flickering group; Server aisle with the flashlight; Substrate with the Threshold's strip of light; a mid-noclip frame; the same Halls corridor at 15 Coherence. Capsule art: the wordmark over the Halls corridor render from the title screen; no text other than NOCLIP.
- **Trailer:** optional; a 40 s capture of one Garage encounter and one noclip is enough.
- **Content rating notes:** no gore, no language, no violence against depicted beings; horror themes; flashing lights (the Reduce flashing option exists).

## 6. Credits (`game/data/credits.txt`, shown in the ending and from the Archive)

- "NOCLIP was designed and built by an AI (Claude, Anthropic) using the Godot Engine."
- Godot Engine: MIT license text (required to be included; show the full notice in a `LICENSES` submenu reachable from the title's settings, generated from `Engine.get_license_text()`).
- Fonts: the bundled OFL font with its copyright line.
- Third-party audio: each CC0 file with source (if any were used; the synth pipeline is the default).
- gd-agentic-skills (LGPL-3.0) is referenced as a development resource in `README.md`; it is not shipped in the game.
- A line: "Thank you for looking."

## 7. Post-1.0 list (not in scope, recorded so nobody builds them early)

Mid-run suspend/resume; Steam achievements and leaderboards (GodotSteam); controller support; localisation; macOS; a seventh stratum; a sixth error; photo mode.

## Interfaces

The export presets, the build scripts' arguments and outputs, and the version source are the contract other tasks (checkpoint builds, the Steam upload, the QA checklist) rely on.

### Interface additions during production
- M4.1a version: `Version.VERSION` in `game/src/core/version.gd` is the one source. `project.godot` `application/config/version` mirrors it (the Windows file and product versions come from there, written as `1.0.0.0`); `Title.VERSION` reads it; `tests/unit/test_export_presets.gd` and `export.sh` fail when they differ.
- M4.1a presets: `Windows x86_64` and `Linux x86_64` in `game/export_presets.cfg`, `all_resources` plus `include_filter="*.json, *.txt"` (the audio `manifest.json` and text notices are read with `FileAccess`; the imported audio ships as resources, so the raw WAVs are not copied a second time), `exclude_filter="tests/*, scenes/debug/*, *.md"`. The exclusions apply to `--export-debug` with these presets too; bench scenes run from the project.
- M4.1a outputs: `tools/ci/export.sh [--no-bake] [version]` writes `build/windows/NOCLIP.exe` + `NOCLIP.pck`, `build/linux/NOCLIP.x86_64` + `NOCLIP.pck`, `build/NOCLIP-<version>-<platform>.zip` (one folder `NOCLIP-<version>-<platform>/` with the binary, the PCK, `README.txt` from `tools/ci/README.txt.in`, `LICENSES.txt` from `tools/ci/licenses.gd`, `SHA256SUMS.txt`), `build/NOCLIP-<version>-SHA256SUMS.txt` for the zips, and logs in `build/logs/`. This spelling replaces `noclip-<version>-<platform>` in §1. The version argument is optional and must match `Version.VERSION`.
- M4.1a icons: `tools/ci/icons.gd` (a Godot script, in place of `icons.py`: no Python image library needed) renders `assets/ui/glyphs/noclip.svg` on black to `game/assets/icon.png` (256 px; `application/config/icon`) and `game/assets/icon.ico` (16, 24, 32, 48, 64, 128, 256 px PNG entries; `application/config/windows_native_icon` and the Windows preset icon). Output is deterministic and committed; `export.sh` regenerates it. Godot 4.7 writes the icon and version resources into the exe itself (`application/modify_resources`); rcedit is not used.
- M4.1a shader baker: it needs a rendering device. `export.sh` exports under Xvfb with Mesa lavapipe when both are installed, else on the desktop session, else headless without baked shaders (warned; `--no-bake` forces it). `export.sh` restores `project.godot` and `export_presets.cfg` after a windowed editor run re-saves them.
- M4.1a smoke: `tools/ci/smoke.sh [build dir]` runs the exported Linux binary with a fresh `XDG_DATA_HOME`: `--headless -- --smoke` (exit 0 within 20 s, `smoke: ok`), `-- --seed 1 --depth 1 --stratum halls` and the plain title boot for a few seconds each (`--max-fps 60 --quit-after N`), and, with Xvfb and lavapipe, `--smoke` again on the Forward+ renderer. Any script or resource-loading error in the output fails it, as does a missing executable bit or `user://` folder. The Windows smoke (`NOCLIP.exe --headless -- --smoke`, no console window) runs on Windows only.
