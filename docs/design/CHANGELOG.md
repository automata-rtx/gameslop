# Design changelog

Entries are one line each: date, document, change, rationale. The design was locked on 2026-10-07; anything after that is listed here.

- 2026-10-07 — all — Initial design lock (v1.0 design).
- 2026-10-07 — 02 — Post stack is a full-screen spatial quad (can read depth), not a CanvasLayer; world shader stays opaque and unrenders by dithered alpha scissor. Reason: canvas shaders cannot read depth; alpha-blend geometry breaks SSAO, fog, and chalk decals.
- 2026-10-07 — 08 — Echo targets the entry 800 ms before its newest heard step and freezes when the player stops; Search never inspects the player's own cell. Reason: the original wording contradicted the "stop" counter.
- 2026-10-07 — 08, 06 — Still's "lit" predicate includes chemical lights and uses fixture power state and light range, not the light pool. Still chase speed capped at 5.4 m/s; aggression table clamps outside [0.25, 0.75]. Reason: readability and sprint must remain an escape.
- 2026-10-07 — 08 — Per-error definitions of notice and evasion; Flicker distances in XZ; Attached lunge defined. Reason: codex counters and unlocks were unreachable for three errors.
- 2026-10-07 — 06, 05 — Noclip refused with `TOO THIN` when Coherence ≤ cost; fairness rule 5 restated as testable invariants; `substrate` death cause added. Reason: pillar 1 (spending is a legible, survivable choice).
- 2026-10-07 — 07 — Variant B always places one fuse and the validator checks it; Substrate dead ends ≤ 4 cells; spawn/exit/breaker rooms defined for Pools, Garage, Server, Substrate; Landing holds the door until the level is ready. Reason: winnability guarantees.
- 2026-10-07 — 05, 02, 07 — Null only in the Substrate in Cycle 2 (radius ×2 from depth 12); Server's native slot is a previously met hunter. Reason: undefined Pursuit on ordinary strata.
- 2026-10-07 — 11, 14, 06 — Hitstop and pause use the scene tree pause with ALWAYS-mode presentation nodes; no custom time scale. Reason: Godot has no custom pausable process groups.
- 2026-10-07 — 09, 05, 01 — Chalk is one stack of uses (cap 20); exit entry is a walk-in trigger; notes per level defined (2, or 1 on depth 6); `exit_status_changed(status, timer)`. Reason: contradictions and a pacing gap for Archive completion.
- 2026-10-07 — 12, 04 — Rebind conflicts swap; FSR 2 only below render scale 1.0 and replaces AA; first-run hints and the Landing panel render key names from bindings. Reason: engine behaviour and rebinding correctness.
- 2026-10-07 — 05, 07, 13 — One seed derivation function (`Seeds.derive`) and one daily seed expression. Reason: two-argument `hash()` does not exist.
- 2026-10-07 — 15, CLAUDE.md — Continuous production with tagged checkpoints replaces milestone gates; human play only at cp-12 and cp-13. Reason: the user wants minimal playtesting and bisectable builds.

## Production

- 2026-10-07 — 01, 08 — Note U1 and Null's codex say "object" instead of "entity". Reason: "entity" is a forbidden word (01 §2); the rule outranks the two passages that broke it.
- 2026-10-07 — 14 — Pinned Godot 4.7.2 stable (newest 4.7 patch) in `tools/godot/VERSION`. Reason: 14 §1 asks for 4.7 stable; the patch release carries fixes only.
- 2026-10-07 — 04 — Typing cursor is `▌` (U+258C) instead of `▮`. Reason: JetBrains Mono has no U+25AE, and font fallback is disabled so missing glyphs stay visible.
- 2026-10-07 — 14 — Additive autoload API from M0.2 recorded under 14 Interfaces; project theme set to `noclip_theme.tres`. Reason: contracts other tasks will call.
- 2026-10-07 — 04 — Boot line is `rendering` without the ellipsis. Reason: 01 §6 writing rules ban ellipses in UI strings and 01 wins.
- 2026-10-07 — 04, 09 — Breaker prompt text is `FLIP BREAKER` and door prompts are `OPEN DOOR` / `CLOSE DOOR` (04 §6); the breaker stays a 0.6 s hold (06, 07, 09). Reason: 04 wins over 09's `THROW BREAKER` and `OPEN`.
- 2026-10-07 — 02 — Substrate distance fog runs 25 m to 45 m (the §7 range); §6's "black at 40 m" is read as a point inside it. Reason: the two sections of 02 disagree.
- 2026-10-07 — 11, 06 — Flicker lunge trauma 0.4 (11 §3) is superseded by the contact trauma 0.6 (06 §9) whenever a lunge lands. Reason: 06 wins; both values stay in `tuning.gd`.
- 2026-10-07 — 04, 14 — `strings.gd` lives in `game/src/core/` (14 §2), not `game/data/` (04 §11). Reason: 14 owns the layout.
- 2026-10-07 — 07, 05, 14 — `Seeds.derive` lives in `game/src/core/seeds.gd` (`class_name Seeds`); `tuning.gd` stays constants only and is exempt from the 400-line script limit. Unlock ids are `Tuning.UNLOCK_IDS` in milestone order. Reason: a const-only class cannot hold a function; unlock ids were unspecified.
- 2026-10-07 — 14, 15, CLAUDE.md — Agents verify rendering themselves with `tools/ci/render.sh` (Forward+ on Mesa lavapipe under Xvfb). Reason: removes the human from visual verification before cp-12; frame-time budgets still need a real GPU.
- 2026-10-07 — 03 — Audio manifest is the sample catalogue; crank split into ratchet and whine; six extra sounds (`noclip_cancel`, `noclip_fall`, `drop_arrival`, `ui_hold_tick`, `ui_shutter`, `ui_type`) that 11 and 04 call for. Reason: interfaces for M1.11.
- 2026-10-07 — 11 — "Leave hide spot" gets sound (cloth) and motion (0.6 s slide out) so every player input has three channels (pillar 4). "Still within 8 m" and "Still observed ≥ 2 s" stay sparse on purpose: absence of sound is Still's tell (pillar 3); "Unlock earned" is not a player input. Reason: cp-01 review.
- 2026-10-07 — 06 — Player interface additions and six readings recorded under 06 Interfaces (M1.3). Reason: contracts for HUD, errors, run flow.
