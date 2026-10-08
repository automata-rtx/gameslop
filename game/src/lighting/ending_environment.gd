class_name EndingEnvironment
extends RefCounted
## The ending corridor's Environment (01 §8 step 2, 02 §3): the Halls pipeline (AgX, soft
## glow, AO by preset) with warm daylight air instead of the mustard haze, a warm ambient so
## the shadows are not black, and the volumetric fog thin enough that the sun draws its shaft
## through the window. Built through StratumEnvironment from a StratumData made here, so the
## graphics settings apply to it exactly as to a level.

const ID := &"ending"
const FOG_COLOR := Color("#E8DCC6")
const FOG_DENSITY := 0.006
const AMBIENT_COLOR := Color("#FFE4C0")
const AMBIENT_ENERGY := 0.32


static func data() -> StratumData:
	var d := StratumData.new()
	d.id = ID
	d.fog_color = FOG_COLOR
	d.fog_density = FOG_DENSITY
	d.ambient_color = AMBIENT_COLOR
	d.ambient_energy = AMBIENT_ENERGY
	d.exposure = 1.0
	return d


static func build() -> Environment:
	return StratumEnvironment.build(data(), _preset())


## The player's graphics options on this scene's viewport and environment (12 §3), as
## SettingsManager applies them to a level on level_entered.
static func apply_settings(root: Node) -> void:
	var values := {}
	for key: StringName in SettingsSchema.DEFAULTS:
		var v: Variant = SettingsManager.get_value(key)
		if v != null:
			values[key] = v
	SettingsApply.graphics(root, values)


static func _preset() -> StringName:
	var p: Variant = SettingsManager.get_value(&"preset")
	var preset := StringName(p) if p is String or p is StringName else Tuning.QUALITY_PRESET_DEFAULT
	return preset if StratumEnvironment.PRESETS.has(preset) else Tuning.QUALITY_PRESET_DEFAULT
