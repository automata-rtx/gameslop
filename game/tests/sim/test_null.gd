extends TestCase
## 08 §7 Null, headless, on the flat floor with the real player and a wall between them:
## the rule (straight at the player at exactly 2.4 m/s, through walls; Cycle 2 2.8), the
## tell reaching CoherenceRenderer (g_null_pos / g_null_radius, 24 m from depth 12) and the
## 11 §3 jitter, the cost (12 per second inside the 2 m core, not a contact: no gate, no
## stun, hidden or not; walking out ends it), Dormant until pursue(), no Satiated, no
## Search, notice once and never an evasion, the roster (depth 6 and the Cycle 2 Substrate
## only), the spawn at LevelData.null_spawn_cell, and determinism.

var _world: Node3D
var _p: Player
var _gate_calls: int = 0


func before_each() -> void:
	get_tree().root.size = Vector2i(1920, 1080)
	PlayerFixture.release_all()
	_world = ErrorFixture.make_world(self)
	_p = PlayerFixture.spawn_player(_world, Vector3(0, 0.05, 0))
	_gate_calls = 0
	CoherenceRenderer.set_null(CoherenceRenderer.NULL_POS_ABSENT, 0.0)
	await await_physics_frames(3)


func after_each() -> void:
	PlayerFixture.release_all()
	_world.free()
	CoherenceRenderer.set_null(CoherenceRenderer.NULL_POS_ABSENT, 0.0)
	await await_physics_frames(1)


func _null(pos: Vector3, depth: int = 6, cycle: int = 1) -> ErrorNull:
	var e := ErrorFixture.spawn(_world, &"null", pos, _p) as ErrorNull
	e.depth = depth
	e.cycle = cycle
	e.contact_request = func(_e: ErrorBase) -> bool:
		_gate_calls += 1
		return false
	return e


func _seconds(t: float) -> void:
	await await_physics_frames(int(round(t * Engine.physics_ticks_per_second)))


func _flat(a: Vector3, b: Vector3) -> float:
	return ErrorFixture.flat(a, b)


# --- the rule ------------------------------------------------------------------------------------

func test_walks_straight_through_a_wall_at_exactly_2_4() -> void:
	# A 4 m high wall 10 m out, between Null (20 m) and the player.
	PlayerFixture.wall(_world, Vector3(0.2, 4.0, 20.0), Vector3(10.0, 2.0, 0.0))
	var e := _null(Vector3(20.0, 0.0, 0.0))
	e.pursue()
	assert_eq(e.state, Tuning.ERROR_STATE_CHASE)
	var start := e.global_position
	await _seconds(2.0)
	var moved := e.global_position.distance_to(start)
	assert_approx(moved, Tuning.NULL_SPEED_CYCLE1 * 2.0, 0.01, "2.4 m/s (moved %.3f m in 2 s)" % moved)
	assert_approx(e.global_position.z, 0.0, 0.001, "a straight line at the player")
	await _seconds(3.0)
	assert_lt(e.global_position.x, 9.0, "it passed the wall (x %.2f)" % e.global_position.x)
	assert_approx(e.global_position.distance_to(start), Tuning.NULL_SPEED_CYCLE1 * 5.0, 0.01, "no slowdown at the wall")


func test_speed_ignores_aggression_and_cycle_2_is_2_8() -> void:
	var e := _null(Vector3(20.0, 0.0, 0.0))
	e.set_aggression(1.0)
	assert_eq(e.speed(), 2.4)
	var c2 := _null(Vector3(-20.0, 0.0, 0.0), 12, 2)
	assert_eq(c2.speed(), 2.8)
	c2.pursue()
	var start := c2.global_position
	await _seconds(1.0)
	assert_approx(c2.global_position.distance_to(start), 2.8, 0.01)


func test_follows_the_players_current_position() -> void:
	var e := _null(Vector3(20.0, 0.0, 0.0))
	e.pursue()
	await _seconds(0.5)
	_p.global_position = Vector3(0.0, 0.05, 20.0)
	_p.velocity = Vector3.ZERO
	var before := e.global_position
	await _seconds(1.0)
	var step := e.global_position - before
	var want := (_p.global_position - before)
	assert_gt(Vector2(step.x, step.z).normalized().dot(Vector2(want.x, want.z).normalized()), 0.999, "re-aims at once")


func test_dormant_does_not_move_or_unrender() -> void:
	var e := _null(Vector3(20.0, 0.0, 0.0))
	await _seconds(1.0)
	assert_true(e.is_dormant())
	assert_eq(e.global_position, Vector3(20.0, 0.0, 0.0))
	assert_eq(CoherenceRenderer.null_radius, 0.0)


# --- the tell ------------------------------------------------------------------------------------

