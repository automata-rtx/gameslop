# Play script: cp-12 (30 minutes of play, needs a GPU)

M3 made the game cohere: the Feedback Contract audit, the visual targets, the mix pass, the tuning from simulated Descents, the performance pass, the accessibility pass. The machines have done what machines can do (more than 1,200 tests, the sims, the budgets). This is the first checkpoint written to be **played**, not inspected. Nothing here is pass or fail. Each prompt asks you to notice something and write down what you noticed, in your own words, short. The design wants a particular experience (`docs/design/00_OVERVIEW.md`: "How real the world looks is how alive you are"); this script finds out whether it arrives.

**How to use it.** Play one Descent from a fresh save, naturally, the way you would play a game you bought. The `Notice` lines tell you what to watch for at each stage; do not stop playing to write more than a few words. Keep `docs/qa/notes_cp-12.md` open beside the game (copy it as it is; it has a heading for every stage below) and jot at the pauses: the Landing, the summary, the end. If something looks broken, write one line and keep going. A rule, a counter or a tell you did not understand is the most valuable thing you can record: do not look it up first.

**The clock.** Core play is 30 minutes, then the rating sheet (5 minutes). The times in `[ ]` are a guide to where you should be, not a limit. If you die, that is not a failure of the session: read the summary, press DESCEND AGAIN, and keep the clock running. Up to three Descents is the target (`00` §9: a new player reaches depth 2 within three attempts). At minute 20 stop the natural play wherever you are and do Stage 6, then Stage 7.

---

## 0. Setup

### 0.1 Get the build

The checkpoint is the branch named in `docs/checkpoints.md` under `cp-12-cohesion` (expected `checkpoint/cp-12-cohesion`; the tag `cp-12-cohesion` may not be present, the proxy can refuse tag pushes). From a clone of the repository:

```
git fetch origin
git checkout checkpoint/cp-12-cohesion
tools/godot/fetch.sh                  # downloads the pinned Godot 4.7.2 into tools/godot/bin; prints: export GODOT_BIN=...
export GODOT_BIN=<the path it printed>   # Linux; on Windows use the editor you installed (4.7.2) and set the same name
$GODOT_BIN --headless --path game --import   # once, and again after any pull
```

Run every command below from the repository root. Every `$GODOT_BIN` line is a command for the editor binary, so the debug overlay (F3) and the bench scenes exist.

**Or an export** (the real game, no F3, no benches, so no Part T, L, P or G): `tools/godot/fetch.sh --templates`, then `tools/ci/export.sh`; it writes `build/NOCLIP-<version>-linux.zip` and `-windows.zip` with checksums (the version is in `game/src/core/version.gd`). Unzip, run `./NOCLIP.x86_64` or `NOCLIP.exe` with `NOCLIP.pck` beside it. Use the export for the core 30 minutes if you want the shipped feel; use the editor binary for everything else. Either way write which one you used in the notes.

### 0.2 What you need

A computer with a Vulkan GPU (the target is a GTX 1060-class card at 1920 x 1080; say what you have), keyboard and mouse, closed headphones. A dark room helps. Close other programs.

### 0.3 The save

