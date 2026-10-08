extends TestCase
## R13: cells a prop fills (LevelGrid.F_BLOCKED). The grid treats them as not walkable
## everywhere a walker, a spawn, a landing or a path asks (07 §2 additions), while the
## builder still lays their floor; grammars block only where the level stays whole; Garage
## cars and barriers, and Pools lifeguard chairs, are blocked; no car parks at a ramp head.

const SEEDS := 40


## A 5x5 open floor (all inner edges open).
func _open_grid() -> LevelGrid:
	var g := LevelGrid.new(Vector2i(5, 5))
	for i in g.cell_count():
		g.cells[i] = LevelGrid.FLOOR
	for i in g.cell_count():
		var c := g.cell_at(i)
		for d: int in [LevelGrid.E, LevelGrid.S]:
			if g.in_bounds(c + LevelGrid.DIRS[d]):
				g.set_wall(c, d, LevelGrid.NONE)
	return g


func test_blocked_cell_is_not_walkable_but_keeps_its_kind() -> void:
	var g := _open_grid()
	var c := Vector2i(2, 2)
	g.block(c)
	assert_true(g.is_blocked(c))
	assert_false(g.is_walkable(c))
	assert_false(g.is_walkable_i(g.idx(c)))
	assert_eq(g.kind(c), LevelGrid.FLOOR, "the floor is still built")
	assert_true(g.is_open(c), "sight and the builder see open floor")
	assert_true(g.has_flag(c, LevelGrid.F_NO_SPAWN))
	assert_false(g.floor_drop_valid(c))
	assert_eq(g.walkable_count(), 24)
	assert_eq(g.openings(c), 0)
	for d in 4:
		assert_false(g.can_step(c + LevelGrid.DIRS[d], LevelGrid.opposite(d)), "no step into it from %d" % d)


func test_distance_field_routes_round_a_blocked_cell() -> void:
	var g := _open_grid()
	g.block(Vector2i(2, 1))
	g.block(Vector2i(2, 2))
	g.block(Vector2i(2, 3))
	var dist := g.distance_field(Vector2i(1, 2))
	assert_eq(dist[g.idx(Vector2i(2, 2))], -1, "never entered")
	# Round the wall of three: up to row 0 or down to row 4, across, and back.
	assert_eq(dist[g.idx(Vector2i(3, 2))], 6)
	var cells := 0
	for i in g.cell_count():
		if g.is_walkable_i(i):
			cells += 1
			assert_gt(dist[i], -1, "reachable %s" % g.cell_at(i))
	assert_eq(cells, 22)


## Someone at the edge of a blocked cell (cell_of rounds into it) still measures outwards.
func test_distance_field_from_a_blocked_cell_measures_outwards() -> void:
	var g := _open_grid()
	g.block(Vector2i(2, 2))
	var dist := g.distance_field(Vector2i(2, 2))
	assert_eq(dist[g.idx(Vector2i(2, 2))], 0)
	assert_eq(dist[g.idx(Vector2i(3, 2))], 1)
	assert_eq(dist[g.idx(Vector2i(4, 4))], 4)


func test_a_pillar_stays_a_pillar_beside_a_blocked_cell() -> void:
	var g := _open_grid()
	var p := Vector2i(2, 2)
	g.set_kind(p, LevelGrid.VOID)
	assert_true(g.is_pillar(p))
	g.block(Vector2i(3, 2))
	assert_true(g.is_pillar(p), "the car beside it does not take the pillar's floor away")


func test_block_ops_keep_the_level_whole() -> void:
	var g := _open_grid()
	var from := Vector2i(0, 0)
	# A full column would cut the floor in two.
	var column: Array[Vector2i] = [Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4)]
	assert_false(BlockOps.can_block(g, column, from))
	assert_false(BlockOps.can_block(g, [from] as Array[Vector2i], from), "never the start")
	g.add_flag(Vector2i(4, 4), LevelGrid.F_CRITICAL_PATH)
	assert_false(BlockOps.can_block(g, [Vector2i(4, 4)] as Array[Vector2i], from), "never on the critical path")
	assert_true(BlockOps.try_block(g, [Vector2i(2, 2), Vector2i(2, 3)] as Array[Vector2i], from))
	assert_true(g.is_blocked(Vector2i(2, 3)))
	assert_false(BlockOps.can_block(g, [Vector2i(2, 2)] as Array[Vector2i], from), "already blocked")


