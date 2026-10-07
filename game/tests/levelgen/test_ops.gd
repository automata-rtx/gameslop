extends TestCase
## The shared ops library (07 §4) on small grids.


func _open_edges(g: LevelGrid) -> int:
	var n := 0
	for i in g.cell_count():
		var c := g.cell_at(i)
		for d: int in [LevelGrid.E, LevelGrid.S]:
			if g.can_step(c, d):
				n += 1
	return n


func _reachable(g: LevelGrid, from: Vector2i) -> int:
	var n := 0
	for d in g.distance_field(from):
		if d >= 0:
			n += 1
	return n


func test_maze_fill_is_a_spanning_tree() -> void:
	for s in 10:
		var g := LevelGrid.new(Vector2i(12, 9))
		var carved := MazeOps.maze_fill(g, Rect2i(0, 0, 12, 9), make_rng(s))
		assert_eq(carved, 12 * 9)
		assert_eq(_reachable(g, Vector2i(0, 0)), 12 * 9, "connected")
		assert_eq(_open_edges(g), 12 * 9 - 1, "perfect maze: a tree")


func test_maze_fill_skips_blocked_and_rooms() -> void:
	var g := LevelGrid.new(Vector2i(10, 10))
	RoomOps.add_room(g, Rect2i(2, 2, 3, 3), RoomData.GENERIC)
	var blocked := {g.idx(Vector2i(8, 8)): true}
	MazeOps.maze_fill(g, Rect2i(0, 0, 10, 10), make_rng(3), blocked)
	assert_eq(g.kind(Vector2i(8, 8)), LevelGrid.VOID)
	assert_eq(g.kind(Vector2i(3, 3)), LevelGrid.ROOM)
	assert_eq(g.walkable_count(), 100 - 1)


func test_sparsify_hits_target_and_keeps_connectivity() -> void:
	var g := LevelGrid.new(Vector2i(16, 16))
	MazeOps.maze_fill(g, Rect2i(0, 0, 16, 16), make_rng(8))
	var keep := {g.idx(Vector2i(0, 0)): true, g.idx(Vector2i(15, 15)): true}
	MazeOps.sparsify(g, 120, make_rng(9), keep)
	assert_eq(g.walkable_count(), 120)
	assert_eq(_reachable(g, Vector2i(0, 0)), 120)
	assert_true(g.is_walkable(Vector2i(15, 15)), "protected cells stay")


func test_braid_opens_dead_ends_and_flags_the_rest() -> void:
	var g := LevelGrid.new(Vector2i(14, 14))
	MazeOps.maze_fill(g, Rect2i(0, 0, 14, 14), make_rng(1))
	var before := MazeOps.dead_ends(g).size()
	var opened := MazeOps.braid(g, 1.0, make_rng(2))
	assert_gt(opened, 0)
	assert_lt(MazeOps.dead_ends(g).size(), before)
	for c in MazeOps.dead_ends(g):
		assert_true(g.has_flag(c, LevelGrid.F_DEAD_END))
	var none := LevelGrid.new(Vector2i(14, 14))
	MazeOps.maze_fill(none, Rect2i(0, 0, 14, 14), make_rng(1))
	assert_eq(MazeOps.braid(none, 0.0, make_rng(2)), 0)


func test_limit_dead_ends_caps_chains() -> void:
	# A 1-wide snake: one long dead end.
	var g := LevelGrid.new(Vector2i(20, 3))
	for x in 20:
		g.set_kind(Vector2i(x, 1), LevelGrid.FLOOR)
		if x > 0:
			g.set_wall(Vector2i(x, 1), LevelGrid.W, LevelGrid.NONE)
	g.finalize_walls()
	MazeOps.limit_dead_ends(g, 12, {})
	for chain in MazeOps.dead_end_chains(g):
		assert_true(chain.size() <= 12, "chain %d" % chain.size())


