extends TestCase
## M2.13a Pools and Garage look (02 §5, §6, §7): the per-stratum environment (ambient, fog
## emission, SSAO strength, background reflection) against Tuning and StratumData, the water
## material and shader, the Pools tile refinements (grout, bevel, wet sheen), the props on the
## world shader in their palettes, the pillar lamps' light standing off the pillar, and the
## build-verification poses (no corridor pose starts in a parked car; the deck pose stands
## clear of cars).

const WORLD_SHADER := "res://shaders/world_surface.gdshader"
const WATER_SHADER := "res://shaders/water.gdshader"
const FIXTURE_GLOW_SHADER := "res://shaders/fixture_glow.gdshader"
const WATER := "res://data/materials/pools/water.tres"
const POOLS_TILES := ["tile_floor", "tile_wall", "tile_ceiling", "basin_tile", "soft_wall"]
## 02 §7 Garage props: car bodies #2E2E33, #5A1E1E, #1E2E5A, #CFCFCF.
const CAR_COLORS: Array[String] = ["#2E2E33", "#5A1E1E", "#1E2E5A", "#CFCFCF"]
const PROP_SCENES: Array[String] = [
	"res://scenes/props/garage/car.tscn", "res://scenes/props/garage/barrier.tscn",
	"res://scenes/props/garage/exit_sign.tscn", "res://scenes/props/garage/pillar.tscn",
	"res://scenes/props/garage/fixture_sodium_lamp.tscn",
	"res://scenes/props/pools/lifeguard_chair.tscn", "res://scenes/props/pools/lane_rope.tscn",
	"res://scenes/props/pools/ladder.tscn", "res://scenes/props/pools/fixture_panel.tscn",
]


func _mat(path: String) -> ShaderMaterial:
	return load(path) as ShaderMaterial


func _p(m: ShaderMaterial, name: StringName) -> Variant:
	return m.get_shader_parameter(name)


# ---------------------------------------------------------------- environment

func test_environment_values_per_stratum() -> void:
	for id in Tuning.STRATA_ALL:
		var s := DataRegistry.stratum(id)
		assert_approx(s.ambient_energy, float(Tuning.STRATUM_AMBIENT_ENERGY[id]), 0.0001, "ambient energy " + String(id))
		# 02 §6 range 0.08 to 0.2 (the Substrate is darker by its look sheet, 0.05).
		assert_true(id == &"substrate" or (s.ambient_energy >= Tuning.LIGHT_AMBIENT_ENERGY_MIN and s.ambient_energy <= Tuning.LIGHT_AMBIENT_ENERGY_MAX),
				"02 §6 ambient energy 0.08 to 0.2: " + String(id))
		var env := StratumEnvironment.build(s, &"medium")
		assert_eq(env.ambient_light_color, s.ambient_color, String(id))
		assert_approx(env.ambient_light_energy, s.ambient_energy, 0.0001, String(id))
		assert_approx(env.ssao_intensity, float(Tuning.RENDER_AO_INTENSITY_STRATUM.get(id, Tuning.RENDER_AO_INTENSITY)), 0.0001, String(id))
		var reflects := Tuning.RENDER_REFLECT_BACKGROUND_STRATA.has(id)
		assert_eq(env.reflected_light_source, Environment.REFLECTION_SOURCE_BG if reflects else Environment.REFLECTION_SOURCE_DISABLED, String(id))
		if env.volumetric_fog_enabled:
			assert_approx(env.volumetric_fog_emission_energy,
					float(Tuning.RENDER_FOG_EMISSION_STRATUM.get(id, Tuning.RENDER_FOG_EMISSION_ENERGY)), 0.0001, String(id))
	# Halls keeps its look (no regression): AO 2.0, no reflections, the default fog emission.
	var halls := StratumEnvironment.build(DataRegistry.stratum(&"halls"), &"medium")
	assert_approx(halls.ssao_intensity, Tuning.RENDER_AO_INTENSITY)
	assert_eq(halls.reflected_light_source, Environment.REFLECTION_SOURCE_DISABLED)
	assert_approx(halls.volumetric_fog_emission_energy, Tuning.RENDER_FOG_EMISSION_ENERGY)


