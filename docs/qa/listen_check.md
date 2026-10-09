# Listen check (cp-12, M3.3)

The machine checks cover the numbers: every recipe renders to its loudness target (`tools/audio/synth.py --verify`), the mix rules of 03 §6 hold on the rendered files (`tools/audio/measure.py`), the Errors bus is kept under -6 dBFS at play time, occlusion muffles and opens on the 0.2 s pass, and every 04 §10 caption reaches the caption stack (`game/tests/unit/test_audio_mix_pass.gd`). None of that says whether it sounds right. This list is for ears. The cp-12 play script refers to it as **Part L**.

**How to use it.** Same rules as the other human checks: do the steps in order, tick `PASS` or `FAIL`, write one line in `Note` for a fail, `could not` when the thing never showed up. Taste goes in the questions at the end.

**What you need.** Closed headphones for L1 to L12, then laptop or desk speakers for L13. Master volume in the game at its default (80); set your system volume once on L1 so a footstep is comfortable, then leave it alone. The editor binary (`$GODOT_BIN`) from the repository root.

**Launch lines**

| Name | Line |
|---|---|
| Board | `$GODOT_BIN --path game res://scenes/debug/audio_board.tscn` |
| Arena | `$GODOT_BIN --path game res://scenes/debug/error_arena.tscn -- --stratum halls` (also `pools`, `substrate`) |
| Stratum | `$GODOT_BIN --path game -- --stratum <id> --depth <n> --seed <n>` |
| Guard | `$GODOT_BIN --path game --script tests/stress/audio_guard_window.gd -- --seconds 30` |

The Board lists every sound by bus with a button (loops are toggles). The top row holds the stratum picker (reverb and room tone), the emitter's distance (`EMITTER M`) and bearing, `ECHO PAIR`, `WALL`, and the line `PEAK DB` with each bus's live peak.

---

**L1. Your own steps.** Board. Pick each stratum in turn (HALLS, POOLS, GARAGE, OFFICES, SERVER, SUBSTRATE) and press its footstep (`foot_carpet`, `foot_tile`, `foot_concrete`, `foot_carpet`, `foot_raised_floor`, `foot_substrate`) a few times with the room tone on.
Expect: every step is clearly heard over the room tone (03 §6 rule 1); carpet soft and dull, tile a hard ceramic tick (not a beep), concrete dry, raised floor with a hollow knock under it, the Substrate step synthetic. `foot_water` is louder than the others on purpose.
`PASS / FAIL` Note:

**L2. Echo's steps.** Board, Halls, `EMITTER M` 3, bearing 150 (behind right). Press `ECHO PAIR` several times; then at 8 m; then at 1 m.
Expect: your step under you, then 0.8 s later the same step from behind right, a little quieter and a little roomier (the 20 ms extra reverb), clearly the same sound and clearly not yours. At 1 m it is not louder than your own step and does not crunch or clip (the Errors ceiling). Repeat in POOLS and SUBSTRATE: the copy follows the surface.
`PASS / FAIL` Note:

**L3. Occlusion.** Board, Halls, emitter 6 m ahead. Toggle `radio_static` on, then `WALL` on and off a few times. Do the same with `flicker_stutter`, then press `door_open` with the wall on and off.
Expect: with the wall the sound turns duller and quieter (about half as loud, highs gone) within a fraction of a second, without a click; off, it opens again. It never disappears. Now `static_hum` with the wall on and off: no change (Static is heard through walls). A footstep (`foot_carpet` at the emitter) is not muffled by the wall (only Errors and Interact sounds are).
`PASS / FAIL` Note:

**L4. The tells against the room.** Board, Halls, room tone playing. Toggle `static_hum` at 40 m, 20 m, 10 m, 3 m; `INSIDE STATIC` then `OUTSIDE STATIC`. Then `flicker_stutter` and `flicker_stutter_fast` together, moving `LOOP PITCH`; `flicker_spark`; `flicker_lunge` then `LUNGE SILENCE`. Then `STILL 5 M` and `STILL GONE`.
Expect: Static's hum is faint but findable at 40 m and grows steadily; inside, the noise bed rises. Flicker's stutter reads as a sick fluorescent tube, the fast one more urgent. After the lunge flash, everything (room tone, fixtures, drone) is gone for 1.5 s and comes back. With Still near, the room drops noticeably (quieter, not silent); gone, it returns. None of the tells is louder than your own footstep at 3 m.
`PASS / FAIL` Note:

