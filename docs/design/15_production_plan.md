# 15 — Production Plan

**Depends on:** every other document. This is the document the orchestrating agent works from.

---

## 1. Team model

NOCLIP is built by an **orchestrator** session and **specialist agents** it spawns per task. The orchestrator owns integration, the test gate, the changelog, and the human's 15-minute check at each milestone. Specialists own one task each, read only the documents the task lists, and deliver code plus tests plus a short report.

### Model recommendations

The user plans to run the orchestrator on Opus 5.5 after this design phase. In Claude Code, a subagent inherits the orchestrator's model unless an agent definition (`.claude/agents/<name>.md`, `model:` in its frontmatter) or the `model` parameter of the Agent tool overrides it. The agent definitions in this repo already set the recommended model per role, so the orchestrator only needs to pick the role.

| Role | Model | Why |
|---|---|---|
| Orchestrator (the main session) | **Opus 5.5** | Holds the whole design, makes integration calls, reviews cohesion. The hardest job. |
| `levelgen-engineer`, `errors-engineer`, `render-engineer`, `player-engineer` | **Opus 5.5** | Core systems where feel and correctness interact and where mistakes cascade. Each gets a fresh context per task. |
| `director-engineer`, `ui-engineer`, `audio-engineer`, `systems-engineer` | **Opus 5.5** for first implementation; **Sonnet 5.5** for follow-up tasks once interfaces exist | These are specified tightly enough for Sonnet after the first version exists. |
| `feature-engineer` (bounded tasks: settings menu, save/meta, glyphs, data resources, export presets, credits, test scaffolding, recipes) | **Sonnet 5.5** | Well-bounded work with explicit acceptance criteria. Cheaper and fast. |
| `design-reviewer` | **Opus 5.5** | Reads a delivered task against the design and the pillars; reports deviations. Run at every milestone, and after any core-four task. |
| `qa-engineer` | **Sonnet 5.5** | Writes and runs tests, fills checklists, reproduces bugs. |
| Haiku | not used for code | Only for mechanical file lookups if ever. |

Working rules for agents:
1. One task per agent, fresh context, the task's document list in the prompt. Never "read all of docs/design"; `00` plus the named documents.
2. Parallel tasks run in separate git worktrees (`isolation: worktree`) when they touch different directories; the orchestrator merges and runs the test gate.
3. Every task delivers: code, tests (or bench scene updates), a `CHANGELOG.md` line if a design number moved, and a 10-line report (what, how verified, open questions).
4. Agents never change an "Interfaces" section silently; they propose the change in the report.
5. The orchestrator runs `tools/ci/test.sh` after every merge and never merges red.
6. When an agent cannot verify visually (no GPU), it says so and lists what the human should look at in the next checkpoint note; it does not wait.

### Continuous production and checkpoints (how the human stays out of the loop)

The orchestrator does **not** wait for the human at milestone boundaries. It proceeds through every task in order, merging as the test gate allows, and stops only at **checkpoints**: states of the repository where the game is coherent enough to be built and tried. The human may test any checkpoint later to find where something broke, and is expected to play seriously only at the last two.

**Checkpoint rules**
1. A checkpoint is a git tag `cp-NN-<slug>` on `main` (NN two digits, in order), with a one-paragraph note in `docs/checkpoints.md`: what works, what is stubbed, known issues, and what a tester would look at. The cloud session's git proxy may refuse tag pushes (it did for `cp-00-design`): always also push the same commit as a branch `checkpoint/cp-NN-<slug>`, which is never force-pushed, so every checkpoint is reachable on GitHub either way. The human can turn checkpoint branches into tags at any time with `git tag cp-NN-<slug> origin/checkpoint/cp-NN-<slug> && git push origin cp-NN-<slug>`.
2. Before tagging: `tools/ci/checkpoint.sh` green (the full suite with `NOCLIP_FULL_TESTS=1`: 1,000 seeds per stratum and wall-clock budgets enforced, which the per-merge gate samples and only reports, plus `--validate-levels 1000`, smoke, and exports); in detail: `tools/ci/test.sh` green; `$GODOT_BIN --headless --path game -- --smoke` exits 0 (the smoke mode must work headless: it boots, generates depth 1, runs 2 s of logic, and quits; no rendering required); and from cp-06 onward, `tools/ci/export.sh` produces the Windows and Linux zips headless (exports do not need a GPU; templates are fetched by `tools/godot/fetch.sh`).
3. Builds for a checkpoint are attached to a GitHub release for that tag when the session has GitHub release access (`gh release create cp-NN-<slug> build/*.zip`); otherwise the note says "build from tag with `tools/ci/export.sh`".
4. The orchestrator writes `docs/qa/human_check_cp-NN.md` for checkpoints marked **(human)** below, as a numbered list of observations. These are requests, not gates: production continues immediately.
5. Nothing is tagged red. If a checkpoint cannot be reached green, the orchestrator fixes forward, never tags around it.

