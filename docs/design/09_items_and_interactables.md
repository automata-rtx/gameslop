# 09 — Items and Interactables

**Depends on:** `00_OVERVIEW.md`, `02_visual_direction.md`, `03_audio_direction.md`, `04_ui_design_language.md`, `06_player.md`, `07_level_generation.md`, `08_entities.md`
**Skills to read:** `godot-inventory-system`, `godot-resource-data-patterns`, `godot-tweening`, `godot-physics-3d`
**Pulls engagement levers:** decisions every minute (spend or hold), variable reward, counters in conflict (each item interacts with specific errors).

---

## 1. Principles

- **Every item answers an error or a maze.** No item is "generic healing" except the Polaroid, and the Polaroid is the fiction's anchor, not a potion.
- **Four slots, no stacking across kinds.** The belt holds up to four kinds; each kind stacks to its cap. Picking up a fifth kind requires dropping one (prompt `[E] SWAP FOR …`). Scarcity forces choices.
- **Items are Resources.** `ItemData` defines a kind; `ItemSlot` holds `kind` and `count`. Mutable per-instance state (radio charge) lives in the slot, not the resource (horror skill rule: never mutate shared resources).
- **Use is instant or short.** No item takes longer than 1.2 s to use. Nothing pauses the world.

## 2. The six items (plus the keycard)

| Item | Cap | Use (`use_item`) | Effect | Answers |
|---|---|---|---|---|
| **Polaroid** | 3 | Hold it up: 1.2 s, the photo fills the lower half of the view, a white flash on the last frame. Cannot use while stunned or charging noclip. | +25 Coherence with the gain pulse. The photo is one of 8 procedurally drawn "real world" images (`§4`). | Everything, by refilling the dial |
| **Glowstick** | 4 | Throw (arc, 8 m at 45°, bounces once, settles). Or hold `use_item` 0.5 s to drop at the feet. | A chemical light: `OmniLight3D` `#7CFF4A`, energy 0.9, range 4 m, no shadows, 90 s, dimming over the last 20 s. Landing is an `impact` noise (6 m). Lit area counts for observing Still (`08` §4). Flicker cannot use it. Marks a junction for 90 s. | Still (observation without the flashlight), Flicker (safe light), Echo (lure), wayfinding |
| **Flare** | 2 | Strike: held, burning 40 s; `use_item` again throws it (same arc). | `OmniLight3D` `#FF4A2E`, energy 2.2, range 8 m, shadows at High, with 1 Hz brightness flutter. Continuous `light` noise 14 m. Pushes Static away (6 m). Counts for observing Still at up to 8 m. Flicker cannot use it. | Static (clears a corridor), Still (strong observation light), Echo (lure when thrown), Offices crossings |
| **Chalk** | 20 uses (one stack; a pickup adds 8 uses) | Stamp: an arrow decal on the aimed wall or floor within 2 m, pointing in the player's facing direction (yaw snapped to 45°). 0.3 s. | A `Decal` (`#F2F2F2` arrow glyph, 0.4 m, `ui_fg` with slight roughness). Persists for the level. Visible through unrender (the decal's shader ignores `u`). | Mazes (Halls, Offices cubicles, Server aisles, Substrate). The arrow's direction is the player's, so a convention emerges ("arrow points the way I came from" or "toward the exit"), and the Cartographer loadout exists for this. |
| **Radio** | 1 (3 charges of 30 s) | Toggle on/off. | Static that swells and pings faster as the player faces the exit (angle to the exit within 20°: fast ping; within 60°: slow; else: noise). Emits `radio` noise 10 m per second while on. Attracts Echo. | Wayfinding under pressure, at the cost of noise |
| **Fuse** | 1 | At an empty fuse socket (breaker Variant B): insert, 0.8 s. Can be pulled back out (0.8 s). | Powers the floor and the exit (Powered lock). Carried fuses persist across levels. | Powered exits; the Offices light dilemma (`08` §5) |
| **Keycard** | — (not a belt item) | Automatic at the reader: `[E] SWIPE`. | Opens a Keyed exit. Dropped at the end of the level. Shown as a `key` glyph beside the depth label. | Keyed exits |

