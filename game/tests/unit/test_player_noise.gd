extends TestCase
## 06 §6 noise model: the radius table, cadence, wall attenuation, and that each player
## action emits its EventBus.noise_emitted event with the right radius and kind.

var _noises: Array = []


func before_each() -> void:
	_noises.clear()
	EventBus.noise_emitted.connect(_on_noise)
	PlayerFixture.release_all()


func after_each() -> void:
	EventBus.noise_emitted.disconnect(_on_noise)
	PlayerFixture.release_all()


func _on_noise(pos: Vector3, radius: float, kind: StringName) -> void:
	_noises.append([pos, radius, kind])


func _of_kind(kind: StringName) -> Array:
	return _noises.filter(func(n: Array) -> bool: return n[2] == kind)


func test_walk_step_radius_per_surface() -> void:
	var table := {&"carpet": 5.0, &"tile": 7.0, &"concrete": 7.0, &"raised_floor": 8.0, &"substrate": 6.0}
	for surface: StringName in table:
		assert_approx(NoiseModel.step_radius(surface, &"walk"), table[surface], 0.0001, String(surface))


func test_gait_multipliers_and_water() -> void:
	assert_approx(NoiseModel.step_radius(&"tile", &"sprint"), 7.0 * 1.8, 0.0001)
	assert_approx(NoiseModel.step_radius(&"tile", &"crouch"), 7.0 * 0.4, 0.0001)
	assert_approx(NoiseModel.step_radius(&"tile", &"walk", true), 10.0, 0.0001, "step in water")
	assert_approx(NoiseModel.step_radius(&"tile", &"walk", true, true), 16.0, 0.0001, "wading x1.6")
	assert_approx(NoiseModel.step_radius(&"unknown", &"walk"), 5.0, 0.0001, "unknown surface falls back")


func test_step_cadence() -> void:
	assert_approx(NoiseModel.step_distance(&"walk"), 0.55)
	assert_approx(NoiseModel.step_distance(&"sprint"), 0.45)
	assert_approx(NoiseModel.step_distance(&"crouch"), 0.7)
	var n := NoiseModel.new()
	var steps := 0
	for i in 111:
		if n.advance(0.1, &"walk"):
			steps += 1
	assert_eq(steps, 20, "11.1 m walked at 0.55 m per step")


func test_fixed_action_radii() -> void:
	assert_approx(Tuning.NOISE_CRANK_RADIUS, 12.0)
	assert_approx(Tuning.NOISE_NOCLIP_COMMIT_RADIUS, 20.0)
	assert_approx(Tuning.NOISE_FLASHLIGHT_TOGGLE_RADIUS, 2.0)
	assert_approx(Tuning.NOISE_CONTACT_RADIUS, 15.0)


func test_walls_attenuate_35_percent_each() -> void:
	var world := PlayerFixture.make_world(self)
	PlayerFixture.box(world, Vector3(0.2, 3, 6), Vector3(2, 1.5, 0))
	PlayerFixture.box(world, Vector3(0.2, 3, 6), Vector3(4, 1.5, 0))
	await await_physics_frames(2)
	var space := world.get_world_3d().direct_space_state
	var from := Vector3(0, 1, 0)
	var to := Vector3(6, 1, 0)
	assert_eq(NoiseModel.count_walls(space, from, to), 2)
	assert_approx(NoiseModel.effective_radius(space, from, to, 20.0), 20.0 * 0.65 * 0.65, 0.001)
	assert_false(NoiseModel.can_hear(space, from, to, 10.0), "6 m away through 2 walls: 4.2 m effective")
	assert_true(NoiseModel.can_hear(space, from, Vector3(1.5, 1, 0), 10.0), "no wall in between")
	world.free()


func test_player_walk_steps_emit_step_noise() -> void:
	var world := PlayerFixture.make_world(self)
	var p := PlayerFixture.spawn_player(world, Vector3(0, 0.05, 0))
	await await_physics_frames(2)
	Input.action_press(&"move_forward")
	await await_physics_frames(60)
	var steps := _of_kind(Tuning.NOISE_KIND_STEP)
	assert_gt(steps.size(), 2, "steps while walking")
	for s: Array in steps:
		assert_approx(s[1], 5.0, 0.0001, "carpet walk step")
	PlayerFixture.release_all()
	_noises.clear()
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await await_physics_frames(60)
	var sprint := _of_kind(Tuning.NOISE_KIND_STEP)
	assert_gt(sprint.size(), 2)
	assert_approx(sprint[sprint.size() - 1][1], 9.0, 0.0001, "sprint step x1.8")
	world.free()


func test_player_flashlight_and_crank_noise() -> void:
	var world := PlayerFixture.make_world(self)
	var p := PlayerFixture.spawn_player(world, Vector3(0, 0.05, 0))
	await await_physics_frames(2)
	p.flashlight.set_on(true)
	var mech := _of_kind(Tuning.NOISE_KIND_MECH)
	assert_eq(mech.size(), 1)
	assert_approx(mech[0][1], 2.0, 0.0001, "toggle 2 m")
	_noises.clear()
	p.flashlight.set_charge(10.0)
	Input.action_press(&"crank")
	await await_physics_frames(61)
	Input.action_release(&"crank")
	var crank := _of_kind(Tuning.NOISE_KIND_MECH)
	assert_true(crank.size() == 2 or crank.size() == 3, "12 m every 0.5 s (got %d in ~1 s)" % crank.size())
	for c: Array in crank:
		assert_approx(c[1], 12.0, 0.0001)
	world.free()
