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
	assert_eq(counts["notice"], 1, "back within 5 s: the same engagement (2026-10-08)")
	_p.global_position = Vector3(15, 0.05, 0)
	await await_physics_frames(3)
	assert_eq(counts["lost"], 1, "released after 2 s: an evasion")
	_p.global_position = Vector3(0, 0.05, 0)
	await await_physics_frames(3)
	assert_eq(counts["notice"], 2, "an evasion re-arms the notice")


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


## A grid of `size` cells over the fixture floor (2 m cells from the origin), walkable
## where `open` says so, with every edge between two walkable cells open.
func _grid(size: Vector2i, open: Callable) -> LevelGrid:
	var g := LevelGrid.new(size)
	for x in size.x:
		for y in size.y:
			if bool(open.call(Vector2i(x, y))):
				g.set_kind(Vector2i(x, y), LevelGrid.FLOOR)
	for x in size.x:
		for y in size.y:
			var c := Vector2i(x, y)
			if not g.is_walkable(c):
				continue
			if x + 1 < size.x and g.is_walkable(c + Vector2i(1, 0)):
				g.set_wall(c, LevelGrid.E, LevelGrid.NONE)
			if y + 1 < size.y and g.is_walkable(c + Vector2i(0, 1)):
				g.set_wall(c, LevelGrid.S, LevelGrid.NONE)
	g.finalize_walls()
	return g


## Review item 4: a nudge forces Wander, plans to the destination at 1.2 m/s and keeps
## the nudge (no dwell, no Search on noise) until it arrives; it works from Search.
func test_nudge_from_search_keeps_until_arrival() -> void:
	var g := _grid(Vector2i(12, 12), func(_c: Vector2i) -> bool: return true)
	var s := ErrorFixture.spawn(_world, &"static", g.world_of(Vector2i(2, 2)), _p) as ErrorStatic
	s.grid = g
	s.wake()
	NoiseModel.emit(s.global_position + Vector3(0, 0, 3), 20.0, Tuning.NOISE_KIND_TEAR)
	await await_physics_frames(2)
	assert_eq(s.state, Tuning.ERROR_STATE_SEARCH)
	var dest := g.world_of(Vector2i(2, 10))
	s.nudge(dest)
	assert_eq(s.state, Tuning.ERROR_STATE_WANDER, "the nudge ends the Search")
	assert_true(s.is_nudged())
	var a := s.global_position
	await await_physics_frames(int(Engine.physics_ticks_per_second))
	assert_approx(ErrorFixture.flat(a, s.global_position), Tuning.STATIC_FAIR_NUDGE_SPEED, 0.1, "1.2 m/s")
	NoiseModel.emit(s.global_position, 20.0, Tuning.NOISE_KIND_TEAR)
	await await_physics_frames(1)
	assert_eq(s.state, Tuning.ERROR_STATE_WANDER, "noise waits until it has arrived")
	assert_true(s.is_nudged(), "kept until arrival")
	Engine.time_scale = 4.0
	for i in 900:
		await get_tree().physics_frame
		if not s.is_nudged():
			break
	assert_false(s.is_nudged(), "released on arrival")
	assert_lt(ErrorFixture.flat(s.global_position, dest), 0.05, "it arrived")


## Review item 9: the wander filter bounds the drift (05 §10 first Descent side loop).
func test_wander_filter_bounds_the_drift() -> void:
	var g := _grid(Vector2i(14, 14), func(_c: Vector2i) -> bool: return true)
	var s := ErrorFixture.spawn(_world, &"static", g.world_of(Vector2i(10, 6)), _p) as ErrorStatic
	s.grid = g
	s.set_wander_filter(func(c: Vector2i) -> bool: return c.x >= 8)
	for i in 50:
		var c := g.cell_of(s._wander_target())
		assert_true(c.x >= 8, "cell %s passes the filter" % c)
		if c.x < 8:
			break
	# Out of reach (10 cells) of every passing cell: the nearest passing cell.
	s.global_position = g.world_of(Vector2i(0, 0))
	s.set_wander_filter(func(c: Vector2i) -> bool: return c == Vector2i(13, 13))
	assert_eq(g.cell_of(s._wander_target()), Vector2i(13, 13))
	s.set_wander_filter(Callable())
	assert_ne(g.cell_of(s._wander_target()), Vector2i(-1, -1))


