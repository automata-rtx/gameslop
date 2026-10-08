extends TestCase
## M2.8: a car hide spot works on a real Garage level. The Garage grammar's `under_car`
## placements become HideSpot scenes under their cars, the interaction ray finds the flank from
## the aisle, and the player slides under (camera 0.35 m, +-35 deg) and out again.

const LEVEL_SCENE := preload("res://scenes/level.tscn")
const MAX_FRAMES := 1500

var _level: Level
var _p: Player


func before_all() -> void:
	var data := LevelGenerator.generate(&"garage", 2, 3)
	_level = LEVEL_SCENE.instantiate() as Level
	add_child(_level)
	_level.begin(data)
	var frames := 0
	while not _level.is_ready() and frames < MAX_FRAMES:
		await get_tree().process_frame
		frames += 1


func after_all() -> void:
	PlayerFixture.release_all()
	_level.queue_free()


func _spots() -> Array[HideSpot]:
	var out: Array[HideSpot] = []
	for n in get_tree().get_nodes_in_group(&"hide_spots"):
		if n is HideSpot and _level.is_ancestor_of(n):
			out.append(n)
	return out


func test_every_under_car_placement_became_a_spot_under_its_car() -> void:
	var placements := _level.data.placements_of(LevelData.P_HIDE_SPOT)
	assert_gt(placements.size(), 0, "this Garage seed has cars to hide under")
	var spots := _spots()
	assert_eq(spots.size(), placements.size(), "no marker left in place of a spot")
	var cars: Array[Node3D] = []
	for n in get_tree().get_nodes_in_group(&"props"):
		if _level.is_ancestor_of(n) and n is GarageCar:
			cars.append(n)
	for s in spots:
		assert_eq(s.kind, &"under_car")
		var under := false
		for c in cars:
			if c.global_position.distance_to(s.global_position) < 0.05:
				under = true
		assert_true(under, "the spot stands at its car's centre")
		assert_approx(s.yaw_limit_deg, 35.0, 0.0001, "the placement's view_yaw_limit")


func test_the_spot_looks_out_of_the_aisle_side_of_the_car() -> void:
	for s in _spots():
		var p: Dictionary = {}
		for q in _level.data.placements_of(LevelData.P_HIDE_SPOT):
			if _level.data.grid.world_of(q[&"cell"]).distance_to(s.global_position) < 2.5:
				p = q
		var wall_dir := int(p[&"params"][&"dir"])
		var wall := LevelGrid.DIRS[wall_dir]
		var out := -s.global_transform.basis.z
		assert_lt(out.x * wall.x + out.z * wall.y, -0.99, "it looks away from the wall the car is parked against")
		break


func test_the_ray_from_the_aisle_reaches_the_flank_before_the_car_body() -> void:
	var space := _level.get_world_3d().direct_space_state
	var checked := 0
	for s in _spots():
		var out := -s.global_transform.basis.z
		var from := s.global_position + out * 2.0 + Vector3.UP * 0.5
		var q := PhysicsRayQueryParameters3D.create(from, s.global_position + Vector3.UP * 0.5,
				PlayerLayers.WORLD_MASK | PlayerLayers.INTERACTABLE_MASK)
		q.collide_with_areas = true
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var col := hit[&"collider"] as CollisionObject3D
		if col != null and Interactable.find_on(col) == s.interactable:
			checked += 1
	assert_gt(checked, 0, "at least one car can be hidden under from its aisle side")


func test_hiding_under_a_car_on_the_real_level() -> void:
	var spots := _spots()
	assert_gt(spots.size(), 0)
	var s := spots[0]
	PlayerFixture.release_all()
	_p = PlayerFixture.spawn_player(_level, s.exit_transform().origin + Vector3(0, 0.05, 0))
	await await_physics_frames(3)
	assert_true(s.interactable.can_interact(_p), "no error within 3 m on a fresh level")
	_p.enter_hide(s)
	assert_true(_p.is_hidden())
	await get_tree().create_timer(Tuning.HIDE_UNDER_CAR_SLIDE_TIME + 0.15).timeout
	var cam := _p.rig.camera.global_position
	assert_approx(cam.y - s.global_position.y, 0.35, 0.03, "the eye is 0.35 m up")
	assert_lt(Vector2(cam.x - s.global_position.x, cam.z - s.global_position.z).length(), 0.9, "under the car, inside its footprint")
	_p.rig.anchored_look(10.0, 0.0, s.yaw_limit_deg)
	var yaw := wrapf(_p.rig.rotation.y - s.view_transform().basis.get_euler().y, -PI, PI)
	assert_approx(absf(yaw), deg_to_rad(35.0), 0.001, "yaw +-35")
	_p.leave_hide()
	await get_tree().create_timer(Tuning.HIDE_UNDER_CAR_SLIDE_TIME + 0.15).timeout
	assert_false(_p.is_hidden())
	assert_lt(_p.global_position.distance_to(s.exit_transform().origin), 0.2)
	_p.queue_free()
