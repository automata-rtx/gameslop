extends TestCase
## 08 §7 / 10 §2 Null on a built Substrate (depth 6) with the real Director: spawned
## Dormant at its spawn cell (07 §5.6) when that cell is fair, not awake after a drop, woken
## only by Pursuit at the end of Calm (30 s, 15 s after a drop), never retreated by the
## chaser cap, and unrendering around itself through CoherenceRenderer once awake.

const LEVEL_SCENE := preload("res://scenes/level.tscn")
const MAX_FRAMES := 2400

var _level: Level
var _p: Player
var _d: Director
var _clock: FakeClock
## A run another suite left active would name the stratum and the met hunters; set aside.
var _saved_run: RunState


func before_all() -> void:
	_level = LEVEL_SCENE.instantiate() as Level
	add_child(_level)
	_level.begin(LevelGenerator.generate(&"substrate", 6, 4))
	var frames := 0
	while not _level.is_ready() and frames < MAX_FRAMES:
		await get_tree().process_frame
		frames += 1
	_p = PlayerFixture.spawn_player(_level)
	_p.global_transform = _level.spawn_transform()
	_level.attach_player(_p, _p.rig.camera)
	await await_physics_frames(5)


func after_all() -> void:
	_level.queue_free()
	CoherenceRenderer.set_null(CoherenceRenderer.NULL_POS_ABSENT, 0.0)


func before_each() -> void:
	_saved_run = GameState.run
	GameState.run = null
	_level.attach_player(_p, _p.rig.camera)
	_clock = fake_clock(0.0)
	_d = Director.new()
	_d.time_source = _clock.now
	_level.add_child(_d)


func after_each() -> void:
	GameState.run = _saved_run
	_d.queue_free()
	for e in get_tree().get_nodes_in_group(ErrorBase.GROUP):
		e.queue_free()
	await await_physics_frames(2)
	CoherenceRenderer.set_null(CoherenceRenderer.NULL_POS_ABSENT, 0.0)


func _advance(seconds: float) -> void:
	_clock.advance(seconds)
	_d.update()


func _null() -> ErrorNull:
	for e in _d.errors:
		if e is ErrorNull:
			return e as ErrorNull
	return null


func test_spawned_dormant_and_woken_only_by_pursuit() -> void:
	assert_true(_level.builder.navigation_ok, "the Substrate baked")
	_d.begin(_level, _p, Tuning.RUN_ARRIVE_START)
	assert_true(_d.roster.has(&"null"))
	assert_false(_d.skipped.has(&"null"), "Null has a scene")
	var n := _null()
	assert_not_null(n, "spawned (pending: %s)" % [_d.hunters.pending])
	if n == null:
		return
	assert_true(n.is_dormant())
	assert_true(DirectorSpawn.flat_dist(n.body_position(), _p.global_position) >= Tuning.ERROR_SPAWN_MIN_DIST)
	assert_eq(_level.data.grid.cell_of(n.global_position), _level.data.null_spawn_cell, "07 §5.6 spawn cell")
	await await_physics_frames(2)
	assert_eq(CoherenceRenderer.null_radius, 0.0, "Dormant: no unrender")
	_advance(29.9)
	assert_eq(_d.phase, DirectorPacing.CALM)
	assert_true(n.is_dormant(), "not before Calm ends")
	_advance(0.2)
	assert_eq(_d.phase, DirectorPacing.PURSUIT)
	assert_eq(n.state, Tuning.ERROR_STATE_CHASE, "Pursuit wakes it")
	assert_eq(_d.hunters.null_replaced, 0, "20 m or more away at Pursuit entry: not moved (R14)")
	var at := n.global_position
	await await_physics_frames(30)
	assert_approx(n.global_position.distance_to(at), Tuning.NULL_SPEED_CYCLE1 * 0.5, 0.02, "walks at 2.4 m/s")
	assert_eq(CoherenceRenderer.null_radius, Tuning.NULL_UNRENDER_RADIUS)
	assert_true(CoherenceRenderer.null_pos.is_equal_approx(n.centre()))
	for i in 10:
		_advance(1.0)
	assert_eq(_d.hunters.cap_retreats, 0, "the cap never sends Null away")
	assert_eq(n.state, Tuning.ERROR_STATE_CHASE)