**Planned checkpoints** (the orchestrator may add intermediate ones, never skip these):

| Tag | Content | Human? |
|---|---|---|
| `cp-00-design` | The design documents (this tag exists before any code). | no |
| `cp-01-foundation` | M0 complete: project opens headless, autoloads, data, tests, synth pipeline. | no |
| `cp-02-halls` | Halls generates, builds, validates; a player can walk, look, light, crank; debug overlay; `--seed` launch. | no |
| `cp-03-noclip` | Noclip through walls and floors; the Coherence renderer and world shader; HUD. | no |
| `cp-04-still` | Static and Still with the Director's phases; contact, stun, hiding. | no |
| `cp-05-loop` | Exit with Powered lock, Landing with item choice, drop arrival, death, summary, minimal title, Polaroid/Chalk/Glowstick, notes, audio for everything so far. | no |
| `cp-06-slice` | M1 complete, reviewed by `design-reviewer`, first exported builds. | optional (first look, 10 minutes) |
| `cp-07-pools-garage` | Pools and Garage grammars, water, two decks, their props and audio. | no |
| `cp-08-offices-server` | Offices and Server grammars, dark groups, breaker dilemma, cages. | no |
| `cp-09-echo-flicker` | Echo and Flicker complete, all four locks, Flare/Radio/Fuse/Keycard, all hide spots, scares. | no |
| `cp-10-substrate` | Substrate, Null, the Threshold, the ending and variant, Cycle 2 corruption. | no |
| `cp-11-meta` | Score, unlocks, loadouts, Daily, Endless, meta.json, Archive, complete settings with rebinding, captions, first-run guidance, music director. | no |
| `cp-12-cohesion` | M3 complete: Feedback Contract audit, visual targets, mix pass, tuning from telemetry, performance pass, accessibility. | **yes** (30-minute play script) |
| `cp-13-rc` | Release candidate: exports, icons, smoke, Steam templates, store page facts, credits, checklists. | **yes** (clean-machine run) |
| `cp-14-release` | Fixes from the human's RC notes; the build uploaded to Steam. | yes (upload) |

Between cp-06 and cp-12 the orchestrator runs its own simulated playtests (headless scripted runs with Director telemetry, `10` §9) and the `design-reviewer` after each checkpoint, so that the human's first real session at cp-12 is about taste and feel, not bugs.

## 2. Milestones

### M0 — Foundation (toolchain and skeleton)
Goal: a Godot project that opens, runs tests headless, and has every autoload, signal, resource type, and convention in place with stubs.

Deliverables: `tools/godot/fetch.sh` working in the container; `game/project.godot` with renderer, physics, layers, globals, input map, autoloads; `EventBus` with all 18 signals; `tuning.gd` with every number from the design (named per document section); `strings.gd` with every UI string; the eight autoload stubs; `TestCase` and the runner; `tools/ci/test.sh`; the UI theme with the bundled font (`tools/fonts/fetch.sh`); the glyph SVG set; `StratumData`/`ItemData`/`NoteData`/`ErrorData`/`LoadoutData` resource scripts and the `.tres` files authored from the documents (notes verbatim); `.gitignore`; `CLAUDE.md` build commands verified.

Acceptance: `tools/ci/test.sh` passes with at least the tuning and data tests (every note ID present, every item kind, every stratum); `$GODOT_BIN --headless --path game --quit` exits 0 with no errors.

### M1 — Vertical slice (Halls, depth 1 → 2)
Goal: the loop exists and feels right in one stratum.

Deliverables: player (`06` complete, including noclip wall and floor); Halls grammar, builder, validator, navigation (`07` for Halls only, including soft walls and the Powered lock with breaker); `LightPool` and fixtures; world shader and Coherence post stack (`02` §4 and §5 complete); HUD (`04` §6 complete); Static and Still (`08`); Director with phases and Still/Static only (`10`); exit, Landing with item choice, drop arrival (`05` §4); items Polaroid, Chalk, Glowstick (`09`); notes pickup and sheet; death and the Run Summary; a minimal title (DESCEND, SETTINGS placeholder, QUIT); audio: the synth pipeline with the player, Halls, Static, Still, and UI recipes; the Feedback Contract rows for everything above; the debug overlay and `--seed` launch; the screenshot tour.

