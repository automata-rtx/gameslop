extends Node
## The Coherence renderer's driver (02 §4-§5, 14 §3, §11). Writes the global shader
## parameters every frame from values it is fed through setters and EventBus signals. It
## never reads the player (14 §3).
## It also owns the post stack (02 §4), in two passes:
## - a CanvasLayer (layer -10, under the HUD) running coherence_screen.gdshader after TAA:
##   CA, desaturation, warmth, grain, vignette, scanline, flashes, drop black, ripple. It
##   grades everything the camera drew, transparent surfaces included;
## - a full-screen QuadMesh running coherence_post.gdshader that follows the current 3D
##   camera, shown only while Null is present (g_null_radius > 0): the depth-reading halo
##   and core.
## Curves and pulse shapes: CoherencePost.

const G_COHERENCE := &"g_coherence"
const G_NOCLIP_CHARGE := &"g_noclip_charge"
const G_NOCLIP_COMMIT := &"g_noclip_commit"
const G_NOCLIP_TARGET := &"g_noclip_target"
const G_NOCLIP_TARGET_NORMAL := &"g_noclip_target_normal"
const G_NOCLIP_INVALID := &"g_noclip_invalid"
const G_NULL_POS := &"g_null_pos"
const G_NULL_RADIUS := &"g_null_radius"
const G_TIME := &"g_time"

## 14 §11 declared defaults; also the reset state at run start.
const NULL_POS_ABSENT := Vector3(0.0, -1000.0, 0.0)
const NOCLIP_TARGET_ABSENT := Vector3(0.0, -1000.0, 0.0)
const COHERENCE_MAX := Tuning.COHERENCE_MAX
const POST_SHADER_PATH := "res://shaders/coherence_post.gdshader"
const SCREEN_SHADER_PATH := "res://shaders/coherence_screen.gdshader"
## Canvas layers (CHANGELOG): -20 hide masks, -10 this pass, 0 and up HUD, menus above.
const SCREEN_LAYER := -10
## CoherencePost keys fed to the screen pass (the scene pass reads only the Null globals).
const SCREEN_KEYS: Array[StringName] = [&"ca", &"sat", &"warmth", &"grain", &"vig", &"scan",
		&"invert", &"flash", &"black", &"ripple"]
## Settings keys (12 §3, §6) the renderer listens to.
const SETTING_REDUCE_NOISE := &"reduce_visual_noise"
const SETTING_REDUCE_FLASHING := &"reduce_flashing"
const SETTING_TEXTURE_DETAIL := &"texture_detail"
## The shared stratum noise textures whose resolution follows the Texture detail setting.
const NOISE_TEXTURES: Array[String] = ["res://data/materials/noise_albedo.tres",
		"res://data/materials/noise_normal.tres"]

## Values as written to the globals (normalised where the shader expects 0..1).
var coherence01: float = 1.0
var noclip_charge: float = 0.0
var noclip_commit: float = 0.0
var noclip_target: Vector3 = NOCLIP_TARGET_ABSENT
var noclip_target_normal: Vector3 = Vector3.ZERO
var noclip_invalid: bool = false
var null_pos: Vector3 = NULL_POS_ABSENT
var null_radius: float = 0.0
var world_time: float = 0.0
var threat: float = 0.0
## 0..1 inside Static's field (02 §8): grain toward 0.6, CA toward 0.02.
var static_amount: float = 0.0
var reduce_noise: bool = false
var reduce_flashing: bool = false
## The last uniform set written to the screen pass (CoherencePost.KEYS).
var post_params: Dictionary = {}

