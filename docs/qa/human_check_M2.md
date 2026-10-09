# Human check: M2 (about 40 minutes, needs a GPU)

M2 added five strata, five errors, six items, four locks, the menus, the accessibility options and the ending. The machine checks run by themselves: more than 1,200 unit, level and sim tests, the error arena driven key by key, the stratum sweeps. What a machine cannot judge is whether it looks right, sounds right and is clear. This list is for that.

**How to use it.** Do the steps in order. For each one do the thing, compare with **Expect**, and tick `PASS` or `FAIL`. If a step fails, write one line (what you saw, and the launch line or seed if the step has one) in the `Note` space and keep going; do not stop to debug. If you cannot do a step (the thing never showed up), tick neither and write `could not`. A pass means the thing is there and works. Taste (is it scary, is it too long) goes in the feel questions at the end.

**What you need**
- A computer with a Vulkan graphics card, a keyboard, a mouse. Headphones for the audio steps.
- The Godot editor binary (`tools/godot/fetch.sh` downloads it; it prints `export GODOT_BIN=...`), run from the repository root. Every launch line below is a command for `$GODOT_BIN`. An exported build runs the real game (Parts A and B) but not the bench scenes (Parts C to G).
- A clean profile for Part A, and a mid-game profile for the rest. The user directory is `~/.local/share/NOCLIP/` on Linux and `%APPDATA%\NOCLIP\` on Windows. The mid-game profile is the file `docs/qa/fixtures/meta_m2_mid_save.json` copied there as `meta.json`: it unlocks the glowstick, radio, flare, fuse, the three loadouts and Daily Descent, with 14 notes found (12 of them unread) and the hints retired. The ending is still to be earned.

**Controls**

| | |
|---|---|
| Move | W A S D |
| Look | Mouse |
| Sprint / Crouch | hold Left Shift / hold Left Ctrl |
| Interact | E (hold where a prompt says HOLD) |
| Flashlight / Crank | F / hold R |
| Noclip | hold Left Mouse Button |
| Use item / pick item | Right Mouse Button / 1 to 4 or wheel |
| Status | Tab |
| Pause | Esc |
| Debug overlay (editor and debug builds) | F3 |

**Launch lines** (used below)

| Name | Line |
|---|---|
| Game | `$GODOT_BIN --path game` |
| Arena | `$GODOT_BIN --path game res://scenes/debug/error_arena.tscn -- --stratum halls` (also `pools`, `offices`, `substrate`) |
| Items bench | `$GODOT_BIN --path game res://scenes/debug/items_bench.tscn` |
| Exits bench | `$GODOT_BIN --path game res://scenes/debug/exits_bench.tscn` |
| Ending | `$GODOT_BIN --path game res://scenes/debug/ending_bench.tscn` (add `-- --variant` for the variant) |
| Stratum | `$GODOT_BIN --path game -- --stratum <id> --depth <n> --seed <n>` |

Direct launches (Stratum) drop you into a built level with the Director running but no HUD, no run, no cabin: the exit will not take you down. They are for looking at the level.

---

## Part A. Title, menus, settings (about 8 minutes; clean profile)

Start with no `meta.json` and no `settings.cfg` in the user directory.

**A1. The title.** Launch the Game.
Expect: a black screen, the word `rendering` typing itself with a block cursor, a shutter, then the title: NOCLIP, a menu with `DESCEND`, `DAILY DESCENT` (dimmed), `ARCHIVE`, `SETTINGS`, `QUIT`, and the line `v1.0.0 · MADE BY AN AI · SEED OF THE DAY <date>`. Behind the menu, a live yellow Halls corridor (seen through a 55% black backing) drifts past slowly as if walked at a stroll, with faint grain; every 25 to 40 s a 200 ms ripple of white grid lines on black runs down the corridor ahead and is gone. Turn on ACCESSIBILITY > REDUCE FLASHING and wait a minute: the ripple never comes. `ENDLESS` is not listed. Up and Down move the `▸` marker with a tick sound.
[ ] PASS  [ ] FAIL  Note: ______________________