### Item pool and placement
- **Notes per level:** 2 on depths 1 to 5, 1 on depth 6, drawn from the current stratum's six notes: unfound notes of the allowed tiers first (`01` §6), then, when none remain, already-found notes at half weight (so a completed stratum still has paper on the floor). Placed like items but never in the spawn room; one of the two is always within the first 40% of the critical path. A winning Descent yields about 11 notes; the Archive completes in roughly four to six runs that reach depth 4 or deeper.
- Per level: `2 + floor(depth / 2)` items (depth 1: 2, depth 6: 5), placed by Poisson selection with weights: dead ends ×3, rooms ×2, cages (Server) ×4, off-critical-path cells ×2. Plus one Polaroid guaranteed on depth 1 and one guaranteed somewhere on every even depth.
- Kind weights (base, before unlock gating): Polaroid 3, Glowstick 3, Chalk 2, Flare 2, Radio 1, Fuse 1 (only when the level's lock is Powered Variant B or the next two levels could be). Unlock gating per `05` §6. The Landing's two-item choice draws from the same weights, excluding kinds at cap and favouring kinds the player holds none of.
- Pickup: `[E] PICK UP GLOWSTICK` → the item flies to the belt slot (0.3 s tween) with the pickup tick, HUD slot pulses.
- Items in the world are primitive-built, lit by a faint `OmniLight3D` of their colour (energy 0.15, range 1 m) so they are findable in the dark, with a slow 0.2 Hz bob of 2 cm.

## 3. Held-item visuals (lower right of the viewport)

- Polaroid: a 0.09 × 0.11 m white quad with a black inner quad; on use it rises to fill the lower half.
- Glowstick: a 0.15 m green emissive cylinder with a dark cap.
- Flare: a 0.25 m dark red cylinder; burning adds the particle flame (`GPUParticles3D`, 60 particles, additive) and the light.
- Chalk: a 0.06 m white tapered cylinder.
- Radio: a 0.12 m box with a 0.1 m antenna; a small red LED when on.
- Fuse: a 0.05 m grey cylinder with brass caps.
All held items have a 0.5 s lower-in/raise-out tween and share the flashlight's bob at 60%.

## 4. Polaroid images

Eight images, generated procedurally at startup into 256 × 256 textures by `PolaroidPainter` (2D drawing into a `SubViewport`, then cached): a kitchen window with light, a street with a lamp post, a bedroom with a lamp, a tree in a yard, a bicycle against a wall, a kettle, a dog-shaped silhouette on a sofa, a hand holding a mug. They are drawn as flat-colour shapes with a warm palette and a thin white border, deliberately naive. They are the only warm, saturated images in the game until the ending. Each Polaroid pickup assigns one image by seed; the Archive's Statistics tab shows which have been seen.

## 5. Interactables (all implement `Interactable`)

| Interactable | Prompt | Behaviour |
|---|---|---|
| **Door** | `[E] OPEN` / `[E] CLOSE` | Hinged, 0.6 s swing with ease-out, blocks movement when closed. Errors open doors; a chasing error slams (door opens in 0.15 s with the slam sound). Doors never lock. A closed door breaks Still's line of sight. |
| **Breaker** | `[HOLD E] THROW BREAKER` (0.6 s) | A wall box with a lever. Throwing it: lever animates 0.3 s, the clunk, 25 m `mech` noise, the power wave from the box, exit powered. Variant B shows `[E] INSERT FUSE` if the player carries one, else `FUSE MISSING` in `ui_dim`. |
| **Fuse socket** | `[E] INSERT FUSE` / `[E] PULL FUSE` | Part of the Variant B breaker. |
| **Card reader** | `[E] SWIPE` / `NO CARD` (dim) | On the Keyed exit. Accept beep, exit opens. |
| **Exit** | none (walk-in trigger volume, `07` §6) | The stratum's exit prefab with a trigger volume; entering while open starts the 0.6 s entering tween. Status per `07` §6. Cycled exits show the countdown on a small emissive display on the frame. |
| **Hide spot** | `[E] HIDE` / `[HOLD E] LEAVE` | Under car, under desk, locker, pump room corner, rack gap. Enters hidden state (`06` §10). Each spot has a `view_position` and a `view_yaw_limit`. |
| **Vending machine** | `[E] USE` | Once per machine: 1.0 s whir, then dispenses a random item from the pool into the tray (`[E] PICK UP`). 8 m `mech` noise. The front panel is an emissive quad with a procedural grid of coloured rectangles; it hums. |
| **Payphone** | `[E] ANSWER` (only while ringing) | The Director rings it (`10`); ringing is an 18 m `door`-class noise every 6 s. Answering silences it and plays 2 s of line hum. Nothing speaks. |
| **Note** | `[E] READ` | Pickup: the sheet shows (`04` §8), `EventBus.note_found(id)`, the paper removed from the world. |
| **Landing panel** | `[1]` / `[2]` | Two-item choice in the cabin (`05` §4). |
| **Item** | `[E] PICK UP X` / `[E] SWAP FOR X` | §2. |
| **Water** | none | `Area3D` with `WATER`; the player's wading state (`06` §3). Items thrown into deep water are lost (splash). |
| **Ladder** | none | Prop only; not climbable. The steps are the way. |

## 6. Hide spots

- **Under car (Garage):** the player slides under (0.6 s), camera at 0.35 m, view toward one side, yaw ±35°. Still's feet are visible when it passes (the column's bottom 0.4 m).
- **Under desk (Offices):** camera at 0.5 m behind the desk's modesty panel, view through the 0.3 m gap at the floor.
- **Locker (Offices closets, Halls closets):** door closes with a click; slatted view (a shader mask of 6 horizontal slits); yaw ±35°.
- **Pump room corner (Pools):** the room's door closes; view at the door's small window.
- **Rack gap (Server):** a 1-cell nook; view along the aisle; the LEDs light the player's hands (none visible; the HUD dims).
- Rules: entering requires no error within 3 m; errors that saw the player enter know the spot (`08`). Leaving is a 0.6 s hold. The player's breathing is audible inside and is not a noise event (hiding is silent to errors).

