extends TestCase
## M3.2 render pass: 02 §10 particles (Pools' rising bubbles per wet basin, the Substrate's
## 1 px white pixels drifting upward, none in Server) and the Substrate's themed Landing
## (05 §4, 02 §7: the cabin shell in the Substrate surface, the cabin lights out, one studio
## light, the item panel unchanged).

const SUBSTRATE_SURFACE := "res://data/materials/substrate/surface.tres"


# ---------------------------------------------------------------- particles

func test_substrate_pixels_rise_one_pixel_white() -> void:
	var d := DustMotes.create_pixels()
	assert_eq(d.amount, Tuning.SUBSTRATE_PIXEL_PARTICLES)
	assert_false(d.local_coords, "world space, like the dust")
	var m := d.process_material as ParticleProcessMaterial
	assert_eq(m.direction, Vector3.UP)
	assert_true(m.spread < 30.0, "drifting upward, not in every direction")
	assert_gt(m.initial_velocity_min, 0.0)
	assert_eq(m.gravity, Vector3.ZERO)
	var mat := (d.draw_pass_1 as QuadMesh).material as ShaderMaterial
	assert_eq(mat.shader.resource_path, "res://shaders/pixel_particles.gdshader")
	assert_approx(float(mat.get_shader_parameter(&"pixel_px")), 1.0)
	var c: Color = mat.get_shader_parameter(&"pixel_color")
	assert_true(c.r > 0.85 and c.g > 0.85 and c.b > 0.85, "white pixels")
	# Low preset: 50% counts (02 §12).
	assert_eq(DustMotes.create_pixels(Tuning.PARTICLES_LOW_SCALE).amount, roundi(Tuning.SUBSTRATE_PIXEL_PARTICLES * 0.5))
	d.free()
	DustMotes.create_pixels(0.5).free()


func test_pool_bubbles_rise_floor_to_surface() -> void:
	var size := Vector2(6.0, 8.0)
	var streams := PoolBubbles.streams(size, -1.5, 1.2, 7)
	assert_eq(streams.size(), PoolBubbles.stream_count(size))
	assert_eq(PoolBubbles.stream_count(size), mini(Tuning.POOLS_BUBBLE_STREAMS_MAX, roundi(48.0 / Tuning.POOLS_BUBBLE_STREAM_AREA)))
	for b in streams:
		assert_eq(b.amount, Tuning.POOLS_BUBBLES_PER_STREAM)
		var m := b.process_material as ParticleProcessMaterial
		assert_eq(m.direction, Vector3.UP)
		assert_true(absf(b.position.x) <= size.x * 0.5 and absf(b.position.z) <= size.y * 0.5, "source inside the basin")
		# A bubble ends at the surface: start height + rise over its lifetime stays under it.
		var top := b.position.y + Tuning.POOLS_BUBBLE_RISE * b.lifetime
		assert_lt(top, -1.5 + 1.2, "bubbles end under the surface")
		assert_gt(top, -1.5 + 1.2 - 0.1, "bubbles reach the surface")
		assert_approx(float(b.get_instance_shader_parameter(&"surface_y")), -1.5 + 1.2)
		assert_eq(((b.draw_pass_1 as QuadMesh).material as ShaderMaterial).render_priority, 1,
				"drawn after the water's surface (it refracts the opaque image only)")
		b.free()
	# Deterministic sources: the same key gives the same points; a dry basin has none.
	var again := PoolBubbles.streams(size, -1.5, 1.2, 7)
	var other := PoolBubbles.streams(size, -1.5, 1.2, 8)
	assert_eq(again[0].position, PoolBubbles.streams(size, -1.5, 1.2, 7)[0].position)
	assert_ne(again[0].position, other[0].position)
	for b in again + other:
		b.free()
	assert_true(PoolBubbles.streams(Vector2(4.0, 4.0), 0.0, 0.0, 1).is_empty())
	assert_eq(PoolBubbles.stream_count(Vector2(40.0, 40.0)), Tuning.POOLS_BUBBLE_STREAMS_MAX)
	assert_eq(PoolBubbles.stream_count(Vector2(1.6, 1.6)), 1)
	# Low preset: half the bubbles per stream.
	var low := PoolBubbles.create(Vector3.ZERO, 1.0, Tuning.PARTICLES_LOW_SCALE)
	assert_eq(low.amount, roundi(Tuning.POOLS_BUBBLES_PER_STREAM * 0.5))
	low.free()


func test_water_volume_carries_bubbles() -> void:
	var w := WaterVolume.new()
	w.setup(Rect2i(0, 0, 2, 3), -0.4, -1.6)
	add_child(w)
	assert_false(w.bubbles.is_empty(), "a wet basin has bubbles")
	for b in w.bubbles:
		assert_eq(b.get_parent(), w)
	w.queue_free()
	await await_frames(1)


