# Feedback Contract checklist

One row per row of `docs/design/11_feedback_contract.md` §2 and §3 (plus the item pickup, which §2 lists under Interact press), in the bench's firing order. Filled for every row by `game/scenes/debug/feedback_bench.tscn` on 2026-10-09 (M3.1, the Feedback Contract audit), seed 4, Halls, headless; the table below is the bench's `--md` output unedited. Re-generate with

```
$GODOT_BIN --headless --path game res://scenes/debug/feedback_bench.tscn -- --auto build/fb.json --md build/fb.md
```

`sim/test_feedback_bench.gd` runs the same sequence in the merge gate; `unit/test_feedback_rows.gd` fails when a row of the bench is missing from this file or not ticked.

**Legend.** `[x]` in **Ticked**: the row is implemented, reacts on at least min(3, listed) channels (the contract's floor) and every channel the table lists reacted on time except the ones the row documents as timed later by the table itself. `x` the channel reacted on time; `x*` it reacted although the table lists a dash; `+N` it reacted N physics ticks late; `no` the table lists it and nothing reacted; `-` not listed. **On time** means within 50 ms of the triggering frame, measured three ways (3 physics ticks, 3 process frames, 50 ms of wall time); it is late only if late by all three, because headless runs are not locked to 60 fps and physics ticks bunch up after a stall. **Result** `ok n/m`: n channels on time, m required (3, or the row's own count for the sparse rows). **What reacted** names the first thing the spy saw change per channel, filtered to the keys the row itself names (a sound id, a HUD part, the held light), so a coincidence elsewhere cannot pass a row. Image is the state the renderer and held objects are fed (CoherenceRenderer, flashlight, held item, exit, decals, hide mask), not pixels; Sound is AudioManager's player pool, loops and ducks; Motion is CameraRig; Readout is every property of the HUD tree. What it looks like on screen is the human's call (`human_check_M2.md`, `human_check_M3.md`) and the tour's (`tools/ci/tour_check.py`).

