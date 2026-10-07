class_name StratumEnvironment
extends RefCounted
## Builds the WorldEnvironment's Environment from a StratumData and a quality preset
## (02 §3, §6, §7, §12), and applies the preset's viewport settings. Pure data in, no
## scene access except the viewport passed in.

const PRESETS := Tuning.QUALITY_PRESETS


## The preset dictionary for `preset`, falling back to Medium for an unknown name.
static func preset_of(preset: StringName) -> Dictionary:
	if not PRESETS.has(preset):
		push_error("StratumEnvironment: unknown preset %s, using medium" % preset)
		return PRESETS[Tuning.QUALITY_PRESET_DEFAULT]
	return PRESETS[preset]


static func build(data: StratumData, preset: StringName = Tuning.QUALITY_PRESET_DEFAULT) -> Environment:
	var p := preset_of(preset)
	var env := Environment.new()
	# 02 §6: no sky texture; cameras never see a sky; its colour is the fog colour.
	env.background_mode = Environment.BG_COLOR
	env.background_color = data.fog_color
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = data.ambient_color
	env.ambient_light_energy = data.ambient_energy
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	# 02 §3: AgX, exposure 1.0 with the stratum's offset.
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = data.exposure
	# 02 §3: no GI in v1.0.
	env.sdfgi_enabled = false
	_apply_glow(env)
	_apply_occlusion(env, p)
	_apply_fog(env, data, p)
	return env


## 02 §12: AA, render scale, shadow atlas and froxel size live on the viewport/server.
static func apply_viewport_preset(vp: Viewport, preset: StringName = Tuning.QUALITY_PRESET_DEFAULT) -> void:
	var p := preset_of(preset)
	var aa: StringName = p[&"aa"]
	vp.use_taa = aa == &"taa"
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == &"fxaa" else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.scaling_3d_scale = float(p[&"render_scale"])
	vp.positional_shadow_atlas_size = int(p[&"shadow_atlas"])
	var froxel: int = p[&"fog_froxel_px"]
	if froxel > 0:
		RenderingServer.environment_set_volumetric_fog_volume_size(froxel, Tuning.RENDER_FOG_FROXEL_DEPTH)


static func _apply_glow(env: Environment) -> void:
	# 02 §3: fixtures bloom softly, nothing else.
	env.glow_enabled = true
	env.glow_hdr_threshold = Tuning.RENDER_GLOW_THRESHOLD
	env.glow_intensity = Tuning.RENDER_GLOW_INTENSITY
	env.glow_bloom = Tuning.RENDER_GLOW_BLOOM
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT


static func _apply_occlusion(env: Environment, p: Dictionary) -> void:
	env.ssao_enabled = bool(p[&"ssao"])
	env.ssao_radius = Tuning.RENDER_AO_RADIUS
	env.ssao_intensity = Tuning.RENDER_AO_INTENSITY
	env.ssil_enabled = bool(p[&"ssil"])
	env.ssr_enabled = false


static func _apply_fog(env: Environment, data: StratumData, p: Dictionary) -> void:
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	if data.distance_fog_end > 0.0:
		# 02 §7 Substrate: distance fog to the fog colour (black), every preset.
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_light_color = data.fog_color
		env.fog_light_energy = 1.0
		env.fog_density = 1.0
		env.fog_depth_begin = data.distance_fog_begin
		env.fog_depth_end = data.distance_fog_end
		env.fog_depth_curve = 1.0
		env.fog_sky_affect = 1.0
		return
	if data.fog_density <= 0.0:
		return
	if p[&"volumetric_fog"] == &"on":
		# 02 §6: the air is visible. Albedo is the stratum's fog colour; a faint emission in
		# the same colour keeps fog in the darkest shadow (T3) where no light scatters.
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = data.fog_density
		env.volumetric_fog_albedo = data.fog_color
		env.volumetric_fog_emission = data.fog_color
		env.volumetric_fog_emission_energy = Tuning.RENDER_FOG_EMISSION_ENERGY
		env.volumetric_fog_ambient_inject = Tuning.RENDER_FOG_AMBIENT_INJECT
		env.volumetric_fog_length = Tuning.RENDER_FOG_LENGTH
		env.volumetric_fog_sky_affect = 0.0
	else:
		# 02 §12 Low: volumetric fog off, replaced by distance fog of the same density.
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_light_color = data.fog_color
		env.fog_light_energy = Tuning.RENDER_FOG_LOW_LIGHT_ENERGY
		env.fog_density = data.fog_density
		env.fog_sky_affect = 1.0
