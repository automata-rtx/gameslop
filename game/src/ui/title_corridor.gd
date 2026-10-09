class_name TitleCorridor
extends Node3D
## The title screen's live background (04 §7, M3.6): a generated Halls level (seed 0, no
## errors, no Director) seen through a camera that strolls slowly along its corridors, fog
## up 30% and the Coherence renderer at 85 so there is faint grain. Every 25 to 40 s (a
## seeded draw) a 200 ms unrender flicker ripples down the corridor ahead: the noclip preview
## sphere (CoherenceRenderer.set_noclip_target / set_noclip_charge, no sound, no Null) runs
## MENU_TITLE_FLICKER_REACH metres along the walk and is gone. Reduce flashing (12 §6) turns
## the flicker off; the camera's field of view follows the FOV setting (12 §2, the same
## horizontal-to-vertical conversion as the player's camera, KEEP_HEIGHT).
## The walk: from the head of the longest straight corridor, straight on while the next
## edge is open (no door leaf to pass through), turning left or right at the end (seeded),
## up to MENU_TITLE_PATH_CELLS cells; at its end the camera cuts back to the start.
## Generation runs on a worker thread (07 §1); the title shows black until the geometry is
## built. Title.set_background() hosts it.

signal started

const LEVEL_SCENE := "res://scenes/level.tscn"
const EYE := 1.6
const SETTING_FOV := &"fov"
const SETTING_REDUCE_FLASHING := &"reduce_flashing"

var level: Level
var camera: Camera3D
var data: LevelData
## World points of the walk at eye height, one per cell.
var points: PackedVector3Array = PackedVector3Array()
## Metres walked along `points`.
var s: float = 0.0
## Seconds to the next flicker; the flicker's own clock (< 0: none running).
var flicker_in: float = 0.0
var flicker_t: float = -1.0
var flickers: int = 0
var _rng := RandomNumberGenerator.new()
var _job: Job = null
var _task: int = -1
var _length: float = 0.0


class Job extends RefCounted:
	var result: LevelData

	func run() -> void:
		result = LevelGenerator.generate(&"halls", 1, Tuning.MENU_TITLE_SEED, false, 1)


func _ready() -> void:
	_rng.seed = Tuning.MENU_TITLE_SEED
	flicker_in = next_flicker_delay()
	camera = Camera3D.new()
	camera.name = "TitleCamera"
	camera.near = Tuning.CAMERA_NEAR
	camera.far = Tuning.CAMERA_FAR
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	add_child(camera)
	apply_fov()
	SettingsManager.changed.connect(_on_setting_changed)
	_job = Job.new()
	_task = WorkerThreadPool.add_task(_job.run, false, "TitleCorridor")


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	_end_flicker()
	CoherenceRenderer.set_coherence(Tuning.COHERENCE_MAX)


func is_started() -> bool:
	return level != null and not points.is_empty()


## The next gap between flickers, 25 to 40 s (seeded).
func next_flicker_delay() -> float:
	return _rng.randf_range(Tuning.MENU_TITLE_FLICKER_MIN, Tuning.MENU_TITLE_FLICKER_MAX)


func apply_fov() -> void:
	var v: Variant = SettingsManager.get_value(SETTING_FOV)
	var h := clampf(float(v) if v != null else float(Tuning.CAMERA_FOV_DEFAULT), Tuning.CAMERA_FOV_MIN, Tuning.CAMERA_FOV_MAX)
	camera.fov = CameraRig.hfov_to_vfov(h)


static func flashing_allowed() -> bool:
	return not bool(SettingsManager.get_value(SETTING_REDUCE_FLASHING))


func _on_setting_changed(key: StringName, _v: Variant) -> void:
	if key == SETTING_FOV:
		apply_fov()
	elif key == SETTING_REDUCE_FLASHING and not flashing_allowed():
		_end_flicker()


func _process(delta: float) -> void:
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_begin_level(_job.result)
		return
	if not is_started():
		return
	walk(delta)


func _begin_level(d: LevelData) -> void:
	if d == null:
		return
	data = d
	level = (load(LEVEL_SCENE) as PackedScene).instantiate() as Level
	add_child(level)
	level.begin(data)
	# 04 §7: fog up 30%, before the graphics profile records the fog it restores.
	var env := level.world_environment.environment
	env.volumetric_fog_density *= 1.0 + Tuning.MENU_TITLE_FOG_BOOST
	env.fog_density *= 1.0 + Tuning.MENU_TITLE_FOG_BOOST
	var vals := {}
	for k: StringName in SettingsSchema.DEFAULTS:
		vals[k] = SettingsManager.get_value(k)
	SettingsApply.graphics(level, vals)
	points = walk_points(data.grid, _rng)
	_length = maxf(0.0, (points.size() - 1) * Tuning.GRID_CELL_SIZE)
	level.light_pool.target = camera
	if level.dust != null:
		level.dust.follow = camera
	camera.make_current()
	CoherenceRenderer.set_coherence(Tuning.MENU_TITLE_COHERENCE)
	await level.geometry_ready
	level.light_pool.reevaluate()
	_place()
	started.emit()