func test_unrender_radius_reaches_the_renderer() -> void:
	var e := _null(Vector3(20.0, 0.0, 0.0))
	e.pursue()
	await _seconds(0.5)
	assert_eq(CoherenceRenderer.null_radius, Tuning.NULL_UNRENDER_RADIUS)
	assert_true(CoherenceRenderer.null_pos.is_equal_approx(e.centre()), "g_null_pos follows it every frame")
	assert_approx(e.centre().y - e.global_position.y, Tuning.ERROR_EYE_HEIGHT, 0.0001, "centred at eye height")
	e.sleep()
	assert_eq(CoherenceRenderer.null_radius, 0.0, "asleep: no radius")
	e.pursue()
	await _seconds(0.1)
	assert_gt(CoherenceRenderer.null_radius, 0.0)
	e.free()
	assert_eq(CoherenceRenderer.null_radius, 0.0, "freed: the slot is cleared")


func test_radius_doubles_from_depth_12() -> void:
	assert_eq(_null(Vector3(20, 0, 0), 6).radius(), 12.0)
	assert_eq(_null(Vector3(25, 0, 0), 11, 2).radius(), 12.0)
	var e := _null(Vector3(30, 0, 0), 12, 2)
	assert_eq(e.radius(), 24.0)
	e.pursue()
	await _seconds(0.1)
	assert_eq(CoherenceRenderer.null_radius, 24.0)


func test_jitter_in_the_radius_and_in_the_core() -> void:
	var e := _null(Vector3(20.0, 0.0, 0.0))
	e.pursue()
	await _seconds(0.2)
	assert_eq(float(_p.rig.get(&"_jitter")), 0.0, "outside the radius")
	e.global_position = Vector3(8.0, 0.0, 0.0)
	await _seconds(0.1)
	assert_eq(float(_p.rig.get(&"_jitter")), Tuning.FEEDBACK_NULL_RADIUS_JITTER)
	e.global_position = _p.global_position
	await _seconds(0.1)
	assert_eq(float(_p.rig.get(&"_jitter")), Tuning.FEEDBACK_NULL_CORE_JITTER)
	e.free()
	assert_eq(float(_p.rig.get(&"_jitter")), 0.0)


# --- the cost ------------------------------------------------------------------------------------

func test_core_drains_12_per_second_without_a_contact() -> void:
	var e := _null(_p.global_position)
	var hits: Array = []
	e.contacted_player.connect(func(c: float) -> void: hits.append(c))
	var before := _p.coherence
	e.pursue()
	await _seconds(1.0)
	assert_true(e.in_core())
	assert_approx(before - _p.coherence, Tuning.NULL_DRAIN_PER_S, 0.25, "12 per second")
	assert_approx(e.drained, before - _p.coherence, 0.001)
	assert_eq(_gate_calls, 0, "not a contact: the gate is never asked")
	assert_false(e.can_contact(), "Null never contacts")
	assert_eq(hits.size(), 0)
	assert_ne(_p.state_machine.state, PlayerStateMachine.STUNNED, "no stun")
	assert_eq(e.state, Tuning.ERROR_STATE_CHASE, "no Satiated")


func test_drain_kills_as_null() -> void:
	var causes: Array = []
	_p.dissolved.connect(func(c: StringName) -> void: causes.append(c))
	_p.apply_coherence(-(_p.coherence - 3.0), &"test")
	var e := _null(_p.global_position)
	e.pursue()
	await _seconds(0.5)
	assert_eq(causes, [&"null"])


func test_outside_the_core_no_drain_and_walking_out_is_possible() -> void:
	var e := _null(Vector3(2.6, 0.0, 0.0))
	var before := _p.coherence
	e.set_physics_process(false)
	e.pursue()
	e.set_physics_process(true)
	await _seconds(0.1)
	assert_false(e.in_core())
	assert_eq(_p.coherence, before, "2.6 m away: nothing")
	# The player walks away faster than it follows (3.2 vs 2.4 m/s): the drain stops.
	e.global_position = _p.global_position
	await _seconds(0.3)
	assert_lt(_p.coherence, before)
	Input.action_press(&"move_forward")
	await _seconds(4.0)
	Input.action_release(&"move_forward")
	assert_false(e.in_core(), "walked out (%.2f m)" % e.eye_distance())
	var after := _p.coherence
	await _seconds(0.3)
	assert_eq(_p.coherence, after, "no drain outside the core")


# --- the Director link ---------------------------------------------------------------------------

