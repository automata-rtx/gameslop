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

- **Wall target:** surface normal within 30° of horizontal. Valid if the level marks the surface's cell wall as passable (every interior wall and partition is; perimeter and "solid" walls are not; `07` §7) and a shape cast of the player capsule from the far side of the wall finds free space within 0.3 to 2.0 m beyond the surface. Reasons shown when invalid: `SOLID` (perimeter), `NO SPACE` (no free cell behind), `TOO FAR` (not within 2.5 m), `TOO THIN` (the player's Coherence is not greater than the cost: a noclip can never reduce Coherence to 0, so spending is always a survivable choice).
- **Floor target:** surface normal within 20° of up, hit point within 2.5 m, and the current depth is not the last of the run (depth 6 in Descent; never solid in Endless). Invalid reason on depth 6: `SOLID`.
- **Soft walls** (`09` §8): same as wall target but the charge is faster and cheaper (below).
- Ceilings are never valid (`SOLID`).
- Any target is invalid with reason `TOO THIN` when `coherence <= cost` for that target type.

### Charge
| Target | Charge time | Coherence cost | Speed while charging | Noise on commit |
|---|---|---|---|---|
| Soft wall | 0.35 s | 5 | crouch cap | 20 m |
| Wall | 0.6 s | 10 | crouch cap | 20 m |
| Floor (drop) | 2.5 s | 30 | crouch cap | 20 m |

Releasing before full charge cancels (no cost, a short descending tone). Looking away from the target cancels. Being contacted by an error cancels. The charge is shown by the HUD arc (`04` §6), the world-shader unrender preview around the target point, the rising sine cluster, and a slow FOV pull-in of 6° (`11`).

### Commit
1. **Hitstop:** 80 ms freeze of the world via `Clock.hitstop(80)` (`11` §4: the scene tree is paused; HUD, post stack, and audio run as `PROCESS_MODE_ALWAYS`), with the sub thump and the tear.
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
- At 0: **dissolution**. Input is locked; 1.5 s of the dissolve sequence (`02` §10, `03` §4), then the Run Summary (`04` §7). Cause is the last damage source: one of the five error ids, or `&"substrate"` for the Cycle 2 ambient drain (summary line `DISSOLVED BY THE SUBSTRATE`). Noclip can never be a cause (`§8`, `TOO THIN`).

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
- `Player.apply_coherence(delta: float, source: StringName)`; `Player.contact(error: Node3D, amount: float) -> bool` (applies the contact rules; returns false when the Director refuses it under the 3 s exclusivity, `10` §4); `Player.is_observing(node: Node3D) -> bool` (frustum, distance ≤ 30 m, unoccluded, and lit per `08` §4: flashlight on and within 25° of the beam axis, or a glowstick within 4 m or a burning flare within 8 m of the node, or the node inside the light range of a powered fixture); `Player.eye_position() -> Vector3`; `Player.is_hidden() -> bool`.
- `EventBus.noise_emitted(pos, radius, kind)`.
- `tuning.gd` constants for every number in this document.

