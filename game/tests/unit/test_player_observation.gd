extends TestCase
## 06 Interfaces / 08 §4: Player.is_observing(node) = frustum, <= 30 m, unoccluded, lit.

var _world: Node3D
var _p: Player


func before_each() -> void:
	# Headless windows are tiny; observation tests need the shipped 16:9 frustum.
	get_tree().root.size = Vector2i(1920, 1080)
	_world = PlayerFixture.make_world(self)
	_p = PlayerFixture.spawn_player(_world, Vector3(0, 0.05, 0))
	await await_physics_frames(2)


func after_each() -> void:
	_world.free()


func _node_at(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	_world.add_child(n)
	n.global_position = pos
	return n


func test_dark_means_not_observed() -> void:
	var n := _node_at(Vector3(0, 1.6, -8))
	assert_false(_p.is_observing(n), "in view but unlit")


func test_flashlight_on_and_aimed_observes() -> void:
	var n := _node_at(Vector3(0, 1.5, -8))
	_p.flashlight.set_on(true)
	assert_true(_p.is_observing(n))


func test_outside_the_25_degree_beam_is_not_lit() -> void:
	_p.flashlight.set_on(true)
	var n := _node_at(Vector3(5, 1.6, -6))  # ~40 deg off axis, still in the 90 deg view
	assert_true(_p.rig.camera.is_position_in_frustum(n.global_position))
	assert_false(_p.is_observing(n))


func test_behind_is_not_observed() -> void:
	_p.flashlight.set_on(true)
	assert_false(_p.is_observing(_node_at(Vector3(0, 1.6, 8))))


func test_beyond_30_m_is_not_observed() -> void:
	_p.flashlight.set_on(true)
	_p.add_light_query(func(_pos: Vector3) -> bool: return true)
	assert_false(_p.is_observing(_node_at(Vector3(0, 1.6, -31))))
	assert_true(_p.is_observing(_node_at(Vector3(0, 1.6, -29))))


func test_occluded_is_not_observed() -> void:
	_p.flashlight.set_on(true)
	PlayerFixture.box(_world, Vector3(4, 3, 0.2), Vector3(0, 1.5, -4))
	await await_physics_frames(1)
	assert_false(_p.is_observing(_node_at(Vector3(0, 1.6, -8))))


func test_other_lights_count() -> void:
	var n := _node_at(Vector3(4, 1.6, -6))
	var q := func(pos: Vector3) -> bool: return pos.distance_to(Vector3(4, 2.8, -6)) <= 7.0
	_p.add_light_query(q)
	assert_true(_p.is_observing(n), "inside a powered fixture's range")
	_p.remove_light_query(q)
	assert_false(_p.is_observing(n))


func test_eye_position_and_hidden_flag() -> void:
	assert_approx(_p.eye_position().y, _p.global_position.y + Tuning.PLAYER_CAMERA_HEIGHT, 0.01)
	assert_false(_p.is_hidden())
