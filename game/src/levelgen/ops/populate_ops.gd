class_name PopulateOps
extends RefCounted
## Shared decorate steps (07 §3 pipeline, 09 §2): soft walls, lock objective pickups,
## notes, items and error spawn points. Each takes the running StratumGenerator, whose
## grid, critical path and spawn distance field are current.

## Minimum spacing between pickups in cells (Poisson selection, 09 §2).
const PICKUP_SPACING := 3
## Spacing between error spawn points and between soft walls, cells.
const SPAWN_POINT_SPACING := 3
const SOFT_WALL_SPACING := 3
## Path cells used as extra distance-field landmarks when bounding soft wall savings.
const LANDMARKS := 2
## Exact soft wall measurements (one BFS each) allowed when the bounds fall short.
const EXACT_CHECKS := 24


## Soft walls (07 §4, 09 §8). With `first_run`, one is forced onto the critical path (a
## path cell on at least one side) within the 05 §10 walking time of spawn; one joining
## two path cells (a true shortcut along the path) is preferred.
static func soft_walls(gen: StratumGenerator, count: int, first_run: bool, exclude_flags: int) -> void:
	var grid := gen.grid
	var fields: Array[PackedInt32Array] = [gen.spawn_dist, grid.distance_field(gen.data.exit_cell)]
	var path := gen.data.critical_path
	if path.size() > LANDMARKS:
		# Extra bounds from cells spread along the critical path tighten the estimate.
		for k in LANDMARKS:
			fields.append(grid.distance_field(path[(k + 1) * path.size() / (LANDMARKS + 1)]))
	var candidates := PlaceOps.soft_wall_candidates(grid, fields, Tuning.SOFT_WALL_MIN_SAVING, exclude_flags)
	var marked: Array[Vector3i] = []
	if first_run:
		var reach := int(Tuning.FIRST_DESCENT_SOFT_WALL_TIME * Tuning.PLAYER_WALK_SPEED / Tuning.GRID_CELL_SIZE)
		var both: Array[Vector3i] = []
		var one: Array[Vector3i] = []
		for e in candidates:
			var a := Vector2i(e.x, e.y)
			var b := a + LevelGrid.DIRS[e.z]
			var pa := grid.has_flag(a, LevelGrid.F_CRITICAL_PATH) and gen.spawn_dist[grid.idx(a)] <= reach
			var pb := grid.has_flag(b, LevelGrid.F_CRITICAL_PATH) and gen.spawn_dist[grid.idx(b)] <= reach
			if pa and pb:
				both.append(e)
			elif pa or pb:
				one.append(e)
		var pool := both if not both.is_empty() else one
		if pool.is_empty():
			# The first Descent's guarantee is worth measuring every path-side wall.
			var side := _path_side_walls(gen, exclude_flags, reach)
			pool = PlaceOps.exact_soft_candidates(grid, side, Tuning.SOFT_WALL_MIN_SAVING, gen.rng_place, side.size())
		if not pool.is_empty():
			marked.append_array(PlaceOps.mark_soft_walls(grid, pool, 1, SOFT_WALL_SPACING, gen.rng_place))
		else:
			var from: Array[Vector2i] = []
			for c in path:
				if gen.spawn_dist[grid.idx(c)] <= reach:
					from.append(c)
			_carve(gen, from, fields, exclude_flags, marked)
	var rest := PlaceOps.mark_soft_walls(grid, candidates, count - marked.size(), SOFT_WALL_SPACING, gen.rng_place, marked)
	marked.append_array(rest)
	if marked.size() < count:
		var exact := PlaceOps.exact_soft_candidates(grid, PlaceOps.interior_walls(grid, exclude_flags),
			Tuning.SOFT_WALL_MIN_SAVING, gen.rng_place, EXACT_CHECKS)
		marked.append_array(PlaceOps.mark_soft_walls(grid, exact, count - marked.size(), SOFT_WALL_SPACING, gen.rng_place, marked))
	if marked.size() < count:
		var everywhere: Array[Vector2i] = []
		for i in grid.cell_count():
			if LevelGrid.kind_walkable(grid.cells[i]):
				everywhere.append(grid.cell_at(i))
		while marked.size() < count and _carve(gen, everywhere, fields, exclude_flags, marked):
			pass
	gen.data.soft_walls = marked
	gen.data.expected_soft_walls = count


## One authored shortcut (PlaceOps.carve_soft_shortcut); refreshes the spawn distances and
## dead-end flags the later steps read. Returns false when no shortcut can be cut.
static func _carve(gen: StratumGenerator, from: Array[Vector2i], fields: Array[PackedInt32Array],
		exclude_flags: int, marked: Array[Vector3i]) -> bool:
	var e := PlaceOps.carve_soft_shortcut(gen.grid, from, fields, Tuning.SOFT_WALL_MIN_SAVING, gen.rng_place, exclude_flags)
	if e.x < 0:
		return false
	marked.append(e)
	gen.spawn_dist = gen.grid.distance_field(gen.data.spawn_cell)
	MazeOps.mark_dead_ends(gen.grid)
	return true


