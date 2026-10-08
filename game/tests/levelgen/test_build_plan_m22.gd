extends TestCase
## BuildPlan for Offices and Server (M2.2, 07 §8): partitions 1.5 m and glass in their own
## classes; racks as blocks SERVER_RACK_HEIGHT high, open above, faces in class C_RACK with
## vertex colour B = 1 only on the fronts (across the rows), one box per rack cell carrying
## the rack noclip metadata; the rack ruling's far side from that metadata.

var _offices: LevelData
var _server: LevelData
var _op: BuildPlan
var _sp: BuildPlan


func before_all() -> void:
	_offices = LevelGenerator.generate(&"offices", 3, 2)
	_server = LevelGenerator.generate(&"server", 4, 2)
	_op = BuildPlan.make(_offices, float(Tuning.STRATUM_CEILING_HEIGHT[&"offices"]))
	_sp = BuildPlan.make(_server, float(Tuning.STRATUM_CEILING_HEIGHT[&"server"]))


func _verts(plan: BuildPlan, cls: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in plan.meshes:
		if m[&"cls"] == cls:
			out.append(m)
	return out


func test_plans_report_no_errors() -> void:
	assert_eq(_op.errors.size(), 0)
	assert_eq(_sp.errors.size(), 0)
	assert_true(BuildPlan.SUPPORTED_STRATA.has(&"offices") and BuildPlan.SUPPORTED_STRATA.has(&"server"))


func test_offices_partitions_and_glass() -> void:
	var part := _verts(_op, BuildPlan.C_PARTITION)
	assert_false(part.is_empty(), "partition meshes")
	var top := 0.0
	for m in part:
		for v in (m[&"arrays"][Mesh.ARRAY_VERTEX] as PackedVector3Array):
			top = maxf(top, v.y)
	assert_approx(top, Tuning.GRID_PARTITION_HEIGHT, 0.001, "partitions stop at 1.5 m")
	assert_false(_verts(_op, BuildPlan.C_GLASS).is_empty(), "glass meshes")
	var glass := 0
	var partitions := 0
	for b in _op.boxes:
		if b[&"kind"] == &"GLASS":
			glass += 1
		if b[&"kind"] == &"PARTITION":
			partitions += 1
			assert_approx((b[&"size"] as Vector3).y, Tuning.GRID_PARTITION_HEIGHT, 0.001)
	assert_gt(glass, 0)
	assert_gt(partitions, 40)


func test_server_racks_are_blocks_with_led_fronts() -> void:
	var racks := _verts(_sp, BuildPlan.C_RACK)
	assert_false(racks.is_empty(), "rack meshes")
	var fronts := 0
	var ends := 0
	var top := 0.0
	var along_x := _sp.rows_along_x
	for m in racks:
		var vs: PackedVector3Array = m[&"arrays"][Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = m[&"arrays"][Mesh.ARRAY_NORMAL]
		var cs: PackedColorArray = m[&"arrays"][Mesh.ARRAY_COLOR]
		for k in vs.size():
			top = maxf(top, vs[k].y)
			if absf(ns[k].y) > 0.5:
				assert_eq(cs[k].b, 0.0, "rack tops are not fronts")
				continue
			var across := absf(ns[k].z) > 0.5 if along_x else absf(ns[k].x) > 0.5
			if across:
				assert_eq(cs[k].b, 1.0, "a front")
				fronts += 1
			else:
				assert_eq(cs[k].b, 0.0, "a row end")
				ends += 1
	assert_approx(top, Tuning.SERVER_RACK_HEIGHT, 0.001, "racks stop at their height; open above")
	assert_gt(fronts, ends, "rows are longer than they are deep")
	assert_gt(ends, 0)
	# The ceiling runs over the racks.
	var ceil_ys: Dictionary = {}
	for m in _verts(_sp, BuildPlan.C_CEILING):
		for v in (m[&"arrays"][Mesh.ARRAY_VERTEX] as PackedVector3Array):
			ceil_ys[snappedf(v.y, 0.01)] = true
	assert_eq(ceil_ys.keys(), [Tuning.STRATUM_CEILING_HEIGHT[&"server"]])


func test_rack_collision_and_far_side() -> void:
	var g := _server.grid
	var checked := 0
	for b in _sp.boxes:
		if b[&"kind"] != BuildPlan.BODY_RACK:
			continue
		var meta: Dictionary = b[&"meta"]
		var c: Vector2i = meta[&"cell"]
		assert_eq(g.kind(c), LevelGrid.RACK)
		assert_approx((b[&"size"] as Vector3).x, Tuning.GRID_CELL_SIZE + Tuning.GRID_WALL_THICKNESS, 0.001)
		for d in 4:
			# A face seen from the d side has its normal pointing towards d.
			var dv := LevelGrid.DIRS[d]
			var far := NoclipQuery.far_side(meta, Vector3(dv.x, 0.0, dv.y))
			var beyond := c - dv
			assert_true(far[&"known"])
			assert_eq(far[&"cell"], beyond)
			assert_eq(far[&"walkable"], g.is_walkable(beyond))
			assert_approx(float(far[&"pass_depth"]), Tuning.GRID_CELL_SIZE, 0.001)
		checked += 1
	assert_gt(checked, 100)
	# No wall box stands on a rack's edge (the rack box covers its strips).
	for b in _sp.boxes:
		var meta: Dictionary = b[&"meta"]
		if meta.has(&"dir") and meta.has(&"other_cell"):
			assert_ne(g.kind(meta[&"cell"]), LevelGrid.RACK)
			assert_ne(g.kind(meta[&"other_cell"]), LevelGrid.RACK)


## 14: scripts stay under 400 lines.
func test_m22_script_sizes() -> void:
	for path in ["res://src/levelgen/strata/offices.gd", "res://src/levelgen/strata/office_rooms.gd",
			"res://src/levelgen/strata/office_furnish.gd", "res://src/levelgen/strata/server.gd",
			"res://src/levelgen/strata/server_racks.gd", "res://src/levelgen/strata/server_furnish.gd",
			"res://src/levelgen/stratum_rules.gd", "res://src/levelgen/ops/ring_ops.gd",
			"res://src/levelgen/build_plan.gd", "res://src/levelgen/build_collision.gd",
			"res://src/levelgen/level_validator.gd", "res://src/levelgen/level_placer.gd",
			"res://src/lighting/light_pool.gd", "res://src/player/noclip_query.gd"]:
		var f := FileAccess.open(path, FileAccess.READ)
		assert_lt(f.get_as_text().split("\n").size(), 400, path)