func test_critical_path_is_shortest_and_marked() -> void:
	var g := LevelGrid.new(Vector2i(9, 9))
	MazeOps.maze_fill(g, Rect2i(0, 0, 9, 9), make_rng(4))
	var path := PathOps.critical_path(g, Vector2i(0, 0), Vector2i(8, 8))
	assert_eq(path[0], Vector2i(0, 0))
	assert_eq(path[path.size() - 1], Vector2i(8, 8))
	assert_eq(path.size() - 1, g.distance_field(Vector2i(0, 0))[g.idx(Vector2i(8, 8))])
	for c in path:
		assert_true(g.has_flag(c, LevelGrid.F_CRITICAL_PATH))
	assert_approx(PathOps.path_length_m(path), (path.size() - 1) * Tuning.GRID_CELL_SIZE)


func test_pick_far_cell() -> void:
	var g := LevelGrid.new(Vector2i(10, 1))
	for x in 10:
		g.set_kind(Vector2i(x, 0), LevelGrid.FLOOR)
		if x > 0:
			g.set_wall(Vector2i(x, 0), LevelGrid.W, LevelGrid.NONE)
	var dist := g.distance_field(Vector2i(0, 0))
	assert_eq(PathOps.pick_far_cell(g, dist, 0.5), Vector2i(9, 0))
	var c := PathOps.pick_far_cell(g, dist, 0.5, Callable(), make_rng(1))
	assert_true(c.x >= 5)


func test_carve_rooms_keeps_gaps() -> void:
	for s in 10:
		var g := LevelGrid.new(Vector2i(24, 24))
		var rooms := RoomOps.carve_rooms(g, 6, Vector2i(3, 3), Vector2i(6, 5), 2, make_rng(s))
		assert_gt(rooms.size(), 0)
		for a in rooms:
			assert_true(a.rect.position.x >= 2 and a.rect.end.x <= 22 and a.rect.position.y >= 2 and a.rect.end.y <= 22, "margin")
			for b in rooms:
				if a != b:
					assert_false(a.rect.grow(1).intersects(b.rect), "1-cell gap between rooms")


func test_connect_rooms_guarantees_an_opening() -> void:
	var g := LevelGrid.new(Vector2i(12, 12))
	var rooms := RoomOps.carve_rooms(g, 3, Vector2i(3, 3), Vector2i(4, 4), 2, make_rng(6))
	MazeOps.maze_fill(g, Rect2i(0, 0, 12, 12), make_rng(7))
	RoomOps.connect_rooms(g, rooms, Vector2i(1, 2), make_rng(8), 0.5)
	for r in rooms:
		assert_gt(r.doors.size(), 0)
	assert_eq(_reachable(g, Vector2i(0, 0)), g.walkable_count())


func test_insert_room_only_grows_connectivity() -> void:
	var g := LevelGrid.new(Vector2i(12, 12))
	MazeOps.maze_fill(g, Rect2i(0, 0, 12, 12), make_rng(11))
	var before := g.distance_field(Vector2i(0, 0))[g.idx(Vector2i(11, 11))]
	var room := RoomOps.insert_room(g, Rect2i(5, 5, 2, 2), RoomData.BREAKER)
	assert_not_null(room)
	assert_eq(_reachable(g, Vector2i(0, 0)), g.walkable_count())
	assert_true(g.distance_field(Vector2i(0, 0))[g.idx(Vector2i(11, 11))] <= before)


func test_bsp_split_tiles_the_region() -> void:
	var region := Rect2i(0, 0, 30, 20)
	var parts := RoomOps.bsp_split(region, Vector2i(4, 4), make_rng(2))
	var area := 0
	for p in parts:
		area += p.get_area()
		assert_true(p.size.x >= 4 and p.size.y >= 4)
		assert_true(region.encloses(p))
	assert_eq(area, region.get_area())


func test_poisson_cells_respects_spacing() -> void:
	var cells: Array[Vector2i] = []
	for z in 20:
		for x in 20:
			cells.append(Vector2i(x, z))
	var picks := PlaceOps.poisson_cells(cells, 12, 4, make_rng(1))
	assert_gt(picks.size(), 5)
	for a in picks:
		for b in picks:
			if a != b:
				assert_true(maxi(absi(a.x - b.x), absi(a.y - b.y)) >= 4)


func test_shuffle_is_seeded() -> void:
	var a := [1, 2, 3, 4, 5, 6, 7, 8]
	var b := a.duplicate()
	RoomOps.shuffle(a, make_rng(3))
	RoomOps.shuffle(b, make_rng(3))
	assert_eq(a, b)
