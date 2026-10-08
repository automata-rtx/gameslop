class_name BuildPlan
extends RefCounted
## The level's geometry as pure data (07 §8): merged mesh arrays per 8x8-cell chunk and
## surface class, collision boxes with the noclip metadata of 07 §7, and navigation source
## faces. No nodes and no autoloads, so it runs on a worker thread; LevelBuilder turns it
## into nodes in 4 ms slices on the main thread.
##
## Geometry model: each cell axis is split at its edge strips, so the plan sees a fine grid
## of (2W+1) x (2H+1) elements: cell interiors (1.8 m), edge strips (0.2 m, the wall
## thickness) and corner posts (0.2 m). Each element is open, full, a door opening (solid
## above the door height) or a partition (solid up to 1.5 m). Visible faces are exactly the
## boundaries between solid and open parts, so walls, floor and ceiling meet without overlap
## (no z-fighting, no light leaks at seams). Every face is subdivided on one global lattice
## (element breaks along X and Z, 0.5 m steps plus the door and partition heights along Y),
## so faces that share an edge share its vertices: no T-junctions, and the world shader's
## world-position vertex jitter moves coincident vertices together (no cracks).

enum Elem { OPEN, FULL, DOOR, PART }

## Surface classes. Each chunk gets one mesh per class it uses; soft walls get their own
## mesh per edge (09 §8: the soft uniform must differ per segment).
const C_FLOOR := 0
const C_CEILING := 1
const C_WALL := 2
const C_PARTITION := 3
const C_GLASS := 4
const C_SOFT := 5
const CLASS_NAMES: Array[StringName] = [&"floor", &"ceiling", &"wall", &"partition", &"glass", &"soft"]

## Body keys for collision. Wall bodies are split by wall type so the body itself carries
## a single `wall_kind` meta (noise wall counting reads it from the collider).
const BODY_FLOOR := &"floor"
## Solid blocks filling void cells next to walkable space (meta `void`, no `wall_kind`).
const BODY_VOID := &"void"

var grid: LevelGrid
var height: float = 3.0
var chunk_cells: int = 8
var chunks: Vector2i = Vector2i.ONE

## Mesh surfaces: Array of {key: String, chunk: Vector2i, cls: int, soft: int (edge index
## or -1), arrays: Array (Mesh.ARRAY_MAX), aabb: AABB}.
var meshes: Array[Dictionary] = []
## Collision boxes: Array of {body: String, chunk: Vector2i, kind: StringName (wall type
## name or &"floor"), size: Vector3, pos: Vector3, meta: Dictionary}.
var boxes: Array[Dictionary] = []
## Triangle soup for the navigation bake: floors (walkable) and wall faces (obstacles).
var nav_faces: PackedVector3Array = PackedVector3Array()
var triangle_count: int = 0
## Problems found while planning (also pushed as errors), e.g. an unsupported stratum.
var errors: PackedStringArray = PackedStringArray()

## Strata whose grids the plan models faithfully. TODO(M2.1): per-cell floor heights
## (Substrate offsets, Garage decks, ramps), RAMP/BASIN/RACK cells and water are not built
## yet; every floor is at y = 0 and every non-walkable cell is a solid block. M2.1 extends
## _classify/_emit_horizontal and BuildCollision.boxes, then adds its stratum here.
const SUPPORTED_STRATA: Array[StringName] = [&"halls"]

# Fine grid.
var _fw: int = 0
var _fh: int = 0
var _kind: PackedByteArray = PackedByteArray()
var _cls: PackedByteArray = PackedByteArray()
var _soft: PackedInt32Array = PackedInt32Array()
# Lattice breaks per fine column / row, and global Y breaks.
var _xb: Array[PackedFloat32Array] = []
var _zb: Array[PackedFloat32Array] = []
var _yb: PackedFloat32Array = PackedFloat32Array()
var _door_h: float = 2.1
var _part_h: float = 1.5
var _mesh: BuildMesh = BuildMesh.new()
# Edge key (Vector3i, E/S form) -> index in LevelData.soft_walls.
var _soft_index: Dictionary = {}


