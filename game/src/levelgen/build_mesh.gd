class_name BuildMesh
extends RefCounted
## Mesh accumulators for BuildPlan (07 §8), pure data: quads on a lattice are appended per
## chunk and surface class (soft walls per edge), then turned into Mesh.ARRAY_MAX arrays.
## Also collects the navigation source faces (one coarse quad per patch).
## Vertex colour (07 §8): R per-cell hash, G the UNFINISHED flag, B distance to the nearest
## wall in metres clamped to 1 (floors only; the world shader's wear lanes and floor seam),
## A 1 on corridor (FLOOR) cells.

var meshes: Array[Dictionary] = []
var nav_faces: PackedVector3Array = PackedVector3Array()
var triangle_count: int = 0

# Accumulators keyed by "cx,cz,cls" or "s<soft index>".
var _acc: Dictionary = {}


func acc(chunk: Vector2i, cls: int, soft: int) -> Dictionary:
	var key := "s%d" % soft if soft >= 0 else "%d,%d,%d" % [chunk.x, chunk.y, cls]
	if not _acc.has(key):
		_acc[key] = {
			&"key": key, &"chunk": chunk, &"cls": cls, &"soft": soft,
			&"v": PackedVector3Array(), &"n": PackedVector3Array(), &"c": PackedColorArray(),
			&"uv": PackedVector2Array(), &"i": PackedInt32Array(),
		}
	return _acc[key]


## A grid of quads: corner(u, v) for u in us, v in vs; normal n. Winding is fixed so the
## front face is towards n (Godot culls clockwise-from-front back faces). `blue` (optional,
## Callable(Vector3) -> float) sets the colour's B per vertex. `nav` false leaves the patch
## out of the navigation source (ceilings; deep water's floor, 07 §8).
func patch(a: Dictionary, us: PackedFloat32Array, vs: PackedFloat32Array, corner: Callable,
		n: Vector3, col: Color, blue: Callable = Callable(), nav: bool = true) -> void:
	var v: PackedVector3Array = a[&"v"]
	var nn: PackedVector3Array = a[&"n"]
	var cc: PackedColorArray = a[&"c"]
	var uv: PackedVector2Array = a[&"uv"]
	var idx: PackedInt32Array = a[&"i"]
	var base := v.size()
	var nu := us.size()
	for b in vs.size():
		for k in nu:
			var p: Vector3 = corner.call(us[k], vs[b])
			v.append(p)
			nn.append(n)
			if blue.is_valid():
				cc.append(Color(col.r, col.g, float(blue.call(p)), col.a))
			else:
				cc.append(col)
			uv.append(Vector2(us[k], vs[b]))
	# Decide the winding once from the patch's own axes.
	var p00: Vector3 = corner.call(us[0], vs[0])
	var p10: Vector3 = corner.call(us[1], vs[0])
	var p01: Vector3 = corner.call(us[0], vs[1])
	var flip := (p10 - p00).cross(p01 - p00).dot(n) > 0.0
	for b in vs.size() - 1:
		for k in nu - 1:
			var i00 := base + b * nu + k
			var i10 := i00 + 1
			var i01 := i00 + nu
			var i11 := i01 + 1
			if flip:
				idx.append_array([i00, i01, i10, i10, i01, i11])
			else:
				idx.append_array([i00, i10, i01, i10, i11, i01])
	triangle_count += (vs.size() - 1) * (nu - 1) * 2
	if not nav:
		return
	# Navigation gets one coarse quad per patch.
	var p11: Vector3 = corner.call(us[nu - 1], vs[vs.size() - 1])
	var pu: Vector3 = corner.call(us[nu - 1], vs[0])
	var pv: Vector3 = corner.call(us[0], vs[vs.size() - 1])
	if flip:
		nav_faces.append_array([p00, pv, pu, pu, pv, p11])
	else:
		nav_faces.append_array([p00, pu, pv, pu, p11, pv])


## Turns the accumulators into `meshes` (sorted by key, so the order is deterministic).
func finish() -> void:
	var keys := _acc.keys()
	keys.sort()
	for key in keys:
		var a: Dictionary = _acc[key]
		if (a[&"v"] as PackedVector3Array).is_empty():
			continue  # opened for faces that all came out empty (M2.2: rack corners)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = a[&"v"]
		arrays[Mesh.ARRAY_NORMAL] = a[&"n"]
		arrays[Mesh.ARRAY_COLOR] = a[&"c"]
		arrays[Mesh.ARRAY_TEX_UV] = a[&"uv"]
		arrays[Mesh.ARRAY_INDEX] = a[&"i"]
		var verts: PackedVector3Array = a[&"v"]
		var box := AABB(verts[0], Vector3.ZERO)
		for p in verts:
			box = box.expand(p)
		meshes.append({&"key": a[&"key"], &"chunk": a[&"chunk"], &"cls": a[&"cls"], &"soft": a[&"soft"],
			&"arrays": arrays, &"aabb": box})
	_acc.clear()
