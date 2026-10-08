extends TestCase
## 10 §4, §7 rule 1, 05 §9 rule 1: spawn fairness over many seeds on real Halls levels (grid
## data from the generator): every picked cell is ≥ 20 m from the player walking and in a
## straight line, outside the view cone, out of the grid line of sight, distinct, and
## Static is never within 20 m of the spawn room. Also: hint rings, and Static's cut test.

const SEEDS := 40
const POSES_PER_SEED := 4
const FOV := 75.0
const ASPECT := 16.0 / 9.0


func _forward(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func test_spawn_fairness_over_many_halls_seeds() -> void:
	var half := DirectorSpawn.half_fov_h(FOV, ASPECT)
	var picked := 0
	var missing := 0
	for s in range(1, SEEDS + 1):
		var data := LevelGenerator.generate(&"halls", 1 + s % 3, s)
		var g := data.grid
		var rng := make_rng(s)
		for pose in POSES_PER_SEED:
			var cell := data.spawn_cell if pose == 0 else g.random_walkable_cell(rng)
			var pos := g.world_of(cell)
			var eye := pos + Vector3.UP * Tuning.PLAYER_CAMERA_HEIGHT
			var yaw := LevelData.yaw_facing(data.spawn_dir) if pose == 0 else rng.randf() * TAU
			var fwd := _forward(yaw)
			var roster: Array[StringName] = [&"static", &"still", &"still", &"static"]
			var cells := DirectorSpawn.pick_cells(data, roster, &"still", pos, eye, fwd, half, rng)
			assert_eq(cells.size(), roster.size())
			var walk := g.distance_field(cell)
			var spawn_room := DirectorSpawn._spawn_room_cells(data)
			var seen: Dictionary = {}
			for i in cells.size():
				var c := cells[i]
				if c == LevelData.NO_CELL:
					missing += 1
					continue
				picked += 1
				var p := g.world_of(c)
				var probe := p + Vector3.UP * Tuning.DIRECTOR_SPAWN_EYE_HEIGHT
				var ctx := "seed %d pose %d %s at %s" % [s, pose, roster[i], c]
				assert_false(seen.has(c), "distinct: " + ctx)
				seen[c] = true
				assert_true(DirectorSpawn.flat_dist(p, pos) >= Tuning.ERROR_SPAWN_MIN_DIST, "≥ 20 m straight: " + ctx)
				assert_true(walk[g.idx(c)] * Tuning.GRID_CELL_SIZE >= Tuning.DIRECTOR_SPAWN_MIN_WALK_DIST, "≥ 20 m walking: " + ctx)
				assert_false(DirectorSpawn.in_cone(eye, fwd, half, probe), "outside the frustum: " + ctx)
				assert_false(SightOps.clear(g, eye, probe), "out of line of sight: " + ctx)
				if roster[i] == &"static":
					assert_false(DirectorSpawn._near_any(c, spawn_room, Tuning.STATIC_SPAWN_MIN_FROM_SPAWN_ROOM),
						"Static ≥ 20 m from the spawn room: " + ctx)
	assert_gt(picked, SEEDS * POSES_PER_SEED * 3, "nearly every roster entry found a fair cell (%d missing)" % missing)


func test_spawn_prefers_markers_and_path_band_for_the_native() -> void:
	var data := LevelGenerator.generate(&"halls", 2, 7)
	var g := data.grid
	var pos := g.world_of(data.spawn_cell)
	var eye := pos + Vector3.UP * Tuning.PLAYER_CAMERA_HEIGHT
	var fwd := _forward(LevelData.yaw_facing(data.spawn_dir))
	var half := DirectorSpawn.half_fov_h(FOV, ASPECT)
	var markers: Array[Vector2i] = []
	for p in data.placements_of(LevelData.P_ERROR_SPAWN):
		markers.append(p[&"cell"])
	var on_marker := 0
	var in_band := 0
	for s in 20:
		var roster: Array[StringName] = [&"still"]
		var c := DirectorSpawn.pick_cells(data, roster, &"still", pos, eye, fwd, half, make_rng(s))[0]
		on_marker += 1 if markers.has(c) else 0
		var f := DirectorSpawn.path_fraction(data.critical_path, c)
		in_band += 1 if f >= Tuning.DIRECTOR_SPAWN_NATIVE_PATH_MIN and f <= Tuning.DIRECTOR_SPAWN_NATIVE_PATH_MAX else 0
	assert_eq(on_marker, 20, "error_spawn markers first")
	assert_gt(in_band, 0, "the native hunter lands in the 35% to 65% band when a marker is there")


func test_hint_rings_never_name_the_player_cell() -> void:
	var data := LevelGenerator.generate(&"halls", 1, 3)
	var g := data.grid
	var rng := make_rng(3)
	for i in 50:
		var cell := g.random_walkable_cell(rng)
		var pos := g.world_of(cell)
		var c := DirectorSpawn.cell_in_ring(g, pos, Tuning.DIRECTOR_HINT_RANGE_MIN, Tuning.DIRECTOR_HINT_RANGE_MAX, rng)
		assert_ne(c, LevelData.NO_CELL)
		var d := DirectorSpawn.flat_dist(g.world_of(c), pos)
		assert_true(d >= Tuning.DIRECTOR_HINT_RANGE_MIN - 0.01 and d <= Tuning.DIRECTOR_HINT_RANGE_MAX + 0.01, "hint 15 to 30 m (%.1f)" % d)
		var a := DirectorSpawn.cell_at_distance(g, pos, Tuning.AWAKE_SEARCH_DIST, rng)
		var da := DirectorSpawn.flat_dist(g.world_of(a), pos)
		assert_true(absf(da - Tuning.AWAKE_SEARCH_DIST) <= Tuning.DIRECTOR_HINT_DIST_TOLERANCE + 0.01 or da > 20.0,
			"awake arrival cell about 30 m out (%.1f)" % da)


func _grid(cells: Array[Vector2i]) -> LevelGrid:
	var g := LevelGrid.new(Vector2i(12, 6))
	for c in cells:
		g.set_kind(c, LevelGrid.FLOOR)
		if c.y == 2:
			g.add_flag(c, LevelGrid.F_CRITICAL_PATH)
	for c in cells:
		for d in [LevelGrid.E, LevelGrid.S]:
			if cells.has(c + LevelGrid.DIRS[d]):
				g.set_wall(c, d, LevelGrid.NONE)
	g.finalize_walls()
	return g


## A 1-wide corridor of 10 cells: a field over its middle cuts the only route; a parallel
## loop gives a second route, and an off-path cell exists on it.
func test_static_cut_test() -> void:
	var corridor: Array[Vector2i] = []
	for x in range(1, 11):
		corridor.append(Vector2i(x, 2))
	var g := _grid(corridor)
	var from := Vector2i(1, 2)
	var to := Vector2i(10, 2)
	assert_true(DirectorSpawn.static_cuts_path(g, g.world_of(Vector2i(5, 2)), 3.0, from, to), "covers the corridor")
	assert_false(DirectorSpawn.static_cuts_path(g, Vector3(10.0, 0.0, 40.0), 3.0, from, to), "far away")
	var loop := corridor.duplicate()
	for x in range(1, 11):
		loop.append(Vector2i(x, 5))
	for y in [3, 4]:
		loop.append(Vector2i(1, y))
		loop.append(Vector2i(10, y))
	var g2 := _grid(loop)
	assert_false(DirectorSpawn.static_cuts_path(g2, g2.world_of(Vector2i(5, 2)), 1.5, from, to), "a second route exists")
	var off := DirectorSpawn.off_path_cell(g2, corridor, g2.world_of(Vector2i(5, 2)))
	assert_ne(off, LevelData.NO_CELL, "an off-path cell on the loop")
	if off != LevelData.NO_CELL:
		assert_eq(off.y, 5)