## Computes the whole plan. `soft_walls` is LevelData.soft_walls (Vector3i(x, z, dir)).
static func make(level: LevelData, ceiling_height: float) -> BuildPlan:
	var p := BuildPlan.new()
	p.grid = level.grid
	p.height = ceiling_height
	p.chunk_cells = Tuning.LEVELBUILD_CHUNK_CELLS
	p._door_h = Tuning.LEVELBUILD_DOOR_HEIGHT
	p._part_h = Tuning.GRID_PARTITION_HEIGHT
	p.chunks = Vector2i(ceili(level.grid.size.x / float(p.chunk_cells)), ceili(level.grid.size.y / float(p.chunk_cells)))
	if not SUPPORTED_STRATA.has(level.stratum):
		# TODO(M2.1): heights and special cells. Built anyway (flat), but loudly.
		p.errors.append("BuildPlan: stratum '%s' needs per-cell heights and special cells (M2.1); built flat" % level.stratum)
		push_error(p.errors[p.errors.size() - 1])
	p._classify(level.soft_walls)
	p._lattice()
	p._emit_horizontal()
	p._emit_vertical()
	p._mesh.finish()
	p.meshes = p._mesh.meshes
	p.nav_faces = p._mesh.nav_faces
	p.triangle_count = p._mesh.triangle_count
	p.boxes = BuildCollision.boxes(p.grid, p.height, p.chunk_cells, p._part_h, p._door_h, p._soft_index)
	return p


# ---------------------------------------------------------------- classification

func _fi(i: int, j: int) -> int:
	return j * _fw + i


## Wall type of the edge strip at fine (i, j); exactly one of i, j is even.
func _strip_wall(i: int, j: int) -> Array:
	# Returns [type, cell_a walkable, cell_b walkable].
	var a: Vector2i
	var dir: int
	if i % 2 == 0:
		a = Vector2i(i / 2 - 1, (j - 1) / 2)
		dir = LevelGrid.E
	else:
		a = Vector2i((i - 1) / 2, j / 2 - 1)
		dir = LevelGrid.S
	var b := a + LevelGrid.DIRS[dir]
	var t: int
	if grid.in_bounds(a):
		t = grid.wall(a, dir)
	else:
		t = grid.wall(b, LevelGrid.opposite(dir))
	return [t, grid.is_walkable(a), grid.is_walkable(b), a, dir]


func _classify(soft_walls: Array[Vector3i]) -> void:
	_fw = grid.size.x * 2 + 1
	_fh = grid.size.y * 2 + 1
	var n := _fw * _fh
	_kind.resize(n)
	_cls.resize(n)
	_cls.fill(C_WALL)
	_soft.resize(n)
	_soft.fill(-1)
	var soft_index := _soft_index
	for k in soft_walls.size():
		var e := soft_walls[k]
		soft_index[BuildCollision.edge_key(Vector2i(e.x, e.y), e.z)] = k
	# Cells and strips first; posts read the strips around them.
	for j in _fh:
		for i in _fw:
			var f := _fi(i, j)
			if i % 2 == 1 and j % 2 == 1:
				_kind[f] = Elem.OPEN if grid.is_walkable(Vector2i((i - 1) / 2, (j - 1) / 2)) else Elem.FULL
			elif i % 2 != j % 2:
				var s := _strip_wall(i, j)
				var t: int = s[0]
				if not s[1] and not s[2]:
					_kind[f] = Elem.FULL
				elif t == LevelGrid.NONE:
					_kind[f] = Elem.OPEN
				elif t == LevelGrid.DOOR:
					_kind[f] = Elem.DOOR
				elif t == LevelGrid.PARTITION:
					_kind[f] = Elem.PART
					_cls[f] = C_PARTITION
				else:
					_kind[f] = Elem.FULL
					if t == LevelGrid.GLASS:
						_cls[f] = C_GLASS
					elif t == LevelGrid.SOFT:
						var key := BuildCollision.edge_key(s[3], s[4])
						if soft_index.has(key):
							_cls[f] = C_SOFT
							_soft[f] = soft_index[key]
	for j in range(0, _fh, 2):
		for i in range(0, _fw, 2):
			var full := false
			var part := false
			for d in LevelGrid.DIRS:
				var si := i + d.x
				var sj := j + d.y
				if si < 0 or sj < 0 or si >= _fw or sj >= _fh:
					continue
				var k: int = _kind[_fi(si, sj)]
				full = full or k == Elem.FULL or k == Elem.DOOR
				part = part or k == Elem.PART
			var on_border := i == 0 or j == 0 or i == _fw - 1 or j == _fh - 1
			_kind[_fi(i, j)] = Elem.FULL if full or on_border else (Elem.PART if part else Elem.OPEN)
			if not full and part:
				_cls[_fi(i, j)] = C_PARTITION


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


