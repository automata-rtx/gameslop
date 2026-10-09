class_name PerfBench
extends Node
## M3.5 performance bench (14 §10, 00 §9: Garage and Server with the Director at peak).
## A real run (run.tscn: player, HUD, Director, the level's roster) at depth 11, Cycle 2's
## depth 5: the largest level (580 cells), the full roster (three Statics, Still, Echo,
## Flicker) and the Cycle 2 aggression. Then the worst case is held on purpose: every hunter
## awake (Still and Echo placed 10 m of walking from the player, then sent to Search at the
## player every 2 s while beyond 12 m and not already searching), the Director
## forced to Peak (its chaser cap still applies), the power wave re-igniting every dark
## fixture every 8 s, the player sprinting with the flashlight on, back and forth along the
## first 14 cells of the critical path (Echo hears the steps, Flicker hops between groups by
## itself), every contact refused (the chase never ends in Satiated), Coherence held near 40
## (topped up from 25).
## PerfProbe records every frame; `result` holds the summary.
##   $GODOT_BIN --headless --path game res://scenes/debug/perf_bench.tscn -- --stratum server --seconds 20 --out build/perf/server.json
##   tools/ci/render.sh --path game --resolution 1920x1080 res://scenes/debug/perf_bench.tscn -- --stratum garage --shots build/perf
## Options: --stratum garage|server (default server), --seconds N (recorded, default 20),
## --warmup N (default 3), --depth D (default 11), --fps N (frame cap, default 60, 0 uncapped),
## --out <json> and --shots <dir>
## (relative to the repository). The quality settings are the current ones (default Medium).
## Debug-only: no player text lives here.

signal finished(result: Dictionary)

const RUN_SCENE := "res://scenes/run.tscn"
const DEFAULT_DEPTH := 11
const HINT_EVERY := 2.0
## Hunters nearer than this are left to their own senses (a pull would reset their Search).
const PULL_DIST := 12.0
## The player sprints back and forth along this many cells of the critical path (PerfWalk).
const ROUTE_CELLS := 14
## Still and Echo are placed this many cells (2 m) of walking from the player at the start.
const PLACE_CELLS := 5
## A Search younger than this is left to run (a pull restarts it).
const PULL_SEARCH_TIME := 12.0
const WAVE_EVERY := 8.0
## Peak play is low-Coherence play: the bench holds it near 40 (the post stack graded, the
## static bed rendering, 03 §4), topping it up from 25 so the run never dissolves.
const COHERENCE_HOLD := 40.0
const COHERENCE_FLOOR := 25.0
const SOURCE_BENCH := &"perf_bench"
const SAVE_DIR := "user://perf_bench"
## The frame cap while measuring: one physics step per frame, as on a 60 Hz display.
const BENCH_FPS := 60

var stratum: StringName = Tuning.STRATUM_SERVER
var depth: int = DEFAULT_DEPTH
var seconds: float = 20.0
var fps: int = BENCH_FPS
var warmup: float = 3.0
var out_path: String = ""
var shots_dir: String = ""
## Quit when done (true when the bench is the main scene).
var standalone: bool = false

var run: Run
var director: Director
var probe: PerfProbe
var result: Dictionary = {}

var _walk: PerfWalk
var _hint_left: float = 0.0
var _wave_left: float = 0.0
var _waves: int = 0
var _states: Dictionary = {}
var _chasing_frames: PackedInt32Array = PackedInt32Array()
var _saved_meta: MetaState
var _saved_dir: String = ""
var _saved_fps: int = 0
var _driving: bool = false


func _ready() -> void:
	standalone = get_tree().current_scene == self
	if standalone:
		_read_args(OS.get_cmdline_user_args())
		_main.call_deferred()


func _read_args(args: PackedStringArray) -> void:
	for i in args.size() - 1:
		var v := args[i + 1]
		match args[i]:
			"--stratum": stratum = StringName(v)
			"--seconds": seconds = float(v)
			"--warmup": warmup = float(v)
			"--depth": depth = int(v)
			"--out": out_path = v
			"--fps": fps = int(v)
			"--shots": shots_dir = v


## The first run seed whose strata order puts `stratum` at `depth` (05 §2).
static func seed_for(p_stratum: StringName, p_depth: int) -> int:
	for s in range(1, 5000):
		var order := GameState.strata_order_for(s)
		if order[posmod(p_depth - 1, Tuning.RUN_CYCLE_LENGTH)] == p_stratum:
			return s
	return 1


