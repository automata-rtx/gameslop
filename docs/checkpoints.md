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

## cp-07-pools-garage — 2026-10-08 (commit 1dd067d)
- **Works:** Pools (drained, shallow and full basins, steps, ladders, lane ropes, water volumes with wading, caustics and a real water shader) and Garage (split-level decks joined by ramps, pillars, parked cars with under-car hide spots, sodium lamps), each with materials, props and audio; 1,000 seeds each validate. Also on this commit: Echo, Flare/Radio/Fuse/Keycard, vending, payphone, every hide spot, the engine audio-race guard, and the cp-06 loop. `tools/ci/checkpoint.sh` green (977 tests with budgets enforced, validator, exports, Linux smoke).
- **Stubbed:** Flicker (Still stands in), locks other than Open/Powered, scares, Substrate, Null, captions, music.
- **Known issues:** Pools exit is a plain slab (fixed at cp-09); see `docs/qa/open_items.md`.
- **Tester:** optional. A Descent reaches Pools or Garage at depth 2.

## cp-08-offices-server — 2026-10-08 (commit 1dd067d, same as cp-07)
- **Works:** Offices (ring corridor, cubicle partitions you can see over, glass meeting room, dark fixture groups until the breaker, desks with under-desk hide spots, monitors) and Server (staggered rack aisles lit by LEDs, cages, a floor hatch exit, rack noclip through the whole rack); 1,000 seeds each validate. Dark strata are measured with the flashlight on (CHANGELOG).
- **Stubbed / known issues / tester:** as cp-07 (both strata merged before the cp-07 look pass, so they share the commit).

## cp-09-echo-flicker — 2026-10-08
- **Works:** all four hunting errors: Static, Still, Echo (follows heard footsteps 800 ms behind, freezes when you stop, lured by noise) and Flicker (lives in lit fixtures, lunges, latches onto a flashlight; darkness and chemical light are its counters; only Flicker makes lights flicker). All four locks with an exit prefab per stratum (elevator, drain hatch, stairwell door, floor hatch; Open, Powered with Variant B fuse, Keyed with the card reader, Cycled on a timer). Flare, Radio, Fuse, Keycard, vending, payphone, every hide spot. The Director's scares (rare, Build only, never near a hunter), full roster, chaser caps, awake arrivals, Pursuit schedule, telemetry. Also on this commit: the Substrate grammar with the Threshold door (a win ends the Descent), Cycle 2 corruption, captions and first-run hints, accessibility wiring, the generative music director, the Null tone generator. `tools/ci/checkpoint.sh` green: 1,111 tests with budgets enforced, validator, exports, Linux smoke.
- **Stubbed:** Null itself (the error), the ending scene and credits, the title's live corridor.
- **Known issues:** a few contacts in sims came without a chase (mostly Echo, some in Relief); Garage colliders the grid does not know about; see `docs/qa/open_items.md`. Not verified without a GPU or ears: frame times, mouse feel, every sound and the music.
- **Tester:** optional. A full Descent reaches the Substrate and its Threshold door.

## cp-10-substrate — 2026-10-09 (commit 45497b5)
- **Works:** the Substrate (lines on black, soft walls, checker rooms, the Threshold door) and Null: Dormant through the 30 s calm, then the Pursuit. It walks straight at the player through every wall at 2.4 m/s (2.8 in Cycle 2). The 12 m unrender radius lets you see the layout through walls (24 m from depth 12), and the 2 m core drains 12/s with the screen black and only the grid tone left. It never contacts. If it is within 20 m when it wakes, the Director first moves it unseen to a fair cell (ahead of the player on the path, or behind a player already past halfway). Crossing the Threshold plays the ending (white cut, the corridor, DEPTH 0, NOCLIP, credits per 16 §6), then the summary; the variant shows when all 36 notes are found; the ending is skippable from the second win. Cycle 2 corruption and its 0.2/s Substrate drain. Contacts come only from a chase. `tools/ci/checkpoint.sh` green: 1,260 tests with budgets enforced, the validator, exports, Linux smoke.
- **Stubbed:** stratum-themed Landings (every Landing is the elevator cabin; M3, S12); Pools bubbles and Substrate rising pixels (N4); the Archive credits page (M3.6).
- **Known issues:** Null is still too lethal for the bots. Depth-6 sims exit direct 6/12, explorer 7/12, cautious 9/12, and whole Descents reach the Threshold 8 of 30 times, mostly losing to Null. The final tuning goes to M3.4 with human runs (`docs/qa/descent_sim.md`, `open_items.md`). Not verified without a GPU: frame times, the unrender halo at 1080p, the checker's magenta under AgX, audio by ear.
- **Tester (optional):** `$GODOT_BIN --path game -- --seed 1 --depth 6 --stratum substrate`. Wait 30 s, then route to the Threshold around Null using what the unrender shows (noclip through soft walls).

## cp-11-meta — 2026-10-09 (commit 45497b5, same as cp-10)
- **Works:** score, unlocks and their notifications, loadouts (Lightbearer now cranks ×1.5), Daily, Endless, `meta.json` saves, the Archive, complete settings with rebinding and live test, `auto_sprint`, captions, first-run guidance, accessibility options (Flicker intensity 0.3 is now a 2 Hz pulse), the music director, the LICENSES page under the title's settings, a real DISTANCE WALKED. M2 is done and reviewed (`docs/reviews/M2_cohesion.md`, every blocking and should-fix finding fixed except S12 for M3). All five errors in the arena (keys 1–5); a chained Descent sim from depth 1 to 6.
- **Stubbed:** the title's live corridor (M3).
- **Known issues:** as cp-10; see `docs/qa/open_items.md`.
- **Tester (optional, 30–45 minutes, needs a GPU):** `docs/qa/human_check_M2.md` with the save fixture `docs/qa/fixtures/meta_m2_mid_save.json`.

