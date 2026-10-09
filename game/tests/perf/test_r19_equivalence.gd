extends TestCase
## R19: the arrival and Relief-entry speedups change no answer. On generated levels (the
## Server and Offices at Cycle 2 depth 5, the Garage at depth 4), the rewritten searches
## agree with their pre-R19 forms kept here: the hint ring (cell_in_ring), the Static's
## off-path cell (the cached mask), the Static's BFS cell path (open_mask), the fair-cell
## scan (`_fallback_cells`, also in chunks), the last-resort `farthest_cell`, and pick_cells
## with its rng-free parts made ahead (pick_context + fallback_chunk) draws the same cells.

const SAMPLES := 120

var _levels: Array[LevelData] = []


func before_all() -> void:
	for spec: Array in [[Tuning.STRATUM_SERVER, 11], [&"offices", 11], [&"garage", 10]]:
		var stratum: StringName = spec[0]
		var depth: int = spec[1]
		_levels.append(LevelGenerator.generate(stratum, depth, PerfBench.seed_for(stratum, depth), false, 2))


# --- the pre-R19 forms --------------------------------------------------------------------

static func _ring_old(grid: LevelGrid, centre: Vector3, rmin: float, rmax: float, rng: RandomNumberGenerator) -> Vector2i:
	var pool: Array[Vector2i] = []
	var best := LevelData.NO_CELL
	var best_err := INF
	for i in grid.cell_count():
		var c := grid.cell_at(i)
		if not grid.is_walkable(c):
			continue
		var d := DirectorSpawn.flat_dist(grid.world_of(c), centre)
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


static func _off_path_old(grid: LevelGrid, path: Array[Vector2i], from: Vector3) -> Vector2i:
	var start := grid.cell_of(from)
	if not grid.in_bounds(start) or not grid.is_walkable(start):
		return LevelData.NO_CELL
	var walk := grid.distance_field(start)
	var best := LevelData.NO_CELL
	var best_w := Tuning.DIRECTOR_STATIC_OFF_PATH_SEARCH_CELLS + 1
	var clear_cells := Tuning.DIRECTOR_STATIC_OFF_PATH_CLEARANCE / Tuning.GRID_CELL_SIZE
	for i in walk.size():
		var w := walk[i]
		if w < 0 or w >= best_w:
			continue
		var c := grid.cell_at(i)
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


