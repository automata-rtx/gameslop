class_name BuildPlan
extends RefCounted
## The level's geometry as pure data (07 §8): merged mesh arrays per 8x8-cell chunk and
## surface class, collision boxes with the noclip metadata of 07 §7, and navigation source
## faces. No nodes and no autoloads, so it runs on a worker thread; LevelBuilder turns it
## into nodes in 4 ms slices on the main thread.
##
## Geometry model: each cell axis is split at its edge strips, so the plan sees a fine grid
## of (2W+1) x (2H+1) elements: cell interiors (1.8 m), edge strips (0.2 m, the wall
## thickness) and corner posts (0.2 m). Each element is solid except for one open interval
## [lo, hi] of heights: a cell from its floor to its ceiling (M2.1: per-cell floors, Garage
## decks at +3.2 m, Pools basins below 0), a door strip up to the door height, a partition
## strip above 1.5 m. A Garage ramp's interval slopes along its run (BuildSlopes). Visible
## faces are exactly the boundaries between solid and open parts, so walls, floors, basin
## sides and ceilings meet without overlap. Every face is subdivided on one global lattice
## (element breaks along X and Z; 0.5 m steps plus every floor, ceiling, door and partition
## height along Y), so faces that share an edge share its vertices: no T-junctions (sloped
## faces excepted), and the world shader's vertex jitter moves coincident vertices together.

## Surface classes. Each chunk gets one mesh per class it uses; soft walls get their own
## mesh per edge (09 §8: the soft uniform must differ per segment). C_BASIN: a pool's floor,
## sides and steps (07 §8 "basin" surface class).
const C_FLOOR := 0
const C_CEILING := 1
const C_WALL := 2
const C_PARTITION := 3
const C_GLASS := 4
const C_SOFT := 5
const C_BASIN := 6
const CLASS_NAMES: Array[StringName] = [&"floor", &"ceiling", &"wall", &"partition", &"glass", &"soft", &"basin"]

## Body keys for collision. Wall bodies are split by wall type so the body itself carries
## a single `wall_kind` meta (noise wall counting reads it from the collider).
const BODY_FLOOR := &"floor"
## Solid blocks filling void cells next to walkable space (meta `void`, no `wall_kind`).
const BODY_VOID := &"void"
## Pools: the invisible edge of deep water (07 §5.2 "SOLID for movement"; meta `rail`).
const BODY_RAIL := &"rail"

## Strata whose grids the plan models faithfully (M2.1: heights, ramps, basins, pillars).
const SUPPORTED_STRATA: Array[StringName] = [&"halls", &"pools", &"garage"]
## Strata whose ceiling stays level over sunken floors (a pool hall's 6 m ceiling); every
## other stratum's ceiling is the room height above the floor (Garage decks and ramps).
const FLAT_CEILING_STRATA: Array[StringName] = [&"pools"]

var grid: LevelGrid
var height: float = 3.0
var chunk_cells: int = 8
var chunks: Vector2i = Vector2i.ONE
## True when ceilings follow floors (not FLAT_CEILING_STRATA).
var follow: bool = true

## Mesh surfaces: Array of {key: String, chunk: Vector2i, cls: int, soft: int (edge index
## or -1), arrays: Array (Mesh.ARRAY_MAX), aabb: AABB}.
var meshes: Array[Dictionary] = []
## Collision shapes: Array of {body: String, chunk: Vector2i, kind: StringName (wall type
## name, &"floor", &"void" or &"rail"), size: Vector3, pos: Vector3, meta: Dictionary,
## points: PackedVector3Array (a convex shape instead of the box, ramps)}.
var boxes: Array[Dictionary] = []
## Triangle soup for the navigation bake: floors (walkable) and wall faces (obstacles).
var nav_faces: PackedVector3Array = PackedVector3Array()
var triangle_count: int = 0
## Problems found while planning (also pushed as errors), e.g. an unsupported stratum.
var errors: PackedStringArray = PackedStringArray()

