class_name BuildSlopes
extends RefCounted
## Ramps for BuildPlan (07 §8, M2.1). A ramp run is a line of RAMP cells rising along one
## direction (LevelGrid.set_ramp): Garage ramps between the decks slope floor and ceiling
## together (the plan's elements carry a sloped interval; this class draws the faces that
## slant along a ramp's sides), and a Pools basin's steps are a stepped block standing on
## the basin floor under the hall's level ceiling (07 §5.2: "built as a stepped mesh with
## step 0.25 m"). Collision for both is one sloped convex shape per cell (BuildCollision):
## the slope runs through the middle of every riser.

var plan: BuildPlan
var grid: LevelGrid


func _init(p: BuildPlan) -> void:
	plan = p
	grid = p.grid


## Floor below a ramp run: the floor of the cell before its first cell.
func run_bottom(c: Vector2i) -> float:
	var up := grid.ramp_dir_of(c)
	var p := c
	var guard := grid.cell_count()
	while grid.kind(p) == LevelGrid.RAMP and guard > 0:
		guard -= 1
		p -= LevelGrid.DIRS[up]
	return grid.floor_y(p)


## Floor above a ramp run: the floor of the cell after its last cell.
func run_top(c: Vector2i) -> float:
	var up := grid.ramp_dir_of(c)
	var p := c
	var guard := grid.cell_count()
	while grid.kind(p) == LevelGrid.RAMP and guard > 0:
		guard -= 1
		p += LevelGrid.DIRS[up]
	return grid.floor_y(p)


## A vertical face whose bottom and top run linearly along it: part = (lo, hi) at us[0]
## and (lo, hi) at the last break. Subdivided to at most 0.5 m up its tallest side.
func slanted_face(acc: Dictionary, us: PackedFloat32Array, part: Vector4, plane: float, along_x: bool,
		n: Vector3, col: Color) -> void:
	var tall := maxf(part.y - part.x, part.w - part.z)
	if tall < 0.0001:
		return
	var rows := maxi(1, ceili(tall / Tuning.LEVELBUILD_MESH_MAX_EDGE - 0.0001))
	var vs := PackedFloat32Array()
	for k in rows + 1:
		vs.append(float(k) / rows)
	var u0 := us[0]
	var u1 := us[us.size() - 1]
	plan._mesh.patch(acc, us, vs, func(u: float, v: float) -> Vector3:
		var t := (u - u0) / (u1 - u0)
		var y := lerpf(lerpf(part.x, part.z, t), lerpf(part.y, part.w, t), v)
		return Vector3(plane, y, u) if along_x else Vector3(u, y, plane), n, col)


## Pools steps (level-ceiling strata only): one stepped block per run, from the basin floor
## to the rim, across the run's 1.8 m interior. Risers of at most POOLS_STEP_HEIGHT; the
## sides show where the next cell over is lower (an open basin), not against the rim wall.
func stairs() -> void:
	if plan.follow:
		return
	for i in grid.cell_count():
		var c := grid.cell_at(i)
		var up := grid.ramp_dir_of(c)
		if up < 0 or grid.kind(c - LevelGrid.DIRS[up]) == LevelGrid.RAMP:
			continue
		var run: Array[Vector2i] = [c]
		while grid.kind(run[run.size() - 1] + LevelGrid.DIRS[up]) == LevelGrid.RAMP:
			run.append(run[run.size() - 1] + LevelGrid.DIRS[up])
		_stair(run, up)


func _stair(run: Array[Vector2i], up: int) -> void:
	var dv := LevelGrid.DIRS[up]
	var x_axis := dv.x != 0
	var sgn := float(dv.x + dv.y)
	var lo := run_bottom(run[0])
	var hi := run_top(run[0])
	var steps := maxi(1, ceili((hi - lo) / Tuning.POOLS_STEP_HEIGHT - 0.0001))
	var rise := (hi - lo) / steps
	var half := (Tuning.GRID_CELL_SIZE - Tuning.GRID_WALL_THICKNESS) * 0.5
	var first := (run[0].x if x_axis else run[0].y) * Tuning.GRID_CELL_SIZE
	var last := (run[run.size() - 1].x if x_axis else run[run.size() - 1].y) * Tuning.GRID_CELL_SIZE
	var s0 := first - sgn * half
	var s1 := last + sgn * half
	var tread := (s1 - s0) / steps
	var lat_c := (run[0].y if x_axis else run[0].x) * Tuning.GRID_CELL_SIZE
	var lats := PackedFloat32Array()
	var cols := ceili(2.0 * half / Tuning.LEVELBUILD_MESH_MAX_EDGE - 0.0001)
	for k in cols + 1:
		lats.append(lat_c - half + 2.0 * half * k / cols)
	var acc := plan._mesh.acc(Vector2i(run[0].x / plan.chunk_cells, run[0].y / plan.chunk_cells), BuildPlan.C_BASIN, -1)
	var col := Color(0.5, 0.0, 0.0, 0.0)
	var at := func(s: float, l: float, y: float) -> Vector3:
		return Vector3(s, y, l) if x_axis else Vector3(l, y, s)
	var along_n := Vector3(-sgn, 0.0, 0.0) if x_axis else Vector3(0.0, 0.0, -sgn)
	# Sides open to a lower neighbour (the basin) show the block's stepped profile.
	var side_dirs: Array[int] = [(up + 1) % 4, (up + 3) % 4]
	for k in steps:
		var y := lo + rise * (k + 1)
		# Tread k runs from its riser (mid-way between slope points) to the next riser.
		var a := s0 + tread * (k + 0.5)
		var b := s0 + tread * minf(k + 1.5, steps)
		plan._mesh.patch(acc, PackedFloat32Array([a, b]), lats, func(s: float, l: float) -> Vector3: return at.call(s, l, y), Vector3.UP, col)
		var rows := PackedFloat32Array([y - rise, y])
		plan._mesh.patch(acc, lats, rows, func(l: float, yy: float) -> Vector3: return at.call(a, l, yy), along_n, col)
		for d in side_dirs:
			var o := run[0] + LevelGrid.DIRS[d]
			if grid.is_open(o) and grid.floor_y(o) >= y - 0.0001:
				continue
			var sd := LevelGrid.DIRS[d]
			var l := lat_c + float(sd.x + sd.y) * half
			var side_n := Vector3(float(sd.x), 0.0, float(sd.y))
			plan._mesh.patch(acc, PackedFloat32Array([a, b]), PackedFloat32Array([lo, y]),
				func(s: float, yy: float) -> Vector3: return at.call(s, l, yy), side_n, col)