**A2. The detail column.** Move onto each item and read the column beside it.
Expect: DESCEND shows BEST DEPTH 0, RUNS 0, WINS 0 and LAST CAUSE OF DEATH with a dash (a new save); no loadout cards (only one loadout is unlocked). DAILY DESCENT cannot be chosen (Enter does nothing, the line stays dim). ARCHIVE and SETTINGS show their one-line descriptions.
[ ] PASS  [ ] FAIL  Note: ______________________

**A3. Settings tabs.** Open SETTINGS. Go through the six tabs: DISPLAY, GRAPHICS, AUDIO, CONTROLS, ACCESSIBILITY, GAMEPLAY (Left and Right or click).
Expect: each tab lists its options with a one-line description under the selected row; `RESET TAB TO DEFAULTS` at the bottom of each; Esc goes back one page; the whole screen is readable at your resolution. Under the six tabs, `LICENSES` (title only, 16 §6) opens a page: ENGINE prints `Godot Engine. MIT license.` and the MIT text in full, COMPONENTS 1/4 to 4/4 list the engine's components as `name ………… license` rows, then TYPEFACE and SOUND; nothing scrolls.
[ ] PASS  [ ] FAIL  Note: ______________________

**A4. Display options apply live.** On DISPLAY drag FIELD OF VIEW from 90 to 110 and back, then BRIGHTNESS; read the test strip text.
Expect: the title's live corridor widens and narrows its field of view at once, with no stutter; the darkest bar of the brightness strip is barely visible at the default. Change WINDOW MODE to WINDOWED: a `KEEP` / `REVERT` prompt appears with `REVERTING IN 10`; choose REVERT and the old mode returns; choose it again and KEEP, and it stays.
[ ] PASS  [ ] FAIL  Note: ______________________

**A5. Graphics presets.** On GRAPHICS set PRESET to LOW, then HIGH, then change one option (SHADOW QUALITY).
Expect: the other options jump to the preset's values; the image visibly gets simpler on LOW (fewer shadows, no fog shafts) and richer on HIGH; changing one option turns PRESET into CUSTOM. Set it back to MEDIUM.
[ ] PASS  [ ] FAIL  Note: ______________________

**A6. Audio.** On AUDIO drag MASTER, then MUSIC, then EFFECTS.
Expect: each slider changes its bus at once; the title drone is the music; dragging MASTER to zero silences everything, UI ticks included, and back up restores it.
[ ] PASS  [ ] FAIL  Note: ______________________

**A7. Rebinding.** On CONTROLS select FLASHLIGHT. Press Enter, then `G`.
Expect: the row shows `PRESS A KEY` while waiting, then `G`. Rebind INTERACT to `G` too: the two actions swap (FLASHLIGHT gets E back) and the row that lost the key flashes. Press Enter on a row, then Esc: nothing changes. Press Enter, then Backspace: the slot clears. Rebind a mouse button (USE ITEM to the Middle button) and it takes. Then RESET TAB TO DEFAULTS restores the defaults in the list.
[ ] PASS  [ ] FAIL  Note: ______________________

**A8. The mouse test.** Still on CONTROLS: type a MOUSE SENSITIVITY value in the number field, drag the slider, press TEST and turn the mouse.
Expect: the field and the slider stay in step; TEST shows a turning mark that follows your hand at the chosen speed.
[ ] PASS  [ ] FAIL  Note: ______________________

**A9. Rebinds survive a restart.** Rebind FLASHLIGHT to `G` (and INTERACT back to `E`), quit the game from the title (QUIT), launch it again, open CONTROLS.
Expect: FLASHLIGHT still `G`; every other setting you changed in A4 to A6 is still changed.
[ ] PASS  [ ] FAIL  Note: ______________________

Reset FLASHLIGHT to `F` before going on. Quit the game, then copy the mid-game profile into place (see "What you need").

---

## Part B. A real Descent (about 12 minutes; mid-game profile)

**B1. The title with a mid-game save.** Launch the Game.
Expect: DAILY DESCENT is now selectable; the DESCEND column shows BEST DEPTH 5, RUNS 12 and LOADOUT cards you can step through with Left and Right (FALLER, CARTOGRAPHER, LIGHTBEARER, DIVER; text under each says what it does). ARCHIVE is listed.
[ ] PASS  [ ] FAIL  Note: ______________________