## Runs the bench; emits `finished` and returns the result.
func measure() -> Dictionary:
	_saved_meta = GameState.meta
	_saved_dir = SaveManager.directory
	_saved_fps = Engine.max_fps
	SaveManager.directory = SAVE_DIR
	GameState.meta = MetaState.new()
	GameState.meta.first_descent_done = true
	var run_seed := seed_for(stratum, depth)
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", run_seed)
	GameState.run.depth = depth
	GameState.run.max_depth = depth
	run = (load(RUN_SCENE) as PackedScene).instantiate() as Run
	run.capture_mouse = false
	var t_build := Time.get_ticks_msec()
	add_child(run)
	await _until(func() -> bool: return run.phase == Run.PHASE_PLAYING, 120.0)
	if run.phase != Run.PHASE_PLAYING or run.level == null:
		push_error("PerfBench: the run never reached a playable level")
		result = {&"error": "no level"}
		await _teardown()
		finished.emit(result)
		return result
	var build := {&"to_playing_s": (Time.get_ticks_msec() - t_build) / 1000.0}
	director = run.level.find_child("Director", true, false) as Director if run.level != null else null
	await _until(func() -> bool: return run.level.is_ready() and _nav_ready(), 60.0)
	build.merge(build_stats(run.level.builder))
	_walk = PerfWalk.new(run.player, run.data, ROUTE_CELLS)
	_peak_setup()
	Engine.max_fps = fps
	probe = PerfProbe.new()
	probe.name = "PerfProbe"
	probe.level = run.level
	probe.roots = _roots()
	add_child(probe)
	_driving = true
	await _wait(warmup)
	probe.start()
	_states.clear()
	_chasing_frames.clear()
	await _wait(seconds)
	if not shots_dir.is_empty():
		await _shot("perf_%s" % stratum)
	probe.stop()
	_driving = false
	result = _result(run_seed, build)
	await _teardown()
	if not out_path.is_empty():
		_write_json(out_path, result)
	finished.emit(result)
	return result


## 14 §10 level build slice and navigation bake readings of a finished build.
static func build_stats(b: LevelBuilder) -> Dictionary:
	return {
		&"slice_p90_ms": PerfProbe.percentile(b.slice_ms, 0.9), &"slice_max_ms": b.max_slice_ms,
		&"slice_mean_ms": PerfProbe.stats(b.slice_ms)[&"mean"], &"bake_ms": b.bake_ms,
		&"slowest_job": String(b.slowest_job), &"slowest_job_ms": b.slowest_job_ms, &"slices": b.slices,
	}


func _main() -> void:
	await measure()
	print("perf_bench %s" % JSON.stringify(result))
	if standalone:
		get_tree().quit(0)


func _nav_ready() -> bool:
	if director == null:
		return true
	for e in director.errors:
		if is_instance_valid(e) and not e.navigation_ready:
			return false
	return true


func _roots() -> Dictionary:
	var tree := get_tree()
	return {
		&"level": func() -> Array: return [run.level],
		&"player": func() -> Array: return [run.player],
		&"director": func() -> Array: return tree.get_nodes_in_group(Director.GROUP),
		&"errors": func() -> Array: return tree.get_nodes_in_group(ErrorBase.GROUP),
		&"light_pool": func() -> Array: return [run.level.light_pool] + tree.get_nodes_in_group(&"fixtures"),
		&"audio": func() -> Array: return [AudioManager],
		&"renderer": func() -> Array: return [CoherenceRenderer],
		&"hud": func() -> Array: return [run.hud],
	}


# --- the peak --------------------------------------------------------------------------------

func _peak_setup() -> void:
	var p := run.player
	p.flashlight.set_on(true, true)
	p.apply_coherence(COHERENCE_HOLD - p.coherence, SOURCE_BENCH)
	var near := _cell_at_walk(PLACE_CELLS)
	for e in _hunters():
		# The walkers start 10 m (walking) from the beat, so the chase starts in the window.
		if near != LevelData.NO_CELL and (e is ErrorStill or e is ErrorEcho):
			e.call(&"place_at", run.data.grid.world_of(near))
		_pull(e)
	_force_peak()
	_wave_left = 1.0
	_hint_left = HINT_EVERY


## The first walkable cell (index order) `cells` steps from the player's cell.
func _cell_at_walk(cells: int) -> Vector2i:
	var g := run.data.grid
	var field := g.distance_field(g.cell_of(run.player.global_position))
	for i in field.size():
		if field[i] == cells:
			return g.cell_at(i)
	return LevelData.NO_CELL


