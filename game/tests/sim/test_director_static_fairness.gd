extends TestCase
## M2.16: the Director's Static fairness (05 §9 rule 6, 08 §3, 10 §7 rule 4). A Static
## field that cuts the only route to the exit is counted every 5 s; at 40 s cumulative it is
## nudged off the critical path (1.2 m/s). A field that does not cut the route is never
## counted, and the count resets after the nudge. Driven through DirectorStatics directly
## (the Director calls it on its 5 s check), on a real Halls level.

const LEVEL_SCENE := preload("res://scenes/level.tscn")
const MAX_FRAMES := 1500
const SEED := 5

var _level: Level
var _p: Player
var _d: Director
var _clock: FakeClock


func before_all() -> void:
	_level = LEVEL_SCENE.instantiate() as Level
	add_child(_level)
	_level.begin(LevelGenerator.generate(&"halls", 1, SEED))
	var frames := 0
	while not _level.is_ready() and frames < MAX_FRAMES:
		await get_tree().process_frame
		frames += 1
	_p = PlayerFixture.spawn_player(_level)
	_level.attach_player(_p, _p.rig.camera)
	await await_physics_frames(5)


func after_all() -> void:
	_level.queue_free()


func before_each() -> void:
	_clock = fake_clock(0.0)
	_d = Director.new()
	_d.time_source = _clock.now
	_level.add_child(_d)
	_d.begin(_level, _p, Tuning.RUN_ARRIVE_START)
	for e in _d.errors.duplicate():
		if is_instance_valid(e):
			e.queue_free()
	_d.errors.clear()
	await await_physics_frames(2)


func after_each() -> void:
	_d.queue_free()
	for e in get_tree().get_nodes_in_group(ErrorBase.GROUP):
		e.queue_free()
	await await_physics_frames(2)


## A critical-path cell where a field of `radius` cuts the only route from the player to the exit.
func _cutting_cell(radius: float) -> Vector2i:
	var g := _level.data.grid
	var from := g.cell_of(_p.global_position)
	for c in _level.data.critical_path:
		if c != from and c != _level.data.exit_cell \
				and DirectorSpawn.static_cuts_path(g, g.world_of(c), radius, from, _level.data.exit_cell):
			return c
	return LevelData.NO_CELL


func _static_at(cell: Vector2i, radius: float) -> ErrorStatic:
	var g := _level.data.grid
	var st := _d.spawn_error(&"static", g.world_of(cell)) as ErrorStatic
	assert_not_null(st)
	if st == null:
		return null
	st.global_position = g.world_of(cell)
	st.radius = radius
	st.wake()
	return st


func test_a_field_cutting_the_route_is_nudged_after_forty_seconds() -> void:
	var g := _level.data.grid
	_p.global_position = g.world_of(_level.data.spawn_cell)
	var cell := _cutting_cell(Tuning.STATIC_RADIUS_MAX)
	if cell == LevelData.NO_CELL:
		fail("seed %d has no single-route cell" % SEED)
		return
	var st := _static_at(cell, Tuning.STATIC_RADIUS_MAX)
	var checks := int(Tuning.STATIC_FAIR_CUMULATIVE_LIMIT / Tuning.STATIC_FAIR_CHECK_INTERVAL)
	for i in checks - 1:
		_d.statics.static_fairness(Tuning.STATIC_FAIR_CHECK_INTERVAL)
	assert_approx(_d.statics.cut_time(st), Tuning.STATIC_FAIR_CUMULATIVE_LIMIT - Tuning.STATIC_FAIR_CHECK_INTERVAL, 0.001, "counting")
	assert_false(st.is_nudged(), "not yet at 35 s")
	_d.statics.static_fairness(Tuning.STATIC_FAIR_CHECK_INTERVAL)
	assert_true(st.is_nudged(), "40 s cumulative: nudged off the critical path")
	assert_approx(_d.statics.cut_time(st), 0.0, 0.001, "the count starts again")


func test_a_field_off_the_route_is_never_counted() -> void:
	var g := _level.data.grid
	_p.global_position = g.world_of(_level.data.spawn_cell)
	# A walkable cell not on the critical path and not covering any of it.
	var far := LevelData.NO_CELL
	for i in g.cell_count():
		var c := g.cell_at(i)
		if g.is_walkable(c) and not DirectorSpawn.static_cuts_path(g, g.world_of(c), Tuning.STATIC_RADIUS_MAX, g.cell_of(_p.global_position), _level.data.exit_cell):
			far = c
			break
	assert_ne(far, LevelData.NO_CELL)
	var st := _static_at(far, Tuning.STATIC_RADIUS_MAX)
	for i in 12:
		_d.statics.static_fairness(Tuning.STATIC_FAIR_CHECK_INTERVAL)
	assert_approx(_d.statics.cut_time(st), 0.0, 0.001)
	assert_false(st.is_nudged())


func test_a_dormant_static_is_ignored() -> void:
	var g := _level.data.grid
	_p.global_position = g.world_of(_level.data.spawn_cell)
	var cell := _cutting_cell(Tuning.STATIC_RADIUS_MAX)
	assert_ne(cell, LevelData.NO_CELL)
	if cell == LevelData.NO_CELL:
		return
	var st := _static_at(cell, Tuning.STATIC_RADIUS_MAX)
	st.sleep()
	for i in 10:
		_d.statics.static_fairness(Tuning.STATIC_FAIR_CHECK_INTERVAL)
	assert_approx(_d.statics.cut_time(st), 0.0, 0.001, "a dormant Static cuts nothing")
	assert_false(st.is_nudged())
