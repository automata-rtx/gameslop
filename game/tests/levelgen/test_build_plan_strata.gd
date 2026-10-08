extends TestCase
## BuildPlan for Pools and Garage (M2.1, 07 §8): sunken basins with tiled sides and stepped
## blocks, deck floors and ceilings at their heights, sloped ramps, collision wedges per ramp
## cell, ledges made solid, deep water's rail, and its floor kept out of navigation.

var _pools: LevelData
var _garage: LevelData
var _pp: BuildPlan
var _gp: BuildPlan


func before_all() -> void:
	# A Pools seed with deep water (a full 1.8 m basin).
	for s in range(1, 60):
		var l := LevelGenerator.generate(&"pools", 2, s)
		for i in l.grid.cell_count():
			if l.grid.cells[i] == LevelGrid.DEEP:
				_pools = l
				break
		if _pools != null:
			break
	_garage = LevelGenerator.generate(&"garage", 2, 1)
	_pp = BuildPlan.make(_pools, float(Tuning.STRATUM_CEILING_HEIGHT[&"pools"]))
	_gp = BuildPlan.make(_garage, float(Tuning.STRATUM_CEILING_HEIGHT[&"garage"]))


func _ys(plan: BuildPlan, cls: int) -> Dictionary:
	var out: Dictionary = {}
	for m in plan.meshes:
		if m[&"cls"] != cls:
			continue
		for v in (m[&"arrays"][Mesh.ARRAY_VERTEX] as PackedVector3Array):
			out[snappedf(v.y, 0.01)] = true
	return out


func test_plans_report_no_errors() -> void:
	assert_not_null(_pools, "a Pools seed with deep water")
	assert_eq(_pp.errors.size(), 0)
	assert_eq(_gp.errors.size(), 0)


func test_pools_basins_are_sunken_and_tiled() -> void:
	var basin := _ys(_pp, BuildPlan.C_BASIN)
	assert_false(basin.is_empty(), "basin class meshes")
	var lowest := 0.0
	for y: float in basin:
		lowest = minf(lowest, y)
	assert_approx(lowest, -Tuning.POOLS_EXIT_BASIN_DEPTH, 0.01, "the exit basin's floor")
	# Steps: treads between the floor and the rim (not only at basin depths).
	var between := 0
	for y: float in basin:
		var at_depth := false
		for d in Tuning.POOLS_BASIN_DEPTHS:
			at_depth = at_depth or absf(y + d) < 0.011
		if y < -0.05 and not at_depth:
			between += 1
	assert_gt(between, 3, "stepped treads inside the basins")
	# The hall's own floor stays at 0, its ceiling at 6 m over the basins too.
	assert_true(_ys(_pp, BuildPlan.C_FLOOR).has(0.0))
	assert_eq(_ys(_pp, BuildPlan.C_CEILING).keys(), [6.0])


func test_pools_collision() -> void:
	var g := _pools.grid
	var rails := 0
	var wedges := 0
	var rim_reach := 0
	for b in _pp.boxes:
		var meta: Dictionary = b[&"meta"]
		if b[&"kind"] == BuildPlan.BODY_RAIL:
			rails += 1
			assert_eq(meta[&"wall_type"], LevelGrid.SOLID)
			assert_true(meta.get(&"rail", false))
			assert_eq(g.kind(meta[&"other_cell"]), LevelGrid.DEEP)
		elif b[&"kind"] == BuildPlan.BODY_FLOOR:
			if b.has(&"points"):
				wedges += 1
				assert_eq(g.kind(meta[&"cell"]), LevelGrid.RAMP)
			else:
				var c: Vector2i = meta[&"cell"]
				var pos: Vector3 = b[&"pos"]
				var size: Vector3 = b[&"size"]
				assert_approx(pos.y + size.y * 0.5, g.floor_y(c), 0.001, "floor top at the cell's floor")
				if pos.y - size.y * 0.5 < g.floor_y(c) - 0.5:
					rim_reach += 1
	var want_rails := 0
	var ramps := 0
	for i in g.cell_count():
		var c := g.cell_at(i)
		if g.kind(c) == LevelGrid.RAMP:
			ramps += 1
		if g.is_walkable(c):
			for d in 4:
				if g.kind(c + LevelGrid.DIRS[d]) == LevelGrid.DEEP:
					want_rails += 1
	assert_eq(rails, want_rails, "every walkable edge into deep water has its rail")
	assert_gt(rails, 0)
	assert_eq(wedges, ramps, "one wedge per step cell")
	assert_gt(rim_reach, 10, "rim floors reach down: the basin sides are solid")


