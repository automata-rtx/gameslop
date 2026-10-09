# Glossary — canonical names

Use these exact words in code identifiers, UI strings, and documents. The code column is the identifier form.

| Term | Meaning | Code |
|---|---|---|
| NOCLIP | The game. Also the verb: pass through a wall or floor by spending Coherence. | `noclip` (action), `NoclipTargeting` |
| Descent | One run from depth 1 to death, abandonment, or the Threshold. | `RunState`, `start_run` |
| Depth | Integer level index, 1 upward. | `depth: int` |
| Stratum (plural strata) | The theme of a level: Halls, Pools, Garage, Offices, Server, Substrate. | `StratumData`, `&"halls"` `&"pools"` `&"garage"` `&"offices"` `&"server"` `&"substrate"` |
| Cycle | Depths 1 to 6 are Cycle 1; 7 to 12 Cycle 2 (Endless). | `cycle: int` |
| Coherence | How real the player is: the only health; spent by noclip; drives the renderer. | `coherence: float`, `apply_coherence` |
| Stamina | Sprint resource. | `stamina` |
| Charge | Flashlight energy, raised by cranking. Also: noclip charge progress. | `flashlight_charge`, `noclip_charge` |
| Crank | Hold to recharge the flashlight; loud. | `crank` (action) |
| Error | One of the five things that hunt the player. Never "monster", "enemy", "entity" in text or code. | `ErrorBase`, group `errors` |
| Static | Drifting distortion field; drains inside. | `ErrorStatic`, `&"static"` |
| Still | Moves only when unobserved. | `ErrorStill`, `&"still"` |
| Flicker | Lives in lit fixtures; lunges; attaches to the flashlight. | `ErrorFlicker`, `&"flicker"` |
| Echo | Follows the footstep trail 800 ms late. | `ErrorEcho`, `&"echo"` |
| Null | Walks through everything; unrenders the world. | `ErrorNull`, `&"null"` |
| Observe / observing | The player's lit, unoccluded, in-frustum view of a node (Still's rule). | `Player.is_observing` |
| Contact | An error reaching the player: fixed cost, stun, push, satiated. | `Player.contact`, `contacted_player` |
| Satiated | An error's 20 s retreat after contact. | `&"satiated"` |
| Evasion | A chasing error losing the player. | `lost_player`, `evasions` |
| Encounter / notice | An error entering chase against the player (Archive counter). | `noticed_player`, `codex` |
| Director | Per-level pacing authority. | `Director` |
| Intensity | Director's 0..1 pacing value. | `intensity` |
| Aggression | Director's 0..1 error parameter scale. | `aggression` |
| Phase | Director phase: Calm, Build, Peak, Relief, Pursuit. | `&"calm"` `&"build"` `&"peak"` `&"relief"` `&"pursuit"` |
| Threat | 0..1 presentation value for vignette and heartbeat. | `threat` |
| Scare | A Director event (door slam, payphone, swell, dropout, pre-echo). | `Scares` |
| Awake | The post-drop aggression bonus. | `awake` |
| Exit | The sanctioned way down. One per level. | `Exit`, `exit_cell` |
| Lock | Exit condition: Open, Powered, Keyed, Cycled. | `&"open"` `&"powered"` `&"keyed"` `&"cycled"` |
| Breaker | Powers a Powered exit (and Offices lights). | `Breaker`, `breaker_thrown` |
| Fuse | Item for breaker Variant B. | `&"fuse"` |
| Keycard | Non-slot key for a Keyed exit. | `keycard` |
| Landing | The 6 s cabin between levels after a proper exit; the item choice. | `landing.tscn`, `LandingPanel` |
| Drop | Leaving a level by noclipping through the floor. | `descend(false)`, `drops_in_a_row` |
| Proper exit | Leaving through the exit. | `descend(true)`, `proper_exits` |
| Threshold | The front door at depth 6; the win. | `threshold_door`, `ending.tscn` |
| Dissolve / dissolution | Death at 0 Coherence. | `dissolved`, `&"dissolve"` pulse |
| Soft wall | Generator-marked cheap noclip wall with a shimmer. | wall type `SOFT`, uniform `soft` |
| Solid | A wall that cannot be passed (perimeter, cores). | wall type `SOLID` |
| Partition | 1.5 m cubicle wall. | wall type `PARTITION` |
| Unrender | Geometry shown as grid lines on black (Null, noclip, Substrate). | shader term `u`, `g_null_*` |
| Placeholder | Magenta/black checker on unfinished Substrate surfaces. | `pattern_mode 5`, flag `UNFINISHED` |
| Fixture | A light prefab with an emissive mesh and a pooled light. | `Fixture`, group `fixtures` |
| Fixture group | A set of fixtures (room or corridor segment); Flicker's habitat unit. | `fixture_group: int` |
| Light pool | The nearest-N light enabling system. | `LightPool` |
| Hide spot | Under car, under desk, locker, pump corner, rack gap. | `HideSpot`, layer `hide_spots` |
| Note | One of 36 lore sheets. Voices: faller, builder, stray, builder_final. | `NoteData`, `note_found` |
| Polaroid | Item: +25 Coherence, a warm image. | `&"polaroid"` |
| Glowstick, Flare, Chalk, Radio | Items. | `&"glowstick"` `&"flare"` `&"chalk"` `&"radio"` |
| Belt | The four item slots. | `Inventory`, `ItemSlot` |
| Loadout | Faller, Cartographer, Lightbearer, Diver. | `LoadoutData`, `&"faller"` `&"cartographer"` `&"lightbearer"` `&"diver"` |
| Daily Descent | The date-seeded mode. | `&"daily"` |
| Endless | Post-win mode continuing past depth 6. | `&"endless"` |
| Archive | The meta screen: notes, errors codex, statistics, unlocks, credits. | `archive.tscn` |
| Descent Score | The run score. | `compute_score` |
| Coherence renderer | The post stack and global shader params tied to Coherence. | `CoherenceRenderer` |
| World shader | The single surface shader for level geometry and props. | `world_surface.gdshader` |
| Feedback Contract | The per-action feedback table (`11`). | `docs/qa/feedback_checklist.md` |
| Shutter | The UI's 6-band reveal/hide motion. | `shutter_in/out` |
| Glitch transition | The 120 ms sliced screen transition. | `GlitchTransition` |
| Tour | The screenshot tour debug mode. | `--tour` |
| Grid, cell, edge | The 2 m level grid; walls on edges. | `LevelGrid`, `Vector2i` cells |
| Critical path | BFS path from spawn to exit. | flag `CRITICAL_PATH` |
| Calm window | The chase-free first 30 s (15 s after a drop) of a level. | `CALM_SECONDS` |
| Hint | A Director suggestion to an error's wander/search destination. | `hint(pos)` |
