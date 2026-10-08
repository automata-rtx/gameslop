extends TestCase
## 09 §2, §10: the Radio. A tap toggles it; on, static that swells and pings faster as the
## player faces the exit (20 deg fast, 60 deg slow, else noise), a 10 m `mech` noise each
## second, 3 charges of 30 s. Held 0.5 s it is set down, playing (the Echo lure).

var _world: Node3D
var _p: Player
var _inv: Inventory
var _ri: RadioItem
var _noises: Array = []
var _noise_cb: Callable


func before_each() -> void:
	PlayerFixture.release_all()
	_world = PlayerFixture.make_world(self)
	_p = PlayerFixture.spawn_player(_world, Vector3(0, 0.05, 0))
	await await_physics_frames(2)
	_inv = _p.inventory
	_inv.add(&"radio")
	_ri = _inv.behavior_for(&"radio") as RadioItem
	_noises = []
	_noise_cb = func(pos: Vector3, r: float, kind: StringName) -> void: _noises.append([pos, r, kind])
	EventBus.noise_emitted.connect(_noise_cb)


func after_each() -> void:
	EventBus.noise_emitted.disconnect(_noise_cb)
	PlayerFixture.release_all()
	_world.free()


func _mech() -> Array:
	return _noises.filter(func(n: Array) -> bool: return n[2] == &"radio")


func _exit_at(pos: Vector3) -> Node3D:
	var e := Node3D.new()
	e.add_to_group(&"exits")
	_world.add_child(e)
	e.global_position = pos
	return e


func test_ping_bands_by_angle_to_the_exit() -> void:
	assert_eq(RadioItem.band(0.0), RadioItem.BAND_FAST)
	assert_eq(RadioItem.band(20.0), RadioItem.BAND_FAST)
	assert_eq(RadioItem.band(-20.0), RadioItem.BAND_FAST)
	assert_eq(RadioItem.band(20.1), RadioItem.BAND_SLOW)
	assert_eq(RadioItem.band(60.0), RadioItem.BAND_SLOW)
	assert_eq(RadioItem.band(60.1), RadioItem.BAND_NOISE)
	assert_eq(RadioItem.band(180.0), RadioItem.BAND_NOISE)
	assert_lt(RadioItem.ping_interval(RadioItem.BAND_FAST), RadioItem.ping_interval(RadioItem.BAND_SLOW), "faster when aligned")
	assert_eq(RadioItem.ping_interval(RadioItem.BAND_NOISE), 0.0, "no ping off-axis")


func test_the_static_swells_towards_the_exit() -> void:
	assert_approx(RadioItem.gain_db(0.0), 0.0)
	assert_approx(RadioItem.gain_db(20.0), 0.0)
	assert_approx(RadioItem.gain_db(60.0), Tuning.RADIO_GAIN_FAR_DB)
	assert_approx(RadioItem.gain_db(180.0), Tuning.RADIO_GAIN_FAR_DB)
	assert_gt(RadioItem.gain_db(30.0), RadioItem.gain_db(50.0))


func test_angle_between_the_view_and_the_exit() -> void:
	var ahead := RadioItem.angle_between(Vector3(0, 0, -1), Vector3.ZERO, Vector3(0, 0, -9))
	assert_approx(ahead, 0.0, 0.01)
	assert_approx(RadioItem.angle_between(Vector3(0, 0, -1), Vector3.ZERO, Vector3(9, 0, 0)), 90.0, 0.01)
	assert_approx(RadioItem.angle_between(Vector3(0, 0, -1), Vector3.ZERO, Vector3(0, 0, 9)), 180.0, 0.01)
	assert_approx(RadioItem.angle_between(Vector3(0, 0, -1), Vector3.ZERO, Vector3.ZERO), 180.0, 0.01, "no direction: noise")


func test_the_item_reads_the_exit_in_the_level() -> void:
	_p.rotation.y = 0.0
	assert_approx(_ri.angle_to_exit(), 180.0, 0.01, "no exit: noise only")
	_exit_at(Vector3(0, 0, -10))
	assert_approx(_ri.angle_to_exit(), 0.0, 1.0)
	_p.rotation.y = deg_to_rad(90.0)
	assert_approx(_ri.angle_to_exit(), 90.0, 1.0)


func test_a_toggle_moves_the_hand_and_lights_the_led_at_once() -> void:
	await get_tree().create_timer(0.7).timeout  # the raise tween
	var m := _ri.held()
	assert_not_null(m, "the radio is in hand")
	var led := m.get_node("Led") as MeshInstance3D
	_inv.use_selected()
	assert_not_null(_ri._flick, "the hand dips on the toggle")
	assert_gt(float((led.material_override as ShaderMaterial).get_shader_parameter(&"emission_strength")), 1.0, "the LED is lit")


func test_toggle_on_off_and_charge_total() -> void:
	assert_true(_inv.use_selected())
	var slot := _inv.selected_slot()
	assert_true(RadioItem.is_on(slot))
	assert_approx(RadioItem.charge_of(slot), 90.0, 0.001, "3 charges of 30 s")
	assert_true(_inv.use_selected())
	assert_false(RadioItem.is_on(slot))
	assert_approx(RadioItem.full_charge(), 90.0)


