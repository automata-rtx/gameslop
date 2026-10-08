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


## R4 #3 / M2.1: the plan models Halls, Pools and Garage (heights, ramps, basins, pillars);
## a stratum whose special cells it does not model yet is reported loudly.
func test_unsupported_stratum_is_reported() -> void:
	assert_eq(_plan.errors.size(), 0, "Halls is supported")
	for st: StringName in [&"pools", &"garage", &"offices", &"server", &"substrate"]:
		assert_true(BuildPlan.SUPPORTED_STRATA.has(st))
	# M2.3: every stratum is modelled; a grid labelled with an unknown id is reported.
	var was := _level.stratum
	_level.stratum = &"nowhere"
	var p := BuildPlan.make(_level, 3.0)
	_level.stratum = was
	assert_eq(p.errors.size(), 1)


## R4 #2: every void cell next to walkable space has a solid block.
func test_void_blocks_next_to_walkable() -> void:
	var g := _level.grid
	var blocks: Dictionary = {}
	for b in _plan.boxes:
		if b[&"kind"] == BuildPlan.BODY_VOID:
			blocks[b[&"meta"][&"cell"]] = b
			assert_eq(b[&"meta"][&"wall_type"], LevelGrid.SOLID)
	var want := 0
	for i in g.cell_count():
		var c := g.cell_at(i)
		if g.is_walkable(c):
			continue
		for d in LevelGrid.DIRS:
			if g.is_walkable(c + d):
				want += 1
				assert_true(blocks.has(c), "void %s has a block" % c)
				break
	assert_eq(blocks.size(), want)


## R4 V2: floor vertex colour B is the distance to the nearest wall (0 at the wall, about
## 0.9 m at a corridor's centre line); A marks corridor cells.
func test_floor_colour_carries_wall_distance() -> void:
	var g := _level.grid
	var lo := 1.0
	var hi := 0.0
	var corridor := 0
	for m in _plan.meshes:
		if m[&"cls"] != BuildPlan.C_FLOOR:
			continue
		var v: PackedVector3Array = m[&"arrays"][Mesh.ARRAY_VERTEX]
		var col: PackedColorArray = m[&"arrays"][Mesh.ARRAY_COLOR]
		for k in v.size():
			lo = minf(lo, col[k].b)
			hi = maxf(hi, col[k].b)
			var c := g.cell_of(v[k])
			if col[k].a > 0.5:
				corridor += 1
			# A vertex at a cell centre of a 1-wide corridor is 0.9 m from both walls.
			if v[k].distance_to(g.world_of(c)) < 0.01 and g.kind(c) == LevelGrid.FLOOR \
					and not g.can_step(c, LevelGrid.N) and not g.can_step(c, LevelGrid.S):
				assert_approx(col[k].b, 0.9, 0.01, "corridor centre %s" % c)
	assert_approx(lo, 0.0, 0.001, "vertices on the wall line")
	assert_gt(hi, 0.85)
	assert_gt(corridor, 100)


## R4 #16: the plan stays under the 400-line script limit (14).
func test_build_plan_script_size() -> void:
	var f := FileAccess.open("res://src/levelgen/build_plan.gd", FileAccess.READ)
	assert_lt(f.get_as_text().split("\n").size(), 400)


## R4 #22: LevelShots has a pose at the head of the longest corridor (T1 at 12 m).
func test_level_shots_long_corridor_pose() -> void:
	var names: Array = []
	for p in LevelShots.poses(_level):
		names.append(p[&"name"])
		if p[&"name"] == "corridor_long":
			assert_gt(float(p[&"run_m"]), 6.0, "a corridor long enough to look down")
	assert_contains(names, "corridor_long")