## Review item 10: the flare push never leaves the walkable cells and never freezes.
func test_flare_push_stays_walkable_and_escapes() -> void:
	# One corridor row (y = 1) of 14 cells; the flare sits beside it, so straight away is
	# into the void.
	var g := _grid(Vector2i(14, 3), func(c: Vector2i) -> bool: return c.y == 1)
	var s := ErrorFixture.spawn(_world, &"static", g.world_of(Vector2i(6, 1)), _p) as ErrorStatic
	s.grid = g
	s.hint(s.global_position)
	s.wake()
	await await_physics_frames(2)
	var f := _flare(s.global_position + Vector3(0, 0, -1.0))
	Engine.time_scale = 4.0
	var off_grid := 0
	var t := 0.0
	while t < 12.0 and ErrorFixture.flat(s.global_position, f.global_position) < Tuning.STATIC_FLARE_RANGE:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		off_grid += 0 if g.is_walkable(g.cell_of(s.global_position)) else 1
	assert_eq(off_grid, 0, "never off the walkable cells")
	assert_gt(ErrorFixture.flat(s.global_position, f.global_position), Tuning.STATIC_FLARE_RANGE - 0.01,
		"out of the flare's 6 m (%.1f s)" % t)
	assert_lt(t, 12.0, "it never froze")


## Review item 11: inside the field the post drain reads at least 0.6 (08 §3), as well as
## grain and CA (02 §8); outside it is released.
func test_drain_floor_inside() -> void:
	var s := _static_at(Vector3.ZERO)
	s.wake()
	await await_physics_frames(5)
	assert_approx(CoherenceRenderer.drain_floor, Tuning.STATIC_FORCED_DRAIN, 0.0001)
	var p := CoherencePost.compute(1.0, 0.0, 0.0, {}, {}, 0.0, false, false, 1.0, CoherenceRenderer.drain_floor)
	var full := CoherencePost.compute(0.4, 0.0, 0.0, {}, {}, 0.0, false, false)
	assert_approx(float(p[&"sat"]), float(full[&"sat"]), 0.0001, "graded as at drain 0.6")
	_p.global_position = Vector3(15, 0.05, 0)
	await await_physics_frames(3)
	assert_approx(CoherenceRenderer.drain_floor, 0.0, 0.0001, "released outside")


## Review item 18: with two Statics only the nearest pushes the renderer state.
func test_two_fields_share_one_renderer_state() -> void:
	var near := _static_at(Vector3.ZERO)
	var far := _static_at(Vector3(20, 0, 0))
	near.wake()
	far.wake()
	await await_physics_frames(5)
	assert_gt(CoherenceRenderer.static_amount, 0.99)
	far.queue_free()
	await await_physics_frames(3)
	assert_gt(CoherenceRenderer.static_amount, 0.99, "the far one leaving does not clear it")
	near.queue_free()
	await await_physics_frames(3)
	assert_approx(CoherenceRenderer.static_amount, 0.0, 0.0001, "the last one leaving clears it")
	assert_approx(CoherenceRenderer.drain_floor, 0.0, 0.0001)


## Review item 18: the headless script cost of one Static (inside its field, drifting),
## printed for the report; the 14 budget is 0.3 ms for every error together.
func test_script_cost() -> void:
	var s := _static_at(Vector3(1.0, 0, 0))
	s.clear_hint()
	s.wake()
	var usec := 0
	for i in 120:
		await get_tree().physics_frame
		usec += int(ErrorTiming.frame_usec_by_id.get(&"static", 0))
	var ms := usec / 1000.0 / 120.0
	print("  # static: script %.3f ms/frame headless" % ms)
	assert_gt(ms, 0.0)
	assert_lt(ms, Tuning.BUDGET_ERRORS_SCRIPT_MS, "within the errors' budget")
