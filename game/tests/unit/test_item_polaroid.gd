extends TestCase
## 09 §2, §4, §10: the Polaroid. +25 Coherence with the gain pulse after 1.2 s, the flash on the
## last frame, lockouts (stunned, charging noclip, cranking), the error hook, the photographs.

class FakeError extends Node3D:
	var error_id: StringName = &"still"
	var flashed_from: Array[Vector3] = []

	func on_polaroid(origin: Vector3, _dir: Vector3) -> void:
		flashed_from.append(origin)


var _world: Node3D
var _p: Player
var _inv: Inventory
var _pol: PolaroidItem


func before_each() -> void:
	PlayerFixture.release_all()
	_world = PlayerFixture.make_world(self)
	_p = PlayerFixture.spawn_player(_world, Vector3(0, 0.05, 0))
	await await_physics_frames(2)
	_inv = _p.inventory
	_inv.add(&"polaroid", 2)
	_pol = _inv.behavior_for(&"polaroid") as PolaroidItem
	_p.apply_coherence(-50.0, &"static")


func after_each() -> void:
	PlayerFixture.release_all()
	_world.free()


func test_use_takes_one_point_two_seconds_then_gains_twenty_five() -> void:
	assert_approx(_p.coherence, 50.0)
	assert_true(_inv.use_selected())
	assert_true(_pol.busy)
	_pol.tick(1.1)
	assert_approx(_p.coherence, 50.0, 0.001, "nothing before the flash")
	assert_eq(_inv.count_of(&"polaroid"), 2, "the Polaroid is spent on the flash")
	_pol.tick(0.11)
	assert_approx(_p.coherence, 75.0, 0.001, "+25 (09 §2)")
	assert_eq(_inv.count_of(&"polaroid"), 1)
	assert_false(_pol.busy)


func test_gain_pulse_flash_and_item_used() -> void:
	var used: Array[StringName] = []
	var cb := func(k: StringName) -> void: used.append(k)
	EventBus.item_used.connect(cb)
	var gains: Array = []
	var cb2 := func(_v: float, d: float, src: StringName) -> void: gains.append([d, src])
	_p.coherence_changed.connect(cb2)
	_inv.use_selected()
	_pol.tick(Tuning.POLAROID_USE_TIME + 0.01)
	EventBus.item_used.disconnect(cb)
	assert_eq(used, [&"polaroid"] as Array[StringName])
	assert_eq(gains, [[25.0, &"polaroid"]], "the Player's gain path (pulse, chord, FOV) runs")
	assert_lt(CoherenceRenderer.pulse_age(&"flash"), 1.0, "the post flash pulse fired")
	assert_lt(CoherenceRenderer.pulse_age(&"coherence_gain"), 1.0)


func test_gain_is_clamped_at_full() -> void:
	_p.apply_coherence(45.0, &"exit")
	_inv.use_selected()
	_pol.tick(1.3)
	assert_approx(_p.coherence, 100.0)


func test_no_second_use_while_one_runs() -> void:
	assert_true(_inv.use_selected())
	assert_false(_inv.use_selected())
	assert_false(_inv.select(1), "no belt change mid-use")


func test_view_narrows_three_degrees_during_the_use() -> void:
	_inv.use_selected()
	await get_tree().create_timer(1.2).timeout
	_pol.tick(0.05)
	assert_lt(_p.rig.fov_hold_of(PolaroidItem.FOV_KEY), -1.0, "the view narrows towards 3 degrees")
	assert_gt(_p.rig.fov_hold_of(PolaroidItem.FOV_KEY), -Tuning.POLAROID_NARROW_DEG - 0.01)
	_pol.tick(1.2)
	await get_tree().create_timer(1.0).timeout
	assert_approx(_p.rig.fov_hold_of(PolaroidItem.FOV_KEY), 0.0, 0.3, "released on the flash")


func test_refused_while_stunned() -> void:
	var e := FakeError.new()
	_world.add_child(e)
	_p.contact(e, 10.0)
	assert_true(_p.is_stunned())
	assert_false(_inv.use_selected(), "09 §2: not while stunned")
	assert_false(_pol.busy)
	assert_eq(_inv.count_of(&"polaroid"), 2)


func test_refused_while_charging_noclip() -> void:
	assert_true(_p.begin_noclip_charge())
	assert_false(_inv.use_selected(), "09 §2: not while charging noclip")
	_p.end_noclip_charge()
	assert_true(_inv.use_selected())


func test_refused_while_cranking() -> void:
	_p.flashlight.set_cranking(true)
	assert_false(_inv.use_selected(), "06 §5: no items while cranking")
	_p.flashlight.set_cranking(false)
	assert_true(_inv.use_selected())


func test_a_contact_mid_use_cancels_it_and_costs_nothing() -> void:
	_inv.use_selected()
	_pol.tick(0.5)
	var e := FakeError.new()
	_world.add_child(e)
	_p.contact(e, 10.0)
	var before := _p.coherence
	_pol.tick(1.0)
	assert_false(_pol.busy)
	assert_approx(_p.coherence, before, 0.001, "no gain")
	assert_eq(_inv.count_of(&"polaroid"), 2, "no Polaroid spent")


