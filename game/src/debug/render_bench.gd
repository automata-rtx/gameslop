extends Node3D
## Render bench (02 §13, M1.5): a Halls corridor and room from BoxMeshes with the Halls
## materials, fixtures on the exact 4 m grid, dust, the Halls environment at a preset.
## The seed of the screenshot tour.
##   -- --shots <dir>     capture the Coherence 100/60/30/10, close-ups, noclip (charge,
##                        invalid, commit), Static, drop, ripple and Null frames plus
##                        manifest.json (T1/T3 numbers), then quit
##   -- --preset low|medium|high
## Interactive keys: 1-4 Coherence 100/60/30/10, C charge (aimed at the wall ahead),
## I invalid, N commit, U Null at 8 m (Substrate environment), H hit, S Static, D drop
## (press again for the arrival), R ripple.

const HALLS := preload("res://data/strata/halls.tres")
const SUBSTRATE := preload("res://data/strata/substrate.tres")
const MAT_DIR := "res://data/materials/halls/"
const HEIGHT := 3.0
const WALL_T := 0.2
const CORRIDOR_LEN := 20.0
const ROOM := Vector2(8.0, 8.0)
const EYE := 1.6
const SETTLE_FRAMES := 12
const FIXTURE_LIGHT_DROP := 0.3
const T1_DISTANCES: Array[float] = [2.0, 4.0, 6.0, 8.0, 10.0, 12.0]

var _mats: Dictionary = {}
var _camera: Camera3D
var _fixtures: Array[MeshInstance3D] = []
var _lights: Array[OmniLight3D] = []
var _preset: StringName = Tuning.QUALITY_PRESET_DEFAULT
var _hold_commit: bool = false
var _world_env: WorldEnvironment
var _halls_env: Environment
var _substrate_env: Environment


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var shots_dir := _arg(args, "--shots")
	var preset := _arg(args, "--preset")
	if preset != "":
		_preset = StringName(preset)
	for m in ["wallpaper", "soft_wall", "carpet", "ceiling_tile", "fixture_emissive"]:
		_mats[m] = load(MAT_DIR + m + ".tres")
	_build_environment()
	_build_corridor()
	_build_room()
	_build_fixtures()
	_build_camera()
	_shadow_nearest(int(StratumEnvironment.preset_of(_preset)[&"shadowed"]))
	if shots_dir != "":
		_capture_all.call_deferred(shots_dir)


func _process(_delta: float) -> void:
	if _hold_commit:
		# The bench renders slowly on CPU; re-fire the commit so the 250 ms hold is what shows.
		CoherenceRenderer.pulse(&"noclip_commit")
		CoherenceRenderer._process(0.0)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	match key.keycode:
		KEY_1: CoherenceRenderer.set_coherence(100.0)
		KEY_2: CoherenceRenderer.set_coherence(60.0)
		KEY_3: CoherenceRenderer.set_coherence(30.0)
		KEY_4: CoherenceRenderer.set_coherence(10.0)
		KEY_C:
			_aim_noclip_target()
			CoherenceRenderer.set_noclip_charge(0.0 if CoherenceRenderer.noclip_charge > 0.0 else 0.75)
		KEY_I: CoherenceRenderer.set_noclip_invalid(not CoherenceRenderer.noclip_invalid)
		KEY_N: CoherenceRenderer.pulse(&"noclip_commit")
		KEY_H: CoherenceRenderer.pulse(&"hit")
		KEY_S: CoherenceRenderer.set_static(0.0 if CoherenceRenderer.static_amount > 0.0 else 1.0)
		KEY_D: CoherenceRenderer.pulse(&"drop")
		KEY_R: CoherenceRenderer.pulse(&"ripple")
		KEY_U: _set_null(CoherenceRenderer.null_radius <= 0.0)


# ---------------------------------------------------------------- scene

func _build_environment() -> void:
	_halls_env = StratumEnvironment.build(HALLS, _preset)
	_substrate_env = StratumEnvironment.build(SUBSTRATE, _preset)
	_world_env = WorldEnvironment.new()
	_world_env.environment = _halls_env
	add_child(_world_env)
	StratumEnvironment.apply_viewport_preset(get_viewport(), _preset)


