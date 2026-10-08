extends TestCase
## 08 §4 Still, headless on a flat navigable floor: the rule (never a millimetre while
## observed, lit, in frustum), movement when unobserved or unlit, the Chase speed cap,
## contact only through the gate, the reaction window, notice and evasion, the render
## tick, dormancy until navigation is ready, and the 08 §9 behaviour test.

var _world: Node3D
var _p: Player


func before_each() -> void:
	get_tree().root.size = Vector2i(1920, 1080)
	PlayerFixture.release_all()
	_world = ErrorFixture.make_world(self)
	_p = PlayerFixture.spawn_player(_world, Vector3(0, 0.05, 0))
	await await_physics_frames(3)


func after_each() -> void:
	Engine.time_scale = 1.0
	_world.free()


func _still(pos: Vector3, aggression: float = 0.25) -> ErrorStill:
	var s := ErrorFixture.spawn(_world, &"still", pos, _p) as ErrorStill
	s.set_aggression(aggression)
	return s


func test_never_moves_while_observed() -> void:
	# Lit by the flashlight, in frustum, 6 m ahead; hinted onto the player and aggressive.
	_p.flashlight.set_on(true)
	var s := _still(Vector3(0, 0, -6), 1.0)
	s.hint(_p.global_position)
	s.wake()
	await await_physics_frames(2)
	var start := s.body_position()
	var moved := 0.0
	var frames_observed := 0
	for i in 180:
		await get_tree().physics_frame
		moved = maxf(moved, s.body_position().distance_to(start))
		frames_observed += 1 if s.observed else 0
	assert_eq(frames_observed, 180, "observed every frame")
	assert_eq(moved, 0.0, "not a millimetre while observed")
	assert_eq(s.state, Tuning.ERROR_STATE_CHASE, "it saw the player and chases, frozen")


func test_moves_when_unlit() -> void:
	# In view but dark: looking is not enough (08 §4).
	var s := _still(Vector3(0, 0, -12))
	s.senses.sight_range = 0.0  # it would stand through its reaction window otherwise
	s.hint(Vector3(6, 0, -12))
	s.wake()
	await await_physics_frames(60)
	assert_false(s.observed)
	assert_gt(s.body_position().distance_to(Vector3(0, 0, -12)), 0.5, "moved in the dark")


func test_moves_when_out_of_frustum() -> void:
	_p.flashlight.set_on(true)
	var s := _still(Vector3(0, 0, 12))  # behind the player
	s.senses.sight_range = 0.0
	s.hint(Vector3(6, 0, 12))
	s.wake()
	await await_physics_frames(60)
	assert_false(s.observed)
	assert_gt(s.body_position().distance_to(Vector3(0, 0, 12)), 0.5)


func test_freezes_the_moment_it_is_lit() -> void:
	var s := _still(Vector3(0, 0, -22), 1.0)
	s.wake()
	for i in 120:  # it sees the player (no light needed) and chases
		await get_tree().physics_frame
		if s.state == Tuning.ERROR_STATE_CHASE:
			break
	await await_physics_frames(20)
	assert_eq(s.state, Tuning.ERROR_STATE_CHASE)
	_p.flashlight.set_on(true)
	await await_physics_frames(1)
	var at := s.body_position()
	await await_physics_frames(60)
	assert_eq(s.body_position().distance_to(at), 0.0, "frozen once observed")


func test_speed_table_and_cap() -> void:
	var s := _still(Vector3(0, 0, -20))
	s.set_aggression(0.25)
	assert_approx(s.speed_for(Tuning.ERROR_STATE_WANDER), 1.8 * 0.9, 0.0001)
	assert_approx(s.speed_for(Tuning.ERROR_STATE_SEARCH), 3.6 * 0.9, 0.0001)
	assert_approx(s.speed_for(Tuning.ERROR_STATE_CHASE), 5.0 * 0.9, 0.0001)
	s.set_aggression(1.0)
	assert_approx(s.speed_for(Tuning.ERROR_STATE_CHASE), Tuning.STILL_CHASE_SPEED_CAP, 0.0001, "5.75 capped at 5.4")
	assert_lt(Tuning.STILL_CHASE_SPEED_CAP, Tuning.PLAYER_SPRINT_SPEED, "sprint stays an escape")
	assert_approx(s.reaction_window(), 0.8, 0.0001)
	s.set_aggression(0.5)
	assert_approx(s.reaction_window(), 1.15, 0.0001)