func test_pursue_wakes_into_chase_with_one_notice_and_no_evasion() -> void:
	var e := _null(Vector3(20.0, 0.0, 0.0))
	var notices: Array = []
	var losses: Array = []
	e.noticed_player.connect(func() -> void: notices.append(1))
	e.lost_player.connect(func() -> void: losses.append(1))
	assert_true(e.has_method(&"pursue"))
	e.pursue()
	e.pursue()
	assert_eq(e.state, Tuning.ERROR_STATE_CHASE)
	assert_eq(notices.size(), 1)
	e.retreat(20.0)
	assert_eq(e.state, Tuning.ERROR_STATE_CHASE, "retreat does nothing: no Satiated")
	e.start_search(Vector3(-30, 0, 0))
	assert_eq(e.state, Tuning.ERROR_STATE_CHASE, "no Search")
	e.hint(Vector3(-30, 0, 0), true)
	await _seconds(1.0)
	assert_lt(_flat(e.global_position, _p.global_position), 20.0 - 2.0, "hints never steer it")
	assert_eq(losses.size(), 0)


func test_wake_before_navigation_is_remembered() -> void:
	var e := ErrorBase.create(&"null") as ErrorNull
	e.setup(_p, null, 1)
	_world.add_child(e)
	e.global_position = Vector3(20, 0, 0)
	e.pursue()
	assert_true(e.is_dormant())
	e.set_navigation_ready(true)
	assert_eq(e.state, Tuning.ERROR_STATE_CHASE)


func test_never_in_the_roster_outside_depth_6_and_the_cycle_2_substrate() -> void:
	for depth in range(1, 19):
		for stratum: StringName in [&"halls", &"pools", &"garage", &"offices", &"server", &"substrate"]:
			for first: bool in [true, false]:
				var r := DirectorRules.roster(depth, stratum, first, [&"still", &"echo"], make_rng(depth))
				var want := 1 if DirectorRules.cycle_depth(depth) == 6 and stratum == &"substrate" else 0
				assert_eq(r.count(&"null"), want, "depth %d %s" % [depth, stratum])
	assert_true(DirectorRules.spawnable(&"null"))
	assert_false(DirectorRules.phase_wakes(&"null"), "only Pursuit wakes it")
	assert_eq(DirectorRules.awake_arrival_indices([&"null"] as Array[StringName], 2), [] as Array[int],
		"never awake after a drop")


func test_director_spawns_it_at_its_spawn_cell() -> void:
	var data := LevelGenerator.generate(&"substrate", 6, 4)
	assert_ne(data.null_spawn_cell, LevelData.NO_CELL)
	var g := data.grid
	var pos := g.world_of(data.spawn_cell)
	var eye := pos + Vector3.UP * 1.6
	# Facing away from the cell (seed 4: 32 m out, no grid sight).
	var away := pos - g.world_of(data.null_spawn_cell)
	away.y = 0.0
	away = away.normalized()
	assert_true(DirectorSpawn.spawn_ok(g, data.null_spawn_cell, pos, eye, away, deg_to_rad(40.0),
		g.distance_field(g.cell_of(pos))))
	var cells := DirectorSpawn.pick_cells(data, [&"static", &"static", &"null"] as Array[StringName], &"null",
		pos, eye, away, deg_to_rad(40.0), make_rng(1))
	assert_eq(cells[2], data.null_spawn_cell, "07 §5.6: 55% of the critical path")
	# Facing it: Dormant Null draws nothing, so 07 §5.6's point stands (the cone is for bodies).
	cells = DirectorSpawn.pick_cells(data, [&"null"] as Array[StringName], &"null", pos, eye, -away,
		deg_to_rad(40.0), make_rng(1))
	assert_eq(cells[0], data.null_spawn_cell)
	# Within 20 m of it: another fair cell.
	var near := g.world_of(data.null_spawn_cell) + Vector3(4.0, 0.0, 0.0)
	assert_false(DirectorSpawn.null_cell_ok(data, near, []))
	assert_true(DirectorSpawn.null_cell_ok(data, pos, []))


# --- determinism ---------------------------------------------------------------------------------

func test_deterministic() -> void:
	var runs: Array = []
	for i in 2:
		_p.global_position = Vector3(0, 0.05, 0)
		_p.velocity = Vector3.ZERO
		_p.apply_coherence(100.0, &"test")
		var e := _null(Vector3(9.0, 0.0, 5.0))
		e.pursue()
		var trace: Array = []
		for k in 300:
			await get_tree().physics_frame
			if k == 120:
				_p.global_position = Vector3(-3.0, 0.05, 1.0)
				_p.velocity = Vector3.ZERO
			if k % 30 == 0:
				trace.append(e.global_position.snapped(Vector3.ONE * 0.0001))
		trace.append(snappedf(e.drained, 0.0001))
		runs.append(trace)
		e.free()
	assert_eq(runs[0], runs[1])