The user folder is `~/.local/share/NOCLIP/` on Linux (`$XDG_DATA_HOME/NOCLIP/` if set) and `%APPDATA%\NOCLIP\` on Windows. It holds `settings.cfg` and `meta.json`.

- **Fresh save (the core 30 minutes).** Rename the folder (`NOCLIP` to `NOCLIP.mine`) so nothing is lost, and start the game. With no `meta.json` this is a **first Descent**: depth 1 has Static only, the hints are on, the Archive is empty. This is the experience that matters most; you can only have it once per save, so do not rehearse it first.
- **Mid-game fixture (optional parts).** Copy `docs/qa/fixtures/meta_m2_mid_save.json` into the folder as `meta.json`. It unlocks the Glowstick, Radio, Flare and Fuse, three loadouts (Cartographer, Lightbearer, Diver) and Daily Descent, with 14 notes found and the hints retired. Use it for Parts T, L, P, A and G, never for the core 30 minutes. To go back to a fresh save, delete `meta.json` (and `settings.cfg` if you changed settings).

### 0.4 Settings to note (do not change them for the core play)

Open SETTINGS from the title and write down, in the notes, what the defaults are on your machine: WINDOW MODE, resolution, FIELD OF VIEW (default 90), BRIGHTNESS, graphics PRESET (default MEDIUM), MASTER volume (default 80), and every ACCESSIBILITY option (all at their defaults). Do not turn on captions, Reduce visual noise or anything else for the core 30 minutes: the first Descent is judged as designed. Set your system volume once on the first footsteps so a footstep is comfortable, then leave it alone.

### 0.5 Controls

| | |
|---|---|
| Move / Look | W A S D / Mouse |
| Sprint / Crouch | hold Left Shift / hold Left Ctrl |
| Interact | E (hold where a prompt says HOLD) |
| Flashlight / Crank | F / hold R |
| Noclip | hold Left Mouse Button (release to cancel) |
| Use item / pick item | Right Mouse Button / 1 to 4 or wheel |
| Status | hold Tab |
| Pause | Esc |
| Debug overlay (editor binary) | F3 |

You are not told how any of it works beyond the in-game hints. That is the point.

### 0.6 Launch lines

| Name | Line |
|---|---|
| Game | `$GODOT_BIN --path game` |
| Game with telemetry | `$GODOT_BIN --path game -- --telemetry` (debug builds; writes each level's Director CSV to `<user folder>/run_telemetry/`) |
| Level | `$GODOT_BIN --path game -- --seed <n> --depth <n> --stratum <halls\|pools\|garage\|offices\|server\|substrate>` (give all three) |
| Ending | `$GODOT_BIN --path game res://scenes/debug/ending_bench.tscn` (add `-- --variant` for the variant) |
| Arena | `$GODOT_BIN --path game res://scenes/debug/error_arena.tscn -- --stratum halls` |
| Items bench | `$GODOT_BIN --path game res://scenes/debug/items_bench.tscn` |
| Board | `$GODOT_BIN --path game res://scenes/debug/audio_board.tscn` |

A Level launch drops you into a built level with the Director running but no HUD, no run and no cabin: the exit does not take you down. Press F3 for the seed, Coherence and the Director's lines. It is for looking at one place and for the targeted runs of Part T.

---

## The core 30 minutes

The first Descent is the experience. The staged prompts below follow it in order; the depth you are at decides which stage you are in, not the clock. Stages 1 to 5 are the natural play; Stage 6 and Stage 7 start at minute 20 whatever happened.

### Stage 1. Title and the first minute `[0:00 to 2:00]`

Launch the Game on the fresh save, and choose DESCEND.

Notice:
- What did the title promise? One word for the mood.
- Between pressing DESCEND and having control: how long did it feel, and what was on the screen?
- In the first 30 seconds, what did you do with your hands before the hints told you? (Look, walk, press F?)
- Did the hint lines (`MOVE`, `FLASHLIGHT`, `CRANK`, `NOCLIP`) arrive when you needed them, early, or late? Which one did you not need?
- Can you read every element of the HUD (Coherence, depth, the exit line, the belt) without being told what it is? Which one did you have to guess?

### Stage 2. Depth 1: Halls `[2:00 to 8:00]`

The first Descent has Static only, drifting near the main route between the breaker and the exit. The exit is Powered: it needs the breaker.

**The place (pillars 4 and 5).**
- Name the first thing that felt wrong about the Halls (scale, repetition, light, absence). Was it subtle or obvious?
- Is the Halls a place you would believe in, 10% wrong, or is it a set? Where did it tip?
- Press F, then crank (hold R) once. Did the flashlight and the crank feel like something you did (a sound, a motion, a change in the image), or like a setting you toggled? Say which of the three (image, sound, motion) was weakest.
- Sprint, then crouch-walk. Could you tell from sound alone which you were doing?

**Coherence, the dial (pillar 1).**
- Where did your eye go to check Coherence: the readout or the picture? When did you first notice the picture change?
- Spend some on purpose (see "Noclip as a choice" below) and note: at about what Coherence did the world feel clearly less real? At what Coherence did you feel afraid of it?

**Static (rule, tell, counter).**
- How did you first become aware of Static: a sound, the look of the air, the loss of Coherence? At what distance, roughly?
- When you were inside it, did you know what was happening and why? Could you tell where the edge was?
- What did you do about it (go around, wait, noclip past, ignore it)? Did you learn that from the game or work it out? Could you say its rule in one sentence now?
- How much did the loss cost you, in how you played afterwards?