**B2. The Archive.** Open ARCHIVE.
Expect: four sections (NOTES, ERRORS, STATISTICS, UNLOCKS). NOTES is a grid of 36 slots with 14 found (the rest show a locked mark); twelve of the found ones blink for a moment as unread and stop after you have looked (leave and reopen: they no longer blink); Enter on a found note opens it with its text. ERRORS lists each error with its encounter count and, for the ones you hold a codex for, its counter line. STATISTICS shows RUNS 12, BEST DEPTH 5, BEST SCORE 4,210. UNLOCKS lists what you hold. Esc returns.
[ ] PASS  [ ] FAIL  Note: ______________________

**B3. First-run guidance off.** Open SETTINGS, ACCESSIBILITY, set HINTS to ON (the profile has them retired), and go back.
Expect: nothing happens yet; hints will print in the first seconds of the next Descent.
[ ] PASS  [ ] FAIL  Note: ______________________

**B4. Descend, depth 1.** Choose the FALLER loadout and DESCEND.
Expect: a short glitch cut, then Halls: yellow striped wallpaper, brown carpet, fluorescent tubes on the ceiling, a low electrical hum. At the bottom a hint line prints `[W A S D] MOVE · [MOUSE] LOOK` and goes when you have walked 3 m; a few seconds later `[F] FLASHLIGHT`. Top left, the Coherence readout (a bar and a number); top right `DEPTH 01`, `HALLS` and an exit line; bottom right the belt.
[ ] PASS  [ ] FAIL  Note: ______________________

**B5. Flashlight and crank.** Press F. Hold R.
Expect: a relay click and a beam; a battery percent bottom left falling slowly; with R held a ratchet with a rising whine, the percent climbing, a bright click at the top. Hints `[HOLD R] CRANK` appears if the percent is low.
[ ] PASS  [ ] FAIL  Note: ______________________

**B6. Captions.** Open SETTINGS from the pause menu (Esc, then SETTINGS), ACCESSIBILITY, set SOUND CUE CAPTIONS to ON, back out, and make a noise: finish a noclip through a wall, or throw the breaker (B9).
Expect: small text lines above the prompt area such as `[tear]` or `[breaker thrown]` (sounds from a direction add it and `near` or `far`, for example `[hum, left, far]` near a Static); they fade after a few seconds; at most a few stack at once; Text size 1.4 (same tab) makes them larger.
[ ] PASS  [ ] FAIL  Note: ______________________

**B7. Noclip, and why it refuses.** Hold the left mouse button on an ordinary wall until it finishes; then hold it facing the outer edge of the level.
Expect: a ring filling and a rising tone, a thump and tearing sound at the end, you on the other side, Coherence down by 10 and the picture a little greyer; on the outer edge a dashed ring and a word under the crosshair (`SOLID`, `NO SPACE`, `TOO THIN` or `TOO FAR`). On the floor (look straight down, hold) you drop a level for 30 Coherence: do this only if you want to skip to depth 2; the cabin step below happens either way.
[ ] PASS  [ ] FAIL  Note: ______________________

**B8. A note, and an item.** Find a paper note on the floor (a glint of white) and press E; find an item (a small glowing shape) and press E.
Expect: the note sheet slides in with the text typing, a paper sound; closing it returns you to the game; the item flies to the belt with a tick and the belt slot pulses. `1` to `4` or the wheel select slots, and the held item appears bottom right.
[ ] PASS  [ ] FAIL  Note: ______________________

**B9. The breaker (the Powered lock).** Depth 1 is Powered about six times in ten (this profile is not a first Descent, so it can be OPEN: if the exit line reads `EXIT: OPEN`, press DESCEND AGAIN after the summary until it reads `EXIT: POWERED`, or do F5 and F6 instead). Find the grey breaker box on a wall and hold E on it.
Expect: the prompt `[HOLD E] FLIP BREAKER`; the lever drops with a heavy clunk and a small camera shake; a wave of light runs through the corridors from the box toward the exit, tube by tube, with the caption `[lights waking]` if captions are on; the exit line turns to `EXIT: OPEN`; the exit's lamp lights. If you have the Hold-to-press option on, a single press does it.
[ ] PASS  [ ] FAIL  Note: ______________________