## 7. Props (per stratum, built from primitives, placed by `07`)

Halls: `vending`, `payphone`, `chair`, `wall_clock` (hands frozen at a hashed time). Pools: `ladder`, `lifeguard_chair`, `lane_rope`, `drip`. Garage: `car` (4 palette colours), `barrier`, `pillar`, `exit_sign`. Offices: `desk`, `monitor`, `chair`, `filing_cabinet`, `water_cooler`, `breaker_box`, `locker`. Server: `rack`, `fan_grille`, `cable_tray`, `emergency_box`. Substrate: `studio_light`, `scaffold` (wireframe box), `threshold_door`. Shared: `door`, `fixture_*`, `elevator`, `stairwell_door`, `drain_hatch`, `floor_hatch`, `landing_cabin_*`.

Every prop is a scene under `game/scenes/props/<stratum>/` using `MeshInstance3D` primitives (`BoxMesh`, `CylinderMesh`, `CapsuleMesh`, `PlaneMesh`) with the world shader material (and the small prop shaders from `02` §7) and a `StaticBody3D` with box or cylinder shapes where the player can touch it. Props never use imported meshes (visual target T8).

## 8. Soft walls

Not interactable: the generator marks `SOFT` edges (`07` §4) and the builder sets the wall's material uniform `soft = 1.0` on that segment's quad (the merged mesh splits soft segments into their own surface so the uniform can differ). The shimmer (`02` §5) is the only signal. Noclip through a soft wall is cheaper and faster (`06` §8). Soft walls are the generator's authored shortcuts, so every one of them saves ≥ 20 m.

## 9. Chalk and decals

- `ChalkDecal`: a `Decal` node with the arrow texture (hand-written SVG rasterised at import, 256 px), size 0.4 × 0.4 × 0.1 m, albedo `#F2F2F2`, emission 0.15 so it is readable in the dark, `cull_mask` set to render on world geometry only. Max 40 decals per level (oldest removed).
- The decal shader is the default `Decal`; unrender does not affect decals because `Decal` is not the world shader, which is the behaviour we want.

