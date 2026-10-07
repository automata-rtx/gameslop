extends TestCase
## BuildPlan (07 §8): conforming, subdivided geometry and collision metadata as pure data.

var _level: LevelData
var _plan: BuildPlan


func before_all() -> void:
	_level = LevelGenerator.generate(&"halls", 1, 1)
	var t0 := Time.get_ticks_usec()
	_plan = BuildPlan.make(_level, float(Tuning.STRATUM_CEILING_HEIGHT[&"halls"]))
	print("  # plan: %.1f ms, %d meshes, %d tris, %d boxes" % [(Time.get_ticks_usec() - t0) / 1000.0,
		_plan.meshes.size(), _plan.triangle_count, _plan.boxes.size()])


func test_mesh_edges_at_most_half_metre() -> void:
	var worst := 0.0
	for m in _plan.meshes:
		var v: PackedVector3Array = m[&"arrays"][Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = m[&"arrays"][Mesh.ARRAY_INDEX]
		for t in range(0, idx.size(), 3):
			worst = maxf(worst, v[idx[t]].distance_to(v[idx[t + 1]]))
			worst = maxf(worst, v[idx[t + 1]].distance_to(v[idx[t + 2]]))
	# The diagonal of a 0.5 x 0.5 quad is the longest edge a triangle may have.
	assert_lt(worst, Tuning.LEVELBUILD_MESH_MAX_EDGE * sqrt(2.0) + 0.001)


## No T-junctions on the wall/floor seam: every wall vertex at floor height is a floor vertex.
func test_wall_base_vertices_are_floor_vertices() -> void:
	var floor_pts: Dictionary = {}
	for m in _plan.meshes:
		if m[&"cls"] == BuildPlan.C_FLOOR:
			for p in (m[&"arrays"][Mesh.ARRAY_VERTEX] as PackedVector3Array):
				floor_pts[Vector3i(roundi(p.x * 1000), 0, roundi(p.z * 1000))] = true
	var missing := 0
	var checked := 0
	for m in _plan.meshes:
		if m[&"cls"] == BuildPlan.C_WALL or m[&"cls"] == BuildPlan.C_SOFT:
			for p in (m[&"arrays"][Mesh.ARRAY_VERTEX] as PackedVector3Array):
				if absf(p.y) < 0.0001:
					checked += 1
					if not floor_pts.has(Vector3i(roundi(p.x * 1000), 0, roundi(p.z * 1000))):
						missing += 1
	assert_gt(checked, 100)
	assert_eq(missing, 0, "wall base vertices without a floor vertex (T-junctions)")


## No T-junctions where walls meet walls: every vertex on a vertical wall edge appears in
## every wall patch sharing that edge, so the vertex set per (x, z) column is consistent.
func test_wall_columns_share_vertical_breaks() -> void:
	var cols: Dictionary = {}
	for m in _plan.meshes:
		if m[&"cls"] != BuildPlan.C_WALL and m[&"cls"] != BuildPlan.C_SOFT:
			continue
		for p in (m[&"arrays"][Mesh.ARRAY_VERTEX] as PackedVector3Array):
			var k := Vector2i(roundi(p.x * 1000), roundi(p.z * 1000))
			if not cols.has(k):
				cols[k] = {}
			cols[k][roundi(p.y * 1000)] = true
	var bad := 0
	for k in cols:
		var ys: Array = (cols[k] as Dictionary).keys()
		ys.sort()
		# Full-height columns run 0..3 m in 0.5 m steps (plus the door height where a header meets).
		for i in ys.size() - 1:
			if ys[i + 1] - ys[i] > 501:
				bad += 1
	assert_eq(bad, 0)


func test_soft_walls_have_own_meshes() -> void:
	var soft := 0
	for m in _plan.meshes:
		if m[&"cls"] == BuildPlan.C_SOFT:
			soft += 1
	assert_eq(soft, _level.soft_walls.size())


func test_every_wall_edge_has_a_box_with_metadata() -> void:
	var g := _level.grid
	var have: Dictionary = {}
	for b in _plan.boxes:
		var meta: Dictionary = b[&"meta"]
		if meta.has(&"dir"):
			for k in [&"cell", &"dir", &"wall_type", &"wall_kind", &"thickness", &"other_cell", &"walkable", &"other_walkable"]:
				assert_true(meta.has(k), "wall meta has %s" % k)
			have[_key(meta[&"cell"], meta[&"dir"])] = true
	var want := 0
	for z in g.size.y:
		for x in g.size.x:
			var c := Vector2i(x, z)
			if not g.is_walkable(c):
				continue
			for d in 4:
				if g.wall(c, d) == LevelGrid.NONE:
					continue
				want += 1
				assert_true(have.has(_key(c, d)), "edge %s %d has a collider" % [c, d])
	assert_gt(want, 100)


func _key(c: Vector2i, d: int) -> Vector3i:
	if d == LevelGrid.N or d == LevelGrid.W:
		var o: Vector2i = c + LevelGrid.DIRS[d]
		return Vector3i(o.x, o.y, LevelGrid.opposite(d))
	return Vector3i(c.x, c.y, d)


func test_plan_is_deterministic() -> void:
	var again := BuildPlan.make(_level, float(Tuning.STRATUM_CEILING_HEIGHT[&"halls"]))
	assert_eq(again.meshes.size(), _plan.meshes.size())
	assert_eq(again.triangle_count, _plan.triangle_count)
	assert_eq(again.boxes.size(), _plan.boxes.size())