func _lattice() -> void:
	for i in _fw:
		_xb.append(_breaks(i))
	for j in _fh:
		_zb.append(_breaks(j))
	var ys: Array[float] = []
	var steps := ceili(height / Tuning.LEVELBUILD_MESH_MAX_EDGE - 0.0001)
	for k in steps + 1:
		ys.append(minf(height, k * Tuning.LEVELBUILD_MESH_MAX_EDGE) if k < steps else height)
	for extra in [_door_h, _part_h]:
		if extra > 0.0 and extra < height and not ys.has(extra):
			ys.append(extra)
	ys.sort()
	_yb = PackedFloat32Array(ys)


## The solid interval [lo, hi] of an element kind; lo >= hi means empty.
func _solid(k: int) -> Vector2:
	match k:
		Elem.FULL:
			return Vector2(0.0, height)
		Elem.DOOR:
			return Vector2(_door_h, height)
		Elem.PART:
			return Vector2(0.0, _part_h)
	return Vector2(height, height)


# ---------------------------------------------------------------- faces

func _cell_of(i: int, j: int) -> Vector2i:
	return Vector2i(clampi(i / 2, 0, grid.size.x - 1), clampi(j / 2, 0, grid.size.y - 1))


func _acc_for(i: int, j: int, cls: int, soft: int) -> Dictionary:
	var c := _cell_of(i, j)
	return _mesh.acc(Vector2i(c.x / chunk_cells, c.y / chunk_cells), cls, soft)


## Per-cell variation (07 §8): R = a hash of the cell in 0..1, G = the UNFINISHED flag,
## A = 1 on corridor cells (B, the floor's distance to a wall, is set per vertex).
func _vcolor(i: int, j: int) -> Color:
	var c := _cell_of(i, j)
	var h := absf(sin(c.x * 12.9898 + c.y * 78.233) * 43758.5453)
	var r := h - floorf(h)
	var g := 1.0 if grid.has_flag(c, LevelGrid.F_UNFINISHED) else 0.0
	return Color(r, g, 0.0, 1.0 if grid.kind(c) == LevelGrid.FLOOR else 0.0)


## Distance from floor point p (inside element (i, j)) to the nearest element solid at floor
## level, clamped to LEVELBUILD_WALL_DIST_MAX (< a cell, so the 3 x 3 neighbourhood is enough).
func _wall_dist(p: Vector3, i: int, j: int) -> float:
	var best := Tuning.LEVELBUILD_WALL_DIST_MAX
	for nj in range(maxi(j - 1, 0), mini(j + 2, _fh)):
		for ni in range(maxi(i - 1, 0), mini(i + 2, _fw)):
			var k: int = _kind[_fi(ni, nj)]
			if k != Elem.FULL and k != Elem.PART:
				continue
			var xs := _xb[ni]
			var zs := _zb[nj]
			var dx := maxf(maxf(xs[0] - p.x, p.x - xs[xs.size() - 1]), 0.0)
			var dz := maxf(maxf(zs[0] - p.z, p.z - zs[zs.size() - 1]), 0.0)
			best = minf(best, sqrt(dx * dx + dz * dz))
	return best / Tuning.LEVELBUILD_WALL_DIST_MAX


