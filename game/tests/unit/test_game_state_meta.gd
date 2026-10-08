extends TestCase
## M2.10 GameState rules: the Descent Score (05 §5) with time from Clock.run_seconds, the 14
## milestone unlocks (05 §6) at their events and once only, loadouts (05 §7), Daily and Endless
## (05 §8, 13 §4), first-Descent flags (05 §10), the 13 §3 persistence writes, and no double
## count of depth_reached.

const DIR := "user://tests/game_state_case"

var _meta: MetaState
var _run: RunState
var _dir_before: String
var _now_before: Callable
var _fake_usec: int = 0
var _earned: Array[StringName] = []


func before_all() -> void:
	_meta = GameState.meta
	_run = GameState.run
	_dir_before = SaveManager.directory
	_now_before = Clock.now_usec
	SaveManager.directory = DIR
	Clock.now_usec = func() -> int: return _fake_usec
	EventBus.unlock_earned.connect(_on_unlock)


func after_all() -> void:
	EventBus.unlock_earned.disconnect(_on_unlock)
	if GameState.is_run_active():
		GameState.end_run(&"abandoned")
	Clock.now_usec = _now_before
	for p in [SaveManager.meta_path(), SaveManager.tmp_path()]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	SaveManager.directory = _dir_before
	GameState.meta = _meta
	GameState.run = _run


func before_each() -> void:
	if GameState.is_run_active():
		GameState.end_run(&"abandoned")
	GameState.meta = MetaState.new()
	_earned.clear()
	_fake_usec = 0


func _on_unlock(id: StringName) -> void:
	_earned.append(id)


func _advance(seconds: float) -> void:
	_fake_usec += int(seconds * 1_000_000.0)


func _saved() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SaveManager.meta_path()))
	return data if data is Dictionary else {}


# --- score (05 §5) ---------------------------------------------------------------------------

func test_score_formula_cases() -> void:
	# Death at depth 3: 3000 + 2 exits 600 + 0 Coherence + 2 notes 300 + 5 evasions 250.
	assert_eq(GameState.score_for(3, 2, 0.0, 2, 5, 900.0, false), 4150)
	# Win: 6000 + 1500 + 40 x 5 + 6 x 150 + 4 x 50 + (1800 - 1500) x 0.5.
	assert_eq(GameState.score_for(6, 5, 40.0, 6, 4, 1500.0, true), 8950)
	assert_eq(GameState.score_for(6, 5, 40.0, 6, 4, 2000.0, true), 8800, "no bonus past 30 minutes")
	assert_eq(GameState.score_for(6, 5, 40.0, 6, 4, 1500.0, false), 8800, "time bonus is win only")
	assert_eq(GameState.score_for(1, 0, 37.6, 0, 0, 10.0, false), 1190, "Coherence as the HUD's whole number")
	assert_eq(GameState.score_for(6, 5, 0.0, 0, 0, 1201.0, true), 6000 + 1500 + 299, "time bonus rounds down")
	assert_eq(GameState.score_for(5, 0, 0.0, 0, 0, 0.0, false), 5000, "drops are not penalised")


func test_compute_score_reads_the_clock_run_timer() -> void:
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 3)
	for i in 5:
		GameState.descend(true)
	GameState.run.coherence = 40.0
	_advance(1500.0)
	Clock.set_menu_pause(true)
	_advance(600.0)  # pause-menu time is not run time
	Clock.set_menu_pause(false)
	assert_approx(Clock.run_seconds(), 1500.0, 0.01)
	GameState.end_run(&"threshold")
	assert_eq(GameState.run.score, 6000 + 1500 + 200 + 150)
	assert_eq(GameState.compute_score(), GameState.run.score)


func test_diver_counts_max_depth_normally() -> void:
	GameState.start_run(Tuning.MODE_DESCENT, &"diver", 4)
	GameState.descend(false)
	GameState.run.coherence = 0.0
	GameState.end_run(&"still")
	assert_eq(GameState.run.score, 4000)


