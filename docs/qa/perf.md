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

- **The arrival frame.** The builder's last job (`finish`) emits `geometry_ready`; the run's listeners prepare the level and, on a start or a drop, arrive (the Director's `begin` spawns the roster). That one frame reads 40 to 80 ms headless here (Director.begin about 21 ms in the Server). It is the frame the level appears, under the glitch transition or the drop's black. The 4 ms slice budget holds for every other slice.
- **Relief entry.** Hinting every hunter and Static away at once (10 §2) costs 10 to 16 ms in one Director tick in the Server; it happens at a contact, inside the 60 ms hitstop's aftermath.
- **Offices at Cycle 2 depth 5** (not this task's strata): 3,097 nodes in the level (144 hide spots under desks at about 6 nodes each, 142 desks, 109 fixtures), over the 3,000 budget. Filed in `docs/qa/open_items.md`.

## Not measured here

Real GPU frame times, render ms, VRAM at 1080p, Medium versus High, and startup to title need a machine with a graphics card: `docs/qa/perf_checklist.md` (Part P of the cp-12 play script). The CPU renderer's own frame times (130 ms a frame at 960x540) say nothing about a GPU.
