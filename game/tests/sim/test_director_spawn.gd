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
			var fair := DirectorSpawn._fallback_cells(g, pos, eye, fwd, half, walk)
			for p in data.placements_of(LevelData.P_ERROR_SPAWN):
				if DirectorSpawn.spawn_ok(g, p[&"cell"], pos, eye, fwd, half, walk) and not fair.has(p[&"cell"]):
					fair.append(p[&"cell"])
			var seen: Dictionary = {}
			for i in cells.size():
				var c := cells[i]
				if c == LevelData.NO_CELL:
					missing += 1
					continue
				picked += 1
				# Hunters choose first, then the Statics in roster order.
				var before: Array[Vector2i] = []
				for j in cells.size():
					if cells[j] != LevelData.NO_CELL and (DirectorRules.is_hunter(roster[j]) or j < i):
						before.append(cells[j])
				before.erase(c)
				if roster[i] == &"static" and DirectorSpawn._eligible(fair, before, &"static", spawn_room).is_empty():
					# No fair cell left: Static's last resort, the farthest legal cell (M1.13).
					assert_eq(c, DirectorSpawn.farthest_cell(g, before, pos, eye, fwd, half, walk),
						"seed %d pose %d: Static at the farthest legal cell" % [s, pose])
					seen[c] = true
					continue
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


func _spawn_pose(data: LevelData) -> Array:
	var pos := data.grid.world_of(data.spawn_cell)
	return [pos, pos + Vector3.UP * Tuning.PLAYER_CAMERA_HEIGHT, _forward(LevelData.yaw_facing(data.spawn_dir))]


## M1.13 ruling: every depth-2 level of a run (its stratum from the run seed, generated as
## the run does) spawns a hunter (an unbuilt native becomes Still) and a Static, from the
## player's arrival pose.
func test_every_depth_2_level_has_a_hunter_and_a_static() -> void:
	var half := DirectorSpawn.half_fov_h(FOV, ASPECT)
	for s in range(1, 21):
		var stratum: StringName = GameState.strata_order_for(s)[1]
		var build := stratum if LevelGenerator.supports(stratum) else Tuning.STRATUM_DEPTH1
		# The run's options (Run._begin_generation), so the level is the one a run builds.
		var options := {&"item_pool": RunLevelSetup.item_pool(MetaState.new(), false), &"fuse_unlocked": false,
			&"endless": false}
		var data := LevelGenerator.generate(build, 2, s, false, 1, options)
		var rng := Seeds.rng(Seeds.derive(data.level_seed, Tuning.SEED_LABEL_DIRECTOR))
		var design := DirectorRules.roster(2, stratum, false, [], rng)
		var native := DirectorRules.native_for(stratum, [], rng)
		var sub := DirectorRules.substitute_unbuilt_native(design, native)
		var ids: Array[StringName] = []
		for id: StringName in sub[&"roster"]:
			if DirectorRules.spawnable(id):
				ids.append(id)
		var pose := _spawn_pose(data)
		var cells := DirectorSpawn.pick_cells(data, ids, sub[&"native"], pose[0], pose[1], pose[2], half, rng)
		var hunter := false
		var static_ok := false
		for i in ids.size():
			if cells[i] == LevelData.NO_CELL:
				continue
			hunter = hunter or DirectorRules.is_hunter(ids[i])
			static_ok = static_ok or ids[i] == &"static"
		assert_true(hunter, "seed %d (%s): a hunter spawns (%s)" % [s, stratum, ids])
		assert_true(static_ok, "seed %d (%s): a Static spawns" % [s, stratum])


