# 07 — Level Generation

**Depends on:** `00_OVERVIEW.md`, `01_fiction_and_tone.md`, `02_visual_direction.md`, `05_run_structure_and_progression.md`, `06_player.md`
**Skills to read:** `godot-procedural-generation`, `godot-3d-world-building`, `godot-navigation-pathfinding`, `godot-ai-navigation`, `godot-performance-optimization`, `godot-genre-roguelike` (seeded RNG, run state), `godot-testing-patterns`
**Pulls engagement levers:** variable reward (exploration pays), readable rules (each stratum has a layout grammar), fairness contract (validation), push your luck (soft walls and drops are generator-authored choices).

---

## 1. Principles

1. **Grammar, not noise.** Each stratum has a layout grammar a player can learn: Halls are a braided maze with rooms; Pools are big halls on a spine; Garage is an open deck with pillars and cores; Offices are rings around cubicle mazes; Server is parallel aisles; Substrate is Halls or Offices with pieces missing. Learning the grammar is progression.
2. **The level is data first.** Generation produces a `LevelGrid` and a `Placements` list on a worker thread. Building nodes happens on the main thread in time slices. Every consumer (navigation, Director, noclip validation, exit status, minimap-free wayfinding through fixtures) reads the grid, never the scene tree.
3. **Edge walls.** Walls live on cell edges, 0.2 m thick. This makes every interior wall thin enough to noclip, makes thickness explicit, and lets the generator mark walls `SOLID`, `WALL`, `SOFT`, `PARTITION`, or `DOOR`.
4. **Deterministic.** One `RandomNumberGenerator` per level seeded by `Seeds.derive(run_seed, "depth:%d" % depth)` (`tuning.gd`: `derive(base: int, label: String) -> int` = `hash("%d:%s" % [base, label])`), with derived sub-seeds (`Seeds.derive(level_seed, "layout")` and so on) for layout, placement, props, and fixtures, so the same seed always builds the same level and a tuning change in props does not reshuffle the maze.
5. **Validated or rejected.** A level that fails validation (§8) is regenerated with `sub_seed + 1`, up to 8 attempts, then falls back to the stratum's simplest grammar. The build never ships an invalid level.

## 2. Grid model

- **Cell:** 2 m × 2 m in XZ. Cell `(x, z)` has world origin `(x × 2, 0, z × 2)`. Heights per stratum (§5).
- **`LevelGrid`** (pure data class, no nodes): `size: Vector2i`, `cells: PackedByteArray` (kind per cell), `room_id: PackedInt32Array` (−1 corridor, else room index), `floor_y: PackedFloat32Array` (per cell floor height; 0 default; Pools basins negative; Garage deck 1 at +3.2; Substrate offsets), `walls: PackedByteArray` (4 entries per cell, one per direction N E S W, sharing edges with neighbours; writes go through `set_wall(cell, dir, type)` which updates both sides), `deck: PackedByteArray` (Garage only; 0 or 1), `flags: PackedInt32Array` (bit flags: `WATER`, `UNFINISHED`, `NO_SPAWN`, `CRITICAL_PATH`, `EXIT_ROOM`, `SPAWN_ROOM`, `LOCK_ROOM`, `HIDE_SPOT_HOST`, `DEAD_END`).
- **Cell kinds:** `VOID` (not walkable, not built), `FLOOR` (corridor), `ROOM` (room interior), `RAMP` (Garage, carries a slope direction), `BASIN` (Pools, sunken), `RACK` (Server, built as a rack block, not walkable).
- **Wall types:** `NONE`, `WALL` (passable by noclip), `SOLID` (perimeter or structural core; not passable), `SOFT` (cheap noclip, shimmer), `PARTITION` (1.5 m high cubicle wall: blocks movement, not standing sight), `DOOR` (a door prefab in the edge; walkable when open), `GLASS` (Offices meeting rooms: blocks movement, not sight, not passable by noclip because it is `SOLID` for the shader rule; keep rare).
- **Rooms:** `rooms: Array[RoomData]` with `rect: Rect2i`, `kind` (`generic`, `spawn`, `exit`, `breaker`, `closet`, `pool_hall`, `pump`, `office_open`, `office_small`, `meeting`, `cage`, `pocket`), `fixture_group: int`.
- **`Placements`:** list of `{kind: StringName, cell: Vector2i, offset: Vector3, yaw: float, params: Dictionary}` for props, items, notes, hide spots, fixtures, error spawn points, the exit, lock objectives, water volumes, soft wall previews, studio lights, chalk-ready surfaces.

