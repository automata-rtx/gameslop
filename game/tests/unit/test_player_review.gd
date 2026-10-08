extends TestCase
## M1.3 player review fixes (R2): observation of tall targets and beam range, hide
## spot leave feedback and breath, the step trail, halting on loss of agency, stamina
## every frame, crank and breath loops, the Coherence loss tick, the hide prompt gate, the
## silent reset, the interactor's fresh-press rule, the crank glow, the beam at the
## lens, wall-only noise attenuation (test_player_noise) and the push displacement.

var _world: Node3D
var _p: Player
var _locker: HideSpot


func before_each() -> void:
	get_tree().root.size = Vector2i(1920, 1080)
	PlayerFixture.release_all()
	SettingsManager.set_value(&"hold_to_press", false)
	_world = PlayerFixture.make_world(self)
	_p = PlayerFixture.spawn_player(_world, Vector3(0, 0.05, 0))
	_locker = null
	await await_physics_frames(2)


func after_each() -> void:
	PlayerFixture.release_all()
	var guard := 0
	while get_tree().paused and guard < 200:
		guard += 1
		await get_tree().process_frame
	_world.free()
	CoherenceRenderer.set_coherence(Tuning.COHERENCE_MAX)


func _spawn_locker() -> HideSpot:
	_locker = (load(PlayerFixture.LOCKER_SCENE) as PackedScene).instantiate() as HideSpot
	_world.add_child(_locker)
	_locker.global_position = Vector3(0, 0, -1.6)
	return _locker


func _column(base: Vector3, height: float) -> Node3D:
	var c := _Column.new()
	c.height = height
	_world.add_child(c)
	c.global_position = base
	return c


# ------------------------------------------------------------- 1. observation

func test_crouched_player_observes_a_tall_column_at_2_5_m() -> void:
	Input.action_press(&"crouch")
	await await_physics_frames(20)
	assert_true(_p.locomotion.crouched)
	var still := _column(Vector3(0, 0, -2.5), 2.6)
	var top: Vector3 = still.observe_points()[1]
	assert_false(_p.rig.camera.is_position_in_frustum(top), "the top is above the view")
	assert_true(_p.rig.camera.is_position_in_frustum(still.observe_points()[0]))
	_p.flashlight.set_on(true)
	assert_true(_p.is_observing(still), "any point in the frustum is enough")


func test_every_observe_point_still_needs_a_clear_ray() -> void:
	Input.action_press(&"crouch")
	await await_physics_frames(20)
	var still := _column(Vector3(0, 0, -2.5), 2.6)
	_p.flashlight.set_on(true)
	# A beam that hides the top from the eye but not the centre.
	PlayerFixture.box(_world, Vector3(2, 0.3, 0.2), Vector3(0, 2.3, -2.2))
	await await_physics_frames(1)
	assert_false(_p.is_observing(still))


func test_no_observe_point_in_frustum_is_not_observed() -> void:
	_p.add_light_query(func(_pos: Vector3) -> bool: return true)
	assert_false(_p.is_observing(_column(Vector3(0, 0, 5), 2.6)))


func test_beam_lit_observation_needs_the_beam_range() -> void:
	_p.flashlight.set_on(true)
	var near := _p.eye_position() - _p.global_transform.basis.z * (Tuning.FLASH_RANGE - 2.0)
	var far := _p.eye_position() - _p.global_transform.basis.z * (Tuning.FLASH_RANGE + 3.0)
	assert_true(_p.is_observing(_node_at(near)), "inside 22 m")
	assert_false(_p.is_observing(_node_at(far)), "beyond the beam's 22 m, within 30 m")
	assert_true(PlayerObservation.in_beam(Vector3(0, 0, -10), Vector3.ZERO, Vector3.FORWARD))
	var off := Vector3(sin(deg_to_rad(Tuning.STILL_OBSERVE_BEAM_ANGLE + 1.0)), 0, -cos(deg_to_rad(Tuning.STILL_OBSERVE_BEAM_ANGLE + 1.0)))
	assert_false(PlayerObservation.in_beam(off * 5.0, Vector3.ZERO, Vector3.FORWARD), "26 deg off axis")


