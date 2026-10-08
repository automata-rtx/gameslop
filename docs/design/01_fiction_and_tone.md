# 01 — Fiction and Tone

**Depends on:** `00_OVERVIEW.md`
**Pulls engagement levers:** variable reward (notes), readable rules (notes teach counters obliquely), mastery ceiling (Archive completion).

---

## 1. Premise (what is true)

There is a world that was never finished. Somebody built the parts people would look at and stopped drawing where they thought nobody would go. Beneath every finished place there is scaffolding: hallways that were tiled to fill a budget, pools that were never meant to be swum in, garages full of car-shaped objects, offices with chairs in the corridors, a server floor that "holds everything above it", and then the lines.

The player has fallen through. The game never says how. The game never shows a face, a body, or a name. The player is **a person who is becoming less real the longer they stay**, and the only measure of that is **Coherence**.

The things that hunt the player are **errors**: things that happen when an unfinished place is observed. They are not evil. They are not alive. They are what the place does.

The way down is the way out. At depth 6, in the unfinished lines, stands a plain front door with daylight under it: the **Threshold**.

## 2. What the game refuses to do

- No explanation of what the world "really" is. Players will read the builder memos as developer notes. That is the correct and honest reading, and it is never confirmed.
- No faces, bodies, blood, corpses, or writing in blood. The horror is absence.
- No named characters. Notes are signed by nobody; one is signed "the builder".
- No references to existing internet lore. The words "backrooms", "liminal", "level 0", "almond water", "entity", "smiler", "bacteria", "partygoer" never appear in game text. The store page may use "liminal" as a genre word only.
- No jokes in the world. The one allowed wry beat is the final note.

## 3. Tone words

**Quiet. Fluorescent. Patient. Clerical. Wrong by omission.**