Acceptance: a human plays depth 1 to depth 2 repeatedly; Still never moves while observed; soft walls shimmer and pass; the breaker powers the exit with the wave; Coherence visibly degrades the image; the summary shows the cause; 1,000 Halls seeds validate; all M1 unit tests pass; the orchestrator's simulated runs and the design-reviewer confirm the loop; the optional cp-06 human look is recorded, not awaited.

### M2 — Breadth (every stratum, every error, every system)
Goal: the whole game exists, rough.

Deliverables: Pools, Garage (two decks), Offices, Server, Substrate grammars with validation; Echo, Flicker, Null; Flare, Radio, Fuse, Keycard; all four locks; Director scares and the Pursuit schedule; water; hide spots (all five kinds); vending, payphone; the full roster per depth; `GameState` with score, unlocks, loadouts, Daily, Endless; `meta.json`; the Archive; the complete settings menu with rebinding; captions; music director; all stratum audio recipes and the error recipes; the ending scene; the first-run guidance; Cycle 2 corruption.

Acceptance: a full Descent to the Threshold is possible; every error has been observed to kill and be evaded by its counter in `error_arena.tscn`; 1,000 seeds per stratum validate; every setting persists; the sawtooth simulation test passes; simulated full Descents reach the Threshold; the design-reviewer passes; production continues without waiting for the human.

### M3 — Cohesion (the pass that makes it a game)
Goal: greater than the sum of its parts.

Deliverables: the Feedback Contract audit with every row ticked; visual targets T1 to T8 verified per stratum from the tour with fixes; audio mix pass (bus levels, ducking, occlusion, captions); tuning pass over the error roster, aggression, item weights, and level sizes from the Director telemetry of at least 20 agent-simulated and 5 human runs; the Still/Flicker light dilemma verified in Offices; performance pass to the budgets (`14` §10) including the Garage and Server at peak; accessibility options verified; the title screen's live corridor; the ending variant; the forbidden-words grep; every debug bench updated.

Acceptance: `docs/qa/feedback_checklist.md` complete; tour frames pass the histogram script; frame budgets verified by the profiler where measurable headless and by the cp-12 human play script (the first checkpoint that waits for nothing but is written for the human to play).

### M4 — Release
Goal: a build the human can upload.

Deliverables: export presets, icons, `export.sh`, `smoke.sh`, zipped builds for both platforms with README and checksums, Steam build scripts, store page facts file (`docs/release/store_page.md` from `16` §5 with the final screenshot list), credits with licenses, the release checklist filled.

Acceptance: `docs/qa/release_checklist.md` complete for both platforms; the human runs the Windows build on a clean machine and confirms the first-run flow.

## 3. Task breakdown

Each task: id, role, documents (always plus `00`), depends on, deliverable, acceptance. Tasks within a milestone with no dependency between them run in parallel.

### M0
| ID | Role | Docs | Depends | Deliverable | Acceptance |
|---|---|---|---|---|---|
| M0.1 | systems-engineer | 14 | — | `tools/godot/fetch.sh`, `VERSION`, `tools/ci/test.sh`, `tests/run_tests.gd`, `test_case.gd`, `.gitignore` | runner executes a sample test headless |
| M0.2 | systems-engineer | 14, 05, 06 | M0.1 | `project.godot` (renderer, physics, layers, input map, globals, autoloads), the eight autoload stubs, `EventBus` signals, `Clock`, `SceneRouter` with glitch stub | project loads headless with no errors |
| M0.3 | feature-engineer | 06, 08, 10, 05, 02 | M0.1 | `tuning.gd` with every constant, named by doc section; `strings.gd` with every UI string | a test asserts the presence of listed constants |
| M0.4 | feature-engineer | 01, 09, 07, 05, 08 | M0.1 | Resource scripts and `.tres` data: strata, items, notes (verbatim), errors, loadouts | data tests: 36 notes, 6 strata, 6 items + keycard, 5 errors, 4 loadouts |
| M0.5 | ui-engineer | 04 | M0.1 | `tools/fonts/fetch.sh`, theme resource, glyph SVG set (all listed) | `ui_gallery.tscn` placeholder shows every glyph |
| M0.6 | audio-engineer | 03 | — | `tools/audio/synth.py` engine + `recipes.json` for UI and player sounds; `--verify` | WAVs generated, verify passes |

