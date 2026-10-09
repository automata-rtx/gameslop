# Descent simulation (R18, M3.4 tuning pass)

Chained simulated Descents: one run per seed and profile, depths 1 to 6, Coherence, belt and
RunState carried through the real exit, Landing (item pick) and arrival. M3.4 tuned from these
(15 §2: telemetry from at least 20 simulated runs; the 5 human runs are for cp-12, below).

```
tools/godot/bin/godot --headless --fixed-fps 60 --path game --script tests/sim/sim_run.gd -- \
    --descent --seeds 20 --from 1 --profiles direct,explorer,cautious [--json out.json] [--csv dir]
tools/godot/bin/godot --headless --fixed-fps 60 --path game --script tests/sim/sim_run.gd -- \
    --depths 6 --seeds 20 --from 1 --profiles direct,cautious,explorer --max-seconds 300
```

`--csv dir` writes each level's Director telemetry (`<profile>_seed<n>_d<depth>.csv`, plot with
`tools/telemetry/plot.py`). Each `levels` entry of a Descent result carries the M3.4 telemetry
keys (`SimBotTelemetry`, `SimDescent.TELEMETRY_KEYS`): `losses` (Coherence lost per source),
`last_losses`, `contact_log`, `contact_light` (lit fixture within 4 m, flashlight on, at each
contact), `evasions`, `breaker_s`, `phase_intensity` (mean intensity and seconds per phase),
`max_intensity`, the Null keys and `stuck_at`. The gate (`tests/sim/test_sim_descent.gd`) plays
direct seeds 1 and 2; `NOCLIP_FULL_TESTS=1` plays 10 seeds of every profile. Runs are not
bit-identical between processes (the navigation bake and audio run on threads), so a row can
move by a death or two between two sweeps of the same tree.

## The three stages (20 seeds per profile, `--max-seconds 600` per level)

- **Before**: the cp-11 tree (`ee33cc7`), R18 bot.
- **Bot fixed**: same game, the M3.4 sim-bot fixes (below) except the Polaroid rule.
- **After**: the M3.4 tree: bot fixes, every profile uses its Polaroid below 55, Null's core
  drains 10/s (was 12), and the death cause reads a 0.25 s window (06 §9, CHANGELOG).

| stage | profile | runs | Threshold | died | other | deaths by depth (1..6) | death causes | mean arrival Coherence (1..6) | noclip spent / run |
|---|---|---|---|---|---|---|---|---|---|
| before | direct | 20 | 8 | 12 | 0 | 0/0/0/1/1/10 | null 10, still 1, static 1 | 100/97/99/100/98/96 | 0.0 |
| before | cautious | 20 | 8 | 10 | timeout 1, stuck 1 | 0/0/0/1/3/6 | null 6, still 2, flicker 2 | 100/99/95/98/94/89 | 4.8 |
| before | explorer | 20 | 0 | 17 | stuck 3 | 7/6/0/3/1/0 | echo 9, still 7, flicker 1 | 100/71/69/64/80/- | 0.0 |
| bot fixed | direct | 20 | 15 | 5 | 0 | 0/0/0/1/1/3 | null 3, still 1, flicker 1 | 100/97/99/100/98/96 | 0.0 |
| bot fixed | cautious | 20 | 9 | 11 | 0 | 0/0/0/1/2/8 | null 8, flicker 2, still 1 | 100/99/97/100/96/90 | 5.2 |
| bot fixed | explorer | 20 | 0 | 19 | stuck 1 | 8/8/2/0/1/0 | still 10, echo 6, static 2, flicker 1 | 100/75/52/100/95/- | 0.0 |
| **after** | direct | 20 | **16** | 4 | 0 | 0/0/0/1/1/2 | null 2, still 1, flicker 1 | 100/99/100/100/98/95 | 0.0 |
| **after** | cautious | 20 | **11** | 8 | stuck 1 | 0/0/0/2/1/5 | null 5, still 2, flicker 1 | 100/99/95/99/99/93 | 4.5 |
| **after** | explorer | 20 | **0** | 15 | timeout 5 | 3/9/1/1/0/1 | still 9, echo 4, null 1, flicker 1 | 100/76/58/87/85/35 | 0.0 |

All deaths by cause: before null 16 (41%), still 10 (26%), echo 9 (23%), flicker 3, static 1;
after still 12 (44%), null 8 (30%), echo 4 (15%), flicker 3 (11%).

