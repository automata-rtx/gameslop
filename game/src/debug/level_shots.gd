class_name LevelShots
extends Node
## Build verification frames for a built level (02 §13 poses, 14 §9): spawn facing the
## longest sightline, a corridor midpoint, the longest corridor from its head (T1 at 12 m),
## the exit room, and a soft wall from 1.3 m. Saves PNGs plus manifest.json with
## the T1 floor luminance at 2..12 m and the T3 numbers (darkest percentile, clipped pixels).
## Run with tools/ci/render.sh (CPU Forward+); it says nothing about frame times.

const EYE := 1.6
const SETTLE_FRAMES := 24
const T1_DISTANCES: Array[float] = [2.0, 4.0, 6.0, 8.0, 10.0, 12.0]
## T1 floor probe: how far below the camera's floor a surface is still searched for (basin
## steps, the far end of a ramp), the steepest surface that counts as floor, and how far the
## hit may sit from its cell's floor height (a car roof does not count).
const FLOOR_PROBE_DEPTH := 3.6
const FLOOR_MIN_NORMAL_Y := 0.7
const FLOOR_HEIGHT_TOLERANCE := 0.3

var _camera: Camera3D
var _level: Level


func capture(level: Level, dir: String) -> void:
	var abs_dir := dir if dir.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join("..").path_join(dir).simplify_path()
	DirAccess.make_dir_recursive_absolute(abs_dir)
	begin(level)
	var manifest: Dictionary = {&"seed": level.data.run_seed, &"stratum": level.data.stratum,
		&"depth": level.data.depth, &"shots": {}, &"overrides": _apply_overrides(level)}
	for pose in poses(level.data):
		_camera.global_position = pose[&"from"]
		_camera.look_at(pose[&"to"])
		level.light_pool.reevaluate()
		await _frames(SETTLE_FRAMES)
		if OS.get_cmdline_user_args().has("--shot-debug-lights"):
			for l in level.light_pool.get_children():
				if l is Light3D and (l as Light3D).visible:
					print("light ", pose[&"name"], " ", (l as Node3D).global_position, " e=", (l as Light3D).light_energy)
			print("camera ", _camera.global_position, " fwd ", -_camera.global_basis.z)
		var img := get_viewport().get_texture().get_image()
		var name: String = pose[&"name"]
		img.save_png(abs_dir.path_join(name + ".png"))
		manifest[&"shots"][name] = _measure(img)
		if pose.has(&"run_m"):
			manifest[&"shots"][name][&"run_m"] = pose[&"run_m"]
	var f := FileAccess.open(abs_dir.path_join("manifest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "  "))
	f.close()
	print("level_shots: ", abs_dir)


## Puts a reference camera in `level` (the player's field of view), makes it current and
## points the light pool and the dust at it. The screenshot tour (ScreenshotTour) shares it.
func begin(level: Level) -> Camera3D:
	_level = level
	_camera = Camera3D.new()
	var hfov := deg_to_rad(float(Tuning.CAMERA_FOV_DEFAULT))
	_camera.fov = rad_to_deg(2.0 * atan(tan(hfov * 0.5) * Tuning.CAMERA_ASPECT_REF))
	_camera.near = Tuning.CAMERA_NEAR
	_camera.far = Tuning.CAMERA_FAR
	level.add_child(_camera)
	_camera.make_current()
	level.light_pool.target = _camera
	if level.dust != null:
		level.dust.follow = _camera
	return _camera


## T1 and T3 numbers of a captured frame (see _measure).
func measure(img: Image) -> Dictionary:
	return _measure(img)


## Tuning aid: `--shot-light-kind omni|spot --shot-spot-angle A --shot-spot-attenuation S
## --shot-light-energy E --shot-light-decay D --shot-light-range R --shot-light-drop M
## --shot-light-out O --shot-pool N --shot-ambient A --shot-ambient-color HEX
## --shot-ao-intensity I --shot-ao-affect L --shot-exposure X --shot-agx-contrast C
## --shot-fog-density D --shot-fog-emission F` override the
## look for this capture only (compare values before Tuning and 02 change);
## `--shot-debug-lights 1` prints the lent lights per pose.
func _apply_overrides(level: Level) -> Dictionary:
	var args := OS.get_cmdline_user_args()
	var out: Dictionary = {}
	var env := level.world_environment.environment
	var pool := level.light_pool
	var relight := false
	for i in args.size() - 1:
		if not args[i].begins_with("--shot-"):
			continue
		var v := args[i + 1].to_float()
		out[args[i]] = args[i + 1]
		match args[i]:
			"--shot-light-kind":
				pool.light_kind = StringName(args[i + 1])
				relight = true
			"--shot-spot-angle":
				pool.spot_angle = v
				relight = true
			"--shot-spot-attenuation":
				pool.spot_attenuation = v
				relight = true
			"--shot-pool":
				pool.pool_size = int(v)
				relight = true
			"--shot-light-drop":
				pool.light_drop = v
				relight = true
			"--shot-light-out":
				pool.light_out = v
				relight = true
			"--shot-light-energy":
				pool.light_energy = v
			"--shot-light-decay":
				pool.light_attenuation = v
				relight = true
			"--shot-light-range":
				pool.light_range = v
				relight = true
			"--shot-ambient":
				env.ambient_light_energy = v
			"--shot-ambient-color":
				env.ambient_light_color = Color(args[i + 1])
			"--shot-ao-intensity":
				env.ssao_intensity = v
			"--shot-exposure":
				env.tonemap_exposure = v
			"--shot-agx-contrast":
				env.tonemap_agx_contrast = v
			"--shot-fog-density":
				env.volumetric_fog_density = v
			"--shot-fog-emission":
				env.volumetric_fog_emission_energy = v
			"--shot-ao-affect":
				env.ssao_light_affect = v
	if relight:
		pool.rebuild_lights()
	return out


func _frames(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw


## The three poses: {name, from, to}.
static func poses(data: LevelData) -> Array[Dictionary]:
	var g := data.grid
	var out: Array[Dictionary] = []
	var eye := Vector3(0, EYE, 0)
	# Spawn, facing the longest sightline: the longest straight walk from any cell of the
	# spawn room, standing at its start.
	var start := data.spawn_cell
	var best := _longest_run_from(g, start)
	var spawn_room := g.room_of(data.spawn_cell)
	if spawn_room != null:
		for c in spawn_room.cells():
			var r := _longest_run_from(g, c)
			if r.y > best.y:
				best = r
				start = c
	var dv := LevelGrid.DIRS[best.x]
	var from := g.world_of(start) + eye - Vector3(dv.x, 0, dv.y) * 0.8
	out.append({&"name": "spawn", &"from": from, &"to": from + Vector3(dv.x, 0, dv.y) * 12.0 + Vector3(0, -0.3, 0)})
	# Corridor midpoint: the middle of the longest straight corridor, looking along it.
	var run := _longest_corridor(g)
	var mid := Vector2i(run.x, run.y) + LevelGrid.DIRS[run.z] * (run.w / 2)
	dv = LevelGrid.DIRS[run.z]
	from = g.world_of(mid) + eye
	out.append({&"name": "corridor", &"from": from, &"to": from + Vector3(dv.x, 0, dv.y) * 12.0 + Vector3(0, -0.3, 0)})
	# The longest straight corridor from its head, looking down its length: the one pose
	# with floor visible out to 12 m, where T1 is measured at its limit (R4 #22).
	from = g.world_of(Vector2i(run.x, run.y)) + eye - Vector3(dv.x, 0, dv.y) * 0.6
	out.append({&"name": "corridor_long", &"from": from, &"to": from + Vector3(dv.x, 0, dv.y) * 12.0 + Vector3(0, -0.3, 0),
		&"run_m": run.w * Tuning.GRID_CELL_SIZE})
	# Exit room: from the far side of the room, looking at the exit wall.
	var ev := LevelGrid.DIRS[data.exit_dir]
	var room := g.room_of(data.exit_cell)
	var back := data.exit_cell
	while room != null and room.has_cell(back - ev):
		back -= ev
	from = g.world_of(back) + eye - Vector3(ev.x, 0, ev.y) * 0.6
	var to := g.world_of(data.exit_cell) + Vector3(ev.x, 0, ev.y) * Tuning.GRID_CELL_SIZE * 0.5 + Vector3(0, 1.2, 0)
	out.append({&"name": "exit_room", &"from": from, &"to": to})
	# A soft wall from 1.3 m, aimed at (02 §5: the band, and the preview inside 2 m).
	if not data.soft_walls.is_empty():
		var e := data.soft_walls[0]
		var sc := Vector2i(e.x, e.y)
		var sv := LevelGrid.DIRS[e.z]
		from = g.world_of(sc) + eye - Vector3(sv.x, 0, sv.y) * 0.4
		out.append({&"name": "soft_wall", &"from": from, &"to": from + Vector3(sv.x, -0.15, sv.y) * 3.0})
	out.append_array(StratumShots.poses(data))
	return out


## Vector2i(dir, cells) of the longest straight walk from c.
static func _longest_run_from(g: LevelGrid, c: Vector2i) -> Vector2i:
	var best := Vector2i(0, -1)
	for d in 4:
		var n := 0
		var p := c
		while g.can_step(p, d):
			p += LevelGrid.DIRS[d]
			n += 1
		if n > best.y:
			best = Vector2i(d, n)
	return best


## Vector4i(x, z, dir, cells) of the longest straight run of corridor cells (E or S).
static func _longest_corridor(g: LevelGrid) -> Vector4i:
	var best := Vector4i(0, 0, LevelGrid.E, 0)
	for i in g.cell_count():
		var c := g.cell_at(i)
		if g.kind(c) != LevelGrid.FLOOR:
			continue
		if prop_cell(g, c):
			continue
		for d: int in [LevelGrid.E, LevelGrid.S]:
			# Only start at the head of a run.
			var back := c - LevelGrid.DIRS[d]
			if g.kind(back) == LevelGrid.FLOOR and g.can_step(back, d) and not prop_cell(g, back):
				continue
			var n := 1
			var p := c
			while g.can_step(p, d) and g.kind(p + LevelGrid.DIRS[d]) == LevelGrid.FLOOR and not prop_cell(g, p + LevelGrid.DIRS[d]):
				p += LevelGrid.DIRS[d]
				n += 1
			if n > best.w:
				best = Vector4i(c.x, c.y, d, n)
	return best


## A floor cell a prop stands on (a parked car, a barrier, a lifeguard chair: the generators
## flag those F_NO_SPAWN outside the spawn and exit rooms). Corridor poses never start in one.
static func prop_cell(g: LevelGrid, c: Vector2i) -> bool:
	return g.has_flag(c, LevelGrid.F_NO_SPAWN) and not g.has_flag(c, LevelGrid.F_SPAWN_ROOM | LevelGrid.F_EXIT_ROOM)


## The floor point T1 reads `d` metres ahead of the camera: on the floor under that point
## (the camera's own floor height, EYE below it, then the walkable surface found straight
## down, so deck 1, ramps and basin steps read where the player stands). Null when there is
## no floor there or it is hidden from the eye (behind a wall, under a car).
func _floor_point(space: PhysicsDirectSpaceState3D, fwd: Vector3, d: float) -> Variant:
	var eye := _camera.global_position
	var p := eye + fwd * d
	p.y = eye.y - EYE
	var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, eye.y, p.z), Vector3(p.x, p.y - FLOOR_PROBE_DEPTH, p.z), 1))
	if down.is_empty() or (down[&"normal"] as Vector3).y < FLOOR_MIN_NORMAL_Y:
		return null
	p = down[&"position"]
	# A car roof or a barrier top is not the floor: the surface must be a walkable cell's floor
	# (or a ramp, whose height runs between two decks).
	if _level != null and _level.data != null:
		var g := _level.data.grid
		var c := g.cell_of(p)
		if g.kind(c) != LevelGrid.RAMP and (not g.is_walkable(c) or absf(p.y - g.floor_y(c)) > FLOOR_HEIGHT_TOLERANCE):
			return null
	# Skip points behind a wall (the ray from the eye to the floor point is blocked).
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, p + Vector3(0, 0.05, 0), 1))
	if not hit.is_empty() or _camera.is_position_behind(p):
		return null
	return p


