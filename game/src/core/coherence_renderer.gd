extends Node
## The Coherence renderer's driver (02 §4-§5, 14 §3, §11). Writes the six global
## shader parameters every frame from values it is fed through setters and
## EventBus signals. It never reads the player (14 §3).
## It also owns the post stack (02 §4): a full-screen QuadMesh running
## coherence_post.gdshader that follows the current 3D camera (desaturation, vignette,
## Null halo: the depth-reading scene pass), and a CanvasLayer running
## coherence_screen.gdshader after TAA (CA, grain, scanline, flashes). Curves and pulse
## shapes: CoherencePost.

const G_COHERENCE := &"g_coherence"
const G_NOCLIP_CHARGE := &"g_noclip_charge"
const G_NOCLIP_COMMIT := &"g_noclip_commit"
const G_NULL_POS := &"g_null_pos"
const G_NULL_RADIUS := &"g_null_radius"
const G_TIME := &"g_time"

## 14 §11 declared defaults; also the reset state at run start.
const NULL_POS_ABSENT := Vector3(0.0, -1000.0, 0.0)
const COHERENCE_MAX := Tuning.COHERENCE_MAX
const POST_SHADER_PATH := "res://shaders/coherence_post.gdshader"
const SCREEN_SHADER_PATH := "res://shaders/coherence_screen.gdshader"
## Below the HUD and menus (layer 0 and up): the HUD is never grained.
const SCREEN_LAYER := -10
## Which CoherencePost keys feed which pass.
const SCENE_KEYS: Array[StringName] = [&"sat", &"warmth", &"vig"]
const SCREEN_KEYS: Array[StringName] = [&"ca", &"grain", &"scan", &"invert", &"flash"]
## Settings keys (12 §6) the post stack listens to.
const SETTING_REDUCE_NOISE := &"reduce_visual_noise"
const SETTING_REDUCE_FLASHING := &"reduce_flashing"

## Values as written to the globals (normalised where the shader expects 0..1).
var coherence01: float = 1.0
var noclip_charge: float = 0.0
var noclip_commit: float = 0.0
var null_pos: Vector3 = NULL_POS_ABSENT
var null_radius: float = 0.0
var world_time: float = 0.0
var threat: float = 0.0
var reduce_noise: bool = false
var reduce_flashing: bool = false
## The last uniform set written to the post shader (CoherencePost.KEYS).
var post_params: Dictionary = {}

## Wall-clock microseconds when each pulse kind last fired (-1 when never).
## Pulses are wall-clock so they keep decaying through hitstop (11 §4).
var _pulse_at_usec: Dictionary = {}
## Process frame each pulse kind last fired at (-1 when never), for 2-frame flashes.
var _pulse_at_frame: Dictionary = {}
var _post_quad: MeshInstance3D
var _post_material: ShaderMaterial
var _screen_layer: CanvasLayer
var _screen_material: ShaderMaterial


func _ready() -> void:
	# 11 §4: the post stack keeps running through hitstop and the pause menu.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_clear_pulses()
	EventBus.threat_changed.connect(set_threat)
	EventBus.run_started.connect(_on_run_started)
	SettingsManager.changed.connect(_on_setting_changed)
	_build_post_quad()
	_write_globals()


func _process(delta: float) -> void:
	# World time freezes with the tree (hitstop, pause) so world-shader motion freezes too.
	if not get_tree().paused:
		world_time = fmod(world_time + delta, Tuning.POST_TIME_WRAP_S)
	noclip_commit = CoherencePost.commit_envelope(pulse_age(&"noclip_commit"))
	_write_globals()
	_update_post()


## Coherence in player units (0..COHERENCE_MAX); written to g_coherence as 0..1.
func set_coherence(v: float) -> void:
	coherence01 = clampf(v / COHERENCE_MAX, 0.0, 1.0)


func set_threat(v: float) -> void:
	threat = clampf(v, 0.0, 1.0)


func set_null(pos: Vector3, radius: float) -> void:
	null_pos = pos
	null_radius = maxf(radius, 0.0)


## Proposed Interfaces addition (02): the noclip charge preview, 0..1.
func set_noclip_charge(v: float) -> void:
	noclip_charge = clampf(v, 0.0, 1.0)


func pulse(kind: StringName) -> void:
	if not _pulse_at_usec.has(kind):
		push_warning("CoherenceRenderer: unknown pulse kind %s" % kind)
		return
	_pulse_at_usec[kind] = Time.get_ticks_usec()
	_pulse_at_frame[kind] = Engine.get_process_frames()
	if kind == &"noclip_commit":
		noclip_commit = 1.0