**The exit and the breaker (a decision every 60 seconds).**
- What was your exit line when you first saw it (OPEN, POWERED)? What did you do next?
- If it was POWERED: was finding and throwing the breaker satisfying (the clunk, the wave of light travelling to the exit), or a chore? What was your fear on the way there?
- Write the time you reached the exit, and what you guess the level took (the design targets about 3 minutes).

### Stage 3. Noclip as a choice `[any time; at least once by minute 12]`

You are told at the first hint that noclip exists. Use it at least once through a wall, and think about the floor.

Notice:
- The first time you thought "I could noclip": what made you consider it (a threat, a long walk, curiosity)? What made you do it, or not?
- During the 2.5 s of a floor drop, and the 0.35 s of a wall: what did the charge feel like (the ring, the tone, the image)? Was it ever unclear what it would do or why it refused (the words `SOLID`, `NO SPACE`, `TOO THIN`, `TOO FAR`)?
- The moment it fired: could you feel the cost (sound, image, Coherence)? Did it feel powerful, dangerous, or both?
- Did you ever noclip when you did not need to, only because you could? Did you ever wish you had and could not afford it?
- A drop (floor) costs 30 and the next level arrives `DROPPED · THEY ARE AWAKE`. If you dropped: did the next level feel meaner, and was it worth it? If you did not: what held you back?

### Stage 4. The Landing, and the sawtooth `[after the first exit, about 8:00]`

Walk into the open exit.

**The Landing (the cabin).**
- What did the cabin feel like: relief, a pause, a loading screen? Did the 6 seconds feel too short or too long?
- Did you understand the item choice at once (`CHOOSE ONE`, `[1]` and `[2]`)? How did you decide between the two? What did you pick?
- The panel prints the Coherence the arrival will add (`COHERENCE +7` means you were at 93; no line at all means you were already full). Did you notice it arriving? Did it feel like a reward?
- What was your Coherence when you entered each cabin, and did the world look less real at any point before depth 6? (M3 review S1: this decides the Landing gain, below.)
- How did the door opening onto the next level feel?

**The sawtooth (pillar 3).** From now to the end, keep a rough line in the notes: write the time whenever you felt dread rising, a peak (a chase, a contact, a near thing) and relief (the quiet after). Three words each is enough.
- Was there a stretch of two minutes or more where nothing happened and it still felt tense? (Good.) Was there a stretch where you were bored? (Note when and where.)
- After a chase or a contact: did the game give you room to recover, and did you feel it (sound thinning, the music dropping, the vignette easing)? How long did relief last before dread began again?
- Did intensity (music, vignette) ever stay at its height for minutes with nothing happening, for example on a level you explored slowly after cranking at the start? (M3 review S2: since R20 cranking in the quiet phases adds no dread.)
- Was any moment a **startle** (a jump-scare, a loud sudden sound with no build)? Which one, and did it feel earned or cheap?

### Stage 5. Depths 2 and 3: new strata, new errors `[8:00 to about 20:00]`

Depth 2 is Pools or Garage, depth 3 another of Pools, Garage or Offices. You will meet a hunter: Echo in Pools, Still in Garage, Flicker in Offices (the native of each stratum), plus Static. If you die here, that is the main data.

**Each stratum.**
- At the arrival: what told you in the first five seconds that this is a different place? Which stratum had the strongest identity, which the weakest?
- Was the exit easy to find (the exit line `UNKNOWN`, then its status)? What did the lock ask of you (Open, Powered, Keyed, Cycled), and was it clear?
- In the darker strata (Offices, Server): was the dark a fear or a nuisance?

**First contact (do not read this section before it happens).** Whatever error touches you first:
- Did you understand **what** touched you and **why**? Say it in a sentence before you read the summary.
- Was there a telegraph before it landed? What was it, and when did you first notice it? If you did not notice it, say what it would have taken.
- Was it **fair**: could you have avoided it with what you knew? What would you do differently?
- The cost (a fixed hit, a stun, a push): did it feel right? What did you do in the 20 seconds after (the error retreats, `Satiated`)?

**For each error you meet, one line each in the notes** (use the table in `notes_cp-12.md`): where you met it, how you first sensed it (the tell, with distance), whether the rule was readable, which counter you tried, whether it worked, and whether the contact (if any) was fair.