func test_garage_is_sodium_dark_but_not_black() -> void:
	var g := DataRegistry.stratum(&"garage")
	var env := StratumEnvironment.build(g, &"medium")
	# The bounce of the sodium lamps: an amber ambient (red > green > blue), at the 02 cap.
	assert_eq(g.ambient_color.to_html(false).to_upper(), "6A5032")
	assert_gt(g.ambient_color.r, g.ambient_color.g)
	assert_gt(g.ambient_color.g, g.ambient_color.b)
	assert_approx(env.ambient_light_energy, Tuning.LIGHT_AMBIENT_ENERGY_MAX)
	assert_lt(env.ssao_intensity, Tuning.RENDER_AO_INTENSITY, "softer AO in the Garage")
	assert_gt(env.volumetric_fog_emission_energy, 1.0, "the deep shadows hold amber air")
	assert_approx(g.fog_density, 0.015, 0.0001, "fog density unchanged (02 §6)")
	assert_approx(g.fixture_light_energy, 1.4, 0.0001)
	assert_approx(g.fixture_light_range, 12.0, 0.0001)
	# Pillar lamps light from off the pillar face.
	assert_gt(float(Tuning.LIGHT_FIXTURE_OUT_STRATUM.get(&"garage", 0.0)), 0.3)
	assert_false(Tuning.LIGHT_FIXTURE_OUT_STRATUM.has(&"halls"))


# ---------------------------------------------------------------- water

func test_water_material_properties() -> void:
	var m := _mat(WATER)
	var pools := DataRegistry.stratum(&"pools")
	assert_eq((m.shader as Shader).resource_path, WATER_SHADER)
	var wc: Color = _p(m, &"water_color")
	assert_eq(wc.to_html(false).to_upper(), "2E8B8B", "02 §7 water #2E8B8B")
	assert_approx(wc.a, Tuning.POOLS_WATER_ALPHA, 0.001, "alpha 0.75")
	assert_eq(wc, pools.water_color, "StratumData water colour")
	assert_approx(float(_p(m, &"refraction")), Tuning.POOLS_WATER_REFRACTION, 0.0001, "refraction 0.03")
	var rc: Color = _p(m, &"reflect_color")
	assert_eq(rc.to_html(false), pools.fog_color.to_html(false), "Fresnel reflects the air (fog colour)")
	var deep: Color = _p(m, &"deep_color")
	assert_lt(deep.get_luminance(), wc.get_luminance(), "deep water is darker")
	assert_gt(float(_p(m, &"tint_depth")), 0.0)
	assert_gt(float(_p(m, &"caustic_strength")), 0.0)
	assert_gt(float(_p(m, &"drip_strength")), 0.0)
	# T8: procedural noise only.
	assert_true(_p(m, &"normal_noise") is NoiseTexture2D, "normal layers from NoiseTexture2D")
	assert_contains((load(WATER_SHADER) as Shader).code, "float caustic_web(", "caustics are shader math")


func test_water_shader_takes_the_coherence_include() -> void:
	var code := (load(WATER_SHADER) as Shader).code
	assert_contains(code, "#include \"res://shaders/include/coherence.gdshaderinc\"")
	assert_contains(code, "coh_jitter(", "jitters like the world")
	assert_contains(code, "coh_null_u(", "unrenders near Null")
	assert_contains(code, "coh_commit_u(", "unrenders in the noclip commit")
	assert_contains(code, "GRID_COLOR * line", "unrendered water shows the world grid")
	assert_contains(code, "hint_depth_texture", "depth tint and caustics read what lies below")
	assert_contains(code, "hint_screen_texture", "screen-space refraction")
	# Graded by the screen pass (it runs over the finished image): no grade of its own here.
	assert_false(code.contains("g_coherence"), "desaturation is the screen pass's job")
	var names: Array[StringName] = []
	for u in RenderingServer.get_shader_parameter_list((load(WATER_SHADER) as Shader).get_rid()):
		names.append(StringName(u[&"name"]))
	if names.is_empty():
		return  # the dummy renderer reports no uniforms (see test_render_setup)
	for n: StringName in [&"water_color", &"deep_color", &"refraction", &"reflect_color", &"caustic_strength", &"tint_depth"]:
		assert_true(names.has(n), "water uniform " + String(n))


# ---------------------------------------------------------------- tiles and props

func test_pools_tiles_have_grout_bevel_and_wet_sheen() -> void:
	for n in POOLS_TILES:
		var m := _mat("res://data/materials/pools/%s.tres" % n)
		assert_eq((m.shader as Shader).resource_path, WORLD_SHADER, n)
		assert_eq(int(_p(m, &"pattern_mode")), 1, n + ": tiles")
		assert_approx(float(_p(m, &"pattern_scale")), Tuning.POOLS_TILE_SIZE, 0.0001, n)
		assert_approx(float(_p(m, &"pattern_detail")), Tuning.POOLS_TILE_GROUT, 0.0001, n)
		assert_gt(float(_p(m, &"grout_roughness")), float(_p(m, &"roughness")), n + ": grout is rougher than glaze")
		assert_gt(float(_p(m, &"tile_bevel")), 0.0, n)
	assert_gt(float(_p(_mat("res://data/materials/pools/basin_tile.tres"), &"wet")), 0.0, "basins are wet")
	assert_gt(float(_p(_mat("res://data/materials/pools/tile_floor.tres"), &"puddles")), 0.0, "the deck has standing water")
	# Halls materials never set the new uniforms (shader defaults are off).
	for n in ["carpet", "wallpaper", "ceiling_tile"]:
		var h := _mat("res://data/materials/halls/%s.tres" % n)
		assert_null(_p(h, &"wet"), n)
		assert_null(_p(h, &"tile_bevel"), n)


