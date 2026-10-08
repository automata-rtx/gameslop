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
	apply_viewport_profile(vp, preset_of(preset))


## The same from a profile dictionary (a preset, or SettingsApply.graphics_profile with the
## player's individual options). 12 §2: below render scale 1.0 the `upscaling` choice
## applies (the settings default is FSR 2); FSR 2 replaces anti-aliasing and is incompatible with MSAA.
## Above 1.0 is bilinear supersampling.
static func apply_viewport_profile(vp: Viewport, p: Dictionary) -> void:
	var aa: StringName = p.get(&"aa", &"taa")
	var scale := float(p.get(&"render_scale", 1.0))
	# A bare 02 §12 preset has no upscaling entry: Low is FXAA at 0.8 bilinear as 02 lists it.
	var fsr := scale < 1.0 and StringName(p.get(&"upscaling", &"bilinear")) == &"fsr2"
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if fsr else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = scale
	vp.use_taa = aa == &"taa" and not fsr
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == &"fxaa" and not fsr else Viewport.SCREEN_SPACE_AA_DISABLED
	var msaa := Viewport.MSAA_DISABLED
	if not fsr and aa == &"msaa2x":
		msaa = Viewport.MSAA_2X
	elif not fsr and aa == &"msaa4x":
		msaa = Viewport.MSAA_4X
	vp.msaa_3d = msaa
	vp.positional_shadow_atlas_size = int(p.get(&"shadow_atlas", 4096))
	var froxel: int = p.get(&"fog_froxel_px", 0)
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
	env.ssao_light_affect = Tuning.RENDER_AO_LIGHT_AFFECT
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
		env.volumetric_fog_emission_energy = float(Tuning.RENDER_FOG_EMISSION_STRATUM.get(data.id, Tuning.RENDER_FOG_EMISSION_ENERGY))
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
