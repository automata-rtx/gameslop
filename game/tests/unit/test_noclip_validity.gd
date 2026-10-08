extends TestCase
## 06 §8 / 07 §7 noclip validity against synthetic walls carrying the builder's metadata:
## each reason (SOLID, NO SPACE, TOO FAR, TOO THIN), wall / soft / floor targets, ceilings,
## the far-side grid rule, and a landing that is always free capsule space.

var _w: Node3D


func before_each() -> void:
	_w = NoclipFixture.world(self)


func after_each() -> void:
	_w.free()


func _settle() -> void:
	await await_physics_frames(2)


func test_passable_wall_is_valid_with_free_landing_behind() -> void:
	NoclipFixture.wall(_w, &"WALL")
	await _settle()
	var a := NoclipFixture.aim(_w)
	assert_eq(a[&"target"], NoclipQuery.TARGET_WALL)
	assert_true(a[&"valid"], "reason %s" % a[&"reason"])
	assert_true(a[&"has_landing"])
	var land: Vector3 = a[&"landing"]
	var far_face := NoclipFixture.WALL_Z - NoclipFixture.WALL_SIZE.z * 0.5
	assert_lt(land.z, far_face - Tuning.PLAYER_CAPSULE_RADIUS + 0.001, "beyond the far face by a radius")
	assert_gt(land.z, NoclipFixture.WALL_Z - 0.1 - Tuning.NOCLIP_FREE_SPACE_MAX - 0.01, "within the band")
	assert_true(NoclipQuery.is_free(_w.get_world_3d().direct_space_state, land, NoclipFixture.capsule()))
	assert_approx(land.y, Tuning.NOCLIP_LANDING_LIFT, 0.01, "stands on the floor")


func test_lowercase_interior_and_partition_and_closed_door_are_candidates() -> void:
	for kind: StringName in [&"interior", &"PARTITION", &"DOOR"]:
		var b := NoclipFixture.wall(_w, kind)
		await _settle()
		assert_true(NoclipFixture.aim(_w)[&"valid"], String(kind))
		b.free()
	var door := NoclipFixture.wall(_w, &"DOOR")
	door.set_meta(&"closed", false)
	door.remove_meta(&"shape_meta")
	await _settle()
	assert_eq(NoclipFixture.aim(_w)[&"reason"], Tuning.NOCLIP_REASON_SOLID, "an open door leaf is not a wall")


func test_solid_reasons() -> void:
	for kind: StringName in [&"SOLID", &"GLASS", &"PROP", &"perimeter"]:
		var b := NoclipFixture.wall(_w, kind)
		await _settle()
		var a := NoclipFixture.aim(_w)
		assert_false(a[&"valid"], String(kind))
		assert_eq(a[&"reason"], Tuning.NOCLIP_REASON_SOLID, String(kind))
		b.free()
	var bare := PlayerFixture.box(_w, NoclipFixture.WALL_SIZE, Vector3(0, 1.35, NoclipFixture.WALL_Z))
	await _settle()
	assert_eq(NoclipFixture.aim(_w)[&"reason"], Tuning.NOCLIP_REASON_SOLID, "a collider without metadata")
	bare.free()


func test_ceiling_is_solid_with_or_without_a_collider() -> void:
	await _settle()
	var up := Vector3(0, 1, -0.2).normalized()
	var a := NoclipFixture.aim(_w, up)
	assert_eq(a[&"reason"], Tuning.NOCLIP_REASON_SOLID, "no ceiling collider: still SOLID")
	PlayerFixture.box(_w, Vector3(10, 0.2, 10), Vector3(0, 2.6, 0)).set_meta(&"wall_kind", &"WALL")
	await _settle()
	a = NoclipFixture.aim(_w, up)
	assert_eq(a[&"target"], NoclipQuery.TARGET_WALL)
	assert_eq(a[&"reason"], Tuning.NOCLIP_REASON_SOLID, "ceilings are never valid")


func test_too_far() -> void:
	NoclipFixture.wall(_w, &"WALL", Vector3(0, 1.35, -4.0))
	await _settle()
	var a := NoclipFixture.aim(_w)
	assert_eq(a[&"target"], NoclipQuery.TARGET_WALL)
	assert_eq(a[&"reason"], Tuning.NOCLIP_REASON_TOO_FAR)
	assert_false(a[&"valid"])


func test_no_space_when_thick() -> void:
	# A 2.4 m deep passable block: no free capsule spot 0.3..2.0 m beyond the surface.
	NoclipFixture.wall(_w, &"WALL", Vector3(0, 1.35, -0.9 - 1.2), Vector3(4, 2.7, 2.4))
	await _settle()
	assert_eq(NoclipFixture.aim(_w)[&"reason"], Tuning.NOCLIP_REASON_NO_SPACE)


func test_no_space_when_blocked_or_floorless_behind() -> void:
	NoclipFixture.wall(_w, &"WALL")
	var block := PlayerFixture.box(_w, Vector3(4, 2.7, 2.5), Vector3(0, 1.35, -2.4))
	await _settle()
	assert_eq(NoclipFixture.aim(_w)[&"reason"], Tuning.NOCLIP_REASON_NO_SPACE, "solid mass behind")
	block.free()
	await _settle()
	assert_true(NoclipFixture.aim(_w)[&"valid"], "space again")
	# A floor that ends at the wall: open air behind, nothing to stand on.
	_w.free()
	_w = Node3D.new()
	add_child(_w)
	NoclipFixture.floor_slab(_w, Vector3(4, 0.2, 4), Vector3(0, -0.1, 1.0))
	NoclipFixture.wall(_w, &"WALL")
	await _settle()
	assert_eq(NoclipFixture.aim(_w)[&"reason"], Tuning.NOCLIP_REASON_NO_SPACE, "no floor behind")