## 10. Verification

- Unit tests: belt rules (four kinds, caps, swap), Polaroid gain and use lockouts, radio ping angle bands and charge, glowstick timers, flare push on Static, fuse insert/pull state, keycard non-slot behaviour.
- `game/scenes/debug/items_bench.tscn`: all items and interactables spawned in a room with Still and Flicker spawn buttons for interaction tests.

## Interfaces

- `ItemData` resource: `kind: StringName`, `display_name: String`, `glyph: Texture2D`, `cap: int`, `use_time: float`, `held_scene: PackedScene`, `world_scene: PackedScene`, `weight: int`, `unlock_id: StringName`.
- `ItemSlot`: `kind`, `count`, `state: Dictionary` (radio charge, flare burning, fuse).
- `Inventory` (on the player): `add(kind, count) -> bool`, `remove(kind, count)`, `select(index)`, `use_selected()`, `has(kind) -> bool`, signal `changed(slots, selected)`.
- `Interactable` component: `prompt_text() -> String`, `can_interact(player) -> bool`, `hold_time: float`, `interact(player)`.
- `EventBus.item_used(kind)`, `EventBus.item_picked(kind)`, `EventBus.note_found(id)`, `EventBus.breaker_thrown(pos)`, `EventBus.exit_status_changed(status, timer)`, `EventBus.hide_state(on)`.