Reference, for after you have tried to work it out yourself:
| Error | Rule | Counter | Tell |
|---|---|---|---|
| Static | A drifting field; drains inside | Go around, wait, noclip past, a burning flare | Hum through walls; visible distortion |
| Still | Moves only when you are not observing it | Keep it in a lit view and back away; break line of sight and hide; noclip | The room goes quiet; a matte-black column |
| Echo | Follows your footsteps, late | Stop; crouch-walk; throw a noise elsewhere | Your own footsteps behind you; a shimmer at 4 m |
| Flicker | Lives in lit fixtures; lunges if you stand in its light | Darkness; chemical light is immune | Fixtures stutter, 8 to 20 Hz |
| Null | Walks straight at you through everything | Route around it by the unrender view; soft walls | The grid tone; walls going to lines |

**Counters in conflict.** If two errors were ever on the same level: did their counters pull against each other (Still wants light on it, Flicker wants it off)? What did you choose?

**Death and the summary (if it happens; it will).**
- Dissolving: what did the screen do, and did it read as "I ran out of reality" or as "I was killed"?
- The summary: did the top line (`DISSOLVED BY <ERROR> · DEPTH <n> · <STRATUM>`) explain your death accurately? Did you agree?
- The score and the unlocks: did you care? Did you want to know what the score meant?
- How long between dying and being in control of a new Descent? Did DESCEND AGAIN feel like a reflex or a hesitation?
- How many minutes did this Descent take? (The design: 5 to 10 for an early death.)

### Stage 6. The Substrate: the crescendo `[at minute 20, or when you arrive]`

If you are alive at depth 5 or 6 in a real Descent, play it out here. Otherwise, at minute 20 launch the level directly (this has no cabin, no HUD; press F3 for Coherence):

```
$GODOT_BIN --path game -- --seed 1 --depth 6 --stratum substrate
```

(Seeds 2, 12 and 17 are the ones the simulated players found hardest; try one later with `--seed 2`.)

Null is dormant for about 30 seconds, then walks straight at you through everything at 2.4 m/s, slower than you walk (3.2). Inside 2 m of it your Coherence falls 10 a second.

Notice:
- The first ten seconds: what does the Substrate look like to you (wireframe, magenta and black, bare lights)? Does it read as unfinished on purpose, or as a bug? What was your reaction?
- The 30-second calm: what did you do with it? Were you afraid of the quiet?
- The wake: how did you know Null was awake? Did the moment have a shape (a tone rising, a change in the image)? Did anything pop or jump in a way that looked wrong?
- The unrender: when walls turned to lines on black around you, did you understand it as "Null is near"? Did it show you something useful (the layout through the walls), or only scare you?
- **Did you route around Null, or walk through it?** What did you decide, and when? Did you try soft walls? Did you walk straight at the Threshold?
- If you entered its core: what did it feel like (the screen black, the grid tone, the drain)? How long were you in it, and did you know how much time you had?
- The crescendo: was there a build from the calm to the pursuit to the door? Where was the peak? Did the end feel like an escape?
- Hard but winnable, or unfair, or too easy? Write how many attempts it took to cross, or how many times you died, and where. Record your Coherence at the moment you met Null.

If you reach the Threshold in a real Descent, go straight on to Stage 7 (the ending) and keep the run.

### Stage 7. The ending `[about 27:00]`

If your Descent crossed the Threshold, you have just seen it: continue from the white cut. If not, launch the bench (it saves nothing to your profile):

```
$GODOT_BIN --path game res://scenes/debug/ending_bench.tscn
```

Notice:
- The white cut and the sunlit corridor: what did you feel first? Was the quiet a relief? Did the picture "restoring" read as Coherence coming back?
- Walk toward the window: `DEPTH 0`, then the title card `NOCLIP`. Did it land? Did it feel like an answer, or like a menu?
- The credits: can you read every line (the line that an AI made the game, the engine, the typeface)? Did the corridor behind them help or get in the way?
- What do you want to do now: go back down, stop, tell somebody?
- Did the game "wink" anywhere? (It should not, beyond the one line of the credits.)

If you reached it for real, you also have the run summary with `THRESHOLD CROSSED · DEPTH 06`; write what you thought of the score line and what unlocked (Endless, Cycle 2).

### Stage 8. The run summary, once more `[any Descent's end]`

In the notes, one line: did the summary tell you what you wanted to know? What do you want it to say that it does not?

---

## Rating sheet (5 minutes, straight after Stage 7)

Circle one number from 1 (no) to 5 (yes) in `notes_cp-12.md`, then one line of free text.

