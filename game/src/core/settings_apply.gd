class_name SettingsApply
extends RefCounted
## How each setting reaches the engine (12 §1: every option applies immediately). Called by
## SettingsManager only; static so the pieces are testable on their own. Consumers that own a
## behaviour (camera FOV, look, buses, HUD modes, the renderer's caps and texture detail)
## listen to SettingsManager.changed themselves; this file covers what has no owner node:
## the window, the root viewport, the WorldEnvironments, the light pools and particles.

## Display keys that change the window (12 §2).
const WINDOW_KEYS: Array[StringName] = [&"window_mode", &"resolution"]
## Keys whose change re-applies the graphics profile (viewport, environments, pools).
const GRAPHICS_KEYS: Array[StringName] = [
	&"render_scale", &"upscaling", &"anti_aliasing", &"shadow_quality", &"ambient_occlusion",
	&"indirect_lighting", &"volumetric_fog", &"glow", &"particles", &"light_pool_size", &"brightness",
]
const META_FOG := &"noclip_fog"

const WINDOW_MODES: Dictionary = {
	&"fullscreen": DisplayServer.WINDOW_MODE_FULLSCREEN,
	&"exclusive_fullscreen": DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
	&"windowed": DisplayServer.WINDOW_MODE_WINDOWED,
}
const VSYNC_MODES: Dictionary = {
	&"off": DisplayServer.VSYNC_DISABLED, &"on": DisplayServer.VSYNC_ENABLED, &"adaptive": DisplayServer.VSYNC_ADAPTIVE,
}


## The live graphics profile in the shape of Tuning.QUALITY_PRESETS (02 §12), plus
## `upscaling`, `glow`, `msaa`, from the individual settings (12 §3). Pure.
static func graphics_profile(values: Dictionary) -> Dictionary:
	var d := SettingsSchema.DEFAULTS
	var shadow: StringName = values.get(&"shadow_quality", d[&"shadow_quality"])
	var shadow_row: Dictionary = Tuning.SETTINGS_SHADOW_QUALITY.get(shadow, Tuning.SETTINGS_SHADOW_QUALITY[&"medium"])
	var fog: StringName = values.get(&"volumetric_fog", d[&"volumetric_fog"])
	var froxel := 0
	if fog == &"low":
		froxel = int(Tuning.QUALITY_PRESETS[&"medium"][&"fog_froxel_px"])
	elif fog == &"high":
		froxel = int(Tuning.QUALITY_PRESETS[&"high"][&"fog_froxel_px"])
	return {
		&"lights": int(values.get(&"light_pool_size", d[&"light_pool_size"])),
		&"shadowed": int(shadow_row[&"shadowed"]),
		&"shadow_atlas": int(shadow_row[&"atlas"]),
		&"volumetric_fog": &"off" if fog == &"off" else &"on",
		&"fog_froxel_px": froxel,
		&"ssao": bool(values.get(&"ambient_occlusion", d[&"ambient_occlusion"])),
		&"ssil": bool(values.get(&"indirect_lighting", d[&"indirect_lighting"])),
		&"aa": StringName(values.get(&"anti_aliasing", d[&"anti_aliasing"])),
		&"render_scale": float(values.get(&"render_scale", d[&"render_scale"])),
		&"upscaling": StringName(values.get(&"upscaling", d[&"upscaling"])),
		&"particles": Tuning.SETTINGS_PARTICLES_LOW_RATIO if values.get(&"particles", d[&"particles"]) == &"low" else 1.0,
		&"glow": bool(values.get(&"glow", d[&"glow"])),
	}


## 12 §2: true when FSR 2 is the active upscaler (render scale below 1.0 and FSR 2 chosen);
## then it replaces anti-aliasing and the AA row shows `FSR 2`.
static func fsr_active(values: Dictionary) -> bool:
	var scale := float(values.get(&"render_scale", SettingsSchema.DEFAULTS[&"render_scale"]))
	return scale < 1.0 and StringName(values.get(&"upscaling", &"fsr2")) == &"fsr2"