## Wall-clock microseconds when each pulse kind last fired (-1 when never).
## Pulses are wall-clock so they keep decaying through hitstop (11 §4).
var _pulse_at_usec: Dictionary = {}
## Process frame each pulse kind last fired at (-1 when never), for 2-frame flashes.
var _pulse_at_frame: Dictionary = {}
## The drop arrival (the second `drop` pulse of a fall); -1 when none.
var _drop_arrive_usec: int = -1
## Heartbeat phase 0..1 (0 on the beat), accumulated so rate changes never jump it.
var _beat_phase: float = 0.0
var _viewports: Array[Viewport] = []
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
	reduce_noise = bool(SettingsManager.get_value(SETTING_REDUCE_NOISE))
	reduce_flashing = bool(SettingsManager.get_value(SETTING_REDUCE_FLASHING))
	var detail: Variant = SettingsManager.get_value(SETTING_TEXTURE_DETAIL)
	if detail != null:
		apply_texture_detail(detail)
	_build_post_quad()
	_write_globals()


func _process(delta: float) -> void:
	# World time freezes with the tree (hitstop, pause) so world-shader motion freezes too.
	if not get_tree().paused:
		world_time = fmod(world_time + delta, Tuning.POST_TIME_WRAP_S)
	advance_heartbeat(delta)
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


## The noclip charge preview, 0..1 (14 interface additions).
func set_noclip_charge(v: float) -> void:
	noclip_charge = clampf(v, 0.0, 1.0)


## Where the charge preview grows (02 §9): the aimed surface point and its normal. Noclip
## targeting feeds it every frame while charging. A zero normal makes the preview a sphere.
func set_noclip_target(pos: Vector3, normal: Vector3) -> void:
	noclip_target = pos
	noclip_target_normal = normal.normalized() if normal.length_squared() > 0.0 else Vector3.ZERO


## 11 §2 noclip invalid: the preview is drawn dashed while set.
func set_noclip_invalid(on: bool) -> void:
	noclip_invalid = on


## 02 §8 inside Static: 0 outside, 1 at full strength (grain 0.6, CA 0.02).
func set_static(amount: float) -> void:
	static_amount = clampf(amount, 0.0, 1.0)


## Kinds: Tuning.POST_PULSE_KINDS. `drop` is fired twice per drop: at the floor commit
## (to black) and on arrival (black to the world over 400 ms).
func pulse(kind: StringName) -> void:
	if not _pulse_at_usec.has(kind):
		push_warning("CoherenceRenderer: unknown pulse kind %s" % kind)
		return
	var now := Time.get_ticks_usec()
	if kind == &"drop":
		var fall_at: int = _pulse_at_usec[kind]
		if fall_at >= 0 and _drop_arrive_usec < 0:
			_drop_arrive_usec = now
			return
		_drop_arrive_usec = -1
	_pulse_at_usec[kind] = now
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
	return _age_of(at)


## The heartbeat rate the vignette pulses at (03 §3: 60 to 140 bpm by threat, never below
## 90 under the danger threshold, 06 §7). Same rule as AudioMix.heartbeat_bpm.
func heartbeat_bpm() -> float:
	return AudioMix.heartbeat_bpm(threat, coherence01 * COHERENCE_MAX)


## Heartbeat phase 0..1, 0 on the beat. AudioManager can lock the heartbeat sample to it.
func heartbeat_phase() -> float:
	return _beat_phase


## Advances the heartbeat phase by `delta` wall seconds at the current rate.
func advance_heartbeat(delta: float) -> void:
	_beat_phase = fmod(_beat_phase + delta * heartbeat_bpm() / 60.0, 1.0)


## SubViewport cameras (monitors, Polaroid) may register. The globals already reach every
## world shader in every viewport; the post stack grades only the main viewport, so a
## registered viewport is only recorded for now (14 interface additions: future work).
func register_viewport(vp: Viewport) -> void:
	if vp != null and not _viewports.has(vp):
		_viewports.append(vp)
		vp.tree_exiting.connect(unregister_viewport.bind(vp), CONNECT_ONE_SHOT)


func unregister_viewport(vp: Viewport) -> void:
	_viewports.erase(vp)


func registered_viewports() -> Array[Viewport]:
	return _viewports.duplicate()