Substrate survival (arrivals at depth 6 that crossed the Threshold): before direct 8/18,
cautious 8/14; bot fixed direct 15/18, cautious 9/17; after direct 16/18, cautious 11/16.

## Depth 6 alone (single levels from 100 Coherence, seeds 1 to 20)

| game | bot | direct | cautious | explorer |
|---|---|---|---|---|
| cp-11 (12/s, spawn 55%) | R18 | 10/20 | 12/20 | - |
| spawn point 75% | R18 | 6/12 (same 6 deaths) | - | - |
| cp-11 | M3.4 | 18/20 | 12/20 | 13/20 |
| spawn point 75% | M3.4 | - | 14/20 | 13/20 |
| **10/s (adopted)** | M3.4 | - | **16/20** | **15/20** |
| 9/s | M3.4 | 20/20 | 17/20 | 15/20 |

## Per depth after M3.4 (all three profiles, 60 Descents)

| depth | levels | exits | deaths | contacts / level | contacts by error | evasions by error | loss / level by source | phase mean intensity (mean s per level) |
|---|---|---|---|---|---|---|---|---|
| 1 | 60 | 57 | 3 | 0.78 | echo 30, still 17 | static 13, echo 4 | echo 12, still 10, static 3 | calm 0.08 (30), build 0.85 (79), peak 0.98 (4), relief 0.49 (29) |
| 2 | 57 | 47 | 9 | 0.84 | still 31, echo 17 | static 18, still 1 | still 16, echo 7, static 3 | calm 0.28 (29), build 0.82 (35), peak 0.94 (2), relief 0.49 (27) |
| 3 | 47 | 42 | 1 | 0.09 | flicker 4 | flicker 13, static 6 | flicker 3, static 2 | calm 0.21 (30), build 0.88 (80), peak 0.97 (0), relief 0.28 (6) |
| 4 | 42 | 38 | 4 | 0.48 | still 9, flicker 7, echo 4 | flicker 1 | still 7, flicker 4, echo 2 | calm 0.20 (30), build 0.56 (40), peak 0.83 (1), relief 0.26 (15) |
| 5 | 38 | 35 | 2 | 0.63 | still 18, echo 5, flicker 1 | static 15, still 2 | still 16, static 4, echo 3, flicker 1 | calm 0.20 (30), build 0.55 (33), peak 0.90 (5), relief 0.29 (21) |
| 6 | 35 | 27 | 8 | 0 | - | static 7 | null 43, static 4, noclip 3 | calm 0.14 (30), pursuit 0.92 (24) |

By profile: direct meets almost nothing (0 to 0.3 contacts a level; most levels end inside
Build); cautious 0.05 to 0.8 a level, rising with depth; explorer 2 to 2.5 a level at depths 1
and 2 (it lingers 6 to 7 minutes a level and never plays Still's or Echo's counter).

## Reading

- **Null was mostly a bot artefact.** The R18 bot walked a room's cells in an L or a staircase
  and went into the Threshold door from its back, so after the head-on pass it gained about
  0.8 m/s on Null and stood in the core for 6 to 8 s. Walking straight across open floor
  (what a player reading the unrender view does) took direct from 10/20 to 18/20 at depth 6
  with no game change. The cautious bot, which plays 08 §7's counter (route around Null's
  ring, soft walls) and is further back when Null wakes (30 to 45% of the path against 45 to
  60% for direct), still died in 8 of 17 Substrate arrivals. 10/s is the smallest drain that
  brings it to about 70 to 80%; the 75% spawn point did not move it. Seeds 2, 12 and 17 hold
  most of the remaining depth-6 deaths of every profile: their path doubles back across the
  Pursuit (walk 2.2 to 4 times the straight line), so Null meets the player twice. Left as
  layouts, not tuned.
- **Targets.** Cautious reaches the Threshold 11/20 (a majority, not yet a clear one; its depth
  6 survival is 11/16 and its Offices deaths are the light dilemma, below). Direct 16/20 is
  above "about half": the direct bot walks the grid path it is given and spends 30 to 60 s a
  level, so it meets almost no hunter (0 to 0.3 contacts a level); no human plays like that,
  and slowing the Substrate for it would undo the cautious result. The explorer never reaches
  the Threshold: it plays no counter for Still or Echo, so the Director's sawtooth brings a
  contact each cycle (2 a level) and it dies at depths 1 and 2 in 12 of 20 runs.