func test_level_begin_adds_substrate_pixels() -> void:
	var data := LevelGenerator.generate(Tuning.STRATUM_SUBSTRATE, Tuning.RUN_FINAL_DEPTH, 1, false, 1, {})
	var level := (load("res://scenes/level.tscn") as PackedScene).instantiate() as Level
	add_child(level)
	level.begin(data)
	assert_not_null(level.dust)
	assert_eq(String(level.dust.name), "SubstratePixels")
	await level.built
	level.queue_free()
	await await_frames(1)


# ---------------------------------------------------------------- the Substrate Landing

func _landing(stratum: StringName) -> Landing:
	var l := (load("res://scenes/landing.tscn") as PackedScene).instantiate() as Landing
	l.apply_theme(stratum)
	add_child(l)
	return l


func test_cabin_landing_keeps_its_lights() -> void:
	var l := _landing(&"halls")
	assert_null(l.studio_light)
	var lit := 0
	for n in l.geometry.get_children():
		if n is Light3D and (n as Light3D).visible:
			lit += 1
	assert_eq(lit, 2, "the ceiling light and the warm key")
	l.queue_free()
	await await_frames(1)


func test_substrate_landing_is_the_lit_white_pocket() -> void:
	var l := _landing(Tuning.STRATUM_SUBSTRATE)
	var surface := load(SUBSTRATE_SURFACE)
	assert_approx(float((surface as ShaderMaterial).get_shader_parameter(&"u_floor")), 0.55)
	var panel_quad := l.geometry.get_node(^"PanelQuad") as MeshInstance3D
	var shell := 0
	for n in l.geometry.get_children():
		var mi := n as MeshInstance3D
		if mi == null or not mi.visible or mi == panel_quad:
			continue
		shell += 1
		assert_eq(mi.material_override, surface, "shell surface %s is the Substrate's" % mi.name)
	assert_gt(shell, 8, "the whole shell")
	# The item panel is unchanged (its own shader, the panel texture).
	assert_eq((panel_quad.material_override as ShaderMaterial).shader.resource_path, Landing.PANEL_SHADER)
	# One studio light, white, 0.6, 15 m, no shadows; the cabin's lights are out.
	var lights: Array[Light3D] = []
	for n in l.find_children("*", "Light3D", true, false):
		if (n as Light3D).is_visible_in_tree():
			lights.append(n as Light3D)
	assert_eq(lights.size(), 1, "one studio light")
	assert_eq(lights[0], l.studio_light)
	assert_eq(l.studio_light.light_color, Color.WHITE)
	assert_approx(l.studio_light.light_energy, Tuning.SUBSTRATE_STUDIO_LIGHT_ENERGY)
	assert_approx(l.studio_light.omni_range, Tuning.SUBSTRATE_STUDIO_LIGHT_RANGE)
	assert_false(l.studio_light.shadow_enabled)
	# Nothing warm: no emissive mesh but the studio face (02 §7: the only warm light in the
	# stratum is the Threshold's daylight).
	for n in l.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.is_visible_in_tree() or not (mi.material_override is ShaderMaterial):
			continue
		var sm := mi.material_override as ShaderMaterial
		if sm.shader.resource_path != "res://shaders/world_surface.gdshader":
			continue
		var es: Variant = sm.get_shader_parameter(&"emission_strength")
		if es != null and float(es) > 0.0:
			var e: Color = sm.get_shader_parameter(&"emission")
			assert_true(is_equal_approx(e.r, e.g) and is_equal_approx(e.g, e.b), "white emission only: %s" % mi.name)
	l.queue_free()
	await await_frames(1)


func test_landing_theme_follows_the_run() -> void:
	# The run descends before it opens the Landing, so the run's depth is the door's stratum.
	var keep := GameState.run
	GameState.run = RunState.new()
	GameState.run.depth = Tuning.RUN_FINAL_DEPTH
	assert_eq(Landing.next_stratum(), GameState.stratum_for(Tuning.RUN_FINAL_DEPTH))
	assert_eq(Landing.next_stratum(), Tuning.STRATUM_SUBSTRATE)
	GameState.run = keep


# ---------------------------------------------------------------- shaders, T2

func test_particle_shaders_compile() -> void:
	for path in ["res://shaders/pixel_particles.gdshader", "res://shaders/bubble_particles.gdshader"]:
		var sh := load(path) as Shader
		assert_not_null(sh, path)
		assert_gt(sh.get_shader_uniform_list().size(), 0, "%s compiled" % path)