func test_on_it_emits_a_ten_metre_mech_noise_each_second_and_drains() -> void:
	_inv.use_selected()
	var slot := _inv.selected_slot()
	for i in 600:
		_ri._physics_process(0.1)
	var m := _mech()
	assert_eq(m.size(), 60, "one per second for 60 s")
	assert_approx(float(m[0][1]), 10.0)
	assert_approx(RadioItem.charge_of(slot), 30.0, 0.01, "60 s spent")
	_inv.use_selected()
	_noises.clear()
	for i in 100:
		_ri._physics_process(0.1)
	assert_eq(_mech().size(), 0, "off: silent")
	assert_approx(RadioItem.charge_of(slot), 30.0, 0.01, "off: no drain")


func test_a_spent_radio_leaves_the_belt() -> void:
	_inv.use_selected()
	_inv.selected_slot().state[RadioItem.CHARGE] = 0.05
	_ri._physics_process(0.1)
	assert_false(_inv.has(&"radio"))


func test_the_static_loop_runs_while_on() -> void:
	_inv.use_selected()
	_ri._physics_process(0.016)
	assert_not_null(_ri._loop)
	_inv.use_selected()
	assert_null(_ri._loop)


func test_ping_rate_follows_the_alignment() -> void:
	_exit_at(Vector3(0, 0, -10))
	_p.rotation.y = 0.0
	_inv.use_selected()
	var pings := [0]
	var t := 0.0
	for i in 100:
		var before := _ri._ping_left
		_ri._physics_process(0.1)
		if _ri._ping_left > before:
			pings[0] += 1
		t += 0.1
	var fast: int = pings[0]
	_p.rotation.y = deg_to_rad(45.0)
	pings[0] = 0
	for i in 100:
		var before := _ri._ping_left
		_ri._physics_process(0.1)
		if _ri._ping_left > before:
			pings[0] += 1
	assert_gt(fast, int(pings[0]) * 2, "facing the exit pings far more often than 45 degrees off")
	_p.rotation.y = deg_to_rad(150.0)
	_ri._physics_process(0.1)
	assert_eq(_ri._ping_left, 0.0, "facing away: noise, no ping")


func test_hold_sets_it_down_playing_and_it_keeps_luring() -> void:
	_inv.use_selected()
	_inv.feed_use(true, true, 0.016)
	var t := 0.0
	while t < 0.55:
		_inv.feed_use(false, true, 0.05)
		t += 0.05
	assert_false(_inv.has(&"radio"), "off the belt")
	var placed: RadioPickup = null
	for n in get_tree().get_nodes_in_group(&"pickups"):
		if n is RadioPickup:
			placed = n
	assert_not_null(placed)
	assert_true(placed.is_on())
	assert_lt(placed.global_position.distance_to(_p.global_position), 1.0)
	_noises.clear()
	for i in 30:
		placed._physics_process(0.1)
	assert_eq(_mech().size(), 3, "3 s on the floor: 3 noises of 10 m")
	assert_approx(float(_mech()[0][1]), 10.0)
	assert_lt(placed.charge(), 90.0)
	placed.free()


func test_a_placed_radio_can_be_taken_back_switched_off() -> void:
	var placed := ItemPickup.spawn(_world, &"radio", 1, {RadioItem.ON: true, RadioItem.CHARGE: 40.0}, Vector3(0, 0, -2)) as RadioPickup
	await await_physics_frames(1)
	assert_true(placed.is_on())
	assert_false(placed.can_take(_inv), "the belt already holds its one radio")
	_inv.remove(&"radio", 1)
	assert_true(placed.can_take(_inv))
	assert_true(placed.take(_p))
	assert_true(_inv.has(&"radio"))
	assert_false(RadioItem.is_on(_inv.selected_slot()), "taking it back switches it off")
	assert_approx(RadioItem.charge_of(_inv.selected_slot()), 40.0, 0.5, "with what is left")


func test_a_dead_placed_radio_cannot_be_taken() -> void:
	var placed := ItemPickup.spawn(_world, &"radio", 1, {RadioItem.ON: true, RadioItem.CHARGE: 0.05}, Vector3(0, 0, -2)) as RadioPickup
	await await_physics_frames(1)
	_inv.remove(&"radio", 1)
	for i in 3:
		placed._physics_process(0.1)
	assert_false(placed.is_on())
	assert_false(placed.can_take(_inv))
	assert_false(placed.interactable.can_interact(_p))


func test_leaving_the_level_switches_it_off() -> void:
	_inv.use_selected()
	EventBus.level_left.emit(true)
	assert_false(RadioItem.is_on(_inv.selected_slot()))


func test_held_model_has_an_antenna_and_an_led_that_follows_the_state() -> void:
	var m := ItemModels.held(&"radio")
	var box := (m.get_node("Box") as MeshInstance3D).mesh as BoxMesh
	assert_approx(box.size.x, 0.12)
	assert_approx(((m.get_node("Antenna") as MeshInstance3D).mesh as CylinderMesh).height, 0.1)
	var led := m.get_node("Led") as MeshInstance3D
	assert_eq(float((led.material_override as ShaderMaterial).get_shader_parameter(&"emission_strength") if (led.material_override as ShaderMaterial).get_shader_parameter(&"emission_strength") != null else 0.0), 0.0)
	ItemModels.set_radio_led(m, true)
	assert_gt(float((led.material_override as ShaderMaterial).get_shader_parameter(&"emission_strength")), 1.0, "a small red LED when on")
	ItemModels.set_radio_led(m, false)
	assert_eq(float((led.material_override as ShaderMaterial).get_shader_parameter(&"emission_strength")), 0.0)
	m.free()
