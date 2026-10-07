extends TestCase
## 07 §10: the same seed twice produces byte-identical LevelGrid and Placements; different
## seeds differ; a worker thread produces the same bytes as the main thread.

var _thread_hash: String = ""


func test_same_seed_is_byte_identical() -> void:
	for s in [1, 2, 77, -5, 123456789]:
		var a := LevelGenerator.generate(&"halls", 1, s)
		var b := LevelGenerator.generate(&"halls", 1, s)
		assert_eq(a.to_bytes(), b.to_bytes(), "seed %d bytes" % s)
		assert_eq(a.hash_hex(), b.hash_hex(), "seed %d hash" % s)
		assert_eq(a.to_ascii(), b.to_ascii(), "seed %d ascii" % s)


func test_same_seed_first_run_and_options_are_identical() -> void:
	var opts := {&"fuse_unlocked": true, &"item_pool": Tuning.ITEM_KINDS}
	var a := LevelGenerator.generate(&"halls", 1, 42, true, 1, opts)
	var b := LevelGenerator.generate(&"halls", 1, 42, true, 1, opts)
	assert_eq(a.hash_hex(), b.hash_hex())


func test_different_seeds_differ() -> void:
	var seen := {}
	for s in range(1, 21):
		var h := LevelGenerator.generate(&"halls", 1, s).hash_hex()
		assert_false(seen.has(h), "seed %d repeats seed %s" % [s, seen.get(h, -1)])
		seen[h] = s
	# Layouts differ too, not only metadata.
	var a := LevelGenerator.generate(&"halls", 1, 1).grid
	var b := LevelGenerator.generate(&"halls", 1, 2).grid
	assert_ne(a.walls, b.walls)


func test_depth_and_run_seed_feed_the_level_seed() -> void:
	var a := LevelGenerator.generate(&"halls", 1, 9)
	assert_eq(a.level_seed, Seeds.for_depth(9, 1))
	assert_eq(a.run_seed, 9)


func test_worker_thread_matches_main_thread() -> void:
	var main_hash := LevelGenerator.generate(&"halls", 1, 31337).hash_hex()
	var task := WorkerThreadPool.add_task(_generate_on_worker)
	WorkerThreadPool.wait_for_task_completion(task)
	assert_eq(_thread_hash, main_hash, "07 §1: generation is worker-thread safe and deterministic")


func _generate_on_worker() -> void:
	_thread_hash = LevelGenerator.generate(&"halls", 1, 31337).hash_hex()