## 02 T2 (seed 1 of every stratum with fixtures): the stratum's own fixtures repeat on an
## exact grid. Corridor fixtures sit on the level-wide corridor lattice (07 §5: every 2 cells,
## `FixtureOps.on_lattice`); the fixtures of a room form one regular grid (equal steps in x
## and in z, every row full). Profiles (Server's rack LEDs and exit light) are skipped.
const T2_CORRIDOR_SPACING := {&"halls": Tuning.HALLS_FIXTURE_SPACING_CELLS,
	&"pools": Tuning.POOLS_FIXTURE_SPACING_CORRIDOR_CELLS, &"offices": Tuning.OFFICES_FIXTURE_SPACING_CELLS}


func test_t2_fixtures_repeat_on_an_exact_grid() -> void:
	for id: StringName in [&"halls", &"pools", &"garage", &"offices", &"server"]:
		var s := DataRegistry.stratum(id)
		var data := LevelGenerator.generate(id, s.depth_min, 1, false, 1, {})
		var by_room: Dictionary = {}
		var off: Array[String] = []
		var n := 0
		for p in data.placements_of(LevelData.P_FIXTURE):
			var kind: StringName = p[&"params"].get(&"fixture", s.fixture_kind)
			if kind != s.fixture_kind:
				continue
			n += 1
			var c: Vector2i = p[&"cell"]
			var o: Vector3 = p[&"offset"]
			var room := data.grid.room_of(c)
			if room == null:
				if T2_CORRIDOR_SPACING.has(id) and not FixtureOps.on_lattice(data.grid, c, T2_CORRIDOR_SPACING[id]):
					off.append("corridor %s" % c)
				continue
			if not by_room.has(room):
				by_room[room] = []
			by_room[room].append(Vector2(c) * Tuning.GRID_CELL_SIZE + Vector2(o.x, o.z))
		assert_gt(n, 3, "%s has fixtures" % id)
		for room: RoomData in by_room:
			var pts: Array = by_room[room]
			var xs := _distinct(pts.map(func(v: Vector2) -> float: return v.x))
			var zs := _distinct(pts.map(func(v: Vector2) -> float: return v.y))
			if not _even(xs) or not _even(zs) or xs.size() * zs.size() != pts.size():
				off.append("room %s: x %s z %s (%d)" % [room.rect, xs, zs, pts.size()])
		print("T2 %s: %d fixtures, %d rooms, off %s" % [id, n, by_room.size(), off])
		assert_true(off.is_empty(), "%s fixtures off the grid: %s" % [id, off])


static func _distinct(values: Array) -> Array[float]:
	var out: Array[float] = []
	for v: float in values:
		var seen := false
		for u in out:
			seen = seen or absf(u - v) < 0.001
		if not seen:
			out.append(v)
	out.sort()
	return out


static func _even(v: Array[float]) -> bool:
	for i in range(2, v.size()):
		if absf((v[i] - v[i - 1]) - (v[1] - v[0])) > 0.001:
			return false
	return true


## 02 T7: no motion blur, lens flare or depth of field. Godot draws none of them without
## CameraAttributes; neither the player's camera nor any stratum's environment carries any,
## and glow is the soft fixture bloom of 02 §3.
func test_t7_no_lens_effects() -> void:
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	for n in player.find_children("*", "Camera3D", true, false):
		assert_null((n as Camera3D).attributes, "camera attributes on %s" % n.name)
	player.free()
	for id in Tuning.STRATA_ALL:
		var env := StratumEnvironment.build(DataRegistry.stratum(id), &"medium")
		assert_eq(env.glow_blend_mode, Environment.GLOW_BLEND_MODE_SOFTLIGHT, String(id))
		assert_approx(env.glow_hdr_threshold, Tuning.RENDER_GLOW_THRESHOLD, 0.0001, String(id))


## 02 §6: the player's beam has the soft cone edge (spot_angle_attenuation 1.2), not a
## steeper distance falloff; the tour's stand-in flashlight is the same light.
func test_flashlight_beam_matches_02() -> void:
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	var beams := player.find_children("Beam", "SpotLight3D", true, false)
	assert_eq(beams.size(), 1)
	var beam := beams[0] as SpotLight3D
	assert_approx(beam.spot_angle_attenuation, Tuning.FLASH_ATTENUATION_ANGLE)
	assert_approx(beam.spot_attenuation, 1.0)
	player.free()
	var torch := ScreenshotTour.make_flashlight()
	var spot := torch.get_child(0) as SpotLight3D
	assert_approx(spot.spot_angle_attenuation, Tuning.FLASH_ATTENUATION_ANGLE)
	assert_approx(spot.spot_angle, Tuning.FLASH_SPOT_ANGLE)
	torch.free()