### Interface additions during production
- Player signals: `dissolved(cause)`, `state_changed`, `sprint_changed`, `stamina_exhausted`, `stun_changed`, `flashlight_toggled`, `crank_changed`, `prompt_changed(text, hold_time)`, `prompt_progress(f)`.
- Player methods: `add_light_query`/`remove_light_query`, `reset_for_run`, `enter_hide`/`leave_hide`, `can_use_item`, `is_stunned`, `is_dissolving`; noclip seam `begin_noclip_charge`, `end_noclip_charge`, `report_noclip`, `can_noclip`, and an exported `noclip_targeting` called as `physics_update(player, held, delta)`.
- Player properties: `water_depth`, `default_surface`; floor colliders may carry a `surface` meta.
- `CameraRig.fov_hold(delta_deg, ms = 200, key = &"default")`: one hold per key, summed (keys `&"sprint"`, `&"noclip"`; the noclip targeting sets its −6° pull-in under `&"noclip"` and the Player releases it over 150 ms whenever `NoclipCharge` ends). `Interactable` has `prompt`, `enabled`, `condition`, `interacted`, `find_on()`.
- `Player.step_trail() -> RingBuffer` (08 Interfaces): every step, oldest first, entries `{position: Vector3, time: float (s), surface: StringName, speed_kind: &"walk"|&"sprint"|&"crouch"}`, 64 kept.
- `Player.contact_gate: Callable` `(error) -> bool`: the Director sets it to `try_contact` (10 §4); `contact()` asks it only after the player's own refusals and clamps the amount to `COHERENCE_MAX_SINGLE_HIT`. `Player.can_hide()`; `PlayerLocomotion.halt()` on every loss of agency.
- Level builder contract: wall and partition colliders carry the meta `wall_kind` (any value, e.g. `&"interior"`, `&"perimeter"`, `&"soft"`). Noise attenuation (`NoiseModel.count_walls`) counts only colliders with it; floors, props and error bodies are stepped over.
- Settings keys read by the player: `fov`, `mouse_sensitivity`, `invert_y`, `head_bob`, `screen_shake`, `sprint_mode`, `crouch_mode` (`&"hold"`/`&"toggle"`), `hold_to_press`.
- M1.4 noclip: `NoclipTargeting` (`game/src/player/noclip_targeting.gd`, the `%NoclipTargeting` child wired to the exported seam) with `cancel(silent = false)`, `reset()` (called by `reset_for_run`), `is_charging()`, `charge_fraction()`, `is_floor_solid()` (Descent depth 6 from `GameState.run`, never in Endless; an exported `floor_solid` without a run); pure validity in `NoclipQuery.evaluate(space, eye, dir, body_pos, shape, coherence, floor_solid, exclude) -> {target, valid, reason, point, normal, distance, key, landing, has_landing}`. Player signals `noclip_committed(target, from, to)` (the Director's hook, 06 §8 step 4) and `floor_drop_committed` (the run flow's hook: it calls `GameState.descend(false)` at once and owns the drop from there; unconnected, the drop respawns where the player was first seen, for direct launch and benches). NoclipTargeting calls `GameState.record_spend`, `record_wall_pass` and `record_drop` itself.
- Readings (M1.4): a wall whose far cell is not walkable in the grid (builder metadata `walkable`/`other_walkable`) is `NO SPACE` before any shape cast; reasons are checked in the order SOLID, TOO FAR, TOO THIN, NO SPACE (R6: TOO FAR first beyond 2.5 m, except ceilings); a wall target is the builder `wall_kind` `WALL`, `PARTITION`, `DOOR` (closed) or `SOFT`, anything else (or no meta) is SOLID; an upward aim that meets no collider is the ceiling (SOLID); the free-space band is measured from the aimed point along the horizontal aim to the capsule centre; the Coherence cost lands at commit (so the readout meets 50 ms), the pass and cooldown after; looking away means a different target (R6: wall kind and plane, not the collider shape; every valid floor counts as the same target); after a commit a new charge needs a fresh press; the pass ends at the found spot only if it is still free, else back at the start (R6: first a spot found again in the landing cell).
- Readings: wall attenuation of noise compounds ×0.65 per wall; wading noise is 10 m × 1.6; contact is refused during the noclip pass, the Landing and a drop; hold interactions need a fresh press; the hidden body has collision off; the crank stops at 100 and goes silent.
- R6 noclip review (2026-10-08): `NoclipQuery.evaluate(..., exclude, cache = null)` returns also `wall_kind`, `plane` (normal · point), `far_cell`, `has_far_cell`, `far_floor_y`; `NoclipQuery.same_target(a, b)` (same target id and wall kind, normals within `NOCLIP_PLANE_NORMAL_DOT`, plane within `NOCLIP_PLANE_TOLERANCE`), `far_side(info, normal)`, `is_ceiling(n)`, `cell_at(pos)`, `find_landing_cached(cache, ...)`; `find_landing(..., ref_y, shape, exclude, far)` (implemented in `NoclipLanding`, `game/src/player/noclip_landing.gd`) lands only inside the far cell, on a floor within a step of the far cell's `floor_y` (edge meta gains `floor_y`/`other_floor_y`), along the aim and then straight through. `NoclipMotion` (`game/src/player/noclip_motion.gd`) owns the pass (sine in-out) and the fall (clamped `NOCLIP_FALL_CLAMP_BELOW` under the floor, body on no layer); `NoclipTargeting.motion`, `pass_time()`. `Player.SOURCE_NOCLIP_REFUND` (`&"noclip_refund"`): no gain feedback, the HUD snaps the numeral; `Player.NO_LOSS_STATES` (Dropping, Landing). `NoclipCharge` may go to `Landing` and `Hidden` (the charge ends silently and needs a fresh press). `Exit.try_enter` refuses a player without movement (`PlayerStateMachine.has_movement()`). Door jambs carry the leaf's `closed`; a DOOR edge without `closed` (the header) is SOLID. Without a run `is_floor_solid()` reads the live `Level.data.floor_solid`. A press during the cooldown or before a fresh release shows the dashed preview, a dull tone once per hold and the arc dimmed (`noclip_state(0.15, target, false, &"")`, no reason word). The debug drop arrival calls `notify(MSG_DROPPED)` on a `Hud` bound to the player.
- M2.2 rack ruling (2026-10-08): `NoclipQuery.evaluate` also returns `pass_depth` (m the pass reaches beyond a plain wall: 2.0 through a Server rack, else 0); `NoclipQuery.far_side` answers a rack face from its box metadata (`rack`, `far_walkable`, `far_floor_y`) through `rack_far_side(info, normal, out)`: the far cell is the rack cell's neighbour along the face's inward normal. `NoclipLanding.find` starts its free-space band `pass_depth` beyond the aimed point; `NoclipMotion` keeps it for the re-check at the end of the pass.
