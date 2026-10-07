class_name Stamina
extends RefCounted
## The sprint meter (06 §4). Pure logic: the Player ticks it every physics frame.
## 100 max; sprint drains 20/s (x1.5 wading); regen 25/s after a 1 s delay once sprint
## is released; at 0 a 2 s lockout during which regeneration continues.

signal changed(value: float)
## Emitted once when the meter hits 0 (gasp, FOV snap, bob cut, arc in ui_danger; 11 §2).
signal exhausted

## Float residue below this counts as empty.
const EMPTY_EPSILON := 0.0001

var value: float = Tuning.STAMINA_MAX
## Seconds since sprint drain last happened (regen starts at STAMINA_REGEN_DELAY).
var _since_drain: float = INF
var _lockout: float = 0.0


## Advance by `dt`. `sprinting` is true only when the player is actually sprinting this
## frame (moving, sprint held, allowed); the Player decides that with can_sprint().
func tick(dt: float, sprinting: bool, wading: bool = false) -> void:
	var before := value
	if _lockout > 0.0:
		_lockout = maxf(0.0, _lockout - dt)
	if sprinting and can_sprint():
		var rate := Tuning.STAMINA_SPRINT_DRAIN * (Tuning.STAMINA_WADE_DRAIN_MULT if wading else 1.0)
		value = value - rate * dt
		if value <= EMPTY_EPSILON:
			value = 0.0
		_since_drain = 0.0
		if value <= 0.0:
			# 06 §4: 2 s lockout; regeneration continues during it (after the usual delay).
			_lockout = Tuning.STAMINA_LOCKOUT_TIME
			exhausted.emit()
	else:
		_since_drain += dt
		if _since_drain >= Tuning.STAMINA_REGEN_DELAY:
			# Regen only for the part of dt that lies beyond the delay.
			var regen_dt := minf(dt, _since_drain - Tuning.STAMINA_REGEN_DELAY)
			value = minf(Tuning.STAMINA_MAX, value + Tuning.STAMINA_REGEN * regen_dt)
	if not is_equal_approx(before, value):
		changed.emit(value)


func can_sprint() -> bool:
	return _lockout <= 0.0 and value > 0.0


func is_locked_out() -> bool:
	return _lockout > 0.0


func reset() -> void:
	value = Tuning.STAMINA_MAX
	_since_drain = INF
	_lockout = 0.0
	changed.emit(value)
