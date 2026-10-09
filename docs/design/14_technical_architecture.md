# 14 — Technical Architecture

**Depends on:** `00_OVERVIEW.md` and every system document's "Interfaces" section.
**Skills to read:** `godot-master` (routing), `godot-project-foundations`, `godot-autoload-architecture`, `godot-signal-architecture`, `godot-composition`, `godot-gdscript-mastery`, `godot-scene-management`, `godot-resource-data-patterns`, `godot-testing-patterns`, `godot-debugging-profiling`, `godot-performance-optimization`

---

## 1. Engine and toolchain

- **Godot 4.7 stable**, standard build (not .NET), GDScript only, typed. If 4.7 stable is unavailable from the official GitHub releases at build time, use the newest 4.x stable and record it in `tools/godot/VERSION`; never mix versions across agents. The skills library targets 4.7.
- **Renderer:** Forward+ (`rendering/renderer/rendering_method = "forward_plus"`). **Physics:** Jolt (`physics/3d/physics_engine = "Jolt Physics"`), with GodotPhysics3D as the documented fallback if a Jolt-specific issue blocks M1.
- **Binary fetch:** `tools/godot/fetch.sh` downloads the Linux headless-capable editor binary and the export templates for the pinned version into `tools/godot/bin/` (gitignored), verifies SHA-512 sums from the release page, and prints `GODOT_BIN`. All scripts use `$GODOT_BIN` (default `tools/godot/bin/godot`).
- **Import before anything:** `$GODOT_BIN --headless --path game --import` after any asset change (fonts, SVG, WAV). CI runs it first.
- **Python 3.11+** with numpy for `tools/audio/synth.py` and `tools/telemetry/plot.py` (matplotlib optional).
- **No other dependencies.** No addons from the Asset Library in v1.0 (the test runner is in-repo).

## 2. Repository layout

```
gameslop/
├── CLAUDE.md                      # agent entry point
├── docs/design/                   # this design
├── docs/qa/                       # checklists filled during milestones
├── third_party/gd-agentic-skills/ # vendored skills (reference only, not shipped)
├── tools/
│   ├── godot/fetch.sh, VERSION
│   ├── audio/synth.py, recipes.json
│   ├── fonts/fetch.sh
│   ├── ci/test.sh, export.sh, smoke.sh
│   ├── steam/app_build.vdf.template, depot_*.vdf.template
│   └── telemetry/plot.py
└── game/                          # the Godot project
    ├── project.godot
    ├── export_presets.cfg
    ├── src/
    │   ├── core/        # autoloads: event_bus.gd, game_state.gd, settings_manager.gd, save_manager.gd,
    │   │                #            audio_manager.gd, coherence_renderer.gd, clock.gd, scene_router.gd
    │   │                # plus tuning.gd (constants), strings.gd (UI strings), glossary names as StringName consts
    │   ├── player/      # player.gd, player_state_machine.gd, camera_rig.gd, flashlight.gd, noclip_targeting.gd, inventory.gd
    │   ├── levelgen/    # level_grid.gd, level_data.gd, level_generator.gd, level_builder.gd, level_validator.gd,
    │   │                # ops/*.gd, strata/halls.gd pools.gd garage.gd offices.gd server.gd substrate.gd
    │   ├── errors/      # error_base.gd, error_static.gd, error_still.gd, error_flicker.gd, error_echo.gd, error_null.gd, senses.gd
    │   ├── director/    # director.gd, scares.gd
    │   ├── items/       # item_data.gd, item_slot.gd, items/*.gd (polaroid, glowstick, flare, chalk, radio, fuse), polaroid_painter.gd
    │   ├── interactables/ # interactable.gd, door.gd, breaker.gd, exit.gd, hide_spot.gd, vending.gd, payphone.gd, note_pickup.gd, card_reader.gd
    │   ├── lighting/    # light_pool.gd, fixture.gd
    │   ├── ui/          # hud.gd, menu_shell.gd, title.gd, pause.gd, settings_menu.gd, archive.gd, run_summary.gd, note_sheet.gd, captions.gd, landing_panel.gd, glitch_transition.gd
    │   ├── audio/       # music_director.gd, generator_layers.gd (static bed, null tone)
    │   └── debug/       # debug_overlay.gd, screenshot_tour.gd, cli_args.gd
    ├── scenes/
    │   ├── main.tscn, title.tscn, run.tscn, level.tscn, landing.tscn, ending.tscn, summary.tscn
    │   ├── player/player.tscn, ui/*.tscn, errors/*.tscn, props/<stratum>/*.tscn, exits/*.tscn
    │   └── debug/ (audio_board, ui_gallery, levelgen_viewer, error_arena, items_bench, feedback_bench)
    ├── shaders/         # world_surface.gdshader, coherence_post.gdshader, static_field.gdshader, water.gdshader,
    │                    # monitor.gdshader, rack_leds.gdshader, locker_slats.gdshader, dissolve_grid.gdshader
    ├── data/            # strata/*.tres, items/*.tres, notes/*.tres, errors/*.tres, loadouts/*.tres
    ├── assets/          # audio/ (generated), ui/glyphs/*.svg, ui/noclip_theme.tres, fonts/
    └── tests/           # run_tests.gd, test_case.gd, unit/, levelgen/, sim/
```

