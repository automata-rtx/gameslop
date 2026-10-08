extends TestCase
## M2.7 Director: the roster per depth as a table (05 §3: all five errors, Null only at depth 6
## and the Cycle 2 Substrate), chaser caps with Null exempt (10 §4 "Null plus 1"), awake
## arrivals after drops (never Null), the Substrate's Pursuit schedule on a FakeClock (Calm
## 30 s even after a drop, then Null wakes, Static hinted across the path every 60 s but never
## into the Threshold pocket, intensity floor 0.6, no Relief), and the telemetry CSV columns.

const LEVEL_SCENE := preload("res://scenes/level.tscn")
const FAKE_NULL := preload("res://tests/sim/fake_null.gd")
const MAX_FRAMES := 1500

var _level: Level
var _p: Player
var _d: Director
var _clock: FakeClock


func before_all() -> void:
	_level = LEVEL_SCENE.instantiate() as Level
	add_child(_level)
	_level.begin(LevelGenerator.generate(&"halls", 1, 9))
	var frames := 0
	while not _level.is_ready() and frames < MAX_FRAMES:
		await get_tree().process_frame
		frames += 1
	_p = PlayerFixture.spawn_player(_level)
	_level.attach_player(_p, _p.rig.camera)
	await await_physics_frames(5)


func after_all() -> void:
	_level.queue_free()


func before_each() -> void:
	_level.attach_player(_p, _p.rig.camera)
	_clock = fake_clock(0.0)
	_d = Director.new()
	_d.time_source = _clock.now
	_level.add_child(_d)


func after_each() -> void:
	_d.queue_free()
	for e in get_tree().get_nodes_in_group(ErrorBase.GROUP):
		e.queue_free()
	await await_physics_frames(2)


func _advance(seconds: float) -> void:
	_clock.advance(seconds)
	_d.update()


