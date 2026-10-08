class_name ScreenshotTour
extends Node
## The screenshot tour (14 §9, 02 §13): `--tour [out_dir]`. For every stratum that has a
## grammar (it grows with the game), builds seed 1 and photographs it from three poses (spawn
## facing the longest sightline, the middle of the longest corridor, the exit room) at
## Coherence 100, 60, 30 and 10, plus one mid-noclip frame (the commit pass at a wall) and
## one with Null 8 m ahead (the unrender radius is faked through the renderer globals;
## there is no Null yet). It also takes the head of the longest corridor at Coherence 100,
## where T1 is measured out to 12 m. Output: PNGs under <out_dir>/<stratum>/ and
## manifest.json carrying the luminance numbers LevelShots measures; tools/ci/tour_check.py
## turns them into the T1, T3 and T4 table.
## Needs a renderer: tools/ci/render.sh --path game --resolution 960x540 -- --tour build/tour
## (CPU Forward+, slow). It says nothing about frame times.

const SEED := 1
const COHERENCE_STEPS: Array[float] = [100.0, 60.0, 30.0, 10.0]
const POSES: Array[StringName] = [&"spawn", &"corridor", &"exit_room"]
## The extra pose where T1 is read out to 12 m (LevelShots' head of the longest corridor).
const T1_POSE := &"corridor_long"
const NOCLIP_COHERENCE := 70.0
const NULL_DISTANCE := 8.0
const SETTLE_POSE := 12
const SETTLE_STEP := 5
## 02 T1: the floor must read this far; Server and Substrate are darker on purpose.
const T1_LIMIT_M := 12.0
const T1_LIMIT_DARK_M := 6.0
const DARK_STRATA: Array[StringName] = [&"server", &"substrate"]
const SUBSTRATE_PATH := "res://data/strata/substrate.tres"

var manifest: Dictionary = {}

var _out: String = ""
var _shots: LevelShots
var _camera: Camera3D
var _level: Level
var _stratum: StringName = &""
var _entries: Dictionary = {}


## The strata the tour visits: every stratum with a generator grammar.
static func strata() -> Array[StringName]:
	var out: Array[StringName] = []
	for s in CliArgs.STRATA:
		if LevelGenerator.supports(s):
			out.append(s)
	return out


static func t1_limit(stratum: StringName) -> float:
	return T1_LIMIT_DARK_M if DARK_STRATA.has(stratum) else T1_LIMIT_M


## What the tour photographs in `data`'s level: {poses: [{name, from, to}], noclip:
## {from, to, point, normal} (empty when the level has no wall between two walkable cells)}.
static func plan(data: LevelData) -> Dictionary:
	var wanted: Array[Dictionary] = []
	var by_name: Dictionary = {}
	for p in LevelShots.poses(data):
		by_name[p[&"name"]] = p
	for n in POSES:
		if by_name.has(n):
			wanted.append(by_name[n])
	if by_name.has(T1_POSE):
		wanted.append(by_name[T1_POSE])
	return {&"poses": wanted, &"noclip": noclip_view(data)}


## A wall between two walkable cells, seen from 0.4 m behind the cell centre: the camera, its
## target, the wall point and its normal (what noclip targeting would feed the renderer).
static func noclip_view(data: LevelData) -> Dictionary:
	var g := data.grid
	var cells: Array[Vector2i] = []
	var room := g.room_of(data.spawn_cell)
	if room != null:
		cells.append_array(room.cells())
	cells.append(data.spawn_cell)
	for i in g.cell_count():
		cells.append(g.cell_at(i))
	for c in cells:
		if not g.is_walkable(c):
			continue
		for d in 4:
			var o := c + LevelGrid.DIRS[d]
			if g.wall(c, d) != LevelGrid.WALL or not g.in_bounds(o) or not g.is_walkable(o):
				continue
			var dv := LevelGrid.DIRS[d]
			var fwd := Vector3(dv.x, 0.0, dv.y)
			var centre := g.world_of(c)
			var from := centre - fwd * 0.4 + Vector3(0.0, LevelShots.EYE, 0.0)
			return {
				&"from": from,
				&"to": from + fwd * 3.0 + Vector3(0.0, -0.15, 0.0),
				&"point": centre + fwd * (Tuning.GRID_CELL_SIZE * 0.5) + Vector3(0.0, 1.4, 0.0),
				&"normal": -fwd,
			}
	return {}