# Fine grid: open flag, the open interval at the element's low and high end along its slope
# axis (flat: equal), the slope axis (-1 flat, 0 x, 1 z), bottom and top face classes, the
# class and soft index of its solid faces, and whether its floor feeds navigation.
var _fw: int = 0
var _fh: int = 0
var _open: PackedByteArray = PackedByteArray()
var _lo: PackedVector2Array = PackedVector2Array()
var _hi: PackedVector2Array = PackedVector2Array()
var _axis: PackedInt32Array = PackedInt32Array()
var _bot: PackedByteArray = PackedByteArray()
var _top: PackedByteArray = PackedByteArray()
var _cls: PackedByteArray = PackedByteArray()
var _soft: PackedInt32Array = PackedInt32Array()
var _nav: PackedByteArray = PackedByteArray()
var _door: PackedByteArray = PackedByteArray()
# Lattice breaks per fine column / row, and global Y breaks.
var _xb: Array[PackedFloat32Array] = []
var _zb: Array[PackedFloat32Array] = []
var _yb: PackedFloat32Array = PackedFloat32Array()
var _door_h: float = 2.1
var _part_h: float = 1.5
var _mesh: BuildMesh = BuildMesh.new()
var _slopes: BuildSlopes = null
# Edge key (Vector3i, E/S form) -> index in LevelData.soft_walls.
var _soft_index: Dictionary = {}


## Computes the whole plan. `ceiling_height` is the room height (Garage: per deck).
static func make(level: LevelData, ceiling_height: float) -> BuildPlan:
	var p := BuildPlan.new()
	p.grid = level.grid
	p.height = ceiling_height
	p.follow = not FLAT_CEILING_STRATA.has(level.stratum)
	p.chunk_cells = Tuning.LEVELBUILD_CHUNK_CELLS
	p._door_h = Tuning.LEVELBUILD_DOOR_HEIGHT
	p._part_h = Tuning.GRID_PARTITION_HEIGHT
	p.chunks = Vector2i(ceili(level.grid.size.x / float(p.chunk_cells)), ceili(level.grid.size.y / float(p.chunk_cells)))
	if not SUPPORTED_STRATA.has(level.stratum):
		p.errors.append("BuildPlan: stratum '%s' has special cells this plan does not model yet; built as far as it can" % level.stratum)
		push_error(p.errors[p.errors.size() - 1])
	p._slopes = BuildSlopes.new(p)
	for k in level.soft_walls.size():
		var e := level.soft_walls[k]
		p._soft_index[LevelGrid.edge_key(Vector2i(e.x, e.y), e.z)] = k
	p._lattice()
	p._classify()
	var faces := BuildFaces.new(p)
	faces.emit_horizontal()
	faces.emit_vertical()
	p._slopes.stairs()
	p._mesh.finish()
	p.meshes = p._mesh.meshes
	p.nav_faces = p._mesh.nav_faces
	p.triangle_count = p._mesh.triangle_count
	p.boxes = BuildCollision.boxes(p)
	return p


# ---------------------------------------------------------------- cells

## Ceiling over cell c at floor height y (a level ceiling in pools, room height above).
func ceiling_at(c: Vector2i, y: float) -> float:
	if not follow:
		return height
	return y + height


## Basin-ish cells: a pool's floor and steps (class C_BASIN).
func is_basin(c: Vector2i) -> bool:
	var k := grid.kind(c)
	return k == LevelGrid.BASIN or k == LevelGrid.DEEP or (k == LevelGrid.RAMP and not follow)


## Open interval of cell c at world coordinate `at` along its ramp axis (flat cells ignore it).
func cell_interval(c: Vector2i, at: float) -> Vector2:
	var y := grid.floor_y(c)
	var up := grid.ramp_dir_of(c)
	if up >= 0:
		if not follow:
			return Vector2(_slopes.run_bottom(c), height)
		var dv := LevelGrid.DIRS[up]
		var centre := (c.x if dv.x != 0 else c.y) * Tuning.GRID_CELL_SIZE
		y += grid.ramp_grade[grid.idx(c)] * (at - centre) * (dv.x + dv.y)
	return Vector2(y, ceiling_at(c, y))


## Slope axis of a sloped (Garage) ramp cell: 0 x, 1 z, -1 none.
func cell_axis(c: Vector2i) -> int:
	var up := grid.ramp_dir_of(c)
	if up < 0 or not follow:
		return -1
	return 0 if LevelGrid.DIRS[up].x != 0 else 1


# ---------------------------------------------------------------- classification

func _fi(i: int, j: int) -> int:
	return j * _fw + i


func _set_open(f: int, lo: Vector2, hi: Vector2, axis: int, bot: int, top: int) -> void:
	_open[f] = 1 if minf(hi.x - lo.x, hi.y - lo.y) > 0.0001 else 0
	_lo[f] = lo
	_hi[f] = hi
	_axis[f] = axis
	_bot[f] = bot
	_top[f] = top