## M1.13 ruling: with no fair cell left, Static takes the farthest legal cell (≥ 20 m and out
## of view when one exists), else the farthest cell; it always spawns.
func test_static_always_spawns_at_the_farthest_legal_cell() -> void:
	var data := LevelGenerator.generate(&"halls", 1, 11)
	var g := data.grid
	var pose := _spawn_pose(data)
	var half := DirectorSpawn.half_fov_h(FOV, ASPECT)
	var walk := g.distance_field(data.spawn_cell)
	var none: Array[Vector2i] = []
	var c := DirectorSpawn.farthest_cell(g, none, pose[0], pose[1], pose[2], half, walk)
	assert_ne(c, LevelData.NO_CELL)
	assert_true(DirectorSpawn.spawn_ok(g, c, pose[0], pose[1], pose[2], half, walk), "a fair cell when one exists")
	var best := -1
	for i in g.cell_count():
		var o := g.cell_at(i)
		if DirectorSpawn.spawn_ok(g, o, pose[0], pose[1], pose[2], half, walk):
			best = maxi(best, walk[g.idx(o)])
	assert_eq(walk[g.idx(c)], best, "the farthest walking among the legal cells")
	# Every legal cell used: still a cell (the farthest of the rest), never NO_CELL.
	var used: Array[Vector2i] = []
	for i in g.cell_count():
		var o := g.cell_at(i)
		if DirectorSpawn.spawn_ok(g, o, pose[0], pose[1], pose[2], half, walk):
			used.append(o)
	var last := DirectorSpawn.farthest_cell(g, used, pose[0], pose[1], pose[2], half, walk)
	assert_ne(last, LevelData.NO_CELL, "Static always spawns")
	assert_false(used.has(last))
	# Through pick_cells: a roster of more Statics than fair cells still places every one.
	var tiny := LevelGrid.new(Vector2i(4, 1))
	for x in 4:
		tiny.set_kind(Vector2i(x, 0), LevelGrid.FLOOR)
	for x in 3:
		tiny.set_wall(Vector2i(x, 0), LevelGrid.E, LevelGrid.NONE)
	tiny.finalize_walls()
	var td := LevelData.new()
	td.grid = tiny
	td.spawn_cell = Vector2i(0, 0)
	var roster: Array[StringName] = [&"static", &"still"]
	var p0 := tiny.world_of(Vector2i(0, 0))
	var picked := DirectorSpawn.pick_cells(td, roster, &"still", p0, p0 + Vector3.UP * 1.6, Vector3.FORWARD, half, make_rng(1))
	assert_eq(picked[0], Vector2i(3, 0), "no fair cell on an 8 m strip: Static at the farthest cell")
	assert_eq(picked[1], LevelData.NO_CELL, "a hunter is never forced (the rule is Static's)")


## M1.13 ruling (05 §10): on the first Descent the first Static spawns between the breaker
## and the exit, within 6 m of that stretch of the critical path, still at a fair cell.
func test_first_descent_static_between_breaker_and_exit() -> void:
	var half := DirectorSpawn.half_fov_h(FOV, ASPECT)
	var placed := 0
	var levels := 0
	var fair_levels := 0
	for s in range(1, 13):
		var data := LevelGenerator.generate(&"halls", 1, s, true)
		var band := DirectorSpawn.breaker_exit_band(data)
		if data.breaker_cell == LevelData.NO_CELL:
			continue
		levels += 1
		assert_false(band.is_empty(), "seed %d: a band between the breaker and the exit" % s)
		var g := data.grid
		var bi := roundi(DirectorSpawn.path_fraction(data.critical_path, data.breaker_cell) * (data.critical_path.size() - 1))
		var before: Array[Vector2i] = data.critical_path.slice(0, maxi(bi - 3, 0))
		for c: Vector2i in band:
			assert_false(g.has_flag(c, LevelGrid.F_EXIT_ROOM) or g.has_flag(c, LevelGrid.F_SPAWN_ROOM), "no room cell in the band")
		for c: Vector2i in before:
			if g.has_flag(c, LevelGrid.F_SPAWN_ROOM):
				continue
			var near_after := false
			for i in range(bi, data.critical_path.size()):
				if not g.has_flag(data.critical_path[i], LevelGrid.F_EXIT_ROOM):
					near_after = near_after or Vector2(data.critical_path[i] - c).length() * Tuning.GRID_CELL_SIZE <= Tuning.DIRECTOR_FD_STATIC_PATH_BAND
			assert_eq(band.has(c), near_after, "seed %d: path cell %s before the breaker is in the band only near the stretch" % [s, c])
		var pose := _spawn_pose(data)
		var roster: Array[StringName] = [&"static"]
		var c := DirectorSpawn.pick_cells(data, roster, &"", pose[0], pose[1], pose[2], half, make_rng(s), band)[0]
		assert_ne(c, LevelData.NO_CELL, "seed %d: Static spawns" % s)
		var walk := g.distance_field(data.spawn_cell)
		var spawn_room := DirectorSpawn._spawn_room_cells(data)
		var fair_in_band := false
		for b: Vector2i in band:
			fair_in_band = fair_in_band or (DirectorSpawn.spawn_ok(g, b, pose[0], pose[1], pose[2], half, walk)
				and not DirectorSpawn._near_any(b, spawn_room, Tuning.STATIC_SPAWN_MIN_FROM_SPAWN_ROOM))
		if not fair_in_band:
			print("  # seed %d: no fair cell between the breaker and the exit" % s)
			continue
		fair_levels += 1
		if band.has(c):
			placed += 1
			assert_true(DirectorSpawn.spawn_ok(g, c, pose[0], pose[1], pose[2], half, walk), "seed %d: still a fair cell" % s)
	assert_gt(levels, 8, "first-Descent levels have a breaker")
	assert_gt(fair_levels, levels - 3, "most first-Descent levels have a fair cell there")
	assert_eq(placed, fair_levels, "the first Static sits between the breaker and the exit whenever a fair cell is there (%d of %d)" % [placed, fair_levels])