func run(out_dir: String) -> void:
	if DisplayServer.get_name() == "headless":
		push_error("ScreenshotTour: --tour needs a renderer (use tools/ci/render.sh)")
		get_tree().quit(1)
		return
	_out = out_dir if out_dir.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join("..").path_join(out_dir).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out)
	var size := get_viewport().get_visible_rect().size
	manifest = {&"seed": SEED, &"resolution": [int(size.x), int(size.y)],
		&"coherence_steps": COHERENCE_STEPS, &"strata": {}}
	for s in strata():
		await _tour_stratum(s)
	var f := FileAccess.open(_out.path_join("manifest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "  "))
	f.close()
	print("tour: ", _out)
	get_tree().quit(0)


func _tour_stratum(stratum: StringName) -> void:
	_stratum = stratum
	DirAccess.make_dir_recursive_absolute(_out.path_join(String(stratum)))
	var d := DirectLevel.new()
	d.name = "TourLevel"
	d.stratum = stratum
	d.depth = 1
	d.run_seed = SEED
	d.capture_mouse = false
	add_child(d)
	await d.built
	if d.player != null:
		d.player.queue_free()
	_level = d.level
	_shots = LevelShots.new()
	add_child(_shots)
	_camera = _shots.begin(_level)
	_entries = {}
	manifest[&"strata"][String(stratum)] = {&"t1_limit_m": t1_limit(stratum), &"shots": _entries}
	var tour_plan := plan(d.data)
	for pose in tour_plan[&"poses"]:
		_aim(pose[&"from"], pose[&"to"])
		await _frames(SETTLE_POSE)
		var steps: Array[float] = [100.0] if pose[&"name"] == T1_POSE else COHERENCE_STEPS
		for c in steps:
			CoherenceRenderer.set_coherence(c)
			await _frames(SETTLE_STEP)
			_save("%s_c%03d" % [pose[&"name"], int(c)], {&"pose": pose[&"name"], &"coherence": c,
					&"kind": &"pose"})
	CoherenceRenderer.set_coherence(Tuning.COHERENCE_MAX)
	await _noclip_frame(tour_plan[&"noclip"])
	await _null_frame(tour_plan[&"poses"])
	_reset()
	_shots.queue_free()
	d.queue_free()
	await get_tree().process_frame


## The mid-noclip frame: the commit pass at a wall, the pulse held at its peak (the CPU
## renderer is slow, so it is re-fired every frame as noclip_shots does).
func _noclip_frame(view: Dictionary) -> void:
	if view.is_empty():
		return
	_aim(view[&"from"], view[&"to"])
	_level.light_pool.reevaluate()
	await _frames(SETTLE_POSE)
	CoherenceRenderer.set_coherence(NOCLIP_COHERENCE)
	CoherenceRenderer.set_noclip_target(view[&"point"], view[&"normal"])
	for i in SETTLE_STEP:
		CoherenceRenderer.pulse(&"noclip_commit")
		await RenderingServer.frame_post_draw
	_save("noclip_commit", {&"pose": &"noclip", &"coherence": NOCLIP_COHERENCE, &"kind": &"noclip"})
	_reset()


## Null 8 m ahead of the spawn pose: the renderer globals fake the unrender radius, over the
## Substrate environment (black, fog to black) as render_bench frames it.
func _null_frame(poses: Array) -> void:
	if poses.is_empty():
		return
	var pose: Dictionary = poses[0]
	_aim(pose[&"from"], pose[&"to"])
	var env := _level.world_environment.environment
	_level.world_environment.environment = StratumEnvironment.build(load(SUBSTRATE_PATH) as StratumData,
			_level.preset)
	CoherenceRenderer.set_coherence(Tuning.COHERENCE_MAX)
	CoherenceRenderer.set_null(_camera.global_position - _camera.global_basis.z * NULL_DISTANCE,
			Tuning.NULL_UNRENDER_RADIUS)
	await _frames(SETTLE_POSE)
	_save("null_8m", {&"pose": &"spawn", &"coherence": Tuning.COHERENCE_MAX, &"kind": &"null"})
	_level.world_environment.environment = env
	_reset()


func _aim(from: Vector3, to: Vector3) -> void:
	_camera.global_position = from
	_camera.look_at(to)
	_level.light_pool.reevaluate()


func _reset() -> void:
	CoherenceRenderer.set_coherence(Tuning.COHERENCE_MAX)
	CoherenceRenderer.set_null(CoherenceRenderer.NULL_POS_ABSENT, 0.0)
	CoherenceRenderer.set_noclip_target(CoherenceRenderer.NOCLIP_TARGET_ABSENT, Vector3.ZERO)
	CoherenceRenderer.set_noclip_charge(0.0)


func _frames(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw


## Saves the current frame as <stratum>/<name>.png and records its numbers.
func _save(shot_name: String, info: Dictionary) -> void:
	var img := get_viewport().get_texture().get_image()
	var rel := "%s/%s.png" % [_stratum, shot_name]
	var err := img.save_png(_out.path_join(rel))
	var entry: Dictionary = _shots.measure(img)
	entry.merge(info)
	entry[&"file"] = rel
	_entries[shot_name] = entry
	print("tour: %s (%s) p01 %.3f median %.3f clipped %d" % [rel, error_string(err),
			entry[&"luma_p01"], entry[&"luma_median"], entry[&"clipped_px"]])
