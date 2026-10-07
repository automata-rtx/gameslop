extends TestCase
## LevelGrid (07 §2): edge storage and its symmetry invariant, queries, world mapping.


func test_new_grid_has_solid_border_and_closed_interior() -> void:
	var g := LevelGrid.new(Vector2i(5, 4))
	for x in 5:
		assert_eq(g.wall(Vector2i(x, 0), LevelGrid.N), LevelGrid.SOLID)
		assert_eq(g.wall(Vector2i(x, 3), LevelGrid.S), LevelGrid.SOLID)
	for z in 4:
		assert_eq(g.wall(Vector2i(0, z), LevelGrid.W), LevelGrid.SOLID)
		assert_eq(g.wall(Vector2i(4, z), LevelGrid.E), LevelGrid.SOLID)
	assert_eq(g.wall(Vector2i(2, 2), LevelGrid.E), LevelGrid.WALL)
	assert_eq(g.walkable_count(), 0)


func test_set_wall_writes_both_sides() -> void:
	var g := LevelGrid.new(Vector2i(4, 4))
	for type in [LevelGrid.NONE, LevelGrid.SOFT, LevelGrid.DOOR, LevelGrid.GLASS, LevelGrid.PARTITION]:
		g.set_wall(Vector2i(1, 1), LevelGrid.E, type)
		assert_eq(g.wall(Vector2i(2, 1), LevelGrid.W), type)
		g.set_wall(Vector2i(1, 2), LevelGrid.N, type)
		assert_eq(g.wall(Vector2i(1, 1), LevelGrid.S), type)
	# The border never opens.
	g.set_wall(Vector2i(0, 0), LevelGrid.W, LevelGrid.NONE)
	assert_eq(g.wall(Vector2i(0, 0), LevelGrid.W), LevelGrid.SOLID)


func test_generated_levels_keep_edge_symmetry() -> void:
	for s in range(1, 31):
		var g := LevelGenerator.generate(&"halls", 1, s).grid
		var broken := 0
		for z in g.size.y:
			for x in g.size.x:
				var c := Vector2i(x, z)
				for d in 4:
					var o := c + LevelGrid.DIRS[d]
					if g.in_bounds(o):
						if g.wall(c, d) != g.wall(o, LevelGrid.opposite(d)):
							broken += 1
					elif g.wall(c, d) != LevelGrid.SOLID:
						broken += 1
		assert_eq(broken, 0, "seed %d" % s)


func test_walls_between_walkable_and_void_are_walls() -> void:
	# 07 §2, §8 rule 5: a walkable cell is never open onto a void cell, and void cells
	# carry no walls between themselves.
	for s in range(1, 21):
		var g := LevelGenerator.generate(&"halls", 1, s).grid
		for z in g.size.y:
			for x in g.size.x:
				var c := Vector2i(x, z)
				for d: int in [LevelGrid.E, LevelGrid.S]:
					var o := c + LevelGrid.DIRS[d]
					if not g.in_bounds(o):
						continue
					if g.is_walkable(c) != g.is_walkable(o):
						assert_eq(g.wall(c, d), LevelGrid.WALL, "seed %d %s" % [s, c])
					elif not g.is_walkable(c):
						assert_eq(g.wall(c, d), LevelGrid.NONE, "seed %d %s" % [s, c])


func test_noclip_classification_matches_07_s7() -> void:
	assert_false(LevelGrid.wall_noclip_candidate(LevelGrid.SOLID))
	assert_false(LevelGrid.wall_noclip_candidate(LevelGrid.GLASS))
	assert_false(LevelGrid.wall_noclip_candidate(LevelGrid.NONE))
	for t in [LevelGrid.WALL, LevelGrid.PARTITION, LevelGrid.DOOR, LevelGrid.SOFT]:
		assert_true(LevelGrid.wall_noclip_candidate(t))
	var g := LevelGrid.new(Vector2i(3, 3))
	g.set_kind(Vector2i(1, 1), LevelGrid.FLOOR)
	g.set_kind(Vector2i(2, 1), LevelGrid.RACK)
	assert_true(g.floor_drop_valid(Vector2i(1, 1)))
	assert_false(g.floor_drop_valid(Vector2i(2, 1)))
	assert_false(g.floor_drop_valid(Vector2i(0, 0)))


func test_wall_types_follow_tuning_order() -> void:
	var names := Tuning.GRID_WALL_TYPES
	assert_eq(names[LevelGrid.NONE], &"NONE")
	assert_eq(names[LevelGrid.WALL], &"WALL")
	assert_eq(names[LevelGrid.SOLID], &"SOLID")
	assert_eq(names[LevelGrid.SOFT], &"SOFT")
	assert_eq(names[LevelGrid.PARTITION], &"PARTITION")
	assert_eq(names[LevelGrid.DOOR], &"DOOR")
	assert_eq(names[LevelGrid.GLASS], &"GLASS")


func test_world_mapping_round_trips() -> void:
	var g := LevelGrid.new(Vector2i(10, 10))
	for c in [Vector2i(0, 0), Vector2i(3, 7), Vector2i(9, 9)]:
		var p := g.world_of(c)
		assert_eq(p, Vector3(c.x * 2.0, 0.0, c.y * 2.0))
		assert_eq(g.cell_of(p), c)
		assert_eq(g.cell_of(p + Vector3(0.9, 1.5, -0.9)), c)


func test_distance_field_respects_walls_and_doors() -> void:
	var g := LevelGrid.new(Vector2i(3, 1))
	for x in 3:
		g.set_kind(Vector2i(x, 0), LevelGrid.FLOOR)
	g.set_wall(Vector2i(0, 0), LevelGrid.E, LevelGrid.DOOR)
	var d := g.distance_field(Vector2i(0, 0))
	assert_eq(d[1], 1, "a door is walkable")
	assert_eq(d[2], -1, "a wall is not")
	g.set_wall(Vector2i(1, 0), LevelGrid.E, LevelGrid.SOFT)
	assert_eq(g.distance_field(Vector2i(0, 0))[2], -1, "a soft wall is not walkable")
	g.set_wall(Vector2i(1, 0), LevelGrid.E, LevelGrid.NONE)
	assert_eq(g.distance_field(Vector2i(0, 0))[2], 2)
	assert_eq(g.openings(Vector2i(1, 0)), 2)


func test_random_walkable_cell_is_seeded_and_filtered() -> void:
	var g := LevelGenerator.generate(&"halls", 1, 4).grid
	var a := g.random_walkable_cell(make_rng(5), func(c: Vector2i) -> bool: return g.kind(c) == LevelGrid.ROOM)
	var b := g.random_walkable_cell(make_rng(5), func(c: Vector2i) -> bool: return g.kind(c) == LevelGrid.ROOM)
	assert_eq(a, b)
	assert_eq(g.kind(a), LevelGrid.ROOM)


func test_ascii_dump_shape() -> void:
	var level := LevelGenerator.generate(&"halls", 1, 1)
	var lines := level.to_ascii().split("\n")
	assert_eq(lines.size(), level.grid.size.y * 2 + 1)
	assert_eq(lines[0].length(), level.grid.size.x * 2 + 1)
	assert_contains(level.to_ascii(), "S")
	assert_contains(level.to_ascii(), "X")