| # | Scale | Free text |
|---|---|---|
| R1 | I felt dread, not just surprise. | the moment that was the most dreadful |
| R2 | Every time I was hurt, I could say why and what I could have done. | the unfair moment, if any |
| R3 | The world looked less real as I lost Coherence, and I noticed. | when it first registered |
| R4 | Noclip felt like a choice with a price, and I was tempted. | what made it hard to choose |
| R5 | The game gave me room to recover after trouble. | the best and the worst pacing moment |
| R6 | Every action I took answered me (sound, picture, motion). | the weakest action |
| R7 | The places felt like ordinary places, a little wrong. | the strongest place, the weakest |
| R8 | I understood the HUD without help. | what I had to guess |
| R9 | The Substrate and Null were hard but beatable. | what I would change |
| R10 | I would start another Descent right now. | why or why not |

Then three sentences, free: the one moment to keep; the one that felt worst; what the game is, in your words, to someone who has not played it.

---

## Optional parts

Each is independent. The time estimates are for the whole part.

### Part L. Listen check (about 25 minutes)

`docs/qa/listen_check.md` (L1 to L14) is the audio list: your own steps, Echo's late steps, occlusion, the tells against the room, contact, noclip, Null at four distances, music, six places with eyes closed, the quiet floor, loudness, the Threshold, speakers and the audio guard on your machine. Use closed headphones for L1 to L12 and speakers for L13. Tick PASS / FAIL there and copy the three lines that matter most into the Part L heading of the notes. Its launch lines are the Board, the Arena and the Level line above, and the Guard line that file gives.

### Part P. Performance and F3 readings (about 20 minutes)

`docs/qa/perf_checklist.md` (P1 to P8) is the performance list. Use the editor binary, 1920 x 1080, other programs closed. Press F3 in a level and read FPS, FRAME, GPU, RENDER CPU, DRAW CALLS, VRAM and the LIGHTS line. Two launch lines carry the numbers:

```
$GODOT_BIN --path game --resolution 1920x1080 res://scenes/debug/perf_bench.tscn -- --stratum server --seconds 30 --fps 0 --out build/perf/gpu_server.json
$GODOT_BIN --path game --resolution 1920x1080 res://scenes/debug/perf_bench.tscn -- --stratum garage --seconds 30 --fps 0 --out build/perf/gpu_garage.json
```