## T1: floor luma along the view at 2..12 m; T3: darkest percentile and clipped pixels.
func _measure(img: Image) -> Dictionary:
	var floor_luma: Dictionary = {}
	var fwd := -_camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var space := _camera.get_world_3d().direct_space_state
	for d in T1_DISTANCES:
		var found: Variant = _floor_point(space, fwd, d)
		if found == null:
			continue
		var p: Vector3 = found
		# unproject_position works in the viewport's visible rect, which differs from the
		# captured image under a content scale (--resolution 960x540 in a 1920x1080 window).
		var px := _camera.unproject_position(p) * Vector2(img.get_size()) / _camera.get_viewport().get_visible_rect().size
		if Rect2(Vector2.ZERO, Vector2(img.get_size())).has_point(px):
			floor_luma["%dm" % int(d)] = snappedf(_luma_at(img, Vector2i(px)), 0.001)
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
		&"luma_p01": snappedf(lumas[int(lumas.size() * 0.01)], 0.001),
		&"luma_p10": snappedf(lumas[int(lumas.size() * 0.1)], 0.001),
		&"luma_median": snappedf(lumas[lumas.size() / 2], 0.001),
		&"luma_p90": snappedf(lumas[int(lumas.size() * 0.9)], 0.001),
		&"clipped_px": clipped,
		&"active_lights": _level.light_pool.active_light_count(),
	}


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
