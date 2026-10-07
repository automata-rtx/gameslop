class_name StratumGenerator
extends RefCounted
## Base of the six grammars (07 §5, 14 §6: the only inheritance tree in levelgen).
## `generate` runs one attempt: sizes and lock, then the grammar's `layout`, the shared
## critical path, then the grammar's `decorate`. One instance per attempt; no shared state,
## no nodes, no autoloads, so it runs on a worker thread.

## Seed label for the lock draw. It is not offset by the retry index, so a retry keeps
## the lock the run was dealt.
const SEED_LABEL_LOCK := "lock"

## Options understood by every grammar (LevelGenerator.generate `options`):
##   item_pool: Array[StringName]  kinds that may be placed (unlock gating, 05 §6);
##                                 default polaroid and chalk (always unlocked).
##   fuse_unlocked: bool           unlock #4: Powered may be Variant B (07 §6).
##   endless: bool                 Endless mode: the floor is never solid (06 §8).
const DEFAULT_ITEM_POOL: Array[StringName] = [&"polaroid", &"chalk"]

var data: LevelData = null
var grid: LevelGrid = null
var options: Dictionary = {}
## True for the fallback ("simplest grammar", 07 §1 rule 5).
var simplest: bool = false
var rng_layout: RandomNumberGenerator = null
var rng_place: RandomNumberGenerator = null
var rng_props: RandomNumberGenerator = null
var rng_fixtures: RandomNumberGenerator = null
## Walking distance in cells from the spawn cell, refreshed by `compute_paths`.
var spawn_dist: PackedInt32Array = PackedInt32Array()
## Cell indices holding a pickup (item, note, keycard): 07 §8 rule 8, one per cell.
var occupied: Dictionary = {}


## One generation attempt. `attempt` offsets every sub-seed (07 §1 rule 5: sub_seed + 1).
func generate(stratum: StringName, depth: int, run_seed: int, first_run: bool, cycle: int,
		opts: Dictionary, attempt: int, use_simplest: bool) -> LevelData:
	options = opts
	simplest = use_simplest
	data = LevelData.new()
	data.stratum = stratum
	data.depth = depth
	data.cycle = cycle
	data.run_seed = run_seed
	data.level_seed = Seeds.for_depth(run_seed, depth)
	data.first_run = first_run
	data.attempt = attempt
	data.fallback = use_simplest
	# 06 §8: the floor is solid on the last depth of a Descent; never in Endless.
	data.floor_solid = depth == Tuning.RUN_FINAL_DEPTH and not bool(opts.get(&"endless", false))
	var n := grid_side(depth, cycle)
	grid = LevelGrid.new(Vector2i(n, n))
	data.grid = grid
	rng_layout = _sub_rng(Tuning.SEED_LABEL_LAYOUT, attempt)
	rng_place = _sub_rng(Tuning.SEED_LABEL_PLACEMENT, attempt)
	rng_props = _sub_rng(Tuning.SEED_LABEL_PROPS, attempt)
	rng_fixtures = _sub_rng(Tuning.SEED_LABEL_FIXTURES, attempt)
	_choose_lock(Seeds.rng(Seeds.derive(data.level_seed, SEED_LABEL_LOCK)))
	layout()
	compute_paths()
	decorate()
	return data


func _sub_rng(label: String, attempt: int) -> RandomNumberGenerator:
	return Seeds.rng(Seeds.derive(data.level_seed, label) + attempt)


# ------------------------------------------------------------------ virtual

## Builds rooms, corridors and walls; sets data.spawn_cell/dir and data.exit_cell/dir.
func layout() -> void:
	push_error("StratumGenerator.layout is abstract")


## Lock objective, soft walls, hide spots, items, notes, props, fixtures, error spawns.
func decorate() -> void:
	push_error("StratumGenerator.decorate is abstract")


# ------------------------------------------------------------------ sizes and lock

## 07 §2: grid side per depth (within a Cycle), +2 per Cycle after the first.
static func grid_side(depth: int, cycle: int) -> int:
	var d := cycle_depth(depth)
	return int(Tuning.GRID_SIZE_BY_DEPTH.get(d, 24)) + Tuning.GRID_CYCLE2_EXTRA * maxi(0, cycle - 1)


## Depth within its Cycle, 1..6.
static func cycle_depth(depth: int) -> int:
	return (maxi(1, depth) - 1) % Tuning.RUN_CYCLE_LENGTH + 1