func _node_at(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	_world.add_child(n)
	n.global_position = pos
	return n


# ------------------------------------------------------------- 2. hide spot feedback

func test_hide_breath_and_leave_feedback() -> void:
	var locker := _spawn_locker()
	await await_physics_frames(2)
	_p.enter_hide(locker)
	assert_true(_p.is_hidden())
	assert_true(_p.sounds.is_looping(PlayerAudio.LOOP_HIDE_BREATH), "breathing while hidden")
	_p.sounds.played.clear()
	_p.leave_hide()
	assert_false(_p.sounds.is_looping(PlayerAudio.LOOP_HIDE_BREATH), "breath stops on leaving")
	assert_eq(_p.sounds.played, [locker.sound_id(), &"crouch"], "the spot's sound, then cloth")
	assert_true(_p.rig.is_anchored(), "the camera is still sliding out")
	await get_tree().create_timer(Tuning.HIDE_CAMERA_SLIDE_TIME + 0.1).timeout
	assert_false(_p.rig.is_anchored(), "slid out in 0.6 s")


func test_locker_mask_sits_below_the_screen_pass() -> void:
	var locker := _spawn_locker()
	await await_physics_frames(2)
	_p.enter_hide(locker)
	var mask: CanvasLayer = null
	for c in locker.get_children():
		if c is CanvasLayer:
			mask = c
	assert_not_null(mask)
	assert_eq(mask.layer, -20, "under the -10 Coherence screen pass")


# ------------------------------------------------------------- 4. step trail

func test_step_trail_records_every_step() -> void:
	var steps := [0]
	var on_noise := func(_pos: Vector3, _r: float, kind: StringName) -> void:
		if kind == Tuning.NOISE_KIND_STEP:
			steps[0] += 1
	EventBus.noise_emitted.connect(on_noise)
	Input.action_press(&"move_forward")
	await await_physics_frames(60)
	Input.action_press(&"sprint")
	await await_physics_frames(40)
	EventBus.noise_emitted.disconnect(on_noise)
	var trail := _p.step_trail()
	assert_gt(steps[0], 3)
	assert_eq(trail.size(), steps[0], "one entry per step noise")
	var prev_t := -1.0
	var kinds: Array = []
	for e: Dictionary in trail.to_array():
		assert_true(e[&"position"] is Vector3)
		assert_eq(e[&"surface"], &"carpet")
		assert_true(float(e[&"time"]) >= prev_t, "times ascend")
		prev_t = float(e[&"time"])
		kinds.append(e[&"speed_kind"])
	assert_eq(kinds[0], NoiseModel.GAIT_WALK)
	assert_eq(kinds[kinds.size() - 1], NoiseModel.GAIT_SPRINT)


func test_ring_buffer() -> void:
	var r := RingBuffer.new(3)
	assert_true(r.is_empty())
	for i in 5:
		r.push(i)
	assert_eq(r.size(), 3)
	assert_eq(r.to_array(), [2, 3, 4], "oldest dropped")
	assert_eq(r.oldest(), 2)
	assert_eq(r.newest(), 4)
	assert_eq(r.get_at(-2), 3)
	assert_null(r.get_at(3))
	r.clear()
	assert_eq(r.size(), 0)


# ------------------------------------------------------------- 7, 9. halt, sprint, loops

func _start_sprint() -> void:
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await await_physics_frames(20)


func test_sprint_loop_and_fov_hold() -> void:
	await _start_sprint()
	assert_true(_p.locomotion.sprinting)
	assert_true(_p.sounds.is_looping(PlayerAudio.LOOP_SPRINT_BREATH), "breath loop fades in")
	assert_gt(_p.rig.fov_hold_of(CameraRig.HOLD_SPRINT), 0.5)
	Input.action_release(&"sprint")
	await await_physics_frames(30)
	assert_false(_p.sounds.is_looping(PlayerAudio.LOOP_SPRINT_BREATH))
	assert_approx(_p.rig.fov_hold_of(CameraRig.HOLD_SPRINT), 0.0, 0.01, "back over 300 ms")


func test_halt_on_every_loss_of_agency() -> void:
	for s in [PlayerStateMachine.STUNNED, PlayerStateMachine.LANDING, PlayerStateMachine.DROPPING,
			PlayerStateMachine.DISSOLVING]:
		PlayerFixture.release_all()
		_p.state_machine.reset()
		await await_physics_frames(2)
		await _start_sprint()
		assert_true(_p.locomotion.sprinting, "sprinting before %s" % s)
		var ends := []
		var on_sprint := func(on: bool) -> void: ends.append(on)
		_p.sprint_changed.connect(on_sprint)
		assert_true(_p.state_machine.transition_to(s))
		assert_eq(ends, [false], "sprint_changed(false) on %s" % s)
		assert_false(_p.sounds.is_looping(PlayerAudio.LOOP_SPRINT_BREATH), "breath stops on %s" % s)
		assert_approx(PlayerFixture.flat_speed(_p), 0.0, 0.0001, "stopped dead on %s" % s)
		_p.sprint_changed.disconnect(on_sprint)
		await await_physics_frames(25)
		assert_approx(_p.rig.fov_hold_of(CameraRig.HOLD_SPRINT), 0.0, 0.01, "FOV hold released on %s" % s)


func test_hiding_halts_a_sprint() -> void:
	var locker := _spawn_locker()
	await _start_sprint()
	_p.enter_hide(locker)
	assert_false(_p.locomotion.sprinting)
	assert_false(_p.sounds.is_looping(PlayerAudio.LOOP_SPRINT_BREATH))


func test_noclip_hold_is_released_when_the_charge_ends() -> void:
	assert_true(_p.begin_noclip_charge())
	_p.rig.fov_hold(-Tuning.NOCLIP_FOV_PULL_DEG, 0.0, CameraRig.HOLD_NOCLIP)
	_p.end_noclip_charge()
	await get_tree().create_timer(0.3).timeout
	assert_approx(_p.rig.fov_hold_of(CameraRig.HOLD_NOCLIP), 0.0, 0.01)


func test_crank_loops_and_whine_pitch() -> void:
	_p.flashlight.set_charge(20.0)
	Input.action_press(&"crank")
	await await_physics_frames(10)
	assert_true(_p.sounds.is_looping(PlayerAudio.LOOP_CRANK_RATCHET))
	assert_true(_p.sounds.is_looping(PlayerAudio.LOOP_CRANK_WHINE))
	var p1 := _p.sounds.loop_pitch01(PlayerAudio.LOOP_CRANK_WHINE)
	assert_approx(p1, _p.flashlight.charge / 100.0, 0.01, "pitch follows charge")
	await await_physics_frames(30)
	assert_gt(_p.sounds.loop_pitch01(PlayerAudio.LOOP_CRANK_WHINE), p1, "rises as it charges")
	Input.action_release(&"crank")
	await await_physics_frames(2)
	assert_false(_p.sounds.is_looping(PlayerAudio.LOOP_CRANK_RATCHET))
	assert_false(_p.sounds.is_looping(PlayerAudio.LOOP_CRANK_WHINE))


# ------------------------------------------------------------- 8. stamina

func test_stamina_regenerates_while_hidden() -> void:
	var locker := _spawn_locker()
	_p.locomotion.stamina.tick(1.0, true)
	var low := _p.locomotion.stamina.value
	assert_approx(low, 80.0, 0.01)
	await await_physics_frames(2)
	_p.enter_hide(locker)
	await get_tree().create_timer(Tuning.STAMINA_REGEN_DELAY + 0.5).timeout
	assert_gt(_p.locomotion.stamina.value, low + 5.0, "regen continues inside the hide spot")


func test_stamina_regenerates_during_landing() -> void:
	_p.locomotion.stamina.tick(1.0, true)
	_p.state_machine.transition_to(PlayerStateMachine.LANDING)
	await get_tree().create_timer(Tuning.STAMINA_REGEN_DELAY + 0.5).timeout
	assert_gt(_p.locomotion.stamina.value, 85.0)


# ------------------------------------------------------------- 11. loss tick

func _ticks() -> int:
	return _p.sounds.played.count(&"coherence_loss_tick")


func test_loss_tick_per_unit_rate_limited() -> void:
	_p.sounds.played.clear()
	_p.apply_coherence(-5.0, &"static")
	assert_eq(_ticks(), 1, "the first tick is immediate")
	_p.tick_timers(0.02)
	assert_eq(_ticks(), 1, "no faster than 20 Hz")
	for i in 10:
		_p.tick_timers(1.0 / Tuning.AUDIO_LOSS_TICK_MAX_HZ)
	assert_eq(_ticks(), 5, "one per unit lost")
	_p.apply_coherence(-0.4, &"static")
	_p.tick_timers(0.1)
	_p.apply_coherence(-0.4, &"static")
	_p.tick_timers(0.1)
	assert_eq(_ticks(), 5, "fractions accumulate")
	_p.apply_coherence(-0.4, &"static")
	_p.tick_timers(0.1)
	assert_eq(_ticks(), 6)
	_p.sounds.played.clear()
	_p.apply_coherence(10.0, &"polaroid")
	_p.tick_timers(0.1)
	assert_eq(_ticks(), 0, "gains never tick")


# ------------------------------------------------------------- 12. hide prompt gate

func test_hide_prompt_only_when_hidden_is_reachable() -> void:
	var locker := _spawn_locker()
	await await_physics_frames(2)
	assert_true(locker.interactable.can_interact(_p))
	_p.begin_noclip_charge()
	assert_true(_p.can_hide(), "noclip review: hiding mid-charge ends the charge silently")
	assert_true(locker.interactable.can_interact(_p), "HIDE prompt mid-charge")
	_p.end_noclip_charge()
	_p.state_machine.transition_to(PlayerStateMachine.STUNNED)
	assert_false(locker.interactable.can_interact(_p), "no HIDE prompt while stunned")


# ------------------------------------------------------------- 13. silent reset

func test_reset_for_run_is_silent() -> void:
	_p.flashlight.set_on(true)
	var toggles := []
	_p.flashlight_toggled.connect(func(on: bool) -> void: toggles.append(on))
	var noises := []
	var on_noise := func(_pos: Vector3, _r: float, kind: StringName) -> void: noises.append(kind)
	EventBus.noise_emitted.connect(on_noise)
	_p.sounds.played.clear()
	_p.reset_for_run()
	EventBus.noise_emitted.disconnect(on_noise)
	assert_false(_p.flashlight.on)
	assert_eq(toggles, [false], "the HUD still hears the light is off")
	assert_false(&"flashlight_toggle" in _p.sounds.played, "no click")
	assert_eq(noises, [], "no noise event")


# ------------------------------------------------------------- 15. interactor

func test_target_change_needs_a_fresh_press() -> void:
	var ir := Interactor.new()
	var who := Node.new()
	var a := Interactable.new()
	a.prompt = Strings.PROMPT_USE
	a.hold_time = 0.6
	var b := Interactable.new()
	b.prompt = Strings.PROMPT_USE
	b.hold_time = 0.6
	var fired := []
	b.interacted.connect(func(_pl: Node) -> void: fired.append(b))
	ir.forced = a
	ir.physics_update(who, true, true, 0.1)
	ir.physics_update(who, true, false, 0.1)
	ir.forced = b
	for i in 10:
		ir.physics_update(who, true, false, 0.1)
	assert_eq(fired, [], "a key held over from A does not fill B")
	ir.physics_update(who, true, true, 0.1)
	for i in 6:
		ir.physics_update(who, true, false, 0.1)
	assert_eq(fired, [b], "a fresh press does")
	for n: Node in [ir, who, a, b]:
		n.free()


# ------------------------------------------------------------- 18, 19. crank glow, beam

func test_crank_glows_the_lens_with_the_light_off() -> void:
	var f := _p.flashlight
	f.set_charge(50.0)
	assert_approx(f.lens_emission(), 0.0)
	Input.action_press(&"crank")
	await await_physics_frames(5)
	assert_false(f.on)
	assert_gt(f.lens_emission(), 0.0, "the wheel's dynamo lights the lens")
	assert_lt(f.lens_emission(), Flashlight.LENS_EMISSION_ON * 0.5, "a faint glow, not the beam")
	Input.action_release(&"crank")
	await await_physics_frames(2)
	assert_approx(f.lens_emission(), 0.0)


func test_beam_leaves_the_held_lens_along_the_view() -> void:
	var f := _p.flashlight
	assert_eq(f.beam.get_parent(), f.held, "the beam is under Held")
	assert_lt(f.beam_origin().distance_to(f.lens.global_position), 0.02, "at the lens")
	var view := -_p.rig.camera.global_transform.basis.z
	assert_lt(rad_to_deg(f.beam_axis().angle_to(view)), 0.5, "parallel to the view axis")


# ------------------------------------------------------------- 21. push

func test_push_into_a_wall_never_bounces_back() -> void:
	PlayerFixture.wall(_world, Vector3(4, 3, 0.2), Vector3(0, 1.5, 0.8))
	await await_physics_frames(2)
	var e := Node3D.new()
	_world.add_child(e)
	e.global_position = Vector3(0, 0.5, -0.8)
	assert_true(_p.contact(e, 10.0))
	var guard := 0
	while get_tree().paused and guard < 200:
		guard += 1
		await get_tree().process_frame
	await await_physics_frames(20)
	assert_lt(_p.global_position.z, 0.7 - Tuning.PLAYER_CAPSULE_RADIUS + 0.05, "the wall stopped the push")
	assert_gt(_p.global_position.z, 0.2, "pushed up to the wall")
	assert_lt(PlayerFixture.flat_speed(_p), 0.01, "no velocity left over from the push")
	var z := _p.global_position.z
	await await_physics_frames(10)
	assert_approx(_p.global_position.z, z, 0.01, "stays put")


class _Column extends Node3D:
	var height: float = 2.6

	func observe_points() -> Array:
		return [global_position + Vector3.UP * height * 0.5, global_position + Vector3.UP * height]
