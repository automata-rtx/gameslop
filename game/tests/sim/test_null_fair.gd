extends TestCase
## R14 (10 §2, 07 §5.6): on Pursuit entry a dormant Null within 20 m of the player is
## re-placed at DirectorSpawn.null_pursuit_cell: the critical-path cell between the player
## and the Threshold, >= 20 m from the player, nearest the 55% point; else the path cell on
## the Threshold side farthest from the player; else the walkable cell farthest from the
## player. Pure helper on a hand-made U corridor, then over real Substrate levels.

## The U: row 0 from x 0 to 19, down column 19 to row 4, row 4 back to x 0 (the Threshold
## pocket is (0,4) and (1,4)). 43 path cells; the 55% point is index 23, (19,4).
const W := 20
const ROWS := 5


func _u_level() -> LevelData:
	var g := LevelGrid.new(Vector2i(W, ROWS))
	var path: Array[Vector2i] = []
	for x in W:
		path.append(Vector2i(x, 0))
	for y in range(1, ROWS):
		path.append(Vector2i(W - 1, y))
	for x in range(W - 2, -1, -1):
		path.append(Vector2i(x, ROWS - 1))
	for c in path:
		g.set_kind(c, LevelGrid.FLOOR)
	for i in range(1, path.size()):
		var d := LevelGrid.DIRS.find(path[i] - path[i - 1])
		g.set_wall(path[i - 1], d, LevelGrid.NONE)
	g.finalize_walls()
	g.add_flag(Vector2i(0, ROWS - 1), LevelGrid.F_EXIT_ROOM)
	g.add_flag(Vector2i(1, ROWS - 1), LevelGrid.F_EXIT_ROOM)
	var data := LevelData.new()
	data.grid = g
	data.critical_path = path
	return data


func _at(data: LevelData, c: Vector2i) -> Vector3:
	return data.grid.world_of(c)


func test_needs_replace_is_the_20_m_rule() -> void:
	assert_true(DirectorSpawn.null_needs_replace(Vector3(19.9, 0, 0), Vector3.ZERO))
	assert_false(DirectorSpawn.null_needs_replace(Vector3(20.0, 0, 0), Vector3.ZERO))
	assert_false(DirectorSpawn.null_needs_replace(Vector3(12.0, 3.0, 16.0), Vector3(0, -5.0, 0)), "XZ only")


func test_tier_1_path_cell_ahead_nearest_55_percent() -> void:
	var data := _u_level()
	assert_eq(data.critical_path.size(), 43)
	# At the start: the 55% point itself is ahead and 35 m away.
	assert_eq(DirectorSpawn.null_pursuit_cell(data, _at(data, Vector2i(2, 0))), Vector2i(19, 4))
	# Past the 55% point: the first cell ahead that is 20 m out, (7,4), never one behind.
	var c := DirectorSpawn.null_pursuit_cell(data, _at(data, Vector2i(17, 4)))
	assert_eq(c, Vector2i(7, 4))
	assert_true(DirectorSpawn.flat_dist(_at(data, c), _at(data, Vector2i(17, 4))) >= Tuning.NULL_SPAWN_MIN_DIST)


func test_tier_1_ignores_cells_near_in_a_straight_line_but_behind() -> void:
	var data := _u_level()
	# On row 0 at x 6 the row-4 cells under it are 8 m away in a straight line and behind
	# no wall that matters: not chosen. Ahead and >= 20 m: column 19 and (16..18, 4); the
	# 55% point (19,4) is 27 m away.
	var c := DirectorSpawn.null_pursuit_cell(data, _at(data, Vector2i(6, 0)))
	assert_eq(c, Vector2i(19, 4))
	assert_gt(data.critical_path.find(c), 6, "between the player and the Threshold")
	# At x 10 nothing ahead is 20 m out ((19,4) is 19.7 m): the farthest cell ahead.
	assert_eq(DirectorSpawn.null_pursuit_cell(data, _at(data, Vector2i(10, 0))), Vector2i(19, 4))


func test_tier_2_farthest_path_cell_ahead() -> void:
	var data := _u_level()
	# At (8,4) every cell ahead is within 16 m: the farthest of them, outside the pocket.
	assert_eq(DirectorSpawn.null_pursuit_cell(data, _at(data, Vector2i(8, 4))), Vector2i(2, 4))


func test_tier_3_farthest_walkable_cell() -> void:
	var data := _u_level()
	# In the pocket nothing outside it lies ahead: the farthest walkable cell.
	assert_eq(DirectorSpawn.null_pursuit_cell(data, _at(data, Vector2i(1, 4))), Vector2i(19, 0))
	# No path at all: the same rule.
	data.critical_path = [] as Array[Vector2i]
	assert_eq(DirectorSpawn.null_pursuit_cell(data, _at(data, Vector2i(0, 0))), Vector2i(19, 4))


