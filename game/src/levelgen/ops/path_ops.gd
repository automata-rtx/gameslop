class_name PathOps
extends RefCounted
## Distance operations of the shared ops library (07 §4): distance_field, critical_path,
## pick_far_cell. Walking respects walls: only NONE and DOOR edges are crossed on foot.


static func distance_field(grid: LevelGrid, from: Vector2i) -> PackedInt32Array:
	return grid.distance_field(from)


## Shortest walking path from `from` to `to` (inclusive), or [] when unreachable.
## Ties break by direction order N, E, S, W, so the path is deterministic. Marks
## CRITICAL_PATH on its cells (and clears the flag everywhere else) when `mark` is true.
static func critical_path(grid: LevelGrid, from: Vector2i, to: Vector2i, mark: bool = true) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var dist := grid.distance_field(to)
	if not grid.in_bounds(from) or dist[grid.idx(from)] < 0:
		return path
	var c := from
	path.append(c)
	var guard := grid.cell_count()
	while c != to and guard > 0:
		guard -= 1
		var here := dist[grid.idx(c)]
		for d in 4:
			var o := c + LevelGrid.DIRS[d]
			if grid.can_step(c, d) and dist[grid.idx(o)] == here - 1:
				c = o
				break
		path.append(c)
	if mark:
		for i in grid.cell_count():
			grid.flags[i] &= ~LevelGrid.F_CRITICAL_PATH
		for p in path:
			grid.add_flag(p, LevelGrid.F_CRITICAL_PATH)
	return path


## Walking length of a path of cells in metres (centre to centre).
static func path_length_m(path: Array[Vector2i]) -> float:
	return maxf(0.0, float(path.size() - 1)) * Tuning.GRID_CELL_SIZE


## The largest finite value in a distance field.
static func max_distance(dist: PackedInt32Array) -> int:
	var m := 0
	for d in dist:
		m = maxi(m, d)
	return m


## A cell at >= `min_fraction` of the maximum distance that passes `filter`
## (Callable(Vector2i) -> bool). With an rng the choice is uniform among them; without,
## the farthest (lowest index on ties). Returns (-1, -1) when none qualifies.
static func pick_far_cell(grid: LevelGrid, dist: PackedInt32Array, min_fraction: float,
		filter: Callable = Callable(), rng: RandomNumberGenerator = null) -> Vector2i:
	var threshold := int(ceil(max_distance(dist) * min_fraction))
	var pool: Array[Vector2i] = []
	var best := Vector2i(-1, -1)
	var best_d := -1
	for i in dist.size():
		if dist[i] < threshold:
			continue
		var c := grid.cell_at(i)
		if filter.is_valid() and not filter.call(c):
			continue
		pool.append(c)
		if dist[i] > best_d:
			best_d = dist[i]
			best = c
	if rng == null or pool.is_empty():
		return best
	return pool[rng.randi_range(0, pool.size() - 1)]
