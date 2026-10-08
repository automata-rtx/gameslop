class_name SimBot
extends RefCounted
## The orchestrator's simulated playtest (M1.8): a scripted bot plays depth 1 of a real
## run (run.tscn, the Director and its errors active) by walking the grid path to the
## breaker (when the exit is Powered), throwing it, then walking into the exit. It walks,
## and sprints only while a hunter chases within 15 m. Headless; no rendering.
## Used by `sim_run.gd` (CLI) and `test_sim_run.gd` (one seed in the gate).
##
## Result keys: seed, reached (bool), dissolved (bool), time_s (game seconds on the level),
## contacts, refused, phases (visited, in order, deduplicated runs), max_intensity,
## notices, unsticks, coherence, roster, skipped, telemetry_rows.

const RUN_SCENE := "res://scenes/run.tscn"
const ARRIVE_DIST := 0.5
const BREAKER_REACH := 2.2
const STUCK_WINDOW := 2.0
const STUCK_MIN_MOVE := 0.3
const SPRINT_CHASE_DIST := 15.0
const REPATH_INTERVAL := 2.0

var tree: SceneTree
var host: Node
var run: Run
var max_seconds: float = 600.0
var csv_path: String = ""

var _waypoints: Array[Vector3] = []
var _goal: Vector3 = Vector3.INF
var _repath_left: float = 0.0
var _stuck_left: float = STUCK_WINDOW
var _stuck_from: Vector3 = Vector3.ZERO
var _unsticks: int = 0


## Plays one seed (first Descent off, so depth 1 carries a hunter). Returns the result.
func play(run_seed: int) -> Dictionary:
	var meta := GameState.meta
	GameState.meta = MetaState.new()
	GameState.meta.first_descent_done = true
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", run_seed)
	run = (load(RUN_SCENE) as PackedScene).instantiate() as Run
	run.capture_mouse = false
	run.landing_time = 0.5
	host.add_child(run)
	var waited := 0
	while run.phase != Run.PHASE_PLAYING and waited < 3000:
		await tree.process_frame
		waited += 1
	var level := run.level
	var director := level.find_child("Director", true, false) as Director if level != null else null
	var result := {&"seed": run_seed, &"reached": false, &"dissolved": false, &"time_s": 0.0}
	if director == null:
		result[&"error"] = "no Director on the level"
		await _teardown(meta)
		return result
	var t := 0.0
	var max_i := 0.0
	while t < max_seconds:
		await tree.physics_frame
		var dt := tree.root.get_physics_process_delta_time()
		t += dt
		max_i = maxf(max_i, director.intensity)
		if run.phase == Run.PHASE_DISSOLVING or run.phase == Run.PHASE_ENDED:
			result[&"dissolved"] = true
			break
		if run.phase != Run.PHASE_PLAYING:
			result[&"reached"] = true
			break
		_steer(dt)
	PlayerFixture.release_all()
	result[&"time_s"] = snappedf(t, 0.1)
	result[&"contacts"] = director.contacts
	result[&"refused"] = director.refused
	result[&"phases"] = _runs(director.pacing.history)
	result[&"max_intensity"] = snappedf(max_i, 0.01)
	result[&"notices"] = GameState.run.encounters.duplicate()
	result[&"unsticks"] = _unsticks
	result[&"coherence"] = snappedf(run.player.coherence, 0.1)
	result[&"roster"] = director.roster.duplicate()
	result[&"skipped"] = director.skipped.duplicate()
	result[&"telemetry_rows"] = director.telemetry.size()
	if not csv_path.is_empty():
		director.telemetry.dump_csv(csv_path)
	await _teardown(meta)
	return result


func _teardown(meta: MetaState) -> void:
	PlayerFixture.release_all()
	if run != null and is_instance_valid(run):
		run.queue_free()
	for i in 3:
		await tree.process_frame
	if GameState.is_run_active():
		GameState.end_run(&"abandon")
	GameState.meta = meta


static func _runs(history: Array[StringName]) -> Array[StringName]:
	var out: Array[StringName] = []
	for p in history:
		if out.is_empty() or out[out.size() - 1] != p:
			out.append(p)
	return out


# --- the bot -------------------------------------------------------------------------------

func _steer(dt: float) -> void:
	var p := run.player
	var grid := run.data.grid
	var goal := _current_goal()
	if run.breaker != null and not run.breaker.is_thrown \
			and DirectorSpawn.flat_dist(p.global_position, run.breaker.global_position) < BREAKER_REACH:
		run.breaker.throw_breaker()
	_repath_left -= dt
	if goal != _goal or _repath_left <= 0.0 or _waypoints.is_empty():
		_goal = goal
		_repath_left = REPATH_INTERVAL
		_waypoints.clear()
		for c in ErrorStatic.cell_path(grid, grid.cell_of(p.global_position), grid.cell_of(goal)):
			_waypoints.append(grid.world_of(c))
		_waypoints.append(goal)
	while not _waypoints.is_empty() and DirectorSpawn.flat_dist(p.global_position, _waypoints[0]) < ARRIVE_DIST:
		_waypoints.remove_at(0)
	var waiting := run.exit != null and goal == _exit_point() and not run.exit.is_open()
	if _waypoints.is_empty() or (waiting and _waypoints.size() <= 1):
		Input.action_release(&"move_forward")
		_stuck_left = STUCK_WINDOW
		_stuck_from = p.global_position
		return
	var w := _waypoints[0]
	var to := Vector3(w.x - p.global_position.x, 0.0, w.z - p.global_position.z)
	p.rotation = Vector3(0.0, atan2(-to.x, -to.z), 0.0)
	Input.action_press(&"move_forward")
	if _chased_near():
		Input.action_press(&"sprint")
	else:
		Input.action_release(&"sprint")
	_stuck_left -= dt
	if _stuck_left <= 0.0:
		if DirectorSpawn.flat_dist(p.global_position, _stuck_from) < STUCK_MIN_MOVE:
			# A closed closet door or a corner: step onto the next waypoint (counted).
			p.global_position = w + Vector3.UP * 0.05
			_unsticks += 1
		_stuck_left = STUCK_WINDOW
		_stuck_from = p.global_position


func _current_goal() -> Vector3:
	if run.breaker != null and not run.breaker.is_thrown and run.data.breaker_cell != LevelData.NO_CELL:
		return run.data.grid.world_of(run.data.breaker_cell)
	return _exit_point()


func _exit_point() -> Vector3:
	if run.exit != null:
		return run.exit.to_global(Vector3(0.0, 0.1, -0.45))
	return run.data.grid.world_of(run.data.exit_cell)


func _chased_near() -> bool:
	for e in tree.get_nodes_in_group(ErrorBase.GROUP):
		var err := e as ErrorBase
		if err != null and DirectorRules.is_chasing_state(err.state) and err.distance_to_player() < SPRINT_CHASE_DIST:
			return true
	return false
