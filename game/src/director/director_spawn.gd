class_name DirectorSpawn
extends RefCounted
## Where the Director puts errors and hints (10 §4, §7), on grid data only: spawn cells
## that are fair (≥ 20 m from the player both walking and in a straight line, outside the
## frustum and out of the player's line of sight in every direction), hint cells in rings
## around the player, and Static's critical-path cut test (08 §3, 10 §7 rule 4).
## Nothing here hands an error the player's position: a hint is always a cell at a range.

const CS := Tuning.GRID_CELL_SIZE


static func flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Horizontal half-FOV (radians) of a camera with vertical `fov_deg` and `aspect`, widened
## by the frustum margin (conservative: a point near the edge counts as in view).
static func half_fov_h(fov_deg: float, aspect: float) -> float:
	var h := atan(tan(deg_to_rad(fov_deg) * 0.5) * maxf(aspect, 1.0))
	return minf(h + deg_to_rad(Tuning.DIRECTOR_SPAWN_FRUSTUM_MARGIN_DEG), PI)


## True when `point` is inside the horizontal view cone from `eye` along `forward`.
static func in_cone(eye: Vector3, forward: Vector3, half_fov: float, point: Vector3) -> bool:
	var f := Vector2(forward.x, forward.z)
	var to := Vector2(point.x - eye.x, point.z - eye.z)
	if f.length_squared() < 0.0001 or to.length_squared() < 0.0001:
		return true
	return absf(f.angle_to(to)) <= half_fov


## 10 §4, §7 rule 1, 05 §9 rule 1: a fair spawn cell for a player at `player_pos` looking
## along `forward`. `walk` is the grid distance field from the player's cell.
static func spawn_ok(grid: LevelGrid, c: Vector2i, player_pos: Vector3, eye: Vector3, forward: Vector3,
		half_fov: float, walk: PackedInt32Array) -> bool:
	if not grid.in_bounds(c) or not grid.is_walkable(c):
		return false
	var w := walk[grid.idx(c)]
	if w < 0 or w * CS < Tuning.DIRECTOR_SPAWN_MIN_WALK_DIST:
		return false
	var p := grid.world_of(c)
	if flat_dist(p, player_pos) < Tuning.ERROR_SPAWN_MIN_DIST:
		return false
	var probe := p + Vector3.UP * Tuning.DIRECTOR_SPAWN_EYE_HEIGHT
	if in_cone(eye, forward, half_fov, probe):
		return false
	# Line of sight in any direction: the player could turn before the error moves.
	return not SightOps.clear(grid, eye, probe)


## Fraction (0..1) along the critical path of the path cell nearest to `c`.
static func path_fraction(path: Array[Vector2i], c: Vector2i) -> float:
	if path.size() < 2:
		return 0.0
	var best := 0
	var best_d := INF
	for i in path.size():
		var d := Vector2(path[i] - c).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return float(best) / float(path.size() - 1)


