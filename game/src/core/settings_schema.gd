class_name SettingsSchema
extends RefCounted
## Every option of 12 §2 to §7: its key, tab, kind, default and range, in menu order, and the
## validation SettingsManager applies to everything it loads or is given (12 §1, §8). Pure
## data: no autoloads, no nodes. Labels and descriptions live in Strings (SETTING_LABELS,
## SETTING_DESCRIPTIONS) under the same keys.

const TAB_DISPLAY := &"display"
const TAB_GRAPHICS := &"graphics"
const TAB_AUDIO := &"audio"
const TAB_CONTROLS := &"controls"
const TAB_ACCESSIBILITY := &"accessibility"
const TAB_GAMEPLAY := &"gameplay"
## 04 §7: the settings tabs, in the order of the left column (Strings.SETTINGS_TABS).
const TABS: Array[StringName] = [TAB_DISPLAY, TAB_GRAPHICS, TAB_AUDIO, TAB_CONTROLS, TAB_ACCESSIBILITY, TAB_GAMEPLAY]

const KIND_ENUM := &"enum"
const KIND_BOOL := &"bool"
const KIND_INT := &"int"
const KIND_FLOAT := &"float"
## Enums whose values come from the machine: the screen's resolutions, the audio devices.
const KIND_RESOLUTION := &"resolution"
const KIND_DEVICE := &"device"

const NATIVE := &"native"
const DEVICE_DEFAULT := "Default"
const PRESET_CUSTOM := &"custom"
const PRESETS: Array[StringName] = [&"low", &"medium", &"high", PRESET_CUSTOM]
## 12 §1: these two apply on confirm with the 10 s revert countdown.
const REVERT_KEYS: Array[StringName] = [&"window_mode", &"resolution"]
## 12 §3: "Preset sets everything below"; 02 §12 also sets the render scale.
const PRESET_KEYS: Array[StringName] = [
	&"anti_aliasing", &"shadow_quality", &"ambient_occlusion", &"indirect_lighting", &"volumetric_fog",
	&"glow", &"particles", &"light_pool_size", &"texture_detail", &"render_scale",
]
## 12 §2 Max FPS: 30 to 360, or Unlimited (stored as 0).
const FPS_UNLIMITED := Tuning.SETTINGS_FPS_UNLIMITED

