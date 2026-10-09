class_name Flashlight
extends Node3D
## The flashlight and its crank (06 §5, 02 §6, 02 §9, 11 §2). Parented to the camera.
## Charge 0..100 drains 1.6/s while on; the crank adds 25/s (x1.5 Lightbearer). Energy
## lerps 0.5..1.6 with charge, and the cone narrows 38 -> 30 deg below 30 charge. The light
## is never fully dark (T1). The held model is primitives: a 0.18 m body, lens, crank wheel.
## The Player owns input, speed caps and the noise events; this node owns charge and visuals.

signal charge_changed(value: float)
## `quiet` is true for a silent reset (reset_for_run): no click, no kick, no noise.
signal toggled(on: bool, quiet: bool)
## Crank started or stopped turning (stops by itself when full).
signal crank_changed(turning: bool)
## Every CRANK_NOISE_INTERVAL while the wheel turns (the Player emits the 12 m noise).
signal crank_tick
signal crank_full

## Wheel turns this many radians per unit of charge added (a fast, visible spin).
const WHEEL_RAD_PER_CHARGE := 0.9
## Held model bob: share of the camera's step bob felt by the hand (02 §9).
const HELD_BOB := 0.006
const LENS_EMISSION_ON := 6.0
const LENS_EMISSION_OFF := 0.0
## 11 §2 crank row "lens brightens": with the light off, the turning wheel's dynamo gives
## the lens a faint glow, this bright at full charge (never enough to light the room).
const LENS_EMISSION_CRANK := 1.5
## Glow from the dynamo at empty charge, as a share of LENS_EMISSION_CRANK.
const LENS_EMISSION_CRANK_MIN := 0.35

@onready var beam: SpotLight3D = %Beam
@onready var hand_light: OmniLight3D = %HandLight
@onready var held: Node3D = %Held
@onready var wheel: Node3D = %Wheel
@onready var lens: MeshInstance3D = %Lens

var charge: float = Tuning.FLASH_CHARGE_MAX
var on: bool = false
var lightbearer: bool = false
## 0..1 extra dimming of the held light (noclip charge dims it 30%, 11 §2).
var dim: float = 0.0
## Flicker attached (08 §5): the beam's stutter gate (1 lit, 0 an off instant) and its
## lunge flash (0..1 toward white x3). Set by ErrorFlicker only; 1 and 0 otherwise.
var stutter: float = 1.0
var flash: float = 0.0

var _cranking: bool = false
var _turning: bool = false
var _crank_timer: float = 0.0
var _held_rest: Vector3
var _held_rest_basis: Basis
var _dip_tween: Tween
var _beam_color: Color = Color.WHITE


func _ready() -> void:
	_held_rest = held.position
	_held_rest_basis = held.basis
	# The beam leaves the held lens (it sits under %Held, so it bobs with the hand), but
	# points along the camera's view axis, not the model's slight inward tilt.
	beam.basis = held.basis.inverse()
	beam.spot_range = Tuning.FLASH_RANGE
	beam.spot_angle_attenuation = Tuning.FLASH_ATTENUATION_ANGLE
	beam.shadow_enabled = true
	_beam_color = beam.light_color
	hand_light.omni_range = Tuning.FLASH_HAND_LIGHT_RANGE
	_apply_visuals()


# --- pure rules (unit-tested) ---------------------------------------------------------

## 06 §5: energy = lerp(0.5, 1.6, charge/100).
static func energy_for(c: float) -> float:
	return lerpf(Tuning.FLASH_ENERGY_MIN, Tuning.FLASH_ENERGY_MAX, clampf(c / Tuning.FLASH_CHARGE_MAX, 0.0, 1.0))


## 06 §5: SpotLight3D.spot_angle (half cone): 19 deg, narrowing to 15 as charge falls below 30.
static func spot_angle_for(c: float) -> float:
	var full := Tuning.FLASH_CONE_FULL_DEG
	if c < Tuning.FLASH_TIRED_BELOW:
		full = lerpf(Tuning.FLASH_CONE_TIRED_FULL_DEG, Tuning.FLASH_CONE_FULL_DEG,
				clampf(c / Tuning.FLASH_TIRED_BELOW, 0.0, 1.0))
	return full * 0.5


static func crank_rate(is_lightbearer: bool) -> float:
	return Tuning.CRANK_RATE * (Tuning.CRANK_RATE_LIGHTBEARER_MULT if is_lightbearer else 1.0)


## One step of charge. Cranking at full holds the charge at full (the wheel stops).
static func step_charge(c: float, dt: float, light_on: bool, cranking: bool, is_lightbearer: bool) -> float:
	if cranking:
		c += crank_rate(is_lightbearer) * dt
	if light_on:
		c -= Tuning.FLASH_DRAIN * dt
	if cranking and c >= Tuning.FLASH_CHARGE_MAX - Tuning.FLASH_DRAIN * dt:
		return Tuning.FLASH_CHARGE_MAX
	return clampf(c, 0.0, Tuning.FLASH_CHARGE_MAX)


