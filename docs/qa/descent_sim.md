# Descent simulation (R18, review S6)

Chained simulated Descents: one run per seed and profile, depths 1 to 6, Coherence, belt and
RunState carried through the real exit, Landing (item pick) and arrival. Inputs for M3.4
(Null lethality, `open_items.md`). Measured on the tree at R14b plus R18, seeds 1 to 10 per
profile, `--max-seconds 600` per level.

```
tools/godot/bin/godot --headless --fixed-fps 60 --path game --script tests/sim/sim_run.gd -- \
    --descent --seeds 10 --from 1 --profiles direct,explorer,cautious [--json out.json]
```

The gate (`tests/sim/test_sim_descent.gd`) plays direct seeds 1 and 2; `NOCLIP_FULL_TESTS=1`
plays the 10-seed sweep over all three profiles. The Landing pick is the bots' rule
(`SimDescent.pick_index`: Polaroid below 75 Coherence, else glowstick, flare, Polaroid, else
row 0). Each seed is deterministic for one build; a later change to a rule will move a row.

## Per profile

| profile | runs | threshold | died | other | deaths_by_depth(1..6) | mean_arrival_coh(1..6) | n_arrivals(1..6) | mean_time_s | death_causes |
|---|---|---|---|---|---|---|---|---|---|
| direct | 10 | 4 | 6 | 0 | 0/0/0/0/0/6 | 100/97/99/100/98/95 | 10/10/10/10/10/10 | 275 | null:6 |
| explorer | 10 | 0 | 7 | 3 | 3/1/0/2/1/0 | 100/75/69/68/100/- | 10/7/4/3/1/0 | 512 | echo:4 flicker:2 still:1 |
| cautious | 10 | 3 | 7 | 0 | 0/0/0/1/1/5 | 100/99/98/100/99/92 | 10/10/10/10/9/8 | 415 | null:5 still:1 static:1 |

`deaths_by_depth` and `mean_arrival_coh` run depth 1 to 6; arrival Coherence is after the
Landing's +20.

## Per run

