class_name Landing
extends Node3D
## The Landing (05 §4, GLOSSARY): a small enclosed cabin between levels after a proper exit.
## Built from primitives (02 T8). For 6 s the cabin shudders, the world shader's unrender
## ripple crosses once, and the panel offers two items; the next level generates meanwhile.
## The door opens only when the level is ready (07 §3, CHANGELOG "Landing holds the door"):
## after 6 s and the navigation bake, or 3 s later with walkable geometry at least.
## The run owns the player and the level; it feeds `level_walkable` / `level_built` and
## awaits `finished` (signals up, calls down).
## Halls, Garage, Offices use the elevator cabin; the stairwell and white pocket of 05 §4
## are later strata's (M2).

signal choice_made(kind: StringName)
signal door_opened
signal finished

const CABIN_SIZE := Vector3(2.0, 2.4, 2.0)
const WALL := 0.1
const DOOR_WIDTH := 1.0
const DOOR_HEIGHT := 2.1
const DOOR_X := -0.35
const PANEL_SIZE := Vector2(0.64, 0.36)
const PANEL_POS := Vector3(0.6, 1.5, -0.94)
const PLAYER_POS := Vector3(0.0, 0.0, 0.45)
const SHUDDER_M := 0.004
const SHUDDER_HZ := Vector2(31.0, 23.0)
const DOOR_TIME := 0.6
const CEILING_EMISSION := 2.5
const LIGHT_ENERGY := 0.9
const METAL := "res://data/materials/halls/prop_metal.tres"
const BLACK := "res://data/materials/halls/prop_black.tres"
const EMISSIVE := "res://data/materials/halls/fixture_emissive.tres"

## Seconds the cabin holds (Tuning.LANDING_TIME; tests shorten it).
var landing_time: float = Tuning.LANDING_TIME
var level_walkable: bool = false
var level_built: bool = false
var elapsed: float = 0.0
var running: bool = false
var door_open: bool = false
var panel: LandingPanel
var geometry: Node3D
var _door_l: MeshInstance3D
var _door_r: MeshInstance3D
var _viewport: SubViewport
var _panel_quad: MeshInstance3D
var _rippled: bool = false
var _hum: AudioLoop
var _player: Node3D


func _init() -> void:
	name = "Landing"
	geometry = Node3D.new()
	geometry.name = "Cabin"
	add_child(geometry)
	_build_cabin()
	_build_panel()
	set_process(false)


## 05 §4 open/close rule (07 §3): may the door open now?
static func door_may_open(t: float, hold: float, built: bool, walkable: bool) -> bool:
	if t < hold or not walkable:
		return false
	return built or t >= hold + Tuning.LANDING_MAX_EXTRA_WAIT


## Starts the Landing with `player` standing in the cabin (the run re-parents it here).
func begin(player: Node3D, choices: Array[StringName], hint: bool) -> void:
	_player = player
	panel.setup(choices, Tuning.COHERENCE_GAIN_PROPER_EXIT, hint)
	elapsed = 0.0
	running = true
	set_process(true)
	_hum = AudioManager.loop(&"fixture_hum_halls")
	if _hum != null:
		_hum.start(0.3)
	AudioManager.play_2d(&"exit_latch")


## Where the player stands, facing the door and the panel.
func player_transform() -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, PLAYER_POS)


func _process(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	if not door_open:
		# 05 §4 the cabin shudders (and keeps shuddering while the door is held, 07 §3).
		geometry.position = Vector3(sin(elapsed * SHUDDER_HZ.x) * SHUDDER_M, sin(elapsed * SHUDDER_HZ.y) * SHUDDER_M * 0.7, 0.0)
	if not _rippled and elapsed >= landing_time * Tuning.LANDING_RIPPLE_AT:
		_rippled = true
		CoherenceRenderer.pulse(&"ripple")
	if not door_open and door_may_open(elapsed, landing_time, level_built, level_walkable):
		_open_door()


func _open_door() -> void:
	door_open = true
	geometry.position = Vector3.ZERO
	AudioManager.play_2d(&"exit_open")
	if _hum != null:
		_hum.stop(DOOR_TIME)
	door_opened.emit()
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_door_l, ^"position:x", DOOR_X - DOOR_WIDTH * 0.75, DOOR_TIME)
	tw.tween_property(_door_r, ^"position:x", DOOR_X + DOOR_WIDTH * 0.75, DOOR_TIME)
	tw.chain().tween_callback(func() -> void:
		running = false
		finished.emit())


func _exit_tree() -> void:
	if _hum != null:
		_hum.release()
		_hum = null


# --- choice input (05 §4: keys or click) ---------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not running:
		return
	if event.is_action_pressed(&"item_1"):
		_choose(0)
	elif event.is_action_pressed(&"item_2"):
		_choose(1)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var slot := slot_under_crosshair()
		if slot >= 0:
			_choose(slot)


func _choose(i: int) -> void:
	if panel.choose(i):
		choice_made.emit(panel.kinds[i])
		get_viewport().set_input_as_handled()