Hand back `build/perf/gpu_server.json` and `gpu_garage.json` together with the filled table of that file. In the notes also write, from play and not from numbers: did you ever feel a stutter, and what was happening (a level appearing, a contact, Flicker's flash, a door)?

### Part A. Accessibility pass (about 6 minutes; any save)

Not a pass or fail test of each option (`docs/qa/human_check_M2.md` Part E does that). One question for each: could you play comfortably with it, and did it change the fear? Open SETTINGS, ACCESSIBILITY, and one at a time, with the Level line `--seed 3 --depth 2 --stratum pools` for a place to stand:
- **Reduce visual noise** and **Reduce flashing**: spend Coherence below 40 by noclipping walls. Is the world still frightening with the grain capped? Does the flash feel gentler, and is anything lost?
- **Captions** (SOUND CUE CAPTIONS) with **Text size** 1.4: do the lines (`[hum, left, far]`, `[tear]`) tell you something your ears did not? Do they cover the view?
- **HUD** minimal and off; **Crosshair** modes; **Hold-to-press**; the **colour-blind accent**; **UI scale** 1.5 at a small window. Anything unreadable?
- **Flicker intensity** 0.3: still a threat?
Write one line per option you tried, and one line on whether you would play with any of them on.

### Part G. The GPU-only visual items (about 10 minutes)

The machines rendered these on a CPU renderer; only a GPU on a real display settles them. For each, write what you see, in your own words, and whether it is better, as intended, or worse than you expected. Screenshots of anything wrong are welcome (use your system screenshot tool).

- **Bloom.** `-- --seed 1 --depth 1 --stratum halls`: look at the fluorescent tubes from the end of the corridor. Then the Substrate's boundary lines and the warm strip of the Threshold (`--seed 1 --depth 6 --stratum substrate`). Soft glow, or a blown-out haze?
- **AgX.** Same Halls corridor, then the Garage (`--seed 1 --depth 3 --stratum garage`) and the Server (`--seed 7 --depth 5 --stratum server`). Are the yellow, amber and the blue LEDs the colours the design names? Is any area crushed to black or washed?
- **The checker colour.** In the Substrate: the placeholder surfaces. Hot magenta and black, or pink-lavender (the CPU renderer showed #D070D0)? Does it read as a deliberate "unfinished"?
- **The unrender halo at 1080p.** When Null is within 12 m: the edge between the drawn world and the lines on black. Clean, or does it shimmer, crawl or leave a halo?
- **The Null wake pop.** Watch the moment Null wakes after the calm. Does anything visibly pop, appear or move in a way that gives the repositioning away?
- **Credits readability.** The ending bench, the credits lines over the corridor: legible at 1080p, in your seat?
- **T5 and T6 (the machines judged these by eye on CPU frames, `docs/qa/visual_targets_by_eye.md`).** T5: in any Descent, pause in a corridor of each stratum you reach and ask yourself whether you could name the stratum from that one picture alone, without the HUD. T6: with the flashlight off, from about 15 m (some twenty walking steps), could you tell Static (a grey grainy veil), Still (a black column), Flicker (a stuttering light group) apart, and was any of them invisible?
- **Also, if you have a minute:** Pools' rising bubbles under TAA; the Substrate's 1 px drifting pixels (do they shimmer or vanish?); the title's corridor (smooth, or heavy?); the burning flare (Items bench, `J` for items, Right Mouse to strike: a flame, or a blocky white mass?); the Cycled exit's display in the Server legible.

---

## Part T. Targeted runs for the cp-12 questions (optional, 15 to 20 minutes; mid-game fixture save)

The M3.4 tuning left five questions for human runs (`docs/checkpoints.md`, `docs/qa/descent_sim.md`). The core 30 minutes answers the first three; these runs answer the rest. Use the fixture save so everything is unlocked. For every run write the depth, how it ended, and the Coherence at the start and the end.

- **Still evasion (the sims saw 3 in 279 levels).** `-- --seed 1 --depth 2 --stratum garage`, then `--seed 2 --depth 2 --stratum garage`, then `-- --seed 7 --depth 5 --stratum server`. Find Still. Try each counter in turn and note whether the chase ended: (a) flashlight on, Still in view in the light, back away; (b) break line of sight and hide (under a car, a locker, a rack gap); (c) noclip through a wall. Which worked every time, which sometimes, which never? Did you ever see it lose you (an evasion)?
- **The Offices light dilemma.** `-- --seed 3 --depth 4 --stratum offices`. Some fixture groups are dark until the breaker. Did the choice between light (breaker, flashlight; Still sees you) and dark (Flicker cannot) read as a choice? In a direct launch the belt is empty, so the Glowstick half only exists in a real Descent: if one of your fixture-save Descents reaches Offices holding a Glowstick, use it and write what it solved.
- **Noclip budget.** In any real Descent: count your walls and your drops, and the Coherence on arrival at each depth (the Landing adds up to 20, never past 100). Was it more or less than you expected? (The sims spent almost none.) Note the Coherence at depth 6 arrival.
- **Null again.** `--seed 2`, `--seed 12` and `--seed 17` at `--depth 6 --stratum substrate`. Which route did you take, and did it differ from seed 1?
- **Decision rule for the Landing gain (pre-agreed, R20; M3 review S1).** If the human runs arrive at depths 3 to 6 averaging 90 or more Coherence (with fewer than 2 noclips a level), cp-13 halves the Landing gain from 20 to 10 (05 §4, 06 §9, `tuning.gd` and `test_tuning.gd` together, CHANGELOG with the data). If they arrive below 70, it stays 20. Between 70 and 90 the orchestrator decides from the notes. This is why the arrival Coherence at every depth matters.
- **Telemetry.** Play one Descent with `$GODOT_BIN --path game -- --telemetry` and hand back the CSVs in `<user folder>/run_telemetry/`.

---

## Reporting back

1. Copy nothing: **fill in `docs/qa/notes_cp-12.md` in place** (it is the template; every heading corresponds to a stage above). Short answers. Write `could not` where a thing never happened.
2. Hand it back by either (a) committing the file (and `build/perf/*.json` if you did Part P) on a branch and pushing it, or (b) pasting the file into the conversation. Add any screenshots, and the CSVs of Part T if you made them.
3. For a defect, always write the launch line or the seed (F3 shows it in an editor run), the depth, and one sentence. A taste complaint needs no seed.
4. Things the checkpoint note already lists as not verifiable without a GPU or a human (frame times, mouse feel, audio by ear, the unrender halo, the checker under AgX, bloom) are exactly what Parts L, P and G are for; if you skipped them, say so and the orchestrator will not treat them as confirmed.
