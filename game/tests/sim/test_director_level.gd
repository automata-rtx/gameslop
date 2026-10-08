extends TestCase
## The Director on a built Halls level (headless, FakeClock): the roster spawns at fair
## cells (≥ 20 m, out of view), Static awake and hunters Dormant; Calm holds 30 s (15 s
## after a drop) and Build wakes a hunter; awake arrivals search 30 m out; aggression
## reaches the errors; the F3 lines and the telemetry CSV.

const LEVEL_SCENE := preload("res://scenes/level.tscn")
const MAX_FRAMES := 1500

var _level: Level
var _p: Player
var _d: Director
var _clock: FakeClock
var _phases: Array[StringName] = []


func before_all() -> void:
	_level = LEVEL_SCENE.instantiate() as Level
	add_child(_level)
	_level.begin(LevelGenerator.generate(&"halls", 1, 5))
	var frames := 0
	while not _level.is_ready() and frames < MAX_FRAMES:
		await get_tree().process_frame
		frames += 1
	_p = PlayerFixture.spawn_player(_level)
	_level.attach_player(_p, _p.rig.camera)
	await await_physics_frames(5)
	EventBus.director_phase.connect(_on_phase)


func after_all() -> void:
	EventBus.director_phase.disconnect(_on_phase)
	_level.queue_free()


func _on_phase(p: StringName) -> void:
	_phases.append(p)


func before_each() -> void:
	_phases.clear()
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


func _begin(arrival: StringName = Tuning.RUN_ARRIVE_START) -> void:
	_d.begin(_level, _p, arrival)
	# Depth 1 adds a Still or an Echo; Echo has no scene in M1, so make sure one hunter exists.
	if _hunter() == null:
		_d.hunters.spawn_roster([&"still"] as Array[StringName])


func _hunter() -> ErrorBase:
	for e in _d.errors:
		if is_instance_valid(e) and DirectorRules.is_hunter(e.error_id):
			return e
	return null


func _advance(seconds: float) -> void:
	_clock.advance(seconds)
	_d.update()


func test_roster_spawns_fairly() -> void:
	_begin()
	assert_eq(_d.roster[0], &"static")
	assert_eq(_d.roster.size(), 2, "depth 1 of a later Descent: Static plus one hunter")
	assert_eq(_d.errors.size() + _d.skipped.size(), _d.roster.size() + (1 if _d.skipped.size() > 0 else 0))
	var g := _level.data.grid
	var eye := _p.eye_position()
	for e in _d.errors:
		var pos := e.body_position()
		assert_true(DirectorSpawn.flat_dist(pos, _p.global_position) >= Tuning.ERROR_SPAWN_MIN_DIST, "%s ≥ 20 m" % e.error_id)
		assert_false(_p.rig.camera.is_position_in_frustum(pos + Vector3.UP * Tuning.DIRECTOR_SPAWN_EYE_HEIGHT), "%s out of the frustum" % e.error_id)
		assert_false(SightOps.clear(g, eye, pos + Vector3.UP * Tuning.DIRECTOR_SPAWN_EYE_HEIGHT), "%s out of sight" % e.error_id)
		if e.error_id == &"static":
			assert_false(e.is_dormant(), "Static starts awake")
		else:
			assert_true(e.is_dormant(), "hunters start Dormant")
	assert_eq(_phases, [DirectorPacing.CALM] as Array[StringName])
	assert_true(_p.contact_gate.is_valid())


func test_calm_30_s_then_build_wakes_a_hunter() -> void:
	_begin()
	var h := _hunter()
	_advance(Tuning.DIRECTOR_CALM_TIME - 0.15)
	assert_eq(_d.phase, DirectorPacing.CALM)
	assert_true(h.is_dormant(), "no hunter wakes during Calm")
	_advance(0.2)
	assert_eq(_d.phase, DirectorPacing.BUILD)
	assert_false(h.is_dormant(), "Build wakes a hunter")
	assert_true(h.has_hint(), "and hints it toward the player's region")
	assert_true(_phases.has(DirectorPacing.BUILD))


func test_calm_after_drop_is_15_s() -> void:
	_begin(Tuning.RUN_ARRIVE_DROP)
	_advance(Tuning.DIRECTOR_CALM_TIME_AFTER_DROP - 0.15)
	assert_eq(_d.phase, DirectorPacing.CALM)
	_advance(0.2)
	assert_eq(_d.phase, DirectorPacing.BUILD)


func test_a_chase_during_calm_is_sent_away() -> void:
	_begin()
	var h := _hunter()
	h.wake()
	h.transition_to(Tuning.ERROR_STATE_CHASE, "test")
	assert_eq(h.state, Tuning.ERROR_STATE_SATIATED, "no chase in the calm window (10 §7 rule 2)")


func test_awake_arrival_searches_30_m_out() -> void:
	_begin(Tuning.RUN_ARRIVE_DROP)
	var h := _hunter()
	_d.hunters.awake_arrivals(1)
	assert_eq(h.state, Tuning.ERROR_STATE_SEARCH)
	var d := DirectorSpawn.flat_dist(h.senses.last_known_pos, _p.global_position)
	assert_true(absf(d - Tuning.AWAKE_SEARCH_DIST) <= Tuning.DIRECTOR_HINT_DIST_TOLERANCE + 0.01,
		"last_known_pos is a cell 30 m from the player, not the player (%.1f m)" % d)


func test_aggression_reaches_errors() -> void:
	_begin()
	assert_approx(_d.aggression, 0.25, 0.0001)
	for e in _d.errors:
		var want := DirectorRules.error_aggression(0.25, 1, e.error_id)
		assert_approx(e.aggression, want, 0.0001, "%s aggression" % e.error_id)
	_d.depth = 3
	_advance(1.1)
	assert_approx(_d.aggression, 0.45, 0.0001, "re-applied within a second of a change")
	assert_approx(_hunter().aggression, 0.45, 0.0001)


func test_debug_lines_threat_and_telemetry() -> void:
	_begin()
	_advance(5.0)
	var info := _d.debug_info()
	for key in ["director", "intensity", "aggression", "threat"]:
		assert_true(info.has(key), "F3 line %s" % key)
	assert_true(String(info["director"]).begins_with("CALM"))
	assert_true(_d.telemetry.size() >= 5, "a row per second")
	var path := "user://test_director_telemetry.csv"
	assert_eq(_d.telemetry.dump_csv(path), OK)
	var text := FileAccess.get_file_as_string(path)
	assert_true(text.begins_with(DirectorTelemetry.HEADER))
	assert_eq(text.strip_edges().split("\n").size(), _d.telemetry.size() + 1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_true(_d.threat >= 0.0 and _d.threat <= 1.0)


func test_end_releases_the_gate() -> void:
	_begin()
	_d.end()
	assert_false(_p.contact_gate.is_valid())
	_advance(40.0)
	assert_eq(_d.phase, DirectorPacing.CALM, "an ended Director no longer runs")
