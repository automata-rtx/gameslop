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