func test_run_ended_carries_the_score() -> void:
	var got: Array = []
	var cb := func(cause: StringName, score: int) -> void: got.append([cause, score])
	EventBus.run_ended.connect(cb)
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 5)
	GameState.run.coherence = 0.0
	GameState.end_run(&"echo")
	EventBus.run_ended.disconnect(cb)
	assert_eq(got, [[&"echo", 1000]])


# --- unlocks (05 §6) -------------------------------------------------------------------------

func test_depth_unlocks_at_their_depths() -> void:
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 6)
	assert_eq(_earned.size(), 0, "depth 1 earns nothing")
	var expect := {2: [&"glowstick"], 3: [&"radio", &"daily"], 4: [&"flare"], 5: [&"fuse"]}
	for d in [2, 3, 4, 5]:
		_earned.clear()
		GameState.descend(true)
		assert_eq(Array(_earned), expect[d], "depth %d" % d)
	_earned.clear()
	GameState.descend(true)
	assert_eq(_earned.size(), 0, "depth 6 earns nothing by depth")
	assert_eq(GameState.run.unlocks_earned, [&"glowstick", &"radio", &"daily", &"flare", &"fuse"] as Array[StringName])
	GameState.end_run(&"null")
	# Once only: a second run through the same depths announces nothing (it stops at depth 3,
	# since a second visit to depth 4 earns Diver).
	_earned.clear()
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 7)
	for i in 2:
		GameState.descend(false)
	GameState.end_run(&"null")
	assert_eq(_earned.size(), 0, "each unlock announced once")
	assert_eq(GameState.run.unlocks_earned.size(), 0)


func test_diver_after_reaching_depth_4_twice() -> void:
	for i in 2:
		GameState.start_run(Tuning.MODE_DESCENT, &"faller", 10 + i)
		for d in 3:
			GameState.descend(true)
		assert_eq(GameState.meta.is_unlocked(&"diver"), i == 1, "run %d" % i)
		GameState.end_run(&"still")
	assert_eq(_earned.count(&"diver"), 1)


func test_depth_reached_is_not_double_counted() -> void:
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 12)
	GameState.descend(true)
	GameState.descend(false)
	GameState.end_run(&"echo")
	assert_eq(GameState.meta.stats["depth_reached_counts"], {"1": 1, "2": 1, "3": 1})
	assert_eq(GameState.meta.stats["best_depth"], 3)
	GameState.start_run(Tuning.MODE_DESCENT, &"diver", 13)
	GameState.end_run(&"echo")
	assert_eq(GameState.meta.stats["depth_reached_counts"], {"1": 1, "2": 1, "3": 2}, "Diver's start depth counts once")
	assert_false(GameState.meta.is_unlocked(&"diver"))


func test_cartographer_after_five_notes() -> void:
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 14)
	for id: StringName in [&"H1", &"H2", &"H3", &"H4"]:
		EventBus.note_found.emit(id)
	EventBus.note_found.emit(&"H4")
	assert_false(GameState.meta.is_unlocked(&"cartographer"), "4 distinct notes")
	EventBus.note_found.emit(&"P1")
	assert_true(GameState.meta.is_unlocked(&"cartographer"))
	EventBus.note_found.emit(&"P2")
	assert_eq(_earned, [&"cartographer"] as Array[StringName], "once")
	assert_eq(GameState.meta.stats["notes_total"], 6)
	assert_eq(_saved()["notes_found"].size(), 6, "13 §3: written at note pickup")


func test_note_u6_after_the_35_other_notes() -> void:
	var others: Array[StringName] = []
	for n in DataRegistry.notes():
		if n.id != GameState.NOTE_U6:
			others.append(n.id)
	assert_eq(others.size(), Tuning.UNLOCK_NOTE_U6_NOTES)
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 15)
	for i in others.size() - 1:
		EventBus.note_found.emit(others[i])
	assert_false(GameState.meta.is_unlocked(&"note_u6"), "34 notes")
	EventBus.note_found.emit(others[others.size() - 1])
	assert_true(GameState.meta.is_unlocked(&"note_u6"))
	assert_eq(_earned.count(&"note_u6"), 1)