## Bounds of fine column i (or row) in world metres.
func span(breaks: Array[PackedFloat32Array], i: int) -> Vector2:
	var b := breaks[i]
	return Vector2(b[0], b[b.size() - 1])


func _classify() -> void:
	_fw = grid.size.x * 2 + 1
	_fh = grid.size.y * 2 + 1
	var n := _fw * _fh
	_open.resize(n)
	_bot.resize(n)
	_top.resize(n)
	_cls.resize(n)
	_nav.resize(n)
	_door.resize(n)
	_cls.fill(C_WALL)
	_lo.resize(n)
	_hi.resize(n)
	_axis.resize(n)
	_axis.fill(-1)
	_soft.resize(n)
	_soft.fill(-1)
	for j in _fh:
		for i in _fw:
			if i % 2 == 1 and j % 2 == 1:
				_classify_cell(i, j)
			elif i % 2 != j % 2:
				_classify_strip(i, j)
	for j in range(0, _fh, 2):
		for i in range(0, _fw, 2):
			_classify_post(i, j)


func _classify_cell(i: int, j: int) -> void:
	var c := Vector2i((i - 1) / 2, (j - 1) / 2)
	var f := _fi(i, j)
	if not grid.is_sight_open(c):
		return
	var axis := cell_axis(c)
	var s := span(_xb if axis == 0 else _zb, i if axis == 0 else j)
	var a := cell_interval(c, s.x)
	var b := cell_interval(c, s.y)
	var bot := C_BASIN if is_basin(c) else C_FLOOR
	_set_open(f, Vector2(a.x, b.x), Vector2(a.y, b.y), axis, bot, C_CEILING)
	# Deep water's floor stays out of navigation (07 §8). A pool step cell's floor stays in:
	# the stepped block's first half tread is that floor (under the block, the treads above
	# leave no headroom, so the bake drops it).
	_nav[f] = 0 if grid.kind(c) == LevelGrid.DEEP else 1


## The two cells either side of strip (i, j) and the edge direction from the first.
func strip_cells(i: int, j: int) -> Array:
	if i % 2 == 0:
		return [Vector2i(i / 2 - 1, (j - 1) / 2), LevelGrid.E]
	return [Vector2i((i - 1) / 2, j / 2 - 1), LevelGrid.S]


func _classify_strip(i: int, j: int) -> void:
	var f := _fi(i, j)
	var sc := strip_cells(i, j)
	var a: Vector2i = sc[0]
	var dir: int = sc[1]
	var b := a + LevelGrid.DIRS[dir]
	var t := grid.wall(a, dir) if grid.in_bounds(a) else grid.wall(b, LevelGrid.opposite(dir))
	var oa := grid.is_sight_open(a)
	var ob := grid.is_sight_open(b)
	if not oa and not ob:
		return
	if t == LevelGrid.NONE and oa and ob:
		var axis := cell_axis(a) if cell_axis(a) == cell_axis(b) else -1
		var along := (axis == 0 and dir == LevelGrid.E) or (axis == 1 and dir == LevelGrid.S)
		var s := span(_xb if dir == LevelGrid.E else _zb, i if dir == LevelGrid.E else j)
		if along:
			# Between two cells of one sloped run: the slope carries on over the strip.
			var lo_a := cell_interval(a, s.x)
			var lo_b := cell_interval(a, s.y)
			_set_open(f, Vector2(lo_a.x, lo_b.x), Vector2(lo_a.y, lo_b.y), axis, C_FLOOR, C_CEILING)
		else:
			var va := cell_interval(a, s.x)
			var vb := cell_interval(b, s.y)
			var lo := maxf(va.x, vb.x)
			var hi := minf(va.y, vb.y)
			_set_open(f, Vector2(lo, lo), Vector2(hi, hi), -1, C_BASIN if is_basin(a) and is_basin(b) else C_FLOOR, C_CEILING)
		var under_steps := not follow and grid.kind(a) == LevelGrid.RAMP and grid.kind(b) == LevelGrid.RAMP
		_nav[f] = 0 if grid.kind(a) == LevelGrid.DEEP or grid.kind(b) == LevelGrid.DEEP or under_steps else 1
		return
	if t == LevelGrid.DOOR and oa and ob:
		var y := maxf(grid.floor_y(a), grid.floor_y(b))
		_set_open(f, Vector2(y, y), Vector2(y + _door_h, y + _door_h), -1, C_FLOOR, C_WALL)
		_nav[f] = 1
		_door[f] = 1
		return
	if t == LevelGrid.PARTITION and oa and ob:
		var y := maxf(grid.floor_y(a), grid.floor_y(b))
		var top := minf(ceiling_at(a, grid.floor_y(a)), ceiling_at(b, grid.floor_y(b)))
		_set_open(f, Vector2(y + _part_h, y + _part_h), Vector2(top, top), -1, C_PARTITION, C_CEILING)
		_cls[f] = C_PARTITION
		return
	if t == LevelGrid.GLASS:
		_cls[f] = C_GLASS
	elif t == LevelGrid.SOFT:
		var key := LevelGrid.edge_key(a, dir)
		if _soft_index.has(key):
			_cls[f] = C_SOFT
			_soft[f] = _soft_index[key]


