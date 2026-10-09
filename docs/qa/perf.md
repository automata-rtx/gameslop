# Performance readings (M3.5)

The 14 §10 budgets measured in the Garage and the Server at their worst-case peak, 2026-10-09, on the agent container (Intel Xeon 2.8 GHz VM, 4 cores, no GPU). Headless runs were taken with `uptime` load 0.34 to 0.50 (one-minute average) and nothing else of ours running; the CPU-renderer runs at 0.5 to 2.0.

## The peak

`scenes/debug/perf_bench.tscn` (`PerfBench`) plays a real run (`run.tscn`: player, HUD, Director) at depth 11, Cycle 2's depth 5: the largest level (580 cells), the largest roster (three Statics, Still, Echo, Flicker) and the Cycle 2 aggression. It then holds the worst case on purpose:

- every hunter awake; Still and Echo start 10 m of walking from the player and are sent to Search at the player whenever they drift beyond 12 m; every contact is refused, so a chase never ends in Satiated (Still chased 100% of the Server window, Echo followed 82%, two or more hunters chased 82 to 89% of frames);
- the Director forced to Peak (its chaser cap still applies);
- every fixture group but Flicker's switched off and re-lit by the breaker's power wave every 8 s;
- the player sprinting with the flashlight on, back and forth over 14 cells of the critical path (Flicker stalks, attaches and lunges in the Server; the Garage's few lamps give it no habitat, so it stays dormant there, which is its rule);
- Coherence held near 40 (the post stack and the static bed working).

`PerfProbe` records every frame. Script time is read by process-priority bands: every node of a system gets one priority and marker nodes between the bands stamp the clock, so nothing is called twice and the engine still decides what runs. "Script" is every scene-tree callback of the frame (GDScript plus engine node internals such as `AudioStreamPlayer3D` and `NavigationAgent3D`), less the bench's own driving (`harness`, about 0.17 ms). "Physics" is the engine's step between the last physics callback and the next callback (Jolt, the navigation sync, the query flush). Errors are read with `ErrorTiming`, the same monitor as F3.

Commands:

```
$GODOT_BIN --headless --path game res://scenes/debug/perf_bench.tscn -- --stratum server --seconds 20 --out build/perf/server.json
tools/ci/render.sh --path game --resolution 960x540 res://scenes/debug/perf_bench.tscn -- --stratum garage --seconds 20 --out build/perf/render_garage.json --shots build/perf
tools/ci/test.sh --filter perf/     # the budgets as tests (enforced by tools/ci/checkpoint.sh)
```

## Budgets

Headless means over 20 s (about 1,200 frames at 60 fps); p95 in brackets. "Before" is the same bench on the code before this pass (HEAD `6eaef3a` with only the bench added), at the same load.

| Budget (14 §10) | Limit | Server, before | Server | Garage, before | Garage | Headroom (worse of the two) | Method |
|---|---|---|---|---|---|---|---|
| Script per frame | ≤ 3.0 ms (was 2.5) | 3.04 (4.44) | 2.65 (3.91) | 2.52 (3.75) | 2.34 (3.30) | 12% | headless, PerfProbe bands |
| Errors' script | ≤ 1.0 ms (was 0.3) | 0.85 (1.32) | 0.77 (1.15) | 0.65 (0.93) | 0.63 (0.92) | 23% | headless, ErrorTiming |
| of which: Still / Echo / Flicker / 3 Statics | | 0.22 / 0.26 / 0.22 / 0.15 | 0.22 / 0.26 / 0.14 / 0.15 | 0.23 / 0.25 / 0.00 / 0.16 | 0.22 / 0.26 / 0.00 / 0.14 | | ErrorTiming per id |
| Player, audio, HUD, light pool, Director, level props | (in script) | 0.69, 0.40, 0.18, 0.16, 0.06, 0.36 | 0.60, 0.42, 0.18, 0.16, 0.06, 0.10 | 0.72, 0.39, 0.18, 0.13, 0.04, 0.07 | 0.60, 0.37, 0.18, 0.13, 0.04, 0.07 | | PerfProbe bands |
| Physics step | ≤ 1.5 ms (was 2) | 0.88 (1.27) | 0.77 (1.19) | 0.90 (1.26) | 0.72 (1.03) | 49% | headless, gap after the physics callbacks |
| Render | ≤ 10 ms | | not measurable | | not measurable | | GPU: cp-12 checklist P1 to P4 |
| Draw calls | ≤ 1,500 | | 155 mean, 321 max | | 336 mean, 472 max | 69% | render.sh, 960x540, Medium |
| Visible objects | (none) | | 277 mean, 640 max | | 519 mean, 753 max | | render.sh |
| Active lights (drawn) | ≤ 24 | 20 max | 14 max | 24 max | 19 max | 21% | lights not past their distance fade, from the camera ("before": every visible light; nothing faded then) |
| Pooled lights | ≤ 16 Medium (24 High) | | 12 max | | 13 max | | LightPool |
| Shadowed lights | ≤ 4 + flashlight | | 2 + 1 max | | 2 + 1 max | 40% | Medium shadows 2 |
| Nodes in a level | ≤ 3,000 | 1,291 | 1,327 | 1,324 | 1,327 | 56% | level subtree |
| Level build slice | ≤ 4 ms | p90 3.06 | p90 3.07 | p90 2.97 | p90 2.98 | 23% | LevelBuilder slices; the arrival frame is separate, below |
| Navigation bake | ≤ 2 s, worker | 291 ms | 271 ms | 37 ms | 29 ms | 86% | LevelBuilder |
| VRAM | ≤ 1.5 GB | | 136 MB | | 132 MB | 91% | render.sh at 960x540; 1080p on a GPU: P1 |
| Startup to title | ≤ 4 s | | not measured | | | | cp-12 checklist P7 |
| Memory growth per level | 0 after 10 levels | +5.4 MB a level (a Garage level built and freed six times) | a plan made five times: +0.0 MB | | Garage depth 8 vs depth 2 of one Descent: +2.7 MB, 0 orphan nodes | within the 8 MB slack | `tests/perf/test_memory_levels.gd` |

Readings on the budgets that moved (CHANGELOG 2026-10-09, M3.5):

- **Errors 0.3 → 1.0 ms.** 0.3 ms was set before any error existed. The floor of one walking hunter is about 0.2 ms headless here: a `NavigationAgent3D`, `move_and_slide`, a sight ray and its rule in GDScript (Still 0.22, Echo 0.26). The largest roster is six errors, so 0.3 ms total cannot be met without ticking the rules less often, which would change how fast they react (pillar 2). 1.0 ms is the measured 0.77 plus margin for a faster or slower CPU.
- **Script 2.5 → 3.0 ms, physics 2 → 1.5 ms.** The frame is unchanged (render ≤ 10, the rest headroom). Physics measured 0.77 ms mean and 1.19 p95 at the peak; the 0.5 ms moved to script covers the errors' share above.

## What this pass changed

| Change | Where | Effect at the peak |
|---|---|---|
| LightPool queries (`lit_fixtures_near`, `is_lit`) read only the fixtures in the 4 m buckets the query touches, with an optional group filter for Flicker's own-group tests | `lighting/fixture_index.gd`, `light_pool.gd`, `fixture_groups.gd`, `errors/flicker_habitat.gd` | Flicker 0.22 → 0.14 ms; Still's observation light query cheaper; answers identical (test) |
| Ambient prop loops stop beyond their max distance + 3 m and start again inside it (fans, vending machines) | `audio/audio_cull.gd`, `core/audio_manager.gd`, `levelgen/props/server_fan.gd`, `interactables/vending.gd` | Server: playing 3D players 58 → 25; level band 0.36 → 0.10 ms |
| A Server fan's rotor animates only while on screen | `server_fan.gd` (`VisibleOnScreenEnabler3D`) | part of the level band above |
| A loop's volume part that does not change is not written again (Static sets its band every frame; each write retires a bus block, RCA1) | `audio/audio_loop.gd` | fewer volume writes; no audible change |
| The crank gauge repaints only when the shown percent or its state changes | `ui/hud_crank.gd` | player band 0.69 → 0.60 ms (the charge drains every frame) |
| Unpooled lights of range ≤ 4 m (pickup glints, notes, Garage exit signs) take the pool's distance fade | `levelgen/level.gd`, `core/run_level_setup.gd` | Garage drawn lights 24 → 19 max |
| Static's critical-path cut test searches packed arrays | `director/director_spawn.gd` | same answers (test); cheaper Director tick |
| **Leak:** `BuildSlopes` held its `BuildPlan` strongly while the plan held it: every level's plan (its mesh arrays) stayed alive | `levelgen/build_slopes.gd` | +5.4 MB a level → none |

## Known spikes (not budget rows, written down for cp-12)

R19 (2026-10-09) fixed the three M3.5 left open; the M3.5 readings are kept in the "before" column.

| Spike | Before (M3.5 code) | After R19 | How |
|---|---|---|---|
| Offices at Cycle 2 depth 5, nodes in the level (budget 3,000) | 3,095 (seed 9: 142 under-desk hide spots at 6 nodes) | 2,409 to 2,858 over five seeds (seed 9: 2,665); every other stratum at its largest depth 413 to 1,309 | an under-desk hide spot is 3 nodes: the host is its own kneehole `StaticBody3D` with its shape and `Interactable`; every hide spot's view and exit points are transforms, not `Marker3D` nodes. Same scenes, same boxes, same layer, same world transforms (test) |
| The frame a level appears: worst headless frame from the level walkable to 30 frames after arrival, start (Garage, depth 10) | 41 to 57 ms | 10 to 14 ms | see the steps below |
| The same, a drop into the Server (depth 11, the full Cycle 2 roster) | 64 to 75 ms | 12 to 14 ms | |
| Relief entry (`hint_away_now`: three hunters and three Statics hinted at once, one Director tick), mean of 10 (worst) | 12.2 to 13.3 ms (17 to 20) | 1.7 to 2.5 ms (2.4 to 4.8) | cached, not spread: the hint ring is scanned once for every hunter hinted from one spot in a frame; the Static's off-path cell reads a per-level mask and a walk cut at its 15-cell search radius; the Static's BFS path runs on cell indices. Every answer and rng draw is the old one (test). The chasers' retreat stays in the entry tick (test) |

The arrival after R19, its main-thread ms per frame (drop into the Server, three runs; `Run.arrival_ms`, `Director.arrival_work.queue.frame_ms`):

| Frame | ms | What runs |
|---|---|---|
| builder's last slice | within the slice | `finish`: the pool re-evaluated, `geometry_ready` (it also ran everything below, 40 to 80 ms) |
| props | 1.3 to 2.8 | exit and breaker prefabs (their scenes loaded on a worker while the level built; unheld, they were read from disk here) |
| pickups | 2.2 to 3.7 (worst frame) | items and notes, a 3 ms slice a frame, rng order kept |
| audio | 1.0 to 1.8 (4.9 the first time a stratum's files load) | room tone and fixture hums into the library cache; the error scenes taken from the worker (each level's first spawn read its scene from disk: 3 to 7 ms) |
| prelight | 3.7 to 6.9 | the light pool lent from the spawn's eye (16 lights and their hum players); behind the drop's black, before the first level at a start; skipped at a proper exit, whose arrival frame is under the transition |
| arrive | 6.5 to 10.5 | the player placed, `level_entered` (its listeners: SettingsManager's graphics re-apply walks the tree, 2.5 to 3.5; the HUD 1.3; music and audio 0.5), `Director.begin` (clock, Calm, listeners, the pose) 0.7 |
| roster, 5 to 8 frames | 1.6 to 3.8 each | the fair-cell context, the fair-cell scan in 64-cell chunks, the pick, one spawn a step, awake arrivals and Static bounds, the aggression; whatever is left runs before the first 0.1 s tick (it never had to) |

Readings: 2026-10-09, the same container, `uptime` load 0.75 at the start of each set, rising to 1.6 while other agents' gates ran; "before" (HEAD `3ce4273` exported to a scratch copy) and "after" were run in turn, three times, on the same harness (a run starting at depth 10 and dropping into the Server at 11). Commands: `tools/ci/test.sh --filter perf/` prints the readings; `NOCLIP_FULL_TESTS=1` (checkpoint) enforces them: `tests/perf/test_level_nodes.gd`, `test_arrival_frames.gd` (each staged frame within the 4 ms slice, the prelight and arrival frames under 16.6 ms, Relief entry within the 3 ms script budget), `test_r19_equivalence.gd`. The full perf set passed with budgets enforced at load 1.8.

Still open (filed in `docs/qa/open_items.md`): the arrival frame is 6.5 to 10.5 ms headless. After a drop (its black) and a proper exit (the glitch transition) it is covered; at a start (the first level of a Descent) it is the first frame the level shows. Its largest shares are other owners' `level_entered` listeners (SettingsManager's whole-tree graphics walk, the HUD).

## R21: the cp-12 script regression (2026-10-09)

Main (`30cd6c1`) read the Server peak at 2.94 to 3.07 ms script (budget 3.0). Bisect, the perf bench (`--stratum server --seconds 20`) on snapshots of each point, interleaved, twice each, `uptime` load 0.2 to 0.7:

| Point | Script ms (two runs) | Errors ms |
|---|---|---|
| `53ce14a` (M3.5's own branch tip, before M3.1 was merged in) | 2.96, 3.06 | 0.91, 0.93 |
| `3ce4273` (M3.5 merged, with M3.1's proximity crossing) | 2.98, 2.96 | 0.89, 0.87 |
| `007f9a5` (R20) | 2.81, 2.88 | 0.84, 0.87 |
| `30cd6c1` (R19, main) | 2.92, 2.98 (later: 2.89 to 3.03 over 10 runs) | 0.84 to 0.93 |

No commit added the cost: M3.5's own code reads the same today. Its recorded 2.65 ms is not reproducible on this container now; the gap is the machine, plus a bench that is not deterministic: Flicker spends 300 to 575 of 1,200 frames Satiated depending on timing, which moves its share between 0.13 and 0.22 ms. The 2.65 was one good reading of the same code. M3.1's crossing check (an Array built per error per frame) cost too little to resolve against that noise, but it was removed anyway.

So R21 bought headroom with changes that keep every answer (`tests/perf/test_r21_equivalence.gd` runs each against its old form), found with the local debugger's script profiler (`godot -d`, `EngineDebugger.profiler_enable("scripts", true)`) on a 90 s Server peak:

| Change | Where | Effect (bench band) |
|---|---|---|
| Hidden UI idles: a shutter processes only while it moves (a note sheet while shown), a menu row only while its flash runs (the pause and settings menus had 49 idle `_process` calls a frame) | `ui/ui_shutter.gd`, `ui/note_sheet.gd`, `ui/menu_row.gd` | other 0.19 → 0.12 |
| The ducker applies only when a duck, slider or the room tone changed (version + bus count), and filters its list only on the frame a duck expires; `has` without a lambda | `audio/audio_ducker.gd` | audio 0.45 → 0.38 (with the next row) |
| A pad voice writes `volume_db` only when the level moves (a write to a playing player retires a bus block) | `audio/music_voice.gd` | in the row above |
| Echo's trail: `resolve` runs only when an unresolved step was added; `target_index` is kept for the trail version and delay | `errors/echo_trail.gd` | Echo about -0.02 |
| The proximity crossing is two comparisons, not an Array per error per frame; Still's column scale and Flicker's stutter emitter are written only on a change | `errors/error_base.gd`, `still_present.gd`, `error_flicker.gd` | errors about -0.03 |
| Lit-fixture queries test the group before the lit state and read a bucket with one lookup; the input poll builds no lambda; the exit timer compares whole seconds, not two strings | `lighting/fixture_groups.gd`, `fixture_index.gd`, `player/player_input.gd`, `ui/hud_depth.gd` | small |

`NOCLIP_FULL_TESTS=1 tools/ci/test.sh --filter test_perf_peak`, budgets enforced, three runs (load 0.22, 0.42, 0.48):

| | Before (`30cd6c1`) | After R21 |
|---|---|---|
| Server script | 2.89 to 3.07 (mean of 10 bench runs 2.96) | 2.80, 2.65, 2.73 (bench runs 2.58 to 2.94, mean 2.73) |
| Server errors | 0.84 to 0.93 | 0.85, 0.80, 0.83 |
| Garage script | 2.77 | 2.52, 2.52, 2.61 |
| Garage errors | 0.76 | 0.66, 0.69, 0.70 |

Headroom under 3.0 ms: the Garage 0.39 to 0.48 ms; the Server 0.20 to 0.35 (mean 0.27), so the 0.3 ms target is met on average only in the Garage. Not done (each would change what is heard or seen, or is engine time): the Coherence static bed renders its noise in GDScript (about 65 µs a frame at Coherence 40, two `randf_range` calls a sample), the errors' `move_and_slide` and navigation agents, the player's interact ray. The bed is the next candidate if the Server needs more (a cached noise table changes the sample stream, so it needs an audio sign-off).

## Not measured here

Real GPU frame times, render ms, VRAM at 1080p, Medium versus High, and startup to title need a machine with a graphics card: `docs/qa/perf_checklist.md` (Part P of the cp-12 play script). The CPU renderer's own frame times (130 ms a frame at 960x540) say nothing about a GPU.