- **Deaths by cause.** Still 44%, Null 30%, Echo 15%, Flicker 11%, Static 0 (Static drains 3
  to 5 a level and takes the last few points of some deaths). Still's share is the explorer's
  (9 of 12); over the cautious and direct runs Null is 7 of 12. Each error kills sometimes.
  Evasions by counter: Static 59, Flicker 14, Echo 4, Still 3. Still is almost never "lost"
  (its evasion needs a Search ending without contact), so the sims cannot show its counter
  working; that is the first thing the human runs must check.
- **The sawtooth.** Every profile shows Calm, Build, Peak, Relief in that order and the
  Pursuit at 0.86 to 0.97 (floor 0.6). Peaks are short (1 to 10 s a level) because a chase
  ends quickly in a contact or an evasion; Build sits high for a lingering player (explorer
  0.89 to 0.95 for 1.5 to 7 minutes), since the time input and any nearby hunter keep it up and
  Build only leaves on a chase. Relief clamps to 0.5 and decays.
- **Noclip.** The bots spend almost nothing (cautious 4.5 a run, all on Substrate soft walls;
  direct and explorer 0). The economy is not stressed from the spend side; human runs decide
  whether noclip is used as a tool.
- **Death cause.** Twice a depth-6 death read `static` after Null had drained 85 and 86: Static
  processes before Null in a frame and its 0.067 tick landed first. 06 §9 now reads the
  largest loss within 0.25 s as the last damage source (CHANGELOG).

## Offices light dilemma (08 §1, §5)

`tests/sim/test_offices_dilemma.gd` checks the truth table on one floor with both errors awake:
lit room, light off: Still held by the fixtures, Flicker stalks and lunges (30); dark room,
light off: Flicker cannot live there, Still is not observed and walks; dark room, beam on: the
beam holds Still and Flicker, 8 m off, neither stalks nor attaches; lit room, beam on: Still
held, Flicker attaches to the beam; the breaker's wave powers the dark room and ends the safe
dark. In the after sweep (46 Offices levels, breaker thrown in 36): Flicker's contacts came
with the player in a lit area and the flashlight off 9 times (out of a lit area 3); Still's came
in the dark 6 times (3 with the flashlight off, 3 on but not on it) and in light 5. Both counters
cost something in the same room. All of the cautious bot's deaths before depth 6 were in
Offices: two combine the two errors (Flicker 30 and 55 with Still 70), the third Echo and
Still (50 each); its one `stuck` is an Offices door leaf. The glowstick case (both safe) is covered by
`test_flicker.gd::test_glowstick_watches_still_safe_from_flicker`.

## Sim-bot fixes (test code only)

- Pursuit: every profile walks straight across open floor to the farthest of its next 8
  waypoints on a clear line (`SimBotNull.straighten`, `walk_clear`; never across a studio
  light's cell, into the Threshold pocket, past a doorway pair or a soft crossing).
- The Threshold door is walked into from its face (`SimBot._threshold_front`).
- Explore targets are cells reachable from the spawn; open strata top up with spread cells off
  the path (the Garage `stuck` runs walked at a walled-off core room's centre).
- Every profile uses a Polaroid below 55 with no hunter within 20 m (the explorer and the
  direct bot died holding one to three).
- Left: an open door's leaf can trap the bot in the pocket between the leaf and the wall
  (Offices; 5 explorer timeouts and 1 cautious stuck in the after sweep). Doors owner item in
  `open_items.md`.

## What the cp-12 human runs must confirm

1. The Substrate at 10/s: of the 5 human runs, how many reach the Threshold, how many die to
   Null, and whether players route around Null with the unrender view or walk through its core.
   Target: hard but winnable, most deaths of a careful player at the Substrate.
2. Still's counter: a human who keeps Still lit in view and backs away, or hides, gets away
   (an evasion on the summary) at depths 2 and 5; the sims recorded 3 Still evasions in 279
   levels.
3. Depths 1 and 2 for a new player: reach depth 2 within three attempts (00 §9); note deaths
   to Still and Echo at depths 1 and 2 and the time they take (05 §2: 5 to 10 minutes).
4. The Offices dilemma reads as a choice: light (breaker, flashlight) against dark, and the
   glowstick as the answer.
5. Noclip use per run and whether Coherence at depth 6 arrival is still 90+ (the sims say it is).
6. The sawtooth by ear: a long Build at full intensity while exploring should not feel like
   constant maximum dread; music and the threat vignette should drop in Relief.

## R18 (history)

R18 (10 seeds, R14b tree): direct 4/10, cautious 3/10, explorer 0/10 reached the Threshold;
deaths at depth 6 were all Null. The M3.4 "before" stage repeats it at 20 seeds.
