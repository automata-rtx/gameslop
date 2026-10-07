extends TestCase
## 06 §7 interaction ray and the Interactable contract; 06 §10 hiding in a locker.

var _world: Node3D
var _p: Player


func before_each() -> void:
	PlayerFixture.release_all()
	SettingsManager.set_value(&"hold_to_press", false)
	_world = PlayerFixture.make_world(self)
	_p = PlayerFixture.spawn_player(_world, Vector3(0, 0.05, 0))
	await await_physics_frames(2)


func after_each() -> void:
	PlayerFixture.release_all()
	_world.free()


## A 0.5 m interactable box `dist` metres in front of the eye.
func _target(dist: float, hold: float = 0.0) -> Interactable:
	var body := PlayerFixture.box(_world, Vector3(0.5, 0.5, 0.5), Vector3(0, 1.65, -dist - 0.25),
			PlayerLayers.INTERACTABLE_MASK)
	var i := Interactable.new()
	i.prompt = Strings.PROMPT_USE
	i.hold_time = hold
	body.add_child(i)
	return i


func _press(action: StringName, frames: int = 2) -> void:
	Input.action_press(action)
	await await_physics_frames(frames)


func test_interactable_contract() -> void:
	var i := Interactable.new()
	assert_false(i.can_interact(null), "no prompt, no interaction")
	i.prompt = "USE"
	assert_true(i.can_interact(null))
	i.condition = func(_p: Node) -> bool: return false
	assert_false(i.can_interact(null))
	var body := StaticBody3D.new()
	body.add_child(i)
	assert_eq(Interactable.find_on(body), i)
	var plain := Node.new()
	assert_null(Interactable.find_on(plain))
	plain.free()
	body.free()


func test_ray_finds_target_within_range_and_press_fires() -> void:
	var i := _target(1.5)
	var fired := [0]
	i.interacted.connect(func(_p: Node) -> void: fired[0] += 1)
	var prompts := []
	_p.prompt_changed.connect(func(t: String, h: float) -> void: prompts.append([t, h]))
	await await_physics_frames(2)
	assert_eq(_p.interactor.target, i)
	assert_eq(prompts[prompts.size() - 1], ["USE", 0.0])
	await _press(&"interact")
	assert_eq(fired[0], 1, "a press fires once")
	await await_physics_frames(5)
	assert_eq(fired[0], 1, "holding does not repeat")


func test_ray_ignores_targets_beyond_2_2_m() -> void:
	_target(2.5)
	await await_physics_frames(2)
	assert_null(_p.interactor.target)


func test_walls_occlude_the_ray() -> void:
	_target(1.5)
	PlayerFixture.box(_world, Vector3(2, 3, 0.1), Vector3(0, 1.5, -0.8))
	await await_physics_frames(2)
	assert_null(_p.interactor.target)


func test_hold_interaction_needs_the_full_hold() -> void:
	var i := _target(1.5, Tuning.INTERACT_HOLD_TIME)
	var fired := [0]
	i.interacted.connect(func(_p: Node) -> void: fired[0] += 1)
	await await_physics_frames(2)
	await _press(&"interact", 20)
	assert_eq(fired[0], 0, "not after 0.33 s")
	await await_physics_frames(25)
	assert_eq(fired[0], 1, "after 0.6 s")


func test_hold_to_press_setting() -> void:
	SettingsManager.set_value(&"hold_to_press", true)
	var i := _target(1.5, Tuning.INTERACT_HOLD_TIME)
	var fired := [0]
	i.interacted.connect(func(_p: Node) -> void: fired[0] += 1)
	await await_physics_frames(2)
	await _press(&"interact", 3)
	assert_eq(fired[0], 1)
	SettingsManager.set_value(&"hold_to_press", false)


func test_hide_in_locker_and_leave() -> void:
	var locker := (load(PlayerFixture.LOCKER_SCENE) as PackedScene).instantiate() as HideSpot
	_world.add_child(locker)
	locker.global_position = Vector3(0, 0, -1.6)
	locker.rotation.y = 0.0
	var hidden := []
	_p.hidden_changed.connect(func(on: bool) -> void: hidden.append(on))
	var bus := []
	var on_bus := func(on: bool) -> void: bus.append(on)
	EventBus.hide_state.connect(on_bus)
	await await_physics_frames(2)
	assert_eq(_p.interactor.target, locker.interactable, "the locker door is the target")
	await _press(&"interact")
	assert_true(_p.is_hidden())
	assert_eq(_p.state_machine.state, PlayerStateMachine.HIDDEN)
	assert_eq(hidden, [true])
	assert_eq(bus, [true])
	assert_eq(_p.collision_layer, 0, "no body while hidden")
	assert_eq(locker.interactable.prompt_text(), Strings.PROMPT_LEAVE)
	# Movement is disabled inside.
	var pos := _p.global_position
	PlayerFixture.release_all()
	await _press(&"move_forward", 10)
	assert_true(_p.global_position.is_equal_approx(pos), "no movement while hidden")
	Input.action_release(&"move_forward")
	# Look stays within the locker's yaw limit.
	await get_tree().create_timer(Tuning.HIDE_CAMERA_SLIDE_TIME + 0.1).timeout
	_p.look(Vector2(-100000, 0))
	var yaw := _p.rig.rotation.y - locker.view_transform().basis.get_euler().y
	assert_approx(absf(wrapf(yaw, -PI, PI)), deg_to_rad(locker.yaw_limit_deg), 0.001)
	# Leaving is a 0.6 s hold.
	await _press(&"interact", 20)
	assert_true(_p.is_hidden(), "still hidden before the hold completes")
	await await_physics_frames(25)
	assert_false(_p.is_hidden(), "left after 0.6 s")
	assert_eq(hidden, [true, false])
	Input.action_release(&"interact")
	await get_tree().create_timer(Tuning.HIDE_CAMERA_SLIDE_TIME + 0.1).timeout
	assert_eq(_p.state_machine.state, PlayerStateMachine.IDLE)
	assert_true(_p.global_position.distance_to(locker.exit_transform().origin) < 0.2, "stands at the exit point")
	assert_false(_p.rig.is_anchored())
	EventBus.hide_state.disconnect(on_bus)


func test_hide_refused_with_an_error_within_3_m() -> void:
	var locker := (load(PlayerFixture.LOCKER_SCENE) as PackedScene).instantiate() as HideSpot
	_world.add_child(locker)
	locker.global_position = Vector3(0, 0, -1.6)
	var e := Node3D.new()
	e.add_to_group(&"errors")
	_world.add_child(e)
	e.global_position = Vector3(1.5, 0, -1.6)
	await await_physics_frames(2)
	assert_null(_p.interactor.target, "no HIDE prompt with an error near")
	await _press(&"interact")
	assert_false(_p.is_hidden())
