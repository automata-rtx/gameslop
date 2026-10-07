extends TestCase
## SightOps: grid line of sight across open edges only.


func _corridor() -> LevelGrid:
	# A 5 x 3 grid: an open corridor along z = 1, walled from rows 0 and 2 (all walkable).
	var g := LevelGrid.new(Vector2i(5, 3))
	for z in 3:
		for x in 5:
			g.set_kind(Vector2i(x, z), LevelGrid.FLOOR)
	for x in 4:
		for z in 3:
			g.set_wall(Vector2i(x, z), LevelGrid.E, LevelGrid.NONE)
	for x in 5:
		g.set_wall(Vector2i(x, 0), LevelGrid.S, LevelGrid.WALL)
		g.set_wall(Vector2i(x, 1), LevelGrid.S, LevelGrid.WALL)
	return g


func test_open_corridor_is_clear() -> void:
	var g := _corridor()
	assert_true(SightOps.clear(g, g.world_of(Vector2i(0, 1)), g.world_of(Vector2i(4, 1))))


func test_wall_blocks() -> void:
	var g := _corridor()
	assert_false(SightOps.clear(g, g.world_of(Vector2i(0, 1)), g.world_of(Vector2i(0, 0))))
	assert_false(SightOps.clear(g, g.world_of(Vector2i(0, 1)), g.world_of(Vector2i(3, 2))))


func test_opening_lets_sight_through() -> void:
	var g := _corridor()
	g.set_wall(Vector2i(2, 1), LevelGrid.S, LevelGrid.NONE)
	assert_true(SightOps.clear(g, g.world_of(Vector2i(2, 1)), g.world_of(Vector2i(2, 2))))
	g.set_wall(Vector2i(2, 1), LevelGrid.S, LevelGrid.DOOR)
	assert_true(SightOps.clear(g, g.world_of(Vector2i(2, 1)), g.world_of(Vector2i(2, 2))), "doors do not block grid sight")


func test_from_inside_void_is_not_clear() -> void:
	var g := _corridor()
	g.set_kind(Vector2i(0, 0), LevelGrid.VOID)
	assert_false(SightOps.clear(g, g.world_of(Vector2i(0, 0)), g.world_of(Vector2i(4, 1))))
