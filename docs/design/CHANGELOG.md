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