Rules: `game/assets/audio/` is generated and committed (so builds do not need Python). `tools/godot/bin/` and `game/.godot/` are gitignored. Exports go to `build/` (gitignored).

## 3. Autoloads (exactly these eight)

| Autoload | Responsibility | Never |
|---|---|---|
| `EventBus` | The global signal bus (§4). Lifecycle and cross-system events only. | Hold state |
| `GameState` | `RunState` and `MetaState`; `start_run`, `descend`, `end_run`, `compute_score`; unlock evaluation | Touch nodes or UI |
| `SettingsManager` | Load/validate/apply/persist settings; bindings | Game logic |
| `SaveManager` | `meta.json` I/O with atomic writes | Interpret data |
| `AudioManager` | Sample playback, buses, reverb per stratum, ducking, pooling of `AudioStreamPlayer3D` (pool of 32) | Game logic |
| `CoherenceRenderer` | Global shader params, post stack, pulses, threat | Read player directly (it is fed by signals) |
| `Clock` | `hitstop(ms)` via tree pause, wall-clock timers that survive pause, run timer | — |
| `SceneRouter` | Scene changes with the glitch transition, threaded loads | — |

Everything else is a node in a scene. The Director is per-level. The HUD is a child of `run.tscn`. The player is a child of `run.tscn`, re-parented into each level.

## 4. The signal bus (canonical, complete)

```
# lifecycle
run_started(mode: StringName, seed: int)
level_entered(depth: int, stratum: StringName, arrival: StringName)   # arrival: &"proper" | &"drop" | &"start"
level_left(proper: bool)
run_ended(cause: StringName, score: int)
unlock_earned(id: StringName)
settings_changed(key: StringName, value: Variant)
# world
noise_emitted(pos: Vector3, radius: float, kind: StringName)
note_found(id: StringName)
item_picked(kind: StringName)
item_used(kind: StringName)
breaker_thrown(pos: Vector3)
exit_status_changed(status: StringName, timer: float)
hide_state(on: bool)
# errors and director
error_proximity(id: StringName, distance: float)
error_state(id: StringName, from: StringName, to: StringName)
director_phase(phase: StringName)
threat_changed(threat: float)
# presentation
audio_cue(text: String, pos: Vector3)
```

Eighteen signals. Adding one requires an entry in `CHANGELOG.md`. Direct signals (parent-child within a scene) are preferred for anything local; the bus is for crossing scene boundaries.

## 5. Scene flow

```
main.tscn (SceneRouter host)
 └─ title.tscn ──DESCEND──► run.tscn
                              ├─ Player (persistent across levels)
                              ├─ HUD
                              ├─ Level (level.tscn instance per depth: LevelBuilder output, LightPool, Director, errors, props)
                              ├─ Landing (landing.tscn, shown between levels)
                              └─ Summary (summary.tscn) ──► title.tscn
                           ending.tscn (from Substrate Threshold) ──► summary
```

Level transition: `GameState.descend(proper)` → `run.tscn` starts generating depth+1 on a worker thread → shows Landing (proper) or the drop black (drop) → when `LevelBuilder.built` fires, swaps the Level child, re-parents the Player at the spawn, calls `Director.begin`, emits `level_entered`.

