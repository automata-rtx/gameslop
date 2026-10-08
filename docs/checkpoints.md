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

## cp-03-noclip — 2026-10-08
- **Works:** noclip through walls, soft walls and floors (hold the noclip key): target query with the four invalid reasons (SOLID, TOO FAR, TOO THIN, NO SPACE, including the never-into-a-void rule), 0.35/0.6/2.5 s charge, 5/10/30 Coherence, cancel paths, 80 ms hitstop and the 250 ms pass, floor drop hook. The charge preview is a wireframe disc anchored on the target; the HUD shows the cold arc, readiness ring and reason. The Coherence renderer (two passes) and the world shader respond to everything. 523 tests green.
- **Stubbed:** floor drop in direct launch respawns at spawn (the run flow takes it over at cp-05). Direct launch has no HUD yet; HUD screenshots come from `noclip_shots.tscn`.
- **Known issues:** in the commit frame the world lines within 3 m are nearly invisible (being fixed in the world shader); the invalid world preview is faint.
- **Tester:** optional. Direct launch as at cp-02, hold the noclip key at a wall between two corridors.

## cp-04-still — 2026-10-08
- **Works:** Static (drifting drain field) and Still (moves only when unobserved and unlit) on a shared ErrorBase with senses, notice and evasion, navigation pathing and the render-line tick. The Director runs per level: Calm/Build/Peak/Relief sawtooth, aggression, roster per depth, fair spawns (≥ 20 m, out of view and sight), contact exclusivity (3 s, refused errors retreat), Satiated, awake arrivals after drops, telemetry, F3 lines. The full loop from cp-05 content is already present: title, run, breaker and power wave, Powered exit, Landing with item choice, drop arrival, dissolve, summary. Windows and Linux exports build with `tools/ci/export.sh`. A headless bot reaches the depth 1 exit on 5/5 seeds. 637 tests green.
- **Stubbed:** scares, Echo/Flicker/Null, other strata (depths 2+ generate as Halls), score.
- **Known issues:** floor drop edge cases (death impossible mid-fall, unbounded fall) are being fixed for cp-05; see `docs/qa/open_items.md`.
- **Tester:** optional. Launch normally, DESCEND, find the breaker, take the exit. Watch for Still in lit corridors.

## cp-05-loop — 2026-10-08
- **Works:** the whole depth-1 loop: title, DESCEND, breaker and power wave, Powered exit, Landing with item choice and +20 Coherence, depth 2; noclip through walls and floors with the drop arrival (`DROPPED · THEY ARE AWAKE`), never fatal or wasted mid-pass (refund on a failed landing, no loss while dropping or in the Landing); dissolve and the run summary with a cause line; Polaroid, Chalk, Glowstick, notes; Static and Still under the Director; audio for all of it. 658 tests green; Windows and Linux exports build.
- **Stubbed:** score, unlocks, settings menu, other strata (depths 2+ are Halls), Echo/Flicker/Null, scares.
- **Known issues (being fixed now):** Still can get stuck against an open door leaf; an unlit Still is drawn more clearly than it should be; the Director's intensity does not rise for a quiet player; Static looks like dark smoke. See `docs/qa/open_items.md`.
- **Tester:** optional; same as cp-04.

## cp-06-slice — 2026-10-08
- **Works:** M1 complete and reviewed (M1.13), plus early M2. The full loop: title (Descent, Daily, Archive, settings with full rebinding), Halls, Pools and Garage levels (1,000 seeds each validate), the player, noclip, the Coherence renderer, HUD, items, Static and Still under the Director (Peak only with a chase, real Relief, a hunter on every level, fair spawns), breaker and exit, Landing, drop, dissolve, summary with score and unlocks, saves in a NOCLIP user folder. `tools/ci/checkpoint.sh` is green: 837 tests with budgets enforced, validator, smoke, Windows and Linux exports, Linux smoke four ways. The feedback bench passes every implemented row; the screenshot tour passes T1/T3/T4 for Halls and Pools.
- **Stubbed:** Offices, Server, Substrate (depths 4–6 generate as an earlier stratum); Echo, Flicker, Null (Still stands in); Flare, Radio, Fuse, Keycard; scares; music; first-run hints; captions; the ending.
- **Known issues:** Garage is too dark near the camera (tour T3 fails on Garage poses); Garage sim runs sometimes get the bot stuck; an intermittent worker-thread crash in sim children under heavy load (being root-caused); see `docs/qa/open_items.md`. Not verified without a GPU: frame times, mouse feel, audio by ear, the shortened Still column under door headers.
- **Builds:** not attached (no GitHub release access in this session). Build from the tag with `tools/ci/export.sh` (needs `tools/godot/fetch.sh --templates`); outputs `build/NOCLIP-1.0.0-{windows,linux}.zip` with checksums.
- **Tester (optional, 10 minutes):** `docs/qa/human_check_cp-06.md`.