func test_chase_respects_the_cap() -> void:
	var s := _still(Vector3(0, 0, 22), 1.0)  # behind, dark: unobserved, within sight range
	s.wake()
	var last := s.body_position()
	var top := 0.0
	for i in 240:
		await get_tree().physics_frame
		var now := s.body_position()
		var dt := get_physics_process_delta_time()
		if s.state == Tuning.ERROR_STATE_CHASE:
			top = maxf(top, ErrorFixture.flat(now, last) / dt)
		last = now
	assert_gt(top, 4.0, "it chased")
	assert_lt(top, Tuning.STILL_CHASE_SPEED_CAP + 0.05, "never above 5.4 m/s")


func test_contact_only_through_the_gate() -> void:
	var s := _still(Vector3(0, 0, 0.8))  # behind, within 1 m
	var asked := [0]
	s.contact_request = func(_e: ErrorBase) -> bool:
		asked[0] += 1
		return false
	var hits := [0]
	s.contacted_player.connect(func(_c: float) -> void: hits[0] += 1)
	s.wake()
	await await_physics_frames(20)
	assert_gt(asked[0], 0, "the gate was asked")
	assert_eq(hits[0], 0)
	assert_approx(_p.coherence, Tuning.COHERENCE_MAX, 0.0001, "refused: nothing applied")
	s.contact_request = func(_e: ErrorBase) -> bool: return true
	await await_physics_frames(6)
	assert_eq(hits[0], 1)
	assert_approx(_p.coherence, Tuning.COHERENCE_MAX - Tuning.STILL_CONTACT_COST, 0.0001)
	assert_eq(s.state, Tuning.ERROR_STATE_SATIATED)


func test_player_contact_gate_also_refuses() -> void:
	var s := _still(Vector3(0, 0, 0.8))
	_p.contact_gate = func(_e: Node3D) -> bool: return false
	s.wake()
	await await_physics_frames(20)
	assert_approx(_p.coherence, Tuning.COHERENCE_MAX, 0.0001)
	assert_ne(s.state, Tuning.ERROR_STATE_SATIATED)


func test_no_contact_with_a_hidden_player_by_proximity() -> void:
	var s := _still(Vector3(0, 0, 0.8))
	_p.hiding.spot = HideSpot.new()  # stands in for an occupied spot
	s.wake()
	await await_physics_frames(20)
	_p.hiding.spot.free()
	_p.hiding.spot = null
	assert_approx(_p.coherence, Tuning.COHERENCE_MAX, 0.0001)


func test_reaction_window_then_chase_and_notice() -> void:
	var s := _still(Vector3(0, 0, -10), 0.25)
	var notices := [0]
	s.noticed_player.connect(func() -> void: notices[0] += 1)
	s.wake()
	await await_physics_frames(2)
	var at := s.body_position()
	await await_physics_frames(int(1.2 * Engine.physics_ticks_per_second))
	assert_eq(s.state, Tuning.ERROR_STATE_WANDER, "still inside the 1.5 s reaction window")
	assert_lt(s.body_position().distance_to(at), 0.01, "it stands while it reacts")
	await await_physics_frames(int(0.5 * Engine.physics_ticks_per_second))
	assert_eq(s.state, Tuning.ERROR_STATE_CHASE)
	assert_eq(notices[0], 1)


func test_heard_steps_start_a_chase() -> void:
	var s := _still(Vector3(0, 0, 8))  # behind, dark, but within hearing
	s.senses.sight_range = 0.0  # isolate hearing
	s.wake()
	await await_physics_frames(2)
	NoiseModel.emit(Vector3(0, 0, 4), 7.0, Tuning.NOISE_KIND_STEP)
	await await_physics_frames(1)
	assert_eq(s.state, Tuning.ERROR_STATE_WANDER, "one step: 0.6")
	NoiseModel.emit(Vector3(0, 0, 4), 7.0, Tuning.NOISE_KIND_STEP)
	await await_physics_frames(2)
	assert_eq(s.state, Tuning.ERROR_STATE_CHASE, "two steps: 1.2")
	assert_approx(s.senses.last_known_pos.z, 4.0, 0.001)