**L5. Contact.** Arena (Halls). Let Echo catch you (walk, stop, walk while it follows), then let Flicker lunge at you.
Expect: a heavy bite: a tear, a sub thump and a decaying noise band. It is the loudest thing in the game but does not distort, and it does not sound doubled or flanged (Echo and Flicker play it on Errors while the player plays it too). `PEAK DB` on the Board for the same sound (`error_contact_hit`) stays under -1 on MASTER.
`PASS / FAIL` Note:

**L6. Noclip.** Stratum (Halls). Noclip through a wall a few times.
Expect: the rising charge, then a sub thump, a digital tear and a short hole of silence at the freeze; the rest of the world dips for a moment (the 8 dB duck) without an audible pump when it comes back; your own breath and heartbeat do not dip.
`PASS / FAIL` Note:

**L7. Null.** Board: `NULL AT EMITTER` at 60, 20, 5 and 1.5 m; then `NULL GONE`. Then Stratum (`--stratum substrate --depth 6`) and approach Null.
Expect: a low three-note grid tone with a slow digital pulse, barely there at 60 m, strong at 5 m, heard through walls; inside 2 m everything else drops out and only the tone is left; leaving the core brings the world back.
`PASS / FAIL` Note:

**L8. Music.** Board: pick a stratum, `INTENSITY` 0 then 1, `PEAK`, `RELIEF`, `TITLE MUSIC`, `ENDING`.
Expect: a dark, slow drone that never loops audibly over a minute; at intensity 1 it brightens and a dissonant fourth voice creeps in; `PEAK` drops the music out for about 4 s, then it returns thin; the title drone wavers slowly; the ending is one clean major chord, the only consonant thing in the game. The drone sits under the room tone and footsteps, never on top.
`PASS / FAIL` Note:

**L9. Places with eyes closed.** Stratum, one minute in each of the six strata (any depth and seed), eyes closed for the last 20 s.
Expect: you can tell the stratum from the room tone and the reverb alone: Halls dry and buzzing, Pools long and wet, Garage big and hard, Offices dead and close, Server fans and short, Substrate thin and hollow (the 300 Hz high-pass makes it sound like an empty render).
`PASS / FAIL` Note:

**L10. The quiet floor.** Stratum (Offices). Stand still for 30 s, then walk near a Still (or `STILL 5 M` on the Board) and stand.
Expect: the room tone is always there under everything, never a dead digital silence, except in Still's silence (quieter still) and the 1.5 s after a Flicker lunge (true silence).
`PASS / FAIL` Note:

**L11. Loudness sweep.** Board, Halls. Press each button of the INTERACT, ERRORS and PLAYER sections once at 5 m (one-shots) or toggle for 2 s (loops).
Expect: nothing jumps out much louder than its neighbours except on purpose (`door_slam`, `error_contact_hit`, `noclip_commit`, `dissolve`); UI ticks (`ui_move`, `ui_type`) are quiet but audible; the payphone ring is attention-getting, not painful; `ERRORS` on the `PEAK DB` line never goes above -6.
`PASS / FAIL` Note:

**L12. Threshold.** Stratum (`--stratum substrate --depth 6`); reach the Threshold (or the ending bench).
Expect: A1 alone, then its fifth when the Threshold door is in view; at the door the 1.2 s white tone cuts clean; then the ending's room tone and chord.
`PASS / FAIL` Note:

**L13. Speakers.** Repeat L2, L4 (Static at 10 m, Still) and L12 on laptop or desk speakers.
Expect: Echo's late step and Static's hum are still audible on small speakers (they carry above 200 Hz, not only in the sub), and the Threshold tone does not distort.
`PASS / FAIL` Note:

**L14. The audio guard on your machine (RCA1).** Run the Guard line (it opens a small window and plays 24 positional tones for 30 s), once on Linux and once on Windows, with the game's audio device on. Then play the Game for 10 minutes, dragging the window once (Windows) and alt-tabbing twice.
Expect: the Guard line prints `mode FRAME_TAIL`, `tripped false` and a tail p95 under 2 ms; write down its last two lines. In play, no clicks, crackles or dropouts. If it prints `tripped true`, the guard turned itself off: note the numbers; it is not a failure of the game, it means the RCA1 race stays unguarded on that machine.
`PASS / FAIL` Note:

---

**Feel questions**
1. Do you trust your own footsteps enough to notice a late one? (Echo depends on it.)
2. Which error did you hear before you saw it? Which one surprised you without warning?
3. Is any sound cheap or "video-gamey"? Name it (the Board's button name).
4. Is the contact hit too loud, too soft, or right?
