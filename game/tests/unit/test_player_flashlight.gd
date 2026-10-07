extends TestCase
## 06 §5 flashlight and crank math: drain 1.6/s (about 62 s), crank +25/s (x1.5
## Lightbearer), energy lerp 0.5..1.6, cone 38 -> 30 below 30 charge, never dark.

const DT := 1.0 / 60.0


func _run(c: float, seconds: float, on: bool, cranking: bool, lb: bool = false) -> float:
	for i in int(round(seconds / DT)):
		c = Flashlight.step_charge(c, DT, on, cranking, lb)
	return c


func test_drain_lasts_about_62_seconds() -> void:
	assert_approx(_run(100.0, 10.0, true, false), 84.0, 0.01)
	assert_gt(_run(100.0, 62.0, true, false), 0.0)
	assert_approx(_run(100.0, 63.0, true, false), 0.0, 0.0001, "empty after 62.5 s, clamped")


func test_off_does_not_drain() -> void:
	assert_approx(_run(50.0, 10.0, false, false), 50.0)


func test_crank_rate_and_lightbearer() -> void:
	assert_approx(_run(0.0, 1.0, false, true), 25.0, 0.01)
	assert_approx(_run(0.0, 1.0, false, true, true), 37.5, 0.01, "Lightbearer x1.5")
	assert_approx(_run(0.0, 1.0, true, true), 25.0 - 1.6, 0.01, "crank with the light on")
	assert_approx(Flashlight.crank_rate(false), 25.0)


func test_crank_at_full_holds_full() -> void:
	assert_approx(_run(99.0, 2.0, true, true), 100.0, 0.0001)


func test_energy_and_cone() -> void:
	assert_approx(Flashlight.energy_for(100.0), 1.6)
	assert_approx(Flashlight.energy_for(0.0), 0.5, 0.0001, "never dark (T1)")
	assert_approx(Flashlight.energy_for(50.0), 1.05)
	assert_approx(Flashlight.spot_angle_for(100.0), 19.0)
	assert_approx(Flashlight.spot_angle_for(30.0), 19.0)
	assert_approx(Flashlight.spot_angle_for(15.0), 17.0, 0.0001, "half-way tired: 34 deg cone")
	assert_approx(Flashlight.spot_angle_for(0.0), 15.0, 0.0001, "30 deg cone")


func test_held_flashlight_signals_and_wheel() -> void:
	var world := PlayerFixture.make_world(self)
	var p := PlayerFixture.spawn_player(world, Vector3(0, 0.05, 0))
	await await_physics_frames(2)
	var f := p.flashlight
	var full := [0]
	var turning := []
	f.crank_full.connect(func() -> void: full[0] += 1)
	f.crank_changed.connect(func(t: bool) -> void: turning.append(t))
	f.set_charge(98.0)
	var wheel_before := f.wheel.transform.basis
	Input.action_press(&"crank")
	await await_physics_frames(30)
	assert_approx(f.charge, 100.0, 0.0001)
	assert_eq(full[0], 1, "crank full fires once")
	assert_eq(turning, [true, false], "wheel starts then stops at full")
	assert_false(f.wheel.transform.basis.is_equal_approx(wheel_before), "the wheel turned")
	Input.action_release(&"crank")
	await await_physics_frames(2)
	f.toggle()
	assert_true(f.on)
	assert_true(f.beam.visible)
	assert_approx(f.beam.light_energy, 1.6, 0.01)
	world.free()
