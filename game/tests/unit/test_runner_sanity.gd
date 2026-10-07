extends TestCase
## Proves the runner works: sync, async, rng determinism, fake clock (M0.1).

func test_assertions() -> void:
	assert_eq(1 + 1, 2)
	assert_eq(&"chase", "chase", "StringName equals String by content")
	assert_approx(0.1 + 0.2, 0.3, 0.000001)
	assert_contains([1, 2, 3], 2)
	assert_contains({"a": 1}, "a")
	assert_contains("noclip", "clip")

func test_await_frames() -> void:
	var f0 := Engine.get_process_frames()
	await await_frames(3)
	assert_gt(Engine.get_process_frames(), f0)

func test_seeded_rng_is_deterministic() -> void:
	var a := make_rng(42)
	var b := make_rng(42)
	for i in 10:
		assert_eq(a.randi(), b.randi())

func test_fake_clock() -> void:
	var c := fake_clock(1.0)
	c.advance(0.5)
	assert_approx(c.now(), 1.5)
	assert_eq(c.now_ms(), 1500)