## cp-12-cohesion — 2026-10-09 (commit e0caa96) — **for the human to play**
- **Works:** M3 is complete and reviewed (`docs/reviews/M3_cohesion.md`, no blocking findings).
  - **Feedback Contract:** all 47 rows ticked from the bench (`docs/qa/feedback_checklist.md`).
  - **Visual targets:** T1 to T8 pass the histogram script for every stratum and Cycle 2 (107 checks). T5/T6 are judged by eye in `docs/qa/visual_targets_by_eye.md`.
  - **Audio:** mix pass (Errors headroom, Echo's step level, occlusion and caption coverage tests).
  - **Tuning and performance:** tuning from 60 simulated Descents; performance pass with budgets enforced at the Garage and Server peak, plus R19/R21 hitch and CPU fixes.
  - **UI:** UI fits at UI scale 0.75 to 1.5 and 1280x720 to 2560x1440; the title's live corridor; Archive credits.
  - **Text:** a text gate (forbidden words, punctuation, model names).
  - **New here:** Pools bubbles, Substrate pixels and the Substrate's white Landing pocket.
  - **Gate:** `tools/ci/checkpoint.sh` green: 1,400 tests with budgets enforced, validator, exports, Linux smoke.
- **Stubbed:** stairwell Landings for Pools and Server (they still use the cabin; M4); Archive Polaroid thumbnails (M4).
- **Known issues:** see `docs/qa/open_items.md`.
  - Slow explorers can sit at the top of dread for minutes in Build.
  - The first visible frame of a Descent is 6.5 to 10.5 ms headless.
  - Server peak script headroom is 0.2 to 0.35 ms.
  - Not verified without a GPU or ears: frame times, bloom, AgX, every sound.
- **Tester (wanted, about 30 minutes plus optional parts):** `docs/qa/human_check_M3.md`, with notes in `docs/qa/notes_cp-12.md`. Optional parts: L listen check, P performance, A accessibility, G GPU visuals, T targeted runs.

### cp-12 tuning questions (M3.4)
- **Tuned from sims (M3.4):** 60 simulated Descents before and after (`docs/qa/descent_sim.md`). Null's core drains 10/s (was 12); a death names the largest loss within 0.25 s. Threshold reached: direct 8 → 16, cautious 8 → 11, explorer 0 → 0 of 20. Most of the old Null lethality was the sim bot walking rooms cell by cell.
- **The 5 human runs must confirm:** (1) the Substrate is hard but winnable at 10/s, and whether players route around Null with the unrender view or walk through its core; (2) Still's counter works for a human: keeping it lit in view and backing away, or hiding, ends its chase at depths 2 and 5 (the sims record 3 Still evasions in 279 levels, so no Still number was changed); (3) a new player reaches depth 2 within three attempts and early deaths take 5 to 10 minutes; (4) the Offices light dilemma reads as a choice (breaker and flashlight against dark, the glowstick as the answer); (5) how much noclip a human spends and the Coherence at depth 6 arrival (sims: 90+); (6) the sawtooth by ear: a long Build while exploring should not feel like constant maximum dread (R20: the crank row now counts only in Build, Peak and Pursuit). **Landing gain decision rule (R20, M3 review S1, pre-agreed):** if the human runs arrive at depths 3 to 6 averaging 90 or more Coherence, cp-13 halves the Landing gain to 10; below 70 it stays 20. Record per run: depth reached, cause, Coherence at each arrival, Null core time if any.


## cp-13-rc — 2026-10-09 (commit 4b131df) — **release candidate, needs a clean-machine run**
- **Works:** everything in cp-12, plus the release pipeline:
  - **Builds:** export presets per 16, icons generated from `noclip.svg`, `export.sh`, `verify_release.sh` and `smoke.sh`. The zips contain README, LICENSES and SHA256SUMS, and nothing from the debug benches or the F3 overlay ships in release.
  - **Credits:** a root `CREDITS.md`.
  - **Steam:** templates and `tools/steam/upload.sh`, which refuses placeholder IDs and never sets a build live.
  - **Store page:** `docs/release/store_page.md`, checked by the text gate.
  - **Release checklist:** filled in (`docs/qa/release_checklist.md`).
  - **Landings and Archive:** stairwell Landings for Pools and Server, and Polaroid thumbnails in the Archive.
  - **Checkpoint:** `tools/ci/checkpoint.sh` green, with 1,423 tests (budgets enforced), the validator, both exports verified and the Linux smoke.
- **Builds:** `build/NOCLIP-1.0.0-windows.zip` and `build/NOCLIP-1.0.0-linux.zip` are not committed; rebuild them with `tools/ci/export.sh`. Check them against the SHA256SUMS file that ships with the zip.
- **Pending human data:** the cp-12 tuning decisions (the Landing gain rule first). See the table in `docs/qa/human_check_M4.md`.
- **Not verified here:** the Windows smoke, SmartScreen or antivirus prompts, real GPU frame times, and audio.
- **Tester (needed for cp-14):** `docs/qa/human_check_M4.md` on a clean Windows machine, about 20 minutes, with notes in `docs/qa/notes_cp-13.md`. Then cp-14 applies the fixes from the cp-12 and cp-13 notes, and uploads to Steam with `tools/steam/README.md`.