**B10. The exit, the cabin and the next level.** Walk into the open exit.
Expect: a 0.6 s entering move, then a small metal cabin that hums and shudders; a panel offering two items (`[1]` and `[2]`) and `COHERENCE +20` on arrival; you pick one with 1, 2 or a click, the cabin door opens and the next stratum is there with the item on your belt and Coherence higher.
[ ] PASS  [ ] FAIL  Note: ______________________

**B11. Depth 2.** You are in Pools or Garage.
Expect: either teal tile with sunken water basins (Pools), or concrete with amber lamps and parked cars (Garage); the depth line reads `DEPTH 02` and the stratum name; the exit line reads UNKNOWN until you see the exit, then its real status (OPEN, POWERED or KEYED).
[ ] PASS  [ ] FAIL  Note: ______________________

**B12. Dying and the summary.** Press Esc, choose ABANDON DESCENT, confirm. (Or let an error take you.)
Expect: the pause menu lists RESUME, SETTINGS, ABANDON DESCENT, QUIT TO TITLE and says the run ends but depth and notes are kept; confirming plays the picture breaking into squares; the summary prints the top line `DESCENT ABANDONED` (or `DISSOLVED BY <ERROR>`), DEPTH, TIME, COHERENCE SPENT, WALLS PASSED, FLOORS DROPPED, NOTES FOUND, ERRORS EVADED, SCORE and BEST, and the buttons DESCEND AGAIN, ARCHIVE, TITLE. DESCEND AGAIN starts a new Descent in a few seconds.
[ ] PASS  [ ] FAIL  Note: ______________________

**B13. Loadouts and Daily.** From the title choose the DIVER card and DESCEND. Then quit to title and choose DAILY DESCENT; abandon it; return to the title.
Expect: Diver starts at `DEPTH 03` with Coherence 70 and two Polaroids on the belt. Daily Descent starts at depth 1 with the Faller kit; after abandoning, the Daily item shows `SCORE <n> · DEPTH <n>` for that attempt and cannot be chosen again; its detail column says today's attempt is spent. The seed of the day on the title is the same string as before.
[ ] PASS  [ ] FAIL  Note: ______________________

---

## Part C. The strata (about 8 minutes)

One minute each with the Stratum line. Walk about, look, listen. Press F3 for the seed line if you need to report one.

**C1. Halls.** `-- --stratum halls --depth 1 --seed 4`
Expect: yellow wallpaper in 0.6 m stripes with a faint print, brown carpet with paler wear lanes down the middle, white drop-ceiling tiles, a tube every 4 m with its soft glow on the ceiling, one tube in six buzzing slightly greener. Mustard haze in the distance. Props in rooms: vending machine, payphone, chair.
[ ] PASS  [ ] FAIL  Note: ______________________

**C2. Pools.** `-- --stratum pools --depth 2 --seed 3`
Expect: pale teal tile with grout lines, a high 6 m ceiling with square panels, sunken basins with moving water (shallow and deep), pool ladders, a lifeguard chair; wade into shallow water: you slow down, a splash; water drips make expanding rings. Teal fog, a faint reverb.
[ ] PASS  [ ] FAIL  Note: ______________________

**C3. Garage.** `-- --stratum garage --depth 3 --seed 1`
Expect: grey concrete with painted bay lines, amber sodium lamps on the pillars, parked cars of four colours with dark glass and wheels, two decks joined by ramps, a stairwell door as the exit, amber fog; the car bodies read above black.
[ ] PASS  [ ] FAIL  Note: ______________________

**C4. Offices.** `-- --stratum offices --depth 3 --seed 2`
Expect: pale grey panels, blue-grey carpet tile, fabric cubicle partitions, desks with monitors showing a dark blue screen with slow pale text, a water cooler, filing cabinets, some fixture groups dark; glass walls you can see through but not walk through.
[ ] PASS  [ ] FAIL  Note: ______________________

**C5. Server.** `-- --stratum server --depth 5 --seed 7`
Expect: near-black room, rows of racks with columns of tiny green, red and blue LEDs blinking at different rates, a faint blue glow from them, fan noise, cable trays overhead, cages, narrow aisles; the exit is a floor hatch.
[ ] PASS  [ ] FAIL  Note: ______________________