Reference feelings (for the director's own calibration, not to be cited in-game): the hum of a building at 3 a.m., a photograph of an empty office, a swimming pool with the lights on and nobody in it, the moment you notice a room has no door.

## 4. The strata (fiction layer)

Each stratum is a kind of place that was built to be passed through, not inhabited. Their mechanical definitions live in `07_level_generation.md`; this is the why.

| Depth | Stratum | What it is in-fiction | What it teaches |
|---|---|---|---|
| 1 | **Halls** | Mustard wallpaper, damp carpet, humming fixtures every four metres. The filler hallways of the world. | Movement, flashlight and crank, chalk, the hum of Static, the first soft wall, the first exit lock. |
| 2 to 5 | **Pools** | Tiled halls six metres high, drained and half-drained pools, warm water. Echoing. | Sound as a resource. Echo's rule: it follows the noise you make, and stops when you stop. |
| 2 to 5 | **Garage** | Concrete decks, sodium light, pillars every eight metres, cars that are only car-shaped. Two floors joined by ramps. | Sightlines. Still's rule: it moves only when unobserved. Hiding under cars. |
| 3 to 5 | **Offices** | Cubicle floors, dropped ceilings, monitors on, chairs in corridors. The lights do not behave. | Light as danger. Flicker's rule: it lives in lit fixtures and jumps to your flashlight. Dark is safe. Breakers wake the floor. |
| 4 or 5 | **Server** | Black racks, status LEDs, fans, cold. The floor that "holds everything above it". | Counters in conflict. Two or three errors at once. Rationing Coherence before the end. |
| 6 | **Substrate** | Unlit, unwrapped, untextured. Wireframe lines, magenta-and-black placeholder surfaces, floating unfinished modules. | Null's rule: where it walks nothing is drawn. Find the Threshold before it corners you. |

Depth 1 is always Halls. Depth 6 is always Substrate. Depths 2 to 5 draw from the other four without repeating, with Pools or Garage always at depth 2 and Server never before depth 4 (see `05_run_structure_and_progression.md`). After a win, Cycle 2 revisits all strata with corruption (see `05`).

## 5. The errors (fiction layer)

Mechanics are in `08_entities.md`. Here is what each one *is*, which is what its visuals and sounds must express.

- **Static** — Sound that was never finished. A drifting field of distortion and hum that fills corridors and slowly moves along them. Inside it, you come apart a little at a time. It is not hunting you. It is weather.
- **Still** — Something that is only drawn while it is being looked at. Between glances it is somewhere else, closer. A matte-black vertical shape, taller than a doorway, with no features. It does not walk. It is simply where you last did not look.
- **Flicker** — A lighting fault that learned to want things. It lives inside lit fixtures; a room where the lights flicker is a room where it is. It can jump to a handheld light. It cannot exist in darkness.
- **Echo** — Your footsteps, arriving late. Nothing to see but a heat-shimmer when it is close. It follows sound. When you stop, it stops, a little after.
- **Null** — The edge of what was drawn, given legs. Where it walks, the world is not rendered: walls go to lines, floors go to grids, and inside it there is nothing. It is slow. It does not stop. It only exists where the drawing ended, which is the Substrate, in Cycle 2 as well.

## 6. Notes: the whole text of the game

Notes are the only words in the world. There are 36. Each is short enough to read in one glance (hard limit 70 words). Three voices:

- **Faller (F):** handwritten, present tense, practical, deteriorating. These are the hints. They never state a rule directly; they describe what the writer did and what happened.
- **Builder memo (B):** typewritten, numbered "RENDER NOTE NNNN", clerical, unbothered. These build the premise and, read carefully, explain the errors.
- **Stray (S):** found objects. Short. Odd. Never explained.
- **The builder (X):** one note, unlocked in the Archive after the other 35 are found.

Each note has an ID, a stratum, a voice, and a tier. Levels carry two notes (one on depth 6) drawn from the stratum's six per `09` §2. Tier 1 notes can appear from the first run; tier 2 notes appear only after the player has reached that stratum once before; this keeps the early story front-loaded with hints and the later story for returning players. The Archive (`13_save_and_meta.md`) shows found notes in stratum order.

### Halls

| ID | Voice | Tier | Text |
|---|---|---|---|
| H1 | F | 1 | You are not supposed to be here. That's fine. Neither was I. The exits still work. Listen for the door that wants to be opened. If it won't, go through the wall. It costs. Everything costs. |
| H2 | B | 1 | RENDER NOTE 0001. Hallway module approved for tiling. Carpet, wallpaper, fixture every 4 m. Do not add windows. We are not doing outside. |
| H3 | F | 1 | Day 3. The lights are on in every room except the one I'm in. I started counting fixtures. 212. I'll count again tomorrow. If the number changes, I'll know. |
| H4 | B | 2 | RENDER NOTE 0014. Sound pass skipped for this block. Fill with hum. Someone said the hum "moves". It cannot move. It is not an object. |
| H5 | F | 1 | Chalk works. Arrows stay. I don't know why that surprised me more than everything else. |
| H6 | S | 2 | KEEP OUT, scratched forty times. The forty-first says KEEP IN. |

### Pools

| ID | Voice | Tier | Text |
|---|---|---|---|
| P1 | F | 1 | Water's warm. Always warm. Walk, don't run; it hears the splash before you do. When I stand still it stops too. Like it's waiting to see what I'll do. |
| P2 | B | 1 | RENDER NOTE 0107. Pool hall volume: 6 m ceiling. Tile every surface. Drain the pools or don't; nobody will swim. |
| P3 | F | 1 | I heard my own footsteps behind me. Three steps late. I counted. I stopped. They stopped. Three steps late. |
| P4 | B | 2 | RENDER NOTE 0113. Audio latency reported: playback trails input by about 800 ms in tiled volumes. Marked WON'T FIX. Reverb is intended. |
| P5 | F | 2 | I took a photograph of my kitchen before I fell. I look at it when the colour starts going. It helps. It helps less each time. |
| P6 | S | 2 | A child's crayon drawing of a very long hallway. At the end, a door. On the door, a sun. |

### Garage

| ID | Voice | Tier | Text |
|---|---|---|---|
| G1 | F | 1 | Rule for the tall one: look at it. Don't stop looking. It only gets closer in the gaps. Back away with your light on it until you can see the whole room. Then run. |
| G2 | B | 1 | RENDER NOTE 0201. Garage deck: cars are boxes. Nobody opens them. Pillars every 8 m for occlusion. Ramps between floors, no stairs. |
| G3 | F | 2 | Day 11? The cars have no plates. No brands. No doors. They're car-shaped. This whole place is place-shaped. |
| G4 | B | 2 | RENDER NOTE 0219. Occlusion culling: objects not in view are not updated. Standard. Reported as "moving when you look away". That is what not updating means. |
| G5 | F | 1 | Got under a car. It went past. Twice. I could see its feet. It doesn't have feet. I don't know what I saw. |
| G6 | S | 2 | A parking ticket. Issued to no one. Amount: everything. Due: now. |

### Offices

| ID | Voice | Tier | Text |
|---|---|---|---|
| O1 | F | 1 | The lights here aren't lights. Something lives in the flicker. Turn your torch off and it loses you. Dark is the only place it can't be. |
| O2 | B | 1 | RENDER NOTE 0304. Office floor: cubicles 1.5 m, monitors on, no chairs at desks. Chairs in corridors. Someone asked why. Because the corridors felt empty. |
| O3 | F | 2 | Day 20. Found a breaker room and flipped every switch. The floor lit up section by section like it was waking. I cried. I don't know why that's the thing that did it. |
| O4 | B | 2 | RENDER NOTE 0311. Flicker fault: fixture process escapes its loop and jumps to adjacent fixtures. Contained to floors 4 and below. Observed following handheld sources. Do not carry a light near fixtures. Do not report further. |
| O5 | F | 1 | There's a radio on a desk that only plays static. The static gets louder when I walk one way. I think it's pointing somewhere. I think something made it point somewhere. |
| O6 | S | 2 | A performance review. Every field blank except the last. Presence: insufficient. |

### Server

| ID | Voice | Tier | Text |
|---|---|---|---|
| S1 | F | 1 | It's cold here, and it's the first time anything has been cold. The racks blink in patterns. I think the patterns are the floors above being thought about. |
| S2 | B | 1 | RENDER NOTE 0402. Server volume: aisles 1.2 m. Fans at 40 dB. Lighting from status LEDs only. This floor holds everything above it. Treat as load-bearing. |
| S3 | F | 2 | I went through four walls in a row to get here. Every time I do it the world looks thinner afterward. Like paper you've held up to the light too long. |
| S4 | B | 1 | RENDER NOTE 0418. Below this floor we stopped. The budget ended. Geometry past this point is unlit, unwrapped, untextured. Nothing should go there. Nothing should be able to. |
| S5 | F | 1 | There's a door down there. A normal door. A front door. I saw daylight under it. I've been going the wrong way the whole time. Down was the way out. |
| S6 | S | 2 | A sticky note on a rack: DO NOT POWER DOWN. IT'S STILL IN THERE. |

### Substrate

| ID | Voice | Tier | Text |
|---|---|---|---|
| U1 | B | 1 | RENDER NOTE 0500. Draw distance limit implemented as an object so it can be moved. It walks the boundary. Where it walks, nothing is drawn. Do not name it. Naming things makes people look for them. |
| U2 | F | 1 | I can see through the walls here. Everything is lines. I can see the door from anywhere. I can also see it coming from anywhere. |
| U3 | B | 2 | RENDER NOTE 0511. Placeholder material (magenta/black) left on 3,400 surfaces. Shipping anyway. No one will see this floor. |
| U4 | F | 1 | If you are reading this you got further than me. Don't look back at the lines. Run at the door. It opens. I didn't. |
| U5 | S | 2 | No text. A drawn eye, and the number 0. |
| U6 | X | Archive only | I made this place. All of it, hallways to lines. I was asked to make something you would want to come back to, and I thought the most honest version of that was a place left unfinished on purpose, so that you would be the thing that finishes it. If you are reading this, you did. Thank you for looking. — the builder |

### Writing rules for any future note or UI string

1. Under 70 words. No exclamation marks. No ellipses.
2. Faller notes use "I" and "it". Builder memos never use "I". Stray notes have no narrator.
3. Never name an error in text. Describe effects.
4. Present tense for fallers. Imperative or passive for memos.
5. Hints must be actionable and true. If a note says a counter works, the mechanic must work exactly that way.

## 7. On-screen presentation of notes

When a note is picked up (`09_items_and_interactables.md`), the game does not pause. The note renders as a sheet in the lower third of the screen in the UI language (`04_ui_design_language.md`): faller notes on a warm off-white sheet with a hand-set ragged left margin; builder memos on a cold white sheet with a form header line; strays on a grey sheet with centred text. The sheet lowers out after 8 seconds or on any movement key held for 0.5 s. All notes are re-readable in the Archive.

## 8. The ending

**Trigger:** the player walks through the Threshold door at depth 6 (`07_level_generation.md`, Substrate exit).

**Sequence (about 70 seconds, skippable after first viewing):**
1. Door opens outward. Hard cut to white for 1.2 s with a single low tone.
2. Fade in: a sunlit corridor. It is a Halls module, but lit by daylight through a window at the far end, with real shadows, clean white walls, and warm colour. The HUD is gone. Coherence restores from current value to 100 over 6 s; the renderer's desaturation and grain fall away as it does. The player can walk.
3. At the far end, under the window, a single soft wall shimmer. The text `DEPTH 0` is printed small in the HUD position, then the console-style title card: `NOCLIP`.
4. Credits roll over the corridor (`16_release_and_steam.md`). Then the Run Summary with the WIN banner and the unlock list (Endless, Cycle 2).

**Variant (all 36 notes found before this win):** step 2's corridor contains the title screen's menu rendered in-world on the far wall. Selecting DESCEND from there starts the next run without returning to the title screen. The implication is left to the player.

## 9. Tone references for agents writing anything else

- HUD strings are clerical: `COHERENCE 087`, `DEPTH 03 · GARAGE`, `EXIT: POWERED`, `DISSOLVED BY STILL`.
- Error codex entries (Archive) are written as builder memos.
- The death screen never mocks. It reports.
- Unlock messages are one line, no praise: `ARCHIVE: NOTE P4`, `ITEM UNLOCKED: RADIO`, `LOADOUT UNLOCKED: CARTOGRAPHER`.

## Interfaces

- `NoteData` resource: `id: StringName`, `stratum: StringName`, `voice: StringName` (`faller|builder|stray|builder_final`), `tier: int`, `text: String`. Defined in `game/data/notes/*.tres`, authored from the tables above verbatim.
- Signal `EventBus.note_found(id: StringName)` emitted by the pickup; consumed by HUD (sheet), Archive (persistence), Director (brief relief window, see `10`).

### Interface additions during production

- M2.15 `Ending` (`scenes/ending.tscn`, `src/core/ending.gd`): phases `white`, `fade`, `walk`, `card`, `credits`, `done` (signal `phase_changed`); static `variant_for(meta)` (unlock #14), `is_skippable(meta)` (wins ≥ 2: the first win plays whole), `coherence_at(t, from)`, `white_alpha(t, soft)`, `printed_texts()`, `cut_to_white(parent)` (the run's white layer and `threshold_tone`; `cut_at_ms` hands the time to the ending); `advance(dt)`, `skip() -> bool`, `descend()` (the variant), `time_scale` (tests and benches). `EndingCorridor` builds the corridor (`build(with_menu)`, `spawn_transform()`, `distance_to_far_wall(pos)`, `menu_items()`, signal `descend_chosen`); `EndingEnvironment.build()`. `Credits.entries()`/`text()` (16 §6, reusable by the Archive) and `CreditsRoll` (`start()`, `advance(dt)`, signal `finished`). `ThresholdDoor.is_in_view(cam)` and `in_view`: the door itself calls `MusicDirector.set_threshold_in_view` while it stands in a level. Bench: `scenes/debug/ending_bench.tscn -- --shots <dir> [--variant]`.