func test_deterministic_and_fair_on_substrate_levels() -> void:
	var tier1 := 0
	var tries := 0
	for s in range(1, 13):
		var data := LevelGenerator.generate(&"substrate", 6, s)
		var g := data.grid
		var path := data.critical_path
		var to_exit := g.distance_field(path[path.size() - 1])
		var k55 := roundi((path.size() - 1) * Tuning.NULL_SPAWN_PATH_FRACTION)
		var rng := make_rng(s)
		# Players standing within 20 m of Null's spawn cell (the M2.6 failure).
		var near: Array[Vector2i] = []
		for i in g.cell_count():
			var c := g.cell_at(i)
			if g.is_walkable(c) and DirectorSpawn.flat_dist(g.world_of(c), g.world_of(data.null_spawn_cell)) < Tuning.NULL_SPAWN_MIN_DIST:
				near.append(c)
		for k in 6:
			var pc := near[rng.randi_range(0, near.size() - 1)]
			var pos := g.world_of(pc)
			var c := DirectorSpawn.null_pursuit_cell(data, pos)
			tries += 1
			var ctx := "seed %d player %s -> %s" % [s, pc, c]
			assert_eq(DirectorSpawn.null_pursuit_cell(data, pos), c, "deterministic: " + ctx)
			assert_true(g.is_walkable(c), ctx)
			if DirectorSpawn.flat_dist(g.world_of(c), pos) < Tuning.NULL_SPAWN_MIN_DIST:
				continue
			if not path.has(c):
				continue
			tier1 += 1
			assert_false(g.has_flag(c, LevelGrid.F_EXIT_ROOM), "never in the Threshold pocket: " + ctx)
			assert_lt(to_exit[g.idx(c)], to_exit[g.idx(pc)], "nearer the Threshold than the player: " + ctx)
			# No other qualifying path cell is nearer the 55% point.
			var i := path.find(c)
			for j in path.size():
				var o := path[j]
				if g.has_flag(o, LevelGrid.F_EXIT_ROOM) or to_exit[g.idx(o)] >= to_exit[g.idx(pc)]:
					continue
				if DirectorSpawn.flat_dist(g.world_of(o), pos) < Tuning.NULL_SPAWN_MIN_DIST:
					continue
				assert_true(absi(j - k55) >= absi(i - k55), "nearest the 55%% point: %s (index %d vs %d)" % [ctx, i, j])
	assert_gt(tier1, tries / 2, "most re-placements land on the path ahead, 20 m out (%d of %d)" % [tier1, tries])


## R14 sim bot: in the Pursuit the explorer and the cautious bot may plan through a soft
## wall (SimBotNull.soft_edge) when it shortens the way; the crossing is recorded for the
## noclip at the near cell; a refused soft wall (`bad_soft`) is not planned again.
func test_bot_plans_through_a_soft_wall_when_shorter() -> void:
	# Two rows joined at x 19; a soft wall between (3,0) and (3,1).
	var g := LevelGrid.new(Vector2i(W, 2))
	for x in W:
		g.set_kind(Vector2i(x, 0), LevelGrid.FLOOR)
		g.set_kind(Vector2i(x, 1), LevelGrid.FLOOR)
		if x + 1 < W:
			g.set_wall(Vector2i(x, 0), LevelGrid.E, LevelGrid.NONE)
			g.set_wall(Vector2i(x, 1), LevelGrid.E, LevelGrid.NONE)
	g.set_wall(Vector2i(W - 1, 0), LevelGrid.S, LevelGrid.NONE)
	g.set_wall(Vector2i(3, 0), LevelGrid.S, LevelGrid.SOFT)
	g.finalize_walls()
	var data := LevelData.new()
	data.grid = g
	var run := Run.new()
	run.data = data
	var bot := SimBot.new()
	bot.run = run
	bot.nul.bot = bot
	assert_true(SimBotNull.soft_edge(g, Vector2i(3, 0), LevelGrid.S, {}))
	assert_true(SimBotNull.soft_edge(g, Vector2i(3, 1), LevelGrid.N, {}), "either side")
	assert_false(SimBotNull.soft_edge(g, Vector2i(4, 0), LevelGrid.S, {}), "an ordinary wall is not planned")
	var walk := bot._path_avoiding(Vector2i(0, 0), Vector2i(0, 1), {Vector2i(-1, -1): true}, false)
	assert_eq(walk.size(), 2 * W - 1, "without soft walls: around the far end")
	assert_true(bot._soft_cross.is_empty())
	var short := bot._path_avoiding(Vector2i(0, 0), Vector2i(0, 1), {}, true)
	assert_eq(short, [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(3, 1), Vector2i(2, 1), Vector2i(1, 1),
		Vector2i(0, 1)] as Array[Vector2i], "through the soft wall")
	assert_eq(bot._soft_cross, {Vector2i(3, 0): LevelGrid.S}, "the crossing to noclip")
	# Not shorter: the soft wall is not used.
	bot._path_avoiding(Vector2i(10, 0), Vector2i(12, 0), {}, true)
	assert_true(bot._soft_cross.is_empty(), "only when it shortens the way")
	bot.nul.bad_soft[LevelGrid.edge_key(Vector2i(3, 0), LevelGrid.S)] = true
	var again := bot._path_avoiding(Vector2i(0, 0), Vector2i(0, 1), {}, true)
	assert_eq(again.size(), 2 * W - 1, "a refused soft wall is not tried again")
	assert_true(bot._soft_cross.is_empty())
	run.free()
