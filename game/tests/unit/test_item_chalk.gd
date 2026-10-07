extends TestCase
## 09 §2, §9, 11 §2: Chalk. One stack of uses, an arrow decal on the aimed surface within 2 m
## pointing the way the player faces (yaw snapped to 45 degrees), 40 decals a level.

var _world: Node3D
var _p: Player
var _inv: Inventory
var _chalk: ChalkItem


func before_each() -> void:
	PlayerFixture.release_all()
	ChalkItem.clear_decals(get_tree())
	_world = PlayerFixture.make_world(self)
	_p = PlayerFixture.spawn_player(_world, Vector3(0, 0.05, 0))
	await await_physics_frames(2)
	_inv = _p.inventory
	_inv.add(&"chalk", 8)
	_chalk = _inv.behavior_for(&"chalk") as ChalkItem


func after_each() -> void:
	PlayerFixture.release_all()
	ChalkItem.clear_decals(get_tree())
	_world.free()


func _decals() -> Array[Node]:
	return get_tree().get_nodes_in_group(&"chalk")


func test_stamps_on_a_wall_in_reach() -> void:
	PlayerFixture.wall(_world, Vector3(4, 3, 0.2), Vector3(0, 1.5, -1.6))
	await await_physics_frames(2)
	assert_true(_inv.use_selected())
	assert_eq(_decals().size(), 1)
	assert_eq(_inv.count_of(&"chalk"), 7, "one use spent")
	var d := _decals()[0] as ChalkDecal
	assert_approx(d.global_position.z, -1.5 + 0.02 + 0.0, 0.05, "on the wall face")
	assert_gt(d.global_transform.basis.y.dot(Vector3(0, 0, 1)), 0.99, "the decal's up is the wall normal")
	assert_gt(d.tip_direction().dot(Vector3.UP), 0.99, "facing the wall head-on stamps an up arrow")


func test_decal_is_a_chalk_decal_per_09() -> void:
	PlayerFixture.wall(_world, Vector3(4, 3, 0.2), Vector3(0, 1.5, -1.6))
	await await_physics_frames(2)
	_inv.use_selected()
	var d := _decals()[0] as ChalkDecal
	assert_lt(d.size.x, 0.4, "scaling in (11 §2: 100 ms)")
	await get_tree().create_timer(0.6).timeout
	assert_eq(d.size, Vector3(0.4, 0.1, 0.4))
	assert_eq(d.modulate.to_html(false), "f2f2f2")
	assert_approx(d.emission_energy, 0.15)
	assert_not_null(d.texture_albedo)
	assert_eq(d.cull_mask, 1, "world geometry only")
	assert_true(d.is_in_group(&"chalk"))


func test_out_of_reach_stamps_nothing_and_costs_nothing() -> void:
	PlayerFixture.wall(_world, Vector3(4, 3, 0.2), Vector3(0, 1.5, -3.0))
	await await_physics_frames(2)
	assert_false(_inv.use_selected())
	assert_eq(_decals().size(), 0)
	assert_eq(_inv.count_of(&"chalk"), 8)


func test_stamp_lockout_is_the_stroke_time() -> void:
	PlayerFixture.wall(_world, Vector3(4, 3, 0.2), Vector3(0, 1.5, -1.6))
	await await_physics_frames(2)
	assert_true(_inv.use_selected())
	assert_false(_inv.use_selected(), "0.3 s per stamp")
	_chalk.tick(0.31)
	assert_true(_inv.use_selected())
	assert_eq(_inv.count_of(&"chalk"), 6)


func test_stamps_on_the_floor_pointing_the_way_the_player_faces() -> void:
	_p.rotation.y = deg_to_rad(40.0)  # snaps to 45 degrees
	_p.rig.add_pitch(deg_to_rad(-80.0))
	await await_physics_frames(3)
	assert_true(_inv.use_selected(), "looking down at the floor within reach")
	var d := _decals()[0] as ChalkDecal
	assert_gt(d.global_transform.basis.y.dot(Vector3.UP), 0.99)
	var tip := d.tip_direction()
	var want := Vector3.ZERO.direction_to(Vector3(-sin(deg_to_rad(45.0)), 0.0, -cos(deg_to_rad(45.0))))
	assert_gt(tip.dot(want), 0.99, "yaw snapped to 45 degrees")


func test_floor_arrow_basis_snaps_yaw() -> void:
	for deg in [0.0, 10.0, 22.0, 23.0, 44.0, 90.0, 133.0, -100.0]:
		var yaw := deg_to_rad(deg)
		var facing := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var tip := -ChalkDecal.arrow_basis(Vector3.UP, facing).z
		var snapped_yaw := snappedf(yaw, deg_to_rad(45.0))
		var want := Vector3(-sin(snapped_yaw), 0.0, -cos(snapped_yaw))
		assert_gt(tip.dot(want), 0.999, "yaw %s" % deg)


func test_wall_arrow_basis_ahead_is_up_and_sideways_is_sideways() -> void:
	var n := Vector3(0, 0, 1)  # wall faces +Z; the player stands at +Z looking -Z
	var straight := -ChalkDecal.arrow_basis(n, Vector3(0, 0, -1)).z
	assert_gt(straight.dot(Vector3.UP), 0.999)
	# Facing 45 degrees to the right of straight ahead (towards +X): up and to the right.
	var right := Vector3(sin(deg_to_rad(45.0)), 0.0, -cos(deg_to_rad(45.0)))
	var tip := -ChalkDecal.arrow_basis(n, right).z
	assert_gt(tip.x, 0.6)
	assert_gt(tip.y, 0.6)
	var left := Vector3(-sin(deg_to_rad(45.0)), 0.0, -cos(deg_to_rad(45.0)))
	assert_lt((-ChalkDecal.arrow_basis(n, left).z).x, -0.6)
	for b in [straight, tip]:
		assert_approx((b as Vector3).length(), 1.0, 0.001)
	var basis := ChalkDecal.arrow_basis(n, right)
	assert_approx(basis.determinant(), 1.0, 0.001, "a proper rotation")


func test_at_most_forty_decals_oldest_removed() -> void:
	for i in 43:
		_inv.add(&"chalk", 20)
		_chalk.stamp(Vector3(float(i) * 0.5, 1.0, -1.5), Vector3(0, 0, 1), Vector3(0, 0, -1))
	await await_frames(2)
	assert_eq(_decals().size(), Tuning.CHALK_MAX_DECALS)
	var min_x := 1e9
	for d in _decals():
		min_x = minf(min_x, (d as Node3D).global_position.x)
	assert_gt(min_x, 1.4, "the first three stamps are the ones that went")


func test_leaving_a_level_clears_the_chalk() -> void:
	_chalk.stamp(Vector3(0, 1, -1.5), Vector3(0, 0, 1), Vector3(0, 0, -1))
	assert_eq(_decals().size(), 1)
	EventBus.level_left.emit(true)
	await await_frames(2)
	assert_eq(_decals().size(), 0)


func test_arrow_texture_is_drawn_not_imported() -> void:
	var img := ChalkDecal.arrow_image()
	assert_eq(img.get_width(), 256)
	assert_gt(img.get_pixel(128, 60).a, 0.3, "the head")
	assert_gt(img.get_pixel(128, 200).a, 0.3, "the shaft")
	assert_eq(img.get_pixel(5, 5).a, 0.0, "transparent corners")
	assert_eq(img.get_pixel(30, 200).a, 0.0, "the shaft is narrow")
