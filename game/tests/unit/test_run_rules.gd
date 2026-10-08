extends TestCase
## M1.9 rules: strata order (05 §2), power wave order (02 §6), exit lock (07 §6), the Landing
## door rule (07 §3), Landing choices (05 §4, 09 §2), drop cells (05 §4), note recording,
## summary lines (04 §7).

const ELEVATOR := preload("res://scenes/exits/elevator.tscn")
const BREAKER := preload("res://scenes/interactables/breaker.tscn")

var _meta: MetaState
var _run: RunState


func before_all() -> void:
	_meta = GameState.meta
	_run = GameState.run
	GameState.meta = MetaState.new()


func after_all() -> void:
	if GameState.is_run_active():
		GameState.end_run(&"abandoned")
	GameState.meta = _meta
	GameState.run = _run


func test_strata_order_follows_05_2() -> void:
	for s in 200:
		var order := GameState.strata_order_for(s)
		assert_eq(order.size(), 6)
		assert_eq(order[0], &"halls")
		assert_contains([&"pools", &"garage"], order[1])
		assert_contains([&"pools", &"garage", &"offices"], order[2])
		assert_ne(order[2], order[1])
		assert_ne(order[1], &"server")
		assert_ne(order[2], &"server")
		assert_eq(order[5], &"substrate")
		var mid := order.slice(1, 5)
		for k: StringName in [&"pools", &"garage", &"offices", &"server"]:
			assert_eq(mid.count(k), 1, "seed %d: %s once in depths 2 to 5" % [s, k])
	assert_eq(GameState.strata_order_for(7), GameState.strata_order_for(7), "seeded")


func test_start_run_applies_loadout_and_order() -> void:
	GameState.start_run(Tuning.MODE_DESCENT, &"diver", 5)
	assert_eq(GameState.run.depth, 3)
	assert_approx(GameState.run.coherence, 70.0)
	assert_eq(GameState.run.strata_order, GameState.strata_order_for(5))
	assert_eq(GameState.stratum_for(1), &"halls")
	assert_eq(GameState.stratum_for(7), &"halls", "Cycle 2 repeats the order")
	GameState.end_run(&"abandoned")


func test_note_found_is_recorded_once() -> void:
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 9)
	EventBus.note_found.emit(&"H2")
	EventBus.note_found.emit(&"H2")
	assert_eq(GameState.run.notes_found, [&"H2"] as Array[StringName])
	assert_true(GameState.meta.notes_found.has(&"H2"))
	GameState.end_run(&"abandoned")
	EventBus.note_found.emit(&"H3")
	assert_false(GameState.run.notes_found.has(&"H3"), "no recording after the run ended")


## A U-shaped corridor: fixture B is close in a straight line but far on foot.
func test_power_wave_orders_by_walking_distance() -> void:
	var g := LevelGrid.new(Vector2i(3, 4))
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3),
		Vector2i(1, 3), Vector2i(2, 3), Vector2i(2, 2), Vector2i(2, 1), Vector2i(2, 0)]
	for k in path.size():
		g.set_kind(path[k], LevelGrid.FLOOR)
		if k > 0:
			g.set_wall(path[k - 1], LevelGrid.DIRS.find(path[k] - path[k - 1]), LevelGrid.NONE)
	var from := Vector2i(0, 0)
	var near_walk := g.world_of(Vector2i(0, 2))   # 4 m on foot, 4 m straight
	var far_walk := g.world_of(Vector2i(2, 0))    # 4 m straight, 16 m on foot
	var delays := Breaker.wave_delays(g, from, [far_walk, near_walk] as Array[Vector3])
	assert_lt(delays[1], delays[0], "walking distance, not the straight line, orders the wave")
	assert_approx(delays[1], 4.0 / Tuning.LIGHT_BREAKER_WAVE_SPEED, 0.001, "12 m/s, first fixture no stagger")
	assert_approx(delays[0], 16.0 / Tuning.LIGHT_BREAKER_WAVE_SPEED + Tuning.LIGHT_BREAKER_STAGGER_MS / 1000.0, 0.001,
			"second fixture adds the 40 ms stagger")


func test_powered_exit_is_locked_until_powered() -> void:
	var exit := ELEVATOR.instantiate() as Exit
	exit.lock = Tuning.LOCK_POWERED
	add_child(exit)
	var statuses: Array = []
	var cb := func(s: StringName, _t: float) -> void: statuses.append(s)
	EventBus.exit_status_changed.connect(cb)
	assert_eq(exit.status, Tuning.EXIT_STATUS_POWERED)
	assert_false(exit.is_open())
	var p := Player.new()
	assert_false(exit.try_enter(p), "closed")
	exit.mark_seen()
	assert_eq(statuses, [Tuning.EXIT_STATUS_POWERED], "seen prints EXIT: POWERED")
	exit.power()
	assert_true(exit.is_open())
	assert_eq(statuses.back(), Tuning.EXIT_STATUS_OPEN)
	var entered: Array = []
	exit.entering.connect(func(n: Node3D) -> void: entered.append(n))
	assert_true(exit.try_enter(p))
	assert_false(exit.try_enter(p), "once")
	assert_eq(entered.size(), 1)
	EventBus.exit_status_changed.disconnect(cb)
	p.free()
	exit.queue_free()


