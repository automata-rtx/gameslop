extends TestCase
## M2.3 the Threshold (01 §8, 02 §7, 07 §5.6, §6): the prefab RunLevelSetup maps
## `threshold_door` to, Open from the start with its daylight strip lit, its leaf shut until
## the player walks into the doorway and then swung outward; crossing it ends a Descent (cause
## `threshold`) and is a proper exit in Endless.

const SCENE := "res://scenes/exits/threshold_door.tscn"

var _world: Node3D
var _p: Player


func before_each() -> void:
	PlayerFixture.release_all()
	_world = PlayerFixture.make_world(self)
	_p = PlayerFixture.spawn_player(_world, Vector3(0, 0.05, -4))
	await await_physics_frames(2)


func after_each() -> void:
	PlayerFixture.release_all()
	_world.free()


func _door() -> ThresholdDoor:
	var e := (load(SCENE) as PackedScene).instantiate() as ThresholdDoor
	e.lock = Tuning.LOCK_OPEN
	_world.add_child(e)
	e.set_physics_process(false)
	return e


func test_the_map_names_the_prefab() -> void:
	assert_eq(RunLevelSetup.exit_scene_for(SubstrateGenerator.THRESHOLD_DOOR), SCENE)
	var e := _door()
	assert_eq(e.exit_kind, SubstrateGenerator.THRESHOLD_DOOR)
	assert_eq(e.sound_open, &"threshold_open")
	assert_true(AudioManager.library == null or AudioManager.library.has(e.sound_open), "the open sound exists")
	e.free()


func test_open_but_shut_until_walked_into() -> void:
	var e := _door()
	assert_true(e.is_open(), "07 §6 depth 6: Open")
	assert_approx(e.leaf_open_amount(), 0.0, 0.001, "the leaf stands shut")
	var strip := e.get_node(^"%Daylight") as MeshInstance3D
	var mat := strip.material_override as ShaderMaterial
	assert_approx(float(mat.get_shader_parameter(&"emission_strength")), Tuning.THRESHOLD_STRIP_EMISSION, 0.001,
		"02 §7: daylight x20 under the door")
	assert_true((mat.get_shader_parameter(&"emission") as Color).is_equal_approx(Color("#FFF7E0")), "the only warm light")
	assert_approx((strip.mesh as BoxMesh).size.y, Tuning.THRESHOLD_STRIP_HEIGHT, 0.0001, "a 2 cm strip")
	var entered: Array = []
	e.entering.connect(func(n: Node3D) -> void: entered.append(n))
	_p.global_position = e.walk_in_point()
	await await_physics_frames(4)
	assert_eq(entered.size(), 1, "walking into the doorway enters")
	await get_tree().create_timer(Exit.DOOR_OPEN_TIME + 0.15).timeout
	assert_approx(e.leaf_open_amount(), 1.0, 0.02, "the leaf swung open")
	# Outward: the free edge of the leaf ends up behind the door (+Z), away from the player.
	var plate := e.get_node(^"%Leaf/Plate") as Node3D
	assert_gt(e.to_local(plate.global_position).z, 0.2, "01 §8: the door opens outward")
	e.free()


func test_crossing_ends_a_descent_only() -> void:
	assert_true(RunLevelSetup.ends_descent(SubstrateGenerator.THRESHOLD_DOOR, Tuning.MODE_DESCENT))
	assert_true(RunLevelSetup.ends_descent(SubstrateGenerator.THRESHOLD_DOOR, Tuning.MODE_DAILY))
	assert_false(RunLevelSetup.ends_descent(SubstrateGenerator.THRESHOLD_DOOR, Tuning.MODE_ENDLESS),
		"05 §8: Endless goes on into Cycle 2")
	assert_false(RunLevelSetup.ends_descent(&"elevator", Tuning.MODE_DESCENT))
	assert_eq(GameState.WIN_CAUSE, &"threshold")
