extends TestCase
## 06 §9 Coherence: sources, clamps, no regen, renderer feed, dissolution and its cause;
## contact rules: cost, stun 1.2 s, push 1.5 m, 3 s exclusivity, refusals.

var _world: Node3D
var _p: Player
var _changes: Array = []
var _dissolved: Array = []


func before_each() -> void:
	PlayerFixture.release_all()
	_world = PlayerFixture.make_world(self)
	_p = PlayerFixture.spawn_player(_world, Vector3(0, 0.05, 0))
	_changes.clear()
	_dissolved.clear()
	_p.coherence_changed.connect(func(v: float, d: float, s: StringName) -> void: _changes.append([v, d, s]))
	_p.dissolved.connect(func(c: StringName) -> void: _dissolved.append(c))
	await await_physics_frames(3)


func after_each() -> void:
	PlayerFixture.release_all()
	await _await_unpaused()
	_world.free()
	CoherenceRenderer.set_coherence(Tuning.COHERENCE_MAX)


func _await_unpaused() -> void:
	var guard := 0
	while get_tree().paused and guard < 200:
		guard += 1
		await get_tree().process_frame


func _error(id: StringName, pos: Vector3) -> Node3D:
	var e := _ErrorStub.new()
	e.error_id = id
	_world.add_child(e)
	e.global_position = pos
	return e


func test_sources_and_clamps() -> void:
	_p.apply_coherence(-10.0, &"noclip")
	assert_approx(_p.coherence, 90.0)
	_p.apply_coherence(Tuning.COHERENCE_GAIN_POLAROID, &"polaroid")
	assert_approx(_p.coherence, 100.0, 0.0001, "clamped at 100")
	assert_eq(_changes.size(), 2)
	assert_approx(_changes[1][1], 10.0, 0.0001, "delta reports what was applied")
	_p.apply_coherence(5.0, &"exit")
	assert_eq(_changes.size(), 2, "no change at max emits nothing")


func test_no_passive_regeneration() -> void:
	_p.apply_coherence(-40.0, &"static")
	await await_physics_frames(30)
	assert_approx(_p.coherence, 60.0)


func test_renderer_is_fed_through_its_setter() -> void:
	_p.apply_coherence(-30.0, &"static")
	assert_approx(CoherenceRenderer.coherence01, 0.7, 0.0001)


func test_dissolves_at_zero_with_error_cause() -> void:
	_p.apply_coherence(-50.0, &"static")
	_p.apply_coherence(-60.0, &"null")
	assert_approx(_p.coherence, 0.0)
	assert_eq(_dissolved, [&"null"])
	assert_true(_p.is_dissolving())
	assert_false(_p.has_agency(), "input locked")
	_p.apply_coherence(25.0, &"polaroid")
	assert_approx(_p.coherence, 0.0, 0.0001, "nothing changes after dissolution")
	assert_eq(_dissolved.size(), 1)


func test_cause_is_last_damage_source_and_substrate() -> void:
	_p.apply_coherence(-95.0, &"substrate")
	_p.apply_coherence(-10.0, &"noclip")
	assert_eq(_dissolved, [&"substrate"], "noclip is never a cause")


func test_contact_costs_stuns_and_pushes() -> void:
	var e := _error(&"still", Vector3(0, 0.5, -0.8))
	var start := _p.global_position
	assert_true(_p.contact(e, Tuning.COHERENCE_CONTACT_STILL))
	assert_approx(_p.coherence, 65.0)
	assert_eq(_changes[_changes.size() - 1][2], &"still")
	assert_true(_p.is_stunned())
	assert_true(_p.rig.trauma >= Tuning.CONTACT_TRAUMA - 0.01)
	assert_false(_p.can_noclip(), "no noclip while stunned")
	await _await_unpaused()
	await await_physics_frames(20)
	var pushed := Vector3(_p.global_position.x - start.x, 0, _p.global_position.z - start.z)
	assert_approx(pushed.length(), Tuning.CONTACT_PUSH_DIST, 0.1, "pushed 1.5 m")
	assert_gt(pushed.z, 0.0, "away from the error")