## The options, tab by tab, in menu order. Fields: key, tab, kind, default, and per kind
## values (enum), min/max/step (int, float). 12 §2 to §7.
const OPTIONS: Array[Dictionary] = [
	# 12 §2 DISPLAY
	{&"key": &"window_mode", &"tab": TAB_DISPLAY, &"kind": KIND_ENUM, &"default": &"fullscreen", &"values": Tuning.SETTINGS_WINDOW_MODES},
	{&"key": &"resolution", &"tab": TAB_DISPLAY, &"kind": KIND_RESOLUTION, &"default": NATIVE},
	{&"key": &"vsync", &"tab": TAB_DISPLAY, &"kind": KIND_ENUM, &"default": &"on", &"values": Tuning.SETTINGS_VSYNC_MODES},
	{&"key": &"max_fps", &"tab": TAB_DISPLAY, &"kind": KIND_INT, &"default": Tuning.SETTINGS_FPS_UNLIMITED,
		&"min": Tuning.SETTINGS_FPS_MIN, &"max": Tuning.SETTINGS_FPS_MAX, &"step": 1},
	{&"key": &"render_scale", &"tab": TAB_DISPLAY, &"kind": KIND_FLOAT, &"default": Tuning.SETTINGS_RENDER_SCALE_DEFAULT,
		&"min": Tuning.SETTINGS_RENDER_SCALE_MIN, &"max": Tuning.SETTINGS_RENDER_SCALE_MAX, &"step": Tuning.SETTINGS_RENDER_SCALE_STEP},
	{&"key": &"upscaling", &"tab": TAB_DISPLAY, &"kind": KIND_ENUM, &"default": &"fsr2", &"values": Tuning.SETTINGS_UPSCALING_MODES},
	{&"key": &"ui_scale", &"tab": TAB_DISPLAY, &"kind": KIND_FLOAT, &"default": Tuning.SETTINGS_UI_SCALE_DEFAULT,
		&"min": Tuning.SETTINGS_UI_SCALE_MIN, &"max": Tuning.SETTINGS_UI_SCALE_MAX, &"step": Tuning.SETTINGS_UI_SCALE_STEP},
	{&"key": &"brightness", &"tab": TAB_DISPLAY, &"kind": KIND_FLOAT, &"default": Tuning.SETTINGS_BRIGHTNESS_DEFAULT,
		&"min": Tuning.SETTINGS_BRIGHTNESS_MIN, &"max": Tuning.SETTINGS_BRIGHTNESS_MAX, &"step": Tuning.SETTINGS_BRIGHTNESS_STEP},
	{&"key": &"fov", &"tab": TAB_DISPLAY, &"kind": KIND_INT, &"default": Tuning.SETTINGS_FOV_DEFAULT,
		&"min": Tuning.SETTINGS_FOV_MIN, &"max": Tuning.SETTINGS_FOV_MAX, &"step": Tuning.SETTINGS_FOV_STEP},
	{&"key": &"head_bob", &"tab": TAB_DISPLAY, &"kind": KIND_FLOAT, &"default": Tuning.SETTINGS_HEAD_BOB_DEFAULT,
		&"min": 0.0, &"max": 1.0, &"step": Tuning.SETTINGS_UNIT_STEP},
	{&"key": &"screen_shake", &"tab": TAB_DISPLAY, &"kind": KIND_FLOAT, &"default": Tuning.SETTINGS_SHAKE_DEFAULT,
		&"min": 0.0, &"max": 1.0, &"step": Tuning.SETTINGS_UNIT_STEP},
	# 12 §3 GRAPHICS
	{&"key": &"preset", &"tab": TAB_GRAPHICS, &"kind": KIND_ENUM, &"default": Tuning.SETTINGS_PRESET_DEFAULT, &"values": PRESETS},
	{&"key": &"anti_aliasing", &"tab": TAB_GRAPHICS, &"kind": KIND_ENUM, &"default": &"taa", &"values": Tuning.SETTINGS_AA_MODES},
	{&"key": &"shadow_quality", &"tab": TAB_GRAPHICS, &"kind": KIND_ENUM, &"default": &"medium", &"values": [&"off", &"low", &"medium", &"high"]},
	{&"key": &"ambient_occlusion", &"tab": TAB_GRAPHICS, &"kind": KIND_BOOL, &"default": true},
	{&"key": &"indirect_lighting", &"tab": TAB_GRAPHICS, &"kind": KIND_BOOL, &"default": false},
	{&"key": &"volumetric_fog", &"tab": TAB_GRAPHICS, &"kind": KIND_ENUM, &"default": &"low", &"values": Tuning.SETTINGS_VOLUMETRIC_FOG_MODES},
	{&"key": &"glow", &"tab": TAB_GRAPHICS, &"kind": KIND_BOOL, &"default": true},
	{&"key": &"particles", &"tab": TAB_GRAPHICS, &"kind": KIND_ENUM, &"default": &"full", &"values": [&"low", &"full"]},
	{&"key": &"light_pool_size", &"tab": TAB_GRAPHICS, &"kind": KIND_INT, &"default": Tuning.SETTINGS_LIGHT_POOL_DEFAULT,
		&"min": Tuning.LIGHT_POOL_SIZE_MIN, &"max": Tuning.LIGHT_POOL_SIZE_MAX, &"step": 1},
	{&"key": &"texture_detail", &"tab": TAB_GRAPHICS, &"kind": KIND_ENUM, &"default": &"high", &"values": [&"low", &"high"]},
	# 12 §4 AUDIO
	{&"key": &"audio_master", &"tab": TAB_AUDIO, &"kind": KIND_INT, &"default": Tuning.SETTINGS_AUDIO_MASTER_DEFAULT,
		&"min": Tuning.SETTINGS_AUDIO_MIN, &"max": Tuning.SETTINGS_AUDIO_MAX, &"step": 1},
	{&"key": &"audio_effects", &"tab": TAB_AUDIO, &"kind": KIND_INT, &"default": Tuning.SETTINGS_AUDIO_EFFECTS_DEFAULT,
		&"min": Tuning.SETTINGS_AUDIO_MIN, &"max": Tuning.SETTINGS_AUDIO_MAX, &"step": 1},
	{&"key": &"audio_ambience", &"tab": TAB_AUDIO, &"kind": KIND_INT, &"default": Tuning.SETTINGS_AUDIO_AMBIENCE_DEFAULT,
		&"min": Tuning.SETTINGS_AUDIO_MIN, &"max": Tuning.SETTINGS_AUDIO_MAX, &"step": 1},
	{&"key": &"audio_music", &"tab": TAB_AUDIO, &"kind": KIND_INT, &"default": Tuning.SETTINGS_AUDIO_MUSIC_DEFAULT,
		&"min": Tuning.SETTINGS_AUDIO_MIN, &"max": Tuning.SETTINGS_AUDIO_MAX, &"step": 1},
	{&"key": &"audio_ui", &"tab": TAB_AUDIO, &"kind": KIND_INT, &"default": Tuning.SETTINGS_AUDIO_UI_DEFAULT,
		&"min": Tuning.SETTINGS_AUDIO_MIN, &"max": Tuning.SETTINGS_AUDIO_MAX, &"step": 1},
	{&"key": &"audio_output_device", &"tab": TAB_AUDIO, &"kind": KIND_DEVICE, &"default": DEVICE_DEFAULT},
	{&"key": &"mute_unfocused", &"tab": TAB_AUDIO, &"kind": KIND_BOOL, &"default": Tuning.SETTINGS_MUTE_UNFOCUSED_DEFAULT},
	# 12 §5 CONTROLS (key bindings are SettingsManager.bindings(), not values)
	{&"key": &"mouse_sensitivity", &"tab": TAB_CONTROLS, &"kind": KIND_FLOAT, &"default": Tuning.PLAYER_MOUSE_SENS_DEFAULT,
		&"min": Tuning.PLAYER_MOUSE_SENS_MIN, &"max": Tuning.PLAYER_MOUSE_SENS_MAX, &"step": Tuning.SETTINGS_SENS_STEP},
	{&"key": &"invert_y", &"tab": TAB_CONTROLS, &"kind": KIND_BOOL, &"default": false},
	{&"key": &"sprint_mode", &"tab": TAB_CONTROLS, &"kind": KIND_ENUM, &"default": &"hold", &"values": [&"hold", &"toggle"]},
	{&"key": &"crouch_mode", &"tab": TAB_CONTROLS, &"kind": KIND_ENUM, &"default": &"hold", &"values": [&"hold", &"toggle"]},
	{&"key": &"raw_mouse", &"tab": TAB_CONTROLS, &"kind": KIND_BOOL, &"default": true},
	# 12 §6 ACCESSIBILITY
	{&"key": &"captions", &"tab": TAB_ACCESSIBILITY, &"kind": KIND_BOOL, &"default": false},
	{&"key": &"reduce_visual_noise", &"tab": TAB_ACCESSIBILITY, &"kind": KIND_BOOL, &"default": false},
	{&"key": &"reduce_flashing", &"tab": TAB_ACCESSIBILITY, &"kind": KIND_BOOL, &"default": false},
	{&"key": &"flicker_intensity", &"tab": TAB_ACCESSIBILITY, &"kind": KIND_FLOAT, &"default": Tuning.SETTINGS_FLICKER_INTENSITY_DEFAULT,
		&"min": Tuning.SETTINGS_FLICKER_INTENSITY_MIN, &"max": Tuning.SETTINGS_FLICKER_INTENSITY_MAX, &"step": Tuning.SETTINGS_UNIT_STEP},
	{&"key": &"crosshair", &"tab": TAB_ACCESSIBILITY, &"kind": KIND_ENUM, &"default": &"dot_ring", &"values": Tuning.SETTINGS_CROSSHAIR_MODES},
	{&"key": &"hud_mode", &"tab": TAB_ACCESSIBILITY, &"kind": KIND_ENUM, &"default": &"full", &"values": Tuning.SETTINGS_HUD_MODES},
	{&"key": &"hints", &"tab": TAB_ACCESSIBILITY, &"kind": KIND_BOOL, &"default": true},
	{&"key": &"text_size", &"tab": TAB_ACCESSIBILITY, &"kind": KIND_FLOAT, &"default": Tuning.SETTINGS_TEXT_SIZE_DEFAULT,
		&"min": Tuning.SETTINGS_TEXT_SIZE_MIN, &"max": Tuning.SETTINGS_TEXT_SIZE_MAX, &"step": Tuning.SETTINGS_UNIT_STEP},
	{&"key": &"hold_to_press", &"tab": TAB_ACCESSIBILITY, &"kind": KIND_BOOL, &"default": false},
	{&"key": &"colorblind_accent", &"tab": TAB_ACCESSIBILITY, &"kind": KIND_BOOL, &"default": false},
	# 12 §7 GAMEPLAY
	{&"key": &"show_depth", &"tab": TAB_GAMEPLAY, &"kind": KIND_BOOL, &"default": true},
	{&"key": &"show_exit_status", &"tab": TAB_GAMEPLAY, &"kind": KIND_BOOL, &"default": true},
	{&"key": &"auto_sprint", &"tab": TAB_GAMEPLAY, &"kind": KIND_BOOL, &"default": false},
	{&"key": &"debug_overlay", &"tab": TAB_GAMEPLAY, &"kind": KIND_BOOL, &"default": false},
]

