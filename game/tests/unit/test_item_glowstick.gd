extends TestCase
## 09 §2, §10: the Glowstick. A thrown chemical light: the Omni in group `chemical_light`, 90 s
## with a 20 s dim, the 6 m impact noise on landing, hold 0.5 s to set one down quietly.

var _world: Node3D
var _p: Player
var _inv: Inventory
var _gi: GlowstickItem
var _noises: Array = []
var _noise_cb: Callable


func before_each() -> void:
	PlayerFixture.release_all()
	_clear_sticks()
	_world = PlayerFixture.make_world(self)
	_p = PlayerFixture.spawn_player(_world, Vector3(0, 0.05, 0))
	await await_physics_frames(2)
	_inv = _p.inventory
	_inv.add(&"glowstick", 4)
	_gi = _inv.behavior_for(&"glowstick") as GlowstickItem
	_noises = []
	_noise_cb = func(pos: Vector3, r: float, kind: StringName) -> void: _noises.append([pos, r, kind])
	EventBus.noise_emitted.connect(_noise_cb)


func after_each() -> void:
	EventBus.noise_emitted.disconnect(_noise_cb)
	PlayerFixture.release_all()
	_clear_sticks()
	_world.free()


func _clear_sticks() -> void:
	for n in get_tree().get_nodes_in_group(&"chemical_light"):
		n.get_parent().free()


func _sticks() -> Array[Node]:
	return get_tree().get_nodes_in_group(&"chemical_light")


func test_light_matches_09() -> void:
	var s := Glowstick.new()
	add_child(s)
	var l := s.light
	assert_eq(l.light_color.to_html(false), "7cff4a")
	assert_approx(l.light_energy, 0.9)
	assert_approx(l.omni_range, 4.0)
	assert_false(l.shadow_enabled)
	assert_true(l.is_in_group(&"chemical_light"))
	assert_eq(s.collision_layer, 128, "layer 8, thrown")
	assert_eq(s.collision_mask, 1, "collides with the world only")
	var tube := s.get_node("Model/Tube") as MeshInstance3D
	assert_true((tube.material_override as StandardMaterial3D).emission_enabled)
	s.free()


func test_burns_ninety_seconds_dimming_over_the_last_twenty() -> void:
	assert_approx(Glowstick.life_factor(0.0), 1.0)
	assert_approx(Glowstick.life_factor(70.0), 1.0)
	assert_approx(Glowstick.life_factor(80.0), 0.5)
	assert_approx(Glowstick.life_factor(90.0), 0.0)
	var s := Glowstick.new()
	add_child(s)
	s.tick(60.0)
	assert_approx(s.light.light_energy, 0.9)
	s.tick(20.0)
	assert_approx(s.light.light_energy, 0.45, 0.001, "half way through the dim")
	assert_false(s.is_queued_for_deletion())
	s.tick(10.5)
	assert_true(s.is_queued_for_deletion(), "gone after 90 s")
	s.free()


func test_lit_predicate_reads_the_group() -> void:
	var s := Glowstick.new()
	add_child(s)
	s.global_position = Vector3(10, 0, 10)
	assert_true(Glowstick.is_lit(get_tree(), Vector3(12.5, 0, 10)), "2.5 m: inside 4 m")
	assert_false(Glowstick.is_lit(get_tree(), Vector3(15, 0, 10)), "5 m: outside")
	s.tick(89.9)
	assert_false(Glowstick.is_lit(get_tree(), Vector3(12.5, 0, 10)), "a spent stick lights nothing")
	s.free()


func test_the_player_asks_the_group() -> void:
	var s := Glowstick.new()
	add_child(s)
	s.global_position = Vector3(0, 1, -6)
	var found := false
	for q: Callable in _p._light_queries:
		if bool(q.call(Vector3(0, 1, -8))):
			found = true
	assert_true(found, "Player.add_light_query carries the chemical-light predicate (06 Interfaces)")
	s.free()


func test_throw_speed_lands_eight_metres_away() -> void:
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	for h in [0.0, 1.2, 1.5]:
		var v := Glowstick.throw_speed(8.0, h)
		var vx := v * cos(deg_to_rad(45.0))
		var vy := v * sin(deg_to_rad(45.0))
		var t := (vy + sqrt(vy * vy + 2.0 * g * h)) / g
		assert_approx(vx * t, 8.0, 0.01, "height %s" % h)


func test_tap_throws_a_stick_that_lands_and_makes_an_impact_noise() -> void:
	_p.rotation.y = 0.0
	_inv.feed_use(true, true, 0.016)
	assert_eq(_sticks().size(), 0, "a tap acts when the key comes up")
	_inv.feed_use(false, false, 0.016)
	assert_eq(_sticks().size(), 1)
	assert_eq(_inv.count_of(&"glowstick"), 3)
	var stick := _sticks()[0].get_parent() as Glowstick
	await await_physics_frames(150)
	var d := Vector2(stick.global_position.x, stick.global_position.z).length()
	assert_gt(d, 6.0, "about 8 m (09 §2)")
	assert_lt(d, 11.0)
	assert_lt(stick.global_position.z, -5.0, "thrown the way the player faces")
	assert_lt(stick.global_position.y, 0.2, "settled on the floor")
	var impacts := _noises.filter(func(n: Array) -> bool: return n[2] == &"impact")
	assert_eq(impacts.size(), 1, "one impact on landing, not one per bounce")
	assert_approx(float(impacts[0][1]), 6.0)
	stick.queue_free()


func test_hold_half_a_second_sets_one_down_silently() -> void:
	var t := 0.0
	_inv.feed_use(true, true, 0.016)
	while t < 0.49:
		_inv.feed_use(false, true, 0.05)
		t += 0.05
	assert_eq(_sticks().size(), 0, "not yet")
	_inv.feed_use(false, true, 0.05)
	assert_eq(_sticks().size(), 1)
	_inv.feed_use(false, false, 0.016)
	assert_eq(_sticks().size(), 1, "the release after a drop does not also throw")
	assert_eq(_inv.count_of(&"glowstick"), 3)
	var stick := _sticks()[0].get_parent() as Glowstick
	assert_lt(stick.global_position.distance_to(_p.global_position), 1.0, "at the feet")
	await await_physics_frames(60)
	assert_eq(_noises.filter(func(n: Array) -> bool: return n[2] == &"impact").size(), 0)
	stick.queue_free()


func test_cranking_mid_hold_drops_nothing() -> void:
	_inv.feed_use(true, true, 0.016)
	_inv.feed_use(false, true, 0.2)
	_p.flashlight.set_cranking(true)
	_inv.feed_use(false, true, 0.016, _p.can_use_item())
	_p.flashlight.set_cranking(false)
	_inv.feed_use(false, false, 0.016)
	assert_eq(_sticks().size(), 0, "the hold was aborted, so the release throws nothing")
	assert_eq(_inv.count_of(&"glowstick"), 4)


func test_use_selected_throws_now() -> void:
	assert_true(_inv.use_selected())
	assert_eq(_sticks().size(), 1)
	assert_eq(_inv.count_of(&"glowstick"), 3)


func test_leaving_the_level_removes_the_sticks() -> void:
	_inv.use_selected()
	assert_eq(_sticks().size(), 1)
	EventBus.level_left.emit(false)
	await await_frames(2)
	assert_eq(_sticks().size(), 0)


func test_item_used_is_announced_per_throw() -> void:
	var used := []
	var cb := func(k: StringName) -> void: used.append(k)
	EventBus.item_used.connect(cb)
	_inv.use_selected()
	EventBus.item_used.disconnect(cb)
	assert_eq(used, [&"glowstick"])