### Interface additions during production
- `Inventory.add(kind, count = 1, state = {}) -> int` returns the number accepted (0 when refused), replacing the `-> bool` of the list above; `remove(kind, count) -> int`; `consume(kind, count)` (remove, then `EventBus.item_used`); `swap_in(kind, count, state, index = selected) -> ItemSlot` (returns the stack it replaced); `can_accept(kind)`, `count_of(kind)`, `select_step(+-1)`, `selected_slot()`, `reset(items)`, `snapshot()`, `feed_use(pressed, held, dt)` (the Player calls it each physics frame), `Inventory.of(node)`. `slots` is always four entries, each an `ItemSlot` or null; `selected` is 0 to 3. The Player owns it as `%Inventory` (`Player.inventory`).
- `ItemSlot` is a `RefCounted` with `kind`, `count`, `state`. Polaroid slots keep `state.images` (the photo indices, oldest used first).
- Behaviours live in `game/src/items/items/` as `ItemBase` children of the Inventory (`PolaroidItem`, `ChalkItem`, `GlowstickItem`); Flare, Radio and Fuse add theirs in M2.8. Held and world models are built by `ItemModels` (no `held_scene` is authored). `ItemData.world_scene` is the `ItemPickup` scene (`scenes/items/pickup_<kind>.tscn`); only the three M1 kinds have one, and `ItemSpawner` skips placements of kinds without it.
- World pickups sit on physics layers 4 (`interactable`, the ray's layer) and 5 (`items`). `ItemPickup`, `NotePickup` and `ItemSpawner.populate(level_root, level_data, rng, options)` are the level builder's calls; `options` takes `found` (note ids) and `stratum_reached` (tier 2 allowed), defaulting from `GameState.meta` (`stats.strata_reached`, else any found note of the stratum).
- Glowsticks (and later flares) put their `OmniLight3D` in group `chemical_light`; `Glowstick.is_lit(tree, pos, grid = null)` is the predicate (inside any such light's range with a clear grid line, `SightOps`; the grid defaults to the live level's), registered on the Player with `add_light_query`. A stick's light node is hidden while the stick is out of grid view of the camera (`Glowstick.update_view(grid, eye)`); the predicate ignores that visibility. Chalk decals are `ChalkDecal` (group `chalk`).
- Tuning additions: `POLAROID_FRAMES_TIME` 0.4, `GLOWSTICK_BOUNCE` 0.35. (`POLAROID_CONE_DEG` and `POLAROID_RANGE` were removed with the `on_polaroid` hook: no error reacts to the Polaroid.)
- Sound ids: `item_pickup`, `note_pickup`, `polaroid_charge`, `polaroid_shutter`, `glowstick_crack`, `glowstick_fizz` (loop), `glowstick_land`, `chalk_mark`.
- Readings: the Polaroid is spent on the flash, so a stun or noclip charge mid-use cancels it for free; use_item on a Glowstick acts on release (a tap throws, a 0.5 s hold sets it down silently); chalk on a wall points up when the player faces the wall and turns left or right with the snapped angle of the facing to the wall; a stack at its cap cannot be picked up, a partly fitting pickup leaves the remainder in the world.
- R4 (2026-10-08): `Inventory.can_swap_out(index = selected)` (the old kind has a world scene); a swap is refused otherwise (`ItemPickup.can_take` false, `swap_in` null). `ItemSlot.accepted_state(state, n)` / `remaining_state(state, n)`: a partly fitting pickup moves only the accepted Polaroid photos. Pickups rest with their lowest point 3 cm above the floor at the bottom of the bob (`ITEM_WORLD_REST_HEIGHT`), jittered ±0.35 m in the cell with a random yaw from the placement rng (`ITEM_PLACE_JITTER`); `ItemSpawner` push_errors when a fuse placement would be skipped. Item world and held models use the world shader (`ItemModels.material`, `ItemModels.set_held`; held = 1 in hand); the Polaroid held up and chalk decals are the exceptions. A glowstick set down makes no sound. Chalk at nothing in reach: a dull tick (`ui_hold_tick` pitched down), the hand jabs, a 0.3° nod, nothing spent; a stamp on a moving body (a door leaf) is its child. Item select also bobs the hand one cycle (12 mm, 300 ms) and nods the view 0.3° (`CameraRig.nod`). Held models live in `HeldHand` (`game/src/items/held_hand.gd`), owned by the Inventory.
- M1.9 `Exit` (`src/interactables/exit.gd`, prefab `scenes/exits/elevator.tscn`, group `exits`): `lock`, `status`, `is_seen`, `set_lock(kind)`, `open()`, `seal()`, `power()`, `is_open()`, `try_enter(player) -> bool`, `mark_seen()`, `check_seen(camera)`, `entry_transform()`, `accepting`; signals `status_changed(status)`, `seen`, `entering(player)`. `Breaker` (`src/interactables/breaker.gd`, `scenes/interactables/breaker.tscn`, group `breakers`): `variant`, `is_thrown`, `fuse_in`, `throw_breaker() -> bool`, signal `thrown(pos)`, static `wave_delays(grid, from_cell, positions) -> PackedFloat32Array` (12 m/s by walking distance, 40 ms stagger). `LandingPanel` (`src/ui/landing_panel.gd`): `setup(kinds, gain, hint)`, `choose(index) -> bool`, signal `chosen(kind)`. The Landing offers only kinds with a world scene (M1: Polaroid, Glowstick, Chalk).
- M2.8 (every item and hide spot is real; additive, no number moved):
  - `ItemData.world_scene` exists for all six belt kinds and the keycard; the Landing, `RunLevelSetup.item_pool` and `ItemSpawner` offer and spawn every kind. `ItemSpawner.populate` also spawns one `KeycardPickup` per `P_KEYCARD` placement; `RunLevelSetup.prepare` frees those markers.
  - `FlareItem` / `Flare` (`src/items/items/flare_item.gd`, `flare.gd`): use_item strikes (slot `state.burn` = seconds left, 40 s), again throws (`ItemThrow.plan`, 8 m at 45 degrees; a 0.3 s lockout after the strike); a burnt-out flare, or one thrown, spends one of the stack. `Flare` is a `RigidBody3D` on layer 8 in group `flares_burning` (`Tuning.STATIC_FLARE_GROUP`), its `OmniLight3D` in `chemical_light` (energy 2.2 with a 1 Hz flutter of +-15%, range 8 m, shadows only at the High `shadow_quality`, dying down over the last 1.5 s), a 60-particle additive flame, a 14 m `light` noise each second, a 6 m `impact` on landing. Carried it follows the hand's tip (the hip when another item is in hand); a flare does not survive leaving the level; swapping the stack out puts it out.
  - `RadioItem` (`radio_item.gd`) / `RadioPickup` (`src/items/radio_pickup.gd`): tap toggles (slot `state.on`, `state.charge` = seconds left of 90). On: a 10 m `radio` noise (`Tuning.NOISE_KIND_RADIO`, Echo lures on it) each second, the static loop `radio_static` with its level by the angle to the nearest node in group `exits` (`band(angle)`: `fast` within 20 degrees, `slow` within 60, else `noise`; pings 0.35 s / 1.0 s, no ping off-axis), the model's LED lit. A spent radio leaves the belt; the level ending switches it off. Reading (09 says toggle, the brief says lure): holding use_item 0.5 s sets the radio down where it stands, still playing, as a `RadioPickup` (the same mech noise, a positional static loop, the charge draining); `[E] PICK UP` takes it back switched off with what is left; a dead one cannot be taken.
  - `FuseItem`: use_item with nothing to put it in is only a nudge and a pitched-down `ui_hold_tick`. `Breaker.insert_fuse(player)`, `Breaker.pull_fuse(player)`: a small socket collider (`%Socket`, `%SocketInteractable`) offers `[HOLD E] PULL FUSE` (0.8 s) on a Variant B box with the fuse in, when the belt can take it, before or after the throw (R15: after the throw it trips the breaker, `Breaker.power_cut(pos)`; the run's `RunLevelSetup.cut_power` unpowers the fixtures the wave lit and `Exit.unpower()` seals a Powered exit back to EXIT: POWERED; inserting it again re-runs `throw_breaker()`; `Exit.power_after(delay)` carries the wave to the exit). The fuse shows in the socket while it is in.
  - Keycard: `Inventory.keycard: bool`, `Inventory.set_keycard(on)`, signal `Inventory.keycard_changed(has_card)`; cleared by `reset()` and by `EventBus.level_left`. `KeycardPickup` (`scenes/items/pickup_keycard.tscn`) sets it; its card pulses in ui_accent and is drawn out to 20 m. `CardReader` (`src/interactables/card_reader.gd`, `scenes/interactables/card_reader.tscn`, group `card_readers`): `[E] SWIPE` with the card, `NO CARD` (dim) without; `swipe(player) -> bool`, signals `swiped(player)` (accepted, once; M2.9 connects it to `Exit.open`) and `rejected(player)`; it does not take the card.
  - `Vending` (script on `scenes/props/halls/vending.tscn`, group `vending_machines`): `[E] USE`, once; an 8 m `mech` noise and `vending_whir`, then after `VENDING_WHIR_TIME` an `ItemPickup` appears at `%TrayPoint`. The kind is drawn from `RunLevelSetup.item_pool` by `ITEM_WEIGHT` with a rng seeded from the level seed and the machine's position (`Vending.rng_for`, `Vending.pick_kind`), never a fuse (the generator places those). `Payphone` (script on `payphone.tscn`, group `payphones`): `ring(seconds = 30) -> bool`, `answer(player) -> bool`, `tick(dt)`, signals `ringing_changed(on)` and `answered`, static `Payphone.candidates(tree, from)` (not ringing, 15 to 40 m, nearest first) for the Director. `[E] ANSWER` only while ringing; each ring (2 s on, 4 s off) is an 18 m `door` noise at its start; answering plays `payphone_line` (2 s). `Scares.request(PAYPHONE)` is not wired (the Director's).
  - Hide spots: `HideSpot` kinds `locker`, `under_car`, `under_desk` (placement kind `desk` also maps), `pump_corner`, `rack_gap`, one scene each under `scenes/interactables/hide_spot_<kind>.tscn` (a scene looks out along -Z, the locker +Z; `LevelPlacer` orients an `under_car` spot by the placement's `dir`, the aisle side of the car, and calls `HideSpot.configure(params)` for `view_yaw_limit`). View heights: car 0.35 m (under the 0.4 m belly), desk 0.5 m, pump corner 1.1 m, rack gap 1.5 m. Masks (`HideSpot.MASK_CLEAR`): locker six slits, desk a floor-level band, pump corner the door's small window; car and rack gap none. An `under_desk` host expects the desk prop's modesty panel not to block the 0.5 m eye line. Sounds `hide_<kind>`.
  - Tuning (task constants): `RADIO_PING_FAST_INTERVAL` 0.35, `RADIO_PING_SLOW_INTERVAL` 1.0, `RADIO_NOISE_INTERVAL` 1.0, `RADIO_PUT_DOWN_HOLD`, `RADIO_GAIN_FAR_DB` -14, `FLARE_STRIKE_LOCKOUT` 0.3, `FLARE_FADE_TIME` 1.5, `FLARE_FLUTTER_DEPTH` 0.15, `HIDE_PUMP_CORNER_EYE_HEIGHT` 1.1, `HIDE_RACK_GAP_EYE_HEIGHT` 1.5.
  - Sound ids: `flare_ignite`, `flare_burn` (loop), `flare_land`, `radio_static` (loop), `radio_ping`, `fuse_insert`, `fuse_pull`, `keycard_accept`, `keycard_reject`, `vending_hum` (loop), `vending_whir`, `payphone_ring`, `payphone_line`, `hide_locker`, `hide_under_car`, `hide_under_desk`, `hide_pump_corner`, `hide_rack_gap`.
- R19 (14 §10 nodes in a level; behaviour and look unchanged): a hide spot's eye and exit are `HideSpot.view_offset` and `exit_offset` (transforms local to the host) instead of `ViewPoint`/`ExitPoint` marker nodes; `view_transform()` and `exit_transform()` are the API. The under-desk host is itself the kneehole `StaticBody3D` (layer 4) with its shape and `Interactable`: 3 nodes (was 6). `ItemSpawner.populate_steps(root, data, rng, out, options)` is `populate` as steps (the run spreads them over frames).
- M2.9 exits and locks (additive; no number moved):
  - Exit prefabs per `exit_kind` (`RunLevelSetup.EXIT_SCENES`, `exit_scene_for(kind)`): `scenes/exits/elevator.tscn` (Halls, Offices), `drain_hatch.tscn` (Pools, a chrome-framed grate in the dry basin floor that lifts open over a lit shaft), `stairwell_door.tscn` (Garage, a steel door with push bar and wired-glass window that swings out onto the lit stair flight, below the green exit sign), `floor_hatch.tscn` (Server, a raised-floor hatch with an amber edge). Hatches carry an exit post (lamp, Cycled display, reader mount). `threshold_door` (Substrate) is a hook: the elevator stands in until `scenes/exits/threshold_door.tscn` exists (M2.15).
  - `Exit` additions: exports `exit_kind`, `sound_open` (`exit_open`, `exit_open_door`, `exit_open_drain`, `exit_open_hatch`), `leaf_motion` (`slide` with %DoorL/%DoorR or `hinge` with %Leaf and `hinge_open_deg`), `lamp_on`, `interior_on`, `button_on`, `light_on`, `entry_offset`; optional nodes %Leaves, %Interior, %Lamp, %CallButton, %Display (Label3D countdown, Cycled), %ReaderMount, %ReaderPost. `reader` (the Keyed exit's own `CardReader`, whose `swiped` opens it), `start_cycle()` (the run calls it on arrival), `advance_cycle(dt)`, `cycle_running`, `cycle_left`, `status_timer()`, `walk_in_point()`, `approach_point(dist)`, `leaf_open_amount()`. `exit_status_changed(status, timer)` carries the Cycled phase's seconds left. Keyed starts lit and closed (`EXIT: KEYED`); Cycled starts sealed for a full 70 s from arrival, plays `exit_tone` 5 s before each opening and as its seen sound, seals with the latch, and never seals while the player is being carried in. A Powered or Keyed unlock is announced even unseen; a Cycled opening only once seen.
  - `CardReader`: a rejected swipe also blinks the indicator red twice with the two beeps; `indicator_glow()`.
  - `Run.fuse_unlocked(meta, daily)` (unlock #4, or Daily) feeds `fuse_unlocked`; `Run.generation_overrides` (tests). Bench `scenes/debug/exits_bench.tscn` (`-- --exit-shots <dir>`).