Grid sizes per depth: 1: 24×24, 2: 28×28, 3: 32×32, 4: 34×34, 5: 36×36, 6: 28×28. Walkable cell targets (validation asserts within ±25%): 1: 300, 2: 380, 3: 460, 4: 520, 5: 580, 6: 360. Cycle 2 adds +2 to each dimension.

## 3. Pipeline

```
seed ─► Layout(stratum) ─► Rooms + Corridors + Walls ─► Decks/Basins/Heights
     ─► Critical path (BFS spawn→exit)  ─► Lock objective placement
     ─► Soft walls ─► Hide spots ─► Items, notes ─► Props ─► Fixtures + groups
     ─► Error spawn points ─► Validate ─► (reject → retry) ─► Build (main thread, sliced)
     ─► Collision ─► Navigation bake (threaded) ─► LightPool register ─► ready
```

Stage timings must fit the 6 s Landing (`05` §4): layout and placement under 300 ms on the worker thread; build sliced at 4 ms per frame; navigation bake asynchronous; a level is "ready" when the bake completes. If the Landing's 6 s or a drop's 1.2 s elapse before ready, the cabin door stays shut (the cabin keeps shuddering) or the arrival black holds, until ready (max 3 s extra, then arrive with navigation pending; errors stay dormant until the bake finishes).

## 4. Shared layout operations (library, `game/src/levelgen/ops/`)

- `carve_rooms(grid, count_range, size_range, margin, rng)`: jittered-grid placement of non-overlapping rectangles with 1-cell gaps; returns rooms.
- `maze_fill(grid, region, rng)`: recursive backtracker over odd coordinates within a region, producing 1-cell corridors with walls on edges; bounded iteration.
- `braid(grid, fraction, rng)`: removes dead ends by opening a wall to an adjacent corridor cell for `fraction` of dead ends; marks remaining `DEAD_END`.
- `connect_rooms(grid, rooms, doors_per_room_range, rng)`: opens `DOOR` or `NONE` edges between a room and adjacent corridors; guarantees at least one.
- `bsp_split(region, min_size, rng) -> Array[Rect2i]`: binary space partition.
- `spine_and_branches(grid, rng)`: one long corridor across the grid with branches (Pools).
- `critical_path(grid, from, to) -> Array[Vector2i]`: BFS over walkable cells respecting walls and doors; marks `CRITICAL_PATH`.
- `distance_field(grid, from) -> PackedInt32Array`: BFS distances for placement weighting.
- `pick_far_cell(grid, dist, min_fraction, filter)`: a cell at ≥ `min_fraction` of the maximum distance.
- `mark_soft_walls(grid, count, min_saving_m, rng)`: for candidate `WALL` edges between two walkable cells whose walking distance exceeds `min_saving_m`, mark `SOFT`; prefer those near dead ends; never on the exit room or perimeter.
- `poisson_cells(grid, filter, min_spacing, rng)`: Poisson-disk cell selection for props and items (procedural generation skill rule: never pure random).

## 5. Stratum grammars

Each grammar is a `StratumGenerator` subclass implementing `layout(grid, rng)` and `decorate(grid, placements, rng)`. Values here are initial tuning in `StratumData`.

### 5.1 Halls (height 3.0 m)
- `carve_rooms`: 5 to 8 rooms, 3×3 to 6×5, margin 2. Room kinds: `spawn` (3×3, on the perimeter, attached to the Landing cabin), `exit` (3×3), `breaker` (2×2) when Powered, 1 to 2 `closet` (1×1 with a `DOOR`, hide spot host), rest `generic`.
- `maze_fill` the remainder; `braid` 0.15. Corridors are 2 m wide, 3 m high. Long straight runs are encouraged: after the maze, straighten 10% of corridor turns by opening the wall ahead if it joins a corridor (produces the signature long hallway).
- Props in generic rooms: 0 to 2 from `vending`, `payphone`, `chair`, `wall_clock`. Corridors: none, except one `payphone` per level on a corridor wall.
- Fixtures: ceiling tubes every 2 cells along corridors (centred), rooms 1 per 2×2. Groups: one per corridor segment between junctions (max 6 fixtures) and one per room.
- Soft walls: 4 (depth 1 first run: one guaranteed on the critical path within 60 s of walking).
- Hide spots: closets (2).
- Exit: `elevator` in the exit room's perimeter wall. Lock per §6.

