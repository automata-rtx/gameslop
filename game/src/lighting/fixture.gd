class_name Fixture
extends Node3D
## A light fixture (02 §6, GLOSSARY): an emissive mesh on the stratum's exact grid. It owns
## no light node; the LightPool lends one of its pooled lights to the nearest fixtures.
## Disabled-light fixtures still glow, so the room reads as lit. State here is what other
## systems read: power (Powered lock, Offices dark groups), flicker (Flicker's habitat
## signature, 08), and an intensity the pool multiplies into the lent light.
## Scene contract: %Tube (MeshInstance3D, the emissive part, material_override = the lit
## material); optional %Glow (the ceiling halo, fixture_glow.gdshader, instance `energy`).
## One fixture in six (the hashed tired ballast that buzzes, 03) is `buzzing`: a slightly
## greener tube at 85% energy, its lent light too. It is steady: only Flicker flickers (02 §6).

signal power_changed(on: bool)

## Fixture group id (Flicker's habitat unit, 07 §5).
var group_id: int = -1
var powered: bool = true
## 0..1.3: multiplies the pooled light's energy (breaker overshoot 1.3, flicker 0 or 1).
var intensity: float = 1.0
## The hum loop this fixture carries while it holds a pooled light (03).
var hum_id: StringName = &""
## The tired-ballast fixture (LightPool.register_fixture): greener, 85% energy, steady.
var buzzing: bool = false

@onready var tube: MeshInstance3D = %Tube
@onready var glow: GeometryInstance3D = get_node_or_null(^"%Glow") as GeometryInstance3D

var _lit_material: Material
var _flickering: bool = false
var _flick_on: bool = true
var _flick_left: float = 0.0
var _rng: RandomNumberGenerator
var _wave: Tween

## Unlit twins of lit materials, shared by every fixture of a stratum.
static var _dark_materials: Dictionary = {}
## Buzzing twins (greener, 85% emission) of lit materials.
static var _buzz_materials: Dictionary = {}


func _ready() -> void:
	add_to_group(&"fixtures")
	_lit_material = tube.material_override
	set_process(false)
	_apply_visual()


## Marks the fixture as the buzzing kind (03; R4 V3): greener tube and light at 85% energy.
func set_buzzing(on: bool) -> void:
	buzzing = on
	_apply_visual()


## Multiplier on the lent light's energy and the glow (1, or 0.85 for a buzzing fixture).
func energy_scale() -> float:
	return Tuning.LIGHT_FIXTURE_BUZZ_ENERGY if buzzing else 1.0


## The lent light's colour for this fixture, given the stratum's.
func light_tint(base: Color) -> Color:
	return base * Tuning.LIGHT_FIXTURE_BUZZ_TINT if buzzing else base


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
	var lit := buzz_twin(_lit_material) if buzzing else _lit_material
	tube.material_override = lit if is_emitting() else dark_twin(_lit_material)
	if glow != null:
		var e := Tuning.LIGHT_FIXTURE_GLOW_ENERGY * energy_scale() * clampf(intensity, 0.0, 1.3) if is_emitting() else 0.0
		glow.set_instance_shader_parameter(&"energy", e)
		glow.visible = e > 0.0


## The same material greener and at 85% emission (the buzzing fixtures).
static func buzz_twin(lit: Material) -> Material:
	if _buzz_materials.has(lit):
		return _buzz_materials[lit]
	var m := lit.duplicate() as Material
	if m is ShaderMaterial:
		var sm := m as ShaderMaterial
		sm.set_shader_parameter(&"emission", (sm.get_shader_parameter(&"emission") as Color) * Tuning.LIGHT_FIXTURE_BUZZ_TINT)
		sm.set_shader_parameter(&"emission_strength", float(sm.get_shader_parameter(&"emission_strength")) * Tuning.LIGHT_FIXTURE_BUZZ_ENERGY)
	elif m is StandardMaterial3D:
		var st := m as StandardMaterial3D
		st.emission = st.emission * Tuning.LIGHT_FIXTURE_BUZZ_TINT
		st.emission_energy_multiplier *= Tuning.LIGHT_FIXTURE_BUZZ_ENERGY
	_buzz_materials[lit] = m
	return m


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
