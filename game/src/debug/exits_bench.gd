extends Node3D
## M2.9 exits bench (09 §10, 07 §6): builds a real level of each stratum with its exit prefab
## (Keyed, so the reader stands beside it; Server's with the Cycled display) and frames the
## exit from the nearest clear standing point. Arrow keys / 1-5 pick the stratum, O opens and
## seals. `-- --exit-shots <dir>` captures each prefab closed and open, then quits:
## tools/ci/render.sh --path game res://scenes/debug/exits_bench.tscn -- --exit-shots build/exits

const LEVEL_SCENE := "res://scenes/level.tscn"
const STRATA: Array[StringName] = [&"halls", &"pools", &"garage", &"offices", &"server"]
const DEPTHS: Dictionary = {&"halls": 1, &"pools": 2, &"garage": 2, &"offices": 3, &"server": 4}
const LOCKS: Dictionary = {&"halls": &"keyed", &"pools": &"keyed", &"garage": &"keyed",
	&"offices": &"keyed", &"server": &"cycled"}
const EYE := 1.6
const SHOT_SIZE := Vector2i(960, 540)

@onready var camera: Camera3D = %Camera

var level: Level
var data: LevelData
var exit: Exit
var index: int = 0
var _busy: bool = false


func _ready() -> void:
	var shots := ""
	var args := OS.get_cmdline_user_args()
	for i in args.size() - 1:
		if args[i] == "--exit-shots":
			shots = args[i + 1]
	if shots != "":
		get_window().size = SHOT_SIZE
		_shoot_all.call_deferred(shots)
	else:
		_show.call_deferred(0)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or _busy:
		return
	if k.keycode >= KEY_1 and k.keycode <= KEY_5:
		_show(k.keycode - KEY_1)
	elif k.keycode == KEY_RIGHT:
		_show((index + 1) % STRATA.size())
	elif k.keycode == KEY_LEFT:
		_show((index + STRATA.size() - 1) % STRATA.size())
	elif k.keycode == KEY_O and exit != null:
		if exit.is_open():
			exit.seal()
		else:
			exit.open()


func _show(i: int) -> void:
	_busy = true
	index = i
	await _build(STRATA[i])
	_busy = false


func _build(stratum: StringName) -> void:
	if level != null:
		level.queue_free()
		level = null
		exit = null
		await get_tree().process_frame
	data = LevelGenerator.generate(stratum, DEPTHS[stratum], 11, false, 1, {&"lock": LOCKS[stratum]})
	level = (load(LEVEL_SCENE) as PackedScene).instantiate() as Level
	add_child(level)
	level.begin(data)
	await level.geometry_ready
	exit = RunLevelSetup.prepare(level, data)[&"exit"]
	exit.set_physics_process(false)
	exit.mark_seen()
	exit.start_cycle()
	_frame()
	level.light_pool.reevaluate()


## Puts the camera at the nearest clear standing point in front of (or round) the exit.
func _frame() -> void:
	var target := exit.sight_point.global_position
	var g := data.grid
	var best := Vector3.INF
	var dirs: Array[Vector3] = [-exit.global_transform.basis.z, exit.global_transform.basis.x,
		-exit.global_transform.basis.x, exit.global_transform.basis.z]
	for dist: float in [4.0, 3.5, 3.0, 2.5]:
		for d in dirs:
			var p := exit.walk_in_point() + Vector3(d.x, 0.0, d.z).normalized() * dist
			var c := g.cell_of(p)
			if not g.in_bounds(c) or not g.is_walkable(c):
				continue
			var eye := Vector3(p.x, g.floor_y(c) + EYE, p.z)
			var q := PhysicsRayQueryParameters3D.create(eye, target, PlayerLayers.WORLD_MASK)
			var hit := get_world_3d().direct_space_state.intersect_ray(q)
			if hit.is_empty() or exit.is_ancestor_of(hit["collider"] as Node) or hit["collider"] == exit.leaves:
				best = eye
				break
		if best != Vector3.INF:
			break
	if best == Vector3.INF:
		best = exit.approach_point(3.0) + Vector3(0.0, EYE, 0.0)
	var stand_in := Node3D.new()
	level.add_child(stand_in)
	level.attach_player(stand_in, camera)
	camera.global_position = best
	camera.look_at(target.lerp(exit.global_position, 0.3), Vector3.UP)
	camera.make_current()


func _shoot_all(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for s in STRATA:
		await _build(s)
		await _settle(1.0)
		_save("%s/%s_%s_closed.png" % [dir, s, exit.exit_kind])
		if exit.lock == Tuning.LOCK_CYCLED:
			exit.advance_cycle(exit.cycle_left - 0.01)
		else:
			exit.open()
		await _settle(Exit.DOOR_OPEN_TIME + 0.8)
		_save("%s/%s_%s_open.png" % [dir, s, exit.exit_kind])
		print("exits_bench: %s %s %s" % [s, exit.exit_kind, exit.global_position])
	get_tree().quit()


func _settle(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _save(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