func test_lightbearer_after_three_flicker_evasions_in_one_run() -> void:
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 16)
	GameState.record_evasion(&"flicker")
	GameState.record_evasion(&"flicker")
	GameState.record_evasion(&"still")
	GameState.end_run(&"still")
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 17)
	GameState.record_evasion(&"flicker")
	assert_false(GameState.meta.is_unlocked(&"lightbearer"), "in one run, not across runs")
	GameState.record_evasion(&"flicker")
	GameState.record_evasion(&"flicker")
	assert_true(GameState.meta.is_unlocked(&"lightbearer"))
	GameState.record_evasion(&"flicker")
	assert_eq(_earned.count(&"lightbearer"), 1)
	assert_eq(GameState.run.evasions, 4)


func test_codex_unlocks_after_three_encounters() -> void:
	for id: StringName in [&"still", &"echo", &"flicker", &"null"]:
		GameState.start_run(Tuning.MODE_DESCENT, &"faller", 18)
		GameState.record_notice(id)
		GameState.record_notice(id)
		GameState.end_run(&"abandoned")
		GameState.start_run(Tuning.MODE_DESCENT, &"faller", 19)
		var unlock := StringName("codex_" + String(id))
		assert_false(GameState.meta.is_unlocked(unlock))
		GameState.record_notice(id)
		assert_true(GameState.meta.is_unlocked(unlock), "%s: three encounters across runs" % id)
		GameState.record_notice(id)
		assert_eq(_earned.count(unlock), 1)
		assert_eq(int(_saved()["codex"][String(id)]), 4, "13 §3: written at notice")
		GameState.end_run(&"abandoned")
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 20)
	for i in 4:
		GameState.record_notice(&"static")
	assert_eq(int(GameState.meta.codex["static"]), 4, "Static has a codex count but no unlock")
	assert_eq(_earned.size(), 4)


func test_endless_after_crossing_the_threshold() -> void:
	assert_false(GameState.is_mode_available(Tuning.MODE_ENDLESS), "gated before a win")
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 22)
	GameState.end_run(&"null")
	assert_false(GameState.is_mode_available(Tuning.MODE_ENDLESS), "a death does not open it")
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 23)
	for i in 5:
		GameState.descend(true)
	GameState.end_run(&"threshold")
	assert_true(GameState.is_mode_available(Tuning.MODE_ENDLESS))
	assert_true(GameState.meta.cycle_unlocked, "13 §3 Ending: cycle_unlocked")
	assert_eq(GameState.meta.stats["wins"], 1)
	assert_true(GameState.run.unlocks_earned.has(&"endless"))
	var saved := _saved()
	assert_true(bool(saved["cycle_unlocked"]))
	assert_true(bool(saved["unlocks"]["endless"]))


func test_every_unlock_has_a_trigger() -> void:
	# Drives every trigger once and checks the 14 ids of Tuning.UNLOCK_IDS were all announced.
	for i in 2:
		GameState.start_run(Tuning.MODE_DESCENT, &"faller", 30 + i)
		for d in 5:
			GameState.descend(true)
		for k in 3:
			GameState.record_evasion(&"flicker")
		for id: StringName in [&"still", &"echo", &"flicker", &"null"]:
			GameState.record_notice(id)
			GameState.record_notice(id)
		GameState.end_run(&"threshold")
	for n in DataRegistry.notes():
		EventBus.note_found.emit(n.id)
	for id in Tuning.UNLOCK_IDS:
		assert_eq(_earned.count(id), 1, "%s earned once" % id)
		assert_true(GameState.meta.is_unlocked(id))
	assert_eq(_earned.size(), Tuning.UNLOCK_COUNT)


# --- loadouts and modes (05 §7, §8) ---------------------------------------------------------