**C6. Substrate.** `-- --stratum substrate --depth 6 --seed 1`
Expect: wireframe, unlit geometry with magenta-and-black placeholder surfaces, bare studio lights, a pocket of finished room, a warm strip of light far off (the Threshold). After the calm window (about 30 s) a low tone rises: Null is awake. Within 12 m of it the walls draw as lines on black and you can see through them. Walking away from it works; being within 2 m of its core drains Coherence (about 12 a second) with a black screen and a grid.
[ ] PASS  [ ] FAIL  Note: ______________________

**C7. Cycle 2.** `-- --stratum halls --depth 7 --seed 1`
Expect: a Halls level that is the same palette but corrupted: the hue pulled toward the next stratum, a quarter of the tubes dead, thicker fog, a larger maze with more dead ends, some surfaces drawn as lines.
[ ] PASS  [ ] FAIL  Note: ______________________

---

## Part D. The five errors (about 7 minutes)

Launch the Arena. Five buttons (also keys `1` to `5`) spawn the errors at least 20 m away and out of view. `L` switches the fixtures off and on, `K` removes every error, `H` sends them away. The log under the buttons shows each one's state. Mouse capture: click in the window; Esc releases.

**D1. Static (button 1).** Press `1`, then walk toward where you hear a low hum.
Expect: the hum gets louder through walls and a patch of air looks like moving, refracting noise with no edge. Inside it: a rising noise band, grainy picture, a slight camera tremble, and Coherence falling by about 4 a second at the centre. Step out and it stops. It drifts slowly (about 0.6 m/s) and does not chase.
[ ] PASS  [ ] FAIL  Note: ______________________

**D2. Still (button 2).** Press `2`. Find the matte black column (about 2.6 m tall, a hole in the picture). With the flashlight on, look straight at it; look away; look back.
Expect: while you look at it in the light it never moves; looking away it closes the distance; after about 2 s of continuous look a thin white line flashes across it for a moment with a high blip every couple of seconds; the room goes quiet when it is near; closing a door between you breaks its line. In the dark with the flashlight off you cannot hold it (press `L` to kill the fixtures to try). Letting it touch you: a heavy hit, a shove, and a short loss of camera control.
[ ] PASS  [ ] FAIL  Note: ______________________

**D3. Echo (button 3).** Press `3`. Walk steadily, then stop.
Expect: after a few steps you hear your own footsteps a moment late behind you, on the surface you are walking on, and they keep your pace; within about 4 m a faint man-sized heat shimmer in the air. Stop moving: the footsteps catch up to about three steps behind you and stop. Crouch-walk (hold Ctrl) away: the steps fade, it loses you. Contact costs 25 Coherence.
[ ] PASS  [ ] FAIL  Note: ______________________