| Ticked | Action / event | Ref | I | S | M | R | Result | What reacted |
|---|---|---|---|---|---|---|---|---|
| [x] | Walk step | 11 §2 | x | x | x | - | ok 3/3 | I held.bob_amp; S play.foot_carpet; M cam.offset |
| [x] | Sprint start | 11 §2 | x | x | x | x | ok 4/3 | I held.bob_amp; S loop.sprint_breath_loop.24215.on; M rig.bob_amp; R StaminaShutter.vis |
| [x] | Sprint stop | 11 §2 | x | x | x | - | ok 3/3 | I held.bob_amp; S loop.sprint_breath_loop.24215.db; M rig.bob_amp |
| [x] | Stamina empty | 11 §2 | x* | x | x | x | ok 3/3 | I held.bob_amp; S play.stamina_empty_gasp; M cam.fov; R @Control@82.exhausted |
| [x] | Crouch | 11 §2 | x | x | x | - | ok 3/3 | I light.held_rot; S play.crouch; M cam.offset |
| [x] | Stand | 11 §2 | x | x | x | - | ok 3/3 | I light.held_rot; S play.crouch; M cam.offset |
| [x] | Flashlight on | 11 §2 | x | x | x | x | ok 4/3 | I light.on; S play.flashlight_toggle; M cam.rotation; R Crank.charge |
| [x] | Flashlight off | 11 §2 | x | x | x | x | ok 4/3 | I light.on; S play.flashlight_toggle; M cam.rotation; R Crank.light_on |
| [x] | Crank (hold) | 11 §2 | x | x | x | x | ok 4/3 | I light.beam; S loop.crank_loop.48683.on; M cam.offset; R Crank.charge |
| [x] | Crank full | 11 §2 | x | x | x* | x | ok 3/3 | I light.wheel_turning; S play.crank_full; M rig.sway; R Crank.turning |
| [x] | Item select | 11 §2 | x | x | x | x | ok 4/3 | I hand.pos; S play.ui_move; M cam.rotation; R Belt.selected |
| [x] | Item use: Polaroid | 11 §2 | x | x | x | +72 | ok 3/3 (R later by design: 09 §2: the Polaroid is spent on its flash at 1.2 s (a stun mid-use cancels it for free), so the count and Coherence read there) | I hand.model; S play.polaroid_charge; M cam.fov |
| [x] | Item use: Glowstick | 11 §2 | x | x | x | x | ok 4/3 | I scene.children; S play.glowstick_crack; M cam.rotation; R Slot1.draws |
| [x] | Chalk stamp | 11 §2 | x | x | x | x | ok 4/3 | I decals; S play.chalk_mark; M cam.rotation; R Slot1.draws |
| [x] | Item use: Flare | 11 §2 | x | x | x | x | ok 4/3 | I scene.children; S play.flare_ignite; M cam.rotation; R BeltShutter.draws |
| [x] | Item use: Radio | 11 §2 | x | x | x | x | ok 4/3 | I hand.model; S play.radio_ping; M cam.rotation; R BeltShutter.draws |
| [x] | Interact press | 11 §2 | x | x | x | x | ok 4/3 | I x.door; S play.door_close; M cam.rotation; R Prompt.raw_text |
| [x] | Interact press: item | 11 §2 | x | x | x | x | ok 4/3 | I x.fly; S play.item_pickup; M cam.rotation; R BeltShutter.draws |
| [x] | Interact hold | 11 §2 | x | x | - | x | ok 3/3 | I ui.underline; S play.ui_hold_tick; R Shutter.draws |
| [x] | Noclip charge | 11 §2 | x | x | x | x | ok 4/3 | I cr.noclip_target; S loop.noclip_charge.17961.on; M cam.offset; R @Control@83.target |
| [x] | Noclip cancel | 11 §2 | x | x | x | x | ok 4/3 | I cr.noclip_preview_collapsing; S play.noclip_cancel; M rig.sway; R NoclipShutter.draws |
| [x] | Noclip invalid | 11 §2 | x | x | - | x | ok 3/3 | I cr.noclip_charge; S play.noclip_fail; R NoclipShutter.vis |
| [x] | Noclip commit (wall) | 11 §2 | x | x | x | x | ok 4/3 | I cr.noclip_commit; S play.noclip_commit; M clock.hitstop; R Coherence.value |
| [x] | Enter hide spot | 11 §2 | x | x | x* | x | ok 3/3 | I hide.mask; S play.crouch; M cam.rotation; R ..hidden_state |
| [x] | Leave hide spot | 11 §2 | x | x | x | x | ok 4/3 | I hide.mask; S play.crouch; M cam.rotation; R ..hidden_state |
| [x] | Coherence loss | 11 §3 | x | x | - | x | ok 3/3 | I cr.coherence; S play.coherence_loss_tick; R Coherence.value |
| [x] | Coherence gain | 11 §3 | x | x | x | x | ok 4/3 | I cr.coherence; S play.coherence_gain; M cam.fov; R Coherence.value |
| [x] | Error contact | 11 §3 | x | x | x | x | ok 4/3 | I cr.coherence; S play.error_contact_hit; M clock.hitstop; R Coherence.value |
| [x] | Inside Static | 11 §3 | x | x | x | x | ok 4/3 | I cr.coherence; S loop.static_hum.29288.on; M cam.offset; R Coherence.value |
| [x] | Still within 8 m | 11 §3 | - | x | - | x | ok 2/2 | S duck.Ambience; R Stack.draws |
| [x] | Still observed 2 s | 11 §3 | x | x | - | - | ok 2/2 | I still.ticks; S play.still_tick |
| [x] | Flicker lunge | 11 §3 | x | x | x | x | ok 4/3 | I fixtures.flash; S play.flicker_lunge; M cam.offset; R Coherence.value |
| [x] | Echo at 4 m | 11 §3 | x | x | - | x | ok 3/3 | I echo.presence; S play.echo_breath; R Stack.draws |
| [x] | Null radius | 11 §3 | x | x | x | x* | ok 3/3 | I cr.null_radius; S gen.null_tone; M rig.jitter; R @Container@464.vis |
| [x] | Null core | 11 §3 | x | x | x | x | ok 4/3 | I cr.null_core; S gen.null_core; M rig.jitter; R Coherence.value |
| [x] | Exit seen | 11 §3 | x | x | - | x | ok 3/3 | I exit.lamp; S play.exit_latch; R Depth.status |
| [x] | Breaker thrown by player | 11 §3 | x | x | x | x | ok 4/3 | I x.lever; S play.breaker_lever; M cam.offset; R Stack.draws |
| [x] | Exit unlocked | 11 §3 | x | x | - | x | ok 3/3 | I exit.lamp; S play.exit_latch; R Depth.status |
| [x] | Note found | 11 §3 | x | x | - | x | ok 3/3 | I x.paper; S play.note_pickup; R Notifications.draws |
| [x] | Unlock earned | 11 §3 | - | x | - | x | ok 2/2 | S play.ui_unlock; R Notifications.draws |
| [x] | Noclip commit (floor) | 11 §2 | x | x | x | x | ok 4/3 | I cr.coherence; S play.noclip_commit; M clock.hitstop; R Coherence.value |
| [x] | Arrival (drop) | 11 §3 | x | x | x | x | ok 4/3 | I cr.drop_arrive; S play.drop_arrival; M cam.offset; R Notifications.draws |
| [x] | Enter exit | 11 §3 | x | x | x | x | ok 4/3 | I run.phase; S play.exit_open_door; M cam.fov; R Notifications.draws |
| [x] | Landing | 11 §3 | x | x | x | x | ok 4/3 | I run.phase; S play.exit_latch; M cam.offset; R ..size |
| [x] | Arrival (proper) | 11 §3 | x | x | x* | x | ok 3/3 | I landing.door; S play.exit_open; M rig.trauma; R Depth.depth |
| [x] | Dissolve | 11 §3 | x | x | x | x | ok 4/3 | I cr.coherence; S play.dissolve; M cam.offset; R Coherence.value |
| [x] | Threshold crossed | 11 §3 | x | x | - | x | ok 3/3 | I x.white; S play.threshold_tone; R ..vis |