### M1
| ID | Role | Docs | Depends | Deliverable | Acceptance |
|---|---|---|---|---|---|
| M1.1 | levelgen-engineer | 07, 09 §8 | M0.2, M0.4 | `LevelGrid`, ops library, Halls grammar, validator, determinism | 1,000 Halls seeds validate; determinism test |
| M1.2 | levelgen-engineer | 07, 02 §6, 14 §10 | M1.1 | `LevelBuilder` (merged meshes, collision with metadata, nav bake), `LightPool`, fixture prefab, Halls props | integration test: path on navmesh; build slice ≤ 4 ms |
| M1.3 | player-engineer | 06, 11, 02 §9, §11 | M0.2, M0.3 | Player, camera rig, flashlight and crank, interaction ray, noise model, Coherence, stun, hide (closet), state machine | unit tests from `06` §13 |
| M1.4 | player-engineer | 06 §8, 07 §7, 11 | M1.2, M1.3 | `NoclipTargeting`, charge/commit, wall pass, floor drop hooks, soft wall handling | validity tests against synthetic walls; manual pass through Halls walls |
| M1.5 | render-engineer | 02 | M0.2 | `world_surface.gdshader`, `coherence_post.gdshader`, `CoherenceRenderer`, globals, Halls materials, fog/environment per `StratumData`, dust | tour frames at 100/60/30/10; T1, T3, T4 pass for Halls |
| M1.6 | ui-engineer | 04 §6, §8, 11 | M0.5, M1.3 | HUD complete, note sheet, prompts, notifications, shutter and typing | `ui_gallery.tscn` states |
| M1.7 | errors-engineer | 08 §2, §3, §4 | M1.2, M1.3 | `ErrorBase`, senses, Static, Still | observation tests; `error_arena.tscn`; behaviour test |
| M1.8 | director-engineer | 10 | M1.7 | Director phases, intensity, aggression, spawning, fairness functions (scares stubbed) | sawtooth sim test; calm window; contact exclusivity |
| M1.9 | systems-engineer | 05 §4, 09 §5, 14 §5 | M1.2, M1.3 | `run.tscn` flow, exit + Powered lock + breaker + power wave, Landing cabin and item panel, drop arrival, death → summary, title minimal | play depth 1 → 2 → death → summary → title |
| M1.10 | feature-engineer | 09 | M1.3, M1.6 | Inventory, Polaroid (with `PolaroidPainter`), Chalk, Glowstick, note pickup, items in world | unit tests from `09` §10 |
| M1.11 | audio-engineer | 03 | M0.6, M1.3, M1.7 | `AudioManager`, buses, reverb per stratum, recipes for Halls, Static, Still, doors, breaker, noclip; generator layers (static bed) | audio board; mix rules 1 to 5 |
| M1.12 | qa-engineer | 11, 14 §9 | M1.3 to M1.11 | `feedback_bench.tscn`, debug overlay, `--seed` launch, screenshot tour, `human_check_M1.md` | bench fires every M1 row |
| M1.13 | design-reviewer | all M1 docs | M1.12 | Cohesion review against pillars and interfaces; list of deviations | report; orchestrator schedules fixes |

### M2
| ID | Role | Docs | Depends | Deliverable |
|---|---|---|---|---|
| M2.1 | levelgen-engineer | 07 §5.2, §5.3 | M1.2 | Pools (basins, water, steps, drain hatch) and Garage (two decks, ramps, cores, cars, stairwell) grammars, props, validation |
| M2.2 | levelgen-engineer | 07 §5.4, §5.5 | M1.2 | Offices (ring, cubicle partitions, dark groups, glass) and Server (racks, cages, hatch) grammars, props, validation |
| M2.3 | levelgen-engineer | 07 §5.6, §9 | M2.1 | Substrate (unfinish, pocket, Threshold, studio lights) and Cycle 2 corruption |
| M2.4 | errors-engineer | 08 §6 | M1.7 | Echo (trail, mirroring, lures, hiding) |
| M2.5 | errors-engineer | 08 §5, 02 §6 | M1.7, M1.2 | Flicker (groups, habitat, stalk, lunge, attach/shed, chemical immunity, breaker interaction) |
| M2.6 | errors-engineer | 08 §7, 02 §5 | M1.7, M2.3 | Null (motion, unrender driver, core, audio tone) |
| M2.7 | director-engineer | 10 §5, §2 Pursuit, 05 §3 | M1.8, M2.4 to M2.6 | Scares, roster per depth, chaser caps, awake arrivals, Pursuit schedule, telemetry CSV |
| M2.8 | feature-engineer | 09 | M1.10 | Flare, Radio, Fuse, Keycard, vending, payphone, hide spots (car, desk, locker, pump, rack gap), water area, thrown physics |
| M2.9 | systems-engineer | 07 §6, 05 | M1.9 | All four locks and exit prefabs per stratum, Cycled timers, Keyed readers, Variant B |
| M2.10 | systems-engineer | 05, 13 | M1.9 | `GameState` complete (score, unlocks, loadouts, Daily, Endless), `SaveManager`, `meta.json`, unlock notifications |
| M2.11 | ui-engineer | 04 §7, 12 | M1.6 | Menu shell, title complete (live corridor), pause, settings with rebinding and live test, Archive, summary complete, loadout select |
| M2.12 | ui-engineer | 04 §9, §10, 12 §6 | M2.11 | First-run guidance, captions, accessibility options wiring |
| M2.13 | render-engineer | 02 §7, §8, §10 | M1.5, M2.1 to M2.3 | Materials and environments for the five remaining strata, water, monitor, rack LED, dissolve grid, error visuals, Threshold, ending corridor look |
| M2.14 | audio-engineer | 03 | M1.11 | Remaining recipes (strata, errors, items, scares), `MusicDirector`, Null tone, occlusion, captions emission |
| M2.15 | systems-engineer | 01 §8 | M2.3, M2.13 | Ending scene, credits scroll, variant |
| M2.16 | qa-engineer | all | M2.* | Tests for every new system; `error_arena` buttons for all five; `human_check_M2.md` |
| M2.17 | design-reviewer | all | M2.16 | Cohesion review |