## Wakes a hunter and, unless it already chases or the Director sent it away (Satiated, the
## Peak cap), sends it to Search from the player's position, where its senses take over.
## Flicker keeps its own habitat logic (it hops toward the player by itself).
func _pull(e: ErrorBase) -> void:
	# Contacts are refused, so a chase never ends in Satiated: the hunters stay on the player.
	e.contact_request = _refuse_contact
	if e.is_dormant():
		e.wake()
	if e is ErrorFlicker or DirectorRules.is_chasing_state(e.state) or e.state == Tuning.ERROR_STATE_SATIATED \
			or e.distance_to_player() < PULL_DIST or (e.state == Tuning.ERROR_STATE_SEARCH and e.state_time < PULL_SEARCH_TIME):
		return
	e.start_search(run.player.global_position)


func _refuse_contact(_e: Node) -> bool:
	return false


func _hunters() -> Array[ErrorBase]:
	var out: Array[ErrorBase] = []
	if director == null:
		return out
	for e in director.errors:
		if is_instance_valid(e) and DirectorRules.is_hunter(e.error_id):
			out.append(e)
	return out


func _force_peak() -> void:
	if director == null or director.pacing.phase == DirectorPacing.PEAK:
		return
	director.pacing._enter(DirectorPacing.PEAK)
	director.pacing.intensity = maxf(director.pacing.intensity, Tuning.DIRECTOR_WAKE_INTENSITY)
	EventBus.director_phase.emit(DirectorPacing.PEAK)


## 02 §6 breaker: every group but Flicker's goes dark, then lights in the wave from the player.
func _power_wave() -> void:
	var pool := run.level.light_pool
	var keep := -1
	for e in _hunters():
		if e is ErrorFlicker:
			keep = (e as ErrorFlicker).current_group
	for g in pool.group_ids():
		if int(g) != keep:
			for f in pool.group(int(g)):
				f.set_powered(false)
	pool.reevaluate()
	RunLevelSetup.run_power_wave(run.level, run.data, null, run.player.global_position)
	_waves += 1


func _physics_process(delta: float) -> void:
	if not _driving or run == null or not is_instance_valid(run) or run.phase != Run.PHASE_PLAYING:
		return
	var t0 := Time.get_ticks_usec()
	_drive_peak(delta)
	if probe != null:
		probe.harness_ms += (Time.get_ticks_usec() - t0) / 1000.0


func _drive_peak(delta: float) -> void:
	var p := run.player
	if p.coherence < COHERENCE_FLOOR:
		p.apply_coherence(COHERENCE_HOLD - p.coherence, SOURCE_BENCH)
	_force_peak()
	_hint_left -= delta
	if _hint_left <= 0.0:
		_hint_left = HINT_EVERY
		for e in _hunters():
			_pull(e)
	_wave_left -= delta
	if _wave_left <= 0.0:
		_wave_left = WAVE_EVERY
		_power_wave()
	_walk.drive(delta)
	if probe != null and probe.recording:
		var chasing := 0
		for e in _hunters():
			var sk := "%s:%s" % [e.error_id, e.state]
			_states[sk] = int(_states.get(sk, 0)) + 1
			if DirectorRules.is_chasing_state(e.state):
				chasing += 1
		_chasing_frames.append(chasing)


# --- results ---------------------------------------------------------------------------------

func _result(run_seed: int, build: Dictionary) -> Dictionary:
	var s := probe.summary()
	var chasing := PackedFloat32Array()
	var two := 0
	for c in _chasing_frames:
		chasing.append(c)
		if c >= 2:
			two += 1
	var roster: Array = []
	if director != null:
		for e in director.errors:
			if is_instance_valid(e):
				roster.append(String(e.error_id))
	return {
		&"stratum": String(stratum), &"depth": depth, &"seed": run_seed, &"pool_size": run.level.light_pool.pool_size,
		&"roster": roster, &"build": build, &"metrics": s, &"waves": _waves,
		&"hunter_states": _states, &"chasing": PerfProbe.stats(chasing),
		&"two_chasing_share": float(two) / maxf(1.0, _chasing_frames.size()),
		&"fixtures": run.level.light_pool.fixtures().size(),
		&"cells": run.data.grid.walkable_count(),
		&"renderer": RenderingServer.get_current_rendering_method(),
		&"headless": DisplayServer.get_name() == "headless",
	}


func _teardown() -> void:
	PerfWalk.release()
	Engine.max_fps = _saved_fps
	if probe != null:
		probe.queue_free()
		probe = null
	if run != null and is_instance_valid(run):
		run.queue_free()
	for i in 3:
		await get_tree().process_frame
	if GameState.is_run_active():
		GameState.end_run(&"abandon")
	GameState.meta = _saved_meta
	SaveManager.directory = _saved_dir


func _write_json(path: String, data: Dictionary) -> void:
	var abs_path := ProjectSettings.globalize_path("res://").path_join("..").path_join(path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://").path_join("..").path_join(shots_dir)
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))


func _wait(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame


func _until(cond: Callable, s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await get_tree().process_frame
