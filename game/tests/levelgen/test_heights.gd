extends TestCase
## M2.1 grid heights (07 §2): per-cell floors, RAMP runs, ledges a walker cannot step, DEEP
## water (built, not walkable), Garage pillars (void with no walls), and grid sight across
## them.


func _flat(n: int) -> LevelGrid:
	var g := LevelGrid.new(Vector2i(n, 1))
	for x in n:
		g.set_kind(Vector2i(x, 0), LevelGrid.FLOOR)
	for x in n - 1:
		g.set_wall(Vector2i(x, 0), LevelGrid.E, LevelGrid.NONE)
	return g


func test_ramp_floor_is_continuous() -> void:
	var g := _flat(7)
	var run: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)]
	for x in range(5, 7):
		g.set_floor_y(Vector2i(x, 0), 3.2)
	GridHeights.set_ramp(g, run, LevelGrid.E, 0.0, 3.2)
	GridHeights.refresh_ledges(g)
	assert_eq(g.ramp_dir_of(Vector2i(2, 0)), LevelGrid.E)
	assert_eq(g.kind(Vector2i(1, 0)), LevelGrid.RAMP)
	# Neighbouring edges meet: the floor at each shared edge is the same from both sides.
	for x in range(0, 6):
		var a := g.edge_floor_y(Vector2i(x, 0), LevelGrid.E)
		var b := g.edge_floor_y(Vector2i(x + 1, 0), LevelGrid.W)
		assert_approx(a, b, 0.05, "edge %d" % x)
	assert_approx(g.edge_floor_y(Vector2i(1, 0), LevelGrid.W), 0.0, 0.05)
	assert_approx(g.edge_floor_y(Vector2i(4, 0), LevelGrid.E), 3.2, 0.05)
	# Walkable end to end: no ledge on the ramp.
	assert_eq(g.distance_field(Vector2i(0, 0))[g.idx(Vector2i(6, 0))], 6)


func test_ledge_blocks_a_height_break() -> void:
	var g := _flat(3)
	g.set_floor_y(Vector2i(2, 0), -1.2)
	GridHeights.refresh_ledges(g)
	assert_true(g.can_step(Vector2i(0, 0), LevelGrid.E))
	assert_false(g.can_step(Vector2i(1, 0), LevelGrid.E), "a 1.2 m drop is a ledge")
	assert_false(g.can_step(Vector2i(2, 0), LevelGrid.W))
	assert_eq(g.distance_field(Vector2i(0, 0))[g.idx(Vector2i(2, 0))], -1)
	# A step within the climb is fine.
	g.set_floor_y(Vector2i(2, 0), -0.25)
	GridHeights.refresh_ledges(g)
	assert_true(g.can_step(Vector2i(1, 0), LevelGrid.E))


func test_deep_water_is_open_but_not_walkable() -> void:
	var g := _flat(3)
	g.set_kind(Vector2i(2, 0), LevelGrid.DEEP)
	g.finalize_walls()
	assert_false(g.is_walkable(Vector2i(2, 0)))
	assert_true(g.is_open(Vector2i(2, 0)))
	assert_eq(g.wall(Vector2i(1, 0), LevelGrid.E), LevelGrid.NONE, "no wall is built around a pool")
	assert_false(g.can_step(Vector2i(1, 0), LevelGrid.E))
	assert_false(g.floor_drop_valid(Vector2i(2, 0)), "07 §7: no floor drop from deep water")
	assert_true(SightOps.clear(g, g.world_of(Vector2i(0, 0)), g.world_of(Vector2i(2, 0))), "sight crosses a pool")


func test_pillar_is_void_without_walls() -> void:
	var g := LevelGrid.new(Vector2i(3, 3))
	for c in RoomData.new(Rect2i(0, 0, 3, 3)).cells():
		g.set_kind(c, LevelGrid.FLOOR)
		for d in 4:
			if g.in_bounds(c + LevelGrid.DIRS[d]):
				g.set_wall(c, d, LevelGrid.NONE)
	var mid := Vector2i(1, 1)
	g.set_kind(mid, LevelGrid.VOID)
	assert_true(g.is_pillar(mid))
	assert_false(g.is_walkable(mid))
	assert_true(g.is_sight_open(mid))
	assert_false(g.can_step(Vector2i(0, 1), LevelGrid.E), "nobody walks into the pillar")
	assert_true(SightOps.clear(g, g.world_of(Vector2i(0, 1)), g.world_of(Vector2i(2, 1))), "sight runs past a pillar")
	# A void block (walls on its edges) is not a pillar.
	g.set_wall(mid, LevelGrid.N, LevelGrid.WALL)
	assert_false(g.is_pillar(mid))


func test_ramp_cells_are_hashed() -> void:
	var a := _flat(4)
	var b := _flat(4)
	GridHeights.set_ramp(b, [Vector2i(1, 0), Vector2i(2, 0)] as Array[Vector2i], LevelGrid.E, 0.0, 1.0)
	assert_ne(a.to_bytes(), b.to_bytes())


## 07 §7 floor drops: valid on FLOOR, ROOM and BASIN cells, not on ramps or steps.
func test_floor_drop_cells() -> void:
	var g := _flat(4)
	g.set_kind(Vector2i(1, 0), LevelGrid.BASIN)
	GridHeights.set_ramp(g, [Vector2i(2, 0)] as Array[Vector2i], LevelGrid.E, -0.6, 0.0)
	assert_true(g.floor_drop_valid(Vector2i(0, 0)))
	assert_true(g.floor_drop_valid(Vector2i(1, 0)))
	assert_false(g.floor_drop_valid(Vector2i(2, 0)))