## Interior walls with a critical-path cell within `reach` cells of spawn on one side.
static func _path_side_walls(gen: StratumGenerator, exclude_flags: int, reach: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var grid := gen.grid
	for e in PlaceOps.interior_walls(grid, exclude_flags):
		for c: Vector2i in [Vector2i(e.x, e.y), Vector2i(e.x, e.y) + LevelGrid.DIRS[e.z]]:
			if grid.has_flag(c, LevelGrid.F_CRITICAL_PATH) and gen.spawn_dist[grid.idx(c)] <= reach:
				out.append(e)
				break
	return out


## Cells whose spawn distance lies in [lo, hi] (cells), walkable, not in the spawn or exit
## room, not occupied, passing `extra` (Callable(Vector2i) -> bool) when valid.
static func band_cells(gen: StratumGenerator, lo: int, hi: int, extra: Callable = Callable()) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var grid := gen.grid
	for i in grid.cell_count():
		var d := gen.spawn_dist[i]
		if d < lo or d > hi or gen.occupied.has(i):
			continue
		if (grid.flags[i] & (LevelGrid.F_SPAWN_ROOM | LevelGrid.F_EXIT_ROOM)) != 0:
			continue
		var c := grid.cell_at(i)
		if extra.is_valid() and not extra.call(c):
			continue
		out.append(c)
	return out


## 09 §2 placement weights: dead ends x3, rooms x2, off-critical-path x2.
static func pickup_weights(gen: StratumGenerator, cells: Array[Vector2i]) -> PackedFloat32Array:
	var w := PackedFloat32Array()
	for c in cells:
		var x := 1.0
		if gen.grid.has_flag(c, LevelGrid.F_DEAD_END):
			x *= Tuning.ITEM_PLACE_WEIGHT_DEAD_END
		if gen.grid.kind(c) == LevelGrid.ROOM:
			x *= Tuning.ITEM_PLACE_WEIGHT_ROOM
		if not gen.grid.has_flag(c, LevelGrid.F_CRITICAL_PATH):
			x *= Tuning.ITEM_PLACE_WEIGHT_OFF_PATH
		w.append(x)
	return w


static func _take(gen: StratumGenerator, c: Vector2i) -> void:
	gen.occupied[gen.grid.idx(c)] = true


## One pickup in the 35% to 70% critical-path band, off the path when possible (07 §6).
static func band_pickup(gen: StratumGenerator, rng: RandomNumberGenerator) -> Vector2i:
	var length := gen.data.critical_path.size() - 1
	var lo := int(ceil(length * 0.35))
	var hi := int(floor(length * 0.70))
	var off := band_cells(gen, lo, hi, func(c: Vector2i) -> bool:
		if gen.grid.has_flag(c, LevelGrid.F_CRITICAL_PATH):
			return false
		var r := gen.grid.room_of(c)
		return r == null or r.kind == RoomData.GENERIC)
	if off.is_empty():
		off = band_cells(gen, lo, hi)
	var pick := PlaceOps.poisson_cells(off, 1, 0, rng, pickup_weights(gen, off))
	if pick.is_empty():
		return LevelData.NO_CELL
	_take(gen, pick[0])
	return pick[0]


## Keycard (Keyed) and the one guaranteed fuse (Powered Variant B), 07 §6.
static func lock_pickups(gen: StratumGenerator) -> void:
	var data := gen.data
	if data.exit_lock == Tuning.LOCK_KEYED:
		data.keycard_cell = band_pickup(gen, gen.rng_place)
		if data.keycard_cell != LevelData.NO_CELL:
			data.add_placement(LevelData.P_KEYCARD, data.keycard_cell)
	if data.exit_lock == Tuning.LOCK_POWERED and data.lock_variant == &"b":
		data.fuse_cell = band_pickup(gen, gen.rng_place)
		if data.fuse_cell != LevelData.NO_CELL:
			data.add_placement(LevelData.P_ITEM, data.fuse_cell, Vector3.ZERO, 0.0,
				{&"item": &"fuse", &"guaranteed": true})


## Note slots (09 §2): 2 per level (1 at depth 6), never in the spawn room, slot 0 within the
## first 40% of the critical path (first Descent: within 10 m of spawn, 05 §10). Which note
## goes in a slot is chosen at build time from the Archive state.
static func notes(gen: StratumGenerator) -> void:
	var data := gen.data
	var count := Tuning.NOTES_PER_LEVEL_DEPTH6 if StratumGenerator.cycle_depth(data.depth) == 6 else Tuning.NOTES_PER_LEVEL
	data.expected_notes = count
	var length := data.critical_path.size() - 1
	var early_hi := int(floor(length * Tuning.NOTES_FIRST_PATH_FRACTION))
	if data.first_run and data.depth == 1:
		early_hi = int(floor(Tuning.FIRST_DESCENT_NOTE_DIST / Tuning.GRID_CELL_SIZE))
	for slot in count:
		var cells := band_cells(gen, 1, early_hi if slot == 0 else gen.grid.cell_count())
		var pick := PlaceOps.poisson_cells(cells, 1, 0, gen.rng_place, pickup_weights(gen, cells))
		if pick.is_empty():
			continue
		_take(gen, pick[0])
		data.add_placement(LevelData.P_NOTE, pick[0], Vector3.ZERO, 0.0,
			{&"slot": slot, &"early": slot == 0, &"first_descent": data.first_run and slot == 0})


## Items (09 §2): 2 + floor(depth / 2), plus a guaranteed Polaroid on depth 1 and every even
## depth. Kinds by base weight from the unlocked pool; fuse only when the lock is Variant B.
static func items(gen: StratumGenerator, pool: Array[StringName]) -> void:
	var data := gen.data
	var d := StratumGenerator.cycle_depth(data.depth)
	var kinds: Array[StringName] = []
	var count := Tuning.ITEM_COUNT_BASE + d / Tuning.ITEM_COUNT_DEPTH_DIV
	var weights: Dictionary = {}
	for k in Tuning.ITEM_KINDS:
		if pool.has(k) and (k != &"fuse" or data.lock_variant == &"b"):
			weights[k] = Tuning.ITEM_WEIGHT[k]
	for i in count:
		kinds.append(StratumGenerator.pick_weighted(weights, gen.rng_place) if not weights.is_empty() else &"polaroid")
	if data.depth == 1 or data.depth % 2 == 0:
		kinds.append(&"polaroid")
	# The guaranteed Variant B fuse (lock_pickups) counts on top of the drawn items.
	data.expected_items = kinds.size() + (1 if data.lock_variant == &"b" else 0)
	var cells := band_cells(gen, 1, gen.grid.cell_count(), func(c: Vector2i) -> bool:
		var r := gen.grid.room_of(c)
		return r == null or r.kind != RoomData.CLOSET)
	var taken: Array[Vector2i] = []
	for p in data.placements_of(LevelData.P_ITEM):
		taken.append(p[&"cell"])
	var picks := PlaceOps.poisson_cells(cells, kinds.size(), PICKUP_SPACING, gen.rng_place, pickup_weights(gen, cells), taken)
	if picks.size() < kinds.size():
		var more := PlaceOps.poisson_cells(cells, kinds.size() - picks.size(), 1, gen.rng_place, PackedFloat32Array(), picks)
		picks.append_array(more)
	for i in mini(picks.size(), kinds.size()):
		_take(gen, picks[i])
		data.add_placement(LevelData.P_ITEM, picks[i], Vector3.ZERO, 0.0, {&"item": kinds[i], &"guaranteed": false})


## Error spawn points (07 §8 rule 7): >= 20 m walking from spawn, outside the spawn and exit
## rooms and closets, spread by Poisson.
static func error_spawns(gen: StratumGenerator) -> void:
	var grid := gen.grid
	var min_cells := int(ceil(Tuning.VALIDATE_ERROR_SPAWN_MIN_WALK / Tuning.GRID_CELL_SIZE))
	var cells: Array[Vector2i] = []
	for i in grid.cell_count():
		if gen.spawn_dist[i] < min_cells or (grid.flags[i] & LevelGrid.F_NO_SPAWN) != 0:
			continue
		var c := grid.cell_at(i)
		var r := grid.room_of(c)
		if r != null and r.kind == RoomData.CLOSET:
			continue
		cells.append(c)
	var want := Tuning.VALIDATE_ERROR_SPAWNS_MIN + 2
	var picks := PlaceOps.poisson_cells(cells, want, SPAWN_POINT_SPACING, gen.rng_place)
	if picks.size() < Tuning.VALIDATE_ERROR_SPAWNS_MIN:
		picks.append_array(PlaceOps.poisson_cells(cells, want - picks.size(), 1, gen.rng_place, PackedFloat32Array(), picks))
	for c in picks:
		gen.data.add_placement(LevelData.P_ERROR_SPAWN, c, Vector3.ZERO, 0.0,
			{&"off_path": not grid.has_flag(c, LevelGrid.F_CRITICAL_PATH)})
