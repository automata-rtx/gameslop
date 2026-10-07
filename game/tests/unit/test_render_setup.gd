extends TestCase
## Shaders compile, the Halls materials match the look sheet, the environment builder maps
## StratumData and presets, the post stack is wired (02 §3-§7, §10, §12). Headless: the
## dummy renderer still parses shaders and reports an empty uniform list on failure.

const SHADERS := {
	"res://shaders/world_surface.gdshader": [&"albedo", &"albedo_secondary", &"pattern_mode", &"pattern_scale",
			&"roughness", &"metallic", &"emission", &"emission_strength", &"noise_albedo", &"noise_normal",
			&"normal_strength", &"triplanar_scale", &"held", &"soft", &"u_floor", &"jitter_floor",
			&"pattern_contrast", &"print_amount"],
	"res://shaders/coherence_post.gdshader": [&"line_color"],
	"res://shaders/coherence_screen.gdshader": [&"ca", &"sat", &"warmth", &"grain", &"vig", &"scan", &"invert",
			&"flash", &"black", &"ripple", &"grain_time"],
}
const INCLUDE := "res://shaders/include/coherence.gdshaderinc"
const GLOBALS: Array[String] = ["g_coherence", "g_noclip_charge", "g_noclip_commit", "g_noclip_target",
		"g_noclip_target_normal", "g_noclip_invalid", "g_null_pos", "g_null_radius", "g_time"]
const HALLS_MATERIALS := ["carpet", "wallpaper", "ceiling_tile", "fixture_emissive", "soft_wall"]
const HALLS := preload("res://data/strata/halls.tres")
const SUBSTRATE := preload("res://data/strata/substrate.tres")


func _uniform_names(shader: Shader) -> Array[StringName]:
	var out: Array[StringName] = []
	for u in shader.get_shader_uniform_list():
		out.append(StringName(u["name"]))
	return out


func test_shaders_compile_with_their_uniforms() -> void:
	for path in SHADERS:
		var shader := load(path) as Shader
		assert_not_null(shader, path)
		var names := _uniform_names(shader)
		assert_gt(names.size(), 0, "%s compiled" % path)
		for u in SHADERS[path]:
			assert_contains(names, u, path)


func test_world_shader_reads_the_globals_and_never_blends() -> void:
	var code := (load("res://shaders/world_surface.gdshader") as Shader).code
	assert_contains(code, "#include \"res://shaders/include/coherence.gdshaderinc\"")
	code += (load(INCLUDE) as ShaderInclude).code
	for g in GLOBALS:
		assert_contains(code, "global uniform", g)
		assert_contains(code, g)
	assert_contains(code, "ALPHA_SCISSOR_THRESHOLD")
	assert_false(code.contains("blend_add") or code.contains("depth_draw_never"), "opaque pipeline only")


func test_materials_instantiate_headless() -> void:
	for m in HALLS_MATERIALS:
		var mat := load("res://data/materials/halls/%s.tres" % m) as ShaderMaterial
		assert_not_null(mat, m)
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		mi.material_override = mat
		add_child(mi)
	await await_frames(2)
	for c in get_children():
		c.queue_free()


