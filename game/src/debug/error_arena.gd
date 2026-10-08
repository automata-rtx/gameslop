class_name ErrorArena
extends Node3D
## 08 §9 error arena: a built Halls level (seed 1) with the player, spawn buttons per error,
## a light toggle, an aggression slider and the state log. Used to tune errors and to
## capture their signature frames (02 §13).
##   Keys: 1 spawn Static, 2 spawn Still, 3 spawn Echo, L fixtures on/off, K remove every error,
##   H hint every error away at once (10 §2 Relief: hint(pos, true)).
##   F (the player's own flashlight) toggles the beam.
## The log shows the errors' script time per physics frame (ErrorTiming.MONITOR, also in the
## Performance custom monitors / F3), refreshed 4 times a second.
##   -- --shots <dir>   capture still_lit_6m, still_dark, still_tick, static_outside,
##                      static_inside, echo_4m_halls into <dir> (relative to the repository)
##                      and quit. With `--stratum pools` the arena is a Pools level and the
##                      shots are echo_4m_pools only.
##   -- --stratum <id>  the arena's stratum (default halls).
## Errors spawn the Director's way: an `error_spawns` marker >= 20 m away and outside the
## camera frustum (08 §2), else the farthest walkable cell.

const LEVEL_SCENE := "res://scenes/level.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const ARENA_SEED := 1
const SETTLE_FRAMES := 6
const CORRIDOR_CELLS := 6

var level: Level
var data: LevelData
var player: Player
var errors: Array[ErrorBase] = []
var aggression: float = 0.25
var _spawned: int = 0
var _log: Label
var _lights_on: bool = true
var _cost_acc: float = 0.0
var _stratum: StringName = &"halls"


func _ready() -> void:
	var shots := _arg("--shots")
	if _arg("--stratum") != "":
		_stratum = StringName(_arg("--stratum"))
	await _build()
	_build_ui()
	if shots != "":
		await _capture_all(shots)
		get_tree().quit(0)


func _arg(key: String) -> String:
	var args := OS.get_cmdline_user_args()
	var i := args.find(key)
	return args[i + 1] if i != -1 and i + 1 < args.size() else ""


func _build() -> void:
	data = LevelGenerator.generate(_stratum, 1, ARENA_SEED)
	level = (load(LEVEL_SCENE) as PackedScene).instantiate() as Level
	add_child(level)
	level.begin(data)
	await level.geometry_ready
	player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	level.add_child(player)
	level.attach_player(player, player.rig.camera)
	player.rig.camera.make_current()
	if not level.is_ready():
		await level.built


# --- spawning (the Director's rules, for the bench) ----------------------------------------

func spawn(id: StringName, at: Vector3 = Vector3.INF) -> ErrorBase:
	var e := ErrorBase.create(id)
	if e == null:
		return null
	e.setup(player, level, Seeds.derive(data.level_seed, ErrorBase.seed_label(id, _spawned)))
	_spawned += 1
	level.add_child(e)
	var pos := at if at != Vector3.INF else _spawn_point()
	if e is ErrorStill:
		(e as ErrorStill).place_at(pos)
	elif e is ErrorEcho:
		(e as ErrorEcho).place_at(pos)
	else:
		e.global_position = pos
	e.set_aggression(aggression)
	e.state_changed.connect(func(_f: StringName, _t: StringName) -> void: _refresh_log())
	errors.append(e)
	_refresh_log()
	return e


func _spawn_point() -> Vector3:
	var cam := player.rig.camera
	var best := player.global_position
	var best_d := -1.0
	for n in get_tree().get_nodes_in_group(LevelPlacer.GROUP_ERROR_SPAWNS):
		var p := (n as Node3D).global_position
		var d := p.distance_to(player.global_position)
		var fair := d >= Tuning.ERROR_SPAWN_MIN_DIST and not cam.is_position_in_frustum(p + Vector3.UP)
		if fair:
			return p
		if d > best_d:
			best_d = d
			best = p
	return best


func clear_errors() -> void:
	for e in errors:
		if is_instance_valid(e):
			e.queue_free()
	errors.clear()
	_refresh_log()


## 10 §2 Relief: every error hinted to the walkable cell farthest from the player (at
## least 25 m when the level has one), re-targeting at once in Wander and Search.
func hint_away() -> void:
	var g := data.grid
	var best := player.global_position
	var best_d := -1.0
	for i in g.cell_count():
		var c := g.cell_at(i)
		var d := g.world_of(c).distance_to(player.global_position) if g.is_walkable(c) else -1.0
		if d > best_d:
			best_d = d
			best = g.world_of(c)
	for e in errors:
		if is_instance_valid(e):
			e.hint(best, true)


func set_lights(on: bool) -> void:
	_lights_on = on
	level.light_pool.set_all_powered(on)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_1:
			spawn(&"static").wake()
		KEY_2:
			spawn(&"still").wake()
		KEY_3:
			spawn(&"echo").wake()
		KEY_L:
			set_lights(not _lights_on)
		KEY_K:
			clear_errors()
		KEY_H:
			hint_away()


