extends TestCase
## 09 §2, §10: the Flare. Struck in the hand (40 s of burn), thrown on the second use_item;
## a fire, not a fixture: its light is in `chemical_light`, the node in `flares_burning`
## (Static is pushed 6 m); a 14 m `light` noise each second; the landing is a 6 m impact.

var _world: Node3D
var _p: Player
var _inv: Inventory
var _fi: FlareItem
var _noises: Array = []
var _noise_cb: Callable


func before_each() -> void:
	PlayerFixture.release_all()
	_clear()
	_world = PlayerFixture.make_world(self)
	_p = PlayerFixture.spawn_player(_world, Vector3(0, 0.05, 0))
	await await_physics_frames(2)
	_inv = _p.inventory
	_inv.add(&"flare", 2)
	_fi = _inv.behavior_for(&"flare") as FlareItem
	_noises = []
	_noise_cb = func(pos: Vector3, r: float, kind: StringName) -> void: _noises.append([pos, r, kind])
	EventBus.noise_emitted.connect(_noise_cb)


func after_each() -> void:
	EventBus.noise_emitted.disconnect(_noise_cb)
	PlayerFixture.release_all()
	_clear()
	_world.free()


func _clear() -> void:
	for n in get_tree().get_nodes_in_group(Tuning.STATIC_FLARE_GROUP):
		n.free()


func _flares() -> Array[Node]:
	return get_tree().get_nodes_in_group(Tuning.STATIC_FLARE_GROUP)


func test_light_matches_09() -> void:
	var f := Flare.new()
	add_child(f)
	var l := f.light
	assert_eq(l.light_color.to_html(false), "ff4a2e")
	assert_approx(l.light_energy, 2.2)
	assert_approx(l.omni_range, 8.0)
	assert_true(l.is_in_group(&"chemical_light"), "fire is chemical light to Flicker and Still")
	assert_true(f.is_in_group(Tuning.STATIC_FLARE_GROUP))
	assert_false(f.is_in_group(&"fixtures"), "not a fixture: Flicker cannot live in it")
	assert_eq(f.collision_layer, 128, "layer 8, thrown")
	assert_eq(f.collision_mask, 1, "collides with the world only")
	assert_eq(f.flame.amount, 60)
	var quad := f.flame.draw_pass_1 as QuadMesh
	assert_eq((quad.material as StandardMaterial3D).blend_mode, BaseMaterial3D.BLEND_MODE_ADD)
	assert_false(l.shadow_enabled, "shadows only at the High setting")
	f.free()


func test_shadows_follow_the_high_setting() -> void:
	var was: Variant = SettingsManager.get_value(&"shadow_quality")
	SettingsManager.set_value(&"shadow_quality", &"high")
	var f := Flare.new()
	assert_true(f.light.shadow_enabled)
	f.free()
	SettingsManager.set_value(&"shadow_quality", &"low")
	var g := Flare.new()
	assert_false(g.light.shadow_enabled)
	g.free()
	SettingsManager.set_value(&"shadow_quality", was)


func test_one_hertz_flutter_and_a_fade_over_the_last_second_and_a_half() -> void:
	assert_approx(Flare.energy_at(0.0, 40.0), 2.2)
	assert_approx(Flare.energy_at(0.25, 39.75), 2.2 * (1.0 + Tuning.FLARE_FLUTTER_DEPTH), 0.001, "the crest of the 1 Hz flutter")
	assert_approx(Flare.energy_at(0.75, 39.25), 2.2 * (1.0 - Tuning.FLARE_FLUTTER_DEPTH), 0.001)
	assert_approx(Flare.energy_at(1.0, 39.0), 2.2, 0.001, "one second later, the same")
	assert_approx(Flare.energy_at(38.5, 0.75), 2.2 * 0.5, 0.001, "half way through the fade")
	assert_approx(Flare.energy_at(40.0, 0.0), 0.0)


func test_burns_forty_seconds_then_goes() -> void:
	var f := Flare.new()
	add_child(f)
	var out := [0]
	f.burnt_out.connect(func() -> void: out[0] += 1)
	for i in 39:
		f.tick(1.0)
	assert_false(f.is_queued_for_deletion())
	assert_gt(f.light.light_energy, 0.0)
	assert_true(Glowstick.is_lit(get_tree(), f.global_position + Vector3(2, 0, 0)))
	f.tick(1.0)
	assert_eq(out[0], 1)
	assert_true(f.is_queued_for_deletion())
	assert_false(f.is_in_group(Tuning.STATIC_FLARE_GROUP), "a spent flare pushes nothing")
	assert_false(Glowstick.is_lit(get_tree(), f.global_position + Vector3(2, 0, 0)), "and lights nothing")
	f.free()


func test_a_burning_flare_makes_a_14_m_light_noise_each_second() -> void:
	var f := Flare.new()
	add_child(f)
	for i in 10:
		f.tick(1.0)
	var lights := _noises.filter(func(n: Array) -> bool: return n[2] == &"light")
	assert_eq(lights.size(), 10)
	assert_approx(float(lights[0][1]), 14.0)
	f.free()


func test_counts_for_observing_out_to_eight_metres() -> void:
	var f := Flare.new()
	add_child(f)
	f.global_position = Vector3(10, 0, 10)
	assert_true(Glowstick.is_lit(get_tree(), Vector3(17.5, 0, 10)), "7.5 m: inside 8 m")
	assert_false(Glowstick.is_lit(get_tree(), Vector3(19, 0, 10)), "9 m: outside")
	var found := false
	for q: Callable in _p._light_queries:
		if bool(q.call(Vector3(10, 0, 4))):
			found = true
	assert_true(found, "the Player's light query reaches the flare too")
	f.free()


