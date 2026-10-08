extends TestCase
## 09 §6, §10: the five hide spots (locker, under car, under desk, pump corner, rack gap): one
## scene each, one HideSpot host. View height, yaw limit, view mask, the slide in and out.

const DIR := "res://scenes/interactables/hide_spot_%s.tscn"
const KINDS: Array[StringName] = [&"locker", &"under_car", &"under_desk", &"pump_corner", &"rack_gap"]

var _world: Node3D
var _p: Player


func before_each() -> void:
	PlayerFixture.release_all()
	SettingsManager.set_value(&"hold_to_press", false)
	_world = PlayerFixture.make_world(self)
	_p = PlayerFixture.spawn_player(_world, Vector3(0, 0.05, 0))
	await await_physics_frames(2)


func after_each() -> void:
	PlayerFixture.release_all()
	_world.free()


func _spot(kind: StringName, pos: Vector3 = Vector3(0, 0, -8), yaw: float = 0.0) -> HideSpot:
	var s := (load(DIR % kind) as PackedScene).instantiate() as HideSpot
	s.position = pos
	s.rotation.y = yaw
	_world.add_child(s)
	return s


func test_every_kind_has_a_scene_with_its_host_contract() -> void:
	for kind in KINDS:
		var s := _spot(kind)
		assert_eq(s.kind, kind, String(kind))
		assert_not_null(s.view_point, "%s view point" % kind)
		assert_not_null(s.exit_point, "%s exit point" % kind)
		assert_eq(s.interactable.prompt_text(), Strings.PROMPT_HIDE, String(kind))
		assert_true(s.is_in_group(&"hide_spots"))
		var body := s.interactable.get_parent() as CollisionObject3D
		assert_eq(body.collision_layer & PlayerLayers.INTERACTABLE_MASK, PlayerLayers.INTERACTABLE_MASK, "%s on the interactable layer" % kind)
		assert_eq(Interactable.find_on(body), s.interactable)
		assert_true(AudioManager.has_sound(s.sound_id()), "%s has its own sound %s" % [kind, s.sound_id()])
		s.free()


func test_placer_maps_every_kind() -> void:
	for kind in KINDS:
		assert_true(LevelPlacer.HIDE_SPOT_SCENES.has(kind), String(kind))
		assert_true(ResourceLoader.exists(LevelPlacer.HIDE_SPOT_SCENES[kind]), String(kind))
	assert_eq(LevelPlacer.HIDE_SPOT_SCENES[&"desk"], LevelPlacer.HIDE_SPOT_SCENES[&"under_desk"])


func test_view_heights_follow_09_06() -> void:
	var car := _spot(&"under_car")
	assert_approx(car.view_point.position.y, Tuning.HIDE_UNDER_CAR_CAMERA_HEIGHT, 0.0001, "0.35 m under a car")
	assert_lt(car.view_point.position.y, Tuning.HIDE_UNDER_CAR_SLOT_HEIGHT, "below the 0.4 m belly")
	assert_approx(_spot(&"under_desk").view_point.position.y, Tuning.HIDE_UNDER_DESK_CAMERA_HEIGHT, 0.0001, "0.5 m behind the panel")
	assert_approx(_spot(&"pump_corner").view_point.position.y, Tuning.HIDE_PUMP_CORNER_EYE_HEIGHT, 0.0001)
	assert_approx(_spot(&"rack_gap").view_point.position.y, Tuning.HIDE_RACK_GAP_EYE_HEIGHT, 0.0001)


func test_yaw_limits() -> void:
	assert_approx(_spot(&"under_car").yaw_limit_deg, 35.0, 0.0001, "under car +-35")
	assert_approx(_spot(&"locker").yaw_limit_deg, Tuning.HIDE_LOCKER_YAW_LIMIT)
	for kind in [&"under_desk", &"pump_corner", &"rack_gap"]:
		assert_approx(_spot(kind).yaw_limit_deg, Tuning.HIDE_YAW_LIMIT_DEFAULT, 0.0001, String(kind))
	var s := _spot(&"under_desk")
	s.configure({&"view_yaw_limit": 20.0})
	assert_approx(s.yaw_limit_deg, 20.0, 0.0001, "the placement's param wins")


func test_view_masks() -> void:
	for kind in [&"locker", &"under_desk", &"pump_corner"]:
		var s := _spot(kind)
		assert_true(s.has_mask(), String(kind))
		s.set_occupant(_p)
		var layer := s.get_children().filter(func(n: Node) -> bool: return n is CanvasLayer)
		assert_eq(layer.size(), 1, "%s mask" % kind)
		assert_eq((layer[0] as CanvasLayer).layer, HideSpot.MASK_CANVAS_LAYER)
		assert_true((layer[0] as CanvasLayer).visible)
		s.set_occupant(null)
		assert_false((layer[0] as CanvasLayer).visible, "the mask lifts on leaving")
	for kind in [&"under_car", &"rack_gap"]:
		assert_false(_spot(kind).has_mask(), "%s: the geometry is the frame" % kind)
	var locker := _spot(&"locker")
	locker.set_occupant(_p)
	var slit_bars := (locker.get_children().filter(func(n: Node) -> bool: return n is CanvasLayer)[0] as CanvasLayer).get_child_count()
	assert_eq(slit_bars, Tuning.HIDE_LOCKER_SLITS + 1, "six slits: seven bars between and around them")


