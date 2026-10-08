# 05 — Run Structure and Progression

**Depends on:** `00_OVERVIEW.md`, `01_fiction_and_tone.md`
**Skills to read:** `godot-genre-roguelike`, `godot-save-load-systems`
**Pulls engagement levers:** push your luck (exit versus drop), mastery ceiling (score, daily), variable reward (item choice, unlocks), session shape (short runs, instant restart).

---

## 1. Vocabulary

- **Descent:** one run. Starts at depth 1 with a loadout; ends at dissolution, abandonment, or crossing the Threshold.
- **Depth:** the integer level index, 1 upward. **Stratum:** the level theme at that depth.
- **Cycle:** depths 1 to 6 are Cycle 1. In Endless, depths 7 to 12 are Cycle 2, and so on.
- **Proper exit:** leaving a level through its exit. **Drop:** leaving by noclipping through the floor.
- **Awake:** the state of the next level's errors after a drop.

## 2. Descent structure

| Depth | Stratum | Rule |
|---|---|---|
| 1 | Halls | Always |
| 2 | Pools or Garage | Coin flip by seed |
| 3 | one of Pools, Garage, Offices | Not the depth 2 stratum; Server never here |
| 4 | one of the remaining of Pools, Garage, Offices, Server | |
| 5 | the last remaining | |
| 6 | Substrate | Always; the Threshold is here |

Cycle 2+ (Endless only): same rule with the same strata, each with corruption (`02` §7, `07` §9). The seed for depth *d* is `Seeds.derive(run_seed, "depth:%d" % d)` (defined in `tuning.gd`, see `07` §1), so a run is fully reproducible from `run_seed`.

**Level size and time budget** (the generator targets these; `07` holds the grid numbers):

| Depth | Target time to exit, competent player | Walkable cells (2 m cells, see `07` §2) |
|---|---|---|
| 1 | 3 min | 300 |
| 2 | 4 min | 380 |
| 3 | 5 min | 460 |
| 4 | 5 min | 520 |
| 5 | 6 min | 580 |
| 6 | 4 min | 360, open |

A full winning Descent is 25 to 30 minutes. Death at depth 2 or 3 takes 5 to 10 minutes. Restart to being in control again is under 3 seconds.

## 3. Error roster per depth (initial tuning)

The Director (`10`) spawns from this roster; "native" is the stratum's teaching error (Pools: Echo, Garage: Still, Offices: Flicker, Substrate: Null; Server has no native: its "native" slot is one hunter already met this run, chosen by seed).

| Depth | Roster | Director aggression base |
|---|---|---|
| 1 | Static ×1 (first Descent ever: Static only, placed far from the critical path) | 0.25 |
| 2 | Static ×1, native ×1 | 0.35 |
| 3 | Static ×1, native ×1 | 0.45 |
| 4 | Static ×1, native ×1, plus one of the hunters already met this run (Still or Echo) | 0.55 |
| 5 | Static ×2, Still ×1, Echo ×1, Flicker ×1 (Server: all three; other strata: native plus two) | 0.65 |
| 6 | Null ×1, Static ×2 | 0.75 |
| Cycle 2 (7 to 12) | as above with +1 Static and aggression +0.15; Null appears only in the Substrate (depth 12, 18, …) with radius ×2 from depth 12 | |

**Awake:** after a drop, the next level's aggression base is +0.15 and one hunter starts in "searching" state at 30 m from the player instead of "dormant". Dropping twice in a row makes it +0.25 and two hunters searching. Dropping three times in a row keeps +0.25 (it does not escalate further; the fairness floor holds).

## 4. Transitions

### Proper exit (the Landing)
1. The player enters the exit volume (elevator car, stairwell door, pool drain hatch, ramp gate; `07` §6). The HUD prints `DESCENDING`.
2. A 6 s **Landing** interstitial: the player stands in a small enclosed cabin scene (stratum-themed: elevator for Halls, Garage, Offices; stairwell landing for Pools, Server; a lit white pocket for Substrate), the camera is free, the cabin shudders, the world shader unrender ripples once, and the next level generates in a thread (`07` §8).
3. Rewards, presented in-world on the cabin wall as a two-item panel (labelled with the `item_1` and `item_2` bindings, `[1]` and `[2]` by default, glyph and name, choose with keys or click): one of two items from the current item pool, weighted by what the player lacks. Choosing is optional; the cabin opens after 6 s regardless. The panel also prints `COHERENCE +20`, applied on arrival with the gain pulse.
4. The cabin door opens onto the next level's spawn room. Depth label shutters in.

