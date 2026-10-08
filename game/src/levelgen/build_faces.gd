class_name BuildFaces
extends RefCounted
## The visible faces of a BuildPlan (07 §8): a floor at the bottom and a ceiling at the top
## of every open element (sloped along a Garage ramp), and on every boundary between two
## elements the part of each one's open interval the other closes off (walls, basin sides,
## door headers, partition sides, the lintel over a ramp). Faces go into the plan's
## BuildMesh on the shared lattice; pure data, worker thread.

var p: BuildPlan


func _init(plan: BuildPlan) -> void:
	p = plan


func cell_of(i: int, j: int) -> Vector2i:
	return Vector2i(clampi(i / 2, 0, p.grid.size.x - 1), clampi(j / 2, 0, p.grid.size.y - 1))


func acc_for(i: int, j: int, cls: int, soft: int) -> Dictionary:
	var c := cell_of(i, j)
	return p._mesh.acc(Vector2i(c.x / p.chunk_cells, c.y / p.chunk_cells), cls, soft)


## Per-cell variation (07 §8): R = a hash of the cell in 0..1, G = the UNFINISHED flag,
## A = 1 on corridor cells (B, the floor's distance to a wall, is set per vertex).
func vcolor(i: int, j: int) -> Color:
	var c := cell_of(i, j)
	var h := absf(sin(c.x * 12.9898 + c.y * 78.233) * 43758.5453)
	var r := h - floorf(h)
	var g := 1.0 if p.grid.has_flag(c, LevelGrid.F_UNFINISHED) else 0.0
	return Color(r, g, 0.0, 1.0 if p.grid.kind(c) == LevelGrid.FLOOR else 0.0)


## Distance from floor point pt (inside element (i, j)) to the nearest element that is solid
## at that floor's height, clamped to LEVELBUILD_WALL_DIST_MAX.
func _wall_dist(pt: Vector3, i: int, j: int) -> float:
	var best := Tuning.LEVELBUILD_WALL_DIST_MAX
	for nj in range(maxi(j - 1, 0), mini(j + 2, p._fh)):
		for ni in range(maxi(i - 1, 0), mini(i + 2, p._fw)):
			var g := p._fi(ni, nj)
			if p._open[g] == 1 and p._lo[g].x <= pt.y + 0.05:
				continue
			var xs := p._xb[ni]
			var zs := p._zb[nj]
			var dx := maxf(maxf(xs[0] - pt.x, pt.x - xs[xs.size() - 1]), 0.0)
			var dz := maxf(maxf(zs[0] - pt.z, pt.z - zs[zs.size() - 1]), 0.0)
			best = minf(best, sqrt(dx * dx + dz * dz))
	return best / Tuning.LEVELBUILD_WALL_DIST_MAX


func emit_horizontal() -> void:
	for j in p._fh:
		for i in p._fw:
			var f := p._fi(i, j)
			if p._open[f] == 0:
				continue
			var col := vcolor(i, j)
			var lo := p._lo[f]
			var hi := p._hi[f]
			var axis := p._axis[f]
			var xs := p._xb[i]
			var zs := p._zb[j]
			var sx := p.span(p._xb, i)
			var sz := p.span(p._zb, j)
			var at := func(u: float, w: float, v: Vector2) -> float:
				if axis < 0:
					return v.x
				var t := (u - sx.x) / (sx.y - sx.x) if axis == 0 else (w - sz.x) / (sz.y - sz.x)
				return lerpf(v.x, v.y, t)
			var n_up := _slope_normal(axis, lo, sx if axis == 0 else sz, 1.0)
			var n_dn := _slope_normal(axis, hi, sx if axis == 0 else sz, -1.0)
			p._mesh.patch(acc_for(i, j, p._bot[f], -1), xs, zs, func(u: float, w: float) -> Vector3: return Vector3(u, at.call(u, w, lo), w),
				n_up, col, _wall_dist.bind(i, j) if p._bot[f] == BuildPlan.C_FLOOR else Callable(), p._nav[f] == 1)
			p._mesh.patch(acc_for(i, j, p._top[f], -1), xs, zs, func(u: float, w: float) -> Vector3: return Vector3(u, at.call(u, w, hi), w),
				n_dn, col, Callable(), false)