func _box(size: Vector3, center: Vector3, mat_name: String) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mats[mat_name]
	mi.position = center
	add_child(mi)
	return mi


func _slab(size_xz: Vector2, center_xz: Vector2) -> void:
	_box(Vector3(size_xz.x, WALL_T, size_xz.y), Vector3(center_xz.x, -WALL_T * 0.5, center_xz.y), "carpet")
	_box(Vector3(size_xz.x, WALL_T, size_xz.y), Vector3(center_xz.x, HEIGHT + WALL_T * 0.5, center_xz.y), "ceiling_tile")


## Corridor: 2 m wide (one cell), along -Z from z = 0 to z = -20.
func _build_corridor() -> void:
	var half := CORRIDOR_LEN * 0.5
	_slab(Vector2(2.0, CORRIDOR_LEN), Vector2(0.0, -half))
	for side in [-1.0, 1.0]:
		_box(Vector3(WALL_T, HEIGHT, CORRIDOR_LEN), Vector3(side * (1.0 + WALL_T * 0.5), HEIGHT * 0.5, -half), "wallpaper")
	_box(Vector3(2.0 + WALL_T * 2.0, HEIGHT, WALL_T), Vector3(0.0, HEIGHT * 0.5, WALL_T * 0.5), "wallpaper")


## Room: 8 x 8 m at the corridor's end; the back wall's middle 2 m segment is a soft wall.
func _build_room() -> void:
	var z0 := -CORRIDOR_LEN
	var zc := z0 - ROOM.y * 0.5
	_slab(ROOM, Vector2(0.0, zc))
	for side in [-1.0, 1.0]:
		_box(Vector3(WALL_T, HEIGHT, ROOM.y), Vector3(side * (ROOM.x * 0.5 + WALL_T * 0.5), HEIGHT * 0.5, zc), "wallpaper")
		var seg := (ROOM.x - 2.0) * 0.5
		_box(Vector3(seg, HEIGHT, WALL_T), Vector3(side * (1.0 + seg * 0.5), HEIGHT * 0.5, z0 + WALL_T * 0.5), "wallpaper")
		_box(Vector3(seg, HEIGHT, WALL_T), Vector3(side * (1.0 + seg * 0.5), HEIGHT * 0.5, z0 - ROOM.y - WALL_T * 0.5), "wallpaper")
	_box(Vector3(2.0, HEIGHT, WALL_T), Vector3(0.0, HEIGHT * 0.5, z0 - ROOM.y - WALL_T * 0.5), "soft_wall")


## 02 §7 Halls: a 1.2 x 0.3 m recessed tube every 4 m on the exact grid (T2).
func _build_fixtures() -> void:
	var spacing := HALLS.fixture_spacing_m
	var z := -spacing * 0.5
	while z > -CORRIDOR_LEN:
		_fixture(Vector3(0.0, HEIGHT, z))
		z -= spacing
	for fx in [-spacing * 0.5, spacing * 0.5]:
		for fz in [-CORRIDOR_LEN - spacing * 0.5, -CORRIDOR_LEN - spacing * 1.5]:
			_fixture(Vector3(fx, HEIGHT, fz))


func _fixture(at: Vector3) -> void:
	var tube := _box(Vector3(0.3, 0.04, 1.2), at + Vector3(0.0, -0.01, 0.0), "fixture_emissive")
	tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fixtures.append(tube)
	var light := OmniLight3D.new()
	light.light_color = HALLS.fixture_light_color
	light.light_energy = HALLS.fixture_light_energy
	light.omni_range = HALLS.fixture_light_range
	light.shadow_bias = HALLS.shadow_bias
	# Hung below the recess so the ceiling around the tube reads lit.
	light.position = at + Vector3(0.0, -FIXTURE_LIGHT_DROP, 0.0)
	add_child(light)
	_lights.append(light)


