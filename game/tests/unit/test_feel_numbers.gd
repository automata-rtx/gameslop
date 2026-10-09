extends TestCase
## M3.1: the numbers 11 gives for how the player feels (camera, footsteps, noclip), checked
## on the real Player and CameraRig rather than on the constants alone. The bench
## (sim/test_feedback_bench.gd) proves that each row reacts in time; this proves the reaction
## has the size and the duration the contract writes down.

var _world: Node3D
var _p: Player
var _saved: Dictionary = {}


func before_each() -> void:
	for k: StringName in [&"screen_shake", &"head_bob", &"fov"]:
		_saved[k] = SettingsManager.get_value(k)
	SettingsManager.set_value(&"screen_shake", 1.0)
	SettingsManager.set_value(&"head_bob", 1.0)
	_world = PlayerFixture.make_world(self)
	_p = PlayerFixture.spawn_player(_world, Vector3(0, 0.05, 0))
	await await_physics_frames(2)


func after_each() -> void:
	PlayerFixture.release_all()
	_world.free()
	for k: StringName in _saved:
		SettingsManager.set_value(k, _saved[k])


func _motion() -> Node3D:
	return _p.rig.get(&"_motion")


## Peak per-axis offset (m) and rotation (rad) of the camera's motion node over 400 noise
## samples at a fixed trauma.
func _shake_peaks(trauma: float) -> Vector2:
	var rig := _p.rig
	var peak_p := 0.0
	var peak_r := 0.0
	for i in 400:
		rig.trauma = trauma
		rig.set(&"_shake_time", float(i) * 0.05)
		rig.call(&"_apply_motion")
		var m := _motion()
		for a in 3:
			peak_p = maxf(peak_p, absf(m.position[a]))
			peak_r = maxf(peak_r, absf(m.rotation[a]))
	return Vector2(peak_p, peak_r)


# --- 11 §1 camera shake ---------------------------------------------------------------------

func test_shake_is_trauma_squared_capped_and_scaled_by_the_setting() -> void:
	var full := _shake_peaks(1.0)
	assert_true(full.x <= Tuning.CAMERA_SHAKE_MAX_TRANSLATION + 0.000001, "at most 0.04 m")
	assert_true(full.y <= deg_to_rad(Tuning.CAMERA_SHAKE_MAX_ROTATION) + 0.000001, "at most 1.2 degrees")
	assert_gt(full.x, Tuning.CAMERA_SHAKE_MAX_TRANSLATION * 0.3, "trauma 1 really shakes")
	assert_gt(full.y, deg_to_rad(Tuning.CAMERA_SHAKE_MAX_ROTATION) * 0.3)
	var half := _shake_peaks(0.5)
	assert_approx(half.x, full.x * 0.25, 0.00001, "shake = trauma squared (0.5 gives a quarter)")
	assert_approx(half.y, full.y * 0.25, 0.00001)
	SettingsManager.set_value(&"screen_shake", 0.5)
	assert_approx(_shake_peaks(1.0).x, full.x * 0.5, 0.00001, "scaled by the setting")
	SettingsManager.set_value(&"screen_shake", 0.0)
	var none := _shake_peaks(1.0)
	assert_approx(none.x, 0.0, 0.000001, "the setting at 0 removes it")
	assert_approx(none.y, 0.0, 0.000001)


func test_trauma_decays_one_and_a_half_per_second() -> void:
	_p.rig.trauma = 1.0
	_p.rig._process(0.4)
	assert_approx(_p.rig.trauma, 0.4, 0.0001, "1.0 - 1.5 x 0.4")
	assert_eq(Tuning.CAMERA_TRAUMA_DECAY, 1.5)