## key -> default, for every option above (SettingsManager.DEFAULTS).
const DEFAULTS: Dictionary = {
	&"window_mode": &"fullscreen", &"resolution": NATIVE, &"vsync": &"on", &"max_fps": Tuning.SETTINGS_FPS_UNLIMITED,
	&"render_scale": Tuning.SETTINGS_RENDER_SCALE_DEFAULT, &"upscaling": &"fsr2", &"ui_scale": Tuning.SETTINGS_UI_SCALE_DEFAULT,
	&"brightness": Tuning.SETTINGS_BRIGHTNESS_DEFAULT, &"fov": Tuning.SETTINGS_FOV_DEFAULT,
	&"head_bob": Tuning.SETTINGS_HEAD_BOB_DEFAULT, &"screen_shake": Tuning.SETTINGS_SHAKE_DEFAULT,
	&"preset": Tuning.SETTINGS_PRESET_DEFAULT, &"anti_aliasing": &"taa", &"shadow_quality": &"medium",
	&"ambient_occlusion": true, &"indirect_lighting": false, &"volumetric_fog": &"low", &"glow": true,
	&"particles": &"full", &"light_pool_size": Tuning.SETTINGS_LIGHT_POOL_DEFAULT, &"texture_detail": &"high",
	&"audio_master": Tuning.SETTINGS_AUDIO_MASTER_DEFAULT, &"audio_effects": Tuning.SETTINGS_AUDIO_EFFECTS_DEFAULT,
	&"audio_ambience": Tuning.SETTINGS_AUDIO_AMBIENCE_DEFAULT, &"audio_music": Tuning.SETTINGS_AUDIO_MUSIC_DEFAULT,
	&"audio_ui": Tuning.SETTINGS_AUDIO_UI_DEFAULT, &"audio_output_device": DEVICE_DEFAULT,
	&"mute_unfocused": Tuning.SETTINGS_MUTE_UNFOCUSED_DEFAULT,
	&"mouse_sensitivity": Tuning.PLAYER_MOUSE_SENS_DEFAULT, &"invert_y": false, &"sprint_mode": &"hold",
	&"crouch_mode": &"hold", &"raw_mouse": true,
	&"captions": false, &"reduce_visual_noise": false, &"reduce_flashing": false,
	&"flicker_intensity": Tuning.SETTINGS_FLICKER_INTENSITY_DEFAULT, &"crosshair": &"dot_ring", &"hud_mode": &"full",
	&"hints": true, &"text_size": Tuning.SETTINGS_TEXT_SIZE_DEFAULT, &"hold_to_press": false, &"colorblind_accent": false,
	&"show_depth": true, &"show_exit_status": true, &"auto_sprint": false, &"debug_overlay": false,
}