## 6. Conventions

- **GDScript:** static typing everywhere (`var x: int`, `-> void`), `class_name` on every reusable script, `snake_case` files and members, `PascalCase` classes, `StringName` literals (`&"chase"`) for ids and states, constants in `tuning.gd` (no magic numbers in logic), `@export` for designer-facing values on scenes, `%UniqueName` node access instead of string paths, `@onready` for node refs.
- **Composition over inheritance:** `Interactable`, `Senses`, `HideSpotHost` are child-node components. The only inheritance trees are `ErrorBase` → the five errors, `StratumGenerator` → the six grammars, and `TestCase` → tests.
- **Signals up, calls down.** A child never calls `get_parent()` for logic. Cross-scene communication goes through `EventBus`.
- **Resources for data:** `StratumData`, `ItemData`, `NoteData`, `ErrorData`, `LoadoutData`. Mutable runtime copies use `duplicate(true)`.
- **RNG discipline:** no `randi()`/`randf()` in gameplay or generation. Every system takes an `RandomNumberGenerator` or a seed. UI and purely cosmetic effects may use a global cosmetic RNG seeded from time.
- **Threads:** generation data only; never touch nodes off the main thread; results handed over by `call_deferred`.
- **Hitstop and pause both use `get_tree().paused`** (`11` §4); nodes that must keep running during either (post quad, HUD, captions, pulse audio, Clock, SceneRouter, menus) are `PROCESS_MODE_ALWAYS`; everything in the level is pausable. There is no custom time scale.
- **Errors in code:** `assert()` for invariants (stripped in release), `push_error` for recoverable failures with a fallback.
- **Comments:** explain why, not what. Reference the design doc section when implementing a rule: `# 08 §4: Still freezes while observed`.
- **File size:** scripts over 400 lines are split. Functions over 60 lines are split.
- **No unused Godot features:** no `AnimationTree`, no `Lightmap`, no `GridMap`, no `CSG` at runtime (CSG is allowed only for authoring static prop scenes if simpler, baked to meshes).

## 7. Physics layers and groups

| Layer | Name | Who |
|---|---|---|
| 1 | `world` | Level geometry, props' static bodies |
| 2 | `player` | The player body |
| 3 | `errors` | Still, Echo bodies |
| 4 | `interactable` | Interactable colliders (ray target) |
| 5 | `items` | World item pickups |
| 6 | `hide_spots` | Hide spot volumes |
| 7 | `water` | Water areas |
| 8 | `thrown` | Glowsticks and flares in flight |

Groups: `errors`, `fixtures`, `doors`, `interactables`, `chalk`, `gameplay` (nodes affected by hitstop).

## 8. Testing

- **Runner:** `game/tests/run_tests.gd` (a `SceneTree` script). Discovers `test_*.gd` under `game/tests/`, instantiates each `TestCase`, runs `test_*` methods, prints TAP-style output, exits 0/1. Run with `tools/ci/test.sh` = `$GODOT_BIN --headless --path game --script tests/run_tests.gd`.
- **`TestCase`:** `assert_true/false/eq/ne/approx/gt/lt/null/not_null/contains`, `fail(msg)`, `await_frames(n)`, `make_rng(seed)`, and a `fake_clock` for Director and error timing tests.
- **Categories:** `unit/` (pure logic: tuning math, noise model, Coherence, noclip validity, inventory, settings, save), `levelgen/` (1,000 seeds per stratum; determinism), `sim/` (Director sawtooth; Still observation behaviour on a built level, headless, no rendering).
- **Headless limits:** no GPU in agent containers. Rendering-dependent checks (visual targets, feedback timing on screen) are done by the screenshot tour on the human's machine or by `godot-agent-vision` where a GPU exists. Tests never depend on rendering. `--headless` still builds scenes and runs physics and navigation.
- **Gate:** every merge runs `tools/ci/test.sh`; red blocks the merge.

## 9. Debug tooling