| profile | seed | outcome | death_depth | cause | reached | time_s | spent | coherence_at_arrival | items_at_arrival |
|---|---|---|---|---|---|---|---|---|---|
| direct | 1 | threshold | 0 |  | 6 | 243.0 | 0.0 | 100 100 100 100 100 100 | cha8+pol1 | cha8+glo1+pol1 | cha8+glo2+pol1 | cha8+glo2+pol2 | cha8+glo2+pol2+rad1 | cha8+glo3+pol2+rad1 |
| direct | 2 | dissolved | 6 | null | 6 | 254.7 | 0.0 | 100 100 100 100 100 100 | cha8+pol1 | cha8+pol2 | cha8+glo1+pol2 | cha8+fla1+glo1+pol2 | cha8+fla1+glo1+pol3 | cha8+fla1+glo2+pol3 |
| direct | 3 | threshold | 0 |  | 6 | 270.5 | 0.0 | 100 100 100 100 100 85 | cha8+pol1 | cha8+glo1+pol1 | cha8+glo1+pol2 | cha8+glo2+pol2 | cha8+fla1+glo2+pol2 | cha8+fla1+glo2+pol3 |
| direct | 4 | threshold | 0 |  | 6 | 290.4 | 0.0 | 100 100 100 100 100 70 | cha8+pol1 | cha8+glo1+pol1 | cha8+glo2+pol1 | cha8+glo3+pol1 | cha8+glo4+pol1 | cha8+fus1+glo4+pol1 |
| direct | 5 | dissolved | 6 | null | 6 | 276.1 | 0.0 | 100 100 100 100 100 100 | cha8+pol1 | cha8+pol2 | cha8+glo1+pol2 | cha8+fla1+glo1+pol2 | cha8+fla1+glo2+pol2 | fla1+glo2+pol2+rad1 |
| direct | 6 | dissolved | 6 | null | 6 | 263.9 | 0.0 | 100 100 100 100 100 100 | cha8+pol1 | cha8+glo1+pol1 | cha8+glo2+pol1 | cha8+glo2+pol2 | cha8+glo3+pol2 | cha8+glo4+pol2 |
| direct | 7 | threshold | 0 |  | 6 | 310.0 | 0.0 | 100 66 86 100 100 100 | cha8+pol1 | cha8+pol2 | cha8+glo1+pol2 | cha8+glo2+pol2 | cha8+glo3+pol2 | cha8+fla1+glo3+pol2 |
| direct | 8 | dissolved | 6 | null | 6 | 322.3 | 0.0 | 100 100 100 100 85 91 | cha8+pol1 | cha8+pol2 | cha8+glo1+pol2 | cha8+fla1+glo1+pol2 | cha8+fla2+glo1+pol2 | cha8+fla2+glo2+pol2 |
| direct | 9 | dissolved | 6 | null | 6 | 252.4 | 0.0 | 100 100 100 100 100 100 | cha8+pol1 | cha8+glo1+pol1 | cha8+glo1+pol2 | cha8+glo2+pol2 | cha8+glo2+pol3 | cha8+fus1+glo2+pol3 |
| direct | 10 | dissolved | 6 | null | 6 | 270.2 | 0.0 | 100 100 100 100 100 100 | cha8+pol1 | cha8+glo1+pol1 | cha8+glo2+pol1 | cha8+glo3+pol1 | cha8+glo3+pol2 | cha8+glo4+pol2 |
| explorer | 1 | stuck | 0 |  | 3 | 590.6 | 0.0 | 100 85 80 | cha8+pol1 | cha8+pol2 | cha8+pol3 |
| explorer | 2 | dissolved | 2 | echo | 2 | 305.5 | 0.0 | 100 50 | cha8+pol1 | cha8+pol2 |
| explorer | 3 | dissolved | 1 | echo | 1 | 278.7 | 0.0 | 100 | cha8+pol1 |
| explorer | 4 | dissolved | 4 | flicker | 4 | 638.8 | 0.0 | 100 100 84 54 | cha8+pol1 | cha8+glo1+pol1 | cha8+glo2+pol1 | cha8+glo3+pol1 |
| explorer | 5 | stuck | 0 |  | 2 | 292.5 | 0.0 | 100 83 | cha8+pol1 | cha8+pol2 |
| explorer | 6 | dissolved | 1 | echo | 1 | 285.3 | 0.0 | 100 | cha8+pol1 |
| explorer | 7 | dissolved | 4 | echo | 4 | 765.7 | 0.0 | 100 50 39 59 | cha8+pol1 | cha8+pol2 | cha8+glo1+pol2 | cha8+glo2+pol2 |
| explorer | 8 | dissolved | 5 | flicker | 5 | 1204.8 | 0.0 | 100 54 74 92 100 | cha8+pol1 | cha8+pol2 | cha8+pol3 | cha8+glo1+pol3 | cha8+fla1+glo1+pol3 |
| explorer | 9 | stuck | 0 |  | 2 | 495.7 | 0.0 | 100 100 | cha8+pol1 | cha8+glo1+pol1 |
| explorer | 10 | dissolved | 1 | still | 1 | 264.4 | 0.0 | 100 | cha8+pol1 |
| cautious | 1 | threshold | 0 |  | 6 | 351.8 | 0.0 | 100 100 100 100 100 100 | cha8+pol1 | cha8+glo1+pol2 | cha8+glo3+pol2 | cha20+fla1+glo3+pol2 | cha20+fla1+glo4+pol3 | cha20+fla2+glo4+pol3 |
| cautious | 2 | dissolved | 6 | null | 6 | 319.9 | 0.0 | 100 100 93 100 100 100 | cha8+pol1 | cha8+pol3 | cha8+glo1+pol3 | cha8+glo2+pol3 | cha8+glo3+pol3 | cha8+glo4+pol3+rad1 |
| cautious | 3 | threshold | 0 |  | 6 | 455.0 | 20.0 | 100 100 100 100 100 85 | cha8+pol1 | cha8+glo1+pol2 | cha8+glo1+pol3 | cha16+glo2+pol3+rad1 | cha16+glo3+pol3+rad1 | cha16+glo4+pol3+rad1 |
| cautious | 4 | dissolved | 4 | still | 4 | 549.1 | 0.0 | 100 100 85 100 | cha8+pol1 | cha8+glo1+pol1 | cha16+glo3+pol2 | cha16+glo4+pol2 |
| cautious | 5 | dissolved | 6 | null | 6 | 389.2 | 0.0 | 100 100 100 100 100 70 | cha8+pol1 | cha16+pol2 | cha16+glo1+pol3 | cha16+fla1+glo2+pol3 | cha20+fla2+glo4+pol3 | cha20+fla2+fus1+glo4 |
| cautious | 6 | dissolved | 6 | null | 6 | 330.6 | 5.0 | 100 89 100 100 100 100 | cha8+pol1 | cha8+pol3 | cha16+glo2+pol3 | cha20+glo3+pol3+rad1 | cha20+fla1+glo4+rad1 | cha20+fla2+glo4+rad1 |
| cautious | 7 | threshold | 0 |  | 6 | 367.2 | 10.0 | 100 100 100 100 100 100 | cha8+pol1 | cha8+glo1+pol1 | cha8+glo2+pol2 | cha8+glo2+pol3+rad1 | cha8+glo4+pol3+rad1 | cha16+glo4+pol3+rad1 |
| cautious | 8 | dissolved | 6 | null | 6 | 486.0 | 0.0 | 100 100 100 100 100 81 | cha8+pol1 | cha8+pol3 | cha8+glo2+pol3 | cha16+glo3+pol3 | cha16+fla2+glo3+pol3 | cha20+fla2+glo4+pol3 |
| cautious | 9 | dissolved | 5 | static | 5 | 555.3 | 0.0 | 100 100 100 100 100 | cha8+pol1 | cha8+glo1+pol2 | cha8+glo4+pol3 | cha16+fla1+glo4+pol3 | cha16+fla2+glo4+pol3 |
| cautious | 10 | dissolved | 6 | null | 6 | 349.8 | 5.0 | 100 100 100 100 95 100 | cha8+pol1 | cha8+glo1+pol3 | cha16+glo1+pol3 | cha16+glo2+pol3 | cha16+glo3+pol2+rad1 | cha16+glo3+pol3+rad1 |

