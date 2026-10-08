extends TestCase
## M1.9 run flow, headless (14 §5, 05 §4): start_run → depth 1 built → breaker → exit →
## Landing → depth 2 built → dissolve → summary → title; and the drop arrival.

const RUN_SCENE := preload("res://scenes/run.tscn")
const TIMEOUT_S := 40.0

var _host: Node
var _prev_host: Node
var _prev_transition: Object
var _prev_first_done: bool
var _meta: MetaState


func before_all() -> void:
	_meta = GameState.meta
	GameState.meta = MetaState.new()


func after_all() -> void:
	GameState.meta = _meta


func before_each() -> void:
	_prev_host = SceneRouter.get_host()
	_prev_transition = SceneRouter.transition
	SceneRouter.transition = null
	_prev_first_done = GameState.meta.first_descent_done
	_host = Node.new()
	_host.name = "RunTestHost"
	add_child(_host)
	SceneRouter.set_host(_host)


func after_each() -> void:
	for c in _host.get_children():
		c.queue_free()
	await await_frames(3)
	SceneRouter.set_host(_prev_host)
	SceneRouter.transition = _prev_transition
	GameState.meta.first_descent_done = _prev_first_done
	_host.free()


func _until(cond: Callable, seconds: float = TIMEOUT_S) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _start_run(run_seed: int, first_descent: bool) -> Run:
	GameState.meta.first_descent_done = not first_descent
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", run_seed)
	var run := RUN_SCENE.instantiate() as Run
	run.capture_mouse = false
	run.landing_time = 0.5
	run.drop_fall_time = 0.2
	run.dissolve_time = 0.2
	_host.add_child(run)
	SceneRouter.set_host(_host)
	await _until(func() -> bool: return run.phase == Run.PHASE_PLAYING)
	return run


func test_descent_depth_1_to_2_then_dissolve_to_summary_and_title() -> void:
	var entered: Array = []
	var cb := func(d: int, s: StringName, a: StringName) -> void: entered.append([d, s, a])
	EventBus.level_entered.connect(cb)
	var run := await _start_run(11, true)
	assert_eq(run.phase, Run.PHASE_PLAYING, "depth 1 arrived")
	assert_eq(GameState.run.depth, 1)
	assert_true(run.level.is_walkable_now(), "depth 1 built")
	assert_eq(run.player.get_parent(), run.level, "player re-parented into the level")
	assert_true(run.data.grid.is_walkable(run.data.grid.cell_of(run.player.global_position)), "player on a walkable cell")
	assert_eq(entered.size(), 1)
	if entered.size() > 0:
		assert_eq(entered[0][2], Tuning.RUN_ARRIVE_START)
	# 05 §10 first Descent: a Powered exit with its breaker.
	var exit := run.exit
	assert_not_null(exit, "exit prefab placed")
	assert_not_null(run.breaker, "breaker prefab placed")
	if exit == null or run.breaker == null:
		EventBus.level_entered.disconnect(cb)
		return
	assert_eq(exit.lock, Tuning.LOCK_POWERED)
	assert_eq(exit.status, Tuning.EXIT_STATUS_POWERED)
	assert_false(exit.try_enter(run.player), "a Powered exit refuses the player until powered")
	assert_eq(GameState.run.depth, 1)
	assert_true(run.breaker.throw_breaker(), "breaker thrown")
	assert_true(await _until(func() -> bool: return exit.is_open(), 10.0), "the power wave opens the exit")
	var all_lit := func() -> bool:
		for f in run.level.light_pool.fixtures():
			if not f.powered:
				return false
		return true
	assert_true(await _until(all_lit, 10.0), "every dark fixture lit by the wave")
	# Into the exit: lower Coherence first so the Landing's +20 shows.
	run.player.apply_coherence(-30.0, &"test")
	var door_state: Array = []
	var phase_cb := func(p: StringName) -> void:
		if p == Run.PHASE_LANDING:
			run.landing.door_opened.connect(func() -> void:
				door_state.append([run.landing.elapsed, run.level != null and run.level.is_walkable_now()]))
	run.phase_changed.connect(phase_cb)
	run.player.global_position = exit.to_global(Vector3(0.0, 0.1, -0.45))
	assert_true(await _until(func() -> bool: return run.phase == Run.PHASE_LANDING, 10.0), "Landing reached")
	assert_eq(GameState.run.depth, 2, "descend(true)")
	assert_eq(GameState.run.proper_exits, 1)
	assert_true(await _until(func() -> bool: return run.phase == Run.PHASE_PLAYING and run.arrival == Tuning.RUN_ARRIVE_PROPER),
			"depth 2 arrived")
	assert_eq(door_state.size(), 1, "the cabin door opened once")
	if door_state.size() == 1:
		assert_true(door_state[0][0] >= 0.5, "the Landing held at least its time")
		assert_true(door_state[0][1], "the door waited for walkable geometry")
	assert_approx(run.player.coherence, 90.0, 0.01, "COHERENCE +20 on arrival")
	assert_eq(entered.size(), 2)
	if entered.size() == 2:
		assert_eq(entered[1][0], 2)
		assert_eq(entered[1][2], Tuning.RUN_ARRIVE_PROPER)
	EventBus.level_entered.disconnect(cb)
	# Death: dissolve → summary → title.
	run.player.apply_coherence(-1000.0, &"still")
	assert_true(await _until(func() -> bool: return SceneRouter.current_scene() is RunSummary), "summary shown")
	assert_eq(GameState.last_cause(), &"still")
	assert_false(GameState.is_run_active())
	var summary := SceneRouter.current_scene() as RunSummary
	if summary != null:
		assert_contains(RunSummary.top_line(), "DISSOLVED BY STILL · DEPTH 02")
		summary.choose(RunSummary.ITEM_TITLE)
	assert_true(await _until(func() -> bool: return SceneRouter.current_scene() is Title), "title shown")


func test_drop_arrives_on_a_valid_cell() -> void:
	var run := await _start_run(12, false)
	assert_eq(run.phase, Run.PHASE_PLAYING)
	var owner_node: Object = run.player if run.player.has_signal(Run.DROP_SIGNAL) else run.player.noclip_targeting
	if owner_node != null and owner_node.has_signal(Run.DROP_SIGNAL):
		assert_true(owner_node.is_connected(Run.DROP_SIGNAL, run.commit_drop), "floor_drop_committed connected")
		owner_node.emit_signal(Run.DROP_SIGNAL)
	else:
		run.commit_drop()
	assert_eq(run.phase, Run.PHASE_DROPPING)
	assert_eq(GameState.run.depth, 2)
	assert_eq(GameState.run.drops_total, 0, "the noclip commit counts drops, not the run")
	assert_eq(GameState.run.drops_in_a_row, 1)
	assert_true(await _until(func() -> bool: return run.phase == Run.PHASE_PLAYING), "arrived after the drop")
	assert_eq(run.arrival, Tuning.RUN_ARRIVE_DROP)
	var c := run.data.grid.cell_of(run.player.global_position)
	assert_true(RunLevelSetup.is_drop_cell(run.data, c, [] as Array[Vector3]), "a valid drop cell")
	assert_false(run.data.grid.has_flag(c, LevelGrid.F_EXIT_ROOM), "not in the exit room")
	assert_true(run.player.state_machine.is_in(PlayerStateMachine.IDLE))