## The panel row the camera's centre ray points at, or -1.
func slot_under_crosshair() -> int:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return -1
	var t := _panel_quad.global_transform
	var n := t.basis.z.normalized()
	var dir := -cam.global_transform.basis.z
	var denom := dir.dot(n)
	if absf(denom) < 0.0001:
		return -1
	var d := (t.origin - cam.global_position).dot(n) / denom
	if d <= 0.0:
		return -1
	var local := t.affine_inverse() * (cam.global_position + dir * d)
	if absf(local.x) > PANEL_SIZE.x * 0.5 or absf(local.y) > PANEL_SIZE.y * 0.5:
		return -1
	# Rows sit in the upper half: row 0 above row 1 (the panel's layout, top to bottom).
	var v := 0.5 - local.y / PANEL_SIZE.y
	if panel.kinds.is_empty():
		return -1
	var row_px := v * LandingPanel.SIZE.y
	var first := float(LandingPanel.PAD + (56 if panel._hint.visible else 0))
	var idx := int((row_px - first) / 48.0)
	return idx if idx >= 0 and idx < panel.kinds.size() else -1


# --- geometry -------------------------------------------------------------------------------

func _build_cabin() -> void:
	var metal := load(METAL) as Material
	var black := load(BLACK) as Material
	var hw := CABIN_SIZE.x * 0.5
	var hd := CABIN_SIZE.z * 0.5
	var h := CABIN_SIZE.y
	_box(Vector3(CABIN_SIZE.x, WALL, CABIN_SIZE.z), Vector3(0, -WALL * 0.5, 0), black, true)
	_box(Vector3(CABIN_SIZE.x, WALL, CABIN_SIZE.z), Vector3(0, h + WALL * 0.5, 0), metal, false)
	_box(Vector3(WALL, h, CABIN_SIZE.z), Vector3(-hw - WALL * 0.5, h * 0.5, 0), metal, true)
	_box(Vector3(WALL, h, CABIN_SIZE.z), Vector3(hw + WALL * 0.5, h * 0.5, 0), metal, true)
	_box(Vector3(CABIN_SIZE.x, h, WALL), Vector3(0, h * 0.5, hd + WALL * 0.5), metal, true)
	# Front wall around the door opening.
	var left_w := DOOR_X - DOOR_WIDTH * 0.5 + hw
	var right_w := hw - (DOOR_X + DOOR_WIDTH * 0.5)
	_box(Vector3(left_w, h, WALL), Vector3(-hw + left_w * 0.5, h * 0.5, -hd - WALL * 0.5), metal, true)
	_box(Vector3(right_w, h, WALL), Vector3(hw - right_w * 0.5, h * 0.5, -hd - WALL * 0.5), metal, true)
	_box(Vector3(DOOR_WIDTH, h - DOOR_HEIGHT, WALL), Vector3(DOOR_X, (h + DOOR_HEIGHT) * 0.5, -hd - WALL * 0.5), metal, true)
	_door_l = _box(Vector3(DOOR_WIDTH * 0.5, DOOR_HEIGHT, 0.04), Vector3(DOOR_X - DOOR_WIDTH * 0.25, DOOR_HEIGHT * 0.5, -hd + 0.03), metal, false)
	_door_r = _box(Vector3(DOOR_WIDTH * 0.5, DOOR_HEIGHT, 0.04), Vector3(DOOR_X + DOOR_WIDTH * 0.25, DOOR_HEIGHT * 0.5, -hd + 0.03), metal, false)
	# Handrail and the ceiling light panel.
	_box(Vector3(0.04, 0.04, CABIN_SIZE.z * 0.8), Vector3(hw - 0.06, 0.95, 0), black, false)
	var lit := (load(EMISSIVE) as Material).duplicate() as ShaderMaterial
	if lit != null:
		lit.set_shader_parameter(&"emission_strength", CEILING_EMISSION)
	_box(Vector3(1.2, 0.03, 1.2), Vector3(0, h - 0.015, 0), lit, false)
	var light := OmniLight3D.new()
	light.name = "CabinLight"
	light.position = Vector3(0, h - 0.3, 0)
	light.omni_range = 3.5
	light.light_energy = LIGHT_ENERGY
	light.light_color = Color(1.0, 0.94, 0.78)
	geometry.add_child(light)


func _box(sz: Vector3, pos: Vector3, mat: Material, solid: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	geometry.add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = PlayerLayers.WORLD_MASK
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = sz
		cs.shape = shape
		body.add_child(cs)
		body.position = pos
		geometry.add_child(body)
	return mi


func _build_panel() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "PanelViewport"
	_viewport.size = LandingPanel.SIZE
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	panel = LandingPanel.new()
	panel.name = "LandingPanel"
	_viewport.add_child(panel)
	add_child(_viewport)
	_panel_quad = MeshInstance3D.new()
	_panel_quad.name = "PanelQuad"
	var q := QuadMesh.new()
	q.size = PANEL_SIZE
	_panel_quad.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _viewport.get_texture()
	_panel_quad.material_override = mat
	_panel_quad.position = PANEL_POS
	geometry.add_child(_panel_quad)