## R14: the player walked up to the dormant Null during Calm; Pursuit re-places it (it
## draws nothing yet) at DirectorSpawn.null_pursuit_cell, 20 m or more away, then wakes it.
func test_pursuit_re_places_a_dormant_null_within_20_m() -> void:
	_d.begin(_level, _p, Tuning.RUN_ARRIVE_START)
	var n := _null()
	assert_not_null(n)
	if n == null:
		return
	var g := _level.data.grid
	var path := _level.data.critical_path
	# 8 m before Null's cell on the critical path: walked up to it during Calm.
	var near := path[maxi(path.find(g.cell_of(n.global_position)) - 4, 0)]
	_p.global_position = g.world_of(near) + Vector3.UP * 0.05
	await await_physics_frames(2)
	var before := DirectorSpawn.flat_dist(n.global_position, _p.global_position)
	assert_true(DirectorSpawn.null_needs_replace(n.global_position, _p.global_position), "set up within 20 m")
	var want := DirectorSpawn.null_pursuit_cell(_level.data, _p.global_position)
	_advance(30.1)
	assert_eq(_d.phase, DirectorPacing.PURSUIT)
	assert_eq(_d.hunters.null_replaced, 1)
	assert_eq(g.cell_of(n.global_position), want, "at the R14 cell")
	assert_true(path.has(want) and path.find(want) > path.find(near), "on the critical path, Threshold side")
	assert_gt(DirectorSpawn.flat_dist(n.global_position, _p.global_position), before, "farther than it was")
	assert_eq(n.state, Tuning.ERROR_STATE_CHASE, "then woken")
	_p.global_transform = _level.spawn_transform()
	await await_physics_frames(2)


func test_not_awake_after_a_drop() -> void:
	_d.begin(_level, _p, Tuning.RUN_ARRIVE_DROP)
	var n := _null()
	if n == null:
		assert_true(_d.hunters.pending.has(&"null"), "spawned or pending")
		return
	assert_true(n.is_dormant(), "a drop never wakes Null (10 §7 rule 9)")
	assert_false(_d.hunters.awake.has(n))
	_advance(14.9)
	assert_true(n.is_dormant())


## 08 §9 arena: key 5 spawns Null awake (its Pursuit), fair, and unrendering.
func test_arena_key_5_spawns_null_awake() -> void:
	var arena := (load("res://scenes/debug/error_arena.tscn") as PackedScene).instantiate() as ErrorArena
	add_child(arena)
	var frames := 0
	while (arena.player == null or not arena.level.is_ready() or arena.get(&"_log") == null) and frames < MAX_FRAMES:
		await get_tree().process_frame
		frames += 1
	var ev := InputEventKey.new()
	ev.keycode = KEY_5
	ev.pressed = true
	arena._unhandled_key_input(ev)
	assert_eq(arena.errors.size(), 1)
	var n := arena.errors[0] as ErrorNull
	assert_not_null(n)
	if n != null:
		assert_eq(n.state, Tuning.ERROR_STATE_CHASE)
		assert_true(n.distance_to_player() >= Tuning.ERROR_SPAWN_MIN_DIST - 0.01 or arena.data.null_spawn_cell == LevelData.NO_CELL)
		await await_physics_frames(2)
		assert_eq(CoherenceRenderer.null_radius, Tuning.NULL_UNRENDER_RADIUS)
	arena.free()
	await await_physics_frames(1)
	assert_eq(CoherenceRenderer.null_radius, 0.0, "freed with the arena")
