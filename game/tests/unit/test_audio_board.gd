extends TestCase
## M1.11a: the audio board (03 §7) instantiates headless with one control per manifest id
## and plays through AudioManager.


func test_board_lists_every_sound() -> void:
	var scene := load("res://scenes/debug/audio_board.tscn") as PackedScene
	assert_not_null(scene)
	var board := scene.instantiate() as AudioBoard
	add_child(board)
	await await_frames(1)
	var ids := AudioManager.library.ids()
	assert_gt(ids.size(), 0)
	assert_eq(board.button_count(), ids.size(), "one control per manifest id")
	for id in ids:
		assert_true(board.has_button(id), String(id))
	board._play(&"door_slam")
	board._toggle_loop(&"static_hum", true)
	board._toggle_loop(&"crank_whine", true)
	board._set_loop_pitch(1.0)
	# M3.3 listen-check controls: the wall muffles the emitter; Echo's step follows the player's.
	board.set_wall(true)
	assert_true(board.has_wall())
	await await_physics_frames(2)
	var p := AudioManager.play_3d(&"door_open", board.get_node("%Emitter").global_position)
	assert_true(bool(p.get_meta(AudioOcclusion.META_OCCLUDED, false)), "the wall stands between them")
	board.set_wall(false)
	assert_false(board.has_wall())
	var cues: Array[String] = []
	var cb := func(text: String, _pos: Vector3) -> void: cues.append(text)
	EventBus.audio_cue.connect(cb)
	await board.echo_pair()
	EventBus.audio_cue.disconnect(cb)
	assert_eq(cues.size(), 1, "Echo's step captions; the player's own does not")
	board._stop_all()
	board.queue_free()
	await await_frames(1)
	AudioManager.stop_all()
