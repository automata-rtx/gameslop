extends TestCase
## M2.15 end to end, headless (01 §8, 14 §5, 13 §3): a Descent at depth 6 builds the
## Substrate; the Threshold in view raises A1's fifth (03 §5); walking through the door ends
## the run with cause `threshold`, cuts to white with the low tone, and routes to the ending
## (no glitch); the win, Endless and Cycle 2 are on disk before the ending plays; the ending
## runs to the Run Summary with the WIN line.

const RUN_SCENE := preload("res://scenes/run.tscn")
const TIMEOUT_S := 60.0

var _host: Node
var _prev_host: Node
var _prev_transition: Object
var _meta: MetaState


func before_all() -> void:
	_meta = GameState.meta
	GameState.meta = MetaState.new()


func after_all() -> void:
	GameState.meta = _meta


func before_each() -> void:
	_prev_host = SceneRouter.get_host()
	_prev_transition = SceneRouter.transition
	SceneRouter.transition = null
	_host = Node.new()
	_host.name = "EndingFlowHost"
	add_child(_host)
	SceneRouter.set_host(_host)


func after_each() -> void:
	for c in _host.get_children():
		c.queue_free()
	await await_frames(3)
	SceneRouter.set_host(_prev_host)
	SceneRouter.transition = _prev_transition
	_host.free()


func _until(cond: Callable, seconds: float = TIMEOUT_S) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func test_crossing_the_threshold_plays_the_ending_then_the_summary() -> void:
	GameState.meta.first_descent_done = true
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 31)
	GameState.run.depth = Tuning.RUN_FINAL_DEPTH
	GameState.run.max_depth = Tuning.RUN_FINAL_DEPTH
	var run := RUN_SCENE.instantiate() as Run
	run.capture_mouse = false
	_host.add_child(run)
	SceneRouter.set_host(_host)
	assert_true(await _until(func() -> bool: return run.phase == Run.PHASE_PLAYING), "depth 6 arrived")
	assert_eq(run.data.stratum, &"substrate")
	var door := run.exit as ThresholdDoor
	assert_not_null(door, "the Substrate's exit is the Threshold")
	if door == null:
		return
	# 03 §5: facing the door from its pocket, the fifth joins; facing away, it leaves.
	var stand := door.approach_point(3.0)
	run.player.global_position = stand
	run.player.look_at(Vector3(door.global_position.x, stand.y, door.global_position.z), Vector3.UP)
	run.player.rig.reset_pitch()
	assert_true(await _until(func() -> bool: return door.in_view, 3.0), "the Threshold is in view")
	assert_true(AudioManager.music.threshold_in_view, "MusicDirector.set_threshold_in_view(true)")
	run.player.rotate_y(PI)
	assert_true(await _until(func() -> bool: return not door.in_view, 3.0), "out of view")
	assert_false(AudioManager.music.threshold_in_view)
	# Through the door.
	run.player.global_position = door.walk_in_point()
	# Under load the router can swap the run for the ending before a frame sees PHASE_ENDED.
	var run_ref: WeakRef = weakref(run)
	var ended := func() -> bool:
		var r: Run = run_ref.get_ref() as Run
		return r == null or r.phase == Run.PHASE_ENDED
	assert_true(await _until(ended, 10.0), "the run ends at the door")
	assert_eq(GameState.last_cause(), &"threshold")
	assert_false(GameState.is_run_active())
	# 13 §3 Ending: written before the ending plays.
	var saved := SaveManager.load_meta()
	assert_true(saved.cycle_unlocked, "cycle_unlocked on disk")
	assert_true(saved.is_unlocked(&"endless"), "unlocks.endless on disk")
	assert_eq(int(saved.stats.get("wins", 0)), 1)
	assert_true(GameState.is_mode_available(Tuning.MODE_ENDLESS), "05 §8: Endless after a win")
	assert_true(await _until(func() -> bool: return SceneRouter.current_scene() is Ending, 10.0), "the ending scene")
	var ending := SceneRouter.current_scene() as Ending
	if ending == null:
		return
	ending.capture_mouse = false
	assert_eq(ending.phase, Ending.PHASE_WHITE, "it opens on the white")
	assert_approx(ending.white.color.a, 1.0, 0.001)
	assert_false(ending.skippable, "the first win plays whole")
	assert_true(AudioManager.music.mode == MusicDirector.MODE_ENDING, "MusicDirector plays the ending chord")
	ending.time_scale = 400.0
	assert_true(await _until(func() -> bool: return SceneRouter.current_scene() is RunSummary), "then the Run Summary")
	assert_eq(GameState.last_cause(), &"threshold", "the summary's cause")
	assert_contains(RunSummary.top_line(), "THRESHOLD CROSSED · DEPTH 06")
	assert_contains(RunSummary.unlock_lines(), Hud.unlock_message(&"endless"))