func test_no_space_when_far_cell_is_not_walkable_even_with_room() -> void:
	# Orchestrator rule (M1.4): the grid decides first. Hollow void blocks have floor-free
	# room the shape cast could accept; the metadata says the far cell is not walkable.
	NoclipFixture.wall(_w, &"WALL", Vector3(0, 1.35, NoclipFixture.WALL_Z), NoclipFixture.WALL_SIZE, false)
	await _settle()
	var a := NoclipFixture.aim(_w)
	assert_false(a[&"valid"])
	assert_eq(a[&"reason"], Tuning.NOCLIP_REASON_NO_SPACE)
	# From the other side the far cell is `cell` (walkable): valid.
	assert_eq(NoclipQuery.far_side_walkable({&"dir": LevelGrid.N, &"walkable": true, &"other_walkable": false},
			Vector3(0, 0, -1)), 1, "aiming from the other cell")
	assert_eq(NoclipQuery.far_side_walkable({}, Vector3(0, 0, 1)), -1, "no metadata: shape cast decides")


func test_too_thin_per_target() -> void:
	NoclipFixture.wall(_w, &"WALL")
	await _settle()
	assert_eq(NoclipFixture.aim(_w, NoclipFixture.FORWARD, Tuning.NOCLIP_WALL_COST)[&"reason"],
			Tuning.NOCLIP_REASON_TOO_THIN, "coherence == cost")
	assert_eq(NoclipFixture.aim(_w, NoclipFixture.FORWARD, 4.0)[&"reason"], Tuning.NOCLIP_REASON_TOO_THIN)
	assert_true(NoclipFixture.aim(_w, NoclipFixture.FORWARD, Tuning.NOCLIP_WALL_COST + 0.5)[&"valid"])
	assert_true(NoclipQuery.too_thin(Tuning.NOCLIP_SOFT_COST, NoclipQuery.TARGET_SOFT))
	assert_false(NoclipQuery.too_thin(Tuning.NOCLIP_SOFT_COST + 0.1, NoclipQuery.TARGET_SOFT))
	assert_true(NoclipQuery.too_thin(Tuning.NOCLIP_FLOOR_COST, NoclipQuery.TARGET_FLOOR))


func test_soft_wall_is_cheaper_and_faster() -> void:
	NoclipFixture.wall(_w, &"SOFT")
	await _settle()
	var a := NoclipFixture.aim(_w, NoclipFixture.FORWARD, 8.0)
	assert_eq(a[&"target"], NoclipQuery.TARGET_SOFT)
	assert_true(a[&"valid"], "8 Coherence affords a soft wall (cost 5) but not a wall")
	assert_approx(NoclipQuery.cost(&"soft"), 5.0)
	assert_approx(NoclipQuery.charge_time(&"soft"), 0.35)
	assert_approx(NoclipQuery.cost(&"wall"), 10.0)
	assert_approx(NoclipQuery.charge_time(&"wall"), 0.6)
	assert_approx(NoclipQuery.cost(&"floor"), 30.0)
	assert_approx(NoclipQuery.charge_time(&"floor"), 2.5)


func test_floor_targets() -> void:
	await _settle()
	var down := Vector3(0, -1.65, -1.0).normalized()
	var a := NoclipFixture.aim(_w, down)
	assert_eq(a[&"target"], NoclipQuery.TARGET_FLOOR)
	assert_true(a[&"valid"], "reason %s" % a[&"reason"])
	assert_eq(a[&"key"], "floor", "every floor shares one key")
	assert_eq(NoclipFixture.aim(_w, down, 100.0, true)[&"reason"], Tuning.NOCLIP_REASON_SOLID, "last depth")
	assert_eq(NoclipFixture.aim(_w, down, Tuning.NOCLIP_FLOOR_COST)[&"reason"], Tuning.NOCLIP_REASON_TOO_THIN)
	var shallow := Vector3(0, -1.65, -3.0).normalized()
	assert_eq(NoclipFixture.aim(_w, shallow)[&"reason"], Tuning.NOCLIP_REASON_TOO_FAR, "hit beyond 2.5 m")


func test_floor_cell_kinds_and_unmarked_tops() -> void:
	_w.free()
	_w = Node3D.new()
	add_child(_w)
	NoclipFixture.floor_slab(_w, Vector3(10, 0.2, 10), Vector3(0, -0.1, 0), LevelGrid.RACK)
	await _settle()
	var down := Vector3(0, -1, -0.5).normalized()
	assert_eq(NoclipFixture.aim(_w, down)[&"reason"], Tuning.NOCLIP_REASON_SOLID, "RACK cell")
	PlayerFixture.box(_w, Vector3(10, 0.2, 10), Vector3(0, 0.75, 0))
	await _settle()
	assert_eq(NoclipFixture.aim(_w, down)[&"reason"], Tuning.NOCLIP_REASON_SOLID, "a desk top is no floor")