func test_starting_noclip_mid_use_cancels() -> void:
	_inv.use_selected()
	_pol.tick(0.3)
	_p.begin_noclip_charge()
	_pol.tick(0.1)
	assert_false(_pol.busy)
	assert_eq(_inv.count_of(&"polaroid"), 2)


func test_in_cone_rule() -> void:
	var o := Vector3.ZERO
	var fwd := Vector3(0, 0, -1)
	assert_true(PolaroidItem.in_cone(o, fwd, Vector3(0, 0, -10)))
	assert_true(PolaroidItem.in_cone(o, fwd, Vector3(3, 0, -10)))
	assert_false(PolaroidItem.in_cone(o, fwd, Vector3(10, 0, -3)), "70 degrees off axis")
	assert_false(PolaroidItem.in_cone(o, fwd, Vector3(0, 0, 5)), "behind")
	assert_false(PolaroidItem.in_cone(o, fwd, Vector3(0, 0, -Tuning.POLAROID_RANGE - 1.0)), "out of range")


func test_errors_in_the_cone_get_the_hook() -> void:
	var front := FakeError.new()
	front.add_to_group(&"errors")
	_world.add_child(front)
	front.global_position = Vector3(0, 1.65, -6)
	var behind := FakeError.new()
	behind.add_to_group(&"errors")
	_world.add_child(behind)
	behind.global_position = Vector3(0, 1.65, 6)
	var walled := FakeError.new()
	walled.add_to_group(&"errors")
	_world.add_child(walled)
	walled.global_position = Vector3(0, 1.65, -12)
	PlayerFixture.wall(_world, Vector3(4, 3, 0.2), Vector3(0, 1.5, -9))
	var no_hook := Node3D.new()
	no_hook.add_to_group(&"errors")
	_world.add_child(no_hook)
	no_hook.global_position = Vector3(0, 1.65, -5)
	await await_physics_frames(2)
	_inv.use_selected()
	_pol.tick(1.3)
	assert_eq(front.flashed_from.size(), 1, "in the cone and in sight")
	assert_eq(behind.flashed_from.size(), 0, "behind the player")
	assert_eq(walled.flashed_from.size(), 0, "behind a wall")


func test_photo_queue_is_consumed_oldest_first() -> void:
	_inv.reset()
	_inv.add(&"polaroid", 1, {&"images": [6]})
	_inv.add(&"polaroid", 1, {&"images": [2]})
	_inv.use_selected()
	assert_eq(_pol.image_index, 6)
	_pol.tick(1.3)
	assert_eq(_inv.slots[0].state[&"images"], [2])
	_inv.use_selected()
	assert_eq(_pol.image_index, 2)
	_pol.tick(1.3)
	assert_false(_inv.has(&"polaroid"))


func test_seen_photos_are_recorded_in_the_meta() -> void:
	var meta: MetaState = GameState.meta
	var before := meta.polaroids_seen.duplicate()
	meta.polaroids_seen.clear()
	_inv.reset()
	_inv.add(&"polaroid", 1, {&"images": [4]})
	_inv.use_selected()
	_pol.tick(1.3)
	assert_eq(meta.polaroids_seen, [4] as Array[int])
	meta.polaroids_seen.assign(before)


# --- PolaroidPainter (09 §4) ------------------------------------------------------------

func test_painter_makes_eight_distinct_256_images() -> void:
	PolaroidPainter.clear_cache()
	var hashes := {}
	for i in PolaroidPainter.COUNT:
		var img := PolaroidPainter.image(i)
		assert_eq(img.get_width(), 256)
		assert_eq(img.get_height(), 256)
		hashes[img.get_data().hex_encode().sha256_text()] = true
	assert_eq(hashes.size(), 8, "eight different images")
	assert_eq(PolaroidPainter.COUNT, Tuning.POLAROID_IMAGE_COUNT)


func test_painter_images_are_warm_with_a_thin_white_border() -> void:
	for i in PolaroidPainter.COUNT:
		var img := PolaroidPainter.image(i)
		assert_eq(img.get_pixel(1, 1), PolaroidPainter.WHITE, "border at the corner of image %d" % i)
		assert_eq(img.get_pixel(128, 2), PolaroidPainter.WHITE)
		assert_eq(img.get_pixel(254, 128), PolaroidPainter.WHITE)
		var white := 0
		for y in range(16, 240, 4):
			for x in range(16, 240, 4):
				if img.get_pixel(x, y) == PolaroidPainter.WHITE:
					white += 1
		assert_lt(float(white) / (56.0 * 56.0), 0.25, "the border is thin: the picture is not white (image %d)" % i)
		var sat := 0.0
		var warm := 0.0
		var n := 0
		for y in range(16, 240, 8):
			for x in range(16, 240, 8):
				var c := img.get_pixel(x, y)
				sat += c.s
				warm += c.r - c.b
				n += 1
		assert_gt(sat / n, 0.25, "image %d is saturated" % i)
		assert_gt(warm / n, 0.0, "image %d leans warm" % i)


func test_painter_caches_and_wraps_indices() -> void:
	assert_eq(PolaroidPainter.image(3), PolaroidPainter.image(3))
	assert_eq(PolaroidPainter.image(11), PolaroidPainter.image(3))
	assert_eq(PolaroidPainter.index_for(-1), 7)
	assert_eq(PolaroidPainter.texture(0).get_width(), 256)
	assert_eq(PolaroidPainter.name_of(0), &"kitchen_window")