func test_stun_speed_cap_and_end() -> void:
	var e := _error(&"echo", Vector3(0, 0.5, 1))
	_p.contact(e, Tuning.COHERENCE_CONTACT_ECHO)
	await _await_unpaused()
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await await_physics_frames(30)
	assert_approx(PlayerFixture.flat_speed(_p), Tuning.PLAYER_CROUCH_SPEED, 0.1, "crouch speed while stunned")
	_p.tick_timers(Tuning.CONTACT_STUN_TIME)
	assert_false(_p.is_stunned(), "stun ends after 1.2 s")


func test_no_player_side_cooldown_exclusivity_is_the_directors() -> void:
	# 10 §4 (CHANGELOG): the Player holds no 3 s clock; the Director's gate refuses.
	var e := _error(&"flicker", Vector3(0, 0.5, -1))
	assert_true(_p.contact(e, Tuning.COHERENCE_CONTACT_FLICKER))
	assert_true(_p.contact(e, Tuning.COHERENCE_CONTACT_FLICKER), "no gate: a second contact lands")
	assert_approx(_p.coherence, 40.0)
	var asked := []
	_p.contact_gate = func(err: Node3D) -> bool:
		asked.append(err)
		return false
	assert_false(_p.contact(e, Tuning.COHERENCE_CONTACT_FLICKER), "the gate refuses")
	assert_eq(asked, [e], "the gate is asked with the error")
	assert_approx(_p.coherence, 40.0, 0.0001, "refused contacts cost nothing")
	_p.contact_gate = func(_err: Node3D) -> bool: return true
	assert_true(_p.contact(e, 10.0))
	assert_approx(_p.coherence, 30.0)


func test_own_state_refusals_do_not_ask_the_gate() -> void:
	var e := _error(&"still", Vector3(0, 0.5, -1))
	var asked := [0]
	_p.contact_gate = func(_err: Node3D) -> bool:
		asked[0] += 1
		return true
	for s in [PlayerStateMachine.LANDING, PlayerStateMachine.DROPPING]:
		_p.state_machine.reset()
		assert_true(_p.state_machine.transition_to(s))
		assert_false(_p.contact(e, 35.0), "refused in %s" % s)
	_p.state_machine.reset()
	_p.begin_noclip_charge()
	_p.state_machine.transition_to(PlayerStateMachine.NOCLIP_PASS)
	assert_false(_p.contact(e, 35.0), "refused in the noclip pass")
	assert_eq(asked[0], 0, "own refusals never consume the Director's clock")
	assert_approx(_p.coherence, 100.0)


func test_contact_amount_is_clamped_to_the_single_hit_cap() -> void:
	var e := _error(&"still", Vector3(0, 0.5, -1))
	assert_true(_p.contact(e, 80.0))
	assert_approx(_p.coherence, 100.0 - Tuning.COHERENCE_MAX_SINGLE_HIT)
	assert_false(_p.is_dissolving())


func test_contact_refused_during_noclip_pass_and_dissolve() -> void:
	var e := _error(&"still", Vector3(0, 0.5, -1))
	assert_true(_p.begin_noclip_charge())
	assert_true(_p.state_machine.transition_to(PlayerStateMachine.NOCLIP_PASS))
	assert_false(_p.contact(e, 35.0), "Stunned cannot interrupt NoclipPass")
	assert_approx(_p.coherence, 100.0)


func test_contact_interrupts_noclip_charge() -> void:
	var e := _error(&"still", Vector3(0, 0.5, -1))
	_p.begin_noclip_charge()
	assert_true(_p.contact(e, 35.0))
	assert_true(_p.is_stunned())


func test_lethal_contact_dissolves() -> void:
	_p.apply_coherence(-80.0, &"static")
	var e := _error(&"still", Vector3(0, 0.5, -1))
	assert_true(_p.contact(e, 35.0))
	assert_eq(_dissolved, [&"still"])
	assert_false(_p.is_stunned(), "dissolving, not stunned")


class _ErrorStub extends Node3D:
	var error_id: StringName = &""
