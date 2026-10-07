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
	board._stop_all()
	board.queue_free()
	await await_frames(1)
	AudioManager.stop_all()