func test_loadouts_applied_in_start_run() -> void:
	var expect := {
		&"faller": [100.0, 1, {&"polaroid": 1, &"chalk": 8}, 1.0, 1.0],
		&"cartographer": [90.0, 1, {&"chalk": 20, &"radio": 1}, 1.0, 1.0],
		&"lightbearer": [100.0, 1, {&"glowstick": 3, &"flare": 1}, 1.5, 1.5],
		&"diver": [70.0, 3, {&"polaroid": 2}, 1.0, 1.0],
	}
	for id: StringName in expect:
		GameState.start_run(Tuning.MODE_DESCENT, id, 40)
		var e: Array = expect[id]
		var r := GameState.run
		assert_eq(r.loadout, id)
		assert_approx(r.coherence, e[0], 0.001, "%s Coherence" % id)
		assert_eq(r.depth, e[1], "%s start depth" % id)
		assert_eq(r.max_depth, e[1])
		assert_eq(r.start_items, e[2], "%s start items" % id)
		assert_approx(r.crank_rate_mult, e[3], 0.001, "%s crank rate" % id)
		assert_approx(r.flicker_attract_mult, e[4], 0.001, "%s Flicker attraction" % id)
		GameState.end_run(&"abandoned")


func test_loadout_availability_follows_unlocks() -> void:
	assert_true(GameState.is_loadout_available(&"faller"))
	for id: StringName in [&"cartographer", &"lightbearer", &"diver"]:
		assert_false(GameState.is_loadout_available(id), id)
		GameState.meta.earn(id)
		assert_true(GameState.is_loadout_available(id), id)
	assert_false(GameState.is_loadout_available(&"nobody"))


func test_daily_seed_for_a_fixed_date() -> void:
	var date := {"year": 2026, "month": 10, "day": 7}
	assert_eq(GameState.today_key(date), "20261007")
	assert_eq(GameState.daily_seed(date), hash("NOCLIP:20261007"), "05 §8, 13 §4")
	assert_eq(GameState.daily_seed(date), Seeds.daily(date))
	assert_ne(GameState.daily_seed(date), GameState.daily_seed({"year": 2026, "month": 10, "day": 8}))
	assert_eq(GameState.today_key({"year": 2027, "month": 1, "day": 2}), "20270102")
	assert_eq(GameState.today_key().length(), 8)


func test_daily_uses_faller_and_one_attempt_per_day() -> void:
	assert_false(GameState.is_mode_available(Tuning.MODE_DAILY), "locked until depth 3 (#8)")
	GameState.meta.earn(&"daily")
	assert_true(GameState.is_mode_available(Tuning.MODE_DAILY))
	GameState.start_run(Tuning.MODE_DAILY, &"diver", GameState.daily_seed())
	assert_eq(GameState.run.loadout, &"faller", "Daily always uses Faller (05 §7)")
	assert_eq(GameState.run.depth, 1)
	assert_eq(GameState.run.daily_key, GameState.today_key())
	assert_false(GameState.is_mode_available(Tuning.MODE_DAILY), "the attempt is spent at start")
	assert_true(_saved()["daily"].has(GameState.today_key()), "written at once, quitting cannot retry")
	GameState.descend(true)
	GameState.run.coherence = 0.0
	GameState.end_run(&"still")
	var result := GameState.meta.daily_result(GameState.today_key())
	assert_eq(result, {"score": 2000 + 300, "depth": 2, "cause": "still"})
	assert_eq(_saved()["daily"][GameState.today_key()]["score"], 2300)


func test_endless_records_best_depth_and_cycle() -> void:
	GameState.start_run(Tuning.MODE_ENDLESS, &"faller", 50)
	for i in 7:
		GameState.descend(true)
	assert_eq(GameState.run.depth, 8)
	assert_eq(GameState.cycle_for(GameState.run.depth), 2, "Cycle 2 past depth 6")
	assert_eq(GameState.cycle_for(6), 1)
	assert_eq(GameState.cycle_for(13), 3)
	GameState.end_run(&"static")
	assert_eq(GameState.meta.endless_best_depth, 8)
	assert_eq(GameState.run.score, 8000 + 7 * 300 + 5 * 100, "Threshold counted as a proper exit")


