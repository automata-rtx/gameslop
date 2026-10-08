extends TestCase
## M2.10 SaveManager and the meta.json schema (13 §2, §7, 14 §12): round trip, schema defaults
## for missing fields, validation, unknown keys preserved, migration from a synthetic version 0,
## atomic write (a crash between the tmp write and the rename), corrupt file recovery.

const DIR := "user://tests/save_case"

var _dir_before: String


func before_all() -> void:
	_dir_before = SaveManager.directory
	SaveManager.directory = DIR


func after_all() -> void:
	_wipe()
	SaveManager.directory = _dir_before
	SaveManager.crash_before_rename = false


func before_each() -> void:
	_wipe()
	SaveManager.crash_before_rename = false
	SaveManager.consume_reset_notice()


func _wipe() -> void:
	for p in [SaveManager.meta_path(), SaveManager.tmp_path(), SaveManager.bad_path()]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _read_json(path: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


func _sample() -> MetaState:
	var m := MetaState.new()
	m.first_descent_done = true
	m.earn(&"glowstick")
	m.earn(&"radio")
	m.note_found(&"H1")
	m.note_found(&"H3")
	m.codex_notice(&"still")
	m.codex_notice(&"still")
	m.polaroids_seen.append(3)
	m.depth_reached(3)
	m.depth_reached(4)
	m.depth_reached(4)
	m.stratum_reached(&"garage")
	m.item_used(&"polaroid")
	m.add_stat("distance_walked_m", 15320.5)
	m.record_run({"cause": "still", "depth": 3, "stratum": "garage", "score": 4150, "seed": 123456789,
			"mode": Tuning.MODE_DAILY, "won": false, "seconds": 600.0, "daily_key": "20261007"})
	m.endless_best_depth = 9
	m.cycle_unlocked = true
	m.unknown["future_key"] = {"a": 1.0}
	return m


func test_paths_and_custom_user_dir() -> void:
	assert_eq(SaveManager.meta_path(), DIR + "/meta.json")
	assert_eq(SaveManager.tmp_path(), DIR + "/meta.json.tmp", "13 §1 atomic tmp name")
	assert_eq(SaveManager.bad_path(), DIR + "/meta.json.bad", "13 §2 corrupt backup name")
	assert_true(bool(ProjectSettings.get_setting("application/config/use_custom_user_dir")))
	assert_eq(ProjectSettings.get_setting("application/config/custom_user_dir_name"), "NOCLIP")
	assert_ne(SaveManager.DEFAULT_DIR, SaveManager.TEST_DIR)
	assert_true(SaveManager._under_test_runner(), "the test runner never touches the player's Archive")


func test_round_trip() -> void:
	var m := _sample()
	assert_true(SaveManager.save_meta(m))
	assert_true(FileAccess.file_exists(SaveManager.meta_path()))
	assert_false(FileAccess.file_exists(SaveManager.tmp_path()), "tmp renamed away")
	var back := SaveManager.load_meta()
	assert_eq(back.to_dict(), m.to_dict(), "everything survives a save and load")
	assert_eq(back.version, 1)
	assert_true(back.is_unlocked(&"radio"))
	assert_false(back.is_unlocked(&"flare"))
	assert_eq(back.notes_found, [&"H1", &"H3"] as Array[StringName])
	assert_eq(int(back.codex["still"]), 2)
	assert_eq(back.depth_count(4), 2)
	assert_true(back.has_reached_stratum(&"garage"))
	assert_eq(back.daily_result("20261007"), {"score": 4150, "depth": 3, "cause": "still"})
	assert_eq(int(back.last_run["seed"]), 123456789)
	assert_eq(back.unknown, {"future_key": {"a": 1.0}}, "unknown keys preserved (13 §2)")
	assert_false(SaveManager.has_reset_notice())


func test_file_layout_matches_schema_v1() -> void:
	SaveManager.save_meta(_sample())
	var d := _read_json(SaveManager.meta_path())
	for k in MetaSchema.KNOWN_KEYS:
		assert_true(d.has(k), "meta.json has %s (13 §2)" % k)
	assert_eq(int(d["version"]), 1)
	assert_eq((d["unlocks"] as Dictionary).size(), Tuning.UNLOCK_COUNT, "all 14 unlock ids written")
	var stats: Dictionary = d["stats"]
	for k in ["runs", "wins", "best_depth", "best_score", "deaths_by", "distance_walked_m", "walls_passed",
			"floors_dropped", "coherence_spent", "notes_total", "evasions", "time_played_s",
			"breakers_thrown", "depth_reached_counts", "items_used"]:
		assert_true(stats.has(k), "stats.%s" % k)
	assert_true((stats["deaths_by"] as Dictionary).has("substrate"))


func test_missing_fields_take_defaults() -> void:
	_write(SaveManager.meta_path(), "{\"version\": 1, \"notes_found\": [\"H2\"]}")
	var m := SaveManager.load_meta()
	assert_false(SaveManager.has_reset_notice(), "a sparse file is not corrupt")
	assert_eq(m.notes_found, [&"H2"] as Array[StringName])
	assert_false(m.first_descent_done)
	assert_eq(m.unlocks.size(), Tuning.UNLOCK_COUNT)
	for id in Tuning.UNLOCK_IDS:
		assert_false(m.is_unlocked(id))
	assert_eq(int(m.codex.get("null", -1)), 0)
	assert_eq(m.stats, MetaSchema.default_stats())
	assert_eq(m.daily, {})
	assert_eq(m.last_run, {})
	assert_eq(m.endless_best_depth, 0)
	assert_false(m.cycle_unlocked)
	assert_false(m.created_at.is_empty())


func test_values_are_validated() -> void:
	var bad := {
		"version": 1, "first_descent_done": "yes", "unlocks": {"radio": 1, "flare": true},
		"notes_found": ["H1", 7, "H1", ""], "codex": {"still": -4, "echo": 2.0},
		"polaroids_seen": [1, -1, "x", 1],
		"stats": {"runs": -3, "best_depth": 5000, "best_score": -10, "coherence_spent": "lots",
			"depth_reached_counts": {"4": 2.0, "0": 3, "abc": 1, "1000": 1}, "deaths_by": {"still": 2.0},
			"strata_reached": ["garage", "moon"], "my_stat": 9},
		"daily": {"20261007": {"score": -5, "depth": 0, "cause": "echo"}, "yesterday": {"score": 1}},
		"last_run": {"depth": 1200, "score": 20.0, "seed": "s"},
		"endless_best_depth": -2, "cycle_unlocked": 1,
	}
	var m := MetaSchema.from_dict(MetaSchema.migrate(bad))
	assert_false(m.first_descent_done, "non-bool -> default")
	assert_false(m.is_unlocked(&"radio"), "1 is not true")
	assert_true(m.is_unlocked(&"flare"))
	assert_eq(m.notes_found, [&"H1"] as Array[StringName], "strings only, no duplicates")
	assert_eq(int(m.codex["still"]), 0, "counts >= 0")
	assert_eq(m.codex["echo"], 2, "JSON floats become ints")
	assert_eq(m.polaroids_seen, [1] as Array[int])
	assert_eq(m.stats["runs"], 0)
	assert_eq(m.stats["best_depth"], Tuning.META_DEPTH_MAX, "depth 1 to 999")
	assert_eq(m.stats["best_score"], 0, "scores >= 0")
	assert_eq(m.stats["coherence_spent"], 0.0)
	assert_eq(m.stats["depth_reached_counts"], {"4": 2})
	assert_eq(int(m.stats["deaths_by"]["still"]), 2)
	assert_eq(m.stats["strata_reached"], ["garage"])
	assert_eq(m.stats["my_stat"], 9, "unknown stats keys preserved")
	assert_eq(m.daily.keys(), ["20261007"])
	assert_eq(m.daily["20261007"]["score"], 0)
	assert_eq(m.daily["20261007"]["depth"], 1)
	assert_eq(m.last_run["depth"], Tuning.META_DEPTH_MAX)
	assert_eq(m.last_run["seed"], 0)
	assert_eq(m.endless_best_depth, 0)
	assert_false(m.cycle_unlocked)


func test_migration_from_version_0() -> void:
	_write(SaveManager.meta_path(), JSON.stringify({
		"unlocks": ["glowstick", "daily"], "notes_found": ["P1"], "first_descent_done": true,
	}))
	var m := SaveManager.load_meta()
	assert_false(SaveManager.has_reset_notice(), "an old version is migrated, not reset")
	assert_eq(m.version, 1)
	assert_true(m.is_unlocked(&"glowstick"))
	assert_true(m.is_unlocked(&"daily"))
	assert_false(m.is_unlocked(&"radio"))
	assert_true(m.first_descent_done)
	SaveManager.save_meta(m)
	assert_eq(int(_read_json(SaveManager.meta_path())["version"]), 1, "saved as version 1")


func test_atomic_write_survives_a_crash_before_rename() -> void:
	var old := MetaState.new()
	old.note_found(&"H1")
	SaveManager.save_meta(old)
	var newer := MetaState.new()
	newer.note_found(&"H1")
	newer.note_found(&"H2")
	SaveManager.crash_before_rename = true
	assert_false(SaveManager.save_meta(newer))
	SaveManager.crash_before_rename = false
	assert_true(FileAccess.file_exists(SaveManager.tmp_path()), "the tmp file was written")
	assert_eq(_read_json(SaveManager.meta_path())["notes_found"], ["H1"], "meta.json untouched")
	var m := SaveManager.load_meta()
	assert_eq(m.notes_found, [&"H1"] as Array[StringName], "the last complete file loads")
	assert_false(FileAccess.file_exists(SaveManager.tmp_path()), "the stale tmp is cleared")
	# A crash after removing the old file but before the rename leaves only the tmp.
	SaveManager.crash_before_rename = true
	SaveManager.save_meta(newer)
	SaveManager.crash_before_rename = false
	DirAccess.remove_absolute(SaveManager.meta_path())
	m = SaveManager.load_meta()
	assert_eq(m.notes_found, [&"H1", &"H2"] as Array[StringName], "rescued from the tmp")
	assert_true(FileAccess.file_exists(SaveManager.meta_path()))


func test_save_replaces_an_existing_file() -> void:
	var a := MetaState.new()
	a.first_descent_done = false
	SaveManager.save_meta(a)
	a.first_descent_done = true
	assert_true(SaveManager.save_meta(a))
	assert_true(SaveManager.load_meta().first_descent_done)


func test_corrupt_file_is_backed_up_and_reset() -> void:
	for text in ["{not json", "", "[1, 2, 3]", "{\"version\": \"one\"}", "{\"version\": -1}"]:
		_wipe()
		SaveManager.consume_reset_notice()
		_write(SaveManager.meta_path(), text)
		var m := SaveManager.load_meta()
		assert_not_null(m, "a fresh Archive for %s" % text)
		assert_eq(m.notes_found.size(), 0)
		assert_true(FileAccess.file_exists(SaveManager.bad_path()), "backed up as meta.json.bad (%s)" % text)
		assert_eq(FileAccess.get_file_as_string(SaveManager.bad_path()), text, "the backup keeps the bytes")
		assert_true(FileAccess.file_exists(SaveManager.meta_path()), "a fresh file is created")
		assert_eq(int(_read_json(SaveManager.meta_path()).get("version", 0)), 1)
		assert_true(SaveManager.has_reset_notice())
		assert_eq(SaveManager.consume_reset_notice(), Strings.TITLE_ARCHIVE_RESET, "the title shows it")
		assert_eq(SaveManager.consume_reset_notice(), "", "once")


func test_missing_file_is_a_fresh_archive_without_notice() -> void:
	var m := SaveManager.load_meta()
	assert_eq(m.to_dict()["unlocks"].size(), Tuning.UNLOCK_COUNT)
	assert_false(SaveManager.has_reset_notice())
	assert_false(FileAccess.file_exists(SaveManager.meta_path()), "nothing written until the first save")


func test_reset_meta_writes_and_hands_over() -> void:
	var before := GameState.meta
	GameState.meta = _sample()
	var fresh := SaveManager.reset_meta()
	assert_eq(GameState.meta, fresh)
	assert_eq(fresh.notes_found.size(), 0)
	assert_eq(SaveManager.load_meta().notes_found.size(), 0)
	GameState.meta = before


func test_record_run_does_not_count_depths() -> void:
	var m := MetaState.new()
	m.depth_reached(1)
	m.depth_reached(2)
	m.record_run({"cause": "echo", "depth": 2, "score": 2300, "seconds": 300.0})
	assert_eq(m.stats["depth_reached_counts"], {"1": 1, "2": 1}, "record_run leaves depth counts alone")
	assert_eq(m.stats["runs"], 1)
	assert_eq(m.stats["deaths_by"]["echo"], 1)
	assert_eq(m.stats["best_score"], 2300)
	assert_eq(m.stats["best_depth"], 2)
	assert_approx(m.stats["time_played_s"], 300.0)
	assert_eq(m.daily, {}, "not daily")
