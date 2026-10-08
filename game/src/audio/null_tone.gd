class_name NullTone
extends RefCounted
## The Null grid tone (03 §4 Errors, 08 §7): three sines at 55, 82.5 and 110 Hz whose
## amplitude is 1 - distance / 60 m (the tone's audible radius, AUDIO_NULL_MAX_DISTANCE:
## Null is heard through walls to 60 m, beyond its 12 m unrender radius), plus a 1 Hz
## pulse of digital noise (sample-and-hold, 3-bit). Panned by the listener-relative side.
## Pure rendering state: GeneratorLayers owns the player, AudioManager feeds distance and pan.

## Per-sine peak levels (sum 0.36, about -9 dBFS at the core).
const SINE_LEVELS: Array[float] = [0.16, 0.11, 0.09]
const PULSE_LEVEL := 0.07
const PULSE_HZ := 1.0
const PULSE_LEN_S := 0.06
const PULSE_HOLD := 6                 # samples held: the digital grain
const PULSE_BITS := 3.0

var mix_rate: float
var distance: float = INF            # m to g_null_pos; INF = no Null on the level
var pan: float = 0.0                 # -1 left .. 1 right
var _phase: PackedFloat64Array = [0.0, 0.0, 0.0]
var _gain: float = 0.0
var _pan_now: float = 0.0
var _pulse_t: float = 0.0
var _hold_v: float = 0.0
var _hold_n: int = 0
var _rng := RandomNumberGenerator.new()


func _init(rate: float) -> void:
	mix_rate = rate
	_rng.seed = 0x4E55  # cosmetic noise, fixed for repeatable renders


## 03 §4: amplitude tied to 1 - distance / radius, radius = the 60 m audible range.
static func amplitude(d: float) -> float:
	if is_inf(d) or is_nan(d):
		return 0.0
	return clampf(1.0 - d / Tuning.AUDIO_NULL_MAX_DISTANCE, 0.0, 1.0)


func target_gain() -> float:
	return amplitude(distance)


func current_gain() -> float:
	return _gain


func is_silent() -> bool:
	return target_gain() <= 0.0 and _gain <= 0.0


## Renders `frames` stereo frames; gain and pan ramp across the block (no zipper).
func render(frames: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(frames)
	if frames <= 0:
		return out
	var target := target_gain()
	var g0 := _gain
	if g0 <= 0.0 and target <= 0.0:
		return out
	var gstep := (target - g0) / float(frames)
	var p0 := _pan_now
	var pstep := (clampf(pan, -1.0, 1.0) - p0) / float(frames)
	var inc: Array[float] = []
	for hz in Tuning.AUDIO_NULL_TONE_HZ:
		inc.append(hz / mix_rate)
	var pulse_len := PULSE_LEN_S * PULSE_HZ
	var steps := pow(2.0, PULSE_BITS - 1.0)
	for i in frames:
		var s := 0.0
		for k in 3:
			_phase[k] = fmod(_phase[k] + inc[k], 1.0)
			s += sin(TAU * _phase[k]) * SINE_LEVELS[k]
		_pulse_t = fmod(_pulse_t + PULSE_HZ / mix_rate, 1.0)
		if _pulse_t < pulse_len:
			if _hold_n <= 0:
				_hold_v = roundf(_rng.randf_range(-1.0, 1.0) * steps) / steps
				_hold_n = PULSE_HOLD
			_hold_n -= 1
			s += _hold_v * PULSE_LEVEL * (1.0 - _pulse_t / pulse_len)
		var g := g0 + gstep * float(i + 1)
		var p := p0 + pstep * float(i + 1)
		var ang := (p + 1.0) * PI / 4.0
		out[i] = Vector2(cos(ang), sin(ang)) * (s * g * sqrt(2.0))
	_gain = target
	_pan_now = clampf(pan, -1.0, 1.0)
	return out
