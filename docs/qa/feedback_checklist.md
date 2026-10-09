# Feedback Contract checklist

One row per row of `docs/design/11_feedback_contract.md` §2 and §3, in the bench's firing order. Filled for every row (M1 and M2) by `game/scenes/debug/feedback_bench.tscn` on 2026-10-09 (R17, after the M2.17 review), seed 4, Halls, headless; the table below is the bench's `--md` output unedited. Re-generate with

```
$GODOT_BIN --headless --path game res://scenes/debug/feedback_bench.tscn -- --auto build/fb.json --md build/fb.md
```

`sim/test_feedback_bench.gd` runs the same sequence in the merge gate and fails when an implemented row reacts on fewer than min(3, listed) channels within the budget.

**Legend.** `x` the channel reacted on time; `x*` it reacted although the table lists a dash; `+N` it reacted N physics ticks late; `no` the table lists it and nothing reacted; `-` not listed; `pending` the feature does not exist yet. **On time** means within 50 ms of the triggering frame, measured three ways (3 physics ticks, 3 process frames, 50 ms of wall time); it is late only if late by all three, because headless runs are not locked to 60 fps and physics ticks bunch up after a stall. **Result** `ok n/m`: n channels on time, m required (3, or the row's own count for the sparse rows). **What reacted** names the first thing the spy saw change per channel: Image is the state the renderer and held objects are fed (CoherenceRenderer, flashlight, held item, exit, decals, hide mask), not pixels; Sound is AudioManager's player pool, loops and ducks; Motion is CameraRig; Readout is every property of the HUD tree. What it looks like on screen is the human's call (`human_check_cp-06.md`) and the tour's (`tools/ci/tour_check.py`).

| Action / event | Ref | I | S | M | R | Result | What reacted |
|---|---|---|---|---|---|---|---|
| Walk step | 11 §2 | x | x | x | - | ok 3/3 | I held.bob_amp; S play.foot_carpet; M cam.offset |
| Sprint start | 11 §2 | x | x | x | x | ok 4/3 | I held.bob_amp; S loop.sprint_breath_loop.76309.on; M rig.bob_amp; R StaminaShutter.vis |
| Sprint stop | 11 §2 | x | x | x | - | ok 3/3 | I held.bob_amp; S loop.sprint_breath_loop.76309.db; M rig.bob_amp |
| Stamina empty | 11 §2 | x* | x | x | x | ok 3/3 | I held.bob_amp; S play.stamina_empty_gasp; M cam.fov; R @Control@82.exhausted |
| Crouch | 11 §2 | x | x | x | - | ok 3/3 | I light.held_rot; S play.crouch; M cam.offset |
| Stand | 11 §2 | x | x | x | - | ok 3/3 | I light.held_rot; S play.crouch; M cam.offset |
| Flashlight on | 11 §2 | x | x | x | x | ok 4/3 | I light.on; S play.flashlight_toggle; M cam.rotation; R Crank.charge |
| Flashlight off | 11 §2 | x | x | x | x | ok 4/3 | I light.on; S play.flashlight_toggle; M cam.rotation; R Crank.light_on |
| Crank (hold) | 11 §2 | x | x | x | x | ok 4/3 | I light.beam; S loop.crank_loop.62770.on; M cam.offset; R Crank.charge |
| Crank full | 11 §2 | x | x | x* | x | ok 3/3 | I light.wheel_turning; S play.crank_full; M rig.sway; R Crank.turning |
| Item select | 11 §2 | x | x | x | x | ok 4/3 | I hand.pos; S play.ui_move; M cam.rotation; R Belt.selected |
| Item use: Polaroid | 11 §2 | x | x | x | +72 | ok 3/3 | I hand.model; S play.polaroid_charge; M cam.fov |
| Item use: Glowstick | 11 §2 | x | x | x | x | ok 4/3 | I scene.children; S play.glowstick_crack; M cam.rotation; R Slot1.draws |
| Chalk stamp | 11 §2 | x | x | x | x | ok 4/3 | I decals; S play.chalk_mark; M cam.rotation; R Slot1.draws |
| Item use: Flare | 11 §2 | x | x | x | x | ok 4/3 | I scene.children; S play.flare_ignite; M cam.rotation; R BeltShutter.draws |
| Item use: Radio | 11 §2 | +11 | x | x | x | ok 3/3 | S play.radio_ping; M cam.rotation; R BeltShutter.draws |
| Interact press | 11 §2 | x | x | x | x | ok 4/3 | I x.door; S play.door_close; M cam.rotation; R Prompt.raw_text |
| Interact hold | 11 §2 | x | x | - | x | ok 3/3 | I ui.underline; S play.ui_hold_tick; R Prompt.progress |
| Noclip charge | 11 §2 | x | x | x | x | ok 4/3 | I cr.noclip_target; S loop.noclip_charge.19497.on; M cam.offset; R @Control@83.target |
| Noclip cancel | 11 §2 | x | x | x | x | ok 4/3 | I cr.noclip_target; S play.noclip_cancel; M rig.sway; R NoclipShutter.draws |
| Noclip invalid | 11 §2 | x | x | - | x | ok 3/3 | I cr.noclip_charge; S play.noclip_fail; R NoclipShutter.vis |
| Noclip commit (wall) | 11 §2 | x | x | x | x | ok 4/3 | I cr.noclip_commit; S play.noclip_commit; M clock.hitstop; R Coherence.value |
| Enter hide spot | 11 §2 | x | x | x* | x | ok 3/3 | I hide.mask; S play.crouch; M cam.rotation; R ..hidden_state |
| Leave hide spot | 11 §2 | no | x | x | x | ok 3/3 | S play.crouch; M cam.rotation; R ..hidden_state |
| Coherence loss | 11 §3 | x | x | - | x | ok 3/3 | I cr.coherence; S play.coherence_loss_tick; R Coherence.value |
| Coherence gain | 11 §3 | x | x | x | x | ok 4/3 | I cr.coherence; S play.coherence_gain; M cam.fov; R Coherence.value |
| Error contact | 11 §3 | x | x | x | x | ok 4/3 | I cr.coherence; S play.error_contact_hit; M clock.hitstop; R Coherence.value |
| Inside Static | 11 §3 | x | x | x | x | ok 4/3 | I cr.coherence; S loop.static_hum.94466.on; M cam.offset; R Coherence.value |
| Still within 8 m | 11 §3 | - | x | - | x | ok 2/2 | S duck.Ambience; R Stack.draws |
| Still observed 2 s | 11 §3 | x | x | - | - | ok 2/2 | I still.ticks; S play.still_tick |
| Flicker lunge | 11 §3 | x | x | x | x | ok 4/3 | I fixtures.flash; S play.flicker_lunge; M cam.offset; R Coherence.value |
| Echo at 4 m | 11 §3 | x | x | - | x | ok 3/3 | I echo.presence; S play.echo_breath; R Stack.draws |
| Null radius | 11 §3 | x | x | x | x* | ok 3/3 | I cr.null_radius; S gen.null_tone; M rig.jitter; R @Container@449.vis |
| Null core | 11 §3 | x | x | x | x | ok 4/3 | I cr.null_core; S gen.null_core; M rig.jitter; R Coherence.value |
| Exit seen | 11 §3 | x | x | - | x | ok 3/3 | I exit.lamp; S play.exit_latch; R Depth.status |
| Breaker thrown by player | 11 §3 | x | x | x | x | ok 4/3 | I x.lever; S play.breaker_lever; M cam.offset; R Stack.draws |
| Exit unlocked | 11 §3 | x | x | - | x | ok 3/3 | I exit.lamp; S play.exit_latch; R Depth.status |
| Note found | 11 §3 | x | x | - | x | ok 3/3 | I x.paper; S play.note_pickup; R Notifications.draws |
| Unlock earned | 11 §3 | - | x | - | x | ok 2/2 | S play.ui_unlock; R Notifications.draws |
| Noclip commit (floor) | 11 §2 | x | x | x | x | ok 4/3 | I cr.coherence; S play.noclip_commit; M clock.hitstop; R Coherence.value |
| Arrival (drop) | 11 §3 | x | x | x | x | ok 4/3 | I cr.drop_arrive; S play.drop_arrival; M cam.offset; R Depth.draws |
| Enter exit | 11 §3 | x | x | x | no | ok 3/3 | I run.phase; S play.exit_open_door; M cam.fov |
| Landing | 11 §3 | x | x | x | x | ok 4/3 | I run.phase; S play.exit_latch; M cam.offset; R ..size |
| Arrival (proper) | 11 §3 | x | x | x* | x | ok 3/3 | I landing.door; S play.exit_open; M rig.trauma; R Depth.depth |
| Dissolve | 11 §3 | x | x | x | x | ok 4/3 | I cr.coherence; S play.dissolve; M cam.offset; R Coherence.value |
| Threshold crossed | 11 §3 | x | x | - | x | ok 3/3 | I x.white; S play.threshold_tone; R ..vis |

## Notes on the rows

- **Gaps:** none. The M1.12 gaps closed in M2.12 (the `[silence]` and Echo captions on the HUD, the unlock chime); the rows were promoted and the gate test pins them as implemented.
- **Pending:** none. Threshold crossed (R17) is fired through the run's own `Run._cross_threshold` with the bench's run kept on screen (`Run.threshold_scene` cleared): the white cut layer's alpha (I, probe `x.white`), the single low tone `threshold_tone` (S), the HUD gone (R, the HUD root's `visible`). Motion is a dash in 11 §3.
- **Late or missing channels on rows that still pass:** Polaroid's count and Coherence arrive at 1.2 s by design (`+72`); Radio's held-item raise landed 11 ticks late on this run (its sound, nod and belt are on time); Leave hide spot lifts the view mask at the end of the 0.6 s slide, not at its start; Enter exit shows `DESCENDING` at the end of the 0.6 s tween (R reads `no` inside the 20-tick window, about 9 ticks late in the gate's run).
- **Contract nits:** Interact hold lists the prompt underline (Image) and the fill bar (Readout), which are one widget, so both channels read it. The walk step's dust stir near the feet is still a TODO in `player_locomotion.gd`; its Image channel today is the held flashlight and item bob. Crouch / Stand gained the held light's dip (R11) and now meet three channels.
- Rows run in one Descent: the level rows first, then the drop (Noclip commit floor, Arrival drop), then Enter exit, Landing, Arrival proper, the Dissolve, and Threshold crossed last.
- What each row looks and sounds like is still the human's check on a GPU (`human_check_M2.md`); the bench reads the state the renderer, the audio pool and the HUD are fed.
