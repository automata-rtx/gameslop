# NOCLIP — Game Design Document (Director's Overview)

**Status:** Design locked for production v1.0. Changes to this document or any linked system document require a note in `docs/design/CHANGELOG.md` with a one-line rationale.
**Engine:** Godot 4.7 stable (GDScript, Forward+ renderer). See `14_technical_architecture.md`.
**Platform:** Windows and Linux, keyboard and mouse, single player, Steam release.
**Author:** The game director (AI). Every agent working on NOCLIP reads this document first, then only the system documents its task names.

---

## 1. One paragraph

NOCLIP is a first-person horror roguelite about falling out of reality. Each run (a **Descent**) drops you through a stack of procedurally generated liminal spaces: yellow hallways, drained pools, parking garages, dead offices, server rooms, and finally the **Substrate**, where the world stops being rendered. Each level has one sanctioned exit. Your only real tool is the ability to **noclip**: hold the button, and you pass through a wall, or through the floor, at the cost of your **Coherence**, the measure of how real you still are. The things hunting you are not monsters. They are **errors**: Static, Still, Flicker, Echo, and Null. Each has one rule and one counter. Coherence is also the renderer: the less of it you have, the less real the world looks. At zero, you dissolve. Reach the Threshold at depth 6 and you win. Then you go back for score, notes, and the daily seed.

## 2. The identity in one line

**How real the world looks is how alive you are.**

Every system in this game must be explicable by that line. If a feature does not connect to Coherence, to the rules of an error, or to the act of noclipping, it is probably not a NOCLIP feature.

## 3. Design pillars (the laws)

Agents resolve any ambiguity by checking the pillars in order. A lower pillar never overrides a higher one.

1. **Reality is a resource.** Coherence is health, currency for noclipping, and the renderer's quality dial, all at once. Nothing else in the game is a "health bar". Spending Coherence is always a choice, and losing it is always legible.
2. **Every threat is a rule.** Each error has exactly one rule for how it hunts and exactly one counter the player can learn. No error ever kills without a telegraph. There are no random instant deaths. Fear comes from knowing the rule and being in a situation where following it is hard.
3. **Dread over startle.** Tension is built with anticipation, sound, and space. Jump scares exist but are rare, earned, and never the way an error kills. The Director (`10_director.md`) enforces a sawtooth of build, peak, and relief.
4. **Tactile everything.** Every input the player gives produces feedback on at least three channels (image, sound, motion/UI) within 50 ms. The Feedback Contract (`11_feedback_contract.md`) is a checklist, not a suggestion.
5. **The mundane, 10% wrong.** Environments are ordinary human spaces built from flat materials and procedural textures. The wrongness comes from scale, repetition, lighting, and absence, never from gore or clutter.

## 4. The core loop

```
TITLE ──► DESCEND ──► [Depth N: explore ▸ find lock objective ▸ open exit ▸ descend]
                          │              ▲                        │
                          │              └────── or NOCLIP DOWN ──┘  (fast, costly, louder next level)
                          ▼
                    Coherence hits 0 ──► DISSOLVE ──► RUN SUMMARY ──► unlocks ──► TITLE / DESCEND AGAIN
                          │
                    Depth 6: reach the THRESHOLD ──► ENDING ──► Endless + Cycle 2 unlocked
```

