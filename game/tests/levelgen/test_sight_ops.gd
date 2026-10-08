extends TestCase
## SightOps: grid line of sight with its own edge rule (R4 #11).


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
	assert_true(SightOps.clear(g, g.world_of(Vector2i(2, 1)), g.world_of(Vector2i(2, 2))), "an open door does not block grid sight")


func test_from_inside_void_is_not_clear() -> void:
	var g := _corridor()
	g.set_kind(Vector2i(0, 0), LevelGrid.VOID)
	assert_false(SightOps.clear(g, g.world_of(Vector2i(0, 0)), g.world_of(Vector2i(4, 1))))


## R4 #11: sight has its own edge rule. Partitions are seen over, glass through; a closed
## door blocks, an open one does not; soft and solid walls block like walls.
func test_own_edge_rule() -> void:
	var g := _corridor()
	var a := g.world_of(Vector2i(2, 1))
	var b := g.world_of(Vector2i(2, 2))
	g.set_wall(Vector2i(2, 1), LevelGrid.S, LevelGrid.PARTITION)
	assert_true(SightOps.clear(g, a, b), "partition: seen over")
	g.set_wall(Vector2i(2, 1), LevelGrid.S, LevelGrid.GLASS)
	assert_true(SightOps.clear(g, a, b), "glass: seen through")
	g.set_wall(Vector2i(2, 1), LevelGrid.S, LevelGrid.SOFT)
	assert_false(SightOps.clear(g, a, b), "soft wall blocks")
	g.set_wall(Vector2i(2, 1), LevelGrid.S, LevelGrid.SOLID)
	assert_false(SightOps.clear(g, a, b), "solid blocks")
	g.set_wall(Vector2i(2, 1), LevelGrid.S, LevelGrid.DOOR)
	var v := g.door_version
	g.set_door_closed(Vector2i(2, 2), LevelGrid.N, true)
	assert_gt(g.door_version, v, "door changes bump the version")
	assert_true(g.is_door_closed(Vector2i(2, 1), LevelGrid.S), "either side names the edge")
	assert_false(SightOps.clear(g, a, b), "closed door blocks")
	g.set_door_closed(Vector2i(2, 1), LevelGrid.S, false)
	assert_true(SightOps.clear(g, a, b), "open door lets sight through")


func test_clear_near_accepts_one_step_away() -> void:
	var g := _corridor()
	g.set_wall(Vector2i(3, 1), LevelGrid.S, LevelGrid.NONE)
	# From (2, 1), the cell (3, 2) is behind the wall; one step east it is in view.
	var eye := g.world_of(Vector2i(2, 1))
	var to := g.world_of(Vector2i(3, 2))
	assert_false(SightOps.clear(g, eye, to))
	assert_true(SightOps.clear_near(g, eye, to))


## R4 #6: a fixture lights a point only with a clear grid sight line from its light to it.
func test_light_pool_is_lit_needs_sight() -> void:
	var g := _corridor()
	var pool := LightPool.new()
	add_child(pool)
	pool.configure(load("res://data/strata/halls.tres") as StratumData)
	pool.grid = g
	var f := (load("res://scenes/props/halls/fixture_tube.tscn") as PackedScene).instantiate() as Fixture
	add_child(f)
	f.global_position = g.world_of(Vector2i(1, 1)) + Vector3(0, 3.0, 0)
	pool.register_fixture(f)
	assert_true(pool.is_lit(g.world_of(Vector2i(3, 1)) + Vector3(0, 1, 0)), "down the corridor")
	assert_false(pool.is_lit(g.world_of(Vector2i(1, 2)) + Vector3(0, 1, 0)), "2 m away behind the wall")
	pool.grid = null
	assert_true(pool.is_lit(g.world_of(Vector2i(1, 2)) + Vector3(0, 1, 0)), "no grid: range only")
	f.free()
	pool.free()
