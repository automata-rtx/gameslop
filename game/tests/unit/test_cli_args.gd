extends TestCase
## CliArgs (14 §9): debug launch flags.


func test_empty() -> void:
	var a := CliArgs.parse(PackedStringArray())
	assert_false(a.smoke)
	assert_false(a.has_seed)
	assert_eq(a.depth, 0)
	assert_eq(a.stratum, &"")
	assert_false(a.wants_direct_level())


func test_seed_depth_stratum() -> void:
	var a := CliArgs.parse(PackedStringArray(["--seed", "1", "--depth", "3", "--stratum", "garage"]))
	assert_true(a.has_seed)
	assert_eq(a.run_seed, 1)
	assert_eq(a.depth, 3)
	assert_eq(a.stratum, &"garage")
	assert_true(a.wants_direct_level())


func test_equals_form_and_negative_seed() -> void:
	var a := CliArgs.parse(PackedStringArray(["--seed=-42", "--stratum=HALLS"]))
	assert_eq(a.run_seed, -42)
	assert_eq(a.stratum, &"halls")
	var b := CliArgs.parse(PackedStringArray(["--seed", "-7"]))
	assert_eq(b.run_seed, -7)


func test_smoke_and_tour() -> void:
	var a := CliArgs.parse(PackedStringArray(["--smoke", "--tour"]))
	assert_true(a.smoke)
	assert_true(a.tour)
	assert_eq(a.tour_dir, CliArgs.DEFAULT_TOUR_DIR)
	var b := CliArgs.parse(PackedStringArray(["--tour", "out/dir", "--validate-levels", "50"]))
	assert_eq(b.tour_dir, "out/dir")
	assert_eq(b.validate_levels, 50)


func test_bad_values_are_ignored() -> void:
	var a := CliArgs.parse(PackedStringArray(["--depth", "0", "--stratum", "basement", "--seed", "x", "--smoke"]))
	assert_eq(a.depth, 0)
	assert_eq(a.stratum, &"")
	assert_false(a.has_seed)
	assert_true(a.smoke, "a later valid flag still parses")