## Cells for each id of `roster` (NO_CELL when nothing fair exists), distinct, from the
## level's error_spawn placements first and any fair walkable cell second. The native
## hunter prefers 35% to 65% of the critical path; the others prefer side branches; Static
## is never within 20 m of the spawn room. Hunters choose before Statics; with nothing fair
## outside the rooms a hunter takes `farthest_cell(..., fair_only)` (a fair room cell) or
## NO_CELL (the Director retries it, `DirectorHunters.spawn_pending`); Static always
## spawns (M1.13 ruling): with no fair cell it takes the farthest legal one (`farthest_cell`). `band` (cell -> true, the
## first Descent's breaker-to-exit stretch, `breaker_exit_band`) is where the first Static
## goes when a fair cell lies in it (05 §10, M1.13 ruling).
static func pick_cells(data: LevelData, roster: Array[StringName], native: StringName, player_pos: Vector3,
		eye: Vector3, forward: Vector3, half_fov: float, rng: RandomNumberGenerator,
		band: Dictionary = {}) -> Array[Vector2i]:
	var grid := data.grid
	var walk := grid.distance_field(grid.cell_of(player_pos))
	var markers: Array[Vector2i] = []
	var off_path: Dictionary = {}
	for p in data.placements_of(LevelData.P_ERROR_SPAWN):
		var c: Vector2i = p[&"cell"]
		if spawn_ok(grid, c, player_pos, eye, forward, half_fov, walk) and not markers.has(c):
			markers.append(c)
			off_path[c] = bool((p.get(&"params", {}) as Dictionary).get(&"off_path", false))
	var fallback: Array[Vector2i] = []
	var fallback_done := false
	var spawn_room := _spawn_room_cells(data)
	var out: Array[Vector2i] = []
	out.resize(roster.size())
	out.fill(LevelData.NO_CELL)
	var used: Array[Vector2i] = []
	# Hunters choose first: Static always has a last resort (M1.13), a hunter only a fair one.
	var order: Array[int] = []
	for pass_hunters: bool in [true, false]:
		for i in roster.size():
			if DirectorRules.is_hunter(roster[i]) == pass_hunters:
				order.append(i)
	var band_done := band.is_empty()
	for i in order:
		var id := roster[i]
		var cell := LevelData.NO_CELL
		if id == &"static" and not band_done:
			# The first Static on the first Descent: a fair cell between the breaker and the exit.
			band_done = true
			if not fallback_done:
				fallback_done = true
				fallback = _fallback_cells(grid, player_pos, eye, forward, half_fov, walk)
			var both: Array[Vector2i] = markers.duplicate()
			both.append_array(fallback)
			var in_band: Array[Vector2i] = []
			for c in _eligible(both, used, id, spawn_room):
				if band.has(c) and not in_band.has(c):
					in_band.append(c)
			if not in_band.is_empty():
				cell = in_band[rng.randi_range(0, in_band.size() - 1)]
		if cell == LevelData.NO_CELL:
			cell = _pick_one(data, id, native, markers, off_path, used, spawn_room, rng)
		if cell == LevelData.NO_CELL and not fallback_done:
			fallback_done = true
			fallback = _fallback_cells(grid, player_pos, eye, forward, half_fov, walk)
		if cell == LevelData.NO_CELL:
			cell = _pick_one(data, id, native, fallback, off_path, used, spawn_room, rng)
		if cell == LevelData.NO_CELL:
			# Last resort: a hunter only on a fair cell (the spawn and exit rooms allowed);
			# Static always, at the farthest cell when nothing fair is left (M1.13).
			cell = farthest_cell(grid, used, player_pos, eye, forward, half_fov, walk, id != &"static")
		out[i] = cell
		if cell != LevelData.NO_CELL:
			used.append(cell)
	return out


## One cell for `id` from `cells` (not `used`): Null takes LevelData.null_spawn_cell when
## it is eligible; the native hunter prefers 35% to 65% of the critical path, the others
## side branches. NO_CELL when none is eligible.
static func _pick_one(data: LevelData, id: StringName, native: StringName, cells: Array[Vector2i], off_path: Dictionary,
		used: Array[Vector2i], spawn_room: Array[Vector3], rng: RandomNumberGenerator) -> Vector2i:
	var pool := _eligible(cells, used, id, spawn_room)
	if pool.is_empty():
		return LevelData.NO_CELL
	if id == &"null" and pool.has(data.null_spawn_cell):
		# 07 §5.6: Null's own spawn point, the critical path at 55% (when it is fair now).
		return data.null_spawn_cell
	var preferred: Array[Vector2i] = []
	for c in pool:
		if id == native and DirectorRules.is_hunter(id):
			var f := path_fraction(data.critical_path, c)
			if f >= Tuning.DIRECTOR_SPAWN_NATIVE_PATH_MIN and f <= Tuning.DIRECTOR_SPAWN_NATIVE_PATH_MAX:
				preferred.append(c)
		elif bool(off_path.get(c, false)) or not data.grid.has_flag(c, LevelGrid.F_CRITICAL_PATH):
			preferred.append(c)
	var from := preferred if not preferred.is_empty() else pool
	return from[rng.randi_range(0, from.size() - 1)]