## 11 §6: no shake on walking, doors or notes. Trauma comes from a short list of events;
## a new caller is a design change and has to be added here on purpose.
func test_trauma_has_only_the_contract_s_sources() -> void:
	var allowed := ["res://src/player/noclip_targeting.gd", "res://src/player/noclip_motion.gd",
			"res://src/player/player_contact.gd", "res://src/core/run.gd", "res://src/player/camera_rig.gd"]
	var found: Array[String] = []
	_scan("res://src", found)
	found.sort()
	for f in found:
		assert_contains(allowed, f, "%s adds camera trauma: 11 §6 lists only noclip, contact, drop, landing, breaker" % f)


func _scan(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd") and FileAccess.get_file_as_string(dir.path_join(f)).contains(".add_trauma("):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(d), out)


func test_walking_never_shakes() -> void:
	Input.action_press(&"move_forward")
	await await_physics_frames(60)
	assert_eq(_p.rig.trauma, 0.0, "11 §6: no shake on walking")
	var m := _motion()
	assert_true(absf(m.position.x) <= Tuning.CAMERA_BOB_LATERAL + 0.0001 and absf(m.position.y) <= Tuning.CAMERA_BOB_VERTICAL + 0.05 + 0.0001,
			"a walking camera is the bob and nothing else")


# --- 11 §2 moving ---------------------------------------------------------------------------

func test_walk_bob_and_strafe_roll() -> void:
	Input.action_press(&"move_right")
	await await_physics_frames(60)
	_p.rig.call(&"_process", 1.0)  # let the lean settle
	assert_approx(absf(rad_to_deg(float(_p.rig.get(&"_lean")))), Tuning.CAMERA_LEAN_DEG, 0.05, "1.5 degree strafe roll")
	Input.action_release(&"move_right")
	Input.action_press(&"move_forward")
	await await_physics_frames(60)
	assert_approx(float(_p.rig.get(&"_bob_amp_target")), 1.0, 0.0001, "bob amplitude 1 at a walk")
	assert_approx(absf(float(_p.rig.get(&"_lean"))), 0.0, 0.05, "no roll walking straight")


func test_sprint_bob_is_one_point_six_and_fov_plus_four() -> void:
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await await_physics_frames(30)
	assert_true(_p.locomotion.sprinting)
	assert_approx(float(_p.rig.get(&"_bob_amp_target")), 1.6, 0.0001, "bob amplitude x1.6")
	assert_approx(_p.rig.fov_hold_of(CameraRig.HOLD_SPRINT), 4.0, 0.05, "FOV +4 degrees after 200 ms")
	assert_approx(_p.rig.current_hfov(), 94.0, 0.05)
	Input.action_release(&"sprint")
	await await_physics_frames(30)
	assert_approx(_p.rig.fov_hold_of(CameraRig.HOLD_SPRINT), 0.0, 0.01, "back after 300 ms")
	assert_approx(float(_p.rig.get(&"_bob_amp_target")), 1.0, 0.0001, "and the bob with it")


func test_stamina_empty_cuts_the_bob_by_a_fifth_for_two_seconds() -> void:
	_p.locomotion.call(&"_on_stamina_exhausted")
	_p.locomotion.tick_timers(0.0)
	assert_approx(_p.rig.bob_scale, 1.0 - Tuning.FEEDBACK_STAMINA_EMPTY_BOB_CUT, 0.0001, "bob reduced 20%")
	_p.locomotion.tick_timers(1.9)
	assert_approx(_p.rig.bob_scale, 0.8, 0.0001, "still reduced at 1.9 s")
	_p.locomotion.tick_timers(0.2)
	assert_approx(_p.rig.bob_scale, 1.0, 0.0001, "back to full after 2 s")


func test_crouch_moves_the_eye_in_120_ms_with_a_5_cm_dip() -> void:
	var rig := _p.rig
	assert_approx(rig.position.y, Tuning.PLAYER_CAMERA_HEIGHT, 0.001)
	Input.action_press(&"crouch")
	var low := 0.0
	var t0 := Time.get_ticks_msec()
	var at_120 := INF
	while Time.get_ticks_msec() - t0 < 400:
		await get_tree().process_frame
		low = minf(low, _motion().position.y)
		if at_120 == INF and Time.get_ticks_msec() - t0 >= 130:
			at_120 = rig.position.y
	assert_approx(rig.position.y, Tuning.PLAYER_CAMERA_HEIGHT_CROUCH, 0.002, "crouched eye height")
	assert_true(low <= -Tuning.CAMERA_DIP * 0.8, "the camera dips 0.05 m on the way (got %s)" % low)
	assert_true(low >= -Tuning.CAMERA_DIP - 0.005, "and not more than that")
	assert_approx(at_120, Tuning.PLAYER_CAMERA_HEIGHT_CROUCH, 0.05, "the height is there after 120 ms (expo ease out)")


func test_flashlight_kicks_the_camera_a_third_of_a_degree_toward_the_hand() -> void:
	_p.flashlight.set_on(false, true)
	_p.rig.set(&"_kick_roll", 0.0)
	Input.action_press(&"flashlight")
	await await_physics_frames(2)
	var kick := rad_to_deg(float(_p.rig.get(&"_kick_roll")))
	assert_true(absf(kick) > Tuning.FEEDBACK_FLASHLIGHT_ROLL_KICK_DEG * 0.5 and absf(kick) <= Tuning.FEEDBACK_FLASHLIGHT_ROLL_KICK_DEG + 0.001,
			"0.3 degree roll kick (got %s)" % kick)
	assert_lt(kick, 0.0, "toward the hand (the right)")


func test_crank_sways_the_camera_at_one_hertz_four_millimetres() -> void:
	_p.flashlight.set_charge(20.0)
	Input.action_press(&"crank")
	await await_physics_frames(10)
	assert_approx(float(_p.rig.get(&"_sway_amp")), 0.004, 0.000001, "0.004 m")
	var phase0 := float(_p.rig.get(&"_sway_phase"))
	_p.rig.call(&"_process", 0.25)
	var d := fposmod(float(_p.rig.get(&"_sway_phase")) - phase0, TAU)
	assert_approx(d, TAU * 0.25, 0.0001, "one cycle per second")
	Input.action_release(&"crank")
	await await_physics_frames(10)
	assert_approx(float(_p.rig.get(&"_sway_amp")), 0.0, 0.000001, "the sway stops with the crank")


func test_interacting_nods_the_view_two_tenths_of_a_degree() -> void:
	_p.rig.set(&"_kick_pitch", 0.0)
	_p.interactor.interacted.emit(null)
	assert_approx(rad_to_deg(float(_p.rig.get(&"_kick_pitch"))), -Tuning.FEEDBACK_INTERACT_NOD_DEG, 0.0001)


func test_gain_pulses_the_fov_two_degrees_and_back_in_400_ms() -> void:
	_p.coherence = 50.0
	_p.apply_coherence(25.0, &"polaroid")
	await get_tree().create_timer(0.25).timeout
	var peak := _p.rig.current_hfov() - 90.0
	assert_true(peak > 0.0 and peak <= Tuning.FEEDBACK_GAIN_FOV_DEG + 0.01, "FOV up to +2 degrees (got %s)" % peak)
	await get_tree().create_timer(0.6).timeout
	assert_approx(_p.rig.current_hfov(), 90.0, 0.02, "and back")


# --- footsteps ------------------------------------------------------------------------------

func test_a_step_every_0_55_m_walking_0_45_sprinting_0_7_crouching() -> void:
	var by_gait := {NoiseModel.GAIT_WALK: 0.55, NoiseModel.GAIT_SPRINT: 0.45, NoiseModel.GAIT_CROUCH: 0.7}
	for g: StringName in by_gait:
		assert_approx(NoiseModel.step_distance(g), float(by_gait[g]), 0.0001, String(g))
	var steps: Array[Vector3] = []
	var on_noise := func(pos: Vector3, _r: float, kind: StringName) -> void:
		if kind == Tuning.NOISE_KIND_STEP:
			steps.append(pos)
	EventBus.noise_emitted.connect(on_noise)
	Input.action_press(&"move_forward")
	await await_physics_frames(120)
	EventBus.noise_emitted.disconnect(on_noise)
	assert_gt(steps.size(), 6, "walked a few metres")
	for i in range(2, steps.size()):
		assert_approx(steps[i].distance_to(steps[i - 1]), 0.55, 0.12, "step %d is one stride on" % i)


# --- noclip ---------------------------------------------------------------------------------

func test_noclip_numbers_are_the_contract_s() -> void:
	assert_eq(Tuning.NOCLIP_COMMIT_HITSTOP_MS, 80)
	assert_eq(Tuning.CONTACT_HITSTOP_MS, 60)
	assert_eq(Tuning.NOCLIP_FOV_PULL_DEG, 6.0)
	assert_eq(Tuning.NOCLIP_FOV_PUNCH_DEG, 8.0)
	assert_eq(Tuning.FEEDBACK_NOCLIP_COMMIT_TRAUMA, 0.8)
	assert_eq(Tuning.FEEDBACK_NOCLIP_SWAY, 0.003)
	assert_eq(Tuning.FEEDBACK_NOCLIP_CANCEL_COLLAPSE_MS, 100)
	assert_eq(Tuning.FEEDBACK_NOCLIP_CANCEL_FOV_MS, 150)
	assert_eq(Tuning.FEEDBACK_NOCLIP_FALL_PITCH_DEG, 10.0)
	assert_eq(Tuning.FEEDBACK_NOCLIP_FLASHLIGHT_DIM, 0.3)
	assert_eq(Tuning.FEEDBACK_NOCLIP_SOUND_GAP_MS, 60)
	assert_eq(Tuning.CONTACT_TRAUMA, 0.6)
	assert_eq(Tuning.CONTACT_STUN_TIME, 1.2)
	assert_eq(Tuning.CONTACT_PUSH_DIST, 1.5)
	assert_eq(Tuning.FEEDBACK_LANDING_TRAUMA, 0.3)
	assert_eq(Tuning.FEEDBACK_ARRIVAL_DROP_TRAUMA, 0.3)
	assert_eq(Tuning.FEEDBACK_BREAKER_TRAUMA, 0.3)
	assert_eq(Tuning.FEEDBACK_STATIC_JITTER, 0.002)
	assert_eq(Tuning.FEEDBACK_NULL_RADIUS_JITTER, 0.004)
	assert_eq(Tuning.FEEDBACK_NULL_CORE_JITTER, 0.01)
	assert_eq(Tuning.FEEDBACK_DISSOLVE_DRIFT, 0.02)
	assert_eq(Tuning.FEEDBACK_ENTER_EXIT_FOV_DEG, -3.0)
	assert_eq(Tuning.FEEDBACK_MAX_LATENCY_MS, 50)


func test_contact_trauma_stun_and_push_on_the_real_player() -> void:
	_p.rig.trauma = 0.0
	var e := Node3D.new()
	_world.add_child(e)
	e.global_position = _p.global_position + Vector3(0, 0, -1)
	_p.coherence = 80.0
	assert_true(_p.contact(e, 35.0))
	assert_approx(_p.rig.trauma, Tuning.CONTACT_TRAUMA, 0.01, "trauma 0.6")
	assert_true(_p.is_stunned(), "stunned")
	assert_approx(_p._stun_left, Tuning.CONTACT_STUN_TIME, 0.0001, "for 1.2 s")
	assert_true(_p.locomotion.is_pushing(), "pushed away")
	assert_approx(_p.rig.bob_scale, 1.0, 0.0001)
	_p.locomotion.tick_timers(0.0)
	assert_eq(_p.rig.bob_scale, 0.0, "bob off while stunned")