### M3
| ID | Role | Docs | Deliverable |
|---|---|---|---|
| M3.1 | qa-engineer + player-engineer | 11 | Feedback Contract audit and fixes; checklist filled |
| M3.2 | render-engineer | 02 §2, §13 | Visual target verification per stratum from the tour; histogram script; fixes |
| M3.3 | audio-engineer | 03 §6 | Mix pass; loudness; occlusion; caption coverage |
| M3.4 | director-engineer + errors-engineer | 10, 08, 05 §3 | Tuning pass from telemetry: roster, aggression, timings; Offices light dilemma verification |
| M3.5 | systems-engineer | 14 §10 | Performance pass: profiling in Garage and Server at peak; light pool, chunk culling, errors' budget |
| M3.6 | ui-engineer | 04, 12 | Polish pass: all menus and HUD at UI scale 0.75 to 1.5 and 1280 × 720 to 2560 × 1440; accessibility verification |
| M3.7 | feature-engineer | 01 §2, 16 §4 | Forbidden-words grep; strings review; credits text |
| M3.8 | design-reviewer | all | Final cohesion review: play the simulated run logs, read the summary screens, confirm pillars |
| M3.9 | qa-engineer | — | `human_check_M3.md`: 30-minute play script with observations |

### M4
| ID | Role | Docs | Deliverable |
|---|---|---|---|
| M4.1 | systems-engineer | 16 | Export presets, icons, `export.sh`, `smoke.sh`, zips, checksums, README.txt |
| M4.2 | feature-engineer | 16 §3, §5 | Steam templates and upload script; `docs/release/store_page.md` |
| M4.3 | qa-engineer | 16 §4 | Release checklist filled; `human_check_M4.md` (clean-machine run) |

## 4. Risk register

| Risk | Impact | Mitigation |
|---|---|---|
| No GPU in agent containers | Visual verification depends on the human | Logic in tests; tour command; human check lists; `godot-agent-vision` where available |
| Runtime navmesh bake too slow for large levels | Errors dormant too long after arrival | Threaded bake; cap level size; bake per chunk if needed |
| Garage two decks complicate generation and navigation | M2.1 slips | Fallback documented: single deck with cores and strips; keep ramps as a stretch within M2 |
| Flicker habitat edge cases (no lit groups, attach during crank) | Confusing behaviour | Explicit state table in `08` §5; despawn/respawn rule; tests |
| Synthesized audio sounds cheap | Store impression | Recipes iterated in M3.3; CC0 allowed for water and relays; mix rules |
| Font or template downloads blocked | M0 slips | Fallback to Godot's default font; templates fetched by the human if needed |
| Merged meshes with per-vertex data break TAA or SSAO | Visual artifacts | Test in M1.5 early; fall back to per-cell meshes with MultiMesh |
| Still observation predicate feels unfair (lit requirement) | Core rule misread | Render tick as confirmation; hint 7; `error_arena` tuning; the human check asks specifically |
| Scope creep from agents "improving" errors | Pillar 2 broken | `08` §1 law; design-reviewer at every milestone |

## 5. Definition of done per task

Code compiles headless with no warnings-as-errors in the project's GDScript warnings config; tests pass; the task's bench scene (if any) runs; the report is written; no "Interfaces" change without a proposal; `CHANGELOG.md` updated if a number moved; no forbidden words introduced.