func test_deep_floor_is_not_navigation() -> void:
	var g := _pools.grid
	for k in range(0, _pp.nav_faces.size(), 3):
		var a := _pp.nav_faces[k]
		var b := _pp.nav_faces[k + 1]
		var c := _pp.nav_faces[k + 2]
		var n := (b - a).cross(c - a)
		if n.length() < 0.0001 or absf(n.normalized().y) < 0.9:
			continue  # walls
		var centre := (a + b + c) / 3.0
		var cell := g.cell_of(centre)
		if g.in_bounds(cell) and g.kind(cell) == LevelGrid.DEEP:
			assert_false(absf(centre.y - g.floor_y(cell)) < 0.01, "deep floor %s left out (%s %s %s)" % [cell, a, b, c])


func test_garage_decks_and_ramps() -> void:
	var g := _garage.grid
	var floors := _ys(_gp, BuildPlan.C_FLOOR)
	assert_true(floors.has(0.0), "deck 0")
	assert_true(floors.has(Tuning.GARAGE_DECK_RISE), "deck 1")
	var ceilings := _ys(_gp, BuildPlan.C_CEILING)
	assert_true(ceilings.has(Tuning.GARAGE_DECK_RISE), "deck 0 ceiling")
	assert_true(ceilings.has(Tuning.GARAGE_DECK_RISE * 2.0), "deck 1 ceiling")
	# Ramp floors slope: floor vertices between the decks.
	var mid := 0
	for y: float in floors:
		if y > 0.2 and y < Tuning.GARAGE_DECK_RISE - 0.2:
			mid += 1
	assert_gt(mid, 4, "sloped ramp floors")
	var wedges := 0
	var pillar_floors := 0
	for b in _gp.boxes:
		var meta: Dictionary = b[&"meta"]
		if b.has(&"points"):
			wedges += 1
			var top := -INF
			for p in (b[&"points"] as PackedVector3Array):
				top = maxf(top, p.y)
			assert_true(top > 0.0 and top <= Tuning.GARAGE_DECK_RISE + 0.001)
		if b[&"kind"] == BuildPlan.BODY_FLOOR and g.is_pillar(meta[&"cell"]):
			pillar_floors += 1
		if b[&"kind"] == BuildPlan.BODY_VOID:
			assert_false(g.is_pillar(meta[&"cell"]), "a pillar cell is open (its mesh is the prop)")
		if meta.has(&"dir") and meta[&"wall_type"] != LevelGrid.DOOR:
			# Wall boxes reach down to the floor on each open side.
			var y0 := (b[&"pos"] as Vector3).y - (b[&"size"] as Vector3).y * 0.5
			for x: Vector2i in [meta[&"cell"], meta[&"other_cell"]]:
				if g.is_walkable(x) and g.kind(x) != LevelGrid.RAMP:
					assert_true(y0 <= g.floor_y(x) + 0.001, "wall %s %d reaches %s's floor" % [meta[&"cell"], meta[&"dir"], x])
	var ramps := 0
	for i in g.cell_count():
		if g.cells[i] == LevelGrid.RAMP:
			ramps += 1
	assert_eq(wedges, ramps)
	assert_gt(pillar_floors, 4)


## 14: scripts stay under 400 lines.
func test_levelgen_script_sizes() -> void:
	for path in ["res://src/levelgen/build_plan.gd", "res://src/levelgen/build_faces.gd", "res://src/levelgen/build_slopes.gd",
			"res://src/levelgen/build_collision.gd", "res://src/levelgen/level_grid.gd", "res://src/levelgen/level_builder.gd",
			"res://src/levelgen/strata/pools.gd", "res://src/levelgen/strata/garage.gd", "res://src/levelgen/strata/garage_parking.gd"]:
		var f := FileAccess.open(path, FileAccess.READ)
		assert_lt(f.get_as_text().split("\n").size(), 400, path)