## Notes on the rows

- **Complete.** Every action and event of 11 §2 and §3 has a row (47 rows); the contract document is parsed by `unit/test_feedback_rows.gd`, which fails when a row of the tables has no bench row. Fuse use has no row of its own: a fuse is used at a socket, which is the Interact hold row (the breaker's hold) and the `fuse_insert` sound; `use_item` on a fuse with no socket is a dull tick and a nudge, not a use.
- **Late by design (one channel).** Item use: Polaroid. The Polaroid is spent on its flash at 1.2 s (09 §2: a stun or a noclip charge mid-use cancels it for free), so the belt count and the +25 Coherence read at the flash (`+72`); its image (held photo), sound (`polaroid_charge`) and motion (the 3 degree narrowing) are on time. This is the only `allow` in `FeedbackRows`, pinned by `test_late_by_design_is_a_short_list`.
- **Real latencies the audit found and fixed in game code.** Leave hide spot: the view mask lifted when the 0.6 s slide out ended; it now lifts when it starts. Enter exit: `DESCENDING` printed when the level was left, 0.6 s after the entering tween began (the old checklist called it "about 9 ticks late"); it now prints with the tween (`Hud.show_descending`). Still within 8 m: the proximity report was a 10 Hz poll (up to 100 ms after the crossing); an error now also reports on the tick it crosses 8 m or 10 m.
- **The four intermittent rows were isolation or measurement faults.** `coherence_loss`: an earlier row's loss held the loss tick's rate limit (`PlayerAudio.reset_loss_limit`). `interact_hold` (S): the spy only counted a sound while it was playing, and the 40 ms hold tick could start and end between two slow frames; it now counts a sound by its start stamp. `echo_4m` (R): the recipe woke the Echo early, it wandered and stepped, and its caption was already on screen, so the step inside 4 m only refreshed it; the Echo now stays dormant until the anchor and takes its stride (`EchoWalk.stride_step`) there. `sprint_stop` (S): the recipe waited 140 physics ticks for the breath's 2 s fade-in, a process-time tween, and under load the fade was still moving at the stop, which made the fade-out's volume key "noisy"; it now waits for the loop to reach full level. The same pass fixed `null_core` (the Null walked into the core while the bench waited for quiet), `item_radio` (the hand raise was still moving at the press), and `noclip_cancel` (the preview's collapse is its own key now; the charge value itself moves every frame).
- **Real paths.** Recipes go through the game's own code: input actions, the interaction ray, `Player.contact`, `GameState`'s unlock grant, `ErrorBase` proximity, `EchoWalk.stride_step`, `Run._cross_threshold`. Where a recipe stands in for a walk it moves the cause (an error placed at 3.5 m, a Null placed on the player, a Still placed inside 8 m) and the consequence is the game's: Echo at 4 m, Null core, Still within 8 m, Exit unlocked after a placement only when the power wave has already arrived. Hooks left on purpose: the player is placed to face a door, a breaker or a wall (`face_interactable`, `face_edge`); Polaroid, Glowstick, Chalk, Flare and Radio are used with the right mouse button on a belt the bench stocks.
- **Contract nits.** Interact hold lists the prompt underline (Image) and the fill bar (Readout), which are one widget, so both channels read it. The walk step's dust stir near the feet is still a TODO in `player_locomotion.gd`; its Image channel today is the held flashlight and item bob.
- Rows run in one Descent: the level rows first, then the drop (Noclip commit floor, Arrival drop), then Enter exit, Landing, Arrival proper, the Dissolve, and Threshold crossed last.
- Not verified here: how any row looks or sounds (no GPU, no speakers). The bench reads the state the renderer, the audio pool and the HUD are fed; the human's check is in `human_check_M3.md`.
