extends TestCase
## 08 §3 Static, headless: drain rate and falloff inside and nothing outside, the renderer
## and bed while inside, notice and evasion, drift speeds by aggression, Search on noise,
## the flare push and the flare's 6 m, the grid cell path, and the seeded radius.

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
	await await_physics_frames(1)


## A Static whose field centre sits `offset` from the player's eye, parked (hinted onto
## itself, so it dwells).
func _static_at(offset: Vector3, aggression: float = 0.25) -> ErrorStatic:
	var eye := _p.eye_position()
	var root := eye + offset - Vector3.UP * Tuning.STATIC_CENTRE_HEIGHT
	var s := ErrorFixture.spawn(_world, &"static", root, _p) as ErrorStatic
	s.set_aggression(aggression)
	s.hint(root)
	return s


func test_falloff() -> void:
	assert_approx(ErrorStatic.falloff(4.0, 0.0), 1.0)
	assert_approx(ErrorStatic.falloff(4.0, 2.4), 1.0, 0.0001, "full in the inner 60%")
	assert_approx(ErrorStatic.falloff(4.0, 3.2), 0.5, 0.0001, "smooth between")
	assert_approx(ErrorStatic.falloff(4.0, 4.0), 0.0)
	assert_approx(ErrorStatic.falloff(4.0, 6.0), 0.0)


func test_radius_is_seeded() -> void:
	var a := ErrorFixture.spawn(_world, &"static", Vector3(20, 0, 20), _p, 11) as ErrorStatic
	var b := ErrorFixture.spawn(_world, &"static", Vector3(-20, 0, 20), _p, 11) as ErrorStatic
	assert_approx(a.radius, b.radius, 0.0, "same seed, same radius")
	assert_true(a.radius >= Tuning.STATIC_RADIUS_MIN and a.radius <= Tuning.STATIC_RADIUS_MAX)
	assert_approx(((a.mesh.mesh as SphereMesh).radius), a.radius, 0.0001, "the mesh matches")


func test_drains_four_per_second_at_the_centre() -> void:
	var s := _static_at(Vector3.ZERO)
	s.wake()
	var frames := int(Engine.physics_ticks_per_second)
	await await_physics_frames(frames)
	var expect := Tuning.STATIC_DRAIN_PER_S * frames / float(Engine.physics_ticks_per_second)
	assert_approx(s.drained, expect, 0.15, "4 per second")
	assert_approx(Tuning.COHERENCE_MAX - _p.coherence, s.drained, 0.01, "applied to the player")
	assert_true(s.inside)
	assert_gt(CoherenceRenderer.static_amount, 0.99, "renderer: grain and CA inside")
	assert_approx(_p.rig._jitter, Tuning.FEEDBACK_STATIC_JITTER, 0.00001)


func test_drain_scales_at_the_edge() -> void:
	var s := _static_at(Vector3(0, 0, 0))
	var d := s.radius * 0.8  # halfway between 0.6 r and r
	s.queue_free()
	await await_physics_frames(1)
	s = _static_at(Vector3(d, 0, 0))
	s.wake()
	await await_physics_frames(int(Engine.physics_ticks_per_second))
	assert_approx(s.drained, Tuning.STATIC_DRAIN_PER_S * 0.5, 0.2, "smoothstep(r, 0.6 r, d) = 0.5")


func test_no_drain_outside() -> void:
	var s := _static_at(Vector3(6.0, 0, 0))
	s.wake()
	await await_physics_frames(60)
	assert_false(s.inside)
	assert_approx(_p.coherence, Tuning.COHERENCE_MAX, 0.0001)
	assert_approx(CoherenceRenderer.static_amount, 0.0, 0.0001)


func test_ignores_hiding() -> void:
	var s := _static_at(Vector3.ZERO)
	_p.hiding.spot = HideSpot.new()
	s.wake()
	await await_physics_frames(30)
	_p.hiding.spot.free()
	_p.hiding.spot = null
	assert_gt(Tuning.COHERENCE_MAX - _p.coherence, 1.0)


func test_notice_and_evasion() -> void:
	var s := _static_at(Vector3.ZERO)
	var counts := {"notice": 0, "lost": 0}
	s.noticed_player.connect(func() -> void: counts["notice"] += 1)
	s.lost_player.connect(func() -> void: counts["lost"] += 1)
	s.wake()
	await await_physics_frames(20)
	assert_eq(counts["notice"], 1, "the field first contains the player")
	# Out after under 2 s: no evasion.
	_p.global_position = Vector3(15, 0.05, 0)
	await await_physics_frames(3)
	assert_eq(counts["lost"], 0, "released before 2 s")
	assert_approx(CoherenceRenderer.static_amount, 0.0, 0.0001, "renderer released")
	_p.global_position = Vector3(0, 0.05, 0)
	await await_physics_frames(int(2.2 * Engine.physics_ticks_per_second))
	assert_eq(counts["notice"], 2, "a new engagement")
	_p.global_position = Vector3(15, 0.05, 0)
	await await_physics_frames(3)
	assert_eq(counts["lost"], 1, "released after 2 s: an evasion")


func test_drift_speed_by_aggression() -> void:
	var s := _static_at(Vector3(20, 0, 0))
	assert_approx(s.drift_speed(), 0.6, 0.0001)
	assert_approx(s.search_speed(), 0.9, 0.0001)
	s.set_aggression(1.0)
	assert_approx(s.drift_speed(), 0.9, 0.0001)
	assert_approx(s.search_speed(), 1.2, 0.0001)
	s.set_aggression(0.25)
	s.clear_hint()
	s.hint(s.global_position + Vector3(0, 0, 20))
	s.wake()
	await await_physics_frames(2)
	var a := s.global_position
	await await_physics_frames(int(Engine.physics_ticks_per_second))
	assert_approx(ErrorFixture.flat(a, s.global_position), 0.6, 0.05, "0.6 m/s")


