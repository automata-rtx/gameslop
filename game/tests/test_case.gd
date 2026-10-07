class_name TestCase
extends Node
## Base class for every NOCLIP test (14 §8). Subclass it in a file named test_*.gd
## under game/tests/; every method whose name starts with "test_" is a test.
## Optional hooks: before_all(), before_each(), after_each(), after_all().
## Test methods may await (frames, physics); the runner awaits them.

var _failures: PackedStringArray = []
var _current: String = ""

## Seeded RNG for tests. Never use randi()/randf() in tests.
func make_rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng

## A manual clock for timing tests (Director phases, error timers).
func fake_clock(start_s: float = 0.0) -> FakeClock:
	return FakeClock.new(start_s)

func await_frames(n: int = 1) -> void:
	for i in n:
		await get_tree().process_frame

func await_physics_frames(n: int = 1) -> void:
	for i in n:
		await get_tree().physics_frame

func fail(msg: String) -> void:
	_failures.append(msg)

func assert_true(cond: bool, msg: String = "") -> void:
	if not cond:
		fail("expected true" + _ctx(msg))

func assert_false(cond: bool, msg: String = "") -> void:
	if cond:
		fail("expected false" + _ctx(msg))

func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if not _equal(actual, expected):
		fail("expected %s, got %s%s" % [_s(expected), _s(actual), _ctx(msg)])

func assert_ne(actual: Variant, unexpected: Variant, msg: String = "") -> void:
	if _equal(actual, unexpected):
		fail("expected anything but %s%s" % [_s(unexpected), _ctx(msg)])

func assert_approx(actual: float, expected: float, tolerance: float = 0.0001, msg: String = "") -> void:
	if absf(actual - expected) > tolerance:
		fail("expected %s ± %s, got %s%s" % [expected, tolerance, actual, _ctx(msg)])

func assert_gt(actual: Variant, bound: Variant, msg: String = "") -> void:
	if not (actual > bound):
		fail("expected %s > %s%s" % [_s(actual), _s(bound), _ctx(msg)])

func assert_lt(actual: Variant, bound: Variant, msg: String = "") -> void:
	if not (actual < bound):
		fail("expected %s < %s%s" % [_s(actual), _s(bound), _ctx(msg)])

func assert_null(value: Variant, msg: String = "") -> void:
	if value != null:
		fail("expected null, got %s%s" % [_s(value), _ctx(msg)])

func assert_not_null(value: Variant, msg: String = "") -> void:
	if value == null:
		fail("expected non-null" + _ctx(msg))

## Works on String (substring), Array/Packed*Array (element), Dictionary (key).
func assert_contains(container: Variant, item: Variant, msg: String = "") -> void:
	var found := false
	match typeof(container):
		TYPE_STRING, TYPE_STRING_NAME:
			found = String(container).contains(String(item))
		TYPE_DICTIONARY:
			found = (container as Dictionary).has(item)
		_:
			if container is Array or typeof(container) >= TYPE_PACKED_BYTE_ARRAY:
				found = item in container
	if not found:
		fail("expected %s to contain %s%s" % [_s(container), _s(item), _ctx(msg)])

func _equal(a: Variant, b: Variant) -> bool:
	# StringName and String compare equal by content, as GDScript does with ==.
	if typeof(a) != typeof(b) and not (a is String or a is StringName) and not (a is float or a is int):
		return false
	return a == b

func _ctx(msg: String) -> String:
	return "" if msg.is_empty() else " (" + msg + ")"

func _s(v: Variant) -> String:
	var t := var_to_str(v)
	return t if t.length() <= 200 else t.substr(0, 200) + "…"
