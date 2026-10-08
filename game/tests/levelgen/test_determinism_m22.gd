extends TestCase
## M2.2 (07 §1 rule 4, §10): Offices and Server are byte-deterministic, on the main thread
## and on a worker thread, and different seeds differ.

var _hashes: Dictionary = {}


func test_same_seed_is_byte_identical() -> void:
	for stratum: StringName in [&"offices", &"server"]:
		for s in [1, 2, 77, -5]:
			var a := LevelGenerator.generate(stratum, 4, s)
			var b := LevelGenerator.generate(stratum, 4, s)
			assert_eq(a.to_bytes(), b.to_bytes(), "%s seed %d bytes" % [stratum, s])
			assert_eq(a.to_ascii(), b.to_ascii(), "%s seed %d ascii" % [stratum, s])
		var c := LevelGenerator.generate(stratum, 4, 1)
		var d := LevelGenerator.generate(stratum, 4, 2)
		assert_ne(c.hash_hex(), d.hash_hex(), "%s: seeds differ" % stratum)


func test_worker_matches_main() -> void:
	var main := {}
	for stratum: StringName in [&"offices", &"server"]:
		main[stratum] = LevelGenerator.generate(stratum, 5, 4242, false, 1, {&"fuse_unlocked": true}).hash_hex()
	var task := WorkerThreadPool.add_task(_on_worker)
	WorkerThreadPool.wait_for_task_completion(task)
	for stratum: StringName in main:
		assert_eq(_hashes.get(stratum, ""), main[stratum], "%s on a worker" % stratum)


func _on_worker() -> void:
	for stratum: StringName in [&"offices", &"server"]:
		_hashes[stratum] = LevelGenerator.generate(stratum, 5, 4242, false, 1, {&"fuse_unlocked": true}).hash_hex()