Items are the belt at each arrival (`cha` chalk, `pol` Polaroid, `glo` glowstick, `fla` flare,
`rad` radio, `fus` fuse).

## Reading

- Pillar 1 across a Descent: direct and cautious arrive at depth 6 at 92 to 100 mean Coherence.
  +20 per exit plus the Polaroid refill cover everything depths 1 to 5 take from them; the
  Substrate is where Coherence is decided. Neither profile spends Coherence on noclip to speak of
  (`spent` 0 to 20), so the economy is not stressed from the spend side.
- The Substrate (Null) kills 6 of 10 direct and 5 of 10 cautious runs that arrive there, and the
  survivors cross at 100 down to 20. 4/10 and 3/10 reach the Threshold. That is the R14b rate
  (6/12 to 9/12 exits from 100) seen from a whole run: arriving at 90+ is the norm, so the chain
  does not make Null deadlier than the single-level sims said. Judge it with human runs (N3).
- The explorer never reaches the Threshold: 7 of 10 die at depths 1 to 5 (Echo 4, Flicker 2,
  Still 1; it lingers 4 to 6 minutes a level and meets every hunter) and 3 of 10 end `stuck`
  (seeds 1, 5, 9 at depths 3, 2, 2, bot navigation, not a game defect found here). Its
  Coherence is 68 to 75 on average at depths 2 to 4. It is the profile for the Director, not
  for the economy.