### 5.2 Pools (height 6.0 m)
- `spine_and_branches`: a main 1-cell corridor across the long axis with 3 to 5 branches; `bsp_split` the remaining space into 6 to 9 `pool_hall` rooms of 8×6 to 14×10 attached to the spine or a branch by a 1-cell doorway (no door prefab, an open tiled arch).
- Each pool hall gets a `BASIN`: inner rect inset by 2 cells, `floor_y` −0.6, −1.2, or −1.8 (rng), `WATER` flag with water surface at `floor_y + fill` where fill ∈ {0 (dry), 0.5 (shallow), basin depth (full)} weighted 30/40/30. One side of the basin has a 2-cell `RAMP` of steps (built as a stepped mesh with step 0.25 m) and ladders (`ladder` prop) on two edges. Full basins deeper than 1.2 m are impassable except by the steps (wading depth limit 1.3 m; deeper is modelled as `SOLID` for movement).
- 1 to 2 `pump` rooms (2×2, `DOOR`), hide spot hosts. When the lock is Powered, one pump room is also the `breaker` room (the breaker box on its wall).
- `spawn` room: a 3×3 tiled antechamber on the perimeter attached to the stairwell landing; `exit` room: the exit hall.
- Props: ladders, `lifeguard_chair` (1 per 3 halls), `lane_rope` floating in full basins, drips at hashed ceiling points.
- Fixtures: ceiling panels every 3 cells in halls, every 2 cells in corridors. Groups per hall.
- Soft walls: 3, between adjacent halls.
- Exit: `drain_hatch` at the bottom of a **dry** basin in the exit hall (the generator forces the exit hall's basin dry and 1.8 m deep). Players descend the steps into the empty pool to leave.

### 5.3 Garage (height 3.2 m per deck, two decks)
- Two deck grids of equal size (`deck` 0 and 1). Each deck: perimeter `SOLID`; pillars (`VOID` 1×1 with a pillar mesh) every 4 cells in both axes; 3 to 5 interior wall strips (`WALL`, 4 to 10 cells long) to break sightlines; two `SOLID` **cores** (3×3) per deck at the same positions on both decks, one holding the stairwell exit (on deck 0), the other a `breaker` room when Powered.
- Two to three `RAMP` runs connect the decks: 4 cells long, straight, 1 cell wide, with low `WALL` edges; placed against the perimeter.
- Parking bays: cells adjacent to interior strips and the perimeter are bays; `car` props fill 35% of bays (Poisson, min spacing 1 cell), each a hide spot host (`under_car`). `barrier` props at 10% of bay ends.
- Fixtures: sodium cage lamps on pillars every 4 cells (one per pillar face facing the longest open run). Groups: 4×4-cell quadrants.
- `spawn` room: a 3×3 elevator lobby on deck 1 (walled, one opening) attached to the Landing cabin; `exit` room: the 3×3 core on deck 0 holding the stairwell door. Spawn on deck 1, exit on deck 0 (so every Garage level requires finding a ramp). Keycard (when Keyed) on the other deck from the exit.
- Soft walls: 3, on interior strips only. Cores are `SOLID`.
- Exit: `stairwell_door` in a core, with an `exit_sign` prop above it (the only green light in the stratum, visible across the deck).

### 5.4 Offices (height 3.0 m)
- A corridor **ring** 1 cell wide inset 3 cells from the perimeter, plus 1 to 2 cross corridors. `bsp_split` the outside band and the interior into rooms: 2 to 3 `office_open` (10×8 to 14×10), 6 to 10 `office_small` (3×3 to 5×4, `DOOR`), 1 `meeting` (5×4, `GLASS` on the corridor side), 1 `breaker` (2×2) when Powered, 1 to 2 `closet` (lockers, hide spot host).
- `office_open` interiors: `maze_fill` with `PARTITION` walls, `braid` 0.35, then place `desk` + `monitor` in 60% of cubicle cells, each desk a hide spot host (`under_desk`). Chairs are placed **only in corridors** (Poisson, spacing 3 cells, facing random).
- Lighting state: **40% of fixture groups start dark** (unpowered). Throwing the breaker (Powered lock) powers the whole floor with the power wave (`02` §6), which also gives Flicker more groups to live in. If the lock is not Powered, a breaker still exists (so the player can choose to light the floor) but is not required.
- Fixtures: troffers every 2 cells in corridors and open offices, 1 per small office. Groups: per room; corridors in 6-fixture segments.
- Props: `filing_cabinet`, `water_cooler` (corridor junctions), `breaker_box` on the breaker room wall, `chair`.
- Soft walls: 4, between small offices and the ring.
- Exit: `elevator` on the ring's outer band.

### 5.5 Server (height 3.5 m)
- Rows of `RACK` blocks: each row 6 to 12 cells long, 1 cell wide, with 1-cell aisles between rows; cross aisles every 6 to 10 cells; 2 to 4 `cage` rooms (4×4, fenced with `GLASS`-like mesh fences that block movement and allow sight, with a `DOOR` gate) containing an item each; 1 `breaker` room when Powered; corridors around the perimeter.
- Racks are placed in a staggered pattern so no aisle is straight for more than 12 cells.
- Fixtures: none overhead; `emergency_box` red lights at aisle ends every 6 cells, rack LEDs per rack face (`02` §7). Groups: per aisle (Flicker uses emergency boxes and rack LEDs).
- Props: `fan_grille` on the ceiling every 5 cells, `cable_tray` along aisle ceilings (visual), `rack_gap` hide spots: 3 per level, a 1-cell nook between two racks with a `HIDE_SPOT_HOST`.
- Soft walls: none (racks are not walls). Noclip through a `RACK` cell is allowed as `WALL` (racks are 1 m deep; the shape cast decides).
- `spawn` room: a 3×3 stairwell landing on the perimeter; `exit` room: a 3×3 clearing at the end of an aisle holding the `floor_hatch`, lit by one white light.

### 5.6 Substrate (height 3.0 m)
- Run the Halls grammar at 28×28 (Cycle 2: Offices grammar alternates), then **unfinish**:
  - Remove 20% of corridor cells in 2 to 5-cell clusters (set `VOID`), re-validate connectivity, reinsert the minimum cells to reconnect (BFS repair).
  - Mark 30% of built surfaces `UNFINISHED` (placeholder checker), by room or corridor segment, never partially.
  - Offset `floor_y` of 25% of rooms by +0.25 or −0.25 m with short ramps at doorways (within the step height).
  - Replace all fixtures with none; place 6 to 10 `studio_light` at random walkable cells ≥ 6 cells apart; the exit pocket always has one.
  - Edges to `VOID` become `SOLID` and are drawn as the brighter grid (invisible walls in fiction, visible lines in render).
- `spawn` room: the Halls grammar's spawn room, kept finished (no `UNFINISHED`, no `VOID`) with a studio light. The **Threshold** is the exit: a `threshold_door` prefab at the far end of the critical path in a `pocket` room (3×3, lit). The critical path from spawn to Threshold is forced to ≥ 140 m and ≤ 220 m of walking (`05` §9 rule 8 is about Null's pressure, not distance).
- Null's spawn point: the cell on the critical path at 55% distance from spawn, at least 20 m from the player (fairness rule), dormant for the calm window (`10`). Static ×2 off the critical path.
- No lock. No hide spots. Soft walls: 6 (the Substrate is where noclip is most useful; the shader shows them clearly).

