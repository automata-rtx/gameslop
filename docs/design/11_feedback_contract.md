# 11 — The Feedback Contract

**Depends on:** `00_OVERVIEW.md`, `02_visual_direction.md`, `03_audio_direction.md`, `04_ui_design_language.md`, `06_player.md`
**Skills to read:** `godot-tweening`, `godot-camera-systems`, `godot-particles`, `godot-animation-player`
**Pulls engagement levers:** tactile everything (pillar 4), push your luck (costs are felt), readable rules (tells are consistent).

---

## 1. The contract

Every player action and every event that affects the player produces feedback on at least three of four channels within 50 ms of the triggering frame:

- **Image** (I): a change in the world render, the post stack, the held object, or particles.
- **Sound** (S): a sample or a change in a continuous layer.
- **Motion** (M): camera translation, rotation, FOV, head bob change, or hitstop.
- **Readout** (R): a HUD change.

The tables below are the contract. An agent implementing an action implements its row completely. An agent reviewing a milestone checks each row in the bench scene. Durations use `TRANS_EXPO`/`EASE_OUT` unless stated. Camera shake uses trauma (`shake = trauma²`, decays 1.5 per second, max 0.04 m / 1.2°, scaled by the setting).

## 2. Player actions

| Action | I | S | M | R |
|---|---|---|---|---|
| Walk step | flashlight bob step, dust stir near feet (Halls, Garage, Offices) | surface step sample | head bob cycle, 1.5° strafe roll | — |
| Sprint start / stop | bob amplitude ×1.6 / back | breath loop fades in over 2 s / out 1 s | FOV +4° over 200 ms / back 300 ms | stamina arc appears |
| Stamina empty | — | gasp | FOV snaps back; bob reduces 20% for 2 s | arc `ui_danger`, blinks twice |
| Crouch / stand | — | cloth rustle | camera height 120 ms, 0.05 m dip overshoot | — |
| Flashlight on / off | beam, lens emissive, hand light | relay click | 0.3° roll kick toward the hand | crank gauge brightens / dims |
| Crank (hold) | wheel spins at charge rate, lens brightens | ratchet loop with rising whine | 1 Hz 0.004 m camera sway with the crank | gauge fills, handle glyph rotates |
| Crank full | wheel stops | bright click | — | gauge `ui_dim` |
| Interact press | target object animates (door swing, lever throw, item fly) | the object's sound | 0.2° nod | prompt shutters out |
| Interact hold | underline fills on the prompt | low tick per 0.2 s | — | fill bar |
| Item select | held item lower-in/raise-out 0.5 s | UI tick | hand bob 1 cycle | slot underline moves, glyph pulses 1.15× |
| Item use (each) | per `09` (flash, throw arc, flame, stamp decal, LED) | per `03` | throw: 2° pitch recoil; Polaroid: 1 s view narrows 3° then flash | count decrements with a 100 ms `ui_accent` blink |
| Noclip charge | unrender preview grows at the target; scanline shimmer; held flashlight dims 30% | rising sine cluster tracks charge | FOV −6° over the charge; sway 0.003 m | arc fills in `ui_cold`, target glyph, readiness ring at 90% |
| Noclip cancel | preview collapses 100 ms | descending tone | FOV returns 150 ms | arc shutters out |
| Noclip commit (wall) | 80 ms hitstop; world lines within 3 m; CA 0.05 pulse; grain spike | sub thump, tear, 60 ms gap | FOV +8° punch, 250 ms pass, 0.8 trauma | Coherence −10 loss animation; `[tear]` caption |
| Noclip commit (floor) | as wall, then 1.2 s black with grain | as wall plus a falling sine | camera pitches down 10° during the fall | Coherence −30; `DROPPED · THEY ARE AWAKE` |
| Noclip invalid | preview dashed | dull tone once | — | reason word under the crosshair |
| Chalk stamp | decal appears with a 100 ms scale-in | three scrapes | 1° pitch nod | count decrements |
| Enter hide spot | camera slides 0.6 s; view mask | cloth plus the spot's sound (car scrape, locker click) | — | HUD dims, eye glyph |
| Leave hide spot | view mask lifts | cloth (the entry sound reversed in order, not in time) | camera slides out 0.6 s | HUD restores |

## 3. Things that happen to the player