func test_halls_materials_match_the_look_sheet() -> void:
	var wall := load("res://data/materials/halls/wallpaper.tres") as ShaderMaterial
	assert_eq(wall.get_shader_parameter(&"albedo"), HALLS.wall_color)
	assert_eq(wall.get_shader_parameter(&"albedo_secondary"), HALLS.wall_color_secondary)
	assert_eq(wall.get_shader_parameter(&"pattern_mode"), HALLS.wall_pattern_mode)
	assert_approx(wall.get_shader_parameter(&"pattern_detail"), HALLS.wall_pattern_scale, 0.0001, "0.6 m stripes")
	assert_approx(wall.get_shader_parameter(&"roughness"), HALLS.wall_roughness)
	assert_approx(wall.get_shader_parameter(&"normal_strength"), HALLS.wall_normal_strength)
	var carpet := load("res://data/materials/halls/carpet.tres") as ShaderMaterial
	assert_eq(carpet.get_shader_parameter(&"albedo"), HALLS.floor_color)
	assert_eq(carpet.get_shader_parameter(&"pattern_mode"), HALLS.floor_pattern_mode)
	assert_approx(carpet.get_shader_parameter(&"pattern_scale"), HALLS.floor_pattern_scale)
	assert_approx(carpet.get_shader_parameter(&"roughness"), HALLS.floor_roughness)
	var ceiling := load("res://data/materials/halls/ceiling_tile.tres") as ShaderMaterial
	assert_eq(ceiling.get_shader_parameter(&"albedo"), HALLS.ceiling_color)
	assert_eq(ceiling.get_shader_parameter(&"pattern_mode"), HALLS.ceiling_pattern_mode)
	assert_approx(ceiling.get_shader_parameter(&"pattern_scale"), HALLS.ceiling_pattern_scale)
	assert_approx(ceiling.get_shader_parameter(&"roughness"), HALLS.ceiling_roughness)
	var fixture := load("res://data/materials/halls/fixture_emissive.tres") as ShaderMaterial
	assert_eq(fixture.get_shader_parameter(&"emission"), HALLS.fixture_emission_color)
	assert_approx(fixture.get_shader_parameter(&"emission_strength"), HALLS.fixture_emission_strength)
	var soft := load("res://data/materials/halls/soft_wall.tres") as ShaderMaterial
	assert_approx(soft.get_shader_parameter(&"soft"), 1.0)
	assert_eq(soft.get_shader_parameter(&"albedo"), HALLS.wall_color)


func test_noise_textures_respect_the_budget() -> void:
	# T8: procedural only; 14 §10: noise textures <= 1024².
	for n in ["noise_albedo", "noise_normal"]:
		var tex := load("res://data/materials/%s.tres" % n) as NoiseTexture2D
		assert_not_null(tex, n)
		assert_true(tex.width <= Tuning.WORLD_NOISE_TEXTURE_MAX and tex.height <= Tuning.WORLD_NOISE_TEXTURE_MAX, n)
		assert_true(tex.seamless, n)
		assert_eq(tex.width, Tuning.QUALITY_TEXTURE_SIZE_HIGH, "12 §3: Texture detail defaults to High")


func test_environment_maps_stratum_data() -> void:
	var env := StratumEnvironment.build(HALLS, &"medium")
	assert_eq(env.background_mode, Environment.BG_COLOR)
	assert_eq(env.background_color, HALLS.fog_color, "sky colour is the fog colour")
	assert_eq(env.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR)
	assert_eq(env.ambient_light_color, HALLS.ambient_color)
	assert_approx(env.ambient_light_energy, HALLS.ambient_energy)
	assert_eq(env.tonemap_mode, Environment.TONE_MAPPER_AGX)
	assert_approx(env.tonemap_exposure, HALLS.exposure)
	assert_false(env.sdfgi_enabled, "no GI in v1.0")
	assert_true(env.glow_enabled)
	assert_approx(env.glow_hdr_threshold, 1.0)
	assert_approx(env.glow_intensity, 0.6)
	assert_approx(env.glow_bloom, 0.1)
	assert_eq(env.glow_blend_mode, Environment.GLOW_BLEND_MODE_SOFTLIGHT)
	assert_true(env.ssao_enabled)
	assert_approx(env.ssao_radius, 1.0)
	assert_approx(env.ssao_intensity, 2.0)
	assert_false(env.ssil_enabled, "SSIL at High only")
	assert_true(env.volumetric_fog_enabled)
	assert_approx(env.volumetric_fog_density, HALLS.fog_density)
	assert_eq(env.volumetric_fog_albedo, HALLS.fog_color)
	assert_false(env.fog_enabled)


func test_environment_presets() -> void:
	var high := StratumEnvironment.build(HALLS, &"high")
	assert_true(high.ssil_enabled)
	assert_true(high.ssao_enabled)
	var low := StratumEnvironment.build(HALLS, &"low")
	assert_false(low.ssao_enabled)
	assert_false(low.volumetric_fog_enabled, "Low: volumetric fog off")
	assert_true(low.fog_enabled, "replaced by distance fog")
	assert_eq(low.fog_mode, Environment.FOG_MODE_EXPONENTIAL)
	assert_approx(low.fog_density, HALLS.fog_density)
	assert_eq(low.fog_light_color, HALLS.fog_color)