## Y breaks within [lo, hi].
func _ys(lo: float, hi: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for y in _yb:
		if y >= lo - 0.0001 and y <= hi + 0.0001:
			out.append(y)
	return out


func _emit_horizontal() -> void:
	for j in _fh:
		for i in _fw:
			var k: int = _kind[_fi(i, j)]
			var col := _vcolor(i, j)
			var xs := _xb[i]
			var zs := _zb[j]
			if k == Elem.OPEN or k == Elem.DOOR:
				_flat(_acc_for(i, j, C_FLOOR, -1), xs, zs, 0.0, Vector3.UP, col, _wall_dist.bind(i, j))
			if k == Elem.OPEN or k == Elem.PART:
				_flat(_acc_for(i, j, C_CEILING, -1), xs, zs, height, Vector3.DOWN, col)
			if k == Elem.PART:
				_flat(_acc_for(i, j, _cls[_fi(i, j)], -1), xs, zs, _part_h, Vector3.UP, col)
			elif k == Elem.DOOR:
				_flat(_acc_for(i, j, C_WALL, -1), xs, zs, _door_h, Vector3.DOWN, col)


func _flat(acc: Dictionary, xs: PackedFloat32Array, zs: PackedFloat32Array, y: float, n: Vector3, col: Color,
		blue: Callable = Callable()) -> void:
	_mesh.patch(acc, xs, zs, func(u: float, w: float) -> Vector3: return Vector3(u, y, w), n, col, blue)


func _emit_vertical() -> void:
	for j in _fh:
		for i in _fw:
			if i + 1 < _fw:
				_boundary(i, j, i + 1, j)
			if j + 1 < _fh:
				_boundary(i, j, i, j + 1)


## Faces on the shared boundary of two neighbouring elements, each facing the other's open part.
func _boundary(i0: int, j0: int, i1: int, j1: int) -> void:
	var f0 := _fi(i0, j0)
	var f1 := _fi(i1, j1)
	var k0: int = _kind[f0]
	var k1: int = _kind[f1]
	if k0 == k1:
		return
	_face_side(i1, j1, f1, k1, k0, i0, j0, i1 != i0, -1.0)
	_face_side(i0, j0, f0, k0, k1, i1, j1, i1 != i0, 1.0)


## Solid element (i, j) of kind k shows a face towards its neighbour of kind other.
## along_x: the neighbours differ in i (face plane is constant x). sign: +1 when the
## neighbour lies on the + side of the solid element.
func _face_side(i: int, j: int, f: int, k: int, other: int, oi: int, oj: int, along_x: bool, sign: float) -> void:
	var s := _solid(k)
	var o := _solid(other)
	if s.x >= s.y:
		return
	# s minus o: up to two intervals.
	var parts: Array[Vector2] = []
	if o.x >= o.y:
		parts.append(s)
	else:
		if s.x < o.x:
			parts.append(Vector2(s.x, minf(s.y, o.x)))
		if s.y > o.y:
			parts.append(Vector2(maxf(s.x, o.y), s.y))
	if parts.is_empty():
		return
	# Faces only matter where the neighbour is open air next to walkable space.
	var col := _vcolor(oi, oj)
	var acc := _acc_for(i, j, _cls[f], _soft[f])
	for part in parts:
		if part.y - part.x < 0.0001:
			continue
		var ys := _ys(part.x, part.y)
		if along_x:
			var x := _xb[i][_xb[i].size() - 1] if sign > 0.0 else _xb[i][0]
			var n := Vector3(sign, 0.0, 0.0)
			_mesh.patch(acc, _zb[j], ys, func(u: float, y: float) -> Vector3: return Vector3(x, y, u), n, col)
		else:
			var z := _zb[j][_zb[j].size() - 1] if sign > 0.0 else _zb[j][0]
			var n := Vector3(0.0, 0.0, sign)
			_mesh.patch(acc, _xb[i], ys, func(u: float, y: float) -> Vector3: return Vector3(u, y, z), n, col)


## Solid-element count by kind (tests and debugging).
func element_counts() -> Dictionary:
	var out := {Elem.OPEN: 0, Elem.FULL: 0, Elem.DOOR: 0, Elem.PART: 0}
	for k in _kind:
		out[k] += 1
	return out