## 6. Exits and locks

| Lock | Mechanic | HUD status | Where it may appear |
|---|---|---|---|
| **Open** | Walk in. | `EXIT: OPEN` | Depth 1 (not first run), 2, 3; Depth 6 always |
| **Powered** | The exit is dark and dead until the level's `breaker` is thrown (hold `interact` 0.6 s). Throwing it emits a 25 m noise, runs the power wave, and powers the exit. Variant B (after unlock #4, 50% of Powered): the breaker has an empty fuse socket; **exactly one `fuse` item is always placed in the level**, reachable on foot (validation rule 3 covers it), at 35% to 70% critical-path distance; a player who already carries a fuse can skip the search. | `EXIT: POWERED` then `EXIT: OPEN` | Depths 1 to 5 |
| **Keyed** | The exit has a card reader; a `keycard` item (glowing, visible from 20 m by a pulsing `ui_accent` emissive) is placed at 35% to 70% critical-path distance, off the direct path when the grammar allows. The keycard occupies no belt slot (it is a key, shown next to the depth label as a `key` glyph). | `EXIT: KEYED` then `EXIT: OPEN` | Depths 2 to 5 |
| **Cycled** | The exit opens on a schedule: sealed 70 s, open 20 s, with an audible signal 5 s before opening (a long tone from the exit, `max_distance` 60 m, heard through walls) and the seal/unseal sounds. | `EXIT: SEALED 00:42` / `EXIT: OPEN 00:20` | Depths 4 and 5 |

Distribution by depth (weights): depth 1: Open 40 / Powered 60 (first run: Powered 100); depth 2 to 3: Open 20 / Powered 40 / Keyed 40; depth 4 to 5: Powered 30 / Keyed 35 / Cycled 35; depth 6: Open. Cycle 2: depth 7 onward uses the depth 4 to 5 table everywhere except Substrate.

Exit prefabs (one per stratum, §5) share an `Exit` component: `status`, `open()`, `seal()`, a trigger volume that calls `GameState.descend(true)` after a 0.6 s "entering" tween, and a "seen" detector (frustum + 25 m + unoccluded) that sets the HUD status from `UNKNOWN`.

## 7. Noclip validity data