## Process frames since `kind` last fired; -1 if never.
func pulse_frames(kind: StringName) -> int:
	var at: int = _pulse_at_frame.get(kind, -1)
	if at < 0:
		return -1
	return Engine.get_process_frames() - at


## The post quad node (for benches and tests); null before _ready.
func post_quad() -> MeshInstance3D:
	return _post_quad


## The after-TAA screen pass layer (for benches and tests); null before _ready.
func screen_layer() -> CanvasLayer:
	return _screen_layer


## Seconds since `kind` last fired; INF if never.
func pulse_age(kind: StringName) -> float:
	var at: int = _pulse_at_usec.get(kind, -1)
	if at < 0:
		return INF
	return float(Time.get_ticks_usec() - at) / 1_000_000.0


func _on_run_started(_mode: StringName, _seed: int) -> void:
	# 05 §7: the loadout sets the start (Cartographer 90, Diver 70), not always full.
	var start := COHERENCE_MAX
	if GameState.run != null:
		start = GameState.run.coherence
	set_coherence(start)
	noclip_charge = 0.0
	threat = 0.0
	set_null(NULL_POS_ABSENT, 0.0)
	noclip_commit = 0.0
	_clear_pulses()


func _clear_pulses() -> void:
	for kind in Tuning.POST_PULSE_KINDS:
		_pulse_at_usec[kind] = -1
		_pulse_at_frame[kind] = -1


func _write_globals() -> void:
	RenderingServer.global_shader_parameter_set(G_COHERENCE, coherence01)
	RenderingServer.global_shader_parameter_set(G_NOCLIP_CHARGE, noclip_charge)
	RenderingServer.global_shader_parameter_set(G_NOCLIP_COMMIT, noclip_commit)
	RenderingServer.global_shader_parameter_set(G_NULL_POS, null_pos)
	RenderingServer.global_shader_parameter_set(G_NULL_RADIUS, null_radius)
	RenderingServer.global_shader_parameter_set(G_TIME, world_time)


func _on_setting_changed(key: StringName, value: Variant) -> void:
	if key == SETTING_REDUCE_NOISE:
		reduce_noise = bool(value)
	elif key == SETTING_REDUCE_FLASHING:
		reduce_flashing = bool(value)


## 02 §4: a 2 x 2 QuadMesh whose vertex shader writes clip space, never culled.
func _build_post_quad() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_post_material = ShaderMaterial.new()
	_post_material.shader = load(POST_SHADER_PATH) as Shader
	# First in the transparent pass: it reads the opaque image; transparent effects
	# (dust, Static's field, water) draw over it and read g_coherence themselves (02 §5).
	_post_material.render_priority = Material.RENDER_PRIORITY_MIN
	_post_quad = MeshInstance3D.new()
	_post_quad.name = "CoherencePost"
	_post_quad.mesh = quad
	_post_quad.material_override = _post_material
	_post_quad.extra_cull_margin = 16384.0
	_post_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_post_quad.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_post_quad.visible = false
	add_child(_post_quad)
	_screen_material = ShaderMaterial.new()
	_screen_material.shader = load(SCREEN_SHADER_PATH) as Shader
	var rect := ColorRect.new()
	rect.name = "CoherenceScreen"
	rect.material = _screen_material
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen_layer = CanvasLayer.new()
	_screen_layer.layer = SCREEN_LAYER
	_screen_layer.visible = false
	_screen_layer.add_child(rect)
	add_child(_screen_layer)


func _update_post() -> void:
	var ages: Dictionary = {}
	var frames: Dictionary = {}
	for kind in Tuning.POST_PULSE_KINDS:
		ages[kind] = pulse_age(kind)
		frames[kind] = pulse_frames(kind)
	var wall_s := Time.get_ticks_msec() / 1000.0
	post_params = CoherencePost.compute(coherence01, noclip_charge, threat, ages, frames, wall_s,
			reduce_noise, reduce_flashing)
	if _post_quad == null:
		return
	# Functionally parented to the camera: it follows the active 3D camera every frame.
	var cam := get_viewport().get_camera_3d()
	_post_quad.visible = cam != null
	_screen_layer.visible = cam != null
	if cam == null:
		return
	_post_quad.global_transform = cam.global_transform
	for key in SCENE_KEYS:
		_post_material.set_shader_parameter(key, post_params[key])
	for key in SCREEN_KEYS:
		_screen_material.set_shader_parameter(key, post_params[key])
	_screen_material.set_shader_parameter(&"grain_time", fmod(wall_s, Tuning.POST_TIME_WRAP_S))