## Every fair walkable cell outside the spawn and exit rooms.
static func _fallback_cells(grid: LevelGrid, player_pos: Vector3, eye: Vector3, forward: Vector3, half_fov: float,
		walk: PackedInt32Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in grid.cell_count():
		var c := grid.cell_at(i)
		if grid.has_flag(c, LevelGrid.F_SPAWN_ROOM) or grid.has_flag(c, LevelGrid.F_EXIT_ROOM):
			continue
		if spawn_ok(grid, c, player_pos, eye, forward, half_fov, walk):
			out.append(c)
	return out


## The last resort (M1.13 ruling): the walkable cell farthest (walking) from the player that
## is fair (`spawn_ok`, any room), else (Static only, `fair_only` false) the farthest
## reachable cell, else the farthest walkable one; never a cell in `used`. NO_CELL on an
## empty grid, or with `fair_only` (a hunter) when no cell is fair.
static func farthest_cell(grid: LevelGrid, used: Array[Vector2i], player_pos: Vector3, eye: Vector3,
		forward: Vector3, half_fov: float, walk: PackedInt32Array, fair_only: bool = false) -> Vector2i:
	var order: Array[Vector2i] = []
	for i in grid.cell_count():
		var c := grid.cell_at(i)
		if grid.is_walkable(c) and not used.has(c):
			order.append(c)
	if order.is_empty():
		return LevelData.NO_CELL
	order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var wa := walk[grid.idx(a)]
		var wb := walk[grid.idx(b)]
		if wa != wb:
			return wa > wb
		return flat_dist(grid.world_of(a), player_pos) > flat_dist(grid.world_of(b), player_pos))
	for c in order:
		if walk[grid.idx(c)] < 0:
			break
		if spawn_ok(grid, c, player_pos, eye, forward, half_fov, walk):
			return c
	return LevelData.NO_CELL if fair_only else order[0]


