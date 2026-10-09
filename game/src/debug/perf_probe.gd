class_name PerfProbe
extends Node
## 14 §10 per-frame CPU readings by system (M3.5), headless or rendered. Script time is
## measured by bracketing: every node of a system gets the same process and physics
## priority, and marker nodes at the priorities between the systems stamp the clock as the
## tree reaches them, so a system's time is the gap between its two markers (nothing is
## re-implemented or called twice; the engine still decides what processes). Nodes nobody
## claimed keep priority 0 and land in `other`. Priorities change only the call order
## within a frame, which no system relies on (signals up, calls down).
## Readings per frame: script ms per system and total, physics (the engine step, Jolt),
## navigation, nodes, lights, shadows, draw calls and objects (0 headless), memory.

## The systems, in the order their bands run and are claimed: a later claim wins, so
## `level` keeps what the others do not take (props, interactables, pickups, the builder).
const SYSTEMS: Array[StringName] = [&"level", &"player", &"director", &"errors", &"light_pool", &"audio", &"renderer", &"hud"]
const BAND_BASE := 1000
const FIRST := -1000000
const LAST := 1000000
const COUNT_EVERY := 10
const ERROR_IDS: Array[StringName] = [&"static", &"still", &"echo", &"flicker", &"null"]

## System id -> Callable returning Array[Node] (the roots; their subtrees are claimed).
var roots: Dictionary = {}
## Frames recorded: one Dictionary per idle frame.
var frames: Array[Dictionary] = []
var recording: bool = false
## Milliseconds a harness (the bench driving the peak) spent this frame in its own physics
## step; taken out of `other` and `script`, reported as `harness`.
var harness_ms: float = 0.0
## The level root for the node count (14 §10 nodes in a level) and the light counts.
var level: Level

var _idle_marks: Array[_Mark] = []
var _phys_marks: Array[_Mark] = []
var _phys_ms: Dictionary = {}
var _phys_script_ms: float = 0.0
var _phys_ticks: int = 0
var _claim_left: float = 0.0
var _counts: Dictionary = {}
var _phys_end: int = 0
var _step_ms: float = 0.0


class _Mark extends Node:
	var stamp: int = 0
	var physics: bool = false
	## FIRST marks report to the probe (the end of the engine's physics step).
	var on_stamp: Callable

	func _init(p_physics: bool, priority: int) -> void:
		physics = p_physics
		process_mode = Node.PROCESS_MODE_ALWAYS
		if physics:
			process_physics_priority = priority
			set_physics_process(true)
		else:
			process_priority = priority
			set_process(true)

	func _process(_d: float) -> void:
		stamp = Time.get_ticks_usec()
		if on_stamp.is_valid():
			on_stamp.call(stamp)

	func _physics_process(_d: float) -> void:
		stamp = Time.get_ticks_usec()
		if on_stamp.is_valid():
			on_stamp.call(stamp)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Marks: [first, before band 0, before band 1, ..., after the last band, last].
	for physics in [false, true]:
		var marks: Array[_Mark] = []
		marks.append(_Mark.new(physics, FIRST))
		marks[0].on_stamp = _on_first
		for k in SYSTEMS.size() + 1:
			marks.append(_Mark.new(physics, BAND_BASE + 2 * k))
		marks.append(_Mark.new(physics, LAST))
		for m in marks:
			add_child(m)
		if physics:
			_phys_marks = marks
		else:
			_idle_marks = marks
	# The probe reads after the last mark of each loop.
	process_priority = LAST + 1
	process_physics_priority = LAST + 1
	if DisplayServer.get_name() != "headless":
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


## Physics engine time: from the end of the scene's physics callbacks to the next scene
## callback (the next tick's or the idle step's first mark). In Main::iteration that gap
## is the navigation server's physics sync, the message queue and the physics server step
## (Jolt), then the next step's query flush (area and body signals).
func _on_first(stamp: int) -> void:
	if _phys_end > 0 and recording:
		_step_ms += (stamp - _phys_end) / 1000.0
	_phys_end = 0


## Gives every node under the system's roots the system's band (call again after spawns;
## the probe re-claims once a second by itself).
func claim() -> void:
	for k in SYSTEMS.size():
		var id := SYSTEMS[k]
		if not roots.has(id):
			continue
		var prio := BAND_BASE + 2 * k + 1
		for r: Node in (roots[id] as Callable).call():
			if is_instance_valid(r):
				_claim_tree(r, prio)


func _claim_tree(n: Node, prio: int) -> void:
	# A node that orders itself on purpose keeps its place (AudioMixGuard runs last, RCA1).
	if _own_order(n.process_priority) or _own_order(n.process_physics_priority):
		pass
	else:
		n.process_priority = prio
		n.process_physics_priority = prio
	for c in n.get_children():
		_claim_tree(c, prio)


func _own_order(p: int) -> bool:
	return p != 0 and (p < BAND_BASE or p > BAND_BASE + 2 * SYSTEMS.size() + 2)


func _physics_process(_d: float) -> void:
	if not recording:
		return
	_phys_end = Time.get_ticks_usec()
	_phys_ticks += 1
	_phys_script_ms += _span(_phys_marks, 0, _phys_marks.size() - 1)
	var bands := _bands(_phys_marks)
	for id: StringName in bands:
		_phys_ms[id] = float(_phys_ms.get(id, 0.0)) + float(bands[id])


