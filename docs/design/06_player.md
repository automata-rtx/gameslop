# 06 — The Player

**Depends on:** `00_OVERVIEW.md`, `02_visual_direction.md`, `03_audio_direction.md`, `04_ui_design_language.md`
**Skills to read:** `godot-physics-3d`, `godot-camera-systems`, `godot-input-handling`, `godot-raycasting-queries`, `godot-state-machine-advanced`
**Pulls engagement levers:** push your luck (noclip costs), decisions every minute (speed versus silence, light versus dark), tactile everything.

---

## 1. What the player is

A `CharacterBody3D` with a camera at eye height and no visible body. The player has five verbs: **move**, **look**, **light** (toggle and crank), **interact**, and **noclip**, plus **use item**. There is no jump, no attack, no lean.

The player carries three meters: **Coherence** (how real they are; the only health), **Stamina** (sprint), and **Charge** (flashlight). Each has one way up and a few ways down, and each is read on the HUD in a fixed place (`04` §6).

## 2. Input map (canonical action names)

| Action name | Default | Notes |
|---|---|---|
| `move_forward` / `move_back` / `move_left` / `move_right` | W / S / A / D | |
| `look` (mouse motion) | mouse | sensitivity and invert Y in `12` |
| `sprint` | Left Shift | hold by default; toggle option |
| `crouch` | Left Ctrl | hold by default; toggle option |
| `interact` | E | press; some prompts are hold (0.6 s) |
| `flashlight` | F | toggle |
| `crank` | R | hold |
| `noclip` | Left Mouse | hold to charge, release to cancel |
| `use_item` | Right Mouse | press |
| `item_1` to `item_4` | 1 to 4 | select slot |
| `item_next` / `item_prev` | wheel down / wheel up | |
| `status` | Tab | hold: shows run stats overlay and the last note |
| `pause` | Escape | |
| `ui_accept` / `ui_cancel` / `ui_up` … | Enter / Esc / arrows | Godot built-ins, not rebindable |

All non-UI actions are rebindable (`12`). Prompts display the bound key's name.

## 3. Body and movement

| Parameter | Value |
|---|---|
| Capsule | radius 0.35 m, height 1.8 m; crouched 1.1 m (camera 1.65 m / 0.95 m) |
| Walk speed | 3.2 m/s |
| Sprint speed | 5.6 m/s |
| Crouch speed | 1.6 m/s |
| Cranking or charging noclip | capped at crouch speed |
| Wading (Pools water deeper than 0.3 m) | speed × 0.6, noise × 1.6 |
| Acceleration / deceleration | 12 / 16 m/s² (grounded; snappy, no slide) |
| Step height | 0.3 m (`floor_snap_length` 0.3, `floor_max_angle` 46°) |
| Gravity | 9.8 m/s²; the player is never airborne except during a drop (`05` §4) |
| Crouch transition | 120 ms camera height tween, blocked from standing if the ceiling is low (shape cast) |
| Mouse look | yaw unbounded, pitch clamped ±89°; sensitivity 0.1 to 3.0 (default 1.0 = 0.0022 rad per pixel) |

**Feel rules:** no acceleration curves on input (digital keys); strafing speed equals forward speed; diagonal normalised. Movement must feel grounded and immediate, like a person walking, not like a shooter. Head bob and lean per `02` §11.

## 4. Stamina

- 100 max. Sprint drains 20 per second (5 s of full sprint). Regenerates 25 per second after a 1 s delay once sprint is released.
- At 0: 2 s lockout (cannot sprint), the gasp sound, stamina arc in `ui_danger`. Regeneration continues during the lockout.
- Sprinting while wading drains at 1.5×.
- Sprinting is the player's fastest way to make noise (§6) and the only way to outpace a chasing Still over open ground. The decision "run or stay quiet" is the stamina system's reason to exist.

## 5. Flashlight and crank

- **Charge** 0 to 100. Drains 1.6 per second while on (about 62 s). The light's energy scales `lerp(0.5, 1.6, charge/100)` and the spot angle narrows from 38° to 30° as charge falls below 30 (the beam "tires").
- **Crank** (hold `crank`): +25 per second. While cranking: speed capped to crouch speed, cannot noclip or use items, the held flashlight model's wheel spins, the whine rises in pitch with charge (`03`), and a noise event of radius 12 m is emitted every 0.5 s. Crank is available any time, even with the light on.
- **Toggle** is instant with the relay click. The light can be toggled during a charge of noclip.
- **Lightbearer** loadout cranks at ×1.5.
- Design intent: cranking is loud and slow, so the player is forced to choose a moment for it. The flashlight is never "empty" (minimum energy 0.5), so T1 (`02`) holds, but a tired beam cannot hold Still at distance (its observation check needs a lit, unoccluded view; `08`).