| Event | I | S | M | R |
|---|---|---|---|---|
| Coherence loss (any) | post `drain` updates immediately (desaturation/grain/CA step), the HUD segment in `ui_danger` for 600 ms | loss tick per unit (rate-limited) | — | numeral ticks down at 30 per second |
| Coherence gain | saturation overshoot 1.15 for 600 ms, warmth | warm chord | FOV +2° then back 400 ms | segment flashes `ui_accent`, numeral ticks up |
| Error contact | inverted-luminance flash 2 frames, CA 0.03, grain spike, the error's signature at full | contact hit | 1.5 m push, trauma 0.6, 1.2 s stun with bob off | loss animation, `[contact]` caption, stun indicated by the crosshair becoming a dashed ring for 1.2 s |
| Inside Static | refraction, grain to 0.6, CA 0.02 | hum and noise band rise | 0.002 m jitter | Coherence drains visibly 4 per second |
| Still within 8 m | — | ambience −6 dB | — | `[silence]` caption |
| Still observed ≥ 2 s | render-line tick | 6 kHz blip | — | — |
| Flicker lunge | group flashes white 2 frames, then dark 1.5 s | flash noise, then silence | trauma 0.4 if hit | loss if hit |
| Echo at 4 m | shimmer | breath swell | — | `[footsteps, behind, late]` |
| Null radius | unrender lines, halo | grid tone | 0.004 m jitter | — |
| Null core | black with halo | everything muted but grid tone | 0.01 m jitter | drain 12 per second |
| Exit seen | exit prefab's light pulses once | long tone (Cycled) or latch (others) | — | `EXIT: …` status shutters in, −0.15 intensity |
| Exit unlocked | exit light goes steady warm | latch and hiss | — | status to `OPEN` in `ui_fg`, `EXIT UNLOCKED` notification |
| Enter exit | 0.6 s entering tween into the cabin | hydraulic hiss | FOV −3° | `DESCENDING` |
| Landing | cabin shudder, one unrender ripple | cabin hum, latch | 0.3 trauma at start and end | item panel, `COHERENCE +20` |
| Arrival (proper) | cabin door opens | door | — | depth label shutters in |
| Arrival (drop) | black and grain to the world over 400 ms | sub settle | 0.3 trauma | `DROPPED · THEY ARE AWAKE` |
| Note found | sheet shutters in, types | paper slide | — | `ARCHIVE: NOTE X` |
| Unlock earned | — | unlock chime | — | notification in `ui_accent` |
| Breaker thrown by player | lever, power wave sweeps the floor | clunk, fixtures igniting in sequence | 0.3 trauma | `EXIT: OPEN` |
| Dissolve | the view breaks into a 48 × 27 grid of quads that scatter to black with grain, 1.5 s | dissolve sound | input locked, camera drifts 0.02 m | HUD shutters out at 0.5 s |
| Threshold crossed | door opens, cut to white | low tone | — | HUD gone |

## 4. Hitstop

Implemented by `Clock.hitstop(ms)`: `get_tree().paused = true` for N ms of wall-clock time (a one-shot `Timer` with `process_mode = PROCESS_MODE_ALWAYS` unpauses). The post stack quad, the HUD, the captions, the audio players for pulses, and the Clock itself are `PROCESS_MODE_ALWAYS` so the image and sound continue; the player, errors, props, Director, and level are `PROCESS_MODE_PAUSABLE` (the default). The pause menu uses the same tree pause, so `Clock` refuses a hitstop while the menu is open and ends any hitstop when the menu opens. Used only for the noclip commit (80 ms) and error contact (60 ms). Never for UI.

## 5. Tweens and timing

- All HUD value changes: 180 ms. All shutters: 120 ms. Screen transitions: 120 ms glitch.
- Camera FOV changes: 200 to 300 ms. Camera height: 120 ms.
- Held objects: 500 ms lower-in/raise-out.
- Anything the player might do twice in a row (select, stamp, toggle) must be interruptible: a new tween kills the previous.

## 6. What must never happen

- Feedback that lies: a sound without its noise event, a flicker without Flicker, a render tick without observation.
- Decorative shake: no shake on walking, on doors, or on notes.
- Feedback that hides information: the Coherence bar is never covered by a note sheet or a prompt; captions never overlap the prompt (captions sit above it).
- Audio clipping: all pulses go through the limiter.

## 7. Verification

- `game/scenes/debug/feedback_bench.tscn`: buttons for every row above, each firing the exact event through `EventBus`, with a frame counter that prints the delay from event to first visible change (must be ≤ 3 frames at 60 fps).
- The milestone review walks every row with the bench and ticks it in `docs/qa/feedback_checklist.md`.

## Interfaces

- `CoherenceRenderer.pulse(kind)` kinds: `hit`, `noclip_commit`, `coherence_gain`, `dissolve`, `flash`.
- `CameraRig`: `add_trauma(v)`, `fov_punch(delta_deg, up_ms, down_ms)`, `fov_hold(delta_deg)`, `set_bob_scale(v)`, `nod(pitch_deg)`, `roll_kick(deg)`.
- `Clock.hitstop(ms)`.
- `HUD` methods per `04`.