**D4. Flicker (button 4).** Press `4`: it appears in the lit group ahead of you.
Expect: the tubes of that group stutter at about 8 Hz (only Flicker makes lights flicker); stand under them and the stutter rises toward 20 Hz over about 2 s, then the whole group flashes white and you take 30 Coherence. Step into the dark (switch your flashlight off, stay out of the group's light) and it stops charging: that is the counter. Keep your flashlight on within 4 m of its lights for 1.5 s and the beam itself stutters (it has attached); switching it off sheds it. Reduce flashing (Part E) must turn the white flash into a soft fade.
[ ] PASS  [ ] FAIL  Note: ______________________

**D5. Null (button 5).** Press `5`.
Expect: at once a rising grid tone; within 12 m the world around you becomes lines on black; it walks straight at you at 2.4 m/s through walls, slower than you walk (3.2 m/s); inside 2 m your Coherence falls about 12 a second and the screen goes black with a grid; walking out of it works. The tone and the unrender go away when you press `K`.
[ ] PASS  [ ] FAIL  Note: ______________________

**D6. The same errors elsewhere.** Close the Arena and launch it again with `-- --stratum pools`, `-- --stratum offices` and `-- --stratum substrate`; press `3` in Pools, `4` in Offices, `5` in Substrate.
Expect: Echo's steps follow the surface it is on (and slow in water); Flicker's group is a troffer group in Offices; Null's unrender draws the Substrate's geometry as lines. None of them looks or sounds broken.
[ ] PASS  [ ] FAIL  Note: ______________________

---

## Part E. Accessibility (about 4 minutes)

Open SETTINGS, ACCESSIBILITY (from the title). Toggle each option, then look at the title or the Arena.

**E1. Reduce visual noise.** Turn it ON and spend Coherence (hold noclip on walls in the Arena until you are below 40).
Expect: the grain, colour split and scanline shimmer are capped at a low level; the greying and the dark corners at low Coherence stay.
[ ] PASS  [ ] FAIL  Note: ______________________

**E2. Reduce flashing.** Turn it ON, then let Flicker lunge (Arena `4`) or take a Static hit.
Expect: no two-frame white flashes: each becomes a soft 200 ms fade to 60% white; the title's unrender flicker stops. The ending's white cut (Part G) becomes a fade too.
[ ] PASS  [ ] FAIL  Note: ______________________

**E3. Flicker intensity.** Set it to 0.3 and spawn Flicker.
Expect: the stutter is a slow shallow pulse (about 2 Hz) that is still visible.
[ ] PASS  [ ] FAIL  Note: ______________________

**E4. Crosshair and HUD.** Cycle CROSSHAIR through OFF, DOT, DOT AND RING; HUD through FULL, MINIMAL, OFF.
Expect: the crosshair changes at once. In a Descent MINIMAL shows only Coherence, prompts and captions; OFF shows only the Coherence bar.
[ ] PASS  [ ] FAIL  Note: ______________________

**E5. Hints, text size, hold-to-press.** HINTS OFF: no hint lines in a new Descent. TEXT SIZE 1.4: notes and captions get bigger, nothing else does. HOLD-TO-PRESS ON: the breaker and leaving a hide spot become a single press; noclip stays a hold.
[ ] PASS  [ ] FAIL  Note: ______________________

**E6. Colour-blind safe accent.** Turn it ON.
Expect: the amber accent becomes a paler yellow with a thin outline on accent items; danger text gains a `!`, cold text a `~`.
[ ] PASS  [ ] FAIL  Note: ______________________

**E7. Gameplay tab.** Switch off SHOW DEPTH AND STRATUM and EXIT STATUS LINE in a Descent.
Expect: the top right lines vanish; switching them back on returns them.
[ ] PASS  [ ] FAIL  Note: ______________________

Put the options back to your preference.

---

## Part F. Items, hide spots, locks (about 6 minutes)

**F1. The items bench.** Launch the Items bench. Click to capture the mouse. Press `J` for a Polaroid, two glowsticks and chalk on the belt.
Expect: a room with one pickup of each kind on the floor (Polaroid, glowstick, flare, chalk, radio, fuse, keycard), a note, a wall for chalk, a vending machine, a payphone, a card reader, a breaker and each hide spot. Each pickup has a faint glow of its colour and bobs slowly.
[ ] PASS  [ ] FAIL  Note: ______________________

**F2. Each item.** Pick up and use each with the Right Mouse Button.
Expect: the Polaroid held up for about 1.2 s with a photo filling the lower view and a flash, Coherence +25 (press `K` first to drain 40); the glowstick thrown in an arc that lands about 8 m away with a thud and a green light for 90 s (hold the button 0.5 s to put it down at your feet instead); the flare struck, red light with a flicker for 40 s, thrown with a second press; chalk stamps an arrow on the aimed wall, in your facing direction, `L` clears them; the radio toggles with a hiss (in a real level it pings faster as you face the exit); the fuse is picked up (it shows on the belt as a fuse); the keycard shows a key glyph beside the depth label and takes no belt slot.
[ ] PASS  [ ] FAIL  Note: ______________________

**F3. The vending machine and payphone.** Press E on the vending machine, wait; press E on the payphone when it rings (if it never rings in the bench, tick `could not` for that half).
Expect: the machine whirs for a second with a noise, then an item sits in its tray you can pick up, once per machine; the payphone rings (a caption `[phone rings, ...]` with captions on) and `[E] ANSWER` silences it for two seconds of line hum with nothing said.
[ ] PASS  [ ] FAIL  Note: ______________________

**F4. The five hide spots.** Enter each: under the car, under the desk, the locker, the pump-room corner, the rack gap (`E` to hide, hold `E` to leave).
Expect: the camera slides in and down for the car and desk, a click and slits for the locker, a small window for the pump corner, a view along an aisle for the rack gap; your own breathing is audible; the HUD dims and the crosshair becomes an eye; the view turns only a limited angle; leaving takes a 0.6 s hold.
[ ] PASS  [ ] FAIL  Note: ______________________

**F5. Breaker and Fuse (Variant B).** On the bench breaker (if it has a socket): with no fuse it reads `FUSE MISSING` (dim); pick up the fuse from the floor and it reads `[E] INSERT FUSE`; insert (0.8 s), the exit powers.
[ ] PASS  [ ] FAIL  Note: ______________________

**F6. The exit prefabs and the locks.** Launch the Exits bench. Keys `1` to `5` pick the stratum (Halls elevator, Pools drain hatch, Garage stairwell door, Offices elevator, Server floor hatch), Left and Right step, `O` opens and seals.
Expect: each stratum has its own exit look and sound; opening moves the leaves with a mechanical sound and a green or lit frame; sealing closes them with a thud; the Keyed variants show a card reader beside the exit (`NO CARD` dim without a card, `SWIPE` with one, an accept beep); the Server's has a small display counting down: sealed about 70 s, a long tone 5 s before opening (you hear it through walls), open about 20 s.
[ ] PASS  [ ] FAIL  Note: ______________________

**F7. A Keyed level, for real.** `-- --stratum pools --depth 2 --seed 3` (the exit is Keyed).
Expect: a pulsing glowing keycard you can see from across the room; pick it up (no belt slot); at the reader `[E] SWIPE` and an accept beep, and the exit lights as open. (Direct launches have no HUD or run, so the key glyph and the exit line show only in a real Descent: keep an eye out for them at depth 2 and 3. If the reader says NO CARD after you took the card, note the launch line.)
[ ] PASS  [ ] FAIL  Note: ______________________

---

## Part G. The ending (about 4 minutes)

**G1. The ending.** Launch the Ending (`ending_bench.tscn`, no flags). It plays the end of a won Descent for you and saves nothing to your profile.
Expect, in order: a hard cut to white for 1.2 s with one low tone (a soft fade with Reduce flashing); a fade in to a sunlit corridor: clean white walls, warm daylight through a window at the far end, real shadows from the window frame on the carpet, no HUD; the picture re-colours as your Coherence is restored: grain and grey fall away over 6 s; you can walk; the tubes are dark and there is no electrical hum. Under the window one soft shimmer in the wall.
[ ] PASS  [ ] FAIL  Note: ______________________

**G2. The card and the credits.** Walk toward the window.
Expect: within about 4 m of the wall, small text `DEPTH 0`, then a console title card `NOCLIP` typing itself; then the credits roll over the corridor with no panel behind them, each line on its own thin dark backing: the line that an AI (Claude, Anthropic) made the game, `Godot Engine. MIT license.`, the typeface and its copyright, the sound line, the LICENSES.txt line; the corridor stays visible and the text stays readable over the daylight; the last line holds, centred; then the Run Summary with `THRESHOLD CROSSED · DEPTH 06`, the unlock list naming `ENDLESS AND CYCLE 2`, and the buttons.
[ ] PASS  [ ] FAIL  Note: ______________________

**G3. The variant.** Launch the Ending with `-- --variant`.
Expect: the same corridor, but the title menu is printed on the far wall beside the window: `▸ DESCEND`, DAILY DESCENT, ARCHIVE, SETTINGS, QUIT (and ENDLESS, now that the Threshold is crossed); looking at DESCEND shows the prompt `DESCEND`; pressing E starts the next Descent without going through the title.
[ ] PASS  [ ] FAIL  Note: ______________________

---

## Feel questions (one line each)

1. Which stratum looked best, and which looked the weakest?
2. Which error was the most frightening, and which was only irritating?
3. Did the hints and the captions help or get in the way?
4. Was there any menu step where you did not know what to do next?
5. The one moment you most want to keep, and the one that felt worst.

## Summary

| Part | Steps | Pass | Fail | Could not |
|---|---|---|---|---|
| A Title, menus, settings | 9 | | | |
| B A real Descent | 13 | | | |
| C Strata | 7 | | | |
| D Errors | 6 | | | |
| E Accessibility | 7 | | | |
| F Items, hide spots, locks | 7 | | | |
| G Ending | 3 | | | |

Put this file with your ticks and notes next to the build, or paste it into the conversation. Failures with a launch line are reproducible from it; a failure from a real Descent needs the seed from the title or F3 line and the depth.
