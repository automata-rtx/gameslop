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
## M2.2: this fixture's own light where it differs from the stratum's (Server: the rack
## LEDs' blue aggregate and the exit clearing's white light beside the red emergency
## boxes). Keys, all optional: color, energy, range, drop, shadow (false: never shadowed),
## buzz (false: never the buzzing kind), hum (false: carries no hum loop, M2.3). Empty: the
## pool's stratum light. Set before the
## pool registers the fixture (LevelPlacer).
var light_profile: Dictionary = {}

@onready var tube: MeshInstance3D = %Tube
@onready var glow: GeometryInstance3D = get_node_or_null(^"%Glow") as GeometryInstance3D

var _lit_material: Material
var _flickering: bool = false
var _flick_on: bool = true
## The stutter gate (stutter_step).
var _stutter: Array = new_stutter_state()
## 08 §5: Flicker's stutter rate (8 Hz resident, rising to 20 Hz as its charge builds).
var _flick_hz: float = Tuning.FLICKER_STUTTER_MIN_HZ
## Flicker's lunge (08 §5, 02 §8): the 2-frame white flash, then dark for 1.5 s. Neither
## changes `powered` (observation and habitat read power, 08 §4).
var _flash_frame: int = -1
var _flash_usec: int = -1
var _dark: bool = false
var _rng: RandomNumberGenerator
var _wave: Tween

## Unlit twins of lit materials, shared by every fixture of a stratum.
static var _dark_materials: Dictionary = {}
## Buzzing twins (greener, 85% emission) of lit materials.
static var _buzz_materials: Dictionary = {}
## White twins (the lunge flash) of lit materials.
static var _white_materials: Dictionary = {}


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
	var c: Color = light_profile.get(&"color", base)
	return c * Tuning.LIGHT_FIXTURE_BUZZ_TINT if buzzing else c


## The profile's value for `key`, else `fallback` (the pool's stratum light).
func light_value(key: StringName, fallback: Variant) -> Variant:
	return light_profile.get(key, fallback)


## M2.2 light profiles by fixture kind (params.fixture); empty for the stratum's own.
static func profile_for(kind: StringName) -> Dictionary:
	match kind:
		&"rack_led":
			return {&"color": Tuning.SERVER_LED_LIGHT_COLOR, &"energy": Tuning.SERVER_LED_LIGHT_ENERGY,
				&"range": Tuning.SERVER_LED_LIGHT_RANGE, &"drop": 0.0, &"shadow": false, &"buzz": false}
		&"exit_light":
			return {&"color": Tuning.SERVER_EXIT_LIGHT_COLOR, &"energy": Tuning.SERVER_EXIT_LIGHT_ENERGY,
				&"range": Tuning.SERVER_EXIT_LIGHT_RANGE, &"buzz": false}
		&"emergency_box":
			return {&"drop": Tuning.SERVER_EMERGENCY_LIGHT_DROP, &"buzz": false}
		&"studio_light":
			# 02 §7 Substrate (M2.3): white, energy 0.6, range 15 m, no shadows, lit at the head.
			return {&"color": Color.WHITE, &"energy": Tuning.SUBSTRATE_STUDIO_LIGHT_ENERGY,
				&"range": Tuning.SUBSTRATE_STUDIO_LIGHT_RANGE, &"drop": 0.0, &"shadow": false, &"buzz": false, &"hum": false}
	return {}


## True when the fixture currently emits (powered, and not in a flicker-off instant or
## Flicker's post-lunge dark).
func is_emitting() -> bool:
	return powered and not _dark and (not _flickering or _flick_on)


## Lit for Flicker's habitat and lit area (08 §5): powered and not in its post-lunge dark.
## Flicker's stutter does not change it (the off instants are presentation).
func is_lit() -> bool:
	return powered and not _dark


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


## 02 §6: fixtures flicker only while Flicker is present in their group (08). Nothing
## else calls this: a flicker always means Flicker.
func set_flicker(on: bool) -> void:
	if _flickering == on:
		return
	_flickering = on
	if on and _rng == null:
		# Cosmetic, but seeded from the fixture's place so it is reproducible.
		_rng = RandomNumberGenerator.new()
		_rng.seed = hash(Vector3i(global_position.round()))
	_flick_on = true
	_stutter = new_stutter_state()
	if not on:
		intensity = 1.0 if powered else 0.0
	_update_process()
	_apply_visual()