static var _by_key: Dictionary = {}


static func option(key: StringName) -> Dictionary:
	if _by_key.is_empty():
		for o in OPTIONS:
			_by_key[o[&"key"]] = o
	return _by_key.get(key, {})


static func has_key(key: StringName) -> bool:
	return not option(key).is_empty()


static func keys_for(tab: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for o in OPTIONS:
		if o[&"tab"] == tab:
			out.append(o[&"key"])
	return out


static func kind_of(key: StringName) -> StringName:
	return option(key).get(&"kind", &"")


## A valid value for `key` from `v`: numbers are clamped to the range and snapped to the step,
## enums must be one of the values, wrong types fall back to the default (12 §8 "validates
## every value against its range"). Unknown keys pass through untouched.
static func validate(key: StringName, v: Variant) -> Variant:
	var o := option(key)
	if o.is_empty():
		return v
	var def: Variant = o[&"default"]
	match o[&"kind"]:
		KIND_BOOL:
			if v is bool:
				return v
			if v is int or v is float:
				return v != 0
			return def
		KIND_INT:
			if not (v is int or v is float):
				return def
			if key == &"max_fps" and int(v) == FPS_UNLIMITED:
				return FPS_UNLIMITED
			return clampi(roundi(float(v)), int(o[&"min"]), int(o[&"max"]))
		KIND_FLOAT:
			if not (v is int or v is float):
				return def
			var step := float(o[&"step"])
			var lo := float(o[&"min"])
			var x := clampf(float(v), lo, float(o[&"max"]))
			return snappedf(lo + snappedf(x - lo, step), 0.0001)
		KIND_ENUM:
			if not (v is String or v is StringName):
				return def
			var s := StringName(v)
			return s if (o[&"values"] as Array).has(s) else def
		KIND_RESOLUTION:
			if not (v is String or v is StringName):
				return def
			var s := StringName(v)
			if s == NATIVE:
				return NATIVE
			var r := parse_resolution(String(s))
			if r.x < Tuning.SETTINGS_MIN_RESOLUTION.x or r.y < Tuning.SETTINGS_MIN_RESOLUTION.y:
				return def
			return StringName(resolution_text(r))
		KIND_DEVICE:
			return String(v) if (v is String or v is StringName) and not String(v).is_empty() else def
	return def


## "1920x1080" -> Vector2i(1920, 1080); Vector2i.ZERO when malformed.
static func parse_resolution(s: String) -> Vector2i:
	var parts := s.split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))


