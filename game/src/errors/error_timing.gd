class_name ErrorTiming
extends RefCounted
## Script cost of the errors (08 §2 processing budget, 14 BUDGET_ERRORS_SCRIPT_MS 0.3 ms):
## microseconds spent in every error's _physics_process during the last completed physics
## frame, in total and per error id. Exposed as the Performance custom monitor
## `noclip/errors_ms` (the debugger's monitors, F3, the error arena).

const MONITOR := &"noclip/errors_ms"

static var frame_usec: int = 0
static var frame_usec_by_id: Dictionary = {}
static var _acc_usec: int = 0
static var _acc_by_id: Dictionary = {}
static var _acc_frame: int = -1


static func ensure_monitor() -> void:
	if not Performance.has_custom_monitor(MONITOR):
		Performance.add_custom_monitor(MONITOR, ErrorTiming.errors_ms)


## Milliseconds of error script time in the last physics frame (all errors).
static func errors_ms() -> float:
	return frame_usec / 1000.0


## Milliseconds of `id`'s script time in the last physics frame (every error of that id).
static func error_ms(id: StringName) -> float:
	return int(frame_usec_by_id.get(id, 0)) / 1000.0


static func account(id: StringName, usec: int) -> void:
	var f := Engine.get_physics_frames()
	if f != _acc_frame:
		frame_usec = _acc_usec
		frame_usec_by_id = _acc_by_id
		_acc_usec = 0
		_acc_by_id = {}
		_acc_frame = f
	_acc_usec += usec
	_acc_by_id[id] = int(_acc_by_id.get(id, 0)) + usec