func test_static_finds_the_flare_within_six_metres() -> void:
	var f := Flare.new()
	add_child(f)
	f.global_position = Vector3(10, 0, 10)
	assert_eq(StaticPaths.nearest_flare(get_tree(), Vector3(14, 0, 10)), f)
	assert_null(StaticPaths.nearest_flare(get_tree(), Vector3(17, 0, 10)))
	f.free()


func test_use_strikes_then_a_second_use_throws() -> void:
	var used := []
	var cb := func(k: StringName) -> void: used.append(k)
	EventBus.item_used.connect(cb)
	assert_true(_inv.use_selected())
	EventBus.item_used.disconnect(cb)
	assert_eq(used, [&"flare"], "the strike is the use")
	var slot := _inv.selected_slot()
	assert_true(FlareItem.is_burning(slot))
	assert_approx(float(slot.state[FlareItem.BURN]), 40.0)
	assert_eq(slot.count, 2, "both flares still on the belt: one is burning in the hand")
	assert_eq(_flares().size(), 1)
	assert_true(_fi.flare.carried)
	assert_eq(_fi.flare.collision_layer, 0, "carried: nothing to hit")
	assert_false(_inv.use_selected(), "a tap right after the strike does not throw it")
	_fi._strike_left = 0.0
	assert_true(_inv.use_selected())
	assert_false(FlareItem.is_burning(_inv.selected_slot()))
	assert_eq(_inv.count_of(&"flare"), 1)
	var thrown := _flares()[0] as Flare
	assert_false(thrown.carried)
	assert_eq(thrown.collision_layer, 128)
	thrown.free()


func test_the_burn_is_kept_in_the_slot() -> void:
	_inv.use_selected()
	var f := _fi.flare
	f.tick(10.0)
	await await_physics_frames(2)
	assert_approx(float(_inv.selected_slot().state[FlareItem.BURN]), 29.99, 0.1, "the slot mirrors the flare's remaining burn")


func test_the_flare_follows_the_hand_while_another_item_is_in_hand() -> void:
	_inv.add(&"chalk", 8)
	_inv.use_selected()
	var f := _fi.flare
	await await_physics_frames(3)
	var raised := f.global_position
	_inv.select(_inv.slot_of(&"chalk"))
	await await_physics_frames(3)
	assert_eq(_flares().size(), 1, "it keeps burning while another item is selected")
	assert_lt(f.global_position.y, raised.y + 0.05, "lowered to the hip")
	assert_true(Glowstick.is_lit(get_tree(), f.global_position + Vector3(2, 0, 0)))


func test_thrown_flare_lands_about_eight_metres_away_with_one_impact() -> void:
	_p.rotation.y = 0.0
	_inv.use_selected()
	_fi._strike_left = 0.0
	_inv.use_selected()
	var thrown := _flares()[0] as Flare
	await await_physics_frames(150)
	var d := Vector2(thrown.global_position.x, thrown.global_position.z).length()
	assert_gt(d, 6.0, "about 8 m (09 §2)")
	assert_lt(d, 11.0)
	assert_lt(thrown.global_position.z, -5.0, "thrown the way the player faces")
	assert_lt(thrown.global_position.y, 0.2, "settled on the floor")
	var impacts := _noises.filter(func(n: Array) -> bool: return n[2] == &"impact")
	assert_eq(impacts.size(), 1, "one impact on landing, not one per bounce")
	assert_approx(float(impacts[0][1]), 6.0)
	assert_true(thrown.is_in_group(Tuning.STATIC_FLARE_GROUP), "it keeps burning where it lies")
	thrown.free()


func test_a_flare_that_burns_out_in_the_hand_is_spent() -> void:
	_inv.use_selected()
	_fi.flare.tick(41.0)
	assert_eq(_inv.count_of(&"flare"), 1)
	assert_false(FlareItem.is_burning(_inv.selected_slot()))
	assert_eq(_flares().size(), 0)
	_inv.use_selected()
	_fi.flare.tick(41.0)
	assert_false(_inv.has(&"flare"), "the last flare leaves the belt")


func test_leaving_the_level_puts_the_flare_out() -> void:
	_inv.use_selected()
	EventBus.level_left.emit(true)
	await await_frames(2)
	assert_eq(_flares().size(), 0)
	assert_eq(_inv.count_of(&"flare"), 1, "the burning one was spent")
	assert_false(FlareItem.is_burning(_inv.selected_slot()))


func test_swapping_the_stack_out_puts_the_flare_out() -> void:
	_inv.add(&"polaroid", 1)
	_inv.add(&"chalk", 8)
	_inv.add(&"radio")
	_inv.select(_inv.slot_of(&"flare"))
	_inv.use_selected()
	var old := _inv.swap_in(&"glowstick", 1)
	assert_not_null(old)
	assert_false(old.state.has(FlareItem.BURN), "the flare dropped is not burning")
	await await_frames(2)
	assert_eq(_flares().size(), 0)


func test_held_model_is_a_quarter_metre_red_cylinder_in_the_world_shader() -> void:
	var m := ItemModels.held(&"flare")
	var body := m.get_node("Body") as MeshInstance3D
	assert_approx((body.mesh as CylinderMesh).height, 0.25)
	var mat := body.material_override as ShaderMaterial
	assert_eq(mat.shader, ItemModels.WORLD_SHADER)
	assert_eq(float(mat.get_shader_parameter(&"held")), 1.0)
	var c := mat.get_shader_parameter(&"albedo") as Color
	assert_gt(c.r, c.g * 3.0, "dark red")
	m.free()