## Moves the camera `dt` seconds along the walk and runs the flicker clock.
func walk(dt: float) -> void:
	s += dt * Tuning.MENU_TITLE_CAMERA_SPEED
	if s > _length - Tuning.MENU_TITLE_LOOK_AHEAD:
		s = 0.0   # the loop cuts back to the start
	_place()
	if flicker_t >= 0.0:
		flicker_t += dt
		if flicker_t >= Tuning.MENU_TITLE_FLICKER_MS / 1000.0:
			_end_flicker()
		else:
			_flicker_frame()
		return
	flicker_in -= dt
	if flicker_in <= 0.0:
		flicker_in = next_flicker_delay()
		if flashing_allowed():
			flicker_t = 0.0
			flickers += 1
			_flicker_frame()


func is_flickering() -> bool:
	return flicker_t >= 0.0


## The flicker's front: the walk point ahead of the camera, 0 to REACH m over 200 ms, and
## the preview's strength (a triangle 0 -> 1 -> 0).
func _flicker_frame() -> void:
	var k := clampf(flicker_t / (Tuning.MENU_TITLE_FLICKER_MS / 1000.0), 0.0, 1.0)
	CoherenceRenderer.set_noclip_target(sample(s + 1.0 + k * Tuning.MENU_TITLE_FLICKER_REACH), Vector3.ZERO)
	CoherenceRenderer.set_noclip_charge(1.0 - absf(k * 2.0 - 1.0))


## Holds the flicker at fraction `k` of its 200 ms (benches and screenshots).
func hold_flicker(k: float) -> void:
	flicker_t = k * Tuning.MENU_TITLE_FLICKER_MS / 1000.0
	_flicker_frame()


func _end_flicker() -> void:
	flicker_t = -1.0
	CoherenceRenderer.set_noclip_charge(0.0)
	CoherenceRenderer.set_noclip_target(CoherenceRenderer.NOCLIP_TARGET_ABSENT, Vector3.ZERO)


func _place() -> void:
	if points.size() < 2:
		return
	var span := Tuning.MENU_TITLE_SMOOTH
	var p := Vector3.ZERO
	for i in 5:
		p += sample(s + span * (i / 2.0 - 1.0))
	p /= 5.0
	var ahead := sample(s + Tuning.MENU_TITLE_LOOK_AHEAD)
	camera.global_position = p
	if p.distance_squared_to(ahead) > 0.01:
		camera.look_at(Vector3(ahead.x, p.y, ahead.z), Vector3.UP)


## The walk at `d` metres (clamped to its ends).
func sample(d: float) -> Vector3:
	if points.is_empty():
		return Vector3.ZERO
	var f := clampf(d / Tuning.GRID_CELL_SIZE, 0.0, float(points.size() - 1))
	var i := mini(int(f), points.size() - 2)
	if i < 0:
		return points[0]
	return points[i].lerp(points[i + 1], f - i)


## The camera's walk through `g`: corridor cells joined by open edges (no doors), straight on
## where it can, a seeded left or right turn where it cannot, never back on itself.
static func walk_points(g: LevelGrid, rng: RandomNumberGenerator) -> PackedVector3Array:
	var cells := walk_cells(g, rng)
	var out := PackedVector3Array()
	for c in cells:
		out.append(g.world_of(c) + Vector3(0.0, EYE, 0.0))
	return out


static func walk_cells(g: LevelGrid, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var start := Vector4i(-1, -1, 0, 0)
	for i in g.cell_count():
		var c := g.cell_at(i)
		if not _corridor(g, c):
			continue
		for d: int in [LevelGrid.E, LevelGrid.S, LevelGrid.W, LevelGrid.N]:
			var n := 0
			var p := c
			while _open(g, p, d):
				p += LevelGrid.DIRS[d]
				n += 1
			if n > start.w:
				start = Vector4i(c.x, c.y, d, n)
	var out: Array[Vector2i] = []
	if start.x < 0:
		return out
	var cur := Vector2i(start.x, start.y)
	var dir := start.z
	var seen := {cur: true}
	out.append(cur)
	while out.size() < Tuning.MENU_TITLE_PATH_CELLS:
		var choices: Array[int] = []
		if _open(g, cur, dir) and not seen.has(cur + LevelGrid.DIRS[dir]):
			choices = [dir]
		else:
			for t: int in [(dir + 1) % 4, (dir + 3) % 4]:
				if _open(g, cur, t) and not seen.has(cur + LevelGrid.DIRS[t]):
					choices.append(t)
		if choices.is_empty():
			break
		dir = choices[rng.randi_range(0, choices.size() - 1)]
		cur += LevelGrid.DIRS[dir]
		seen[cur] = true
		out.append(cur)
	return out


static func _corridor(g: LevelGrid, c: Vector2i) -> bool:
	return g.in_bounds(c) and g.kind(c) == LevelGrid.FLOOR and not g.is_blocked(c)


static func _open(g: LevelGrid, c: Vector2i, d: int) -> bool:
	return g.can_step(c, d) and g.wall(c, d) == LevelGrid.NONE and _corridor(g, c + LevelGrid.DIRS[d])
