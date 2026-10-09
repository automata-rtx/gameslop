extends TestCase
## M2.16: the belt slot's state helpers (09 §1 Interfaces) and the shared throw (09 §2).


func test_slot_copy_does_not_share_state() -> void:
	var a := ItemSlot.new(&"polaroid", 2, {"images": [3, 5]})
	var b := a.copy()
	(b.state["images"] as Array).append(9)
	assert_eq(a.state["images"], [3, 5], "the copy owns its state")
	assert_eq(b.count, 2)
	assert_false(a.is_empty())
	assert_true(ItemSlot.new().is_empty())
	assert_true(ItemSlot.new(&"chalk", 0).is_empty(), "count 0 is empty")


func test_merge_state_appends_arrays_and_keeps_existing_scalars() -> void:
	var s := ItemSlot.new(&"polaroid", 1, {"images": [1], "burning": false})
	s.merge_state({"images": [2, 3], "burning": true, "extra": [7]})
	assert_eq(s.state["images"], [1, 2, 3], "photos queue oldest first")
	assert_eq(s.state["burning"], false, "an existing value wins")
	assert_eq(s.state["extra"], [7], "a new key is copied in")
	var src := {"extra2": [1]}
	s.merge_state(src)
	(s.state["extra2"] as Array).append(2)
	assert_eq(src["extra2"], [1], "merged arrays are copies")


func test_accepted_and_remaining_state_split_per_item_arrays() -> void:
	var st := {"images": [10, 11, 12, 13], "charge": 0.5}
	var took := ItemSlot.accepted_state(st, 3)
	var left := ItemSlot.remaining_state(st, 3)
	assert_eq(took["images"], [10, 11, 12])
	assert_eq(left["images"], [13])
	assert_eq(took["charge"], 0.5, "scalars travel with the accepted items")
	assert_eq(left["charge"], 0.5)
	assert_eq(ItemSlot.accepted_state(st, 0)["images"], [])
	assert_eq(ItemSlot.remaining_state(st, 99)["images"], [])
	assert_eq(st["images"].size(), 4, "the pickup's own state is untouched")


func test_throw_plan_without_a_player_lands_eight_metres_out() -> void:
	var plan := ItemThrow.plan(null)
	var o: Vector3 = plan[&"origin"]
	var v: Vector3 = plan[&"velocity"]
	assert_lt(v.z, 0.0, "away from the thrower")
	assert_gt(v.y, 0.0)
	assert_approx(v.y, absf(v.z), 0.001, "45 degrees")
	# Integrate the arc to the floor: it lands Tuning.GLOWSTICK_THROW_DIST from the release.
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var h := ItemThrow.DEFAULT_HEIGHT
	var t := (v.y + sqrt(v.y * v.y + 2.0 * g * h)) / g
	assert_approx(absf(v.z) * t, Tuning.GLOWSTICK_THROW_DIST, 0.05, "the 8 m throw")
	assert_gt(o.y, ItemThrow.DEFAULT_HEIGHT - 0.01, "released near the right hand's height")
	assert_approx(ItemThrow.height_above_floor(o, null), ItemThrow.DEFAULT_HEIGHT, 0.0001)


func test_throw_speed_falls_as_the_release_gets_higher() -> void:
	var low := Glowstick.throw_speed(8.0, 0.0)
	var high := Glowstick.throw_speed(8.0, 2.0)
	assert_gt(low, high, "a higher release needs less speed to land at the same range")
	assert_approx(low, sqrt(9.8 * 8.0), 0.05, "v = sqrt(g r) at floor height")
