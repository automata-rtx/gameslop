extends TestCase
## 06 §3 movement: speeds per gait, caps, acceleration, feel rules, crouch, walls.

var _world: Node3D
var _p: Player


func before_each() -> void:
	PlayerFixture.release_all()
	_world = PlayerFixture.make_world(self)
	_p = PlayerFixture.spawn_player(_world, Vector3(0, 0.05, 0))
	await await_physics_frames(3)


func after_each() -> void:
	PlayerFixture.release_all()
	_world.free()


func _hold(actions: Array[StringName], frames: int) -> void:
	for a in actions:
		Input.action_press(a)
	await await_physics_frames(frames)


func test_max_speed_table() -> void:
	assert_approx(PlayerMovement.max_speed(&"walk", false, false), 3.2)
	assert_approx(PlayerMovement.max_speed(&"sprint", false, false), 5.6)
	assert_approx(PlayerMovement.max_speed(&"crouch", false, false), 1.6)
	assert_approx(PlayerMovement.max_speed(&"sprint", true, false), 1.6, 0.0001, "crank/noclip/stun cap")
	assert_approx(PlayerMovement.max_speed(&"walk", false, true), 3.2 * 0.6, 0.0001, "wading")


func test_acceleration_and_deceleration_rates() -> void:
	var v := PlayerMovement.approach(Vector3.ZERO, Vector3.FORWARD, 3.2, 0.1)
	assert_approx(v.length(), 1.2, 0.0001, "12 m/s^2")
	var w := PlayerMovement.approach(Vector3(0, 0, -3.2), Vector3.ZERO, 3.2, 0.1)
	assert_approx(w.length(), 1.6, 0.0001, "16 m/s^2 to rest")


func test_diagonal_is_normalised_and_strafe_equals_forward() -> void:
	var b := Basis.IDENTITY
	assert_approx(PlayerMovement.wish_dir(Vector2(1, 1).normalized(), b).length(), 1.0, 0.0001)
	assert_approx(PlayerMovement.wish_dir(Vector2(1, 0), b).length(), 1.0, 0.0001)


func test_walk_speed() -> void:
	await _hold([&"move_forward"], 40)
	assert_approx(PlayerFixture.flat_speed(_p), Tuning.PLAYER_WALK_SPEED, 0.05)
	assert_eq(_p.state_machine.state, PlayerStateMachine.WALK)


func test_diagonal_walk_speed_equals_forward() -> void:
	await _hold([&"move_forward", &"move_right"], 40)
	assert_approx(PlayerFixture.flat_speed(_p), Tuning.PLAYER_WALK_SPEED, 0.05)


func test_sprint_speed_and_state() -> void:
	await _hold([&"move_forward", &"sprint"], 50)
	assert_approx(PlayerFixture.flat_speed(_p), Tuning.PLAYER_SPRINT_SPEED, 0.05)
	assert_eq(_p.state_machine.state, PlayerStateMachine.SPRINT)
	assert_lt(_p.locomotion.stamina.value, Tuning.STAMINA_MAX, "sprint drains")


func test_crouch_speed_and_capsule() -> void:
	await _hold([&"move_forward", &"crouch"], 40)
	assert_approx(PlayerFixture.flat_speed(_p), Tuning.PLAYER_CROUCH_SPEED, 0.05)
	assert_eq(_p.state_machine.state, PlayerStateMachine.CROUCH)
	assert_approx((_p.collision.shape as CapsuleShape3D).height, Tuning.PLAYER_CAPSULE_HEIGHT_CROUCH)


func test_crank_caps_speed_and_blocks_sprint() -> void:
	await _hold([&"move_forward", &"sprint", &"crank"], 40)
	assert_approx(PlayerFixture.flat_speed(_p), Tuning.PLAYER_CROUCH_SPEED, 0.05)
	assert_false(_p.can_noclip(), "no noclip while cranking")
	assert_false(_p.can_use_item(), "no items while cranking")


func test_release_stops_quickly() -> void:
	await _hold([&"move_forward"], 30)
	Input.action_release(&"move_forward")
	await await_physics_frames(20)
	assert_lt(PlayerFixture.flat_speed(_p), 0.01, "decelerates to rest (16 m/s^2)")
	assert_eq(_p.state_machine.state, PlayerStateMachine.IDLE)


func test_walking_into_a_wall_stops_dead() -> void:
	PlayerFixture.box(_world, Vector3(4, 3, 0.2), Vector3(0, 1.5, -1.0))
	await _hold([&"move_forward"], 60)
	var z := _p.global_position.z
	await await_physics_frames(10)
	assert_approx(_p.global_position.z, z, 0.002, "no jitter against the wall")
	assert_gt(_p.global_position.z, -1.0 + 0.1 + Tuning.PLAYER_CAPSULE_RADIUS - 0.05, "did not pass the wall")


func test_stand_blocked_under_low_ceiling() -> void:
	await _hold([&"crouch"], 5)
	PlayerFixture.box(_world, Vector3(3, 0.2, 3), Vector3(0, 1.35, 0))
	Input.action_release(&"crouch")
	await await_physics_frames(5)
	assert_true(_p.locomotion.crouched, "cannot stand under a 1.25 m ceiling")
	assert_false(_p.locomotion.can_stand())


func test_step_up_onto_a_low_step() -> void:
	PlayerFixture.box(_world, Vector3(4, 0.2, 4), Vector3(0, 0.1, -3.0))
	await _hold([&"move_forward"], 90)
	assert_gt(_p.global_position.y, 0.15, "climbed the 0.2 m step")
	assert_lt(_p.global_position.z, -1.2, "kept walking onto it")


func test_look_clamps_pitch_and_turns_body() -> void:
	SettingsManager.set_value(&"mouse_sensitivity", 1.0)
	_p.look(Vector2(100, 0))
	assert_approx(_p.rotation.y, -0.22, 0.0001, "0.0022 rad per pixel")
	_p.look(Vector2(0, -100000))
	assert_approx(rad_to_deg(_p.rig.pitch), 89.0, 0.001, "pitch clamped at +89")