func test_the_desk_mask_leaves_a_floor_level_band() -> void:
	var s := _spot(&"under_desk")
	s.set_occupant(_p)
	var layer := s.get_children().filter(func(n: Node) -> bool: return n is CanvasLayer)[0] as CanvasLayer
	var clear := HideSpot.MASK_CLEAR[&"under_desk"] as Rect2
	assert_approx(clear.size.x, 1.0, 0.0001, "the full width")
	assert_lt(clear.size.y, 0.3, "a thin band: the 0.3 m gap at the floor")
	assert_gt(clear.position.y, 0.4, "low in the frame")
	assert_eq(layer.get_child_count(), 2, "above and below, no side bars")
	var win := HideSpot.MASK_CLEAR[&"pump_corner"] as Rect2
	assert_lt(win.size.x, 0.4, "the door's small window")
	s.set_occupant(null)


## Aim the player's camera at the spot's collider from `back` metres out along its facing.
func _aim_at(s: HideSpot, out: float, from_y: float) -> void:
	var out_dir := -s.global_transform.basis.z
	var target := (s.interactable.get_parent() as Node3D).global_position
	var shape := (s.interactable.get_parent().get_child(0) as CollisionShape3D)
	target = shape.global_position
	_p.global_position = Vector3(target.x, 0.05, target.z) + out_dir * out
	var look := target - Vector3(_p.global_position.x, from_y, _p.global_position.z)
	_p.rotation = Vector3(0.0, atan2(-look.x, -look.z), 0.0)
	_p.rig.reset_pitch()
	_p.rig.add_pitch(atan2(look.y, Vector2(look.x, look.z).length()))


func test_the_ray_finds_each_spot_from_where_the_player_stands() -> void:
	# kind: [metres out along its facing to stand at, true: stand on the facing side]
	var cases := {
		&"under_car": [1.6, 1.0], &"locker": [-1.6, 1.0], &"under_desk": [-1.2, 1.0],
		&"pump_corner": [1.6, 1.0], &"rack_gap": [1.6, 1.0],
	}
	for kind: StringName in cases:
		var s := _spot(kind, Vector3(0, 0, -8))
		var out := float((cases[kind] as Array)[0])
		if kind == &"locker":
			# The locker faces +Z; its door is on the +Z side.
			_p.global_position = Vector3(0, 0.05, -8.0 + 1.6)
			_p.rotation = Vector3.ZERO
			_p.rig.reset_pitch()
		else:
			_aim_at(s, out, 1.68)
		await await_physics_frames(4)
		assert_eq(_p.interactor.target, s.interactable, "%s: the ray finds it" % kind)
		s.free()
		await await_physics_frames(1)


func test_enter_slide_look_limit_and_leave_for_every_kind() -> void:
	for kind in KINDS:
		var s := _spot(kind, Vector3(0, 0, -8), 0.0)
		var hidden := []
		var cb := func(on: bool) -> void: hidden.append(on)
		_p.hidden_changed.connect(cb)
		_p.global_position = Vector3(0, 0.05, -4.0)
		_p.enter_hide(s)
		assert_true(_p.is_hidden(), String(kind))
		assert_eq(_p.collision_layer, 0, "no body inside")
		assert_eq(s.occupant, _p)
		assert_eq(s.interactable.prompt_text(), Strings.PROMPT_LEAVE)
		assert_approx(s.interactable.hold_time, Tuning.HIDE_LEAVE_HOLD_TIME, 0.0001, "leaving is a 0.6 s hold")
		await get_tree().create_timer(Tuning.HIDE_CAMERA_SLIDE_TIME + 0.15).timeout
		var cam := _p.rig.camera.global_position
		var want := s.view_transform().origin
		assert_lt(cam.distance_to(want), 0.02, "%s: the eye slid to the view point" % kind)
		assert_approx(cam.y, s.view_point.global_position.y, 0.02)
		# Look is clamped to the spot's yaw limit.
		_p.rig.anchored_look(10.0, 0.0, s.yaw_limit_deg)
		var yaw := wrapf(_p.rig.rotation.y - s.view_transform().basis.get_euler().y, -PI, PI)
		assert_approx(absf(yaw), deg_to_rad(s.yaw_limit_deg), 0.001, "%s: +-%s deg" % [kind, s.yaw_limit_deg])
		_p.leave_hide()
		await get_tree().create_timer(Tuning.HIDE_CAMERA_SLIDE_TIME + 0.15).timeout
		assert_false(_p.is_hidden(), "%s: out again" % kind)
		assert_null(s.occupant)
		assert_lt(_p.global_position.distance_to(s.exit_transform().origin), 0.2, "%s: at the exit point" % kind)
		assert_eq(hidden, [true, false])
		_p.hidden_changed.disconnect(cb)
		s.free()
		await await_physics_frames(2)


func test_no_error_within_three_metres() -> void:
	var s := _spot(&"under_car")
	var e := Node3D.new()
	e.add_to_group(&"errors")
	_world.add_child(e)
	e.global_position = s.global_position + Vector3(2.5, 0, 0)
	assert_false(s.interactable.can_interact(_p), "09 §6: not with an error within 3 m")
	e.global_position = s.global_position + Vector3(3.5, 0, 0)
	assert_true(s.interactable.can_interact(_p))
	e.free()