## 6. Noise model

Every player action emits `EventBus.noise_emitted(pos, radius, kind)`. Errors (`08`) hear a noise if their distance to `pos` is less than `radius` (with walls reducing the effective radius by 35% per wall in the straight line, computed with up to 3 raycasts). The same event drives the sound playback (`03`), so what is heard by errors is exactly what the player hears.

| Action | Radius (m) | Kind |
|---|---|---|
| Walk step: carpet / tile / concrete / raised floor / substrate | 5 / 7 / 7 / 8 / 6 | `step` |
| Walk step in water | 10 | `step` |
| Sprint step | walk radius × 1.8 | `step` |
| Crouch step | walk radius × 0.4 | `step` |
| Crank (per 0.5 s) | 12 | `mech` |
| Noclip commit | 20 | `tear` |
| Flashlight toggle | 2 | `mech` |
| Door open / close / slam | 8 / 8 / 18 | `door` |
| Item drop (glowstick, flare landing) | 6 | `impact` |
| Flare burning (per 1 s) | 14 | `light` |
| Radio on (per 1 s) | 10 | `mech` |
| Breaker thrown | 25 | `mech` |
| Error contact | 15 | `tear` |

Step cadence: one step every 0.55 m walked (0.45 m sprinting, 0.7 m crouching), so sprint is both louder and more frequent.

## 7. Interaction

- A ray from the camera, 2.2 m, on the `interactable` physics layer, evaluated every physics frame; the hit's `Interactable` component provides `prompt_text()`, `can_interact()`, `interact(player)` and optionally `hold_time` (default 0, i.e. press).
- The HUD prompt shows `[E] TEXT` while a valid target exists. Hold interactions show a filling underline on the prompt.
- Interactables (`09`): doors, items, notes, breakers, keycard readers, fuse sockets, hide spots, vending machines, payphones, the Landing's item panel, the exit.

## 8. Noclip (the signature verb)

### Targeting
Each physics frame while `noclip` is held, a ray from the camera (max 2.5 m) finds the aimed surface on the `world` layer.

- **Wall target:** surface normal within 30° of horizontal. Valid if the level marks the surface's cell wall as passable (every interior wall and partition is; perimeter and "solid" walls are not; `07` §7) and a shape cast of the player capsule from the far side of the wall finds free space within 0.3 to 2.0 m beyond the surface. Reasons shown when invalid: `SOLID` (perimeter), `NO SPACE` (no free cell behind), `TOO FAR` (not within 2.5 m).
- **Floor target:** surface normal within 20° of up, hit point within 2.5 m, and the current depth is not the last of the run (depth 6 in Descent; never solid in Endless). Invalid reason on depth 6: `SOLID`.
- **Soft walls** (`09` §8): same as wall target but the charge is faster and cheaper (below).
- Ceilings are never valid (`SOLID`).

### Charge
| Target | Charge time | Coherence cost | Speed while charging | Noise on commit |
|---|---|---|---|---|
| Soft wall | 0.35 s | 5 | crouch cap | 20 m |
| Wall | 0.6 s | 10 | crouch cap | 20 m |
| Floor (drop) | 2.5 s | 30 | crouch cap | 20 m |

Releasing before full charge cancels (no cost, a short descending tone). Looking away from the target cancels. Being contacted by an error cancels. The charge is shown by the HUD arc (`04` §6), the world-shader unrender preview around the target point, the rising sine cluster, and a slow FOV pull-in of 6° (`11`).

### Commit
1. **Hitstop:** 80 ms freeze of the world (`Engine.time_scale` 0.0 is not used; the player's and errors' processing is paused and the audio gap plays), with the sub thump and the tear.
2. **Pass (wall):** the camera moves through the wall over 250 ms along the aim direction to the found free spot; during the pass, collision with the `world` layer is disabled for the player, the world shader's `g_noclip_commit` is 1.0 (geometry within 3 m is lines), the post shader's `noclip_commit` pulse plays, and the FOV punches +8° then returns over 300 ms.
3. **Pass (floor):** the camera drops through the floor into black with grain for 1.2 s, then the next level's arrival (`05` §4). `GameState.descend(false)` is called at commit, so a death during the fall is impossible.
4. **After:** Coherence is deducted with the loss animation; a 1.0 s cooldown before another charge; the noise event; the Director is informed (`10`).

