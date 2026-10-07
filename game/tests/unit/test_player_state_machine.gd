extends TestCase
## 06 §12 state machine: explicit transitions; Stunned interrupts NoclipCharge but not
## NoclipPass; a drop never leads to Dissolving; Dissolving and Cinematic are terminal.

const SM := preload("res://src/player/player_state_machine.gd")


func test_twelve_states_exist() -> void:
	# Crank is a flag, not a state (06 §12): 12 states.
	assert_eq(SM.ALL.size(), 12)
	for s in SM.ALL:
		assert_true(SM.TRANSITIONS.has(s), "table row for %s" % s)


func test_locomotion_moves_freely() -> void:
	for a in SM.LOCOMOTION:
		for b in SM.LOCOMOTION:
			assert_eq(SM.allowed(a, b), a != b, "%s -> %s" % [a, b])


func test_stun_interrupts_charge_not_pass() -> void:
	assert_true(SM.allowed(SM.NOCLIP_CHARGE, SM.STUNNED))
	assert_false(SM.allowed(SM.NOCLIP_PASS, SM.STUNNED))


func test_drop_cannot_dissolve() -> void:
	assert_false(SM.allowed(SM.DROPPING, SM.DISSOLVING))
	assert_true(SM.allowed(SM.NOCLIP_CHARGE, SM.DROPPING))


func test_terminal_states() -> void:
	for s in SM.ALL:
		assert_false(SM.allowed(SM.DISSOLVING, s), "Dissolving -> %s" % s)
		assert_false(SM.allowed(SM.CINEMATIC, s), "Cinematic -> %s" % s)


func test_hidden_rules() -> void:
	assert_true(SM.allowed(SM.IDLE, SM.HIDDEN))
	assert_false(SM.allowed(SM.NOCLIP_CHARGE, SM.HIDDEN), "no hiding mid-charge")
	assert_true(SM.allowed(SM.HIDDEN, SM.STUNNED), "a found hider is contacted")
	assert_false(SM.allowed(SM.HIDDEN, SM.SPRINT))


func test_transition_emits_and_refuses() -> void:
	var sm := PlayerStateMachine.new()
	var seen := []
	sm.state_changed.connect(func(a: StringName, b: StringName) -> void: seen.append([a, b]))
	assert_true(sm.transition_to(SM.WALK))
	assert_true(sm.transition_to(SM.NOCLIP_CHARGE))
	assert_true(sm.transition_to(SM.NOCLIP_PASS))
	assert_false(sm.transition_to(SM.STUNNED))
	assert_eq(sm.state, SM.NOCLIP_PASS)
	assert_eq(seen.size(), 3)
	assert_eq(seen[2], [SM.NOCLIP_CHARGE, SM.NOCLIP_PASS])
	assert_false(sm.has_movement(), "no input movement during the pass")
	sm.free()


func test_player_states_follow_input() -> void:
	var world := PlayerFixture.make_world(self)
	var p := PlayerFixture.spawn_player(world, Vector3(0, 0.05, 0))
	await await_physics_frames(2)
	assert_eq(p.state_machine.state, SM.IDLE)
	Input.action_press(&"move_forward")
	await await_physics_frames(10)
	assert_eq(p.state_machine.state, SM.WALK)
	Input.action_press(&"crouch")
	await await_physics_frames(3)
	assert_eq(p.state_machine.state, SM.CROUCH)
	PlayerFixture.release_all()
	await await_physics_frames(30)
	assert_eq(p.state_machine.state, SM.IDLE)
	world.free()