- `--seed N --depth D --stratum S` launches directly into a generated level (skips title).
- `--validate-levels N` runs the generator and validator N times per stratum headless and prints a report (also a test).
- `--tour [out_dir]` runs the screenshot tour (`02` §13): for each stratum, build seed 1, place the camera at 3 poses (spawn facing the longest sightline, a corridor mid-point, the exit room), capture at Coherence 100/60/30/10, plus a mid-noclip frame and a Null-at-8 m frame, and save PNGs with a JSON manifest. Requires a GPU.
- `--smoke` boots, generates depth 1, waits 2 s, quits with exit code 0; used by the export smoke test.
- **Debug overlay (F3, debug builds):** fps, frame ms split, draw calls, active lights, Director phase/intensity/aggression, each error's state and distance, Coherence, noise events (last 5), current cell, exit status, seed. Also toggles: show navmesh, show grid walls (wire), show critical path, god mode (no Coherence loss), teleport to exit, spawn error by id.
- **Bench scenes** listed in each system document.

## 10. Performance budgets (Medium preset, 1080p, GTX 1060-class)

| Budget | Limit |
|---|---|
| Frame time | 16.6 ms; render ≤ 10, physics ≤ 1.5, script ≤ 3, rest headroom |
| Draw calls | ≤ 1,500 (merged chunk meshes; props instanced; particles few) |
| Active lights | ≤ 24 (pool), shadowed ≤ 4 (+ flashlight) |
| Nodes in a level | ≤ 3,000 |
| Errors' per-frame script | ≤ 1.0 ms total at the largest roster (Cycle 2 depth 5: three Statics, Still, Echo, Flicker), as `ErrorTiming` reads it |
| Level build slice | ≤ 4 ms per frame |
| Navigation bake | ≤ 2 s on a worker thread for the largest level |
| VRAM | ≤ 1.5 GB; noise textures ≤ 1024² |
| Startup to title | ≤ 4 s |
| Memory growth per level | 0 after 10 levels (no leaks: `queue_free` and pools) |

Profiling: the `godot-debugging-profiling` skill's approach; the debug overlay's frame split is the first stop; `--print-fps` in headless for script-only budgets. M3.5: the perf bench (`scenes/debug/perf_bench.tscn`, `PerfBench` + `PerfProbe`) holds the Garage or the Server at its worst-case peak and reads every budget above per frame (script per system by process-priority bands, the physics step, nodes, drawn lights and shadows, and with `tools/ci/render.sh` draw calls, objects and VRAM); `tests/perf/` enforces them in `tools/ci/checkpoint.sh`; the frame times that need a GPU are the cp-12 human checklist `docs/qa/perf_checklist.md`; the readings are in `docs/qa/perf.md`.

## 11. Global shader parameters

Declared in `project.godot` under `[shader_globals]`: `g_coherence` (float 1.0), `g_noclip_charge` (float 0.0), `g_noclip_commit` (float 0.0), `g_noclip_target` (vec3 0,−1000,0), `g_noclip_target_normal` (vec3 0,0,0), `g_noclip_invalid` (float 0.0), `g_null_pos` (vec3 0,−1000,0), `g_null_radius` (float 0.0), `g_time` (float). `CoherenceRenderer` writes them in `_process`. Shaders include them from `shaders/include/coherence.gdshaderinc`.

## 12. Security and robustness

- `user://` only for writes. No network. No external process calls.
- All file reads validated. All `Dictionary` access with defaults.
- The game must survive: a missing audio file (silent with a `push_error`), a failed navigation bake (errors dormant, level still winnable), a level validation failure after 8 retries (fallback grammar), a corrupt save (reset with notice), a monitor change mid-run (re-apply window mode).

## Interfaces

Every system document's "Interfaces" section is the contract; this document owns the autoload list, the signal bus, the layout, and the conventions. Changes here are breaking changes and go through the orchestrator with a `CHANGELOG.md` entry.