func test_open_exit_and_unseen_status() -> void:
	var exit := ELEVATOR.instantiate() as Exit
	add_child(exit)
	var statuses: Array = []
	var cb := func(s: StringName, _t: float) -> void: statuses.append(s)
	EventBus.exit_status_changed.connect(cb)
	assert_true(exit.is_open())
	assert_eq(statuses.size(), 0, "UNKNOWN until seen")
	exit.mark_seen()
	assert_eq(statuses, [Tuning.EXIT_STATUS_OPEN])
	EventBus.exit_status_changed.disconnect(cb)
	exit.queue_free()


func test_breaker_throws_once_with_noise_and_bus() -> void:
	var b := BREAKER.instantiate() as Breaker
	add_child(b)
	var thrown: Array = []
	var noises: Array = []
	var cb := func(pos: Vector3) -> void: thrown.append(pos)
	var ncb := func(_p: Vector3, r: float, k: StringName) -> void: noises.append([r, k])
	EventBus.breaker_thrown.connect(cb)
	EventBus.noise_emitted.connect(ncb)
	assert_eq(b.interactable.prompt, Strings.PROMPT_FLIP_BREAKER)
	assert_approx(b.interactable.hold_time, Tuning.BREAKER_HOLD_TIME)
	assert_true(b.throw_breaker())
	assert_false(b.throw_breaker())
	assert_eq(thrown.size(), 1)
	assert_contains(noises, [Tuning.NOISE_BREAKER_RADIUS, Tuning.NOISE_KIND_MECH])
	assert_false(b.interactable.enabled)
	EventBus.breaker_thrown.disconnect(cb)
	EventBus.noise_emitted.disconnect(ncb)
	b.queue_free()


func test_landing_door_waits_for_the_level() -> void:
	var hold := Tuning.LANDING_TIME
	assert_false(Landing.door_may_open(hold - 0.1, hold, true, true), "never before 6 s")
	assert_true(Landing.door_may_open(hold, hold, true, true))
	assert_false(Landing.door_may_open(hold + 1.0, hold, false, true), "holds for the bake")
	assert_true(Landing.door_may_open(hold + Tuning.LANDING_MAX_EXTRA_WAIT, hold, false, true), "at most 3 s extra")
	assert_false(Landing.door_may_open(hold + 60.0, hold, false, false), "never without geometry")


func test_landing_choices() -> void:
	var meta := MetaState.new()
	var pool := RunLevelSetup.item_pool(meta)
	assert_eq(pool, [&"polaroid", &"chalk"] as Array[StringName], "locked kinds stay out")
	meta.earn(&"glowstick")
	meta.earn(&"flare")
	meta.earn(&"radio")
	meta.earn(&"fuse")
	pool = RunLevelSetup.item_pool(meta)
	for k: StringName in [&"flare", &"radio", &"fuse"]:
		assert_false(pool.has(k), "%s has no world scene until M2.8" % k)
	assert_true(pool.has(&"glowstick"))
	var accept_all := func(_k: StringName) -> bool: return true
	var none_held := func(_k: StringName) -> int: return 0
	for s in 50:
		var c := RunLevelSetup.landing_choices(pool, accept_all, none_held, make_rng(s))
		assert_eq(c.size(), 2)
		assert_ne(c[0], c[1], "two different kinds")
	var no_polaroid := func(k: StringName) -> bool: return k != &"polaroid"
	for s in 20:
		assert_false(RunLevelSetup.landing_choices(pool, no_polaroid, none_held, make_rng(s)).has(&"polaroid"),
				"kinds the belt cannot take are excluded")


func test_drop_cell_rules() -> void:
	var data := LevelGenerator.generate(&"halls", 2, 3)
	var rng := make_rng(1)
	var c := RunLevelSetup.pick_drop_cell(data, rng, [] as Array[Vector3])
	assert_ne(c, LevelData.NO_CELL)
	assert_true(data.grid.is_walkable(c))
	assert_false(data.grid.has_flag(c, LevelGrid.F_EXIT_ROOM))
	var err := data.grid.world_of(c)
	assert_false(RunLevelSetup.is_drop_cell(data, c, [err] as Array[Vector3]), "15 m from every error")
	for s in 30:
		var d := RunLevelSetup.pick_drop_cell(data, make_rng(s), [err] as Array[Vector3])
		assert_true(data.grid.world_of(d).distance_to(err) >= Tuning.DROP_ARRIVAL_MIN_ERROR_DIST)
	assert_false(RunLevelSetup.is_drop_cell(data, data.exit_cell, [] as Array[Vector3]), "never the exit room")


func test_summary_lines() -> void:
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 21)
	GameState.record_wall_pass()
	GameState.record_drop()
	GameState.record_spend(&"noclip_wall", 15.4)
	GameState.end_run(&"echo")
	assert_eq(RunSummary.top_line(), "DISSOLVED BY ECHO · DEPTH 01 · HALLS")
	var t := RunSummary.table_lines()
	assert_contains(t, "WALLS PASSED 1")
	assert_contains(t, "FLOORS DROPPED 1")
	assert_contains(t, "COHERENCE SPENT 15")
	assert_contains(t, "DEPTH 1")
	assert_eq(RunSummary.format_time(702.0), "11:42")
	assert_ne(RunSummary.cause_explanation(&"echo"), Strings.CAUSE_EXPLANATION_DEFAULT)
