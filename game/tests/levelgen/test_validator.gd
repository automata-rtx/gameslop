extends TestCase
## LevelValidator (07 §8): the lock rules checked independently of the validator, and the
## validator catching broken levels.


func _reach(g: LevelGrid, from: Vector2i, to: Vector2i) -> bool:
	return g.distance_field(from)[g.idx(to)] >= 0


func test_powered_lock_always_has_a_reachable_breaker() -> void:
	var powered := 0
	for s in range(1, 121):
		# First Descent levels are always Powered; the rest are Powered 60% of the time.
		var level := LevelGenerator.generate(&"halls", 1, s, s % 2 == 0)
		if level.exit_lock != Tuning.LOCK_POWERED:
			continue
		powered += 1
		var g := level.grid
		var breakers := level.placements_of(LevelData.P_BREAKER)
		assert_eq(breakers.size(), 1, "seed %d" % s)
		var cell: Vector2i = breakers[0][&"cell"]
		assert_eq(cell, level.breaker_cell)
		var room := g.room_of(cell)
		assert_true(room != null and room.kind == RoomData.BREAKER, "seed %d: breaker in its room" % s)
		assert_true(_reach(g, level.spawn_cell, cell), "seed %d: breaker reachable from spawn" % s)
		assert_true(_reach(g, cell, level.exit_cell), "seed %d: exit reachable from breaker" % s)
		# The box hangs on a closed edge.
		assert_false(LevelGrid.wall_walkable(g.wall(cell, breakers[0][&"params"][&"dir"])))
	assert_gt(powered, 70)


func test_variant_b_places_exactly_one_reachable_fuse() -> void:
	var found := 0
	for s in range(1, 61):
		var level := LevelGenerator.generate(&"halls", 1, s, false, 1, {&"fuse_unlocked": true})
		if level.lock_variant != &"b":
			continue
		found += 1
		var fuses := 0
		for p in level.placements_of(LevelData.P_ITEM):
			if p[&"params"][&"item"] == &"fuse":
				fuses += 1
				assert_eq(p[&"cell"], level.fuse_cell)
		assert_eq(fuses, 1, "seed %d" % s)
		assert_true(_reach(level.grid, level.spawn_cell, level.fuse_cell))
		var length := level.critical_path.size() - 1
		var d := level.grid.distance_field(level.spawn_cell)[level.grid.idx(level.fuse_cell)]
		assert_true(d >= ceili(length * 0.35) and d <= floori(length * 0.70), "seed %d: fuse at 35-70%% (%d of %d)" % [s, d, length])
	assert_gt(found, 5)


func test_without_unlock_there_is_no_variant_b() -> void:
	for s in range(1, 31):
		assert_ne(LevelGenerator.generate(&"halls", 1, s).lock_variant, &"b")


func test_keyed_places_a_reachable_keycard() -> void:
	var found := 0
	for s in range(1, 41):
		var level := LevelGenerator.generate(&"halls", 2, s)
		if level.exit_lock != Tuning.LOCK_KEYED:
			continue
		found += 1
		assert_eq(level.placements_of(LevelData.P_KEYCARD).size(), 1)
		assert_true(_reach(level.grid, level.spawn_cell, level.keycard_cell))
		assert_true(_reach(level.grid, level.keycard_cell, level.exit_cell))
	assert_gt(found, 5)


func test_soft_walls_save_twenty_metres() -> void:
	for s in range(1, 21):
		var level := LevelGenerator.generate(&"halls", 1, s)
		for e in level.soft_walls:
			var a := Vector2i(e.x, e.y)
			var b := a + LevelGrid.DIRS[e.z]
			assert_eq(level.grid.wall(a, e.z), LevelGrid.SOFT)
			var walk := level.grid.distance_field(a)[level.grid.idx(b)]
			assert_true((walk - 1) * Tuning.GRID_CELL_SIZE >= Tuning.SOFT_WALL_MIN_SAVING, "seed %d %s walk %d" % [s, e, walk])


func test_validator_catches_a_missing_breaker() -> void:
	var level := LevelGenerator.generate(&"halls", 1, 2, true)
	assert_true(level.failures.is_empty())
	for p in level.placements_of(LevelData.P_BREAKER):
		level.placements.erase(p)
	level.breaker_cell = LevelData.NO_CELL
	assert_true(_any_starts(LevelValidator.validate(level), "r3"))


func test_validator_catches_asymmetric_and_open_border() -> void:
	var level := LevelGenerator.generate(&"halls", 1, 3)
	var g := level.grid
	g.walls[g.idx(Vector2i(5, 5)) * 4 + LevelGrid.E] = LevelGrid.SOFT
	g.walls[g.idx(Vector2i(0, 4)) * 4 + LevelGrid.W] = LevelGrid.NONE
	var f := LevelValidator.validate(level)
	assert_true(_any_contains(f, "asymmetric"))
	assert_true(_any_contains(f, "border"))


func test_validator_catches_unreachable_exit() -> void:
	var level := LevelGenerator.generate(&"halls", 1, 4)
	var g := level.grid
	for e in g.room_of(level.exit_cell).perimeter_edges():
		g.set_wall(Vector2i(e.x, e.y), e.z, LevelGrid.WALL if g.in_bounds(Vector2i(e.x, e.y) + LevelGrid.DIRS[e.z]) else LevelGrid.SOLID)
	assert_true(_any_starts(LevelValidator.validate(level), "r1"))


func test_validator_catches_too_few_error_spawns() -> void:
	var level := LevelGenerator.generate(&"halls", 1, 5)
	var spawns := level.placements_of(LevelData.P_ERROR_SPAWN)
	for k in spawns.size() - 2:
		level.placements.erase(spawns[k])
	assert_true(_any_starts(LevelValidator.validate(level), "r7"))


func test_simplest_grammar_validates() -> void:
	for s in range(1, 21):
		var level := HallsGenerator.new().generate(&"halls", 1, s, false, 1, {}, Tuning.LEVELGEN_RETRIES, true)
		var f := LevelValidator.validate(level)
		# The fallback must be at least as robust: retries of it are allowed, but it must
		# succeed within its budget for every seed.
		if not f.is_empty():
			var ok := false
			for k in LevelGenerator.FALLBACK_TRIES:
				var again := HallsGenerator.new().generate(&"halls", 1, s, false, 1, {}, Tuning.LEVELGEN_RETRIES + k, true)
				if LevelValidator.validate(again).is_empty():
					ok = true
					break
			assert_true(ok, "seed %d: %s" % [s, f])


func _any_starts(lines: PackedStringArray, prefix: String) -> bool:
	for l in lines:
		if l.begins_with(prefix):
			return true
	return false


func _any_contains(lines: PackedStringArray, needle: String) -> bool:
	for l in lines:
		if l.contains(needle):
			return true
	return false