func _build_camera() -> void:
	_camera = Camera3D.new()
	# 02 §11: 90° horizontal at 16:9 -> vertical FOV.
	var hfov := deg_to_rad(float(Tuning.CAMERA_FOV_DEFAULT))
	_camera.fov = rad_to_deg(2.0 * atan(tan(hfov * 0.5) * Tuning.CAMERA_ASPECT_REF))
	_camera.near = Tuning.CAMERA_NEAR
	_camera.far = Tuning.CAMERA_FAR
	add_child(_camera)
	_camera.make_current()
	_pose(&"corridor")
	var dust := DustMotes.create(float(StratumEnvironment.preset_of(_preset)[&"particles"]))
	dust.follow = _camera
	add_child(dust)
	# A held flashlight body: same world shader with held = 1 (never jitters or unrenders).
	var held := (_mats["fixture_emissive"] as ShaderMaterial).duplicate() as ShaderMaterial
	held.set_shader_parameter(&"held", 1.0)
	held.set_shader_parameter(&"emission_strength", 0.0)
	held.set_shader_parameter(&"albedo", Color(0.12, 0.12, 0.12))
	var body := CylinderMesh.new()
	body.top_radius = 0.025
	body.bottom_radius = 0.025
	body.height = Tuning.FLASHLIGHT_MODEL_LENGTH
	var mi := MeshInstance3D.new()
	mi.mesh = body
	mi.material_override = held
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0.24, -0.24, -0.5)
	mi.rotation_degrees = Vector3(-75.0, 8.0, 0.0)
	_camera.add_child(mi)


func _pose(name: StringName) -> void:
	match name:
		&"corridor":
			_camera.position = Vector3(0.0, EYE, -0.6)
			_camera.look_at(Vector3(0.0, EYE - 0.25, -12.0))
		&"wall":
			_camera.position = Vector3(0.1, EYE, -7.0)
			_camera.look_at(Vector3(1.0, EYE - 0.3, -8.2))
		&"room":
			_camera.position = Vector3(-0.4, EYE, -17.0)
			_camera.look_at(Vector3(0.3, EYE - 0.2, -28.0))
		&"carpet_close":
			# Looking down at the carpet 1 to 3 m ahead: the loop pile must survive TAA.
			_camera.position = Vector3(0.0, EYE, -3.0)
			_camera.look_at(Vector3(0.0, 0.0, -4.6))
		&"wall_close":
			# 0.9 m from the wallpaper across a stripe edge: print and pinstripes.
			_camera.position = Vector3(0.1, EYE, -5.0)
			_camera.look_at(Vector3(1.0, EYE - 0.15, -5.4))
		&"soft":
			# 1.5 m from the soft wall, aimed at it: the 1 px grid preview shows (02 §5).
			_camera.position = Vector3(-0.6, EYE, -26.5)
			_camera.look_at(Vector3(0.2, EYE - 0.1, -28.0))
	_shadow_nearest(int(StratumEnvironment.preset_of(_preset)[&"shadowed"]))


## 02 §6: the nearest N fixtures cast shadows (LightPool's rule, done by hand here).
func _shadow_nearest(n: int) -> void:
	if _camera == null:
		return
	var sorted := _lights.duplicate()
	var cam := _camera.global_position
	sorted.sort_custom(func(a: OmniLight3D, b: OmniLight3D) -> bool:
		return a.global_position.distance_squared_to(cam) < b.global_position.distance_squared_to(cam))
	for i in sorted.size():
		(sorted[i] as OmniLight3D).shadow_enabled = i < n


func _null_at_8m() -> Vector3:
	return _camera.global_position - _camera.global_basis.z * 8.0


## Null at 8 m ahead, in the Substrate environment (black background, distance fog to
## black), as the tour frames it; off restores the Halls environment.
func _set_null(on: bool) -> void:
	_world_env.environment = _substrate_env if on else _halls_env
	CoherenceRenderer.set_null(_null_at_8m() if on else CoherenceRenderer.NULL_POS_ABSENT,
			Tuning.NULL_UNRENDER_RADIUS if on else 0.0)