# --- control (called by the Player) ---------------------------------------------------

## `quiet` skips the toggle's click, kick and noise (a new run resets the light silently).
func set_on(v: bool, quiet: bool = false) -> void:
	if v == on:
		return
	on = v
	_apply_visuals()
	toggled.emit(on, quiet)


func toggle() -> void:
	set_on(not on)


func set_cranking(v: bool) -> void:
	_cranking = v
	if not v:
		_crank_timer = 0.0


func is_cranking() -> bool:
	return _cranking


## True while the wheel actually turns (cranking and not yet full).
func is_turning() -> bool:
	return _turning


## 11 §2 crouch / stand Image: the held light (and its beam) pitches down `deg` and back
## over the camera dip's 120 ms. Interruptible (11 §5).
func dip(deg: float) -> void:
	if _dip_tween:
		_dip_tween.kill()
	if not is_inside_tree() or held == null:
		return
	var half := Tuning.CAMERA_DIP_MS / 2000.0
	var rad := deg_to_rad(deg)
	_dip_tween = create_tween().set_trans(Tween.TRANS_SINE)
	_dip_tween.tween_method(_set_held_dip, 0.0, rad, half).set_ease(Tween.EASE_OUT)
	_dip_tween.tween_method(_set_held_dip, rad, 0.0, half).set_ease(Tween.EASE_IN_OUT)


func _set_held_dip(rad: float) -> void:
	held.basis = _held_rest_basis.rotated(Vector3.RIGHT, -rad)


## Re-applies the beam after `stutter` or `flash` changed (ErrorFlicker).
func refresh() -> void:
	_apply_visuals()


func set_charge(v: float) -> void:
	charge = clampf(v, 0.0, Tuning.FLASH_CHARGE_MAX)
	charge_changed.emit(charge)
	_apply_visuals()


## Beam axis in world space (06 Interfaces: observation is within 25 deg of it).
## The beam leaves the held lens (02 §9), so origin and axis follow the hand.
func beam_axis() -> Vector3:
	return -beam.global_transform.basis.z


func beam_origin() -> Vector3:
	return beam.global_position


func tick(dt: float, bob_phase: float, bob_amp: float) -> void:
	var before := charge
	var was_full := before >= Tuning.FLASH_CHARGE_MAX
	charge = step_charge(charge, dt, on, _cranking, lightbearer)
	var turning := _cranking and not (was_full and charge >= Tuning.FLASH_CHARGE_MAX)
	if turning:
		wheel.rotate_object_local(Vector3.UP, (charge - before + Tuning.FLASH_DRAIN * dt * float(on)) * WHEEL_RAD_PER_CHARGE)
		# 06 §5: a 12 m noise every 0.5 s; the first lands as the wheel starts.
		_crank_timer -= dt
		if _crank_timer <= 0.0:
			_crank_timer += Tuning.CRANK_NOISE_INTERVAL
			crank_tick.emit()
	if turning != _turning:
		_turning = turning
		if not turning:
			_crank_timer = 0.0
		crank_changed.emit(turning)
		if not turning and _cranking:
			crank_full.emit()
	if not is_equal_approx(before, charge):
		charge_changed.emit(charge)
	held.position = _held_rest + Vector3(0.0, -absf(sin(bob_phase)) * HELD_BOB * bob_amp, 0.0)
	_apply_visuals()


func _apply_visuals() -> void:
	if beam == null:
		return
	var e := energy_for(charge) * (1.0 - dim) * stutter
	if flash > 0.0:
		e = lerpf(e, energy_for(charge) * Tuning.LIGHT_FLICKER_FLASH_INTENSITY, flash)
	beam.visible = on
	beam.light_color = _beam_color.lerp(Color.WHITE, flash)
	beam.light_energy = e
	beam.spot_angle = spot_angle_for(charge)
	hand_light.visible = on
	hand_light.light_energy = Tuning.FLASH_HAND_LIGHT_ENERGY * (1.0 - dim) * stutter
	var mat := lens.material_override as StandardMaterial3D
	if mat:
		mat.emission_energy_multiplier = lens_emission()


## Lens emissive: the beam's energy while on; a faint dynamo glow while the wheel turns
## with the light off (11 §2 crank: "lens brightens"); dark otherwise.
func lens_emission() -> float:
	if on:
		return LENS_EMISSION_ON * energy_for(charge) * (1.0 - dim) * maxf(stutter, flash) / Tuning.FLASH_ENERGY_MAX
	if _turning:
		var c := clampf(charge / Tuning.FLASH_CHARGE_MAX, 0.0, 1.0)
		return LENS_EMISSION_CRANK * lerpf(LENS_EMISSION_CRANK_MIN, 1.0, c)
	return LENS_EMISSION_OFF
