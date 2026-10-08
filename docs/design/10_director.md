# 10 — The Director

**Depends on:** `00_OVERVIEW.md`, `05_run_structure_and_progression.md`, `06_player.md`, `07_level_generation.md`, `08_entities.md`
**Skills to read:** `godot-genre-horror` (director pacing, sawtooth), `godot-game-loop-waves` (intensity scheduling), `godot-signal-architecture`
**Pulls engagement levers:** a decision every 60 seconds, dread over startle, fairness contract, counters in conflict (roster selection).

---

## 1. Purpose

The Director is the invisible pacing authority for one level at a time. It decides when errors wake, where they are hinted, how aggressive they are, when to apply a scare, and when to leave the player alone. It is the system that makes the game feel designed rather than random, and it is the system that enforces fairness. It never controls the player.

The Director is **macro** (hints, aggression, spawns, scares). Errors remain **honest** at the micro level: a chase starts only from senses (`08` §2). The Director may put an error near the player; it may never tell the error where the player is.

## 2. Intensity model

`intensity` ∈ [0, 1], updated at 10 Hz.

**Inputs (added per tick, scaled to per-second rates):**

| Source | Contribution |
|---|---|
| Time on level after the calm window | +0.010 per second |
| Player noise: sprint step / crank (per 0.5 s) / noclip commit / breaker | +0.02 / +0.10 / +0.20 / +0.25 |
| Nearest hunter distance (Still, Echo, Flicker group, Null) | +`clamp((20 − d) / 20, 0, 1) × 0.05` per second |
| A hunter in `Chase`/`Follow`/`Stalk` | +0.15 per second (cap 1.0) |
| Coherence below 30 | +0.10 once, when crossing |
| Exit first seen | −0.15 once |
| Successful evasion (`lost_player`) | −0.30 |
| Error contact | −0.40 (the "bite" ends the peak) |
| Note picked up | −0.10 |
| Noclip pass that broke line of sight (`06` §8) | −0.20 |
| Decay in `Relief` | −0.03 per second |
| Decay otherwise | −0.01 per second |