## What noclip targeting (M1.4) will do: the crosshair ray's first hit on the bench's
## axis-aligned walls, floor or ceiling (analytic; the bench boxes have no collision).
func _aim_noclip_target() -> void:
	var o := _camera.global_position
	var d := -_camera.global_basis.z
	var best_t := INF
	var best_n := Vector3.ZERO
	var planes: Array[Plane] = [Plane(Vector3.UP, 0.0), Plane(Vector3.DOWN, -HEIGHT),
			Plane(Vector3.LEFT, -1.0), Plane(Vector3.RIGHT, -1.0),
			Plane(Vector3.LEFT, -ROOM.x * 0.5), Plane(Vector3.RIGHT, -ROOM.x * 0.5),
			Plane(Vector3.BACK, -CORRIDOR_LEN - ROOM.y)]
	for p in planes:
		var denom := p.normal.dot(d)
		if denom >= -0.0001:
			continue
		var t := (p.d - p.normal.dot(o)) / denom
		if t > 0.0 and t < best_t:
			best_t = t
			best_n = p.normal
	if is_inf(best_t):
		return
	CoherenceRenderer.set_noclip_target(o + d * best_t, best_n)


# ---------------------------------------------------------------- shots

func _capture_all(dir: String) -> void:
	var abs_dir := dir if dir.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join("..").path_join(dir).simplify_path()
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var manifest: Dictionary = {&"preset": _preset, &"stratum": HALLS.id, &"shots": {}}
	# Let the noise textures generate and the history buffers fill.
	await _frames(SETTLE_FRAMES * 2)
	for c in [100.0, 60.0, 30.0, 10.0]:
		_reset_state()
		_pose(&"corridor")
		CoherenceRenderer.set_coherence(c)
		manifest[&"shots"]["c%03d" % int(c)] = await _shot(abs_dir, "c%03d" % int(c))
	_reset_state()
	_pose(&"room")
	manifest[&"shots"]["room_c100"] = await _shot(abs_dir, "room_c100")
	_pose(&"soft")
	manifest[&"shots"]["soft_wall"] = await _shot(abs_dir, "soft_wall")
	_pose(&"carpet_close")
	manifest[&"shots"]["carpet_close"] = await _shot(abs_dir, "carpet_close")
	_pose(&"wall_close")
	manifest[&"shots"]["wall_close"] = await _shot(abs_dir, "wall_close")
	_reset_state()
	_pose(&"wall")
	CoherenceRenderer.set_coherence(70.0)
	_aim_noclip_target()
	CoherenceRenderer.set_noclip_charge(0.75)
	manifest[&"shots"]["noclip_charge"] = await _shot(abs_dir, "noclip_charge")
	CoherenceRenderer.set_noclip_invalid(true)
	manifest[&"shots"]["noclip_invalid"] = await _shot(abs_dir, "noclip_invalid")
	CoherenceRenderer.set_noclip_invalid(false)
	CoherenceRenderer.set_noclip_charge(0.0)
	_hold_commit = true
	manifest[&"shots"]["noclip_commit"] = await _shot(abs_dir, "noclip_commit")
	_hold_commit = false
	_reset_state()
	_pose(&"corridor")
	CoherenceRenderer.set_static(1.0)
	manifest[&"shots"]["static"] = await _shot(abs_dir, "static")
	_reset_state()
	# Drop arrival a third of the way through its 400 ms fade (wall-clock, so set the age).
	CoherenceRenderer.pulse(&"drop")
	CoherenceRenderer.pulse(&"drop")
	manifest[&"shots"]["drop_black"] = await _shot_at_drop(abs_dir, "drop_black", -1.0)
	manifest[&"shots"]["drop_arrival"] = await _shot_at_drop(abs_dir, "drop_arrival", 0.13)
	_reset_state()
	manifest[&"shots"]["ripple"] = await _shot_at_ripple(abs_dir, "ripple", 0.35)
	_reset_state()
	_set_null(true)
	manifest[&"shots"]["unrender"] = await _shot(abs_dir, "unrender")
	_set_null(false)
	_reset_state()
	var f := FileAccess.open(abs_dir.path_join("manifest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "  "))
	f.close()
	print("render_bench: shots in ", abs_dir)
	get_tree().quit(0)


func _reset_state() -> void:
	# The same reset a run start does (pulses, Static, target, Null).
	CoherenceRenderer._on_run_started(&"bench", 0)
	CoherenceRenderer.set_coherence(Tuning.COHERENCE_MAX)
	CoherenceRenderer.set_null(CoherenceRenderer.NULL_POS_ABSENT, 0.0)


func _frames(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw


func _shot(dir: String, name: String) -> Dictionary:
	await _frames(SETTLE_FRAMES)
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(name + ".png"))
	return _measure(img)


## Pulses are wall-clock and the CPU renderer takes seconds per frame, so the bench pins a
## pulse's age by back-dating it right before the capture frame.
func _shot_at_drop(dir: String, name: String, arrival_age_s: float) -> Dictionary:
	await _frames(SETTLE_FRAMES)
	var now := Time.get_ticks_usec()
	CoherenceRenderer._pulse_at_usec[&"drop"] = now - int((Tuning.NOCLIP_FLOOR_FALL_TIME + 1.0) * 1e6)
	CoherenceRenderer._drop_arrive_usec = -1 if arrival_age_s < 0.0 else now - int(arrival_age_s * 1e6)
	return await _capture_now(dir, name)


func _shot_at_ripple(dir: String, name: String, progress: float) -> Dictionary:
	await _frames(SETTLE_FRAMES)
	CoherenceRenderer._pulse_at_usec[&"ripple"] = Time.get_ticks_usec() - int(progress * Tuning.POST_PULSE_RIPPLE_MS * 1000.0)
	return await _capture_now(dir, name)


## Writes the post uniforms for the pinned state, renders one frame and saves it.
func _capture_now(dir: String, name: String) -> Dictionary:
	CoherenceRenderer._process(0.0)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(name + ".png"))
	return _measure(img)


## T1: luminance of the corridor floor centre line at 2..12 m. T3: darkest percentile and
## clipped-white pixels against the largest fixture's screen area.
func _measure(img: Image) -> Dictionary:
	var floor_luma: Dictionary = {}
	var fwd := -_camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	for d in T1_DISTANCES:
		var p := _camera.global_position + fwd * d
		p.y = 0.0
		if _camera.is_position_behind(p):
			continue
		var px := _camera.unproject_position(p)
		if not Rect2(Vector2.ZERO, Vector2(img.get_size())).has_point(px):
			continue
		floor_luma["%dm" % int(d)] = _luma_at(img, Vector2i(px))
	var lumas: PackedFloat32Array = []
	var clipped := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			lumas.append(0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b)
			if minf(c.r, minf(c.g, c.b)) >= 0.995:
				clipped += 4
	lumas.sort()
	return {
		&"floor_luma": floor_luma,
		&"luma_p01": lumas[int(lumas.size() * 0.01)],
		&"luma_min": lumas[0],
		&"luma_median": lumas[lumas.size() / 2],
		&"clipped_px": clipped,
		&"largest_fixture_px": _largest_fixture_area(),
	}


## Rec. 709 luma of the encoded (display) pixel values, averaged over 5 x 5.
func _luma_at(img: Image, at: Vector2i) -> float:
	var sum := 0.0
	var n := 0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var q := at + Vector2i(dx, dy)
			if q.x < 0 or q.y < 0 or q.x >= img.get_width() or q.y >= img.get_height():
				continue
			var c := img.get_pixel(q.x, q.y)
			sum += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return sum / maxf(n, 1)


func _largest_fixture_area() -> int:
	var best := 0
	for f in _fixtures:
		var aabb := f.global_transform * f.get_aabb()
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var visible := true
		for i in 8:
			var corner := aabb.get_endpoint(i)
			if _camera.is_position_behind(corner):
				visible = false
				break
			var s := _camera.unproject_position(corner)
			lo = lo.min(s)
			hi = hi.max(s)
		if visible:
			var r := Rect2(lo, hi - lo).intersection(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size))
			best = maxi(best, int(r.get_area()))
	return best


static func _arg(args: PackedStringArray, flag: String) -> String:
	var i := args.find(flag)
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	for a in args:
		if a.begins_with(flag + "="):
			return a.substr(flag.length() + 1)
	return ""