static func resolution_text(r: Vector2i) -> String:
	return "%dx%d" % [r.x, r.y]


## 12 §2: the resolutions offered for `screen` (all of Tuning.SETTINGS_RESOLUTIONS that fit,
## plus the screen's own size), as "WxH" ids after "native".
static func resolutions_for(screen: Vector2i) -> Array[StringName]:
	var out: Array[StringName] = [NATIVE]
	for r in Tuning.SETTINGS_RESOLUTIONS:
		if screen == Vector2i.ZERO or (r.x <= screen.x and r.y <= screen.y):
			out.append(StringName(resolution_text(r)))
	if screen.x >= Tuning.SETTINGS_MIN_RESOLUTION.x and screen.y >= Tuning.SETTINGS_MIN_RESOLUTION.y:
		var own := StringName(resolution_text(screen))
		if not out.has(own):
			out.append(own)
	return out


## 12 §3, 02 §12: the values a preset sets (Low, Medium, High), from Tuning.QUALITY_PRESETS.
static func preset_values(preset: StringName) -> Dictionary:
	if not Tuning.QUALITY_PRESETS.has(preset):
		return {}
	var p: Dictionary = Tuning.QUALITY_PRESETS[preset]
	var shadow := &"off"
	for q: StringName in Tuning.SETTINGS_SHADOW_QUALITY:
		var row: Dictionary = Tuning.SETTINGS_SHADOW_QUALITY[q]
		if int(row[&"atlas"]) == int(p[&"shadow_atlas"]) and int(row[&"shadowed"]) == int(p[&"shadowed"]):
			shadow = q
	var fog := &"off"
	if p[&"volumetric_fog"] == &"on":
		fog = &"high" if int(p[&"fog_froxel_px"]) >= Tuning.QUALITY_PRESETS[&"high"][&"fog_froxel_px"] else &"low"
	return {
		&"anti_aliasing": p[&"aa"], &"shadow_quality": shadow, &"ambient_occlusion": bool(p[&"ssao"]),
		&"indirect_lighting": bool(p[&"ssil"]), &"volumetric_fog": fog, &"glow": true,
		&"particles": &"full" if float(p[&"particles"]) >= 1.0 else &"low", &"light_pool_size": int(p[&"lights"]),
		&"texture_detail": Tuning.SETTINGS_PRESET_TEXTURE_DETAIL[preset], &"render_scale": float(p[&"render_scale"]),
	}