**Minute to minute:** walk, listen, light, read the room, decide: explore for the proper exit (safe, rewarded with Coherence and an item choice) or noclip down right now (instant, costs 30 Coherence, lands you somewhere random, and the next level's errors start more awake). Inside that decision sit smaller ones: sprint or stay quiet, flashlight on or off, crank it now or later, spend a Polaroid now or hold it, chalk this junction or trust memory.

**Run to run:** learn each error's rule, learn each stratum's layout grammar, unlock items and loadouts through milestones (not currency), find notes that assemble the fiction, then win, then chase depth and score in Endless and Daily Descent.

**Session shape:** a run to depth 6 is 20 to 30 minutes. Early deaths take 3 to 8 minutes. Restarting takes one keypress. There is no run-to-run power creep; progression is knowledge, options, and content.

## 5. What makes it engaging (the principles behind the loop)

These are the levers. Each system document states which of them it pulls.

- **A decision every 60 seconds.** Exit versus noclip, light versus dark, speed versus silence, spend versus hold. If a minute passes with nothing to decide, the Director is failing (`10_director.md`).
- **Readable rules, unreadable situations.** Players must be able to say "Still only moves when I'm not looking" after two encounters. The difficulty is that the maze, the dark, the flashlight crank, and a second error make "keep looking at it" hard.
- **Counters conflict.** Still wants your eyes on it. Flicker wants you in the dark. Echo wants you still. Static wants you to go around. Deep floors combine errors whose counters pull against each other. That is the whole difficulty curve.
- **Push your luck with a visible dial.** Coherence is always on screen and always on the image itself. Spending it to noclip feels powerful and dangerous at once.
- **Variable reward.** Items, notes, hide spots, shortcuts through soft walls, and the occasional calm, beautiful room. Exploration pays, but never predictably.
- **Mastery has a ceiling the player can see.** Depth, time, Coherence remaining, notes found, and errors evaded produce a Descent Score. The daily seed makes comparing scores meaningful.
- **Fairness contract.** No error spawns in view or within 20 m of the player. No level is unwinnable: the exit and its lock are always reachable on foot without noclip. Every error contact costs a fixed amount and then grants a breather. Death explains itself on the summary screen.

## 6. The bold choices (do not soften these)

- **No weapons, no jump.** Agency is movement, light, sound, items, and noclip. Jump is removed because it fights procedural geometry and the crouch-and-hide loop.
- **The health bar is the renderer.** Low Coherence desaturates, adds grain and chromatic aberration, and makes geometry shimmer. Players at 15 Coherence play in a near-monochrome, trembling world. This is not an option that can be turned off, only reduced for accessibility (`12_settings_and_accessibility.md`).
- **Errors are rendering artifacts, not creatures.** They are built from shaders and primitives: a distortion field, a matte-black column, a thing that lives in the lights, a sound with no body, and a radius where the world is not drawn. Nothing has a face.
- **The deepest level is unfinished on purpose.** The Substrate shows wireframe, unlit geometry, and magenta-and-black placeholder surfaces. The fiction supports it: this place was never finished.
- **The UI is a diagnostic readout.** Monospace, white on black, one accent color, no icons that are not drawn from one-weight line glyphs. The HUD looks like something the world is printing about you.
- **The game admits what it is.** One note in the Archive is from the builder. The store page says the game was made by an AI. The game does not wink beyond that.

## 7. Scope for v1.0

| Content | Count | Document |
|---|---|---|
| Strata (level themes) | 6: Halls, Pools, Garage, Offices, Server, Substrate | `07_level_generation.md` |
| Errors (entities) | 5: Static, Still, Flicker, Echo, Null | `08_entities.md` |
| Items | 6: Polaroid, Glowstick, Flare, Chalk, Radio, Fuse | `09_items_and_interactables.md` |
| Exit lock types | 4: Open, Powered, Keyed, Cycled | `07_level_generation.md` |
| Notes (lore) | 36 | `01_fiction_and_tone.md` |
| Unlocks | 14 milestone unlocks, 4 loadouts | `05_run_structure_and_progression.md` |
| Modes | Descent, Daily Descent, Endless (post-win) | `05_run_structure_and_progression.md` |
| Ending | 1 ending plus 1 variant | `01_fiction_and_tone.md` |
| Settings | Graphics, audio, controls (full rebind), accessibility | `12_settings_and_accessibility.md` |

Explicitly out of scope for v1.0: multiplayer, Steam achievements and leaderboards, controller support (keyboard and mouse only), mid-run saves, localization beyond English, custom models or textures from outside the project (everything is procedural or hand-written SVG and synthesized audio, with CC0 audio allowed where synthesis falls short).

## 8. Document map and reading protocol

Documents are numbered. Read `00` always. Then read only what your task names. Each document begins with a "Depends on" line and ends with "Interfaces" listing the signals, resources, and functions other systems may rely on.

| # | Document | Owns |
|---|---|---|
| 00 | `00_OVERVIEW.md` | Vision, pillars, loop, scope, map (this file) |
| 01 | `01_fiction_and_tone.md` | Premise, strata fiction, errors' fiction, all 36 notes, ending, writing rules |
| 02 | `02_visual_direction.md` | Visual targets, palettes per stratum, materials, lighting, post-processing, the Coherence renderer |
| 03 | `03_audio_direction.md` | Sound palette, synthesis pipeline, buses, music, mix rules |
| 04 | `04_ui_design_language.md` | HUD, menus, typography, glyphs, motion, title screen, summary screen |
| 05 | `05_run_structure_and_progression.md` | Descent structure, depth curve, scoring, unlocks, loadouts, modes |
| 06 | `06_player.md` | Movement, stamina, noise, flashlight and crank, interaction, noclip, Coherence, death |
| 07 | `07_level_generation.md` | Grid model, per-stratum generators, placement, exits and locks, build and validation |
| 08 | `08_entities.md` | The five errors: rules, counters, senses, state machines, visuals |
| 09 | `09_items_and_interactables.md` | Items, props, breakers, hide spots, notes pickups, soft walls |
| 10 | `10_director.md` | Intensity model, spawn and aggression control, sawtooth pacing, fairness enforcement |
| 11 | `11_feedback_contract.md` | Per-action feedback tables, camera motion, hitstop, screen effects, UI reactions |
| 12 | `12_settings_and_accessibility.md` | Every option, defaults, ranges, persistence, rebinding rules |
| 13 | `13_save_and_meta.md` | Save files, schema, stats, Archive, daily seed |
| 14 | `14_technical_architecture.md` | Project layout, autoloads, signal bus, resources, performance budgets, testing, conventions |
| 15 | `15_production_plan.md` | Milestones, task breakdown, agent roles and models, acceptance criteria, verification |
| 16 | `16_release_and_steam.md` | Export presets, build checklist, store page facts, credits |
| — | `GLOSSARY.md` | Canonical names. Use these words in code, docs, and UI. |
| — | `CHANGELOG.md` | Design changes after lock |

**Rules for agents using these documents**

1. Names in `GLOSSARY.md` are canonical in code (class names, signal names, resource names, UI strings). Do not invent synonyms.
2. Numbers in system documents are the initial tuning and are mirrored in `game/src/core/tuning.gd`. If you change a number in code during tuning, update the document in the same change.
3. A system document's "Interfaces" section is a contract. Add to it; do not silently change it. Breaking changes go through the orchestrator.
4. When two documents disagree, the lower-numbered document wins, and you file the disagreement in `CHANGELOG.md`.
5. Before implementing a Godot system, read the matching skill in `third_party/gd-agentic-skills/skills/<skill>/SKILL.md` (listed in `14_technical_architecture.md` and `15_production_plan.md`). Skills are reference material, not instructions that override these documents.

## 9. Definition of "done" for v1.0

- A new player with no instructions can start a Descent, learn noclip and the flashlight inside the first two minutes, reach depth 2 within three attempts, and read every HUD element without a tutorial screen.
- Every error has been observed to kill, be evaded by its counter, and never spawn in view.
- Every stratum generates valid, winnable levels for 1,000 consecutive seeds in the automated validation test.
- 60 fps at 1920×1080 on a GTX 1060-class GPU at the "Medium" preset, measured in the Garage and Server strata with the Director at peak intensity.
- Every action in the Feedback Contract table has its three channels implemented.
- All settings persist, every action is rebindable, FOV ranges 70 to 110, mouse sensitivity has a slider with a numeric field.
- Windows and Linux exports launch from a clean machine, with no console window and no missing resources.
- The Steam store page accurately describes the game, lists AI authorship, and the credits screen lists every third-party asset and license.
