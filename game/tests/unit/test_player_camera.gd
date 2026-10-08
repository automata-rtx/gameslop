extends TestCase
## 12 §2 FOV conversion (hfov at 16:9 -> vfov, KEEP_HEIGHT), 06 §3 sensitivity, 11 §1
## trauma, and the rig's FOV holds and punches.

var _world: Node3D
var _p: Player


func before_each() -> void:
	_world = PlayerFixture.make_world(self)
	_p = PlayerFixture.spawn_player(_world, Vector3(0, 0.05, 0))
	await await_physics_frames(1)


func after_each() -> void:
	_world.free()
	SettingsManager.set_value(&"fov", Tuning.CAMERA_FOV_DEFAULT)


func _hfov_at_aspect(vfov: float, aspect: float) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(vfov) * 0.5) * aspect))


func test_hfov_to_vfov_formula() -> void:
	assert_approx(CameraRig.hfov_to_vfov(90.0), rad_to_deg(2.0 * atan(9.0 / 16.0)), 0.0001)
	assert_approx(CameraRig.hfov_to_vfov(90.0), 58.7155, 0.001)
	assert_approx(CameraRig.hfov_to_vfov(70.0), 43.0, 0.1)
	assert_approx(CameraRig.hfov_to_vfov(110.0), 77.55, 0.1)


func test_16_9_round_trips_and_21_9_gains_width() -> void:
	for h in [70.0, 90.0, 110.0]:
		var v := CameraRig.hfov_to_vfov(h)
		assert_approx(_hfov_at_aspect(v, 16.0 / 9.0), h, 0.001, "16:9 shows the set hfov")
		assert_gt(_hfov_at_aspect(v, 21.0 / 9.0), h, "21:9 gains width at the same height")


func test_camera_keeps_height_and_follows_the_setting() -> void:
	var cam := _p.rig.camera
	assert_eq(cam.keep_aspect, Camera3D.KEEP_HEIGHT)
	assert_approx(cam.fov, CameraRig.hfov_to_vfov(90.0), 0.01)
	SettingsManager.set_value(&"fov", 110)
	assert_approx(cam.fov, CameraRig.hfov_to_vfov(110.0), 0.01)
	SettingsManager.set_value(&"fov", 300)
	assert_approx(cam.fov, CameraRig.hfov_to_vfov(110.0), 0.01, "clamped to 70..110")
	assert_approx(cam.near, 0.05)
	assert_approx(cam.far, 120.0)


func test_mouse_sensitivity_math() -> void:
	assert_approx(CameraRig.mouse_to_radians(100.0, 1.0), 0.22, 0.00001)
	assert_approx(CameraRig.mouse_to_radians(100.0, 3.0), 0.66, 0.00001)
	assert_approx(CameraRig.mouse_to_radians(100.0, 10.0), 0.66, 0.00001, "clamped to 3.0")
	assert_approx(CameraRig.mouse_to_radians(100.0, 0.0), 0.022, 0.00001, "clamped to 0.1")


func test_invert_y() -> void:
	SettingsManager.set_value(&"invert_y", true)
	_p.look(Vector2(0, 10))
	assert_gt(_p.rig.pitch, 0.0, "inverted: mouse down looks up")
	SettingsManager.set_value(&"invert_y", false)
	_p.rig.reset_pitch()
	_p.look(Vector2(0, 10))
	assert_lt(_p.rig.pitch, 0.0, "mouse down looks down")


func test_look_is_free_in_the_landing_but_movement_is_not() -> void:
	_p.state_machine.transition_to(PlayerStateMachine.LANDING)
	assert_false(_p.has_agency())
	var yaw := _p.rotation.y
	_p.look(Vector2(20, 10))
	assert_ne(_p.rotation.y, yaw, "05 §4: the cabin camera is free")
	assert_ne(_p.rig.pitch, 0.0)
	_p.state_machine.reset()
	_p.state_machine.transition_to(PlayerStateMachine.DROPPING)
	yaw = _p.rotation.y
	_p.look(Vector2(20, 0))
	assert_approx(_p.rotation.y, yaw, 0.00001, "other agency-less states still refuse look")


func test_trauma_clamps_and_decays() -> void:
	var rig := _p.rig
	rig.trauma = 0.0
	rig.add_trauma(0.8)
	rig.add_trauma(0.8)
	assert_approx(rig.trauma, 1.0, 0.0001, "clamped at 1")
	rig._process(0.5)
	assert_approx(rig.trauma, 0.25, 0.0001, "decays 1.5 per second")


func test_fov_hold_and_punch() -> void:
	var rig := _p.rig
	rig.fov_hold(4.0, 0.0)
	assert_approx(rig.current_hfov(), 94.0, 0.0001)
	rig.fov_hold(0.0, 0.0)
	rig.fov_punch(8.0, 50.0, 100.0)
	await get_tree().create_timer(0.3).timeout
	assert_approx(rig.current_hfov(), 90.0, 0.01, "punch returns")


func test_fov_holds_are_keyed_and_sum() -> void:
	var rig := _p.rig
	rig.fov_hold(-6.0, 0.0, CameraRig.HOLD_NOCLIP)
	rig.fov_hold(4.0, 0.0, CameraRig.HOLD_SPRINT)
	assert_approx(rig.current_hfov(), 88.0, 0.0001, "90 - 6 + 4")
	rig.fov_hold(0.0, 0.0, CameraRig.HOLD_SPRINT)
	assert_approx(rig.fov_hold_of(CameraRig.HOLD_NOCLIP), -6.0, 0.0001, "sprint release keeps the noclip pull-in")
	assert_approx(rig.current_hfov(), 84.0, 0.0001)
	rig.fov_hold(-3.0, 50.0, CameraRig.HOLD_NOCLIP)
	rig.fov_hold(2.0, 0.0)
	await get_tree().create_timer(0.2).timeout
	assert_approx(rig.current_hfov(), 89.0, 0.01, "a tweened key replaces only itself; default key sums too")
	rig.fov_hold(0.0, 0.0, CameraRig.HOLD_NOCLIP)
	rig.fov_hold(0.0, 0.0)
	assert_approx(rig.fov_hold_total(), 0.0)