### Interface additions during production
- `Clock`: `set_menu_pause(on)`, `is_menu_paused()`, `is_hitstopping()`, `hitstop_remaining_ms()`, `wall_timer(s) -> Clock.WallTimer`, `start_run_timer()`, `stop_run_timer()`, `run_seconds()`. The pause menu calls `set_menu_pause`; nothing else writes `get_tree().paused` except `Clock.hitstop`. The run timer excludes pause-menu time. `g_time` freezes during hitstop and pause.
- `SceneRouter`: `set_host`, `get_host`, `change_to`, `is_loading`, `current_path`, `current_scene`, signals `scene_changed`/`scene_failed` (local to SceneRouter, not on the bus), `transition` property.
- `CoherenceRenderer`: `set_noclip_charge(v)`.
- `GameState`: `is_run_active()`, `last_cause()`. Helper scripts `RunState` and `MetaState` live beside it.
- `SettingsManager`: `REBINDABLE_ACTIONS`.
- `CoherenceRenderer` (M1.5): `post_quad()`, `screen_layer()`, `pulse_frames(kind)`, read-only `post_params`, `reduce_noise`, `reduce_flashing`; it listens to `SettingsManager.changed` for `reduce_visual_noise` and `reduce_flashing`, and on `run_started` takes the start Coherence from `GameState.run.coherence`. Pure curves in `CoherencePost` (`game/src/core/coherence_post.gd`).
- `CoherenceRenderer` (R3): `set_noclip_target(pos, normal)`, `set_noclip_invalid(on)`, `set_static(amount)`, pulse kinds `ripple` and `drop` (`drop` fired at the floor commit and again on the drop arrival), `heartbeat_phase()` and `heartbeat_bpm()` (AudioManager should lock the heartbeat sample to the phase), `apply_texture_detail(level)` (listens to the `texture_detail` setting), `register_viewport(vp)` / `unregister_viewport(vp)` / `registered_viewports()`. Viewports: the globals reach world shaders in every viewport already; the post stack grades only the main viewport, and a registered SubViewport (monitor, Polaroid) is only recorded for now. Grading SubViewport cameras is future work. The scene pass quad is visible only while Null is present. `SettingsManager.DEFAULTS` gains `reduce_visual_noise` and `reduce_flashing` (both false).
- Rendering helpers (M1.5): `StratumEnvironment.build(data, preset) -> Environment`, `StratumEnvironment.apply_viewport_preset(viewport, preset)`, `DustMotes.create(particle_scale)` with `follow` (`game/src/lighting/`). Halls materials in `game/data/materials/halls/`.
- M1.9 `Run` (`scenes/run.tscn`, `src/core/run.gd`): `phase` (`loading`, `playing`, `entering`, `landing`, `dropping`, `dissolving`, `ended`), `level`, `data`, `exit`, `breaker`, `landing`, `arrival`, `commit_drop()`, `drop_transform()`, signals `phase_changed(phase)`, `level_ready(depth)`. It connects `floor_drop_committed()` by name on the Player or its `noclip_targeting`, and calls a level's Director (a node named `Director` or in group `director`) as `begin(level, player, arrival)` with as many arguments as `begin` takes. `RunLevelSetup` (static): `prepare`, `run_power_wave`, `item_pool`, `landing_choices`, `pick_drop_cell`, `is_drop_cell`, `open_dir`. `Landing` (`scenes/landing.tscn`): `begin(player, kinds, hint)`, `door_may_open(t, hold, built, walkable)`, signals `choice_made`, `door_opened`, `finished`. `GlitchTransition` (`src/ui/glitch_transition.gd`) is installed by `main.gd` as `SceneRouter.transition`; `main.gd` routes to `scenes/title.tscn` by default. `DissolveGrid` draws the 48 × 27 dissolve. Bench: `scenes/debug/run_bench.tscn -- --shots <dir>`.
- M3.5 performance pass: `PerfBench` (`src/debug/perf_bench.gd`, `scenes/debug/perf_bench.tscn`: `stratum`, `depth`, `seconds`, `warmup`, `measure() -> Dictionary`, signal `finished(result)`, `seed_for(stratum, depth)`) and `PerfProbe` (`src/debug/perf_probe.gd`: `roots`, `level`, `harness_ms`, `start()`, `stop()`, `summary()`, `stats(values)`). `LightPool.lit_fixtures_near(pos, radius, group = -1)` (an optional group filter) and `FixtureGroups.lit_near(..., group = -1)`; the pool answers its queries from `FixtureIndex` buckets (`src/lighting/fixture_index.gd`). `AudioCull` (`src/audio/audio_cull.gd`): `mark(loop)`, `tick(players, listener_pos)`, `is_culled(p)`; AudioManager runs it with the occlusion pass, ServerFan and Vending mark their loops. `Level.fade_small_lights(root)`, `Level.is_drawn(light, from)`, `Level.light_counts(root, from = INF)` (with `from`, only lights not past their distance fade); the F3 overlay's first lines read FPS, FRAME (1000 / fps), PROCESS and PHYS (the engine's worst step over the last second), then GPU, RENDER CPU and VRAM. `BuildSlopes.plan` is a weak reference (the plan owns it).
- R19 performance (additive; no number moved): the arrival is spread over frames within the 4 ms build slice. `StepQueue` (`src/core/step_queue.gd`: `append`, `append_all`, `run(budget_ms) -> bool`, `is_done`, `clear`, `frame_ms`, `slice_budget_ms()`). `RunStaging` (`src/core/run_staging.gd`): `request_prefabs(data)` (the run calls it when the level data is ready: the exit and breaker prefabs and the error scenes load on a worker while the level builds; unheld, each was read from disk again in the arrival's frames), then the coroutine `prepare(level, data, still, ms)`: after `geometry_ready`, `RunLevelSetup.prepare_props(level, data)` in one frame (holding `take_prefabs(data)`), `RunLevelSetup.populate_steps(level, data, out)` (over `ItemSpawner.populate_steps(root, data, rng, out, options)`; `prepare` and `populate` keep their one-call forms) at a slice a frame, `warm_audio(level, stratum)` (the room tone and the fixtures' hums into the library cache) with `take_error_scenes()`, `Level.prelight(eye_height)` (the pool lent from the spawn's eye; `attach_player` frees its marker; skipped at a proper exit, `prepare(..., prelight = false)`, whose arrival frame is under the transition); the arrival in the next frame; a drop's `drop_transform()` one frame before it. `Run.arrival_ms` (`props`, `pickups`, `audio`, `prelight`, `arrive`). `ErrorBase.scene(id)`, `has_scene(id)`, `provide(id, packed)`: the error scenes stay loaded once used (`create` instances from them). `RunLevelSetup.begin_director(level, player, kind, staged = false)`; the run passes true: `Director.staged`, `Director.arrival_work: DirectorArrival` (`src/director/director_arrival.gd`: `roster_steps(director, roster)`, `plan(roster)`, `queue`), `Director.is_arriving()`. Staged, `begin` reads the pose and starts the clock, Calm and listeners at once, and the roster (fair-cell context, the fair-cell scan in chunks of `FALLBACK_CHUNK_CELLS`, the pick, one spawn a step, the awake arrivals and Static bounds, the aggression) runs a slice a frame; whatever is left runs before the first 0.1 s tick, so the rng draws and the first tick are unchanged. `DirectorSpawn.pick_cells(..., band, ctx = {})` with `pick_context(data, pos)` / `fallback_chunk(data, ctx, pos, eye, fwd, half_fov, cells)`; `DirectorSpawn.off_path_mask(grid, path)` and `off_path_cell(grid, path, from, mask = [])` (`DirectorHunters` keeps the mask per level); `LevelGrid.distance_field(from, max_cells = -1)`; `DirectorSpawn.ring(grid, centre, rmin, rmax, filter)` and `pick_in_ring(ring, rng)` (`cell_in_ring` is the two; `DirectorHunters` shares one scan among the hunters it hints from one spot in one frame); `StaticPaths.cell_path`, `cell_in_ring` and `farthest_cell` give the same answers faster. `HideSpot.view_offset` / `exit_offset` (local transforms) replace the `ViewPoint` / `ExitPoint` marker nodes (`view_transform()` / `exit_transform()` unchanged); the under-desk host is its own `StaticBody3D` (3 nodes). Tests: `tests/perf/test_level_nodes.gd`, `test_arrival_frames.gd`, `test_r19_equivalence.gd`.
- M2.15 `SceneRouter.change_to(path, with_transition = true)`: false swaps without the glitch transition (the Threshold's cut to white is its own transition). `run.gd` routes the win to `scenes/ending.tscn`, which routes to the summary (or, in the variant, to the next run).