# --- UI ------------------------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var box := VBoxContainer.new()
	box.position = Vector2(16, 120)
	layer.add_child(box)
	for spec: Array in [["SPAWN STATIC [1]", &"static"], ["SPAWN STILL [2]", &"still"],
			["SPAWN ECHO [3]", &"echo"]]:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		var id: StringName = spec[1]
		b.pressed.connect(func() -> void: spawn(id).wake())
		box.add_child(b)
	var away := Button.new()
	away.text = "HINT AWAY [H]"
	away.focus_mode = Control.FOCUS_NONE
	away.pressed.connect(hint_away)
	box.add_child(away)
	var lights := Button.new()
	lights.text = "FIXTURES ON/OFF [L]"
	lights.focus_mode = Control.FOCUS_NONE
	lights.pressed.connect(func() -> void: set_lights(not _lights_on))
	box.add_child(lights)
	var label := Label.new()
	label.text = "AGGRESSION"
	box.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = aggression
	slider.custom_minimum_size = Vector2(240, 0)
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(_on_aggression)
	box.add_child(slider)
	_log = Label.new()
	box.add_child(_log)


func _process(delta: float) -> void:
	_cost_acc += delta
	if _cost_acc >= 0.25:
		_cost_acc = 0.0
		_refresh_log()


func _on_aggression(v: float) -> void:
	aggression = v
	for e in errors:
		if is_instance_valid(e):
			e.set_aggression(v)
	_refresh_log()


func _refresh_log() -> void:
	if _log == null:
		return
	var lines: PackedStringArray = ["AGGRESSION %.2f" % aggression,
		"ERRORS %.3f MS (STATIC %.3f, STILL %.3f, ECHO %.3f)" % [ErrorTiming.errors_ms(),
			ErrorTiming.error_ms(&"static"), ErrorTiming.error_ms(&"still"), ErrorTiming.error_ms(&"echo")]]
	for e in errors:
		if is_instance_valid(e):
			lines.append_array(e.log_lines)
	_log.text = "\n".join(lines)


# --- shots ---------------------------------------------------------------------------------

## A straight corridor: a walkable cell and a direction with CORRIDOR_CELLS open steps,
## outside the spawn room. Returns [cell, dir].
func _corridor(cells: int = CORRIDOR_CELLS, rooms: bool = false) -> Array:
	var g := data.grid
	for i in g.cell_count():
		var c := g.cell_at(i)
		if not g.is_walkable(c) or g.has_flag(c, LevelGrid.F_SPAWN_ROOM) or (g.room_of(c) != null and not rooms):
			continue
		for d in 4:
			var run := 0
			var at := c
			while run < cells and g.can_step(at, d):
				at += LevelGrid.DIRS[d]
				run += 1
			if run >= cells:
				return [c, d]
	return [data.spawn_cell, 0]


func _pose_player(cell: Vector2i, dir: int) -> Vector3:
	var g := data.grid
	var pos := g.world_of(cell)
	var fwd := Vector3(LevelGrid.DIRS[dir].x, 0, LevelGrid.DIRS[dir].y)
	player.global_position = pos + Vector3.UP * 0.05
	player.rotation = Vector3(0, atan2(-fwd.x, -fwd.z), 0)
	player.velocity = Vector3.ZERO
	level.light_pool.reevaluate()
	return fwd


func _capture_all(dir: String) -> void:
	var abs_dir := dir if dir.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join("..").path_join(dir).simplify_path()
	DirAccess.make_dir_recursive_absolute(abs_dir)
	if _stratum != &"halls":
		await _echo_shot(abs_dir)
		print("error_arena: shots in ", abs_dir)
		return
	var cor := _corridor()
	var cell: Vector2i = cor[0]
	var d: int = cor[1]
	var fwd := _pose_player(cell, d)
	var base := data.grid.world_of(cell)
	# Still at 6 m, lit by the flashlight (and the Halls tubes).
	var still := spawn(&"still", base + fwd * 6.0) as ErrorStill
	still.set_physics_process(false)
	player.flashlight.set_on(true, true)
	await _shot(abs_dir, "still_lit_6m")
	# The render-line tick, pinned on.
	still._set_line(true, 0.62)
	await _shot(abs_dir, "still_tick")
	still._set_line(false)
	# In the dark: fixtures off, flashlight off.
	set_lights(false)
	player.flashlight.set_on(false, true)
	await _shot(abs_dir, "still_dark")
	set_lights(true)
	still.queue_free()
	errors.erase(still)
	# Static down the corridor, then with the player at its centre.
	var st := spawn(&"static", base + fwd * 8.0) as ErrorStatic
	st.set_physics_process(false)
	await _shot(abs_dir, "static_outside")
	st.global_position = player.global_position + fwd * 0.5
	st.hint(st.global_position)
	st.set_physics_process(true)
	st.wake()
	await _shot(abs_dir, "static_inside")
	free_error(st)
	await _echo_shot(abs_dir)
	print("error_arena: shots in ", abs_dir)


## 02 §8 Echo at 4 m: the shimmer down a corridor (it has no body; only the refraction).
func _echo_shot(abs_dir: String) -> void:
	var cor := _corridor(3, _stratum != &"halls")
	var cell: Vector2i = cor[0]
	var fwd := _pose_player(cell, cor[1])
	var e := spawn(&"echo", data.grid.world_of(cell) + fwd * Tuning.ECHO_SHIMMER_RANGE) as ErrorEcho
	e.set_physics_process(false)
	EchoPresent.set_presence(e, EchoPresent.presence_at(Tuning.ECHO_SHIMMER_RANGE))
	player.flashlight.set_on(true, true)
	await _shot(abs_dir, "echo_4m_%s" % _stratum)


func free_error(e: ErrorBase) -> void:
	if is_instance_valid(e):
		e.queue_free()
	errors.erase(e)


func _shot(dir: String, name: String) -> void:
	for i in SETTLE_FRAMES:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(name + ".png"))