**Phases** (sawtooth, from the horror skill's director pattern):

| Phase | Enter when | Director behaviour | Leave when |
|---|---|---|---|
| **Calm** | Level entered | No hunter may be in `Chase`. Hunters dormant or `Wander` far (≥ 30 m). No scares. Static drifts. | 30 s elapsed (drop arrival: 15 s) |
| **Build** | After Calm or Relief | Hints hunters toward the player's region (a random walkable cell 15 to 30 m from the player, re-hinted every 20 s). Scares allowed. Aggression = base + awake + time pressure. | A hunter enters `Chase`/`Follow`/`Stalk`, or intensity ≥ 0.8 (then the Director wakes the nearest dormant hunter and hints it to 12 m) |
| **Peak** | A chase is on | No new hunters woken. No scares. Music drops (`03` §5). The threat vignette follows the nearest hunter. Max duration 45 s, after which the Director retreats the chasing hunter (`retreat(20)`) if no contact has happened: a chase that does not resolve is exhausting, not scary. | Evasion, contact, or the 45 s cap |
| **Relief** | After Peak | Duration 20 to 40 s (longer after contact: 40 s). Hunters hinted away (≥ 25 m). Static hinted off the critical path. No scares. Intensity decays at −0.03 per second. The player's Coherence and crank state are not touched (relief is space, not gifts). | Timer ends |

Depth 6 (Substrate) runs a different schedule: Calm 30 s, then Null wakes and the phase is **Pursuit** until the Threshold: no relief, Static hinted across the critical path every 60 s, intensity floor 0.6. The Substrate is the designed crescendo and the only level without a sawtooth.

## 3. Aggression

`aggression = clamp(base(depth) + awake + time_pressure + cycle, 0, 1)`:
- `base(depth)` from `05` §3.
- `awake` +0.15 after one drop, +0.25 after two or more (`05` §3).
- `time_pressure`: +0.10 per full minute beyond 2× the level's target time (`05` §2), cap +0.30. Camping is answered with pressure, not with instant punishment.
- `cycle`: +0.15 in Cycle 2 and beyond.
Applied to every error via `set_aggression` whenever it changes (at most once per second).

## 4. Roster and spawning

- At level entry, the Director reads the roster for the depth and stratum (`05` §3), and the `error_spawn` placements (`07`). It spawns every roster error immediately in `Dormant` at distinct spawn points, choosing points ≥ 20 m walking distance from the player and outside the camera frustum, preferring points at 35% to 65% of the critical path for the native hunter and side branches for the others.
- Static starts awake (it is weather). Hunters wake per the phases. Null wakes after Calm.
- **Max simultaneous chasers:** depth ≤ 3: 1; depth 4 to 5: 2; depth 6: Null plus 1 (Static does not count; Flicker in `Stalk` counts). When the cap is reached, other hunters are hinted away.
- **Contact exclusivity:** the Director holds a `last_contact_ms`; `Player.contact` is refused (returns false) within 3 s of it, and the refused error gets `retreat(5)`.
- **Spawn after Flicker despawn:** if Flicker lost its habitat (no lit group within 10 m), the Director respawns it in `Build` at a lit group ≥ 20 m away, once per 60 s.
- **Awake arrivals** (`05` §3): one or two hunters start in `Search` with `last_known_pos` = a cell 30 m from the player (not the player's position: the Director never leaks the player).

## 5. Scares (Build phase only, never during Calm, Peak, or Relief)

Scares are cheap, honest-sounding events that create anticipation. They never cost Coherence and never spawn anything.

| Scare | Rule | Min interval |
|---|---|---|
| **Far door slam** | A door ≥ 20 m away and out of the frustum slams (18 m `door` noise; errors hear it too, which can pull a hunter toward that door rather than the player). | 60 s |
| **Payphone ring** | A payphone within 15 to 40 m rings until answered or 30 s. It is an 18 m noise every 6 s, so it attracts Echo and raises Still's suspicion if near. The player can silence it, at the cost of going to it. | 90 s |
| **Static swell** | Static's hum gains +4 dB for 3 s (no gameplay change). | 45 s |
| **Fixture dropout** | One fixture ≥ 12 m away goes dark permanently with the ballast tink. Not a flicker (flicker means Flicker, `02` §6). | 40 s |
| **Echo pre-echo** | Only when Echo is on the level and dormant or wandering ≥ 25 m away: one of the player's recent steps plays once at Echo's position. A true tell with a longer delay. | 50 s |

At most one scare per 30 s. Scares scale with intensity: none below 0.2, all available above 0.5.

## 6. Outputs to presentation

- `threat` ∈ [0, 1] for the renderer's vignette and the heartbeat rate: `max over hunters of clamp((15 − d) / 15, 0, 1)`, ×1.0 in `Chase`, ×0.5 otherwise, plus 0.3 inside Static's field, plus `1 − d / 12` inside Null's radius. Smoothed with a 0.5 s time constant on the way up and 2 s on the way down.
- `MusicDirector.set_intensity(intensity)`.
- `EventBus.director_phase(phase)` for the debug overlay.

## 7. Fairness enforcement (the Director owns these checks)

1. Spawn distance and frustum rules (§4).
2. Calm window: no chases for 30 s after a proper exit arrival, 15 s after a drop.
3. Contact exclusivity (3 s).
4. Static critical-path nudge (every 5 s check, 40 s cumulative cap; `08` §3).
5. Peak cap of 45 s without resolution.
6. Chaser caps per depth.
7. Awake cap (+0.25).
8. Time pressure cap (+0.30).
9. On depth 6, Null is never woken before Calm ends, and Static is never hinted into the Threshold pocket.

Every rule is a unit-testable function in `Director` with a deterministic clock input.

## 8. Tuning knobs (in `tuning.gd`, mirrored here)

`CALM_SECONDS 30`, `CALM_SECONDS_AFTER_DROP 15`, `PEAK_MAX_SECONDS 45`, `RELIEF_MIN 20`, `RELIEF_MAX 40`, `RELIEF_AFTER_CONTACT 40`, `HINT_INTERVAL 20`, `HINT_RANGE_MIN 15`, `HINT_RANGE_MAX 30`, `WAKE_INTENSITY 0.8`, `SCARE_MIN_INTERVAL 30`, `TIME_PRESSURE_PER_MINUTE 0.10`, `TIME_PRESSURE_CAP 0.30`, `AWAKE_ONE 0.15`, `AWAKE_TWO 0.25`, `CYCLE_BONUS 0.15`.

## 9. Verification

- Simulation test: a headless run of the Director with a scripted "player" emitting noise at intervals and errors as stubs; assert the sawtooth (phases cycle Calm → Build → Peak → Relief → Build), the calm window, chaser caps, and that intensity never exceeds 1 or goes below 0.
- Telemetry in debug builds: a CSV per level of `time, intensity, phase, nearest_hunter_d, coherence`, plotted by `tools/telemetry/plot.py` so the human can see the sawtooth.

## Interfaces

- `Director` (per-level node, created by the level scene): `begin(level: LevelData, depth, stratum, arrival: StringName)`, `end()`, `intensity: float`, `phase: StringName`, `aggression: float`, `threat: float`, `try_contact(error) -> bool`, `spawn_error(id, spawn_point)`, `request_scare()`.
- Listens to: `EventBus.noise_emitted`, `Player.coherence_changed`, `ErrorBase.state_changed/lost_player/contacted_player`, `EventBus.exit_status_changed`, `EventBus.note_found`, `EventBus.hide_state`.
- Emits: `EventBus.director_phase(phase)`, `EventBus.threat_changed(threat)`.

### Interface additions during production
- M1.8 `Director` (`game/src/director/director.gd`, a child of the level; the run and `DirectLevel` add one): `begin(level: Level, player: Player, arrival: StringName)` is the form the run calls (14 Interfaces, M1.9 hook); depth, Cycle and first-Descent come from `level.data`, the stratum from `GameState.stratum_for(depth)` during a run (else `level.data.stratum`), drops from `GameState.run.drops_in_a_row`. `intensity` and `phase` are read-only properties over `DirectorPacing`. `time_source: Callable` (seconds; tests pass `FakeClock.now`; default: the Director's own pausable physics time) and `update()` (advances in 0.1 s steps). `spawn_error(id, spawn_point: Vector3) -> ErrorBase`. Counters `contacts`, `refused`, `last_contact_ms`; `roster` (05 §3 ids) and `skipped` (ids without a scene yet); `telemetry: DirectorTelemetry` (`dump_csv(path)`, rows `time,intensity,phase,aggression,threat,nearest_hunter_d,coherence,chasing`); `scares: Scares` (gating real, `request` a no-op until M2). Contact exclusivity is wired through `Player.contact_gate = try_contact` (never `ErrorBase.contact_request`). Joins groups `director` and `debug_info`.
- Pure helpers: `DirectorPacing` (intensity, phases, action queue), `DirectorRules` (aggression, roster, caps, threat, exclusivity window), `DirectorSpawn` (fair cells, hint rings, Static cut test), `DirectorHunters` (calls down to errors).
- Readings (M1.8): the time input (+0.010/s) and the decay rows both apply (net 0 outside Relief, −0.02/s in Relief); Build wakes one dormant hunter at each entry (the nearest) and hints it; intensity ≥ 0.8 in Build wakes the nearest dormant (else awake) hunter, hints it to a cell 12 m out and enters Peak, but only when the level has a hunter; a contact in Build or Peak goes to Relief 40 s; an evasion ends Peak; "in view" for spawns is the camera's horizontal cone widened 10° plus any clear grid line of sight in any direction; a hunter that enters Chase during Calm is retreated for the rest of Calm; over the chaser cap the farthest chasers retreat 5 s and the free hunters are hinted away; after a wall pass that broke every chaser's sight intensity drops 0.20 and cannot rise above that for 15 s; a sprint step is a `step` noise within 2 m of the player while the player is in Sprint, a crank is a 12 m `mech` noise there; the breaker counts from `EventBus.breaker_thrown`, the noclip commit from `Player.noclip_committed`; "exit first seen" is the level Exit's `seen` signal.
- R8 (cp-04 review, 2026-10-08): the decay rows apply only on a tick with no other input (an event since the last tick, the time input, a hunter within 20 m, a chase); the time input runs in Build, Peak and Pursuit only (Relief is space and decays at −0.03/s; Calm is before the calm window). Build entry and the 0.8 wake never wake a hunter on the first Descent's depth 1 (`Director.wake_allowed()`, 05 §10). A hunter chase that starts in Relief is retreated for the rest of Relief (at least 5 s), as in Calm; such chases are counted in `Director.retreated_chases`, every other hunter chase in `Director.encounters`. A Static `lost_player` changes no intensity and does not end Peak. The crank input is the Flashlight's `crank_tick` signal (`Player.flashlight`, every 0.5 s while the wheel turns), not a 12 m `mech` noise. Peak pressure: a Peak entered by the 0.8 wake with no chase re-hints the woken hunter (`DirectorHunters.peak_hunter`) to a cell 12 m from the player every 20 s (`HINT_INTERVAL`, action `hint_peak`) until a chase starts or the 45 s cap. First Descent: `DirectorHunters.bound_statics_off_path()` gives each Static a wander filter (`DirectorSpawn.side_loop_cells`: the walkable region reachable from Static without coming within 6 m of the critical path, the spawn room or the exit room; only the path and those rooms when that region has fewer than 3 cells) through `ErrorStatic.set_wander_filter(filter)` when it exists; the filter takes a cell (`Vector2i`) or a world position (`Vector3`) and returns bool.
- Not yet wired: `EventBus.hide_state` (no Director rule reads it in 10 §2 to §7), `MusicDirector.set_intensity` (no MusicDirector yet), Null's wake and the Flicker respawn (M2.5, M2.6).
