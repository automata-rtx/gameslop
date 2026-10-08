class_name DirectLevel
extends Node
## 14 §9 debug launch straight into a level: `--seed N --depth D --stratum S`. Generates
## on a worker thread, builds level.tscn, spawns the player at the spawn (walkable as soon
## as the geometry is built) and applies the stratum environment. With `--shots <dir>` it
## captures the verification frames (LevelShots) instead of spawning the player, then
## quits. main.gd's --smoke uses it headless with `capture_mouse = false`.

signal geometry_ready
signal built

const LEVEL_SCENE := "res://scenes/level.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const DEFAULT_SEED := 1

var stratum: StringName = Tuning.STRATUM_DEPTH1
var depth: int = 1
var run_seed: int = DEFAULT_SEED
var shots_dir: String = ""
var capture_mouse: bool = true

var data: LevelData
var level: Level
var player: Player
var director: Director
var generate_ms: float = 0.0


static func from_args(args: CliArgs) -> DirectLevel:
	var d := DirectLevel.new()
	d.name = "DirectLevel"
	if args.stratum != &"":
		d.stratum = args.stratum
	if args.depth > 0:
		d.depth = args.depth
	if args.has_seed:
		d.run_seed = args.run_seed
	d.shots_dir = args.shots_dir
	return d


func _ready() -> void:
	add_to_group(DebugOverlay.GROUP)
	_run.call_deferred()


## Lines for the F3 overlay (14 §9).
func debug_info() -> Dictionary:
	var info := {"seed": run_seed, "stratum": "%s depth %d" % [stratum, depth]}
	if player != null and data != null and data.grid != null:
		info["cell"] = data.grid.cell_of(player.global_position)
		info["coherence"] = "%.1f" % player.coherence
	if level != null and level.light_pool != null:
		info["lights"] = level.light_pool.active_light_count()
	return info


func _run() -> void:
	# 07 §1: generation is data only, on a worker thread.
	var t0 := Time.get_ticks_usec()
	var task := WorkerThreadPool.add_task(_generate, false, "LevelGenerator")
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	generate_ms = (Time.get_ticks_usec() - t0) / 1000.0
	if data == null:
		push_error("DirectLevel: no grammar for stratum %s" % stratum)
		return
	level = (load(LEVEL_SCENE) as PackedScene).instantiate() as Level
	add_child(level)
	level.built.connect(func() -> void: built.emit())
	level.begin(data)
	await level.geometry_ready
	if shots_dir.is_empty():
		_spawn_player()
		# M1.8: errors and pacing on direct launches too (the run does the same per level).
		director = Director.new()
		level.add_child(director)
		director.begin(level, player, Tuning.RUN_ARRIVE_START)
	geometry_ready.emit()
	if not shots_dir.is_empty():
		if not level.is_ready():
			await level.built
		var shots := LevelShots.new()
		shots.name = "LevelShots"
		add_child(shots)
		await shots.capture(level, shots_dir)
		get_tree().quit(0)


func _generate() -> void:
	data = LevelGenerator.generate(stratum, depth, run_seed, false, 1 if depth <= 6 else 2)


func _spawn_player() -> void:
	player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	level.add_child(player)
	level.attach_player(player, player.rig.camera)
	player.rig.camera.make_current()
	if capture_mouse and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not capture_mouse or player == null:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed(&"pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