## Every car and barrier stands on blocked cells, off the critical path, clear of the ramp
## heads; every blocked cell holds one; the validator passes with them counted.
func test_garage_cars_and_barriers_block_their_cells() -> void:
	var cars := 0
	for s in range(1, SEEDS + 1):
		var level := LevelGenerator.generate(&"garage", 3, s)
		var g := level.grid
		var heads := _ramp_heads(g)
		var held: Dictionary = {}
		for p in level.placements_of(LevelData.P_PROP):
			var prop: StringName = p[&"params"].get(&"prop", &"")
			if prop != &"car" and prop != &"barrier":
				continue
			var c: Vector2i = p[&"cell"]
			var cells: Array[Vector2i] = [c]
			if prop == &"car":
				cars += 1
				# The car's centre sits on the edge to its second cell (yaw: along the wall).
				var off: Vector3 = p[&"offset"]
				var dir := int(p[&"params"][&"dir"])
				var along := Vector3(off.x, 0.0, off.z) - StratumGenerator.wall_offset(dir, GarageParking.CAR_INSET)
				cells.append(c + Vector2i(roundi(along.x), roundi(along.z)))
			for x in cells:
				held[x] = true
				assert_true(g.is_blocked(x), "seed %d %s at %s blocked" % [s, prop, x])
				assert_false(g.has_flag(x, LevelGrid.F_CRITICAL_PATH), "seed %d %s off the path" % [s, prop])
				assert_false(heads.has(x), "seed %d %s at %s clear of the ramp heads" % [s, prop, x])
		for i in g.cell_count():
			if g.is_blocked(g.cell_at(i)):
				assert_true(held.has(g.cell_at(i)), "seed %d blocked cell %s holds a car or barrier" % [s, g.cell_at(i)])
		assert_eq(level.failures.size(), 0, "seed %d valid: %s" % [s, level.failures])
	assert_gt(cars, SEEDS * 4, "cars still park")


## Cells within GARAGE_RAMP_HEAD_CLEAR_CELLS beyond either end of a ramp run, in its column
## and the two beside it.
func _ramp_heads(g: LevelGrid) -> Dictionary:
	var out: Dictionary = {}
	for i in g.cell_count():
		var c := g.cell_at(i)
		var up := g.ramp_dir_of(c)
		if up < 0:
			continue
		var side := LevelGrid.DIRS[(up + 1) % 4]
		for d: int in [up, LevelGrid.opposite(up)]:
			if g.ramp_dir_of(c + LevelGrid.DIRS[d]) >= 0:
				continue  # not this run's end
			for k in range(1, Tuning.GARAGE_RAMP_HEAD_CLEAR_CELLS + 1):
				for sd in range(-1, 2):
					out[c + LevelGrid.DIRS[d] * k + side * sd] = true
	return out


func test_pools_lifeguard_chairs_block_their_cells() -> void:
	var chairs := 0
	for s in range(1, SEEDS + 1):
		var level := LevelGenerator.generate(&"pools", 2, s)
		for p in level.placements_of(LevelData.P_PROP):
			if p[&"params"].get(&"prop", &"") != &"lifeguard_chair":
				continue
			chairs += 1
			var c: Vector2i = p[&"cell"]
			assert_true(level.grid.is_blocked(c), "seed %d chair at %s blocked" % [s, c])
			assert_false(level.grid.has_flag(c, LevelGrid.F_CRITICAL_PATH))
	assert_gt(chairs, SEEDS / 2, "chairs still stand")


## Nothing else is ever placed on a blocked cell: no item, note, keycard, fuse, breaker, error
## spawn, spawn or exit.
func test_nothing_is_placed_on_a_blocked_cell() -> void:
	var kinds: Array[StringName] = [LevelData.P_ITEM, LevelData.P_NOTE, LevelData.P_KEYCARD, LevelData.P_BREAKER,
		LevelData.P_ERROR_SPAWN, LevelData.P_SPAWN, LevelData.P_EXIT]
	for stratum: StringName in [&"garage", &"pools"]:
		for s in range(1, SEEDS + 1):
			var level := LevelGenerator.generate(stratum, 3, s)
			for p in level.placements:
				if kinds.has(p[&"kind"]):
					assert_false(level.grid.is_blocked(p[&"cell"]), "%s seed %d %s on a blocked cell" % [stratum, s, p[&"kind"]])