func _process(delta: float) -> void:
	_claim_left -= delta
	if _claim_left <= 0.0:
		_claim_left = 1.0
		claim()
	if not recording:
		return
	var f := {}
	var idle := _bands(_idle_marks)
	var ticks := maxi(_phys_ticks, 0)
	for id in idle:
		f[id] = float(idle[id]) + float(_phys_ms.get(id, 0.0))
	f[&"script"] = _span(_idle_marks, 0, _idle_marks.size() - 1) + _phys_script_ms - harness_ms
	f[&"other"] = maxf(0.0, float(f[&"other"]) - harness_ms)
	f[&"harness"] = harness_ms
	harness_ms = 0.0
	f[&"physics_ticks"] = ticks
	# Performance.TIME_*_PROCESS are maxima over the last second, so the probe times the
	# engine's physics step itself (_on_first).
	f[&"physics"] = _step_ms
	if DisplayServer.get_name() != "headless":
		var vp := get_viewport().get_viewport_rid()
		f[&"render_cpu"] = RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		f[&"render_gpu"] = RenderingServer.viewport_get_measured_render_time_gpu(vp)
	f[&"errors_timing"] = ErrorTiming.errors_ms()
	for id: StringName in ERROR_IDS:
		f[StringName("err_%s" % id)] = ErrorTiming.error_ms(id)
	f[&"frame"] = delta * 1000.0
	f[&"nodes"] = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	f[&"draw_calls"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	f[&"objects"] = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	f[&"primitives"] = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	f[&"vram_mb"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	f[&"memory_mb"] = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	# Tree walks are slow: counted every COUNT_EVERY frames (after the last mark, so they
	# cost the frame time but no system's reading).
	if frames.size() % COUNT_EVERY == 0:
		_count_now()
	f.merge(_counts, true)
	frames.append(f)
	_phys_ms = {}
	_phys_script_ms = 0.0
	_phys_ticks = 0
	_step_ms = 0.0


func _count_now() -> void:
	_counts = {&"level_nodes": 0, &"lights": 0, &"pool_lights": 0, &"shadowed": 0, &"players_3d": 0, &"players_3d_playing": 0}
	if level == null or not is_instance_valid(level):
		return
	var cam := get_viewport().get_camera_3d()
	var from := cam.global_position if cam != null else Vector3.INF
	var counts := Level.light_counts(get_tree().root, from)
	_counts[&"level_nodes"] = level_node_count(level)
	_counts[&"lights"] = counts.x + counts.y
	_counts[&"pool_lights"] = level.light_pool.active_light_count() if level.light_pool != null else 0
	_counts[&"shadowed"] = shadowed_count(get_tree().root, from)
	# AudioStreamPlayer3D runs an internal physics step per node while it plays (engine
	# cost inside whichever band owns it).
	var playing := 0
	var players := get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false)
	for n in players:
		if (n as AudioStreamPlayer3D).playing:
			playing += 1
	_counts[&"players_3d"] = players.size()
	_counts[&"players_3d_playing"] = playing


## Milliseconds between marks i and j of one loop (0 when either has not stamped).
func _span(marks: Array[_Mark], i: int, j: int) -> float:
	if marks[i].stamp <= 0 or marks[j].stamp < marks[i].stamp:
		return 0.0
	return (marks[j].stamp - marks[i].stamp) / 1000.0


func _bands(marks: Array[_Mark]) -> Dictionary:
	var out := {}
	# Unclaimed nodes (priority 0) run between the first mark and band 0's opening mark.
	out[&"other"] = _span(marks, 0, 1) + _span(marks, marks.size() - 2, marks.size() - 1)
	for k in SYSTEMS.size():
		out[SYSTEMS[k]] = _span(marks, k + 1, k + 2)
	return out


func start() -> void:
	frames.clear()
	_phys_ms = {}
	_phys_script_ms = 0.0
	_phys_ticks = 0
	_step_ms = 0.0
	_phys_end = 0
	claim()
	recording = true


func stop() -> void:
	recording = false


## Nodes under (and including) `root`.
static func level_node_count(root: Node) -> int:
	var n := 1
	for c in root.get_children():
		n += level_node_count(c)
	return n


## Visible shadow-casting OmniLight3D and SpotLight3D under `root` (the pool's and the
## flashlight's, flares at High).
static func shadowed_count(root: Node, from: Vector3 = Vector3.INF) -> int:
	var n := 0
	for node in root.find_children("*", "Light3D", true, false):
		var l := node as Light3D
		if (l is OmniLight3D or l is SpotLight3D) and l.shadow_enabled and Level.is_drawn(l, from):
			n += 1
	return n


## {metric: {mean, p50, p95, max}} over the recorded frames.
func summary() -> Dictionary:
	var out := {}
	if frames.is_empty():
		return out
	for key: StringName in frames[0]:
		var vals := PackedFloat32Array()
		for f in frames:
			vals.append(float(f.get(key, 0.0)))
		out[key] = stats(vals)
	out[&"frames"] = frames.size()
	return out


## The `q` quantile (0..1) of `vals` (nearest rank, rounding down); 0 when empty.
static func percentile(vals: PackedFloat32Array, q: float) -> float:
	if vals.is_empty():
		return 0.0
	var s := vals.duplicate()
	s.sort()
	return s[int(floor((s.size() - 1) * q))]


static func stats(vals: PackedFloat32Array) -> Dictionary:
	if vals.is_empty():
		return {&"mean": 0.0, &"p50": 0.0, &"p95": 0.0, &"max": 0.0}
	var s := vals.duplicate()
	s.sort()
	var total := 0.0
	for v in s:
		total += v
	return {
		&"mean": total / s.size(),
		&"p50": s[int(floor((s.size() - 1) * 0.5))],
		&"p95": s[int(floor((s.size() - 1) * 0.95))],
		&"max": s[s.size() - 1],
	}
