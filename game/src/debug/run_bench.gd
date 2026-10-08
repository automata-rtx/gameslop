class_name RunBench
extends Node
## M1.9 bench (debug): drives the run flow and saves the review frames: the title, the exit
## room before and after the breaker, the Landing panel, and the run summary.
##   tools/ci/render.sh --path game --resolution 960x540 res://scenes/debug/run_bench.tscn -- --shots build/run
## Debug-only: no player text lives here.

const TITLE_SCENE := "res://scenes/title.tscn"
const RUN_SCENE := "res://scenes/run.tscn"
const DEFAULT_DIR := "build/run"
const RUN_SEED := 4

var out_dir: String = DEFAULT_DIR
var _host: Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i != -1 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join("..").path_join(out_dir))
	_host = Node.new()
	_host.name = "Content"
	add_child(_host)
	SceneRouter.set_host(_host)
	_run.call_deferred()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _until(cond: Callable, seconds: float = 120.0) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://").path_join("..").path_join(out_dir).path_join(name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("run_bench: saved %s" % path)


## `--landing-only`: the Landing cabin alone under the Halls environment (02 §7 cabin look,
## the 2x item panel): from the player's eye, and from the side facing the door.
func _landing_only() -> void:
	var world := WorldEnvironment.new()
	world.environment = StratumEnvironment.build(load("res://data/strata/halls.tres") as StratumData)
	add_child(world)
	var landing := (load("res://scenes/landing.tscn") as PackedScene).instantiate() as Landing
	landing.landing_time = 600.0
	add_child(landing)
	var cam := Camera3D.new()
	cam.fov = 75.0
	add_child(cam)
	cam.global_transform = landing.player_transform().translated(Vector3(0.0, Tuning.PLAYER_CAMERA_HEIGHT, 0.0))
	cam.make_current()
	landing.begin(cam, [&"glowstick", &"chalk"] as Array[StringName], true)
	await _wait(2.0)
	await _shot("landing_cabin")
	cam.look_at_from_position(Vector3(0.6, 1.5, 0.7), Vector3(Landing.DOOR_X, 1.2, -1.0))
	await _wait(1.0)
	await _shot("landing_door")
	get_tree().quit(0)


func _run() -> void:
	if OS.get_cmdline_user_args().has("--landing-only"):
		await _landing_only()
		return
	await SceneRouter.change_to(TITLE_SCENE)
	await _wait(0.5)
	await _shot("title")
	GameState.meta.first_descent_done = false
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", RUN_SEED)
	await SceneRouter.change_to(RUN_SCENE)
	var run := SceneRouter.current_scene() as Run
	run.capture_mouse = false
	await _until(func() -> bool: return run.phase == Run.PHASE_PLAYING and run.level.is_ready())
	var exit := run.exit
	var stand := exit.to_global(Vector3(0.0, 0.0, -4.0))
	run.player.global_position = stand
	run.player.look_at(Vector3(exit.global_position.x, stand.y, exit.global_position.z), Vector3.UP)
	run.player.rig.reset_pitch()
	run.level.light_pool.reevaluate()
	await _wait(1.5)
	await _shot("exit_before")
	run.breaker.throw_breaker()
	await _until(func() -> bool: return exit.is_open(), 30.0)
	await _wait(2.0)
	await _shot("exit_after")
	run.player.global_position = exit.to_global(Vector3(0.0, 0.1, -0.45))
	await _until(func() -> bool: return run.phase == Run.PHASE_LANDING)
	await _wait(2.0)
	await _shot("landing")
	await _until(func() -> bool: return run.phase == Run.PHASE_PLAYING)
	await _wait(1.0)
	await _shot("arrival")
	run.player.apply_coherence(-1000.0, &"still")
	await _wait(0.6)
	await _shot("dissolve")
	await _until(func() -> bool: return SceneRouter.current_scene() is RunSummary)
	await _wait(4.0)
	await _shot("summary")
	get_tree().quit(0)