## 12 §3 Texture detail: Low 512², High 1024² for the shared stratum noise textures.
func apply_texture_detail(level: Variant) -> void:
	var low := StringName(str(level)).to_lower() == &"low"
	var size := Tuning.QUALITY_TEXTURE_SIZE_LOW if low else Tuning.QUALITY_TEXTURE_SIZE_HIGH
	for path in NOISE_TEXTURES:
		var tex := load(path) as NoiseTexture2D
		if tex != null and tex.width != size:
			tex.width = size
			tex.height = size


func _age_of(at_usec: int) -> float:
	if at_usec < 0:
		return INF
	return float(Time.get_ticks_usec() - at_usec) / 1_000_000.0


func _on_run_started(_mode: StringName, _seed: int) -> void:
	# 05 §7: the loadout sets the start (Cartographer 90, Diver 70), not always full.
	var start := COHERENCE_MAX
	if GameState.run != null:
		start = GameState.run.coherence
	set_coherence(start)
	noclip_charge = 0.0
	set_noclip_target(NOCLIP_TARGET_ABSENT, Vector3.ZERO)
	noclip_invalid = false
	threat = 0.0
	static_amount = 0.0
	set_null(NULL_POS_ABSENT, 0.0)
	noclip_commit = 0.0
	_clear_pulses()


func _clear_pulses() -> void:
	for kind in Tuning.POST_PULSE_KINDS:
		_pulse_at_usec[kind] = -1
		_pulse_at_frame[kind] = -1
	_drop_arrive_usec = -1


func _write_globals() -> void:
	RenderingServer.global_shader_parameter_set(G_COHERENCE, coherence01)
	RenderingServer.global_shader_parameter_set(G_NOCLIP_CHARGE, noclip_charge)
	RenderingServer.global_shader_parameter_set(G_NOCLIP_COMMIT, noclip_commit)
	RenderingServer.global_shader_parameter_set(G_NOCLIP_TARGET, noclip_target)
	RenderingServer.global_shader_parameter_set(G_NOCLIP_TARGET_NORMAL, noclip_target_normal)
	RenderingServer.global_shader_parameter_set(G_NOCLIP_INVALID, 1.0 if noclip_invalid else 0.0)
	RenderingServer.global_shader_parameter_set(G_NULL_POS, null_pos)
	RenderingServer.global_shader_parameter_set(G_NULL_RADIUS, null_radius)
	RenderingServer.global_shader_parameter_set(G_TIME, world_time)


func _on_setting_changed(key: StringName, value: Variant) -> void:
	if key == SETTING_REDUCE_NOISE:
		reduce_noise = bool(value)
	elif key == SETTING_REDUCE_FLASHING:
		reduce_flashing = bool(value)
	elif key == SETTING_TEXTURE_DETAIL:
		apply_texture_detail(value)


## 02 §4: a 2 x 2 QuadMesh whose vertex shader writes clip space, never culled.
func _build_post_quad() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_post_material = ShaderMaterial.new()
	_post_material.shader = load(POST_SHADER_PATH) as Shader
	# First in the transparent pass: the halo outlines the opaque geometry.
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
	ages[&"drop_arrival"] = _age_of(_drop_arrive_usec)
	var wall_s := Time.get_ticks_msec() / 1000.0
	post_params = CoherencePost.compute(coherence01, noclip_charge, threat, ages, frames, _beat_phase,
			reduce_noise, reduce_flashing, static_amount)
	if _post_quad == null:
		return
	# Functionally parented to the camera: it follows the active 3D camera every frame.
	var cam := get_viewport().get_camera_3d()
	_post_quad.visible = cam != null and null_radius > 0.0
	_screen_layer.visible = cam != null
	if cam == null:
		return
	_post_quad.global_transform = cam.global_transform
	for key in SCREEN_KEYS:
		_screen_material.set_shader_parameter(key, post_params[key])
	_screen_material.set_shader_parameter(&"grain_time", fmod(wall_s, Tuning.POST_TIME_WRAP_S))
