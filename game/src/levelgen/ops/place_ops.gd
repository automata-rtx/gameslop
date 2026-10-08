class_name PlaceOps
extends RefCounted
## Placement operations of the shared ops library (07 §4): poisson_cells and
## mark_soft_walls. Never pure random (procedural generation skill rule): cells are drawn
## by weight and rejected inside a minimum spacing.


## Weighted Poisson-disk selection of up to `count` cells from `candidates`. `weights`
## (same length, > 0) biases the draw; empty means uniform. Chosen cells are at least
## `min_spacing` cells apart (Chebyshev) from each other and from `taken`.
static func poisson_cells(candidates: Array[Vector2i], count: int, min_spacing: int,
		rng: RandomNumberGenerator, weights: PackedFloat32Array = PackedFloat32Array(),
		taken: Array[Vector2i] = []) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var pool := candidates.duplicate()
	var w := weights.duplicate()
	if w.size() != pool.size():
		w.resize(pool.size())
		w.fill(1.0)
	var guard := pool.size() + 1
	while out.size() < count and not pool.is_empty() and guard > 0:
		guard -= 1
		var k := _weighted_index(w, rng)
		var c: Vector2i = pool[k]
		pool[k] = pool[pool.size() - 1]
		pool.pop_back()
		w[k] = w[w.size() - 1]
		w.resize(w.size() - 1)
		if _far_enough(c, out, min_spacing) and _far_enough(c, taken, min_spacing):
			out.append(c)
	return out


