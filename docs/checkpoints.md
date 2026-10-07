# Checkpoints

One entry per tag, newest last. Format: tag, date, what works, what is stubbed, known issues, what a tester would look at. Rules in `docs/design/15_production_plan.md` §1.

## cp-00-design — 2026-10-07
- **Works:** nothing runs yet. The complete design (`docs/design/`), agent roles, and the vendored skills library.
- **Stubbed:** the entire `game/` project.
- **Known issues:** none.
- **Tester:** nothing to test.

## cp-01-foundation — 2026-10-07
- **Works:** Godot 4.7.2 pinned and fetched by script; the project opens headless with no errors; all eight autoloads with the 18-signal bus, Clock hitstop, SceneRouter; `tuning.gd` (~1,100 constants) and `strings.gd`; all data resources (6 strata, 7 items, 36 notes, 5 errors, 4 loadouts); `Seeds`; JetBrains Mono, the UI theme and 34 glyphs; the audio synth with 113 player and UI WAVs; `--smoke` exits 0; 129 tests green. `tools/ci/render.sh` renders Forward+ on the CPU, so agents check visuals themselves.
- **Stubbed:** title is a placeholder label; SettingsManager, SaveManager, AudioManager are API stubs; no level, player, or rendering yet; `--smoke` does not generate a level yet.
- **Known issues:** none blocking. Deferred items are in `docs/qa/open_items.md`.
- **Tester:** nothing to play. Optionally open `game/scenes/debug/ui_gallery.tscn` in the editor to see the font, colours and glyphs.

## cp-02-halls — 2026-10-07
- **Works:** Halls generates (1,000 seeds validate, deterministic, worker thread), builds time-sliced into merged, subdivided meshes with collision metadata, navigation bakes on a worker thread, and the light pool lends lights only to fixtures in view. The player walks, sprints, crouches, looks, toggles and cranks the flashlight, hides in lockers, and takes contact. World shader and Coherence post stack (two passes) are in, plus the HUD, inventory with Polaroid, Chalk and Glowstick, and the AudioManager with the Halls, player, UI, Static and Still sounds. `--seed N --depth 1 --stratum halls` launches into a walkable level; `--smoke` builds depth 1 headless; F3 shows a minimal debug overlay. 494 tests green.
- **Stubbed:** no title, run flow, exit, Landing, or death screen yet (direct launch only, without the HUD). No errors or Director. Noclip charge input is a seam only. Items spawn only through the bench and tests, not in levels yet.
- **Known issues:** see `docs/qa/open_items.md` (camera judder risk without physics interpolation, FSR 2 on Low, commit-frame lines lost under grain, note text wrap).
- **Tester:** optional. `godot --path game -- --seed 1 --depth 1 --stratum halls`, walk around, F to toggle the light, hold the crank key, F3 for the overlay. Look for: mouse feel, the light pools every 4 m, the hum.
