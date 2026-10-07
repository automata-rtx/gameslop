class_name Fixture
extends Node3D
## A light fixture (02 §6, GLOSSARY): an emissive mesh on the stratum's exact grid. It owns
## no light node; the LightPool lends one of its pooled lights to the nearest fixtures.
## Disabled-light fixtures still glow, so the room reads as lit. State here is what other
## systems read: power (Powered lock, Offices dark groups), flicker (Flicker's habitat
## signature, 08), and an intensity the pool multiplies into the lent light.
## Scene contract: %Tube (MeshInstance3D, the emissive part, material_override = the lit
## material).

signal power_changed(on: bool)

## Fixture group id (Flicker's habitat unit, 07 §5).
var group_id: int = -1
var powered: bool = true
## 0..1.3: multiplies the pooled light's energy (breaker overshoot 1.3, flicker 0 or 1).
var intensity: float = 1.0
## The hum loop this fixture carries while it holds a pooled light (03).
var hum_id: StringName = &""

@onready var tube: MeshInstance3D = %Tube

var _lit_material: Material
var _flickering: bool = false
var _flick_on: bool = true
var _flick_left: float = 0.0
var _rng: RandomNumberGenerator
var _wave: Tween

## Unlit twins of lit materials, shared by every fixture of a stratum.
static var _dark_materials: Dictionary = {}


func _ready() -> void:
	add_to_group(&"fixtures")
	_lit_material = tube.material_override
	set_process(false)
	_apply_visual()


## True when the fixture currently emits (powered, and not in a flicker-off instant).
func is_emitting() -> bool:
	return powered and (not _flickering or _flick_on)


func set_powered(on: bool) -> void:
	if _wave != null:
		_wave.kill()
		_wave = null
	if powered == on:
		return
	powered = on
	intensity = 1.0 if on else 0.0
	_apply_visual()
	power_changed.emit(on)


## 02 §6 breaker event: light after `delay` seconds with an energy overshoot to 1.3 that
## settles over 400 ms.
func power_on_wave(delay: float) -> void:
	if powered:
		return
	if _wave != null:
		_wave.kill()
	_wave = create_tween()
	_wave.tween_interval(maxf(delay, 0.0))
	_wave.tween_callback(func() -> void:
		powered = true
		intensity = Tuning.LIGHT_BREAKER_OVERSHOOT
		_apply_visual()
		power_changed.emit(true)
		AudioManager.play_3d(&"power_wave_ignite", global_position))
	_wave.tween_property(self, ^"intensity", 1.0, Tuning.LIGHT_BREAKER_SETTLE_MS / 1000.0)


## 02 §6: fixtures flicker only while Flicker is present in their group (08).
func set_flicker(on: bool) -> void:
	if _flickering == on:
		return
	_flickering = on
	if on and _rng == null:
		# Cosmetic, but seeded from the fixture's place so it is reproducible.
		_rng = RandomNumberGenerator.new()
		_rng.seed = hash(Vector3i(global_position.round()))
	_flick_on = true
	_flick_left = 0.0
	set_process(on)
	if not on:
		intensity = 1.0 if powered else 0.0
	_apply_visual()


func is_flickering() -> bool:
	return _flickering


func _process(delta: float) -> void:
	_flick_left -= delta
	if _flick_left > 0.0:
		return
	# 02 §8: random on/off at 8 to 20 Hz.
	_flick_on = not _flick_on
	_flick_left = 1.0 / _rng.randf_range(Tuning.LIGHT_FLICKER_VISUAL_MIN_HZ, Tuning.LIGHT_FLICKER_VISUAL_MAX_HZ)
	intensity = 1.0 if (_flick_on and powered) else 0.0
	_apply_visual()


func _apply_visual() -> void:
	if tube == null or _lit_material == null:
		return
	tube.material_override = _lit_material if is_emitting() else dark_twin(_lit_material)


## The same material with its emission off (a dark tube still reads as a fixture).
static func dark_twin(lit: Material) -> Material:
	if _dark_materials.has(lit):
		return _dark_materials[lit]
	var dark := lit.duplicate() as Material
	if dark is ShaderMaterial:
		(dark as ShaderMaterial).set_shader_parameter(&"emission_strength", 0.0)
	elif dark is StandardMaterial3D:
		(dark as StandardMaterial3D).emission_enabled = false
	_dark_materials[lit] = dark
	return dark