The builder tags every wall collider with metadata `{cell, dir, wall_type}`. `NoclipTargeting` (`06` §8) reads `wall_type`: `SOLID` and `GLASS` → `SOLID`; `WALL`, `PARTITION`, `DOOR` (closed), `SOFT` → candidates, then the shape cast decides `NO SPACE`. Racks (`RACK` cells) are tagged `WALL` on all four faces. Floors are tagged with the cell; floor drops are valid on any `FLOOR`, `ROOM`, or `BASIN` cell except on the final depth.

## 8. Build and validation

### Build (`LevelBuilder`, main thread, time-sliced)
- Chunks of 8×8 cells. Per chunk and per surface class (floor, ceiling, wall, partition, rack, basin, unfinished), one merged `ArrayMesh` via `SurfaceTool` with the stratum's world shader material, vertex colour carrying a per-cell hash (0..1) in R for pattern variation, the `UNFINISHED` flag in G, on floors the distance to the nearest wall in metres (clamped to 1) in B, and 1 on corridor (`FLOOR`) cells in A (wear lanes and the floor seam, 02 §7). Normals and UVs generated; triplanar sampling in the shader means UVs only matter for tiles.
- Collision: one `StaticBody3D` per chunk with `BoxShape3D` per floor cell (2×0.2×2 at `floor_y`), per wall edge (2×height×0.2), per partition edge (2×1.5×0.2), per void cell next to a walkable cell (1.8×height×1.8 between the wall faces, `wall_type` `SOLID`, so a noclip pass can never end inside a void block), per rack cell, and a sloped `ConvexPolygonShape3D` per ramp cell. Shapes carry the metadata of §7 through `set_meta` on a per-shape owner id lookup (`collider.shape_owner` → metadata dictionary).
- Doors are instanced prefabs (`09`) in the edge, with their own bodies.
- Props and fixtures are instanced prefabs placed from `Placements`. Fixtures register with `LightPool` and their group id.
- Water: one `Area3D` + planar mesh per basin with `WATER`.
- Navigation: all floor and ramp meshes are added to a `NavigationRegion3D` source group; `bake_navigation_mesh(true)` (threaded). Agent radius 0.4, height 1.8, max climb 0.3, cell size 0.2 (the radius is exactly two cells). Partition walls, racks and door jambs are included as obstacles (door leaves are not: errors open doors). Water deeper than 1.3 m is excluded.
- Chunks beyond 40 m of the player are hidden (`visibility_range_end` 45 m, no fade: a fade would alpha-blend level geometry, 02 §5), which, with fog, is invisible.

### Validation (`LevelValidator`, runs on the data before build; also run headless over 1,000 seeds per stratum in tests)
1. Spawn and exit exist, in distinct rooms, and `critical_path` exists.
2. Critical path length within the stratum's band (Halls 80 to 160 m at depth 1 scaling by size; Substrate 140 to 220 m).
3. Lock objective (breaker, keycard, and for Variant B the placed fuse) reachable from spawn, and exit reachable from the objective, without crossing `SOLID` or `GLASS` or deep water.
4. Walkable cell count within ±25% of target.
5. No wall edge thicker than 0.2 m between two walkable cells (by construction).
6. Every room has at least one opening. No `DEAD_END` chain longer than 12 cells.
7. Error spawn points: at least 6, each ≥ 20 m walking distance from spawn, none inside `SPAWN_ROOM` or `EXIT_ROOM`.
8. Items, notes, and hide spots placed within their count ranges; no two items in the same cell.
9. Soft walls each save ≥ 20 m of walking.
10. Garage: both decks reachable; Pools: exit basin dry; Offices: breaker exists; Server: every cage has a gate; Substrate: Threshold pocket lit, `VOID` fraction 15% to 25%, and **no dead end longer than 4 cells** (so Null cannot corner the player; the unfinish step must repair longer dead ends by opening a soft wall at their end).
11. After build (integration test): navigation bake succeeds and a path exists from spawn to exit on the navmesh.

## 9. Cycle 2 corruption (generator side)

- Grid +2 in each dimension; `braid` fraction halved (more dead ends); one extra Static spawn; 10% of corridor fixtures removed; one extra soft wall; in Offices, 60% of groups start dark; in Substrate, Null radius ×2 from depth 12.

## 10. Verification

- `tests/levelgen/test_grammars.gd`: 1,000 seeds per stratum through `layout`, `decorate`, and `LevelValidator`; asserts zero failures after retries and reports mean critical path length and walkable count.
- `tests/levelgen/test_determinism.gd`: same seed twice produces byte-identical `LevelGrid` and `Placements`.
- `game/scenes/debug/levelgen_viewer.tscn`: renders any seed and stratum top-down as a 2D overlay (cells, walls, critical path, placements) and in 3D for the screenshot tour.

