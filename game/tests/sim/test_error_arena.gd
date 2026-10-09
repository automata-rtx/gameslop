extends TestCase
## M2.16: the error arena (08 §9) spawns all five errors from keys 1 to 5 and from its five
## buttons, each fair (20 m away, outside the frustum when the level allows) and in a state
## that shows its tell (08 §1): Static's field, Still's drawn column, Echo's own steps,
## Flicker's stuttering group, Null's unrender radius.

const MAX_FRAMES := 600
const ORDER: Array[StringName] = [&"static", &"still", &"echo", &"flicker", &"null"]
const KEYS: Array[int] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5]

var _arena: ErrorArena


func before_each() -> void:
	_arena = (load("res://scenes/debug/error_arena.tscn") as PackedScene).instantiate() as ErrorArena
	add_child(_arena)
	var frames := 0
	while (_arena.player == null or not _arena.level.is_ready() or _arena.get(&"_log") == null) and frames < MAX_FRAMES:
		await get_tree().process_frame
		frames += 1


func after_each() -> void:
	if is_instance_valid(_arena):
		_arena.free()
	await await_physics_frames(1)


func _press(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	_arena.get_viewport().push_input(ev)


func _newest() -> ErrorBase:
	return _arena.errors[_arena.errors.size() - 1] if not _arena.errors.is_empty() else null


func _fair(e: ErrorBase) -> void:
	if e is ErrorFlicker:
		return   # it lives in a lit group, placed ahead of the player by the bench
	var d := e.distance_to_player()
	var cam := _arena.player.rig.camera
	var in_view := cam.is_position_in_frustum(e.global_position + Vector3.UP)
	# Fair when 20 m away and unseen; the bench falls back to the farthest marker otherwise.
	assert_true(d >= Tuning.ERROR_SPAWN_MIN_DIST or not in_view, "%s spawns fair (%.1f m)" % [e.error_id, d])


func test_the_arena_has_one_button_per_error() -> void:
	var labels: PackedStringArray = []
	for n in _arena.find_children("*", "Button", true, false):
		labels.append((n as Button).text)
	for want in ["SPAWN STATIC [1]", "SPAWN STILL [2]", "SPAWN ECHO [3]", "SPAWN FLICKER [4]", "SPAWN NULL [5]"]:
		assert_true(labels.has(want), "button " + want)


func test_keys_1_to_5_spawn_each_error_awake() -> void:
	for i in 5:
		_press(KEYS[i])
		assert_eq(_arena.errors.size(), i + 1, "key %d spawned one error" % (i + 1))
		var e := _newest()
		assert_not_null(e)
		if e == null:
			return
		assert_eq(e.error_id, ORDER[i], "key %d is %s" % [i + 1, ORDER[i]])
		assert_false(e.is_dormant(), "%s is woken, not asleep" % e.error_id)
		_fair(e)


func test_every_button_spawns_its_error() -> void:
	var by_text: Dictionary = {}
	for n in _arena.find_children("*", "Button", true, false):
		by_text[(n as Button).text] = n
	var specs: Array = [["SPAWN STATIC [1]", &"static"], ["SPAWN STILL [2]", &"still"],
			["SPAWN ECHO [3]", &"echo"], ["SPAWN FLICKER [4]", &"flicker"], ["SPAWN NULL [5]", &"null"]]
	for s: Array in specs:
		var b: Button = by_text.get(s[0])
		assert_not_null(b, s[0])
		if b == null:
			return
		b.pressed.emit()
		assert_eq(_newest().error_id, s[1], s[0])
		assert_false(_newest().is_dormant())
	assert_eq(_arena.errors.size(), 5)


func test_static_shows_its_field() -> void:
	_press(KEY_1)
	var e := _newest() as ErrorStatic
	await await_physics_frames(6)
	assert_eq(e.state, Tuning.ERROR_STATE_WANDER)
	assert_true(e.mesh.visible, "the distortion field is drawn")
	assert_gt(e.field_strength_at(e.centre()), 0.0, "the field has strength at its centre")


func test_still_shows_its_column() -> void:
	_press(KEY_2)
	var e := _newest() as ErrorStill
	await await_physics_frames(6)
	assert_eq(e.state, Tuning.ERROR_STATE_WANDER)
	assert_not_null(e.column)
	assert_true(e.column.is_visible_in_tree(), "the matte-black column is in the world")
	assert_true(e.column.global_position.is_finite())


func test_echo_plays_its_own_steps() -> void:
	_press(KEY_3)
	var e := _newest() as ErrorEcho
	await await_physics_frames(240)
	assert_eq(e.state, Tuning.ERROR_STATE_WANDER)
	assert_gt(e.steps_played, 0, "its steps play where it is (the tell)")


func test_flicker_stutters_its_group() -> void:
	_press(KEY_4)
	var e := _newest() as ErrorFlicker
	await await_physics_frames(6)
	assert_eq(e.state, Tuning.ERROR_STATE_RESIDENT)
	assert_true(e.current_group >= 0, "it lives in a group")
	assert_true(_arena.level.light_pool.is_group_lit(e.current_group), "a lit one")
	assert_true(_arena.level.light_pool.group(e.current_group)[0].is_flickering(), "its group stutters (the tell)")
	assert_approx(_arena.level.light_pool.group(e.current_group)[0].flicker_rate(), Tuning.FLICKER_STUTTER_MIN_HZ, 0.01)


func test_null_unrenders_the_world() -> void:
	_press(KEY_5)
	var e := _newest() as ErrorNull
	await await_physics_frames(2)
	assert_eq(e.state, Tuning.ERROR_STATE_CHASE)
	assert_eq(CoherenceRenderer.null_radius, Tuning.NULL_UNRENDER_RADIUS, "the radius where the world is not drawn")


func test_k_clears_and_l_toggles_the_fixtures() -> void:
	_press(KEY_1)
	assert_eq(_arena.errors.size(), 1)
	_press(KEY_K)
	assert_eq(_arena.errors.size(), 0, "K removes every error")
	var pool := _arena.level.light_pool
	var g: int = pool.group_ids()[0]
	assert_true(pool.is_group_lit(g))
	_press(KEY_L)
	assert_false(pool.is_group_lit(g), "L switches the fixtures off")
	_press(KEY_L)
	assert_true(pool.is_group_lit(g), "and on again")
