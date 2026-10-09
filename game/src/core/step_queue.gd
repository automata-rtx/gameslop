class_name StepQueue
extends RefCounted
## R19 (14 §10 level build slice, 4 ms per frame): ordered steps run a frame's budget at a
## time. A step starts only while one more of the last step's cost still fits the budget;
## the first step of a call always runs. The arrival's work after the builder's last slice
## (the pickups, the Director's roster) goes through one of these.

## Milliseconds spent in each `run` call (one per frame when driven from a frame callback).
var frame_ms: PackedFloat32Array = PackedFloat32Array()
var _steps: Array[Callable] = []


func append(step: Callable) -> void:
	_steps.append(step)


func append_all(steps: Array[Callable]) -> void:
	_steps.append_array(steps)


## Runs waiting steps until `budget_ms` would be passed. Returns true when none is left.
func run(budget_ms: float = INF) -> bool:
	if _steps.is_empty():
		return true
	var t0 := Time.get_ticks_usec()
	var budget_us := budget_ms * 1000.0
	var last_us := 0
	var first := true
	while not _steps.is_empty():
		if not first and Time.get_ticks_usec() - t0 + last_us > budget_us:
			break
		first = false
		var step: Callable = _steps.pop_front()
		var s0 := Time.get_ticks_usec()
		step.call()
		last_us = Time.get_ticks_usec() - s0
	frame_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
	return _steps.is_empty()


func is_done() -> bool:
	return _steps.is_empty()


func clear() -> void:
	_steps.clear()


## The per-frame budget for spread work: the build slice with its headroom (3 ms).
static func slice_budget_ms() -> float:
	return Tuning.LEVELBUILD_SLICE_MS * Tuning.LEVELBUILD_SLICE_HEADROOM
