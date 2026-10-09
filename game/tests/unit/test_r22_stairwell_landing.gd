extends TestCase
## R22: the stairwell Landing (05 §4, 02 §7): Pools and Server arrive by a concrete landing with a
## half-flight going down, a handrail and one wall-mounted fixture, in the stratum's own
## materials; the item panel, the player's spot and the door are the elevator cabin's.


func _landing(stratum: StringName) -> Landing:
	var l := (load("res://scenes/landing.tscn") as PackedScene).instantiate() as Landing
	l.apply_theme(stratum)
	add_child(l)
	return l


func _visible_lights(l: Landing) -> Array[Light3D]:
	var out: Array[Light3D] = []
	for n in l.find_children("*", "Light3D", true, false):
		if (n as Light3D).is_visible_in_tree():
			out.append(n as Light3D)
	return out


func test_stairwell_theme_per_stratum() -> void:
	assert_true(LandingStairwell.is_stairwell(&"pools"))
	assert_true(LandingStairwell.is_stairwell(&"server"))
	for id: StringName in [&"halls", &"garage", &"offices", Tuning.STRATUM_SUBSTRATE]:
		assert_false(LandingStairwell.is_stairwell(id), String(id))
		var l := _landing(id)
		assert_null(l.stair_light, "%s keeps its own Landing" % id)
		assert_null(l.geometry.get_node_or_null(^"StairLanding"))
		l.queue_free()
	await await_frames(1)


func test_stairwell_nodes_and_lights() -> void:
	for id: StringName in [&"pools", &"server"]:
		var l := _landing(id)
		assert_eq(l.theme, id)
		for n in ["StairLanding", "StairFront", "Step0", "Step1", "Step2", "Step3", "StairRail", "StairFixture"]:
			assert_not_null(l.geometry.get_node_or_null(NodePath(n)), "%s: %s" % [id, n])
		# The half-flight descends: each tread below the one before, ending 0.8 m down.
		var prev := 0.0
		for i in LandingStairwell.STAIR_STEPS:
			var step := l.geometry.get_node("Step%d" % i) as MeshInstance3D
			var top := step.position.y + (step.mesh as BoxMesh).size.y * 0.5
			assert_lt(top, prev, "step %d is below the last" % i)
			prev = top
		assert_approx(prev, -LandingStairwell.STAIR_RISE * LandingStairwell.STAIR_STEPS, 0.001)
		# One light, the fixture's, in the stratum's colour; the elevator's are out.
		var lights := _visible_lights(l)
		assert_eq(lights.size(), 1, "%s: one wall fixture light" % id)
		assert_eq(lights[0], l.stair_light)
		var data := load("res://data/strata/%s.tres" % id) as StratumData
		assert_eq(l.stair_light.light_color, data.fixture_light_color)
		assert_gt(l.stair_light.light_energy, 0.0)
		assert_null(l.studio_light)
		# No lit cabin mesh remains: the ceiling panel and the door lamp are hidden; the
		# only emissive mesh is the fixture's face.
		for m in l.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			if not mi.is_visible_in_tree() or not (mi.material_override is ShaderMaterial):
				continue
			var es: Variant = (mi.material_override as ShaderMaterial).get_shader_parameter(&"emission_strength")
			if es != null and float(es) > 0.0:
				assert_eq(mi.get_parent().name, &"StairFixture", "emissive %s" % mi.name)
		l.queue_free()
	await await_frames(1)


func test_stairwell_uses_the_strata_materials() -> void:
	for id: StringName in [&"pools", &"server"]:
		var l := _landing(id)
		var wall := LandingStairwell.material(id, &"wall")
		var floor_mat := LandingStairwell.material(id, &"floor")
		assert_true((wall as Resource).resource_path.begins_with("res://data/materials/%s/" % id))
		var walls := 0
		var ceilings := 0
		for c in l.geometry.get_children():
			var mi := c as MeshInstance3D
			if mi == null:
				continue
			match mi.get_meta(&"role", &"") as StringName:
				&"wall":
					walls += 1
					assert_eq(mi.material_override, wall)
				&"ceiling":
					ceilings += 1
					assert_eq(mi.material_override, LandingStairwell.material(id, &"ceiling"))
				&"floor", &"rail":
					assert_false(mi.visible, "the elevator's floor slab and rail are gone")
		assert_eq(walls, 6, "every shell wall piece")
		assert_eq(ceilings, 1)
		assert_eq(l.geometry.get_node("StairLanding").material_override, floor_mat)
		assert_eq(l._door_l.material_override, LandingStairwell.material(id, &"door"))
		l.queue_free()
	await await_frames(1)


func test_stairwell_keeps_panel_door_and_player_spot() -> void:
	var cabin := _landing(&"halls")
	var stair := _landing(&"pools")
	assert_eq(stair.player_transform(), cabin.player_transform())
	var q0 := cabin.geometry.get_node(^"PanelQuad") as MeshInstance3D
	var q1 := stair.geometry.get_node(^"PanelQuad") as MeshInstance3D
	assert_eq(q1.position, q0.position)
	assert_eq(q1.material_override.shader, q0.material_override.shader)
	assert_eq(stair._door_l.position, cabin._door_l.position)
	assert_eq(stair._door_r.position, cabin._door_r.position)
	# The player's spot still stands on collision: the landing block replaces the slab.
	var space := stair.get_world_3d().direct_space_state
	await await_frames(2)
	var from := stair.player_transform().origin + Vector3(0.0, 1.0, 0.0)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, -2.5, 0.0), PlayerLayers.WORLD_MASK))
	assert_false(hit.is_empty(), "the landing block holds the player")
	assert_approx((hit[&"position"] as Vector3).y, 0.0, 0.001)
	cabin.queue_free()
	stair.queue_free()
	await await_frames(1)


func test_begin_themes_from_the_run() -> void:
	var keep := GameState.run
	GameState.run = RunState.new()
	GameState.run.depth = Tuning.RUN_FINAL_DEPTH - 1
	var want := Landing.next_stratum()
	var l := (load("res://scenes/landing.tscn") as PackedScene).instantiate() as Landing
	add_child(l)
	var probe := Node3D.new()
	add_child(probe)
	l.begin(probe, [&"chalk", &"glowstick"] as Array[StringName], false)
	assert_eq(l.theme, want)
	assert_eq(l.stair_light != null, LandingStairwell.is_stairwell(want))
	l.queue_free()
	probe.queue_free()
	GameState.run = keep
	await await_frames(1)
