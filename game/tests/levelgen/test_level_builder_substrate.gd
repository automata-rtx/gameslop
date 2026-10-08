extends "res://tests/levelgen/test_level_builder_strata.gd"
## LevelBuilder on a Substrate level (M2.3, 07 §5.6, §8): it builds and bakes with a navmesh
## path from the spawn to the Threshold (the base tests: 07 §8 rule 11), floors stand at their
## heights (the rooms that float +-0.25 m and their doorway ramps), the placeholder checker
## and the brighter boundary are their own surface classes, every studio light is a pooled
## fixture lending a white unshadowed light, edges to VOID are SOLID colliders, and the floor
## is solid (no drops on the last depth of a Descent).


func stratum() -> StringName:
	return &"substrate"


func depth() -> int:
	return 6


func test_surface_classes() -> void:
	var level: Level = _levels[&"substrate"]
	var classes: Dictionary = {}
	for m in level.builder.plan.meshes:
		classes[int(m[&"cls"])] = classes.get(int(m[&"cls"]), 0) + 1
	assert_true(classes.has(BuildPlan.C_UNFINISHED), "07 §8: the unfinished surface class")
	assert_true(classes.has(BuildPlan.C_EDGE), "the drawing's boundary")
	assert_true(classes.has(BuildPlan.C_FLOOR) and classes.has(BuildPlan.C_WALL))
	var checker := LevelMaterials.for_class(level.stratum, BuildPlan.C_UNFINISHED) as ShaderMaterial
	assert_eq(int(checker.get_shader_parameter(&"pattern_mode")), 5, "02 §5 placeholder checker")
	assert_eq(checker.get_shader_parameter(&"albedo"), Color(1, 0, 1, 1), "magenta")
	var surface := LevelMaterials.for_class(level.stratum, BuildPlan.C_FLOOR) as ShaderMaterial
	assert_approx(float(surface.get_shader_parameter(&"u_floor")), Tuning.WORLD_SUBSTRATE_U_FLOOR)
	assert_approx(float(surface.get_shader_parameter(&"line_emission")), Tuning.SUBSTRATE_LINE_EMISSION)


## The checker covers exactly the UNFINISHED cells' floors: every floor triangle in a
## C_UNFINISHED mesh carries G = 1, every C_FLOOR one G = 0.
func test_unfinished_faces_follow_the_flag() -> void:
	var level: Level = _levels[&"substrate"]
	for m in level.builder.plan.meshes:
		var cls: int = m[&"cls"]
		if cls != BuildPlan.C_UNFINISHED and cls != BuildPlan.C_FLOOR:
			continue
		var cols: PackedColorArray = m[&"arrays"][Mesh.ARRAY_COLOR]
		for col in cols:
			assert_eq(col.g > 0.5, cls == BuildPlan.C_UNFINISHED, "class %d vertex G %.1f" % [cls, col.g])
			break


func test_studio_lights_are_pooled_fixtures() -> void:
	var level: Level = _levels[&"substrate"]
	var lights := 0
	for f in level.light_pool.fixtures():
		assert_eq(f.light_profile.get(&"color"), Color.WHITE)
		assert_approx(float(f.light_profile.get(&"energy")), Tuning.SUBSTRATE_STUDIO_LIGHT_ENERGY)
		assert_approx(float(f.light_profile.get(&"range")), Tuning.SUBSTRATE_STUDIO_LIGHT_RANGE)
		assert_false(bool(f.light_profile.get(&"shadow", true)), "02 §7: no shadows")
		lights += 1
	assert_eq(lights, level.data.placements_of(LevelData.P_FIXTURE).size())
	assert_true(lights >= Tuning.SUBSTRATE_STUDIO_LIGHTS_MIN and lights <= Tuning.SUBSTRATE_STUDIO_LIGHTS_MAX)
	assert_gt(level.light_pool.active_light_count(), 0, "lights lent from the spawn")


## 07 §5.6: an edge to VOID is SOLID for noclip (the invisible wall of the fiction).
func test_void_edges_are_solid() -> void:
	var level: Level = _levels[&"substrate"]
	var g := level.data.grid
	var checked := 0
	for b in level.builder.plan.boxes:
		var meta: Dictionary = b[&"meta"]
		if not meta.has(&"dir") or not meta.has(&"cell"):
			continue
		var c: Vector2i = meta[&"cell"]
		var o := c + LevelGrid.DIRS[int(meta[&"dir"])]
		if g.is_walkable(c) and g.in_bounds(o) and g.kind(o) == LevelGrid.VOID and g.wall(c, int(meta[&"dir"])) != LevelGrid.SOFT:
			assert_eq(int(meta[&"wall_type"]), LevelGrid.SOLID, "edge %s %d" % [c, meta[&"dir"]])
			checked += 1
	assert_gt(checked, 50)


func test_floor_is_solid_on_the_last_depth() -> void:
	var level: Level = _levels[&"substrate"]
	assert_true(level.data.floor_solid, "06 §8: nothing below the Substrate")