## Interfaces

- `LevelGenerator.generate(stratum: StringName, depth: int, seed: int, first_run: bool, cycle: int) -> LevelData` (worker thread safe; `LevelData` = grid + placements + metadata like `exit_lock`, `spawn_cell`, `exit_cell`, `critical_path`).
- `LevelBuilder.build(level: LevelData, parent: Node3D) -> Signal ready` (main thread, sliced; emits `built` after navigation bake).
- `LevelGrid` queries used by others: `is_walkable(cell)`, `wall(cell, dir)`, `floor_y(cell)`, `cell_of(world_pos) -> Vector2i`, `world_of(cell) -> Vector3`, `distance_field(from)`, `random_walkable_cell(rng, filter)`, `fixture_groups()`, `rooms()`.
- Placement kinds consumed by `09` (props, items, notes, hide spots, exits, locks), by `10` (error spawn points), by `02` (fixtures, studio lights, water).

### Interface additions during production
- `LevelGenerator.generate(stratum, depth, seed, first_run = false, cycle = 1, options = {})`; `options` takes `item_pool` (unlock gating), `fuse_unlocked` (Variant B), `endless`.
- `LevelValidator.validate(level) -> PackedStringArray` (empty when valid) and `LevelValidator.run_batch(stratum, n, depth = 0) -> Dictionary`.
- `LevelGrid.world_of(cell)` returns the cell centre `(x*2, floor_y, z*2)`. Placement kinds are the `LevelData.P_*` constants; a note placement is a slot, and the note is chosen from the Archive at build time. `LevelData.to_ascii()` and a SHA-256 `hash()` exist for debugging and determinism.
- M1.2 builder: `LevelBuilder.build(level, parent) -> Signal` returns `built` (after the threaded navigation bake); `geometry_built` fires first (walkable), `navigation_baked(ok)` between; `navigation_ok`, `spawn_transform`, `light_pool`, `nav_region` properties. The geometry plan is `BuildPlan.make(level, height)` (pure data, worker thread). Collision: `StaticBody3D` per chunk and kind on layer 1 with shape owners (no `CollisionShape3D` nodes); floor bodies carry meta `surface` (Halls `&"carpet"`), wall bodies meta `wall_kind` (the wall type name: `&"WALL"`, `&"SOLID"`, `&"SOFT"`, `&"PARTITION"`, `&"DOOR"`, `&"GLASS"`; props and lockers `&"PROP"`), and `shape_meta` (owner id → `{cell, dir, wall_type, wall_kind, thickness, other_cell, walkable, other_walkable}`); read a hit with `LevelBuilder.shape_info(collider, shape_index)`. Each soft wall is a node in group `soft_walls` (child `Mesh` with `soft = 1`, child `Body`).
- M1.2 placeholders: exit, breaker, keycard, items, notes, spawn and error spawns are `Marker3D` nodes in group `placement_<kind>` (`LevelPlacer.group_of(kind)`; error spawns also in `error_spawns`) with the placement dictionary as meta `placement`. Doors are `Door` prefabs (`scenes/props/shared/door.tscn`, group `doors`, leaf carries the edge meta); closet doors start closed, others open.
- M1.2 level scene: `scenes/level.tscn` (`Level`): `begin(level_data, preset)`, signals `geometry_ready`, `navigation_ready(ok)` (errors stay dormant until it), `built`; `attach_player(player, eye)`, `detach_player(player)`, `spawn_transform()`, `is_walkable_now()`, `is_ready()`. `SightOps.clear(grid, a, b)` is grid line of sight.
- R4 (2026-10-08): `SightOps.clear(grid, a, b)` has its own edge rule: open edges, `PARTITION` (seen over) and `GLASS` pass; `WALL`, `SOLID`, `SOFT` and a closed `DOOR` block. `SightOps.edge_clear(grid, cell, dir)`, `SightOps.clear_near(grid, eye, to)` (the eye's cell or one step from it). `LevelGrid` carries runtime door state (not hashed): `set_door_closed(cell, dir, closed)`, `is_door_closed(cell, dir)`, `door_version`, `LevelGrid.edge_key(cell, dir)`; `Door.grid` keeps it. Void blocks are bodies with meta `void` (no `wall_kind`: not a noise wall) whose shapes carry `{cell, wall_type: SOLID, wall_kind: &"SOLID", thickness, walkable: false, void: true}`. Door jambs carry `wall_type` `WALL` / `wall_kind` `&"WALL"`; the leaf keeps the edge's `wall_type` `DOOR` and its `wall_kind` is `&"DOOR"` while closed and `&"PROP"` while open. `BuildPlan.errors` and `BuildPlan.SUPPORTED_STRATA` (`[&"halls"]`; other strata are built flat with an error until M2.1 adds per-cell heights and special cells). `LevelMaterials.for_class(stratum, cls)` also serves `C_DOOR_LEAF` and `C_DOOR_HANDLE`; `Door.apply_materials(jamb, leaf, handle)`. `Level` is in group `levels` (`Level.grid_in(tree)`) and `debug_info` (light counts for F3; `Level.light_counts(root)`). `LevelShots` adds the `corridor_long` pose.
- M2.1 (2026-10-08): Pools and Garage grammars (`PoolsGenerator` with `PoolBasins`, `PoolPumps`; `GarageGenerator` with `GarageParking`), registered in `LevelGenerator.grammar_for`. `LevelGrid` gains the cell kind `DEEP` (6: built open, not walkable), `ramp_dir`/`ramp_grade` (hashed) and `ledges` (derived), `kind_open`/`is_open`, `is_pillar` (a VOID cell with no walls and walkable cells round it), `is_sight_open`, `set_floor_y`, `ramp_dir_of`, `edge_floor_y(c, dir)`; `open_mask`/`can_step`/`distance_field` honour ledges. `GridHeights.set_ramp(grid, run, uphill, y_low, y_high)` and `GridHeights.refresh_ledges(grid)` write them. `SightOps` sight crosses DEEP and pillar cells. `LevelData.P_WATER` (`params`: `rect`, `surface_y`, `floor_y`). `StratumGenerator.release()` (helpers that point back at the grammar). BuildPlan models per-element open intervals (`SUPPORTED_STRATA` = halls, pools, garage; `FLAT_CEILING_STRATA` = pools), class `C_BASIN`, bodies `BODY_RAIL` (meta `rail`, no `wall_kind`); faces in `BuildFaces`, ramps and pool steps in `BuildSlopes`; collision shapes may carry `points` (a ConvexPolygonShape3D wedge per ramp cell). `LevelNavigation` holds the bake settings and source. `WaterVolume` (Area3D, layer 7) sets `water_depth` on bodies that have it. `LevelMaterials.C_WATER`. `StratumShots.poses(data)` adds `basin`, `ramp`, `ramp_down` and `deck` to LevelShots. Exit placements carry `exit_kind` `&"drain_hatch"` (Pools, at the dry basin's bottom) and `&"stairwell_door"` (Garage); hide spots `&"pump_corner"` and `&"under_car"` are markers until M2.8.
- M2.2 (2026-10-08): Offices and Server grammars (`OfficesGenerator` with `OfficeRooms`, `OfficeFurnish`; `ServerGenerator` with `ServerRacks`, `ServerFurnish`), registered in `LevelGenerator.grammar_for`; `RingOps` (ring corridor, band rooms, `carve_line`); rule 10 for both in `StratumRules` (`offices`, `server`, `longest_hall_run`). Room kinds `&"office_open"`, `&"office_small"`, `&"meeting"` (`OfficeRooms.OPEN/SMALL/MEETING`), `&"cage"` (`ServerGenerator.CAGE`). Placement params: a fixture of a dark group carries `dark = true` (LevelPlacer starts it unpowered); fixture `fixture` kinds `&"troffer"`, `&"emergency_box"`, `&"rack_led"`, `&"exit_light"`, wall-mounted ones carry `dir`; props `desk`, `monitor`, `chair`, `filing_cabinet`, `water_cooler` (Offices), `fan_grille`, `cable_tray` (`params.length` in m) (Server); hide spots `&"under_desk"` and `&"rack_gap"` are markers until M2.8; the Server exit is `exit_kind` `&"floor_hatch"` at the clearing's centre (the elevator prefab stands in until M2.9). `PopulateOps.soft_walls(gen, count, first_run, exclude_flags, prefer := Callable())` marks the grammar's preferred edges first; `PopulateOps.items(gen, pool, first := [])` gives the first items to reserved cells (cages); items never land in closets or cages (`ITEM_EXCLUDED_ROOMS`). `FixtureOps.lattice_fixtures` (a room on the level's lattice) and `single_fixture`. BuildPlan: `SUPPORTED_STRATA` adds offices and server; class `C_RACK` (a RACK cell is a block `SERVER_RACK_HEIGHT` high over the cell and both edge strips, open above; vertex colour B = 1 on its fronts, the faces across the rows; `rows_along_x`, `rack_height`, `is_rack`, `is_built`); body `BODY_RACK` (one box per rack cell, body meta `wall_kind` WALL and `rack`; shape meta `{cell, rack, wall_type WALL, wall_kind, thickness 2.2, walkable false, far_walkable[4], far_floor_y[4]}`, `BuildCollision.rack_box`, `rack_meta`); no wall box stands on a rack's edge. The lattice is `BuildLattice` (`make`, `breaks`, `ys`). `LevelMaterials` tables for offices and server (C_PARTITION, C_GLASS, C_RACK). `StratumShotsM22.poses`: `cubicles`, `dark_group`, `meeting` (Offices), `racks`, `cage` (Server). `MergedProp` (a prop's primitive meshes merged once per scene into one mesh per material). Floor `surface` meta: offices `&"carpet"`, server `&"raised_floor"`.
- M2.2 rack ruling (open item): a rack face is a WALL candidate whose pass crosses the whole rack (the cell and both edge strips) to the cell beyond along the face's inward normal; that cell must be walkable (another rack behind is NO SPACE). Implemented in `NoclipQuery.rack_far_side` (06 additions) from the rack box metadata; the validator (rule 10) checks every rack face toward walkable space is a WALL edge.
- M2.9 (2026-10-08): `LevelGenerator.generate` options also take `lock` and `lock_variant` (tests and benches force the lock; the lock draw still runs so the seed stream is unchanged). Rule 3 for Cycled: the open window (`CYCLED_OPEN_TIME` × `PLAYER_WALK_SPEED` = 64 m) must cover the walk to the exit from every exit-room cell and from the critical-path cell `EXIT_SEEN_DIST` before the exit (`LevelValidator.cycled_walk_m`, `cycled_window_m`; never binds at depths 4 and 5 over 200 seeds per stratum). Keycard and Variant B fuse reachability stay rule 3 as before. Lock weights per depth are unchanged (`StratumGenerator.lock_weights`; first run depth 1 Powered 100).
- M2.3 (2026-10-08): Substrate grammar `SubstrateGenerator` (`strata/substrate.gd`, registered in `LevelGenerator.grammar_for`) runs `HallsGenerator` through `StratumGenerator.adopt(host)` (hooks `walkable_scale`, `closets_enabled`, `exit_band_inset`; `OfficesGenerator.walkable_scale`) and `SubstrateUnfinish` (`unfinish`, `repair`, `limit_dead_ends`, `offset_rooms`, `units`, `mark_units`); `office_modules()` on even Cycles. Room kind `RoomData.POCKET` (the exit room; rule 1 accepts it in the Substrate). `LevelData.null_spawn_cell`, `unfinished_void`, `unfinish_base` (hashed); error spawn params `error` = `&"null"` (one, on the critical path at 55%) or `&"static"` (two, Cycle 2 three, off the path); exit `exit_kind` `&"threshold_door"` at the pocket's centre, `dir` the side it faces; fixtures `fixture` `&"studio_light"` (one group each, `Fixture.profile_for`: white, 0.6, 15 m, unshadowed, no hum; profile key `hum`). Rule 10 `StratumRules.substrate` and `StratumRules.void_fraction`; Cycle 2 checks `StratumRules.cycle2`. `LevelValidator.path_band` gives the Substrate 140 to 220 m at any Cycle. BuildPlan: `SUPPORTED_STRATA` adds substrate; classes `C_UNFINISHED` (8, the checker on UNFINISHED cells' floors, ceilings and walls) and `C_EDGE` (9, SOLID boundary) in `UNFINISHED_STRATA`; `face_class(cls, col)`. `LevelMaterials` substrate table; `for_level(stratum, cls, cycle)` (Cycle 2 twins). Floor `surface` meta substrate `&"substrate"`. Scene `scenes/exits/threshold_door.tscn` (`ThresholdDoor`), `scenes/props/substrate/fixture_studio_light.tscn`. `StratumShotsM23` poses `pocket`, `studio`, `checker` (`checker_pose` public). `--validate-levels N --stratum S` limits the batch to one stratum.
- M2.3 Cycle 2 (07 §9, 02 §7): `Cycle2Ops.corrupt(gen, rng)` runs after `decorate` on Cycle 2+ levels on sub-seed `cycle2` (ordinary strata only): 10% of corridor fixtures removed (groups pruned), 25% of the rest `dead = true` (LevelPlacer: unpowered, not registered with the LightPool, out of group `fixtures`), 10% of surfaces flagged UNFINISHED in units; spawn and exit rooms untouched. `PopulateOps.error_spawns` places one more spawn point in Cycle 2. `Cycle2Ops.hue_toward`, `next_stratum`; LevelPlacer turns each fixture's light and tube 12° towards the next stratum's colours; `Level.apply_cycle2_fog(env)` multiplies fog density by 1.3. World shader uniform `unfinished_u` (u on faces whose vertex colour G is 1).