func test_lost_sight_search_then_evasion() -> void:
	Engine.time_scale = 4.0
	var s := _still(Vector3(0, 0, 14), 0.25)
	var lost := [0]
	s.lost_player.connect(func() -> void: lost[0] += 1)
	s.wake()
	for i in 200:
		await get_tree().physics_frame
		if s.state == Tuning.ERROR_STATE_CHASE:
			break
	assert_eq(s.state, Tuning.ERROR_STATE_CHASE)
	# The player steps behind a wall far away: line of sight breaks.
	PlayerFixture.wall(_world, Vector3(20, 4, 0.4), Vector3(0, 2, -20))
	_p.global_position = Vector3(0, 0.05, -26)
	var saw_search := false
	for i in 600:
		await get_tree().physics_frame
		saw_search = saw_search or s.state == Tuning.ERROR_STATE_SEARCH
		if lost[0] > 0:
			break
	assert_true(saw_search, "Chase -> Search after 2 s without sight")
	assert_eq(lost[0], 1, "Search gave up: one evasion")
	assert_eq(s.state, Tuning.ERROR_STATE_WANDER)


func test_render_tick() -> void:
	_p.flashlight.set_on(true)
	var s := _still(Vector3(0, 0, -6))
	s.senses.sight_range = 0.0  # keep it in Wander
	s.wake()
	await await_physics_frames(3)
	assert_eq(s.ticks, 1, "once when first observed in Wander")
	await await_physics_frames(int(1.8 * Engine.physics_ticks_per_second))
	assert_eq(s.ticks, 1, "nothing before 2 s")
	for i in 30:
		await get_tree().physics_frame
		if s.ticks == 2:
			break
	assert_eq(s.ticks, 2, "again after 2 s observed")
	assert_approx(float(s.column.get_instance_shader_parameter(&"line_on")), 1.0, 0.0001)
	await await_physics_frames(int(0.15 * Engine.physics_ticks_per_second))
	assert_approx(float(s.column.get_instance_shader_parameter(&"line_on")), 0.0, 0.0001, "100 ms")


func test_dormant_until_navigation_ready() -> void:
	var s := ErrorBase.create(&"still") as ErrorStill
	s.setup(_p, null, 3)
	_world.add_child(s)
	s.place_at(Vector3(0, 0, 10))
	s.wake()
	await await_physics_frames(10)
	assert_eq(s.state, Tuning.ERROR_STATE_DORMANT)
	assert_eq(s.body.process_mode, Node.PROCESS_MODE_DISABLED, "body frozen while Dormant")
	s.set_navigation_ready(false)
	assert_eq(s.state, Tuning.ERROR_STATE_DORMANT, "a failed bake keeps it dormant")
	s.set_navigation_ready(true)
	assert_eq(s.state, Tuning.ERROR_STATE_WANDER, "the remembered wake applies")


func test_satiated_retreats_away() -> void:
	var s := _still(Vector3(0, 0, 0.8))
	s.wake()
	await await_physics_frames(10)
	assert_eq(s.state, Tuning.ERROR_STATE_SATIATED)
	var hits := [0]
	s.contacted_player.connect(func(_c: float) -> void: hits[0] += 1)
	Engine.time_scale = 4.0
	await await_physics_frames(120)
	assert_eq(hits[0], 0, "no contact while satiated")
	assert_gt(s.distance_to_player(), 6.0, "it retreats")


## 08 §9: Still 25 m away, the player stands facing away: contact within 40 s.
func test_behaviour_contact_within_40_s_facing_away() -> void:
	Engine.time_scale = 4.0
	var s := _still(Vector3(0, 0, 25), 0.25)
	var hits := [0]
	s.contacted_player.connect(func(_c: float) -> void: hits[0] += 1)
	s.wake()
	var t := 0.0
	while hits[0] == 0 and t < 40.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	assert_eq(hits[0], 1, "contact (%.1f s)" % t)
	assert_lt(t, 40.0)
