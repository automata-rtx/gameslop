# Release checklist

Copy of `docs/design/16_release_and_steam.md` §4, ticked per build.

| Check | Windows | Linux | Notes |
|---|---|---|---|
| Clean-machine launch (no Godot installed; 1080p and 1440p, windowed and fullscreen) | human | human (smoke ok) | Machine: `tools/ci/smoke.sh` boots the exported Linux binary headless, direct to a level, to the title and rendered on lavapipe (M4.3 run below). Human: `docs/qa/human_check_M4.md` Parts 1 to 3 and 9 |
| First-run flow (title → depth 2 within 3 attempts) | human | human | Machine: `tests/sim/test_run_flow.gd` (depth 1 to 2 to summary to title), `tests/unit/test_hud_guidance.gd` (hints, retire at depth 3). Human: `human_check_M4.md` Part 5 and 6 |
| Settings persist; AZERTY key names | human | human | Machine: `tests/unit/test_settings.gd::test_persistence_round_trip` (physical keycodes stored), `test_rebind_*`. Names go through `DisplayServer.keyboard_get_keycode_from_physical` (`src/ui/ui_keys.gd`), which headless cannot exercise. Human: `human_check_M4.md` Part 5 and 8 (rebind one key, relaunch); AZERTY: add the French layout in the OS and check that the CONTROLS tab shows Z Q S D |
| Alt-tab mouse capture; mute when unfocused | human | human | Machine: `tests/unit/test_settings_effects.gd::test_mute_when_unfocused` (the bus rule only). Human: `human_check_M4.md` Part 10 |
| 10 levels, memory flat | ok (machine) | ok (machine) | `tests/perf/test_memory_levels.gd`: 8 levels in the gate, 13 under `NOCLIP_FULL_TESTS=1` (checkpoint.sh); orphans and static MB flat over a Cycle. Process RSS on a real GPU is not measured: human glance at Task Manager during Part 6 |
| Tour matches visual targets | ok (CPU renderer) | ok (CPU renderer) | `tools/ci/tour_check.py` and `tests/levelgen/test_screenshot_tour.gd`; `docs/qa/visual_targets_by_eye.md` for T5/T6. Real GPU and display: `human_check_M3.md` Part G (cp-12), not repeated here |
| Feedback Contract complete | ok (machine) | ok (machine) | `docs/qa/feedback_checklist.md` (47 rows ticked); `tests/unit/test_feedback_rows.gd::test_the_checklist_lists_every_row_ticked`, `tests/sim/test_feedback_bench.gd` |
| Death by each error and the win write meta.json | ok (machine, partial) | ok (machine, partial) | `tests/unit/test_game_state_meta.gd::test_stats_flushed_at_transitions_and_run_end` (cause, `deaths_by`, `last_run` on disk), `tests/sim/test_ending_flow.gd` (the win: `wins`, `cycle_unlocked`, `unlocks.endless` read back from disk), `tests/unit/test_save_meta.gd`. Each error's own kill is in `tests/sim/test_errors_all_strata.gd` and the per-error sim tests. Human: the file is written after your own death in `human_check_M4.md` Part 7 |
| Ending, credits, Endless | ok (machine); look and timing human | ok (machine); look and timing human | `tests/unit/test_ending.gd` (roll prints every entry, skip rules, AI line), `tests/sim/test_ending_flow.gd`, `tests/unit/test_game_state_meta.gd::test_endless_after_crossing_the_threshold`. Human: `human_check_M3.md` Part G (credits readability) |
| Daily locks after one attempt | human | human | Machine: `tests/unit/test_game_state_meta.gd::test_daily_uses_faller_and_one_attempt_per_day`, `tests/unit/test_menus.gd::test_summary_items_and_spent_daily`. Human: `human_check_M4.md` Part 9 (including after a relaunch) |
| Forbidden words grep clean | ok | ok | Automated by `tests/unit/test_text_gate.gd`; M4.3 re-run below. Re-read the store page text by hand |

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

## Store and Steam (M4.2)

Ticked by the agent where a machine can do it; the rows marked "human" need Steamworks or a screen.