## 12 §2: the window mode and, for windowed and exclusive, the resolution.
static func window(values: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode: int = WINDOW_MODES.get(StringName(values.get(&"window_mode", &"fullscreen")), DisplayServer.WINDOW_MODE_FULLSCREEN)
	var screen := DisplayServer.window_get_current_screen()
	var screen_size := DisplayServer.screen_get_size(screen)
	var res := StringName(values.get(&"resolution", SettingsSchema.NATIVE))
	var size := screen_size if res == SettingsSchema.NATIVE else SettingsSchema.parse_resolution(String(res))
	if size.x < Tuning.SETTINGS_MIN_RESOLUTION.x or size.y < Tuning.SETTINGS_MIN_RESOLUTION.y:
		size = Tuning.SETTINGS_MIN_RESOLUTION
	if mode == DisplayServer.WINDOW_MODE_WINDOWED:
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
		DisplayServer.window_set_size(size)
		var origin := DisplayServer.screen_get_position(screen)
		DisplayServer.window_set_position(origin + (screen_size - size) / 2)
	else:
		if mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			DisplayServer.window_set_size(size)
		DisplayServer.window_set_mode(mode)


static func vsync(mode: StringName) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(VSYNC_MODES.get(mode, DisplayServer.VSYNC_ENABLED))


## 12 §2 Max FPS: 0 is Unlimited (VSync governs).
static func max_fps(v: int) -> void:
	Engine.max_fps = maxi(0, v)


## 12 §2 UI scale: sizes are authored at 1080p and the base scale follows the window height,
## so the setting multiplies the auto-derived factor (1.0 at 1080p).
static func ui_scale(win: Window, scale: float) -> void:
	if win == null:
		return
	var h := float(win.size.y) if win.size.y > 0 else float(Tuning.SETTINGS_UI_REFERENCE_HEIGHT)
	win.content_scale_factor = content_scale(h, scale)


static func content_scale(window_height: float, scale: float) -> float:
	return maxf(0.1, window_height / float(Tuning.SETTINGS_UI_REFERENCE_HEIGHT) * scale)


## 12 §5 Raw mouse input: accumulated input off.
static func raw_mouse(on: bool) -> void:
	Input.use_accumulated_input = not on


## 12 §4 Output device; an unknown name falls back to Default.
static func output_device(device: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var list := AudioServer.get_output_device_list()
	AudioServer.output_device = device if list.has(device) else SettingsSchema.DEVICE_DEFAULT


## Applies the profile to the viewport, every WorldEnvironment, light pool and particle
## system under `root` (a level re-applies its preset when it builds; SettingsManager
## calls this again on level_entered).
static func graphics(root: Node, values: Dictionary) -> void:
	if root == null:
		return
	var profile := graphics_profile(values)
	var vp := root.get_viewport() if not (root is Viewport) else root as Viewport
	if vp != null:
		StratumEnvironment.apply_viewport_profile(vp, profile)
	var brightness := float(values.get(&"brightness", Tuning.SETTINGS_BRIGHTNESS_DEFAULT))
	_walk(root, profile, brightness)


static func _walk(n: Node, profile: Dictionary, brightness: float) -> void:
	if n is WorldEnvironment and (n as WorldEnvironment).environment != null:
		environment((n as WorldEnvironment).environment, profile, brightness)
	elif n is LightPool:
		light_pool(n as LightPool, profile)
	elif n is GPUParticles3D:
		(n as GPUParticles3D).amount_ratio = float(profile[&"particles"])
	for c in n.get_children():
		_walk(c, profile, brightness)


## 12 §3 on a built Environment: SSAO, SSIL, glow, volumetric fog (Off becomes the distance
## fog of the same density, 02 §12 Low) and 12 §2 brightness (adjustment_brightness).
static func environment(env: Environment, profile: Dictionary, brightness: float) -> void:
	env.ssao_enabled = bool(profile[&"ssao"])
	env.ssil_enabled = bool(profile[&"ssil"])
	env.glow_enabled = bool(profile[&"glow"])
	env.adjustment_enabled = true
	env.adjustment_brightness = brightness
	if env.fog_enabled and env.fog_mode == Environment.FOG_MODE_DEPTH:
		return  # 02 §7 Substrate: distance fog in every preset.
	if not env.has_meta(META_FOG):
		if env.volumetric_fog_enabled:
			env.set_meta(META_FOG, {"density": env.volumetric_fog_density, "color": env.volumetric_fog_albedo})
		elif env.fog_enabled:
			env.set_meta(META_FOG, {"density": env.fog_density, "color": env.fog_light_color})
		else:
			return
	var fog: Dictionary = env.get_meta(META_FOG)
	if profile[&"volumetric_fog"] == &"on":
		env.fog_enabled = false
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = float(fog["density"])
		env.volumetric_fog_albedo = fog["color"]
		env.volumetric_fog_emission = fog["color"]
		env.volumetric_fog_emission_energy = Tuning.RENDER_FOG_EMISSION_ENERGY
		env.volumetric_fog_ambient_inject = Tuning.RENDER_FOG_AMBIENT_INJECT
		env.volumetric_fog_length = Tuning.RENDER_FOG_LENGTH
		env.volumetric_fog_sky_affect = 0.0
	else:
		env.volumetric_fog_enabled = false
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_light_color = fog["color"]
		env.fog_light_energy = Tuning.RENDER_FOG_LOW_LIGHT_ENERGY
		env.fog_density = float(fog["density"])
		env.fog_sky_affect = 1.0


## 12 §3 Light pool size and the shadowed count of the shadow quality.
static func light_pool(pool: LightPool, profile: Dictionary) -> void:
	var n := int(profile[&"lights"])
	var s := mini(int(profile[&"shadowed"]), n)
	if pool.pool_size == n and pool.shadowed == s:
		return
	pool.pool_size = n
	pool.shadowed = s
	pool.rebuild_lights()
