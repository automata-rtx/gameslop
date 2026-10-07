class_name FakeClock
extends RefCounted
## Manual time source for tests (14 §8). Systems that need time in tests accept
## a Callable returning seconds; pass `clock.now`.

var time_s: float = 0.0

func _init(start_s: float = 0.0) -> void:
	time_s = start_s

func now() -> float:
	return time_s

func now_ms() -> int:
	return int(round(time_s * 1000.0))

func advance(dt_s: float) -> void:
	time_s += dt_s

func now_usec() -> int:
	return int(round(time_s * 1000000.0))
