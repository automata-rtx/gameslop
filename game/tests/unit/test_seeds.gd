extends TestCase

func test_derive_is_deterministic_and_label_sensitive() -> void:
	assert_eq(Seeds.derive(1, "layout"), Seeds.derive(1, "layout"))
	assert_ne(Seeds.derive(1, "layout"), Seeds.derive(1, "props"))
	assert_ne(Seeds.derive(1, "layout"), Seeds.derive(2, "layout"))
	assert_eq(Seeds.derive(7, "layout"), hash("7:layout"))

func test_for_depth_and_daily() -> void:
	assert_eq(Seeds.for_depth(5, 3), hash("5:depth:3"))
	assert_eq(Seeds.daily({"year": 2026, "month": 10, "day": 7}), hash("NOCLIP:20261007"))

func test_rng_is_seeded() -> void:
	assert_eq(Seeds.rng(9).randi(), Seeds.rng(9).randi())