func test_world_shader_new_terms_default_off() -> void:
	var code := (load(WORLD_SHADER) as Shader).code
	for decl in ["uniform float grout_roughness = -1.0;", "uniform float tile_bevel = 0.0;",
			"uniform float wet = 0.0;", "uniform float puddles = 0.0;"]:
		assert_contains(code, decl)


func test_props_use_the_world_shader_in_their_palettes() -> void:
	for path in PROP_SCENES:
		var root := (load(path) as PackedScene).instantiate()
		var meshes := root.find_children("*", "MeshInstance3D", true, false)
		assert_gt(meshes.size(), 0, path)
		for mi: MeshInstance3D in meshes:
			var m := mi.material_override as ShaderMaterial
			assert_not_null(m, "%s %s has a world material" % [path, mi.name])
			# The fixtures' ceiling glow is its own small shader (02 §5); everything else is world.
			if m != null and (m.shader as Shader).resource_path != FIXTURE_GLOW_SHADER:
				assert_eq((m.shader as Shader).resource_path, WORLD_SHADER, "%s %s" % [path, mi.name])
		root.free()
	for i in CAR_COLORS.size():
		var m := _mat("res://data/materials/garage/car_body_%d.tres" % i)
		assert_eq((_p(m, &"albedo") as Color).to_html(false).to_upper(), CAR_COLORS[i].trim_prefix("#"), "car %d" % i)
		# Painted bodies are dielectric: with reflections off, a metal reads black (T3).
		assert_approx(float(_p(m, &"metallic")), 0.0, 0.0001, "car %d" % i)
	for n in ["car_glass", "car_tyre", "fixture_cage"]:
		assert_approx(float(_p(_mat("res://data/materials/garage/%s.tres" % n), &"metallic")), 0.0, 0.0001, n)


# ---------------------------------------------------------------- pillar lamps

func test_pillar_lamp_light_stands_off_the_pillar() -> void:
	var level := LevelGenerator.generate(&"garage", 2, 301)
	var g := level.grid
	var place: Dictionary = {}
	for p in level.placements_of(LevelData.P_FIXTURE):
		if (p[&"params"] as Dictionary).has(&"dir"):
			place = p
			break
	assert_false(place.is_empty(), "a pillar lamp")
	if place.is_empty():
		return
	var pool := LightPool.new()
	add_child(pool)
	pool.configure(DataRegistry.stratum(&"garage"))
	pool.grid = g
	var f := (load("res://scenes/props/garage/fixture_sodium_lamp.tscn") as PackedScene).instantiate() as Fixture
	add_child(f)
	f.global_position = g.world_of(place[&"cell"]) + (place[&"offset"] as Vector3)
	var dir: int = place[&"params"][&"dir"]
	var out := Vector3(LevelGrid.DIRS[dir].x, 0.0, LevelGrid.DIRS[dir].y)
	var want := f.global_position - Vector3(0.0, pool.light_drop, 0.0) + out * Tuning.LIGHT_FIXTURE_OUT_STRATUM[&"garage"]
	assert_true(pool.anchor_of(f).is_equal_approx(want), "anchor %s want %s" % [pool.anchor_of(f), want])
	# A ceiling fixture over a walkable cell hangs straight below.
	var c2 := level.spawn_cell
	f.global_position = g.world_of(c2) + Vector3(0.0, 3.0, 0.0)
	pool.grid = g
	assert_true(pool.anchor_of(f).is_equal_approx(f.global_position - Vector3(0.0, pool.light_drop, 0.0)))
	f.free()
	pool.free()


# ---------------------------------------------------------------- poses

func test_corridor_poses_never_start_in_a_parked_car() -> void:
	for i in 12:
		var level := LevelGenerator.generate(&"garage", 2, 1 + i)
		var g := level.grid
		for p in LevelShots.poses(level):
			if not [&"corridor", &"corridor_long", &"deck"].has(p[&"name"]):
				continue
			var c := g.cell_of(p[&"from"])
			assert_false(LevelShots.prop_cell(g, c), "seed %d %s starts in a prop cell %s" % [1 + i, p[&"name"], c])
			if p[&"name"] == &"deck":
				for d in 4:
					assert_false(LevelShots.prop_cell(g, c + LevelGrid.DIRS[d]), "seed %d deck pose beside a car" % (1 + i))
			# Standing height: the camera is EYE above the floor it stands on (deck 1 too).
			assert_approx((p[&"from"] as Vector3).y - g.floor_y(c), LevelShots.EYE, 0.01, "%s eye height" % p[&"name"])