## 05 §2, 07 §2: walkable cell target for the depth.
static func walkable_target(depth: int) -> int:
	return int(Tuning.LEVEL_WALKABLE_CELLS.get(cycle_depth(depth), 300))


## 07 §6 distribution by depth. Cycle 2 uses the depth 4 to 5 table except at depth 6.
static func lock_weights(depth: int, first_run: bool, cycle: int) -> Dictionary:
	var d := cycle_depth(depth)
	if d == 6:
		return Tuning.LOCK_WEIGHTS_DEPTH6
	if cycle > 1:
		return Tuning.LOCK_WEIGHTS_DEPTH4_5
	match d:
		1:
			return Tuning.LOCK_WEIGHTS_DEPTH1_FIRST_RUN if first_run else Tuning.LOCK_WEIGHTS_DEPTH1
		2, 3:
			return Tuning.LOCK_WEIGHTS_DEPTH2_3
	return Tuning.LOCK_WEIGHTS_DEPTH4_5


func _choose_lock(rng: RandomNumberGenerator) -> void:
	var weights := lock_weights(data.depth, data.first_run, data.cycle)
	data.exit_lock = pick_weighted(weights, rng)
	data.lock_variant = &""
	if data.exit_lock == Tuning.LOCK_POWERED:
		var b := bool(options.get(&"fuse_unlocked", false)) and rng.randf() < Tuning.FUSE_VARIANT_B_CHANCE
		data.lock_variant = &"b" if b else &"a"


## Weighted pick over a {StringName: int} table, in the table's insertion order.
static func pick_weighted(weights: Dictionary, rng: RandomNumberGenerator) -> StringName:
	var total := 0
	for k: StringName in weights:
		total += int(weights[k])
	var r := rng.randi_range(0, maxi(0, total - 1))
	for k: StringName in weights:
		r -= int(weights[k])
		if r < 0:
			return k
	return weights.keys()[0]


# ------------------------------------------------------------------ shared steps

## Critical path spawn -> exit (07 §3), its flags, and the spawn distance field.
func compute_paths() -> void:
	data.critical_path = PathOps.critical_path(grid, data.spawn_cell, data.exit_cell)
	spawn_dist = grid.distance_field(data.spawn_cell)


## Flags every cell of a room (SPAWN_ROOM, EXIT_ROOM, LOCK_ROOM, NO_SPAWN).
func flag_room(room: RoomData, f: int) -> void:
	for c in room.cells():
		grid.add_flag(c, f)


## Middle cell of a room's side `dir` and that side's edge.
static func side_middle(room: RoomData, dir: int) -> Vector2i:
	var r := room.rect
	match dir:
		LevelGrid.N:
			return Vector2i(r.position.x + r.size.x / 2, r.position.y)
		LevelGrid.E:
			return Vector2i(r.end.x - 1, r.position.y + r.size.y / 2)
		LevelGrid.S:
			return Vector2i(r.position.x + r.size.x / 2, r.end.y - 1)
	return Vector2i(r.position.x, r.position.y + r.size.y / 2)


## Perimeter edges of a room that are closed walls (a prop or box can stand there), in
## perimeter order, excluding edges on cells that hold an opening.
func wall_slots(room: RoomData) -> Array[Vector3i]:
	var door_cells: Array[Vector2i] = []
	for e in room.perimeter_edges():
		if grid.wall_walkable(grid.wall(Vector2i(e.x, e.y), e.z)):
			door_cells.append(Vector2i(e.x, e.y))
	var out: Array[Vector3i] = []
	for e in room.perimeter_edges():
		var c := Vector2i(e.x, e.y)
		if door_cells.has(c) and room.rect.size != Vector2i.ONE:
			continue
		if not grid.wall_walkable(grid.wall(c, e.z)):
			out.append(e)
	return out


## Offset that puts a wall-mounted object against edge `dir` of its cell, `inset` m from
## the wall plane.
static func wall_offset(dir: int, inset: float) -> Vector3:
	var v := LevelGrid.DIRS[dir]
	var reach := Tuning.GRID_CELL_SIZE * 0.5 - Tuning.GRID_WALL_THICKNESS * 0.5 - inset
	return Vector3(v.x * reach, 0.0, v.y * reach)
