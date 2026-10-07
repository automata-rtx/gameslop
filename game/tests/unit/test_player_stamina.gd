extends TestCase
## 06 §4 stamina timings: 20/s drain (5 s), 1 s regen delay, 25/s regen, 2 s lockout at 0
## with regen continuing, x1.5 drain wading. Stepped at 60 Hz with pure ticks.

const DT := 1.0 / 60.0


func _run(s: Stamina, seconds: float, sprinting: bool, wading: bool = false) -> void:
	for i in int(round(seconds / DT)):
		s.tick(DT, sprinting, wading)


func test_full_sprint_lasts_five_seconds() -> void:
	var s := Stamina.new()
	_run(s, 4.9, true)
	assert_gt(s.value, 0.0, "not empty before 5 s")
	assert_true(s.can_sprint())
	_run(s, 0.1, true)
	assert_approx(s.value, 0.0, 0.001, "empty at 5 s")


func test_drain_rate() -> void:
	var s := Stamina.new()
	_run(s, 1.0, true)
	assert_approx(s.value, 80.0, 0.01)


func test_wading_drains_one_and_a_half_times() -> void:
	var s := Stamina.new()
	_run(s, 1.0, true, true)
	assert_approx(s.value, 70.0, 0.01)


func test_regen_waits_one_second_then_25_per_second() -> void:
	var s := Stamina.new()
	_run(s, 2.0, true)
	assert_approx(s.value, 60.0, 0.01)
	_run(s, 1.0, false)
	assert_approx(s.value, 60.0, 0.01, "no regen during the 1 s delay")
	_run(s, 1.0, false)
	assert_approx(s.value, 85.0, 0.01, "25 per second after the delay")
	_run(s, 2.0, false)
	assert_approx(s.value, 100.0, 0.001, "clamped at max")


func test_exhaustion_lockout_two_seconds_with_regen() -> void:
	var s := Stamina.new()
	var exhausted := [0]
	s.exhausted.connect(func() -> void: exhausted[0] += 1)
	_run(s, 5.0, true)
	assert_eq(exhausted[0], 1, "exhausted fires once")
	assert_true(s.is_locked_out())
	assert_false(s.can_sprint())
	_run(s, 1.9, true)  # still holding sprint: no drain while locked
	assert_false(s.can_sprint(), "locked for 2 s")
	assert_gt(s.value, 0.0, "regen continues during the lockout")
	_run(s, 0.15, true)
	assert_true(s.can_sprint(), "lockout over after 2 s")
	assert_eq(exhausted[0], 1)


func test_player_sprint_is_refused_when_exhausted() -> void:
	var world := PlayerFixture.make_world(self)
	var p := PlayerFixture.spawn_player(world, Vector3(0, 0.05, 0))
	await await_physics_frames(2)
	p.locomotion.stamina.value = 0.5
	var events := [0]
	p.stamina_exhausted.connect(func() -> void: events[0] += 1)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await await_physics_frames(40)
	assert_eq(events[0], 1, "stamina_exhausted relayed")
	assert_ne(p.state_machine.state, PlayerStateMachine.SPRINT, "walks while locked out")
	assert_lt(PlayerFixture.flat_speed(p), Tuning.PLAYER_WALK_SPEED + 0.05)
	PlayerFixture.release_all()
	world.free()