### Why noclip matters to every other system
- To the Director: it is the loudest voluntary noise and the player's escape valve; the Director lowers intensity for 15 s after a successful wall pass that broke line of sight (`10`).
- To errors: Still and Flicker cannot follow through walls. Echo and Static effectively can (sound). Null does not need walls.
- To the level: soft walls are generator-guaranteed shortcuts; ordinary walls make every maze solvable in more than one way.
- To the renderer: it is the only time the player sees the world as lines by choice.

## 9. Coherence

- 100 max, starts per loadout. There is **no passive regeneration**.
- Gains: proper exit +20; Polaroid +25; the ending restores to 100.
- Losses: noclip (5/10/30); Static inside the field 4 per second; error contact (Still 35, Echo 25, Flicker 30); Null core 12 per second; Cycle 2 ambient drain 0.2 per second in the Substrate only.
- Below 25: HUD danger state, renderer near-monochrome, heartbeat floor 90 bpm. No mechanical penalty: the pressure is perceptual and the player's tools are unchanged (pillar 2: legibility).
- At 0: **dissolution**. Input is locked; 1.5 s of the dissolve sequence (`02` §10, `03` §4), then the Run Summary (`04` §7). Cause is the last damage source.

**Contact rules** (shared with `08` and `10`): on contact the player loses the error's amount, is stunned 1.2 s (no sprint, no noclip, movement at crouch speed, camera trauma 0.6), is pushed 1.5 m away from the error, and the error enters its "satiated" state for 20 s. Two contacts cannot happen within 3 s of each other.

## 10. Hiding

Hide spots (`09` §6) are entered with `interact`. Inside: the camera moves to the spot's view position (under a car: a 0.4 m high slot; a locker: a slatted view; under a desk: the desk's front gap), movement is disabled, the HUD enters hidden state, breathing is audible, and the player can look within ±35°. Leaving is a 0.6 s hold. Errors lose the player's position when they enter a hide spot while not in direct line of sight (`08`). Hiding does not stop Static's drain or Null's core.

## 11. Arrival and spawn

- **Proper exit arrival:** the Landing cabin opens onto the spawn room. The player walks out. Depth label shutters in. The 30 s calm window begins (`10`).
- **Drop arrival:** 1.2 s of black and grain, then standing at a random valid cell ≥ 15 m from all errors and outside the exit room, facing the longest open sightline from that cell. `DROPPED · THEY ARE AWAKE`.
- The player never spawns facing a wall closer than 2 m.

## 12. State machine

`PlayerStateMachine` states: `Idle`, `Walk`, `Sprint`, `Crouch`, `Crank` (overlaps movement states as a flag rather than a state; implemented as a flag), `NoclipCharge`, `NoclipPass`, `Stunned`, `Hidden`, `Landing`, `Dropping`, `Dissolving`, `Cinematic` (ending). Transitions are explicit; `Stunned` can interrupt `NoclipCharge` but not `NoclipPass`.

## 13. Verification

- Unit tests (`14` §8): noise radius table, stamina timings, Coherence arithmetic, noclip validity function against synthetic walls (passable, solid, thick, no space), contact rules (3 s exclusivity).
- Feel checklist (human or vision agent): walking into a wall stops dead with no jitter; crouch under a desk and stand blocked; the sprint arc shutters out 1 s after refill; cranking spins the wheel; noclip preview appears before the arc is 10% full.

## Interfaces

- `Player` node: signals `coherence_changed(value, delta, source)`, `stamina_changed(value)`, `charge_changed(value)`, `noclip_state(charge: float, target: StringName, valid: bool, reason: StringName)`, `contacted(by: StringName)`, `dissolved(cause: StringName)`, `hidden_changed(on: bool)`.
- `Player.apply_coherence(delta: float, source: StringName)`; `Player.contact(error: Node3D, amount: float)` (applies the contact rules); `Player.is_observing(node: Node3D) -> bool` (frustum, distance ≤ 30 m, unoccluded, and lit: either the flashlight is on and aimed within 25° or the node is within a lit fixture group); `Player.eye_position() -> Vector3`; `Player.is_hidden() -> bool`.
- `EventBus.noise_emitted(pos, radius, kind)`.
- `tuning.gd` constants for every number in this document.