### Drop
1. Floor noclip commits (`06` §8). The camera falls through the unrendered floor, 1.2 s of grain and the sub thump, then arrives standing at a random valid cell of the next level at least 15 m from every error and not in the exit room.
2. No reward. `COHERENCE −30` was paid at commit. The HUD prints `DROPPED · THEY ARE AWAKE`.
3. On depth 6 the floor is solid: there is nothing below. The noclip arc shows `SOLID`.

## 5. Scoring

```
score = 1000 × max_depth_reached
      +  300 × proper_exits
      +    5 × coherence_at_end
      +  150 × notes_found_this_run
      +   50 × evasions                    (an error in "chasing" state lost the player)
      +  time_bonus                        (win only: max(0, 1800 − seconds) × 0.5)
```
Drops are not penalised: they already cost Coherence and reward. Endless continues the formula past depth 6 with `proper_exits` counting the Threshold as one.

## 6. Unlocks (milestones, no currency)

| # | Unlock | Condition | Type |
|---|---|---|---|
| 1 | Glowstick in item pool | Reach depth 2 | Item |
| 2 | Radio in item pool | Reach depth 3 | Item |
| 3 | Flare in item pool | Reach depth 4 | Item |
| 4 | Fuse in item pool, and Powered exits may spawn as Variant B (breaker with an empty fuse socket, see `07` §6) | Reach depth 5 | Item |
| 5 | Loadout: Cartographer | Find 5 notes | Loadout |
| 6 | Loadout: Lightbearer | Evade Flicker 3 times in one run | Loadout |
| 7 | Loadout: Diver | Reach depth 4 twice | Loadout |
| 8 | Daily Descent mode | Reach depth 3 | Mode |
| 9 | Endless mode and Cycle 2 | Cross the Threshold | Mode |
| 10 | Archive: Still codex counter line | Encounter Still 3 times | Archive |
| 11 | Archive: Echo codex counter line | Encounter Echo 3 times | Archive |
| 12 | Archive: Flicker codex counter line | Encounter Flicker 3 times | Archive |
| 13 | Archive: Null codex counter line | Encounter Null 3 times | Archive |
| 14 | Note U6 and the ending variant | Find all 35 other notes | Archive |

"Encounter" and "evade" are the `noticed_player` and `lost_player` events defined per error in `08` §2. Unlocks are announced on the Run Summary and as HUD notifications when earned mid-run (`04` §6). Unlocks never increase player power; they add options and knowledge (roguelike skill rule: meta never overpowered).

## 7. Loadouts

| Loadout | Start | Trade-off | Unlock |
|---|---|---|---|
| **Faller** (default) | Polaroid ×1, Chalk ×8 (uses), Coherence 100 | none | always |
| **Cartographer** | Chalk ×20 (uses), Radio ×1, Coherence 90 | starts with 90 | #5 |
| **Lightbearer** | Glowstick ×3, Flare ×1, crank rate ×1.5 | no Polaroid; Flicker is attracted to the player's light from 1.5× distance | #6 |
| **Diver** | Polaroid ×2, start at depth 3 with Coherence 70 | skips depths 1 and 2 and their rewards; score counts max depth normally | #7 |

Daily Descent always uses Faller.

## 8. Modes

- **Descent:** random `run_seed`; loadout chosen; unlocks apply.
- **Daily Descent:** `run_seed = hash("NOCLIP:" + UTC date as YYYYMMDD)` (the same expression as `13` §4). One attempt per day per save. The result is stored in `daily` (`13` §2). The title screen shows today's seed and the player's result if played. Faller loadout, all unlocked items in the pool regardless of unlock state (so every player faces the same game).
- **Endless:** available after a win. Identical to Descent, except the Threshold at depth 6 behaves as a proper exit into Cycle 2 and the run ends only at dissolution or abandonment. The ending plays only in Descent mode.

## 9. Difficulty and fairness rules (enforced by code, tested by `15`)

1. No error spawns within 20 m of the player or inside the camera frustum. (`10`)
2. The exit and its lock objective are reachable on foot from spawn without noclip. (`07` §8 validation)
3. The first 30 s of every level (15 s after a drop) have no hunter in chasing state. (`10` calm window)
4. An error contact costs a fixed amount, stuns 1.2 s, and then that error retreats for 20 s. Two errors cannot contact the player within the same 3 s. (`08`, `10`)
5. No single damage event exceeds 35 Coherence. At least 3 s pass between any two contacts, and the same error cannot contact twice within 20 s (`Satiated`). A noclip is refused when it would reduce Coherence to 0 (`06` §8), so the player can never spend themselves to death.
6. Static never blocks the only route to the exit for more than 40 s (it drifts). (`08`)
7. Awake never exceeds +0.25 aggression.
8. The Threshold is always reachable within 90 s of walking from the Substrate spawn along the generator's critical path, so that Null's pressure is a chase, not a maze.