func _ids(a: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for v in a:
		out.append(StringName(v))
	return out


# --- 05 §3 roster table -------------------------------------------------------------------------

func test_roster_table_per_depth_and_cycle() -> void:
	# depth, stratum, met, expected multiset {id: count}
	var rows := [
		[1, &"halls", [], {&"static": 1, &"hunter": 1}],
		[2, &"pools", [], {&"static": 1, &"echo": 1}],
		[2, &"garage", [], {&"static": 1, &"still": 1}],
		[3, &"offices", [], {&"static": 1, &"flicker": 1}],
		[3, &"garage", [&"echo"], {&"static": 1, &"still": 1}],
		[4, &"server", [&"echo"], {&"static": 1, &"echo": 1, &"still": 1}],
		[4, &"pools", [&"still"], {&"static": 1, &"echo": 1, &"still": 1}],
		[4, &"offices", [&"still", &"echo"], {&"static": 1, &"flicker": 1, &"hunter": 1}],
		[5, &"server", [&"still", &"echo"], {&"static": 2, &"still": 1, &"echo": 1, &"flicker": 1}],
		[5, &"garage", [&"echo"], {&"static": 2, &"still": 1, &"echo": 1, &"flicker": 1}],
		[6, &"substrate", [&"still"], {&"static": 2, &"null": 1}],
		[8, &"pools", [], {&"static": 2, &"echo": 1}],
		[11, &"offices", [], {&"static": 3, &"still": 1, &"echo": 1, &"flicker": 1}],
		[12, &"substrate", [], {&"static": 3, &"null": 1}],
	]
	for row: Array in rows:
		for s in 6:
			var r := DirectorRules.roster(int(row[0]), row[1], false, row[2], make_rng(s))
			var want: Dictionary = row[3]
			var tag := "depth %d %s seed %d: %s" % [row[0], row[1], s, r]
			var hunters := 0
			for id: StringName in [&"still", &"echo", &"flicker", &"null"]:
				hunters += r.count(id)
				if want.has(id):
					assert_eq(r.count(id), int(want[id]), tag)
			assert_eq(r.count(&"static"), int(want[&"static"]), tag)
			var want_hunters := 0
			for k in want:
				if k != &"static":
					want_hunters += int(want[k])
			assert_eq(hunters, want_hunters, tag)
			assert_eq(r[0], &"static", "%s: Statics first" % tag)
			assert_eq(r.count(&"null") > 0, DirectorRules.cycle_depth(int(row[0])) == 6 and row[1] == &"substrate",
				"%s: Null only in the Substrate at depth 6 / 12" % tag)
	# Null never on an ordinary stratum at a Cycle 2 depth-6 slot.
	assert_eq(DirectorRules.roster(12, &"garage", false, [], make_rng(1)).count(&"null"), 0)


# --- 10 §4 chaser caps -----------------------------------------------------------------------------

func test_chaser_caps_with_null_exempt() -> void:
	assert_eq(DirectorRules.chasers_over_cap(_ids([&"still"]), 2), [] as Array[int])
	assert_eq(DirectorRules.chasers_over_cap(_ids([&"still", &"echo"]), 2), [1] as Array[int], "depth ≤ 3: one")
	assert_eq(DirectorRules.chasers_over_cap(_ids([&"echo", &"still", &"flicker"]), 3), [1, 2] as Array[int])
	assert_eq(DirectorRules.chasers_over_cap(_ids([&"still", &"echo"]), 4), [] as Array[int], "depth 4: two")
	assert_eq(DirectorRules.chasers_over_cap(_ids([&"still", &"echo", &"flicker"]), 5), [2] as Array[int])
	assert_eq(DirectorRules.max_other_chasers(6), 1, "depth 6: Null plus one")
	assert_eq(DirectorRules.chasers_over_cap(_ids([&"null", &"still"]), 6), [] as Array[int])
	assert_eq(DirectorRules.chasers_over_cap(_ids([&"still", &"null", &"echo"]), 6), [2] as Array[int],
		"the farthest other hunter, never Null")
	assert_eq(DirectorRules.chasers_over_cap(_ids([&"still", &"echo", &"null"]), 12), [1] as Array[int], "Cycle 2 Substrate")
	assert_true(DirectorRules.chaser_cap_reached(_ids([&"still"]), 2))
	assert_false(DirectorRules.chaser_cap_reached(_ids([&"null"]), 6), "Null alone leaves the other slot free")
	assert_true(DirectorRules.chaser_cap_reached(_ids([&"null", &"echo"]), 6))
	assert_false(DirectorRules.chaser_cap_reached(_ids([&"echo"]), 4))


func test_chaser_cap_on_a_level_retreats_the_farthest() -> void:
	_d.begin(_level, _p, Tuning.RUN_ARRIVE_START)
	var g := _level.data.grid
	var a := _d.hunters.spawn(&"still", g.world_of(DirectorSpawn.cell_at_distance(g, _p.global_position, 22.0, make_rng(1))))
	var b := _d.hunters.spawn(&"echo", g.world_of(DirectorSpawn.cell_at_distance(g, _p.global_position, 34.0, make_rng(2))))
	_advance(Tuning.DIRECTOR_CALM_TIME + 0.05)
	assert_eq(_d.phase, DirectorPacing.BUILD)
	for h in [a, b]:
		h.wake()
	a.transition_to(Tuning.ERROR_STATE_CHASE, "test")
	b.transition_to(Tuning.ERROR_STATE_FOLLOW, "test")
	_advance(Tuning.DIRECTOR_CALM_CHECK_INTERVAL + 0.05)
	var near := a if a.distance_to_player() <= b.distance_to_player() else b
	var far := b if near == a else a
	assert_true(DirectorRules.is_chasing_state(near.state), "the nearer chaser keeps chasing")
	assert_eq(far.state, Tuning.ERROR_STATE_SATIATED, "depth 1: the farther one is sent away")
	assert_gt(_d.hunters.cap_retreats, 0)


# --- 05 §3 awake arrivals ---------------------------------------------------------------------------

func test_awake_arrival_picks_never_null() -> void:
	assert_eq(DirectorRules.awake_arrival_indices(_ids([&"still", &"echo"]), 0), [] as Array[int])
	assert_eq(DirectorRules.awake_arrival_indices(_ids([&"still", &"echo"]), 1), [0] as Array[int], "one after one drop")
	assert_eq(DirectorRules.awake_arrival_indices(_ids([&"still", &"echo"]), 2), [0, 1] as Array[int], "two after two")
	assert_eq(DirectorRules.awake_arrival_indices(_ids([&"still", &"echo", &"flicker"]), 5), [0, 1] as Array[int], "never more than two")
	assert_eq(DirectorRules.awake_arrival_indices(_ids([&"null", &"echo"]), 2), [1] as Array[int], "Null never")
	assert_false(DirectorRules.phase_wakes(&"null"))
	assert_false(DirectorRules.phase_wakes(&"static"))
	assert_true(DirectorRules.phase_wakes(&"echo"))


func test_awake_arrivals_search_30_m_out() -> void:
	_d.begin(_level, _p, Tuning.RUN_ARRIVE_DROP)
	for e in _d.errors.duplicate():
		if DirectorRules.is_hunter(e.error_id):
			_d.errors.erase(e)
			e.queue_free()
	var g := _level.data.grid
	var h1 := _d.hunters.spawn(&"still", g.world_of(DirectorSpawn.cell_at_distance(g, _p.global_position, 25.0, make_rng(3))))
	var h2 := _d.hunters.spawn(&"echo", g.world_of(DirectorSpawn.cell_at_distance(g, _p.global_position, 35.0, make_rng(4))))
	var n := FAKE_NULL.new()
	n.setup(_p, null, 1)
	_level.add_child(n)
	n.global_position = _p.global_position + Vector3(40.0, 0.0, 0.0)
	_d.errors.push_front(n)
	_d.hunters.awake_arrivals(2)
	assert_eq(_d.hunters.awake.size(), 2, "two drops: two hunters search")
	assert_false(_d.hunters.awake.has(n), "never Null")
	for h in [h1, h2]:
		assert_eq(h.state, Tuning.ERROR_STATE_SEARCH, "%s starts in Search" % h.error_id)
		var d := DirectorSpawn.flat_dist(h.senses.last_known_pos, _p.global_position)
		assert_true(absf(d - Tuning.AWAKE_SEARCH_DIST) <= Tuning.DIRECTOR_HINT_DIST_TOLERANCE + 0.01,
			"last_known_pos 30 m from the player, not the player (%.1f m)" % d)
	assert_eq(n.state, Tuning.ERROR_STATE_DORMANT)
	n.queue_free()


# --- 10 §2 Pursuit ------------------------------------------------------------------------------------

func test_pursuit_schedule_pure() -> void:
	for arrival: StringName in [Tuning.RUN_ARRIVE_PROPER, Tuning.RUN_ARRIVE_DROP]:
		var p := DirectorPacing.new(5, arrival, true)
		assert_approx(p.calm_length, 30.0, 0.0001, "Substrate Calm is 30 s, also after a drop")
		var acts: Array = []
		var t := 0.0
		while t < 29.85:
			p.step(0.1, INF, 1, 1)
			acts.append_array(p.take_actions())
			t += 0.1
		assert_eq(p.phase, DirectorPacing.CALM, "Null never wakes before Calm ends")
		assert_false(acts.has(DirectorPacing.ACT_WAKE_NULL))
		var wakes: Array[float] = []
		var hints: Array[float] = []
		while t < 300.0:
			p.step(0.1, 5.0, 1, 1)
			t += 0.1
			for a in p.take_actions():
				if a == DirectorPacing.ACT_WAKE_NULL:
					wakes.append(t)
				elif a == DirectorPacing.ACT_HINT_STATIC_ACROSS:
					hints.append(t)
			if p.phase == DirectorPacing.PURSUIT:
				assert_true(p.intensity >= Tuning.DIRECTOR_PURSUIT_INTENSITY_FLOOR - 0.0001, "floor 0.6")
			if is_equal_approx(fmod(t, 50.0), 0.0):
				p.on_contact()
				p.on_evasion(true)
		assert_eq(wakes.size(), 1, "Null wakes once")
		assert_approx(wakes[0], 30.0, 0.11, "at the end of Calm")
		assert_eq(hints.size(), 5, "Static across the path at 30, 90, 150, 210, 270 s")
		for i in hints.size():
			assert_approx(hints[i], 30.0 + 60.0 * i, 0.2, "every 60 s")
		assert_eq(p.history, [DirectorPacing.CALM, DirectorPacing.PURSUIT] as Array[StringName],
			"no sawtooth: chases, contacts and evasions never leave Pursuit")


func test_pursuit_on_a_level_wakes_null_and_keeps_static_out_of_the_pocket() -> void:
	var was := _level.data.depth
	_level.data.depth = 6
	_d.begin(_level, _p, Tuning.RUN_ARRIVE_DROP)
	_level.data.depth = was
	var n := FAKE_NULL.new()
	n.setup(_p, null, 1)
	_level.add_child(n)
	n.global_position = _p.global_position + Vector3(30.0, 0.0, 0.0)
	_d.errors.append(n)
	_d.hunters.awake_arrivals(2)
	assert_eq(n.pursued, 0)
	_advance(29.9)
	assert_eq(_d.phase, DirectorPacing.CALM)
	assert_eq(n.pursued, 0, "Null not woken before Calm ends (rule 9)")
	_advance(0.2)
	assert_eq(_d.phase, DirectorPacing.PURSUIT)
	assert_eq(n.pursued, 1, "Pursuit wakes Null through its own entry point")
	_advance(5.0)
	assert_eq(_d.hunters.cap_retreats, 0, "the cap never sends Null away")
	assert_ne(n.state, Tuning.ERROR_STATE_SATIATED)
	assert_true(_d.intensity >= Tuning.DIRECTOR_PURSUIT_INTENSITY_FLOOR - 0.0001)
	n.queue_free()


func test_pursuit_static_cells_stay_out_of_the_threshold_pocket() -> void:
	var g := _level.data.grid
	var path := _level.data.critical_path
	var pocket: Array[Vector3] = []
	for i in g.cell_count():
		if g.has_flag(g.cell_at(i), LevelGrid.F_EXIT_ROOM):
			pocket.append(g.world_of(g.cell_at(i)))
	assert_gt(pocket.size(), 0)
	var rng := make_rng(2)
	var seen := 0
	for k in 200:
		var c := DirectorRules.pursuit_static_cell(g, path, rng)
		if c == LevelData.NO_CELL:
			continue
		seen += 1
		assert_true(path.has(c), "on the critical path")
		for q in pocket:
			assert_true(DirectorSpawn.flat_dist(g.world_of(c), q) >= Tuning.DIRECTOR_STATIC_OFF_PATH_CLEARANCE,
				"%s is 6 m or more from the pocket" % c)
	assert_eq(seen, 200, "the path has room")


# --- 10 §9 telemetry ----------------------------------------------------------------------------------

func test_telemetry_csv_columns() -> void:
	assert_eq(DirectorTelemetry.HEADER.split(","), PackedStringArray(["time", "intensity", "phase", "aggression",
		"threat", "nearest_hunter_d", "coherence", "chasing", "scare"]))
	for col in ["time", "intensity", "phase", "nearest_hunter_d", "coherence"]:
		assert_true(DirectorTelemetry.HEADER.split(",").has(col), "10 §9 column %s" % col)
	var t := DirectorTelemetry.new()
	t.record(1.0, 0.25, &"build", 0.35, 0.1, INF, 88.0, 0)
	t.record(2.0, 0.3, &"build", 0.35, 0.1, 18.3, 88.0, 1, Scares.DOOR_SLAM)
	var lines := t.to_csv().strip_edges().split("\n")
	assert_eq(lines.size(), 3)
	for line in lines:
		assert_eq(line.split(",").size(), 9, "every row has every column: %s" % line)
	assert_eq(lines[1], "1.0,0.250,build,0.350,0.100,,88.0,0,")
	assert_eq(lines[2], "2.0,0.300,build,0.350,0.100,18.3,88.0,1,door_slam")
	assert_eq(DirectorTelemetry.dump_debug(_d), "", "off without --telemetry")
	assert_true(CliArgs.parse(PackedStringArray(["--telemetry"])).telemetry)
	assert_false(CliArgs.parse(PackedStringArray(["--seed", "3"])).telemetry)