## Normal of a floor (sign 1) or ceiling (-1) sloping from v.x to v.y over `s`.
static func _slope_normal(axis: int, v: Vector2, s: Vector2, sign: float) -> Vector3:
	if axis < 0:
		return Vector3.UP * sign
	var g := (v.y - v.x) / (s.y - s.x)
	var n := Vector3(-g, 1.0, 0.0) if axis == 0 else Vector3(0.0, 1.0, -g)
	return n.normalized() * sign


func emit_vertical() -> void:
	for j in p._fh:
		for i in p._fw:
			if i + 1 < p._fw:
				_boundary(i, j, i + 1, j)
			if j + 1 < p._fh:
				_boundary(i, j, i, j + 1)


## Faces on the shared boundary of two neighbouring elements, each facing the other's open part.
func _boundary(i0: int, j0: int, i1: int, j1: int) -> void:
	var f0 := p._fi(i0, j0)
	var f1 := p._fi(i1, j1)
	if p._open[f0] == 0 and p._open[f1] == 0:
		return
	var along_x := i1 != i0
	_face_side(i1, j1, f1, f0, i0, j0, along_x, -1.0)
	_face_side(i0, j0, f0, f1, i1, j1, along_x, 1.0)


## Interval of element f on the boundary line with its neighbour: x/y = lo and hi at the
## boundary's start, z/w at its end (they differ only for a slope running along it).
func _edge_interval(f: int, along_x: bool, sign: float) -> Vector4:
	var axis := p._axis[f]
	var lo := p._lo[f]
	var hi := p._hi[f]
	if axis < 0:
		return Vector4(lo.x, hi.x, lo.x, hi.x)
	var runs_along := (axis == 1) == along_x
	if runs_along:
		return Vector4(lo.x, hi.x, lo.y, hi.y)
	# The boundary cuts across the slope: the interval at that end.
	var e := 1 if sign > 0.0 else 0
	return Vector4(lo[e], hi[e], lo[e], hi[e])


## Element (i, j) shows a face towards neighbour (oi, oj) where the neighbour is open and it
## is not. along_x: the neighbours differ in i (face plane is constant x). sign: +1 when the
## neighbour lies on the + side.
func _face_side(i: int, j: int, f: int, g: int, oi: int, oj: int, along_x: bool, sign: float) -> void:
	if p._open[g] == 0:
		return
	var other := _edge_interval(g, along_x, -sign)
	var parts: Array[Vector4] = []
	if p._open[f] == 0:
		parts.append(other)
	else:
		var own := _edge_interval(f, along_x, sign)
		# Flat difference (slopes only ever meet solid sides along their run).
		if other.x < own.x:
			parts.append(Vector4(other.x, minf(other.y, own.x), other.x, minf(other.y, own.x)))
		if other.y > own.y:
			parts.append(Vector4(maxf(other.x, own.y), other.y, maxf(other.x, own.y), other.y))
	var col := vcolor(oi, oj)
	var cls := BuildPlan.C_BASIN if p._bot[g] == BuildPlan.C_BASIN and p._open[f] == 1 else int(p._cls[f])
	if p._open[f] == 0 and p._bot[g] == BuildPlan.C_BASIN and p._cls[f] == BuildPlan.C_WALL:
		cls = BuildPlan.C_BASIN
	if cls == BuildPlan.C_RACK:
		# M2.2: B = 1 on rack fronts (faces across the rows) for rack_leds.gdshader.
		col.b = 1.0 if along_x != p.rows_along_x else 0.0
	var acc := acc_for(i, j, cls, p._soft[f] if p._open[f] == 0 else -1)
	var plane := (p._xb[i][p._xb[i].size() - 1] if sign > 0.0 else p._xb[i][0]) if along_x else (p._zb[j][p._zb[j].size() - 1] if sign > 0.0 else p._zb[j][0])
	var us := p._zb[j] if along_x else p._xb[i]
	var n := Vector3(sign, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, sign)
	for part in parts:
		if part.x == part.z and part.y == part.w:
			if part.y - part.x < 0.0001:
				continue
			var vs := p.ys(part.x, part.y)
			if along_x:
				p._mesh.patch(acc, us, vs, func(u: float, y: float) -> Vector3: return Vector3(plane, y, u), n, col)
			else:
				p._mesh.patch(acc, us, vs, func(u: float, y: float) -> Vector3: return Vector3(u, y, plane), n, col)
		else:
			p._slopes.slanted_face(acc, us, part, plane, along_x, n, col)