# --- first Descent, stats, persistence (05 §10, 13 §3) ------------------------------------------

func test_first_descent_flag() -> void:
	assert_true(GameState.is_first_descent())
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 60)
	assert_true(GameState.run.first_descent)
	assert_true(GameState.is_first_descent())
	GameState.end_run(&"still")
	assert_true(GameState.meta.first_descent_done)
	assert_true(bool(_saved()["first_descent_done"]))
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 61)
	assert_false(GameState.run.first_descent)
	assert_false(GameState.is_first_descent())


func test_stats_flushed_at_transitions_and_run_end() -> void:
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 62)
	GameState.record_wall_pass()
	GameState.record_spend(&"noclip_wall", 15.0)
	GameState.record_drop()
	GameState.record_evasion(&"echo")
	GameState.run.distance_m = 120.5
	GameState.descend(false)
	var s: Dictionary = _saved()["stats"]
	assert_eq(int(s["walls_passed"]), 1, "13 §3: written at the level transition")
	assert_eq(int(s["floors_dropped"]), 1)
	assert_approx(float(s["coherence_spent"]), 15.0)
	assert_approx(float(s["distance_walked_m"]), 120.5)
	assert_eq(int(s["evasions"]), 1)
	assert_eq(int(s["best_depth"]), 2)
	GameState.record_wall_pass()
	EventBus.item_used.emit(&"glowstick")
	EventBus.breaker_thrown.emit(Vector3.ZERO)
	_advance(65.0)
	GameState.end_run(&"echo")
	var m := GameState.meta
	assert_eq(m.stats["walls_passed"], 2, "only the difference is added")
	assert_eq(m.stats["floors_dropped"], 1)
	assert_eq(m.stats["runs"], 1)
	assert_eq(m.stats["deaths_by"]["echo"], 1)
	assert_eq(m.stats["items_used"], {"glowstick": 1})
	assert_eq(m.stats["breakers_thrown"], 1)
	assert_approx(float(m.stats["time_played_s"]), 65.0, 0.01)
	assert_eq(m.last_run["cause"], "echo")
	assert_eq(m.last_run["depth"], 2)
	assert_eq(m.last_run["seed"], 62)
	assert_eq(m.last_run["stratum"], String(GameState.stratum_for(2)))
	assert_eq(int(_saved()["stats"]["runs"]), 1, "13 §3: written at run end")


func test_strata_reached() -> void:
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 63)
	assert_false(GameState.meta.has_reached_stratum(&"halls"), "the level being played is not 'before'")
	GameState.descend(true)
	assert_true(GameState.meta.has_reached_stratum(&"halls"), "counted on leaving it")
	var d2 := GameState.stratum_for(2)
	assert_false(GameState.meta.has_reached_stratum(d2))
	GameState.end_run(&"echo")
	assert_true(GameState.meta.has_reached_stratum(d2), "and at run end")
	assert_true(ItemSpawner.stratum_reached(d2), "ItemSpawner reads it")


func test_summary_shows_score_best_and_unlocks() -> void:
	GameState.start_run(Tuning.MODE_DESCENT, &"faller", 64)
	GameState.descend(true)
	GameState.run.coherence = 0.0
	GameState.end_run(&"echo")
	var t := RunSummary.table_lines()
	assert_contains(t, "SCORE 2,300")
	assert_contains(t, "BEST 2,300")
	assert_eq(RunSummary.unlock_lines(), ["ITEM UNLOCKED: GLOWSTICK"] as Array[String])
	assert_eq(RunSummary.format_score(1234567), "1,234,567")
	assert_eq(RunSummary.format_score(999), "999")
	assert_eq(RunSummary.format_score(0), "0")