func test_search_on_three_steps_or_a_tear() -> void:
	var s := _static_at(Vector3(20, 0, 0))
	s.wake()
	await await_physics_frames(2)
	var at := s.global_position + Vector3(0, 0, 3)
	NoiseModel.emit(at, 7.0, Tuning.NOISE_KIND_STEP)
	NoiseModel.emit(at, 7.0, Tuning.NOISE_KIND_STEP)
	await await_physics_frames(1)
	assert_eq(s.state, Tuning.ERROR_STATE_WANDER, "two steps are not enough")
	NoiseModel.emit(at, 7.0, Tuning.NOISE_KIND_STEP)
	await await_physics_frames(1)
	assert_eq(s.state, Tuning.ERROR_STATE_SEARCH, "three steps within 10 s")
	var t := _static_at(Vector3(-20, 0, 0))
	t.wake()
	await await_physics_frames(2)
	NoiseModel.emit(t.global_position + Vector3(0, 0, 5), 20.0, Tuning.NOISE_KIND_TEAR)
	await await_physics_frames(1)
	assert_eq(t.state, Tuning.ERROR_STATE_SEARCH, "any tear")
	assert_approx(t.senses.last_known_pos.z, t.global_position.z + 5.0, 0.5)


func test_never_chases_or_contacts() -> void:
	var s := _static_at(Vector3.ZERO)
	var hits := [0]
	s.contacted_player.connect(func(_c: float) -> void: hits[0] += 1)
	var states: Array[StringName] = []
	s.state_changed.connect(func(_f: StringName, to: StringName) -> void: states.append(to))
	s.wake()
	for i in 4:
		NoiseModel.emit(_p.global_position, 20.0, Tuning.NOISE_KIND_TEAR)
		await await_physics_frames(10)
	assert_eq(hits[0], 0)
	assert_false(states.has(Tuning.ERROR_STATE_CHASE))
	assert_false(states.has(Tuning.ERROR_STATE_SATIATED))


func _flare(pos: Vector3) -> Node3D:
	var f := Node3D.new()
	_world.add_child(f)
	f.global_position = pos
	f.add_to_group(Tuning.STATIC_FLARE_GROUP)
	return f


func test_flare_pushes_it_back() -> void:
	var s := _static_at(Vector3(20, 0, 0))
	s.wake()
	await await_physics_frames(2)
	var start := s.global_position
	_flare(start + Vector3(3, 0, 0))
	await await_physics_frames(int(Engine.physics_ticks_per_second))
	var moved := s.global_position - start
	assert_approx(moved.x, -Tuning.STATIC_FLARE_PUSH_SPEED, 0.1, "pushed away at 1.2 m/s")


func test_does_not_cross_into_a_flare() -> void:
	Engine.time_scale = 4.0
	var s := _static_at(Vector3(20, 0, 0))
	var start := s.global_position
	var f := _flare(start + Vector3(0, 0, 10))
	s.clear_hint()
	s.hint(start + Vector3(0, 0, 20))  # straight through the flare
	s.wake()
	var closest := INF
	for i in 300:
		await get_tree().physics_frame
		closest = minf(closest, ErrorFixture.flat(s.global_position, f.global_position))
	assert_gt(closest, Tuning.STATIC_FLARE_RANGE - 0.05, "never inside the flare's 6 m")


func test_grid_cell_path_passes_doors_not_walls() -> void:
	var g := LevelGrid.new(Vector2i(4, 3))
	for x in 4:
		for y in 3:
			g.set_kind(Vector2i(x, y), LevelGrid.FLOOR)
			if x < 3:
				g.set_wall(Vector2i(x, y), LevelGrid.E, LevelGrid.NONE)
			if y < 2:
				g.set_wall(Vector2i(x, y), LevelGrid.S, LevelGrid.NONE)
	g.finalize_walls()
	# A wall between column 1 and 2 with a door in the middle row.
	for y in 3:
		g.set_wall(Vector2i(1, y), LevelGrid.E, LevelGrid.WALL)
	g.set_wall(Vector2i(1, 1), LevelGrid.E, LevelGrid.DOOR)
	var path := ErrorStatic.cell_path(g, Vector2i(0, 0), Vector2i(3, 0))
	assert_contains(path, Vector2i(2, 1), "through the door")
	assert_eq(path.back() if not path.is_empty() else null, Vector2i(3, 0))
	g.set_wall(Vector2i(1, 1), LevelGrid.E, LevelGrid.WALL)
	assert_eq(ErrorStatic.cell_path(g, Vector2i(0, 0), Vector2i(3, 0)).size(), 0, "walls stop it")


func test_dormant_until_navigation_ready() -> void:
	var s := ErrorBase.create(&"static") as ErrorStatic
	s.setup(_p, null, 5)
	_world.add_child(s)
	s.global_position = _p.eye_position() - Vector3.UP * Tuning.STATIC_CENTRE_HEIGHT
	s.wake()
	await await_physics_frames(20)
	assert_eq(s.state, Tuning.ERROR_STATE_DORMANT)
	assert_approx(_p.coherence, Tuning.COHERENCE_MAX, 0.0001, "a dormant field drains nothing")
	s.set_navigation_ready(true)
	assert_eq(s.state, Tuning.ERROR_STATE_WANDER)
