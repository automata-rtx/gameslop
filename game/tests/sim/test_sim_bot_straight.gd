extends TestCase
## M3.4 sim-bot fix (test code): in the Pursuit the bot walks straight across open floor
## (`SimBotNull.walk_clear`) instead of a room's cells in an L or a staircase. A 6 x 6 room
## of open floor with one interior wall stub, and a 1-cell corridor bend.

func _room() -> LevelGrid:
	var g := LevelGrid.new(Vector2i(8, 8))
	for z in range(1, 7):
		for x in range(1, 7):
			g.set_kind(Vector2i(x, z), LevelGrid.ROOM)
	for z in range(1, 7):
		for x in range(1, 7):
			var c := Vector2i(x, z)
			if x < 6:
				g.set_wall(c, LevelGrid.E, LevelGrid.NONE)
			if z < 6:
				g.set_wall(c, LevelGrid.S, LevelGrid.NONE)
	# A wall stub: the east edges of (3,4) and (3,5).
	g.set_wall(Vector2i(3, 4), LevelGrid.E, LevelGrid.WALL)
	g.set_wall(Vector2i(3, 5), LevelGrid.E, LevelGrid.WALL)
	g.finalize_walls()
	return g


func test_diagonal_across_open_floor_is_clear() -> void:
	var g := _room()
	assert_true(SimBotNull.walk_clear(g, g.world_of(Vector2i(1, 1)), g.world_of(Vector2i(6, 3))))
	assert_true(SimBotNull.walk_clear(g, g.world_of(Vector2i(1, 1)), g.world_of(Vector2i(6, 1))), "along a row")


func test_wall_stub_blocks_the_line() -> void:
	var g := _room()
	assert_false(SimBotNull.walk_clear(g, g.world_of(Vector2i(2, 5)), g.world_of(Vector2i(5, 5))), "through the stub")
	assert_false(SimBotNull.walk_clear(g, g.world_of(Vector2i(2, 4)), g.world_of(Vector2i(5, 6))), "a parallel grazes it")


func test_line_off_the_floor_is_not_clear() -> void:
	var g := _room()
	assert_false(SimBotNull.walk_clear(g, g.world_of(Vector2i(1, 1)), g.world_of(Vector2i(7, 7))), "into VOID")


func test_avoid_cells_block() -> void:
	var g := _room()
	var a := g.world_of(Vector2i(1, 2))
	var b := g.world_of(Vector2i(6, 2))
	assert_true(SimBotNull.walk_clear(g, a, b))
	assert_false(SimBotNull.walk_clear(g, a, b, {Vector2i(4, 2): true}), "Null's ring")


func test_corridor_bend_is_not_cut() -> void:
	var g := LevelGrid.new(Vector2i(4, 4))
	for c: Vector2i in [Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 2)]:
		g.set_kind(c, LevelGrid.FLOOR)
	g.set_wall(Vector2i(1, 1), LevelGrid.E, LevelGrid.NONE)
	g.set_wall(Vector2i(2, 1), LevelGrid.S, LevelGrid.NONE)
	g.finalize_walls()
	assert_false(SimBotNull.walk_clear(g, g.world_of(Vector2i(1, 1)), g.world_of(Vector2i(2, 2))), "a bend is walked, not cut")
	assert_true(SimBotNull.walk_clear(g, g.world_of(Vector2i(1, 1)), g.world_of(Vector2i(2, 1))))
