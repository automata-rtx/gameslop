# Open items (orchestrator)

Deferred work found during production. Each line names the task that should absorb it.

- M1.6: the theme carries a `NoclipTokens` type and named text-role styles (see `game/src/ui/ui_tokens.gd` and the M0.5 commit); add them to 04 Interfaces when the HUD lands.
- M1.2 / lighting: fixture prefab paths `res://scenes/props/<stratum>/fixture_<kind>.tscn` are referenced by StratumData and do not exist yet.
- Placeholder values chosen in M0.4 (item use times, shadow bias, reverb predelay, loadout descriptions) are listed in that commit; revisit in M3.4.
- M1.4/M1.5: `g_noclip_commit` currently decays 1→0 over 300 ms; 06 §8 wants it held at 1.0 for the 250 ms pass, then decay. Add a hold.
- M1.11 / human cp-06: listen for tile step reading as ceramic (not a beep), the 60 ms silence in noclip commit, and natural sprint breath.
- M1.12/M3.1: camera parented to the body without physics interpolation may judder; consider enabling `physics/common/physics_interpolation` and mouse look in `_process`. Needs a human with a mouse.
- M1.5 follow-up: held flashlight should use the world shader with `held=1`; locker mask should use `locker_slats.gdshader`; dust particles.
- M2.4 (Echo): `Player.step_trail()` is not implemented.
- M2 / Static: inside Static the post grain goes to 0.6 and CA to 0.02 (02 §8); `CoherenceRenderer` has no feed for it yet. Proposed: `CoherenceRenderer.set_static(amount)`.
- Lighting task: the Halls fixture prefab (`scenes/props/halls/fixture_tube.tscn`) can reuse `data/materials/halls/fixture_emissive.tres`; the render bench hangs the omni 0.3 m below the tube so the ceiling reads lit.
- M1.10/M3.6: typed note text wraps with a leading space on the new line (note sheet, 1280x720 H3); UI scale for 720p arrives in M3.6; ui_dim text over bright fixtures has no backing.
- M1.11b/M2.14: AudioManager heartbeat should lock to `CoherenceRenderer.heartbeat_phase()` instead of its own timer.
- M1.2 follow-up / M3.5: `apply_viewport_preset` (game/src/lighting/stratum_environment.gd) needs FSR 2 when render scale < 1.0.
- M2.11: add a `texture_detail` settings key; CoherenceRenderer.apply_texture_detail is ready.
- M1.9/M2.10: GameState must subscribe to note_found and record notes into run/meta; add meta.stats.strata_reached (ItemSpawner uses found notes as a proxy for tier 2).
- M2.1: `BuildPlan` builds Halls only (`SUPPORTED_STRATA`); per-cell floor heights, ramps, basins, racks and water arrive with the other grammars (see `TODO(M2.1)` in `build_plan.gd`).
- M3.x: void blocks have collision but no rendered inner faces; at full unrender (screen door, u ≥ 0.95) a wall next to one shows the next corridor through the block rather than a filled volume. Normally hidden.
- M3.x: chalk at nothing uses `ui_hold_tick` pitched down as its dull tick; a dedicated `chalk_tap` recipe would be better (03).
- M3.2: Static reads as dark smoke (offset pulls in the dark corridor end); 02 §8 wants a faint refraction shimmer. Still column top is rounded like a door arch; consider a flat top.
- M2.13/M3.2: Landing cabin is dim grey metal; door barely reads; give the cabin its own look (02) and a readable door.
- Player owner: `Player.look()` refuses mouse look in Landing; 05 §4 wants a free cabin camera.
- HUD owner: needs a dim keyless prompt (`FUSE MISSING` for Variant B breaker without a fuse); clear the exit line while in the cabin.
- M2.1: depths 2+ generate as Halls until the other grammars exist (HUD shows HALLS, summary names the planned stratum).
- M2.2: decide rack noclip (07 §7 says racks are WALL on all four faces, but a rack cell is not walkable so the query says NO SPACE). Proposal: a rack face passes through the whole rack to the far walkable cell.
- Errors owner: `sim/test_still.gd::test_satiated_retreats_away` failed once and passed on rerun (R5 report). Find the nondeterminism (physics timing, nav bake timing) and make it deterministic.
- M2.10: use a custom user folder (`application/config/use_custom_user_dir`, name `NOCLIP`) so saves live in %APPDATA%\NOCLIP and ~/.local/share/NOCLIP; update README.txt.in. Windows build smoke must be run on Windows by the human at cp-13.
- Errors owner: `ErrorBase.start_search` before navigation is ready ends in Wander, not Search (Director re-calls it on navigation_ready as a workaround).
- M2.14: Director should feed `MusicDirector.set_intensity` once it exists.
- M2.7/M3.4: the sim bot walks the critical path and never provokes Peak; add an exploring/sprinting bot profile so simulated playtests cover the full sawtooth on real levels.
- Player owner: player.gd is 421 lines (limit 400, 14 §6); split it in the next player task.
- M2.11: title shows `SaveManager.consume_reset_notice()` and the Daily result; title asks `GameState.is_mode_available`/`is_loadout_available` before start_run.
- Player/run owner: apply `RunState.crank_rate_mult` (player crank) and `flicker_attract_mult` (Flicker, M2.5); update `RunState.distance_m` from player movement.
- (M2.10 done: custom user dir, note recording, strata_reached, score via Clock.)