func is_flickering() -> bool:
	return _flickering


## 08 §5: the stutter rate in Hz, clamped to 8..20 (Flicker raises it with its charge).
func set_flicker_rate(hz: float) -> void:
	_flick_hz = clampf(hz, Tuning.FLICKER_STUTTER_MIN_HZ, Tuning.FLICKER_STUTTER_MAX_HZ)


func flicker_rate() -> float:
	return _flick_hz


## 02 §8 lunge: a white flash for 2 frames (with reduce flashing: a 200 ms soft fade to 60%
## white, 12 §6). Then call set_lunge_dark(true).
func lunge_flash() -> void:
	if not powered:
		return
	_flash_frame = Engine.get_process_frames()
	_flash_usec = Time.get_ticks_usec()
	_update_process()
	_apply_visual()


func is_flashing() -> bool:
	return flash_amount() > 0.0


## 0..1 of the lunge flash this frame (CoherencePost's 2-frame rule and its reduced fade).
func flash_amount() -> float:
	if _flash_frame < 0:
		return 0.0
	var reduce := CoherenceRenderer.reduce_flashing if is_instance_valid(CoherenceRenderer) else false
	return CoherencePost.flash_amount(Engine.get_process_frames() - _flash_frame,
		(Time.get_ticks_usec() - _flash_usec) / 1000000.0, reduce)


## 08 §5: after the lunge the group is dark (and silent) for 1.5 s; power is unchanged.
func set_lunge_dark(on: bool) -> void:
	if _dark == on:
		return
	_dark = on
	if on:
		_flash_frame = -1
	intensity = 0.0 if on else (1.0 if powered else 0.0)
	_update_process()
	_apply_visual()


func is_lunge_dark() -> bool:
	return _dark


func _update_process() -> void:
	set_process(_flickering or _flash_frame >= 0)


func _process(delta: float) -> void:
	if _flash_frame >= 0:
		var a := flash_amount()
		if a <= 0.0 and Engine.get_process_frames() - _flash_frame >= Tuning.FLICKER_LUNGE_FLASH_FRAMES:
			_flash_frame = -1
			intensity = 0.0 if _dark else (1.0 if powered else 0.0)
			_update_process()
		else:
			intensity = lerpf(1.0, Tuning.LIGHT_FLICKER_FLASH_INTENSITY, a)
		_apply_visual()
		return
	if not _flickering or _dark:
		return
	var m := stutter_step(_stutter, _flick_hz, delta, _rng)
	_flick_on = bool(_stutter[0])
	var want := m if powered else 0.0
	if want != intensity:
		intensity = want
		_apply_visual()


## 12 §6 Flicker intensity (0.3..1): how deep an off instant goes (1: fully dark).
static func flicker_depth() -> float:
	return clampf(flicker_setting(), Tuning.SETTINGS_FLICKER_INTENSITY_MIN, 1.0)


## The 12 §6 Flicker intensity setting (1.0 without the settings autoload).
static func flicker_setting() -> float:
	if not is_instance_valid(SettingsManager):
		return 1.0
	var v: Variant = SettingsManager.get_value(&"flicker_intensity")
	return clampf(float(v), Tuning.SETTINGS_FLICKER_INTENSITY_MIN, 1.0) if v != null else 1.0


## 12 §6 blend 0..1 from the slow pulse (setting 0.3) to the full stutter (setting 1.0).
static func stutter_blend(setting: float) -> float:
	return clampf(inverse_lerp(Tuning.SETTINGS_FLICKER_INTENSITY_MIN, 1.0, setting), 0.0, 1.0)


## The stutter's on/off cycle rate in Hz for a toggle rate `hz` (08 §5, 8..20 toggles a
## second) under the 12 §6 setting: at 1.0 the stutter's own cycle (hz / 2); at 0.3 the
## 2 Hz slow pulse; linear in the setting between.
static func stutter_cycle_hz(setting: float, hz: float) -> float:
	var full := clampf(hz, Tuning.FLICKER_STUTTER_MIN_HZ, Tuning.FLICKER_STUTTER_MAX_HZ) * 0.5
	return lerpf(Tuning.SETTINGS_FLICKER_REDUCED_PULSE_HZ, full, stutter_blend(setting))


## A fresh stutter gate: [on, seconds to the next toggle, pulse phase 0..1, cycle Hz].
static func new_stutter_state() -> Array:
	return [true, 0.0, 0.0, 0.0]


