extends TestCase
## M3.5, 14 §10 "Memory growth per level: 0 after 10 levels (no leaks: queue_free and
## pools)". One Descent dropped through level after level (the run's own transition: the
## old level freed, the next one built, the Director and its errors begun): after each
## arrival the object count, the orphan nodes (alive but in no tree: a leak) and the static
## memory are read. A level and the same stratum one Cycle later (depth d and d + 6) must
## cost the same; orphans must not pile up. The gate drops through 8 levels; the checkpoint
## run through 13 (every stratum twice past the first Cycle, so first-use caches are warm).

const RUN_SCENE := preload("res://scenes/run.tscn")
const RUN_SEED := 4
const TIMEOUT_S := 60.0
const GATE_LEVELS := 8
const FULL_LEVELS := 13
## Objects a level may differ from the same stratum one Cycle later: Cycle 2's extra Static
## (its nodes, loops and senses) and the level's own generation differences.
const OBJECT_SLACK := 600
## MB of static memory the same comparison may differ by (allocator pages, script caches).
const MEMORY_SLACK_MB := 8.0

var _host: Node
var _meta: MetaState
var _prev_host: Node
var _prev_transition: Object


func before_all() -> void:
	_meta = GameState.meta
	GameState.meta = MetaState.new()
	GameState.meta.first_descent_done = true
	_prev_host = SceneRouter.get_host()
	_prev_transition = SceneRouter.transition
	SceneRouter.transition = null
	_host = Node.new()
	_host.name = "MemoryHost"
	add_child(_host)
	SceneRouter.set_host(_host)


func after_all() -> void:
	for c in _host.get_children():
		c.queue_free()
	await await_frames(3)
	if GameState.is_run_active():
		GameState.end_run(&"abandon")
	SceneRouter.set_host(_prev_host)
	SceneRouter.transition = _prev_transition
	GameState.meta = _meta
	_host.free()


func _until(cond: Callable, seconds: float = TIMEOUT_S) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _reading(run: Run) -> Dictionary:
	return {
		&"depth": GameState.run.depth, &"stratum": run.data.stratum,
		&"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		&"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		&"memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		&"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
	}


func test_levels_do_not_leak() -> void:
	var levels := FULL_LEVELS if full_run() else GATE_LEVELS
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", RUN_SEED)
	var run := RUN_SCENE.instantiate() as Run
	run.capture_mouse = false
	run.drop_fall_time = 0.2
	run.landing_time = 0.3
	_host.add_child(run)
	assert_true(await _until(func() -> bool: return run.phase == Run.PHASE_PLAYING), "depth 1 playable")
	var readings: Array[Dictionary] = []
	for i in levels:
		# Let the level settle (deferred frees, the Director's first ticks) before reading.
		await await_physics_frames(30)
		readings.append(_reading(run))
		print("  # depth %d %s: objects %d, orphans %d, nodes %d, static %.1f MB" % [readings[i][&"depth"],
			readings[i][&"stratum"], readings[i][&"objects"], readings[i][&"orphans"], readings[i][&"nodes"],
			readings[i][&"memory_mb"]])
		if i == levels - 1:
			break
		run.commit_drop()
		var want := GameState.run.depth
		if not await _until(func() -> bool: return run.phase == Run.PHASE_PLAYING and run.data != null and run.data.depth == want):
			fail("depth %d never became playable" % want)
			return
	# Orphans: whatever one level leaves behind would pile up level after level.
	var first_orphans := int(readings[1][&"orphans"])
	assert_budget(float(int(readings[levels - 1][&"orphans"]) - first_orphans), 1.0,
		"orphan nodes gained from depth 2 to depth %d" % levels)
	# The same stratum one Cycle later costs the same (depth 1 is skipped: first-use caches).
	for i in range(1, levels - Tuning.RUN_CYCLE_LENGTH):
		var a: Dictionary = readings[i]
		var b: Dictionary = readings[i + Tuning.RUN_CYCLE_LENGTH]
		assert_eq(a[&"stratum"], b[&"stratum"], "the Cycle repeats the order")
		assert_budget(float(int(b[&"objects"]) - int(a[&"objects"])), float(OBJECT_SLACK),
			"objects at depth %d over depth %d (%s)" % [b[&"depth"], a[&"depth"], a[&"stratum"]])
		assert_budget(float(b[&"memory_mb"]) - float(a[&"memory_mb"]), MEMORY_SLACK_MB,
			"static MB at depth %d over depth %d (%s)" % [b[&"depth"], a[&"depth"], a[&"stratum"]])