## 10. The first Descent (scripted guarantees for a new save)

- Depth 1 contains: note H1 within 10 m of spawn, a soft wall on the critical path within 60 s of walking, a Powered exit with the breaker room on the critical path, one Polaroid, and Static placed off the critical path with its drift bounded to a side loop.
- No hunter at depth 1 on the first Descent. From the second Descent on, depth 1 may add a dormant Still or Echo at aggression 0.2 (so depth 1 is never fully safe again).
- The first time the player reaches depth 2, the Landing shows the item choice with the hint `CHOOSE ONE` once.

## Interfaces

- `RunState` (in `GameState` autoload, `14`): `run_seed: int`, `mode: StringName`, `loadout: StringName`, `depth: int`, `strata_order: Array[StringName]`, `coherence: float`, `items: Array[ItemSlot]`, `proper_exits: int`, `drops_in_a_row: int`, `notes_found: Array[StringName]`, `evasions: int`, `encounters: Dictionary`, `started_at_ms: int`.
- `GameState.start_run(mode, loadout, seed)`, `GameState.descend(proper: bool)`, `GameState.end_run(cause: StringName)`, `GameState.compute_score() -> int`.
- Signals on `EventBus` (signatures canonical in `14` §4): `run_started`, `level_entered(depth, stratum, arrival)`, `level_left(proper)`, `run_ended(cause, score)`, `unlock_earned(id)`.
- `MetaState` (`13`): unlock flags, stats, notes, daily history.

### Interface additions during production

- `RunState` also holds `evasions_by: Dictionary` (error id to count; `evasions` stays the total), `max_depth: int`, `walls_passed: int`, `drops_total: int`, `coherence_spent: float`, `distance_m: float`.
- `GameState` counters, called down by the run scene: `record_notice(id: StringName)`, `record_evasion(id: StringName)`, `record_spend(kind: StringName, amount: float)`, `record_wall_pass()`, `record_drop()`.
- `GameState.start_run` starts at the loadout's `start_depth` (`LoadoutData`, via `DataRegistry`). `compute_score` reads the time bonus from `Clock.run_seconds()`.
- `MetaState.stats.depth_reached_counts` (`13` §2) and `MetaState.depth_reached(depth)` back unlock #7 (reach depth 4 twice).
- M1.9: `GameState.strata_order_for(run_seed) -> Array[StringName]` (static, 05 §2), `GameState.stratum_for(depth)`, `GameState.record_note(id)` (connected to `EventBus.note_found`; once per run, also the Archive). `start_run` applies the loadout's `start_coherence` to `RunState.coherence` and fills `strata_order`; the run applies `start_items` to the belt.
- M2.10: `RunState` also holds `first_descent: bool`, `crank_rate_mult`, `flicker_attract_mult` and `start_items` (copied from the loadout in `start_run`), `daily_key: String` (UTC `YYYYMMDD` of a Daily attempt), `score: int` (set by `end_run`), `unlocks_earned: Array[StringName]` (this run, in order; the Run Summary prints them). `GameState.score_for(max_depth, proper_exits, coherence_at_end, notes, evasions, seconds, won) -> int` (static, §5; Coherence counts as the whole number the HUD shows, the time bonus rounds down), `is_mode_available(mode)` (Descent always; Daily once #8 is earned and today has no entry; Endless after a win), `is_loadout_available(id)`, `today_key(date = {})`, `daily_seed(date = {})` (= `Seeds.daily`), `cycle_for(depth)`, `is_first_descent()`. `start_run` does not refuse a locked mode or loadout (debug launches start anything); the title asks first. A Daily `start_run` forces Faller and writes `daily[today]` at once (`score 0`, cause `abandoned`), so quitting does not buy a second attempt; `end_run` overwrites it with the result. Unlocks are evaluated at their events: depth milestones (#1 to #4, #7, #8) in `start_run` and `descend`, notes (#5, #14) in `record_note`, Flicker evasions (#6) in `record_evasion`, codex (#10 to #13) in `record_notice`, the Threshold (#9) in `end_run(&"threshold")`; each is emitted on `EventBus.unlock_earned` once per save (the HUD prints the notification).