## A post is open only when every strip around it is: its interval is their overlap.
func _classify_post(i: int, j: int) -> void:
	if i == 0 or j == 0 or i == _fw - 1 or j == _fh - 1:
		return
	var lo := -INF
	var hi := INF
	var bot := C_FLOOR
	var basin := true
	var nav := false
	for d in LevelGrid.DIRS:
		var g := _fi(i + d.x, j + d.y)
		if _open[g] == 0 or _door[g] == 1 or _axis[g] >= 0:
			return
		if _lo[g].x > lo:
			lo = _lo[g].x
			bot = _bot[g]
		hi = minf(hi, _hi[g].x)
		basin = basin and _bot[g] == C_BASIN
		if _cls[g] == C_PARTITION:
			_cls[_fi(i, j)] = C_PARTITION
	# The post feeds navigation when a strip at its floor height does.
	for d in LevelGrid.DIRS:
		var g := _fi(i + d.x, j + d.y)
		nav = nav or (_nav[g] == 1 and absf(_lo[g].x - lo) < 0.0001)
	var f := _fi(i, j)
	_set_open(f, Vector2(lo, lo), Vector2(hi, hi), -1, C_BASIN if basin else bot, C_CEILING)
	_nav[f] = 1 if nav else 0


# ---------------------------------------------------------------- lattice

## Breaks of fine column i (or row): its two bounds plus subdivisions of at most 0.5 m.
func _breaks(i: int) -> PackedFloat32Array:
	var half_t := Tuning.GRID_WALL_THICKNESS * 0.5
	var cs := Tuning.GRID_CELL_SIZE
	var lo: float
	var hi: float
	if i % 2 == 0:
		var line := (i / 2) * cs - cs * 0.5
		lo = line - half_t
		hi = line + half_t
	else:
		var c := ((i - 1) / 2) * cs
		lo = c - cs * 0.5 + half_t
		hi = c + cs * 0.5 - half_t
	var n := maxi(1, ceili((hi - lo) / Tuning.LEVELBUILD_MESH_MAX_EDGE - 0.0001))
	var out := PackedFloat32Array()
	for k in n + 1:
		out.append(lo + (hi - lo) * k / n if k < n else hi)
	return out


## Y breaks: every 0.5 m, and every floor, ceiling, door top and partition top in the level.
func _lattice() -> void:
	for i in grid.size.x * 2 + 1:
		_xb.append(_breaks(i))
	for j in grid.size.y * 2 + 1:
		_zb.append(_breaks(j))
	var marks: Dictionary = {}
	for i in grid.cell_count():
		if grid.ramp_dir[i] > 0:
			continue
		var y := grid.floor_heights[i]
		for v: float in [y, y + _door_h, y + _part_h, ceiling_at(grid.cell_at(i), y)]:
			marks[roundi(v * 1000.0)] = v
	var lo := 0.0
	var hi := height
	for k: int in marks:
		lo = minf(lo, marks[k])
		hi = maxf(hi, marks[k])
	var step := Tuning.LEVELBUILD_MESH_MAX_EDGE
	for k in range(ceili(lo / step - 0.0001), floori(hi / step + 0.0001) + 1):
		marks[roundi(k * step * 1000.0)] = k * step
	var keys := marks.keys()
	keys.sort()
	for k: int in keys:
		_yb.append(marks[k])


## Y breaks within [lo, hi].
func ys(lo: float, hi: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for y in _yb:
		if y >= lo - 0.0001 and y <= hi + 0.0001:
			out.append(y)
	return out