| Check | Status | Notes |
|---|---|---|
| Steam templates carry the five placeholders (`{APP_ID}`, `{DEPOT_WIN}`, `{DEPOT_LINUX}`, `{BUILD_DIR}`, `{DESCRIPTION}`); no real id or credential committed | done | `tests/unit/test_store_and_steam.gd` |
| VDF syntax valid for the templates and for the filled files | done | `tools/steam/check_vdf.py`; `upload.sh` checks every file it writes |
| `upload.sh` refuses unset, placeholder, zero, 480 and duplicate ids; never prints the account or password | done | `tools/steam/selftest.sh` with a fake steamcmd, run by the test suite |
| `upload.sh --dry-run` on the real exported builds | human | After `tools/ci/export.sh`; ids from Steamworks |
| Real upload to a private branch; install through the Steam client; launch on Windows and Linux | human | `tools/steam/README.md` steps 1 to 10; first contact with Steam, nothing here has been run against it |
| Linux binary keeps its executable bit after the Steam install | human | Check in the installed folder |
| `docs/release/store_page.md` sections in the order of 16 §5; short description verbatim and at most 300 characters | done | `tests/unit/test_store_and_steam.gd` |
| Store page text passes the text gate (forbidden words, punctuation, model names); the gate's planted page fires | done | `tests/unit/test_text_gate.gd`; "liminal" allowed on this page only |
| Store page figures match the game (6 strata, 5 errors, 36 notes, 14 unlocks, 4 loadouts) | done | Notes, loadouts, errors and strata counted from `DataRegistry`; the 14 unlocks are 16 §5 and 05 wording, not counted by a test |
| Store page re-read by hand once more | human | Last check before paste |
| Eight screenshots captured at 1920 x 1080 from the listed frames and looked at | human | `docs/release/store_page.md` §13; frame 8 is Coherence 10, not 15 (tour steps) |
| Capsule art made from the title background, NOCLIP only | human | No capture helper yet |
| Store page, AI disclosure, content survey, price entered in Steamworks | human | The suggested price is USD 2.99 |

## M4.3 evidence (rerun of the automation; export of the M4.2 merge, Linux container, Godot 4.7.2, Xvfb + lavapipe, shaders baked)

Run from a clean worktree. `build/` is not committed. The byte sizes and hashes below are from this run; an export on another day gives other hashes, so the human check compares against the `SHA256SUMS.txt` that ships with the zips they were handed, not against this table.

| Check | Result | Evidence |
|---|---|---|
| `tools/ci/export.sh` | ok | both presets exported, baker ran; `NOCLIP-1.0.0-windows.zip` 57,223,965 B sha256 `22163b69...e9912b9`, `NOCLIP-1.0.0-linux.zip` 40,822,040 B sha256 `ea4b1fd5...36402a9` (full values in `build/NOCLIP-1.0.0-SHA256SUMS.txt`) |
| `tools/ci/verify_release.sh` | ok | "OK (NOCLIP 1.0.0)": zip contents, inner and outer checksums, README and LICENSES lines, exe is a GUI-subsystem PE, no tests or debug scenes in either PCK |
| `tools/ci/smoke.sh` | ok | "Linux build OK": headless smoke, direct level, title, rendered Forward+ on lavapipe, `user://` created, release build with no F3 overlay |
| Filtered tests | ok | `test_save_meta` 12/12, `test_settings` 37/37, `test_game_state_meta` 23/23, `test_text_gate` 23/23, `test_ending` 17/17, `test_hud_guidance` 18/18, `test_settings_effects` 6/6, `test_memory_levels` 1/1, `test_store_and_steam` 10/10, `test_export_presets` 6/6 |
| Stale build warning | note | The `build/` of the main checkout predates the `menu_gallery.tscn` fix: `verify_release.sh` fails on it ("holds files the release must exclude"). Only hand the human a zip from a fresh `export.sh` that `verify_release.sh` accepted |
| Windows smoke, console window, SmartScreen, antivirus | human | `human_check_M4.md` Part 3. The exe is unsigned, so a SmartScreen prompt is expected; record it |
| Frame times, shader stutter on a first launch, real GPU | human | `human_check_M4.md` Part 6 asks for a feel judgement only; numbers are Part P of `human_check_M3.md` |
| Upload, install through Steam, Steam page | human | See the M4.2 table above; none of it is part of cp-13 |

The cp-13 human run is the sign-off for every "human" cell in the first table. Windows and Linux columns are filled from `docs/qa/notes_cp-13.md` when it comes back.