static func _cell_path_old(g: LevelGrid, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if from == to:
		out.append(to)
		return out
	var prev := PackedInt32Array()
	prev.resize(g.cell_count())
	prev.fill(-1)
	var start := g.idx(from)
	var goal := g.idx(to)
	prev[start] = start
	var queue := PackedInt32Array([start])
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		if i == goal:
			break
		var c := g.cell_at(i)
		for d in 4:
			if not g.can_step(c, d):
				continue
			var j := g.idx(c + LevelGrid.DIRS[d])
			if prev[j] == -1:
				prev[j] = i
				queue.append(j)
	if prev[goal] == -1:
		return out
	var k := goal
	while k != start:
		out.push_front(g.cell_at(k))
		k = prev[k]
	return out


static func _fallback_old(grid: LevelGrid, pos: Vector3, eye: Vector3, fwd: Vector3, half: float,
		walk: PackedInt32Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in grid.cell_count():
		var c := grid.cell_at(i)
		if grid.has_flag(c, LevelGrid.F_SPAWN_ROOM) or grid.has_flag(c, LevelGrid.F_EXIT_ROOM):
			continue
		if DirectorSpawn.spawn_ok(grid, c, pos, eye, fwd, half, walk):
			out.append(c)
	return out


static func _farthest_old(grid: LevelGrid, used: Array[Vector2i], pos: Vector3, eye: Vector3, fwd: Vector3,
		half: float, walk: PackedInt32Array, fair_only: bool) -> Vector2i:
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
		return DirectorSpawn.flat_dist(grid.world_of(a), pos) > DirectorSpawn.flat_dist(grid.world_of(b), pos))
	for c in order:
		if walk[grid.idx(c)] < 0:
			break
		if DirectorSpawn.spawn_ok(grid, c, pos, eye, fwd, half, walk):
			return c
	return LevelData.NO_CELL if fair_only else order[0]


# --- helpers ------------------------------------------------------------------------------

static func _walkable(g: LevelGrid) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in g.cell_count():
		if g.is_walkable_i(i):
			out.append(g.cell_at(i))
	return out


## A pose at walkable cell `c` looking along `yaw`, with a jittered position.
static func _pose(g: LevelGrid, c: Vector2i, yaw: float, rng: RandomNumberGenerator) -> Array:
	var pos := g.world_of(c) + Vector3(rng.randf_range(-0.9, 0.9), 0.0, rng.randf_range(-0.9, 0.9))
	var eye := pos + Vector3.UP * Tuning.PLAYER_CAMERA_HEIGHT
	var fwd := Vector3(sin(yaw), 0.0, -cos(yaw))
	return [pos, eye, fwd]


# --- the tests ----------------------------------------------------------------------------

func test_hint_ring_matches_the_old_scan() -> void:
	var rng := make_rng(19)
	for data in _levels:
		var g := data.grid
		var cells := _walkable(g)
		for k in SAMPLES:
			var centre := _pose(g, cells[rng.randi_range(0, cells.size() - 1)], 0.0, rng)[0] as Vector3
			var rmin := rng.randf_range(0.0, 40.0)
			var rmax := rmin + rng.randf_range(0.0, 20.0)
			var seed_value := rng.randi()
			var a := _ring_old(g, centre, rmin, rmax, make_rng(seed_value))
			var b := DirectorSpawn.cell_in_ring(g, centre, rmin, rmax, make_rng(seed_value))
			assert_eq(b, a, "%s ring %.1f..%.1f from %s" % [data.stratum, rmin, rmax, centre])


func test_off_path_cell_matches_the_old_scan() -> void:
	var rng := make_rng(7)
	for data in _levels:
		var g := data.grid
		var cells := _walkable(g)
		var mask := DirectorSpawn.off_path_mask(g, data.critical_path)
		for k in SAMPLES:
			var from := _pose(g, cells[rng.randi_range(0, cells.size() - 1)], 0.0, rng)[0] as Vector3
			var want := _off_path_old(g, data.critical_path, from)
			assert_eq(DirectorSpawn.off_path_cell(g, data.critical_path, from, mask), want, "%s off path from %s (cached mask)" % [data.stratum, from])
			assert_eq(DirectorSpawn.off_path_cell(g, data.critical_path, from), want, "%s off path from %s" % [data.stratum, from])


func test_static_cell_path_matches_the_old_search() -> void:
	var rng := make_rng(3)
	for data in _levels:
		var g := data.grid
		var cells := _walkable(g)
		for k in SAMPLES:
			var a := cells[rng.randi_range(0, cells.size() - 1)]
			var b := cells[rng.randi_range(0, cells.size() - 1)]
			assert_eq(StaticPaths.cell_path(g, a, b), _cell_path_old(g, a, b), "%s path %s -> %s" % [data.stratum, a, b])
		# Blocked or unreachable ends: both empty.
		for i in g.cell_count():
			if not g.is_walkable_i(i):
				var c := g.cell_at(i)
				assert_eq(StaticPaths.cell_path(g, cells[0], c), _cell_path_old(g, cells[0], c), "to a wall cell")
				break


func test_fair_cells_and_pick_cells_match() -> void:
	var rng := make_rng(11)
	var half := DirectorSpawn.half_fov_h(70.0, 16.0 / 9.0)
	var rosters: Array = [
		[&"static", &"static", &"static", &"still", &"echo", &"flicker"],
		[&"still", &"static"], [&"static", &"static", &"static", &"static", &"static", &"static", &"static", &"static"],
	]
	for data in _levels:
		var g := data.grid
		var cells := _walkable(g)
		for k in 12:
			var pose := _pose(g, cells[rng.randi_range(0, cells.size() - 1)], rng.randf_range(-PI, PI), rng)
			var pos: Vector3 = pose[0]
			var eye: Vector3 = pose[1]
			var fwd: Vector3 = pose[2]
			var walk := g.distance_field(g.cell_of(pos))
			var old := _fallback_old(g, pos, eye, fwd, half, walk)
			assert_eq(DirectorSpawn._fallback_cells(g, pos, eye, fwd, half, walk), old, "%s fair cells" % data.stratum)
			var ctx := DirectorSpawn.pick_context(data, pos)
			var guard := 0
			while not DirectorSpawn.fallback_chunk(data, ctx, pos, eye, fwd, half, DirectorArrival.FALLBACK_CHUNK_CELLS) and guard < 1000:
				guard += 1
			assert_eq(ctx[&"fallback"], old, "%s fair cells in chunks" % data.stratum)
			var used: Array[Vector2i] = []
			for u in 3:
				used.append(cells[rng.randi_range(0, cells.size() - 1)])
			for fair_only: bool in [true, false]:
				assert_eq(DirectorSpawn.farthest_cell(g, used, pos, eye, fwd, half, walk, fair_only),
					_farthest_old(g, used, pos, eye, fwd, half, walk, fair_only), "%s farthest (fair only %s)" % [data.stratum, fair_only])
			for roster: Array in rosters:
				var ids: Array[StringName] = []
				ids.assign(roster)
				var seed_value := rng.randi()
				var r1 := make_rng(seed_value)
				var r2 := make_rng(seed_value)
				var a := DirectorSpawn.pick_cells(data, ids, &"still", pos, eye, fwd, half, r1)
				var b := DirectorSpawn.pick_cells(data, ids, &"still", pos, eye, fwd, half, r2, {}, ctx)
				assert_eq(b, a, "%s pick_cells with the context made ahead" % data.stratum)
				assert_eq(r2.state, r1.state, "%s: the same draws" % data.stratum)