static func _eligible(cells: Array[Vector2i], used: Array[Vector2i], id: StringName, spawn_room: Array[Vector3]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in cells:
		if used.has(c):
			continue
		if id == &"static" and _near_any(c, spawn_room, Tuning.STATIC_SPAWN_MIN_FROM_SPAWN_ROOM):
			continue
		out.append(c)
	return out


static func _spawn_room_cells(data: LevelData) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var g := data.grid
	for i in g.cell_count():
		var c := g.cell_at(i)
		if g.has_flag(c, LevelGrid.F_SPAWN_ROOM):
			out.append(g.world_of(c))
	if out.is_empty() and data.spawn_cell != LevelData.NO_CELL:
		out.append(g.world_of(data.spawn_cell))
	return out


static func _near_any(c: Vector2i, points: Array[Vector3], dist: float) -> bool:
	var p := Vector3(c.x * CS, 0.0, c.y * CS)
	for q in points:
		if flat_dist(p, q) < dist:
			return true
	return false


# --- 05 §10 first Descent: the first Static between the breaker and the exit -----------------

## Walkable cells within `near` m (straight line) of the critical path's stretch from the
## breaker (its nearest path cell) to the exit, outside the spawn and exit rooms. Empty
## without a breaker or a path. Cell -> true.
static func breaker_exit_band(data: LevelData, near: float = Tuning.DIRECTOR_FD_STATIC_PATH_BAND) -> Dictionary:
	var out: Dictionary = {}
	var path := data.critical_path
	var grid := data.grid
	if grid == null or path.size() < 2 or data.breaker_cell == LevelData.NO_CELL:
		return out
	var from := roundi(path_fraction(path, data.breaker_cell) * float(path.size() - 1))
	var stretch: Array[Vector2i] = []
	for i in range(from, path.size()):
		if not grid.has_flag(path[i], LevelGrid.F_EXIT_ROOM):
			stretch.append(path[i])
	var r := near / CS
	for i in grid.cell_count():
		var c := grid.cell_at(i)
		if not grid.is_walkable(c) or grid.has_flag(c, LevelGrid.F_SPAWN_ROOM) or grid.has_flag(c, LevelGrid.F_EXIT_ROOM):
			continue
		for p in stretch:
			if Vector2(p - c).length() <= r:
				out[c] = true
				break
	return out


# --- hints --------------------------------------------------------------------------------

## A random walkable cell whose straight-line distance from `centre` is in [rmin, rmax]
## (and passes `filter`); without one, the cell closest to the ring. NO_CELL on an empty grid.
static func cell_in_ring(grid: LevelGrid, centre: Vector3, rmin: float, rmax: float, rng: RandomNumberGenerator,
		filter: Callable = Callable()) -> Vector2i:
	var pool: Array[Vector2i] = []
	var best := LevelData.NO_CELL
	var best_err := INF
	for i in grid.cell_count():
		var c := grid.cell_at(i)
		if not grid.is_walkable(c) or (filter.is_valid() and not bool(filter.call(c))):
			continue
		var d := flat_dist(grid.world_of(c), centre)
		if d >= rmin and d <= rmax:
			pool.append(c)
		else:
			var err := rmin - d if d < rmin else d - rmax
			if err < best_err:
				best_err = err
				best = c
	if not pool.is_empty():
		return pool[rng.randi_range(0, pool.size() - 1)]
	return best


## "A cell `d` m from the player" (wake hint 12 m, awake arrival 30 m), within one cell.
static func cell_at_distance(grid: LevelGrid, centre: Vector3, d: float, rng: RandomNumberGenerator) -> Vector2i:
	return cell_in_ring(grid, centre, d - Tuning.DIRECTOR_HINT_DIST_TOLERANCE, d + Tuning.DIRECTOR_HINT_DIST_TOLERANCE, rng)


## The nearest walkable cell (walking) to `from` that is off the critical path by at least
## the clearance, within the search radius. NO_CELL if none.
static func off_path_cell(grid: LevelGrid, path: Array[Vector2i], from: Vector3) -> Vector2i:
	var start := grid.cell_of(from)
	if not grid.in_bounds(start) or not grid.is_walkable(start):
		return LevelData.NO_CELL
	var walk := grid.distance_field(start)
	var best := LevelData.NO_CELL
	var best_w := Tuning.DIRECTOR_STATIC_OFF_PATH_SEARCH_CELLS + 1
	var clear_cells := Tuning.DIRECTOR_STATIC_OFF_PATH_CLEARANCE / CS
	for i in walk.size():
		var w := walk[i]
		if w < 0 or w >= best_w:
			continue
		var c := grid.cell_at(i)
		# 10 §7 rule 9: never into the Threshold pocket (the exit room).
		var ok := not grid.has_flag(c, LevelGrid.F_EXIT_ROOM)
		for p in path:
			if not ok:
				break
			if Vector2(p - c).length() < clear_cells:
				ok = false
				break
		if ok:
			best = c
			best_w = w
	return best


## Pursuit: a critical-path cell outside the Threshold pocket (10 §7 rule 9).
static func critical_cell(grid: LevelGrid, path: Array[Vector2i], rng: RandomNumberGenerator) -> Vector2i:
	var pool: Array[Vector2i] = []
	for c in path:
		if not grid.has_flag(c, LevelGrid.F_EXIT_ROOM):
			pool.append(c)
	if pool.is_empty():
		return LevelData.NO_CELL
	return pool[rng.randi_range(0, pool.size() - 1)]


# --- 08 §3 Static cut test ----------------------------------------------------------------

## True when a field at `centre` with `radius` covers a critical-path cell and blocks every
## walking route from `from` to `to` (the cut test). The start cell itself never blocks.
static func static_cuts_path(grid: LevelGrid, centre: Vector3, radius: float, from: Vector2i, to: Vector2i) -> bool:
	if not grid.in_bounds(from) or not grid.in_bounds(to) or not grid.is_walkable(from) or not grid.is_walkable(to):
		return false
	var covered: Dictionary = {}
	var on_path := false
	var span := int(ceil(radius / CS)) + 1
	var cc := grid.cell_of(centre)
	for dz in range(-span, span + 1):
		for dx in range(-span, span + 1):
			var c := cc + Vector2i(dx, dz)
			if grid.in_bounds(c) and grid.is_walkable(c) and flat_dist(grid.world_of(c), centre) < radius:
				covered[c] = true
				on_path = on_path or grid.has_flag(c, LevelGrid.F_CRITICAL_PATH)
	if not on_path:
		return false
	if covered.has(to):
		return true
	covered.erase(from)
	var seen: Dictionary = {from: true}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		if c == to:
			return false
		for d in 4:
			if not grid.can_step(c, d):
				continue
			var n := c + LevelGrid.DIRS[d]
			if seen.has(n) or covered.has(n):
				continue
			seen[n] = true
			queue.append(n)
	return true


# --- 05 §10 first-Descent Static side loop ---------------------------------------------------

## The cells Static may drift through on the first Descent: the walkable region reachable
## from `from` without coming within the off-path clearance (6 m) of a critical-path cell,
## the spawn room or the exit room. When that region is too small to drift in (fewer than
## 3 cells), only the critical path and those rooms are excluded. Cell -> true.
static func side_loop_cells(grid: LevelGrid, path: Array[Vector2i], from: Vector3) -> Dictionary:
	for clearance: float in [Tuning.DIRECTOR_STATIC_OFF_PATH_CLEARANCE, 0.0]:
		var ok := _region(grid, path, from, clearance)
		if ok.size() >= 3:
			return ok
	return {}


static func _region(grid: LevelGrid, path: Array[Vector2i], from: Vector3, clearance: float) -> Dictionary:
	var clear_cells := clearance / CS
	var allowed := func(c: Vector2i) -> bool:
		if not grid.in_bounds(c) or not grid.is_walkable(c):
			return false
		if grid.has_flag(c, LevelGrid.F_CRITICAL_PATH) or grid.has_flag(c, LevelGrid.F_SPAWN_ROOM) \
				or grid.has_flag(c, LevelGrid.F_EXIT_ROOM):
			return false
		if clear_cells > 0.0:
			for p in path:
				if Vector2(p - c).length() < clear_cells:
					return false
		return true
	# Start at the allowed cell nearest (walking) to `from`.
	var start := grid.cell_of(from)
	if not grid.in_bounds(start) or not grid.is_walkable(start):
		return {}
	if not bool(allowed.call(start)):
		var walk := grid.distance_field(start)
		var best := LevelData.NO_CELL
		var best_w := 1 << 30
		for i in walk.size():
			if walk[i] >= 0 and walk[i] < best_w and bool(allowed.call(grid.cell_at(i))):
				best = grid.cell_at(i)
				best_w = walk[i]
		if best == LevelData.NO_CELL:
			return {}
		start = best
	var out: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for d in 4:
			if not grid.can_step(c, d):
				continue
			var n := c + LevelGrid.DIRS[d]
			if out.has(n) or not bool(allowed.call(n)):
				continue
			out[n] = true
			queue.append(n)
	return out


## A wander filter over `allowed` cells: takes a grid cell (Vector2i) or a world position
## (Vector3) and answers whether Static may drift there.
static func cell_filter(grid: LevelGrid, allowed: Dictionary) -> Callable:
	return func(where: Variant) -> bool:
		var c: Vector2i = grid.cell_of(where) if where is Vector3 else where
		return allowed.has(c)