func test_substrate_uses_distance_fog_to_black() -> void:
	var env := StratumEnvironment.build(SUBSTRATE, &"high")
	assert_false(env.volumetric_fog_enabled)
	assert_true(env.fog_enabled)
	assert_eq(env.fog_mode, Environment.FOG_MODE_DEPTH)
	assert_approx(env.fog_depth_begin, SUBSTRATE.distance_fog_begin)
	assert_approx(env.fog_depth_end, SUBSTRATE.distance_fog_end)
	assert_eq(env.fog_light_color, SUBSTRATE.fog_color)


func test_viewport_preset() -> void:
	var vp := SubViewport.new()
	add_child(vp)
	StratumEnvironment.apply_viewport_preset(vp, &"low")
	assert_eq(vp.screen_space_aa, Viewport.SCREEN_SPACE_AA_FXAA)
	assert_false(vp.use_taa)
	assert_approx(vp.scaling_3d_scale, 0.8)
	assert_eq(vp.positional_shadow_atlas_size, 2048)
	StratumEnvironment.apply_viewport_preset(vp, &"medium")
	assert_true(vp.use_taa)
	assert_eq(vp.positional_shadow_atlas_size, 4096)
	vp.queue_free()


func test_dust_motes_follow_02() -> void:
	var dust := DustMotes.create()
	assert_eq(dust.amount, Tuning.DUST_PARTICLES)
	assert_false(dust.local_coords, "world-space particles")
	var pm := dust.process_material as ParticleProcessMaterial
	assert_eq(pm.emission_box_extents, Vector3.ONE * Tuning.DUST_BOX_SIZE * 0.5)
	var quad := dust.draw_pass_1 as QuadMesh
	assert_eq(quad.size, Vector2.ONE * Tuning.DUST_QUAD_SIZE)
	assert_approx((quad.material as StandardMaterial3D).albedo_color.a, Tuning.DUST_ALPHA)
	var low := DustMotes.create(0.5)
	assert_eq(low.amount, Tuning.DUST_PARTICLES / 2, "Low: 50% counts")
	dust.free()
	low.free()


func test_post_stack_is_wired() -> void:
	var quad := CoherenceRenderer.post_quad()
	assert_not_null(quad)
	assert_eq((quad.mesh as QuadMesh).size, Vector2(2.0, 2.0))
	var mat := quad.material_override as ShaderMaterial
	assert_eq(mat.render_priority, Material.RENDER_PRIORITY_MIN, "first in the transparent pass")
	assert_eq(quad.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var layer := CoherenceRenderer.screen_layer()
	assert_not_null(layer)
	assert_lt(layer.layer, 0, "below the HUD")
	assert_eq(CoherenceRenderer.process_mode, Node.PROCESS_MODE_ALWAYS)


func test_reduce_settings_reach_the_post_stack() -> void:
	SettingsManager.set_value(&"reduce_visual_noise", true)
	SettingsManager.set_value(&"reduce_flashing", true)
	assert_true(CoherenceRenderer.reduce_noise)
	assert_true(CoherenceRenderer.reduce_flashing)
	CoherenceRenderer.set_coherence(5.0)
	await await_frames(1)
	assert_lt(CoherenceRenderer.post_params[&"grain"], 0.0601)
	SettingsManager.set_value(&"reduce_visual_noise", false)
	SettingsManager.set_value(&"reduce_flashing", false)
	CoherenceRenderer.set_coherence(100.0)
	await await_frames(1)


func test_run_start_takes_the_loadout_coherence() -> void:
	# 05 §7: Diver starts at 70; the renderer must not assume full on run_started.
	var saved: RunState = GameState.run
	var run := RunState.new()
	run.coherence = 70.0
	GameState.run = run
	EventBus.run_started.emit(&"descent", 1)
	assert_approx(CoherenceRenderer.coherence01, 0.7, 0.0001)
	GameState.run = saved
	CoherenceRenderer.set_coherence(Tuning.COHERENCE_MAX)
