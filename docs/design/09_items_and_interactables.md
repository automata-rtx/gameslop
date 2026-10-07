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
| **Chalk** | 10 uses per stick, 2 sticks | Stamp: an arrow decal on the aimed wall or floor within 2 m, pointing in the player's facing direction (yaw snapped to 45°). 0.3 s. | A `Decal` (`#F2F2F2` arrow glyph, 0.4 m, `ui_fg` with slight roughness). Persists for the level. Visible through unrender (the decal's shader ignores `u`). | Mazes (Halls, Offices cubicles, Server aisles, Substrate). The arrow's direction is the player's, so a convention emerges ("arrow points the way I came from" or "toward the exit"), and the Cartographer loadout exists for this. |
| **Radio** | 1 (3 charges of 30 s) | Toggle on/off. | Static that swells and pings faster as the player faces the exit (angle to the exit within 20°: fast ping; within 60°: slow; else: noise). Emits `mech` noise 10 m per second while on. Attracts Echo. | Wayfinding under pressure, at the cost of noise |
| **Fuse** | 1 | At an empty fuse socket (breaker Variant B): insert, 0.8 s. Can be pulled back out (0.8 s). | Powers the floor and the exit (Powered lock). Carried fuses persist across levels. | Powered exits; the Offices light dilemma (`08` §5) |
| **Keycard** | — (not a belt item) | Automatic at the reader: `[E] SWIPE`. | Opens a Keyed exit. Dropped at the end of the level. Shown as a `key` glyph beside the depth label. | Keyed exits |

### Item pool and placement
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
| **Exit** | `[E] DESCEND` (when open) | Trigger volume plus the stratum's exit prefab. Status per `07` §6. Cycled exits show the countdown on a small emissive display on the frame. |
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
- **Locker (Offices closets, Halls closets):** door closes with a click; slatted view (a shader mask of 6 horizontal slits); yaw ±20°.
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
- `EventBus.item_used(kind)`, `EventBus.item_picked(kind)`, `EventBus.note_found(id)`, `EventBus.breaker_thrown(pos)`, `EventBus.exit_status_changed(status)`, `EventBus.hide_state(on)`.
