class_name EndingBench
extends Node
## M2.15 bench (debug): plays the ending from a won Descent and saves the review frames:
## the white, the corridor while Coherence restores and once restored, the window bay,
## DEPTH 0 and the NOCLIP card, the credits mid-roll, the last line, and with `--variant`
## the title menu on the far wall (aimed at DESCEND); then the Run Summary.
##   tools/ci/render.sh --path game --resolution 960x540 res://scenes/debug/ending_bench.tscn -- --shots build/ending [--variant]
## Saves go to user://bench, never the player's Archive. Debug-only: no player text here.

const ENDING_SCENE := "res://scenes/ending.tscn"
const DEFAULT_DIR := "build/ending"
const CROSSING_COHERENCE := 22.0

var out_dir: String = DEFAULT_DIR
var variant: bool = false
var _host: Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i != -1 and i + 1 < args.size():
		out_dir = args[i + 1]
	variant = args.has("--variant")
	DirAccess.make_dir_recursive_absolute(_abs(out_dir))
	SaveManager.directory = "user://bench"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveManager.directory))
	_host = Node.new()
	_host.name = "Content"
	add_child(_host)
	SceneRouter.set_host(_host)
	_run.call_deferred()


func _abs(rel: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").path_join(rel)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _until(cond: Callable, seconds: float = 120.0) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _abs(out_dir).path_join(("variant_" if variant else "") + shot_name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("ending_bench: saved %s" % path)


func _won_run() -> void:
	GameState.meta = MetaState.new()
	GameState.meta.first_descent_done = true
	if variant:
		for n: NoteData in DataRegistry.notes():
			if n.id != GameState.NOTE_U6:
				GameState.meta.note_found(n.id)
		GameState.meta.earn(&"note_u6")
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 6)
	GameState.run.depth = Tuning.RUN_FINAL_DEPTH
	GameState.run.max_depth = Tuning.RUN_FINAL_DEPTH
	GameState.run.coherence = CROSSING_COHERENCE
	GameState.end_run(GameState.WIN_CAUSE)


## Places the player at `local` in the corridor, facing `target` (corridor space).
func _pose(e: Ending, local: Vector3, target: Vector3, pitch: float = 0.0) -> void:
	var p := e.corridor.to_global(local)
	e.player.global_position = p
	var t := e.corridor.to_global(target)
	e.player.look_at(Vector3(t.x, p.y, t.z), Vector3.UP)
	e.player.rig.reset_pitch()
	e.player.rig.add_pitch(pitch)


func _run() -> void:
	_won_run()
	await SceneRouter.change_to(ENDING_SCENE, false)
	var e := SceneRouter.current_scene() as Ending
	e.capture_mouse = false
	await _wait(0.2)
	await _shot("ending_white")
	await _until(func() -> bool: return e.phase == Ending.PHASE_FADE or e.phase == Ending.PHASE_WALK)
	await _until(func() -> bool: return e.restore_t >= Tuning.ENDING_FADE_IN_TIME + 0.3)
	await _shot("ending_restoring")
	e.time_scale = 8.0
	await _until(func() -> bool: return e.restore_t >= Tuning.COHERENCE_ENDING_RESTORE_TIME + 0.5)
	e.time_scale = 0.0
	await _wait(0.3)
	await _shot("ending_corridor")
	_pose(e, Vector3(-0.4, 0.0, e.corridor.far_z + 9.0), Vector3(0.2, 0.0, e.corridor.far_z), -0.08)
	await _wait(0.5)
	await _shot("ending_window")
	if variant:
		await _variant_shots(e)
	_pose(e, Vector3(0.3, 0.0, e.corridor.far_z + 3.5), Vector3(0.0, 0.0, e.corridor.far_z))
	e.time_scale = 1.0
	await _until(func() -> bool: return e.card.visible and not e.card_label.is_typing())
	e.time_scale = 0.0
	await _wait(0.3)
	await _shot("ending_card")
	e.time_scale = 1.0
	await _until(func() -> bool: return e.phase == Ending.PHASE_CREDITS)
	e.time_scale = 0.0
	e.credits.scrolled = 1400.0
	e.credits.advance(0.0)
	e.credits.running = true
	e.time_scale = 0.001
	await _wait(1.6)
	await _shot("ending_credits")
	e.credits.scrolled = e.credits.stop_scroll() - 1.0
	e.time_scale = 1.0
	await _until(func() -> bool: return e.credits.holding >= 0.5)
	await _shot("ending_thanks")
	e.time_scale = 50.0
	await _until(func() -> bool: return SceneRouter.current_scene() is RunSummary)
	await _wait(4.0)
	await _shot("ending_summary")
	get_tree().quit(0)


func _variant_shots(e: Ending) -> void:
	var menu := e.corridor.descend_label.position
	_pose(e, Vector3(menu.x + 0.5, 0.0, e.corridor.far_z + 1.6), Vector3(menu.x + 0.5, 0.0, e.corridor.far_z), 0.12)
	await _wait(0.8)
	await _shot("ending_variant_menu")