static func _weighted_index(w: PackedFloat32Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for x in w:
		total += x
	var r := rng.randf() * total
	for i in w.size():
		r -= w[i]
		if r < 0.0:
			return i
	return w.size() - 1


static func _far_enough(c: Vector2i, others: Array[Vector2i], spacing: int) -> bool:
	for o in others:
		if maxi(absi(o.x - c.x), absi(o.y - c.y)) < spacing:
			return false
	return true


## Soft wall candidates (07 §4, 09 §8): WALL edges between two walkable cells whose walking
## distance is long enough that the wall saves >= min_saving_m. Distance fields from fixed
## cells give cheap lower bounds (|d(a) - d(b)| <= walk(a, b)), so every candidate returned
## is guaranteed; the validator re-measures exactly. Cells carrying any of `exclude_flags`
## are skipped (the exit room). Returns Vector3i(x, z, dir) with dir E or S.
static func soft_wall_candidates(grid: LevelGrid, fields: Array[PackedInt32Array], min_saving_m: float,
		exclude_flags: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var min_cells := int(ceil(min_saving_m / Tuning.GRID_CELL_SIZE)) + 1
	for i in grid.cell_count():
		if not grid.is_walkable_i(i) or fields[0][i] < 0:
			continue
		var c := grid.cell_at(i)
		if (grid.flags[i] & exclude_flags) != 0:
			continue
		for d: int in [LevelGrid.E, LevelGrid.S]:
			var o := c + LevelGrid.DIRS[d]
			if not grid.is_walkable(o) or grid.wall(c, d) != LevelGrid.WALL or grid.has_flag(o, exclude_flags):
				continue
			if not level_pair(grid, c, o):
				continue
			var j := grid.idx(o)
			var bound := 0
			for f in fields:
				if f[i] >= 0 and f[j] >= 0:
					bound = maxi(bound, absi(f[i] - f[j]))
			if bound >= min_cells:
				out.append(Vector3i(c.x, c.y, d))
	return out


## Every WALL edge between two walkable cells (E and S edges), skipping `exclude_flags`.
static func interior_walls(grid: LevelGrid, exclude_flags: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for i in grid.cell_count():
		if not grid.is_walkable_i(i) or (grid.flags[i] & exclude_flags) != 0:
			continue
		var c := grid.cell_at(i)
		for d: int in [LevelGrid.E, LevelGrid.S]:
			var o := c + LevelGrid.DIRS[d]
			if grid.is_walkable(o) and grid.wall(c, d) == LevelGrid.WALL and not grid.has_flag(o, exclude_flags) \
					and level_pair(grid, c, o):
				out.append(Vector3i(c.x, c.y, d))
	return out


## M2.1: a soft wall joins two flat cells on one floor level (never a ramp, never a deck
## or basin edge): the shortcut is a step through a wall, not a drop.
static func level_pair(grid: LevelGrid, a: Vector2i, b: Vector2i) -> bool:
	return grid.kind(a) != LevelGrid.RAMP and grid.kind(b) != LevelGrid.RAMP \
		and absf(grid.floor_y(a) - grid.floor_y(b)) < 0.01


## Measures up to `max_checks` of `edges` (in random order) exactly, one BFS each, and
## returns those whose wall saves >= min_saving_m. Used when the cheap bounds of
## soft_wall_candidates leave too few.
static func exact_soft_candidates(grid: LevelGrid, edges: Array[Vector3i], min_saving_m: float,
		rng: RandomNumberGenerator, max_checks: int) -> Array[Vector3i]:
	var pool := edges.duplicate()
	RoomOps.shuffle(pool, rng)
	var out: Array[Vector3i] = []
	for k in mini(max_checks, pool.size()):
		var e: Vector3i = pool[k]
		var a := Vector2i(e.x, e.y)
		var walk := grid.distance_field(a)[grid.idx(a + LevelGrid.DIRS[e.z])]
		if walk > 0 and (walk - 1) * Tuning.GRID_CELL_SIZE >= min_saving_m:
			out.append(e)
	return out


## Authors a shortcut where the maze offers none: a VOID cell v beside one of `from_cells`
## (p) and beside a corridor cell q far from p on foot becomes a 1-cell corridor stub off q,
## and the edge p|v becomes SOFT. The wall then saves walk(p, q) + 1 - 1 cells.
## `fields` bound walk(p, q) from below as in soft_wall_candidates. Returns the SOFT edge
## as Vector3i(p.x, p.z, dir), or Vector3i(-1, -1, -1).
static func carve_soft_shortcut(grid: LevelGrid, from_cells: Array[Vector2i], fields: Array[PackedInt32Array],
		min_saving_m: float, rng: RandomNumberGenerator, exclude_flags: int) -> Vector3i:
	var min_cells := int(ceil(min_saving_m / Tuning.GRID_CELL_SIZE))
	var options: Array[Vector3i] = []
	var stubs: Array[Vector2i] = []
	for p in from_cells:
		if grid.has_flag(p, exclude_flags):
			continue
		var pi := grid.idx(p)
		for d in 4:
			var v := p + LevelGrid.DIRS[d]
			if not grid.in_bounds(v) or grid.kind(v) != LevelGrid.VOID or not _carvable(grid, v):
				continue
			for d2 in 4:
				var q := v + LevelGrid.DIRS[d2]
				if q == p or grid.kind(q) != LevelGrid.FLOOR or grid.has_flag(q, exclude_flags):
					continue
				if not level_pair(grid, p, q):
					continue
				var qi := grid.idx(q)
				var bound := 0
				for f in fields:
					if f[pi] >= 0 and f[qi] >= 0:
						bound = maxi(bound, absi(f[pi] - f[qi]))
				if bound >= min_cells:
					options.append(Vector3i(p.x, p.y, d))
					stubs.append(q)
	if options.is_empty():
		return Vector3i(-1, -1, -1)
	var k := rng.randi_range(0, options.size() - 1)
	var e := options[k]
	var p := Vector2i(e.x, e.y)
	var v := p + LevelGrid.DIRS[e.z]
	var q := stubs[k]
	grid.set_kind(v, LevelGrid.FLOOR)
	grid.set_floor_y(v, grid.floor_y(q))
	grid.deck[grid.idx(v)] = grid.deck[grid.idx(q)]
	for d in 4:
		grid.set_wall(v, d, LevelGrid.WALL)
	grid.set_wall(v, LevelGrid.DIRS.find(q - v), LevelGrid.NONE)
	grid.set_wall(p, e.z, LevelGrid.SOFT)
	# Soft wall lists hold E and S edges.
	if e.z == LevelGrid.N or e.z == LevelGrid.W:
		return Vector3i(v.x, v.y, LevelGrid.opposite(e.z))
	return e


## A void cell a shortcut may be cut through: not a pillar, not part of a solid core.
static func _carvable(grid: LevelGrid, v: Vector2i) -> bool:
	if grid.is_pillar(v):
		return false
	for d in 4:
		if grid.wall(v, d) == LevelGrid.SOLID and grid.in_bounds(v + LevelGrid.DIRS[d]):
			return false
	return true


## Marks up to `count` soft walls from the candidates, preferring edges next to dead ends
## (weight 3) and spreading them at least `spacing` cells apart. Returns the edges marked.
static func mark_soft_walls(grid: LevelGrid, candidates: Array[Vector3i], count: int, spacing: int,
		rng: RandomNumberGenerator, already: Array[Vector3i] = []) -> Array[Vector3i]:
	var cells: Array[Vector2i] = []
	var weights := PackedFloat32Array()
	for e in candidates:
		var a := Vector2i(e.x, e.y)
		var b := a + LevelGrid.DIRS[e.z]
		cells.append(a)
		var near_dead_end := grid.has_flag(a, LevelGrid.F_DEAD_END) or grid.has_flag(b, LevelGrid.F_DEAD_END)
		weights.append(3.0 if near_dead_end else 1.0)
	var taken: Array[Vector2i] = []
	for e in already:
		taken.append(Vector2i(e.x, e.y))
	var chosen := poisson_cells(cells, count, spacing, rng, weights, taken)
	var out: Array[Vector3i] = []
	for c in chosen:
		var k := cells.find(c)
		# Several candidates can share a cell (its E and S edges); take the first listed.
		var e := candidates[k]
		grid.set_wall(c, e.z, LevelGrid.SOFT)
		out.append(e)
	return out