## Advances a stutter gate (the fixture's, or the attached beam's) by `delta` at Flicker's
## toggle rate `hz` and returns the light multiplier (1 lit .. 1 - depth). At setting 1.0:
## random on/off toggles every 1 / random(hz, 1.5 hz) s (02 §8). Below 1.0 (12 §6) the
## square stutter blends toward a sine pulse: rate and depth interpolate to 2 Hz and 0.3 at
## the 0.3 setting, and the random spread fades with the blend. `rng` is presentation only.
static func stutter_step(state: Array, hz: float, delta: float, rng: RandomNumberGenerator) -> float:
	var setting := flicker_setting()
	var depth := flicker_depth()
	if setting >= 1.0:
		state[1] = float(state[1]) - delta
		if float(state[1]) <= 0.0:
			state[0] = not bool(state[0])
			var lo := clampf(hz, Tuning.FLICKER_STUTTER_MIN_HZ, Tuning.FLICKER_STUTTER_MAX_HZ)
			state[1] = 1.0 / rng.randf_range(lo, minf(lo * Tuning.LIGHT_FLICKER_RATE_SPREAD, Tuning.FLICKER_STUTTER_MAX_HZ))
		return 1.0 if bool(state[0]) else 1.0 - depth
	var t := stutter_blend(setting)
	var cycle := float(state[3])
	if cycle <= 0.0:
		cycle = _pulse_cycle(setting, hz, t, rng)
	var phase := float(state[2]) + delta * cycle
	if phase >= 1.0:
		phase = fmod(phase, 1.0)
		cycle = _pulse_cycle(setting, hz, t, rng)
	state[2] = phase
	state[3] = cycle
	var off := pulse_shape(phase, t)
	state[0] = off < 0.5
	return 1.0 - depth * off


## The pulse's off amount 0..1 at `phase`: a sine (blend 0) blended into the square on/off
## (blend 1).
static func pulse_shape(phase: float, blend: float) -> float:
	var sine := 0.5 - 0.5 * cos(TAU * phase)
	var square := 1.0 if phase >= 0.5 else 0.0
	return lerpf(sine, square, blend)


## One pulse cycle's rate: the blended rate, with the stutter's random spread scaled by the
## blend (none at 0.3), never past the stutter's 20 Hz toggles.
static func _pulse_cycle(setting: float, hz: float, blend: float, rng: RandomNumberGenerator) -> float:
	var base := stutter_cycle_hz(setting, hz)
	var spread := lerpf(1.0, rng.randf_range(1.0, Tuning.LIGHT_FLICKER_RATE_SPREAD), blend)
	return minf(base * spread, maxf(base, Tuning.FLICKER_STUTTER_MAX_HZ * 0.5))


func _apply_visual() -> void:
	if tube == null or _lit_material == null:
		return
	var lit := buzz_twin(_lit_material) if buzzing else _lit_material
	if _flash_frame >= 0 and powered:
		lit = white_twin(_lit_material)
	# A shallow off instant (12 §6 Flicker intensity below 0.5) keeps the tube lit, dimmer.
	var emitting := is_lit() and (not _flickering or _flick_on or flicker_depth() < 0.5)
	tube.material_override = lit if emitting else dark_twin(_lit_material)
	if glow != null:
		var e := Tuning.LIGHT_FIXTURE_GLOW_ENERGY * energy_scale() * clampf(intensity, 0.0, Tuning.LIGHT_FLICKER_FLASH_INTENSITY) if emitting else 0.0
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


## The same material at white, bright emission (the lunge flash, 02 §8).
static func white_twin(lit: Material) -> Material:
	if _white_materials.has(lit):
		return _white_materials[lit]
	var m := lit.duplicate() as Material
	if m is ShaderMaterial:
		var sm := m as ShaderMaterial
		sm.set_shader_parameter(&"emission", Color.WHITE)
		sm.set_shader_parameter(&"emission_strength", float(sm.get_shader_parameter(&"emission_strength")) * Tuning.LIGHT_FLICKER_FLASH_INTENSITY)
	elif m is StandardMaterial3D:
		var st := m as StandardMaterial3D
		st.emission = Color.WHITE
		st.emission_energy_multiplier *= Tuning.LIGHT_FLICKER_FLASH_INTENSITY
	_white_materials[lit] = m
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
